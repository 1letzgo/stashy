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

    var isPurchasing: Bool { purchasingProductID != nil }

    private var customerInfoListener: Task<Void, Never>?

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
                lastProductError = "No stashy+ products available."
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
    func purchase(_ product: StashyStoreProduct) async -> String? {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        let (message, customerInfo) = await StashyRevenueCat.purchase(product)
        if let message { return message }
        StashyPlusManager.shared.clearDebugForceLock()
        await syncUnlockFromStore(customerInfo: customerInfo)
        return nil
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        StashyPlusManager.shared.clearDebugForceLock()
        await StashyRevenueCat.restore()
        do {
            _ = try await AppTransaction.refresh()
        } catch {
            AppLog.debug("AppTransaction.refresh failed: \(error)")
        }
        await syncUnlockFromStore()
    }

    func syncUnlockFromStore(customerInfo: CustomerInfo? = nil) async {
        let snapshot = await StashyRevenueCat.entitlementSnapshot(customerInfo: customerInfo)

        let legacyPaidApp: Bool
        switch await Self.isLegacyPaidAppPurchaser() {
        case .yes:
            legacyPaidApp = true
        case .no:
            legacyPaidApp = false
        case .unknown:
            legacyPaidApp = UserDefaults.standard.string(forKey: StashyPlusManager.sourceKey)
                == StashyPlusSource.legacyPaidApp.rawValue
        }

        StashyPlusManager.shared.applyStoreEntitlements(
            hasLifetimePurchase: snapshot.hasLifetimePurchase,
            subscriptionProductID: snapshot.subscriptionProductID,
            subscriptionExpiration: snapshot.subscriptionExpiration,
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
            let decision = StashyPlusManager.legacyPaidAppDecision(
                environment: appTransaction.environment,
                originalAppVersion: appTransaction.originalAppVersion,
                originalPurchaseDate: appTransaction.originalPurchaseDate
            )
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
    @StateObject private var store = TVStashyPlusStore.shared

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

                featureRow(icon: "sparkles.tv.fill", text: "Channels")
                    // Wer stashy+ bereits besitzt, bekommt weder Kauf- noch
                    // Restore-Button; während eines Kaufs oder Restores sind sie
                    // alle deaktiviert. In beiden Fällen ist diese Zeile das
                    // einzige fokussierbare Element und damit der Weg zurück.
                    .focusable(
                        !stashyPlus.shouldOfferPurchases
                            || store.isPurchasing
                            || store.isRestoringPurchases
                    )
            } footer: {
                Text("stashy+ unlocks premium features across stashy for iPhone and Apple TV with one purchase.")
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
                                    if let message = await store.purchase(productToBuy), !message.isEmpty {
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
                    Text("Unlock")
                } footer: {
                    Text(subscriptionFooter)
                }

                Section {
                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
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
        .task {
            if store.products.isEmpty {
                await store.fetchProducts()
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 44)

            Text(text)
                .font(.body)
        }
    }

    private func planTitle(for product: StashyStoreProduct) -> String {
        StashyPlusProduct.displayNames[product.id] ?? product.displayName
    }

    private func planSubtitle(for product: StashyStoreProduct) -> String {
        if StashyPlusProduct.subscriptionIDs.contains(product.id) {
            return "Auto-renews · cancel anytime"
        }
        return "One-time purchase"
    }

    private var subscriptionFooter: String {
        if stashyPlus.source == .subscription {
            return "Your subscription is active. Buying Lifetime keeps stashy+ forever, even after cancelling."
        }
        return "Payment is charged to your Apple ID. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in your App Store settings."
    }
}
