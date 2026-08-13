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
    /// When true, this instance is the locked stashy+ tab (paywall only — no Settings chrome).
    var stashyPlusOnly: Bool = false

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
    
    // IAP / stashy+
    @StateObject private var storeManager = StoreManager()
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    enum SettingsSection: String, CaseIterable, Identifiable {
        case main = "Main"
        case actions = "Actions"
        case design = "Design"
        case stashyPlus = "stashy+"
        
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

    private var chromeSections: [SettingsSection] {
        if stashyPlusOnly { return [.stashyPlus] }
        if stashyPlus.isUnlocked { return Array(SettingsSection.allCases) }
        return SettingsSection.allCases.filter { $0 != .stashyPlus }
    }

    private var activeSection: SettingsSection {
        if stashyPlusOnly { return .stashyPlus }
        if selectedSection == .stashyPlus && !stashyPlus.isUnlocked { return .main }
        return selectedSection
    }

    var body: some View {
        Group {
            if activeSection == .actions {
                ToolsServerView(embedded: true)
            } else {
                Form {
                    switch activeSection {
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
        .tint(appearanceManager.tintColor)
        .navigationBarHidden(true)
        .popNavigationToRootOnChange(activeSection.rawValue)
        .stashyCustomChromeInset(spacing: 0) {
            StashySectionChromeBar {
                SettingsCategoryRow(
                    selection: Binding(
                        get: { activeSection },
                        set: { newValue in
                            guard !stashyPlusOnly else { return }
                            selectedSection = newValue
                        }
                    ),
                    sections: chromeSections
                )
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
            if !stashyPlusOnly && selectedSection == .stashyPlus && !stashyPlus.isUnlocked {
                selectedSection = .main
            }
        }
        .onChange(of: stashyPlus.isUnlocked) { _, unlocked in
            if !stashyPlusOnly && !unlocked && selectedSection == .stashyPlus {
                selectedSection = .main
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

        if stashyPlus.isUnlocked {
            Section(header: Text("Custom App Icons")) {
                StashyPlusAppIconSettings()
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("AI Subtitles and translation")) {
                StashyPlusAISubtitlesSettings()
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text(AIMotionCopy.name)) {
                NavigationLink(destination: StashSyncSettingsView()) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Tools")) {
                StashyPlusToolToggle(item: .downloads)
                StashyPlusToolToggle(item: .statistics)
                StashyPlusToolToggle(item: .hotOrNot)
                StashyPlusToolToggle(item: .rateMe)
            }
            .listRowBackground(Color.secondaryAppBackground)
        } else {
            Section(header: Text("Included with stashy+")) {
                Label("Custom App Icons", systemImage: "lock.fill")
                Label("Download Scenes", systemImage: "lock.fill")
                Label("AI Subtitles and translation", systemImage: "lock.fill")
                Label(AIMotionCopy.name, systemImage: "lock.fill")
                Label(ToolsItem.statistics.plusFeatureTitle, systemImage: "lock.fill")
                Label(ToolsItem.hotOrNot.plusFeatureTitle, systemImage: "lock.fill")
                Label(ToolsItem.rateMe.title, systemImage: "lock.fill")
            }
            .foregroundColor(.secondary)
            .listRowBackground(Color.secondaryAppBackground)
        }

        stashyPlusPurchaseSection
    }

    // MARK: - TestFlight Banner

    @Environment(\.openURL) private var openURL

    private var appStoreBanner: some View {
        Button {
            if let url = URL(string: "https://discord.gg/cGpVgRbHQ") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TestFlight ends 15 September")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("From then on, stashy is free on the App Store.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    featureRow(icon: "infinity", text: "Grab a Lifetime license at the current price before then")
                    featureRow(icon: "checkmark.seal.fill", text: "Lifetime keeps stashy+ unlocked forever on this Apple ID")
                }

                HStack {
                    Spacer()
                    Text("Join Discord")
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
        .buttonStyle(.plain)
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

    // MARK: - stashy+ In-App Purchases

    private var sortedProducts: [Product] {
        storeManager.products.sorted {
            (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
        }
    }

    private var showsLegacyAppLifetimeButton: Bool {
        stashyPlus.source == .legacyPaidApp
    }

    @ViewBuilder
    private var stashyPlusPurchaseSection: some View {
        Group {
            if showsLegacyAppLifetimeButton {
                Section {
                    legacyAppLifetimeButton
                } header: {
                    Text("stashy+")
                } footer: {
                    Text(stashyPlus.source.statusDetail)
                }
                .listRowBackground(Color.green)
            }

            if showsPurchaseMenu {
                Section {
                    if stashyPlus.isUnlocked && !showsLegacyAppLifetimeButton {
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
                                    Text("Loading stashy+ options…")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(storeManager.lastProductError ?? "stashy+ products unavailable.")
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
                            ForEach(sortedProducts) { product in
                                Button {
                                    Task { await purchaseStashyPlus(product) }
                                } label: {
                                    HStack {
                                        stashyPlusRowLabel(
                                            StashyPlusProduct.displayNames[product.id] ?? product.displayName,
                                            systemImage: iconFor(productID: product.id)
                                        )
                                        Spacer()
                                        if storeManager.isPurchasing {
                                            ProgressView()
                                        } else {
                                            Text(priceLabel(for: product))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
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
                                stashyPlusRowLabel("Restore Purchases", systemImage: "arrow.clockwise")
                                Spacer()
                                if storeManager.isRestoringPurchases {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(storeManager.isPurchasing || storeManager.isRestoringPurchases)
                    }

                    if stashyPlus.source == .subscription {
                        Button {
                            Task { await storeManager.manageSubscriptions() }
                        } label: {
                            stashyPlusRowLabel("Manage Subscription", systemImage: "creditcard")
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(stashyPlus.isUnlocked ? "stashy+" : "Unlock stashy+")
                } footer: {
                    if !stashyPlus.isUnlocked {
                        Text("Monthly, Yearly, or Lifetime. If you bought the app at full price, tap Restore Purchases.")
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
        }
        .task {
            await storeManager.syncUnlockFromStore()
            if storeManager.products.isEmpty {
                await storeManager.fetchProducts()
            }
        }
    }

    private var showsPurchaseMenu: Bool {
        !showsLegacyAppLifetimeButton
            || stashyPlus.shouldOfferPurchases
            || !stashyPlus.isUnlocked
    }

    private var legacyAppLifetimeButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Grab Lifetime")
                    .font(.subheadline.weight(.bold))
                Text("Included with your app purchase")
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
            Text("Purchased")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.vertical, 6)
    }

    private func stashyPlusRowLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundColor(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundColor(appearanceManager.tintColor)
        }
    }

    private func purchaseStashyPlus(_ product: Product) async {
        if let error = await storeManager.purchase(product) {
            ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
        } else if stashyPlus.isUnlocked {
            ToastManager.shared.show("stashy+ unlocked — thank you!", icon: "sparkles", style: .success)
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
        product.displayPrice
    }

    private func restorePurchases() async {
        let wasUnlocked = stashyPlus.isUnlocked
        await storeManager.restorePurchases()
        if stashyPlus.isUnlocked {
            ToastManager.shared.show(
                wasUnlocked ? "Purchases restored" : "stashy+ unlocked",
                icon: "sparkles",
                style: .success
            )
        } else {
            ToastManager.shared.show(
                "No stashy+ purchase found on this Apple ID",
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
        case StashyPlusProduct.tipSmall: return "heart"
        case StashyPlusProduct.tipMedium: return "heart.fill"
        case StashyPlusProduct.tipLarge: return "bolt.heart.fill"
        default: return "sparkles"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {
            tipSection

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

    private var sortedTipProducts: [Product] {
        storeManager.tipProducts.sorted {
            (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
        }
    }

    @ViewBuilder
    private var tipSection: some View {
        Section {
            if sortedTipProducts.isEmpty {
                if storeManager.isLoadingProducts {
                    HStack {
                        ProgressView()
                        Text("Loading tips…")
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips unavailable.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await storeManager.fetchProducts() }
                        }
                    }
                }
            } else {
                ForEach(sortedTipProducts) { product in
                    Button {
                        Task { await purchaseTip(product) }
                    } label: {
                        HStack {
                            stashyPlusRowLabel(
                                StashyPlusProduct.displayNames[product.id] ?? product.displayName,
                                systemImage: iconFor(productID: product.id)
                            )
                            Spacer()
                            if storeManager.isPurchasing {
                                ProgressView()
                            } else {
                                Text(product.displayPrice)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(storeManager.isPurchasing)
                }
            }
        } header: {
            Text("Tips")
        } footer: {
            Text("Support stashy. Tips do not unlock stashy+.")
        }
        .listRowBackground(Color.secondaryAppBackground)
        .task {
            if storeManager.tipProducts.isEmpty {
                await storeManager.fetchProducts()
            }
        }
    }

    private func purchaseTip(_ product: Product) async {
        if let error = await storeManager.purchase(product) {
            ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
        } else {
            ToastManager.shared.show("Thank you for the tip!", icon: "heart.fill", style: .success)
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
    @Published var tipProducts: [Product] = []
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
            let plusIDs = StashyPlusProduct.allIDs
            let tipIDs = StashyPlusProduct.tipIDs
            let loaded = try await Product.products(for: Array(plusIDs.union(tipIDs)))
            self.products = loaded.filter { plusIDs.contains($0.id) }.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            self.tipProducts = loaded.filter { tipIDs.contains($0.id) }.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            let loadedPlus = Set(self.products.map(\.id))
            let missing = plusIDs.subtracting(loadedPlus).sorted()
            if self.products.isEmpty {
                lastProductError = "No stashy+ products returned. For Xcode runs, enable Configuration.storekit on the stashy scheme. For TestFlight, the products must exist in App Store Connect."
                print("💬 StoreKit returned 0 stashy+ products for \(plusIDs.sorted())")
            } else if !missing.isEmpty {
                lastProductError = "Missing from StoreKit/App Store Connect: \(missing.joined(separator: ", "))"
                print("💬 StoreKit loaded \(loadedPlus.sorted()), missing \(missing)")
            } else {
                lastProductError = nil
                print("💬 StoreKit loaded products: \(loaded.map(\.id))")
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
                if StashyPlusProduct.tipIDs.contains(transaction.productID) {
                    await transaction.finish()
                    return nil
                }
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

    /// Refresh entitlements from StoreKit (subscriptions, lifetime, legacy paid app).
    /// Existing UserDefaults from the old tip-unlock era still count; new tips do not.
    func syncUnlockFromStore() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if StashyPlusProduct.allIDs.contains(transaction.productID) {
                await apply(transaction)
            }
            await transaction.finish()
        }

        var hasLifetimePurchase = false
        var subscriptionProductID: String?
        var subscriptionExpiration: Date?
        let legacyTip = UserDefaults.standard.integer(forKey: StashyPlusManager.tipsCountKey) > 0
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

        let legacyPaidApp = await Self.isLegacyPaidAppPurchaser()

        StashyPlusManager.shared.applyStoreEntitlements(
            hasLifetimePurchase: hasLifetimePurchase,
            subscriptionProductID: subscriptionProductID,
            subscriptionExpiration: subscriptionExpiration,
            legacyPaidApp: legacyPaidApp,
            legacyTip: legacyTip
        )

        if StashyPlusManager.shared.isUnlocked {
            print("✅ stashy+ entitlement synced (\(StashyPlusManager.shared.source.rawValue))")
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
        await syncUnlockFromStore()
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
        guard transaction.productID == StashyPlusProduct.lifetime else { return }
        await MainActor.run {
            StashyPlusManager.shared.unlockLifetime(source: .lifetime)
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
                if relevant {
                    if transaction.productID == StashyPlusProduct.lifetime {
                        await MainActor.run {
                            StashyPlusManager.shared.unlockLifetime(source: .lifetime)
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
        let legacyTip = UserDefaults.standard.integer(forKey: StashyPlusManager.tipsCountKey) > 0
            || UserDefaults.standard.bool(forKey: StashyPlusManager.unlockedKey)

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
                Section(header: Text("AI Motion Controls")) {
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
                Section(header: Text("AI Motion Controls")) {
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
                    Label(AIMotionCopy.requiresPlus, systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("Unlock stashy+ to use this feature.")
                }
                .listRowBackground(Color.secondaryAppBackground)
            }

            Section(header: Text("AI Motion Features"), footer: Text(AIMotionCopy.disclaimer)) {
                Toggle(isOn: syncEnabledBinding) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
                .tint(appearanceManager.tintColor)
                .disabled(!stashyPlus.isUnlocked)
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section(header: Text("Sensitivity")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("AI Motion Sensitivity")
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
        .stashySettingsDetailChrome(AIMotionCopy.name)
        .alert("AI Motion Disclaimer", isPresented: $showingDisclaimer) {
            Button("Cancel", role: .cancel) { }
            Button("Accept & Enable") {
                videoManager.isDisclaimerAccepted = true
                videoManager.isVideoSyncEnabled = true
            }
        } message: {
            Text(AIMotionCopy.disclaimer)
        }
    }
}

#Preview {
    SettingsView()
}

#endif
