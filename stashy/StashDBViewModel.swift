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
import Foundation

// MARK: - App Colors

extension Color {
    static let appAccent = Color(red: 0x64/255.0, green: 0x4C/255.0, blue: 0x3D/255.0)
    #if os(tvOS)
    static let appBackground = Color(UIColor.separator).opacity(0.1)
    #else
    static let appBackground = Color(UIColor.systemGray6)
    #endif
    static let studioHeaderGray = Color(red: 44/255.0, green: 44/255.0, blue: 46/255.0)
}

// MARK: - Network Errors

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError
    case serverError(String)
    case networkError(Error)

    var localizedDescription: String {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .noData: return "No data received from server"
        case .decodingError: return "Error processing server response"
        case .serverError(let message): return "Server error: \(message)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
class StashDBViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var serverStatus: String = "Nicht verbunden"

    enum FilterMode: String, Codable {
        case scenes = "SCENES"
        case performers = "PERFORMERS"
        case studios = "STUDIOS"
        case galleries = "GALLERIES"
        case images = "IMAGES"
        case tags = "TAGS"
        case sceneMarkers = "SCENE_MARKERS"
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


    @Published var savedFilters: [String: SavedFilter] = [:]
    @Published var isLoadingSavedFilters = false
    private var isInitializing = false
    
    /// Main entry point for starting/refreshing a server connection
    func initializeServerConnection() {
        guard !isInitializing else { return }
        isInitializing = true
        
        print("🚀 Starting staggered server initialization...")
        
        // 1. First, fetch saved filters as they are needed for dashboard row queries
        fetchSavedFilters { [weak self] success in
            guard let self = self else { return }
            
            // 2. Once filters are done (or failed), fetch statistics
            self.fetchStatistics { [weak self] success in
                guard let self = self else { return }
                
                // 3. Mark initialization as done so rows can start loading
                // Fetching rows will happen automatically via HomeRowView's .onChange(of: savedFilters)
                // but we can also trigger a broad reload if needed.
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isInitializing = false
                    print("✅ Staggered initialization sequence completed")
                }
            }
        }
    }
    
    @objc private func handleServerChange() {
        Task {
            await GraphQLClient.shared.cancelAllRequests()
        }
        DispatchQueue.main.async {
            self.isLoading = true // Show loading immediately
            self.resetData()
            print("🔄 StashDBViewModel reset due to server change")
            self.initializeServerConnection()
        }
    }
    
    // Home Row Caching - prevents reload on view recreation
    @Published var homeRowScenes: [HomeRowType: [Scene]] = [:]
    @Published var homeRowLoadingState: [HomeRowType: Bool] = [:]

    // Connection Status
    @Published var isServerConnected: Bool = false

    // Data properties
    @Published var statistics: Statistics?
    @Published var scenes: [Scene] = []
    @Published var performers: [Performer] = []
    @Published var studios: [Studio] = []
    
    // Throttling states
    private var isFetchingFilters = false
    private var isFetchingHomeRows: Set<HomeRowType> = []

    // Pagination properties for scenes
    @Published var totalScenes: Int = 0
    @Published var isLoadingScenes = false
    @Published var isLoadingMoreScenes = false
    @Published var hasMoreScenes = true
    private var currentScenePage = 1
    private var currentSceneSortOption: SceneSortOption = .dateDesc
    private let scenesPerPage = 20
    @Published var currentSceneFilter: SavedFilter? = nil
    
    // Pagination properties for markers
    @Published var sceneMarkers: [SceneMarker] = []
    @Published var totalSceneMarkers: Int = 0
    @Published var isLoadingMarkers = false
    @Published var hasMoreMarkers = true
    private var currentMarkerPage = 1
    private var currentMarkerSortOption: SceneMarkerSortOption = .createdAtDesc
    private let markersPerPage = 20
    @Published var currentMarkerFilter: SavedFilter? = nil
    private var currentMarkerSearchQuery: String = ""

    func clearSearchResults() {
        scenes = []
        performers = []
    }
    
    // Pagination properties for performers
    @Published var totalPerformers: Int = 0
    @Published var isLoadingPerformers = false
    @Published var isLoadingMorePerformers = false
    @Published var hasMorePerformers = true
    @Published var currentPerformerFilter: SavedFilter? = nil
    private var currentPerformerPage = 1
    private let performersPerPage = 500
    private var currentPerformerSortOption: PerformerSortOption = .nameAsc

    // Pagination properties for studios
    @Published var totalStudios: Int = 0
    @Published var isLoadingStudios = false
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
        case dateDesc
        case dateAsc
        case ratingDesc
        case ratingAsc
        case createdAtDesc
        case createdAtAsc
        case updatedAtDesc
        case updatedAtAsc
        case random

        var displayName: String {
            switch self {
            case .titleAsc: return "Name (A-Z)"
            case .titleDesc: return "Name (Z-A)"
            case .dateDesc: return "Date (Newest)"
            case .dateAsc: return "Date (Oldest)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .createdAtDesc: return "Created (Newest)"
            case .createdAtAsc: return "Created (Oldest)"
            case .updatedAtDesc: return "Updated (Newest)"
            case .updatedAtAsc: return "Updated (Oldest)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .titleAsc, .dateAsc, .ratingAsc, .createdAtAsc, .updatedAtAsc: return "ASC"
            case .titleDesc, .dateDesc, .ratingDesc, .createdAtDesc, .updatedAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .titleAsc, .titleDesc: return "title"
            case .dateDesc, .dateAsc: return "date"
            case .ratingDesc, .ratingAsc: return "rating"
            case .createdAtDesc, .createdAtAsc: return "created_at"
            case .updatedAtDesc, .updatedAtAsc: return "updated_at"
            case .random: return "random"
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

    // Global Images
    @Published var allImages: [StashImage] = []
    @Published var totalImages: Int = 0
    @Published var isLoadingImages: Bool = false
    @Published var hasMoreImages: Bool = false
    @Published var currentImagePage: Int = 1
    @Published var currentImageFilter: SavedFilter? = nil
    var currentImageSortOption: ImageSortOption = .dateDesc

    // Image Sort Options
    enum ImageSortOption: String, CaseIterable {
        case titleAsc
        case titleDesc
        case dateDesc
        case dateAsc
        case ratingDesc
        case ratingAsc
        case createdAtDesc
        case createdAtAsc
        case updatedAtDesc
        case updatedAtAsc
        case random
        
        var displayName: String {
            switch self {
            case .titleAsc: return "Title (A-Z)"
            case .titleDesc: return "Title (Z-A)"
            case .dateDesc: return "Date (Newest)"
            case .dateAsc: return "Date (Oldest)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .createdAtDesc: return "Created (Newest)"
            case .createdAtAsc: return "Created (Oldest)"
            case .updatedAtDesc: return "Updated (Newest)"
            case .updatedAtAsc: return "Updated (Oldest)"
            case .random: return "Random"
            }
        }
        
        var direction: String {
            switch self {
            case .titleAsc, .dateAsc, .ratingAsc, .createdAtAsc, .updatedAtAsc: return "ASC"
            case .titleDesc, .dateDesc, .ratingDesc, .createdAtDesc, .updatedAtDesc, .random: return "DESC"
            }
        }
        
        var sortField: String {
            switch self {
            case .titleAsc, .titleDesc: return "title"
            case .dateDesc, .dateAsc: return "date"
            case .ratingDesc, .ratingAsc: return "rating"
            case .createdAtDesc, .createdAtAsc: return "created_at"
            case .updatedAtDesc, .updatedAtAsc: return "updated_at"
            case .random: return "random"
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
        case oCounterDesc
        case oCounterAsc
        case ratingDesc
        case ratingAsc

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
            case .oCounterDesc: return "Counter (High-Low)"
            case .oCounterAsc: return "Counter (Low-High)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .dateDesc, .createdAtDesc, .durationDesc, .lastPlayedAtDesc, .playCountDesc, .oCounterDesc, .ratingDesc, .random: return "DESC"
            case .dateAsc, .createdAtAsc, .titleAsc, .durationAsc, .lastPlayedAtAsc, .playCountAsc, .oCounterAsc, .ratingAsc: return "ASC"
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
            case .oCounterDesc, .oCounterAsc: return "o_counter"
            case .ratingDesc, .ratingAsc: return "rating"
            case .random: return "random"
            }
        }
    }

    // Marker sort options
    enum SceneMarkerSortOption: String, CaseIterable {
        case random
        case createdAtDesc
        case createdAtAsc
        case updatedAtDesc
        case updatedAtAsc
        case titleAsc
        case titleDesc
        case secondsAsc
        case secondsDesc

        var displayName: String {
            switch self {
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .titleAsc: return "Title (A-Z)"
            case .titleDesc: return "Title (Z-A)"
            case .secondsAsc: return "Time (Start)"
            case .secondsDesc: return "Time (End)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .createdAtDesc, .updatedAtDesc, .titleDesc, .secondsDesc, .random: return "DESC"
            case .createdAtAsc, .updatedAtAsc, .titleAsc, .secondsAsc: return "ASC"
            }
        }

        var sortField: String {
            switch self {
            case .createdAtDesc, .createdAtAsc: return "created_at"
            case .updatedAtDesc, .updatedAtAsc: return "updated_at"
            case .titleAsc, .titleDesc: return "title"
            case .secondsAsc, .secondsDesc: return "seconds"
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
    private var currentPerformerDetailFilter: SavedFilter? = nil

    // Studio scenes
    @Published var studioScenes: [Scene] = []
    @Published var totalStudioScenes: Int = 0
    @Published var isLoadingStudioScenes = false
    @Published var hasMoreStudioScenes = true
    private var currentStudioScenePage = 1
    private var currentStudioSceneSortOption: SceneSortOption = .dateDesc
    private var currentStudioDetailFilter: SavedFilter? = nil
    
    // Tag Scenes (Adding property here as it seems missing/implicit in other parts or I missed it)
    @Published var tagScenes: [Scene] = []
    @Published var totalTagScenes: Int = 0
    @Published var isLoadingTagScenes = false
    @Published var hasMoreTagScenes = true
    private var currentTagScenePage = 1
    private var currentTagSceneSortOption: SceneSortOption = .dateDesc
    private var currentTagDetailFilter: SavedFilter? = nil

    private var cancellables = Set<AnyCancellable>()
    
    // Reset all data and pagination states (e.g. on server switch)
    func resetData() {
        scenes = []
        performers = []
        studios = []
        galleries = []
        tags = []
        allImages = []
        
        homeRowScenes = [:]
        homeRowLoadingState = [:]
        isServerConnected = false
        isInitializing = false // Reset initialization guard
        isLoading = true // Start in loading state
        isLoadingSavedFilters = false // Reset filter loading state
        errorMessage = nil
        isFetchingStats = false
        isFetchingFilters = false
        isFetchingHomeRows.removeAll()
        
        performerGalleries = []
        studioGalleries = []
        performerScenes = []
        studioScenes = []
        tagScenes = []
        
        savedFilters = [:]
        statistics = nil
        
        totalScenes = 0
        totalPerformers = 0
        totalStudios = 0
        totalTags = 0
        totalGalleries = 0
        totalImages = 0
        totalPerformerScenes = 0
        totalStudioScenes = 0
        totalTagScenes = 0
        
        currentScenePage = 1
        currentPerformerPage = 1
        currentStudioPage = 1
        currentTagPage = 1
        currentGalleryPage = 1
        currentImagePage = 1
        
        hasMoreScenes = true
        hasMorePerformers = true
        hasMoreStudios = true
        hasMoreTags = true
        hasMoreGalleries = true
        hasMoreImages = true
        
        currentSceneSortOption = .dateDesc
        currentSceneFilter = nil
        
        currentMarkerPage = 1
        hasMoreMarkers = true
        currentMarkerSortOption = .createdAtDesc
        sceneMarkers = []
        
        currentPerformerSortOption = .nameAsc
        currentPerformerFilter = nil
        
        currentStudioSortOption = .nameAsc
        currentStudioFilter = nil
        
        currentGallerySortOption = .dateDesc
        currentGalleryFilter = nil
        
        currentImageSortOption = .dateDesc
        currentTagSortOption = .nameAsc
        
        currentPerformerGalleryPage = 1
        currentStudioGalleryPage = 1
        hasMorePerformerGalleries = true
        hasMoreStudioGalleries = true
        
        // Detail View Filters
        currentPerformerDetailFilter = nil
        currentStudioDetailFilter = nil
        currentTagDetailFilter = nil
        
        serverStatus = "Connecting..."
        errorMessage = nil
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

    /// Removes an image from all lists without reloading
    func removeImage(id: String) {
        allImages.removeAll { $0.id == id }
        totalImages = max(0, totalImages - 1)

        // Remove from gallery images
        galleryImages.removeAll { $0.id == id }
        totalGalleryImages = max(0, totalGalleryImages - 1)
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
                // Safe access using local copy 'rowScenes' instead of force unwrapping dictionary again
                var updated = rowScenes[index]
                updated = updated.withResumeTime(newResumeTime)
                homeRowScenes[rowType]?[index] = updated
            }
        }
    }

    /// Fetch all saved filters
    func fetchSavedFilters(completion: ((Bool) -> Void)? = nil) {
        if isFetchingFilters { 
            completion?(false)
            return 
        }
        isFetchingFilters = true
        isLoadingSavedFilters = true
        
        let query = """
        {
          "query": "query GetAllFilterDefinitions { findSavedFilters { id name mode filter object_filter } }"
        }
        """
        
        // Use execute with variables: nil to send the raw JSON body, same as performGraphQLQuery does
        GraphQLClient.shared.execute(query: query, variables: nil) { [weak self] (result: Result<SavedFiltersResponse, GraphQLNetworkError>) in
            guard let self = self else { return }
            Task { @MainActor in
                self.isLoadingSavedFilters = false
                self.isFetchingFilters = false
                switch result {
                case .success(let response):
                    if let findResult = response.data?.findSavedFilters {
                        self.savedFilters = Dictionary(findResult.map { ($0.id, $0) }, uniquingKeysWith: { (first, second) in second })
                        print("✅ Fetched \(findResult.count) saved filters")
                        completion?(true)
                    } else {
                        print("⚠️ Saved filters query successful but data is missing")
                        completion?(false)
                    }
                case .failure(let error):
                    print("❌ Error fetching saved filters: \(error.localizedDescription)")
                    self.errorMessage = "Failed to load filters: \(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
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
        request.timeoutInterval = 30 // Match GraphQLClient
        
        // Add API Key if available
        if let apiKey = customConfig.secureApiKey, !apiKey.isEmpty {
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
                         self?.serverStatus = "Not connected (Timeout)"
                         self?.isServerConnected = false
                         self?.errorMessage = "Connection timed out after 30 seconds."
                    } else {
                        print("❌ Connection Error: \(error.localizedDescription)")
                        self?.isServerConnected = false
                        self?.handleError(error)
                    }
                }
            } receiveValue: { [weak self] response in
                self?.isLoading = false
                let version = response.data?.version.version ?? "Unknown"
                print("📱 Version erhalten: \(version)")
                self?.serverStatus = "Connected - Version: \(version)"
                self?.isServerConnected = true
                self?.errorMessage = nil // Clear error on success
            }
            .store(in: &cancellables)
    }

    private var lastStatsFetch: Date?
    private var isFetchingStats = false

    func fetchStatistics(completion: ((Bool) -> Void)? = nil) {
        // Prevent redundant fetches within 3 seconds
        if isFetchingStats { 
            completion?(false)
            return 
        }
        if let last = lastStatsFetch, Date().timeIntervalSince(last) < 3.0 {
            completion?(true)
            return
        }
        
        isFetchingStats = true
        errorMessage = nil // Clear error when starting
        let statisticsQuery = """
        {
          "query": "{ stats { scene_count scenes_size scenes_duration image_count images_size gallery_count performer_count studio_count movie_count tag_count } }"
        }
        """
        
        performGraphQLQuery(query: statisticsQuery) { [weak self] (response: StashStatisticsResponse?) in
            guard let self = self else { return }
            self.isFetchingStats = false
            self.lastStatsFetch = Date()
            
            if let stats = response?.data?.stats {
                DispatchQueue.main.async {
                    self.statistics = stats
                    self.errorMessage = nil // Clear error on success
                    completion?(true)
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Statistics could not be loaded - possibly not supported"
                    completion?(false)
                }
            }
        }
    }
    
    // Search query state for scenes
    private var currentSceneSearchQuery: String = ""
    
    func fetchScenes(sortBy: SceneSortOption = .dateDesc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            // Reset pagination
            currentScenePage = 1
            scenes = [] // Clear scenes to show loading state
            totalScenes = 0
            isLoadingScenes = true
            hasMoreScenes = true
            currentSceneSortOption = sortBy
            currentSceneFilter = filter
            currentSceneSearchQuery = searchQuery
        } else {
            isLoadingScenes = true
        }

        errorMessage = nil
        let page = isInitialLoad ? 1 : currentScenePage + 1
        loadScenesPage(page: page, sortBy: currentSceneSortOption, searchQuery: currentSceneSearchQuery)
    }

    func loadMoreScenes() {
        guard !isLoadingMoreScenes && hasMoreScenes else { return }
        currentScenePage += 1
        loadScenesPage(page: currentScenePage, sortBy: currentSceneSortOption, searchQuery: currentSceneSearchQuery)
    }

    func fetchSceneMarkers(sortBy: SceneMarkerSortOption = .createdAtDesc, searchQuery: String = "", filter: SavedFilter? = nil) {
        currentMarkerPage = 1
        currentMarkerSortOption = sortBy
        currentMarkerSearchQuery = searchQuery
        currentMarkerFilter = filter
        hasMoreMarkers = true
        sceneMarkers = []
        isLoading = true // Set global loading for initial markers load
        
        loadMarkersPage(page: currentMarkerPage, sortBy: sortBy, searchQuery: searchQuery)
    }

    func loadMoreMarkers() {
        guard !isLoadingMarkers && hasMoreMarkers else { return }
        currentMarkerPage += 1
        loadMarkersPage(page: currentMarkerPage, sortBy: currentMarkerSortOption, searchQuery: currentMarkerSearchQuery)
    }

    private func loadMarkersPage(page: Int, sortBy: SceneMarkerSortOption, searchQuery: String = "") {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMarkers = true // Using isLoadingMarkers for pagination loading state
        }
        errorMessage = nil

        let query = GraphQLQueries.queryWithFragments("findSceneMarkers")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": markersPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !searchQuery.isEmpty {
            filterDict["q"] = searchQuery
        }
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        if let savedFilter = currentMarkerFilter {
            if let dict = savedFilter.filterDict {
                variables["scene_marker_filter"] = sanitizeFilter(dict, isMarker: true)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                variables["scene_marker_filter"] = sanitizeFilter(objDict, isMarker: true)
            }
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }

        performGraphQLQuery(query: bodyString) { (response: MarkersResponse?) in
            if let result = response?.data?.findSceneMarkers {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.sceneMarkers = result.scene_markers
                        self.totalSceneMarkers = result.count
                    } else {
                        // Deduplicate: Only add markers that aren't already in the list
                        let existingIds = Set(self.sceneMarkers.map { $0.id })
                        let newMarkers = result.scene_markers.filter { !existingIds.contains($0.id) }
                        self.sceneMarkers.append(contentsOf: newMarkers)
                    }
                    
                    self.hasMoreMarkers = result.scene_markers.count == self.markersPerPage
                    self.currentMarkerPage = page
                    self.isLoadingMarkers = false
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingMarkers = false
                    self.isLoading = false
                    self.errorMessage = "Could not load markers"
                }
            }
        }
    }

    private func loadScenesPage(page: Int, sortBy: SceneSortOption, searchQuery: String = "") {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoadingScenes = true
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
                // Also sanitize object_filter content to handle boolean flags and nested structures
                if let objDict = obj.value as? [String: Any] {
                    let sanitized = sanitizeFilter(objDict)
                    print("🔍 Object Filter sanitized: \(sanitized)")
                    variables["scene_filter"] = sanitized
                } else {
                    variables["scene_filter"] = obj.value
                }
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
                        // Deduplicate: Only add scenes that aren't already in the list
                        let existingIds = Set(self.scenes.map { $0.id })
                        let newScenes = scenesResult.scenes.filter { !existingIds.contains($0.id) }
                        self.scenes.append(contentsOf: newScenes)
                    }
                    
                    // Check if there are more pages
                    self.hasMoreScenes = scenesResult.scenes.count == self.scenesPerPage
                    
                    if isInitialLoad {
                        self.isLoadingScenes = false
                        self.errorMessage = nil // Success
                    } else {
                        self.isLoadingMoreScenes = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoadingScenes = false
                    } else {
                        self.isLoadingMoreScenes = false
                    }
                    // Keep error message processing if present
                }
            }
        }
    }
    
    
    
    // MARK: - Home Tab Support
    
    func fetchScenesForHomeRow(config: HomeRowConfig, limit: Int = 10, forceRefresh: Bool = false, completion: @escaping ([Scene]) -> Void) {
        let rowType = config.type
        
        // Return cached data immediately if available
        if !forceRefresh {
            if let cached = homeRowScenes[rowType], !cached.isEmpty {
                completion(cached)
                return
            }
        }
        
        // Already loading this row? Don't start another request
        if isFetchingHomeRows.contains(rowType) || homeRowLoadingState[rowType] == true {
            return
        }
        
        isFetchingHomeRows.insert(rowType)
        homeRowLoadingState[rowType] = true
        
        var sceneFilter: [String: Any] = [:]
        var sortField = "date"
        var sortDirection = "DESC"
        
        func setSort(_ option: SceneSortOption) {
            sortField = option.sortField
            sortDirection = option.direction
        }
        
        // Check for Default Dashboard Filter
        if let filterId = TabManager.shared.getDefaultFilterId(for: .dashboard),
           let savedFilter = savedFilters[filterId] {
            // Apply saved filter criteria
            if let criteria = savedFilter.filterDict {
                 // Clean up criteria to ensure we don't have conflicting sorts? 
                 // We use sanitizeFilter to handle compatibility (e.g. orientation without modifier)
                 let sanitized = sanitizeFilter(criteria)
                 
                 for (key, value) in sanitized {
                     if key == "sort" || key == "direction" { continue } // Skip sort from filter, use row logic
                     sceneFilter[key] = value
                 }
            }
        }
        
        switch config.type {
        case .lastPlayed:
            setSort(.lastPlayedAtDesc)
        case .lastAdded3Min:
            setSort(.createdAtDesc)
        case .newest3Min:
            setSort(.dateDesc)
        case .mostViewed3Min:
            setSort(.playCountDesc)
        case .topCounter3Min:
            setSort(.oCounterDesc)
        case .topRating3Min:
            setSort(.ratingDesc)
        case .random:
            setSort(.random)
        case .statistics:
            homeRowLoadingState[rowType] = false
            completion([])
            return
        }
        
        // Construct the query
        let perPage = limit
        
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
            isFetchingHomeRows.remove(rowType)
            completion([])
            return
        }
        
        performGraphQLQuery(query: bodyString) { [weak self] (response: AltScenesResponse?) in
            DispatchQueue.main.async {
                self?.homeRowLoadingState[rowType] = false
                self?.isFetchingHomeRows.remove(rowType)
                let scenes = response?.data?.findScenes?.scenes ?? []
                // Cache the result
                self?.homeRowScenes[rowType] = scenes
                completion(scenes)
            }
        }
    }
    
    func mergeFilterWithCriteria(filter: SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: FilterMode = .scenes) -> SavedFilter {
        var baseDict: [String: Any] = [:]
        
        // 1. Recover filter data
        if let filter = filter, let dict = filter.filterDict {
            baseDict = dict
        }
        
        // 2. Extract or create criteria array
        var criteria = baseDict["c"] as? [[String: Any]] ?? []
        
        // 3. Force Performer if selected
        if let performer = performer {
            criteria.removeAll { ($0["id"] as? String) == "performers" }
            criteria.append([
                "id": "performers",
                "value": [performer.id],
                "modifier": "INCLUDES_ALL"
            ])
        }

        // 4. Force Tags if selected
        if !tags.isEmpty {
            criteria.removeAll { ($0["id"] as? String) == "tags" }
            criteria.append([
                "id": "tags",
                "value": tags.map { $0.id },
                "modifier": "INCLUDES_ALL"
            ])
        }
        
        baseDict["c"] = criteria
        
        // 5. Serialize back to StashJSONValue
        let jsonValue: StashJSONValue? = {
            if let data = try? JSONSerialization.data(withJSONObject: baseDict),
               let decoded = try? JSONDecoder().decode(StashJSONValue.self, from: data) {
                return decoded
            }
            return nil
        }()
    
        return SavedFilter(
            id: filter?.id ?? "merged_temp",
            name: filter?.name ?? "Merged Filter",
            mode: mode,
            filter: nil,
            object_filter: jsonValue
        )
    }

    private func sanitizeFilter(_ dict: [String: Any], isMarker: Bool = false) -> [String: Any] {
        print("🔍 sanitizeFilter INPUT: \(dict)")
        var newDict = dict
        
        // 0. Convert "c" array (UI Format) to top-level keys (API Format)
        if let criteria = newDict["c"] as? [[String: Any]] {
            for item in criteria {
                if var key = item["id"] as? String {
                    var outputItem = item
                    // Remove UI-only keys that don't belong in any GraphQL criterion input
                    for uiKey in ["id", "type", "inputType", "criterionOption"] {
                        outputItem.removeValue(forKey: uiKey)
                    }
                    
                    // Map "rating" to "rating100" for GraphQL compatibility if needed
                    if key == "rating" {
                        key = "rating100"
                    }
                    
                    // For markers, move scene-specific criteria to nested scene_filter
                    if isMarker && (key == "orientation" || key == "duration" || key == "rating100" || key == "organized" || key == "performers" || key == "tags") {
                        var sceneFilter = newDict["scene_filter"] as? [String: Any] ?? [:]
                        sceneFilter[key] = outputItem
                        newDict["scene_filter"] = sceneFilter
                        continue
                    }
                    
                    newDict[key] = outputItem
                }
            }
            newDict.removeValue(forKey: "c")
        }
        
        // 1. Clean up known invalid top-level keys (UI-only metadata, not API fields)
        let invalidTopKeys = ["sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection"]
        for key in invalidTopKeys {
            newDict.removeValue(forKey: key)
        }
        
        // Marker specific: move top-level orientation/duration to scene_filter if they exist
        if isMarker {
            let sceneSpecificKeys = ["orientation", "duration", "rating100", "organized", "performers", "tags"]
            for key in sceneSpecificKeys {
                if let val = newDict[key] {
                    var sceneFilter = newDict["scene_filter"] as? [String: Any] ?? [:]
                    sceneFilter[key] = val
                    newDict["scene_filter"] = sceneFilter
                    newDict.removeValue(forKey: key)
                }
            }
        }
        
        // --- Define field sets based on GraphQL schema ---
        
        let nestedFilterKeys: Set<String> = [
            "performers_filter", "studios_filter", "tags_filter", "groups_filter",
            "galleries_filter", "scenes_filter", "images_filter", "markers_filter",
            "movies_filter", "files_filter", "folders_filter", "scene_filter",
            "AND", "OR", "NOT"
        ]
        
        let stringValueKeys: Set<String> = ["is_missing", "has_markers", "has_chapters"]
        
        let booleanFlags: Set<String> = [
            "organized", "interactive", "performer_favorite",
            "filter_favorites", "ignore_auto_tag", "favorite", "is_zip"
        ]
        
        let intFields: Set<String> = [
            "rating", "rating100", "play_count", "resume_time", "scene_count",
            "gallery_count", "performer_count", "tag_count", "duration", "framerate",
            "bitrate", "interactive_speed", "play_duration", "performer_age",
            "o_counter", "stash_id_count", "file_count", "id",
            "image_count", "marker_count", "child_count", "parent_count",
            "sub_group_count", "containing_group_count", "movie_count", "group_count",
            "studio_count", "height_cm", "weight", "birth_year", "age", "death_year"
        ]
        
        let floatFields: Set<String> = ["penis_length"]
        
        let dateFields: Set<String> = [
            "date", "birthdate", "death_date", "created_at", "updated_at",
            "last_played_at", "scene_date", "scene_created_at", "scene_updated_at",
            "mod_time"
        ]
        
        let multiSelectFields: Set<String> = [
            "performers", "studios", "tags", "galleries", "scenes", "groups",
            "movies", "performer_tags", "scene_tags", "parents", "children",
            "containing_groups", "sub_groups"
        ]
        
        // Standard valid keys for most criterion input types
        let stdKeys: Set<String> = ["value", "value2", "modifier"]
        let multiKeys: Set<String> = ["value", "modifier", "depth", "excludes"]
        
        // UI-only keys that can appear inside criterion dicts from the "c" array format
        let uiCriterionKeys: Set<String> = ["type", "inputType", "criterionOption"]
        
        // 2. Iterate over all keys to handle nested structures
        for (key, value) in newDict {
            // --- Nested sub-filter types ---
            if nestedFilterKeys.contains(key) {
                if let subFilterDict = value as? [String: Any] {
                    newDict[key] = sanitizeFilter(subFilterDict, isMarker: false)
                }
                continue
            }
            
            if var subDict = value as? [String: Any] {
                // Strip UI-only keys from criterion objects
                for uiKey in uiCriterionKeys {
                    subDict.removeValue(forKey: uiKey)
                }
                
                // --- String value keys (has_markers, is_missing, has_chapters) ---
                if stringValueKeys.contains(key) {
                    if let val = subDict["value"] as? Bool {
                        newDict[key] = val ? "true" : "false"
                    } else if let valStr = subDict["value"] as? String {
                        newDict[key] = valStr
                    }
                    continue
                }
                
                // --- Duplicated: DuplicationCriterionInput ---
                if key == "duplicated" {
                    var result: [String: Any] = [:]
                    for boolKey in ["duplicated", "phash", "url", "stash_id", "title"] {
                        if let val = subDict[boolKey] as? Bool { result[boolKey] = val }
                        else if let s = subDict[boolKey] as? String { result[boolKey] = (s == "true") }
                    }
                    if let dist = subDict["distance"] as? Int { result["distance"] = dist }
                    if result.isEmpty {
                        if let val = subDict["value"] as? Bool { result["duplicated"] = val }
                        else if let s = subDict["value"] as? String { result["duplicated"] = (s == "true") }
                    }
                    newDict[key] = result
                    continue
                }
                
                // --- Boolean flags ---
                if booleanFlags.contains(key) {
                    if let val = subDict["value"] as? Bool { newDict[key] = val }
                    else if let s = subDict["value"] as? String { newDict[key] = (s == "true") }
                    continue
                }
                
                // --- Universal value unwrapping ---
                // Stash UI stores values as {"value": {"value": X}} or {"value": {"id": X}}
                if let valueDict = subDict["value"] as? [String: Any] {
                    if let inner = valueDict["value"] { subDict["value"] = inner }
                    else if let inner = valueDict["id"] { subDict["value"] = inner }
                    else if let items = valueDict["items"] as? [Any] { subDict["value"] = items }
                }
                if let vd2 = subDict["value2"] as? [String: Any], let iv2 = vd2["value"] {
                    subDict["value2"] = iv2
                }
                
                // --- Multi-Select / ID Arrays ---
                if multiSelectFields.contains(key) {
                    if let valArray = subDict["value"] as? [Any] {
                        subDict["value"] = valArray.compactMap { item -> String? in
                            if let s = item as? String { return s }
                            if let i = item as? Int { return String(i) }
                            if let obj = item as? [String: Any] {
                                if let id = obj["id"] as? String { return id }
                                if let id = obj["id"] as? Int { return String(id) }
                            }
                            return nil
                        }
                    }
                    if let exArr = subDict["excludes"] as? [Any] {
                        subDict["excludes"] = exArr.compactMap { item -> String? in
                            if let s = item as? String { return s }
                            if let i = item as? Int { return String(i) }
                            if let obj = item as? [String: Any] {
                                if let id = obj["id"] as? String { return id }
                                if let id = obj["id"] as? Int { return String(id) }
                            }
                            return nil
                        }
                    }
                    for k in subDict.keys where !multiKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Integer criterion fields ---
                if intFields.contains(key) || (key.contains("count") && !floatFields.contains(key)) {
                    func castInt(_ val: Any?) -> Any? {
                        if let i = val as? Int { return i }
                        if let d = val as? Double { return Int(d) }
                        if let s = val as? String, let i = Int(s) { return i }
                        return val
                    }
                    if let v = subDict["value"] { subDict["value"] = castInt(v) }
                    if let v = subDict["value2"] { subDict["value2"] = castInt(v) }
                    for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Float criterion fields ---
                if floatFields.contains(key) {
                    func castFloat(_ val: Any?) -> Any? {
                        if let d = val as? Double { return d }
                        if let i = val as? Int { return Double(i) }
                        if let s = val as? String, let d = Double(s) { return d }
                        return val
                    }
                    if let v = subDict["value"] { subDict["value"] = castFloat(v) }
                    if let v = subDict["value2"] { subDict["value2"] = castFloat(v) }
                    for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Date/Timestamp fields ---
                if dateFields.contains(key) {
                    for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Orientation: OrientationCriterionInput { value: [OrientationEnum!]! } (NO modifier) ---
                if key == "orientation" {
                    if let arr = subDict["value"] as? [Any] {
                        subDict["value"] = arr.compactMap { item -> String? in
                            if let s = item as? String { return s.uppercased() }
                            if let obj = item as? [String: Any], let id = obj["id"] as? String { return id.uppercased() }
                            return nil
                        }
                    } else if let s = subDict["value"] as? String {
                        subDict["value"] = [s.uppercased()]
                    }
                    // OrientationCriterionInput only has "value", no modifier
                    for k in subDict.keys where k != "value" { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Resolution: ResolutionCriterionInput { value: ResolutionEnum!, modifier } ---
                if key == "resolution" || key == "average_resolution" {
                    if let s = subDict["value"] as? String { subDict["value"] = s.uppercased() }
                    for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Gender: GenderCriterionInput { value: GenderEnum, value_list: [GenderEnum!], modifier } ---
                if key == "gender" {
                    // value can arrive as a string ("MALE") or an array (["Male"])
                    if let s = subDict["value"] as? String {
                        subDict["value"] = s.uppercased()
                    } else if let arr = subDict["value"] as? [Any] {
                        // Array of gender values → move to value_list, remove value
                        let uppercased = arr.compactMap { item -> String? in
                            if let s = item as? String { return s.uppercased() }
                            if let obj = item as? [String: Any], let id = obj["id"] as? String { return id.uppercased() }
                            return nil
                        }
                        subDict["value_list"] = uppercased
                        subDict.removeValue(forKey: "value")
                    }
                    if let vl = subDict["value_list"] as? [Any] {
                        subDict["value_list"] = vl.compactMap { ($0 as? String)?.uppercased() }
                    }
                    let genderKeys: Set<String> = ["value", "value_list", "modifier"]
                    for k in subDict.keys where !genderKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Circumcised: CircumcisionCriterionInput { value: [CircumisedEnum!], modifier } ---
                if key == "circumcised" {
                    if let arr = subDict["value"] as? [Any] {
                        subDict["value"] = arr.compactMap { item -> String? in
                            if let s = item as? String { return s.uppercased() }
                            if let obj = item as? [String: Any], let id = obj["id"] as? String { return id.uppercased() }
                            return nil
                        }
                    } else if let s = subDict["value"] as? String {
                        subDict["value"] = [s.uppercased()]
                    }
                    for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- StashID criterion types ---
                if key == "stash_id_endpoint" {
                    let valid: Set<String> = ["endpoint", "stash_id", "modifier"]
                    for k in subDict.keys where !valid.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                if key == "stash_ids_endpoint" {
                    let valid: Set<String> = ["endpoint", "stash_ids", "modifier"]
                    for k in subDict.keys where !valid.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- PhashDistance ---
                if key == "phash_distance" {
                    let valid: Set<String> = ["value", "modifier", "distance"]
                    for k in subDict.keys where !valid.contains(k) { subDict.removeValue(forKey: k) }
                    newDict[key] = subDict
                    continue
                }
                
                // --- Default: StringCriterionInput { value, modifier } and other types ---
                for k in subDict.keys where !stdKeys.contains(k) { subDict.removeValue(forKey: k) }
                newDict[key] = subDict
                
            } else if key == "orientation", let valArray = value as? [String] {
                // orientation as flat string array
                newDict[key] = ["value": valArray.map { $0.uppercased() }]
            }
        }
        
        print("🔍 sanitizeFilter OUTPUT: \(newDict)")
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
        // Sort Logic
        let sortField = sortBy.sortField
        let sortDirection = sortBy.direction
        
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
        // Sort Logic
        let sortField = sortBy.sortField
        let sortDirection = sortBy.direction
        
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
    
    func fetchPerformerScenes(performerId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentPerformerScenePage = 1
            currentPerformerSceneSortOption = sortBy
            currentPerformerDetailFilter = filter
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
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentPerformerDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        sceneFilter["performers"] = [
            "modifier": "INCLUDES",
            "value": [performerId]
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
    
    func fetchStudioScenes(studioId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentStudioScenePage = 1
            currentStudioSceneSortOption = sortBy
            currentStudioDetailFilter = filter
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
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentStudioDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        sceneFilter["studios"] = [
            "modifier": "INCLUDES",
            "value": [studioId]
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
    
    func fetchPerformers(sortBy: PerformerSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentPerformerPage = 1
            performers = []
            totalPerformers = 0
            isLoadingPerformers = true
            hasMorePerformers = true
            currentPerformerSortOption = sortBy
            currentPerformerFilter = filter
            currentPerformerSearchQuery = searchQuery
        } else {
            isLoadingPerformers = true
        }
        
        loadPerformersPage(page: isInitialLoad ? 1 : currentPerformerPage + 1, sortBy: currentPerformerSortOption, searchQuery: currentPerformerSearchQuery)
    }
    
    func loadMorePerformers() {
        guard !isLoadingMorePerformers && hasMorePerformers else { return }
        currentPerformerPage += 1
        loadPerformersPage(page: currentPerformerPage, sortBy: currentPerformerSortOption, searchQuery: currentPerformerSearchQuery)
    }
    
    private func loadPerformersPage(page: Int, sortBy: PerformerSortOption, searchQuery: String = "") {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoadingPerformers = true
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
                print("🔍 PERFORMER filterDict raw: \(dict)")
                print("🔍 PERFORMER filterDict sanitized: \(sanitized)")
                variables["performer_filter"] = sanitized
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                print("🔍 PERFORMER object_filter raw: \(objDict)")
                let sanitized = sanitizeFilter(objDict)
                print("🔍 PERFORMER object_filter sanitized: \(sanitized)")
                variables["performer_filter"] = sanitized
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
                        self.isLoadingPerformers = false
                    } else {
                        self.isLoadingMorePerformers = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingPerformers = false
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
    
    func fetchStudios(sortBy: StudioSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            // Reset pagination
            currentStudioPage = 1
            currentStudioSortOption = sortBy
            currentStudioSearchQuery = searchQuery
            currentStudioFilter = filter
            hasMoreStudios = true
            studios = []
            isLoadingStudios = true
        } else {
            isLoadingStudios = true
        }
        
        loadStudiosPage(page: isInitialLoad ? 1 : currentStudioPage + 1, sortBy: currentStudioSortOption, searchQuery: currentStudioSearchQuery, filter: currentStudioFilter)
    }
    
    func loadMoreStudios() {
        guard !isLoadingMoreStudios && hasMoreStudios else { return }
        currentStudioPage += 1
        loadStudiosPage(page: currentStudioPage, sortBy: currentStudioSortOption, searchQuery: currentStudioSearchQuery, filter: currentStudioFilter)
    }
    
    private func loadStudiosPage(page: Int, sortBy: StudioSortOption, searchQuery: String = "", filter: SavedFilter? = nil) {
        let isInitialLoad = (page == 1)
        if isInitialLoad {
            isLoadingStudios = true
        } else {
            isLoadingMoreStudios = true
        }
        errorMessage = nil
        
        var studioFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                studioFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                studioFilter = sanitizeFilter(objDict)
            }
        }
        
        // Variables for GraphQL - search query goes in FindFilterType, not StudioFilterType
        var filterParams: [String: Any] = [
            "page": page,
            "per_page": studiosPerPage,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        // Add search query to FindFilterType (not studio_filter)
        if !searchQuery.isEmpty {
            filterParams["q"] = searchQuery
        }
        
        let variables: [String: Any] = [
            "filter": filterParams,
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
                        self.isLoadingStudios = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingMoreStudios = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.isLoadingStudios = false
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
    @Published var isLoadingTags = false
    @Published var isLoadingMoreTags = false
    @Published var hasMoreTags = true
    @Published var currentTagFilter: SavedFilter? = nil
    private var currentTagPage = 1
    private let tagsPerPage = 500
    private var currentTagSortOption: TagSortOption = .nameAsc
    private var currentTagSearchQuery: String = ""
    
    
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
            isLoadingTags = true
        } else {
            isLoadingMoreTags = true
        }
        
        var tagFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                tagFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                tagFilter = sanitizeFilter(objDict)
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
                        self.isLoadingTags = false
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.isLoadingMoreTags = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingTags = false
                    self.isLoadingMoreTags = false
                }
            }
        }
    }
    
    func fetchTagScenes(tagId: String, sortBy: SceneSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        if isInitialLoad {
            currentTagScenePage = 1
            currentTagSceneSortOption = sortBy
            currentTagDetailFilter = filter
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
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentTagDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        sceneFilter["tags"] = [
            "modifier": "INCLUDES",
            "value": [tagId]
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
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                galleryFilter = sanitizeFilter(objDict)
            }
        }
        
        // Variables for GraphQL - search query goes in FindFilterType, not GalleryFilterType
        var filterParams: [String: Any] = [
            "page": page,
            "per_page": 20,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        // Add search query to FindFilterType (not gallery_filter)
        if !searchQuery.isEmpty {
            filterParams["q"] = searchQuery
        }
        
        let variables: [String: Any] = [
            "filter": filterParams,
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
    
    func fetchImages(sortBy: ImageSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil) {
        print("🖼️ fetchImages called, sortBy: \(sortBy.rawValue), isInitialLoad: \(isInitialLoad)")
        
        if isInitialLoad {
            currentImagePage = 1
            allImages = []
            totalImages = 0
            isLoadingImages = true
            currentImageFilter = filter
        } else {
            isLoadingImages = true
        }
        
        currentImageSortOption = sortBy
        let page = isInitialLoad ? 1 : currentImagePage + 1
        
        let query = GraphQLQueries.queryWithFragments("findImages")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": 40,
            "sort": sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        if let savedFilter = currentImageFilter {
            if let dict = savedFilter.filterDict {
                let sanitized = sanitizeFilter(dict)
                print("🔍 Image Filter sanitized: \(sanitized)")
                variables["image_filter"] = sanitized
            } else if let obj = savedFilter.object_filter {
                if let objDict = obj.value as? [String: Any] {
                    let sanitized = sanitizeFilter(objDict)
                    print("🔍 Image Object Filter sanitized: \(sanitized)")
                    variables["image_filter"] = sanitized
                } else {
                    variables["image_filter"] = obj.value
                }
            }
        }
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
            if let result = response?.data?.findImages {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.allImages = result.images
                        self.totalImages = result.count
                    } else {
                        self.allImages.append(contentsOf: result.images)
                    }
                    
                    self.hasMoreImages = result.images.count == 40
                    self.currentImagePage = page
                    self.isLoadingImages = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingImages = false
                }
            }
        }
    }
    
    func loadMoreImages() {
        if !isLoadingImages && hasMoreImages {
            fetchImages(sortBy: currentImageSortOption, isInitialLoad: false, filter: currentImageFilter)
        }
    }
    
    // MARK: - Clips Logic
    
    @Published var clips: [StashImage] = []
    @Published var totalClips: Int = 0
    @Published var isLoadingClips = false
    @Published var hasMoreClips = true
    private var currentClipsPage = 1
    private var currentClipSortOption: ImageSortOption = .dateDesc
    private var currentClipFilter: SavedFilter?
    
    func fetchClips(sortBy: ImageSortOption = .dateDesc, filter: SavedFilter? = nil, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentClipsPage = 1
            clips = []
            totalClips = 0
            isLoadingClips = true
            hasMoreClips = true
            currentClipSortOption = sortBy
            currentClipFilter = filter
            isLoading = true // Set global loading for initial clips load
        } else {
            isLoadingClips = true
        }
        
        let page = isInitialLoad ? 1 : currentClipsPage + 1
        
        // Filter for video-like extensions
        // Regex: .*\.(mp4|gif|mov|webm|m4v)$ (case insensitive usually requires flags, but Stash regex is Go-flavor? or PCRE?)
        // Stash uses Go regex. (?i) is case insensitive.
        let videoRegex = "(?i).*\\.(mp4|gif|mov|webm|m4v|mkv)$"
        
        let query = GraphQLQueries.queryWithFragments("findImages")
        
        // Build image filter, starting with video regex
        var imageFilter: [String: Any] = [
            "path": [
                "value": videoRegex,
                "modifier": "MATCHES_REGEX"
            ]
        ]
        
        // Merge with saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                let sanitized = sanitizeFilter(dict)
                for (key, value) in sanitized {
                    if key != "path" { // Don't override our video filter
                        imageFilter[key] = value
                    }
                }
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                let sanitized = sanitizeFilter(objDict)
                for (key, value) in sanitized {
                    if key != "path" {
                        imageFilter[key] = value
                    }
                }
            }
        }
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": currentClipSortOption.sortField,
                "direction": currentClipSortOption.direction
            ],
            "image_filter": imageFilter
        ]
        
        print("🔍 fetchClips: Variables = \(variables)")
        
        guard let dataRequest = ["query": query, "variables": variables] as [String: Any]?,
              let bodyData = try? JSONSerialization.data(withJSONObject: dataRequest),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        print("🔍 fetchClips: Raw Body = \(bodyString)")
        
        performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
            if let result = response?.data?.findImages {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.clips = result.images
                        self.totalClips = result.count
                    } else {
                        // Deduplicate: Only add clips that aren't already in the list
                        let existingIds = Set(self.clips.map { $0.id })
                        let newClips = result.images.filter { !existingIds.contains($0.id) }
                        self.clips.append(contentsOf: newClips)
                    }
                    
                    self.hasMoreClips = result.images.count == 20
                    self.currentClipsPage = page
                    self.isLoadingClips = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingClips = false
                }
            }
        }
    }
    
    func loadMoreClips() {
        if !isLoadingClips && hasMoreClips {
            fetchClips(sortBy: currentClipSortOption, filter: currentClipFilter, isInitialLoad: false)
        }
    }

    func deleteImage(imageId: String, completion: @escaping (Bool) -> Void) {
        let mutation = """
        {
          "query": "mutation { imageDestroy(input: { id: \\\"\(imageId)\\\" }) }"
        }
        """

        print("🗑️ IMAGE DELETE: Deleting image \(imageId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result,
               let data = result["data"]?.value as? [String: Any],
               let destroyed = data["imageDestroy"] {
                print("✅ IMAGE DELETE: Success for image \(imageId). Response: \(destroyed)")

                // Post notification so other views can update
                NotificationCenter.default.post(
                    name: NSNotification.Name("ImageDeleted"),
                    object: nil,
                    userInfo: ["imageId": imageId]
                )

                completion(true)
            } else {
                print("❌ IMAGE DELETE: Failed for image \(imageId)")
                completion(false)
            }
        }
    }
    func addScenePlay(sceneId: String, completion: ((Int?) -> Void)? = nil) {
        let mutation = """
        mutation SceneAddPlay($id: ID!, $times: [Timestamp!]) {
          sceneAddPlay(id: $id, times: $times) {
            count
            history
          }
        }
        """

        let variables: [String: Any] = [
            "id": sceneId,
            "times": []
        ]

        print("🎬 SCENE PLAY: Sending mutation for scene \(sceneId)")
        Task {
            do {
                let result = try await GraphQLClient.shared.performMutation(mutation: mutation, variables: variables)
                if let data = result["data"]?.value as? [String: Any],
                   let payload = data["sceneAddPlay"] as? [String: Any] {
                    if let newCount = payload["count"] as? Int {
                        print("✅ SCENE PLAY: Success for scene \(sceneId). New count: \(newCount)")
                        await MainActor.run { completion?(newCount) }
                        return
                    } else if let newCount = payload["count"] as? Double {
                        let count = Int(newCount)
                        print("✅ SCENE PLAY: Success for scene \(sceneId). New count: \(count)")
                        await MainActor.run { completion?(count) }
                        return
                    }
                }

                if let errors = result["errors"]?.value {
                    print("❌ SCENE PLAY: Failed for scene \(sceneId). Errors: \(errors)")
                } else {
                    print("❌ SCENE PLAY: Failed for scene \(sceneId)")
                }
                await MainActor.run { completion?(nil) }
            } catch {
                print("❌ SCENE PLAY: Failed for scene \(sceneId). Error: \(error)")
                await MainActor.run { completion?(nil) }
            }
        }
    }
    
    func incrementOCounter(sceneId: String, completion: ((Int?) -> Void)? = nil) {
        let mutation = """
        {
          "query": "mutation SceneIncrementO($id: ID!) { sceneIncrementO(id: $id) }",
          "variables": { "id": "\(sceneId)" }
        }
        """
        
        print("🎬 SCENE O: Sending increment mutation for scene \(sceneId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result,
               let data = result["data"]?.value as? [String: Any],
               let count = data["sceneIncrementO"] as? Int {
                print("✅ SCENE O: Success for scene \(sceneId). New count: \(count)")
                DispatchQueue.main.async {
                    completion?(count)
                }
            } else {
                print("❌ SCENE O: Failed for scene \(sceneId)")
                DispatchQueue.main.async {
                    completion?(nil)
                }
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
        
        guard let url = URL(string: "\(config.baseURL)/graphql") else {
            print("❌ Invalid URL in performGraphQLMutationSilent: \(config.baseURL)")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        request.httpBody = query.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                Task { @MainActor in completion(nil) }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([String: StashJSONValue].self, from: data)
                Task { @MainActor in completion(decoded) }
            } catch {
                Task { @MainActor in completion(nil) }
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
        serverStatus = "Connection failed"
        
        // Keep legacy error notification for auth errors
        if case .unauthorized = error {
            NotificationCenter.default.post(name: NSNotification.Name("AuthError401"), object: nil)
        }
    }

    
    private func handleError(_ error: Error) {
        print("📱 StashDB Error: \(error)")
        
        if let urlError = error as? URLError {
            let urlContext = ServerConfigManager.shared.loadConfig()?.baseURL ?? "Unknown URL"
            switch urlError.code {
            case .notConnectedToInternet:
                errorMessage = "No internet connection"
            case .cannotConnectToHost:
                errorMessage = "Server not reachable (\(urlContext)) - check IP/Port/SSL"
            case .timedOut:
                errorMessage = "Connection timed out (\(urlContext)) - is server running?"
            default:
                errorMessage = "Network Error: \(urlError.localizedDescription) (\(urlContext))"
            }
        } else if let decodingError = error as? DecodingError {
            print("📱 Decoding Error: \(decodingError)")
            errorMessage = "Could not process server response"
        } else {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        serverStatus = "Connection failed"
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
    
    func showScene(sceneId: String) {
        // Implement logic to show scene details or play it
        print("Show scene not implemented")
    }

    func updateImageRating(imageId: String, rating100: Int?, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation ImageUpdate($input: ImageUpdateInput!) {
            imageUpdate(input: $input) { id rating100 }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": imageId,
                "rating100": rating100 as Any
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: ImageUpdateResponse?) in
            if let _ = response?.data?.imageUpdate {
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    func incrementImageOCounter(imageId: String, completion: ((Int?) -> Void)? = nil) {
        let mutation = """
        {
          "query": "mutation ImageIncrementO($id: ID!) { imageIncrementO(id: $id) }",
          "variables": { "id": "\(imageId)" }
        }
        """
        
        print("📷 IMAGE O: Sending increment mutation for image \(imageId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result,
               let data = result["data"]?.value as? [String: Any],
               let count = data["imageIncrementO"] as? Int {
                print("✅ IMAGE O: Success for image \(imageId). New count: \(count)")
                DispatchQueue.main.async {
                    completion?(count)
                }
            } else {
                print("❌ IMAGE O: Failed for image \(imageId)")
                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }
    
    func updateImageOCounter(imageId: String, oCounter: Int?, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation ImageUpdate($input: ImageUpdateInput!) {
            imageUpdate(input: $input) { id o_counter }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": imageId,
                "o_counter": oCounter as Any
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: ImageUpdateResponse?) in
            if let _ = response?.data?.imageUpdate {
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
    
    func updateSceneRating(sceneId: String, rating100: Int?, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation SceneUpdate($input: SceneUpdateInput!) {
            sceneUpdate(input: $input) { id rating100 }
        }
        """
        
        let variables: [String: Any] = [
            "input": [
                "id": sceneId,
                "rating100": rating100 as Any
            ]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            if let _ = response?.data?.sceneUpdate {
                // Notify observers that the rating changed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneRatingUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "rating100": rating100 as Any]
                    )
                }
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func createSceneMarker(sceneId: String, title: String, seconds: Double, endSeconds: Double? = nil, primaryTagId: String, completion: @escaping (Bool) -> Void) {
        let mutation = """
        mutation SceneMarkerCreate($input: SceneMarkerCreateInput!) {
            sceneMarkerCreate(input: $input) {
                id
                title
                seconds
            }
        }
        """
        
        var input: [String: Any] = [
            "scene_id": sceneId,
            "title": title,
            "seconds": seconds,
            "primary_tag_id": primaryTagId
        ]
        
        if let endSeconds = endSeconds {
            input["end_seconds"] = endSeconds
        }
        
        let variables: [String: Any] = [
            "input": input
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SceneMarkerCreateResponse?) in
            if response?.data?.sceneMarkerCreate != nil {
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func fetchAllTags(completion: @escaping ([Tag]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findTags")
        
        let variables: [String: Any] = [
            "filter": [
                "per_page": 1000,
                "sort": "scenes_count",
                "direction": "DESC"
            ],
            "tag_filter": [:]
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([])
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
            completion(response?.data?.findTags.tags ?? [])
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

// MARK: - Scene Deletion
extension StashDBViewModel {
    func deleteSceneWithFiles(scene: Scene, completion: @escaping (Bool) -> Void) {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            completion(false)
            return
        }

        let fileIds = scene.files?.compactMap { $0.id } ?? []
        let sceneMutation = """
        mutation {
            sceneDestroy(input: { id: "\(scene.id)" })
        }
        """

        let sceneRequestBody: [String: Any] = ["query": sceneMutation]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let sceneJsonData = try? JSONSerialization.data(withJSONObject: sceneRequestBody) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        request.httpBody = sceneJsonData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ Network error during deletion: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let data = data {
                    do {
                        if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            if let dataDict = jsonResponse["data"] as? [String: Any],
                               dataDict["sceneDestroy"] != nil {
                                
                                if !fileIds.isEmpty {
                                    Task { @MainActor [weak self] in
                                        self?.deleteSceneFiles(fileIds: fileIds, config: config) { success in
                                            DispatchQueue.main.async {
                                                if success {
                                                    NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": scene.id])
                                                }
                                                completion(success)
                                            }
                                        }
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": scene.id])
                                        completion(true)
                                    }
                                }
                            } else {
                                DispatchQueue.main.async { completion(false) }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async { completion(false) }
                    }
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }

    private func deleteSceneFiles(fileIds: [String], config: ServerConfig, completion: @escaping (Bool) -> Void) {
        let filesMutation = """
        mutation DeleteFiles($ids: [ID!]!) {
            deleteFiles(ids: $ids)
        }
        """

        let variables: [String: Any] = ["ids": fileIds]
        let requestBody: [String: Any] = ["query": filesMutation, "variables": variables]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let _ = error {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
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

struct SceneMarkerCreateResponse: Codable {
    let data: SceneMarkerCreateData?
}
struct SceneMarkerCreateData: Codable {
    let sceneMarkerCreate: SceneMarker?
}

struct SceneUpdateResponse: Codable {
    let data: SceneUpdateData?
}
struct SceneUpdateData: Codable {
    let sceneUpdate: UpdatedItem?
}

struct ImageUpdateResponse: Codable {
    let data: ImageUpdateData?
}
struct ImageUpdateData: Codable {
    let imageUpdate: ImageRatingUpdateItem?
}
struct ImageRatingUpdateItem: Codable {
    let id: String
    let rating100: Int?
    let o_counter: Int?
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

struct MarkersResponse: Codable {
    let data: MarkersData?
}

struct MarkersData: Codable {
    let findSceneMarkers: FindMarkersResult
}

struct FindMarkersResult: Codable {
    let count: Int
    let scene_markers: [SceneMarker]
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
    let oCounter: Int?
    let rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    let paths: ScenePaths?
    let sceneMarkers: [SceneMarker]?
    let interactive: Bool?
    var streams: [SceneStream]?
    
    
    enum CodingKeys: String, CodingKey {
        case id, title, details, date, duration, studio, performers, files, tags, galleries, organized, rating100, paths, interactive, streams
        case resumeTime = "resume_time"
        case playCount = "play_count"
        case oCounter = "o_counter"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sceneMarkers = "scene_markers"
    }

    // Explicit initializer to handle manual updates like 'withStreams'
    init(id: String, title: String?, details: String?, date: String?, duration: Double?, studio: SceneStudio?, performers: [ScenePerformer], files: [SceneFile]?, tags: [Tag]?, galleries: [Gallery]?, organized: Bool?, resumeTime: Double?, playCount: Int?, oCounter: Int?, rating100: Int?, createdAt: String?, updatedAt: String?, paths: ScenePaths?, sceneMarkers: [SceneMarker]?, interactive: Bool?, streams: [SceneStream]? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.date = date
        self.duration = duration
        self.studio = studio
        self.performers = performers
        self.files = files
        self.tags = tags
        self.galleries = galleries
        self.organized = organized
        self.resumeTime = resumeTime
        self.playCount = playCount
        self.oCounter = oCounter
        self.rating100 = rating100
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paths = paths
        self.sceneMarkers = sceneMarkers
        self.interactive = interactive
        self.streams = streams
    }

    // Decodable init
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        studio = try container.decodeIfPresent(SceneStudio.self, forKey: .studio)
        performers = try container.decode([ScenePerformer].self, forKey: .performers)
        files = try container.decodeIfPresent([SceneFile].self, forKey: .files)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        galleries = try container.decodeIfPresent([Gallery].self, forKey: .galleries)
        organized = try container.decodeIfPresent(Bool.self, forKey: .organized)
        resumeTime = try container.decodeIfPresent(Double.self, forKey: .resumeTime)
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount)
        oCounter = try container.decodeIfPresent(Int.self, forKey: .oCounter)
        rating100 = try container.decodeIfPresent(Int.self, forKey: .rating100)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        paths = try container.decodeIfPresent(ScenePaths.self, forKey: .paths)
        sceneMarkers = try container.decodeIfPresent([SceneMarker].self, forKey: .sceneMarkers)
        interactive = try container.decodeIfPresent(Bool.self, forKey: .interactive)
        streams = try container.decodeIfPresent([SceneStream].self, forKey: .streams)
    }
    
    
    // Compat for older views
    struct SceneTag: Codable, Identifiable {
        let id: String
        let name: String
    }
    
    // Computed property to determine if the scene is portrait
    var isPortrait: Bool {
        guard let firstFile = files?.first else { return false }
        if let width = firstFile.width, let height = firstFile.height {
            return height > width
        }
        return false
    }

    // Computed property to determine if scene is truly interactive (has funscript)
    var hasInteractive: Bool {
        return paths?.funscript != nil
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
        // 0. Check local first
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localURL = docs.appendingPathComponent("Downloads/\(id)/thumbnail.jpg")
            if fileManager.fileExists(atPath: localURL.path) {
                return localURL
            }
        }

        // Helper to sign the URL with apikey
        func signed(_ url: URL?) -> URL? {
            guard let url = url else { return nil }
            guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty else { return url }
            if url.query?.lowercased().contains("apikey=") == true { return url }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = comps?.queryItems ?? []
            items.append(URLQueryItem(name: "apikey", value: key))
            comps?.queryItems = items
            return comps?.url ?? url
        }

        // Use path from API if available
        if let screenshotPath = paths?.screenshot {
            let separator = screenshotPath.contains("?") ? "&" : "?"
            let optimizedPath = "\(screenshotPath)\(separator)width=640"
            if let url = URL(string: optimizedPath) {
                 return signed(url)
            }
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signed(URL(string: "\(config.baseURL)/scene/\(id)/screenshot?width=640"))
    }

    /// Finds the best available stream matching the requested quality
    func bestStream(for quality: StreamingQuality) -> URL? {
        guard let streams = streams, !streams.isEmpty else { return nil }
        
        let compatible = ["mp4", "m4v", "mov"]
        let fmt = files?.first?.format?.lowercased() ?? ""
        let isCompatible = compatible.contains(fmt)
        
        // Rule: For compatible formats (MP4), always prefer direct streaming (Original)
        // unless the user specifically requested a different quality and we have a match.
        if isCompatible && (quality == .original) {
            print("🎬 MP4 detected: Using direct stream for Original quality.")
            return nil // Use direct URL from paths?.stream
        }
        
        let hlsStreams = streams.filter { $0.mime_type == "application/vnd.apple.mpegurl" }
        let mp4Streams = streams.filter { $0.mime_type == "video/mp4" }
            .filter { !$0.label.lowercased().contains("direct stream") && !$0.label.lowercased().contains("mkv") }
        
        let targetRes = quality.maxVerticalResolution ?? 0
        
        // Rule: For all other formats (or when specific quality is needed), prioritize HLS
        if !hlsStreams.isEmpty {
            if targetRes > 0 {
                let bestHLS = hlsStreams
                    .compactMap({ stream -> (SceneStream, Int)? in
                        let resString = stream.label.lowercased().replacingOccurrences(of: "p", with: "")
                        if let res = Int(resString) { return (stream, res) }
                        return nil
                    })
                    .filter({ $0.1 <= targetRes })
                    .sorted(by: { $0.1 > $1.1 })
                    .first?.0
                
                if let stream = bestHLS, let url = URL(string: stream.url) {
                    print("📺 Using HLS stream (\(stream.label)) for quality \(quality.displayName)")
                    return url
                }
            }
            
            // Fallback: Use first HLS if no resolution match or for non-compatible formats
            if let firstHLS = hlsStreams.first, let url = URL(string: firstHLS.url) {
                print("📺 Using default HLS stream (\(firstHLS.label))")
                return url
            }
        }
        
        // Final fallback to MP4 transcodes if HLS is unavailable
        if targetRes > 0 {
            let matchingMP4 = mp4Streams
                .compactMap { stream -> (SceneStream, Int)? in
                    let resString = stream.label.lowercased().replacingOccurrences(of: "p", with: "")
                    if let res = Int(resString) { return (stream, res) }
                    return nil
                }
                .filter { $0.1 <= targetRes }
                .sorted(by: { $0.1 > $1.1 })
                .first?.0
            
            if let mp4 = matchingMP4, let url = URL(string: mp4.url) {
                print("⚡ Using MP4 transcode (\(mp4.label)) for quality \(quality.displayName)")
                return url
            }
        }
        
        // Catch-all: Try any non-mkv MP4 or just the first stream
        if let firstMP4 = mp4Streams.first, let url = URL(string: firstMP4.url) {
             return url
        }
        
        return nil
    }

    // Computed property for stream URL (respects global default)
    var videoURL: URL? {
        // 0. Check for local download first (Offline first!)
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localURL = docs.appendingPathComponent("Downloads/\(id)/video.mp4")
            if fileManager.fileExists(atPath: localURL.path) {
                print("📂 Using local download for scene \(id)")
                return localURL
            }
        }

        let quality = ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
        
        // 1. Try best stream (transcoded)
        if let streamURL = bestStream(for: quality) {
            return signedURL(streamURL)
        }

        // 2. Fallbacks (API path or manual construction)
        let potentialURL: URL?
        if let streamPath = paths?.stream, let url = URL(string: streamPath) {
             potentialURL = url
        } else if let config = ServerConfigManager.shared.loadConfig() {
            let urlString = "\(config.baseURL)/scene/\(id)/stream"
            potentialURL = URL(string: urlString)
        } else {
            potentialURL = nil
        }
        
        if let files = files, let first = files.first, let fmt = first.format {
            let compatible = ["mp4", "m4v", "mov"]
            if !compatible.contains(fmt.lowercased()) {
                print("⛔️ Preventing fallback to incompatible '\(fmt)' file for scene \(id)")
                return nil
            }
        }
        return signedURL(potentialURL)
    }

    var heatmapURL: URL? {
        guard let path = paths?.interactive_heatmap, let url = URL(string: path) else { return nil }
        guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty else { return url }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "apikey", value: key))
        comps?.queryItems = items
        return comps?.url ?? url
    }

    var funscriptURL: URL? {
        guard let path = paths?.funscript, let url = URL(string: path) else { return nil }
        guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty else { return url }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "apikey", value: key))
        comps?.queryItems = items
        return comps?.url ?? url
    }

    // Computed property for download URL (preferring MP4 transcoded stream)
    var downloadURL: URL? {
        let compatibleExtensions = ["mp4", "m4v", "mov"]
        let fileFmt = files?.first?.format?.lowercased() ?? ""
        let isOriginalCompatible = compatibleExtensions.contains(fileFmt)

        // 1. Try to find a high-quality MP4 transcode (specifically excluding HLS and direct MKV links)
        let mp4Transcodes = streams?.filter { $0.mime_type == "video/mp4" }
            .filter { stream in
                let label = stream.label.lowercased()
                // Exclude direct streams that are just the original incompatible file
                if label.contains("direct stream") || label.contains("mkv") { return false }
                return true
            }
        
        if let bestMP4 = mp4Transcodes?.sorted(by: { s1, s2 in
            let r1 = Int(s1.label.lowercased().replacingOccurrences(of: "p", with: "")) ?? 0
            let r2 = Int(s2.label.lowercased().replacingOccurrences(of: "p", with: "")) ?? 0
            return r1 > r2
        }).first, let url = URL(string: bestMP4.url) {
            print("💾 Download: Using best MP4 transcode (\(bestMP4.label)) for scene \(id)")
            return signedURL(url)
        }
        
        // 2. Fallback to original ONLY if it's compatible (MP4/MOV/etc)
        if isOriginalCompatible {
             if let streamPath = paths?.stream, let url = URL(string: streamPath) {
                 print("💾 Download: Using compatible original file (\(fileFmt)) for scene \(id)")
                 return signedURL(url)
             }
        }
        
        // 3. Last ditch effort: Look for ANY MP4 stream that isn't the original incompatible file
        // (Sometimes transcodes don't have clear labels)
        if !isOriginalCompatible {
            if let anyMP4 = streams?.first(where: { $0.mime_type == "video/mp4" && !$0.label.lowercased().contains("mkv") }),
               let url = URL(string: anyMP4.url) {
                return signedURL(url)
            }
        }
        
        print("⚠️ Download: No compatible MP4 file found for scene \(id). Original format: \(fileFmt)")
        return nil
    }
    
    
    // Computed property for preview URL (video preview)
    var previewURL: URL? {
        // Helper to sign the URL with apikey
        func signed(_ url: URL?) -> URL? {
            guard let url = url else { return nil }
            guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty else { return url }
            if url.query?.lowercased().contains("apikey=") == true { return url }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = comps?.queryItems ?? []
            items.append(URLQueryItem(name: "apikey", value: key))
            comps?.queryItems = items
            return comps?.url ?? url
        }

        // Use path from API if available
        if let previewPath = paths?.preview, let url = URL(string: previewPath) {
             return signed(url)
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signed(URL(string: "\(config.baseURL)/scene/\(id)/preview"))
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
            oCounter: oCounter,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: streams
        )
    }
    
    /// Creates a copy with updated rating
    func withRating(_ newRating: Int?) -> Scene {
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
            resumeTime: resumeTime,
            playCount: playCount,
            oCounter: oCounter,
            rating100: newRating,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: streams
        )
    }

    /// Creates a copy with updated streams
    func withStreams(_ newStreams: [SceneStream]?) -> Scene {
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
            resumeTime: resumeTime,
            playCount: playCount,
            oCounter: oCounter,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: newStreams
        )
    }
    
    
    /// Creates a copy with updated play count
    func withPlayCount(_ newPlayCount: Int?) -> Scene {
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
            resumeTime: resumeTime,
            playCount: newPlayCount,
            oCounter: oCounter,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: streams
        )
    }
    
    
    /// Creates a copy with updated o count
    func withOCounter(_ newOCounter: Int?) -> Scene {
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
            resumeTime: resumeTime,
            playCount: playCount,
            oCounter: newOCounter,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: streams
        )
    }
    
}

struct SceneStream: Codable {
    let label: String
    let mime_type: String
    let url: String
}

struct SceneStreamsResponse: Codable {
    let data: SceneStreamsData?
}

struct SceneStreamsData: Codable {
    let sceneStreams: [SceneStream]
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

struct MarkerScene: Codable, Identifiable {
    let id: String
    let title: String?
    let date: String?
    let files: [SceneFile]?
    let performers: [ScenePerformer]?
    let rating100: Int?
    let playCount: Int?
    let oCounter: Int?
    let interactive: Bool?
    let paths: ScenePaths?
    let streams: [SceneStream]?

    enum CodingKeys: String, CodingKey {
        case id, title, date, files, performers, rating100, interactive, paths, streams
        case playCount = "play_count"
        case oCounter = "o_counter"
    }

    func withRating(_ rating: Int?) -> MarkerScene {
        MarkerScene(id: id, title: title, date: date, files: files, performers: performers, rating100: rating, playCount: playCount, oCounter: oCounter, interactive: interactive, paths: paths, streams: streams)
    }
    func withOCounter(_ count: Int?) -> MarkerScene {
        MarkerScene(id: id, title: title, date: date, files: files, performers: performers, rating100: rating100, playCount: playCount, oCounter: count, interactive: interactive, paths: paths, streams: streams)
    }
    func withStreams(_ newStreams: [SceneStream]?) -> MarkerScene {
        MarkerScene(id: id, title: title, date: date, files: files, performers: performers, rating100: rating100, playCount: playCount, oCounter: oCounter, interactive: interactive, paths: paths, streams: newStreams)
    }
    func withPlayCount(_ count: Int?) -> MarkerScene {
        MarkerScene(id: id, title: title, date: date, files: files, performers: performers, rating100: rating100, playCount: count, oCounter: oCounter, interactive: interactive, paths: paths, streams: streams)
    }

    // Computed property to determine if scene is truly interactive (has funscript)
    var hasInteractive: Bool {
        return paths?.funscript != nil
    }

    /// Finds the best available stream matching the requested quality
    func bestStream(for quality: StreamingQuality) -> URL? {
        guard let streams = streams, !streams.isEmpty else { return nil }
        
        let compatible = ["mp4", "m4v", "mov"]
        let fmt = files?.first?.format?.lowercased() ?? ""
        let isCompatible = compatible.contains(fmt)
        
        // For markers, we check the associated scene's file format.
        if isCompatible && (quality == .original) {
            return nil // Use direct
        }
        
        let hlsStreams = streams.filter { $0.mime_type == "application/vnd.apple.mpegurl" }
        let mp4Streams = streams.filter { $0.mime_type == "video/mp4" }
            .filter { !$0.label.lowercased().contains("direct stream") && !$0.label.lowercased().contains("mkv") }
        
        let targetRes = quality.maxVerticalResolution ?? 0
        
        // Prioritize HLS for non-MP4 or specific quality
        if !hlsStreams.isEmpty {
            if targetRes > 0 {
                let bestHLS = hlsStreams
                    .compactMap({ stream -> (SceneStream, Int)? in
                        let resString = stream.label.lowercased().replacingOccurrences(of: "p", with: "")
                        if let res = Int(resString) { return (stream, res) }
                        return nil
                    })
                    .filter({ $0.1 <= targetRes })
                    .sorted(by: { $0.1 > $1.1 })
                    .first?.0
                
                if let stream = bestHLS, let url = URL(string: stream.url) {
                    return url
                }
            }
            
            if let firstHLS = hlsStreams.first, let url = URL(string: firstHLS.url) {
                return url
            }
        }
        
        // Fallback to MP4 transcode
        if targetRes > 0 {
            let matchingMP4 = mp4Streams
                .compactMap { stream -> (SceneStream, Int)? in
                    let resString = stream.label.lowercased().replacingOccurrences(of: "p", with: "")
                    if let res = Int(resString) { return (stream, res) }
                    return nil
                }
                .filter { $0.1 <= targetRes }
                .sorted(by: { $0.1 > $1.1 })
                .first?.0
            
            if let mp4 = matchingMP4, let url = URL(string: mp4.url) {
                return url
            }
        }
        
        if let firstMP4 = mp4Streams.first, let url = URL(string: firstMP4.url) {
             return url
        }
        
        return nil
    }

    var videoURL: URL? {
        // 0. Check local first
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localURL = docs.appendingPathComponent("Downloads/\(id)/video.mp4")
            if fileManager.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        let quality = ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
        if let streamURL = bestStream(for: quality) {
            return signedURL(streamURL)
        }
        
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scene/\(id)/stream"))
    }
    
    var thumbnailURL: URL? {
        // 0. Check local first
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localURL = docs.appendingPathComponent("Downloads/\(id)/thumbnail.jpg")
            if fileManager.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scene/\(id)/screenshot"))
    }
}

struct SceneMarker: Codable, Identifiable {
    let id: String
    let title: String?
    let seconds: Double
    let endSeconds: Double?
    let primaryTag: Tag?
    let tags: [Tag]?
    let screenshot: String?
    let preview: String?
    let stream: String?
    let scene: MarkerScene?

    enum CodingKeys: String, CodingKey {
        case id, title, seconds, tags, screenshot, preview, stream, scene
        case endSeconds = "end_seconds"
        case primaryTag = "primary_tag"
    }

    func withScene(_ newScene: MarkerScene?) -> SceneMarker {
        SceneMarker(id: id, title: title, seconds: seconds, endSeconds: endSeconds, primaryTag: primaryTag, tags: tags, screenshot: screenshot, preview: preview, stream: stream, scene: newScene)
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        // 0. Check local first
        if let sceneId = scene?.id {
            let fileManager = FileManager.default
            if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let localURL = docs.appendingPathComponent("Downloads/\(sceneId)/thumbnail.jpg")
                if fileManager.fileExists(atPath: localURL.path) {
                    return localURL
                }
            }
        }

        // Use path from API if available
        if let screenshotPath = screenshot, let url = URL(string: screenshotPath) {
             if screenshotPath.hasPrefix("http") {
                 return signedURL(url)
             } else if let config = ServerConfigManager.shared.loadConfig() {
                 let path = screenshotPath.hasPrefix("/") ? String(screenshotPath.dropFirst()) : screenshotPath
                 return signedURL(URL(string: "\(config.baseURL)/\(path)"))
             }
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scenemarker/\(id)/screenshot"))
    }
    
    // Computed property for stream URL
    var videoURL: URL? {
        // 0. Check for local download first
        if let sceneId = scene?.id {
            let fileManager = FileManager.default
            if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let localURL = docs.appendingPathComponent("Downloads/\(sceneId)/video.mp4")
                if fileManager.fileExists(atPath: localURL.path) {
                    print("📂 Using local download for marker \(id)")
                    return localURL
                }
            }
        }

        let quality = ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
        
        // 1. Try best stream from associated scene (transcoded)
        if let scene = scene, let streamURL = scene.bestStream(for: quality) {
            return signedURL(streamURL)
        }
        
        // 2. Fallbacks (API path or manual construction)
        let potentialURL: URL?
        if let streamPath = stream, let url = URL(string: streamPath) {
             potentialURL = url
        } else if let config = ServerConfigManager.shared.loadConfig() {
            potentialURL = URL(string: "\(config.baseURL)/scenemarker/\(id)/stream")
        } else {
            potentialURL = nil
        }
        
        // Safety Check: Verify format compatibility from associated scene
        if let scene = scene, let files = scene.files, let first = files.first, let fmt = first.format {
            let compatible = ["mp4", "m4v", "mov"]
            if !compatible.contains(fmt.lowercased()) {
                print("⛔️ Preventing fallback to incompatible '\(fmt)' file for marker \(id)")
                return nil
            }
        }
        
        return signedURL(potentialURL)
    }
    
    // Computed property for preview URL
    var previewURL: URL? {
        if let previewPath = preview, let url = URL(string: previewPath) {
             return signedURL(url)
        }
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/scenemarker/\(id)/preview"))
    }
}

struct SceneFile: Codable, Identifiable {
    let id: String
    let path: String?
    let format: String?
    let width: Int?
    let height: Int?
    let duration: Double?
    let videoCodec: String?
    let audioCodec: String?
    let bitRate: Int?
    let frameRate: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, path, format, width, height, duration
        case videoCodec = "video_codec"
        case audioCodec = "audio_codec"
        case bitRate = "bit_rate"
        case frameRate = "frame_rate"
    }
}

struct SceneStudio: Codable {
    let id: String
    let name: String

    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/studio/\(id)/image"))
    }
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

    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/performer/\(id)/image"))
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

struct SinglePerformerResponse: Codable {
    let data: SinglePerformerData?
}

struct SinglePerformerData: Codable {
    let findPerformer: Performer?
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
        
        return signedURL(URL(string: thumbnailURLString))
    }
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
    
    init(id: String, name: String, url: String? = nil, sceneCount: Int = 0, performerCount: Int? = nil, galleryCount: Int? = nil, details: String? = nil, imagePath: String? = nil, favorite: Bool? = nil, rating100: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.sceneCount = sceneCount
        self.performerCount = performerCount
        self.galleryCount = galleryCount
        self.details = details
        self.imagePath = imagePath
        self.favorite = favorite
        self.rating100 = rating100
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(from galleryStudio: GalleryStudio) {
        self.init(id: galleryStudio.id, name: galleryStudio.name)
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
        
        return signedURL(URL(string: thumbnailURLString))
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
    let galleryCount: Int?
    let favorite: Bool?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, favorite
        case imagePath = "image_path"
        case sceneCount = "scene_count"
        case galleryCount = "gallery_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        // /tag/[ID]/image
        return signedURL(URL(string: "\(config.baseURL)/tag/\(id)/image"))
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
        
        let separator = thumbnailPath.contains("?") ? "&" : "?"
        let optimizedPath = "\(thumbnailPath)\(separator)width=640"
        
        // Check if the path is already an absolute URL
        if optimizedPath.starts(with: "http://") || optimizedPath.starts(with: "https://") {
            return signedURL(URL(string: optimizedPath))
        } else {
            // Relative path, prepend baseURL
            return signedURL(URL(string: config.baseURL + optimizedPath))
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

struct GalleryPerformer: Codable, Identifiable {
    let id: String
    let name: String
}

// struct GalleryFile: Codable {
//     let `extension`: String?
// }

struct ImageFile: Codable {
    let path: String
    let height: Int?
    let width: Int?
    let duration: Double?
}

struct ImageGallery: Codable, Identifiable {
    let id: String
    let title: String?
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
    let rating100: Int?
    let o_counter: Int?
    let organized: Bool?
    let date: String?
    let paths: ImagePaths?
    // let files: [ImageFile]?
    let visual_files: [ImageFile]?
    let performers: [GalleryPerformer]?
    let studio: GalleryStudio?
    let galleries: [ImageGallery]?
    let tags: [Tag]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, rating100, o_counter, organized, date, paths, performers, studio, galleries, visual_files, tags
    }
    
    var isVideo: Bool {
        let videoExtensions = ["MP4", "MOV", "M4V", "WEBM", "MKV"]
        if let ext = fileExtension?.uppercased() {
             return videoExtensions.contains(ext)
        }
        return false
    }

    var isGIF: Bool {
        return fileExtension?.uppercased() == "GIF"
    }
    
    var fileExtension: String? {
        // Primary: Use 'visual_files' array if available
        if let path = visual_files?.first?.path {
            return URL(fileURLWithPath: path).pathExtension.uppercased()
        }
        
        // Fallback: Use 'paths.image'
        if let imagePath = paths?.image {
            let cleanPath = imagePath.components(separatedBy: "?").first ?? imagePath
            return URL(fileURLWithPath: cleanPath).pathExtension.uppercased()
        }
        
        return nil
    }
    
    var formattedDate: String {
        guard let dateString = date else { return "" }
        return dateString
    }
    
    func withRating(_ rating: Int?) -> StashImage {
        return StashImage(
            id: id,
            title: title,
            rating100: rating,
            o_counter: o_counter,
            organized: organized,
            date: date,
            paths: paths,
            visual_files: visual_files,
            performers: performers,
            studio: studio,
            galleries: galleries,
            tags: tags
        )
    }

    func withOCounter(_ count: Int?) -> StashImage {
        return StashImage(
            id: id,
            title: title,
            rating100: rating100,
            o_counter: count,
            organized: organized,
            date: date,
            paths: paths,
            visual_files: visual_files,
            performers: performers,
            studio: studio,
            galleries: galleries,
            tags: tags
        )
    }

    
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let thumbnailPath = paths?.thumbnail else { return nil }
        
        let separator = thumbnailPath.contains("?") ? "&" : "?"
        let optimizedPath = "\(thumbnailPath)\(separator)width=640"
        
        if optimizedPath.starts(with: "http://") || optimizedPath.starts(with: "https://") {
            return signedURL(URL(string: optimizedPath))
        } else {
            return signedURL(URL(string: config.baseURL + optimizedPath))
        }
    }
    
    var previewURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let previewPath = paths?.preview else { return nil }
        
        if previewPath.starts(with: "http://") || previewPath.starts(with: "https://") {
            return signedURL(URL(string: previewPath))
        } else {
            return signedURL(URL(string: config.baseURL + previewPath))
        }
    }
    
    var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        guard let imagePath = paths?.image else { return nil }
        
        if imagePath.starts(with: "http://") || imagePath.starts(with: "https://") {
            return signedURL(URL(string: imagePath))
        } else {
            return signedURL(URL(string: config.baseURL + imagePath)!)
        }
    }
    
    var displayFilename: String {
        // Try title first
        if let title = title, !title.isEmpty {
            return title
        }
        // Fallback to filename from image path
        if let imagePath = paths?.image {
            // Strip query parameters for display (e.g. image?t=timestamp -> image)
            let cleanPath = imagePath.components(separatedBy: "?").first ?? imagePath
            return URL(fileURLWithPath: cleanPath).lastPathComponent
        }
        // Last resort: use ID
        return "Image \(id.prefix(8))"
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
    var totalSize: Int64
    var downloadedSize: Int64
}

final class DownloadTaskMap: @unchecked Sendable {
    private var tasks: [Int: (String, URL)] = [:]
    private let lock = NSLock()
    
    nonisolated init() {}
    
    nonisolated func set(_ taskId: Int, info: (String, URL)) {
        lock.lock(); defer { lock.unlock() }
        tasks[taskId] = info
    }
    
    nonisolated func get(_ taskId: Int) -> (String, URL)? {
        lock.lock(); defer { lock.unlock() }
        return tasks[taskId]
    }
    
    nonisolated func remove(_ taskId: Int) -> (String, URL)? {
        lock.lock(); defer { lock.unlock() }
        return tasks.removeValue(forKey: taskId)
    }
}

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloads: [DownloadedScene] = []
    @Published var activeDownloads: [String: ActiveDownload] = [:] // id: info
    
    private let downloadsFolder: URL
    private let metadataFile = "downloads_metadata.json"
    
    nonisolated private let taskMap = DownloadTaskMap()
    private var progressHandlers: [String: (Double, Int64, Int64) -> Void] = [:]
    private var completionHandlers: [String: (Bool) -> Void] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.stashy.backgroundDownload")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false // Download immediately
        return URLSession(configuration: config, delegate: self, delegateQueue: nil) // Delegate queue nil for background
    }()

    override private init() {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
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
        
        // 1. Fetch streams first to ensure we get a compatible MP4 if original is not
        StashDBViewModel().fetchSceneStreams(sceneId: sceneId) { streams in
            let sceneWithStreams = scene.withStreams(streams)
            self.startDownload(sceneWithStreams)
        }
    }

    private func startDownload(_ scene: Scene) {
        let sceneId = scene.id
        let title = scene.title ?? "Unknown Scene"
        
        // Mark as started
        DispatchQueue.main.async {
            self.activeDownloads[sceneId] = ActiveDownload(id: sceneId, title: title, progress: 0.05, totalSize: 0, downloadedSize: 0)
        }
        
        let sceneFolder = downloadsFolder.appendingPathComponent(sceneId, isDirectory: true)
        try? FileManager.default.createDirectory(at: sceneFolder, withIntermediateDirectories: true)
        
        // Use a Group to track multiple downloads
        let dispatchGroup = DispatchGroup()
        var videoSuccess = false
        
        // 1. Download Thumbnail
        if let thumbURL = scene.thumbnailURL {
            dispatchGroup.enter()
            downloadFile(id: sceneId + "_thumb", from: thumbURL, to: sceneFolder.appendingPathComponent("thumbnail.jpg")) { _, _, _ in } completion: { success in
                dispatchGroup.leave()
            }
        }
        
        // 2. Download Video (Uses downloadURL which prefers MP4 transcoded stream)
        if let videoURL = scene.downloadURL {
            dispatchGroup.enter()
            
            // Initialize with size info
            self.activeDownloads[sceneId] = ActiveDownload(id: sceneId, title: title, progress: 0.1, totalSize: 0, downloadedSize: 0)
            
            downloadFile(id: sceneId, from: videoURL, to: sceneFolder.appendingPathComponent("video.mp4")) { progress, written, total in
                // Update progress
                Task { @MainActor in
                    if var activeDownload = self.activeDownloads[sceneId] {
                        activeDownload.progress = 0.1 + (progress * 0.9)
                        activeDownload.downloadedSize = written
                        activeDownload.totalSize = total
                        self.activeDownloads[sceneId] = activeDownload
                        self.objectWillChange.send() // Explicitly trigger UI update
                    }
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
    
    private func downloadFile(id: String, from url: URL, to destination: URL, progressHandler: @escaping (Double, Int64, Int64) -> Void, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        
        if let config = ServerConfigManager.shared.loadConfig(),
           let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
        }
        
        let task = session.downloadTask(with: request)
        taskMap.set(task.taskIdentifier, info: (id, destination))
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
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, destination) = taskMap.get(downloadTask.taskIdentifier) else { return }
        
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            
            // Success: Remove task from map and notify
            _ = taskMap.remove(downloadTask.taskIdentifier)
            
            Task { @MainActor in
                self.completionHandlers[id]?(true)
                self.progressHandlers.removeValue(forKey: id)
                self.completionHandlers.removeValue(forKey: id)
            }
        } catch {
            print("❌ DownloadManager: Failed to move file: \(error)")
            // Failure: Remove task from map and notify
            _ = taskMap.remove(downloadTask.taskIdentifier)
            
            Task { @MainActor in
                self.completionHandlers[id]?(false)
                self.progressHandlers.removeValue(forKey: id)
                self.completionHandlers.removeValue(forKey: id)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0.0
        }
        
        // Debug log moved to check if needed, but keeping logic clean first
        // print("📥 Download Progress: \(totalBytesWritten) / \(totalBytesExpectedToWrite) (...)")
        
        if let (id, _) = taskMap.get(downloadTask.taskIdentifier) {
            Task { @MainActor in
                self.progressHandlers[id]?(progress, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let capturedError = error {
            print("❌ DownloadManager: Task \(task.taskIdentifier) completed with error: \(capturedError)")
            
            if let (id, _) = taskMap.remove(task.taskIdentifier) {
                Task { @MainActor in
                    self.completionHandlers[id]?(false)
                    self.progressHandlers.removeValue(forKey: id)
                    self.completionHandlers.removeValue(forKey: id)
                }
            }
        }
    }
    
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        #if !os(tvOS)
        Task { @MainActor in
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate,
               let completionHandler = appDelegate.backgroundSessionCompletionHandler {
                appDelegate.backgroundSessionCompletionHandler = nil
                completionHandler()
            }
        }
        #endif
    }
}

#if !os(tvOS)
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
#endif


// MARK: - Universal Search Async Methods

extension StashDBViewModel {
    
    func searchPerformersAsync(query: String, limit: Int = 5) async -> [Performer] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findPerformers")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "name",
                        "direction": "ASC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: PerformersResponse?) in
                continuation.resume(returning: response?.data?.findPerformers.performers ?? [])
            }
        }
    }
    
    func searchStudiosAsync(query: String, limit: Int = 5) async -> [Studio] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findStudios")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "name",
                        "direction": "ASC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: StudiosResponse?) in
                continuation.resume(returning: response?.data?.findStudios.studios ?? [])
            }
        }
    }
    
    func searchTagsAsync(query: String, limit: Int = 5) async -> [Tag] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findTags")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "name",
                        "direction": "ASC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
                continuation.resume(returning: response?.data?.findTags.tags ?? [])
            }
        }
    }
    
    func searchScenesAsync(query: String, limit: Int = 5) async -> [Scene] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findScenes")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "date",
                        "direction": "DESC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
                continuation.resume(returning: response?.data?.findScenes?.scenes ?? [])
            }
        }
    }
    
    func searchGalleriesAsync(query: String, limit: Int = 5) async -> [Gallery] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findGalleries")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "date",
                        "direction": "DESC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
                continuation.resume(returning: response?.data?.findGalleries.galleries ?? [])
            }
        }
    }
    
    func fetchSceneStreams(sceneId: String, completion: @escaping ([SceneStream]) -> Void) {
        let query = GraphQLQueries.loadQuery(named: "sceneStreams")
        let variables = ["id": sceneId]
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([])
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SceneStreamsResponse?) in
            let streams = response?.data?.sceneStreams ?? []
            print("📺 Fetched \(streams.count) transcoded streams for scene \(sceneId)")
            DispatchQueue.main.async {
                completion(streams)
            }
        }
    }
}

#if !os(tvOS)
class HandyManager: ObservableObject {
    static let shared = HandyManager()
    
    @AppStorage("handy_connection_key") var connectionKey: String = ""
    @AppStorage("handy_public_url") var publicUrl: String = ""
    @Published var isConnected: Bool = false
    @Published var isSyncing: Bool = false
    @Published var statusMessage: String = "Not Configured"
    
    private let baseURL = "https://www.handyfeeling.com/api/handy/v2"
    private var cancellables = Set<AnyCancellable>()
    
    private var serverTimeOffset: Int64 = 0
    private var lastSyncTime: Date?
    
    private init() {
        if !connectionKey.isEmpty {
            checkConnection()
        }
    }
    
    func checkConnection(completion: ((Bool) -> Void)? = nil) {
        guard !connectionKey.isEmpty else {
            statusMessage = "No connection key"
            isConnected = false
            completion?(false)
            return
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/connected")!)
        request.setValue(connectionKey, forHTTPHeaderField: "X-Connection-Key")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: HandyConnectedResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completionStatus in
                if case .failure(let error) = completionStatus {
                    self.statusMessage = "Offline"
                    print("❌ Handy: Connection failed: \(error.localizedDescription)")
                    self.isConnected = false
                    completion?(false)
                }
            }, receiveValue: { response in
                self.isConnected = response.connected
                self.statusMessage = response.connected ? "Connected" : "Device Offline"
                if response.connected {
                    self.syncServerTime { _ in }
                }
                completion?(response.connected)
            })
            .store(in: &cancellables)
    }
    
    func setupScene(funscriptURL: URL) {
        print("📲 Handy: Setting up scene with URL: \(funscriptURL.absoluteString)")
        
        // Check if URL is local
        let urlString = funscriptURL.absoluteString
        if urlString.contains("127.0.0.1") || urlString.contains("localhost") || urlString.contains("192.168.") || urlString.contains("10.") {
            print("⚠️ Handy: Warning - Funscript URL appears to be local. The Handy Cloud API may not be able to reach it.")
            statusMessage = "Local URL Warning"
        }

        guard isConnected else { 
            print("📲 Handy: Device not connected, checking connection first...")
            checkConnection { [weak self] connected in
                if connected { 
                    self?.setupScene(funscriptURL: funscriptURL) 
                } else {
                    self?.statusMessage = "Connect Device First"
                }
            }
            return 
        }
        
        isSyncing = false
        statusMessage = "Setting up sync..."
        
        // Always sync time before HSSP setup to ensure offset is fresh
        syncServerTime { [weak self] _ in
            guard let self = self else { return }
            
            // 1. Ensure mode is HSSP (1)
            self.setMode(mode: 1) { [weak self] success in
                guard let self = self else { return }
                if success {
                    // 2. Setup HSSP with script
                    self.setupHSSP(url: funscriptURL)
                } else {
                    self.statusMessage = "Mode Error"
                }
            }
        }
    }
    
    private func setMode(mode: Int, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: "\(baseURL)/mode")!)
        request.httpMethod = "PUT"
        request.setValue(connectionKey, forHTTPHeaderField: "X-Connection-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["mode": mode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(success)
            }
        }.resume()
    }
    
    private func setupHSSP(url: URL) {
        // 1. If URL is local, we must use the Upload Bridge
        let urlString = url.absoluteString
        if urlString.contains("127.0.0.1") || urlString.contains("localhost") || urlString.contains("192.168.") || urlString.contains("10.") {
            print("📲 Handy: Local URL detected. Initiating Direct Upload Bridge...")
            statusMessage = "Uploading script..."
            
            uploadToHandyCloud(localUrl: url) { [weak self] publicUrl in
                guard let self = self else { return }
                if let publicUrl = publicUrl {
                    print("📲 Handy: Upload bridge successful. Public URL: \(publicUrl.absoluteString)")
                    self.executeHSSPSetup(url: publicUrl)
                } else {
                    print("❌ Handy: Upload bridge failed.")
                    DispatchQueue.main.async {
                        self.statusMessage = "Upload Failed"
                    }
                }
            }
            return
        }
        
        // 2. If we have a public URL override, use it (fallback)
        if !publicUrl.isEmpty {
            if let publicBase = URL(string: publicUrl),
               var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                comps.host = publicBase.host
                comps.scheme = publicBase.scheme
                comps.port = publicBase.port
                
                if let newUrl = comps.url {
                    print("📲 Handy: Swapping for public override: \(newUrl.absoluteString)")
                    executeHSSPSetup(url: newUrl)
                    return
                }
            }
        }

        // 3. Normal public URL
        executeHSSPSetup(url: url)
    }
    
    private func executeHSSPSetup(url: URL) {
        print("📲 Handy: Sending HSSP setup request for URL: \(url.absoluteString)")
        var request = URLRequest(url: URL(string: "\(baseURL)/hssp/setup")!)
        request.httpMethod = "PUT"
        request.setValue(connectionKey, forHTTPHeaderField: "X-Connection-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url.absoluteString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let success = httpResponse?.statusCode == 200
            
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                print("📲 Handy: HSSP Setup Response (\(httpResponse?.statusCode ?? 0)): \(responseString)")
            }

            DispatchQueue.main.async {
                self.isSyncing = success
                self.statusMessage = success ? "Synced & Ready" : "Sync Failed (\(httpResponse?.statusCode ?? 0))"
                if success {
                    print("✅ Handy: HSSP Setup Successful")
                } else {
                    print("❌ Handy: HSSP Setup Failed")
                }
            }
        }.resume()
    }
    
    private func uploadToHandyCloud(localUrl: URL, completion: @escaping (URL?) -> Void) {
        // Phase 1: Download from Stash
        print("📲 Handy Bridge: Downloading script from \(localUrl.absoluteString)...")
        URLSession.shared.dataTask(with: localUrl) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ Handy Bridge: Failed to download script: \(error?.localizedDescription ?? "no data")")
                completion(nil)
                return
            }
            
            // Phase 2: Upload to Handy Cloud
            // The API v2 endpoint for CSV/JSON upload is https://www.handfeeling.com/api/sync/upload
            // It expects a multipart form-data request
            print("📲 Handy Bridge: Uploading \(data.count) bytes to Handy Cloud...")
            
            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: URL(string: "https://www.handyfeeling.com/api/sync/upload")!)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"syncFile\"; filename=\"script.funscript\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("❌ Handy Bridge: Upload failed (\((response as? HTTPURLResponse)?.statusCode ?? 0))")
                    completion(nil)
                    return
                }
                
                // Response is usually JSON with "url"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let remoteUrlString = json["url"] as? String,
                   let remoteUrl = URL(string: remoteUrlString) {
                    completion(remoteUrl)
                } else {
                    print("❌ Handy Bridge: Could not parse remote URL from response")
                    completion(nil)
                }
            }.resume()
        }.resume()
    }
    
    func play(at seconds: Double) {
        guard isConnected && isSyncing else { 
            print("📲 Handy: Play ignored - Connected: \(isConnected), Syncing: \(isSyncing)")
            return 
        }
        
        let serverTime = estimatedServerTime
        var request = URLRequest(url: URL(string: "\(self.baseURL)/hssp/play")!)
        request.httpMethod = "PUT"
        request.setValue(self.connectionKey, forHTTPHeaderField: "X-Connection-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let startTimeMs = Int(seconds * 1000)
        let body: [String: Any] = [
            "estimatedServerTime": serverTime,
            "startTime": startTimeMs
        ]
        
        print("📲 Handy: Sending Play - estimatedServerTime: \(serverTime), startTime: \(startTimeMs)ms")
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorData = data != nil ? String(data: data!, encoding: .utf8) ?? "" : ""
                print("❌ Handy: Play failed (\(httpResponse.statusCode)): \(errorData)")
            } else if error != nil {
                print("❌ Handy: Play network error: \(error?.localizedDescription ?? "unknown")")
            } else {
                print("✅ Handy: Play command acknowledged")
            }
        }.resume()
    }
    
    private var estimatedServerTime: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000) + serverTimeOffset
    }
    
    private func syncServerTime(completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        fetchServerTime { [weak self] serverTime in
            guard let self = self, let serverTime = serverTime else {
                completion(false)
                return
            }
            let endTime = Date()
            let rtt = Int64(endTime.timeIntervalSince(startTime) * 1000) / 2
            let localTimeAtServerTime = Int64(endTime.timeIntervalSince1970 * 1000) - rtt
            self.serverTimeOffset = serverTime - localTimeAtServerTime
            self.lastSyncTime = Date()
            print("📲 Handy: Server time synced. Offset: \(self.serverTimeOffset)ms, RTT: \(rtt*2)ms")
            completion(true)
        }
    }
    
    func pause() {
        guard isConnected && isSyncing else { return }
        
        print("📲 Handy: Pause command")
        var request = URLRequest(url: URL(string: "\(baseURL)/hssp/stop")!)
        request.httpMethod = "PUT"
        request.setValue(connectionKey, forHTTPHeaderField: "X-Connection-Key")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                 print("❌ Handy: Pause failed (\(httpResponse.statusCode))")
            } else {
                 print("✅ Handy: Pause command acknowledged")
            }
        }.resume()
    }
    
    private func fetchServerTime(completion: @escaping (Int64?) -> Void) {
        let request = URLRequest(url: URL(string: "\(baseURL)/servertime")!)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let time = json["serverTime"] as? Int64 {
                completion(time)
            } else {
                completion(nil)
            }
        }.resume()
    }
}

struct HandyConnectedResponse: Codable {
    let connected: Bool
}

class ButtplugManager: ObservableObject {
    static let shared = ButtplugManager()
    
    @AppStorage("intiface_server_address") var serverAddress: String = "ws://127.0.0.1:12345"
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var statusMessage: String = "Not Connected"
    @Published var devices: [ButtplugDevice] = []
    
    private var webSocket: URLSessionWebSocketTask?
    private var messageId: Int = 1
    
    // Funscript Sync
    private var currentScript: Funscript?
    private var syncTimer: CADisplayLink?
    private var lastPlaybackTime: Double = 0
    private var lastCommandSentAt: Double = 0
    private var isPlayingScript: Bool = false
    @Published var isSyncing: Bool = false
    
    private init() {
        // Optional: Auto-connect if desirable
    }
    
    func connect() {
        guard let url = URL(string: serverAddress) else {
            statusMessage = "Invalid URL"
            return
        }
        
        // Reset state
        DispatchQueue.main.async {
            self.isConnected = false
            self.devices.removeAll()
            self.statusMessage = "Connecting..."
        }
        
        let request = URLRequest(url: url)
        webSocket = URLSession.shared.webSocketTask(with: request)
        webSocket?.resume()
        
        sendHandshake()
        receiveMessage()
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: "User request".data(using: .utf8))
        webSocket = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusMessage = "Disconnected"
            self.devices.removeAll()
        }
    }
    
    private func sendHandshake() {
        let handshake: [[String: Any]] = [
            ["RequestServerInfo": [
                "Id": getNextMessageId(),
                "ClientName": "Stashy",
                "MessageVersion": 3
            ]]
        ]
        sendMessage(handshake)
    }
    
    func startScanning() {
        sendMessage([["StartScanning": ["Id": getNextMessageId()]]])
        isScanning = true
    }
    
    private func getNextMessageId() -> Int {
        let id = messageId
        messageId += 1
        return id
    }
    
    private func sendMessage(_ message: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else { return }
        
        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("❌ Buttplug: Send failed: \(error)")
                // Do not disconnect immediately on send failure to avoid UI flickering during sync
            }
        }
    }
    
    // MARK: - Funscript Sync Logic
    
    func setupScene(funscriptURL: URL) {
        guard isConnected else { return }
        
        statusMessage = "Loading Script..."
        URLSession.shared.dataTask(with: funscriptURL) { [weak self] data, response, error in
            guard let self = self, let data = data else { return }
            
            do {
                let script = try JSONDecoder().decode(Funscript.self, from: data)
                DispatchQueue.main.async {
                    self.currentScript = script
                    self.isSyncing = true
                    self.statusMessage = "Script Loaded"
                    print("✅ Buttplug: Loaded script with \(script.actions?.count ?? 0) actions")
                }
            } catch {
                print("❌ Buttplug: Failed to parse Funscript: \(error)")
                DispatchQueue.main.async {
                    self.statusMessage = "Script Error"
                }
            }
        }.resume()
    }
    
    func play(at seconds: Double) {
        guard isConnected, isSyncing, currentScript != nil else { return }
        
        lastPlaybackTime = seconds
        lastCommandSentAt = 0 // Reset to force immediate command
        isPlayingScript = true
        
        // Use CADisplayLink for high-precision sync
        syncTimer?.invalidate()
        syncTimer = CADisplayLink(target: self, selector: #selector(updateSync))
        syncTimer?.add(to: .main, forMode: .common)
    }
    
    func pause() {
        isPlayingScript = false
        syncTimer?.invalidate()
        syncTimer = nil
        stopAllDevices()
    }
    
    func stopAllDevices() {
        guard isConnected else { return }
        sendMessage([["StopAllDevices": ["Id": getNextMessageId()]]])
    }
    
    @objc private func updateSync() {
        guard isPlayingScript, let script = currentScript, let actions = script.actions, !actions.isEmpty else { return }
        
        // We assume the DisplayLink fires roughly every 16ms. 
        // We increment our local track of playback time.
        let frameDuration = 1.0 / 60.0 // Approximated
        lastPlaybackTime += frameDuration
        
        let currentMs = Int(lastPlaybackTime * 1000)
        
        // Find the index of the next action after currentMs
        // Simplified search:
        guard let nextIndex = actions.firstIndex(where: { $0.at > currentMs }) else {
            // End of script reached
            pause()
            return
        }
        
        // Only send a new command if we haven't sent one for this segment yet
        // A segment is defined by its target time 'at'
        let nextAction = actions[nextIndex]
        if Double(nextAction.at) != lastCommandSentAt {
            
            // Calculate duration from NOW to the next point
            let duration = nextAction.at - currentMs
            if duration > 0 {
                print("🎬 Buttplug Sync: Target \(nextAction.pos)% in \(duration)ms (Index: \(nextIndex))")
                sendMovement(position: Double(nextAction.pos), duration: duration)
                lastCommandSentAt = Double(nextAction.at)
            }
        }
    }
    
    private func sendMovement(position: Double, duration: Int) {
        guard isConnected else { return }
        if devices.isEmpty { return }
        
        var messages: [[String: Any]] = []
        for device in devices {
            if device.supportsLinear {
                messages.append([
                    "LinearCmd": [
                        "Id": getNextMessageId(),
                        "DeviceIndex": device.id,
                        "Vectors": [["Index": 0, "Duration": duration, "Position": position / 100.0]]
                    ]
                ])
            }
            if device.supportsScalar {
                messages.append([
                    "ScalarCmd": [
                        "Id": getNextMessageId(),
                        "DeviceIndex": device.id,
                        "Scalars": [["Index": 0, "Scalar": position / 100.0, "ActuatorType": "Vibrate"]]
                    ]
                ])
            }
        }
        
        if !messages.isEmpty {
            sendMessage(messages)
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default: break
                }
                self.receiveMessage()
            case .failure(let error):
                print("❌ Buttplug: Receive failed: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.statusMessage = "Offline"
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        
        for dict in array {
            if let _ = dict["ServerInfo"] as? [String: Any] {
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.statusMessage = "Connected"
                    self.startScanning()
                    self.requestDeviceList()
                }
            } else if let deviceAdded = dict["DeviceAdded"] as? [String: Any] {
                DispatchQueue.main.async {
                    if let id = deviceAdded["DeviceIndex"] as? Int,
                       let name = deviceAdded["DeviceName"] as? String,
                       let messages = deviceAdded["DeviceMessages"] as? [String: Any] {
                        if !self.devices.contains(where: { $0.id == id }) {
                            let supportsLinear = messages["LinearCmd"] != nil
                            let supportsScalar = messages["ScalarCmd"] != nil || messages["VibrateCmd"] != nil
                            self.devices.append(ButtplugDevice(id: id, name: name, supportsScalar: supportsScalar, supportsLinear: supportsLinear))
                            print("📱 Buttplug: Device Added: \(name) (Scalar: \(supportsScalar), Linear: \(supportsLinear))")
                        }
                    }
                }
            } else if let deviceRemoved = dict["DeviceRemoved"] as? [String: Any] {
                DispatchQueue.main.async {
                    if let id = deviceRemoved["DeviceIndex"] as? Int {
                        self.devices.removeAll(where: { $0.id == id })
                        print("📱 Buttplug: Device Removed (ID: \(id))")
                    }
                }
            } else if let deviceList = dict["DeviceList"] as? [String: Any],
                      let list = deviceList["Devices"] as? [[String: Any]] {
                DispatchQueue.main.async {
                    self.devices = list.compactMap { d -> ButtplugDevice? in
                        guard let id = d["DeviceIndex"] as? Int,
                              let name = d["DeviceName"] as? String,
                              let messages = d["DeviceMessages"] as? [String: Any] else { return nil }
                        let supportsLinear = messages["LinearCmd"] != nil
                        let supportsScalar = messages["ScalarCmd"] != nil || messages["VibrateCmd"] != nil
                        return ButtplugDevice(id: id, name: name, supportsScalar: supportsScalar, supportsLinear: supportsLinear)
                    }
                    print("📱 Buttplug: Found \(self.devices.count) devices")
                }
            } else if let _ = dict["Ok"] as? [String: Any] {
                // Acknowledgement
            } else if let error = dict["Error"] as? [String: Any] {
                print("⚠️ Buttplug Error: \(error["ErrorMessage"] ?? "Unknown")")
            }
        }
    }
    
    func requestDeviceList() {
        sendMessage([["RequestDeviceList": ["Id": getNextMessageId()]]])
    }
    
    // Command sending logic will be added here
}

struct ButtplugDevice: Identifiable, Equatable {
    let id: Int
    let name: String
    let supportsScalar: Bool
    let supportsLinear: Bool
}

// MARK: - Funscript Models

struct Funscript: Codable {
    let actions: [FunscriptAction]?
    let inverted: Bool?
    let range: Int?
    let version: String?
}

struct FunscriptAction: Codable {
    let at: Int // Time in milliseconds
    let pos: Int // Position 0-100
}
#endif


