//
//  TabManager.swift
//  stashy
//
import SwiftUI
import Combine

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
    case reels
    case search
    case settings
    case images
    
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
        case .reels: return "StashTok"
        case .search: return "Search"
        case .settings: return "Settings"

        }
    }
    
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .studios: return "building.2"
        case .performers: return "person.3"
        case .scenes: return "film"
        case .galleries: return "photo.stack"
        case .images: return "photo"
        case .tags: return "tag"
        case .media: return "play.square.stack"
        case .catalogue: return "square.grid.2x2.fill"
        case .downloads: return "square.and.arrow.down"
        case .reels: return "play.rectangle.on.rectangle"
        case .search: return "magnifyingglass"
        case .settings: return "gear"

        }
    }
}

// MARK: - Detail View Configuration
enum DetailViewContext: String, CaseIterable, Codable, Identifiable {
    case performer = "performer_detail"
    case studio = "studio_detail"
    case tag = "tag_detail"
    case gallery = "gallery_detail"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .performer: return "Performer Scenes"
        case .studio: return "Studio Scenes"
        case .tag: return "Tag Scenes"
        case .gallery: return "Gallery Images"
        }
    }
    
    var icon: String {
        switch self {
        case .performer: return "person.fill"
        case .studio: return "building.fill"
        case .tag: return "tag.fill"
        case .gallery: return "photo.on.rectangle.angled"
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
    
    enum CodingKeys: String, CodingKey {
        case id, isVisible, sortOrder, defaultFilterId, defaultFilterName
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
    
    var defaultTitle: String {
        switch self {
        case .lastPlayed: return "Last Played"
        case .lastAdded3Min: return "Recently Added"
        case .newest3Min: return "Newest Scenes"
        case .mostViewed3Min: return "Most Viewed"
        case .topCounter3Min: return "Top Counter"
        case .topRating3Min: return "Top Rated"
        case .random: return "Random Scenes"
        case .statistics: return "Statistics"
        }
    }
}

class TabManager: ObservableObject {
    static let shared = TabManager()
    
    @Published var tabs: [TabConfig] = []
    @Published var detailViews: [DetailViewConfig] = []
    @Published var homeRows: [HomeRowConfig] = []
    
    // Session-only sort options (not persisted)
    private var sessionSortOptions: [AppTab: String] = [:]
    private var sessionDetailSortOptions: [String: String] = [:]
    
    private let userDefaultsKey = "AppTabsConfig"
    private let detailSortKey = "DetailViewsSortConfig"
    private let homeRowsKey = "HomeRowsConfig"
    
    init() {
        // Initial load based on currently active server
        loadAllConfigs()
        
        // Listen for server changes to reload server-specific configuration
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
    
    @objc private func handleServerChange() {
        print("🔄 TabManager: Server changed, reloading configurations")
        loadAllConfigs()
    }
    
    private func loadAllConfigs() {
        loadConfig()
        loadDetailConfigs()
        loadHomeRows()
    }
    
    private var currentServerSuffix: String {
        if let activeConfig = ServerConfigManager.shared.activeConfig {
            return "_\(activeConfig.id.uuidString)"
        }
        return ""
    }
    
    var visibleTabs: [AppTab] {
        // Fixed order: Home, StashTok, Downloads, Search
        // Dashboard, Studios, Tags, Performers, Scenes, Galleries are now sub-tabs of Home
        var result: [AppTab] = [.catalogue]
        
        if tabs.first(where: { $0.id == .reels })?.isVisible ?? true {
            result.append(.reels)
        }
        
        if tabs.first(where: { $0.id == .downloads })?.isVisible ?? true {
            result.append(.downloads)
        }
        
        if tabs.first(where: { $0.id == .settings })?.isVisible ?? true {
            result.append(.settings)
        }
        
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
            
            // Migration: Fix legacy sort option values that don't match enum rawValues
            var needsSave = false
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
                TabConfig(id: .downloads, isVisible: true, sortOrder: 8, defaultSortOption: nil),
                TabConfig(id: .reels, isVisible: true, sortOrder: 10, defaultSortOption: "random"),
                TabConfig(id: .settings, isVisible: true, sortOrder: 9, defaultSortOption: nil)
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
                TabConfig(id: .downloads, isVisible: true, sortOrder: 8, defaultSortOption: nil),
                TabConfig(id: .reels, isVisible: true, sortOrder: 10, defaultSortOption: "random"),
                TabConfig(id: .settings, isVisible: true, sortOrder: 9, defaultSortOption: nil)
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
            self.homeRows = decoded.sorted { $0.sortOrder < $1.sortOrder }
            
            // Force update titles for predefined types to ensure they match new defaults
            for index in 0..<self.homeRows.count {
                let row = self.homeRows[index]
                self.homeRows[index].title = row.type.defaultTitle
            }
            ensureStatisticsRow()
            ensureMostViewedRow()
            ensureRandomRow()
            ensureTopCounterRow()
            ensureTopRatingRow()
        } else {
            // Default Home Rows
            self.homeRows = [
                HomeRowConfig(id: UUID(), title: HomeRowType.statistics.defaultTitle, isEnabled: true, sortOrder: 0, type: .statistics),
                HomeRowConfig(id: UUID(), title: HomeRowType.lastPlayed.defaultTitle, isEnabled: true, sortOrder: 1, type: .lastPlayed),
                HomeRowConfig(id: UUID(), title: HomeRowType.lastAdded3Min.defaultTitle, isEnabled: true, sortOrder: 2, type: .lastAdded3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.newest3Min.defaultTitle, isEnabled: true, sortOrder: 3, type: .newest3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.mostViewed3Min.defaultTitle, isEnabled: true, sortOrder: 4, type: .mostViewed3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.random.defaultTitle, isEnabled: true, sortOrder: 5, type: .random),
                HomeRowConfig(id: UUID(), title: HomeRowType.topCounter3Min.defaultTitle, isEnabled: false, sortOrder: 6, type: .topCounter3Min),
                HomeRowConfig(id: UUID(), title: HomeRowType.topRating3Min.defaultTitle, isEnabled: false, sortOrder: 7, type: .topRating3Min)
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
             // Shift everyone else down
             for i in 0..<homeRows.count {
                 homeRows[i].sortOrder += 1
             }
             let statsRow = HomeRowConfig(id: UUID(), title: HomeRowType.statistics.defaultTitle, isEnabled: true, sortOrder: 0, type: .statistics)
             homeRows.insert(statsRow, at: 0)
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
    
    // Helper to set sort option for a tab (session only)
    func setSortOption(for tab: AppTab, option: String) {
        sessionSortOptions[tab] = option
        objectWillChange.send()
    }
    
    // Helper to set persistent default sort option (from Settings)
    func setPersistentSortOption(for tab: AppTab, option: String) {
        if let index = tabs.firstIndex(where: { $0.id == tab }) {
            tabs[index].defaultSortOption = option
            // Clear session option when default is changed? 
            // Better keep it, but Settings usually implies "next time I open it"
            sessionSortOptions[tab] = option 
            saveConfig()
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
        var configurableTabs = tabs.filter { $0.id != .settings && $0.id != .studios && $0.id != .tags && $0.id != .scenes && $0.id != .galleries && $0.id != .performers && $0.id != .dashboard && $0.id != .media && $0.id != .catalogue }
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
                return $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries
            case .media:
                return false
            default:
                return false
            }
        }
        
        var subTabs = tabs.filter(filter).sorted { $0.sortOrder < $1.sortOrder }
        subTabs.move(fromOffsets: source, toOffset: destination)
        
        // Dashboard is fixed at order 0. Other sub-tabs start at 1.
        if let dashIdx = tabs.firstIndex(where: { $0.id == .dashboard }) {
            tabs[dashIdx].sortOrder = 0
            tabs[dashIdx].isVisible = true
        }
        
        for (index, tab) in subTabs.enumerated() {
            if let originalIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs[originalIndex].sortOrder = index + 1
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
