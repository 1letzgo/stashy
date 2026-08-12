//
//  SettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI
import StoreKit
import UIKit

struct SettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    // UI State
    @State private var isScanningLibrary: Bool = false
    @State private var showScanAlert: Bool = false
    @State private var scanAlertMessage: String = ""
    @State private var showingAddServerSheet = false
    @State private var editingServer: ServerConfig?
    @State private var selectedSection: SettingsSection = .main
    
    // IAP / Stashy+
    @StateObject private var storeManager = StoreManager()
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    enum SettingsSection: String, CaseIterable, Identifiable {
        case main = "Main"
        case actions = "Actions"
        case design = "Design"
        case stashyPlus = "Stashy+"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .main: return "gearshape.fill"
            case .actions: return "server.rack"
            case .design: return "paintbrush.fill"
            case .stashyPlus: return "sparkles"
            }
        }
    }

    var body: some View {
        Group {
            if selectedSection == .actions {
                ToolsServerView(embedded: true)
            } else {
                Form {
                    switch selectedSection {
                    case .main:
                        mainSettings
                    case .design:
                        designSettings
                    case .stashyPlus:
                        stashyPlusSettings
                    case .actions:
                        EmptyView()
                    }
                }
            }
        }
        .applyAppBackground()
        .navigationBarHidden(true)
        .popNavigationToRootOnChange(selectedSection.rawValue)
        .stashyCustomChromeInset(spacing: 0) {
            StashySectionChromeBar {
                SettingsCategoryRow(selection: $selectedSection)
                    .padding(.horizontal, StashyExpandingDock.edgePadding)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: nil) { newConfig in
                    configManager.addOrUpdateServer(newConfig)
                    if configManager.activeConfig == nil {
                        configManager.saveConfig(newConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingServer) { server in
            NavigationView {
                ServerFormViewNew(configToEdit: server, onSave: { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                    editingServer = nil
                }, onDelete: {
                    configManager.deleteServer(id: server.id)
                    editingServer = nil
                })
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            if configManager.activeConfig != nil {
                viewModel.testConnection()
            }
        }
        .alert("Library Scan", isPresented: $showScanAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanAlertMessage)
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var mainSettings: some View {
        ServerListSection(
            viewModel: viewModel,
            isScanningLibrary: $isScanningLibrary,
            showingAddServerSheet: $showingAddServerSheet,
            editingServer: $editingServer,
            onScan: { startLibraryScan() }
        )

        if configManager.activeConfig != nil {
            PlaybackSettingsSection()
            interactiveDevicesSection
        }

        aboutSection
    }

    @ViewBuilder
    private var designSettings: some View {
        // Design: Appearance, Security, Content & Tabs, Default Settings
        Section(header: Text("Appearance")) {
            NavigationLink(destination: AppearanceSettingsView()) {
                Label("Appearance", systemImage: "paintbrush")
            }
            NavigationLink(destination: EditModeSettingsView()) {
                Label("Editing", systemImage: "pencil.circle")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)

        Section(header: Text("Security")) {
            NavigationLink(destination: SecuritySettingsView()) {
                Label("Security", systemImage: "lock.shield")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)

        if configManager.activeConfig != nil {
            ContentSettingsSection()

            Section("Default Settings") {
                NavigationLink(destination: DefaultSortView()) {
                    Label("Sorting", systemImage: "arrow.up.arrow.down")
                }

                NavigationLink(destination: DefaultFilterView()) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        } else {
            Section {
                Text("Content & default settings require an active server.")
                    .foregroundColor(.secondary)
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
    }

    @ViewBuilder
    private var stashyPlusSettings: some View {
        if isTestFlightBuild() {
            Section {
                appStoreBanner
            }
        }

        stashyPlusPurchaseSection

        if stashyPlus.isUnlocked {
            Section(header: Text("AI Subtitles")) {
                StashyPlusAISubtitlesSettings()
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Plus Tools")) {
                StashyPlusToolsSettings()
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("StashSync")) {
                NavigationLink(destination: StashSyncSettingsView()) {
                    Label("StashSync", systemImage: "bolt.fill")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        } else {
            Section(header: Text("Included with Stashy+")) {
                Label("AI Subtitles", systemImage: "lock.fill")
                Label("Downloads", systemImage: "lock.fill")
                Label("Match & RateMe", systemImage: "lock.fill")
                Label("StashSync", systemImage: "lock.fill")
            }
            .foregroundColor(.secondary)
            .listRowBackground(Color.secondaryAppBackground)
        }
    }

    // MARK: - App Store Banner

    @Environment(\.openURL) private var openURL

    private var appStoreBanner: some View {
        Button {
            if let url = URL(string: "https://apps.apple.com/us/app/stashy/id6754876029") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're using a TestFlight build")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("Help support stashy on the App Store")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    featureRow(icon: "arrow.triangle.2.circlepath", text: "Free updates, forever")
                    featureRow(icon: "star.fill", text: "Ratings help others discover stashy")
                    featureRow(icon: "bolt.heart.fill", text: "Directly supports solo development")
                }

                HStack {
                    Spacer()
                    Text("Get stashy on the App Store")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.38, blue: 0.95), Color(red: 0.55, green: 0.2, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - Stashy+ In-App Purchases

    private var stashyPlusPurchaseSection: some View {
        Section {
            if stashyPlus.isUnlocked {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stashyPlus.source.statusTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(statusDetailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if stashyPlus.shouldOfferPurchases {
                if storeManager.products.isEmpty {
                    if storeManager.isLoadingProducts {
                        HStack {
                            ProgressView()
                            Text("Loading Stashy+ options…")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(storeManager.lastProductError ?? "Stashy+ products unavailable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if isTestFlightBuild() {
                                Text("TestFlight loads products from App Store Connect. Create de.stashy.plus.m / .y / .l there (and wait until Ready to Submit), or run from Xcode with the StoreKit config.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Button("Retry") {
                                Task { await storeManager.fetchProducts() }
                            }
                        }
                    }
                } else {
                    ForEach(storeManager.products) { product in
                        Button {
                            Task {
                                if let error = await storeManager.purchase(product) {
                                    ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
                                } else if stashyPlus.isUnlocked {
                                    ToastManager.shared.show("Stashy+ unlocked — thank you!", icon: "sparkles", style: .success)
                                }
                            }
                        } label: {
                            HStack {
                                Label(
                                    StashyPlusProduct.displayNames[product.id] ?? product.displayName,
                                    systemImage: iconFor(productID: product.id)
                                )
                                .foregroundColor(appearanceManager.tintColor)
                                Spacer()
                                if storeManager.isPurchasing {
                                    ProgressView()
                                } else {
                                    Text(priceLabel(for: product))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(storeManager.isPurchasing)
                    }
                    if let missing = storeManager.lastProductError, missing.hasPrefix("Missing from StoreKit") {
                        Text(missing)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !stashyPlus.isUnlocked {
                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                            .foregroundColor(appearanceManager.tintColor)
                        Spacer()
                        if storeManager.isRestoringPurchases {
                            ProgressView()
                        }
                    }
                }
                .disabled(storeManager.isPurchasing || storeManager.isRestoringPurchases)
            }

            if stashyPlus.source == .subscription {
                Button {
                    Task { await storeManager.manageSubscriptions() }
                } label: {
                    Label("Manage Subscription", systemImage: "creditcard")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }

            if isTestFlightBuild() {
                Button(role: .destructive) {
                    stashyPlus.resetUnlockForTesting()
                    ToastManager.shared.show("Stashy+ reset (TestFlight)", icon: "lock.fill", style: .info)
                } label: {
                    Label("Reset Stashy+ Unlock", systemImage: "lock.rotation")
                }
            }
        } header: {
            Text(stashyPlus.isUnlocked ? "Stashy+" : "Unlock Stashy+")
        } footer: {
            if !stashyPlus.isUnlocked {
                Text("Monthly, Yearly, or Lifetime. Full-price app buyers keep Lifetime automatically — use Restore Purchases if needed.")
            } else if isTestFlightBuild() {
                Text("TestFlight only: Reset clears the unlock so you can retest the paywall. A new purchase clears the reset.")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)
        .task {
            await storeManager.syncUnlockFromStore()
            if storeManager.products.isEmpty {
                await storeManager.fetchProducts()
            }
        }
    }

    private var statusDetailText: String {
        if stashyPlus.source == .subscription,
           let id = stashyPlus.activeProductID,
           let name = StashyPlusProduct.displayNames[id] {
            if let exp = stashyPlus.subscriptionExpiration {
                let formatted = exp.formatted(date: .abbreviated, time: .omitted)
                return "\(name) · renews or expires \(formatted)"
            }
            return "\(name) plan"
        }
        return stashyPlus.source.statusDetail
    }

    private func priceLabel(for product: Product) -> String {
        switch product.id {
        case StashyPlusProduct.monthly:
            return "\(product.displayPrice)/mo"
        case StashyPlusProduct.yearly:
            return "\(product.displayPrice)/yr"
        default:
            return product.displayPrice
        }
    }

    private func restorePurchases() async {
        let wasUnlocked = stashyPlus.isUnlocked
        await storeManager.restorePurchases()
        if stashyPlus.isUnlocked {
            ToastManager.shared.show(
                wasUnlocked ? "Purchases restored" : "Stashy+ unlocked",
                icon: "sparkles",
                style: .success
            )
        } else {
            ToastManager.shared.show(
                "No Stashy+ purchase found on this Apple ID",
                icon: "info.circle",
                style: .error
            )
        }
    }

    private func iconFor(productID: String) -> String {
        switch productID {
        case StashyPlusProduct.monthly: return "calendar"
        case StashyPlusProduct.yearly: return "calendar.badge.clock"
        case StashyPlusProduct.lifetime: return "infinity"
        default: return "sparkles"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            Section("Links") {
                Link(destination: URL(string: "https://github.com/1letzgo/stashy")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(appearanceManager.tintColor)
                }
                Link(destination: URL(string: "https://discord.gg/D8wXv6Pm")!) {
                    Label("Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
        }
    }
    // MARK: - Interactive Devices
    private var interactiveDevicesSection: some View {
        Section(header: Text("Device Synchronization")) {
            NavigationLink(destination: HandySettingsView()) {
                Label("The Handy", systemImage: "hand.tap")
            }
            NavigationLink(destination: IntifaceSettingsView()) {
                Label("Intiface", systemImage: "cable.connector")
            }
            NavigationLink(destination: LoveSpouseSettingsView()) {
                Label("Love Spouse", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
        .listRowBackground(Color.secondaryAppBackground)
    }

    // MARK: - Actions

    private func startLibraryScan() {
        isScanningLibrary = true
        viewModel.triggerLibraryScan { success, message in
            DispatchQueue.main.async {
                isScanningLibrary = false
                scanAlertMessage = message
                showScanAlert = true
            }
        }
    }
}

// MARK: - StoreManager

public enum StoreError: Error {
    case failedVerification
}

@MainActor
class StoreManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoadingProducts = false
    @Published var lastProductError: String?
    @Published var isPurchasing = false
    @Published var isRestoringPurchases = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
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
            let requested = StashyPlusProduct.allIDs
            let products = try await Product.products(for: Array(requested))
            self.products = products.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            let loaded = Set(products.map(\.id))
            let missing = requested.subtracting(loaded).sorted()
            if products.isEmpty {
                lastProductError = "No Stashy+ products returned. For Xcode runs, enable Configuration.storekit on the stashy scheme. For TestFlight, the products must exist in App Store Connect."
                print("💬 StoreKit returned 0 products for \(requested.sorted())")
            } else if !missing.isEmpty {
                lastProductError = "Missing from StoreKit/App Store Connect: \(missing.joined(separator: ", "))"
                print("💬 StoreKit loaded \(loaded.sorted()), missing \(missing)")
            } else {
                lastProductError = nil
                print("💬 StoreKit loaded products: \(products.map(\.id))")
            }
        } catch {
            lastProductError = error.localizedDescription
            print("Failed product request from the App Store server: \(error)")
        }
    }

    /// Result used by the Settings UI for toasts.
    @discardableResult
    func purchase(_ product: Product) async -> String? {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                StashyPlusManager.shared.clearDebugForceLock()
                await apply(transaction)
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

    /// Refresh entitlements from StoreKit (subscriptions, lifetime, legacy paid app, old tips).
    func syncUnlockFromStore(scanTipHistory: Bool = false) async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if StashyPlusProduct.allIDs.contains(transaction.productID)
                || StashyPlusProduct.legacyTipIDs.contains(transaction.productID) {
                await apply(transaction)
            }
            await transaction.finish()
        }

        var hasLifetimePurchase = false
        var subscriptionProductID: String?
        var subscriptionExpiration: Date?
        var legacyTip = UserDefaults.standard.integer(forKey: StashyPlusManager.tipsCountKey) > 0
            || UserDefaults.standard.bool(forKey: StashyPlusManager.unlockedKey)

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

        // Tip history scan only on Restore (Transaction.all can be large).
        if scanTipHistory, !hasLifetimePurchase, !legacyTip {
            for await result in Transaction.all {
                guard case .verified(let transaction) = result else { continue }
                if StashyPlusProduct.legacyTipIDs.contains(transaction.productID) {
                    legacyTip = true
                    break
                }
            }
        }

        let legacyPaidApp = await Self.isLegacyPaidAppPurchaser()

        StashyPlusManager.shared.applyStoreEntitlements(
            hasLifetimePurchase: hasLifetimePurchase,
            subscriptionProductID: subscriptionProductID,
            subscriptionExpiration: subscriptionExpiration,
            legacyPaidApp: legacyPaidApp,
            legacyTip: legacyTip
        )

        if StashyPlusManager.shared.isUnlocked {
            print("✅ Stashy+ entitlement synced (\(StashyPlusManager.shared.source.rawValue))")
        }
    }

    func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        StashyPlusManager.shared.clearDebugForceLock()
        do {
            try await AppStore.sync()
        } catch {
            print("AppStore.sync failed: \(error)")
        }
        await syncUnlockFromStore(scanTipHistory: true)
    }

    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            print("Manage subscriptions failed: \(error)")
        }
    }

    private func apply(_ transaction: StoreKit.Transaction) async {
        if transaction.productID == StashyPlusProduct.lifetime
            || StashyPlusProduct.legacyTipIDs.contains(transaction.productID) {
            let source: StashyPlusSource = StashyPlusProduct.legacyTipIDs.contains(transaction.productID)
                ? .legacyTip
                : .lifetime
            await MainActor.run {
                StashyPlusManager.shared.unlockLifetime(source: source)
            }
        }
    }

    /// Paid-app buyers (original build before freemium) get Lifetime.
    /// TestFlight / Sandbox cannot prove a real App Store paid purchase — Apple always
    /// reports `originalAppVersion == "1.0"` there, so we skip grandfathering.
    private static func isLegacyPaidAppPurchaser() async -> Bool {
        do {
            let result = try await AppTransaction.shared
            let appTransaction = try Self.checkVerifiedStatic(result)
            if appTransaction.environment == .sandbox || appTransaction.environment == .xcode {
                print("ℹ️ Skipping paid-app grandfathering in \(appTransaction.environment) (originalAppVersion=\(appTransaction.originalAppVersion))")
                return false
            }
            let original = appTransaction.originalAppVersion
            let isLegacy = StashyPlusManager.isLegacyPaidAppVersion(original)
            print("ℹ️ AppTransaction originalAppVersion=\(original) legacyPaid=\(isLegacy)")
            return isLegacy
        } catch {
            print("AppTransaction check failed: \(error)")
            return false
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                let relevant = StashyPlusProduct.allIDs.contains(transaction.productID)
                    || StashyPlusProduct.legacyTipIDs.contains(transaction.productID)
                if relevant {
                    if transaction.productID == StashyPlusProduct.lifetime
                        || StashyPlusProduct.legacyTipIDs.contains(transaction.productID) {
                        let source: StashyPlusSource = StashyPlusProduct.legacyTipIDs.contains(transaction.productID)
                            ? .legacyTip
                            : .lifetime
                        await MainActor.run {
                            StashyPlusManager.shared.unlockLifetime(source: source)
                        }
                    }
                    await transaction.finish()
                    await Self.refreshEntitlements()
                } else {
                    await transaction.finish()
                }
            }
        }
    }

    /// Keeps entitlement fresh after renewals / revocations outside the purchase UI.
    private static func refreshEntitlements() async {
        var hasLifetimePurchase = false
        var subscriptionProductID: String?
        var subscriptionExpiration: Date?
        var legacyTip = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == StashyPlusProduct.lifetime {
                hasLifetimePurchase = true
            } else if StashyPlusProduct.subscriptionIDs.contains(transaction.productID) {
                let exp = transaction.expirationDate ?? .distantFuture
                if exp > Date() {
                    subscriptionExpiration = exp
                    subscriptionProductID = transaction.productID
                }
            } else if StashyPlusProduct.legacyTipIDs.contains(transaction.productID) {
                legacyTip = true
            }
        }

        let legacyPaidApp = await isLegacyPaidAppPurchaser()
        await MainActor.run {
            StashyPlusManager.shared.applyStoreEntitlements(
                hasLifetimePurchase: hasLifetimePurchase,
                subscriptionProductID: subscriptionProductID,
                subscriptionExpiration: subscriptionExpiration,
                legacyPaidApp: legacyPaidApp,
                legacyTip: legacyTip
            )
        }
    }

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        try Self.checkVerifiedStatic(result)
    }

    private static func checkVerifiedStatic<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}


struct IntifaceSettingsView: View {
    @ObservedObject var buttplugManager = ButtplugManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Intiface", isOn: $buttplugManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Intiface Server")) {
                TextField("Server Address", text: $buttplugManager.serverAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!buttplugManager.isEnabled)
                
                HStack {
                    Text("Status")
                    Spacer()
                    Text(buttplugManager.statusMessage)
                        .foregroundColor(buttplugManager.isConnected ? .green : .secondary)
                }
                
                if buttplugManager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        buttplugManager.disconnect()
                    }
                } else {
                    Button("Connect") {
                        buttplugManager.connect()
                    }
                    .disabled(!buttplugManager.isEnabled)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            if !buttplugManager.devices.isEmpty {
                Section(header: Text("Discovered Devices")) {
                    ForEach(buttplugManager.devices) { device in
                        HStack {
                            Image(systemName: "cable.connector")
                            Text(device.name)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            
            Section(footer: Text("Stashy connects to Intiface Desktop or Intiface Central via WebSockets. Ensure 'Enable Remote Network Access' is turned on in Intiface settings.")) {
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("Intiface")
    }
}

struct HandySettingsView: View {
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable The Handy", isOn: $handyManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Device Type"), footer: Text("The Handy uses HAMP protocol. The Oh. uses HVP protocol.")) {
                Picker("Device", selection: $handyManager.deviceType) {
                    Text("The Handy").tag("The Handy")
                    Text("The Oh.").tag("Oh.")
                }
                .pickerStyle(.segmented)
                .disabled(!handyManager.isEnabled)
            }
            .listRowBackground(Color.secondaryAppBackground)

            if handyManager.deviceType == "The Handy" {
                Section(header: Text("StashSync Controls")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Stroke Length")
                            Spacer()
                            Text("\(Int(handyManager.strokeLength))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.strokeLength, in: 10...100, step: 5)
                            .tint(appearanceManager.tintColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Velocity")
                            Spacer()
                            Text("\(Int(handyManager.maxVelocity))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.maxVelocity, in: 10...100, step: 5)
                            .tint(appearanceManager.tintColor)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!handyManager.isEnabled)
            } else {
                Section(header: Text("StashSync Controls")) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Intensity")
                            Spacer()
                            Text("\(Int(handyManager.maxAmplitude * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $handyManager.maxAmplitude, in: 0.1...1.0, step: 0.05)
                            .tint(appearanceManager.tintColor)
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
                .disabled(!handyManager.isEnabled)
            }

            Section(header: Text("Handy Connection"), footer: Text("Stashy now automatically uploads local funscripts to Handy Cloud. The Public URL is only needed for advanced setups.")) {
                TextField("Connection Key", text: HandyManager.shared.$connectionKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!handyManager.isEnabled)

                TextField("Public URL Override (Optional)", text: HandyManager.shared.$publicUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .disabled(!handyManager.isEnabled)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(handyManager.statusMessage)
                        .foregroundColor(handyManager.isConnected ? .green : .secondary)
                }

                Button("Check Connection") {
                    handyManager.checkConnection()
                }
                .disabled(!handyManager.isEnabled)
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("The Handy")
    }
}

struct LoveSpouseSettingsView: View {
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Love Spouse", isOn: $loveSpouseManager.isEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Connection Status")) {
                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(loveSpouseManager.statusMessage)
                        .foregroundColor(loveSpouseManager.isConnected ? .green : .secondary)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(footer: Text("Love Spouse 2.4g toys use BLE advertising. Ensure Bluetooth is enabled and the toy is in pairing/scan mode. Both toys in range will react simultaneously.")) {
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("Love Spouse")
    }
}


struct StashSyncSettingsView: View {
    @ObservedObject var videoManager = StashVideoSyncManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @State private var showingDisclaimer = false
    
    var body: some View {
        let syncEnabledBinding = Binding<Bool>(
            get: { stashyPlus.isUnlocked && videoManager.isVideoSyncEnabled },
            set: { newValue in
                guard stashyPlus.isUnlocked else { return }
                if newValue && !videoManager.isDisclaimerAccepted {
                    showingDisclaimer = true
                } else {
                    videoManager.isVideoSyncEnabled = newValue
                }
            }
        )
        
        Form {
            if !stashyPlus.isUnlocked {
                Section {
                    Label("StashSync requires Stashy+", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Unlock Stashy+ under Settings → Stashy+.")
                }
                .listRowBackground(Color.secondaryAppBackground)
            }

            Section(header: Text("StashSync Features"), footer: Text("StashSync uses real-time on-device video analysis to synchronize your devices. This process is CPU-intensive and can lead to increased battery drain and device heating. By enabling this feature, you acknowledge that you use StashSync and any controlled hardware devices at your own risk. Any potential damage or injury resulting from the use of connected hardware is your sole responsibility.")) {
                Toggle(isOn: syncEnabledBinding) {
                    Label("StashSync", systemImage: "bolt.fill")
                }
                .tint(appearanceManager.tintColor)
                .disabled(!stashyPlus.isUnlocked)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Sensitivity")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("StashSync Sensitivity")
                        Spacer()
                        Text("\(Int(videoManager.sensitivity * 50))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.sensitivity, in: 0.1...2.0).tint(.orange)
                }.padding(.vertical, 4)
            }
            .disabled(!videoManager.isVideoSyncEnabled)
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Optical Flow Smoothing")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Smoothing")
                        Spacer()
                        Text("\(Int(videoManager.smoothing * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.smoothing, in: 0.0...0.9).tint(.orange)
                }
            }
            .disabled(!videoManager.isVideoSyncEnabled)
            .listRowBackground(Color.secondaryAppBackground)
            

        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashySettingsDetailChrome("StashSync")
        .alert("StashSync Disclaimer", isPresented: $showingDisclaimer) {
            Button("Cancel", role: .cancel) { }
            Button("Accept & Enable") {
                videoManager.isDisclaimerAccepted = true
                videoManager.isVideoSyncEnabled = true
            }
        } message: {
            Text("StashSync uses real-time on-device video analysis to synchronize your devices. This process is CPU-intensive and can lead to increased battery drain and device heating. By enabling this feature, you acknowledge that you use StashSync and any controlled hardware devices at your own risk. Any potential damage or injury resulting from the use of connected hardware is your sole responsibility.")
        }
    }
}

#Preview {
    SettingsView()
}

#endif
