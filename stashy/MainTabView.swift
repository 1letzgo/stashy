//
//  MainTabView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import AVFoundation

struct MainTabView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var securityManager = SecurityManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    /// Feeds (`ReelsView`): bleibt über Tab-Wechsel erhalten; Szenen-/Marker-Scroll-Position in `ReelsSessionRAM`.
    @StateObject private var reelsFeedViewModel = StashDBViewModel()
    @State private var hasValidConfig = false
    @State private var showConfigWarning = false
    @State private var showOnboarding = false
    @State private var warningType: ConfigWarningType = .none

    enum ConfigWarningType {
        case none
        case noServer
        case invalidConfig
        case authExpired
    }

    var body: some View {
        ZStack {
            Color.appBackground(for: appearanceManager.currentTheme)
                .ignoresSafeArea()
            TabView(selection: Binding(
                get: {
                    let selected = coordinator.selectedTab
                    if selected == .search || tabManager.visibleTabs.contains(selected) {
                        return selected
                    }
                    return tabManager.visibleTabs.first ?? .catalogue
                },
                set: { newValue in
                    if newValue == coordinator.selectedTab {
                        if newValue == .catalogue {
                            let now = Date()
                            if let lastTap = coordinator.lastHomeTapTime, now.timeIntervalSince(lastTap) < 0.5 {
                                // Double tap detected -> Go to Dashboard
                                coordinator.catalogueSubTab = CatalogsView.CatalogsTab.dashboard.rawValue
                                coordinator.lastHomeTapTime = nil
                            } else {
                                // Single tap -> Just record time and let system pop/scroll
                                coordinator.lastHomeTapTime = now
                            }
                        } else if newValue == .reels {
                            // Re-tap Feeds only: pop detail + rebuild UI. Do not remount when
                            // merely entering the tab — that aborted in-flight Clips fetches.
                            // TabView also echoes programmatic `selectedTab = .reels` as a re-tap;
                            // swallowing that keeps a pending channel / performer deep link intact.
                            if coordinator.suppressNextFeedsIconRemount {
                                coordinator.suppressNextFeedsIconRemount = false
                            } else {
                                remountFeedsTab()
                            }
                        }
                    } else {
                        coordinator.selectedTab = newValue
                        coordinator.lastHomeTapTime = nil
                    }
                }
            )) {
                ForEach(tabManager.visibleTabs) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        view(for: tab)
                            .tint(appearanceManager.tintColor)
                    }
                }

                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    UniversalSearchView()
                        .applyAppBackground()
                }
            }
            .id(coordinator.serverSwitchID)
            .animation(nil, value: coordinator.selectedTab)
            .tint(appearanceManager.tintColor)
            .withToasts()
            .modifier(TabBarNeverMinimizes())
            .onAppear {
                ServerConfigManager.shared.scrubPlaintextAPIKeysFromDisk()
                checkConfiguration()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuthError401"))) { _ in
                coordinator.selectedTab = .catalogue
                warningType = .authExpired
                showConfigWarning = true
            }
            .onChange(of: coordinator.selectedTab) { oldTab, newTab in
                if newTab != .reels {
                    coordinator.suppressNextFeedsIconRemount = false
                }
                guard oldTab == .reels, newTab != .reels else { return }
                // Suspend before audio teardown so deferred Reel `play()` races cannot restart audio.
                ReelsPlayerRegistry.suspendPlayback()
                NotificationCenter.default.post(name: Notification.Name("ReelsPauseAllPlayers"), object: nil)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            .onChange(of: stashyPlus.isUnlocked) { _, _ in
                ensureSelectedTabIsVisible()
            }
            .onChange(of: tabManager.visibleTabs) { _, _ in
                ensureSelectedTabIsVisible()
            }

            if securityManager.isAppLocked {
                PasscodeEntryView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0), value: securityManager.isAppLocked)
        .sheet(isPresented: $showOnboarding) {
            ServerSetupWizardView { newConfig in
                ServerConfigManager.shared.addOrUpdateServer(newConfig)
                ServerConfigManager.shared.saveConfig(newConfig)
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .alert(isPresented: $showConfigWarning) {
            switch warningType {
            case .noServer:
                return Alert(
                    title: Text("Welcome to stashy"),
                    message: Text("Please configure your Stash server to get started."),
                    dismissButton: .default(Text("Go to Settings")) {
                        coordinator.selectedTab = .settings
                    }
                )
            case .invalidConfig:
                return Alert(
                    title: Text("Incomplete Setup"),
                    message: Text("Your server configuration is missing some details."),
                    dismissButton: .default(Text("Check Settings")) {
                        coordinator.selectedTab = .settings
                    }
                )
            case .authExpired:
                return Alert(
                    title: Text("Authentication Required"),
                    message: Text("Your API key is invalid or expired. Please check your server configuration."),
                    dismissButton: .default(Text("Update API Key")) {
                        coordinator.selectedTab = .settings
                    }
                )
            default:
                return Alert(title: Text("Error"))
            }
        }
        .preferredColorScheme(appearanceManager.preferredTheme.colorScheme)
    }

    private func checkConfiguration() {
        if let config = ServerConfigManager.shared.loadConfig() {
            hasValidConfig = config.hasValidConfig
            if !hasValidConfig {
                warningType = .invalidConfig
                showConfigWarning = true
            }
        } else if ServerConfigManager.shared.savedServers.isEmpty {
            AppLog.error("❌ NO SERVER CONFIGURATION FOUND - SHOWING WIZARD")
            hasValidConfig = false
            showOnboarding = true
        } else {
            hasValidConfig = false
            coordinator.selectedTab = .settings
        }
    }

    /// Clean Feeds rebuild: session save → player teardown → new `NavigationStack` identity.
    /// Keeps `reelsFeedViewModel` warm; sub-mode / position come from `ReelsSessionRAM`.
    private func remountFeedsTab() {
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        ReelsPlayerRegistry.pauseAll()
        // Clear any prior tab-leave suspend so the remounted Feeds instance can autoplay.
        ReelsPlayerRegistry.resumePlayback()
        // Icon re-tap must not re-apply a previous Performer/Tag deep-link.
        coordinator.clearReelsDeepLink()
        coordinator.reelsTabID = UUID()
    }

    /// Tools ↔ stashy+ swap must not leave TabView on a hidden tab.
    private func ensureSelectedTabIsVisible() {
        let selected = coordinator.selectedTab
        guard selected != .search else { return }
        guard !tabManager.visibleTabs.contains(selected) else { return }
        if stashyPlus.isUnlocked {
            coordinator.selectedTab = tabManager.visibleTabs.contains(.tools) ? .tools : .settings
        } else if tabManager.visibleTabs.contains(.stashyPlus) {
            coordinator.selectedTab = .stashyPlus
        } else {
            coordinator.selectedTab = tabManager.visibleTabs.first ?? .catalogue
        }
    }
}

extension MainTabView {
    @ViewBuilder
    func view(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            NavigationStack {
                HomeView()
                    .applyAppBackground()
            }
            .id(coordinator.homeTabID)

        case .performers:
            NavigationStack {
                PerformersView()
                    .applyAppBackground()
            }
            .id(coordinator.performersTabID)

        case .catalogue:
            NavigationStack {
                CatalogsView()
                    .applyAppBackground()
            }
            .id(coordinator.catalogueTabID)

        case .downloads:
            NavigationStack {
                DownloadsView()
                    .applyAppBackground()
            }
            .id(coordinator.downloadsTabID)
            
        case .tools:
            NavigationStack {
                ToolsView()
                    .applyAppBackground()
            }
            .id(coordinator.toolsTabID)

        case .stashyPlus:
            NavigationStack {
                SettingsView(stashyPlusOnly: true)
                    .applyAppBackground()
            }
            .id("stashyPlusTab")

        case .reels:
            NavigationStack {
                ReelsView(viewModel: reelsFeedViewModel, deepLink: coordinator.reelsDeepLink)
            }
            .id(coordinator.reelsTabID)

        case .settings:
            NavigationStack {
                SettingsView()
                    .applyAppBackground()
            }
            .id(coordinator.settingsTabID)
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Tools (Container Tab)

struct ToolsView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    /// Shared across Tools sub-tabs so Overview / Charts stay warm when switching Downloads / Match.
    @StateObject private var statisticsViewModel = StashDBViewModel()
    @StateObject private var topListsViewModel = TopListsViewModel()

    enum ToolsTab: String, CaseIterable {
        case downloads = "Downloads"
        case overview = "Overview"
        case oCount = "O-Count"
        case timeline = "Timeline"
        case topLists = "Charts"
        case filters = "Filters"
        case mergeTags = "Merge Tags"
        case hotOrNot = "Match"
        case rateMe = "RateMe"
        
        var icon: String {
            switch self {
            case .downloads: return "square.and.arrow.down"
            case .overview: return "chart.bar.fill"
            case .oCount: return "calendar"
            case .timeline: return "calendar.day.timeline.left"
            case .topLists: return "list.number"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .mergeTags: return "arrow.triangle.merge"
            case .hotOrNot: return "flame.fill"
            case .rateMe: return "star.fill"
            }
        }
    }
    
    /// Fixed grouping and order. Previously this came from the user's Tools settings, but a
    /// hand-sorted flat list stopped being a good way in once Tools grew — the grid needs stable
    /// categories, so the order is part of the design now rather than a setting.
    static let toolGroups: [(title: String, tools: [ToolsTab])] = [
        ("Library", [.downloads, .filters, .mergeTags]),
        ("Insights", [.overview, .topLists, .oCount, .timeline]),
        ("Discover", [.hotOrNot, .rateMe])
    ]

    private var sortedTabs: [ToolsTab] {
        Self.toolGroups.flatMap(\.tools)
    }
    
    /// Empty (or unknown) sub-tab means the landing grid, not "first tool". Tools grew past the
    /// point where a dropdown alone is a good way in.
    private var showsLanding: Bool {
        ToolsTab(rawValue: coordinator.toolsSubTab).map { !sortedTabs.contains($0) } ?? true
    }

    private var effectiveTab: ToolsTab {
        if let current = ToolsTab(rawValue: coordinator.toolsSubTab), sortedTabs.contains(current) {
            return current
        }
        return sortedTabs.first ?? .overview
    }

    private var selectedTabBinding: Binding<ToolsTab> {
        Binding(
            get: { effectiveTab },
            set: { coordinator.toolsSubTab = $0.rawValue }
        )
    }
    
    var body: some View {
        Group {
            if showsLanding {
                ToolsLandingView(groups: Self.toolGroups) { tool in
                    coordinator.toolsSubTab = tool.rawValue
                }
            } else {
            switch effectiveTab {
            case .downloads:
                DownloadsView()
            case .overview:
                ToolsStatisticsView(viewModel: statisticsViewModel)
            case .oCount:
                OCountHeatmapToolsView()
            case .timeline:
                SessionTimelineToolsView()
            case .topLists:
                TopListsToolsContainerView(viewModel: topListsViewModel)
            case .filters:
                FiltersToolsView()
            case .mergeTags:
                TagMergeToolsView()
            case .hotOrNot:
                HotOrNotToolsView()
            case .rateMe:
                RateMeToolsView()
            }
            }
        }
        .onAppear {
            tabManager.repairMissingToolsIfNeeded()
            normalizeToolsSubTab()
        }
        .onChange(of: stashyPlus.isUnlocked) { _, _ in normalizeToolsSubTab() }
        .popNavigationToRootOnChange(effectiveTab.rawValue)
        .stashySectionChrome {
            toolsCategoryRow
        }
    }

    /// Only the dropdown — its pinned "Tools" entry is the way back to the grid. A separate button
    /// beside it repeated the same icon in the same bar.
    private var toolsCategoryRow: some View {
        toolsDropdown
    }

    private static let allToolsMenuID = "__all_tools__"

    private var toolsDropdown: some View {
        StashyTopNavNameDropdownRow(
            title: "Tools",
            items: [
                StashyNavMenuItem(
                    id: Self.allToolsMenuID,
                    title: "Tools",
                    systemImage: "square.grid.2x2"
                )
            ] + sortedTabs.map {
                StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
            },
            selectionID: showsLanding ? Self.allToolsMenuID : effectiveTab.rawValue,
            titleColor: .white,
            menuAccessibilityLabel: "Tool",
            menuAccessibilityHint: "Chooses which tool to show",
            // Der Weg zurück zur Übersicht darf nicht wegscrollen.
            pinnedItemID: Self.allToolsMenuID
        ) { id in
            if id == Self.allToolsMenuID {
                coordinator.toolsSubTab = ""
            } else if let tab = ToolsTab(rawValue: id) {
                selectedTabBinding.wrappedValue = tab
            }
        }
    }

    private func normalizeToolsSubTab() {
        if coordinator.toolsSubTab == "Hot or Not" || coordinator.toolsSubTab == "Server" {
            coordinator.toolsSubTab = (sortedTabs.first ?? .overview).rawValue
        } else if coordinator.toolsSubTab == "Statistics" {
            coordinator.toolsSubTab = ToolsTab.overview.rawValue
        } else if coordinator.toolsSubTab == "Top 10" || coordinator.toolsSubTab == "Top" {
            coordinator.toolsSubTab = ToolsTab.topLists.rawValue
        } else if ToolsTab(rawValue: coordinator.toolsSubTab) == nil
                    || !sortedTabs.contains(where: { $0.rawValue == coordinator.toolsSubTab }) {
            // Land on the grid rather than dropping the user into an arbitrary tool.
            coordinator.toolsSubTab = ""
        }
    }
}


/// Tools landing: every enabled tool as an icon tile. Tools outgrew a single dropdown, and a
/// grid inside the tab keeps the tab bar and the back gesture intact — unlike a sheet or an
/// overlay, both of which cost exactly that.
private struct ToolsLandingView: View {
    let groups: [(title: String, tools: [ToolsView.ToolsTab])]
    var onSelect: (ToolsView.ToolsTab) -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        // Same as the dashboard's row headings.
                        Text(group.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.tools, id: \.rawValue) { tool in
                                Button {
                                    onSelect(tool)
                                } label: {
                                    tile(tool)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
            .padding(.top, DesignTokens.Tools.menuTopPadding)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
    }

    /// Built like `HomeChannelCardView` on the dashboard: the tinted glyph sits slightly above
    /// centre on the card surface, the title centred at the bottom in 12pt bold. Same corner radius, and
    /// no shadow — the channel cards carry none either.
    private func tile(_ tool: ToolsView.ToolsTab) -> some View {
        let height: CGFloat = 104

        return ZStack(alignment: .bottom) {
            Color.secondaryAppBackground

            Image(systemName: tool.icon)
                .font(.system(size: height * 0.34, weight: .semibold))
                .foregroundColor(appearance.tintColor)
                .offset(y: -height * 0.06)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(tool.rawValue)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(8)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }
}

struct ToolsServerView: View {
    /// When true, omits navigation chrome for embedding in Settings segments.
    var embedded: Bool = false

    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var runningTask: String? = nil
    /// Gefundene ungenutzte Tags, warten auf die Bestätigung.
    @State private var unusedTags: [Tag] = []
    @State private var showUnusedTagsConfirmation = false

    private let tagRepository = TagRepository()

    private var activeServer: ServerConfig? { configManager.activeConfig }
    
    var body: some View {
        Group {
            if activeServer != nil {
                List {
                    Section {
                        stashyScrollingSectionHeader("Scan & Identify")
                        taskRow(label: "Scan Library", icon: "arrow.triangle.2.circlepath", taskId: "scan", index: 0, count: 2) {
                            viewModel.triggerLibraryScan { _, message in
                                showResult(title: "Scan Library", message: message)
                            }
                        }
                        taskRow(label: "Identify", icon: "person.crop.square.filled.and.at.rectangle", taskId: "identify", index: 1, count: 2) {
                            viewModel.triggerIdentify { _, message, _ in
                                showResult(title: "Identify", message: message)
                            }
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Generate")
                        taskRow(label: "Scene covers", icon: "photo.fill", taskId: "gen_covers", index: 0, count: 13) {
                            viewModel.triggerGenerate(covers: true) { _, message in
                                showResult(title: "Scene covers", message: message)
                            }
                        }
                        taskRow(label: "Previews", icon: "play.rectangle.fill", taskId: "gen_previews", index: 1, count: 13) {
                            viewModel.triggerGenerate(previews: true) { _, message in
                                showResult(title: "Previews", message: message)
                            }
                        }
                        taskRow(label: "Animated image previews", icon: "photo.on.rectangle.angled", taskId: "gen_imagePreviews", index: 2, count: 13) {
                            viewModel.triggerGenerate(imagePreviews: true) { _, message in
                                showResult(title: "Animated image previews", message: message)
                            }
                        }
                        taskRow(label: "Scene scrubber sprites", icon: "square.grid.3x3.fill", taskId: "gen_sprites", index: 3, count: 13) {
                            viewModel.triggerGenerate(sprites: true) { _, message in
                                showResult(title: "Scene scrubber sprites", message: message)
                            }
                        }
                        taskRow(label: "Marker previews", icon: "mappin.and.ellipse", taskId: "gen_markers", index: 4, count: 13) {
                            viewModel.triggerGenerate(markers: true) { _, message in
                                showResult(title: "Marker previews", message: message)
                            }
                        }
                        taskRow(label: "Marker animated image previews", icon: "mappin.and.ellipse.circle.fill", taskId: "gen_markerImagePreviews", index: 5, count: 13) {
                            viewModel.triggerGenerate(markerImagePreviews: true) { _, message in
                                showResult(title: "Marker animated image previews", message: message)
                            }
                        }
                        taskRow(label: "Marker screenshots", icon: "camera.fill", taskId: "gen_markerScreenshots", index: 6, count: 13) {
                            viewModel.triggerGenerate(markerScreenshots: true) { _, message in
                                showResult(title: "Marker screenshots", message: message)
                            }
                        }
                        taskRow(label: "Transcodes", icon: "film.stack", taskId: "gen_transcodes", index: 7, count: 13) {
                            viewModel.triggerGenerate(transcodes: true) { _, message in
                                showResult(title: "Transcodes", message: message)
                            }
                        }
                        taskRow(label: "Video perceptual hashes", icon: "number.square.fill", taskId: "gen_phashes", index: 8, count: 13) {
                            viewModel.triggerGenerate(phashes: true) { _, message in
                                showResult(title: "Video perceptual hashes", message: message)
                            }
                        }
                        taskRow(label: "Generate heatmaps and speeds for interactive scenes", icon: "waveform.path.ecg", taskId: "gen_heatmaps", index: 9, count: 13) {
                            viewModel.triggerGenerate(interactiveHeatmapsSpeeds: true) { _, message in
                                showResult(title: "Generate heatmaps and speeds", message: message)
                            }
                        }
                        taskRow(label: "Image clip previews", icon: "play.rectangle.on.rectangle.fill", taskId: "gen_clipPreviews", index: 10, count: 13) {
                            viewModel.triggerGenerate(clipPreviews: true) { _, message in
                                showResult(title: "Image clip previews", message: message)
                            }
                        }
                        taskRow(label: "Image thumbnails", icon: "photo.on.rectangle", taskId: "gen_imageThumbnails", index: 11, count: 13) {
                            viewModel.triggerGenerate(imageThumbnails: true) { _, message in
                                showResult(title: "Image thumbnails", message: message)
                            }
                        }
                        taskRow(label: "Image perceptual hashes", icon: "number.circle.fill", taskId: "gen_imagePhashes", index: 12, count: 13) {
                            viewModel.triggerGenerate(imagePhashes: true) { _, message in
                                showResult(title: "Image perceptual hashes", message: message)
                            }
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Library Cleanup")
                        taskRow(label: "Remove Unused Tags", icon: "tag.slash", taskId: "tags_unused", index: 0, count: 1) {
                            findUnusedTags()
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Cache")
                        taskRow(label: "Clear Image Cache", icon: "internaldrive", taskId: "cache_clear", index: 0, count: 1) {
                            ImageCache.shared.clearCurrentServerCache()
                            showResult(title: "Cache Cleared", message: "Images will be reloaded from the server.")
                        }
                    }
                }
                .stashySettingsList()
                .tint(appearanceManager.tintColor)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "server.rack")
                        .font(.system(size: 64))
                        .foregroundColor(appearanceManager.tintColor)
                    Text("No active server")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(embedded
                          ? "Select a server under Main first."
                          : "Select a server first to use server tasks.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modifier(ToolsServerChromeModifier(embedded: embedded))
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Remove unused tags?", isPresented: $showUnusedTagsConfirmation) {
            Button("Delete \(unusedTags.count)", role: .destructive) { deleteUnusedTags() }
            Button("Cancel", role: .cancel) { runningTask = nil }
        } message: {
            Text(unusedTagsConfirmationMessage)
        }
        .onAppear {
            if activeServer != nil {
                viewModel.testConnection()
            }
        }
    }
    
    @ViewBuilder
    private func taskRow(label: String, icon: String, taskId: String, index: Int, count: Int, action: @escaping () -> Void) -> some View {
        HStack {
            Label {
                Text(label)
                    .foregroundColor(.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(appearanceManager.tintColor)
                    .frame(width: 24, alignment: .center)
            }
            Spacer()
            if runningTask == taskId {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                Button(action: {
                    runningTask = taskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        action()
                    }
                }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(runningTask != nil)
            }
        }
        .stashyGroupedBlockRow(index: index, count: count)
    }
    
    // MARK: - Unused tags

    private var unusedTagsConfirmationMessage: String {
        // Ein paar Namen zeigen, damit die Zahl nachvollziehbar ist.
        let preview = unusedTags.prefix(8).map(\.name).joined(separator: ", ")
        let rest = unusedTags.count > 8 ? " and \(unusedTags.count - 8) more" : ""
        return "\(unusedTags.count) tags are not used anywhere: \(preview)\(rest). Deleting them cannot be undone."
    }

    /// Zählt ein Tag nirgends, ist es ungenutzt. Alle fünf Zähler kommen aus `TagFields`.
    private func isUnused(_ tag: Tag) -> Bool {
        (tag.sceneCount ?? 0) == 0
            && (tag.imageCount ?? 0) == 0
            && (tag.galleryCount ?? 0) == 0
            && (tag.performerCount ?? 0) == 0
            && (tag.sceneMarkerCount ?? 0) == 0
    }

    private func findUnusedTags() {
        Task {
            do {
                let all = try await tagRepository.fetchEveryTag()
                let unused = all.filter(isUnused)
                await MainActor.run {
                    guard !unused.isEmpty else {
                        showResult(title: "Remove Unused Tags", message: "No unused tags found.")
                        return
                    }
                    unusedTags = unused
                    showUnusedTagsConfirmation = true
                }
            } catch {
                AppLog.error("❌ Scanning tags failed: \(error.localizedDescription)")
                await MainActor.run {
                    showResult(title: "Remove Unused Tags", message: "Could not load the tag list.")
                }
            }
        }
    }

    private func deleteUnusedTags() {
        let ids = unusedTags.map(\.id)
        let count = ids.count
        Task {
            do {
                let ok = try await tagRepository.deleteTags(ids: ids)
                await MainActor.run {
                    unusedTags = []
                    // Gelöschte Tags dürfen in Filter-Pickern nicht weiterleben.
                    FilterPickerOptionsStore.shared.invalidate()
                    showResult(
                        title: "Remove Unused Tags",
                        message: ok ? "\(count) unused tags deleted." : "The server rejected the deletion."
                    )
                }
            } catch {
                AppLog.error("❌ Deleting unused tags failed: \(error.localizedDescription)")
                await MainActor.run {
                    unusedTags = []
                    showResult(title: "Remove Unused Tags", message: "Could not delete the tags.")
                }
            }
        }
    }

    private func showResult(title: String, message: String) {
        DispatchQueue.main.async {
            runningTask = nil
            alertTitle = title
            alertMessage = message
            showAlert = true
        }
    }
}

private struct ToolsServerChromeModifier: ViewModifier {
    let embedded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .applyAppBackground()
        }
    }
}

private struct ToolsStatisticsView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Group {
            if configManager.activeConfig != nil {
                ServerStatisticsView(viewModel: viewModel)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 64))
                        .foregroundColor(appearanceManager.tintColor)
                    Text("No active server")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Select a server in Settings to view statistics.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    MainTabView()
}

/// The tab bar must stay put while scrolling. iOS 26 would otherwise be free to collapse it.
private struct TabBarNeverMinimizes: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}
#endif
