//
//  TabManager.swift
//  stashy
//
import SwiftUI
import Combine

/// Catalog grid density for Scenes / Galleries / Images (1 or 2 cards per row).
enum CatalogCardColumns: Int, CaseIterable, Codable {
    case one = 1
    case two = 2

    var next: CatalogCardColumns { self == .one ? .two : .one }

    /// Icon for the *current* layout (tap toggles to the other).
    var toggleIcon: String {
        switch self {
        case .one: return "rectangle.grid.1x2"
        case .two: return "square.grid.2x2"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .one: return "One card per row"
        case .two: return "Two cards per row"
        }
    }

    /// 1/row → 16:9 · 2/row → 1:1
    var cardAspectRatio: CGFloat {
        switch self {
        case .one: return 16.0 / 9.0
        case .two: return 1.0
        }
    }

    func gridItems(spacing: CGFloat = 12) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: rawValue)
    }
}

/// Independent persistence scopes for the 1/2-per-row toggle.
enum CatalogCardColumnScope: String, CaseIterable, Codable {
    case scenes
    case galleries
    case images
    /// Image grid inside an opened gallery (`ImagesView(gallery:)`).
    case openedGallery

    static func from(appTab: AppTab) -> CatalogCardColumnScope? {
        switch appTab {
        case .scenes: return .scenes
        case .galleries: return .galleries
        case .images: return .images
        default: return nil
        }
    }
}

enum AppTab: String, CaseIterable, Codable, Identifiable {
    case dashboard
    case studios
    case performers
    case scenes
    case galleries
    case tags
    case media
    case catalogue
    case downloads
    case tools
    /// Paywall tab shown in place of Tools while stashy+ is locked (iOS).
    case stashyPlus
    case reels
    case search
    case settings
    case images
    case groups
    case markers
    case stashline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .studios: return "Studios"
        case .performers: return "Performers"
        case .scenes: return "Scenes"
        case .galleries: return "Galleries"
        case .images: return "Images"
        case .tags: return "Tags"
        case .media: return "Media"
        case .catalogue: return "Home"
        case .downloads: return "Downloads"
        case .tools: return "Tools"
        case .stashyPlus: return "stashy+"
        case .reels: return "Feeds"
        case .search: return "Search"
        case .settings: return "Settings"
        case .groups: return "Groups"
        case .markers: return "Markers"
        case .stashline: return "StashLine"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .studios: return "building.2"
        case .performers: return "person.fill"
        case .scenes: return "film"
        case .galleries: return "photo.stack"
        case .images: return "photo"
        case .tags: return "tag"
        case .media: return "play.square.stack"
        case .catalogue: return "square.grid.2x2.fill"
        case .downloads: return "square.and.arrow.down"
        case .tools: return "cube.box"
        case .stashyPlus: return "sparkles"
        case .reels: return "play.rectangle.on.rectangle"
        case .search: return "magnifyingglass"
        case .settings: return "gear"
        case .groups: return "rectangle.stack.fill"
        case .markers: return "bookmark.fill"
        case .stashline: return "camera.fill"
        }
    }
}

// MARK: - Detail View Configuration
enum DetailViewContext: String, CaseIterable, Codable, Identifiable {
    case performer = "performer_detail"
    case studio = "studio_detail"
    case tag = "tag_detail"
    case gallery = "gallery_detail"
    case group = "group_detail"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .performer: return "Performer Scenes"
        case .studio: return "Studio Scenes"
        case .tag: return "Tag Scenes"
        case .gallery: return "Gallery Images"
        case .group: return "Group Scenes"
        }
    }
    
    var icon: String {
        switch self {
        case .performer: return "person.fill"
        case .studio: return "building.fill"
        case .tag: return "tag.fill"
        case .gallery: return "photo.on.rectangle.angled"
        case .group: return "rectangle.stack.fill"
        }
    }
}

struct DetailViewConfig: Codable, Identifiable, Equatable {
    let id: DetailViewContext
    var defaultSortOption: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case defaultSortOption = "sortOption"
    }
}

struct TabConfig: Codable, Identifiable, Equatable {
    let id: AppTab
    var isVisible: Bool
    var sortOrder: Int
    var defaultSortOption: String?
    var defaultFilterId: String?
    var defaultFilterName: String?
    var defaultMarkerFilterId: String?
    var defaultMarkerFilterName: String?
    var defaultClipFilterId: String?
    var defaultClipFilterName: String?
    var defaultPreviewFilterId: String?
    var defaultPreviewFilterName: String?

    enum CodingKeys: String, CodingKey {
        case id, isVisible, sortOrder, defaultFilterId, defaultFilterName, defaultMarkerFilterId, defaultMarkerFilterName, defaultClipFilterId, defaultClipFilterName, defaultPreviewFilterId, defaultPreviewFilterName
        case defaultSortOption = "sortOption"
    }
}

// MARK: - Home Row Configuration
struct HomeRowConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var isEnabled: Bool
    var sortOrder: Int
    var type: HomeRowType
    
    static func == (lhs: HomeRowConfig, rhs: HomeRowConfig) -> Bool {
        return lhs.id == rhs.id && 
               lhs.title == rhs.title && 
               lhs.isEnabled == rhs.isEnabled && 
               lhs.sortOrder == rhs.sortOrder && 
               lhs.type == rhs.type
    }
}

enum HomeRowType: String, Codable {
    case lastPlayed
    case lastAdded3Min
    case newest3Min
    case mostViewed3Min
    case topCounter3Min
    case topRating3Min
    case random
    case statistics
    case newPerformers
    case performersHighestSceneCount
    case newStudios
    case studiosHighestSceneCount
    case newGalleries
    case recentlyUpdatedGalleries
    case performersHighestOCount
    case performersHighestRating
    case galleriesHighestImageCount
    
    var defaultTitle: String {
        switch self {
        case .lastPlayed: return "Scenes - Last Played"
        case .lastAdded3Min: return "Scenes - Recently Added"
        case .newest3Min: return "Scenes - New"
        case .mostViewed3Min: return "Scenes - Most Viewed"
        case .topCounter3Min: return "Scenes - Top Counter"
        case .topRating3Min: return "Scenes - Top Rated"
        case .random: return "Scenes - Random"
        case .statistics: return "Statistics"
        case .newPerformers: return "Performers - New"
        case .performersHighestSceneCount: return "Performers - Top"
        case .newStudios: return "Studios - New"
        case .studiosHighestSceneCount: return "Studios - Top"
        case .newGalleries: return "Galleries - New"
        case .recentlyUpdatedGalleries: return "Galleries - Recently Updated"
        case .performersHighestOCount: return "Performers - Counter"
        case .performersHighestRating: return "Performers - Rating"
        case .galleriesHighestImageCount: return "Galleries - Image Count"
        }
    }
}

enum DashboardHeroSize: String, Codable, CaseIterable {
    case big
    case small
    
    var title: String {
        switch self {
        case .big: return "Big Hero"
        case .small: return "Small Hero"
        }
    }
}

// MARK: - Reels Mode Configuration
enum ReelsModeType: String, Codable, CaseIterable {
    case scenes
    case markers
    case clips
    case previews
    case pics
    
    var defaultTitle: String {
        switch self {
        case .scenes: return "Scenes"
        case .markers: return "Markers"
        case .clips: return "Clips"
        case .previews: return "Previews"
        case .pics: return "Pics"
        }
    }
    
    var icon: String {
        switch self {
        case .scenes: return "film"
        case .markers: return "bookmark.fill"
        case .clips: return "photo.on.rectangle.angled"
        case .previews: return "play.rectangle.on.rectangle.fill"
        case .pics: return "camera.fill"
        }
    }
}

struct ReelsModeConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var type: ReelsModeType
    var isEnabled: Bool
    var sortOrder: Int
    var defaultSortOption: String?
}

// MARK: - Tools Configuration

enum ToolsItem: String, Codable, CaseIterable, Identifiable {
    case server
    case downloads
    case statistics
    case hotOrNot
    case rateMe
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .server: return "Server"
        case .downloads: return "Downloads"
        case .statistics: return "Statistics"
        case .hotOrNot: return "Match"
        case .rateMe: return "RateMe"
        }
    }

    /// Name used in stashy+ settings / paywall lists.
    var plusFeatureTitle: String {
        switch self {
        case .statistics: return "Advanced Statistics"
        case .hotOrNot: return "Performer Match"
        default: return title
        }
    }
    
    var icon: String {
        switch self {
        case .server: return "server.rack"
        case .downloads: return "square.and.arrow.down"
        case .statistics: return "chart.bar.fill"
        case .hotOrNot: return "flame.fill"
        case .rateMe: return "star.fill"
        }
    }
}

struct ToolsItemConfig: Codable, Identifiable, Equatable {
    let id: ToolsItem
    var isEnabled: Bool
    var sortOrder: Int
}


class TabManager: ObservableObject {
    static let shared = TabManager()
    
    @Published var tabs: [TabConfig] = []
    @Published var detailViews: [DetailViewConfig] = []
    @Published var homeRows: [HomeRowConfig] = []
    @Published var reelsModes: [ReelsModeConfig] = []
    @Published var tools: [ToolsItemConfig] = []
    @Published var reelsFillHeight: Bool = true {
        didSet {
            UserDefaults.standard.set(reelsFillHeight, forKey: reelsFillHeightKey)
        }
    }
    @Published var reelsContinuousPlay: Bool = false {
        didSet {
            UserDefaults.standard.set(reelsContinuousPlay, forKey: reelsContinuousPlayKey)
        }
    }
    @Published var isPiPEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isPiPEnabled, forKey: isPiPEnabledKey)
        }
    }
    /// Allows live captions to pull a second low-res transcode ahead of the playhead.
    /// Costs extra server CPU, but is the only way to avoid recognition lag on transcoded scenes.
    @Published var isLiveCaptionLookaheadEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isLiveCaptionLookaheadEnabled, forKey: isLiveCaptionLookaheadKey)
        }
    }
    @Published var dashboardHeroSize: DashboardHeroSize = .big {
        didSet {
            UserDefaults.standard.set(dashboardHeroSize.rawValue, forKey: dashboardHeroSizeKey)
        }
    }
    @Published var useCompactStatistics: Bool = false {
        didSet {
            UserDefaults.standard.set(useCompactStatistics, forKey: useCompactStatisticsKey)
        }
    }
    @Published var showDashboardHeroBackground: Bool = true {
        didSet {
            UserDefaults.standard.set(showDashboardHeroBackground, forKey: showDashboardHeroBackgroundKey)
        }
    }
    @Published var useColoredStatistics: Bool = true {
        didSet {
            UserDefaults.standard.set(useColoredStatistics, forKey: useColoredStatisticsKey)
        }
    }
    /// Per-scope catalog card density (Scenes / Galleries / Images / opened gallery). Published for SwiftUI refresh.
    @Published private(set) var catalogCardColumnsByScope: [CatalogCardColumnScope: CatalogCardColumns] = [:]

    // Session-only sort options (not persisted)
    private var sessionSortOptions: [AppTab: String] = [:]
    private var sessionDetailSortOptions: [String: String] = [:]

    private let userDefaultsKey = "AppTabsConfig"
    private let detailSortKey = "DetailViewsSortConfig"
    private let homeRowsKey = "HomeRowsConfig"
    private let reelsModesKey = "ReelsModesConfig"
    private let toolsKey = "ToolsConfig"
    private let reelsFillHeightKey = "ReelsFillHeight"
    private let reelsContinuousPlayKey = "ReelsContinuousPlay"
    private let isPiPEnabledKey = "isPiPEnabled"
    private let isLiveCaptionLookaheadKey = "isLiveCaptionLookaheadEnabled"
    private let dashboardHeroSizeKey = "DashboardHeroSize"
    private let useCompactStatisticsKey = "useCompactStatistics"
    private let showDashboardHeroBackgroundKey = "showDashboardHeroBackground"
    private let useColoredStatisticsKey = "useColoredStatistics"
    private let catalogCardColumnsKey = "CatalogCardColumns"
    
    init() {
        // Initial load based on currently active server
        loadAllConfigs()
        
        // Listen for server changes to reload server-specific configuration
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
        #if !os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStashyPlusChange), name: .stashyPlusUnlocked, object: nil)
        #endif
    }
    
    @objc private func handleServerChange() {
        print("🔄 TabManager: Server changed, reloading configurations")
        loadAllConfigs()
    }

    #if !os(tvOS)
    @objc private func handleStashyPlusChange() {
        objectWillChange.send()
    }
    #endif
    
    private func loadAllConfigs() {
        loadConfig()
        loadDetailConfigs()
        loadHomeRows()
        loadReelsModes()
        loadTools()
        self.reelsFillHeight = UserDefaults.standard.object(forKey: reelsFillHeightKey) as? Bool ?? true
        self.reelsContinuousPlay = UserDefaults.standard.bool(forKey: reelsContinuousPlayKey)
        self.isPiPEnabled = UserDefaults.standard.object(forKey: isPiPEnabledKey) as? Bool ?? true
        self.isLiveCaptionLookaheadEnabled = UserDefaults.standard.object(forKey: isLiveCaptionLookaheadKey) as? Bool ?? true
        if let heroSizeRaw = UserDefaults.standard.string(forKey: dashboardHeroSizeKey),
           let heroSize = DashboardHeroSize(rawValue: heroSizeRaw) {
            self.dashboardHeroSize = heroSize
        } else {
            self.dashboardHeroSize = .big
        }
        self.useCompactStatistics = UserDefaults.standard.bool(forKey: useCompactStatisticsKey)
        self.showDashboardHeroBackground = UserDefaults.standard.object(forKey: showDashboardHeroBackgroundKey) as? Bool ?? true
        self.useColoredStatistics = UserDefaults.standard.object(forKey: useColoredStatisticsKey) as? Bool ?? true
        loadCatalogCardColumns()
    }

    // MARK: - Catalog card columns (1 / 2 per row)

    private func defaultCatalogCardColumns(for scope: CatalogCardColumnScope) -> CatalogCardColumns {
        switch scope {
        case .scenes: return .one
        case .galleries, .images, .openedGallery: return .two
        }
    }

    private func loadCatalogCardColumns() {
        var loaded: [CatalogCardColumnScope: CatalogCardColumns] = [:]
        if let data = UserDefaults.standard.data(forKey: catalogCardColumnsKey),
           let raw = try? JSONDecoder().decode([String: Int].self, from: data) {
            for scope in CatalogCardColumnScope.allCases {
                if let value = raw[scope.rawValue], let columns = CatalogCardColumns(rawValue: value) {
                    loaded[scope] = columns
                }
            }
            // First launch after split: seed opened-gallery from the shared Images preference.
            if loaded[.openedGallery] == nil, let images = loaded[.images] {
                loaded[.openedGallery] = images
            }
        }
        for scope in CatalogCardColumnScope.allCases where loaded[scope] == nil {
            loaded[scope] = defaultCatalogCardColumns(for: scope)
        }
        catalogCardColumnsByScope = loaded
    }

    private func saveCatalogCardColumns() {
        var raw: [String: Int] = [:]
        for (scope, columns) in catalogCardColumnsByScope {
            raw[scope.rawValue] = columns.rawValue
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: catalogCardColumnsKey)
        }
    }

    func catalogCardColumns(for scope: CatalogCardColumnScope) -> CatalogCardColumns {
        catalogCardColumnsByScope[scope] ?? defaultCatalogCardColumns(for: scope)
    }

    func catalogCardColumns(for tab: AppTab) -> CatalogCardColumns {
        guard let scope = CatalogCardColumnScope.from(appTab: tab) else {
            return .two
        }
        return catalogCardColumns(for: scope)
    }

    func setCatalogCardColumns(_ columns: CatalogCardColumns, for scope: CatalogCardColumnScope) {
        var next = catalogCardColumnsByScope
        next[scope] = columns
        catalogCardColumnsByScope = next
        saveCatalogCardColumns()
    }

    func setCatalogCardColumns(_ columns: CatalogCardColumns, for tab: AppTab) {
        guard let scope = CatalogCardColumnScope.from(appTab: tab) else { return }
        setCatalogCardColumns(columns, for: scope)
    }

    func toggleCatalogCardColumns(for scope: CatalogCardColumnScope) {
        setCatalogCardColumns(catalogCardColumns(for: scope).next, for: scope)
    }

    func toggleCatalogCardColumns(for tab: AppTab) {
        guard let scope = CatalogCardColumnScope.from(appTab: tab) else { return }
        toggleCatalogCardColumns(for: scope)
    }
    
    private var currentServerSuffix: String {
        if let activeConfig = ServerConfigManager.shared.activeConfig {
            return "_\(activeConfig.id.uuidString)"
        }
        return ""
    }
    
    var visibleTabs: [AppTab] {
        // Fixed order: Home, Feeds (optional), Tools or stashy+ (iOS), Settings
        // Dashboard, Studios, Tags, Performers, Scenes, Galleries are now sub-tabs of Home
        // Server tasks live under Settings (not in the Tools tab)
        let reelsVisible = tabs.first(where: { $0.id == .reels })?.isVisible ?? true
        let toolsVisible = tabs.first(where: { $0.id == .tools })?.isVisible ?? true
        var result: [AppTab] = [.catalogue]
        if reelsVisible { result.append(.reels) }
        #if !os(tvOS)
        if StashyPlusManager.isUnlockedNow {
            if toolsVisible { result.append(.tools) }
        } else {
            result.append(.stashyPlus)
        }
        #else
        if toolsVisible { result.append(.tools) }
        #endif
        result.append(.settings)
        return result
    }

    
    // Settings is always available, technically, but we render it manually at the end or manage it
    // The user wants to toggle visibility of Studios, Performers, Scenes, Tags.
    
    func loadConfig() {
        let suffix = currentServerSuffix
        let serverSpecificKey = "\(userDefaultsKey)\(suffix)"
        
        var data = UserDefaults.standard.data(forKey: serverSpecificKey)
        
        // Migration: If no server-specific config exists, try to load legacy global config
        if data == nil && !suffix.isEmpty {
            data = UserDefaults.standard.data(forKey: userDefaultsKey)
            if let legacyData = data {
                // CLEAR filter IDs during migration to prevent cross-server filter inheritance
                if var decoded = try? JSONDecoder().decode([TabConfig].self, from: legacyData) {
                    for i in 0..<decoded.count {
                        decoded[i].defaultFilterId = nil
                        decoded[i].defaultFilterName = nil
                    }
                    if let modifiedData = try? JSONEncoder().encode(decoded) {
                        data = modifiedData
                        print("💾 TabManager: Migrated legacy config (filters cleared) for server \(suffix)")
                        // Save it immediately for the new server suffix
                        UserDefaults.standard.set(modifiedData, forKey: serverSpecificKey)
                    }
                }
            }
        }

        if let data = data,
           let decoded = try? JSONDecoder().decode([TabConfig].self, from: data) {
            
            // Migration: rename home to dashboard if needed
            // This is harder in Swift with enums, but we'll try to handle it during decoding or just rely on defaults if rawValue changes
            // If a TabConfig was saved with a rawValue "home", it would fail to decode into AppTab.dashboard directly.
            // The current AppTab enum does not have a 'home' case, so any old 'home' entries would be dropped on decode.
            // We ensure .dashboard is present below.
            
            // Ensure the decoded tabs are sorted
            var decodedTabs = decoded.sorted { $0.sortOrder < $1.sortOrder }
            decodedTabs.removeAll { $0.id == .stashyPlus }
            
            var needsSave = false
            
            // Migration: Downloads is no longer a top-level tab (moved under Tools)
            if let idx = decodedTabs.firstIndex(where: { $0.id == .downloads }) {
                if decodedTabs[idx].isVisible {
                    decodedTabs[idx].isVisible = false
                    decodedTabs[idx].sortOrder = max(decodedTabs.map(\.sortOrder).max() ?? 0, 100)
                    needsSave = true
                }
            }

            // Migration: Fix legacy sort option values that don't match enum rawValues
            let sortOptionMigrations: [String: String] = [
                "scenes_count": "sceneCountDesc",
                "name": "nameAsc",
                "date": "dateDesc"
            ]
            for i in 0..<decodedTabs.count {
                if let currentOption = decodedTabs[i].defaultSortOption,
                   let newOption = sortOptionMigrations[currentOption] {
                    decodedTabs[i].defaultSortOption = newOption
                    needsSave = true
                }
            }
            
            // Ensure dashboard is always at index 0 and visible
            if let dashIdx = decodedTabs.firstIndex(where: { $0.id == .dashboard }) {
                decodedTabs[dashIdx].sortOrder = 0
                decodedTabs[dashIdx].isVisible = true
            }
            
            self.tabs = decodedTabs
            
            // Re-check for dashboard if it was home or missing
            if !tabs.contains(where: { $0.id == .dashboard }) {
                tabs.append(TabConfig(id: .dashboard, isVisible: true, sortOrder: 0, defaultSortOption: nil))
                saveConfig()
            }
            
            // Migration: Check if new tabs are missing and add them
            let allTabs = [
                TabConfig(id: .dashboard, isVisible: true, sortOrder: 0, defaultSortOption: nil),
                TabConfig(id: .studios, isVisible: true, sortOrder: 1, defaultSortOption: "sceneCountDesc"),
                TabConfig(id: .performers, isVisible: true, sortOrder: 2, defaultSortOption: "sceneCountDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .scenes, isVisible: true, sortOrder: 3, defaultSortOption: "dateDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .galleries, isVisible: true, sortOrder: 4, defaultSortOption: "dateDesc"),
                TabConfig(id: .images, isVisible: true, sortOrder: 5, defaultSortOption: "dateDesc"),
                TabConfig(id: .tags, isVisible: true, sortOrder: 6, defaultSortOption: "sceneCountDesc"),
                TabConfig(id: .media, isVisible: true, sortOrder: 6, defaultSortOption: nil),
                TabConfig(id: .catalogue, isVisible: true, sortOrder: 7, defaultSortOption: nil),
                TabConfig(id: .downloads, isVisible: false, sortOrder: 100, defaultSortOption: nil),
                TabConfig(id: .tools, isVisible: true, sortOrder: 8, defaultSortOption: nil),
                TabConfig(id: .reels, isVisible: true, sortOrder: 10, defaultSortOption: "random"),
                TabConfig(id: .settings, isVisible: true, sortOrder: 9, defaultSortOption: nil),
                TabConfig(id: .groups, isVisible: true, sortOrder: 11, defaultSortOption: "nameAsc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .markers, isVisible: true, sortOrder: 12, defaultSortOption: "createdAtDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .stashline, isVisible: true, sortOrder: 13, defaultSortOption: "dateDesc", defaultFilterId: nil, defaultFilterName: nil)
            ]

            var hasChanges = false
            for tab in allTabs {
                if !decodedTabs.contains(where: { $0.id == tab.id }) {
                    decodedTabs.append(tab)
                    hasChanges = true
                }
            }
            
            // Save config if migrations were applied or tabs were added
            self.tabs = decodedTabs
            if hasChanges || needsSave {
                saveConfig()
            }
        } else {
            // Default config
            self.tabs = [
                TabConfig(id: .dashboard, isVisible: true, sortOrder: 0, defaultSortOption: nil),
                TabConfig(id: .studios, isVisible: true, sortOrder: 1, defaultSortOption: "sceneCountDesc"),
                TabConfig(id: .performers, isVisible: true, sortOrder: 2, defaultSortOption: "sceneCountDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .scenes, isVisible: true, sortOrder: 3, defaultSortOption: "dateDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .galleries, isVisible: true, sortOrder: 4, defaultSortOption: "dateDesc"),
                TabConfig(id: .images, isVisible: true, sortOrder: 5, defaultSortOption: "dateDesc"),
                TabConfig(id: .tags, isVisible: true, sortOrder: 6, defaultSortOption: "sceneCountDesc"),
                TabConfig(id: .media, isVisible: true, sortOrder: 6, defaultSortOption: nil),
                TabConfig(id: .catalogue, isVisible: true, sortOrder: 7, defaultSortOption: nil),
                TabConfig(id: .downloads, isVisible: false, sortOrder: 100, defaultSortOption: nil),
                TabConfig(id: .tools, isVisible: true, sortOrder: 8, defaultSortOption: nil),
                TabConfig(id: .reels, isVisible: true, sortOrder: 10, defaultSortOption: "random"),
                TabConfig(id: .settings, isVisible: true, sortOrder: 9, defaultSortOption: nil),
                TabConfig(id: .groups, isVisible: true, sortOrder: 11, defaultSortOption: "nameAsc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .markers, isVisible: true, sortOrder: 12, defaultSortOption: "createdAtDesc", defaultFilterId: nil, defaultFilterName: nil),
                TabConfig(id: .stashline, isVisible: true, sortOrder: 13, defaultSortOption: "dateDesc", defaultFilterId: nil, defaultFilterName: nil)
            ]
            saveConfig()
        }
    }
    
    func loadHomeRows() {
        let suffix = currentServerSuffix
        let serverSpecificKey = "\(homeRowsKey)\(suffix)"
        
        var data = UserDefaults.standard.data(forKey: serverSpecificKey)
        
        // Migration
        if data == nil && !suffix.isEmpty {
            data = UserDefaults.standard.data(forKey: homeRowsKey)
            if let legacyData = data {
                UserDefaults.standard.set(legacyData, forKey: serverSpecificKey)
            }
        }
        
        if let data = data,
           let decoded = try? JSONDecoder().decode([HomeRowConfig].self, from: data) {
            // Deduplicate by type (keep the first occurrence of each type)
            var seenTypes = Set<HomeRowType>()
            let unique = decoded.sorted { $0.sortOrder < $1.sortOrder }.filter { row in
                if seenTypes.contains(row.type) { return false }
                seenTypes.insert(row.type)
                return true
            }
            self.homeRows = unique

            // Re-assign sort orders after dedup
            for i in 0..<self.homeRows.count {
                self.homeRows[i].sortOrder = i
                self.homeRows[i].title = self.homeRows[i].type.defaultTitle
            }
            if unique.count != decoded.count { saveHomeRows() }
            ensureStatisticsRow()
            ensureMostViewedRow()
            ensureRandomRow()
            ensureTopCounterRow()
            ensureTopRatingRow()
            ensureNewPerformersRow()
            ensureHighestSceneCountPerformersRow()
            ensureNewStudiosRow()
            ensureHighestSceneCountStudiosRow()
            ensureRecentlyUpdatedGalleriesRow()
            ensurePerformersHighestOCountRow()
            ensurePerformersHighestRatingRow()
            ensureGalleriesHighestImageCountRow()
        } else {
            // Default Home Rows
            self.homeRows = [
                HomeRowConfig(id: UUID(), title: HomeRowType.statistics.defaultTitle, isEnabled: true, sortOrder: 0, type: .statistics),
                HomeRowConfig(id: UUID(), title: HomeRowType.lastPlayed.defaultTitle, isEnabled: true, sortOrder: 1, type: .lastPlayed),
                HomeRowConfig(id: UUID(), title: HomeRowType.lastAdded3Min.defaultTitle, isEnabled: true, sortOrder: 2, type: .lastAdded3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.newPerformers.defaultTitle, isEnabled: true, sortOrder: 3, type: .newPerformers),
                HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestSceneCount.defaultTitle, isEnabled: true, sortOrder: 4, type: .performersHighestSceneCount),
                HomeRowConfig(id: UUID(), title: HomeRowType.newStudios.defaultTitle, isEnabled: true, sortOrder: 5, type: .newStudios),
                HomeRowConfig(id: UUID(), title: HomeRowType.studiosHighestSceneCount.defaultTitle, isEnabled: true, sortOrder: 6, type: .studiosHighestSceneCount),
                HomeRowConfig(id: UUID(), title: HomeRowType.newGalleries.defaultTitle, isEnabled: true, sortOrder: 7, type: .newGalleries),
                HomeRowConfig(id: UUID(), title: HomeRowType.recentlyUpdatedGalleries.defaultTitle, isEnabled: true, sortOrder: 8, type: .recentlyUpdatedGalleries),
                HomeRowConfig(id: UUID(), title: HomeRowType.galleriesHighestImageCount.defaultTitle, isEnabled: true, sortOrder: 9, type: .galleriesHighestImageCount),
                HomeRowConfig(id: UUID(), title: HomeRowType.newest3Min.defaultTitle, isEnabled: true, sortOrder: 10, type: .newest3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestOCount.defaultTitle, isEnabled: true, sortOrder: 11, type: .performersHighestOCount),
                HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestRating.defaultTitle, isEnabled: true, sortOrder: 12, type: .performersHighestRating),
                HomeRowConfig(id: UUID(), title: HomeRowType.mostViewed3Min.defaultTitle, isEnabled: true, sortOrder: 13, type: .mostViewed3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.random.defaultTitle, isEnabled: true, sortOrder: 14, type: .random),
                HomeRowConfig(id: UUID(), title: HomeRowType.topCounter3Min.defaultTitle, isEnabled: false, sortOrder: 15, type: .topCounter3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.topRating3Min.defaultTitle, isEnabled: false, sortOrder: 16, type: .topRating3Min)
            ]
            saveHomeRows()
        }
    }
    
    func saveHomeRows() {
        if let encoded = try? JSONEncoder().encode(homeRows) {
            let key = "\(homeRowsKey)\(currentServerSuffix)"
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func ensureStatisticsRow() {
         if !homeRows.contains(where: { $0.type == .statistics }) {
             let statsRow = HomeRowConfig(id: UUID(), title: HomeRowType.statistics.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .statistics)
             homeRows.append(statsRow)
             saveHomeRows()
         }
    }
    
    private func ensureRandomRow() {
         if !homeRows.contains(where: { $0.type == .random }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.random.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .random)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureMostViewedRow() {
         if !homeRows.contains(where: { $0.type == .mostViewed3Min }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.mostViewed3Min.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .mostViewed3Min)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureTopCounterRow() {
         if !homeRows.contains(where: { $0.type == .topCounter3Min }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.topCounter3Min.defaultTitle, isEnabled: false, sortOrder: homeRows.count, type: .topCounter3Min)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureTopRatingRow() {
         if !homeRows.contains(where: { $0.type == .topRating3Min }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.topRating3Min.defaultTitle, isEnabled: false, sortOrder: homeRows.count, type: .topRating3Min)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureNewPerformersRow() {
         if !homeRows.contains(where: { $0.type == .newPerformers }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.newPerformers.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .newPerformers)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureHighestSceneCountPerformersRow() {
         if !homeRows.contains(where: { $0.type == .performersHighestSceneCount }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestSceneCount.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .performersHighestSceneCount)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }

    private func ensureNewStudiosRow() {
         if !homeRows.contains(where: { $0.type == .newStudios }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.newStudios.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .newStudios)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureHighestSceneCountStudiosRow() {
         if !homeRows.contains(where: { $0.type == .studiosHighestSceneCount }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.studiosHighestSceneCount.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .studiosHighestSceneCount)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureNewGalleriesRow() {
         if !homeRows.contains(where: { $0.type == .newGalleries }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.newGalleries.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .newGalleries)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureRecentlyUpdatedGalleriesRow() {
         if !homeRows.contains(where: { $0.type == .recentlyUpdatedGalleries }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.recentlyUpdatedGalleries.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .recentlyUpdatedGalleries)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }

    private func ensurePerformersHighestOCountRow() {
         if !homeRows.contains(where: { $0.type == .performersHighestOCount }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestOCount.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .performersHighestOCount)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }

    private func ensurePerformersHighestRatingRow() {
         if !homeRows.contains(where: { $0.type == .performersHighestRating }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.performersHighestRating.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .performersHighestRating)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    private func ensureGalleriesHighestImageCountRow() {
         if !homeRows.contains(where: { $0.type == .galleriesHighestImageCount }) {
             let newRow = HomeRowConfig(id: UUID(), title: HomeRowType.galleriesHighestImageCount.defaultTitle, isEnabled: true, sortOrder: homeRows.count, type: .galleriesHighestImageCount)
             homeRows.append(newRow)
             saveHomeRows()
         }
    }
    
    func toggleHomeRow(_ id: UUID) {
        if let index = homeRows.firstIndex(where: { $0.id == id }) {
            homeRows[index].isEnabled.toggle()
            saveHomeRows()
        }
    }
    
    func moveHomeRow(from source: IndexSet, to destination: Int) {
        homeRows.move(fromOffsets: source, toOffset: destination)
        for i in 0..<homeRows.count {
            homeRows[i].sortOrder = i
        }
        saveHomeRows()
    }
    
    func addCustomHomeRow(title: String, filterId: String) {
        // Deprecated: Custom rows are no longer supported
    }
    
    func removeHomeRow(_ id: UUID) {
        // Deprecated
    }
    
    // MARK: - Reels Mode Configuration
    
    func loadReelsModes() {
        let suffix = currentServerSuffix
        let serverSpecificKey = "\(reelsModesKey)\(suffix)"
        
        var data = UserDefaults.standard.data(forKey: serverSpecificKey)
        
        // Migration
        if data == nil && !suffix.isEmpty {
            data = UserDefaults.standard.data(forKey: reelsModesKey)
            if let legacyData = data {
                UserDefaults.standard.set(legacyData, forKey: serverSpecificKey)
            }
        }
        
        if let data = data,
           let decoded = try? JSONDecoder().decode([ReelsModeConfig].self, from: data) {
            self.reelsModes = decoded.sorted { $0.sortOrder < $1.sortOrder }
            
            // Ensure all modes exist (incl. Pics / StashLine 1-per-row).
            var hasChanges = false
            for modeType in ReelsModeType.allCases {
                if !reelsModes.contains(where: { $0.type == modeType }) {
                    let newMode = ReelsModeConfig(
                        id: UUID(),
                        type: modeType,
                        isEnabled: true,
                        sortOrder: reelsModes.count,
                        defaultSortOption: modeType == .pics ? "dateDesc" : nil
                    )
                    reelsModes.append(newMode)
                    hasChanges = true
                }
            }
            if hasChanges {
                for i in 0..<reelsModes.count { reelsModes[i].sortOrder = i }
                saveReelsModes()
            }
        } else {
            // Default Reels Modes
            self.reelsModes = [
                ReelsModeConfig(id: UUID(), type: .scenes, isEnabled: true, sortOrder: 0),
                ReelsModeConfig(id: UUID(), type: .markers, isEnabled: true, sortOrder: 1),
                ReelsModeConfig(id: UUID(), type: .clips, isEnabled: true, sortOrder: 2),
                ReelsModeConfig(id: UUID(), type: .previews, isEnabled: true, sortOrder: 3),
                ReelsModeConfig(id: UUID(), type: .pics, isEnabled: true, sortOrder: 4, defaultSortOption: "dateDesc")
            ]
            saveReelsModes()
        }
    }
    
    // MARK: - Tools

    func loadTools() {
        let suffix = currentServerSuffix
        let serverSpecificKey = "\(toolsKey)\(suffix)"
        
        var data = UserDefaults.standard.data(forKey: serverSpecificKey)
        
        // Migration
        if data == nil && !suffix.isEmpty {
            data = UserDefaults.standard.data(forKey: toolsKey)
            if let legacyData = data {
                UserDefaults.standard.set(legacyData, forKey: serverSpecificKey)
            }
        }
        
        if let data = data,
           let decoded = try? JSONDecoder().decode([ToolsItemConfig].self, from: data) {
            var result = decoded.sorted { $0.sortOrder < $1.sortOrder }
            
            // Ensure all tools exist (migration for new tools)
            var hasChanges = false
            for item in ToolsItem.allCases {
                if !result.contains(where: { $0.id == item }) {
                    result.append(ToolsItemConfig(id: item, isEnabled: true, sortOrder: result.count))
                    hasChanges = true
                }
            }
            
            self.tools = result.sorted { $0.sortOrder < $1.sortOrder }
            
            enforceFixedTools()
            if hasChanges { saveTools() }
        } else {
            // Default tools
            self.tools = [
                ToolsItemConfig(id: .downloads, isEnabled: true, sortOrder: 0),
                ToolsItemConfig(id: .server, isEnabled: true, sortOrder: 1),
                ToolsItemConfig(id: .statistics, isEnabled: true, sortOrder: 2),
                ToolsItemConfig(id: .hotOrNot, isEnabled: true, sortOrder: 3),
                ToolsItemConfig(id: .rateMe, isEnabled: true, sortOrder: 4)
            ]
            enforceFixedTools()
            saveTools()
        }
    }
    
    func saveTools() {
        enforceFixedTools()
        if let encoded = try? JSONEncoder().encode(tools) {
            let key = "\(toolsKey)\(currentServerSuffix)"
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    var enabledTools: [ToolsItem] {
        let sorted = tools.sorted { $0.sortOrder < $1.sortOrder }
        // Server tasks live under Settings.
        // Downloads / Advanced Statistics / Match / RateMe require stashy+ on iOS.
        return sorted.compactMap { item -> ToolsItem? in
            guard item.isEnabled, item.id != .server else { return nil }
            #if !os(tvOS)
            if Self.isStashyPlusTool(item.id), !StashyPlusManager.isUnlockedNow {
                return nil
            }
            #endif
            return item.id
        }
    }

    /// Tools managed / gated under stashy+.
    static func isStashyPlusTool(_ item: ToolsItem) -> Bool {
        item == .downloads || item == .statistics || item == .hotOrNot || item == .rateMe
    }
    
    func toggleTool(_ item: ToolsItem) {
        guard item != .server else { return }
        if let index = tools.firstIndex(where: { $0.id == item }) {
            tools[index].isEnabled.toggle()
            saveTools()
            objectWillChange.send()
        }
    }
    
    /// Reorder tools.
    func moveTools(from source: IndexSet, to destination: Int) {
        var reordered = tools.sorted { $0.sortOrder < $1.sortOrder }
        reordered.move(fromOffsets: source, toOffset: destination)
        tools = reordered.enumerated().map { idx, item in
            ToolsItemConfig(id: item.id, isEnabled: item.isEnabled, sortOrder: idx)
        }
        saveTools()
        objectWillChange.send()
    }
    
    private func enforceFixedTools() {
        // Ensure downloads exists (stashy+ tool — visibility gated separately).
        if !tools.contains(where: { $0.id == .downloads }) {
            tools.append(ToolsItemConfig(id: .downloads, isEnabled: true, sortOrder: (tools.map(\.sortOrder).max() ?? 0) + 1))
        }
    }

    func saveReelsModes() {
        if let encoded = try? JSONEncoder().encode(reelsModes) {
            let key = "\(reelsModesKey)\(currentServerSuffix)"
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func toggleReelsMode(_ type: ReelsModeType) {
        // Don't allow disabling all modes
        let enabledCount = reelsModes.filter { $0.isEnabled }.count
        if let index = reelsModes.firstIndex(where: { $0.type == type }) {
            if reelsModes[index].isEnabled && enabledCount <= 1 {
                return // Can't disable the last mode
            }
            reelsModes[index].isEnabled.toggle()
            saveReelsModes()
        }
    }
    
    func moveReelsMode(from source: IndexSet, to destination: Int) {
        var editable = reelsModes.sorted { $0.sortOrder < $1.sortOrder }
        editable.move(fromOffsets: source, toOffset: destination)
        for i in 0..<editable.count { editable[i].sortOrder = i }
        reelsModes = editable
        saveReelsModes()
    }
    
    var enabledReelsModes: [ReelsModeType] {
        reelsModes
            .filter { $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.type }
    }

    /// Modes shown in Feeds settings.
    var configurableReelsModes: [ReelsModeConfig] {
        reelsModes.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    func getReelsDefaultSort(for type: ReelsModeType) -> String? {
        return reelsModes.first(where: { $0.type == type })?.defaultSortOption
    }
    
    func setReelsDefaultSort(for type: ReelsModeType, option: String) {
        if let index = reelsModes.firstIndex(where: { $0.type == type }) {
            reelsModes[index].defaultSortOption = option
            saveReelsModes()
        }
    }

    func loadDetailConfigs() {
        let suffix = currentServerSuffix
        // Initialize default configs
        var configs: [DetailViewConfig] = []
        for context in DetailViewContext.allCases {
            let key = "\(detailSortKey)_\(context.rawValue)\(suffix)"
            var savedOption = UserDefaults.standard.string(forKey: key)
            
            // Migration
            if savedOption == nil && !suffix.isEmpty {
                savedOption = UserDefaults.standard.string(forKey: "\(detailSortKey)_\(context.rawValue)")
                if let legacyOption = savedOption {
                    UserDefaults.standard.set(legacyOption, forKey: key)
                }
            }
            
            configs.append(DetailViewConfig(id: context, defaultSortOption: savedOption ?? "dateDesc"))
        }
        self.detailViews = configs
    }
    
    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(tabs) {
            let key = "\(userDefaultsKey)\(currentServerSuffix)"
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // MARK: - Detail Views Sort Persistence
    
    // We need to fix the missing methods first if they are expected.
    // But let's focus on the user request: Detail View Sort Order.
    
    // Helper to get sort option for a tab (checks session first, then default)
    func getSortOption(for tab: AppTab) -> String? {
        if let sessionOption = sessionSortOptions[tab] {
            return sessionOption
        }
        return getPersistentSortOption(for: tab)
    }
    
    // Helper to get ONLY the persistent default sort option
    func getPersistentSortOption(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultSortOption
    }

    /// Scenes: value shown in Settings › Default Sorting, then current session sort if persistent is missing/invalid.
    /// Used when a saved filter / preset has no usable embedded `sortRaw`.
    func resolvedScenesSortFallbackFromTabConfig() -> StashDBViewModel.SceneSortOption {
        if let raw = getPersistentSortOption(for: .scenes),
           !raw.isEmpty,
           let o = StashDBViewModel.SceneSortOption(rawValue: raw) {
            return o
        }
        if let raw = getSortOption(for: .scenes),
           !raw.isEmpty,
           let o = StashDBViewModel.SceneSortOption(rawValue: raw) {
            return o
        }
        return .dateDesc
    }

    /// Detail views that list scenes (performer, studio, …): persistent detail sort, then session detail sort, then global scenes default.
    func resolvedDetailSceneSortFallback(for context: String) -> StashDBViewModel.SceneSortOption {
        if let raw = getPersistentDetailSortOption(for: context),
           !raw.isEmpty,
           let o = StashDBViewModel.SceneSortOption(rawValue: raw) {
            return o
        }
        if let raw = getDetailSortOption(for: context),
           !raw.isEmpty,
           let o = StashDBViewModel.SceneSortOption(rawValue: raw) {
            return o
        }
        return resolvedScenesSortFallbackFromTabConfig()
    }
    
    // Helper to set sort option for a tab (session only)
    func setSortOption(for tab: AppTab, option: String) {
        sessionSortOptions[tab] = option
        objectWillChange.send()
    }
    
    // Helper to set persistent default sort option (from Settings)
    func setPersistentSortOption(for tab: AppTab, option: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultSortOption = option
            sessionSortOptions[tab] = option
            saveConfig()
            NotificationCenter.default.post(
                name: NSNotification.Name("DefaultSortChanged"),
                object: nil,
                userInfo: ["tab": tab.rawValue]
            )
        }
    }
    
    // Helper to get default filter for a tab
    func getDefaultFilterId(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultFilterId
    }

    func getDefaultFilterName(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultFilterName
    }

    // Helper to set default filter for a tab
    func setDefaultFilter(for tab: AppTab, filterId: String?, filterName: String?) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultFilterId = filterId
            tabs[index].defaultFilterName = filterName
            saveConfig()
            
            // Notify listeners that the default filter has changed
            NotificationCenter.default.post(
                name: NSNotification.Name("DefaultFilterChanged"),
                object: nil,
                userInfo: ["tab": tab.id]
            )
        }
    }
    
    // Helper to get default marker filter for a tab
    func getDefaultMarkerFilterId(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultMarkerFilterId
    }

    func getDefaultMarkerFilterName(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultMarkerFilterName
    }

    // Helper to set default marker filter for a tab
    func setDefaultMarkerFilter(for tab: AppTab, filterId: String?, filterName: String?) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultMarkerFilterId = filterId
            tabs[index].defaultMarkerFilterName = filterName
            saveConfig()
            
            // Notify listeners that the default filter has changed
            NotificationCenter.default.post(
                name: NSNotification.Name("DefaultFilterChanged"),
                object: nil,
                userInfo: ["tab": tab.id]
            )
        }
    }
    
    // Helper to get default clip filter for a tab
    func getDefaultClipFilterId(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultClipFilterId
    }

    func getDefaultClipFilterName(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultClipFilterName
    }

    // Helper to set default clip filter for a tab
    func setDefaultClipFilter(for tab: AppTab, filterId: String?, filterName: String?) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultClipFilterId = filterId
            tabs[index].defaultClipFilterName = filterName
            saveConfig()

            NotificationCenter.default.post(
                name: NSNotification.Name("DefaultFilterChanged"),
                object: nil,
                userInfo: ["tab": tab.id]
            )
        }
    }

    // Helper to get default preview filter for a tab
    func getDefaultPreviewFilterId(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultPreviewFilterId
    }

    func getDefaultPreviewFilterName(for tab: AppTab) -> String? {
        return tabs.first(where: { $0.id == tab })?.defaultPreviewFilterName
    }

    // Helper to set default preview filter for a tab
    func setDefaultPreviewFilter(for tab: AppTab, filterId: String?, filterName: String?) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultPreviewFilterId = filterId
            tabs[index].defaultPreviewFilterName = filterName
            saveConfig()

            NotificationCenter.default.post(
                name: NSNotification.Name("DefaultFilterChanged"),
                object: nil,
                userInfo: ["tab": tab.id]
            )
        }
    }

    func getDetailSortOption(for context: String) -> String? {
        if let sessionOption = sessionDetailSortOptions[context] {
            return sessionOption
        }
        return getPersistentDetailSortOption(for: context)
    }

    // Helper to get ONLY the persistent default detail sort option
    func getPersistentDetailSortOption(for context: String) -> String? {
        return detailViews.first(where: { $0.id.rawValue == context })?.defaultSortOption
    }

    func setDetailSortOption(for context: String, option: String) {
        sessionDetailSortOptions[context] = option
        objectWillChange.send()
    }
    
    func setPersistentDetailSortOption(for context: String, option: String) {
        if let index = detailViews.firstIndex(where: { $0.id.rawValue == context }) {
            objectWillChange.send()
            detailViews[index].defaultSortOption = option
            sessionDetailSortOptions[context] = option
            let key = "\(detailSortKey)_\(context)\(currentServerSuffix)"
            UserDefaults.standard.set(option, forKey: key)
        }
    }
    
    func move(from source: IndexSet, to destination: Int) {
        // We only allow reordering of the top-level content tabs (excluding settings and sub-tabs)
        var configurableTabs = tabs.filter { $0.id != .settings && $0.id != .studios && $0.id != .tags && $0.id != .scenes && $0.id != .galleries && $0.id != .performers && $0.id != .dashboard && $0.id != .media && $0.id != .catalogue && $0.id != .images && $0.id != .groups && $0.id != .markers }
            .sorted { $0.sortOrder < $1.sortOrder }
            
        configurableTabs.move(fromOffsets: source, toOffset: destination)
        
        // Re-assign sort orders
        for (index, tab) in configurableTabs.enumerated() {
            if let originalIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs[originalIndex].sortOrder = index
            }
        }
        
        saveConfig()
    }
    
    func moveSubTab(from source: IndexSet, to destination: Int, within parent: AppTab) {
        let filter: (TabConfig) -> Bool = {
            switch parent {
            case .catalogue:
                return $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries || $0.id == .images || $0.id == .dashboard || $0.id == .groups || $0.id == .markers
            case .media:
                return false
            default:
                return false
            }
        }
        
        var subTabs = tabs.filter(filter).sorted { $0.sortOrder < $1.sortOrder }
        subTabs.move(fromOffsets: source, toOffset: destination)
        
        // Ensure dashboard stays at index 0 for Statistic Card & Menu
        if parent == .catalogue {
            if let dashIdx = subTabs.firstIndex(where: { $0.id == .dashboard }) {
                let dash = subTabs.remove(at: dashIdx)
                subTabs.insert(dash, at: 0)
            }
        }
        
        for (index, tab) in subTabs.enumerated() {
            if let originalIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs[originalIndex].sortOrder = index
            }
        }
        
        saveConfig()
    }
    
    func toggle(_ tab: AppTab) {
        // Prevent hiding the dashboard
        guard tab != .dashboard else { return }
        
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].isVisible.toggle()
            saveConfig()
        }
    }
}
