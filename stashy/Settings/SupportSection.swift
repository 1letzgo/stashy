//
//  SupportSection.swift
//  stashy
//
//  Created by Daniel Goletz on 07.02.26.
//

import SwiftUI
import StoreKit

struct SupportSection: View {
    @ObservedObject var storeManager: StoreManager
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        // TestFlight Banner — separate section so it doesn't affect row insets
        if isTestFlightBuild() {
            Section {
                TestFlightNoticeCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }

        Section("Support Stashy") {
            // IAP Cards
            if !storeManager.didFinishLoading {
                ProgressView("Loading products...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if storeManager.products.isEmpty {
                // Products couldn't be loaded — show fallback rows
                fallbackTipRow(emoji: "\u{2615}", title: "Buy me a Coffee", price: "$2.99")
                fallbackTipRow(emoji: "\u{1F355}", title: "Buy me a Pizza", price: "$12.99")
                fallbackTipRow(emoji: "\u{2764}\u{FE0F}", title: "Support Monthly", price: "$1.99/month")

                Button {
                    Task {
                        storeManager.didFinishLoading = false
                        await storeManager.loadProducts()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Retry Loading", systemImage: "arrow.clockwise")
                            .font(.footnote)
                            .foregroundColor(appearanceManager.tintColor)
                        Spacer()
                    }
                }
            } else {
                // Coffee
                if let coffee = storeManager.product(for: StoreManager.coffeeID) {
                    tipRow(emoji: "\u{2615}", title: "Buy me a Coffee", product: coffee)
                }

                // Pizza
                if let pizza = storeManager.product(for: StoreManager.pizzaID) {
                    tipRow(emoji: "\u{1F355}", title: "Buy me a Pizza", product: pizza)
                }

                // Monthly Subscription
                if let monthly = storeManager.product(for: StoreManager.monthlyID) {
                    subscriptionRow(product: monthly)
                }
            }

            // Restore Purchases
            Button {
                Task { await storeManager.restorePurchases() }
            } label: {
                HStack {
                    Spacer()
                    Text("Restore Purchases")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .onChange(of: storeManager.purchaseState) { newState in
            if case .failed(let message) = newState {
                errorMessage = message
                showErrorAlert = true
                storeManager.purchaseState = .idle
            }
        }
        .alert("Purchase Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Fallback Row (products unavailable)

    private func fallbackTipRow(emoji: String, title: String, price: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.title)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(price)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tip Row

    private func tipRow(emoji: String, title: String, product: Product) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.title)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("One-time tip")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            purchaseButton(for: product, label: product.displayPrice)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subscription Row

    private func subscriptionRow(product: Product) -> some View {
        HStack(spacing: 12) {
            Text("\u{2764}\u{FE0F}")
                .font(.title)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Support Monthly")
                    .font(.subheadline.weight(.semibold))
                Text(storeManager.hasActiveSubscription ? "Active" : "\(product.displayPrice)/month")
                    .font(.caption)
                    .foregroundColor(storeManager.hasActiveSubscription ? appearanceManager.tintColor : .secondary)
            }

            Spacer()

            if storeManager.hasActiveSubscription {
                Button {
                    Task { await manageSubscription() }
                } label: {
                    Text("Manage")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(appearanceManager.tintColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            } else {
                purchaseButton(for: product, label: product.displayPrice)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Purchase Button

    @ViewBuilder
    private func purchaseButton(for product: Product, label: String) -> some View {
        if storeManager.purchaseState == .purchasing {
            ProgressView()
                .frame(width: 70)
        } else if storeManager.purchaseState == .purchased {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
                .frame(width: 70)
        } else {
            Button {
                Task { await storeManager.purchase(product) }
            } label: {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appearanceManager.tintColor)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Manage Subscription

    private func manageSubscription() async {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        do {
            try await AppStore.showManageSubscriptions(in: windowScene)
        } catch {
            print("SupportSection: Failed to open subscription management: \(error)")
        }
    }
}
