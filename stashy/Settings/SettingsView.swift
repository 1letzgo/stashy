//
//  SettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI
import StoreKit
import RevenueCat
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

private enum StashyLegalLinks {
    /// Apple Standard EULA — required in App Store metadata for auto-renewable subscriptions.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://github.com/1letzgo/stashy#privacy")!
}

/// What each stashy+ feature does, shown on the stashy+ page while locked and while unlocked.
private enum StashyPlusFeatureCopy {
    struct LockedFeature {
        let title: String
        let detail: String
        var isBeta = false
    }

    #if os(macOS)
    static var appIcons: String { tr("hint_changes_stashy_app_icon_on") }
    #else
    static var appIcons: String { tr("hint_changes_stashy_app_icon_to") }
    #endif
    static var downloads: String { tr("hint_saves_scenes_to_your_device") }
    static var miniPlayer: String { tr("hint_keeps_scene_playing_in_small") }
    static var magazine: String { tr("hint_adds_magazin_view_on_home") }
    static var aiSubtitles: String { tr("hint_creates_subtitles_from_scenes_speech") }
    static var tagSuggestions: String { tr("hint_suggests_tags_based_on_how") }
    static var aiMotion: String { tr("hint_analyzes_playing_video_live_on") }
    static var overview: String { tr("hint_shows_your_library_at_glance") }
    static var oCount: String { tr("hint_shows_o_counts_of_your") }
    static var timeline: String { tr("hint_lists_your_scene_plays_o") }
    static var charts: String { tr("hint_ranks_your_top_scenes_performers") }
    static var filters: String { tr("hint_lets_you_create_edit_rename") }
    static var match: String { tr("hint_puts_performers_against_each_other") }
    static var rateMe: String { tr("hint_shows_unrated_scenes_or_images") }

    static var lockedFeatures: [LockedFeature] {
[
        .init(title: tr("custom_app_icons"), detail: appIcons),
        .init(title: tr("action_download_scenes"), detail: downloads),
        .init(title: tr("miniplayer_and_watchlist"), detail: miniPlayer),
        .init(title: tr("ai_subtitles_and_translation"), detail: aiSubtitles, isBeta: true),
        .init(title: AIMotionCopy.name, detail: aiMotion, isBeta: true),
        .init(title: ToolsItem.statistics.plusFeatureTitle, detail: overview),
        .init(title: ToolsItem.oCount.plusFeatureTitle, detail: oCount),
        .init(title: ToolsItem.timeline.plusFeatureTitle, detail: timeline),
        .init(title: ToolsItem.topLists.plusFeatureTitle, detail: charts),
        .init(title: ToolsItem.filters.plusFeatureTitle, detail: filters),
        .init(title: ToolsItem.hotOrNot.plusFeatureTitle, detail: match),
        .init(title: ToolsItem.rateMe.title, detail: rateMe),
        .init(title: tr("magazin"), detail: magazine),
        .init(title: tr("recommendations"), detail: tagSuggestions, isBeta: true),
    ]
    }
}

struct SettingsView: View {
    /// When true, this instance is the locked stashy+ tab (paywall only — no Settings chrome).
    var stashyPlusOnly: Bool = false

    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
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
    @AppStorage(MagazineMode.enabledKey) private var isMagazineEnabled = false

    enum SettingsSection: String, CaseIterable, Identifiable {
        case main = "Settings"
        case design = "Design"
        case actions = "Server"
        case stashyPlus = "stashy+"
        
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
        .popNavigationToRootOnChange(activeSection.rawValue)
        .stashySectionChrome(showsSwitcher: chromeSections.count > 1) {
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
        }
        .sheet(isPresented: $showingAddServerSheet) {
            NavigationStack {
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
            NavigationStack {
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
                viewModel.testConnection(force: true)
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
        .alert(tr("library_scan"), isPresented: $showScanAlert) {
            Button(tr("ok"), role: .cancel) { }
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

        Section {
            stashyScrollingSectionHeader(tr("app_language"), isBeta: true)
            AppLanguageRow()
                .stashyGroupedSettingsRow()
        }

        if configManager.activeConfig != nil {
            PlaybackSettingsSection()
            interactiveDevicesSection
        }

        Section {
            stashyScrollingSectionHeader(tr("backup_and_transfer"))
            SettingsTransferControls(groupedRows: true)
            stashyScrollingSectionFooter(tr("hint_servers_settings_default_filters_dashboard"))
        }

        Section {
            stashyScrollingSectionHeader("iCloud")
            ICloudSettingsSyncRow()
            stashyScrollingSectionFooter(tr("hint_keeps_servers_api_keys_and"))
        }

        aboutSection
    }

    @ViewBuilder
    private var designSettings: some View {
        Section {
            stashyScrollingSectionHeader(tr("appearance"))
            NavigationLink(destination: AppearanceSettingsView()) {
                Label(tr("appearance"), systemImage: "paintbrush")
            }
            .stashyGroupedBlockRow(index: 0, count: 3)
            NavigationLink(destination: EditModeSettingsView()) {
                Label(tr("editing"), systemImage: "pencil.circle")
            }
            .stashyGroupedBlockRow(index: 1, count: 3)
            NavigationLink(destination: SceneDetailLayoutSettingsView()) {
                Label(tr("scene_view"), systemImage: "rectangle.stack")
            }
            .stashyGroupedBlockRow(index: 2, count: 3)
        }

        Section {
            stashyScrollingSectionHeader(tr("security"))
            NavigationLink(destination: SecuritySettingsView()) {
                Label(tr("security"), systemImage: "lock.shield")
            }
            .stashyGroupedSettingsRow()
        }

        if configManager.activeConfig != nil {
            ContentSettingsSection()
        } else {
            Section {
                Text(tr("hint_content_settings_require_active_server"))
                    .foregroundColor(.secondary)
                    .stashyGroupedSettingsRow()
            }
        }
    }

    @ViewBuilder
    private var stashyPlusSettings: some View {
        if stashyPlus.isUnlocked {
            Section {
                stashyScrollingSectionHeader(tr("custom_app_icons"))
                StashyPlusAppIconSettings()
                    .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.appIcons)
            }

            Section {
                stashyScrollingSectionHeader(tr("miniplayer_and_watchlist"))
                Toggle(isOn: $tabManager.isMiniPlayerEnabled) {
                    Label(tr("miniplayer_and_watchlist"), systemImage: "rectangle.bottomhalf.inset.filled")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.miniPlayer)
            }

            Section {
                stashyScrollingSectionHeader(tr("magazin"))
                Toggle(isOn: $isMagazineEnabled) {
                    Label(tr("magazin_ereader"), systemImage: "magazine")
                }
                .tint(appearanceManager.tintColor)
                .stashyGroupedBlockRow(index: 0, count: isMagazineEnabled ? 2 : 1)

                if isMagazineEnabled {
                    HStack {
                        Text(tr("default_filter"))
                        Spacer()
                        MagazineDefaultFilterMenu(viewModel: viewModel)
                    }
                    .stashyGroupedBlockRow(index: 1, count: 2)
                    .task { viewModel.fetchSavedFilters() }
                }
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.magazine)
            }

            Section {
                stashyScrollingSectionHeader(tr("ai_subtitles_and_translation"), isBeta: true)
                StashyPlusAISubtitlesSettings()
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.aiSubtitles)
            }

            Section {
                stashyScrollingSectionHeader(tr("recommendations"), isBeta: true)
                NavigationLink(destination: AITagsSettingsView()) {
                    Label(tr("recommendations"), systemImage: "sparkles")
                }
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.tagSuggestions)
            }

            Section {
                stashyScrollingSectionHeader(AIMotionCopy.name, isBeta: true)
                NavigationLink(destination: StashSyncSettingsView()) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(StashyPlusFeatureCopy.aiMotion)
            }
        } else {
            Section {
                stashyScrollingSectionHeader(tr("included_with_stashy_plus"))
                let features = StashyPlusFeatureCopy.lockedFeatures
                ForEach(features.indices, id: \.self) { index in
                    lockedPlusFeature(features[index])
                        .stashyGroupedBlockRow(index: index, count: features.count)
                }
            }
        }

        stashyPlusPurchaseSection
    }

    private func lockedPlusFeature(_ feature: StashyPlusFeatureCopy.LockedFeature) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                    Text(feature.detail)
                        .font(.footnote)
                }
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundColor(.secondary)
            if feature.isBeta {
                Spacer()
                StashyBetaBadge()
            }
        }
    }

    // MARK: - stashy+ In-App Purchases

    private var sortedProducts: [StashyStoreProduct] {
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
                    stashyScrollingSectionHeader(stashyPlus.isUnlocked ? "stashy+" : tr("action_unlock_stashy_plus"))

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
                                    Text(tr("loading_stashy_plus_options"))
                                        .foregroundColor(.secondary)
                                }
                                .stashyGroupedSettingsRow()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(storeManager.lastProductError ?? "stashy+ products unavailable.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button(tr("action_retry")) {
                                        Task { await storeManager.fetchProducts() }
                                    }
                                }
                                .stashyGroupedSettingsRow()
                            }
                        } else {
                            stashyPlusPurchaseOptionsCard
                            if let missing = storeManager.lastProductError, missing.hasPrefix("Missing from the store offering") {
                                Text(missing)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .stashyGroupedSettingsRow()
                            }
                        }
                    }

                    if !stashyPlus.isUnlocked, storeManager.products.isEmpty || !stashyPlus.shouldOfferPurchases {
                        stashyPlusRestoreCard
                    }

                    if stashyPlus.source == .subscription {
                        stashyPlusSecondaryActionCard(
                            title: tr("action_manage_subscription"),
                            systemImage: "creditcard",
                            showsProgress: false
                        ) {
                            Task { await storeManager.manageSubscriptions() }
                        }
                    }

                    if !stashyPlus.isUnlocked {
                        stashyScrollingSectionFooter(tr("hint_monthly_yearly_or_lifetime_if"))
                    }

                    if stashyPlus.shouldOfferPurchases {
                        stashyPlusSubscriptionLegalDisclosure
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

    @ViewBuilder
    private var stashyPlusSubscriptionLegalDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((offersFreeTrial
                  ? tr("hint_free_trial_is_for_new")
                  : "")
                 + tr("hint_subscriptions_renew_automatically_unless_canceled"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link(tr("terms_of_use_eula"), destination: StashyLegalLinks.termsOfUse)
                Link(tr("privacy_policy"), destination: StashyLegalLinks.privacyPolicy)
            }
            .font(.caption)
            .foregroundColor(appearanceManager.tintColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var legacyAppLifetimeButton: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("grab_lifetime"))
                    .font(.subheadline.weight(.bold))
                Text(tr("included_with_your_app_purchase"))
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
            Text(tr("purchased"))
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.vertical, 6)
    }

    private func stashyPlusRowLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundColor(appearanceManager.tintColor)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder
    private var stashyPlusPurchaseOptionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedProducts.enumerated()), id: \.element.id) { index, product in
                stashyPlusPurchaseButton(for: product)
                if index < sortedProducts.count - 1 {
                    Divider()
                }
            }

            if !stashyPlus.isUnlocked {
                Divider()
                    .padding(.top, 8)
                stashyPlusRestoreButton
            }
        }
        .stashySettingsCardRow()
    }

    @ViewBuilder
    private var stashyPlusRestoreCard: some View {
        VStack(spacing: 0) {
            stashyPlusRestoreButton
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
        .stashySettingsCardRow()
    }

    private var stashyPlusRestoreButton: some View {
        stashyPlusSecondaryButton(
            title: tr("action_restore_purchases"),
            systemImage: "arrow.clockwise",
            showsProgress: storeManager.isRestoringPurchases
        ) {
            Task { await restorePurchases() }
        }
        .disabled(storeManager.isPurchasing || storeManager.isRestoringPurchases)
    }

    private func stashyPlusSecondaryActionCard(
        title: String,
        systemImage: String,
        showsProgress: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            stashyPlusSecondaryButton(
                title: title,
                systemImage: systemImage,
                showsProgress: showsProgress,
                action: action
            )
        }
        .stashySettingsCardRow()
    }

    private func stashyPlusPurchaseButton(for product: StashyStoreProduct) -> some View {
        Button {
            Task { await purchaseStashyPlus(product) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                stashyPlusRowLabel(
                    StashyPlusProduct.displayNames[product.id] ?? product.displayName,
                    systemImage: iconFor(productID: product.id)
                )
                Spacer(minLength: 8)
                if storeManager.purchasingProductID == product.id {
                    ProgressView()
                } else if let trial = freeTrialLength(for: product) {
                    // The trial leads, the price it turns into sits right below — App Review
                    // (3.1.2) wants what is charged after the trial as visible as the trial.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(trial) free")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(appearanceManager.tintColor)
                        Text("then \(product.pricePerPeriod)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                } else {
                    Text(priceLabel(for: product))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing)
    }

    private func stashyPlusSecondaryButton(
        title: String,
        systemImage: String,
        showsProgress: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                stashyPlusRowLabel(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if showsProgress {
                    ProgressView()
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func purchaseStashyPlus(_ product: StashyStoreProduct) async {
        if let error = await storeManager.purchase(product) {
            ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
        } else if stashyPlus.isUnlocked {
            ToastManager.shared.show(tr("stashy_plus_unlocked_thank_you"), icon: "sparkles", style: .success)
        }
    }

    private var statusDetailText: String {
        if stashyPlus.source == .subscription,
           let id = stashyPlus.activeProductID,
           let name = StashyPlusProduct.displayNames[id] {
            if let exp = stashyPlus.subscriptionExpiration {
                let formatted = exp.formatted(date: .abbreviated, time: .omitted)
                if stashyPlus.isInTrial {
                    return "\(name) · free trial until \(formatted)"
                }
                return "\(name) · renews or expires \(formatted)"
            }
            return "\(name) plan"
        }
        return stashyPlus.source.statusDetail
    }

    private func priceLabel(for product: StashyStoreProduct) -> String {
        product.displayPrice
    }

    /// "7 days" when this plan has a free trial and this Apple ID can still take it.
    private func freeTrialLength(for product: StashyStoreProduct) -> String? {
        guard storeManager.trialEligibleIDs.contains(product.id) else { return nil }
        return product.freeTrialLength
    }

    private var offersFreeTrial: Bool {
        storeManager.products.contains { freeTrialLength(for: $0) != nil }
    }

    private var restoreFailureMessage: String {
        if storeManager.isAppTransactionSandbox {
            return tr("hint_this_install_is_still_testflight")
        }
        return tr("hint_no_stashy_plus_subscription_or")
    }

    private func restorePurchases() async {
        let wasUnlocked = stashyPlus.isUnlocked
        await storeManager.restorePurchases()
        if stashyPlus.isUnlocked {
            ToastManager.shared.show(
                wasUnlocked ? tr("purchases_restored") : "stashy+ unlocked",
                icon: "sparkles",
                style: .success
            )
        } else {
            ToastManager.shared.show(
                restoreFailureMessage,
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
                stashyScrollingSectionHeader(tr("links"))
                Link(destination: URL(string: "https://github.com/1letzgo/stashy")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .stashyGroupedBlockRow(index: 0, count: 3)
                Link(destination: URL(string: "https://discord.gg/DMxEFaVzUM")!) {
                    Label(tr("discord"), systemImage: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .stashyGroupedBlockRow(index: 1, count: 3)
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    Label(tr("acknowledgements"), systemImage: "doc.text")
                }
                .stashyGroupedBlockRow(index: 2, count: 3)
            }
            
        }
    }

    private var sortedTipProducts: [StashyStoreProduct] {
        storeManager.tipProducts.sorted {
            (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
        }
    }

    @ViewBuilder
    private var tipSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("tips"))
            if sortedTipProducts.isEmpty {
                if storeManager.isLoadingProducts {
                    HStack {
                        ProgressView()
                        Text(tr("loading_tips"))
                            .foregroundColor(.secondary)
                    }
                    .stashyGroupedSettingsRow()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("tips_unavailable"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(tr("action_retry")) {
                            Task { await storeManager.fetchProducts() }
                        }
                    }
                    .stashyGroupedSettingsRow()
                }
            } else {
                ForEach(Array(sortedTipProducts.enumerated()), id: \.element.id) { index, product in
                    Button {
                        Task { await purchaseTip(product) }
                    } label: {
                        HStack {
                            stashyPlusRowLabel(
                                StashyPlusProduct.displayNames[product.id] ?? product.displayName,
                                systemImage: iconFor(productID: product.id)
                            )
                            Spacer()
                            if storeManager.purchasingProductID == product.id {
                                ProgressView()
                            } else {
                                Text(product.displayPrice)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(storeManager.isPurchasing)
                    .stashyGroupedBlockRow(index: index, count: sortedTipProducts.count)
                }
            }
            stashyScrollingSectionFooter(tr("hint_support_stashy_tips_do_not"))
        }
        .task {
            if storeManager.tipProducts.isEmpty {
                await storeManager.fetchProducts()
            }
        }
    }

    private func purchaseTip(_ product: StashyStoreProduct) async {
        if let error = await storeManager.purchase(product) {
            ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
        } else {
            ToastManager.shared.show(tr("thank_you_for_tip"), icon: "heart.fill", style: .success)
        }
    }
    // MARK: - Interactive Devices
    private var interactiveDevicesSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("device_synchronization"))
            NavigationLink(destination: HandySettingsView()) {
                Label("The Handy", systemImage: "hand.tap")
            }
            .stashyGroupedBlockRow(index: 0, count: 3)
            NavigationLink(destination: IntifaceSettingsView()) {
                Label(tr("intiface"), systemImage: "cable.connector")
            }
            .stashyGroupedBlockRow(index: 1, count: 3)
            NavigationLink(destination: LoveSpouseSettingsView()) {
                Label(tr("love_spouse"), systemImage: "antenna.radiowaves.left.and.right")
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

/// stashy+ store on iOS. Purchases, restore and product loading run through RevenueCat
/// (`StashyRevenueCat`); paid-app grandfathering stays on `AppTransaction`.
@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published var products: [StashyStoreProduct] = []
    @Published var tipProducts: [StashyStoreProduct] = []
    /// Plans whose free trial this Apple ID can still take (see `StashyRevenueCat.trialEligibleIDs`).
    @Published private(set) var trialEligibleIDs: Set<String> = []
    @Published var isLoadingProducts = false
    @Published var lastProductError: String?
    @Published private(set) var purchasingProductID: String?
    @Published var isRestoringPurchases = false
    /// Last seen `AppTransaction.environment`. Used after Restore to explain a
    /// still-sandbox install (TestFlight overlay).
    @Published private(set) var isAppTransactionSandbox = false

    var isPurchasing: Bool { purchasingProductID != nil }

    private var customerInfoListener: Task<Void, Never>?
    private var legacyPaidRetryCount = 0

    private init() {
        StashyRevenueCat.configureIfNeeded()
        customerInfoListener = StashyRevenueCat.listenForCustomerInfo { info in
            await StoreManager.shared.syncUnlockFromStore(customerInfo: info)
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
            let plusIDs = StashyPlusProduct.allIDs
            let tipIDs = StashyPlusProduct.tipIDs
            let loaded = try await StashyRevenueCat.fetchProducts()
            self.products = loaded.filter { plusIDs.contains($0.id) }.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            self.tipProducts = loaded.filter { tipIDs.contains($0.id) }.sorted {
                (StashyPlusProduct.sortOrder[$0.id] ?? 99) < (StashyPlusProduct.sortOrder[$1.id] ?? 99)
            }
            self.trialEligibleIDs = await StashyRevenueCat.trialEligibleIDs(for: self.products)
            let loadedPlus = Set(self.products.map(\.id))
            let missing = plusIDs.subtracting(loadedPlus).sorted()
            if self.products.isEmpty {
                lastProductError = tr("hint_no_stashy_plus_products_returned")
                AppLog.debug("💬 RevenueCat offering has no stashy+ products for \(plusIDs.sorted())")
            } else if !missing.isEmpty {
                lastProductError = tr("hint_missing_from_store_offering_arg", missing.joined(separator: ", "))
                AppLog.debug("💬 RevenueCat loaded \(loadedPlus.sorted()), missing \(missing)")
            } else {
                lastProductError = nil
                AppLog.debug("💬 RevenueCat loaded products: \(loaded.map(\.id))")
            }
        } catch {
            lastProductError = error.localizedDescription
            AppLog.debug("Failed to load RevenueCat offerings: \(error)")
        }
    }

    /// Result used by the Settings UI for toasts.
    @discardableResult
    func purchase(_ product: StashyStoreProduct) async -> String? {
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        let (message, customerInfo) = await StashyRevenueCat.purchase(product)
        if let message { return message }
        if StashyPlusProduct.tipIDs.contains(product.id) {
            UserDefaults.standard.set(true, forKey: LegacySupporterTipPrompt.hasTippedKey)
            return nil
        }
        StashyPlusManager.shared.clearDebugForceLock()
        await syncUnlockFromStore(customerInfo: customerInfo)
        // A trial taken is gone for the whole subscription group.
        trialEligibleIDs = await StashyRevenueCat.trialEligibleIDs(for: products)
        return nil
    }

    /// Refresh entitlements (RevenueCat + StoreKit: subscriptions, lifetime, paid app before 3.0).
    func syncUnlockFromStore(customerInfo: CustomerInfo? = nil) async {
        let snapshot = await StashyRevenueCat.entitlementSnapshot(customerInfo: customerInfo)
        if snapshot.hasTipped {
            UserDefaults.standard.set(true, forKey: LegacySupporterTipPrompt.hasTippedKey)
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
            AppLog.debug("✅ stashy+ entitlement synced (\(StashyPlusManager.shared.source.rawValue))")
        }
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

    func manageSubscriptions() async {
        #if os(macOS)
        // No in-app sheet on macOS; the App Store app manages subscriptions.
        if let url = URL(string: "macappstore://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
        #else
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            AppLog.debug("Manage subscriptions failed: \(error)")
        }
        #endif
    }

    /// Paid-app buyers (original version before 3.0) get Lifetime.
    /// Sandbox / Xcode cannot prove a real App Store paid purchase — Apple reports
    /// `originalAppVersion == "1.0"` there, so we skip grandfathering.
    private enum LegacyPaidAppResult {
        case yes, no, unknown
    }

    private static func isLegacyPaidAppPurchaser() async -> LegacyPaidAppResult {
        do {
            let result = try await AppTransaction.shared
            let appTransaction = try Self.checkVerifiedStatic(result)
            let environment = appTransaction.environment
            let original = appTransaction.originalAppVersion
            let purchased = appTransaction.originalPurchaseDate
            let decision = StashyPlusManager.legacyPaidAppDecision(
                environment: environment,
                originalAppVersion: original,
                originalPurchaseDate: purchased
            )
            await MainActor.run {
                StoreManager.shared.isAppTransactionSandbox =
                    environment == .sandbox || environment == .xcode
            }
            switch decision {
            case .yes:
                AppLog.debug("ℹ️ AppTransaction originalAppVersion=\(original) purchased=\(purchased) environment=\(environment) pre-3.0 paid=true")
                return .yes
            case .no:
                if environment == .sandbox || environment == .xcode {
                    AppLog.debug("ℹ️ Skipping paid-app grandfathering in \(environment) (App Store purchases only; originalAppVersion=\(original))")
                } else {
                    AppLog.debug("ℹ️ AppTransaction originalAppVersion=\(original) purchased=\(purchased) environment=\(environment) pre-3.0 paid=false")
                }
                return .no
            }
        } catch {
            AppLog.debug("AppTransaction check failed: \(error)")
            return .unknown
        }
    }

    private static func checkVerifiedStatic<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
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
                Toggle(tr("action_enable_intiface"), isOn: $buttplugManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader(tr("intiface_server"))
                TextField(tr("server_address"), text: $buttplugManager.serverAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!buttplugManager.isEnabled)
                    .stashyGroupedBlockRow(index: 0, count: serverRowCount)

                HStack {
                    Text(tr("status"))
                    Spacer()
                    Text(buttplugManager.statusMessage)
                        .foregroundColor(buttplugManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedBlockRow(index: 1, count: serverRowCount)

                if buttplugManager.isConnected {
                    Button(tr("action_disconnect"), role: .destructive) {
                        buttplugManager.disconnect()
                    }
                    .stashyGroupedBlockRow(index: 2, count: serverRowCount)
                } else {
                    Button(tr("action_connect")) {
                        buttplugManager.connect()
                    }
                    .disabled(!buttplugManager.isEnabled)
                    .stashyGroupedBlockRow(index: 2, count: serverRowCount)
                }
            }

            if !buttplugManager.devices.isEmpty {
                Section {
                    stashyScrollingSectionHeader(tr("discovered_devices"))
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
                stashyScrollingSectionFooter(tr("hint_stashy_connects_to_intiface_desktop"))
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("intiface"))
    }
}

struct HandySettingsView: View {
    @ObservedObject var handyManager = HandyManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                Toggle(tr("action_enable_handy"), isOn: $handyManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader(tr("device_type"))
                Picker(tr("device"), selection: $handyManager.deviceType) {
                    Text("The Handy").tag("The Handy")
                    Text(tr("oh")).tag("Oh.")
                }
                .pickerStyle(.segmented)
                .disabled(!handyManager.isEnabled)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(tr("hint_handy_uses_hamp_protocol_oh"))
            }

            if handyManager.deviceType == "The Handy" {
                Section {
                    stashyScrollingSectionHeader(tr("ai_motion_controls"))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tr("stroke_length"))
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
                            Text(tr("max_velocity"))
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
                    stashyScrollingSectionHeader(tr("ai_motion_controls"))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tr("max_intensity"))
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
                stashyScrollingSectionHeader(tr("handy_connection"))
                TextField(tr("connection_key"), text: HandyManager.shared.$connectionKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(!handyManager.isEnabled)
                    .stashyGroupedBlockRow(index: 0, count: 4)

                TextField(tr("public_url_override_optional"), text: HandyManager.shared.$publicUrl)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .disabled(!handyManager.isEnabled)
                    .stashyGroupedBlockRow(index: 1, count: 4)

                HStack {
                    Text(tr("status"))
                    Spacer()
                    Text(handyManager.statusMessage)
                        .foregroundColor(handyManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedBlockRow(index: 2, count: 4)

                Button(tr("check_connection")) {
                    handyManager.checkConnection()
                }
                .disabled(!handyManager.isEnabled)
                .stashyGroupedBlockRow(index: 3, count: 4)

                stashyScrollingSectionFooter(tr("hint_stashy_now_automatically_uploads_local"))
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
                Toggle(tr("action_enable_love_spouse"), isOn: $loveSpouseManager.isEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader(tr("connection_status"))
                HStack {
                    Text(tr("bluetooth"))
                    Spacer()
                    Text(loveSpouseManager.statusMessage)
                        .foregroundColor(loveSpouseManager.isConnected ? .green : .secondary)
                }
                .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionFooter(tr("hint_love_spouse_2_4g_toys"))
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("love_spouse"))
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
                    stashyScrollingSectionFooter(tr("hint_unlock_stashy_plus_to_use"))
                }
            }

            Section {
                stashyScrollingSectionHeader(tr("ai_motion_features"))
                Toggle(isOn: syncEnabledBinding) {
                    Label(AIMotionCopy.name, systemImage: "bolt.fill")
                }
                .tint(appearanceManager.tintColor)
                .disabled(!stashyPlus.isUnlocked)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(AIMotionCopy.disclaimer)
            }

            Section {
                stashyScrollingSectionHeader(tr("sensitivity"))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tr("ai_motion_sensitivity"))
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
                stashyScrollingSectionHeader(tr("optical_flow_smoothing"))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tr("smoothing"))
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
        .alert(tr("ai_motion_disclaimer"), isPresented: $showingDisclaimer) {
            Button(tr("action_cancel"), role: .cancel) { }
            Button(tr("accept_and_enable")) {
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

// MARK: - One-time tip prompt for pre-subscription buyers

/// Buyers of the paid app (before 3.0, the same `legacyPaidApp` check that grants them
/// stashy+ Lifetime) see an alert offering a tip, at most every 90 days, until they have
/// tipped once (here, in Settings, or on another device via RevenueCat / iCloud sync).
/// Closing is the filled default; the tips sit above it.
struct LegacySupporterTipPrompt: ViewModifier {
    /// Time the prompt last appeared (seconds since 1970); set when it appears.
    nonisolated static let lastShownKey = "stashy_legacy_supporter_tip_prompt_last_shown"
    /// Set once any tip was bought; the prompt never appears again.
    nonisolated static let hasTippedKey = "stashy_has_tipped"
    nonisolated static let interval: TimeInterval = 90 * 24 * 60 * 60
    /// DEBUG only: `-stashy_debug_supporter_prompt YES` treats this install as a pre-3.0 buyer.
    nonisolated static let debugForceKey = "stashy_debug_supporter_prompt"

    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    /// Something else is on screen (lock, onboarding, another alert): wait.
    var isBlocked: Bool
    @State private var isPresented = false

    private var isEligible: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.debugForceKey) { return !store.tipProducts.isEmpty && Self.isDue() }
        #endif
        return stashyPlus.source == .legacyPaidApp
            && !store.tipProducts.isEmpty
            && Self.isDue()
    }

    nonisolated static func isDue(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: hasTippedKey) else { return false }
        let last = defaults.double(forKey: lastShownKey)
        return last <= 0 || now.timeIntervalSince1970 - last >= interval
    }

    private var trigger: String {
        "\(stashyPlus.source.rawValue)|\(store.tipProducts.count)|\(isBlocked)"
    }

    func body(content: Content) -> some View {
        content
            .task(id: trigger) {
                guard isEligible, !isBlocked, !isPresented else { return }
                // Let the app settle first; no prompt in the user's face at launch.
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, isEligible, !isBlocked else { return }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastShownKey)
                isPresented = true
            }
            .alert(tr("stashy_has_grown_lot"), isPresented: $isPresented) {
                ForEach(store.tipProducts) { product in
                    Button(tr("tip_arg", product.displayPrice)) {
                        Task { await tip(product) }
                    }
                }
                // Preferred action: drawn as the filled, prominent button, so closing is
                // the easiest choice; Return / Esc also close it on macOS.
                Button(tr("empty_thanks"), role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: {
                Text(tr("hint_you_bought_stashy_before_it"))
            }
    }

    private func tip(_ product: StashyStoreProduct) async {
        if let error = await store.purchase(product) {
            guard error != "Purchase cancelled" else { return }
            ToastManager.shared.show(error, icon: "exclamationmark.triangle", style: .error)
        } else {
            ToastManager.shared.show(tr("thank_you_for_tip"), icon: "heart.fill", style: .success)
        }
    }
}

#endif

/// Settings › App Language (beta): English unless the user picks another language (or the
/// device language on a fresh install); the interface switches at once (`LanguageRefreshing`).
private struct AppLanguageRow: View {
    var body: some View {
        HStack {
            Label(tr("language"), systemImage: "globe")
            Spacer()
            AppLanguageMenu()
        }
    }
}

/// The language menu itself; also used in the setup wizard.
struct AppLanguageMenu: View {
    @State private var selection = AppLanguage.stored

    var body: some View {
        Menu {
            languageButton(AppLanguage.systemValue)
            Divider()
            ForEach(AppLanguage.options, id: \.code) { option in
                languageButton(option.code)
            }
        } label: {
            HStack(spacing: 4) {
                Text(AppLanguage.name(for: selection))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func languageButton(_ code: String) -> some View {
        Button {
            guard code != selection else { return }
            selection = code
            AppLanguage.select(code)
        } label: {
            if code == selection {
                Label(AppLanguage.name(for: code), systemImage: "checkmark")
            } else {
                Text(AppLanguage.name(for: code))
            }
        }
    }
}
