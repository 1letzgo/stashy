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
    @ObservedObject private var storeManager = StoreManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    enum SettingsSection: String, CaseIterable, Identifiable {
        case main = "Main"
        case stashyPlus = "stashy+"
        case actions = "Actions"
        case design = "Design"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .main: return "gearshape.fill"
            case .stashyPlus: return "sparkles"
            case .actions: return "server.rack"
            case .design: return "paintbrush.fill"
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
                List {
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
                .stashySettingsList()
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
        Section {
            stashyScrollingSectionHeader("Appearance")
            NavigationLink(destination: AppearanceSettingsView()) {
                Label("Appearance", systemImage: "paintbrush")
            }
            .stashyGroupedBlockRow(index: 0, count: 2)
            NavigationLink(destination: EditModeSettingsView()) {
                Label("Editing", systemImage: "pencil.circle")
            }
            .stashyGroupedBlockRow(index: 1, count: 2)
        }

        Section {
            stashyScrollingSectionHeader("Security")
            NavigationLink(destination: SecuritySettingsView()) {
                Label("Security", systemImage: "lock.shield")
            }
            .stashyGroupedSettingsRow()
        }

        if configManager.activeConfig != nil {
            ContentSettingsSection()
        } else {
            Section {
                Text("Content settings require an active server.")
                    .foregroundColor(.secondary)
                    .stashyGroupedSettingsRow()
            }
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
            Section {
                stashyScrollingSectionHeader("Custom App Icons")
                StashyPlusAppIconSettings()
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader("AI Subtitles and translation", isBeta: true)
                StashyPlusAISubtitlesSettings()
            }

            Section {
                stashyScrollingSectionHeader(AIMotionCopy.name, isBeta: true)
                NavigationLink(destination: StashSyncSettingsView()) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
                .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader("Tools")
                StashyPlusToolToggle(item: .downloads)
                    .stashyGroupedBlockRow(index: 0, count: 4)
                StashyPlusToolToggle(item: .statistics)
                    .stashyGroupedBlockRow(index: 1, count: 4)
                StashyPlusToolToggle(item: .hotOrNot)
                    .stashyGroupedBlockRow(index: 2, count: 4)
                StashyPlusToolToggle(item: .rateMe)
                    .stashyGroupedBlockRow(index: 3, count: 4)
            }
        } else {
            Section {
                stashyScrollingSectionHeader("Included with stashy+")
                Label("Custom App Icons", systemImage: "lock.fill")
                    .foregroundColor(.secondary)
                    .stashyGroupedBlockRow(index: 0, count: 7)
                Label("Download Scenes", systemImage: "lock.fill")
                    .foregroundColor(.secondary)
                    .stashyGroupedBlockRow(index: 1, count: 7)
                lockedPlusFeature("AI Subtitles and translation", systemImage: "lock.fill", isBeta: true)
                    .stashyGroupedBlockRow(index: 2, count: 7)
                lockedPlusFeature(AIMotionCopy.name, systemImage: "lock.fill", isBeta: true)
                    .stashyGroupedBlockRow(index: 3, count: 7)
                Label(ToolsItem.statistics.plusFeatureTitle, systemImage: "lock.fill")
                    .foregroundColor(.secondary)
                    .stashyGroupedBlockRow(index: 4, count: 7)
                Label(ToolsItem.hotOrNot.plusFeatureTitle, systemImage: "lock.fill")
                    .foregroundColor(.secondary)
                    .stashyGroupedBlockRow(index: 5, count: 7)
                Label(ToolsItem.rateMe.title, systemImage: "lock.fill")
                    .foregroundColor(.secondary)
                    .stashyGroupedBlockRow(index: 6, count: 7)
            }
        }

        stashyPlusPurchaseSection
    }

    private func lockedPlusFeature(_ title: String, systemImage: String, isBeta: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundColor(.secondary)
            if isBeta {
                Spacer()
                StashyBetaBadge()
            }
        }
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
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.38, blue: 0.95), Color(red: 0.55, green: 0.2, blue: 0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
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
                    stashyScrollingSectionHeader("stashy+")
                    legacyAppLifetimeButton
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                                .fill(Color.green)
                        )
                    stashyScrollingSectionFooter(stashyPlus.source.statusDetail)
                }
            }

            if showsPurchaseMenu {
                Section {
                    stashyScrollingSectionHeader(stashyPlus.isUnlocked ? "stashy+" : "Unlock stashy+")

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
                        .stashyGroupedSettingsRow()
                    }

                    if stashyPlus.shouldOfferPurchases {
                        if storeManager.products.isEmpty {
                            if storeManager.isLoadingProducts {
                                HStack {
                                    ProgressView()
                                    Text("Loading stashy+ options…")
                                        .foregroundColor(.secondary)
                                }
                                .stashyGroupedSettingsRow()
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
                                .stashyGroupedSettingsRow()
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
                                .stashySettingsCardRow()
                            }
                            if let missing = storeManager.lastProductError, missing.hasPrefix("Missing from StoreKit") {
                                Text(missing)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .stashyGroupedSettingsRow()
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
                        .stashyGroupedSettingsRow()
                    }

                    if stashyPlus.source == .subscription {
                        Button {
                            Task { await storeManager.manageSubscriptions() }
                        } label: {
                            stashyPlusRowLabel("Manage Subscription", systemImage: "creditcard")
                        }
                        .buttonStyle(.plain)
                        .stashyGroupedSettingsRow()
                    }

                    if !stashyPlus.isUnlocked {
                        stashyScrollingSectionFooter("Monthly, Yearly, or Lifetime. If you bought the app at full price, tap Restore Purchases.")
                    }
                }
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

            Section {
                stashyScrollingSectionHeader("Links")
                Link(destination: URL(string: "https://github.com/1letzgo/stashy")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .stashyGroupedBlockRow(index: 0, count: 2)
                Link(destination: URL(string: "https://discord.gg/D8wXv6Pm")!) {
                    Label("Discord", systemImage: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .stashyGroupedBlockRow(index: 1, count: 2)
            }
            
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
            stashyScrollingSectionHeader("Tips")
            if sortedTipProducts.isEmpty {
                if storeManager.isLoadingProducts {
                    HStack {
                        ProgressView()
                        Text("Loading tips…")
                            .foregroundColor(.secondary)
                    }
                    .stashyGroupedSettingsRow()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips unavailable.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await storeManager.fetchProducts() }
                        }
                    }
                    .stashyGroupedSettingsRow()
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
                    .stashySettingsCardRow()
                }
            }
            stashyScrollingSectionFooter("Support stashy. Tips do not unlock stashy+.")
        }
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
        Section {
            stashyScrollingSectionHeader("Device Synchronization")
            NavigationLink(destination: HandySettingsView()) {
                Label("The Handy", systemImage: "hand.tap")
            }
            .stashyGroupedBlockRow(index: 0, count: 3)
            NavigationLink(destination: IntifaceSettingsView()) {
                Label("Intiface", systemImage: "cable.connector")
            }
            .stashyGroupedBlockRow(index: 1, count: 3)
            NavigationLink(destination: LoveSpouseSettingsView()) {
                Label("Love Spouse", systemImage: "antenna.radiowaves.left.and.right")
            }
            .stashyGroupedBlockRow(index: 2, count: 3)
        }
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
    static let shared = StoreManager()

    @Published var products: [Product] = []
    @Published var tipProducts: [Product] = []
    @Published var isLoadingProducts = false
    @Published var lastProductError: String?
    @Published var isPurchasing = false
    @Published var isRestoringPurchases = false

    private var transactionListener: Task<Void, Never>?
    private var legacyPaidRetryCount = 0

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

        let legacyPaidApp: Bool
        switch await Self.isLegacyPaidAppPurchaser() {
        case .yes:
            legacyPaidApp = true
            legacyPaidRetryCount = 0
        case .no:
            legacyPaidApp = false
            legacyPaidRetryCount = 0
        case .unknown:
            // Don't treat a StoreKit outage as "not a paid buyer". Keep any
            // previously persisted grandfathering and retry a few times.
            legacyPaidApp = UserDefaults.standard.string(forKey: StashyPlusManager.sourceKey)
                == StashyPlusSource.legacyPaidApp.rawValue
                || UserDefaults.standard.bool(forKey: StashyPlusManager.lifetimeKey)
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

    /// Paid-app buyers (original version before 3.0) get Lifetime.
    /// TestFlight / Sandbox cannot prove a real App Store paid purchase — Apple always
    /// reports `originalAppVersion == "1.0"` there, so we skip grandfathering.
    private enum LegacyPaidAppResult {
        case yes, no, unknown
    }

    private static func isLegacyPaidAppPurchaser() async -> LegacyPaidAppResult {
        do {
            let result = try await AppTransaction.shared
            let appTransaction = try Self.checkVerifiedStatic(result)
            if appTransaction.environment == .sandbox || appTransaction.environment == .xcode {
                print("ℹ️ Skipping paid-app grandfathering in \(appTransaction.environment) (originalAppVersion=\(appTransaction.originalAppVersion))")
                return .no
            }
            let original = appTransaction.originalAppVersion
            let isLegacy = StashyPlusManager.isLegacyPaidAppVersion(original)
            print("ℹ️ AppTransaction originalAppVersion=\(original) pre-3.0 paid=\(isLegacy)")
            return isLegacy ? .yes : .no
        } catch {
            print("AppTransaction check failed: \(error)")
            return .unknown
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

        let legacyPaidApp: Bool
        switch await isLegacyPaidAppPurchaser() {
        case .yes: legacyPaidApp = true
        case .no: legacyPaidApp = false
        case .unknown:
            legacyPaidApp = UserDefaults.standard.string(forKey: StashyPlusManager.sourceKey)
                == StashyPlusSource.legacyPaidApp.rawValue
                || UserDefaults.standard.bool(forKey: StashyPlusManager.lifetimeKey)
        }
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
        let serverRowCount = 3
        List {
            Section {
                Toggle("Enable Intiface", isOn: $buttplugManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader("Intiface Server")
                TextField("Server Address", text: $buttplugManager.serverAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!buttplugManager.isEnabled)
                    .stashyGroupedBlockRow(index: 0, count: serverRowCount)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(buttplugManager.statusMessage)
                        .foregroundColor(buttplugManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedBlockRow(index: 1, count: serverRowCount)

                if buttplugManager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        buttplugManager.disconnect()
                    }
                    .stashyGroupedBlockRow(index: 2, count: serverRowCount)
                } else {
                    Button("Connect") {
                        buttplugManager.connect()
                    }
                    .disabled(!buttplugManager.isEnabled)
                    .stashyGroupedBlockRow(index: 2, count: serverRowCount)
                }
            }

            if !buttplugManager.devices.isEmpty {
                Section {
                    stashyScrollingSectionHeader("Discovered Devices")
                    ForEach(Array(buttplugManager.devices.enumerated()), id: \.element.id) { index, device in
                        HStack {
                            Image(systemName: "cable.connector")
                            Text(device.name)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .stashyGroupedBlockRow(index: index, count: buttplugManager.devices.count)
                    }
                }
            }

            Section {
                stashyScrollingSectionFooter("Stashy connects to Intiface Desktop or Intiface Central via WebSockets. Ensure 'Enable Remote Network Access' is turned on in Intiface settings.")
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Intiface")
    }
}

struct HandySettingsView: View {
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                Toggle("Enable The Handy", isOn: $handyManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader("Device Type")
                Picker("Device", selection: $handyManager.deviceType) {
                    Text("The Handy").tag("The Handy")
                    Text("The Oh.").tag("Oh.")
                }
                .pickerStyle(.segmented)
                .disabled(!handyManager.isEnabled)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter("The Handy uses HAMP protocol. The Oh. uses HVP protocol.")
            }

            if handyManager.deviceType == "The Handy" {
                Section {
                    stashyScrollingSectionHeader("AI Motion Controls")
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
                    .stashyGroupedBlockRow(index: 0, count: 2)
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
                    .stashyGroupedBlockRow(index: 1, count: 2)
                }
                .disabled(!handyManager.isEnabled)
            } else {
                Section {
                    stashyScrollingSectionHeader("AI Motion Controls")
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
                    .stashyGroupedSettingsRow()
                }
                .disabled(!handyManager.isEnabled)
            }

            Section {
                stashyScrollingSectionHeader("Handy Connection")
                TextField("Connection Key", text: HandyManager.shared.$connectionKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!handyManager.isEnabled)
                    .stashyGroupedBlockRow(index: 0, count: 4)

                TextField("Public URL Override (Optional)", text: HandyManager.shared.$publicUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .disabled(!handyManager.isEnabled)
                    .stashyGroupedBlockRow(index: 1, count: 4)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(handyManager.statusMessage)
                        .foregroundColor(handyManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedBlockRow(index: 2, count: 4)

                Button("Check Connection") {
                    handyManager.checkConnection()
                }
                .disabled(!handyManager.isEnabled)
                .stashyGroupedBlockRow(index: 3, count: 4)

                stashyScrollingSectionFooter("Stashy now automatically uploads local funscripts to Handy Cloud. The Public URL is only needed for advanced setups.")
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("The Handy")
    }
}

struct LoveSpouseSettingsView: View {
    @ObservedObject var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        List {
            Section {
                Toggle("Enable Love Spouse", isOn: $loveSpouseManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader("Connection Status")
                HStack {
                    Text("Bluetooth")
                    Spacer()
                    Text(loveSpouseManager.statusMessage)
                        .foregroundColor(loveSpouseManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionFooter("Love Spouse 2.4g toys use BLE advertising. Ensure Bluetooth is enabled and the toy is in pairing/scan mode. Both toys in range will react simultaneously.")
            }
        }
        .stashySettingsList()
        .applyAppBackground()
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
        
        List {
            if !stashyPlus.isUnlocked {
                Section {
                    Label(AIMotionCopy.requiresPlus, systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                    stashyScrollingSectionFooter("Unlock stashy+ to use this feature.")
                }
            }

            Section {
                stashyScrollingSectionHeader("AI Motion Features")
                Toggle(isOn: syncEnabledBinding) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
                .tint(appearanceManager.tintColor)
                .disabled(!stashyPlus.isUnlocked)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(AIMotionCopy.disclaimer)
            }

            Section {
                stashyScrollingSectionHeader("Sensitivity")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("AI Motion Sensitivity")
                        Spacer()
                        Text("\(Int(videoManager.sensitivity * 50))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.sensitivity, in: 0.1...2.0).tint(.orange)
                }
                .padding(.vertical, 4)
                .stashyGroupedSettingsRow()
            }
            .disabled(!videoManager.isVideoSyncEnabled)

            Section {
                stashyScrollingSectionHeader("Optical Flow Smoothing")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Smoothing")
                        Spacer()
                        Text("\(Int(videoManager.smoothing * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $videoManager.smoothing, in: 0.0...0.9).tint(.orange)
                }
                .stashyGroupedSettingsRow()
            }
            .disabled(!videoManager.isVideoSyncEnabled)
        }
        .stashySettingsList()
        .applyAppBackground()
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
