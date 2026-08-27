//
//  TVStashyPlusSettingsView.swift
//  stashyTV
//
//  stashy+ status, plans and Restore on Apple TV.
//

import SwiftUI
import StoreKit
import Combine
import UIKit

@MainActor
final class TVStashyPlusStore: ObservableObject {
    static let shared = TVStashyPlusStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var lastProductError: String?
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var isRestoringPurchases = false

    var isPurchasing: Bool { purchasingProductID != nil }

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
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
            await fetchProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func fetchProducts() async {
        isLoadingProducts = true
        lastProductError = nil
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Array(StashyPlusProduct.allIDs))
            products = loaded.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            if products.isEmpty {
                lastProductError = "No stashy+ products available."
                AppLog.debug("💬 StoreKit returned 0 stashy+ products for \(StashyPlusProduct.allIDs.sorted())")
            } else {
                AppLog.debug("💬 StoreKit loaded products: \(loaded.map(\.id))")
            }
        } catch {
            lastProductError = error.localizedDescription
            AppLog.debug("Failed product request from the App Store server: \(error)")
        }
    }

    /// Result used by the Settings UI for inline messages.
    @discardableResult
    func purchase(_ product: Product) async -> String? {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                StashyPlusManager.shared.clearDebugForceLock()
                if transaction.productID == StashyPlusProduct.lifetime {
                    await MainActor.run {
                        StashyPlusManager.shared.unlockLifetime(source: .lifetime)
                    }
                }
                await transaction.finish()
                await syncUnlockFromStore()
                return nil
            case .userCancelled:
                return "Purchase cancelled"
            case .pending:
                return "Purchase pending approval"
            @unknown default:
                return "Purchase could not be completed"
            }
        } catch {
            return error.localizedDescription
        }
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        StashyPlusManager.shared.clearDebugForceLock()
        do {
            try await AppStore.sync()
        } catch {
            AppLog.debug("AppStore.sync failed: \(error)")
        }
        do {
            _ = try await AppTransaction.refresh()
        } catch {
            AppLog.debug("AppTransaction.refresh failed: \(error)")
        }
        await syncUnlockFromStore()
    }

    func syncUnlockFromStore() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if StashyPlusProduct.allIDs.contains(transaction.productID),
               transaction.productID == StashyPlusProduct.lifetime {
                await MainActor.run {
                    StashyPlusManager.shared.unlockLifetime(source: .lifetime)
                }
            }
            await transaction.finish()
        }

        var hasLifetimePurchase = false
        var subscriptionProductID: String?
        var subscriptionExpiration: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == StashyPlusProduct.lifetime {
                hasLifetimePurchase = true
            } else if StashyPlusProduct.subscriptionIDs.contains(transaction.productID) {
                let exp = transaction.expirationDate ?? .distantFuture
                if exp > Date() {
                    if let current = subscriptionExpiration, current >= exp { continue }
                    subscriptionExpiration = exp
                    subscriptionProductID = transaction.productID
                }
            }
        }

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
            hasLifetimePurchase: hasLifetimePurchase,
            subscriptionProductID: subscriptionProductID,
            subscriptionExpiration: subscriptionExpiration,
            legacyPaidApp: legacyPaidApp
        )

        if StashyPlusManager.shared.isUnlocked {
            AppLog.debug("✅ stashy+ entitlement synced on tvOS (\(StashyPlusManager.shared.source.rawValue))")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let safe):
            return safe
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

    private static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                let relevant = StashyPlusProduct.allIDs.contains(transaction.productID)
                if relevant, transaction.productID == StashyPlusProduct.lifetime {
                    await MainActor.run {
                        StashyPlusManager.shared.unlockLifetime(source: .lifetime)
                    }
                }
                await transaction.finish()
                if relevant {
                    await TVStashyPlusStore.shared.syncUnlockFromStore()
                }
            }
        }
    }
}

struct TVStashyPlusSettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @ObservedObject private var store = TVStashyPlusStore.shared

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
                    // Restore-Button — dann ist diese Zeile das einzige
                    // fokussierbare Element und damit der Weg zurück.
                    .focusable(!stashyPlus.shouldOfferPurchases)
            } header: {
                Text("stashy+")
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80).focusable(false)
        }
        .background(Color.appBackground)
        .navigationTitle("stashy+")
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

    private func planTitle(for product: Product) -> String {
        StashyPlusProduct.displayNames[product.id] ?? product.displayName
    }

    private func planSubtitle(for product: Product) -> String {
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
