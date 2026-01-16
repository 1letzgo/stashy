//
//  StashDBViewModel.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI
import Combine
import AVFoundation
import AVKit
import StoreKit

// MARK: - App Colors

// Benutzerdefinierte Akzentfarbe - dunkles Braun #644C3D
extension Color {
    static let appAccent = Color(red: 0x64/255.0, green: 0x4C/255.0, blue: 0x3D/255.0)
    static let appBackground = Color(UIColor.systemGray6)
    static let studioHeaderGray = Color(red: 44/255.0, green: 44/255.0, blue: 46/255.0)
}

// MARK: - Filter Enums





import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case serverError(String)
    case networkError(Error)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .noData:
            return "No data received from server"
        case .decodingError:
            return "Error processing server response"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

class StashDBViewModel: ObservableObject {
    enum FilterMode: String, Codable {
        case scenes = "SCENES"
        case performers = "PERFORMERS"
        case studios = "STUDIOS"
        case galleries = "GALLERIES"
        case tags = "TAGS"
        case unknown = "UNKNOWN"
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self).uppercased()
            self = FilterMode(rawValue: string) ?? .unknown
        }
    }

    struct SavedFilter: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let mode: FilterMode
        let filter: String?
        let object_filter: StashJSONValue?
        
        var filterDict: [String: Any]? {
            if let obj = object_filter {
                return obj.value as? [String: Any]
            }
            if let str = filter, let data = str.data(using: .utf8) {
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return nil
        }
        
        static func == (lhs: SavedFilter, rhs: SavedFilter) -> Bool {
            return lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    struct SavedFiltersData: Codable {
        let findSavedFilters: [SavedFilter]
    }

    struct SavedFiltersResponse: Codable {
        let data: SavedFiltersData?
    }

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
        
        // Initial connection test if config exists
        if let config = ServerConfigManager.shared.loadConfig(), config.hasValidConfig {
             testConnection(with: config)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleServerChange() {
        DispatchQueue.main.async {
            self.resetData()
            print("🔄 StashDBViewModel reset due to server change")
        }
    }
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var serverStatus: String = "Nicht verbunden"

    @Published var savedFilters: [String: SavedFilter] = [:]
    @Published var isLoadingSavedFilters = false
    
    // Home Row Caching - prevents reload on view recreation
    @Published var homeRowScenes: [HomeRowType: [Scene]] = [:]
    @Published var homeRowLoadingState: [HomeRowType: Bool] = [:]

    // Data properties
    @Published var statistics: Statistics?
    @Published var scenes: [Scene] = []
    @Published var performers: [Performer] = []
    @Published var studios: [Studio] = []

    // Pagination properties for scenes
    @Published var totalScenes: Int = 0
    @Published var isLoadingMoreScenes = false
    @Published var hasMoreScenes = true
    private var currentScenePage = 1
    private var currentSceneSortOption: SceneSortOption = .dateDesc
    private let scenesPerPage = 20
    @Published var currentSceneFilter: SavedFilter? = nil

    // Pagination properties for performers
    @Published var totalPerformers: Int = 0
    @Published var isLoadingMorePerformers = false
    @Published var hasMorePerformers = true
    @Published var currentPerformerFilter: SavedFilter? = nil
    private var currentPerformerPage = 1
    private let performersPerPage = 500
    private var currentPerformerSortOption: PerformerSortOption = .nameAsc

    // Pagination properties for studios
    @Published var totalStudios: Int = 0
    @Published var isLoadingMoreStudios = false
    @Published var hasMoreStudios = true
    private var currentStudioPage = 1
    private let studiosPerPage = 500
    private var currentStudioSortOption: StudioSortOption = .nameAsc
    @Published var currentStudioFilter: SavedFilter? = nil

    // GraphQL Fragments


    // Galleries
    @Published var galleries: [Gallery] = []
    @Published var totalGalleries: Int = 0
    @Published var isLoadingGalleries: Bool = false
    @Published var hasMoreGalleries: Bool = false
    @Published var currentGalleryPage: Int = 1
    
    // Gallery Sort Options
    enum GallerySortOption: String, CaseIterable {
        case titleAsc
        case titleDesc
        // case imageCountDesc // Unsupported server-side
        // case imageCountAsc // Unsupported server-side
        case dateDesc
        case dateAsc

        var displayName: String {
            switch self {
            case .titleAsc: return "Name (A-Z)"
            case .titleDesc: return "Name (Z-A)"
            // case .imageCountDesc: return "Image Count (High-Low)"
            // case .imageCountAsc: return "Image Count (Low-High)"
            case .dateDesc: return "Date (Newest)"
            case .dateAsc: return "Date (Oldest)"
            }
        }

        var direction: String {
            switch self {
            case .titleAsc, .dateAsc: return "ASC"
            case .titleDesc, .dateDesc: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .titleAsc, .titleDesc: return "title"
            case .dateDesc, .dateAsc: return "date"
            }
        }
    }
    
    var currentGallerySortOption: GallerySortOption = .dateDesc
    @Published var currentGalleryFilter: SavedFilter? = nil
    var currentGallerySearchQuery: String = ""
    
    // Gallery Images (Detail)
    @Published var galleryImages: [StashImage] = []
    @Published var totalGalleryImages: Int = 0
    @Published var isLoadingGalleryImages: Bool = false
    @Published var hasMoreGalleryImages: Bool = false
    @Published var currentGalleryImagePage: Int = 1
    var currentGalleryImageSortOption: ImageSortOption = .dateDesc

    // Image Sort Options
    enum ImageSortOption: String, CaseIterable {
        case titleAsc
        case titleDesc
        case dateDesc
        case dateAsc
        
        var displayName: String {
            switch self {
            case .titleAsc: return "Title (A-Z)"
            case .titleDesc: return "Title (Z-A)"
            case .dateDesc: return "Date (Newest)"
            case .dateAsc: return "Date (Oldest)"
            }
        }
        
        var direction: String {
            switch self {
            case .titleAsc, .dateAsc: return "ASC"
            case .titleDesc, .dateDesc: return "DESC"
            }
        }
        
        var sortField: String {
            switch self {
            case .titleAsc, .titleDesc: return "title"
            case .dateDesc, .dateAsc: return "date"
            }
        }
    }

    // Performer sort options
    enum PerformerSortOption: String, CaseIterable {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case birthdateDesc
        case birthdateAsc
        case updatedAtDesc
        case updatedAtAsc
        case createdAtDesc
        case createdAtAsc

        var displayName: String {
            switch self {
            case .nameAsc: return "Name (A-Z)"
            case .nameDesc: return "Name (Z-A)"
            case .sceneCountDesc: return "Scene Count (High-Low)"
            case .sceneCountAsc: return "Scene Count (Low-High)"
            case .birthdateDesc: return "Birthday (Youngest First)"
            case .birthdateAsc: return "Birthday (Oldest First)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .birthdateAsc, .updatedAtAsc, .createdAtAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .birthdateDesc, .updatedAtDesc, .createdAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .birthdateAsc, .birthdateDesc: return "birthdate"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .random: return "random"
            }
        }
    }

    // Studio sort options
    enum StudioSortOption: String, CaseIterable {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case updatedAtDesc
        case updatedAtAsc
        case createdAtDesc
        case createdAtAsc

        var displayName: String {
            switch self {
            case .nameAsc: return "Name (A-Z)"
            case .nameDesc: return "Name (Z-A)"
            case .sceneCountDesc: return "Scene Count (High-Low)"
            case .sceneCountAsc: return "Scene Count (Low-High)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .updatedAtAsc, .createdAtAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .updatedAtDesc, .createdAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .random: return "random"
            }
        }
    }

    // Scene sort options
    enum SceneSortOption: String, CaseIterable {
        // ... (existing cases)
        case random
        case dateDesc
        case dateAsc
        case createdAtDesc
        case createdAtAsc
        case titleAsc
        case titleDesc
        case durationDesc
        case durationAsc
        case lastPlayedAtDesc
        case lastPlayedAtAsc
        case playCountDesc
        case playCountAsc

        var displayName: String {
            switch self {
            case .dateDesc: return "Date (Newest First)"
            case .dateAsc: return "Date (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .titleAsc: return "Title (A-Z)"
            case .titleDesc: return "Title (Z-A)"
            case .durationDesc: return "Duration (Longest First)"
            case .durationAsc: return "Duration (Shortest First)"
            case .lastPlayedAtDesc: return "Last Played (Newest First)"
            case .lastPlayedAtAsc: return "Last Played (Oldest First)"
            case .playCountDesc: return "Most Viewed"
            case .playCountAsc: return "Least Viewed"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .dateDesc, .createdAtDesc, .durationDesc, .lastPlayedAtDesc, .playCountDesc, .random: return "DESC"
            case .dateAsc, .createdAtAsc, .titleAsc, .durationAsc, .lastPlayedAtAsc, .playCountAsc: return "ASC"
            case .titleDesc: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .dateDesc, .dateAsc: return "date"
            case .createdAtDesc, .createdAtAsc: return "created_at"
            case .titleAsc, .titleDesc: return "title"
            case .durationDesc, .durationAsc: return "duration"
            case .lastPlayedAtDesc, .lastPlayedAtAsc: return "last_played_at"
            case .playCountDesc, .playCountAsc: return "play_count"
            case .random: return "random"
            }
        }
    }

    // Tag sort options
    enum TagSortOption: String, CaseIterable {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case updatedAtDesc
        case updatedAtAsc
        case createdAtDesc
        case createdAtAsc

        var displayName: String {
            switch self {
            case .nameAsc: return "Name (A-Z)"
            case .nameDesc: return "Name (Z-A)"
            case .sceneCountDesc: return "Scene Count (High-Low)"
            case .sceneCountAsc: return "Scene Count (Low-High)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .updatedAtAsc, .createdAtAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .updatedAtDesc, .createdAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .random: return "random"
            }
        }
    }

    // Detail View: Performer Galleries
    @Published var performerGalleries: [Gallery] = []
    @Published var totalPerformerGalleries: Int = 0
    @Published var isLoadingPerformerGalleries: Bool = false
    @Published var isLoadingMorePerformerGalleries: Bool = false
    @Published var hasMorePerformerGalleries: Bool = false
    @Published var currentPerformerGalleryPage: Int = 1
    private var currentPerformerGallerySortOption: GallerySortOption = .dateDesc

    // Detail View: Studio Galleries
    @Published var studioGalleries: [Gallery] = []
    @Published var totalStudioGalleries: Int = 0
    @Published var isLoadingStudioGalleries: Bool = false
    @Published var isLoadingMoreStudioGalleries: Bool = false
    @Published var hasMoreStudioGalleries: Bool = false
    @Published var currentStudioGalleryPage: Int = 1
    private var currentStudioGallerySortOption: GallerySortOption = .dateDesc

    // Performer scenes
    @Published var performerScenes: [Scene] = []
    @Published var totalPerformerScenes: Int = 0
    @Published var isLoadingPerformerScenes = false
    @Published var hasMorePerformerScenes = true
    private var currentPerformerScenePage = 1
    private var currentPerformerSceneSortOption: SceneSortOption = .dateDesc

    // Studio scenes
    @Published var studioScenes: [Scene] = []
    @Published var totalStudioScenes: Int = 0
    @Published var isLoadingStudioScenes = false
    @Published var hasMoreStudioScenes = true
    private var currentStudioScenePage = 1
    private var currentStudioSceneSortOption: SceneSortOption = .dateDesc

    private var cancellables = Set<AnyCancellable>()
    
    // Reset all data and pagination states (e.g. on server switch)
    func resetData() {
        scenes = []
        performers = []
        studios = []
        statistics = nil
        performerScenes = []
        studioScenes = []
        performerGalleries = []
        studioGalleries = []
        tags = []
        savedFilters = [:]
        
        totalScenes = 0
        totalPerformers = 0
        totalStudios = 0
        totalTags = 0
        
        currentScenePage = 1
        currentPerformerPage = 1
        currentStudioPage = 1
        currentTagPage = 1
        
        hasMoreScenes = true
        hasMorePerformers = true
        hasMoreStudios = true
        hasMoreTags = true
        
        currentPerformerGalleryPage = 1
        currentStudioGalleryPage = 1
        hasMorePerformerGalleries = true
        hasMoreStudioGalleries = true
        
        serverStatus = "Connecting..."
        errorMessage = nil
        
        // Clear home row cache
        homeRowScenes = [:]
        homeRowLoadingState = [:]
    }
    
    // MARK: - In-Place Scene Updates (without full reload)
    
    /// Updates a scene in all lists (scenes, homeRowScenes) without reloading
    func updateSceneInPlace(_ updatedScene: Scene) {
        // Update main scenes list
        if let index = scenes.firstIndex(where: { $0.id == updatedScene.id }) {
            scenes[index] = updatedScene
        }
        
        // Update home row caches
        for (rowType, rowScenes) in homeRowScenes {
            if let index = rowScenes.firstIndex(where: { $0.id == updatedScene.id }) {
                homeRowScenes[rowType]?[index] = updatedScene
            }
        }
    }
    
    /// Removes a scene from all lists without reloading
    func removeScene(id: String) {
        scenes.removeAll { $0.id == id }
        totalScenes = max(0, totalScenes - 1)
        
        // Remove from performer/studio scenes
        performerScenes.removeAll { $0.id == id }
        studioScenes.removeAll { $0.id == id }
        
        // Remove from home row caches
        for rowType in homeRowScenes.keys {
            homeRowScenes[rowType]?.removeAll { $0.id == id }
        }
    }
    
    /// Updates just the resume time of a scene in place
    func updateSceneResumeTime(id: String, newResumeTime: Double) {
        // Update main scenes list
        if let index = scenes.firstIndex(where: { $0.id == id }) {
            var updated = scenes[index]
            updated = updated.withResumeTime(newResumeTime)
            scenes[index] = updated
        }
        
        // Update performer scenes
        if let index = performerScenes.firstIndex(where: { $0.id == id }) {
            var updated = performerScenes[index]
            updated = updated.withResumeTime(newResumeTime)
            performerScenes[index] = updated
        }
        
        // Update studio scenes
        if let index = studioScenes.firstIndex(where: { $0.id == id }) {
            var updated = studioScenes[index]
            updated = updated.withResumeTime(newResumeTime)
            studioScenes[index] = updated
        }
        
        // Update home row caches
        for (rowType, rowScenes) in homeRowScenes {
            if let index = rowScenes.firstIndex(where: { $0.id == id }) {
                var updated = homeRowScenes[rowType]![index]
                updated = updated.withResumeTime(newResumeTime)
                homeRowScenes[rowType]?[index] = updated
            }
        }
    }

    func fetchSavedFilters() {
        guard let config = ServerConfigManager.shared.loadConfig(),
              let url = URL(string: "\(config.baseURL)/graphql") else {
            return
        }
        
        isLoadingSavedFilters = true
        
        // Query provided by user
        let query = """
        query GetAllFilterDefinitions {
          findSavedFilters {
            id
            name
            mode
            filter
            object_filter
          }
        }
        """
        
        let body: [String: Any] = ["query": query]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { 
            isLoadingSavedFilters = false
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                DispatchQueue.main.async {
                    self?.isLoadingSavedFilters = false
                }
            }
            
            guard let data = data, error == nil else {
                print("Error fetching saved filters: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let result = try JSONDecoder().decode(SavedFiltersResponse.self, from: data)
                DispatchQueue.main.async {
                    if let findResult = result.data?.findSavedFilters {
                        self?.savedFilters = Dictionary(uniqueKeysWithValues: findResult.map { ($0.id, $0) })
                        print("✅ Fetched \(findResult.count) saved filters")
                    }
                }
            } catch {
                print("❌ Decoding error (Saved Filters): \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw response: \(str)")
                }
            }
        }.resume()
    }
    
    func testConnection() {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            errorMessage = "Server configuration is missing or incomplete"
            print("❌ Test connection: No valid server configuration found")
            return
        }

        testConnection(with: config)
    }

    func testConnection(with customConfig: ServerConfig) {
        isLoading = true // Show loading state during connection test
        errorMessage = nil

        // GraphQL query for version
        let versionQuery = """
        {
          "query": "{ version { version } }"
        }
        """

        let urlString = "\(customConfig.baseURL)/graphql"
        // print("📱 Testing connection with custom config to: \(urlString)")
        // print("📱 Server config: Type=\(customConfig.connectionType), Domain=\(customConfig.domain), IP=\(customConfig.ipAddress), Port=\(customConfig.port)")

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL: \(urlString)"
            // isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5 // 5 Seconds Timeout
        
        // Add API Key if available
        if let apiKey = customConfig.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            print("📱 API Key wird verwendet (erste 8 Zeichen): \(String(apiKey.prefix(8)))...")
        }
        
        request.httpBody = versionQuery.data(using: .utf8)
        print("📱 Query: \(versionQuery)")

        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                // Debug: Show server response
                if let httpResponse = response as? HTTPURLResponse {
                    print("📱 Test Status Code: \(httpResponse.statusCode)")
                }
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📱 Server response: \(responseString)")
                }
                return data
            }
            .decode(type: VersionResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    // Handle Timeout specifically
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                         self?.serverStatus = "Nicht verbunden (Timeout)"
                         self?.errorMessage = "Connection timed out after 5 seconds."
                    } else {
                        self?.handleError(error)
                    }
                }
            } receiveValue: { [weak self] response in
                self?.isLoading = false
                let version = response.data?.version.version ?? "Unbekannt"
                print("📱 Version erhalten: \(version)")
                self?.serverStatus = "Verbunden - Version: \(version)"
                self?.errorMessage = nil // Clear error on success
            }
            .store(in: &cancellables)
    }

    func fetchStatistics() {
        errorMessage = nil // Clear error when starting
        let statisticsQuery = """
        {
          "query": "{ stats { scene_count scenes_size scenes_duration image_count images_size gallery_count performer_count studio_count movie_count tag_count } }"
        }
        """
        
        performGraphQLQuery(query: statisticsQuery) { (response: StashStatisticsResponse?) in
            if let stats = response?.data?.stats {
                DispatchQueue.main.async {
                    self.statistics = stats
                    self.errorMessage = nil // Clear error on success
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Statistics could not be loaded - possibly not supported"
                }
            }
        }
    }
    
    // Search query state for scenes
    private var currentSceneSearchQuery: String = ""
    
    func fetchScenes(sortBy: SceneSortOption = .dateDesc, searchQuery: String = "", filter: SavedFilter? = nil) {
        // Reset pagination
        currentScenePage = 1
        currentSceneSortOption = sortBy
        currentSceneSearchQuery = searchQuery
        currentSceneFilter = filter
        hasMoreScenes = true
        scenes = [] // Clear scenes to show loading state

        loadScenesPage(page: currentScenePage, sortBy: sortBy, searchQuery: searchQuery)
    }

    func loadMoreScenes() {
        guard !isLoadingMoreScenes && hasMoreScenes else { return }
        currentScenePage += 1
        loadScenesPage(page: currentScenePage, sortBy: currentSceneSortOption, searchQuery: currentSceneSearchQuery)
    }

    private func loadScenesPage(page: Int, sortBy: SceneSortOption, searchQuery: String = "") {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMoreScenes = true
        }
        errorMessage = nil

        // Query using Variables to support complex filters
        // Matches user provided structure: scene_filter first
        // Query using Variables to support complex filters
        // Matches user provided structure: scene_filter first
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !searchQuery.isEmpty {
            filterDict["q"] = searchQuery
        }
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        if let savedFilter = currentSceneFilter {
            if let dict = savedFilter.filterDict {
                let sanitized = sanitizeFilter(dict)
                print("🔍 Scene Filter sanitized: \(sanitized)")
                variables["scene_filter"] = sanitized
            } else if let obj = savedFilter.object_filter {
                variables["scene_filter"] = obj.value
            }
        }
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            print("❌ Error constructing request body in loadScenesPage")
            return
        }
        
        print("🔍 Debug loadScenesPage request body:")
        print(bodyString)
        
        // Pass bodyString as the query argument
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let scenesResult = response?.data?.findScenes {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.scenes = scenesResult.scenes
                        self.totalScenes = scenesResult.count
                    } else {
                        self.scenes.append(contentsOf: scenesResult.scenes)
                    }
                    
                    // Check if there are more pages
                    self.hasMoreScenes = scenesResult.scenes.count == self.scenesPerPage
                    
                    if isInitialLoad {
                        self.isLoading = false
                        self.errorMessage = nil // Success
                    } else {
                        self.isLoadingMoreScenes = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoading = false
                    } else {
                        self.isLoadingMoreScenes = false
                    }
                    // Keep error message processing if present
                }
            }
        }
    }
    
    
    
    // MARK: - Home Tab Support
    
    func fetchScenesForHomeRow(config: HomeRowConfig, completion: @escaping ([Scene]) -> Void) {
        let rowType = config.type
        
        // Return cached data immediately if available
        if let cached = homeRowScenes[rowType], !cached.isEmpty {
            completion(cached)
            return
        }
        
        // Already loading this row? Don't start another request
        if homeRowLoadingState[rowType] == true {
            return
        }
        
        homeRowLoadingState[rowType] = true
        
        var sceneFilter: [String: Any] = [:]
        var sortField = "date"
        var sortDirection = "DESC"
        
        func setSort(_ option: SceneSortOption) {
            sortField = option.sortField
            sortDirection = option.direction
        }
        
        switch config.type {
        case .lastPlayed:
            setSort(.lastPlayedAtDesc)
            sceneFilter["duration"] = ["value": 180, "modifier": "GREATER_THAN"]
        case .lastAdded3Min:
            setSort(.createdAtDesc)
            sceneFilter["duration"] = ["value": 180, "modifier": "GREATER_THAN"]
        case .newest3Min:
            setSort(.dateDesc)
            sceneFilter["duration"] = ["value": 180, "modifier": "GREATER_THAN"]
        case .mostViewed3Min:
            setSort(.playCountDesc)
            sceneFilter["duration"] = ["value": 180, "modifier": "GREATER_THAN"]
        case .random:
            setSort(.random)
            sceneFilter["duration"] = ["value": 180, "modifier": "GREATER_THAN"]
        case .statistics:
            homeRowLoadingState[rowType] = false
            completion([])
            return
        }
        
        // Construct the query
        let perPage = 10
        
        let queryVariables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": perPage,
                "sort": sortField,
                "direction": sortDirection
            ],
            "scene_filter": sceneFilter
        ]
        
        let gqlQuery = GraphQLQueries.queryWithFragments("findScenes")
        
        let body: [String: Any] = [
            "query": gqlQuery,
            "variables": queryVariables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            homeRowLoadingState[rowType] = false
            completion([])
            return
        }
        
        performGraphQLQuery(query: bodyString) { [weak self] (response: AltScenesResponse?) in
            DispatchQueue.main.async {
                self?.homeRowLoadingState[rowType] = false
                let scenes = response?.data?.findScenes?.scenes ?? []
                // Cache the result
                self?.homeRowScenes[rowType] = scenes
                completion(scenes)
            }
        }
    }
    
    private func sanitizeFilter(_ dict: [String: Any]) -> [String: Any] {
        var newDict = dict
        
        // 0. Convert "c" array (UI Format) to top-level keys (API Format)
        if let criteria = newDict["c"] as? [[String: Any]] {
            for item in criteria {
                if let key = item["id"] as? String {
                    var outputItem = item
                    outputItem.removeValue(forKey: "id")
                    newDict[key] = outputItem
                }
            }
            newDict.removeValue(forKey: "c")
        }
        
        // 1. Clean up known invalid top-level keys
        let invalidKeys = ["sort", "direction", "mode"]
        for key in invalidKeys {
            newDict.removeValue(forKey: key)
        }
        
        // 2. Iterate over all keys to handle nested structures recursively
        for (key, value) in newDict {
            if var subDict = value as? [String: Any] {
                // Perform Recursive call first on sub-elements
                subDict = sanitizeFilter(subDict)
                
                // 3. Special handling for specific Boolean Criterion keys that should be a simple Bool
                let booleanFlags = [
                    "duplicated", "organized", "performer_favorite", "studio_favorite", // Scenes
                    "filter_favorites", "is_favorite", "ignore_auto_tag", "favorite",   // Performers & Tags & Studios
                    "has_birthdate", "has_height_cm", "has_weight", "has_measurements",
                    "has_career_length", "has_tattoos", "has_piercings", "has_alias_list",
                    "has_markers"
                ]
                if booleanFlags.contains(key) {
                    var finalBool: Bool? = nil
                    if let val = subDict["value"] as? Bool {
                        finalBool = val
                    } else if let valStr = subDict["value"] as? String {
                        if valStr == "true" { finalBool = true }
                        else if valStr == "false" { finalBool = false }
                    }
                    if let val = finalBool {
                        // Stash API expects boolean filters as strings "true"/"false"
                        newDict[key] = val ? "true" : "false"
                        continue
                    }
                }
                
                // 4. Handle Multi-Select / ID Arrays (Performers, Studios, Tags, etc.)
                var itemsArray: [Any]? = nil
                if let valArray = subDict["value"] as? [Any] {
                    itemsArray = valArray
                } else if let valMap = subDict["value"] as? [String: Any], let items = valMap["items"] as? [Any] {
                    itemsArray = items
                }
                
                if let items = itemsArray {
                    let ids = items.compactMap { item -> String? in
                        if let idStr = item as? String { return idStr }
                        if let idInt = item as? Int { return String(idInt) }
                        if let obj = item as? [String: Any] {
                            if let id = obj["id"] as? String { return id }
                            if let id = obj["id"] as? Int { return String(id) }
                        }
                        return nil
                    }
                    
                    if key == "orientation" {
                        subDict["value"] = ids.map { $0.uppercased() }
                    } else {
                        subDict["value"] = ids
                    }
                    
                    // Modifiers like EQUALS don't work well with arrays in Stash GraphQL for some fields
                    if let mod = subDict["modifier"] as? String, (mod == "EQUALS" || mod == "CONTAINS") {
                        subDict.removeValue(forKey: "modifier")
                    }
                }
                
                // 5. Generic Value Unwrapping / Range Support
                // Stash stores range filter as: "rating": { "value": 4, "value2": 5, "modifier": "BETWEEN" }
                // Ensure value and value2 are correctly typed if they should be numbers
                let numericFields = ["rating", "play_count", "resume_time", "scene_count", "gallery_count", "performer_count", "tag_count", "duration", "framerate", "bitrate"]
                
                func castToNumeric(_ val: Any?) -> Any? {
                    if let i = val as? Int { return i }
                    if let d = val as? Double { return Int(d) }
                    if let s = val as? String, let i = Int(s) { return i }
                    return val
                }
                
                if numericFields.contains(key) || key.contains("count") {
                    if let v1 = subDict["value"] { subDict["value"] = castToNumeric(v1) }
                    if let v2 = subDict["value2"] { subDict["value2"] = castToNumeric(v2) }
                }
                
                // Generic unwrap of single value dicts
                if let valueDict = subDict["value"] as? [String: Any], let innerValue = valueDict["value"] {
                    subDict["value"] = innerValue
                }
                
                newDict[key] = subDict
            } else if key == "orientation", let valArray = value as? [String] {
                newDict[key] = valArray.map { $0.uppercased() }
            }
        }
        
        return newDict
    }
    
    func fetchPerformerGalleries(performerId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentPerformerGalleryPage = 1
            currentPerformerGallerySortOption = sortBy
            // performerGalleries = []
            totalPerformerGalleries = 0
            isLoadingPerformerGalleries = true
            hasMorePerformerGalleries = true
            errorMessage = nil
        } else {
            isLoadingMorePerformerGalleries = true
        }
        
        let page = isInitialLoad ? 1 : currentPerformerGalleryPage + 1
        
        // Sort Logic
        var sortField = "date"
        var sortDirection = "DESC"
        switch sortBy {
        case .titleAsc: sortField = "title"; sortDirection = "ASC"
        case .titleDesc: sortField = "title"; sortDirection = "DESC"
        case .dateDesc: sortField = "date"; sortDirection = "DESC"
        case .dateAsc: sortField = "date"; sortDirection = "ASC"
        }
        
        // Find galleries with performer filter
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortField,
                "direction": sortDirection
            ],
            "gallery_filter": [
                "performers": [
                    "value": [performerId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
            if let result = response?.data?.findGalleries {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.performerGalleries = result.galleries
                        self.totalPerformerGalleries = result.count
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.performerGalleries.append(contentsOf: result.galleries)
                    }
                    
                    self.hasMorePerformerGalleries = result.galleries.count == 20
                    self.currentPerformerGalleryPage = page
                    self.isLoadingPerformerGalleries = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingPerformerGalleries = false
                }
            }
        }
    }
    
    func loadMorePerformerGalleries(performerId: String) {
        if !isLoadingPerformerGalleries && hasMorePerformerGalleries {
            fetchPerformerGalleries(performerId: performerId, sortBy: currentPerformerGallerySortOption, isInitialLoad: false)
        }
    }
    
    
    func fetchStudioGalleries(studioId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentStudioGalleryPage = 1
            currentStudioGallerySortOption = sortBy
            totalStudioGalleries = 0
            isLoadingStudioGalleries = true
            hasMoreStudioGalleries = true
        } else {
            isLoadingStudioGalleries = true
        }
        errorMessage = nil
        
        let page = isInitialLoad ? 1 : currentStudioGalleryPage + 1
        
        // Sort Logic
        var sortField = "date"
        var sortDirection = "DESC"
        switch sortBy {
        case .titleAsc: sortField = "title"; sortDirection = "ASC"
        case .titleDesc: sortField = "title"; sortDirection = "DESC"
        case .dateDesc: sortField = "date"; sortDirection = "DESC"
        case .dateAsc: sortField = "date"; sortDirection = "ASC"
        }
        
        // Find galleries with studio filter
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortField,
                "direction": sortDirection
            ],
            "gallery_filter": [
                "studios": [
                    "value": [studioId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
            if let result = response?.data?.findGalleries {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.studioGalleries = result.galleries
                        self.totalStudioGalleries = result.count
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.studioGalleries.append(contentsOf: result.galleries)
                    }
                    
                    self.hasMoreStudioGalleries = result.galleries.count == 20
                    self.currentStudioGalleryPage = page
                    self.isLoadingStudioGalleries = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingStudioGalleries = false
                }
            }
        }
    }
    
    func loadMoreStudioGalleries(studioId: String) {
        if !isLoadingStudioGalleries && hasMoreStudioGalleries {
            fetchStudioGalleries(studioId: studioId, sortBy: currentStudioGallerySortOption, isInitialLoad: false)
        }
    }
    
    func fetchPerformerScenes(performerId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentPerformerScenePage = 1
            currentPerformerSceneSortOption = sortBy
            // performerScenes = [] <-- Don't clear to keep navigation stable
            totalPerformerScenes = 0
            isLoadingPerformerScenes = true
        } else {
            isLoadingPerformerScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentPerformerScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        let sceneFilter: [String: Any] = [
            "performers": [
                "modifier": "INCLUDES",
                "value": [performerId]
            ]
        ]
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let scenesResult = response?.data?.findScenes {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.performerScenes = scenesResult.scenes
                        self.totalPerformerScenes = scenesResult.count
                    } else {
                        self.performerScenes.append(contentsOf: scenesResult.scenes)
                    }
                    
                    // Check if there are more pages
                    self.hasMorePerformerScenes = scenesResult.scenes.count == self.scenesPerPage
                    self.currentPerformerScenePage = page
                    
                    if isInitialLoad {
                        self.isLoadingPerformerScenes = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingPerformerScenes = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoadingPerformerScenes = false
                    } else {
                        self.isLoadingPerformerScenes = false
                    }
                    self.errorMessage = "Szenen des Schauspielers konnten nicht geladen werden"
                }
            }
        }
    }
    
    func loadMorePerformerScenes(performerId: String) {
        if !isLoadingPerformerScenes && hasMorePerformerScenes {
            fetchPerformerScenes(performerId: performerId, sortBy: currentPerformerSceneSortOption, isInitialLoad: false)
        }
    }
    
    func fetchPerformer(performerId: String, completion: @escaping (Performer?) -> Void) {
        let performerQuery = GraphQLQueries.queryWithFragments("findPerformers")
        
        let variables: [String: Any] = ["ids": [performerId]]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": performerQuery, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: PerformersByIdsResponse?) in
            DispatchQueue.main.async {
                if let performer = response?.data?.findPerformers.performers.first {
                    completion(performer)
                } else {
                    print("❌ Performer mit ID \(performerId) nicht gefunden")
                    completion(nil)
                }
            }
        }
    }
    
    func fetchStudioScenes(studioId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentStudioScenePage = 1
            currentStudioSceneSortOption = sortBy
            // studioScenes = []
            totalStudioScenes = 0
            isLoadingStudioScenes = true
        } else {
            isLoadingStudioScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentStudioScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        let sceneFilter: [String: Any] = [
            "studios": [
                "modifier": "INCLUDES",
                "value": [studioId]
            ]
        ]
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let scenesResult = response?.data?.findScenes {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.studioScenes = scenesResult.scenes
                        self.totalStudioScenes = scenesResult.count
                    } else {
                        self.studioScenes.append(contentsOf: scenesResult.scenes)
                    }
                    
                    // Check if there are more pages
                    self.hasMoreStudioScenes = scenesResult.scenes.count == self.scenesPerPage
                    self.currentStudioScenePage = page
                    
                    if isInitialLoad {
                        self.isLoadingStudioScenes = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingStudioScenes = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoadingStudioScenes = false
                    } else {
                        self.isLoadingStudioScenes = false
                    }
                    self.errorMessage = "Szenen des Studios konnten nicht geladen werden"
                }
            }
        }
    }
    
    func loadMoreStudioScenes(studioId: String) {
        if !isLoadingStudioScenes && hasMoreStudioScenes {
            fetchStudioScenes(studioId: studioId, sortBy: currentStudioSceneSortOption, isInitialLoad: false)
        }
    }
    
    // Search query state for performers
    private var currentPerformerSearchQuery: String = ""
    
    func fetchPerformers(sortBy: PerformerSortOption = .nameAsc, searchQuery: String = "", filter: SavedFilter? = nil) {
        currentPerformerPage = 1
        currentPerformerSortOption = sortBy
        currentPerformerSearchQuery = searchQuery
        currentPerformerFilter = filter
        hasMorePerformers = true
        
        loadPerformersPage(page: currentPerformerPage, sortBy: sortBy, searchQuery: searchQuery)
    }
    
    func loadMorePerformers() {
        guard !isLoadingMorePerformers && hasMorePerformers else { return }
        currentPerformerPage += 1
        loadPerformersPage(page: currentPerformerPage, sortBy: currentPerformerSortOption, searchQuery: currentPerformerSearchQuery)
    }
    
    private func loadPerformersPage(page: Int, sortBy: PerformerSortOption, searchQuery: String = "") {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMorePerformers = true
        }
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findPerformers")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": performersPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !searchQuery.isEmpty {
            filterDict["q"] = searchQuery
        }
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        if let savedFilter = currentPerformerFilter {
            if let dict = savedFilter.filterDict {
                let sanitized = sanitizeFilter(dict)
                variables["performer_filter"] = sanitized
            } else if let obj = savedFilter.object_filter {
                variables["performer_filter"] = obj.value
            }
        }
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: PerformersResponse?) in
            if let performersResult = response?.data?.findPerformers {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.performers = performersResult.performers
                        self.totalPerformers = performersResult.count
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.performers.append(contentsOf: performersResult.performers)
                    }
                    
                    self.hasMorePerformers = performersResult.performers.count == self.performersPerPage
                    
                    if isInitialLoad {
                        self.isLoading = false
                    } else {
                        self.isLoadingMorePerformers = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isLoadingMorePerformers = false
                }
            }
        }
    }
    
    // Search query state for studios
    // Search query state for studios
    private var currentStudioSearchQuery: String = ""
    
    func fetchStudio(studioId: String, completion: @escaping (Studio?) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findStudio")
        
        let variables: [String: Any] = ["id": studioId]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SingleStudioResponse?) in
            DispatchQueue.main.async {
                completion(response?.data?.findStudio)
            }
        }
    }
    
    func fetchTag(tagId: String, completion: @escaping (Tag?) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findTag")
        
        let variables: [String: Any] = ["id": tagId]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SingleTagResponse?) in
            DispatchQueue.main.async {
                completion(response?.data?.findTag)
            }
        }
    }
    
    func fetchStudios(sortBy: StudioSortOption = .nameAsc, searchQuery: String = "", filter: SavedFilter? = nil) {
        // Reset pagination
        currentStudioPage = 1
        currentStudioSortOption = sortBy
        currentStudioSearchQuery = searchQuery
        currentStudioFilter = filter
        hasMoreStudios = true
        // studios = []
        
        loadStudiosPage(page: currentStudioPage, sortBy: sortBy, searchQuery: searchQuery, filter: filter)
    }
    
    func loadMoreStudios() {
        guard !isLoadingMoreStudios && hasMoreStudios else { return }
        currentStudioPage += 1
        loadStudiosPage(page: currentStudioPage, sortBy: currentStudioSortOption, searchQuery: currentStudioSearchQuery, filter: currentStudioFilter)
    }
    
    private func loadStudiosPage(page: Int, sortBy: StudioSortOption, searchQuery: String = "", filter: SavedFilter? = nil) {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMoreStudios = true
        }
        errorMessage = nil
        
        var studioFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                studioFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter {
                studioFilter = obj.value as? [String: Any] ?? [:]
            }
        }
        
        // Add search query to the filter
        if !searchQuery.isEmpty {
            studioFilter["q"] = searchQuery
        }
        
        // Variables for GraphQL
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": studiosPerPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "studio_filter": studioFilter
        ]
        
        let query = GraphQLQueries.queryWithFragments("findStudios")
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            print("❌ Error: Could not serialize Studios request body")
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: StudiosResponse?) in
            if let studiosResult = response?.data?.findStudios {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.studios = studiosResult.studios
                        self.totalStudios = studiosResult.count
                    } else {
                        self.studios.append(contentsOf: studiosResult.studios)
                    }
                    
                    // Check if there are more pages
                    self.hasMoreStudios = studiosResult.studios.count == self.studiosPerPage
                    
                    if isInitialLoad {
                        self.isLoading = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingMoreStudios = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoading = false
                        self.errorMessage = "Studios konnten nicht geladen werden"
                    } else {
                        self.isLoadingMoreStudios = false
                    }
                }
            }
        }
    }
    
    // MARK: - Tags Logic
    
    
    
    // Tag data
    @Published var tags: [Tag] = []
    @Published var totalTags: Int = 0
    @Published var isLoadingMoreTags = false
    @Published var hasMoreTags = true
    @Published var currentTagFilter: SavedFilter? = nil
    private var currentTagPage = 1
    private let tagsPerPage = 500
    private var currentTagSortOption: TagSortOption = .nameAsc
    private var currentTagSearchQuery: String = ""
    
    // Tag Scenes
    @Published var tagScenes: [Scene] = []
    @Published var totalTagScenes: Int = 0
    @Published var isLoadingTagScenes = false
    @Published var hasMoreTagScenes = true
    private var currentTagScenePage = 1
    private var currentTagSceneSortOption: SceneSortOption = .dateDesc
    
    func fetchTags(sortBy: TagSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentTagPage = 1
            tags = []
        }
        currentTagSortOption = sortBy
        currentTagSearchQuery = searchQuery
        currentTagFilter = filter
        hasMoreTags = true
        
        loadTagsPage(page: currentTagPage, sortBy: sortBy, searchQuery: searchQuery, isInitialLoad: isInitialLoad, filter: filter)
    }
    
    func loadMoreTags() {
        guard !isLoadingMoreTags && hasMoreTags else { return }
        currentTagPage += 1
        loadTagsPage(page: currentTagPage, sortBy: currentTagSortOption, searchQuery: currentTagSearchQuery, isInitialLoad: false, filter: currentTagFilter)
    }
    
    private func loadTagsPage(page: Int, sortBy: TagSortOption, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMoreTags = true
        }
        
        var tagFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                tagFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter {
                tagFilter = obj.value as? [String: Any] ?? [:]
            }
        }
        
        // Add search query to the filter
        if !searchQuery.isEmpty {
            tagFilter["name"] = [
                "value": searchQuery,
                "modifier": "INCLUDES"
            ]
        }
        
        // Variables for GraphQL
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": tagsPerPage,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "tag_filter": tagFilter
        ]
        
        let query = GraphQLQueries.queryWithFragments("findTags")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
            if let tagsResult = response?.data?.findTags {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.tags = tagsResult.tags
                        self.totalTags = tagsResult.count
                    } else {
                        self.tags.append(contentsOf: tagsResult.tags)
                    }
                    
                    self.hasMoreTags = tagsResult.tags.count == self.tagsPerPage
                    
                    if isInitialLoad {
                        self.isLoading = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingMoreTags = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isLoadingMoreTags = false
                }
            }
        }
    }
    
    func fetchTagScenes(tagId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentTagScenePage = 1
            currentTagSceneSortOption = sortBy
            // tagScenes = []
            totalTagScenes = 0
            isLoadingTagScenes = true
        } else {
            isLoadingTagScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentTagScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        let filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        let sceneFilter: [String: Any] = [
            "tags": [
                "modifier": "INCLUDES",
                "value": [tagId]
            ]
        ]
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let scenesResult = response?.data?.findScenes {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.tagScenes = scenesResult.scenes
                        self.totalTagScenes = scenesResult.count
                    } else {
                        self.tagScenes.append(contentsOf: scenesResult.scenes)
                    }
                    
                    self.hasMoreTagScenes = scenesResult.scenes.count == self.scenesPerPage
                    self.currentTagScenePage = page
                    
                    self.isLoadingTagScenes = false
                    if isInitialLoad {
                        self.errorMessage = nil
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingTagScenes = false
                    self.errorMessage = "Could not load tag scenes"
                }
            }
        }
    }
    
    func loadMoreTagScenes(tagId: String) {
        if !isLoadingTagScenes && hasMoreTagScenes {
            fetchTagScenes(tagId: tagId, sortBy: currentTagSceneSortOption, isInitialLoad: false)
        }
    }
    
    // MARK: - Galleries
    
    func fetchGalleries(sortBy: GallerySortOption = .dateDesc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentGalleryPage = 1
            galleries = []
            totalGalleries = 0
            isLoadingGalleries = true
            hasMoreGalleries = true
            currentGallerySortOption = sortBy
            currentGalleryFilter = filter
            currentGallerySearchQuery = searchQuery
        } else {
            isLoadingGalleries = true
        }
        
        errorMessage = nil
        let page = isInitialLoad ? 1 : currentGalleryPage + 1
        
        loadGalleriesPage(page: page, sortBy: currentGallerySortOption, searchQuery: currentGallerySearchQuery, isInitialLoad: isInitialLoad, filter: currentGalleryFilter)
    }
    
    private func loadGalleriesPage(page: Int, sortBy: GallerySortOption, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        var galleryFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                galleryFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter {
                galleryFilter = obj.value as? [String: Any] ?? [:]
            }
        }
        
        // Add search query to the filter
        if !searchQuery.isEmpty {
            galleryFilter["q"] = searchQuery
        }
        
        // Variables for GraphQL
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "gallery_filter": galleryFilter
        ]
        
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            print("❌ Error: Could not serialize Galleries request body")
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
            if let result = response?.data?.findGalleries {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.galleries = result.galleries
                        self.totalGalleries = result.count
                    } else {
                        self.galleries.append(contentsOf: result.galleries)
                    }
                    
                    self.hasMoreGalleries = result.galleries.count == 20 // Assuming per_page 20
                    self.currentGalleryPage = page
                    self.isLoadingGalleries = false
                    
                    if isInitialLoad {
                        self.errorMessage = nil
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGalleries = false
                    self.errorMessage = "Could not load galleries"
                }
            }
        }
    }
    
    func loadMoreGalleries(searchQuery: String = "") {
        if !isLoadingGalleries && hasMoreGalleries {
            // Use current state properties
            fetchGalleries(sortBy: currentGallerySortOption, searchQuery: currentGallerySearchQuery, isInitialLoad: false, filter: currentGalleryFilter)
        }
    }
    
    func fetchGalleryImages(galleryId: String, sortBy: ImageSortOption = .dateDesc, isInitialLoad: Bool = true) {
        print("🖼️ fetchGalleryImages called for gallery: \(galleryId), sortBy: \(sortBy.rawValue), isInitialLoad: \(isInitialLoad)")
        
        if isInitialLoad {
            currentGalleryImagePage = 1
            galleryImages = []
            totalGalleryImages = 0
            isLoadingGalleryImages = true
        } else {
            isLoadingGalleryImages = true
        }
        
        currentGalleryImageSortOption = sortBy
        let page = isInitialLoad ? 1 : currentGalleryImagePage + 1
        
        let query = GraphQLQueries.queryWithFragments("findImages")
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 40,
                "sort": sortBy.sortField,
                "direction": sortBy.direction
            ],
            "image_filter": [
                "galleries": [
                    "value": [galleryId],
                    "modifier": "INCLUDES"
                ]
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
            if let result = response?.data?.findImages {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.galleryImages = result.images
                        self.totalGalleryImages = result.count
                    } else {
                        self.galleryImages.append(contentsOf: result.images)
                    }
                    
                    self.hasMoreGalleryImages = result.images.count == 40
                    self.currentGalleryImagePage = page
                    self.isLoadingGalleryImages = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGalleryImages = false
                }
            }
        }
    }
    
    func loadMoreGalleryImages(galleryId: String) {
        if !isLoadingGalleryImages && hasMoreGalleryImages {
            fetchGalleryImages(galleryId: galleryId, sortBy: currentGalleryImageSortOption, isInitialLoad: false)
        }
    }
    
    func deleteImage(imageId: String, completion: @escaping (Bool) -> Void) {
        let mutation = """
        {
          "query": "mutation { imageDestroy(input: { id: \\\"\(imageId)\\\" }) }"
        }
        """
        
        performGraphQLQuery(query: mutation) { (response: GenericMutationResponse?) in
            if let _ = response?.data?["imageDestroy"] {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    func addScenePlay(sceneId: String) {
        let mutation = """
        {
          "query": "mutation SceneAddPlay($id: ID!) { sceneAddPlay(id: $id) { count } }",
          "variables": { "id": "\(sceneId)" }
        }
        """
        
        print("🎬 SCENE PLAY: Sending mutation for scene \(sceneId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result {
                print("✅ SCENE PLAY: Success for scene \(sceneId). Response: \(result)")
            } else {
                print("❌ SCENE PLAY: Failed for scene \(sceneId)")
            }
        }
    }
    
    func updateSceneResumeTime(sceneId: String, resumeTime: Double, completion: ((Bool) -> Void)? = nil) {
        let formattedTime = String(format: "%.2f", resumeTime)
        let mutation = """
        {
          "query": "mutation SceneSaveActivity($id: ID!, $resume_time: Float) { sceneSaveActivity(id: $id, resume_time: $resume_time, playDuration: 0) }",
          "variables": {
            "id": "\(sceneId)",
            "resume_time": \(formattedTime)
          }
        }
        """
        
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result {
                if let data = result["data"]?.value as? [String: Any],
                   let _ = data["sceneSaveActivity"] {
                    // Success
                    DispatchQueue.main.async {
                        completion?(true)
                    }
                } else if let errors = result["errors"] {
                    print("❌ RESUME SAVE ERROR for scene \(sceneId): \(errors)")
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            } else {
                print("❌ RESUME SAVE FAILED for scene \(sceneId)")
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }
    
    func fetchSceneDetails(sceneId: String, completion: @escaping (Scene?) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findScene")
        
        let variables: [String: Any] = ["id": sceneId]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SingleSceneResponse?) in
            DispatchQueue.main.async {
                completion(response?.data?.findScene)
            }
        }
    }
    
    private func performGraphQLMutationSilent(query: String, completion: @escaping ([String: StashJSONValue]?) -> Void) {
        guard let config = ServerConfigManager.shared.loadConfig() else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: URL(string: "\(config.baseURL)/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        request.httpBody = query.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([String: StashJSONValue].self, from: data)
                completion(decoded)
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private func performGraphQLQuery<T: Decodable>(query: String, completion: @escaping (T?) -> Void) {
        guard ServerConfigManager.shared.loadConfig()?.hasValidConfig == true else {
            errorMessage = "Server configuration is missing or incomplete"
            print("❌ No valid server configuration found")
            completion(nil)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Delegate to new GraphQLClient
        GraphQLClient.shared.execute(query: query) { [weak self] (result: Result<T, GraphQLNetworkError>) in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    completion(response)
                case .failure(let error):
                    print("📱 GraphQL Error: \(error)")
                    self?.handleNetworkError(error)
                    completion(nil)
                }
            }
        }
    }
    
    private func handleNetworkError(_ error: GraphQLNetworkError) {
        errorMessage = error.errorDescription
        serverStatus = "Verbindung fehlgeschlagen"
        
        // Keep legacy error notification for auth errors
        if case .unauthorized = error {
            NotificationCenter.default.post(name: NSNotification.Name("AuthError401"), object: nil)
        }
    }

    
    private func handleError(_ error: Error) {
        print("📱 StashDB Fehler: \(error)")
        
        if let urlError = error as? URLError {
            let urlContext = ServerConfigManager.shared.loadConfig()?.baseURL ?? "Unknown URL"
            switch urlError.code {
            case .notConnectedToInternet:
                errorMessage = "Keine Internetverbindung"
            case .cannotConnectToHost:
                errorMessage = "Server not reachable (\(urlContext)) - check IP/Port/SSL"
            case .timedOut:
                errorMessage = "Connection timed out (\(urlContext)) - is server running?"
            default:
                errorMessage = "Netzwerk-Fehler: \(urlError.localizedDescription) (\(urlContext))"
            }
        } else if let decodingError = error as? DecodingError {
            print("📱 Decoding Fehler: \(decodingError)")
            errorMessage = "Server-Antwort konnte nicht verarbeitet werden"
        } else {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        serverStatus = "Verbindung fehlgeschlagen"
    }
    
    // MARK: - Library Actions
    
    func triggerLibraryScan(completion: @escaping (Bool, String) -> Void) {
        let scanMutation = """
        {
          "query": "mutation { metadataScan(input: {}) }"
        }
        """
        
        performGraphQLQuery(query: scanMutation) { (response: GenericMutationResponse?) in
            if response != nil {
                completion(true, "Library scan started successfully!")
            } else {
                completion(false, "Failed to start library scan. Please check your server configuration.")
            }
        }
    }
    


// ... (In GenerateResponse struct)

struct GenerateData: Codable {
    let metadataGenerate: Int?
}
    
    // MARK: - Statistics
    // fetchStatistics already exists in file
    
    // MARK: - Mutations
    
    func toggleTagFavorite(tagId: String, favorite: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation TagUpdate($input: TagUpdateInput!) {
            tagUpdate(input: $input) { id favorite }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": tagId,
                "favorite": favorite
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: TagUpdateResponse?) in
            if let _ = response?.data?.tagUpdate {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func toggleSceneOrganized(sceneId: String, organized: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id organized }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": sceneId,
                "organized": organized
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            if let _ = response?.data?.sceneUpdate {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func togglePerformerFavorite(performerId: String, favorite: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation PerformerUpdate($input: PerformerUpdateInput!) {
            performerUpdate(input: $input) { id favorite }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": performerId,
                "favorite": favorite
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: PerformerUpdateResponse?) in
            if let _ = response?.data?.performerUpdate {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func toggleStudioFavorite(studioId: String, favorite: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation StudioUpdate($input: StudioUpdateInput!) {
            studioUpdate(input: $input) { id favorite }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": studioId,
                "favorite": favorite
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: StudioUpdateResponse?) in
            if let _ = response?.data?.studioUpdate {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}

// Generic mutation response for simple mutations
struct GenericMutationResponse: Codable {
    let data: [String: String]?
}



// MARK: - Response Models
struct ImageDestroyResponse: Codable {
    let data: ImageDestroyData?
}

struct ImageDestroyData: Codable {
    let imageDestroy: Bool
}

struct SceneUpdateResponse: Codable {
    let data: SceneUpdateData?
}
struct SceneUpdateData: Codable {
    let sceneUpdate: UpdatedItem?
}

struct PerformerUpdateResponse: Codable {
    let data: PerformerUpdateData?
}
struct PerformerUpdateData: Codable {
    let performerUpdate: UpdatedItem?
}

struct StudioUpdateResponse: Codable {
    let data: StudioUpdateData?
}
struct StudioUpdateData: Codable {
    let studioUpdate: UpdatedItem?
}

struct VersionResponse: Codable {
    let data: VersionData?
}

struct VersionData: Codable {
    let version: VersionInfo
}

struct VersionInfo: Codable {
    let version: String
}

struct StashStatisticsResponse: Codable {
    let data: StatisticsData?
}

struct StatisticsData: Codable {
    let stats: Statistics
}

struct Statistics: Codable {
    let sceneCount: Int
    let scenesSize: Int64
    let scenesDuration: Float
    let imageCount: Int
    let imagesSize: Int64
    let galleryCount: Int
    let performerCount: Int
    let studioCount: Int
    let movieCount: Int
    let tagCount: Int
    
    enum CodingKeys: String, CodingKey {
        case sceneCount = "scene_count"
        case scenesSize = "scenes_size"
        case scenesDuration = "scenes_duration"
        case imageCount = "image_count"
        case imagesSize = "images_size"
        case galleryCount = "gallery_count"
        case performerCount = "performer_count"
        case studioCount = "studio_count"
        case movieCount = "movie_count"
        case tagCount = "tag_count"
    }
}

// MARK: - Scenes Models (Simple version for better compatibility)
struct SimpleScenesResponse: Codable {
    let data: SimpleScenesData?
}

struct SimpleScenesData: Codable {
    let scenes: [Scene]
}

// Alternative response structure for older StashDB versions
struct AltScenesResponse: Codable {
    let data: AltScenesData?
}

struct AltScenesData: Codable {
    let findScenes: AltFindScenesResult?
}

struct AltFindScenesResult: Codable {
    let count: Int
    let scenes: [Scene]
}

struct SingleSceneResponse: Codable {
    let data: SingleSceneData?
}

struct SingleSceneData: Codable {
    let findScene: Scene?
}

struct Scene: Codable, Identifiable {
    let id: String
    let title: String?
    let details: String?
    let date: String?
    let duration: Double?
    let studio: SceneStudio?
    let performers: [ScenePerformer]
    let files: [SceneFile]?
    let tags: [Tag]?
    let galleries: [Gallery]?
    let organized: Bool?
    let resumeTime: Double?
    let playCount: Int?
    let rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    let paths: ScenePaths?
    
    enum CodingKeys: String, CodingKey {
        case id, title, details, date, duration, studio, performers, files, tags, galleries, organized, rating100, paths
        case resumeTime = "resume_time"
        case playCount = "play_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Compat for older views
    struct SceneTag: Codable, Identifiable {
        let id: String
        let name: String
    }
    
    // Total duration from files if not at top level
    var sceneDuration: Double? {
        if let d = duration, d > 0 { return d }
        // Fallback to max duration of files
        let fileDuration = files?.compactMap { $0.duration }.max() ?? 0
        return fileDuration > 0 ? fileDuration : nil
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        // Use path from API if available
        if let screenshotPath = paths?.screenshot, let url = URL(string: screenshotPath) {
             return url
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/scene/\(id)/screenshot")
    }

    // Computed property for stream URL
    var videoURL: URL? {
        // Use path from API if available
        if let streamPath = paths?.stream, let url = URL(string: streamPath) {
             return url
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/scene/\(id)/stream")
    }
    
    // Computed property for preview URL (video preview)
    var previewURL: URL? {
        // Use path from API if available
        if let previewPath = paths?.preview, let url = URL(string: previewPath) {
             return url
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/scene/\(id)/preview")
    }
    
    /// Creates a copy with updated resume time
    func withResumeTime(_ newResumeTime: Double) -> Scene {
        return Scene(
            id: id,
            title: title,
            details: details,
            date: date,
            duration: duration,
            studio: studio,
            performers: performers,
            files: files,
            tags: tags,
            galleries: galleries,
            organized: organized,
            resumeTime: newResumeTime,
            playCount: playCount,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths
        )
    }
}

struct ScenePaths: Codable {
    let screenshot: String?
    let preview: String?
    let stream: String?
    let webp: String?
    let vtt: String?
    let sprite: String?
    let funscript: String?
    let interactive_heatmap: String?
    let caption: String?
}

struct SceneFile: Codable, Identifiable {
    let id: String
    let path: String?
    let width: Int?
    let height: Int?
    let duration: Double?
    let videoCodec: String?
    let audioCodec: String?
    let bitRate: Int?
    let frameRate: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, path, width, height, duration
        case videoCodec = "video_codec"
        case audioCodec = "audio_codec"
        case bitRate = "bit_rate"
        case frameRate = "frame_rate"
    }
}

struct SceneStudio: Codable {
    let id: String
    let name: String
}

struct ScenePerformer: Codable, Identifiable {
    let id: String
    let name: String
    let sceneCount: Int?
    let galleryCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case sceneCount = "scene_count"
        case galleryCount = "gallery_count"
    }
}

// MARK: - Performers Models
struct PerformersResponse: Codable {
    let data: PerformersData?
}

struct PerformersData: Codable {
    let findPerformers: FindPerformersResult
}

struct FindPerformersResult: Codable {
    let count: Int
    let performers: [Performer]
}

struct FindPerformersByIdsResult: Codable {
    let performers: [Performer]
}

struct PerformersByIdsResponse: Codable {
    let data: PerformersByIdsData?
}

struct PerformersByIdsData: Codable {
    let findPerformers: FindPerformersByIdsResult
}

struct Performer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let disambiguation: String?
    let birthdate: String?
    let country: String?
    let imagePath: String?
    let sceneCount: Int
    let galleryCount: Int?
    let gender: String?
    let ethnicity: String?
    let height: Int? // height_cm
    let weight: Int?
    let measurements: String?
    let fakeTits: String?
    let careerLength: String?
    let tattoos: String?
    let piercings: String?
    let aliasList: [String]?
    let favorite: Bool?
    let rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, birthdate, country, gender, ethnicity, weight, measurements, tattoos, piercings, favorite, rating100
        case imagePath = "image_path"
        case sceneCount = "scene_count"
        case galleryCount = "gallery_count"
        case height = "height_cm"
        case fakeTits = "fake_tits"
        case careerLength = "career_length"
        case aliasList = "alias_list"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        // ... (existing implementation)
        print("🖼️ PERFORMER THUMBNAIL DEBUG for performer \(id):")
        
        // Get server config
        guard let config = ServerConfigManager.shared.loadConfig() else {
            print("🖼️ No server config")
            return nil
        }
        
        // Generate thumbnail URL using the provided format: /performer/[ID]/image
        let thumbnailURLString = "\(config.baseURL)/performer/\(id)/image"
        // print("🖼️ Generated performer thumbnail URL: \(thumbnailURLString)")
        
        return URL(string: thumbnailURLString)
    }
}

// MARK: - Studios Models
// ... (rest of file)

// Update queries in StashDBViewModel
extension StashDBViewModel {
    // ...
    // Note: I need to update the queries in other methods too, not just struct definition.
    // I will use replace_file_content on the queries specifically.
}


// MARK: - Studios Models
struct SingleStudioResponse: Codable {
    let data: SingleStudioData?
}
struct SingleStudioData: Codable {
    let findStudio: Studio?
}


// MARK: - Tag Models

struct SingleTagResponse: Codable {
    let data: SingleTagData?
}
struct SingleTagData: Codable {
    let findTag: Tag?
}

struct TagUpdateResponse: Codable {
    let data: TagUpdateData?
}

struct TagUpdateData: Codable {
    let tagUpdate: UpdatedItem?
}

// MARK: - Generic Updated Item
struct UpdatedItem: Codable {
    let id: String
    let favorite: Bool?
    let organized: Bool?
}

struct StudiosResponse: Codable {
    let data: StudiosData?
}

struct StudiosData: Codable {
    let findStudios: FindStudiosResult
}

struct FindStudiosResult: Codable {
    let count: Int
    let studios: [Studio]
}

struct Studio: Codable, Identifiable {
    let id: String
    let name: String
    let url: String?
    let sceneCount: Int
    let performerCount: Int?
    let galleryCount: Int?
    let details: String?
    let imagePath: String?
    let favorite: Bool?
    let rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, details, favorite, rating100
        case sceneCount = "scene_count"
        case performerCount = "performer_count"
        case galleryCount = "gallery_count"
        case imagePath = "image_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        print("🖼️ STUDIO THUMBNAIL DEBUG for studio \(id):")
        
        // Get server config
        guard let config = ServerConfigManager.shared.loadConfig() else {
            print("🖼️ No server config")
            return nil
        }
        
        // Generate thumbnail URL using the provided format: /studio/[ID]/image
        let thumbnailURLString = "\(config.baseURL)/studio/\(id)/image"
        print("🖼️ Generated studio thumbnail URL: \(thumbnailURLString)")
        
        return URL(string: thumbnailURLString)
    }
}

// MARK: - Tag Models
struct TagsResponse: Codable {
    let data: TagsData?
}

struct TagsData: Codable {
    let findTags: FindTagsResult
}

struct FindTagsResult: Codable {
    let count: Int
    let tags: [Tag]
}

struct Tag: Codable, Identifiable {
    let id: String
    let name: String
    let imagePath: String?
    let sceneCount: Int?
    let favorite: Bool?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, favorite
        case imagePath = "image_path"
        case sceneCount = "scene_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        // /tag/[ID]/image
        return URL(string: "\(config.baseURL)/tag/\(id)/image")
    }
}

// MARK: - Galleries Models
struct GalleriesResponse: Codable {
    let data: GalleriesData?
}

struct GalleriesData: Codable {
    let findGalleries: FindGalleriesResult
}

struct FindGalleriesResult: Codable {
    let count: Int
    let galleries: [Gallery]
}

struct Gallery: Codable, Identifiable {
    let id: String
    let title: String
    let date: String?
    let details: String?
    let imageCount: Int?
    let organized: Bool?
    let createdAt: String?
    let updatedAt: String?
    let studio: GalleryStudio?
    let performers: [GalleryPerformer]?
    let cover: GalleryCover?
    
    enum CodingKeys: String, CodingKey {
        case id, title, date, details, imageCount = "image_count", organized, createdAt = "created_at", updatedAt = "updated_at", studio, performers, cover
    }
    
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let thumbnailPath = cover?.paths.thumbnail else { return nil }
        
        // Check if the path is already an absolute URL
        if thumbnailPath.starts(with: "http://") || thumbnailPath.starts(with: "https://") {
            return URL(string: thumbnailPath)
        } else {
            // Relative path, prepend baseURL
            return URL(string: config.baseURL + thumbnailPath)
        }
    }
    
    var coverURL: URL? {
        thumbnailURL
    }
    
    var displayName: String {
        if !title.isEmpty { return title }
        return "Untitled Gallery"
    }
}

struct GalleryStudio: Codable {
    let id: String
    let name: String
}

struct GalleryPerformer: Codable {
    let id: String
    let name: String
}

struct GalleryCover: Codable {
    let id: String
    let paths: GalleryCoverPaths
}

struct GalleryCoverPaths: Codable {
    let thumbnail: String?
    let preview: String?
    let image: String?
}

// MARK: - Images Models
struct GalleryImagesResponse: Codable {
    let data: GalleryImagesData?
}

struct GalleryImagesData: Codable {
    let findImages: FindImagesResult
}

struct FindImagesResult: Codable {
    let count: Int
    let images: [StashImage]
}

struct StashImage: Codable, Identifiable {
    let id: String
    let title: String?
    let paths: ImagePaths?
    
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let thumbnailPath = paths?.thumbnail else { return nil }
        
        if thumbnailPath.starts(with: "http://") || thumbnailPath.starts(with: "https://") {
            return URL(string: thumbnailPath)
        } else {
            return URL(string: config.baseURL + thumbnailPath)
        }
    }
    
    var previewURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let previewPath = paths?.preview else { return nil }
        
        if previewPath.starts(with: "http://") || previewPath.starts(with: "https://") {
            return URL(string: previewPath)
        } else {
            return URL(string: config.baseURL + previewPath)
        }
    }
    
    var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let imagePath = paths?.image else { return nil }
        
        if imagePath.starts(with: "http://") || imagePath.starts(with: "https://") {
            return URL(string: imagePath)
        } else {
            return URL(string: config.baseURL + imagePath)
        }
    }
}

struct ImagePaths: Codable {
    let thumbnail: String?
    let preview: String?
    let image: String?
}

// MARK: - Filter Models


// MARK - Navigation

//
//  ViewExtension_Search.swift
//  Added here to ensure visibility
//





// MARK: - Download Manager

struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// Model for saved metadata
struct DownloadedScene: Codable, Identifiable {
    let id: String
    let title: String?
    let details: String?
    let date: String?
    let studioName: String?
    let performerNames: [String]
    let downloadDate: Date
    let localVideoPath: String
    let localThumbnailPath: String
    let duration: Double?
    
    var id_uuid: String { id }
}

struct ActiveDownload {
    let id: String
    let title: String
    var progress: Double
}

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloads: [DownloadedScene] = []
    @Published var activeDownloads: [String: ActiveDownload] = [:] // id: info
    
    private let downloadsFolder: URL
    private let metadataFile = "downloads_metadata.json"
    
    private var downloadTasks: [URLSessionDownloadTask: (String, URL)] = [:] // Task: (ID, TargetURL)
    private var progressHandlers: [String: (Double) -> Void] = [:]
    private var completionHandlers: [String: (Bool) -> Void] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.stashy.backgroundDownload")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // Download immediately
        return URLSession(configuration: config, delegate: self, delegateQueue: nil) // Delegate queue nil for background
    }()

    override private init() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        downloadsFolder = documents.appendingPathComponent("Downloads", isDirectory: true)
        
        if !fileManager.fileExists(atPath: downloadsFolder.path) {
            try? fileManager.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        }
        
        super.init()
        loadMetadata()
    }
    
    private func loadMetadata() {
        let file = downloadsFolder.appendingPathComponent(metadataFile)
        guard let data = try? Data(contentsOf: file) else { return }
        if let decoded = try? JSONDecoder().decode([DownloadedScene].self, from: data) {
            self.downloads = decoded
            cleanupIncompleteDownloads()
        }
    }
    
    private func cleanupIncompleteDownloads() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: downloadsFolder, includingPropertiesForKeys: nil) else { return }
        
        let completedIds = Set(downloads.map { $0.id })
        
        for item in contents {
            let itemName = item.lastPathComponent
            if itemName == metadataFile { continue }
            
            // If it's a folder and not in our metadata, it's garbage (incomplete or orphan)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                if !completedIds.contains(itemName) {
                    try? fileManager.removeItem(at: item)
                    print("🗑️ Removed incomplete/orphaned download folder: \(itemName)")
                }
            }
        }
    }
    
    private func saveMetadata() {
        let file = downloadsFolder.appendingPathComponent(metadataFile)
        if let data = try? JSONEncoder().encode(downloads) {
            try? data.write(to: file)
        }
    }
    
    func isDownloaded(id: String) -> Bool {
        return downloads.contains(where: { $0.id == id })
    }
    
    func downloadScene(_ scene: Scene) {
        let sceneId = scene.id
        guard !isDownloaded(id: sceneId), activeDownloads[sceneId] == nil else { return }
        
        let title = scene.title ?? "Unknown Scene"
        
        // Mark as started
        DispatchQueue.main.async {
            self.activeDownloads[sceneId] = ActiveDownload(id: sceneId, title: title, progress: 0.05)
        }
        
        let sceneFolder = downloadsFolder.appendingPathComponent(sceneId, isDirectory: true)
        try? FileManager.default.createDirectory(at: sceneFolder, withIntermediateDirectories: true)
        
        // Use a Group to track multiple downloads
        let dispatchGroup = DispatchGroup()
        var videoSuccess = false
        
        // 1. Download Thumbnail
        if let thumbURL = scene.thumbnailURL {
            dispatchGroup.enter()
            downloadFile(id: sceneId + "_thumb", from: thumbURL, to: sceneFolder.appendingPathComponent("thumbnail.jpg")) { _ in } completion: { success in
                dispatchGroup.leave()
            }
        }
        
        // 2. Download Video
        if let videoURL = scene.videoURL {
            dispatchGroup.enter()
            downloadFile(id: sceneId, from: videoURL, to: sceneFolder.appendingPathComponent("video.mp4")) { progress in
                DispatchQueue.main.async {
                    // Map video progress (0-1) to overall progress (0.1 - 1.0)
                    self.activeDownloads[sceneId]?.progress = 0.1 + (progress * 0.9)
                    self.objectWillChange.send() // Explicitly trigger UI update
                }
            } completion: { success in
                videoSuccess = success
                dispatchGroup.leave()
            }
        }
        
        // Handle completion
        dispatchGroup.notify(queue: .main) {
            if videoSuccess {
                let downloaded = DownloadedScene(
                    id: scene.id,
                    title: scene.title,
                    details: scene.details,
                    date: scene.date,
                    studioName: scene.studio?.name,
                    performerNames: scene.performers.map { $0.name },
                    downloadDate: Date(),
                    localVideoPath: "\(sceneId)/video.mp4",
                    localThumbnailPath: "\(sceneId)/thumbnail.jpg",
                    duration: scene.sceneDuration
                )
                
                self.downloads.append(downloaded)
                self.activeDownloads.removeValue(forKey: sceneId)
                self.saveMetadata()
            } else {
                try? FileManager.default.removeItem(at: sceneFolder)
                self.activeDownloads.removeValue(forKey: sceneId)
            }
        }
    }
    
    private func downloadFile(id: String, from url: URL, to destination: URL, progressHandler: @escaping (Double) -> Void, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        
        if let config = ServerConfigManager.shared.loadConfig(),
           let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        let task = session.downloadTask(with: request)
        downloadTasks[task] = (id, destination)
        progressHandlers[id] = progressHandler
        completionHandlers[id] = completion
        task.resume()
    }
    
    func deleteDownload(id: String) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads.remove(at: index)
            saveMetadata()
            
            let sceneFolder = downloadsFolder.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: sceneFolder)
        }
    }
    
    func getLocalVideoURL(for scene: DownloadedScene) -> URL {
        return downloadsFolder.appendingPathComponent(scene.localVideoPath)
    }
    
    func getLocalThumbnailURL(for scene: DownloadedScene) -> URL {
        return downloadsFolder.appendingPathComponent(scene.localThumbnailPath)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, destination) = downloadTasks[downloadTask] else { return }
        
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            completionHandlers[id]?(true)
        } catch {
            completionHandlers[id]?(false)
        }
        
        downloadTasks.removeValue(forKey: downloadTask)
        progressHandlers.removeValue(forKey: id)
        completionHandlers.removeValue(forKey: id)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, _) = downloadTasks[downloadTask] else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandlers[id]?(progress)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            guard let downloadTask = task as? URLSessionDownloadTask,
                  let (id, _) = downloadTasks[downloadTask] else { return }
            completionHandlers[id]?(false)
            
            downloadTasks.removeValue(forKey: downloadTask)
            progressHandlers.removeValue(forKey: id)
            completionHandlers.removeValue(forKey: id)
        }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
    }
}

// MARK: - Shared Video Components
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isFullscreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player, isFullscreen: $isFullscreen)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        playerViewController.delegate = context.coordinator
        playerViewController.showsPlaybackControls = true
        playerViewController.videoGravity = .resizeAspect
        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player != player {
            uiViewController.player = player
        }
    }
    
    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var player: AVPlayer
        @Binding var isFullscreen: Bool
        
        init(player: AVPlayer, isFullscreen: Binding<Bool>) {
            self.player = player
            _isFullscreen = isFullscreen
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            isFullscreen = true
        }
        
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { _ in
                // Standard behavior might pause, so we force play if we intend to keep playing
                self.player.play()
                
                // Delay setting isFullscreen to false to prevent race condition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isFullscreen = false
                }
            }
        }
    }
}



@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    @Published var hasError: Bool = false
    
    private let subscriptionId = "de.letzgo.stashy.premium.sub"
    private let lifetimeId = "de.letzgo.stashy.premium.lifetime"
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    init() {
        // Check local status or StoreKit status
        self.isPremium = UserDefaults.standard.bool(forKey: "isPremium")
        
        updateListenerTask = listenForTransactions()
        
        Task {
            await refreshPurchaseStatus()
            await fetchProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func fetchProducts() async {
        self.hasError = false
        do {
            let storeProducts = try await Product.products(for: [subscriptionId, lifetimeId])
            self.products = storeProducts.sorted(by: { $0.price < $1.price })
            print("Fetched \(self.products.count) products")
            if self.products.isEmpty {
                self.hasError = true
            }
        } catch {
            print("Failed product fetch: \(error)")
            self.hasError = true
        }
    }
    
    #if DEBUG
    func debugUnlock() {
        self.isPremium = true
        UserDefaults.standard.set(true, forKey: "isPremium")
    }
    #endif
    
    func buy(_ product: Product) async throws {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let _ = try checkVerified(verification)
            await refreshPurchaseStatus()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }
    
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshPurchaseStatus()
    }
    
    func refreshPurchaseStatus() async {
        var purchased = false
        
        // Iterate through all user's transactions
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.productID == subscriptionId || transaction.productID == lifetimeId {
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            purchased = true
                        }
                    } else {
                        // Lifetime
                        purchased = true
                    }
                }
            } catch {
                print("Failed verification: \(error)")
            }
        }
        
        self.isPremium = purchased
        UserDefaults.standard.set(purchased, forKey: "isPremium")
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let _ = try self.checkVerified(result)
                    await self.refreshPurchaseStatus()
                } catch {
                    print("Transaction update check failed: \(error)")
                }
            }
        }
    }
    
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}

struct PaywallView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var store = SubscriptionManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(appearanceManager.tintColor.opacity(0.1))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 44))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                        
                        Text("Become stashy VIP")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("Save your favorite scenes directly to your device and watch them anytime, even offline.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Options
                    VStack(spacing: 12) {
                        if store.products.isEmpty {
                            if store.hasError {
                                Text("Products could not be loaded.")
                                    .foregroundColor(.secondary)
                                
                                Button("Try Again") {
                                    Task { await store.fetchProducts() }
                                }
                                .buttonStyle(.bordered)
                                .tint(appearanceManager.tintColor)
                                
                                #if DEBUG
                                Button("Debug Unlock (Dev Only)") {
                                    store.debugUnlock()
                                    dismiss()
                                }
                                .padding(.top, 20)
                                .foregroundColor(.red)
                                #endif
                            } else {
                                ProgressView()
                                    .padding()
                                
                                #if DEBUG
                                Button("Debug Unlock (Dev Only)") {
                                    store.debugUnlock()
                                    dismiss()
                                }
                                .padding(.top, 40)
                                .foregroundColor(.red)
                                #endif
                            }
                        } else {
                            ForEach(store.products) { product in
                                Button {
                                    purchase(product)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.displayName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(product.displayPrice)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(appearanceManager.tintColor)
                                    }
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(appearanceManager.tintColor.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .disabled(isPurchasing)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Bottom Buttons
                    VStack(spacing: 16) {
                        Button {
                            Task {
                                await store.restorePurchases()
                                if store.isPremium {
                                    dismiss()
                                }
                            }
                        } label: {
                            Text("Restore Purchase")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Subscriptions will automatically renew unless canceled in your iTunes settings.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 20)
                }
                
                if isPurchasing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(appearanceManager.tintColor)
                }
            }
            .alert("Purchase Failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func purchase(_ product: Product) {
        isPurchasing = true
        Task {
            do {
                try await store.buy(product)
                if store.isPremium {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isPurchasing = false
        }
    }
}

