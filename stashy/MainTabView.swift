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
    /// Feeds' time bar in the tab bar accessory: the tab bar may shrink on scroll there too.
    @ObservedObject private var feedsScrubber = FeedsScrubberAccessory.shared
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

    /// `-stashyDebugShowLock YES` (DEBUG): shows the passcode screen for layout checks.
    private static var debugShowsLockScreen: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "stashyDebugShowLock")
        #else
        false
        #endif
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
                        .tint(appearanceManager.tintColor)
                }
            }
            .id(coordinator.serverSwitchID)
            .animation(nil, value: coordinator.selectedTab)
            .tint(appearanceManager.tabBarTint)
            .withToasts()
            #if os(tvOS)
            .modifier(TabBarMinimizesOnScroll(enabled: false))
            #else
            // Collapsing the tab bar is decided there: only with something in the accessory slot.
            .modifier(MiniPlayerHost(hidden: coordinator.selectedTab == .reels, selectedTab: coordinator.selectedTab))
            #endif
            .onAppear {
                ServerConfigManager.shared.scrubPlaintextAPIKeysFromDisk()
                checkConfiguration()
                ICloudSettingsSync.shared.start()
                #if !os(tvOS)
                MiniPlayerStore.shared.restoreLastSessionIfNeeded()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuthError401")).receive(on: DispatchQueue.main)) { _ in
                // Settings is where the key gets fixed; a late 401 must not interrupt that.
                guard coordinator.selectedTab != .settings else { return }
                warningType = .authExpired
                showConfigWarning = true
            }
            .onChange(of: coordinator.selectedTab) { oldTab, newTab in
                // TabView does not always call onDisappear on the list we leave.
                CatalogChromeCollapse.shared.reset()
                if newTab != .reels {
                    coordinator.suppressNextFeedsIconRemount = false
                }
                if newTab == .reels, oldTab != .reels {
                    // A scene / gallery / download player on the tab we came from keeps running
                    // otherwise, and its audio played under the feed until the first swipe.
                    NotificationCenter.default.post(name: .stashyPauseBackgroundPlayers, object: nil)
                }
                guard oldTab == .reels, newTab != .reels else { return }
                // Suspend before audio teardown so deferred Reel `play()` races cannot restart audio.
                ReelsPlayerRegistry.suspendPlayback()
                NotificationCenter.default.post(name: Notification.Name("ReelsPauseAllPlayers"), object: nil)
                AudioSessionCoordinator.shared.releaseSoon()
            }
            .onChange(of: stashyPlus.isUnlocked) { _, _ in
                ensureSelectedTabIsVisible()
            }
            .onChange(of: tabManager.visibleTabs) { _, _ in
                ensureSelectedTabIsVisible()
            }

            #if !os(iOS)
            if securityManager.isAppLocked || Self.debugShowsLockScreen {
                PasscodeEntryView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
            #endif
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0), value: securityManager.isAppLocked)
        #if os(iOS)
        // iOS: the passcode screen gets a window of its own above the app's, so open menus,
        // sheets and covers can never show on top of it.
        .onChange(of: securityManager.isAppLocked || Self.debugShowsLockScreen, initial: true) { _, locked in
            LockScreenWindow.shared.update(locked: locked)
        }
        #endif
        .sheet(isPresented: $showOnboarding) {
            ServerSetupWizardView { newConfig in
                ServerConfigManager.shared.addOrUpdateServer(newConfig)
                ServerConfigManager.shared.saveConfig(newConfig)
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .modifier(LegacySupporterTipPrompt(
            isBlocked: securityManager.isAppLocked || showOnboarding || showConfigWarning
        ))
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
            #if os(macOS)
            // macOS has no UINavigationController to pop: deep links into the catalogue
            // (`cataloguePopToken`) remount the stack instead, so no detail stays on top.
            .id("\(coordinator.catalogueTabID)|\(coordinator.cataloguePopToken)")
            #else
            .id(coordinator.catalogueTabID)
            #endif

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
                    #if os(iOS)
                    // Video under the tab bar: its glass and the time bar in its accessory slot
                    // stay dark in Light Mode, or the white time bar vanishes on light glass.
                    .toolbarColorScheme(.dark, for: .tabBar)
                    #endif
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
        case overview = "Overview"
        case oCount = "O-Count"
        case timeline = "Timeline"
        case topLists = "Charts"
        case hotOrNot = "Match"
        case rateMe = "RateMe"
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .oCount: return "calendar"
            case .timeline: return "calendar.day.timeline.left"
            case .topLists: return "list.number"
            case .hotOrNot: return "flame.fill"
            case .rateMe: return "star.fill"
            }
        }
    }
    
    /// Fixed grouping and order. Previously this came from the user's Tools settings, but a
    /// hand-sorted flat list stopped being a good way in once Tools grew — the grid needs stable
    /// categories, so the order is part of the design now rather than a setting.
    static let toolGroups: [(title: String, tools: [ToolsTab])] = [
        // Downloads and the watchlist are not tools any more: the Dashboard row opens them.
        ("Insights", [.overview, .topLists, .oCount, .timeline]),
        ("Discover", [.hotOrNot, .rateMe])
    ]

    private var visibleToolGroups: [(title: String, tools: [ToolsTab])] { Self.toolGroups }

    private var sortedTabs: [ToolsTab] {
        visibleToolGroups.flatMap(\.tools)
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

    /// Like Home: the tool grid is the root and every tool is pushed onto it, so the system's
    /// swipe-back returns to the grid. The row reads Tools › tool menu.
    private var toolPushedBinding: Binding<Bool> {
        Binding(
            get: { !showsLanding },
            set: { pushed in
                if !pushed, !showsLanding { coordinator.toolsSubTab = "" }
            }
        )
    }

    /// The pushed page keeps its tool while it slides away (the grid is already selected then).
    @State private var lastTool: ToolsTab?

    var body: some View {
        ToolsLandingView(groups: visibleToolGroups) { tool in
            coordinator.toolsSubTab = tool.rawValue
        }
        .navigationDestination(isPresented: toolPushedBinding) { toolPage }
        .onChange(of: showsLanding ? nil : effectiveTab, initial: true) { _, tool in
            if let tool { lastTool = tool }
        }
        .onAppear {
            tabManager.repairMissingToolsIfNeeded()
            normalizeToolsSubTab()
        }
        .onChange(of: stashyPlus.isUnlocked) { _, _ in normalizeToolsSubTab() }
        .stashySectionChrome {
            ToolsBreadcrumbRow(tools: sortedTabs, current: nil) { select($0) }
        }
    }

    @ViewBuilder
    private var toolPage: some View {
        if let tool = (showsLanding ? nil : effectiveTab) ?? lastTool {
            toolContent(tool)
                // Scrolling a tool hides the Tools row like in Home (reaches the tool's scroll view).
                .collapsesCatalogChrome()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Pushed pages don't inherit the grid's background.
                .applyAppBackground()
                // The dropdown swaps the tool inside this page, instantly.
                .transaction(value: coordinator.toolsSubTab) { $0.animation = nil }
                .animation(nil, value: coordinator.toolsSubTab)
                // Switching tools clears details pushed above this page.
                .background(CatalogueStackTrim(trigger: coordinator.toolsSubTab, keepsLibraryPage: true))
                .modifier(ToolPageChrome(
                    context: ToolsBreadcrumbContext(tools: sortedTabs, current: tool) { select($0) },
                    toolDrawsRow: Self.toolsWithOwnControls.contains(tool)
                ))
                .hideSystemNavigationBarForCustomChrome()
                .enableSwipeBackWhenNavBarHidden()
        }
    }

    @ViewBuilder
    private func toolContent(_ tool: ToolsTab) -> some View {
        switch tool {
        case .overview:
            ToolsStatisticsView(viewModel: statisticsViewModel)
        case .oCount:
            OCountHeatmapToolsView()
        case .timeline:
            SessionTimelineToolsView()
        case .topLists:
            TopListsToolsContainerView(viewModel: topListsViewModel)
        case .hotOrNot:
            HotOrNotToolsView()
        case .rateMe:
            RateMeToolsView()
        }
    }

    /// Tools that put their own controls (sort / filter menu) at the right of the Tools row:
    /// they draw the row themselves from `toolsBreadcrumb`.
    static let toolsWithOwnControls: Set<ToolsTab> = [.topLists, .rateMe, .timeline, .hotOrNot]

    /// nil is the grid.
    private func select(_ tool: ToolsTab?) {
        coordinator.toolsSubTab = tool?.rawValue ?? ""
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


/// The Tools row, built like Home's breadcrumb. On the grid: Tools (highlighted) › "Tools"
/// dropdown. In a tool: Tools › a native menu named after the open tool.
struct ToolsBreadcrumbRow<Trailing: View>: View {
    let tools: [ToolsView.ToolsTab]
    /// nil on the grid.
    let current: ToolsView.ToolsTab?
    var onSelect: (ToolsView.ToolsTab?) -> Void
    /// The tool's own controls at the right edge (sort / filter menu).
    @ViewBuilder var trailing: () -> Trailing

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: 6) {
            rootButton
            Image(systemName: "chevron.compact.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
                .accessibilityHidden(true)
            toolMenu(current)
            Spacer(minLength: 0)
            if current != nil { trailing() }
        }
        // As on Home: one mask over the row, so every pill fades as one when the chrome hides.
        .mask(Rectangle().padding(.vertical, -24))
        .padding(.bottom, 4)
    }

    private var rootButton: some View {
        let onRoot = current == nil
        return Button {
            guard !onRoot else { return }
            HapticManager.light()
            onSelect(nil)
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundStyle(onRoot ? Color.onAppTint : Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .stashyChromeFill(shape: Circle(), activeColor: onRoot ? appearance.tintColor : nil)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tools")
        .accessibilityAddTraits(onRoot ? .isSelected : [])
    }

    /// On the grid (`current` nil) the pill reads "Tools" in plain glass and lists the
    /// tools as buttons; in a tool it is highlighted and names it.
    private func toolMenu(_ current: ToolsView.ToolsTab?) -> some View {
        Menu {
            if let current {
                Picker("Tool", selection: Binding(get: { current }, set: { onSelect($0) })) {
                    ForEach(tools, id: \.self) { tool in
                        Label(tool.rawValue, systemImage: tool.icon).tag(tool)
                    }
                }
                .pickerStyle(.inline)
            } else {
                ForEach(tools, id: \.self) { tool in
                    Button {
                        onSelect(tool)
                    } label: {
                        Label(tool.rawValue, systemImage: tool.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(current?.rawValue ?? "Tools")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(current == nil ? Color.white.opacity(0.85) : Color.onAppTint)
            .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
            .frame(height: StashyExpandingDock.activeHeight)
            .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: current == nil ? nil : appearance.tintColor)
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .stashyNeutralMenuItems()
        .fixedSize()
        .accessibilityLabel(current.map { "Tool, \($0.rawValue)" } ?? "Tools")
    }
}

extension ToolsBreadcrumbRow where Trailing == EmptyView {
    init(tools: [ToolsView.ToolsTab], current: ToolsView.ToolsTab?, onSelect: @escaping (ToolsView.ToolsTab?) -> Void) {
        self.init(tools: tools, current: current, onSelect: onSelect) { EmptyView() }
    }
}

/// What a tool needs to draw the Tools row itself, with its own controls at the right.
struct ToolsBreadcrumbContext {
    let tools: [ToolsView.ToolsTab]
    let current: ToolsView.ToolsTab
    let onSelect: (ToolsView.ToolsTab?) -> Void
}

private struct ToolsBreadcrumbKey: EnvironmentKey {
    static let defaultValue: ToolsBreadcrumbContext? = nil
}

extension EnvironmentValues {
    /// Set by `ToolsView` for a tool in `toolsWithOwnControls`; nil everywhere else.
    var toolsBreadcrumb: ToolsBreadcrumbContext? {
        get { self[ToolsBreadcrumbKey.self] }
        set { self[ToolsBreadcrumbKey.self] = newValue }
    }
}

/// The page's Tools row: drawn here, or handed to the tool to draw with its own controls.
private struct ToolPageChrome: ViewModifier {
    let context: ToolsBreadcrumbContext
    let toolDrawsRow: Bool

    func body(content: Content) -> some View {
        if toolDrawsRow {
            content.environment(\.toolsBreadcrumb, context)
        } else {
            content.stashySectionChrome {
                ToolsBreadcrumbRow(tools: context.tools, current: context.current, onSelect: context.onSelect)
            }
        }
    }
}

extension View {
    /// Tools row with the tool's controls at the right. Without a context (the tool shown
    /// outside Tools) it draws nothing; it clears the context for everything below.
    @ViewBuilder
    func toolsBreadcrumbChrome<Trailing: View>(
        _ context: ToolsBreadcrumbContext?,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        if let context {
            environment(\.toolsBreadcrumb, nil)
                .stashySectionChrome {
                    ToolsBreadcrumbRow(tools: context.tools, current: context.current, onSelect: context.onSelect, trailing: trailing)
                }
        } else {
            self
        }
    }
}

/// One choice of a tool's section menu (Charts' Scenes / Performers …, RateMe's Scenes / Images).
struct ToolsRowMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let systemImage: String
    var id: Value { value }
}

/// A tool's section switch as a menu in the Tools row (it was a pill row above the content):
/// the current section's icon collapsed, every section with icon and title open.
struct ToolsRowPickerMenu<Value: Hashable>: View {
    let title: String
    let options: [ToolsRowMenuOption<Value>]
    @Binding var selection: Value
    var isDisabled = false

    var body: some View {
        let current = options.first { $0.value == selection }
        Menu {
            Picker(title, selection: Binding(
                get: { selection },
                set: { value in
                    guard value != selection else { return }
                    HapticManager.selection()
                    selection = value
                }
            )) {
                ForEach(options) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option.value)
                }
            }
            .pickerStyle(.inline)
        } label: {
            ToolsRowMenuLabel(systemImage: current?.systemImage ?? "square.grid.2x2")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .stashyNeutralMenuItems()
        .fixedSize()
        .disabled(isDisabled)
        .accessibilityLabel("\(title), \(current?.title ?? "")")
    }
}

/// Plain-glass menu pill for a tool's control in the Tools row, like the catalog sort menu:
/// an icon (and optional second icon) plus the up/down chevron.
struct ToolsRowMenuLabel: View {
    let systemImage: String
    var secondaryImage: String? = nil
    /// Tint dot: the control narrows what is shown.
    var isActive = false
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            if let secondaryImage {
                Image(systemName: secondaryImage)
                    .font(.caption.weight(.bold))
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
        .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
        .frame(height: StashyExpandingDock.activeHeight)
        .stashyChromeFill(shape: Capsule(style: .continuous), activeColor: nil)
        .overlay(alignment: .topTrailing) {
            if isActive {
                Circle()
                    .fill(appearance.tintColor)
                    .frame(width: 9, height: 9)
                    .offset(x: -1, y: 1)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }
}

/// Tools landing: every enabled tool as an icon tile. Tools outgrew a single dropdown, and a
/// grid inside the tab keeps the tab bar and the back gesture intact — unlike a sheet or an
/// overlay, both of which cost exactly that.
private struct ToolsLandingView: View {
    let groups: [(title: String, tools: [ToolsView.ToolsTab])]
    var onSelect: (ToolsView.ToolsTab) -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    /// Two columns like the Tags grid (three on a wide screen).
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: horizontalSizeClass == .regular ? 3 : 2)
    }

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
        .collapsesCatalogChrome()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
    }

    /// Built like `TagCardView`: a grey header block at 2.2:1 carrying the tinted glyph, the name
    /// in bold below it, card fill, corner radius and shadow of the Tags grid.
    private func tile(_ tool: ToolsView.ToolsTab) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.studioHeaderGray
                .aspectRatio(2.2, contentMode: .fit)
                .overlay(
                    Image(systemName: tool.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(appearance.tintColor)
                )
                .clipped()

            HStack(spacing: 8) {
                Text(tool.rawValue)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

struct ToolsServerView: View {
    /// When true, omits navigation chrome for embedding in Settings segments.
    var embedded: Bool = false

    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var runningTask: String? = nil
    /// Gefundene ungenutzte Einträge (Tags, Performer oder Studios), warten auf die Bestätigung.
    @State private var cleanupKind: CleanupKind = .tags
    @State private var cleanupCandidates: [LibraryCleanupCandidate] = []
    @State private var showCleanupConfirmation = false
    /// Server-Job-Queue, alle 2 s aktualisiert, solange die Seite sichtbar ist.
    @State private var jobs: [StashQueuedJob] = []
    @State private var jobsLoaded = false
    @State private var stoppingJobIds: Set<String> = []
    @State private var showAutoTagConfirmation = false
    @State private var showCleanConfirmation = false
    @State private var showCleanGeneratedConfirmation = false

    /// One Generate option on its own, in the order of the web UI's Generate dialog.
    struct GenerateOption: Identifiable {
        let id: String
        let label: String
        let icon: String
        let start: (StashDBViewModel, @escaping (Bool, String) -> Void) -> Void
    }

    private var generateOptions: [GenerateOption] {
        var options: [GenerateOption] = [
            .init(id: "covers", label: "Covers", icon: "photo.fill") { $0.triggerGenerate(covers: true, completion: $1) },
            .init(id: "previews", label: "Video Previews", icon: "play.rectangle.fill") { $0.triggerGenerate(previews: true, completion: $1) },
            // Stash only renders these inside the video preview task (see triggerGenerate).
            .init(id: "imagePreviews", label: "Animated Image Previews", icon: "photo.on.rectangle.angled") { $0.triggerGenerate(imagePreviews: true, completion: $1) },
            .init(id: "sprites", label: "Scrubber Sprites", icon: "square.grid.3x3.fill") { $0.triggerGenerate(sprites: true, completion: $1) },
            .init(id: "markers", label: "Marker Previews", icon: "mappin.and.ellipse") { $0.triggerGenerate(markers: true, completion: $1) },
            .init(id: "markerImagePreviews", label: "Marker Animated Image Previews", icon: "mappin.and.ellipse.circle.fill") { $0.triggerGenerate(markerImagePreviews: true, completion: $1) },
            .init(id: "markerScreenshots", label: "Marker Screenshots", icon: "camera.fill") { $0.triggerGenerate(markerScreenshots: true, completion: $1) },
            .init(id: "transcodes", label: "Transcodes", icon: "film.stack") { $0.triggerGenerate(transcodes: true, completion: $1) },
            .init(id: "phashes", label: "Video Perceptual Hashes", icon: "number.square.fill") { $0.triggerGenerate(phashes: true, completion: $1) },
            .init(id: "heatmaps", label: "Interactive Heatmaps & Speeds", icon: "waveform.path.ecg") { $0.triggerGenerate(interactiveHeatmapsSpeeds: true, completion: $1) },
            .init(id: "clipPreviews", label: "Image Clip Previews", icon: "play.rectangle.on.rectangle.fill") { $0.triggerGenerate(clipPreviews: true, completion: $1) },
            .init(id: "imageThumbnails", label: "Image Thumbnails", icon: "photo.on.rectangle") { $0.triggerGenerate(imageThumbnails: true, completion: $1) },
        ]
        // Image phashes arrived with Stash 0.31; older servers reject the whole job.
        if StashServerCapabilities.supports031 {
            options.append(.init(id: "imagePhashes", label: "Image Perceptual Hashes", icon: "number.circle.fill") { $0.triggerGenerate(imagePhashes: true, completion: $1) })
        }
        return options
    }

    private let tagRepository = TagRepository()
    private let cleanupRepository = LibraryCleanupRepository()

    enum CleanupKind {
        case tags, performers, studios

        var title: String {
            switch self {
            case .tags: return "Remove Unused Tags"
            case .performers: return "Remove Unused Performers"
            case .studios: return "Remove Unused Studios"
            }
        }
        var noun: String {
            switch self {
            case .tags: return "tags"
            case .performers: return "performers"
            case .studios: return "studios"
            }
        }
    }

    private var activeServer: ServerConfig? { configManager.activeConfig }
    
    var body: some View {
        Group {
            if activeServer != nil {
                List {
                    Section {
                        stashyScrollingSectionHeader("Jobs")
                        jobsBlock
                    }

                    // Same tasks and order as the Tasks page of the Stash web UI.
                    Section {
                        stashyScrollingSectionHeader("Library")
                        taskRow(label: "Scan", icon: "arrow.triangle.2.circlepath", taskId: "scan", index: 0, count: 3) {
                            viewModel.triggerLibraryScan { _, message in
                                showResult(title: "Scan", message: message)
                            }
                        }
                        taskRow(label: "Identify", icon: "person.crop.square.filled.and.at.rectangle", taskId: "identify", index: 1, count: 3) {
                            viewModel.triggerIdentify { _, message, _ in
                                showResult(title: "Identify", message: message)
                            }
                        }
                        taskRow(label: "Auto Tag", icon: "tag", taskId: "autotag", index: 2, count: 3, starts: false) {
                            showAutoTagConfirmation = true
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Generate")
                        taskRow(label: "Generate", icon: "wand.and.stars", taskId: "gen_defaults", index: 0, count: generateOptions.count + 1) {
                            runServerTask("Generate", taskId: "gen_defaults", queued: true) { await viewModel.triggerGenerateWithServerDefaults() }
                        }
                        ForEach(Array(generateOptions.enumerated()), id: \.element.id) { index, option in
                            taskRow(label: option.label, icon: option.icon, taskId: "gen_\(option.id)", index: index + 1, count: generateOptions.count + 1) {
                                option.start(viewModel) { _, message in
                                    showResult(title: option.label, message: message)
                                }
                            }
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Maintenance")
                        taskRow(label: "Clean", icon: "trash.slash", taskId: "clean", index: 0, count: 4, starts: false) {
                            showCleanConfirmation = true
                        }
                        taskRow(label: "Clean Generated Files", icon: "folder.badge.minus", taskId: "clean_generated", index: 1, count: 4, starts: false) {
                            showCleanGeneratedConfirmation = true
                        }
                        taskRow(label: "Optimise Database", icon: "cylinder.split.1x2", taskId: "optimise", index: 2, count: 4) {
                            runServerTask("Optimise Database", taskId: "optimise", queued: true) { await viewModel.triggerOptimiseDatabase() }
                        }
                        taskRow(label: "Backup Database", icon: "externaldrive.badge.timemachine", taskId: "backup", index: 3, count: 4) {
                            runServerTask("Backup Database", taskId: "backup", queued: false, note: "The backup is in the server's backup folder.") { await viewModel.triggerBackupDatabase() }
                        }
                    }

                    Section {
                        stashyScrollingSectionHeader("Library Cleanup")
                        taskRow(label: "Remove Unused Tags", icon: "tag.slash", taskId: "tags_unused", index: 0, count: 3) {
                            findUnused(.tags)
                        }
                        taskRow(label: "Remove Unused Performers", icon: "person.slash", taskId: "performers_unused", index: 1, count: 3) {
                            findUnused(.performers)
                        }
                        taskRow(label: "Remove Unused Studios", icon: "building.2.crop.circle", taskId: "studios_unused", index: 2, count: 3) {
                            findUnused(.studios)
                        }
                    }

                    // Admin-Werkzeuge (früher unter Tools), nur mit stashy+.
                    if stashyPlus.isUnlocked {
                        Section {
                            stashyScrollingSectionHeader("stashy+")
                            NavigationLink(destination: FiltersToolsView().stashySettingsDetailChrome("Filters")) {
                                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .stashyGroupedBlockRow(index: 0, count: 3)
                            NavigationLink(destination: TagMergeToolsView().stashySettingsDetailChrome("Merge Tags")) {
                                Label("Merge Tags", systemImage: "arrow.triangle.merge")
                            }
                            .stashyGroupedBlockRow(index: 1, count: 3)
                            NavigationLink(destination: StudioMergeToolsView().stashySettingsDetailChrome("Merge Studios")) {
                                Label("Merge Studios", systemImage: "building.2")
                            }
                            .stashyGroupedBlockRow(index: 2, count: 3)
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
        .alert("Auto Tag the whole library?", isPresented: $showAutoTagConfirmation) {
            Button("Auto Tag") {
                runServerTask("Auto Tag", taskId: "autotag", queued: true) { await viewModel.triggerAutoTag() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Matches performer, studio and tag names against file paths and adds them to scenes, images and galleries. Short names can match by mistake.")
        }
        .alert("Clean the library?", isPresented: $showCleanConfirmation) {
            Button("Dry Run") {
                runServerTask("Clean (Dry Run)", taskId: "clean", queued: true, note: "The server log lists what would be removed.") {
                    await viewModel.triggerClean(dryRun: true)
                }
            }
            Button("Clean", role: .destructive) {
                runServerTask("Clean", taskId: "clean", queued: true) { await viewModel.triggerClean(dryRun: false) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes scenes, images and galleries whose files no longer exist, with their generated files. This cannot be undone. A dry run only writes to the server log.")
        }
        .alert("Clean generated files?", isPresented: $showCleanGeneratedConfirmation) {
            Button("Clean", role: .destructive) {
                runServerTask("Clean Generated Files", taskId: "clean_generated", queued: true) { await viewModel.triggerCleanGenerated() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes covers, previews, sprites, transcodes, marker files and thumbnails that no longer belong to anything in the database.")
        }
        .alert("Remove unused \(cleanupKind.noun)?", isPresented: $showCleanupConfirmation) {
            Button("Delete \(cleanupCandidates.count)", role: .destructive) { deleteUnused() }
            Button("Cancel", role: .cancel) { runningTask = nil }
        } message: {
            Text(cleanupConfirmationMessage)
        }
        .onAppear {
            if activeServer != nil {
                viewModel.testConnection()
            }
        }
        // Job-Queue wie im Web-UI: solange die Seite sichtbar ist, alle 2 s nachfragen.
        .task(id: activeServer?.id) {
            guard activeServer != nil else { return }
            while !Task.isCancelled {
                await refreshJobs()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    
    // MARK: - Jobs

    @ViewBuilder
    private var jobsBlock: some View {
        if jobs.isEmpty {
            HStack {
                Label {
                    Text(jobsLoaded ? "No jobs running" : "Loading jobs…")
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .center)
                }
                Spacer()
            }
            .stashyGroupedBlockRow(index: 0, count: 1)
        } else {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                jobRow(job, index: index, count: jobs.count)
            }
        }
    }

    private func jobRow(_ job: StashQueuedJob, index: Int, count: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            jobStatusIcon(job)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.description ?? "Job \(job.id)")
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if let detail = jobDetailLine(job) {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if job.isRunning, let progress = job.progress, progress >= 0 {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(appearanceManager.tintColor)
                }
            }

            Spacer(minLength: 0)

            if job.isRunning, let progress = job.progress, progress >= 0 {
                Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if job.isActive {
                if stoppingJobIds.contains(job.id) || job.status == "STOPPING" {
                    ProgressView()
                        .padding(.trailing, 4)
                } else {
                    Button {
                        stopJob(job)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel \(job.description ?? "job")")
                }
            }
        }
        .stashyGroupedBlockRow(index: index, count: count)
    }

    @ViewBuilder
    private func jobStatusIcon(_ job: StashQueuedJob) -> some View {
        switch job.status {
        case "RUNNING":
            ProgressView()
        case "READY":
            Image(systemName: "clock")
                .foregroundColor(appearanceManager.tintColor)
        case "FINISHED":
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case "FAILED":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        case "CANCELLED", "STOPPING":
            Image(systemName: "stop.circle")
                .foregroundColor(.secondary)
        default:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }

    private func jobDetailLine(_ job: StashQueuedJob) -> String? {
        if let error = job.error, !error.isEmpty { return error }
        if job.isRunning, let sub = job.subTasks?.first, !sub.isEmpty { return sub }
        switch job.status {
        case "READY": return "Queued"
        case "STOPPING": return "Stopping…"
        case "FINISHED": return "Finished"
        case "CANCELLED": return "Cancelled"
        case "FAILED": return "Failed"
        default: return nil
        }
    }

    private func refreshJobs() async {
        guard let fetched = await viewModel.fetchJobQueue() else { return }
        if fetched != jobs { jobs = fetched }
        jobsLoaded = true
        // Aufgeräumt, sobald der Server den Job nicht mehr führt.
        stoppingJobIds = stoppingJobIds.filter { id in fetched.contains { $0.id == id } }
    }

    private func stopJob(_ job: StashQueuedJob) {
        stoppingJobIds.insert(job.id)
        Task {
            let ok = await viewModel.stopJob(id: job.id)
            if !ok { stoppingJobIds.remove(job.id) }
            await refreshJobs()
        }
    }

    /// Starts a task through `run` and reports what the server answered.
    private func runServerTask(
        _ title: String,
        taskId: String,
        queued: Bool,
        note: String? = nil,
        run: @escaping () async -> StashDBViewModel.ServerTaskResult
    ) {
        runningTask = taskId
        Task {
            let result = await run()
            await refreshJobs()
            let message: String
            if result.ok {
                message = [queued ? "Added to the server's job queue." : "Done.", note]
                    .compactMap { $0 }.joined(separator: " ")
            } else {
                message = result.error ?? "The server did not start the task."
            }
            showResult(title: title, message: message)
        }
    }

    /// `starts: false` for rows that only ask first (their alert starts the task).
    @ViewBuilder
    private func taskRow(label: String, icon: String, taskId: String, index: Int, count: Int, starts: Bool = true, action: @escaping () -> Void) -> some View {
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
                    guard starts else {
                        action()
                        return
                    }
                    runningTask = taskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        action()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        Task { await refreshJobs() }
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
    
    // MARK: - Library cleanup

    private var cleanupConfirmationMessage: String {
        // Ein paar Namen zeigen, damit die Zahl nachvollziehbar ist.
        let preview = cleanupCandidates.prefix(8).map(\.name).joined(separator: ", ")
        let rest = cleanupCandidates.count > 8 ? " and \(cleanupCandidates.count - 8) more" : ""
        return "\(cleanupCandidates.count) \(cleanupKind.noun) are not used anywhere: \(preview)\(rest). Deleting them cannot be undone."
    }

    /// Zählt ein Tag nirgends, ist es ungenutzt. Alle fünf Zähler kommen aus `TagFields`.
    private func isUnused(_ tag: Tag) -> Bool {
        (tag.sceneCount ?? 0) == 0
            && (tag.imageCount ?? 0) == 0
            && (tag.galleryCount ?? 0) == 0
            && (tag.performerCount ?? 0) == 0
            && (tag.sceneMarkerCount ?? 0) == 0
    }

    private func findUnused(_ kind: CleanupKind) {
        cleanupKind = kind
        Task {
            do {
                let unused: [LibraryCleanupCandidate]
                switch kind {
                case .tags:
                    unused = try await tagRepository.fetchEveryTag().filter(isUnused)
                        .map { LibraryCleanupCandidate(id: $0.id, name: $0.name, isUnused: true) }
                case .performers:
                    unused = try await cleanupRepository.fetchEveryPerformer().filter(\.isUnused)
                case .studios:
                    unused = try await cleanupRepository.fetchEveryStudio().filter(\.isUnused)
                }
                await MainActor.run {
                    guard !unused.isEmpty else {
                        showResult(title: kind.title, message: "No unused \(kind.noun) found.")
                        return
                    }
                    cleanupCandidates = unused
                    showCleanupConfirmation = true
                }
            } catch {
                AppLog.error("❌ Scanning \(kind.noun) failed: \(error.localizedDescription)")
                await MainActor.run {
                    showResult(title: kind.title, message: "Could not load the \(kind.noun) list.")
                }
            }
        }
    }

    private func deleteUnused() {
        let kind = cleanupKind
        let ids = cleanupCandidates.map(\.id)
        let count = ids.count
        Task {
            do {
                let ok: Bool
                switch kind {
                case .tags: ok = try await tagRepository.deleteTags(ids: ids)
                case .performers: ok = try await cleanupRepository.deletePerformers(ids: ids)
                case .studios: ok = try await cleanupRepository.deleteStudios(ids: ids)
                }
                await MainActor.run {
                    cleanupCandidates = []
                    // Gelöschte Einträge dürfen in Filter-Pickern nicht weiterleben.
                    FilterPickerOptionsStore.shared.invalidate()
                    showResult(
                        title: kind.title,
                        message: ok ? "\(count) unused \(kind.noun) deleted." : "The server rejected the deletion."
                    )
                }
            } catch {
                AppLog.error("❌ Deleting unused \(kind.noun) failed: \(error.localizedDescription)")
                await MainActor.run {
                    cleanupCandidates = []
                    showResult(title: kind.title, message: "Could not delete the \(kind.noun).")
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

/// Like Music: scrolling down shrinks the tab bar to its selected tab, and the mini player
/// (the bottom accessory) moves into the same row; scrolling up brings both back.
private struct TabBarMinimizesOnScroll: ViewModifier {
    /// Only while the accessory slot holds something (a loaded mini player, Feeds' time bar):
    /// without it, a shrunken tab bar makes room for nothing.
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            content
        }
        #else
        // macOS: tab bar across the top of the window, like iPad — no sidebar.
        content.tabViewStyle(.tabBarOnly)
        #endif
    }
}
#endif

#if !os(tvOS)
/// Puts the mini player above the tab bar and reopens its scene full screen on tap.
private struct MiniPlayerHost: ViewModifier {
    /// Feeds own the whole screen; the bar steps aside there and its video pauses.
    var hidden: Bool
    var selectedTab: AppTab
    @ObservedObject private var store = MiniPlayerStore.shared
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var feedsScrubber = FeedsScrubberAccessory.shared
    @ObservedObject private var imageScrubber = FeedsScrubberAccessory.images

    /// The image fullscreen viewer is open in this tab: like Feeds, it owns the slot.
    private var imageViewerOpen: Bool { imageScrubber.ownerTab == selectedTab }
    /// Feeds or the image viewer: the mini player steps aside and the slot holds a time bar.
    private var timeBarOwnsSlot: Bool { hidden || imageViewerOpen }
    private var activeScrubber: FeedsScrubberAccessory { hidden ? feedsScrubber : imageScrubber }
    @ObservedObject private var security = SecurityManager.shared

    /// The passcode screen is a ZStack overlay in `MainTabView`; a sheet or cover sits above it,
    /// so the full view stayed readable on the lock screen. While locked both step aside and
    /// the store keeps its state, so they come back after unlocking.
    private var nowPlayingPresented: Binding<Bool> {
        Binding(
            get: { store.showsNowPlaying && !security.isAppLocked },
            set: { shown in
                guard !security.isAppLocked else { return }
                store.showsNowPlaying = shown
            }
        )
    }

    private var expandedScenePresented: Binding<Scene?> {
        Binding(
            get: { security.isAppLocked ? nil : store.expandedScene },
            set: { scene in
                guard !security.isAppLocked else { return }
                store.expandedScene = scene
            }
        )
    }

    /// The mini player sits in the tab bar's accessory slot (not floating over a page without one).
    private var showsMiniPlayerInTabBar: Bool {
        store.session != nil && !hidden && store.isEnabled && !store.tabBarHiddenByPage
    }

    func body(content: Content) -> some View {
        content
            .modifier(TabBarMinimizesOnScroll(enabled: timeBarOwnsSlot ? activeScrubber.showsBar : showsMiniPlayerInTabBar))
            .modifier(MiniPlayerAccessory(
                isEnabled: store.session != nil && !timeBarOwnsSlot && store.isEnabled,
                floats: store.tabBarHiddenByPage,
                // Feeds put their time bar in the same slot (not Pics, not GIFs), and so does the
                // image viewer for videos. A tap that hides the chrome takes the whole slot away,
                // or its empty glass would stay.
                showsFeedsTimeBar: timeBarOwnsSlot && activeScrubber.showsBar && activeScrubber.isUIVisible
                    && FeedsScrubberAccessory.isAvailable,
                timeBarSource: activeScrubber
            ))
            .onChange(of: timeBarOwnsSlot, initial: true) { _, owned in
                store.setFeedsActive(owned)
            }
            .onChange(of: selectedTab, initial: true) { _, tab in
                FeedsScrubberAccessory.selectedTab = tab
            }
            // Settings › stashy+ › Miniplayer & Watchlist off: the bar closes (its spot is kept).
            .onChange(of: tabManager.isMiniPlayerEnabled) { _, enabled in
                if !enabled { store.close(forget: false) }
            }
            .sheet(isPresented: nowPlayingPresented) {
                NowPlayingView()
                    #if os(macOS)
                    .frame(minWidth: 640, minHeight: 720)
                    #endif
            }
            #if os(macOS)
            // macOS has no full-screen cover: a large sheet carries the scene page instead.
            .sheet(item: expandedScenePresented) { scene in
                NavigationStack {
                    SceneDetailView(scene: scene, autoPlay: true)
                        .environment(\.stashyPresentedFromMiniPlayer, true)
                }
                .frame(minWidth: 820, minHeight: 640)
            }
            #else
            .fullScreenCover(item: expandedScenePresented) { scene in
                // The page shows Close instead of Back here; leaving hands the video back to the bar.
                NavigationStack {
                    SceneDetailView(scene: scene, autoPlay: true)
                        .environment(\.stashyPresentedFromMiniPlayer, true)
                }
            }
            #endif
    }
}

#if os(iOS)
/// Feeds' time bar in the accessory slot: full above the tab bar, compact beside it once the tab
/// bar has shrunk. The slot draws the glass, so the bar doesn't add its own.
@available(iOS 26.1, *)
private struct FeedsTimeBarAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @ObservedObject var accessory: FeedsScrubberAccessory

    var body: some View {
        if let state = accessory.state {
            FeedsTimeBar(state: state, accessory: accessory, isCompact: placement == .inline)
                .opacity(accessory.isUIVisible ? 1 : 0)
                .allowsHitTesting(accessory.isUIVisible)
                .animation(.easeInOut(duration: 0.2), value: accessory.isUIVisible)
                // The bar draws in white over video; in Light Mode the slot's glass turned light
                // and swallowed it. Video chrome stays dark, as Feeds' own overlays do.
                .colorScheme(.dark)
                .onChange(of: placement == .inline, initial: true) { _, inline in
                    if accessory.isInline != inline { accessory.isInline = inline }
                }
        }
    }
}

@available(iOS 26.1, *)
private struct FeedsTimeBar: View {
    @ObservedObject var state: ScrubberState
    @ObservedObject var accessory: FeedsScrubberAccessory
    var isCompact: Bool

    var body: some View {
        AetherTimeBar(
            currentTime: state.time,
            duration: state.duration,
            isScrubbing: state.seeking,
            previewImage: state.previewImage,
            previewPlaceholderURL: state.previewPlaceholderURL,
            markerSeconds: state.markerSeconds,
            isCompact: isCompact,
            showsGlass: false,
            playPause: AetherTimeBarPlayPause(isPlaying: accessory.isPlaying) { accessory.togglePlay?() },
            mute: AetherTimeBarMute(isMuted: accessory.isMuted) { accessory.toggleMute?() },
            onScrubChanged: { seconds in
                state.seeking = true
                state.time = seconds
                state.seekTarget = seconds
            },
            onScrubEnded: { seconds in
                state.time = seconds
                state.seekTarget = seconds
                state.seeking = false
            }
        )
    }
}

/// The bar in the accessory slot: full above the tab bar, compact (cover, title, play) once the
/// tab bar has shrunk and the accessory sits inline beside it.
@available(iOS 26.1, *)
private struct MiniPlayerAccessoryBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayerBar(compact: placement == .inline)
    }
}
#endif

/// iOS 26's tab bar accessory slot (the Music-style bar). Older systems, and pages that hide
/// the tab bar (and with it the accessory), get a floating bar instead.
private struct MiniPlayerAccessory: ViewModifier {
    var isEnabled: Bool
    /// The tab bar is hidden by the current page: float at the bottom edge.
    var floats: Bool
    /// Feeds: the slot holds the feed's time bar instead of the mini player.
    var showsFeedsTimeBar: Bool = false
    /// Which page's bar the slot shows: Feeds or the image viewer.
    var timeBarSource: FeedsScrubberAccessory = .shared

    func body(content: Content) -> some View {
        #if os(macOS)
        // macOS: the tab bar sits at the top, so the bar floats at the window's bottom edge.
        content.overlay(alignment: .bottom) {
            floatingBar(visible: isEnabled, bottomPadding: 12)
                .frame(maxWidth: 560)
        }
        #else
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: (isEnabled && !floats) || showsFeedsTimeBar) {
                    if showsFeedsTimeBar {
                        FeedsTimeBarAccessory(accessory: timeBarSource)
                    } else {
                        MiniPlayerAccessoryBar()
                    }
                }
                .overlay(alignment: .bottom) {
                    floatingBar(visible: isEnabled && floats, bottomPadding: 8)
                }
        } else {
            content.overlay(alignment: .bottom) {
                floatingBar(visible: isEnabled, bottomPadding: floats ? 8 : 64)
            }
        }
        #endif
    }

    @ViewBuilder
    private func floatingBar(visible: Bool, bottomPadding: CGFloat) -> some View {
        if visible {
            MiniPlayerBar()
                .frame(height: 56)
                // Same glass as the floating action bar and the chrome pills.
                .stashyGlass(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .floatingShadow()
                .padding(.horizontal, 12)
                .padding(.bottom, bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
#endif


#if os(iOS)
/// Same light / dark choice as the app window (Settings › Appearance); a window of its own
/// does not inherit it.
private struct LockScreenWindowRoot: View {
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        PasscodeEntryView()
            .preferredColorScheme(appearance.preferredTheme.colorScheme)
    }
}

/// The passcode screen in its own window at alert level. As an overlay inside the app window
/// it lost to anything UIKit puts above the content: an open menu (sort, Home views) or a
/// sheet stayed readable on the lock screen after switching apps.
@MainActor
final class LockScreenWindow {
    static let shared = LockScreenWindow()
    private var windows: [ObjectIdentifier: UIWindow] = [:]

    func update(locked: Bool) {
        if locked {
            show()
            // Scenes may still be connecting on a cold start.
            DispatchQueue.main.async { if SecurityManager.shared.isAppLocked { self.show() } }
        } else {
            hide()
        }
    }

    private func show() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where windows[ObjectIdentifier(scene)] == nil {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: LockScreenWindowRoot())
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            windows[ObjectIdentifier(scene)] = window
        }
    }

    private func hide() {
        let leaving = windows.values
        windows.removeAll()
        for window in leaving {
            UIView.animate(withDuration: 0.25, animations: {
                window.alpha = 0
                window.transform = CGAffineTransform(translationX: 0, y: window.bounds.height * 0.08)
            }, completion: { _ in
                window.isHidden = true
                window.rootViewController = nil
            })
        }
    }
}
#endif
