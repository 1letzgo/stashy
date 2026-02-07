//
//  StoreManager.swift
//  stashy
//
//  Created by Daniel Goletz on 07.02.26.
//

import Foundation
import StoreKit

enum PurchaseState: Equatable {
    case idle
    case purchasing
    case purchased
    case failed(String)
}

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let coffeeID = "de.letzgo.stashy.tip.coffee"
    static let pizzaID = "de.letzgo.stashy.tip.pizza"
    static let monthlyID = "de.letzgo.stashy.subscription.monthly"

    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    @Published var hasActiveSubscription: Bool = false
    @Published var didFinishLoading: Bool = false

    private var transactionListener: Task<Void, Error>?

    private init() {
        listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        guard !didFinishLoading else { return }
        do {
            let ids: Set<String> = [
                Self.coffeeID,
                Self.pizzaID,
                Self.monthlyID
            ]
            let fetched = try await Product.products(for: ids)
            // Sort: coffee, pizza, monthly
            let order = [Self.coffeeID, Self.pizzaID, Self.monthlyID]
            products = fetched.sorted { a, b in
                (order.firstIndex(of: a.id) ?? 0) < (order.firstIndex(of: b.id) ?? 0)
            }
        } catch {
            print("StoreManager: Failed to load products: \(error)")
        }
        didFinishLoading = true
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchaseState = .purchased
                await checkSubscriptionStatus()
                // Reset to idle after showing success
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if purchaseState == .purchased {
                    purchaseState = .idle
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() {
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await self?.checkSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Subscription Status

    func checkSubscriptionStatus() async {
        var foundActive = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.monthlyID,
               transaction.revocationDate == nil {
                foundActive = true
                break
            }
        }
        hasActiveSubscription = foundActive
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }
}
