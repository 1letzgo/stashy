//
//  NavigationCoordinator.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS) && !os(watchOS)
import SwiftUI
import Combine

// MARK: - Navigation Coordinator
// AppTab, TabConfig, DetailViewConfig and TabManager are defined in TabManager.swift

class NavigationCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .studios
    var performerToOpen: Performer?
    @Published var studioToOpen: Studio?
    
    // Reels Selection
    @Published var reelsPerformer: ScenePerformer?
    @Published var reelsTags: [Tag] = []
    @Published var reelsStudio: SceneStudio?
    @Published var reelsTargetMode: String? = nil
    @Published var reelsNavigationToken = UUID()
    /// Snapshot captured by the remounted Feeds instance (avoids race where a dying
    /// ReelsView clears performer/tags before the new instance can read them).
    @Published private(set) var reelsDeepLink = ReelsDeepLink.empty
    /// TabView echoes a programmatic `selectedTab = .reels` as an icon re-tap. That would
    /// remount Feeds with an empty deep link and drop the channel / performer handoff.
    var suppressNextFeedsIconRemount = false

    // StashLine Navigation
    @Published var stashlinePath = NavigationPath()
    @Published var picsPerformerFilter: GalleryPerformer?

    
    // IDs to force reset of navigation stacks
    @Published var homeTabID = UUID()
    @Published var performersTabID = UUID()
    @Published var studiosTabID = UUID()
    @Published var catalogueTabID = UUID()
    /// Pops catalogue details without remounting the stack (avoids a top-left zoom).
    @Published var cataloguePopToken = UUID()
    @Published var downloadsTabID = UUID()
    @Published var toolsTabID = UUID()
    @Published var reelsTabID = UUID()
    @Published var stashlineTabID = UUID()
    @Published var settingsTabID = UUID()
    @Published var serverSwitchID = UUID()
    
    // Sub-tab control for Combined Tabs
    @Published var catalogueSubTab: String = ""
    @Published var toolsSubTab: String = ""
    
    // Remote state injection for deep links
    @Published var activeSortOption: String?
    @Published var activeFilter: StashDBViewModel.SavedFilter?
    @Published var activeSearchText: String = ""
    @Published var noDefaultFilter: Bool = false  // Prevent default filter application
    
    // Tap timing for "Double Tap" detection
    var lastHomeTapTime: Date?
    
    // Initializer to set start tab based on config
    init() {
        // Force load TabManager
        _ = TabManager.shared
        
        // Default to the first visible tab
        if let firstTab = TabManager.shared.visibleTabs.first {
            selectedTab = firstTab
        }

        #if DEBUG
        // Simulator automation: `xcrun simctl launch <udid> de.letzgo.stashy -stashyDebugCatalogueSubTab Studios`
        // lands on that catalogue sub-tab (UserDefaults argument domain), no taps needed.
        if let debugSubTab = UserDefaults.standard.string(forKey: "stashyDebugCatalogueSubTab"), !debugSubTab.isEmpty {
            catalogueSubTab = debugSubTab
        }
        // `-stashyDebugOpenStudio "<id>|<name>[|scenes|galleries|images|performers]"` pushes that
        // studio detail from the Studios catalogue; the optional counts mimic a real grid object.
        if let raw = UserDefaults.standard.string(forKey: "stashyDebugOpenStudio"), !raw.isEmpty {
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            func count(_ i: Int) -> Int? { parts.count > i ? Int(parts[i]) : nil }
            catalogueSubTab = "Studios"
            studioToOpen = Studio(
                id: parts[0], name: parts.count > 1 ? parts[1] : "Studio",
                sceneCount: count(2) ?? 0, performerCount: count(5), galleryCount: count(3), imageCount: count(4)
            )
        }
        // `-stashyDebugStudiosSort nameDesc` (StudioSortOption raw value) sets the persistent
        // Studios sort, so a specific studio can be brought to the top of the grid.
        if let raw = UserDefaults.standard.string(forKey: "stashyDebugStudiosSort"),
           StashDBViewModel.StudioSortOption(rawValue: raw) != nil {
            TabManager.shared.setPersistentSortOption(for: .studios, option: raw)
        }
        // `-stashyDebugSelectedTab settings` (AppTab raw value) selects that main tab at launch.
        if let raw = UserDefaults.standard.string(forKey: "stashyDebugSelectedTab"), let tab = AppTab(rawValue: raw) {
            selectedTab = tab
        }
        #endif
        
        // Listen for server changes to reset all stacks
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
    
    @objc private func handleServerChange() {
        resetAllStacks()
    }
    
    func openPerformer(_ performer: Performer) {
        // Reset the Catalogue tab stack (performers live as a catalogue sub-tab)
        catalogueTabID = UUID()
        
        // Set the performer to open
        performerToOpen = performer
        
        // Switch internal sub-tab to Performers
        catalogueSubTab = "Performers"
        
        // Switch to Catalogue tab
        selectedTab = .catalogue
    }
    
    func openStudio(_ studio: Studio) {
        // Reset the Catalogue tab stack (where studios now lives)
        catalogueTabID = UUID()
        
        // Set the studio to open
        studioToOpen = studio
        
        // Switch internal sub-tab to Studios
        catalogueSubTab = "Studios"
        
        // Switch to Catalogue tab
        selectedTab = .catalogue
    }

    // MARK: - Deep Links

    /// Search → Show All / stats deep links: switch catalog instantly.
    /// Do not remount `catalogueTabID` here — a new `NavigationStack` identity zooms
    /// in from the top-left (especially when leaving the Search tab).
    private func switchToCatalogue(_ subTab: String) {
        UIView.setAnimationsEnabled(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cataloguePopToken = UUID()
            catalogueSubTab = subTab
            selectedTab = .catalogue
        }
        DispatchQueue.main.async {
            UIView.setAnimationsEnabled(true)
        }
    }
    
    func navigateToScenes(sort: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter? = nil, search: String = "", noDefaultFilter: Bool = false) {
        self.activeSortOption = sort?.rawValue
        self.activeFilter = filter
        self.activeSearchText = search
        self.noDefaultFilter = noDefaultFilter
        switchToCatalogue("Scenes")
    }
    
    func navigateToPerformers(sort: StashDBViewModel.PerformerSortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Performers")
    }
    
    func navigateToStudios(sort: StashDBViewModel.StudioSortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Studios")
    }
    
    func navigateToTags(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Tags")
    }
    
    func navigateToGalleries(sort: StashDBViewModel.GallerySortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Galleries")
    }
    
    func navigateToImages(search: String = "") {
        self.activeSearchText = search
        self.noDefaultFilter = !search.isEmpty
        switchToCatalogue("Images")
    }
    
    func navigateToGroups(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Groups")
    }

    func navigateToMarkers(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Markers")
    }
    
    func navigateToReels(performer: ScenePerformer? = nil, tags: [Tag] = [], studio: SceneStudio? = nil, mode: String? = nil) {
        let link = ReelsDeepLink(performer: performer, tags: tags, studio: studio, mode: mode, picsPerformer: nil)
        self.reelsDeepLink = link
        self.reelsPerformer = performer
        self.reelsTags = tags
        self.reelsStudio = studio
        self.reelsTargetMode = mode
        self.picsPerformerFilter = nil
        // Tear down players, then remount so performer/tag/studio handoff cannot reuse a stale session.
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    /// Dashboard channel → Feeds in Scenes mode, scoped to a saved scene filter.
    func navigateToReelsChannel(filter: StashDBViewModel.SavedFilter, sort: StashDBViewModel.SceneSortOption) {
        let link = ReelsDeepLink(
            performer: nil,
            tags: [],
            mode: "Scenes",
            picsPerformer: nil,
            sceneFilter: filter,
            sceneSort: sort.rawValue
        )
        self.reelsDeepLink = link
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Scenes"
        self.picsPerformerFilter = nil
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    /// Dashboard image channel → Feeds in Clips mode, scoped to a saved image filter.
    func navigateToReelsClipsChannel(filter: StashDBViewModel.SavedFilter, sort: StashDBViewModel.ImageSortOption) {
        let link = ReelsDeepLink(
            performer: nil,
            tags: [],
            mode: "Clips",
            picsPerformer: nil,
            clipFilter: filter,
            clipSort: sort.rawValue
        )
        self.reelsDeepLink = link
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Clips"
        self.picsPerformerFilter = nil
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    func navigateToStashLine(performer: GalleryPerformer) {
        let link = ReelsDeepLink(performer: nil, tags: [], mode: "Pics", picsPerformer: performer)
        self.reelsDeepLink = link
        self.picsPerformerFilter = performer
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Pics"
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    func clearReelsDeepLink() {
        reelsDeepLink = .empty
        reelsPerformer = nil
        reelsTags = []
        reelsStudio = nil
        reelsTargetMode = nil
        picsPerformerFilter = nil
    }
    
    func resetAllStacks() {
        homeTabID = UUID()
        performersTabID = UUID()
        studiosTabID = UUID()
        catalogueTabID = UUID()
        downloadsTabID = UUID()
        toolsTabID = UUID()
        reelsTabID = UUID()
        stashlineTabID = UUID()
        stashlinePath = NavigationPath()
        settingsTabID = UUID()
        serverSwitchID = UUID()

        activeSortOption = nil
        activeFilter = nil
        activeSearchText = ""
        noDefaultFilter = false
        performerToOpen = nil
        studioToOpen = nil
        clearReelsDeepLink()
        
        // Force navigation to Home (Dashboard) sub-tab
        self.catalogueSubTab = "Dashboard"
        self.selectedTab = .catalogue
    }
}

/// Atomic Feeds deep-link payload (Performer / Tags / Mode) for a single remount.
struct ReelsDeepLink: Equatable {
    var performer: ScenePerformer?
    var tags: [Tag]
    var studio: SceneStudio? = nil
    var mode: String?
    var picsPerformer: GalleryPerformer?
    /// Channel deep link: saved scene filter to apply instead of the Feeds default filter.
    var sceneFilter: StashDBViewModel.SavedFilter? = nil
    /// `SceneSortOption.rawValue` for a channel deep link.
    var sceneSort: String? = nil
    /// Channel deep link: saved image filter applied in Feeds → Clips.
    var clipFilter: StashDBViewModel.SavedFilter? = nil
    /// `ImageSortOption.rawValue` for a Clips channel deep link.
    var clipSort: String? = nil

    static let empty = ReelsDeepLink(performer: nil, tags: [], studio: nil, mode: nil, picsPerformer: nil)

    var isEmpty: Bool {
        performer == nil && tags.isEmpty && studio == nil && mode == nil && picsPerformer == nil
            && sceneFilter == nil && sceneSort == nil
            && clipFilter == nil && clipSort == nil
    }
}

// MARK: - SHARED UI COMPONENTS (Extracted for decluttering)

// MARK: - Connection Error
struct ConnectionErrorView: View {
    var title: String = "Server not reachable"
    let onRetry: () -> Void
    var isDark: Bool = false

    var body: some View {
        StatusPlaceholderView(
            icon: "server.rack",
            title: title,
            buttonText: "Retry Connection",
            isDark: isDark,
            fillsScreen: true,
            onAction: onRetry
        )
    }
}

// MARK: - Shared Empty State
struct SharedEmptyStateView: View {
    var icon: String
    var title: String
    var buttonText: String
    let onRetry: () -> Void
    var isDark: Bool = false

    var body: some View {
        StatusPlaceholderView(
            icon: icon,
            title: title,
            buttonText: buttonText,
            isDark: isDark,
            fillsScreen: true,
            onAction: onRetry
        )
    }
}

// MARK: - Custom Async Image


#endif
