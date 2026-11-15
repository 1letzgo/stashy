//
//  TVStashyPlusSettingsView.swift
//  stashyTV
//
//  stashy+ status, plans and Restore on Apple TV.
//

import SwiftUI
import StoreKit
import RevenueCat
import Combine
import UIKit

@MainActor
final class TVStashyPlusStore: ObservableObject {
    static let shared = TVStashyPlusStore()

    @Published private(set) var products: [StashyStoreProduct] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var lastProductError: String?
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var isRestoringPurchases = false
    /// Last seen `AppTransaction.environment` was sandbox / Xcode (TestFlight or a local run).
    @Published private(set) var isAppTransactionSandbox = false

    var isPurchasing: Bool { purchasingProductID != nil }

    private var customerInfoListener: Task<Void, Never>?
    private var legacyPaidRetryCount = 0

    private init() {
        StashyRevenueCat.configureIfNeeded()
        customerInfoListener = StashyRevenueCat.listenForCustomerInfo { info in
            await TVStashyPlusStore.shared.syncUnlockFromStore(customerInfo: info)
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncUnlockFromStore()
            }
        }
        Task {
            await syncUnlockFromStore()
            await StashyRevenueCat.migrateExistingPurchasesIfNeeded()
            await fetchProducts()
        }
    }

    deinit {
        customerInfoListener?.cancel()
    }

    func fetchProducts() async {
        isLoadingProducts = true
        lastProductError = nil
        defer { isLoadingProducts = false }
        do {
            let loaded = try await StashyRevenueCat.fetchProducts()
            products = loaded.filter { StashyPlusProduct.allIDs.contains($0.id) }.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            if products.isEmpty {
                lastProductError = tr("empty_stashy_plus_products_available")
                AppLog.debug("💬 RevenueCat offering has no stashy+ products for \(StashyPlusProduct.allIDs.sorted())")
            } else {
                AppLog.debug("💬 RevenueCat loaded products: \(loaded.map(\.id))")
            }
        } catch {
            lastProductError = error.localizedDescription
            AppLog.debug("Failed to load RevenueCat offerings: \(error)")
        }
    }

    /// Result used by the Settings UI for inline messages.
    @discardableResult
    func purchase(_ product: StashyStoreProduct) async -> StashyPurchaseOutcome {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        let (outcome, customerInfo) = await StashyRevenueCat.purchase(product)
        guard case .purchased = outcome else { return outcome }
        StashyPlusManager.shared.clearDebugForceLock()
        await syncUnlockFromStore(customerInfo: customerInfo)
        return .purchased
    }

    /// What Restore found; the settings page shows it in an alert.
    enum RestoreOutcome {
        /// stashy+ is unlocked after the restore (from this or an earlier grant).
        case unlocked
        /// Nothing grants stashy+ on this Apple Account. `sandbox`: TestFlight / Xcode install,
        /// where a paid App Store purchase cannot be proven.
        case nothingFound(sandbox: Bool)
        /// The user dismissed the App Store sign-in.
        case cancelled
        case failed(String)
    }

    /// Restore on Apple TV: `AppStore.sync()` first (it may ask for the Apple Account, which is
    /// fine on an explicit tap), then RevenueCat, a fresh app transaction and a full re-check of
    /// subscriptions, Lifetime and the paid app before 3.0.
    func restorePurchases() async -> RestoreOutcome {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        StashyPlusManager.shared.clearDebugForceLock()

        var syncError: String?
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            await syncUnlockFromStore()
            return StashyPlusManager.shared.isUnlocked ? .unlocked : .cancelled
        } catch {
            AppLog.debug("AppStore.sync failed on tvOS: \(error)")
            syncError = error.localizedDescription
        }
        await StashyRevenueCat.restore()
        do {
            _ = try await AppTransaction.refresh()
        } catch {
            AppLog.debug("AppTransaction.refresh failed: \(error)")
        }
        await syncUnlockFromStore()

        if StashyPlusManager.shared.isUnlocked { return .unlocked }
        if let syncError { return .failed(syncError) }
        return .nothingFound(sandbox: isAppTransactionSandbox)
    }

    func syncUnlockFromStore(customerInfo: CustomerInfo? = nil) async {
        let snapshot = await StashyRevenueCat.entitlementSnapshot(customerInfo: customerInfo)

        let legacyPaidApp: Bool
        switch await Self.isLegacyPaidAppPurchaser() {
        case .yes:
            legacyPaidApp = true
            legacyPaidRetryCount = 0
        case .no:
            legacyPaidApp = false
            legacyPaidRetryCount = 0
        case .unknown:
            // A StoreKit hiccup is no "not a paid buyer": keep what was stored and retry a
            // few times, as on iOS. Without the retry one failed check at launch left a
            // pre-3.0 buyer locked until the next foreground.
            legacyPaidApp = UserDefaults.standard.string(forKey: StashyPlusManager.sourceKey)
                == StashyPlusSource.legacyPaidApp.rawValue
            if legacyPaidRetryCount < 3 {
                legacyPaidRetryCount += 1
                let attempt = legacyPaidRetryCount
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 5_000_000_000)
                    await self.syncUnlockFromStore()
                }
            }
        }

        StashyPlusManager.shared.applyStoreEntitlements(
            hasLifetimePurchase: snapshot.hasLifetimePurchase,
            subscriptionProductID: snapshot.subscriptionProductID,
            subscriptionExpiration: snapshot.subscriptionExpiration,
            isTrial: snapshot.isTrial,
            legacyPaidApp: legacyPaidApp
        )

        if StashyPlusManager.shared.isUnlocked {
            AppLog.debug("✅ stashy+ entitlement synced on tvOS (\(StashyPlusManager.shared.source.rawValue))")
        }
    }

    /// Paid-app buyers (original version before 3.0) get Lifetime via the
    /// Universal Purchase — same grandfathering rules as iOS.
    private enum LegacyPaidAppResult {
        case yes, no, unknown
    }

    private static func isLegacyPaidAppPurchaser() async -> LegacyPaidAppResult {
        do {
            let appTransaction = try checkVerifiedStatic(await AppTransaction.shared)
            let environment = appTransaction.environment
            let original = appTransaction.originalAppVersion
            let purchased = appTransaction.originalPurchaseDate
            TVStashyPlusStore.shared.isAppTransactionSandbox =
                environment == .sandbox || environment == .xcode
            let decision = StashyPlusManager.legacyPaidAppDecision(
                environment: environment,
                originalAppVersion: original,
                originalPurchaseDate: purchased,
                dateOverridesFreemiumVersion: true
            )
            AppLog.debug("ℹ️ tvOS AppTransaction originalAppVersion=\(original) purchased=\(purchased) environment=\(environment) pre-3.0 paid=\(decision == .yes)")
            return decision == .yes ? .yes : .no
        } catch {
            AppLog.debug("AppTransaction check failed on tvOS: \(error)")
            return .unknown
        }
    }

    private static func checkVerifiedStatic<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let safe):
            return safe
        }
    }
}

struct TVStashyPlusSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    // `NavigationLink { … }` baut sein Ziel in einer List sofort mit auf. Als
    // `@ObservedObject` liefe der Singleton-Initializer — und damit StoreKit —
    // schon beim Öffnen der Settings los; auf einem Apple TV ohne angemeldeten
    // Account poppte dort die Apple-Account-Anmeldung auf. `@StateObject`
    // wertet den Ausdruck erst beim ersten Rendern dieser Seite aus.
    // Außerhalb eines lokalen Xcode-Laufs startet `TVApp.init` den Store ohnehin beim
    // App-Start (Entitlements und Kauf vor 3.0 müssen sofort gelten).
    @StateObject private var store = TVStashyPlusStore.shared
    /// Outcome of the last Restore, shown in an alert.
    @State private var restoreAlert: RestoreAlert?

    private struct RestoreAlert {
        let title: String
        let message: String
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    Image(systemName: stashyPlus.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                        .font(.title2)
                        .foregroundColor(stashyPlus.isUnlocked ? .green : appearanceManager.tintColor)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stashyPlus.source.statusTitle)
                            .font(.headline)
                        Text(stashyPlus.source.statusDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                featureRow(
                    icon: ToolsItem.hotOrNot.icon,
                    text: ToolsItem.hotOrNot.plusFeatureTitle,
                    detail: tr("hint_puts_performers_against_each_other_under")
                )
                featureRow(
                    icon: ToolsItem.rateMe.icon,
                    text: ToolsItem.rateMe.plusFeatureTitle,
                    detail: tr("hint_shows_unrated_scenes_or_images_one")
                )
                featureRow(
                    icon: "sparkles.tv.fill",
                    text: tr("channels"),
                    detail: tr("hint_plays_scenes_back_to_back")
                )
                    // Wer stashy+ bereits besitzt, bekommt weder Kauf- noch
                    // Restore-Button; während eines Kaufs oder Restores sind sie
                    // alle deaktiviert. In beiden Fällen ist diese Zeile das
                    // einzige fokussierbare Element und damit der Weg zurück.
                    .focusable(
                        !stashyPlus.shouldOfferPurchases
                            || store.isPurchasing
                            || store.isRestoringPurchases
                    )
                featureRow(
                    icon: "sparkles.rectangle.stack",
                    text: tr("similar_scenes_and_up_next"),
                    detail: tr("hint_shows_similar_scenes_on_scene")
                )
            } footer: {
                Text(tr("hint_stashy_plus_unlocks_premium_features"))
            }

            if stashyPlus.shouldOfferPurchases {
                Section {
                    if store.isLoadingProducts && store.products.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .focusable(false)
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                let productToBuy = product
                                Task {
                                    if case .failed(let message) = await store.purchase(productToBuy) {
                                        AppLog.debug("Purchase result: \(message)")
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(planTitle(for: product))
                                            .font(.headline)
                                        Text(planSubtitle(for: product))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if store.purchasingProductID == product.id {
                                        ProgressView()
                                    } else {
                                        Text(product.displayPrice)
                                            .font(.headline)
                                            .foregroundColor(appearanceManager.tintColor)
                                    }
                                }
                            }
                            .disabled(store.isPurchasing || store.isRestoringPurchases)
                        }

                        if let error = store.lastProductError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .focusable(false)
                        }
                    }
                } header: {
                    Text(tr("action_unlock"))
                } footer: {
                    Text(subscriptionFooter)
                }

                Section {
                    Button {
                        Task {
                            let outcome = await store.restorePurchases()
                            restoreAlert = alert(for: outcome)
                        }
                    } label: {
                        HStack {
                            Text(tr("action_restore_purchases"))
                            Spacer()
                            if store.isRestoringPurchases {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isPurchasing || store.isRestoringPurchases)
                }
            }
        }
        .tvSettingsPage("stashy+")
        .alert(
            restoreAlert?.title ?? "",
            isPresented: Binding(
                get: { restoreAlert != nil },
                set: { if !$0 { restoreAlert = nil } }
            ),
            presenting: restoreAlert
        ) { _ in
            Button(tr("ok")) { restoreAlert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .task {
            if store.products.isEmpty {
                await store.fetchProducts()
            }
        }
    }

    private func alert(for outcome: TVStashyPlusStore.RestoreOutcome) -> RestoreAlert? {
        switch outcome {
        case .unlocked:
            return RestoreAlert(title: tr("purchases_restored"), message: stashyPlus.source.statusDetail)
        case .nothingFound(let sandbox):
            return RestoreAlert(
                title: tr("action_restore_purchases"),
                message: tr(sandbox ? "hint_this_install_is_still_testflight" : "hint_no_stashy_plus_subscription_or")
            )
        case .failed(let message):
            return RestoreAlert(title: tr("action_restore_purchases"), message: message)
        case .cancelled:
            return nil
        }
    }

    private func featureRow(icon: String, text: String, detail: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func planTitle(for product: StashyStoreProduct) -> String {
        StashyPlusProduct.displayNames[product.id] ?? product.displayName
    }

    private func planSubtitle(for product: StashyStoreProduct) -> String {
        if StashyPlusProduct.subscriptionIDs.contains(product.id) {
            return tr("auto_renews_cancel_anytime")
        }
        return tr("one_time_purchase")
    }

    private var subscriptionFooter: String {
        if stashyPlus.source == .subscription {
            return tr("hint_your_subscription_is_active_buying")
        }
        return tr("hint_payment_is_charged_to_your")
    }
}
