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
import CoreBluetooth
import Synchronization

// MARK: - App Colors

extension Color {
    static let appAccent = Color(red: 0x64/255.0, green: 0x4C/255.0, blue: 0x3D/255.0)
    /// Default accent on a fresh install (matches the Gray preset).
    static let appDefaultTint = Color.gray

    static func appBackground(for theme: AppTheme) -> Color {
        #if os(tvOS)
        return Color(hex: "#161E2B")
        #else
        switch theme {
        case .darkBlue:
            return Color(hex: "#1E293B")
        default:
            return Color(UIColor.systemGroupedBackground)
        }
        #endif
    }

    static var appBackground: Color {
        appBackground(for: AppearanceManager.shared.currentTheme)
    }

    static func secondaryAppBackground(for theme: AppTheme) -> Color {
        #if os(tvOS)
        return Color(UIColor.separator).opacity(0.15)
        #else
        switch theme {
        case .darkBlue:
            return Color(hex: "#334155")
        default:
            return Color(UIColor.secondarySystemGroupedBackground)
        }
        #endif
    }

    static var secondaryAppBackground: Color {
        secondaryAppBackground(for: AppearanceManager.shared.currentTheme)
    }

    static func pillAccent(for theme: AppTheme) -> Color {
        #if os(tvOS)
        return .primary
        #else
        switch theme {
        case .darkBlue:
            return .white.opacity(0.9)
        default:
            return AppearanceManager.shared.tintColor
        }
        #endif
    }

    static var pillAccent: Color {
        pillAccent(for: AppearanceManager.shared.currentTheme)
    }

    static func studioHeaderGray(for theme: AppTheme) -> Color {
        theme == .darkBlue ? Color(hex: "#1E293B") : Color(red: 44/255.0, green: 44/255.0, blue: 46/255.0)
    }

    static var studioHeaderGray: Color {
        studioHeaderGray(for: AppearanceManager.shared.currentTheme)
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
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
    /// Which studios to list in live-filter dropdowns (`findStudios` + count filter + client sort).
    enum LiveFilterStudioPickerMode {
        /// Studios with at least one scene; sorted by scene count (desc).
        case scenesHasScenes
        /// Studios with at least one image; sorted by image count (desc).
        case imagesHasImages
        /// Studios with at least one gallery; sorted by gallery count (desc).
        case galleriesHasGalleries
    }

    @Published var isLoading = true
    @Published var errorMessage: String?
    /// Letzter Fehler von `findImages` (Katalog/Galerie/Detail). Getrennt von `errorMessage`, damit parallele Requests
    /// (z. B. `fetchSavedFilters`) den Verbindungsfehler der Bildliste nicht per `performGraphQLQuery` zurücksetzen.
    @Published var imageFindListError: String?
    @Published var serverStatus: String = "Nicht verbunden"
    
    /// Per-kind random seeds. Each content kind (scenes, previews, markers, ...)
    /// maintains an independent stable seed so "Random" sort order is not shared
    /// across types (e.g. Scenes and Previews must not coincide).
    enum RandomSeedKind: String, CaseIterable {
        case scenes, previews, markers, clips, images, galleries, performers, studios, tags, groups
    }

    private var randomSeeds: [RandomSeedKind: Int] = [:]

    private func seed(for kind: RandomSeedKind) -> Int {
        if let existing = randomSeeds[kind] { return existing }
        let new = Int.random(in: 1...1_000_000)
        randomSeeds[kind] = new
        return new
    }

    /// Formats a "random_<seed>" sort field for the given kind.
    private func randomSort(_ kind: RandomSeedKind) -> String {
        "random_\(seed(for: kind))"
    }

    // MARK: Per-kind API
    func refreshRandomSeed(for kind: RandomSeedKind) {
        randomSeeds[kind] = Int.random(in: 1...1_000_000)
    }

    func setRandomSeed(_ seed: Int, for kind: RandomSeedKind) {
        randomSeeds[kind] = seed
    }

    func getRandomSeed(for kind: RandomSeedKind) -> Int {
        seed(for: kind)
    }

    // MARK: Legacy API (broadcast to all kinds for backwards compatibility)
    func refreshRandomSeed() {
        for kind in RandomSeedKind.allCases {
            randomSeeds[kind] = Int.random(in: 1...1_000_000)
        }
    }

    func setRandomSeed(_ seed: Int) {
        for kind in RandomSeedKind.allCases {
            randomSeeds[kind] = seed
        }
    }

    func getRandomSeed() -> Int {
        seed(for: .scenes)
    }

    enum FilterMode: String, Codable {
        case scenes = "SCENES"
        case performers = "PERFORMERS"
        case studios = "STUDIOS"
        case galleries = "GALLERIES"
        case images = "IMAGES"
        case tags = "TAGS"
        case groups = "GROUPS"
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
        /// Stash UI / plugin metadata; stashy uses `stashy` key for live-preset round-trip (see ScenesView).
        let ui_options: StashJSONValue?
        /// Server-side list sort (`findScenes` / `findImages` `FindFilterType`).
        var find_filter: SavedFindFilter? = nil
        
        var filterDict: [String: Any]? {
            if let obj = object_filter {
                return obj.value as? [String: Any]
            }
            return uiFilterJSON
        }

        /// Raw Stash UI filter JSON (`sortby` / `sortdir` live here, not in `object_filter`).
        var uiFilterJSON: [String: Any]? {
            guard let str = filter, let data = str.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        /// Sort encoded on the filter: stashy `sortRaw`, then `find_filter`, then the UI JSON.
        var encodedSortPair: (field: String, direction: String)? {
            if let field = find_filter?.sort?.trimmingCharacters(in: .whitespacesAndNewlines), !field.isEmpty {
                let dir = find_filter?.direction?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (field, (dir?.isEmpty == false ? dir! : "DESC"))
            }
            if let dict = uiFilterJSON {
                let field = (dict["sort"] as? String)
                    ?? (dict["sortby"] as? String)
                    ?? (dict["sortBy"] as? String)
                let dir = (dict["direction"] as? String)
                    ?? (dict["sortdir"] as? String)
                    ?? (dict["sortDirection"] as? String)
                    ?? (dict["dir"] as? String)
                if let field, !field.isEmpty {
                    return (field, (dir?.isEmpty == false ? dir! : "DESC"))
                }
            }
            return nil
        }

        var stashySortRaw: String? {
            guard let ui = Self.stringKeyed(ui_options?.value),
                  let stashy = Self.stringKeyed(ui["stashy"]) else { return nil }
            if let raw = stashy["sortRaw"] as? String {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }

        /// Live-chip fragment written by stashy (`ui_options.stashy.liveFragment`).
        var stashyLiveFragment: [String: Any] {
            guard let ui = Self.stringKeyed(ui_options?.value),
                  let stashy = Self.stringKeyed(ui["stashy"]),
                  let live = Self.stringKeyed(stashy["liveFragment"]) else { return [:] }
            return live
        }

        var resolvedSceneSort: SceneSortOption? {
            if let raw = stashySortRaw, let opt = SceneSortOption(rawValue: raw) { return opt }
            if let pair = encodedSortPair { return SceneSortOption(graphqlField: pair.field, direction: pair.direction) }
            return nil
        }

        var resolvedImageSort: ImageSortOption? {
            if let raw = stashySortRaw, let opt = ImageSortOption(rawValue: raw) { return opt }
            if let pair = encodedSortPair { return ImageSortOption(graphqlField: pair.field, direction: pair.direction) }
            return nil
        }

        private static func stringKeyed(_ value: Any?) -> [String: Any]? {
            if let dict = value as? [String: Any] { return dict }
            if let dict = value as? [AnyHashable: Any] {
                var out: [String: Any] = [:]
                for (k, v) in dict {
                    if let s = k as? String { out[s] = v }
                }
                return out.isEmpty ? nil : out
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

    struct SavedFindFilter: Codable, Equatable {
        let sort: String?
        let direction: String?
    }

    struct SavedFiltersData: Codable {
        let findSavedFilters: [SavedFilter]
    }

    struct SavedFiltersResponse: Codable {
        let data: SavedFiltersData?
    }

    private struct SaveFilterGraphQLData: Codable {
        let saveFilter: SavedFilter
    }

    private struct SaveFilterGraphQLEnvelope: Codable {
        let data: SaveFilterGraphQLData?
        let errors: [GraphQLSavedFilterError]?
    }

    private struct DestroyFilterGraphQLData: Codable {
        let destroySavedFilter: Bool
    }

    private struct DestroyFilterGraphQLEnvelope: Codable {
        let data: DestroyFilterGraphQLData?
        let errors: [GraphQLSavedFilterError]?
    }

    private struct GraphQLSavedFilterError: Codable {
        let message: String
    }

    private var performerImageUpdatedObserver: NSObjectProtocol?
    private var imageRatingUpdatedObserver: NSObjectProtocol?
    private var imageOCounterUpdatedObserver: NSObjectProtocol?
    private var sceneOCounterUpdatedObserver: NSObjectProtocol?
    private var sceneUpdatedObserver: NSObjectProtocol?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)

        performerImageUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PerformerImageUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let performerId = notification.userInfo?["performerId"] as? String,
                  let newImagePath = notification.userInfo?["newImagePath"] as? String else { return }
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchPerformerImageInLists(performerId: performerId, newImagePath: newImagePath)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TagImageUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let tagId = notification.userInfo?["tagId"] as? String,
                  let newImagePath = notification.userInfo?["newImagePath"] as? String else { return }
            let updatedAt = notification.userInfo?["updatedAt"] as? String
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchTagImageInLists(tagId: tagId, newImagePath: newImagePath, updatedAt: updatedAt)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneCoverUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String,
                  let updatedAt = notification.userInfo?["updatedAt"] as? String else { return }
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchSceneCoverInLists(sceneId: sceneId, updatedAt: updatedAt)
            }
        }

        imageRatingUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageRatingUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let imageId = notification.userInfo?["imageId"] as? String else { return }
            let rating100 = notification.userInfo?["rating100"] as? Int
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchImageRatingInLists(imageId: imageId, rating100: rating100)
            }
        }

        imageOCounterUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ImageOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let imageId = notification.userInfo?["imageId"] as? String,
                  let oCounter = notification.userInfo?["oCounter"] as? Int else { return }
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchImageOCounterInLists(imageId: imageId, oCounter: oCounter)
            }
        }

        sceneOCounterUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneOCounterUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let sceneId = notification.userInfo?["sceneId"] as? String,
                  let oCounter = notification.userInfo?["oCounter"] as? Int else { return }
            let viewModel = self
            Task { @MainActor in
                viewModel?.patchSceneOCounterInLists(sceneId: sceneId, oCounter: oCounter)
            }
        }

        sceneUpdatedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SceneUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = Scene.fromListMetadataNotification(notification) else { return }
            let viewModel = self
            Task { @MainActor in
                viewModel?.mergeSceneListMetadata(scene)
            }
        }
        
        // Initial connection test if config exists (throttled — many VM instances
        // are created across tabs; the version is stable per session)
        if ServerConfigManager.shared.loadConfig()?.hasValidConfig == true {
             testConnection()
        }
    }
    
    deinit {
        if let performerImageUpdatedObserver {
            NotificationCenter.default.removeObserver(performerImageUpdatedObserver)
        }
        if let imageRatingUpdatedObserver {
            NotificationCenter.default.removeObserver(imageRatingUpdatedObserver)
        }
        if let imageOCounterUpdatedObserver {
            NotificationCenter.default.removeObserver(imageOCounterUpdatedObserver)
        }
        if let sceneOCounterUpdatedObserver {
            NotificationCenter.default.removeObserver(sceneOCounterUpdatedObserver)
        }
        if let sceneUpdatedObserver {
            NotificationCenter.default.removeObserver(sceneUpdatedObserver)
        }
        NotificationCenter.default.removeObserver(self)
    }


    @Published var savedFilters: [String: SavedFilter] = [:]
    @Published var isLoadingSavedFilters = false
    private var isInitializing = false
    
    /// Main entry point for starting/refreshing a server connection
    func initializeServerConnection() {
        guard !isInitializing else { return }
        isInitializing = true
        
        AppLog.debug("🚀 Starting staggered server initialization...")
        
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
                    AppLog.debug("✅ Staggered initialization sequence completed")
                    NotificationCenter.default.post(name: .stashServerInitializationFinished, object: nil)
                }
            }
        }
    }
    
    @objc private func handleServerChange() {
        Task { @MainActor in
            await GraphQLClient.shared.cancelAllRequests()
            self.isLoading = true
            self.resetData()
            AppLog.debug("🔄 StashDBViewModel reset due to server change")
            self.initializeServerConnection()
        }
    }
    
    // Home Row Caching - prevents reload on view recreation
    @Published var homeRowScenes: [HomeRowType: [Scene]] = [:]
    @Published var homeRowPerformers: [HomeRowType: [Performer]] = [:]
    @Published var homeRowStudios: [HomeRowType: [Studio]] = [:]
    @Published var homeRowGalleries: [HomeRowType: [Gallery]] = [:]
    @Published var homeRowLoadingState: [HomeRowType: Bool] = [:]
    private var isFetchingHomeRows: Set<HomeRowType> = []

    // Connection Status
    @Published var isServerConnected: Bool = false

    // Data properties
    @Published var statistics: Statistics?
    @Published var performerGenderCounts: [String: Int] = [:]
    @Published var isLoadingPerformerGenderCounts: Bool = false
    @Published var performerAggregates: PerformerAggregates?
    @Published var isLoadingPerformerAggregates: Bool = false
    @Published var sceneAggregates: SceneAggregates?
    @Published var isLoadingSceneAggregates: Bool = false
    @Published var scenes: [Scene] = []
    // Detailed Content for DetailViews (Tag, Performer, Studio)
    @Published var detailStudios: [Studio] = []
    @Published var detailTags: [Tag] = []
    @Published var detailGroups: [StashGroup] = []
    @Published var detailPerformers: [Performer] = []
    @Published var detailImages: [StashImage] = []
    
    @Published var totalDetailStudios = 0
    @Published var totalDetailTags = 0
    @Published var totalDetailGroups = 0
    @Published var totalDetailPerformers = 0
    @Published var totalDetailImages = 0
    
    @Published var isLoadingDetailStudios = false
    @Published var isLoadingDetailTags = false
    @Published var isLoadingDetailGroups = false
    @Published var isLoadingDetailPerformers = false
    @Published var isLoadingDetailImages = false
    
    var hasMoreDetailStudios = false
    var hasMoreDetailTags = false
    var hasMoreDetailGroups = false
    var hasMoreDetailPerformers = false
    var hasMoreDetailImages = false
    
    var currentDetailStudioPage = 1
    var currentDetailTagPage = 1
    var currentDetailGroupPage = 1
    var currentDetailPerformerPage = 1
    var currentDetailPerformerSortOption: PerformerSortOption = .nameAsc
    private var currentDetailTagSortOption: TagSortOption = .nameAsc
    private var currentDetailStudioSortOption: StudioSortOption = .nameAsc
    var currentDetailImagePage = 1
    private var currentDetailImageSortOption: ImageSortOption = .dateDesc
    /// Saved + live criteria for detail image tabs; reused when `fetchDetailImages` paginates (`isInitialLoad: false`).
    private var detailImagesActiveFilter: SavedFilter?
    private var detailImagesActiveLive: [String: Any] = [:]
    
    @Published var performers: [Performer] = []
    @Published var studios: [Studio] = []
    
    // Throttling states
    private var isFetchingFilters = false

    // Pagination properties for scenes
    @Published var totalScenes: Int = 0
    @Published var isLoadingScenes = false
    @Published var isLoadingMoreScenes = false
    @Published var hasMoreScenes = true
    private var currentScenePage = 1
    private var currentSceneSortOption: SceneSortOption = .dateDesc

    // Feed-paging safety valves. Client-side filtering (previews without a preview path,
    // markers without streams) and dedup against random-sort pages can otherwise page
    // through an entire library and hammer the server with unbounded requests.
    // Caps are deliberately generous: sparse libraries NEED many-page chases to
    // surface their first playable items.
    static let maxFeedNoProgressPages = 6
    static let maxFeedConsecutiveFailures = 3
    static let maxPreviewsEmptyChasePages = 30
    private var scenesNoProgressStreak = 0
    private var markersNoProgressStreak = 0
    private var previewsNoProgressStreak = 0
    private var clipsNoProgressStreak = 0
    private var previewsEmptyChaseCount = 0
    private var feedFailureStreaks: [String: Int] = [:]

    // Single-flight guard: TabView remounts fire `onAppear` multiple times, each
    // re-triggering an initial fetch that resets arrays while rows/players mount —
    // the root of the black-first-cell startup. Identical in-flight initial
    // requests are deduplicated per feed.
    private var scenesInitialInflightKey: String?
    private var markersInitialInflightKey: String?
    private var previewsInitialInflightKey: String?
    private var clipsInitialInflightKey: String?

    /// Visible Reels sub-feed. Prefetch / stale completions for other modes are dropped.
    enum ReelsFeedKind: String {
        case scenes, markers, clips, previews
    }

    /// Stable identity of a Reels page-1 query (sort + saved filter + live chips + overlay).
    struct ReelsFeedSignature: Equatable {
        let kind: ReelsFeedKind
        let sortField: String
        let direction: String
        let filterId: String?
        let liveKey: String
        let performerId: String?
        let tagIds: String
        let studioId: String?
    }

    private var activeReelsFeed: ReelsFeedKind?
    private var reelsFeedSignatures: [ReelsFeedKind: ReelsFeedSignature] = [:]
    private var streamPrefetchGeneration = 0

    func makeReelsFeedSignature(
        kind: ReelsFeedKind,
        sortField: String,
        direction: String,
        filterId: String?,
        liveFilter: [String: Any]?,
        performerId: String?,
        tagIds: [String],
        studioId: String?
    ) -> ReelsFeedSignature {
        ReelsFeedSignature(
            kind: kind,
            sortField: sortField,
            direction: direction,
            filterId: filterId,
            liveKey: liveFilterKey(liveFilter),
            performerId: performerId,
            tagIds: tagIds.sorted().joined(separator: ","),
            studioId: studioId
        )
    }

    func rememberReelsFeedSignature(_ signature: ReelsFeedSignature) {
        reelsFeedSignatures[signature.kind] = signature
    }

    /// True when this mode already has rows that match `signature` — skip a page-1 refetch.
    func hasWarmReelsFeed(_ kind: ReelsFeedKind, signature: ReelsFeedSignature) -> Bool {
        guard reelsFeedSignatures[kind] == signature else { return false }
        switch kind {
        case .scenes: return !scenes.isEmpty && !isLoadingScenes
        case .markers: return !sceneMarkers.isEmpty && !isLoadingMarkers
        case .clips: return !clips.isEmpty && !isLoadingClips
        case .previews: return !previews.isEmpty && !isLoadingPreviews
        }
    }

    /// Drop in-flight work for every Reels feed except `kind` so a mode switch
    /// does not keep hammering Stash (old find* + stream prefetch).
    func abandonInactiveReelsFeeds(keeping kind: ReelsFeedKind) {
        streamPrefetchGeneration += 1
        activeReelsFeed = kind
        if kind != .scenes {
            scenesFetchGeneration += 1
            scenesInitialInflightKey = nil
            isLoadingScenes = false
            isLoadingMoreScenes = false
        }
        if kind != .markers {
            markersFetchGeneration += 1
            markersInitialInflightKey = nil
            isLoadingMarkers = false
            isLoading = false
        }
        if kind != .clips {
            clipsFetchGeneration += 1
            clipsInitialInflightKey = nil
            isLoadingClips = false
        }
        if kind != .previews {
            previewsFetchGeneration += 1
            previewsInitialInflightKey = nil
            isLoadingPreviews = false
            isLoadingMorePreviews = false
        }
    }

    func setActiveReelsFeed(_ kind: ReelsFeedKind?) {
        if activeReelsFeed != kind {
            streamPrefetchGeneration += 1
        }
        activeReelsFeed = kind
    }

    func forgetAllReelsFeedSignatures() {
        reelsFeedSignatures.removeAll()
        streamPrefetchGeneration += 1
        activeReelsFeed = nil
    }

    private func feedCriteriaKey(_ parts: [String?]) -> String {
        parts.map { $0 ?? "-" }.joined(separator: "|")
    }

    private func liveFilterKey(_ liveFilter: [String: Any]?) -> String {
        guard let liveFilter else { return "none" }
        return liveFilter.keys.sorted().joined(separator: ",") + "#\(liveFilter.count)"
    }

    private func feedAllowsLoadMore(_ feed: String) -> Bool {
        (feedFailureStreaks[feed] ?? 0) < Self.maxFeedConsecutiveFailures
    }

    private func noteFeedFailure(_ feed: String) {
        feedFailureStreaks[feed] = (feedFailureStreaks[feed] ?? 0) + 1
        if feedFailureStreaks[feed] == Self.maxFeedConsecutiveFailures {
            AppLog.error("⚠️ Feed \(feed): \(Self.maxFeedConsecutiveFailures) consecutive page failures — pausing auto-paging")
            errorMessage = "Feed paused after repeated loading failures. Reopen or change filters to retry."
        }
    }

    private func resetFeedPagingState(_ feed: String) {
        feedFailureStreaks[feed] = 0
        switch feed {
        case "scenes": scenesNoProgressStreak = 0
        case "markers": markersNoProgressStreak = 0
        case "previews":
            previewsNoProgressStreak = 0
            previewsEmptyChaseCount = 0
        case "clips": clipsNoProgressStreak = 0
        default: break
        }
    }

    /// Returns true when paging should stop because the last pages added nothing new.
    private func noteFeedProgress(feed: String, addedCount: Int, isInitialLoad: Bool, markHasMore: (Bool) -> Void) {
        if isInitialLoad || addedCount > 0 {
            switch feed {
            case "scenes": scenesNoProgressStreak = 0
            case "markers": markersNoProgressStreak = 0
            case "previews": previewsNoProgressStreak = 0
            case "clips": clipsNoProgressStreak = 0
            default: break
            }
            return
        }
        let streak: Int
        switch feed {
        case "scenes": scenesNoProgressStreak += 1; streak = scenesNoProgressStreak
        case "markers": markersNoProgressStreak += 1; streak = markersNoProgressStreak
        case "previews": previewsNoProgressStreak += 1; streak = previewsNoProgressStreak
        case "clips": clipsNoProgressStreak += 1; streak = clipsNoProgressStreak
        default: streak = 0
        }
        if streak >= Self.maxFeedNoProgressPages {
            AppLog.debug("📥 Feed \(feed): \(streak) pages without new items — stopping pagination")
            markHasMore(false)
        }
    }
    #if os(tvOS)
    // tvOS has many large thumbnails on screen; smaller pages reduce memory spikes and crash risk.
    private let scenesPerPage = 12
    #else
    private let scenesPerPage = 20
    #endif
    @Published var currentSceneFilter: SavedFilter? = nil
    
    // Groups properties
    @Published var groups: [StashGroup] = []
    @Published var totalGroups: Int = 0
    @Published var isLoadingGroups = false
    @Published var isLoadingMoreGroups = false
    @Published var hasMoreGroups = true
    private var currentGroupPage = 1
    private var currentGroupSortOption: GroupSortOption = .nameAsc
    private let groupsPerPage = 20
    @Published var currentGroupFilter: SavedFilter? = nil
    /// Live criteria applied on top of `currentGroupFilter` (criteria editor).
    var currentGroupLiveFilter: [String: Any]? = nil
    private var currentGroupSearchQuery: String = ""

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

    // Previews properties
    @Published var previews: [Scene] = []
    @Published var totalPreviews: Int = 0
    @Published var isLoadingPreviews = false
    @Published var isLoadingMorePreviews = false
    @Published var hasMorePreviews = true
    private var currentPreviewPage = 1
    private var currentPreviewSortOption: SceneSortOption = .dateDesc
    private let previewsPerPage = 20
    @Published var currentPreviewFilter: SavedFilter? = nil
    private var currentPreviewSearchQuery: String = ""

    func clearSearchResults() {
        scenes = []
        performers = []
        studios = []
        tags = []
        groups = []
        galleries = []
    }
    
    // Pagination properties for performers
    @Published var totalPerformers: Int = 0
    @Published var isLoadingPerformers = false
    @Published var isLoadingMorePerformers = false
    @Published var hasMorePerformers = true
    @Published var currentPerformerFilter: SavedFilter? = nil
    var currentPerformerLiveFilter: [String: Any] = [:]
    private var currentPerformerPage = 1
    private let performersPerPage = 50
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
    var currentStudioLiveFilter: [String: Any] = [:]

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
        case imageCountDesc
        case imageCountAsc
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
            case .imageCountDesc: return "Image Count (High-Low)"
            case .imageCountAsc: return "Image Count (Low-High)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .titleAsc, .dateAsc, .ratingAsc, .createdAtAsc, .updatedAtAsc, .imageCountAsc: return "ASC"
            case .titleDesc, .dateDesc, .ratingDesc, .createdAtDesc, .updatedAtDesc, .imageCountDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .titleAsc, .titleDesc: return "title"
            case .dateDesc, .dateAsc: return "date"
            case .ratingDesc, .ratingAsc: return "rating"
            case .createdAtDesc, .createdAtAsc: return "created_at"
            case .updatedAtDesc, .updatedAtAsc: return "updated_at"
            case .imageCountDesc, .imageCountAsc: return "images_count"
            case .random: return "random"
            }
        }
    }
    
    var currentGallerySortOption: GallerySortOption = .dateDesc
    @Published var currentGalleryFilter: SavedFilter? = nil
    var currentGallerySearchQuery: String = ""
    var currentGalleryLiveFilter: [String: Any] = [:]

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
    var imageStaticPathFilter: Bool = false
    var imagePerformerIdFilter: String? = nil
    var currentImageLiveFilter: [String: Any] = [:]
    /// Free-text find filter (`q`) for catalog Images deep-link / search.
    var currentImageSearchQuery: String = ""

    /// Bumped on initial fetch / server reset so stale completions are ignored.
    private var imagesFetchGeneration = 0
    private var clipsFetchGeneration = 0
    private var scenesFetchGeneration = 0
    private var previewsFetchGeneration = 0
    private var markersFetchGeneration = 0

    /// Last filter/live used for `fetchGalleryImages` (pagination keeps same criteria).
    private var galleryImagesActiveGalleryId: String = ""
    private var galleryImagesActiveFilter: SavedFilter? = nil
    private var galleryImagesActiveLive: [String: Any] = [:]

    // MARK: - StashLine: criterion overlay snapshot (performer/tags)

    private struct StashLineFrozenImagesState {
        let allImages: [StashImage]
        let currentImagePage: Int
        let totalImages: Int
        let hasMoreImages: Bool
        let currentImageSortOption: ImageSortOption
        let currentImageFilter: SavedFilter?
        let imageStaticPathFilter: Bool
        let imagePerformerIdFilter: String?
        let visiblePostId: String?
    }

    private var stashLineFrozenImages: StashLineFrozenImagesState?

    func clearStashLineFrozenSnapshot() {
        stashLineFrozenImages = nil
    }

    func takeStashLineFrozenImagesSnapshot(visiblePostId: String?) {
        stashLineFrozenImages = StashLineFrozenImagesState(
            allImages: allImages,
            currentImagePage: currentImagePage,
            totalImages: totalImages,
            hasMoreImages: hasMoreImages,
            currentImageSortOption: currentImageSortOption,
            currentImageFilter: currentImageFilter,
            imageStaticPathFilter: imageStaticPathFilter,
            imagePerformerIdFilter: imagePerformerIdFilter,
            visiblePostId: visiblePostId
        )
    }

    @discardableResult
    func restoreStashLineFrozenImagesIfAvailable() -> String? {
        guard let s = stashLineFrozenImages else { return nil }
        allImages = s.allImages
        currentImagePage = s.currentImagePage
        totalImages = s.totalImages
        hasMoreImages = s.hasMoreImages
        currentImageSortOption = s.currentImageSortOption
        currentImageFilter = s.currentImageFilter
        imageStaticPathFilter = s.imageStaticPathFilter
        imagePerformerIdFilter = s.imagePerformerIdFilter
        isLoadingImages = false
        isLoading = false
        stashLineFrozenImages = nil
        return s.visiblePostId
    }

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

        init?(graphqlField field: String, direction: String) {
            let f = field.lowercased()
            if f.hasPrefix("random") {
                self = .random
                return
            }
            let isAsc = direction.uppercased() == "ASC"
            switch f {
            case "title": self = isAsc ? .titleAsc : .titleDesc
            case "date": self = isAsc ? .dateAsc : .dateDesc
            case "rating", "rating100": self = isAsc ? .ratingAsc : .ratingDesc
            case "created_at": self = isAsc ? .createdAtAsc : .createdAtDesc
            case "updated_at": self = isAsc ? .updatedAtAsc : .updatedAtDesc
            default: return nil
            }
        }
    }

    // Performer sort options
    enum PerformerSortOption: String, CaseIterable, DisplayNameProvider {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case imageCountDesc
        case imageCountAsc
        case galleryCountDesc
        case galleryCountAsc
        case birthdateDesc
        case birthdateAsc
        case updatedAtDesc
        case updatedAtAsc
        case createdAtDesc
        case createdAtAsc
        case oCountDesc
        case oCountAsc
        case ratingDesc
        case ratingAsc

        var displayName: String {
            switch self {
            case .nameAsc: return "Name (A-Z)"
            case .nameDesc: return "Name (Z-A)"
            case .sceneCountDesc: return "Scene Count (High-Low)"
            case .sceneCountAsc: return "Scene Count (Low-High)"
            case .imageCountDesc: return "Image Count (High-Low)"
            case .imageCountAsc: return "Image Count (Low-High)"
            case .galleryCountDesc: return "Gallery Count (High-Low)"
            case .galleryCountAsc: return "Gallery Count (Low-High)"
            case .birthdateDesc: return "Birthday (Youngest First)"
            case .birthdateAsc: return "Birthday (Oldest First)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .oCountDesc: return "O Count (High-Low)"
            case .oCountAsc: return "O Count (Low-High)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .imageCountAsc, .galleryCountAsc, .birthdateAsc, .updatedAtAsc, .createdAtAsc, .oCountAsc, .ratingAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .imageCountDesc, .galleryCountDesc, .birthdateDesc, .updatedAtDesc, .createdAtDesc, .oCountDesc, .ratingDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .imageCountAsc, .imageCountDesc: return "images_count"
            case .galleryCountAsc, .galleryCountDesc: return "galleries_count"
            case .birthdateAsc, .birthdateDesc: return "birthdate"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .oCountAsc, .oCountDesc: return "o_counter"
            case .ratingAsc, .ratingDesc: return "rating"
            case .random: return "random"
            }
        }
    }

    // Studio sort options
    enum StudioSortOption: String, CaseIterable, DisplayNameProvider {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case updatedAtDesc
        case updatedAtAsc
        case createdAtDesc
        case createdAtAsc
        case ratingDesc
        case ratingAsc
        case performerCountDesc
        case performerCountAsc
        case galleryCountDesc
        case galleryCountAsc
        case imageCountDesc
        case imageCountAsc

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
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .performerCountDesc: return "Performer Count (High-Low)"
            case .performerCountAsc: return "Performer Count (Low-High)"
            case .galleryCountDesc: return "Gallery Count (High-Low)"
            case .galleryCountAsc: return "Gallery Count (Low-High)"
            case .imageCountDesc: return "Image Count (High-Low)"
            case .imageCountAsc: return "Image Count (Low-High)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .updatedAtAsc, .createdAtAsc, .ratingAsc, .performerCountAsc, .galleryCountAsc, .imageCountAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .updatedAtDesc, .createdAtDesc, .ratingDesc, .performerCountDesc, .galleryCountDesc, .imageCountDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .ratingAsc, .ratingDesc: return "rating"
            case .performerCountAsc, .performerCountDesc: return "performer_count"
            case .galleryCountAsc, .galleryCountDesc: return "galleries_count"
            case .imageCountAsc, .imageCountDesc: return "images_count"
            case .random: return "random"
            }
        }
    }

    // Scene sort options
    enum SceneSortOption: String, CaseIterable, DisplayNameProvider {
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
        case playDurationDesc
        case playDurationAsc
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
            case .playDurationDesc: return "Watch Time (High-Low)"
            case .playDurationAsc: return "Watch Time (Low-High)"
            case .oCounterDesc: return "Counter (High-Low)"
            case .oCounterAsc: return "Counter (Low-High)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .dateDesc, .createdAtDesc, .durationDesc, .lastPlayedAtDesc, .playCountDesc, .playDurationDesc, .oCounterDesc, .ratingDesc, .random: return "DESC"
            case .dateAsc, .createdAtAsc, .titleAsc, .durationAsc, .lastPlayedAtAsc, .playCountAsc, .playDurationAsc, .oCounterAsc, .ratingAsc: return "ASC"
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
            case .playDurationDesc, .playDurationAsc: return "play_duration"
            case .oCounterDesc, .oCounterAsc: return "o_counter"
            case .ratingDesc, .ratingAsc: return "rating"
            case .random: return "random"
            }
        }

        init?(graphqlField field: String, direction: String) {
            let f = field.lowercased()
            if f.hasPrefix("random") {
                self = .random
                return
            }
            let isAsc = direction.uppercased() == "ASC"
            switch f {
            case "date": self = isAsc ? .dateAsc : .dateDesc
            case "created_at": self = isAsc ? .createdAtAsc : .createdAtDesc
            case "title": self = isAsc ? .titleAsc : .titleDesc
            case "duration": self = isAsc ? .durationAsc : .durationDesc
            case "last_played_at": self = isAsc ? .lastPlayedAtAsc : .lastPlayedAtDesc
            case "play_count": self = isAsc ? .playCountAsc : .playCountDesc
            case "play_duration": self = isAsc ? .playDurationAsc : .playDurationDesc
            case "o_counter": self = isAsc ? .oCounterAsc : .oCounterDesc
            case "rating", "rating100": self = isAsc ? .ratingAsc : .ratingDesc
            default: return nil
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
    enum TagSortOption: String, CaseIterable, DisplayNameProvider {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case imageCountDesc
        case imageCountAsc
        case galleryCountDesc
        case galleryCountAsc
        case markerCountDesc
        case markerCountAsc
        case performerCountDesc
        case performerCountAsc
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
            case .imageCountDesc: return "Image Count (High-Low)"
            case .imageCountAsc: return "Image Count (Low-High)"
            case .galleryCountDesc: return "Gallery Count (High-Low)"
            case .galleryCountAsc: return "Gallery Count (Low-High)"
            case .markerCountDesc: return "Marker Count (High-Low)"
            case .markerCountAsc: return "Marker Count (Low-High)"
            case .performerCountDesc: return "Performer Count (High-Low)"
            case .performerCountAsc: return "Performer Count (Low-High)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .imageCountAsc, .galleryCountAsc, .markerCountAsc, .performerCountAsc, .updatedAtAsc, .createdAtAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .imageCountDesc, .galleryCountDesc, .markerCountDesc, .performerCountDesc, .updatedAtDesc, .createdAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .imageCountAsc, .imageCountDesc: return "images_count"
            case .galleryCountAsc, .galleryCountDesc: return "galleries_count"
            case .markerCountAsc, .markerCountDesc: return "scene_markers_count"
            case .performerCountAsc, .performerCountDesc: return "performers_count"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .random: return "random"
            }
        }
    }

    enum GroupSortOption: String, CaseIterable, DisplayNameProvider {
        case random
        case nameAsc
        case nameDesc
        case sceneCountDesc
        case sceneCountAsc
        case galleryCountDesc
        case galleryCountAsc
        case performerCountDesc
        case performerCountAsc
        case dateDesc
        case dateAsc
        case ratingDesc
        case ratingAsc
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
            case .galleryCountDesc: return "Gallery Count (High-Low)"
            case .galleryCountAsc: return "Gallery Count (Low-High)"
            case .performerCountDesc: return "Performer Count (High-Low)"
            case .performerCountAsc: return "Performer Count (Low-High)"
            case .dateDesc: return "Date (Newest First)"
            case .dateAsc: return "Date (Oldest First)"
            case .ratingDesc: return "Rating (High-Low)"
            case .ratingAsc: return "Rating (Low-High)"
            case .updatedAtDesc: return "Updated (Newest First)"
            case .updatedAtAsc: return "Updated (Oldest First)"
            case .createdAtDesc: return "Created (Newest First)"
            case .createdAtAsc: return "Created (Oldest First)"
            case .random: return "Random"
            }
        }

        var direction: String {
            switch self {
            case .nameAsc, .sceneCountAsc, .galleryCountAsc, .performerCountAsc, .dateAsc, .ratingAsc, .updatedAtAsc, .createdAtAsc: return "ASC"
            case .nameDesc, .sceneCountDesc, .galleryCountDesc, .performerCountDesc, .dateDesc, .ratingDesc, .updatedAtDesc, .createdAtDesc, .random: return "DESC"
            }
        }

        var sortField: String {
            switch self {
            case .nameAsc, .nameDesc: return "name"
            case .sceneCountAsc, .sceneCountDesc: return "scenes_count"
            case .galleryCountAsc, .galleryCountDesc: return "galleries_count"
            case .performerCountAsc, .performerCountDesc: return "performer_count"
            case .dateAsc, .dateDesc: return "date"
            case .ratingAsc, .ratingDesc: return "rating"
            case .updatedAtAsc, .updatedAtDesc: return "updated_at"
            case .createdAtAsc, .createdAtDesc: return "created_at"
            case .random: return "random"
            }
        }
    }

    // Detail View: Group Scenes
    @Published var groupScenes: [Scene] = []
    @Published var totalGroupScenes: Int = 0
    @Published var isLoadingGroupScenes = false
    @Published var hasMoreGroupScenes = true
    private var currentGroupScenePage = 1
    private let groupDetailPerPage = 20
    private var currentGroupDetailFilter: SavedFilter? = nil
    private var currentGroupSceneSortOption: SceneSortOption = .dateDesc
    private var currentGroupSceneSearchQuery: String = ""
    var currentGroupDetailSceneLiveFilter: [String: Any] = [:]

    // Detail View: Performer Galleries
    @Published var performerGalleries: [Gallery] = []
    @Published var groupGalleries: [Gallery] = []
    @Published var isLoadingPerformerGalleries = false
    @Published var isLoadingGroupGalleries = false
    @Published var isLoadingMorePerformerGalleries = false
    @Published var isLoadingMoreGroupGalleries = false
    @Published var hasMorePerformerGalleries = true
    @Published var hasMoreGroupGalleries = true
    private var currentPerformerGalleryPage = 1
    private var currentGroupGalleryPage = 1
    private var currentPerformerGallerySortOption: GallerySortOption = .dateDesc
    private var currentGroupGallerySortOption: GallerySortOption = .dateDesc
    private var currentPerformerGalleryFilter: SavedFilter?
    private var currentPerformerGalleryLive: [String: Any] = [:]
    private var currentGroupGalleryFilter: SavedFilter?
    private var currentGroupGalleryLive: [String: Any] = [:]
    @Published var totalPerformerGalleries: Int = 0
    @Published var totalGroupGalleries: Int = 0
    // Detail View: Studio Galleries
    @Published var studioGalleries: [Gallery] = []
    @Published var totalStudioGalleries: Int = 0
    @Published var isLoadingStudioGalleries: Bool = false
    @Published var isLoadingMoreStudioGalleries: Bool = false
    @Published var hasMoreStudioGalleries: Bool = false
    @Published var currentStudioGalleryPage: Int = 1
    private var currentStudioGallerySortOption: GallerySortOption = .dateDesc
    private var currentStudioGalleryFilter: SavedFilter?
    private var currentStudioGalleryLive: [String: Any] = [:]

    // Performer scenes
    @Published var performerScenes: [Scene] = []
    @Published var totalPerformerScenes: Int = 0
    @Published var isLoadingPerformerScenes = false
    @Published var hasMorePerformerScenes = true
    /// Wird nach dem ersten abgeschlossenen `fetchPerformerScenes` (Seite 1) gesetzt — Tab-/Header-Zahlen sollen nicht ewig veraltetes `Performer.sceneCount` aus der Listenkarte mischen, sonst bleibt die leere `ScenesView` aktiv und triggert Endlosschleifen über `onChange(savedFilters)`.
    @Published var performerDetailScenesInitialFetchCompleted = false
    private var currentPerformerScenePage = 1
    private var currentPerformerSceneSortOption: SceneSortOption = .dateDesc
    private var currentPerformerDetailFilter: SavedFilter? = nil
    private var currentPerformerSceneSearchQuery: String = ""
    /// Live scene criteria merged into performer-detail fetches; pagination reuses this until the next initial load.
    var currentPerformerDetailSceneLiveFilter: [String: Any] = [:]
    

    // Studio scenes
    @Published var studioScenes: [Scene] = []
    @Published var totalStudioScenes: Int = 0
    @Published var isLoadingStudioScenes = false
    @Published var hasMoreStudioScenes = true
    private var currentStudioScenePage = 1
    private var currentStudioSceneSortOption: SceneSortOption = .dateDesc
    private var currentStudioDetailFilter: SavedFilter? = nil
    private var currentStudioSceneSearchQuery: String = ""
    var currentStudioDetailSceneLiveFilter: [String: Any] = [:]
    
    // Tag Scenes
    @Published var tagScenes: [Scene] = []
    @Published var totalTagScenes: Int = 0
    @Published var isLoadingTagScenes = false
    @Published var hasMoreTagScenes = true
    private var currentTagScenePage = 1
    private var currentTagSceneSortOption: SceneSortOption = .dateDesc
    private var currentTagDetailFilter: SavedFilter? = nil
    private var currentTagSceneSearchQuery: String = ""
    var currentTagDetailSceneLiveFilter: [String: Any] = [:]

    /// True when tag-detail scene fetches include criteria beyond the tag scope (saved filter, live filter, or search).
    var isTagDetailSceneListConstrained: Bool {
        if currentTagDetailFilter != nil { return true }
        if !currentTagDetailSceneLiveFilter.isEmpty { return true }
        if !currentTagSceneSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    /// True when performer-detail scene fetches include criteria beyond the performer scope.
    var isPerformerDetailSceneListConstrained: Bool {
        if currentPerformerDetailFilter != nil { return true }
        if !currentPerformerDetailSceneLiveFilter.isEmpty { return true }
        if !currentPerformerSceneSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    /// True when studio-detail scene fetches include criteria beyond the studio scope.
    var isStudioDetailSceneListConstrained: Bool {
        if currentStudioDetailFilter != nil { return true }
        if !currentStudioDetailSceneLiveFilter.isEmpty { return true }
        if !currentStudioSceneSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
    
    @Published var tagGalleries: [Gallery] = []
    @Published var totalTagGalleries: Int = 0
    @Published var isLoadingTagGalleries = false
    @Published var isLoadingMoreTagGalleries = false
    @Published var hasMoreTagGalleries = true
    private var currentTagGalleryPage = 1
    private var currentTagGallerySortOption: GallerySortOption = .dateDesc
    private var currentTagGalleryFilter: SavedFilter?
    private var currentTagGalleryLive: [String: Any] = [:]

    private var cancellables = Set<AnyCancellable>()
    
    // Reset all data and pagination states (e.g. on server switch)
    func resetData() {
        scenes = []
        performers = []
        studios = []
        galleries = []
        tags = []
        allImages = []
        clips = []
        previews = []
        sceneMarkers = []
        
        homeRowScenes = [:]
        homeRowPerformers = [:]
        homeRowStudios = [:]
        homeRowGalleries = [:]
        homeRowLoadingState = [:]
        isServerConnected = false
        isInitializing = false // Reset initialization guard
        isLoading = true // Start in loading state
        isLoadingSavedFilters = false // Reset filter loading state
        errorMessage = nil
        imageFindListError = nil
        isFetchingStats = false
        lastStatsFetch = nil
        isFetchingFilters = false
        isFetchingHomeRows.removeAll()
        
        performerScenes = []
        studioScenes = []
        tagScenes = []
        groupScenes = []
        
        groupGalleries = []
        
        savedFilters = [:]
        statistics = nil
        
        totalScenes = 0
        totalPerformers = 0
        totalStudios = 0
        totalTags = 0
        totalGalleries = 0
        totalImages = 0
        totalTagScenes = 0
        totalGroupScenes = 0
        totalGroupGalleries = 0
        
        currentScenePage = 1
        currentPerformerPage = 1
        currentStudioPage = 1
        currentTagPage = 1
        currentGalleryPage = 1
        currentImagePage = 1
        currentClipsPage = 1
        currentGroupPage = 1
        currentGroupScenePage = 1
        currentGroupGalleryPage = 1
        currentMarkerPage = 1
        currentPreviewPage = 1
        
        hasMoreScenes = true
        hasMorePerformers = true
        hasMoreStudios = true
        hasMoreTags = true
        hasMoreGalleries = true
        hasMoreImages = true
        hasMoreClips = true
        hasMoreGroups = true
        hasMoreGroupScenes = true
        hasMoreGroupGalleries = true
        hasMoreMarkers = true
        hasMorePreviews = true
        
        isLoadingClips = false
        isLoadingImages = false
        isLoadingMoreScenes = false
        clearReelsCriterionFrozenSnapshots()
        
        imagesFetchGeneration += 1
        clipsFetchGeneration += 1
        scenesFetchGeneration += 1
        previewsFetchGeneration += 1
        markersFetchGeneration += 1
        streamPrefetchGeneration += 1
        reelsFeedSignatures.removeAll()
        activeReelsFeed = nil
        
        currentSceneSortOption = .dateDesc
        currentSceneFilter = nil
        
        currentMarkerSortOption = .createdAtDesc
        
        currentPerformerSortOption = .nameAsc
        currentPerformerFilter = nil
        
        currentStudioSortOption = .nameAsc
        currentStudioFilter = nil
        
        currentGallerySortOption = .dateDesc
        currentGalleryFilter = nil
        currentGalleryLiveFilter = [:]
        
        currentImageSortOption = .dateDesc
        currentImageFilter = nil
        currentImageLiveFilter = [:]
        currentImageSearchQuery = ""
        currentClipSortOption = .dateDesc
        currentClipFilter = nil
        currentClipLiveFilter = [:]
        currentTagSortOption = .nameAsc
        
        currentPerformerGalleryPage = 1
        currentStudioGalleryPage = 1
        hasMorePerformerGalleries = true
        hasMoreStudioGalleries = true
        currentPerformerGalleryFilter = nil
        currentPerformerGalleryLive = [:]
        currentStudioGalleryFilter = nil
        currentStudioGalleryLive = [:]
        currentTagGalleryFilter = nil
        currentTagGalleryLive = [:]
        currentGroupGalleryFilter = nil
        currentGroupGalleryLive = [:]
        detailImagesActiveFilter = nil
        detailImagesActiveLive = [:]
        
        // Detail View Filters
        currentPerformerDetailFilter = nil
        currentStudioDetailFilter = nil
        currentTagDetailFilter = nil
        currentGroupDetailFilter = nil
        currentGroupFilter = nil
        currentGroupLiveFilter = nil
        
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
        if performerScenes.contains(where: { $0.id == id }) {
            performerScenes.removeAll { $0.id == id }
            totalPerformerScenes = max(0, totalPerformerScenes - 1)
        }
        if studioScenes.contains(where: { $0.id == id }) {
            studioScenes.removeAll { $0.id == id }
            totalStudioScenes = max(0, totalStudioScenes - 1)
        }
        if tagScenes.contains(where: { $0.id == id }) {
            tagScenes.removeAll { $0.id == id }
            totalTagScenes = max(0, totalTagScenes - 1)
        }
        if groupScenes.contains(where: { $0.id == id }) {
            groupScenes.removeAll { $0.id == id }
            totalGroupScenes = max(0, totalGroupScenes - 1)
        }

        // Remove from home row caches
        for rowType in homeRowScenes.keys {
            homeRowScenes[rowType]?.removeAll { $0.id == id }
        }
    }

    /// Updates tag image path / updatedAt in the catalog tag list after a tag image mutation.
    func patchTagImageInLists(tagId: String, newImagePath: String, updatedAt: String?) {
        guard let idx = tags.firstIndex(where: { $0.id == tagId }) else { return }
        tags[idx].imagePath = newImagePath
        if let updatedAt { tags[idx].updatedAt = updatedAt }
    }

    /// Busts scene cover URLs in catalog lists after a cover mutation.
    func patchSceneCoverInLists(sceneId: String, updatedAt: String) {
        func patched(_ list: [Scene]) -> [Scene] {
            guard let idx = list.firstIndex(where: { $0.id == sceneId }) else { return list }
            guard list[idx].updatedAt != updatedAt else { return list }
            var copy = list
            copy[idx] = copy[idx].withUpdatedAt(updatedAt)
            return copy
        }
        let nextScenes = patched(scenes)
        if nextScenes != scenes { scenes = nextScenes }
        let nextPerformer = patched(performerScenes)
        if nextPerformer != performerScenes { performerScenes = nextPerformer }
        let nextStudio = patched(studioScenes)
        if nextStudio != studioScenes { studioScenes = nextStudio }
        let nextTag = patched(tagScenes)
        if nextTag != tagScenes { tagScenes = nextTag }
        let nextGroup = patched(groupScenes)
        if nextGroup != groupScenes { groupScenes = nextGroup }
        for key in homeRowScenes.keys {
            let current = homeRowScenes[key] ?? []
            let next = patched(current)
            if next != current { homeRowScenes[key] = next }
        }
    }

    /// Updates performer profile image path across in-memory lists after a gallery/image mutation.
    func patchPerformerImageInLists(performerId: String, newImagePath: String) {
        for key in homeRowPerformers.keys {
            guard var row = homeRowPerformers[key] else { continue }
            if let idx = row.firstIndex(where: { $0.id == performerId }) {
                var p = row[idx]
                p.imagePath = newImagePath
                row[idx] = p
                homeRowPerformers[key] = row
            }
        }
        if let idx = performers.firstIndex(where: { $0.id == performerId }) {
            var p = performers[idx]
            p.imagePath = newImagePath
            performers[idx] = p
        }

        var images = allImages
        var didChangeImages = false
        for i in images.indices {
            guard var mutablePerformers = images[i].performers,
                  let pIndex = mutablePerformers.firstIndex(where: { $0.id == performerId }) else { continue }
            mutablePerformers[pIndex].image_path = newImagePath
            images[i].performers = mutablePerformers
            didChangeImages = true
        }
        if didChangeImages {
            allImages = images
        }

        var updatedGalleries = galleries
        var didChangeGalleries = false
        for i in updatedGalleries.indices {
            guard var mutablePerformers = updatedGalleries[i].performers,
                  let pIndex = mutablePerformers.firstIndex(where: { $0.id == performerId }) else { continue }
            mutablePerformers[pIndex].image_path = newImagePath
            updatedGalleries[i].performers = mutablePerformers
            didChangeGalleries = true
        }
        if didChangeGalleries {
            galleries = updatedGalleries
        }
    }

    /// Removes an image from all lists without reloading
    func removeImage(id: String) {
        allImages.removeAll { $0.id == id }
        totalImages = max(0, totalImages - 1)

        // Remove from gallery images
        galleryImages.removeAll { $0.id == id }
        totalGalleryImages = max(0, totalGalleryImages - 1)

        clips.removeAll { $0.id == id }
        totalClips = max(0, totalClips - 1)
    }

    func imageInLists(id: String) -> StashImage? {
        allImages.first(where: { $0.id == id })
            ?? galleryImages.first(where: { $0.id == id })
            ?? detailImages.first(where: { $0.id == id })
            ?? clips.first(where: { $0.id == id })
    }

    /// Live-listener: patch `rating100` across in-memory image lists (FullScreen / feed sync).
    func patchImageRatingInLists(imageId: String, rating100: Int?) {
        func patch(_ list: inout [StashImage]) -> Bool {
            guard let idx = list.firstIndex(where: { $0.id == imageId }) else { return false }
            guard list[idx].rating100 != rating100 else { return false }
            list[idx] = list[idx].withRating(rating100)
            return true
        }
        _ = patch(&allImages)
        _ = patch(&galleryImages)
        _ = patch(&detailImages)
        _ = patch(&clips)
    }

    /// Live-listener: patch `o_counter` across in-memory image lists (FullScreen / feed sync).
    func patchImageOCounterInLists(imageId: String, oCounter: Int) {
        func patch(_ list: inout [StashImage]) -> Bool {
            guard let idx = list.firstIndex(where: { $0.id == imageId }) else { return false }
            guard list[idx].o_counter != oCounter else { return false }
            list[idx] = list[idx].withOCounter(oCounter)
            return true
        }
        _ = patch(&allImages)
        _ = patch(&galleryImages)
        _ = patch(&detailImages)
        _ = patch(&clips)
    }

    /// Live-listener: patch `o_counter` across in-memory scene lists.
    func patchSceneOCounterInLists(sceneId: String, oCounter: Int) {
        func patch(_ list: inout [Scene]) {
            guard let idx = list.firstIndex(where: { $0.id == sceneId }) else { return }
            guard list[idx].oCounter != oCounter else { return }
            list[idx] = list[idx].withOCounter(oCounter)
        }
        patch(&scenes)
        patch(&performerScenes)
        patch(&studioScenes)
        patch(&tagScenes)
        patch(&groupScenes)
        for (rowType, rowScenes) in homeRowScenes {
            var copy = rowScenes
            patch(&copy)
            homeRowScenes[rowType] = copy
        }
    }

    /// Live-listener: merge title / details / studio / performers / tags / groups / rating
    /// from Scene Detail onto list stubs without replacing files, paths, or play stats.
    func mergeSceneListMetadata(_ updatedScene: Scene) {
        func patched(_ list: [Scene]) -> [Scene] {
            guard let idx = list.firstIndex(where: { $0.id == updatedScene.id }) else { return list }
            let merged = list[idx].mergingListMetadata(from: updatedScene)
            guard merged != list[idx] else { return list }
            var copy = list
            copy[idx] = merged
            return copy
        }
        let nextScenes = patched(scenes)
        if nextScenes != scenes { scenes = nextScenes }
        let nextPerformer = patched(performerScenes)
        if nextPerformer != performerScenes { performerScenes = nextPerformer }
        let nextStudio = patched(studioScenes)
        if nextStudio != studioScenes { studioScenes = nextStudio }
        let nextTag = patched(tagScenes)
        if nextTag != tagScenes { tagScenes = nextTag }
        let nextGroup = patched(groupScenes)
        if nextGroup != groupScenes { groupScenes = nextGroup }
        for rowType in homeRowScenes.keys {
            let current = homeRowScenes[rowType] ?? []
            let next = patched(current)
            if next != current { homeRowScenes[rowType] = next }
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

        // Update tag scenes
        if let index = tagScenes.firstIndex(where: { $0.id == id }) {
            var updated = tagScenes[index]
            updated = updated.withResumeTime(newResumeTime)
            tagScenes[index] = updated
        }

        // Update group scenes
        if let index = groupScenes.firstIndex(where: { $0.id == id }) {
            var updated = groupScenes[index]
            updated = updated.withResumeTime(newResumeTime)
            groupScenes[index] = updated
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

    /// Increments playCount of a scene in place (used by SceneDetailView playback).
    func incrementScenePlayCount(id: String, by delta: Int = 1) {
        func bumped(_ current: Int?) -> Int {
            max(0, (current ?? 0) + delta)
        }

        if let index = scenes.firstIndex(where: { $0.id == id }) {
            let s = scenes[index]
            scenes[index] = s.withPlayCount(bumped(s.playCount))
        }
        if let index = performerScenes.firstIndex(where: { $0.id == id }) {
            let s = performerScenes[index]
            performerScenes[index] = s.withPlayCount(bumped(s.playCount))
        }
        if let index = studioScenes.firstIndex(where: { $0.id == id }) {
            let s = studioScenes[index]
            studioScenes[index] = s.withPlayCount(bumped(s.playCount))
        }
        if let index = tagScenes.firstIndex(where: { $0.id == id }) {
            let s = tagScenes[index]
            tagScenes[index] = s.withPlayCount(bumped(s.playCount))
        }
        if let index = groupScenes.firstIndex(where: { $0.id == id }) {
            let s = groupScenes[index]
            groupScenes[index] = s.withPlayCount(bumped(s.playCount))
        }
        for (rowType, rowScenes) in homeRowScenes {
            if let index = rowScenes.firstIndex(where: { $0.id == id }) {
                let s = rowScenes[index]
                homeRowScenes[rowType]?[index] = s.withPlayCount(bumped(s.playCount))
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
        
        let query = GraphQLQueries.findSavedFiltersQuery
        
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
                        AppLog.debug("✅ Fetched \(findResult.count) saved filters")
                        completion?(true)
                    } else {
                        AppLog.error("⚠️ Saved filters query successful but data is missing")
                        completion?(false)
                    }
                case .failure(let error):
                    AppLog.error("❌ Error fetching saved filters: \(error.localizedDescription)")
                    self.errorMessage = "Failed to load filters: \(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
    }

    /// Merges a base scene saved filter with live chip criteria (same rules as `findScenes`).
    /// Sanitize the base first so an empty UI `c` tags-criterion cannot overwrite live tags.
    func mergedSceneObjectFilterForSave(base: SavedFilter?, live: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]
        if let base {
            if let dict = base.filterDict, !dict.isEmpty {
                merged = sanitizeFilter(dict)
            } else if let obj = base.object_filter, let objDict = obj.value as? [String: Any], !objDict.isEmpty {
                merged = sanitizeFilter(objDict)
            }
        }
        let liveSan = sanitizeFilter(live)
        for (k, v) in liveSan {
            merged[k] = v
        }
        // Live chips: "Any" means omit the criterion. Do not keep a leftover tags/studios/groups
        // filter from the base saved filter (Stash UI would show that as "Any").
        for key in ["tags", "studios", "groups"] where liveSan[key] == nil {
            merged.removeValue(forKey: key)
        }
        return merged
    }

    /// Merges a base marker saved filter with **scene-style** live chips by nesting live criteria under
    /// `scene_filter` (``SceneMarkerFilterType``). Plain `mergedSceneObjectFilterForSave` flattens like `SceneFilterType`
    /// and yields invalid marker filters—Stash then returns no markers.
    func mergedMarkerObjectFilterForSave(base: SavedFilter?, live: [String: Any]) -> [String: Any] {
        var marker: [String: Any] = [:]
        if let base = base {
            if let dict = base.filterDict {
                marker = dict
            } else if let obj = base.object_filter, let objDict = obj.value as? [String: Any] {
                marker = objDict
            }
        }
        marker = sanitizeFilter(marker, isMarker: true)
        guard !live.isEmpty else { return marker }
        var sceneNested = (marker["scene_filter"] as? [String: Any]) ?? [:]
        let liveSan = sanitizeFilter(live, isMarker: false)
        for (k, v) in liveSan {
            sceneNested[k] = v
        }
        for key in ["tags", "studios", "groups"] where liveSan[key] == nil {
            sceneNested.removeValue(forKey: key)
        }
        marker["scene_filter"] = sanitizeFilter(sceneNested, isMarker: false)
        return sanitizeFilter(marker, isMarker: true)
    }

    /// Hoists scene-only keys mistakenly stored at the root of a marker filter (e.g. older stashy saves)
    /// into `scene_filter` before `findSceneMarkers`.
    private func normalizeSceneMarkerFilterForQuery(_ markerFilter: [String: Any]) -> [String: Any] {
        let hoistFromRoot: Set<String> = [
            "rating100", "organized", "interactive", "orientation", "performer_count",
            "resolution", "performer_favorite", "o_counter", "studios", "groups", "movies"
        ]
        var out = markerFilter
        var sceneNested = (out["scene_filter"] as? [String: Any]) ?? [:]
        for key in hoistFromRoot {
            if let v = out.removeValue(forKey: key) {
                sceneNested[key] = v
            }
        }
        if !sceneNested.isEmpty {
            out["scene_filter"] = sanitizeFilter(sceneNested, isMarker: false)
        }
        return sanitizeFilter(out, isMarker: true)
    }

    /// Creates or updates a **scene** saved filter on the Stash server (`saveFilter`).
    /// Stores stashy metadata in `ui_options` so the live-filter sheet can restore base filter, chips, and sort.
    func saveSceneSavedFilter(
        existingId: String?,
        name: String,
        sort: SceneSortOption,
        baseFilter: SavedFilter?,
        liveFragment: [String: Any],
        completion: @escaping (Result<SavedFilter, Error>) -> Void
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "stashy", code: -2, userInfo: [NSLocalizedDescriptionKey: "Name is empty"])))
            return
        }
        let merged = mergedSceneObjectFilterForSave(base: baseFilter, live: liveFragment)
        var stashy: [String: Any] = [
            "liveFragment": liveFragment,
            "sortRaw": sort.rawValue
        ]
        if let bid = baseFilter?.id {
            stashy["baseSavedFilterId"] = bid
        }
        let uiOptions: [String: Any] = ["stashy": stashy]
        let sortField = sort.sortField == "random" ? "random" : sort.sortField
        let findFilter: [String: Any] = [
            "sort": sortField,
            "direction": sort.direction
        ]
        var input: [String: Any] = [
            "mode": FilterMode.scenes.rawValue,
            "name": trimmedName,
            "find_filter": findFilter,
            "object_filter": merged,
            "ui_options": uiOptions
        ]
        if let existingId = existingId {
            input["id"] = existingId
        }
        let variables: [String: Any] = ["input": input]
        let mutation = GraphQLQueries.saveSceneFilterMutation
        GraphQLClient.shared.execute(query: mutation, variables: variables) { [weak self] (result: Result<SaveFilterGraphQLEnvelope, GraphQLNetworkError>) in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .success(let env):
                    if let err = env.errors?.first?.message {
                        self.errorMessage = err
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                        return
                    }
                    guard let saved = env.data?.saveFilter else {
                        let msg = "Save filter response missing data"
                        self.errorMessage = msg
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                        return
                    }
                    self.savedFilters[saved.id] = saved
                    self.fetchSavedFilters()
                    completion(.success(saved))
                case .failure(let error):
                    self.handleNetworkError(error)
                    completion(.failure(error))
                }
            }
        }
    }

    /// Creates or updates a **catalog list** saved filter on the server (`saveFilter`) for performers, tags, or studios.
    /// `sortRaw` is persisted in `ui_options.stashy` for stashy round-trip; `sortField` / `sortDirection` drive `find_filter`.
    func saveCatalogSavedFilter(
        mode: FilterMode,
        randomSeedKind: RandomSeedKind,
        existingId: String?,
        name: String,
        sortRaw: String,
        sortField: String,
        sortDirection: String,
        baseFilter: SavedFilter?,
        liveFragment: [String: Any],
        completion: @escaping (Result<SavedFilter, Error>) -> Void
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "stashy", code: -2, userInfo: [NSLocalizedDescriptionKey: "Name is empty"])))
            return
        }
        let merged = (mode == .sceneMarkers)
            ? mergedMarkerObjectFilterForSave(base: baseFilter, live: liveFragment)
            : mergedSceneObjectFilterForSave(base: baseFilter, live: liveFragment)
        var stashy: [String: Any] = [
            "liveFragment": liveFragment,
            "sortRaw": sortRaw
        ]
        if let bid = baseFilter?.id {
            stashy["baseSavedFilterId"] = bid
        }
        let uiOptions: [String: Any] = ["stashy": stashy]
        let sortResolved = sortField == "random" ? randomSort(randomSeedKind) : sortField
        let findFilter: [String: Any] = [
            "sort": sortResolved,
            "direction": sortDirection
        ]
        var input: [String: Any] = [
            "mode": mode.rawValue,
            "name": trimmedName,
            "find_filter": findFilter,
            "object_filter": merged,
            "ui_options": uiOptions
        ]
        if let existingId = existingId {
            input["id"] = existingId
        }
        let variables: [String: Any] = ["input": input]
        let mutation = GraphQLQueries.saveCatalogFilterMutation
        GraphQLClient.shared.execute(query: mutation, variables: variables) { [weak self] (result: Result<SaveFilterGraphQLEnvelope, GraphQLNetworkError>) in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .success(let env):
                    if let err = env.errors?.first?.message {
                        self.errorMessage = err
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                        return
                    }
                    guard let saved = env.data?.saveFilter else {
                        let msg = "Save filter response missing data"
                        self.errorMessage = msg
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                        return
                    }
                    self.savedFilters[saved.id] = saved
                    self.fetchSavedFilters()
                    completion(.success(saved))
                case .failure(let error):
                    self.handleNetworkError(error)
                    completion(.failure(error))
                }
            }
        }
    }

    /// Saves a full `object_filter` (full criteria editor / Tools → Filters).
    ///
    /// `liveFragment` defaults to the fragment already stored on `existingId`, so editing a filter in the
    /// criteria editor never destroys the chip metadata a filter was created with.
    func saveFullObjectFilter(
        mode: FilterMode,
        existingId: String?,
        name: String,
        sortField: String,
        sortDirection: String,
        sortRaw: String?,
        objectFilter: [String: Any],
        liveFragment: [String: Any]? = nil,
        randomSeedKind: RandomSeedKind? = nil,
        completion: @escaping (Result<SavedFilter, Error>) -> Void
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            completion(.failure(NSError(domain: "stashy", code: -2, userInfo: [NSLocalizedDescriptionKey: "Name is empty"])))
            return
        }
        let existing = existingId.flatMap { savedFilters[$0] }
        let sanitized = sanitizeFilter(objectFilter, isMarker: mode == .sceneMarkers)
        let resolvedFragment = liveFragment ?? existing?.stashyLiveFragment ?? [:]
        let stashy: [String: Any] = [
            "liveFragment": resolvedFragment,
            "sortRaw": sortRaw ?? "\(sortField)_\(sortDirection.lowercased())"
        ]
        let uiOptions: [String: Any] = ["stashy": stashy]
        let sortResolved: String
        if sortField == "random", let kind = randomSeedKind {
            sortResolved = randomSort(kind)
        } else {
            sortResolved = sortField
        }
        let findFilter: [String: Any] = [
            "sort": sortResolved,
            "direction": sortDirection
        ]
        var input: [String: Any] = [
            "mode": mode.rawValue,
            "name": trimmedName,
            "find_filter": findFilter,
            "object_filter": sanitized,
            "ui_options": uiOptions
        ]
        if let existingId {
            input["id"] = existingId
        }
        let variables: [String: Any] = ["input": input]
        let mutation = (mode == .scenes)
            ? GraphQLQueries.saveSceneFilterMutation
            : GraphQLQueries.saveCatalogFilterMutation
        GraphQLClient.shared.execute(query: mutation, variables: variables) { [weak self] (result: Result<SaveFilterGraphQLEnvelope, GraphQLNetworkError>) in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .success(let env):
                    if let err = env.errors?.first?.message {
                        self.errorMessage = err
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                        return
                    }
                    guard let saved = env.data?.saveFilter else {
                        let msg = "Save filter response missing data"
                        self.errorMessage = msg
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                        return
                    }
                    self.savedFilters[saved.id] = saved
                    completion(.success(saved))
                case .failure(let error):
                    self.handleNetworkError(error)
                    completion(.failure(error))
                }
            }
        }
    }

    /// Renames a saved filter without touching its criteria, sort or stashy metadata.
    func renameSavedFilter(
        _ filter: SavedFilter,
        to name: String,
        completion: @escaping (Result<SavedFilter, Error>) -> Void
    ) {
        let pair = filter.encodedSortPair ?? ("date", "DESC")
        saveFullObjectFilter(
            mode: filter.mode,
            existingId: filter.id,
            name: name,
            sortField: pair.field,
            sortDirection: pair.direction,
            sortRaw: filter.stashySortRaw,
            objectFilter: filter.filterDict ?? [:],
            liveFragment: filter.stashyLiveFragment,
            randomSeedKind: Self.randomSeedKind(for: filter.mode),
            completion: completion
        )
    }

    /// Random-sort seed bucket matching a filter mode.
    static func randomSeedKind(for mode: FilterMode) -> RandomSeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .performers: return .performers
        case .studios: return .studios
        case .tags: return .tags
        case .galleries: return .galleries
        case .images: return .images
        case .groups: return .groups
        case .sceneMarkers: return .markers
        case .unknown: return nil
        }
    }

    func destroySavedSceneFilter(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let mutation = GraphQLQueries.destroySavedFilterMutation
        let variables: [String: Any] = ["input": ["id": id]]
        GraphQLClient.shared.execute(query: mutation, variables: variables) { [weak self] (result: Result<DestroyFilterGraphQLEnvelope, GraphQLNetworkError>) in
            guard let self = self else { return }
            Task { @MainActor in
                switch result {
                case .success(let env):
                    if let err = env.errors?.first?.message {
                        self.errorMessage = err
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: err])))
                        return
                    }
                    guard env.data?.destroySavedFilter == true else {
                        let msg = "Could not delete saved filter"
                        self.errorMessage = msg
                        completion(.failure(NSError(domain: "graphql", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                        return
                    }
                    self.savedFilters.removeValue(forKey: id)
                    self.fetchSavedFilters()
                    completion(.success(()))
                case .failure(let error):
                    self.handleNetworkError(error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    func testConnection(force: Bool = false) {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            errorMessage = "Server configuration is missing or incomplete"
            AppLog.error("❌ Test connection: No valid server configuration found")
            return
        }

        // Passive checks (onAppear / init across many VM instances) are throttled
        // per server — the version does not change within a session.
        if !force {
            if let last = Self.lastConnectionCheckByServer[config.id],
               Date().timeIntervalSince(last) < Self.connectionCheckInterval {
                AppLog.debug("📱 Skipping throttled connection check (\(Int(Date().timeIntervalSince(last)))s ago)")
                return
            }
            Self.lastConnectionCheckByServer[config.id] = Date()
        }

        testConnection(with: config)
    }

    nonisolated private static let connectionCheckInterval: TimeInterval = 300
    nonisolated private static let lastConnectionCheckStore = Mutex<[UUID: Date]>([:])
    nonisolated private static var lastConnectionCheckByServer: [UUID: Date] {
        get { lastConnectionCheckStore.withLock { $0 } }
        set { lastConnectionCheckStore.withLock { $0 = newValue } }
    }

    func testConnection(with customConfig: ServerConfig) {
        isLoading = true // Show loading state during connection test
        errorMessage = nil

        // GraphQL query for version
        let versionQuery = GraphQLQueries.serverVersionQuery

        let urlString = "\(customConfig.baseURL)/graphql"
        // AppLog.debug("📱 Testing connection with custom config to: \(urlString)")
        // AppLog.debug("📱 Server config: Type=\(customConfig.connectionType), Domain=\(customConfig.domain), IP=\(customConfig.ipAddress), Port=\(customConfig.port)")

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL: \(urlString)"
            // isLoading = false
            return
        }

        var request = stashRequest(to: url, config: customConfig)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add API Key if available
        if let apiKey = customConfig.secureApiKey, !apiKey.isEmpty {
            AppLog.debug("📱 Test connection using \(AppLog.redacted(apiKey, label: "ApiKey"))")
        }

        request.httpBody = versionQuery.data(using: .utf8)
        AppLog.debug("📱 Testing version query against \(urlString)")

        StashNetworking.session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                // Debug: Show server response
                if let httpResponse = response as? HTTPURLResponse {
                    AppLog.debug("📱 Test Status Code: \(httpResponse.statusCode)")
                }
                #if DEBUG
                if let responseString = String(data: data, encoding: .utf8) {
                    AppLog.debug("📱 Server response: \(responseString.prefix(500))")
                }
                #endif
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
                        AppLog.error("❌ Connection Error: \(error.localizedDescription)")
                        self?.isServerConnected = false
                        self?.handleError(error)
                    }
                }
            } receiveValue: { [weak self] response in
                self?.isLoading = false
                let version = response.data?.version.version ?? "Unknown"
                AppLog.debug("📱 Version erhalten: \(version)")
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
        let statisticsQuery = GraphQLQueries.serverStatsQuery

        performGraphQLQuery(query: statisticsQuery) { [weak self] (response: StashStatisticsResponse?) in
            guard let self = self else { return }
            self.isFetchingStats = false
            self.lastStatsFetch = Date()

            if let stats = response?.data?.stats {
                DispatchQueue.main.async {
                    self.statistics = stats
                    self.errorMessage = nil
                    self.fetchMarkerCountStandalone()
                    completion?(true)
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Statistics could not be loaded"
                    completion?(false)
                }
            }
        }
    }

    // MARK: - Performer Statistics

    /// Counts performers by gender (only genders with count > 0 are returned).
    /// Uses paging to fetch all performers and aggregates locally.
    func fetchPerformerGenderCounts() {
        guard ServerConfigManager.shared.activeConfig != nil else {
            DispatchQueue.main.async {
                self.performerGenderCounts = [:]
                self.isLoadingPerformerGenderCounts = false
            }
            return
        }

        if isLoadingPerformerGenderCounts { return }
        isLoadingPerformerGenderCounts = true

        let query = GraphQLQueries.queryWithFragments("findPerformers")
        let perPage = 500

        var page = 1
        var counts: [String: Int] = [:]
        var totalCount: Int?

        func normalizeGenderKey(_ raw: String?) -> String? {
            guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s.uppercased()
        }

        func loadNextPage() {
            let filterDict: [String: Any] = [
                "page": page,
                "per_page": perPage,
                "sort": "name",
                "direction": "ASC"
            ]

            let variables: [String: Any] = [
                "filter": filterDict
            ]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                DispatchQueue.main.async { self.isLoadingPerformerGenderCounts = false }
                return
            }

            performGraphQLQuery(query: bodyString) { (response: PerformerGenderCountsResponse?) in
                guard let result = response?.data?.findPerformers else {
                    DispatchQueue.main.async { self.isLoadingPerformerGenderCounts = false }
                    return
                }

                if totalCount == nil { totalCount = result.count }

                for p in result.performers {
                    if let gender = normalizeGenderKey(p.gender) {
                        counts[gender, default: 0] += 1
                    }
                }

                let loadedSoFar = page * perPage
                if let total = totalCount, loadedSoFar >= total || result.performers.isEmpty {
                    DispatchQueue.main.async {
                        self.performerGenderCounts = counts.filter { $0.value > 0 }
                        self.isLoadingPerformerGenderCounts = false
                    }
                } else {
                    page += 1
                    loadNextPage()
                }
            }
        }

        loadNextPage()
    }

    func fetchPerformerAggregates() {
        guard ServerConfigManager.shared.activeConfig != nil else {
            DispatchQueue.main.async {
                self.performerAggregates = nil
                self.isLoadingPerformerAggregates = false
            }
            return
        }

        if isLoadingPerformerAggregates { return }
        isLoadingPerformerAggregates = true

        let query = GraphQLQueries.queryWithFragments("findPerformers")
        let perPage = 500

        var page = 1
        var totalCount: Int?

        var ratedCount = 0
        var ratingSum = 0
        var ratingMin: Int?
        var ratingMax: Int?

        var oCountCount = 0
        var oCountSum = 0
        var oCountMax: Int = 0

        func loadNextPage() {
            let filterDict: [String: Any] = [
                "page": page,
                "per_page": perPage,
                "sort": "name",
                "direction": "ASC"
            ]

            let variables: [String: Any] = ["filter": filterDict]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                DispatchQueue.main.async { self.isLoadingPerformerAggregates = false }
                return
            }

            performGraphQLQuery(query: bodyString) { (response: PerformerAggregatesResponse?) in
                guard let result = response?.data?.findPerformers else {
                    DispatchQueue.main.async { self.isLoadingPerformerAggregates = false }
                    return
                }

                if totalCount == nil { totalCount = result.count }

                for p in result.performers {
                    if let r = p.rating100 {
                        ratedCount += 1
                        ratingSum += r
                        ratingMin = min(ratingMin ?? r, r)
                        ratingMax = max(ratingMax ?? r, r)
                    }
                    if let o = p.oCounter {
                        oCountCount += 1
                        oCountSum += o
                        oCountMax = max(oCountMax, o)
                    }
                }

                let loadedSoFar = page * perPage
                if let total = totalCount, loadedSoFar >= total || result.performers.isEmpty {
                    let avgRating = ratedCount > 0 ? Double(ratingSum) / Double(ratedCount) : nil
                    let avgOCounter = oCountCount > 0 ? Double(oCountSum) / Double(oCountCount) : nil

                    DispatchQueue.main.async {
                        self.performerAggregates = PerformerAggregates(
                            totalCount: totalCount ?? 0,
                            ratedCount: ratedCount,
                            averageRating100: avgRating,
                            minRating100: ratingMin,
                            maxRating100: ratingMax,
                            oCounterCount: oCountCount,
                            averageOCounter: avgOCounter,
                            maxOCounter: oCountMax
                        )
                        self.isLoadingPerformerAggregates = false
                    }
                } else {
                    page += 1
                    loadNextPage()
                }
            }
        }

        loadNextPage()
    }

    func fetchSceneAggregates() {
        guard ServerConfigManager.shared.activeConfig != nil else {
            DispatchQueue.main.async {
                self.sceneAggregates = nil
                self.isLoadingSceneAggregates = false
            }
            return
        }

        if isLoadingSceneAggregates { return }
        isLoadingSceneAggregates = true

        let query = GraphQLQueries.loadQuery(named: "findScenesCompact")
        let perPage = 200

        var page = 1
        var totalCount: Int?

        var ratedCount = 0
        var ratingSum = 0
        var ratingMin: Int?
        var ratingMax: Int?

        var oCountCount = 0
        var oCountSum = 0
        var oCountMax: Int = 0

        var playCountCount = 0
        var playCountSum = 0
        var playCountMax: Int = 0

        var durationCount = 0
        var durationSum: Double = 0
        var durationMax: Double = 0

        func loadNextPage() {
            let filterDict: [String: Any] = [
                "page": page,
                "per_page": perPage,
                "sort": "date",
                "direction": "DESC"
            ]

            let variables: [String: Any] = [
                "filter": filterDict
            ]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                DispatchQueue.main.async { self.isLoadingSceneAggregates = false }
                return
            }

            performGraphQLQuery(query: bodyString) { (response: SceneAggregatesResponse?) in
                guard let result = response?.data?.findScenes else {
                    DispatchQueue.main.async { self.isLoadingSceneAggregates = false }
                    return
                }

                if totalCount == nil { totalCount = result.count }

                for s in result.scenes {
                    if let r = s.rating100 {
                        ratedCount += 1
                        ratingSum += r
                        ratingMin = min(ratingMin ?? r, r)
                        ratingMax = max(ratingMax ?? r, r)
                    }
                    if let o = s.oCounter {
                        oCountCount += 1
                        oCountSum += o
                        oCountMax = max(oCountMax, o)
                    }
                    if let p = s.playCount {
                        playCountCount += 1
                        playCountSum += p
                        playCountMax = max(playCountMax, p)
                    }
                    if let d = s.duration, d > 0 {
                        durationCount += 1
                        durationSum += d
                        durationMax = max(durationMax, d)
                    }
                }

                let loadedSoFar = page * perPage
                if let total = totalCount, loadedSoFar >= total || result.scenes.isEmpty {
                    let avgRating = ratedCount > 0 ? Double(ratingSum) / Double(ratedCount) : nil
                    let avgOCounter = oCountCount > 0 ? Double(oCountSum) / Double(oCountCount) : nil
                    let avgPlayCount = playCountCount > 0 ? Double(playCountSum) / Double(playCountCount) : nil
                    let avgDuration = durationCount > 0 ? durationSum / Double(durationCount) : nil

                    DispatchQueue.main.async {
                        self.sceneAggregates = SceneAggregates(
                            totalCount: totalCount ?? 0,
                            ratedCount: ratedCount,
                            averageRating100: avgRating,
                            minRating100: ratingMin,
                            maxRating100: ratingMax,
                            oCounterCount: oCountCount,
                            averageOCounter: avgOCounter,
                            maxOCounter: oCountMax,
                            playCountCount: playCountCount,
                            averagePlayCount: avgPlayCount,
                            maxPlayCount: playCountMax,
                            durationCount: durationCount,
                            averageDurationSeconds: avgDuration,
                            maxDurationSeconds: durationMax
                        )
                        self.isLoadingSceneAggregates = false
                    }
                } else {
                    page += 1
                    loadNextPage()
                }
            }
        }

        loadNextPage()
    }

    private var cachedMarkerCountKey: String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "cachedMarkerCount_\(serverID)"
    }

    private func fetchMarkerCountStandalone() {
        // Apply cached value immediately so the card never shows 0
        let cached = UserDefaults.standard.integer(forKey: cachedMarkerCountKey)
        if cached > 0 {
            DispatchQueue.main.async {
                guard let current = self.statistics, current.sceneMarkerCount == nil else { return }
                self.statistics = Statistics(
                    sceneCount: current.sceneCount,
                    scenesSize: current.scenesSize,
                    scenesDuration: current.scenesDuration,
                    imageCount: current.imageCount,
                    imagesSize: current.imagesSize,
                    galleryCount: current.galleryCount,
                    performerCount: current.performerCount,
                    studioCount: current.studioCount,
                    groupCount: current.groupCount,
                    movieCount: current.movieCount,
                    tagCount: current.tagCount,
                    totalOCount: current.totalOCount,
                    totalPlayDuration: current.totalPlayDuration,
                    totalPlayCount: current.totalPlayCount,
                    scenesPlayed: current.scenesPlayed,
                    sceneMarkerCount: cached
                )
            }
        }

        let markersCountQuery = GraphQLQueries.findSceneMarkersCountQuery
        performGraphQLQuery(query: markersCountQuery) { [weak self] (response: MarkersResponse?) in
            guard let self = self, let count = response?.data?.findSceneMarkers.count else { return }
            UserDefaults.standard.set(count, forKey: self.cachedMarkerCountKey)
            DispatchQueue.main.async {
                guard let current = self.statistics else { return }
                self.statistics = Statistics(
                    sceneCount: current.sceneCount,
                    scenesSize: current.scenesSize,
                    scenesDuration: current.scenesDuration,
                    imageCount: current.imageCount,
                    imagesSize: current.imagesSize,
                    galleryCount: current.galleryCount,
                    performerCount: current.performerCount,
                    studioCount: current.studioCount,
                    groupCount: current.groupCount,
                    movieCount: current.movieCount,
                    tagCount: current.tagCount,
                    totalOCount: current.totalOCount,
                    totalPlayDuration: current.totalPlayDuration,
                    totalPlayCount: current.totalPlayCount,
                    scenesPlayed: current.scenesPlayed,
                    sceneMarkerCount: count
                )
            }
        }
    }
    
    // Search query state for scenes
    private var currentSceneSearchQuery: String = ""
    var currentSceneLiveFilter: [String: Any] = [:]
    /// Live scene-style chips merged into Reels previews (`findScenes` previewOnly path).
    private var currentPreviewLiveFilter: [String: Any] = [:]
    /// Live scene criteria merged under `scene_marker_filter` → `scene_filter` for markers.
    private var currentMarkerLiveFilter: [String: Any] = [:]
    /// Live image chips merged into Reels clips (`findImages` + video path regex).
    private var currentClipLiveFilter: [String: Any] = [:]
    
    func fetchScenes(sortBy: SceneSortOption = .dateDesc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            let key = feedCriteriaKey([
                "scenes", sortBy.sortField, sortBy.direction, searchQuery,
                filter?.id, liveFilterKey(liveFilter)
            ])
            if scenesInitialInflightKey == key, isLoadingScenes {
                AppLog.debug("📥 fetchScenes: identical initial fetch already in flight — skipping")
                return
            }
            scenesInitialInflightKey = key

            scenesFetchGeneration += 1
            // Reset pagination — keep stale rows until the new page arrives so
            // Reels does not unmount the list (black first cell on remount).
            currentScenePage = 1
            isLoadingScenes = true
            isLoadingMoreScenes = false
            hasMoreScenes = true
            currentSceneSortOption = sortBy
            currentSceneFilter = filter
            currentSceneSearchQuery = searchQuery
            // `nil` means no live chips — must clear, otherwise a previous fetch's criteria (e.g. performer_favorite) sticks forever.
            currentSceneLiveFilter = liveFilter ?? [:]
        } else {
            isLoadingScenes = true
        }

        errorMessage = nil
        let page = isInitialLoad ? 1 : currentScenePage + 1
        loadScenesPage(page: page, sortBy: currentSceneSortOption, searchQuery: currentSceneSearchQuery, fetchGeneration: scenesFetchGeneration)
    }

    func loadMoreScenes() {
        guard !isLoadingMoreScenes, hasMoreScenes, feedAllowsLoadMore("scenes") else { return }
        let page = currentScenePage + 1
        loadScenesPage(page: page, sortBy: currentSceneSortOption, searchQuery: currentSceneSearchQuery, fetchGeneration: scenesFetchGeneration)
    }

    /// One-shot scene page that does not mutate catalog `scenes` (tvOS Feeds channels / playlist).
    func fetchScenePage(
        sortBy: SceneSortOption,
        filter: SavedFilter? = nil,
        page: Int = 1,
        perPage: Int = 20,
        completion: @escaping (_ scenes: [Scene], _ total: Int) -> Void
    ) {
        let query = GraphQLQueries.queryWithFragments("findScenes")
        let filterDict: [String: Any] = [
            "page": page,
            "per_page": perPage,
            "sort": sortBy.sortField == "random" ? randomSort(.scenes) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        var variables: [String: Any] = ["filter": filterDict]
        if let savedFilter = filter {
            var sceneFilter: [String: Any] = [:]
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
            if savedFilter.id != "merged_temp" {
                for (key, value) in sanitizeFilter(savedFilter.stashyLiveFragment) {
                    sceneFilter[key] = value
                }
            }
            if !sceneFilter.isEmpty {
                variables["scene_filter"] = sceneFilter
            }
        }
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([], 0)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            let result = response?.data?.findScenes
            let scenes = result?.scenes ?? []
            let total = result?.count ?? scenes.count
            DispatchQueue.main.async {
                completion(scenes, total)
            }
        }
    }

    /// One-shot clip page (video images) that does not mutate catalog `clips`.
    func fetchClipPage(
        sortBy: ImageSortOption,
        filter: SavedFilter? = nil,
        page: Int = 1,
        perPage: Int = 20,
        completion: @escaping (_ images: [StashImage], _ total: Int) -> Void
    ) {
        let query = GraphQLQueries.queryWithFragments("findImages")
        let videoRegex = "(?i).*\\.(mp4|gif|webp|mov|webm|m4v|mkv)$"
        var imageFilter: [String: Any] = [
            "path": [
                "value": videoRegex,
                "modifier": "MATCHES_REGEX"
            ]
        ]
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                for (key, value) in sanitizeFilter(dict) where key != "path" {
                    imageFilter[key] = value
                }
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                for (key, value) in sanitizeFilter(objDict) where key != "path" {
                    imageFilter[key] = value
                }
            }
            if savedFilter.id != "merged_temp" {
                for (key, value) in sanitizeFilter(savedFilter.stashyLiveFragment) where key != "path" {
                    imageFilter[key] = value
                }
            }
        }
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": sortBy.sortField == "random" ? randomSort(.images) : sortBy.sortField,
                "direction": sortBy.direction
            ],
            "image_filter": sanitizeFilter(imageFilter)
        ]
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([], 0)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
            let result = response?.data?.findImages
            let images = result?.images ?? []
            let total = result?.count ?? images.count
            DispatchQueue.main.async {
                completion(images, total)
            }
        }
    }

    func fetchPreviews(sortBy: SceneSortOption = .dateDesc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            let key = feedCriteriaKey([
                "previews", sortBy.sortField, sortBy.direction, searchQuery,
                filter?.id, liveFilterKey(liveFilter)
            ])
            if previewsInitialInflightKey == key, isLoadingPreviews {
                AppLog.debug("📥 fetchPreviews: identical initial fetch already in flight — skipping")
                return
            }
            previewsInitialInflightKey = key

            previewsFetchGeneration += 1
            currentPreviewPage = 1
            isLoadingPreviews = true
            isLoadingMorePreviews = false
            hasMorePreviews = true
            currentPreviewSortOption = sortBy
            currentPreviewFilter = filter
            currentPreviewSearchQuery = searchQuery
            currentPreviewLiveFilter = liveFilter ?? [:]
            isLoading = true
        } else {
            isLoadingPreviews = true
        }

        errorMessage = nil
        let page = isInitialLoad ? 1 : currentPreviewPage + 1
        loadScenesPage(page: page, sortBy: currentPreviewSortOption, searchQuery: currentPreviewSearchQuery, previewOnly: true, fetchGeneration: previewsFetchGeneration)
    }

    func loadMorePreviews() {
        guard !isLoadingMorePreviews, hasMorePreviews, feedAllowsLoadMore("previews") else { return }
        let page = currentPreviewPage + 1
        loadScenesPage(page: page, sortBy: currentPreviewSortOption, searchQuery: currentPreviewSearchQuery, previewOnly: true, fetchGeneration: previewsFetchGeneration)
    }

    func fetchSceneMarkers(sortBy: SceneMarkerSortOption = .createdAtDesc, searchQuery: String = "", filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        let key = feedCriteriaKey([
            "markers", sortBy.sortField, sortBy.direction, searchQuery,
            filter?.id, liveFilterKey(liveFilter)
        ])
        if markersInitialInflightKey == key, isLoadingMarkers {
            AppLog.debug("📥 fetchSceneMarkers: identical initial fetch already in flight — skipping")
            return
        }
        markersInitialInflightKey = key

        markersFetchGeneration += 1
        currentMarkerPage = 1
        currentMarkerSortOption = sortBy
        currentMarkerSearchQuery = searchQuery
        currentMarkerFilter = filter
        currentMarkerLiveFilter = liveFilter ?? [:]
        hasMoreMarkers = true
        isLoadingMarkers = true
        isLoading = true // Set global loading for initial markers load

        loadMarkersPage(page: currentMarkerPage, sortBy: sortBy, searchQuery: searchQuery, fetchGeneration: markersFetchGeneration)
    }

    func loadMoreMarkers() {
        guard !isLoadingMarkers, hasMoreMarkers, feedAllowsLoadMore("markers") else { return }
        let page = currentMarkerPage + 1
        loadMarkersPage(page: page, sortBy: currentMarkerSortOption, searchQuery: currentMarkerSearchQuery, fetchGeneration: markersFetchGeneration)
    }

    private func loadMarkersPage(page: Int, sortBy: SceneMarkerSortOption, searchQuery: String = "", fetchGeneration: Int) {
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
            "sort": sortBy.sortField == "random" ? randomSort(.markers) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !searchQuery.isEmpty {
            filterDict["q"] = searchQuery
        }
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        var markerFilter: [String: Any] = [:]
        if let savedFilter = currentMarkerFilter {
            if let dict = savedFilter.filterDict {
                markerFilter = sanitizeFilter(dict, isMarker: true)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                markerFilter = sanitizeFilter(objDict, isMarker: true)
            }
        }
        if !currentMarkerLiveFilter.isEmpty {
            var sceneNested = (markerFilter["scene_filter"] as? [String: Any]) ?? [:]
            let liveSan = sanitizeFilter(currentMarkerLiveFilter, isMarker: false)
            for (k, v) in liveSan {
                sceneNested[k] = v
            }
            markerFilter["scene_filter"] = sanitizeFilter(sceneNested, isMarker: false)
        }
        if !markerFilter.isEmpty {
            markerFilter = normalizeSceneMarkerFilterForQuery(markerFilter)
            variables["scene_marker_filter"] = markerFilter
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }

        performGraphQLQuery(query: bodyString) { (response: MarkersResponse?) in
            if let result = response?.data?.findSceneMarkers {
                DispatchQueue.main.async {
                    guard fetchGeneration == self.markersFetchGeneration else { return }
                    let rawMarkers = result.scene_markers ?? []
                    var addedCount = 0
                    if isInitialLoad {
                        self.markersInitialInflightKey = nil
                        self.sceneMarkers = rawMarkers
                        self.totalSceneMarkers = result.count
                        self.resetFeedPagingState("markers")
                    } else {
                        // Deduplicate: Only add markers that aren't already in the list
                        let existingIds = Set(self.sceneMarkers.map { $0.id })
                        let newMarkers = rawMarkers.filter { !existingIds.contains($0.id) }
                        self.sceneMarkers.append(contentsOf: newMarkers)
                        addedCount = newMarkers.count
                    }

                    self.hasMoreMarkers = rawMarkers.count == self.markersPerPage
                    if !isInitialLoad {
                        self.noteFeedProgress(feed: "markers", addedCount: addedCount, isInitialLoad: false) {
                            self.hasMoreMarkers = $0
                        }
                    }
                    self.currentMarkerPage = page
                    self.isLoadingMarkers = false
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    guard fetchGeneration == self.markersFetchGeneration else { return }
                    self.markersInitialInflightKey = nil
                    self.isLoadingMarkers = false
                    self.isLoading = false
                    self.errorMessage = "Could not load markers"
                    self.noteFeedFailure("markers")
                }
            }
        }
    }

    private func loadScenesPage(page: Int, sortBy: SceneSortOption, searchQuery: String = "", previewOnly: Bool = false, fetchGeneration: Int) {
        let isInitialLoad = (page == 1)
        if !previewOnly {
            if isInitialLoad {
                isLoadingScenes = true
            } else {
                isLoadingMoreScenes = true
            }
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
            "sort": sortBy.sortField == "random" ? randomSort(previewOnly ? .previews : .scenes) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !searchQuery.isEmpty {
            filterDict["q"] = searchQuery
        }
        
        var variables: [String: Any] = [
            "filter": filterDict
        ]
        
        if let savedFilter = previewOnly ? currentPreviewFilter : currentSceneFilter {
            if let dict = savedFilter.filterDict {
                let sanitized = sanitizeFilter(dict)
                #if DEBUG
                AppLog.debug("🔍 Scene Filter sanitized: \(sanitized)")
                #endif
                variables["scene_filter"] = sanitized
            } else if let obj = savedFilter.object_filter {
                // Also sanitize object_filter content to handle boolean flags and nested structures
                if let objDict = obj.value as? [String: Any] {
                    let sanitized = sanitizeFilter(objDict)
                    #if DEBUG
                    AppLog.debug("🔍 Object Filter sanitized: \(sanitized)")
                    #endif
                    variables["scene_filter"] = sanitized
                } else {
                    variables["scene_filter"] = obj.value
                }
            }
            let stashyLive = savedFilter.stashyLiveFragment
            if !stashyLive.isEmpty, savedFilter.id != "merged_temp" {
                var merged = (variables["scene_filter"] as? [String: Any]) ?? [:]
                for (key, value) in sanitizeFilter(stashyLive) {
                    merged[key] = value
                }
                variables["scene_filter"] = merged
            }
        }

        // Merge live filter on top of saved filter (Reels scenes vs previews use separate live dicts).
        let liveForThisQuery: [String: Any] = previewOnly ? currentPreviewLiveFilter : currentSceneLiveFilter
        if !liveForThisQuery.isEmpty {
            var merged = (variables["scene_filter"] as? [String: Any]) ?? [:]
            for (key, value) in liveForThisQuery {
                merged[key] = value
            }
            variables["scene_filter"] = sanitizeFilter(merged)
        }
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            AppLog.error("❌ Error constructing request body in loadScenesPage")
            return
        }
        
        #if DEBUG
        AppLog.debug("🔍 Debug loadScenesPage request body:")
        AppLog.debug(bodyString)
        #endif
        
        // Pass bodyString as the query argument
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let scenesResult = response?.data?.findScenes {
                DispatchQueue.main.async {
                    let expectedGen = previewOnly ? self.previewsFetchGeneration : self.scenesFetchGeneration
                    guard fetchGeneration == expectedGen else { return }
                    if previewOnly {
                        // Client-side filter: only keep scenes that actually have a preview path from the server
                        let scenesWithPreview = scenesResult.scenes.filter { scene in
                            guard let preview = scene.paths?.preview else { return false }
                            return !preview.isEmpty
                        }
                        if isInitialLoad {
                            self.previewsInitialInflightKey = nil
                        }
                        let hasMore = scenesResult.scenes.count == self.previewsPerPage
                        var addedCount = 0
                        if isInitialLoad {
                            self.previews = scenesWithPreview
                            self.totalPreviews = scenesResult.count
                            self.resetFeedPagingState("previews")
                        } else {
                            let existingIds = Set(self.previews.map { $0.id })
                            let newScenes = scenesWithPreview.filter { !existingIds.contains($0.id) }
                            self.previews.append(contentsOf: newScenes)
                            addedCount = newScenes.count
                        }
                        if !self.previews.isEmpty, self.errorMessage?.contains("previews") == true {
                            self.errorMessage = nil
                        }
                        self.hasMorePreviews = hasMore
                        self.currentPreviewPage = page

                        // If the filtered result is still empty but there are more pages,
                        // chase a limited number of pages so a sparse library cannot cause
                        // an unbounded request chain.
                        if self.previews.isEmpty && hasMore
                            && self.previewsEmptyChaseCount < Self.maxPreviewsEmptyChasePages {
                            self.previewsEmptyChaseCount += 1
                            AppLog.debug("📥 Previews empty after filter — chasing page \(page + 1) (\(self.previewsEmptyChaseCount)/\(Self.maxPreviewsEmptyChasePages))")
                            let nextPage = page + 1
                            self.loadScenesPage(page: nextPage, sortBy: self.currentPreviewSortOption, searchQuery: self.currentPreviewSearchQuery, previewOnly: true, fetchGeneration: fetchGeneration)
                            return
                        }

                        // Chase exhausted without a single preview — surface it instead
                        // of rendering a silent blank screen.
                        if self.previews.isEmpty {
                            let scanned = page * self.previewsPerPage
                            self.errorMessage = "No scenes with previews found in the first \(scanned) scenes."
                        }

                        if !isInitialLoad {
                            self.noteFeedProgress(feed: "previews", addedCount: addedCount, isInitialLoad: false) {
                                self.hasMorePreviews = $0
                            }
                        }

                        if isInitialLoad {
                            self.isLoadingPreviews = false
                            self.isLoading = false
                        } else {
                            self.isLoadingMorePreviews = false
                        }
                    } else {
                        var addedCount = 0
                        if isInitialLoad {
                            self.scenesInitialInflightKey = nil
                            self.scenes = scenesResult.scenes
                            self.totalScenes = scenesResult.count
                            self.resetFeedPagingState("scenes")
                            // Only the visible Scenes feed — never Markers/Clips/Previews.
                            if self.activeReelsFeed == .scenes {
                                self.prefetchSceneStreams(sceneIds: self.scenes.map { $0.id })
                            }
                        } else {
                            // Deduplicate: Only add scenes that aren't already in the list
                            let existingIds = Set(self.scenes.map { $0.id })
                            let newScenes = scenesResult.scenes.filter { !existingIds.contains($0.id) }
                            self.scenes.append(contentsOf: newScenes)
                            addedCount = newScenes.count
                        }

                        // Check if there are more pages
                        self.hasMoreScenes = scenesResult.scenes.count == self.scenesPerPage
                        if !isInitialLoad {
                            self.noteFeedProgress(feed: "scenes", addedCount: addedCount, isInitialLoad: false) {
                                self.hasMoreScenes = $0
                            }
                        }
                        self.currentScenePage = page

                        if isInitialLoad {
                            self.isLoadingScenes = false
                            self.errorMessage = nil // Success
                        } else {
                            self.isLoadingMoreScenes = false
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    let expectedGen = previewOnly ? self.previewsFetchGeneration : self.scenesFetchGeneration
                    guard fetchGeneration == expectedGen else { return }
                    if previewOnly {
                        if isInitialLoad {
                            self.previewsInitialInflightKey = nil
                            self.isLoadingPreviews = false
                            self.isLoading = false
                        } else {
                            self.isLoadingMorePreviews = false
                        }
                        self.noteFeedFailure("previews")
                    } else {
                        if isInitialLoad {
                            self.scenesInitialInflightKey = nil
                            self.isLoadingScenes = false
                        } else {
                            self.isLoadingMoreScenes = false
                        }
                        self.noteFeedFailure("scenes")
                    }
                    // Keep error message processing if present
                }
            }
        }
    }
    
    
    
    // MARK: - Home Tab Support
    
    /// Convenience: dispatch to the correct fetch method based on row content type.
    func refreshHomeRow(config: HomeRowConfig, limit: Int = 10) {
        switch config.type {
        case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
            fetchPerformersForHomeRow(config: config, limit: limit, forceRefresh: true) { _ in }
        case .newStudios, .studiosHighestSceneCount:
            fetchStudiosForHomeRow(config: config, limit: limit, forceRefresh: true) { _ in }
        case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
            fetchGalleriesForHomeRow(config: config, limit: limit, forceRefresh: true) { _ in }
        default:
            fetchScenesForHomeRow(config: config, limit: limit, forceRefresh: true) { _ in }
        }
    }

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
        case .statistics, .channels, .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating, .newStudios, .studiosHighestSceneCount, .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
            homeRowLoadingState[rowType] = false
            completion([])
            return
        }
        
        // Construct the query
        let perPage = limit
        
        // Apply stable random seed if sort is random
        let finalSortField = sortField == "random" ? randomSort(.scenes) : sortField
        
        let queryVariables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": perPage,
                "sort": finalSortField,
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
    
    func fetchPerformersForHomeRow(config: HomeRowConfig, limit: Int = 10, forceRefresh: Bool = false, completion: @escaping ([Performer]) -> Void) {
        let rowType = config.type
        
        // Return cached data immediately if available
        if !forceRefresh {
            if let cached = homeRowPerformers[rowType], !cached.isEmpty {
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
        
        let performerFilter: [String: Any] = [:]
        var sortField = "name"
        var sortDirection = "ASC"
        
        func setSort(_ option: PerformerSortOption) {
            sortField = option.sortField
            sortDirection = option.direction
        }
        
        switch config.type {
        case .newPerformers:
            setSort(.createdAtDesc)
        case .performersHighestSceneCount:
            setSort(.sceneCountDesc)
        case .performersHighestOCount:
            setSort(.oCountDesc)
        case .performersHighestRating:
            setSort(.ratingDesc)
        default:
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
            "performer_filter": performerFilter
        ]
        
        let gqlQuery = GraphQLQueries.queryWithFragments("findPerformers")
        
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
        
        performGraphQLQuery(query: bodyString) { [weak self] (response: PerformersResponse?) in
            DispatchQueue.main.async {
                self?.homeRowLoadingState[rowType] = false
                self?.isFetchingHomeRows.remove(rowType)
                let performers = response?.data?.findPerformers.performers ?? []
                // Cache the result
                self?.homeRowPerformers[rowType] = performers
                completion(performers)
            }
        }
    }
    
    func fetchStudiosForHomeRow(config: HomeRowConfig, limit: Int = 10, forceRefresh: Bool = false, completion: @escaping ([Studio]) -> Void) {
        let rowType = config.type
        
        // Return cached data immediately if available
        if !forceRefresh {
            if let cached = homeRowStudios[rowType], !cached.isEmpty {
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
        
        var sortField = "name"
        var sortDirection = "ASC"
        
        func setSort(_ option: StudioSortOption) {
            sortField = option.sortField
            sortDirection = option.direction
        }
        
        switch config.type {
        case .newStudios:
            setSort(.createdAtDesc)
        case .studiosHighestSceneCount:
            setSort(.sceneCountDesc)
        default:
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
            ]
        ]
        
        let gqlQuery = GraphQLQueries.queryWithFragments("findStudios")
        
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
        
        performGraphQLQuery(query: bodyString) { [weak self] (response: StudiosResponse?) in
            DispatchQueue.main.async {
                self?.homeRowLoadingState[rowType] = false
                self?.isFetchingHomeRows.remove(rowType)
                let studios = response?.data?.findStudios.studios ?? []
                // Cache the result
                self?.homeRowStudios[rowType] = studios
                completion(studios)
            }
        }
    }
    
    func fetchGalleriesForHomeRow(config: HomeRowConfig, limit: Int = 10, forceRefresh: Bool = false, completion: @escaping ([Gallery]) -> Void) {
        let rowType = config.type
        
        // Return cached data immediately if available
        if !forceRefresh {
            if let cached = homeRowGalleries[rowType], !cached.isEmpty {
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
        
        var sortField = "title"
        var sortDirection = "ASC"
        
        func setSort(_ option: GallerySortOption) {
            sortField = option.sortField
            sortDirection = option.direction
        }
        
        switch config.type {
        case .newGalleries:
            setSort(.createdAtDesc)
        case .recentlyUpdatedGalleries:
            setSort(.updatedAtDesc)
        case .galleriesHighestImageCount:
            setSort(.imageCountDesc)
        default:
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
            ]
        ]
        
        let gqlQuery = GraphQLQueries.queryWithFragments("findGalleries")
        
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
        
        performGraphQLQuery(query: bodyString) { [weak self] (response: GalleriesResponse?) in
            DispatchQueue.main.async {
                self?.homeRowLoadingState[rowType] = false
                self?.isFetchingHomeRows.remove(rowType)
                let galleries = response?.data?.findGalleries.galleries ?? []
                // Cache the result
                self?.homeRowGalleries[rowType] = galleries
                completion(galleries)
            }
        }
    }
    
    func mergeFilterWithCriteria(filter: SavedFilter?, performer: ScenePerformer? = nil, tags: [Tag] = [], studio: SceneStudio? = nil, mode: FilterMode = .scenes) -> SavedFilter {
        var baseDict: [String: Any] = [:]

        if let filter {
            if let dict = filter.filterDict {
                baseDict = dict
            } else if let obj = filter.object_filter, let objDict = obj.value as? [String: Any] {
                baseDict = objDict
            }
        }

        if let performer {
            AppLog.debug("🔍 mergeFilterWithCriteria: Forcing Performer \(performer.name) (\(performer.id))")
            // MultiCriterionInput — no `depth` (that field is only on HierarchicalMultiCriterionInput).
            baseDict["performers"] = ["modifier": "INCLUDES", "value": [performer.id]]
        }

        if !tags.isEmpty {
            AppLog.debug("🔍 mergeFilterWithCriteria: Forcing Tags \(tags.map { $0.name })")
            baseDict["tags"] = ["modifier": "INCLUDES", "value": tags.map(\.id), "depth": 0]
        }

        if let studio {
            AppLog.debug("🔍 mergeFilterWithCriteria: Forcing Studio \(studio.name) (\(studio.id))")
            baseDict["studios"] = ["modifier": "INCLUDES", "value": [studio.id], "depth": 0]
        }

        let jsonValue: StashJSONValue? = {
            if JSONSerialization.isValidJSONObject(baseDict),
               let data = try? JSONSerialization.data(withJSONObject: baseDict),
               let decoded = try? JSONDecoder().decode(StashJSONValue.self, from: data) {
                return decoded
            }
            return filter?.object_filter
        }()

        return SavedFilter(
            id: filter?.id ?? "merged_temp",
            name: filter?.name ?? "Merged Filter",
            mode: mode,
            filter: filter?.filter,
            object_filter: jsonValue,
            ui_options: filter?.ui_options,
            find_filter: filter?.find_filter
        )
    }
    
    private func sanitizeFilter(_ dict: [String: Any], isMarker: Bool = false) -> [String: Any] {
        return FilterMapper.sanitize(dict, isMarker: isMarker)
    }


    func fetchPerformerGalleries(performerId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentPerformerGalleryPage = 1
            currentPerformerGallerySortOption = sortBy
            currentPerformerGalleryFilter = filter
            currentPerformerGalleryLive = liveFilter ?? [:]
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
        let sortByToUse = isInitialLoad ? sortBy : currentPerformerGallerySortOption
        let sortField = sortByToUse.sortField == "random" ? randomSort(.galleries) : sortByToUse.sortField
        let sortDirection = sortByToUse.direction
        
        // Find galleries with performer filter
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        let scope: [String: Any] = [
            "performers": [
                "value": [performerId],
                "modifier": "INCLUDES"
            ]
        ]
        let effSaved = isInitialLoad ? filter : currentPerformerGalleryFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : currentPerformerGalleryLive
        let galleryFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(
            scope: scope,
            saved: effSaved,
            live: effLive.isEmpty ? nil : effLive
        )
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortField,
                "direction": sortDirection
            ],
            "gallery_filter": galleryFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingPerformerGalleries = false
                self.isLoadingMorePerformerGalleries = false
                self.hasMorePerformerGalleries = false
            }
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
                    self.isLoadingMorePerformerGalleries = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingPerformerGalleries = false
                    self.isLoadingMorePerformerGalleries = false
                    self.hasMorePerformerGalleries = false
                }
            }
        }
    }
    
    func loadMorePerformerGalleries(performerId: String) {
        if !isLoadingPerformerGalleries && hasMorePerformerGalleries {
            fetchPerformerGalleries(performerId: performerId, sortBy: currentPerformerGallerySortOption, isInitialLoad: false)
        }
    }
    
    
    func fetchStudioGalleries(studioId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentStudioGalleryPage = 1
            currentStudioGallerySortOption = sortBy
            currentStudioGalleryFilter = filter
            currentStudioGalleryLive = liveFilter ?? [:]
            totalStudioGalleries = 0
            isLoadingStudioGalleries = true
            hasMoreStudioGalleries = true
        } else {
            isLoadingStudioGalleries = true
        }
        errorMessage = nil
        
        let page = isInitialLoad ? 1 : currentStudioGalleryPage + 1
        
        // Sort Logic
        let sortByToUse = isInitialLoad ? sortBy : currentStudioGallerySortOption
        let sortField = sortByToUse.sortField == "random" ? randomSort(.galleries) : sortByToUse.sortField
        let sortDirection = sortByToUse.direction
        
        // Find galleries with studio filter
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        let scope: [String: Any] = [
            "studios": [
                "value": [studioId],
                "modifier": "INCLUDES"
            ]
        ]
        let effSaved = isInitialLoad ? filter : currentStudioGalleryFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : currentStudioGalleryLive
        let galleryFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(
            scope: scope,
            saved: effSaved,
            live: effLive.isEmpty ? nil : effLive
        )
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortField,
                "direction": sortDirection
            ],
            "gallery_filter": galleryFilterMerged
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
    
    func fetchPerformerScenes(
        performerId: String,
        sortBy: SceneSortOption = .dateDesc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil,
        searchQuery: String? = nil
    ) {
        // Prevent parallel page loads (tvOS detail grids fire onAppear aggressively).
        if !isInitialLoad && isLoadingPerformerScenes { return }

        if isInitialLoad {
            currentPerformerScenePage = 1
            currentPerformerSceneSortOption = sortBy
            currentPerformerDetailFilter = filter
            currentPerformerDetailSceneLiveFilter = liveFilter ?? [:]
            if let sq = searchQuery {
                currentPerformerSceneSearchQuery = sq
            }
            // performerScenes = [] <-- Don't clear to keep navigation stable
            isLoadingPerformerScenes = true
        } else {
            isLoadingPerformerScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentPerformerScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField == "random" ? randomSort(.scenes) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !currentPerformerSceneSearchQuery.isEmpty {
            filterDict["q"] = currentPerformerSceneSearchQuery
        }
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentPerformerDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        if !currentPerformerDetailSceneLiveFilter.isEmpty {
            for (key, value) in currentPerformerDetailSceneLiveFilter {
                sceneFilter[key] = value
            }
        }
        
        // Hard bind: always last so saved/live criteria cannot drop the performer scope.
        sceneFilter["performers"] = [
            "modifier": "INCLUDES",
            "value": [performerId]
        ]
        sceneFilter = sanitizeFilter(sceneFilter)
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingPerformerScenes = false
                self.hasMorePerformerScenes = false
                if isInitialLoad { self.performerDetailScenesInitialFetchCompleted = true }
            }
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
                        self.performerDetailScenesInitialFetchCompleted = true
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
                    self.hasMorePerformerScenes = false
                    if isInitialLoad { self.performerDetailScenesInitialFetchCompleted = true }
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
    
    // MARK: - Detail Content Fetching
    
    /// Merges optional saved filter with `scope` (parent-entity constraint wins on key collision), then applies `live`.
    private func mergeDetailScopeWithSavedAndLiveFilters(scope: [String: Any], saved: SavedFilter?, live: [String: Any]?) -> [String: Any] {
        var merged: [String: Any] = [:]
        if let saved {
            if let dict = saved.filterDict {
                merged = sanitizeFilter(dict)
            } else if let obj = saved.object_filter, let d = obj.value as? [String: Any] {
                merged = sanitizeFilter(d)
            }
        }
        for (k, v) in scope {
            merged[k] = v
        }
        if let live {
            for (k, v) in live {
                merged[k] = v
            }
        }
        return sanitizeFilter(merged)
    }
    
    func fetchDetailStudios(
        performerId: String? = nil,
        tagId: String? = nil,
        parentStudioId: String? = nil,
        groupId: String? = nil,
        sortBy: StudioSortOption = .nameAsc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil
    ) {
        if isInitialLoad {
            currentDetailStudioPage = 1
            currentDetailStudioSortOption = sortBy
            detailStudios = []
            isLoadingDetailStudios = true
            hasMoreDetailStudios = true
        } else {
            isLoadingDetailStudios = true
        }
        
        let page = isInitialLoad ? 1 : currentDetailStudioPage + 1
        let query = GraphQLQueries.queryWithFragments("findStudios")
        
        var studioScope: [String: Any] = [:]
        if let pid = performerId {
            studioScope["performers"] = ["value": [pid], "modifier": "INCLUDES"]
        }
        if let tid = tagId {
            studioScope["tags"] = ["value": [tid], "modifier": "INCLUDES"]
        }
        if let psid = parentStudioId {
            studioScope["parent_id"] = psid
        }
        if let gid = groupId {
            studioScope["groups"] = ["value": [gid], "modifier": "INCLUDES"]
        }
        
        let sortToUse = isInitialLoad ? sortBy : currentDetailStudioSortOption
        let sortField = sortToUse.sortField == "random" ? randomSort(.studios) : sortToUse.sortField
        let studioFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(scope: studioScope, saved: filter, live: liveFilter)
        
        let variables: [String: Any] = [
            "filter": ["page": page, "per_page": 20, "sort": sortField, "direction": sortToUse.direction],
            "studio_filter": studioFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingDetailStudios = false
                self.hasMoreDetailStudios = false
            }
            return
        }

        performGraphQLQuery(query: bodyString) { (response: StudiosResponse?) in
            DispatchQueue.main.async {
                if let result = response?.data?.findStudios {
                    if isInitialLoad {
                        self.detailStudios = result.studios
                        self.totalDetailStudios = result.count
                    } else {
                        self.detailStudios.append(contentsOf: result.studios)
                    }
                    self.hasMoreDetailStudios = result.studios.count == 20
                    self.currentDetailStudioPage = page
                } else {
                    self.hasMoreDetailStudios = false
                }
                self.isLoadingDetailStudios = false
            }
        }
    }
    
    func fetchDetailTags(
        performerId: String? = nil,
        studioId: String? = nil,
        groupId: String? = nil,
        sortBy: TagSortOption = .nameAsc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil
    ) {
        if isInitialLoad {
            currentDetailTagPage = 1
            currentDetailTagSortOption = sortBy
            detailTags = []
            isLoadingDetailTags = true
            hasMoreDetailTags = true
        } else {
            isLoadingDetailTags = true
        }
        
        let page = isInitialLoad ? 1 : currentDetailTagPage + 1
        let query = GraphQLQueries.queryWithFragments("findTags")
        
        var tagScope: [String: Any] = [:]
        if let pid = performerId {
            tagScope["performers"] = ["value": [pid], "modifier": "INCLUDES"]
        }
        if let sid = studioId {
            tagScope["studios"] = ["value": [sid], "modifier": "INCLUDES"]
        }
        if let gid = groupId {
            tagScope["groups"] = ["value": [gid], "modifier": "INCLUDES"]
        }
        
        let sortToUse = isInitialLoad ? sortBy : currentDetailTagSortOption
        let sortField = sortToUse.sortField == "random" ? randomSort(.tags) : sortToUse.sortField
        let tagFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(scope: tagScope, saved: filter, live: liveFilter)
        
        let variables: [String: Any] = [
            "filter": ["page": page, "per_page": 40, "sort": sortField, "direction": sortToUse.direction],
            "tag_filter": tagFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingDetailTags = false
                self.hasMoreDetailTags = false
            }
            return
        }

        performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
            DispatchQueue.main.async {
                if let result = response?.data?.findTags {
                    if isInitialLoad {
                        self.detailTags = result.tags
                        self.totalDetailTags = result.count
                    } else {
                        self.detailTags.append(contentsOf: result.tags)
                    }
                    self.hasMoreDetailTags = result.tags.count == 40
                    self.currentDetailTagPage = page
                } else {
                    self.hasMoreDetailTags = false
                }
                self.isLoadingDetailTags = false
            }
        }
    }
    
    func fetchDetailGroups(performerId: String? = nil, tagId: String? = nil, studioId: String? = nil, groupId: String? = nil, isInitialLoad: Bool = true) {
        if isInitialLoad {
            currentDetailGroupPage = 1
            detailGroups = []
            isLoadingDetailGroups = true
            hasMoreDetailGroups = true
        } else {
            isLoadingDetailGroups = true
        }
        
        let page = isInitialLoad ? 1 : currentDetailGroupPage + 1
        let query = GraphQLQueries.queryWithFragments("findGroups")
        
        var groupFilter: [String: Any] = [:]
        if let pid = performerId {
            groupFilter["performers"] = ["value": [pid], "modifier": "INCLUDES"]
        }
        if let tid = tagId {
            groupFilter["tags"] = ["value": [tid], "modifier": "INCLUDES"]
        }
        if let sid = studioId {
            groupFilter["studios"] = ["value": [sid], "modifier": "INCLUDES"]
        }
        if let gid = groupId {
             groupFilter["id"] = ["value": [gid], "modifier": "NOT_EQUALS"] // Don't show self in sub-groups?
        }
        
        let variables: [String: Any] = [
            "filter": ["page": page, "per_page": 20, "sort": "name", "direction": "ASC"],
            "group_filter": groupFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingDetailGroups = false
                self.hasMoreDetailGroups = false
            }
            return
        }

        performGraphQLQuery(query: bodyString) { (response: GroupsResponse?) in
            DispatchQueue.main.async {
                if let result = response?.data?.findGroups {
                    if isInitialLoad {
                        self.detailGroups = result.groups
                        self.totalDetailGroups = result.count
                    } else {
                        self.detailGroups.append(contentsOf: result.groups)
                    }
                    self.hasMoreDetailGroups = result.groups.count == 20
                    self.currentDetailGroupPage = page
                } else {
                    self.hasMoreDetailGroups = false
                }
                self.isLoadingDetailGroups = false
            }
        }
    }
    
    func fetchDetailPerformers(
        tagId: String? = nil,
        studioId: String? = nil,
        groupId: String? = nil,
        sortBy: PerformerSortOption = .nameAsc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil
    ) {
        if isInitialLoad {
            currentDetailPerformerPage = 1
            currentDetailPerformerSortOption = sortBy
            detailPerformers = []
            isLoadingDetailPerformers = true
            hasMoreDetailPerformers = true
        } else {
            isLoadingDetailPerformers = true
        }
        
        let page = isInitialLoad ? 1 : currentDetailPerformerPage + 1
        let query = GraphQLQueries.queryWithFragments("findPerformers")
        
        var performerScope: [String: Any] = [:]
        if let tid = tagId {
            performerScope["tags"] = ["value": [tid], "modifier": "INCLUDES"]
        }
        if let sid = studioId {
            performerScope["studios"] = ["value": [sid], "modifier": "INCLUDES"]
        }
        if let gid = groupId {
            performerScope["groups"] = ["value": [gid], "modifier": "INCLUDES"]
        }
        
        let sortByToUse = isInitialLoad ? sortBy : currentDetailPerformerSortOption
        let sortField = sortByToUse.sortField == "random" ? randomSort(.performers) : sortByToUse.sortField
        let performerFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(scope: performerScope, saved: filter, live: liveFilter)
        
        let variables: [String: Any] = [
            "filter": ["page": page, "per_page": 20, "sort": sortField, "direction": sortByToUse.direction],
            "performer_filter": performerFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { return }
              
        performGraphQLQuery(query: bodyString) { (response: PerformersResponse?) in
            DispatchQueue.main.async {
                if let result = response?.data?.findPerformers {
                    if isInitialLoad {
                        self.detailPerformers = result.performers
                        self.totalDetailPerformers = result.count
                    } else {
                        self.detailPerformers.append(contentsOf: result.performers)
                    }
                    self.hasMoreDetailPerformers = result.performers.count == 20
                    self.currentDetailPerformerPage = page
                }
                self.isLoadingDetailPerformers = false
            }
        }
    }
    
    func fetchDetailImages(performerId: String? = nil, tagId: String? = nil, studioId: String? = nil, groupId: String? = nil, sortBy: ImageSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentDetailImagePage = 1
            currentDetailImageSortOption = sortBy
            detailImagesActiveFilter = filter
            detailImagesActiveLive = liveFilter ?? [:]
            detailImages = []
            isLoadingDetailImages = true
            hasMoreDetailImages = true
        } else {
            isLoadingDetailImages = true
        }

        imageFindListError = nil
        
        let page = isInitialLoad ? 1 : currentDetailImagePage + 1
        let query = GraphQLQueries.queryWithFragments("findImages")
        
        var imageScope: [String: Any] = [:]
        if let pid = performerId {
            imageScope["performers"] = ["value": [pid], "modifier": "INCLUDES"]
        }
        if let tid = tagId {
            imageScope["tags"] = ["value": [tid], "modifier": "INCLUDES"]
        }
        if let sid = studioId {
            imageScope["studios"] = ["value": [sid], "modifier": "INCLUDES"]
        }
        if let gid = groupId {
            imageScope["groups"] = ["value": [gid], "modifier": "INCLUDES"]
        }
        
        let effSaved = isInitialLoad ? filter : detailImagesActiveFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : detailImagesActiveLive
        let imageFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(
            scope: imageScope,
            saved: effSaved,
            live: effLive.isEmpty ? nil : effLive
        )
        
        let sortByToUse = isInitialLoad ? sortBy : currentDetailImageSortOption
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 40,
                "sort": sortByToUse.sortField == "random" ? randomSort(.images) : sortByToUse.sortField,
                "direction": sortByToUse.direction
            ],
            "image_filter": imageFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingDetailImages = false
                let msg = "Could not load images"
                self.imageFindListError = msg
                self.errorMessage = msg
            }
            return
        }
              
        performGraphQLQuery(query: bodyString, clearsGlobalErrorMessageOnStart: false) { (response: ImagesResponse?) in
            DispatchQueue.main.async {
                if let result = response?.data?.findImages {
                    if isInitialLoad {
                        self.detailImages = result.images
                        self.totalDetailImages = result.count
                    } else {
                        self.detailImages.append(contentsOf: result.images)
                    }
                    self.hasMoreDetailImages = result.images.count == 40
                    self.currentDetailImagePage = page
                    self.errorMessage = nil
                    self.imageFindListError = nil
                } else {
                    self.hasMoreDetailImages = false
                    let msg = self.errorMessage ?? "Could not load images"
                    self.imageFindListError = msg
                    if self.errorMessage == nil {
                        self.errorMessage = msg
                    }
                }
                self.isLoadingDetailImages = false
            }
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
                    AppLog.error("❌ Performer mit ID \(performerId) nicht gefunden")
                    completion(nil)
                }
            }
        }
    }
    
    func fetchStudioScenes(
        studioId: String,
        sortBy: SceneSortOption = .dateDesc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil,
        searchQuery: String? = nil
    ) {
        if !isInitialLoad && isLoadingStudioScenes { return }

        if isInitialLoad {
            currentStudioScenePage = 1
            currentStudioSceneSortOption = sortBy
            currentStudioDetailFilter = filter
            currentStudioDetailSceneLiveFilter = liveFilter ?? [:]
            if let sq = searchQuery {
                currentStudioSceneSearchQuery = sq
            }
            isLoadingStudioScenes = true
        } else {
            isLoadingStudioScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentStudioScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField == "random" ? randomSort(.scenes) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !currentStudioSceneSearchQuery.isEmpty {
            filterDict["q"] = currentStudioSceneSearchQuery
        }
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentStudioDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        if !currentStudioDetailSceneLiveFilter.isEmpty {
            for (key, value) in currentStudioDetailSceneLiveFilter {
                sceneFilter[key] = value
            }
        }
        
        sceneFilter["studios"] = [
            "modifier": "INCLUDES",
            "value": [studioId]
        ]
        sceneFilter = sanitizeFilter(sceneFilter)
        
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
    
    func fetchPerformers(sortBy: PerformerSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentPerformerPage = 1
            performers = []
            totalPerformers = 0
            isLoadingPerformers = true
            hasMorePerformers = true
            currentPerformerSortOption = sortBy
            currentPerformerFilter = filter
            currentPerformerSearchQuery = searchQuery
            currentPerformerLiveFilter = liveFilter ?? [:]
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
        // Moderate page size keeps initial GraphQL payloads light; pagination loads more via `loadMorePerformers`.
        let effectivePerPage = performersPerPage
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": effectivePerPage,
            "sort": sortBy.sortField == "random" ? randomSort(.performers) : sortBy.sortField,
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
                AppLog.debug("🔍 PERFORMER filterDict raw: \(dict)")
                AppLog.debug("🔍 PERFORMER filterDict sanitized: \(sanitized)")
                variables["performer_filter"] = sanitized
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                AppLog.debug("🔍 PERFORMER object_filter raw: \(objDict)")
                let sanitized = sanitizeFilter(objDict)
                AppLog.debug("🔍 PERFORMER object_filter sanitized: \(sanitized)")
                variables["performer_filter"] = sanitized
            }
        }
        
        if !currentPerformerLiveFilter.isEmpty {
            var merged = (variables["performer_filter"] as? [String: Any]) ?? [:]
            for (key, value) in currentPerformerLiveFilter { merged[key] = value }
            variables["performer_filter"] = sanitizeFilter(merged)
        }
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            if isInitialLoad {
                isLoadingPerformers = false
            } else {
                isLoadingMorePerformers = false
            }
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
                    
                    self.hasMorePerformers = performersResult.performers.count == effectivePerPage
                    
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
    
    func fetchStudios(sortBy: StudioSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentStudioPage = 1
            currentStudioSortOption = sortBy
            currentStudioSearchQuery = searchQuery
            currentStudioFilter = filter
            hasMoreStudios = true
            studios = []
            isLoadingStudios = true
            currentStudioLiveFilter = liveFilter ?? [:]
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
            "sort": sortBy.sortField == "random" ? randomSort(.studios) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        // Add search query to FindFilterType (not studio_filter)
        if !searchQuery.isEmpty {
            filterParams["q"] = searchQuery
        }
        
        let variables: [String: Any] = [
            "filter": filterParams,
            "studio_filter": sanitizeFilter(currentStudioLiveFilter.isEmpty ? studioFilter : studioFilter.merging(currentStudioLiveFilter) { _, new in new })
        ]
        
        let query = GraphQLQueries.queryWithFragments("findStudios")
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            AppLog.error("❌ Error: Could not serialize Studios request body")
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
    var currentTagLiveFilter: [String: Any] = [:]
    private var currentTagPage = 1
    private let tagsPerPage = 500
    private var currentTagSortOption: TagSortOption = .nameAsc
    private var currentTagSearchQuery: String = ""
    
    
    func fetchTags(sortBy: TagSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentTagPage = 1
            tags = []
            currentTagLiveFilter = liveFilter ?? [:]
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
                "sort": sortBy.sortField == "random" ? randomSort(.tags) : sortBy.sortField,
                "direction": sortBy.direction
            ],
            "tag_filter": sanitizeFilter(currentTagLiveFilter.isEmpty ? tagFilter : tagFilter.merging(currentTagLiveFilter) { _, new in new })
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

    // MARK: - Group Fetching
    func fetchGroups(sortBy: GroupSortOption = .nameAsc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentGroupPage = 1
            groups = []
        }
        currentGroupSortOption = sortBy
        currentGroupSearchQuery = searchQuery
        currentGroupFilter = filter
        currentGroupLiveFilter = liveFilter
        hasMoreGroups = true
        
        loadGroupsPage(page: currentGroupPage, sortBy: sortBy, searchQuery: searchQuery, isInitialLoad: isInitialLoad, filter: filter, liveFilter: liveFilter)
    }
    
    func loadMoreGroups() {
        guard !isLoadingMoreGroups && hasMoreGroups else { return }
        currentGroupPage += 1
        loadGroupsPage(page: currentGroupPage, sortBy: currentGroupSortOption, searchQuery: currentGroupSearchQuery, isInitialLoad: false, filter: currentGroupFilter, liveFilter: currentGroupLiveFilter)
    }
    
    private func loadGroupsPage(page: Int, sortBy: GroupSortOption, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            isLoadingGroups = true
        } else {
            isLoadingMoreGroups = true
        }
        
        var groupFilter: [String: Any] = [:]
        
        // Use saved filter if provided
        if let savedFilter = filter {
            if let dict = savedFilter.filterDict {
                groupFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                groupFilter = sanitizeFilter(objDict)
            }
        }
        
        // Live criteria (criteria editor) override the saved filter per key.
        if let liveFilter, !liveFilter.isEmpty {
            for (key, value) in sanitizeFilter(liveFilter) {
                groupFilter[key] = value
            }
        }

        // Add search query to the filter
        if !searchQuery.isEmpty {
            groupFilter["name"] = [
                "value": searchQuery,
                "modifier": "INCLUDES"
            ]
        }
        
        // Variables for GraphQL
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": groupsPerPage,
                "sort": sortBy.sortField == "random" ? randomSort(.groups) : sortBy.sortField,
                "direction": sortBy.direction
            ],
            "group_filter": groupFilter
        ]
        
        let query = GraphQLQueries.queryWithFragments("findGroups")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GroupsResponse?) in
            if let groupsResult = response?.data?.findGroups {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.groups = groupsResult.groups
                        self.totalGroups = groupsResult.count
                    } else {
                        self.groups.append(contentsOf: groupsResult.groups)
                    }
                    
                    self.hasMoreGroups = groupsResult.groups.count == self.groupsPerPage
                    
                    if isInitialLoad {
                        self.isLoadingGroups = false
                        self.errorMessage = nil
                    } else {
                        self.isLoadingMoreGroups = false
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGroups = false
                    self.isLoadingMoreGroups = false
                }
            }
        }
    }
    
    func fetchGroupScenes(
        groupId: String,
        sortBy: SceneSortOption = .dateDesc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil,
        searchQuery: String? = nil
    ) {
        if !isInitialLoad && isLoadingGroupScenes { return }

        if isInitialLoad {
            currentGroupScenePage = 1
            currentGroupSceneSortOption = sortBy
            currentGroupDetailFilter = filter
            currentGroupDetailSceneLiveFilter = liveFilter ?? [:]
            if let sq = searchQuery {
                currentGroupSceneSearchQuery = sq
            }
            groupScenes = []
            hasMoreGroupScenes = true
            isLoadingGroupScenes = true
        } else {
            isLoadingGroupScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentGroupScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        let sortToUse = currentGroupSceneSortOption
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": groupDetailPerPage,
            "sort": sortToUse.sortField == "random" ? randomSort(.scenes) : sortToUse.sortField,
            "direction": sortToUse.direction
        ]
        if !currentGroupSceneSearchQuery.isEmpty {
            filterDict["q"] = currentGroupSceneSearchQuery
        }
        
        var sceneFilter: [String: Any] = [:]
        if let savedFilter = currentGroupDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        if !currentGroupDetailSceneLiveFilter.isEmpty {
            for (key, value) in currentGroupDetailSceneLiveFilter {
                sceneFilter[key] = value
            }
        }
        sceneFilter["groups"] = [
            "value": [groupId],
            "modifier": "INCLUDES"
        ]
        sceneFilter = sanitizeFilter(sceneFilter)
        
        let variables: [String: Any] = [
            "filter": filterDict,
            "scene_filter": sceneFilter
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: AltScenesResponse?) in
            if let result = response?.data?.findScenes {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.groupScenes = result.scenes
                        self.totalGroupScenes = result.count
                        self.errorMessage = nil
                    } else {
                        self.groupScenes.append(contentsOf: result.scenes)
                    }
                    self.hasMoreGroupScenes = result.scenes.count == self.groupDetailPerPage
                    self.currentGroupScenePage = page
                    self.isLoadingGroupScenes = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGroupScenes = false
                    if isInitialLoad {
                        self.errorMessage = "Szenen der Gruppe konnten nicht geladen werden"
                    }
                }
            }
        }
    }
    
    func loadMoreGroupScenes(groupId: String) {
        if !isLoadingGroupScenes && hasMoreGroupScenes {
            fetchGroupScenes(groupId: groupId, sortBy: currentGroupSceneSortOption, isInitialLoad: false)
        }
    }
    
    func fetchGroupGalleries(groupId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentGroupGalleryPage = 1
            currentGroupGallerySortOption = sortBy
            currentGroupGalleryFilter = filter
            currentGroupGalleryLive = liveFilter ?? [:]
            groupGalleries = []
            totalGroupGalleries = 0
            isLoadingGroupGalleries = true
            hasMoreGroupGalleries = true
        } else {
            isLoadingMoreGroupGalleries = true
        }
        
        let page = isInitialLoad ? 1 : currentGroupGalleryPage + 1
        
        let sortByToUse = isInitialLoad ? sortBy : currentGroupGallerySortOption
        let scope: [String: Any] = [
            "groups": [
                "value": [groupId],
                "modifier": "INCLUDES"
            ]
        ]
        let effSaved = isInitialLoad ? filter : currentGroupGalleryFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : currentGroupGalleryLive
        let galleryFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(
            scope: scope,
            saved: effSaved,
            live: effLive.isEmpty ? nil : effLive
        )
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortByToUse.sortField == "random" ? randomSort(.galleries) : sortByToUse.sortField,
                "direction": sortByToUse.direction
            ],
            "gallery_filter": galleryFilterMerged
        ]
        
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
            if let result = response?.data?.findGalleries {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.groupGalleries = result.galleries
                        self.totalGroupGalleries = result.count
                        self.isLoadingGroupGalleries = false
                    } else {
                        self.groupGalleries.append(contentsOf: result.galleries)
                        self.isLoadingMoreGroupGalleries = false
                    }
                    self.hasMoreGroupGalleries = result.galleries.count == 20
                    self.currentGroupGalleryPage = page
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGroupGalleries = false
                    self.isLoadingMoreGroupGalleries = false
                }
            }
        }
    }
    
    func loadMoreGroupGalleries(groupId: String) {
        guard !isLoadingMoreGroupGalleries && hasMoreGroupGalleries else { return }
        fetchGroupGalleries(groupId: groupId, sortBy: currentGroupGallerySortOption, isInitialLoad: false)
    }
    
    func fetchGroup(groupId: String, completion: @escaping (StashGroup?) -> Void) {
        let variables: [String: Any] = ["id": groupId]
        let query = GraphQLQueries.queryWithFragments("findGroup")
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SingleGroupResponse?) in
            DispatchQueue.main.async {
                completion(response?.data?.findGroup)
            }
        }
    }
    
    func fetchTagScenes(
        tagId: String,
        sortBy: SceneSortOption = .dateDesc,
        isInitialLoad: Bool = true,
        filter: SavedFilter? = nil,
        liveFilter: [String: Any]? = nil,
        searchQuery: String? = nil
    ) {
        if !isInitialLoad && isLoadingTagScenes { return }

        if isInitialLoad {
            currentTagScenePage = 1
            currentTagSceneSortOption = sortBy
            currentTagDetailFilter = filter
            currentTagDetailSceneLiveFilter = liveFilter ?? [:]
            if let sq = searchQuery {
                currentTagSceneSearchQuery = sq
            }
            isLoadingTagScenes = true
        } else {
            isLoadingTagScenes = true
        }
        
        let page = isInitialLoad ? 1 : currentTagScenePage + 1
        errorMessage = nil
        
        let query = GraphQLQueries.queryWithFragments("findScenes")
        
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": scenesPerPage,
            "sort": sortBy.sortField == "random" ? randomSort(.scenes) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !currentTagSceneSearchQuery.isEmpty {
            filterDict["q"] = currentTagSceneSearchQuery
        }
        
        var sceneFilter: [String: Any] = [:]
        
        if let savedFilter = currentTagDetailFilter {
            if let dict = savedFilter.filterDict {
                sceneFilter = sanitizeFilter(dict)
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                sceneFilter = sanitizeFilter(objDict)
            }
        }
        
        if !currentTagDetailSceneLiveFilter.isEmpty {
            for (key, value) in currentTagDetailSceneLiveFilter {
                sceneFilter[key] = value
            }
        }
        
        sceneFilter["tags"] = [
            "modifier": "INCLUDES",
            "value": [tagId]
        ]
        sceneFilter = sanitizeFilter(sceneFilter)
        
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
    
    func fetchTagGalleries(tagId: String, sortBy: GallerySortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentTagGalleryPage = 1
            currentTagGallerySortOption = sortBy
            currentTagGalleryFilter = filter
            currentTagGalleryLive = liveFilter ?? [:]
            // tagGalleries = []
            totalTagGalleries = 0
            isLoadingTagGalleries = true
            hasMoreTagGalleries = true
            errorMessage = nil
        } else {
            isLoadingMoreTagGalleries = true
        }
        
        let page = isInitialLoad ? 1 : currentTagGalleryPage + 1
        let sortByToUse = isInitialLoad ? sortBy : currentTagGallerySortOption
        let sortField = sortByToUse.sortField == "random" ? randomSort(.galleries) : sortByToUse.sortField
        let sortDirection = sortByToUse.direction
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        let scope: [String: Any] = [
            "tags": [
                "value": [tagId],
                "modifier": "INCLUDES"
            ]
        ]
        let effSaved = isInitialLoad ? filter : currentTagGalleryFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : currentTagGalleryLive
        let galleryFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(
            scope: scope,
            saved: effSaved,
            live: effLive.isEmpty ? nil : effLive
        )
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 20,
                "sort": sortField,
                "direction": sortDirection
            ],
            "gallery_filter": galleryFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: GalleriesResponse?) in
            if let result = response?.data?.findGalleries {
                DispatchQueue.main.async {
                    if isInitialLoad {
                        self.tagGalleries = result.galleries
                        self.totalTagGalleries = result.count
                        self.errorMessage = nil // Clear error on success
                    } else {
                        self.tagGalleries.append(contentsOf: result.galleries)
                    }
                    
                    self.hasMoreTagGalleries = result.galleries.count == 20
                    self.currentTagGalleryPage = page
                    self.isLoadingTagGalleries = false
                    self.isLoadingMoreTagGalleries = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingTagGalleries = false
                    self.isLoadingMoreTagGalleries = false
                }
            }
        }
    }
    
    func loadMoreTagGalleries(tagId: String) {
        if !isLoadingTagGalleries && !isLoadingMoreTagGalleries && hasMoreTagGalleries {
            fetchTagGalleries(tagId: tagId, sortBy: currentTagGallerySortOption, isInitialLoad: false)
        }
    }
    
    func loadMoreTagScenes(tagId: String) {
        if !isLoadingTagScenes && hasMoreTagScenes {
            fetchTagScenes(tagId: tagId, sortBy: currentTagSceneSortOption, isInitialLoad: false)
        }
    }
    
    // MARK: - Galleries
    
    func fetchGalleries(sortBy: GallerySortOption = .dateDesc, searchQuery: String = "", isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            currentGalleryPage = 1
            galleries = []
            totalGalleries = 0
            isLoadingGalleries = true
            hasMoreGalleries = true
            currentGallerySortOption = sortBy
            currentGalleryFilter = filter
            currentGallerySearchQuery = searchQuery
            currentGalleryLiveFilter = liveFilter ?? [:]
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
                AppLog.debug("🔍 Gallery filter (filterDict) RAW: \(dict)")
                galleryFilter = sanitizeFilter(dict)
                AppLog.debug("🔍 Gallery filter (filterDict) sanitized: \(galleryFilter)")
            } else if let obj = savedFilter.object_filter, let objDict = obj.value as? [String: Any] {
                AppLog.debug("🔍 Gallery filter (object_filter) RAW: \(objDict)")
                galleryFilter = sanitizeFilter(objDict)
                AppLog.debug("🔍 Gallery filter (object_filter) sanitized: \(galleryFilter)")
            }
        }
        
        let mergedGalleryFilter = sanitizeFilter(
            currentGalleryLiveFilter.isEmpty
                ? galleryFilter
                : galleryFilter.merging(currentGalleryLiveFilter) { _, new in new }
        )
        
        // Variables for GraphQL - search query goes in FindFilterType, not GalleryFilterType
        var filterParams: [String: Any] = [
            "page": page,
            "per_page": 20,
            "sort": sortBy.sortField == "random" ? randomSort(.galleries) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        
        // Add search query to FindFilterType (not gallery_filter)
        if !searchQuery.isEmpty {
            filterParams["q"] = searchQuery
        }
        
        let variables: [String: Any] = [
            "filter": filterParams,
            "gallery_filter": mergedGalleryFilter
        ]
        
        let query = GraphQLQueries.queryWithFragments("findGalleries")
        
        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            AppLog.error("❌ Error: Could not serialize Galleries request body")
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
    
    func fetchGalleryImages(galleryId: String, sortBy: ImageSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, liveFilter: [String: Any]? = nil) {
        AppLog.debug("🖼️ fetchGalleryImages called for gallery: \(galleryId), sortBy: \(sortBy.rawValue), isInitialLoad: \(isInitialLoad)")
        
        if isInitialLoad {
            currentGalleryImagePage = 1
            galleryImages = []
            totalGalleryImages = 0
            isLoadingGalleryImages = true
            galleryImagesActiveGalleryId = galleryId
            galleryImagesActiveFilter = filter
            galleryImagesActiveLive = liveFilter ?? [:]
        } else {
            isLoadingGalleryImages = true
        }

        imageFindListError = nil
        
        currentGalleryImageSortOption = sortBy
        let page = isInitialLoad ? 1 : currentGalleryImagePage + 1
        
        let query = GraphQLQueries.queryWithFragments("findImages")
        let effGalleryId = isInitialLoad ? galleryId : galleryImagesActiveGalleryId
        let effFilter = isInitialLoad ? filter : galleryImagesActiveFilter
        let effLive = isInitialLoad ? (liveFilter ?? [:]) : galleryImagesActiveLive
        let scope: [String: Any] = [
            "galleries": [
                "value": [effGalleryId],
                "modifier": "INCLUDES"
            ]
        ]
        let imageFilterMerged = mergeDetailScopeWithSavedAndLiveFilters(scope: scope, saved: effFilter, live: effLive.isEmpty ? nil : effLive)
        
        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": 40,
                "sort": sortBy.sortField == "random" ? randomSort(.images) : sortBy.sortField,
                "direction": sortBy.direction
            ],
            "image_filter": imageFilterMerged
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingGalleryImages = false
                let msg = "Could not load images"
                self.imageFindListError = msg
                self.errorMessage = msg
            }
            return
        }
        
        performGraphQLQuery(query: bodyString, clearsGlobalErrorMessageOnStart: false) { (response: GalleryImagesResponse?) in
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
                    self.errorMessage = nil
                    self.imageFindListError = nil
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingGalleryImages = false
                    let msg = self.errorMessage ?? "Could not load images"
                    self.imageFindListError = msg
                    if self.errorMessage == nil {
                        self.errorMessage = msg
                    }
                }
            }
        }
    }
    
    func loadMoreGalleryImages(galleryId: String) {
        if !isLoadingGalleryImages && hasMoreGalleryImages {
            fetchGalleryImages(galleryId: galleryId, sortBy: currentGalleryImageSortOption, isInitialLoad: false)
        }
    }
    
    func fetchImages(sortBy: ImageSortOption = .dateDesc, isInitialLoad: Bool = true, filter: SavedFilter? = nil, staticPathFilter: Bool = false, performerId: String? = nil, liveFilter: [String: Any]? = nil) {
        AppLog.debug("🖼️ fetchImages called, sortBy: \(sortBy.rawValue), isInitialLoad: \(isInitialLoad)")

        if isInitialLoad {
            imagesFetchGeneration += 1
            currentImagePage = 1
            allImages = []
            totalImages = 0
            isLoadingImages = true
            currentImageFilter = filter
            imageStaticPathFilter = staticPathFilter
            imagePerformerIdFilter = performerId
            currentImageLiveFilter = liveFilter ?? [:]
        } else {
            isLoadingImages = true
        }

        // Nur Bildlisten-spezifischen Fehler zurücksetzen — `errorMessage` nicht anfassen (paralleles `fetchSavedFilters`).
        imageFindListError = nil

        currentImageSortOption = sortBy
        let page = isInitialLoad ? 1 : currentImagePage + 1
        let requestGeneration = imagesFetchGeneration

        let query = GraphQLQueries.queryWithFragments("findImages")

        let perPage = 100
        var filterDict: [String: Any] = [
            "page": page,
            "per_page": perPage,
            "sort": sortBy.sortField == "random" ? randomSort(.images) : sortBy.sortField,
            "direction": sortBy.direction
        ]
        if !currentImageSearchQuery.isEmpty {
            filterDict["q"] = currentImageSearchQuery
        }

        var variables: [String: Any] = [
            "filter": filterDict
        ]

        // Static path filter: exclude animated/video types (for StashLine mode)
        let includeGifs = UserDefaults.standard.object(forKey: "stashline_include_gifs") as? Bool ?? false
        let staticExtensions = includeGifs ? "jpg|jpeg|png|webp|gif" : "jpg|jpeg|png|webp"
        let staticFilter: [String: Any] = [
            "path": [
                "value": "(?i)\\.(\(staticExtensions))$",
                "modifier": "MATCHES_REGEX"
            ]
        ]

        // Performer filter (StashLine performer tap)
        var performerFilter: [String: Any] = [:]
        if let pid = imagePerformerIdFilter {
            performerFilter["performers"] = ["value": [pid], "modifier": "INCLUDES"]
        }

        if let savedFilter = currentImageFilter {
            if let dict = savedFilter.filterDict {
                var sanitized = sanitizeFilter(dict)
                if imageStaticPathFilter { sanitized.merge(staticFilter) { _, new in new } }
                sanitized.merge(performerFilter) { _, new in new }
                AppLog.debug("🔍 Image Filter sanitized: \(sanitized)")
                variables["image_filter"] = sanitized
            } else if let obj = savedFilter.object_filter {
                if let objDict = obj.value as? [String: Any] {
                    var sanitized = sanitizeFilter(objDict)
                    if imageStaticPathFilter { sanitized.merge(staticFilter) { _, new in new } }
                    sanitized.merge(performerFilter) { _, new in new }
                    AppLog.debug("🔍 Image Object Filter sanitized: \(sanitized)")
                    variables["image_filter"] = sanitized
                } else {
                    variables["image_filter"] = obj.value
                }
            }
        } else {
            var combined: [String: Any] = performerFilter
            if imageStaticPathFilter { combined.merge(staticFilter) { _, new in new } }
            if !combined.isEmpty { variables["image_filter"] = combined }
        }

        if !currentImageLiveFilter.isEmpty {
            if var imgf = variables["image_filter"] as? [String: Any] {
                imgf.merge(currentImageLiveFilter) { _, new in new }
                variables["image_filter"] = sanitizeFilter(imgf)
            } else {
                variables["image_filter"] = sanitizeFilter(currentImageLiveFilter)
            }
        }
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.isLoadingImages = false
                let msg = "Could not load images"
                self.imageFindListError = msg
                self.errorMessage = msg
            }
            return
        }
        
        performGraphQLQuery(query: bodyString, clearsGlobalErrorMessageOnStart: false) { (response: GalleryImagesResponse?) in
            if let result = response?.data?.findImages {
                DispatchQueue.main.async {
                    guard requestGeneration == self.imagesFetchGeneration else { return }
                    if isInitialLoad {
                        self.allImages = result.images
                        self.totalImages = result.count
                    } else {
                        let existingIds = Set(self.allImages.map(\.id))
                        let newImages = result.images.filter { !existingIds.contains($0.id) }
                        self.allImages.append(contentsOf: newImages)
                    }
                    
                    self.hasMoreImages = result.images.count == perPage
                    self.currentImagePage = page
                    self.isLoadingImages = false
                    self.errorMessage = nil
                    self.imageFindListError = nil
                }
            } else {
                DispatchQueue.main.async {
                    guard requestGeneration == self.imagesFetchGeneration else { return }
                    self.isLoadingImages = false
                    let msg = self.errorMessage ?? "Could not load images"
                    self.imageFindListError = msg
                    if self.errorMessage == nil {
                        self.errorMessage = msg
                    }
                }
            }
        }
    }
    
    func loadMoreImages() {
        if !isLoadingImages && hasMoreImages {
            fetchImages(sortBy: currentImageSortOption, isInitialLoad: false, filter: currentImageFilter, staticPathFilter: imageStaticPathFilter, performerId: imagePerformerIdFilter)
        }
    }
    
    // MARK: - Clips Logic
    
    @Published var clips: [StashImage] = []
    @Published var totalClips: Int = 0
    @Published var isLoadingClips = false
    @Published var hasMoreClips = true
    private var currentClipsPage = 1
    private let clipsPerPage = 20
    private var currentClipSortOption: ImageSortOption = .dateDesc
    private var currentClipFilter: SavedFilter?

    // MARK: - Reels: freeze main feed when applying performer/tag overlay
    // Restoring avoids refetch + pagination loss when clearing overlay back to main.

    private struct ReelsFrozenClipsState {
        let clips: [StashImage]
        let currentClipsPage: Int
        let totalClips: Int
        let hasMoreClips: Bool
        let currentClipSortOption: ImageSortOption
        let currentClipFilter: SavedFilter?
        let visibleItemId: String?
    }

    private struct ReelsFrozenScenesState {
        let scenes: [Scene]
        let currentScenePage: Int
        let totalScenes: Int
        let hasMoreScenes: Bool
        let currentSceneSortOption: SceneSortOption
        let currentSceneFilter: SavedFilter?
        let currentSceneSearchQuery: String
        let visibleItemId: String?
    }

    private struct ReelsFrozenMarkersState {
        let sceneMarkers: [SceneMarker]
        let currentMarkerPage: Int
        let totalSceneMarkers: Int
        let hasMoreMarkers: Bool
        let currentMarkerSortOption: SceneMarkerSortOption
        let currentMarkerFilter: SavedFilter?
        let currentMarkerSearchQuery: String
        let visibleItemId: String?
    }

    private struct ReelsFrozenPreviewsState {
        let previews: [Scene]
        let currentPreviewPage: Int
        let totalPreviews: Int
        let hasMorePreviews: Bool
        let currentPreviewSortOption: SceneSortOption
        let currentPreviewFilter: SavedFilter?
        let currentPreviewSearchQuery: String
        let visibleItemId: String?
    }

    private var reelsFrozenClips: ReelsFrozenClipsState?
    private var reelsFrozenScenes: ReelsFrozenScenesState?
    private var reelsFrozenMarkers: ReelsFrozenMarkersState?
    private var reelsFrozenPreviews: ReelsFrozenPreviewsState?

    func clearReelsCriterionFrozenSnapshots() {
        reelsFrozenClips = nil
        reelsFrozenScenes = nil
        reelsFrozenMarkers = nil
        reelsFrozenPreviews = nil
    }

    func takeReelsFrozenClipsSnapshot(visibleItemId: String?) {
        reelsFrozenClips = ReelsFrozenClipsState(
            clips: clips,
            currentClipsPage: currentClipsPage,
            totalClips: totalClips,
            hasMoreClips: hasMoreClips,
            currentClipSortOption: currentClipSortOption,
            currentClipFilter: currentClipFilter,
            visibleItemId: visibleItemId
        )
    }

    @discardableResult
    func restoreReelsFrozenClipsIfAvailable() -> String? {
        guard let s = reelsFrozenClips else { return nil }
        clips = s.clips
        currentClipsPage = s.currentClipsPage
        totalClips = s.totalClips
        hasMoreClips = s.hasMoreClips
        currentClipSortOption = s.currentClipSortOption
        currentClipFilter = s.currentClipFilter
        isLoadingClips = false
        isLoading = false
        reelsFrozenClips = nil
        return s.visibleItemId
    }

    func takeReelsFrozenScenesSnapshot(visibleItemId: String?) {
        reelsFrozenScenes = ReelsFrozenScenesState(
            scenes: scenes,
            currentScenePage: currentScenePage,
            totalScenes: totalScenes,
            hasMoreScenes: hasMoreScenes,
            currentSceneSortOption: currentSceneSortOption,
            currentSceneFilter: currentSceneFilter,
            currentSceneSearchQuery: currentSceneSearchQuery,
            visibleItemId: visibleItemId
        )
    }

    @discardableResult
    func restoreReelsFrozenScenesIfAvailable() -> String? {
        guard let s = reelsFrozenScenes else { return nil }
        scenes = s.scenes
        currentScenePage = s.currentScenePage
        totalScenes = s.totalScenes
        hasMoreScenes = s.hasMoreScenes
        currentSceneSortOption = s.currentSceneSortOption
        currentSceneFilter = s.currentSceneFilter
        currentSceneSearchQuery = s.currentSceneSearchQuery
        isLoadingScenes = false
        isLoadingMoreScenes = false
        isLoading = false
        reelsFrozenScenes = nil
        return s.visibleItemId
    }

    func takeReelsFrozenMarkersSnapshot(visibleItemId: String?) {
        reelsFrozenMarkers = ReelsFrozenMarkersState(
            sceneMarkers: sceneMarkers,
            currentMarkerPage: currentMarkerPage,
            totalSceneMarkers: totalSceneMarkers,
            hasMoreMarkers: hasMoreMarkers,
            currentMarkerSortOption: currentMarkerSortOption,
            currentMarkerFilter: currentMarkerFilter,
            currentMarkerSearchQuery: currentMarkerSearchQuery,
            visibleItemId: visibleItemId
        )
    }

    @discardableResult
    func restoreReelsFrozenMarkersIfAvailable() -> String? {
        guard let s = reelsFrozenMarkers else { return nil }
        sceneMarkers = s.sceneMarkers
        currentMarkerPage = s.currentMarkerPage
        totalSceneMarkers = s.totalSceneMarkers
        hasMoreMarkers = s.hasMoreMarkers
        currentMarkerSortOption = s.currentMarkerSortOption
        currentMarkerFilter = s.currentMarkerFilter
        currentMarkerSearchQuery = s.currentMarkerSearchQuery
        isLoadingMarkers = false
        isLoading = false
        reelsFrozenMarkers = nil
        return s.visibleItemId
    }

    func takeReelsFrozenPreviewsSnapshot(visibleItemId: String?) {
        reelsFrozenPreviews = ReelsFrozenPreviewsState(
            previews: previews,
            currentPreviewPage: currentPreviewPage,
            totalPreviews: totalPreviews,
            hasMorePreviews: hasMorePreviews,
            currentPreviewSortOption: currentPreviewSortOption,
            currentPreviewFilter: currentPreviewFilter,
            currentPreviewSearchQuery: currentPreviewSearchQuery,
            visibleItemId: visibleItemId
        )
    }

    @discardableResult
    func restoreReelsFrozenPreviewsIfAvailable() -> String? {
        guard let s = reelsFrozenPreviews else { return nil }
        previews = s.previews
        currentPreviewPage = s.currentPreviewPage
        totalPreviews = s.totalPreviews
        hasMorePreviews = s.hasMorePreviews
        currentPreviewSortOption = s.currentPreviewSortOption
        currentPreviewFilter = s.currentPreviewFilter
        currentPreviewSearchQuery = s.currentPreviewSearchQuery
        isLoadingPreviews = false
        isLoadingMorePreviews = false
        isLoading = false
        reelsFrozenPreviews = nil
        return s.visibleItemId
    }

    func fetchClips(sortBy: ImageSortOption = .dateDesc, filter: SavedFilter? = nil, isInitialLoad: Bool = true, liveFilter: [String: Any]? = nil) {
        if isInitialLoad {
            let key = feedCriteriaKey([
                "clips", sortBy.sortField, sortBy.direction,
                filter?.id, liveFilterKey(liveFilter)
            ])
            if clipsInitialInflightKey == key, isLoadingClips {
                AppLog.debug("📥 fetchClips: identical initial fetch already in flight — skipping")
                return
            }
            clipsInitialInflightKey = key

            clipsFetchGeneration += 1
            currentClipsPage = 1
            isLoadingClips = true
            hasMoreClips = true
            currentClipSortOption = sortBy
            currentClipFilter = filter
            currentClipLiveFilter = liveFilter ?? [:]
        } else {
            isLoadingClips = true
        }
        
        let page = isInitialLoad ? 1 : currentClipsPage + 1
        let perPage = clipsPerPage
        let requestGeneration = clipsFetchGeneration

        // Filter for video-like and animated extensions
        // Regex: .*\.(mp4|gif|mov|webm|m4v|mkv|webp)$ (case insensitive usually requires flags, but Stash regex is Go-flavor? or PCRE?)
        // Stash uses Go regex. (?i) is case insensitive.
        let videoRegex = "(?i).*\\.(mp4|gif|webp|mov|webm|m4v|mkv)$"
        
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
                AppLog.debug("🔍 fetchClips: Using object_filter = \(objDict)")
                let sanitized = sanitizeFilter(objDict)
                AppLog.debug("🔍 fetchClips: Sanitized filter = \(sanitized)")
                for (key, value) in sanitized {
                    if key != "path" {
                        imageFilter[key] = value
                    }
                }
            }
            if savedFilter.id != "merged_temp" {
                for (key, value) in sanitizeFilter(savedFilter.stashyLiveFragment) where key != "path" {
                    imageFilter[key] = value
                }
            }
        }
        
        if !currentClipLiveFilter.isEmpty {
            let liveSan = sanitizeFilter(currentClipLiveFilter)
            for (key, value) in liveSan where key != "path" {
                imageFilter[key] = value
            }
        }

        let variables: [String: Any] = [
            "filter": [
                "page": page,
                "per_page": perPage,
                "sort": currentClipSortOption.sortField == "random" ? randomSort(.images) : currentClipSortOption.sortField,
                "direction": currentClipSortOption.direction
            ],
            "image_filter": sanitizeFilter(imageFilter)
        ]
        
        AppLog.debug("🔍 fetchClips: Variables = \(variables)")
        
        guard let dataRequest = ["query": query, "variables": variables] as [String: Any]?,
              let bodyData = try? JSONSerialization.data(withJSONObject: dataRequest),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            isLoadingClips = false
            if errorMessage == nil {
                errorMessage = "Could not load clips"
            }
            return
        }

        AppLog.debug("🔍 fetchClips: Raw Body = \(bodyString)")

        performGraphQLQuery(query: bodyString, clearsGlobalErrorMessageOnStart: false) { (response: GalleryImagesResponse?) in
            DispatchQueue.main.async {
                guard requestGeneration == self.clipsFetchGeneration else { return }
                if let result = response?.data?.findImages {
                    var addedCount = 0
                    if isInitialLoad {
                        self.clipsInitialInflightKey = nil
                        self.clips = result.images
                        self.totalClips = result.count
                        self.resetFeedPagingState("clips")
                    } else {
                        let existingIds = Set(self.clips.map { $0.id })
                        let newClips = result.images.filter { !existingIds.contains($0.id) }
                        self.clips.append(contentsOf: newClips)
                        addedCount = newClips.count
                    }

                    self.hasMoreClips = result.images.count == perPage
                    if !isInitialLoad {
                        self.noteFeedProgress(feed: "clips", addedCount: addedCount, isInitialLoad: false) {
                            self.hasMoreClips = $0
                        }
                    }
                    self.currentClipsPage = page
                    self.errorMessage = nil
                } else {
                    if isInitialLoad {
                        self.clipsInitialInflightKey = nil
                    }
                    if isInitialLoad, self.clips.isEmpty {
                        if self.errorMessage == nil {
                            self.errorMessage = "Could not load clips"
                        }
                    }
                    self.noteFeedFailure("clips")
                }
                self.isLoadingClips = false
            }
        }
    }
    
    func loadMoreClips() {
        if !isLoadingClips, hasMoreClips, feedAllowsLoadMore("clips") {
            fetchClips(sortBy: currentClipSortOption, filter: currentClipFilter, isInitialLoad: false)
        }
    }

    func deleteImage(imageId: String, completion: @escaping (Bool) -> Void) {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            completion(false)
            return
        }

        // 1) Fetch file IDs for the image (so we can delete files like scenes do).
        //    Stash rescans will re-import the file if we only destroy the DB entity.
        let fileIdsQuery = """
        {
          "query": "query { findImage(id: \\"\(imageId)\\") { visual_files { ... on BaseFile { id } } } }"
        }
        """

        // 2) Destroy the image record
        let destroyMutation = """
        {
          "query": "mutation { imageDestroy(input: { id: \\"\(imageId)\\" }) }"
        }
        """

        AppLog.debug("🗑️ IMAGE DELETE: Deleting image + files \(imageId)")
        performGraphQLMutationSilent(query: fileIdsQuery) { [weak self] preResult in
            let fileIds: [String] = {
                guard
                    let preResult,
                    let data = preResult["data"]?.value as? [String: Any],
                    let findImage = data["findImage"] as? [String: Any],
                    let visualFiles = findImage["visual_files"] as? [[String: Any]]
                else { return [] }

                return visualFiles.compactMap { $0["id"] as? String }
            }()

            self?.performGraphQLMutationSilent(query: destroyMutation) { [weak self] result in
                guard
                    let result,
                    let data = result["data"]?.value as? [String: Any],
                    data["imageDestroy"] != nil
                else {
                    AppLog.error("❌ IMAGE DELETE: Failed for image \(imageId)")
                    completion(false)
                    return
                }

                self?.removeImage(id: imageId)

                // Post notification so other views can update
                NotificationCenter.default.post(
                    name: NSNotification.Name("ImageDeleted"),
                    object: nil,
                    userInfo: ["imageId": imageId]
                )

                // 3) Delete the underlying files (best-effort; DB entity is already gone)
                guard let self, !fileIds.isEmpty else {
                    AppLog.debug("✅ IMAGE DELETE: Success for image \(imageId) (no files to delete)")
                    completion(true)
                    return
                }

                self.deleteSceneFiles(fileIds: fileIds, config: config) { success in
                    if success {
                        AppLog.debug("✅ IMAGE DELETE: Deleted files for image \(imageId)")
                    } else {
                        AppLog.error("⚠️ IMAGE DELETE: Image destroyed but file deletion failed for \(imageId)")
                    }
                    completion(true)
                }
            }
        }
    }
    func addScenePlay(sceneId: String, completion: ((Int?) -> Void)? = nil) {
        let mutation = GraphQLQueries.sceneAddPlayMutation

        let variables: [String: Any] = [
            "id": sceneId,
            "times": []
        ]

        AppLog.debug("🎬 SCENE PLAY: Sending mutation for scene \(sceneId)")
        Task {
            do {
                let result = try await GraphQLClient.shared.performMutation(mutation: mutation, variables: variables)
                if let data = result["data"]?.value as? [String: Any],
                   let payload = data["sceneAddPlay"] as? [String: Any] {
                    if let newCount = payload["count"] as? Int {
                        AppLog.debug("✅ SCENE PLAY: Success for scene \(sceneId). New count: \(newCount)")
                        await MainActor.run { completion?(newCount) }
                        return
                    } else if let newCount = payload["count"] as? Double {
                        let count = Int(newCount)
                        AppLog.debug("✅ SCENE PLAY: Success for scene \(sceneId). New count: \(count)")
                        await MainActor.run { completion?(count) }
                        return
                    }
                }

                if let errors = result["errors"]?.value {
                    AppLog.error("❌ SCENE PLAY: Failed for scene \(sceneId). Errors: \(errors)")
                } else {
                    AppLog.error("❌ SCENE PLAY: Failed for scene \(sceneId)")
                }
                await MainActor.run { completion?(nil) }
            } catch {
                AppLog.error("❌ SCENE PLAY: Failed for scene \(sceneId). Error: \(error)")
                await MainActor.run { completion?(nil) }
            }
        }
    }
    
    func addSceneMarkerPlay(markerId: String, completion: ((Int?) -> Void)? = nil) {
        let mutation = GraphQLQueries.sceneMarkerIncrementPlayMutation
        
        let variables: [String: Any] = ["id": markerId]
        
        AppLog.debug("🎬 MARKER PLAY: Sending increment via sceneMarkerUpdate for marker \(markerId)")
        Task {
            do {
                let result = try await GraphQLClient.shared.performMutation(mutation: mutation, variables: variables)
                if let data = result["data"]?.value as? [String: Any],
                   let payload = data["sceneMarkerUpdate"] as? [String: Any] {
                    if let newCount = payload["play_count"] as? Int {
                        AppLog.debug("✅ MARKER PLAY: Success for marker \(markerId). New count: \(newCount)")
                        await MainActor.run { completion?(newCount) }
                        return
                    }
                }
                await MainActor.run { completion?(nil) }
            } catch {
                AppLog.error("❌ MARKER PLAY: Error for marker \(markerId): \(error)")
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
        
        AppLog.debug("🎬 SCENE O: Sending increment mutation for scene \(sceneId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result,
               let data = result["data"]?.value as? [String: Any],
               let count = data["sceneIncrementO"] as? Int {
                AppLog.debug("✅ SCENE O: Success for scene \(sceneId). New count: \(count)")
                DispatchQueue.main.async {
                    completion?(count)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneOCounterUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "oCounter": count]
                    )
                }
            } else {
                AppLog.error("❌ SCENE O: Failed for scene \(sceneId)")
                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }
    
    /// Syncs playback activity to Stash. `playDuration` is **added** to the scene's total watch time.
    /// Pass `resumeTime: nil` to update only play duration (e.g. marker streams).
    func updateSceneResumeTime(
        sceneId: String,
        resumeTime: Double?,
        playDuration: Double = 0,
        completion: ((Bool) -> Void)? = nil
    ) {
        let formattedDuration = String(format: "%.2f", max(0, playDuration))
        let mutation: String
        if let resumeTime {
            let formattedTime = String(format: "%.2f", resumeTime)
            mutation = """
            {
              "query": "mutation SceneSaveActivity($id: ID!, $resume_time: Float, $playDuration: Float) { sceneSaveActivity(id: $id, resume_time: $resume_time, playDuration: $playDuration) }",
              "variables": {
                "id": "\(sceneId)",
                "resume_time": \(formattedTime),
                "playDuration": \(formattedDuration)
              }
            }
            """
        } else {
            mutation = """
            {
              "query": "mutation SceneSaveActivity($id: ID!, $playDuration: Float) { sceneSaveActivity(id: $id, playDuration: $playDuration) }",
              "variables": {
                "id": "\(sceneId)",
                "playDuration": \(formattedDuration)
              }
            }
            """
        }

        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result {
                if let data = result["data"]?.value as? [String: Any],
                   let _ = data["sceneSaveActivity"] {
                    if let resumeTime {
                        DispatchQueue.main.async {
                            self.updateSceneResumeTime(id: sceneId, newResumeTime: resumeTime)
                            completion?(true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion?(true)
                        }
                    }
                } else if let errors = result["errors"] {
                    AppLog.error("❌ ACTIVITY SAVE ERROR for scene \(sceneId): \(errors)")
                    DispatchQueue.main.async {
                        completion?(false)
                    }
                }
            } else {
                AppLog.error("❌ ACTIVITY SAVE FAILED for scene \(sceneId)")
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }

    /// Convenience: resume-only save (play duration delta 0).
    func updateSceneResumeTime(sceneId: String, resumeTime: Double, completion: ((Bool) -> Void)? = nil) {
        updateSceneResumeTime(sceneId: sceneId, resumeTime: resumeTime, playDuration: 0, completion: completion)
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
        // Route through GraphQLClient so server-switch cancelAllRequests() covers mutations.
        GraphQLClient.shared.execute(query: query) { (result: Result<[String: StashJSONValue], GraphQLNetworkError>) in
            switch result {
            case .success(let decoded):
                completion(decoded)
            case .failure:
                completion(nil)
            }
        }
    }
    
    private func performGraphQLQuery<T: Decodable>(
        query: String,
        clearsGlobalErrorMessageOnStart: Bool = true,
        setsGlobalLoading: Bool = true,
        completion: @escaping (T?) -> Void
    ) {
        guard ServerConfigManager.shared.loadConfig()?.hasValidConfig == true else {
            errorMessage = "Server configuration is missing or incomplete"
            AppLog.error("❌ No valid server configuration found")
            completion(nil)
            return
        }

        if setsGlobalLoading {
            isLoading = true
        }
        if clearsGlobalErrorMessageOnStart {
            errorMessage = nil
        }

        // Delegate to new GraphQLClient
        GraphQLClient.shared.execute(query: query) { [weak self] (result: Result<T, GraphQLNetworkError>) in
            DispatchQueue.main.async {
                if setsGlobalLoading {
                    self?.isLoading = false
                }
                switch result {
                case .success(let response):
                    completion(response)
                case .failure(let error):
                    AppLog.debug("📱 GraphQL Error: \(error)")
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
        AppLog.debug("📱 StashDB Error: \(error)")
        
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
            AppLog.debug("📱 Decoding Error: \(decodingError)")
            errorMessage = "Could not process server response"
        } else {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        serverStatus = "Connection failed"
    }
    
    // MARK: - Library Actions
    
    func triggerLibraryScan(completion: @escaping (Bool, String) -> Void) {
        let scanMutation = GraphQLQueries.metadataScanMutation

        performGraphQLQuery(query: scanMutation) { (response: GenericMutationResponse?) in
            if response != nil {
                completion(true, "Library scan started successfully!")
            } else {
                completion(false, "Failed to start library scan. Please check your server configuration.")
            }
        }
    }

    private static func identifyOptionsDict(_ opts: StashIdentifyOptions) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let fieldOptions = opts.fieldOptions {
            dict["fieldOptions"] = fieldOptions.map { f -> [String: Any] in
                var entry: [String: Any] = ["field": f.field, "strategy": f.strategy]
                if let c = f.createMissing { entry["createMissing"] = c }
                return entry
            }
        }
        if let v = opts.setCoverImage { dict["setCoverImage"] = v }
        if let v = opts.setOrganized { dict["setOrganized"] = v }
        // performerGenders (newer API) takes precedence over includeMalePerformers (legacy)
        if let genders = opts.performerGenders, !genders.isEmpty {
            dict["performerGenders"] = genders
        } else {
            dict["includeMalePerformers"] = opts.includeMalePerformers ?? false
        }
        if let v = opts.skipMultipleMatches { dict["skipMultipleMatches"] = v }
        if let v = opts.skipMultipleMatchTag { dict["skipMultipleMatchTag"] = v }
        if let v = opts.skipSingleNamePerformers { dict["skipSingleNamePerformers"] = v }
        if let v = opts.skipSingleNamePerformerTag { dict["skipSingleNamePerformerTag"] = v }
        return dict
    }

    /// Starts Identify with server defaults. Pass `sceneIDs` to scope to those scenes; omit for library-wide.
    /// Completion: `(success, message, jobId)` — `jobId` can be polled via ``waitForJob``.
    func triggerIdentify(sceneIDs: [String]? = nil, completion: @escaping (Bool, String, String?) -> Void) {
        // Step 1: fetch configured stash-box endpoints from server
        let configQuery = GraphQLQueries.loadQuery(named: "configuration")
        let configBody: [String: Any] = ["query": configQuery]
        guard let configData = try? JSONSerialization.data(withJSONObject: configBody),
              let configString = String(data: configData, encoding: .utf8) else {
            completion(false, "Failed to build configuration request.", nil)
            return
        }

        performGraphQLQuery(query: configString) { (response: StashConfigurationResponse?) in
            let config = response?.data?.configuration
            let boxes = config?.general?.stashBoxes ?? []
            if boxes.isEmpty {
                completion(false, "No Stash-Box endpoints configured on this server.", nil)
                return
            }

            // Step 2: build sources — use server defaults if present, otherwise all boxes with no per-source options
            let identifyDefaults = config?.defaults?.identify
            let sources: [[String: Any]]
            if let defaultSources = identifyDefaults?.sources, !defaultSources.isEmpty {
                sources = defaultSources.compactMap { src -> [String: Any]? in
                    guard let endpoint = src.source?.stash_box_endpoint else { return nil }
                    var entry: [String: Any] = ["source": ["stash_box_endpoint": endpoint]]
                    if let opts = src.options {
                        entry["options"] = Self.identifyOptionsDict(opts)
                    }
                    return entry
                }
            } else {
                sources = boxes.map { ["source": ["stash_box_endpoint": $0.endpoint]] }
            }

            // Step 3: build global options — use server defaults if present, otherwise sensible fallback
            let options: [String: Any]
            if let defaultOptions = identifyDefaults?.options {
                options = Self.identifyOptionsDict(defaultOptions)
            } else {
                options = [
                    "fieldOptions": [
                        ["field": "title", "strategy": "OVERWRITE"],
                        ["field": "studio", "strategy": "MERGE", "createMissing": true],
                        ["field": "performers", "strategy": "MERGE", "createMissing": true],
                        ["field": "tags", "strategy": "MERGE", "createMissing": true]
                    ],
                    "setCoverImage": true,
                    "setOrganized": false,
                    "includeMalePerformers": false,
                    "skipMultipleMatches": true,
                    "skipSingleNamePerformers": true
                ]
            }

            var input: [String: Any] = ["sources": sources, "options": options]
            if let sceneIDs, !sceneIDs.isEmpty {
                input["sceneIDs"] = sceneIDs
            } else {
                input["paths"] = []
            }

            let identifyQuery = GraphQLQueries.loadQuery(named: "metadataIdentify")
            let body: [String: Any] = ["query": identifyQuery, "variables": ["input": input]]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                completion(false, "Failed to build identify request.", nil)
                return
            }

            self.performGraphQLQuery(query: bodyString) { (response: GenericMutationResponse?) in
                if let jobId = response?.data?["metadataIdentify"], !jobId.isEmpty {
                    let names = boxes.map { $0.name ?? $0.endpoint }.joined(separator: ", ")
                    if let sceneIDs, sceneIDs.count == 1 {
                        completion(true, "Identify started for this scene using: \(names)", jobId)
                    } else if let sceneIDs, !sceneIDs.isEmpty {
                        completion(true, "Identify started for \(sceneIDs.count) scenes using: \(names)", jobId)
                    } else {
                        completion(true, "Identify started using: \(names)", jobId)
                    }
                } else if response != nil {
                    // Older servers may omit / null the job id; treat as started without tracking.
                    let names = boxes.map { $0.name ?? $0.endpoint }.joined(separator: ", ")
                    completion(true, "Identify started using: \(names)", nil)
                } else {
                    completion(false, "Failed to start identify. Please check your server configuration.", nil)
                }
            }
        }
    }

    /// Polls `findJob` until the job finishes, fails, or `timeout` elapses.
    func waitForJob(
        id jobId: String,
        pollInterval: TimeInterval = 1.0,
        timeout: TimeInterval = 180,
        completion: @escaping (Bool, String) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var sawJob = false

        func poll() {
            self.fetchJob(id: jobId) { job in
                if let job {
                    sawJob = true
                    switch job.status.uppercased() {
                    case "FINISHED":
                        completion(true, job.description ?? "Identify finished")
                    case "FAILED":
                        completion(false, job.error ?? "Identify failed")
                    case "CANCELLED":
                        completion(false, "Identify was cancelled")
                    default:
                        // READY / RUNNING / STOPPING
                        guard Date() < deadline else {
                            completion(false, "Identify timed out")
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                            poll()
                        }
                    }
                    return
                }

                // Job missing from queue: finished jobs are often purged quickly.
                if sawJob {
                    completion(true, "Identify finished")
                    return
                }
                guard Date() < deadline else {
                    completion(false, "Identify job not found")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                    poll()
                }
            }
        }

        poll()
    }

    private func fetchJob(id jobId: String, completion: @escaping (StashJob?) -> Void) {
        let query = GraphQLQueries.loadQuery(named: "findJob")
        let body: [String: Any] = ["query": query, "variables": ["input": ["id": jobId]]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(nil)
            return
        }

        // Avoid toggling global `isLoading` while polling.
        GraphQLClient.shared.execute(query: bodyString) { (result: Result<FindJobResponse, GraphQLNetworkError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    completion(response.data?.findJob)
                case .failure:
                    completion(nil)
                }
            }
        }
    }

    func triggerGenerate(
        covers: Bool = false,
        previews: Bool = false,
        imagePreviews: Bool = false,
        sprites: Bool = false,
        markers: Bool = false,
        markerImagePreviews: Bool = false,
        markerScreenshots: Bool = false,
        transcodes: Bool = false,
        phashes: Bool = false,
        interactiveHeatmapsSpeeds: Bool = false,
        clipPreviews: Bool = false,
        imageThumbnails: Bool = false,
        imagePhashes: Bool = false,
        sceneIDs: [String]? = nil,
        markerIDs: [String]? = nil,
        completion: @escaping (Bool, String) -> Void
    ) {
        triggerGenerateReturningJobId(
            covers: covers,
            previews: previews,
            imagePreviews: imagePreviews,
            sprites: sprites,
            markers: markers,
            markerImagePreviews: markerImagePreviews,
            markerScreenshots: markerScreenshots,
            transcodes: transcodes,
            phashes: phashes,
            interactiveHeatmapsSpeeds: interactiveHeatmapsSpeeds,
            clipPreviews: clipPreviews,
            imageThumbnails: imageThumbnails,
            imagePhashes: imagePhashes,
            sceneIDs: sceneIDs,
            markerIDs: markerIDs
        ) { success, message, _ in
            completion(success, message)
        }
    }

    /// Starts a scoped generate job. Completion: `(success, message, jobId)`.
    func triggerGenerateReturningJobId(
        covers: Bool = false,
        previews: Bool = false,
        imagePreviews: Bool = false,
        sprites: Bool = false,
        markers: Bool = false,
        markerImagePreviews: Bool = false,
        markerScreenshots: Bool = false,
        transcodes: Bool = false,
        phashes: Bool = false,
        interactiveHeatmapsSpeeds: Bool = false,
        clipPreviews: Bool = false,
        imageThumbnails: Bool = false,
        imagePhashes: Bool = false,
        overwrite: Bool = false,
        sceneIDs: [String]? = nil,
        markerIDs: [String]? = nil,
        completion: @escaping (Bool, String, String?) -> Void
    ) {
        // Only send enabled flags + scope — matches Stash web and avoids odd no-op jobs.
        var input: [String: Any] = [:]
        if covers { input["covers"] = true }
        if previews { input["previews"] = true }
        if imagePreviews { input["imagePreviews"] = true }
        if sprites { input["sprites"] = true }
        if markers { input["markers"] = true }
        if markerImagePreviews { input["markerImagePreviews"] = true }
        if markerScreenshots { input["markerScreenshots"] = true }
        if transcodes { input["transcodes"] = true }
        if phashes { input["phashes"] = true }
        if interactiveHeatmapsSpeeds { input["interactiveHeatmapsSpeeds"] = true }
        if clipPreviews { input["clipPreviews"] = true }
        if imageThumbnails { input["imageThumbnails"] = true }
        if imagePhashes { input["imagePhashes"] = true }
        if overwrite { input["overwrite"] = true }
        if let sceneIDs, !sceneIDs.isEmpty {
            input["sceneIDs"] = sceneIDs
        }
        if let markerIDs, !markerIDs.isEmpty {
            input["markerIDs"] = markerIDs
        }
        let query = GraphQLQueries.loadQuery(named: "metadataGenerate")
        let body: [String: Any] = ["query": query, "variables": ["input": input]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false, "Failed to build generate request.", nil)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GenericMutationResponse?) in
            if let jobId = response?.data?["metadataGenerate"], !jobId.isEmpty {
                completion(true, "Generate started successfully!", jobId)
            } else if response != nil {
                completion(true, "Generate started successfully!", nil)
            } else {
                completion(false, "Failed to start generate. Please check your server configuration.", nil)
            }
        }
    }

    /// Generates still thumbnails for markers on a scene (frame at each marker's start time).
    ///
    /// Important: scope via `sceneIDs`, not only `markerIDs`. Stash's per-marker generate path
    /// does not create `generated/markers/<hash>/`, so screenshot writes fail for new scenes.
    func generateMarkerScreenshots(sceneId: String, completion: @escaping (Bool, String?) -> Void) {
        guard !sceneId.isEmpty else {
            completion(false, nil)
            return
        }
        triggerGenerateReturningJobId(
            markerScreenshots: true,
            overwrite: true,
            sceneIDs: [sceneId]
        ) { success, _, jobId in
            completion(success, jobId)
        }
    }



struct GenerateData: Codable {
    let metadataGenerate: Int?
}
    
    // MARK: - Statistics
    // fetchStatistics already exists in file
    
    // MARK: - Mutations
    
    func toggleTagFavorite(tagId: String, favorite: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.tagUpdateFavoriteMutation
        
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

    /// Updates tag metadata shown on the detail screen (edit mode).
    func updateTagDetails(
        tagId: String,
        name: String,
        description: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let mutation = GraphQLQueries.tagUpdateDetailsMutation
        var input: [String: Any] = [
            "id": tagId,
            "name": name
        ]
        input["description"] = description ?? NSNull()

        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: TagUpdateResponse?) in
            completion(response?.data?.tagUpdate != nil)
        }
    }
    
    func showScene(sceneId: String) {
        // Implement logic to show scene details or play it
        AppLog.debug("Show scene not implemented")
    }

    func updateImageRating(imageId: String, rating100: Int?, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.imageUpdateRatingMutation
        
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
                DispatchQueue.main.async {
                    self.patchImageRatingInLists(imageId: imageId, rating100: rating100)
                    var userInfo: [String: Any] = ["imageId": imageId]
                    if let rating100 {
                        userInfo["rating100"] = rating100
                    }
                    if let image = self.imageInLists(id: imageId) {
                        let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !title.isEmpty {
                            userInfo["title"] = title
                        }
                        if let thumb = image.paths?.thumbnail ?? image.paths?.preview ?? image.paths?.image {
                            userInfo["thumbnailPath"] = thumb
                        }
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ImageRatingUpdated"),
                        object: nil,
                        userInfo: userInfo
                    )
                }
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
        
        AppLog.debug("📷 IMAGE O: Sending increment mutation for image \(imageId)")
        performGraphQLMutationSilent(query: mutation) { result in
            if let result = result,
               let data = result["data"]?.value as? [String: Any],
               let count = data["imageIncrementO"] as? Int {
                AppLog.debug("✅ IMAGE O: Success for image \(imageId). New count: \(count)")
                DispatchQueue.main.async {
                    self.patchImageOCounterInLists(imageId: imageId, oCounter: count)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ImageOCounterUpdated"),
                        object: nil,
                        userInfo: ["imageId": imageId, "oCounter": count]
                    )
                    completion?(count)
                }
            } else {
                AppLog.error("❌ IMAGE O: Failed for image \(imageId)")
                DispatchQueue.main.async {
                    completion?(nil)
                }
            }
        }
    }
    
    func updateImageOCounter(imageId: String, oCounter: Int?, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.imageUpdateOCounterMutation
        
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
                DispatchQueue.main.async {
                    if let oCounter {
                        self.patchImageOCounterInLists(imageId: imageId, oCounter: oCounter)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ImageOCounterUpdated"),
                            object: nil,
                            userInfo: ["imageId": imageId, "oCounter": oCounter]
                        )
                    }
                }
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    func toggleSceneOrganized(sceneId: String, organized: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateOrganizedMutation
        
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
        let mutation = GraphQLQueries.sceneUpdateRatingMutation
        
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
                    var userInfo: [String: Any] = ["sceneId": sceneId]
                    if let rating100 {
                        userInfo["rating100"] = rating100
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneRatingUpdated"),
                        object: nil,
                        userInfo: userInfo
                    )
                }
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
    /// Creates a scene marker. Completion receives `(success, createdMarker)`.
    func createSceneMarker(sceneId: String, title: String, seconds: Double, endSeconds: Double? = nil, primaryTagId: String, completion: @escaping (Bool, SceneMarker?) -> Void) {
        let mutation = GraphQLQueries.sceneMarkerCreateMutation
        
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
            completion(false, nil)
            return
        }
        
        performGraphQLQuery(query: bodyString) { (response: SceneMarkerCreateResponse?) in
            if let marker = response?.data?.sceneMarkerCreate {
                completion(true, marker)
            } else {
                completion(false, nil)
            }
        }
    }
    
    func fetchAllPerformers(completion: @escaping ([Performer]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findPerformers")
        let variables: [String: Any] = [
            "filter": ["per_page": 1000, "sort": "scenes_count", "direction": "DESC"],
            "performer_filter": [:]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([]); return
        }
        performGraphQLQuery(query: bodyString) { (response: PerformersResponse?) in
            completion(response?.data?.findPerformers.performers ?? [])
        }
    }

    func fetchAllStudios(completion: @escaping ([Studio]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findStudios")
        let variables: [String: Any] = [
            "filter": ["per_page": 1000, "sort": "scenes_count", "direction": "DESC"],
            "studio_filter": [:]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion([]); return
        }
        performGraphQLQuery(query: bodyString) { (response: StudiosResponse?) in
            completion(response?.data?.findStudios.studios ?? [])
        }
    }

    /// Max rows returned for studio/tag live-filter dropdown queries — top N by the relevant count on the server (groups use a separate larger page size).
    private static let sceneLiveFilterPickerMaxResults = 50

    /// Studios suitable for live-filter dropdowns (has scenes / images / galleries); top ``sceneLiveFilterPickerMaxResults`` by the relevant count.
    func fetchStudiosForLiveFilterPicker(mode: LiveFilterStudioPickerMode, completion: @escaping ([Studio]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findStudios")
        let studioFilter: [String: Any]
        let sortField: String
        switch mode {
        case .scenesHasScenes:
            studioFilter = ["scene_count": ["value": 0, "modifier": "GREATER_THAN"]]
            sortField = "scenes_count"
        case .imagesHasImages:
            studioFilter = ["image_count": ["value": 0, "modifier": "GREATER_THAN"]]
            sortField = "images_count"
        case .galleriesHasGalleries:
            studioFilter = ["gallery_count": ["value": 0, "modifier": "GREATER_THAN"]]
            sortField = "galleries_count"
        }
        let variables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": Self.sceneLiveFilterPickerMaxResults,
                "sort": sortField,
                "direction": "DESC"
            ],
            "studio_filter": sanitizeFilter(studioFilter)
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            Task { @MainActor in completion([]) }
            return
        }
        performGraphQLQuery(query: bodyString) { (response: StudiosResponse?) in
            var list = response?.data?.findStudios.studios ?? []
            switch mode {
            case .scenesHasScenes:
                list.sort { $0.sceneCount > $1.sceneCount }
            case .imagesHasImages:
                list.sort { ($0.imageCount ?? 0) > ($1.imageCount ?? 0) }
            case .galleriesHasGalleries:
                list.sort { ($0.galleryCount ?? 0) > ($1.galleryCount ?? 0) }
            }
            Task { @MainActor in completion(list) }
        }
    }

    /// Tags that appear on at least one scene — for scene live-filter pickers; sorted by `scene_count` desc.
    func fetchTagsForSceneLiveFilterPicker(completion: @escaping ([Tag]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findTags")
        let variables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": Self.sceneLiveFilterPickerMaxResults,
                "sort": "scenes_count",
                "direction": "DESC"
            ],
            "tag_filter": sanitizeFilter([
                "scene_count": ["value": 0, "modifier": "GREATER_THAN"]
            ])
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            Task { @MainActor in completion([]) }
            return
        }
        performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
            let list = response?.data?.findTags.tags ?? []
            Task { @MainActor in completion(list) }
        }
    }

    /// Tags that appear on at least one image — for image live-filter pickers; sorted by `image_count` desc.
    func fetchTagsForImageLiveFilterPicker(completion: @escaping ([Tag]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findTags")
        let variables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": Self.sceneLiveFilterPickerMaxResults,
                "sort": "images_count",
                "direction": "DESC"
            ],
            "tag_filter": sanitizeFilter([
                "image_count": ["value": 0, "modifier": "GREATER_THAN"]
            ])
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            Task { @MainActor in completion([]) }
            return
        }
        performGraphQLQuery(query: bodyString) { (response: TagsResponse?) in
            var list = response?.data?.findTags.tags ?? []
            list.sort { ($0.imageCount ?? 0) > ($1.imageCount ?? 0) }
            Task { @MainActor in completion(list) }
        }
    }

    #if !os(tvOS)
    /// Top performers for the criteria-editor multi-ID pickers (iOS only — `FilterEntityOption`
    /// lives in the iOS-only Filters module).
    func fetchPerformersForFilterPicker(completion: @escaping ([FilterEntityOption]) -> Void) {
        fetchAllPerformers { list in
            let options = list.map { FilterEntityOption(id: $0.id, name: $0.name) }
            Task { @MainActor in completion(options) }
        }
    }
    #endif

    /// Groups with at least one scene — for scene live-filter pickers (no 50-cap; large `per_page` like catalog).
    func fetchGroupsForSceneLiveFilterPicker(completion: @escaping ([StashGroup]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findGroups")
        let variables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": 1000,
                "sort": "scenes_count",
                "direction": "DESC"
            ],
            "group_filter": sanitizeFilter([
                "scene_count": ["value": 0, "modifier": "GREATER_THAN"]
            ])
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            Task { @MainActor in completion([]) }
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GroupsResponse?) in
            var list = response?.data?.findGroups.groups ?? []
            list.sort { ($0.scene_count ?? 0) > ($1.scene_count ?? 0) }
            Task { @MainActor in completion(list) }
        }
    }

    func updateScenePerformers(sceneId: String, performerIds: [String], completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdatePerformersMutation
        let variables: [String: Any] = ["input": ["id": sceneId, "performer_ids": performerIds]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false); return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    func updateSceneStudio(sceneId: String, studioId: String?, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateStudioMutation
        var input: [String: Any] = ["id": sceneId]
        if let sid = studioId { input["studio_id"] = sid } else { input["studio_id"] = NSNull() }
        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false); return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    func updateSceneTags(sceneId: String, tagIds: [String], completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateTagsMutation
        let variables: [String: Any] = ["input": ["id": sceneId, "tag_ids": tagIds]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false); return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    func fetchAllGroupsForScene(completion: @escaping ([StashGroup]) -> Void) {
        let query = GraphQLQueries.findGroupsForSceneQuery
        let variables: [String: Any] = ["filter": ["per_page": -1, "sort": "name", "direction": "ASC"]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion([]); return }
        struct Resp: Codable { let data: RData? }
        struct RData: Codable { let findGroups: RGroups }
        struct RGroups: Codable { let groups: [StashGroup] }
        performGraphQLQuery(query: bodyString) { (response: Resp?) in
            completion(response?.data?.findGroups.groups ?? [])
        }
    }

    func updateSceneGroups(sceneId: String, groupIds: [String], completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateGroupsMutation
        let groupsInput = groupIds.map { ["group_id": $0] }
        let variables: [String: Any] = ["input": ["id": sceneId, "groups": groupsInput]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(false); return }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    func fetchAllGalleriesForScene(completion: @escaping ([Gallery]) -> Void) {
        fetchGalleriesForSceneEdit(performerIds: [], completion: completion)
    }

    /// Galleries for the scene-edit sheet. When `performerIds` is non-empty, only galleries
    /// that include at least one of those performers are returned (with cover thumbnails).
    func fetchGalleriesForSceneEdit(performerIds: [String], completion: @escaping ([Gallery]) -> Void) {
        let query = GraphQLQueries.findGalleriesForSceneQuery
        var variables: [String: Any] = ["filter": ["per_page": -1, "sort": "title", "direction": "ASC"]]
        if !performerIds.isEmpty {
            variables["gallery_filter"] = [
                "performers": [
                    "value": performerIds,
                    "modifier": "INCLUDES"
                ]
            ]
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion([]); return }
        struct Resp: Codable { let data: RData? }
        struct RData: Codable { let findGalleries: RGalleries }
        struct RGalleries: Codable { let galleries: [Gallery] }
        performGraphQLQuery(query: bodyString) { (response: Resp?) in
            completion(response?.data?.findGalleries.galleries ?? [])
        }
    }
    func updateSceneGalleries(sceneId: String, galleryIds: [String], completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateGalleriesMutation
        let variables: [String: Any] = ["input": ["id": sceneId, "gallery_ids": galleryIds]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(false); return }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    /// One-shot gallery image preview for scene detail strips (does not touch `galleryImages`).
    func fetchGalleryPreviewImages(galleryId: String, limit: Int = 30, completion: @escaping ([StashImage]) -> Void) {
        let query = GraphQLQueries.queryWithFragments("findImages")
        let variables: [String: Any] = [
            "filter": [
                "page": 1,
                "per_page": limit,
                "sort": "path",
                "direction": "ASC"
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
            completion([])
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
            completion(response?.data?.findImages.images ?? [])
        }
    }

    func updateSceneTitleAndDetails(sceneId: String, title: String?, details: String?, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateTitleDetailsMutation
        var input: [String: Any] = ["id": sceneId]
        if let t = title { input["title"] = t } else { input["title"] = NSNull() }
        if let d = details { input["details"] = d } else { input["details"] = NSNull() }
        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false); return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    /// Writes spoken language into Stash scene `custom_fields.language`.
    func updateSceneLanguage(sceneId: String, languageCode: String?, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateLanguageMutation
        var partial: [String: Any] = [:]
        if let languageCode, !languageCode.isEmpty {
            partial["language"] = languageCode
        } else {
            partial["language"] = NSNull()
        }
        let input: [String: Any] = [
            "id": sceneId,
            "custom_fields": ["partial": partial]
        ]
        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false); return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    func createPerformer(name: String, completion: @escaping (Performer?) -> Void) {
        let mutation = GraphQLQueries.performerCreateMutation
        let variables: [String: Any] = ["input": ["name": name]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(nil); return }
        performGraphQLQuery(query: bodyString) { (response: PerformerCreateResponse?) in
            completion(response?.data?.performerCreate)
        }
    }

    func createStudio(name: String, completion: @escaping (Studio?) -> Void) {
        let mutation = GraphQLQueries.studioCreateMutation
        let variables: [String: Any] = ["input": ["name": name]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(nil); return }
        performGraphQLQuery(query: bodyString) { (response: StudioCreateResponse?) in
            completion(response?.data?.studioCreate)
        }
    }

    func createGroup(name: String, completion: @escaping (StashGroup?) -> Void) {
        let mutation = GraphQLQueries.groupCreateMutation
        let variables: [String: Any] = ["input": ["name": name]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(nil); return }
        performGraphQLQuery(query: bodyString) { (response: GroupCreateResponse?) in
            completion(response?.data?.groupCreate)
        }
    }

    func createTag(name: String, completion: @escaping (Tag?) -> Void) {
        let mutation = GraphQLQueries.tagCreateMutation
        let variables: [String: Any] = ["input": ["name": name]]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else { completion(nil); return }
        performGraphQLQuery(query: bodyString) { (response: TagCreateResponse?) in
            completion(response?.data?.tagCreate)
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
        let mutation = GraphQLQueries.performerUpdateFavoriteMutation
        
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
    
    func setPerformerImage(performerId: String, imageURL: String, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.performerUpdateImageMutation
        let variables: [String: Any] = [
            "input": [
                "id": performerId,
                "image": imageURL
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: PerformerUpdateResponse?) in
            completion(response?.data?.performerUpdate != nil)
        }
    }

    /// Sets a tag's image from a URL or `data:image/...;base64,…` payload (same as Stash web / performer image).
    func setTagImage(tagId: String, image: String, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.tagUpdateImageMutation
        let variables: [String: Any] = [
            "input": [
                "id": tagId,
                "image": image
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: TagUpdateResponse?) in
            completion(response?.data?.tagUpdate != nil)
        }
    }

    /// Sets a scene cover / thumbnail from a URL or `data:image/...;base64,…` payload.
    func setSceneCoverImage(sceneId: String, image: String, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.sceneUpdateCoverImageMutation
        let variables: [String: Any] = [
            "input": [
                "id": sceneId,
                "cover_image": image
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: SceneUpdateResponse?) in
            completion(response?.data?.sceneUpdate != nil)
        }
    }

    /// Updates performer metadata shown on the detail screen (edit mode).
    func updatePerformerDetails(
        performerId: String,
        name: String,
        disambiguation: String?,
        birthdate: String?,
        country: String?,
        gender: String?,
        ethnicity: String?,
        height: Int?,
        weight: Int?,
        measurements: String?,
        fakeTits: String?,
        penisLength: Double?,
        careerLength: String?,
        tattoos: String?,
        piercings: String?,
        aliasList: [String]?,
        rating100: Int?,
        completion: @escaping (Bool) -> Void
    ) {
        let mutation = GraphQLQueries.performerUpdateDetailsMutation
        var input: [String: Any] = [
            "id": performerId,
            "name": name
        ]
        input["disambiguation"] = disambiguation ?? NSNull()
        input["birthdate"] = birthdate ?? NSNull()
        input["country"] = country ?? NSNull()
        input["gender"] = gender ?? NSNull()
        input["ethnicity"] = ethnicity ?? NSNull()
        input["height_cm"] = height ?? NSNull()
        input["weight"] = weight ?? NSNull()
        input["measurements"] = measurements ?? NSNull()
        input["fake_tits"] = fakeTits ?? NSNull()
        input["penis_length"] = penisLength ?? NSNull()
        input["career_length"] = careerLength ?? NSNull()
        input["tattoos"] = tattoos ?? NSNull()
        input["piercings"] = piercings ?? NSNull()
        input["alias_list"] = aliasList ?? NSNull()
        input["rating100"] = rating100 ?? NSNull()

        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: PerformerUpdateResponse?) in
            completion(response?.data?.performerUpdate != nil)
        }
    }

    func toggleStudioFavorite(studioId: String, favorite: Bool, completion: @escaping (Bool) -> Void) {
        let mutation = GraphQLQueries.studioUpdateFavoriteMutation
        
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

    /// Updates studio metadata shown on the detail screen (edit mode).
    func updateStudioDetails(
        studioId: String,
        name: String,
        url: String?,
        details: String?,
        rating100: Int?,
        completion: @escaping (Bool) -> Void
    ) {
        let mutation = GraphQLQueries.studioUpdateDetailsMutation
        var input: [String: Any] = [
            "id": studioId,
            "name": name
        ]
        input["url"] = url ?? NSNull()
        input["details"] = details ?? NSNull()
        input["rating100"] = rating100 ?? NSNull()

        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: StudioUpdateResponse?) in
            completion(response?.data?.studioUpdate != nil)
        }
    }

    /// Updates group metadata shown on the detail screen (edit mode).
    func updateGroupDetails(
        groupId: String,
        name: String,
        date: String?,
        synopsis: String?,
        rating100: Int?,
        completion: @escaping (Bool) -> Void
    ) {
        let mutation = GraphQLQueries.groupUpdateDetailsMutation
        var input: [String: Any] = [
            "id": groupId,
            "name": name
        ]
        input["date"] = date ?? NSNull()
        input["synopsis"] = synopsis ?? NSNull()
        input["rating100"] = rating100 ?? NSNull()

        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GroupUpdateResponse?) in
            completion(response?.data?.groupUpdate != nil)
        }
    }

    /// Updates gallery metadata shown on the opened-gallery screen (edit mode).
    func updateGalleryDetails(
        galleryId: String,
        title: String,
        date: String?,
        details: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let mutation = GraphQLQueries.galleryUpdateDetailsMutation
        var input: [String: Any] = [
            "id": galleryId,
            "title": title
        ]
        input["date"] = date ?? NSNull()
        input["details"] = details ?? NSNull()

        let variables: [String: Any] = ["input": input]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["query": mutation, "variables": variables]),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            completion(false)
            return
        }
        performGraphQLQuery(query: bodyString) { (response: GalleryUpdateResponse?) in
            completion(response?.data?.galleryUpdate != nil)
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
        let sceneId = scene.id
        let sceneMutation = """
        mutation {
            sceneDestroy(input: { id: "\(sceneId)" })
        }
        """

        let sceneRequestBody: [String: Any] = ["query": sceneMutation]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let sceneJsonData = try? JSONSerialization.data(withJSONObject: sceneRequestBody) else {
            completion(false)
            return
        }

        var request = stashRequest(to: url, config: config)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = sceneJsonData

        StashNetworking.session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                AppLog.error("Network error during scene deletion: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let data = data,
                  let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let dataDict = jsonResponse["data"] as? [String: Any],
                  dataDict["sceneDestroy"] != nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            if !fileIds.isEmpty {
                Task { @MainActor [weak self] in
                    self?.deleteSceneFiles(fileIds: fileIds, config: config) { success in
                        DispatchQueue.main.async {
                            if success {
                                NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": sceneId])
                            }
                            completion(success)
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": sceneId])
                    completion(true)
                }
            }
        }.resume()
    }

    private func deleteSceneFiles(fileIds: [String], config: ServerConfig, completion: @escaping (Bool) -> Void) {
        let filesMutation = GraphQLQueries.deleteFilesMutation

        let variables: [String: Any] = ["ids": fileIds]
        let requestBody: [String: Any] = ["query": filesMutation, "variables": variables]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(false)
            return
        }

        var request = stashRequest(to: url, config: config)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        StashNetworking.session.dataTask(with: request) { data, response, error in
            if let error = error {
                AppLog.error("Network error during file deletion: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            DispatchQueue.main.async {
                completion((response as? HTTPURLResponse)?.statusCode == 200)
            }
        }.resume()
    }
}

// Generic mutation response for simple mutations
struct GenericMutationResponse: Codable {
    let data: [String: String]?
}

struct FindJobResponse: Codable {
    let data: FindJobData?
}

struct FindJobData: Codable {
    let findJob: StashJob?
}

struct StashJob: Codable {
    let id: String
    let status: String
    let description: String?
    let progress: Double?
    let error: String?
}

struct StashConfigurationResponse: Codable {
    let data: StashConfigurationData?
}
struct StashConfigurationData: Codable {
    let configuration: StashConfigurationResult?
}
struct StashConfigurationResult: Codable {
    let general: StashGeneralConfig?
    let defaults: StashDefaultsConfig?
}
struct StashGeneralConfig: Codable {
    let stashBoxes: [StashBoxConfig]?
}
struct StashBoxConfig: Codable {
    let endpoint: String
    let name: String?
}
struct StashDefaultsConfig: Codable {
    let identify: StashIdentifyDefaults?
}
struct StashIdentifyDefaults: Codable {
    let sources: [StashIdentifySource]?
    let options: StashIdentifyOptions?
}
struct StashIdentifySource: Codable {
    let source: StashIdentifySourceRef?
    let options: StashIdentifyOptions?
}
struct StashIdentifySourceRef: Codable {
    let stash_box_endpoint: String?
    let stash_box_index: Int?
}
struct StashIdentifyOptions: Codable {
    let fieldOptions: [StashIdentifyFieldOption]?
    let setCoverImage: Bool?
    let setOrganized: Bool?
    let includeMalePerformers: Bool?
    let performerGenders: [String]?
    let skipMultipleMatches: Bool?
    let skipMultipleMatchTag: String?
    let skipSingleNamePerformers: Bool?
    let skipSingleNamePerformerTag: String?
}
struct StashIdentifyFieldOption: Codable {
    let field: String
    let strategy: String
    let createMissing: Bool?
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

struct PerformerCreateResponse: Codable {
    let data: PerformerCreateData?
}
struct PerformerCreateData: Codable {
    let performerCreate: Performer?
}

struct StudioCreateResponse: Codable {
    let data: StudioCreateData?
}
struct StudioCreateData: Codable {
    let studioCreate: Studio?
}

struct TagCreateResponse: Codable {
    let data: TagCreateData?
}
struct TagCreateData: Codable {
    let tagCreate: Tag?
}
struct GroupCreateResponse: Codable {
    let data: GroupCreateData?
}
struct GroupCreateData: Codable {
    let groupCreate: StashGroup?
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

struct GroupUpdateResponse: Codable {
    let data: GroupUpdateData?
}
struct GroupUpdateData: Codable {
    let groupUpdate: UpdatedItem?
}

struct GalleryUpdateResponse: Codable {
    let data: GalleryUpdateData?
}
struct GalleryUpdateData: Codable {
    let galleryUpdate: UpdatedItem?
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
    let scenesSize: Double
    let scenesDuration: Double
    let imageCount: Int
    let imagesSize: Double
    let galleryCount: Int
    let performerCount: Int
    let studioCount: Int
    let groupCount: Int
    let movieCount: Int
    let tagCount: Int
    let totalOCount: Int
    let totalPlayDuration: Double
    let totalPlayCount: Int
    let scenesPlayed: Int
    let sceneMarkerCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case sceneCount = "scene_count"
        case scenesSize = "scenes_size"
        case scenesDuration = "scenes_duration"
        case imageCount = "image_count"
        case imagesSize = "images_size"
        case galleryCount = "gallery_count"
        case performerCount = "performer_count"
        case studioCount = "studio_count"
        case groupCount = "group_count"
        case movieCount = "movie_count"
        case tagCount = "tag_count"
        case totalOCount = "total_o_count"
        case totalPlayDuration = "total_play_duration"
        case totalPlayCount = "total_play_count"
        case scenesPlayed = "scenes_played"
        case sceneMarkerCount = "scene_marker_count"
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

struct ScenesResponse: Codable {
    let data: ScenesData?
}

struct ScenesData: Codable {
    let findScenes: FindScenesResult
}

struct FindScenesResult: Codable {
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
    let scene_markers: [SceneMarker]?
}

struct SingleSceneResponse: Codable {
    let data: SingleSceneData?
}

struct SingleSceneData: Codable {
    let findScene: Scene?
}

struct StashID: Codable, Equatable {
    let endpoint: String?
    let stashId: String?

    enum CodingKeys: String, CodingKey {
        case endpoint
        case stashId = "stash_id"
    }
}

/// NSNotification `userInfo` drops nested Swift structs. Keep Scene on the heap.
final class SceneUpdatedPayload {
    let scene: Scene
    init(_ scene: Scene) {
        self.scene = scene
    }
}

struct Scene: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let details: String?
    /// Free-text field in Stash — there is no director entity, so it is matched by name.
    let director: String?
    let date: String?
    let duration: Double?
    let studio: SceneStudio?
    let performers: [ScenePerformer]
    let files: [SceneFile]?
    let tags: [Tag]?
    let galleries: [Gallery]?
    let groups: [SceneGroupEntry]?
    let organized: Bool?
    let resumeTime: Double?
    let playCount: Int?
    let playDuration: Double?
    let lastPlayedAt: String?
    let oCounter: Int?
    let rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    let paths: ScenePaths?
    let sceneMarkers: [SceneMarker]?
    let interactive: Bool?
    var streams: [SceneStream]?
    let stashIds: [StashID]?
    let captions: [VideoCaption]?
    let customFields: [String: StashJSONValue]?

    /// True when the scene already has at least one Stash-Box ID.
    var hasStashID: Bool {
        guard let stashIds else { return false }
        return stashIds.contains { id in
            !(id.stashId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var hasCaptions: Bool {
        !(captions ?? []).isEmpty
    }

    /// Stash returns `""` rather than `null` for an unset director.
    var normalizedDirector: String? {
        guard let trimmed = director?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Spoken language from Stash custom field `language`, accepting codes as well as names
    /// ("de", "de-DE", "yue-CN", "German", "Cantonese"). `nil` when unresolvable.
    var spokenLanguageCode: String? {
        SubtitleTargetLanguage.normalizedSceneLanguageTag(from: customFields?["language"]?.stringValue)
    }

    /// Prefer Direct/MP4 for speech reader; fall back to paths.stream.
    var transcriptionStreamURL: URL? {
        if let streams {
            let mp4 = streams.filter {
                $0.mime_type == "video/mp4" && !$0.label.lowercased().contains("mkv")
            }
            if let best = mp4.first, let url = URL(string: best.url) {
                return signedURL(url)
            }
            if let direct = streams.first(where: { $0.label.lowercased().contains("direct") }),
               let url = URL(string: direct.url) {
                return signedURL(url)
            }
        }
        if let path = paths?.stream, let url = URL(string: path) {
            return signedURL(url)
        }
        return videoURL
    }
    
    
    enum CodingKeys: String, CodingKey {
        case id, title, details, director, date, duration, studio, performers, files, tags, galleries, groups, organized, rating100, paths, interactive, streams, captions
        case resumeTime = "resume_time"
        case playCount = "play_count"
        case playDuration = "play_duration"
        case lastPlayedAt = "last_played_at"
        case oCounter = "o_counter"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sceneMarkers = "scene_markers"
        case stashIds = "stash_ids"
        case customFields = "custom_fields"
    }

    // Explicit initializer to handle manual updates like 'withStreams'
    init(id: String, title: String?, details: String?, director: String? = nil, date: String?, duration: Double?, studio: SceneStudio?, performers: [ScenePerformer], files: [SceneFile]?, tags: [Tag]?, galleries: [Gallery]?, groups: [SceneGroupEntry]? = nil, organized: Bool?, resumeTime: Double?, playCount: Int?, oCounter: Int?, rating100: Int?, createdAt: String?, updatedAt: String?, paths: ScenePaths?, sceneMarkers: [SceneMarker]?, interactive: Bool?, streams: [SceneStream]? = nil, stashIds: [StashID]? = nil, captions: [VideoCaption]? = nil, customFields: [String: StashJSONValue]? = nil, playDuration: Double? = nil, lastPlayedAt: String? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.director = director
        self.date = date
        self.duration = duration
        self.studio = studio
        self.performers = performers
        self.files = files
        self.tags = tags
        self.galleries = galleries
        self.groups = groups
        self.organized = organized
        self.resumeTime = resumeTime
        self.playCount = playCount
        self.playDuration = playDuration
        self.lastPlayedAt = lastPlayedAt
        self.oCounter = oCounter
        self.rating100 = rating100
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paths = paths
        self.sceneMarkers = sceneMarkers
        self.interactive = interactive
        self.streams = streams
        self.stashIds = stashIds
        self.captions = captions
        self.customFields = customFields
    }

    // Decodable init
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        director = try container.decodeIfPresent(String.self, forKey: .director)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        studio = try container.decodeIfPresent(SceneStudio.self, forKey: .studio)
        performers = try container.decode([ScenePerformer].self, forKey: .performers)
        files = try container.decodeIfPresent([SceneFile].self, forKey: .files)
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        galleries = try container.decodeIfPresent([Gallery].self, forKey: .galleries)
        groups = try container.decodeIfPresent([SceneGroupEntry].self, forKey: .groups)
        organized = try container.decodeIfPresent(Bool.self, forKey: .organized)
        resumeTime = try container.decodeIfPresent(Double.self, forKey: .resumeTime)
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount)
        playDuration = try container.decodeIfPresent(Double.self, forKey: .playDuration)
        lastPlayedAt = try container.decodeIfPresent(String.self, forKey: .lastPlayedAt)
        oCounter = try container.decodeIfPresent(Int.self, forKey: .oCounter)
        rating100 = try container.decodeIfPresent(Int.self, forKey: .rating100)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        paths = try container.decodeIfPresent(ScenePaths.self, forKey: .paths)
        sceneMarkers = try container.decodeIfPresent([SceneMarker].self, forKey: .sceneMarkers)
        interactive = try container.decodeIfPresent(Bool.self, forKey: .interactive)
        streams = try container.decodeIfPresent([SceneStream].self, forKey: .streams)
        stashIds = try container.decodeIfPresent([StashID].self, forKey: .stashIds)
        captions = try container.decodeIfPresent([VideoCaption].self, forKey: .captions)
        customFields = try container.decodeIfPresent([String: StashJSONValue].self, forKey: .customFields)
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
            items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
            comps?.queryItems = items
            return comps?.url ?? url
        }

        // Use path from API if available
        if let screenshotPath = paths?.screenshot {
            var path = screenshotPath
            let separator = path.contains("?") ? "&" : "?"
            path = "\(path)\(separator)width=640"
            
            // Add timestamp for cache busting
            if let updated = updatedAt {
                path = "\(path)&t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
            }

            if let url = URL(string: path) {
                 return signed(url)
            }
        }
        
        // Fallback to manual construction
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var manualPath = "\(config.baseURL)/scene/\(id)/screenshot?width=640"
        if let updated = updatedAt {
            manualPath = "\(manualPath)&t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signed(URL(string: manualPath))
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
            AppLog.debug("🎬 MP4 detected: Using direct stream for Original quality.")
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
                    AppLog.debug("📺 Using HLS stream (\(stream.label)) for quality \(quality.displayName)")
                    return url
                }
            }
            
            // Fallback: Use first HLS if no resolution match or for non-compatible formats
            if let firstHLS = hlsStreams.first, let url = URL(string: firstHLS.url) {
                AppLog.debug("📺 Using default HLS stream (\(firstHLS.label))")
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
                AppLog.debug("⚡ Using MP4 transcode (\(mp4.label)) for quality \(quality.displayName)")
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
                AppLog.debug("📂 Using local download for scene \(id)")
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
                AppLog.debug("⛔️ Preventing fallback to incompatible '\(fmt)' file for scene \(id)")
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
        items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
        comps?.queryItems = items
        return comps?.url ?? url
    }

    var hasFunscript: Bool {
        guard let f = paths?.funscript else { return false }
        return !f.isEmpty && f != "null"
    }

    var funscriptURL: URL? {
        guard let path = paths?.funscript, let url = URL(string: path) else { return nil }
        guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty else { return url }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
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
            AppLog.debug("💾 Download: Using best MP4 transcode (\(bestMP4.label)) for scene \(id)")
            return signedURL(url)
        }
        
        // 2. Fallback to original ONLY if it's compatible (MP4/MOV/etc)
        if isOriginalCompatible {
             if let streamPath = paths?.stream, let url = URL(string: streamPath) {
                 AppLog.debug("💾 Download: Using compatible original file (\(fileFmt)) for scene \(id)")
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
        
        AppLog.error("⚠️ Download: No compatible MP4 file found for scene \(id). Original format: \(fileFmt)")
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
            items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
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
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: newResumeTime, playCount: playCount, oCounter: oCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Creates a copy with updated rating
    func withRating(_ newRating: Int?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: playCount, oCounter: oCounter,
            rating100: newRating, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Creates a copy with updated streams
    func withStreams(_ newStreams: [SceneStream]?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: playCount, oCounter: oCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: newStreams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Creates a copy with updated play count
    func withPlayCount(_ newPlayCount: Int?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: newPlayCount, oCounter: oCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Creates a copy with updated o count
    func withOCounter(_ newOCounter: Int?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: playCount, oCounter: newOCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Copies list-visible metadata from a Scene Detail edit onto this list stub.
    /// Card badges (studio, release date, duration, performer count) prefer the
    /// incoming scene when present and never get wiped by empty notification payloads.
    func mergingListMetadata(from other: Scene) -> Scene {
        let mergedFiles: [SceneFile]? = {
            if let incoming = other.files, incoming.contains(where: { ($0.duration ?? 0) > 0 }) {
                return incoming
            }
            if let existing = files, existing.contains(where: { ($0.duration ?? 0) > 0 }) {
                return existing
            }
            return other.files ?? files
        }()
        let mergedDuration = other.duration
            ?? duration
            ?? mergedFiles?.compactMap(\.duration).max()
        let mergedDate: String? = {
            if let incoming = other.date, !incoming.isEmpty { return incoming }
            return date
        }()
        let mergedStudio = other.studio ?? studio
        let mergedPerformers = other.performers.isEmpty ? performers : other.performers

        return Scene(
            id: id,
            title: other.title ?? title,
            details: other.details ?? details,
            director: other.director ?? director,
            date: mergedDate,
            duration: mergedDuration,
            studio: mergedStudio,
            performers: mergedPerformers,
            files: mergedFiles,
            tags: other.tags ?? tags,
            galleries: other.galleries ?? galleries,
            groups: other.groups ?? groups,
            organized: other.organized ?? organized,
            resumeTime: resumeTime,
            playCount: playCount,
            oCounter: oCounter,
            rating100: other.rating100 ?? rating100,
            createdAt: createdAt,
            updatedAt: Self.newerUpdatedAt(other.updatedAt, updatedAt),
            paths: paths,
            sceneMarkers: sceneMarkers,
            interactive: interactive,
            streams: streams,
            stashIds: other.stashIds ?? stashIds,
            captions: captions,
            customFields: customFields,
            playDuration: playDuration,
            lastPlayedAt: lastPlayedAt
        )
    }

    /// Broadcasts title / details / studio / date / files / performers / tags / rating
    /// so catalog lists merge the edit when popping Scene Detail.
    func postListMetadataUpdated() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SceneUpdated"),
            object: nil,
            userInfo: ["payload": SceneUpdatedPayload(self)]
        )
    }

    static func fromListMetadataNotification(_ notification: Notification) -> Scene? {
        if let payload = notification.userInfo?["payload"] as? SceneUpdatedPayload {
            return payload.scene
        }
        return notification.userInfo?["scene"] as? Scene
    }

    /// Cover cache-bust timestamps must never go backwards during a metadata merge.
    static func newerUpdatedAt(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case let (a?, b?):
            if let da = parseUpdatedAt(a), let db = parseUpdatedAt(b) {
                return da >= db ? a : b
            }
            return a > b ? a : b
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        default:
            return nil
        }
    }

    private static func parseUpdatedAt(_ raw: String) -> Date? {
        if let millis = Int64(raw), (12...14).contains(raw.count) {
            return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        return nil
    }

    /// Creates a copy with updated `updatedAt` (cache-busts screenshot / cover URLs).
    func withUpdatedAt(_ newUpdatedAt: String?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: playCount, oCounter: oCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: newUpdatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: customFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    /// Creates a copy with updated custom fields (e.g. spoken `language`).
    func withCustomFields(_ newFields: [String: StashJSONValue]?) -> Scene {
        return Scene(
            id: id, title: title, details: details, director: director, date: date, duration: duration,
            studio: studio, performers: performers, files: files, tags: tags,
            galleries: galleries, groups: groups, organized: organized,
            resumeTime: resumeTime, playCount: playCount, oCounter: oCounter,
            rating100: rating100, createdAt: createdAt, updatedAt: updatedAt,
            paths: paths, sceneMarkers: sceneMarkers, interactive: interactive, streams: streams, stashIds: stashIds, captions: captions, customFields: newFields,
            playDuration: playDuration, lastPlayedAt: lastPlayedAt
        )
    }

    func withSpokenLanguage(_ code: String?) -> Scene {
        var fields = customFields ?? [:]
        if let code, !code.isEmpty {
            fields["language"] = .string(code)
        } else {
            fields.removeValue(forKey: "language")
        }
        return withCustomFields(fields.isEmpty ? nil : fields)
    }
    
}

struct VideoCaption: Codable, Equatable, Hashable, Identifiable {
    let languageCode: String
    let captionType: String

    var id: String { "\(languageCode).\(captionType)" }

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case captionType = "caption_type"
    }
}

struct SceneStream: Codable, Equatable {
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


struct ScenePaths: Codable, Equatable {
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

struct MarkerScene: Codable, Identifiable, Equatable {
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
    func withPerformers(_ newPerformers: [ScenePerformer]?) -> MarkerScene {
        MarkerScene(id: id, title: title, date: date, files: files, performers: newPerformers, rating100: rating100, playCount: playCount, oCounter: oCounter, interactive: interactive, paths: paths, streams: streams)
    }

    func toScene() -> Scene {
        Scene(
            id: id,
            title: title,
            details: nil,
            date: date,
            duration: files?.first?.duration,
            studio: nil,
            performers: performers ?? [],
            files: files,
            tags: nil,
            galleries: nil,
            organized: nil,
            resumeTime: nil,
            playCount: playCount,
            oCounter: oCounter,
            rating100: rating100,
            createdAt: nil,
            updatedAt: nil,
            paths: paths,
            sceneMarkers: nil,
            interactive: interactive,
            streams: streams
        )
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

struct SceneMarker: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let seconds: Double
    let endSeconds: Double?
    let primaryTag: Tag?
    let tags: [Tag]?
    let screenshot: String?
    let preview: String?
    let stream: String?
    let playCount: Int?
    let scene: MarkerScene?

    enum CodingKeys: String, CodingKey {
        case id, title, seconds, tags, screenshot, preview, stream, scene
        case endSeconds = "end_seconds"
        case primaryTag = "primary_tag"
        case playCount = "play_count"
    }

    func withScene(_ newScene: MarkerScene?) -> SceneMarker {
        SceneMarker(id: id, title: title, seconds: seconds, endSeconds: endSeconds, primaryTag: primaryTag, tags: tags, screenshot: screenshot, preview: preview, stream: stream, playCount: playCount, scene: newScene)
    }

    func withPlayCount(_ newCount: Int?) -> SceneMarker {
        SceneMarker(id: id, title: title, seconds: seconds, endSeconds: endSeconds, primaryTag: primaryTag, tags: tags, screenshot: screenshot, preview: preview, stream: stream, playCount: newCount, scene: scene)
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
                    AppLog.debug("📂 Using local download for marker \(id)")
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
                AppLog.debug("⛔️ Preventing fallback to incompatible '\(fmt)' file for marker \(id)")
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

struct SceneFile: Codable, Identifiable, Equatable {
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

struct SceneStudio: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case updatedAt = "updated_at"
    }

    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var thumbnailURLString = "\(config.baseURL)/studio/\(id)/image"
        if let updated = updatedAt {
            thumbnailURLString = "\(thumbnailURLString)?t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signedURL(URL(string: thumbnailURLString))
    }
}

struct ScenePerformer: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let birthdate: String?
    let sceneCount: Int?
    let galleryCount: Int?
    let oCounter: Int?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, birthdate
        case sceneCount = "scene_count"
        case galleryCount = "gallery_count"
        case oCounter = "o_counter"
        case updatedAt = "updated_at"
    }

    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var thumbnailURLString = "\(config.baseURL)/performer/\(id)/image"
        if let updated = updatedAt {
            thumbnailURLString = "\(thumbnailURLString)?t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signedURL(URL(string: thumbnailURLString))
    }

    func toGalleryPerformer() -> GalleryPerformer {
        GalleryPerformer(id: id, name: name, image_path: nil)
    }
}

// MARK: - Scene Group Entry
struct SceneGroupEntry: Codable, Identifiable, Equatable {
    let group: SceneGroupInfo
    let sceneIndex: Int?

    var id: String { group.id }

    enum CodingKeys: String, CodingKey {
        case group
        case sceneIndex = "scene_index"
    }
}

struct SceneGroupInfo: Codable, Equatable {
    let id: String
    let name: String
    let updatedAt: String?
    let frontImagePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case updatedAt = "updated_at"
        case frontImagePath = "front_image_path"
    }

    var thumbnailURL: URL? {
        guard let path = frontImagePath else { return nil }
        var urlString = path
        let separator = urlString.contains("?") ? "&" : "?"
        urlString += "\(separator)width=320"
        if let updated = updatedAt {
            urlString += "&t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        if urlString.starts(with: "http"), let url = URL(string: urlString) {
            return signedURL(url)
        }
        guard let config = ServerConfigManager.shared.loadConfig(),
              let url = URL(string: config.baseURL + urlString) else { return nil }
        return signedURL(url)
    }

    func toStashGroup() -> StashGroup {
        StashGroup(id: id, name: name, synopsis: nil, date: nil, scene_count: nil, gallery_count: nil, rating100: nil, updatedAt: updatedAt, front_image_path: frontImagePath, back_image_path: nil, studio: nil)
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

// MARK: - Performer Gender Stats (lightweight decode)
struct PerformerGenderCountsResponse: Codable {
    let data: PerformerGenderCountsData?
}

struct PerformerGenderCountsData: Codable {
    let findPerformers: PerformerGenderCountsResult
}

struct PerformerGenderCountsResult: Codable {
    let count: Int
    let performers: [PerformerGenderCountsPerformer]
}

struct PerformerGenderCountsPerformer: Codable {
    let gender: String?
}

// MARK: - Performer Aggregates (lightweight decode)
struct PerformerAggregatesResponse: Codable {
    let data: PerformerAggregatesData?
}

struct PerformerAggregatesData: Codable {
    let findPerformers: PerformerAggregatesResult
}

struct PerformerAggregatesResult: Codable {
    let count: Int
    let performers: [PerformerAggregatesPerformer]
}

struct PerformerAggregatesPerformer: Codable {
    let rating100: Int?
    let oCounter: Int?

    enum CodingKeys: String, CodingKey {
        case rating100
        case oCounter = "o_counter"
    }
}

struct PerformerAggregates: Equatable {
    let totalCount: Int
    let ratedCount: Int
    let averageRating100: Double?
    let minRating100: Int?
    let maxRating100: Int?
    let oCounterCount: Int
    let averageOCounter: Double?
    let maxOCounter: Int
}

// MARK: - Scene Aggregates (lightweight decode)
struct SceneAggregatesResponse: Codable {
    let data: SceneAggregatesData?
}

struct SceneAggregatesData: Codable {
    let findScenes: SceneAggregatesResult
}

struct SceneAggregatesResult: Codable {
    let count: Int
    let scenes: [SceneAggregatesScene]
}

struct SceneAggregatesScene: Codable {
    let rating100: Int?
    let oCounter: Int?
    let playCount: Int?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case rating100
        case oCounter = "o_counter"
        case playCount = "play_count"
        case duration
    }
}

struct SceneAggregates: Equatable {
    let totalCount: Int
    let ratedCount: Int
    let averageRating100: Double?
    let minRating100: Int?
    let maxRating100: Int?
    let oCounterCount: Int
    let averageOCounter: Double?
    let maxOCounter: Int
    let playCountCount: Int
    let averagePlayCount: Double?
    let maxPlayCount: Int
    let durationCount: Int
    let averageDurationSeconds: Double?
    let maxDurationSeconds: Double
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
    var sceneCountDisplay: Int { sceneCount }
    var details: String? { nil } // Performers don't have a large details text in the same way
    let id: String
    var name: String
    var disambiguation: String?
    var birthdate: String?
    var country: String?
    var imagePath: String?
    let sceneCount: Int
    var imageCount: Int? = nil
    let galleryCount: Int?
    var gender: String?
    var ethnicity: String?
    var height: Int? // height_cm
    var weight: Int?
    var measurements: String?
    var fakeTits: String?
    var penis_length: Double?
    var careerLength: String?
    var tattoos: String?
    var piercings: String?
    var aliasList: [String]?
    let favorite: Bool?
    var rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    let oCounter: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, disambiguation, birthdate, country, gender, ethnicity, weight, measurements, tattoos, piercings, favorite, rating100
        case oCounter = "o_counter"
        case imagePath = "image_path"
        case sceneCount = "scene_count"
        case imageCount = "image_count"
        case galleryCount = "gallery_count"
        case height = "height_cm"
        case fakeTits = "fake_tits"
        case penis_length
        case careerLength = "career_length"
        case aliasList = "alias_list"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        if let path = imagePath, (path.starts(with: "http://") || path.starts(with: "https://")) {
            return signedURL(URL(string: path))
        }

        guard let config = ServerConfigManager.shared.loadConfig() else {
            return nil
        }

        let thumbnailURLString = "\(config.baseURL)/performer/\(id)/image"
        return signedURL(URL(string: thumbnailURLString))
    }

    func withOCounter(_ newOCounter: Int?) -> Performer {
        Performer(
            id: id,
            name: name,
            disambiguation: disambiguation,
            birthdate: birthdate,
            country: country,
            imagePath: imagePath,
            sceneCount: sceneCount,
            imageCount: imageCount,
            galleryCount: galleryCount,
            gender: gender,
            ethnicity: ethnicity,
            height: height,
            weight: weight,
            measurements: measurements,
            fakeTits: fakeTits,
            penis_length: penis_length,
            careerLength: careerLength,
            tattoos: tattoos,
            piercings: piercings,
            aliasList: aliasList,
            favorite: favorite,
            rating100: rating100,
            createdAt: createdAt,
            updatedAt: updatedAt,
            oCounter: newOCounter
        )
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

struct Studio: Codable, Identifiable, Equatable {
    var sceneCountDisplay: Int { sceneCount }
    let id: String
    var name: String
    var url: String?
    let sceneCount: Int
    let performerCount: Int?
    let galleryCount: Int?
    /// From `image_count` on `Studio` (GraphQL); used for studio picker ordering and display.
    let imageCount: Int?
    var details: String?
    let imagePath: String?
    var favorite: Bool?
    var rating100: Int?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, details, favorite, rating100
        case sceneCount = "scene_count"
        case performerCount = "performer_count"
        case galleryCount = "gallery_count"
        case imageCount = "image_count"
        case imagePath = "image_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(id: String, name: String, url: String? = nil, sceneCount: Int = 0, performerCount: Int? = nil, galleryCount: Int? = nil, imageCount: Int? = nil, details: String? = nil, imagePath: String? = nil, favorite: Bool? = nil, rating100: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.sceneCount = sceneCount
        self.performerCount = performerCount
        self.galleryCount = galleryCount
        self.imageCount = imageCount
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
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var thumbnailURLString = "\(config.baseURL)/studio/\(id)/image"
        if let updated = updatedAt {
            thumbnailURLString = "\(thumbnailURLString)?t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
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

struct Tag: Codable, Identifiable, Equatable {
    var sceneCountDisplay: Int { sceneCount ?? 0 }
    var details: String? { description }
    var rating100: Int? { nil }
    let id: String
    var name: String
    var description: String?
    var imagePath: String?
    let sceneCount: Int?
    let imageCount: Int?
    let galleryCount: Int?
    let sceneMarkerCount: Int?
    let performerCount: Int?
    var favorite: Bool?
    let createdAt: String?
    var updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, favorite, description
        case imagePath = "image_path"
        case sceneCount = "scene_count"
        case imageCount = "image_count"
        case galleryCount = "gallery_count"
        case sceneMarkerCount = "scene_marker_count"
        case performerCount = "performer_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var manualPath = "\(config.baseURL)/tag/\(id)/image"
        if let updated = updatedAt {
            manualPath = "\(manualPath)?t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signedURL(URL(string: manualPath))
    }
}

// MARK: - Group Models
struct GroupsResponse: Codable {
    let data: GroupsData?
}

struct GroupsData: Codable {
    let findGroups: FindGroupsResult
}

struct FindGroupsResult: Codable {
    let count: Int
    let groups: [StashGroup]
}

struct SingleGroupResponse: Codable {
    let data: SingleGroupData?
}

struct SingleGroupData: Codable {
    let findGroup: StashGroup?
}

struct ImagesResponse: Codable {
    let data: ImagesData?
}

struct ImagesData: Codable {
    let findImages: FindImagesResult
}

struct StashGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var synopsis: String?
    var date: String?
    let scene_count: Int?
    let gallery_count: Int?
    var rating100: Int?
    let updatedAt: String?
    let front_image_path: String?
    let back_image_path: String?
    let studio: GroupStudio?
    
    var details: String? { synopsis }
    var favorite: Bool? { nil }
    var sceneCountDisplay: Int { scene_count ?? 0 }

    enum CodingKeys: String, CodingKey {
        case id, name, synopsis, date, scene_count, gallery_count, rating100, front_image_path, back_image_path, studio
        case updatedAt = "updated_at"
    }
    
    // Computed property for thumbnail URL (using front image)
    var thumbnailURL: URL? {
        if var path = front_image_path {
            let separator = path.contains("?") ? "&" : "?"
            path = "\(path)\(separator)width=640"
            
            if let updated = updatedAt {
                path = "\(path)&t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
            }
            
            if let url = URL(string: path) {
                if path.starts(with: "http") {
                    return signedURL(url)
                }
                guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
                return signedURL(URL(string: config.baseURL + path))
            }
        }
        
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        var fallbackPath = "\(config.baseURL)/group/\(id)/frontimage"
        if let updated = updatedAt {
            fallbackPath = "\(fallbackPath)?t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signedURL(URL(string: fallbackPath))
    }
}

struct GroupStudio: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

#if os(tvOS)
extension Performer: TVDetailItem {}
extension Studio: TVDetailItem {}
extension Tag: TVDetailItem {}
extension StashGroup: TVDetailItem {}
#endif

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

struct Gallery: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var date: String?
    var details: String?
    let imageCount: Int?
    var rating100: Int? = nil
    let organized: Bool?
    let createdAt: String?
    let updatedAt: String?
    let studio: GalleryStudio?
    var performers: [GalleryPerformer]?
    let cover: GalleryCover?

    enum CodingKeys: String, CodingKey {
        case id, title, date, details, imageCount = "image_count", rating100, organized, createdAt = "created_at", updatedAt = "updated_at", studio, performers, cover
    }
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        
        if let thumbnailPath = cover?.paths.thumbnail {
            var path = thumbnailPath
            let separator = path.contains("?") ? "&" : "?"
            path = "\(path)\(separator)width=640"
            
            if let updated = updatedAt {
                path = "\(path)&t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
            }
            
            // Check if the path is already an absolute URL
            if path.starts(with: "http://") || path.starts(with: "https://") {
                return signedURL(URL(string: path))
            } else {
                // Relative path, prepend baseURL
                return signedURL(URL(string: config.baseURL + path))
            }
        }
        
        // Fallback when cover wasn't loaded (e.g. stub Gallery from image→gallery navigation).
        var fallbackPath = "\(config.baseURL)/gallery/\(id)/cover"
        if let updated = updatedAt {
            let separator = fallbackPath.contains("?") ? "&" : "?"
            fallbackPath = "\(fallbackPath)\(separator)t=\(updated.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? updated)"
        }
        return signedURL(URL(string: fallbackPath))
    }
    
    var coverURL: URL? {
        thumbnailURL
    }
    
    var displayName: String {
        if !title.isEmpty { return title }
        return "Untitled Gallery"
    }
}

struct GalleryStudio: Codable, Equatable {
    let id: String
    let name: String
}

struct GalleryPerformer: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    var image_path: String?

    func toPerformer() -> Performer {
        Performer(id: id, name: name, disambiguation: nil, birthdate: nil, country: nil,
                  imagePath: image_path, sceneCount: 0, galleryCount: nil, gender: nil,
                  ethnicity: nil, height: nil, weight: nil, measurements: nil, fakeTits: nil,
                  penis_length: nil, careerLength: nil, tattoos: nil, piercings: nil, aliasList: nil, favorite: nil,
                  rating100: nil, createdAt: nil, updatedAt: nil, oCounter: nil)
    }

    var thumbnailURL: URL? {
        if let path = image_path, !path.isEmpty,
           let config = ServerConfigManager.shared.loadConfig() {
            let separator = path.contains("?") ? "&" : "?"
            let sized = "\(path)\(separator)width=200"
            if sized.starts(with: "http://") || sized.starts(with: "https://") {
                return signedURL(URL(string: sized))
            }
            return signedURL(URL(string: config.baseURL + sized))
        }
        // Fallback when GraphQL omitted image_path (same endpoint as ScenePerformer).
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return signedURL(URL(string: "\(config.baseURL)/performer/\(id)/image"))
    }

    func toScenePerformer() -> ScenePerformer {
        ScenePerformer(id: id, name: name, birthdate: nil, sceneCount: 0, galleryCount: 0, oCounter: 0, updatedAt: nil)
    }
}

// struct GalleryFile: Codable {
//     let `extension`: String?
// }

struct ImageFile: Codable, Equatable {
    let path: String
    let height: Int?
    let width: Int?
    let duration: Double?
    let basename: String?
}

struct ImageGallery: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
}

struct GalleryCover: Codable, Equatable {
    let id: String
    let paths: GalleryCoverPaths
}

struct GalleryCoverPaths: Codable, Equatable {
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

struct StashImage: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let rating100: Int?
    let o_counter: Int?
    let organized: Bool?
    let date: String?
    let createdAt: String?
    let updatedAt: String?
    let paths: ImagePaths?
    // let files: [ImageFile]?
    let visual_files: [ImageFile]?
    var performers: [GalleryPerformer]?
    let studio: GalleryStudio?
    let galleries: [ImageGallery]?
    let tags: [Tag]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, rating100, o_counter, organized, date, paths, performers, studio, galleries, visual_files, tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    var isVideo: Bool {
        let videoExtensions = ["MP4", "MOV", "M4V", "WEBM", "MKV"]
        if let ext = fileExtension?.uppercased() {
             return videoExtensions.contains(ext)
        }
        return false
    }

    /// Pixel size from the primary visual file, when known.
    var pixelSize: CGSize? {
        guard let w = visual_files?.first?.width, let h = visual_files?.first?.height,
              w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// 1/row Images feed card aspect (width ÷ height):
    /// square → 1:1, portrait (incl. portrait video) → 9:12, landscape → native ratio.
    var oneColumnFeedAspectRatio: CGFloat {
        guard let size = pixelSize else { return 1 }
        if size.width > size.height {
            return size.width / size.height
        }
        if size.height > size.width {
            return 9.0 / 12.0
        }
        return 1
    }

    var isAnimated: Bool {
        if let ext = fileExtension?.uppercased() {
            return ext == "GIF" || ext == "WEBP"
        }
        return false
    }
    
    @available(*, deprecated, message: "Use isAnimated instead to support both GIF and WebP")
    var isGIF: Bool {
        return isAnimated
    }

    var fileExtension: String? {
        if let basename = visual_files?.first?.basename, !basename.isEmpty {
            let ext = (basename as NSString).pathExtension
            if !ext.isEmpty { return ext.uppercased() }
        }

        // Primary: Use 'visual_files' array if available
        if let path = visual_files?.first?.path {
            let ext = URL(fileURLWithPath: path).pathExtension
            if !ext.isEmpty { return ext.uppercased() }
        }
        
        // Fallback: Use 'paths.image'
        if let imagePath = paths?.image {
            let cleanPath = imagePath.components(separatedBy: "?").first ?? imagePath
            let ext = URL(fileURLWithPath: cleanPath).pathExtension
            if !ext.isEmpty { return ext.uppercased() }
        }
        
        return nil
    }

    var isGifFile: Bool {
        if fileExtension?.uppercased() == "GIF" { return true }
        let candidates = [
            visual_files?.first?.basename,
            visual_files?.first?.path,
            paths?.image,
            paths?.preview,
            paths?.thumbnail,
            title
        ].compactMap { $0 }
        return candidates.contains { candidate in
            let base = (candidate.components(separatedBy: "?").first ?? candidate).lowercased()
            return base.hasSuffix(".gif")
        }
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
            createdAt: createdAt,
            updatedAt: updatedAt,
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
            createdAt: createdAt,
            updatedAt: updatedAt,
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



struct ImagePaths: Codable, Equatable {
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

final class DownloadTaskMap: Sendable {
    private let tasks = Mutex<[Int: (String, URL)]>([:])

    nonisolated init() {}

    nonisolated func set(_ taskId: Int, info: (String, URL)) {
        tasks.withLock { $0[taskId] = info }
    }

    nonisolated func get(_ taskId: Int) -> (String, URL)? {
        tasks.withLock { $0[taskId] }
    }

    nonisolated func remove(_ taskId: Int) -> (String, URL)? {
        tasks.withLock { $0.removeValue(forKey: taskId) }
    }

    nonisolated func taskIds(matching id: String) -> [Int] {
        tasks.withLock { map in
            map.filter { $0.value.0 == id || $0.value.0 == "\(id)_thumb" }.map(\.key)
        }
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
        config.timeoutIntervalForResource = 6 * 60 * 60
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
                    AppLog.debug("🗑️ Removed incomplete/orphaned download folder: \(itemName)")
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
        #if !os(tvOS)
        guard StashyPlusManager.isUnlockedNow else {
            ToastManager.shared.show(
                "Downloads are part of stashy+ — unlock in Settings",
                icon: "sparkles",
                style: .error
            )
            return
        }
        #endif

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

    /// Cancels an in-flight download (video + thumbnail tasks) and cleans up partial data.
    func cancelDownload(id: String) {
        guard activeDownloads[id] != nil else { return }

        let taskIds = Set(taskMap.taskIds(matching: id))
        guard !taskIds.isEmpty else { return }

        session.getAllTasks { tasks in
            for task in tasks where taskIds.contains(task.taskIdentifier) {
                task.cancel()
            }
        }
        AppLog.debug("📥 DownloadManager: Cancelling download \(id) (\(taskIds.count) task(s))")
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
            AppLog.error("❌ DownloadManager: Failed to move file: \(error)")
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
        // AppLog.debug("📥 Download Progress: \(totalBytesWritten) / \(totalBytesExpectedToWrite) (...)")
        
        if let (id, _) = taskMap.get(downloadTask.taskIdentifier) {
            Task { @MainActor in
                self.progressHandlers[id]?(progress, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let capturedError = error {
            AppLog.error("❌ DownloadManager: Task \(task.taskIdentifier) completed with error: \(capturedError)")
            
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

/// AVPlayerViewController drops hardware-keyboard skip on Mac / iPad fullscreen.
/// We re-apply ±15s arrow seeks only while fullscreen so inline Apple shortcuts stay single-fire.
final class StashyPlayerViewController: AVPlayerViewController {
    var handlesFullscreenKeyboardSkip = false {
        didSet {
            if handlesFullscreenKeyboardSkip {
                becomeFirstResponder()
            }
        }
    }
    private let skipInterval: TimeInterval = 15
    private var windowFullscreenObservers: [NSObjectProtocol] = []

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard handlesFullscreenKeyboardSkip else { return super.keyCommands }
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(skipBackward)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(skipForward)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        observeMacWindowFullscreenIfNeeded()
        if handlesFullscreenKeyboardSkip {
            becomeFirstResponder()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        windowFullscreenObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowFullscreenObservers.removeAll()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard handlesFullscreenKeyboardSkip else {
            super.pressesBegan(presses, with: event)
            return
        }
        for press in presses {
            switch press.key?.keyCode {
            case .keyboardLeftArrow:
                skip(by: -skipInterval)
                return
            case .keyboardRightArrow:
                skip(by: skipInterval)
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    @objc private func skipBackward() { skip(by: -skipInterval) }
    @objc private func skipForward() { skip(by: skipInterval) }

    private func skip(by seconds: TimeInterval) {
        guard let player, let item = player.currentItem else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        var target = current + seconds
        let duration = item.duration.seconds
        if duration.isFinite {
            target = min(max(0, target), max(0, duration))
        } else {
            target = max(0, target)
        }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .positiveInfinity,
            toleranceAfter: .positiveInfinity
        )
    }

    /// Designed-for-iPad on Mac: the green-button window fullscreen is not
    /// `AVPlayerViewController` fullscreen, so Apple's skip shortcuts disappear.
    private func observeMacWindowFullscreenIfNeeded() {
        guard ProcessInfo.processInfo.isiOSAppOnMac, windowFullscreenObservers.isEmpty else { return }
        let center = NotificationCenter.default
        windowFullscreenObservers.append(center.addObserver(
            forName: NSNotification.Name("NSWindowDidEnterFullScreenNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlesFullscreenKeyboardSkip = true
        })
        windowFullscreenObservers.append(center.addObserver(
            forName: NSNotification.Name("NSWindowDidExitFullScreenNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlesFullscreenKeyboardSkip = false
        })
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isFullscreen: Bool
    /// When `false`, the hosted `AVPlayerViewController` keeps `player == nil` so another
    /// surface (e.g. a `fullScreenCover`) can attach the same `AVPlayer`.
    var attachPlayer: Bool = true
    var showsPlaybackControls: Bool = true
    /// External WebVTT captions rendered via `contentOverlayView` (works inline + fullscreen).
    var subtitleText: String = ""
    /// Reserved for future native-menu integration. iOS' `AVPlayerViewController`
    /// has no public API for transport-bar custom menus (those are tvOS-only),
    /// so the value is ignored on this platform — quality selection happens via
    /// the SwiftUI overlay rendered above the inline player.
    var transportMenu: UIMenu? = nil
    @ObservedObject var tabManager = TabManager.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player, isFullscreen: $isFullscreen)
    }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = StashyPlayerViewController()
        playerViewController.player = attachPlayer ? player : nil
        playerViewController.delegate = context.coordinator
        playerViewController.showsPlaybackControls = showsPlaybackControls
        playerViewController.videoGravity = .resizeAspect
        playerViewController.allowsPictureInPicturePlayback = TabManager.shared.isPiPEnabled
        playerViewController.canStartPictureInPictureAutomaticallyFromInline = TabManager.shared.isPiPEnabled
        applyBackgroundPlaybackPolicy(to: player)
        if #available(iOS 16.0, *) {
            // Verhindert das Analyse-/„Text erkennen“-Steuerelement bei pausierten Frames (Visual Look Up).
            playerViewController.allowsVideoFrameAnalysis = false
        }
        context.coordinator.installSubtitleOverlay(on: playerViewController)
        context.coordinator.updateSubtitleText(subtitleText)
        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.showsPlaybackControls = showsPlaybackControls
        if attachPlayer {
            if uiViewController.player !== player { uiViewController.player = player }
        } else {
            uiViewController.player = nil
        }
        if uiViewController.allowsPictureInPicturePlayback != tabManager.isPiPEnabled {
            uiViewController.allowsPictureInPicturePlayback = tabManager.isPiPEnabled
        }
        if uiViewController.canStartPictureInPictureAutomaticallyFromInline != tabManager.isPiPEnabled {
            uiViewController.canStartPictureInPictureAutomaticallyFromInline = tabManager.isPiPEnabled
        }
        applyBackgroundPlaybackPolicy(to: player)
        if #available(iOS 16.0, *) {
            if uiViewController.allowsVideoFrameAnalysis {
                uiViewController.allowsVideoFrameAnalysis = false
            }
        }
        context.coordinator.installSubtitleOverlay(on: uiViewController)
        context.coordinator.updateSubtitleText(subtitleText)
        if let stashyPlayer = uiViewController as? StashyPlayerViewController {
            stashyPlayer.handlesFullscreenKeyboardSkip = isFullscreen
        }
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var player: AVPlayer
        @Binding var isFullscreen: Bool
        private weak var subtitleLabel: UILabel?
        private weak var subtitleContainer: UIView?

        init(player: AVPlayer, isFullscreen: Binding<Bool>) {
            self.player = player
            _isFullscreen = isFullscreen
        }

        func installSubtitleOverlay(on controller: AVPlayerViewController) {
            guard let overlay = controller.contentOverlayView else { return }
            if subtitleContainer?.superview === overlay {
                overlay.bringSubviewToFront(subtitleContainer!)
                return
            }

            subtitleContainer?.removeFromSuperview()

            let container = UIView()
            container.isUserInteractionEnabled = false
            container.translatesAutoresizingMaskIntoConstraints = false
            container.isHidden = true
            overlay.addSubview(container)

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.numberOfLines = 3
            label.textColor = .white
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.95
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = CGSize(width: 0, height: 1)
            label.isHidden = true
            container.addSubview(label)

            // Near the bottom in fullscreen (inline uses SwiftUI overlay instead).
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -16),
                container.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -28),

                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            ])

            overlay.bringSubviewToFront(container)
            subtitleContainer = container
            subtitleLabel = label
        }

        func updateSubtitleText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let label = subtitleLabel, let container = subtitleContainer else { return }
            label.text = trimmed
            let visible = !trimmed.isEmpty
            label.isHidden = !visible
            container.isHidden = !visible
            container.backgroundColor = visible ? UIColor.black.withAlphaComponent(0.55) : .clear
            container.layer.cornerRadius = 8
            container.clipsToBounds = true
            if visible, let overlay = container.superview {
                overlay.bringSubviewToFront(container)
            }
        }

        func playerViewController(_ playerViewController: AVPlayerViewController, willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            isFullscreen = true
            if let stashyPlayer = playerViewController as? StashyPlayerViewController {
                stashyPlayer.handlesFullscreenKeyboardSkip = true
                coordinator.animate(alongsideTransition: nil) { _ in
                    stashyPlayer.becomeFirstResponder()
                }
            }
        }

        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            (playerViewController as? StashyPlayerViewController)?.handlesFullscreenKeyboardSkip = false
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
    
    func searchGroupsAsync(query: String, limit: Int = 5) async -> [StashGroup] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findGroups")
            
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
            
            performGraphQLQuery(query: bodyString) { (response: GroupsResponse?) in
                continuation.resume(returning: response?.data?.findGroups.groups ?? [])
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
                        // Most-used first (same field as Tags catalog scene-count sort).
                        "sort": TagSortOption.sceneCountDesc.sortField,
                        "direction": TagSortOption.sceneCountDesc.direction
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

    func searchImagesAsync(query: String, limit: Int = 5) async -> [StashImage] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findImages")

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

            performGraphQLQuery(query: bodyString) { (response: GalleryImagesResponse?) in
                continuation.resume(returning: response?.data?.findImages.images ?? [])
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

    func searchMarkersAsync(query: String, limit: Int = 5) async -> [SceneMarker] {
        await withCheckedContinuation { continuation in
            let graphqlQuery = GraphQLQueries.queryWithFragments("findSceneMarkers")
            
            let body: [String: Any] = [
                "query": graphqlQuery,
                "variables": [
                    "filter": [
                        "q": query,
                        "per_page": limit,
                        "page": 1,
                        "sort": "title",
                        "direction": "ASC"
                    ]
                ]
            ]
            
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
                  let bodyString = String(data: bodyData, encoding: .utf8) else {
                continuation.resume(returning: [])
                return
            }
            
            performGraphQLQuery(query: bodyString) { (response: MarkersResponse?) in
                continuation.resume(returning: response?.data?.findSceneMarkers.scene_markers ?? [])
            }
        }
    }
    
    func fetchSceneStreams(sceneId: String, completion: @escaping ([SceneStream]) -> Void) {
        // RAM cache: the stream list (HLS/MP4 variants + direct stream URL) is
        // deterministic per scene for the session, but we hit this endpoint
        // every time the user opens a SceneDetailView (and once per Reels
        // card). Caching shaves a full GraphQL round-trip off detail opens,
        // which is especially noticeable on tapped-through navigation.
        if let cached = SceneStreamsRAMCache.shared.streams(for: sceneId) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        let query = GraphQLQueries.loadQuery(named: "sceneStreams")
        let variables = ["id": sceneId]

        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            // Konsistent zur Erfolgsbahn: completion immer auf Main aufrufen
            // (UI / `@Published`-Updates erwarten Main-Thread).
            DispatchQueue.main.async { completion([]) }
            return
        }

        performGraphQLQuery(query: bodyString, clearsGlobalErrorMessageOnStart: false, setsGlobalLoading: false) { (response: SceneStreamsResponse?) in
            if let response {
                let streams = response.data?.sceneStreams ?? []
                AppLog.debug("📺 Fetched \(streams.count) transcoded streams for scene \(sceneId)")
                // Cache only real results — an empty list here is usually a failed
                // request (nil response path below), and caching that would black-hole
                // the reel's stream resolution for the whole TTL.
                if !streams.isEmpty {
                    SceneStreamsRAMCache.shared.set(streams, for: sceneId)
                }
                DispatchQueue.main.async {
                    completion(streams)
                }
            } else {
                AppLog.error("📺 Stream resolution failed for scene \(sceneId) — not caching, caller may retry")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    /// Warms `SceneStreamsRAMCache` right after a feed page lands so the first visible
    /// rows can create their players synchronously. This removes the cold-start race
    /// where row mount, player setup and stream resolution all collide during the
    /// initial request burst (black first cell).
    func prefetchSceneStreams(sceneIds: [String], limit: Int = 4) {
        guard activeReelsFeed == .scenes else { return }
        let generation = streamPrefetchGeneration
        for id in sceneIds.prefix(limit) where SceneStreamsRAMCache.shared.streams(for: id) == nil {
            fetchSceneStreams(sceneId: id) { [weak self] _ in
                guard let self, generation == self.streamPrefetchGeneration else { return }
            }
        }
    }
}

/// Session-lifetime RAM cache for scene stream metadata. Cleared only on
/// explicit invalidation (e.g. server change) or app restart.
final class SceneStreamsRAMCache {
    static let shared = SceneStreamsRAMCache()
    private let lock = NSLock()
    private var store: [String: (streams: [SceneStream], cachedAt: Date)] = [:]
    /// 10-minute TTL — keeps re-opens instant without pinning stale URLs
    /// forever when the server reconfigures transcoders.
    private let ttl: TimeInterval = 10 * 60
    private init() {}

    func streams(for sceneId: String) -> [SceneStream]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[sceneId] else { return nil }
        if Date().timeIntervalSince(entry.cachedAt) > ttl {
            store[sceneId] = nil
            return nil
        }
        return entry.streams
    }

    func set(_ streams: [SceneStream], for sceneId: String) {
        lock.lock(); defer { lock.unlock() }
        store[sceneId] = (streams, Date())
    }

    func invalidate(sceneId: String) {
        lock.lock(); defer { lock.unlock() }
        store[sceneId] = nil
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
}

#if !os(tvOS)
class HandyManager: ObservableObject {
    static let shared = HandyManager()

    @AppStorage("handy_connection_key") var connectionKey: String = ""
    @AppStorage("handy_public_url") var publicUrl: String = ""
    @AppStorage("handy_device_type") var deviceType: String = "The Handy" // "The Handy" or "Oh."
    /// HAMP: stroke range 0–100 (min position and max position, symmetric around 50)
    @AppStorage("handy_stroke_length") var strokeLength: Double = 100.0  // 0–100%
    /// HAMP: max velocity cap 0–100%
    @AppStorage("handy_max_velocity") var maxVelocity: Double = 100.0    // 0–100%
    /// HVP (Oh.): max amplitude cap 0–1
    @AppStorage("handy_max_amplitude") var maxAmplitude: Double = 1.0    // 0–1
    @AppStorage("handy_enabled") var isEnabled: Bool = false {
        didSet {
            if !isEnabled && isConnected {
                pause()
                isConnected = false
            }
        }
    }

    @Published var isConnected: Bool = false
    @Published var isStashSyncMode: Bool = false {
        didSet {
            if isStashSyncMode {
                isSyncing = false
                setupStashSync()
            } else {
                stashCancellable = nil
                // Send explicit stop before clearing state
                if isConnected {
                    if deviceType == "Oh." {
                        sendRequest(path: "/hvp/stop", method: "PUT") { _ in }
                    } else {
                        sendRequest(path: "/hamp/stop", method: "PUT") { _ in }
                    }
                }
                hampIsRunning = false
                if !isSyncing { stop() }
            }
        }
    }
    @Published var isSyncing: Bool = false
    @Published var isPlayingScript: Bool = false
    @Published var statusMessage: String = "Not Configured"

    // API v3
    private let baseURL = "https://www.handyfeeling.com/api/handy-rest/v3"
    private let handyApiKey = "Wu8AA1nDwSJl_P_pQiCdQkOnjNQjLVBL"

    private var cancellables = Set<AnyCancellable>()
    private var stashCancellable: AnyCancellable?
    private var currentTask: URLSessionDataTask?
    private var lastAudioCommandTime: Date = .distantPast

    private init() {
        if !connectionKey.isEmpty { checkConnection() }
    }

    // MARK: - StashSync (video-reactive mode)

    private func setupStashSync() {
        let modeStr = deviceType == "Oh." ? "HVP" : "HAMP"
        AppLog.debug("📲 Handy v3: setupStashSync() — starting \(modeStr)")
        // Put device in HAMP/HVP mode (mode2 = 0) then start motion
        sendRequest(path: "/mode2", method: "PUT", params: ["mode": 0]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                let body = String(data: data, encoding: .utf8) ?? "(empty)"
                AppLog.debug("📲 Handy /mode2 response: \(body)")
            case .failure(let e):
                AppLog.error("❌ Handy /mode2 failed: \(e.localizedDescription)")
            }
            if self.deviceType == "Oh." {
                self.sendRequest(path: "/hvp/start", method: "PUT") { r in
                    if case .success(let d) = r { AppLog.debug("📲 Handy /hvp/start: \(String(data: d, encoding: .utf8) ?? "")") }
                    else if case .failure(let e) = r { AppLog.error("❌ Handy /hvp/start failed: \(e)") }
                }
            } else {
                // Set stroke range before starting
                let halfStroke = self.strokeLength / 2.0
                let slideMin = max(0, 50.0 - halfStroke)
                let slideMax = min(100, 50.0 + halfStroke)
                self.sendRequest(path: "/hamp/slide", method: "PUT", params: ["min": slideMin, "max": slideMax]) { _ in }
                self.sendRequest(path: "/hamp/start", method: "PUT") { r in
                    if case .success(let d) = r { AppLog.debug("📲 Handy /hamp/start: \(String(data: d, encoding: .utf8) ?? "")") }
                    else if case .failure(let e) = r { AppLog.error("❌ Handy /hamp/start failed: \(e)") }
                }
            }
        }

        #if !os(tvOS)
        stashCancellable = StashSyncManager.shared.currentIntensityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] intensity in
                guard let self = self else { return }
                if !self.isStashSyncMode || !self.isConnected || !self.isEnabled {
                    if intensity > 0.05 {
                        AppLog.debug("📲 Handy StashSync BLOCKED — isStashSyncMode:\(self.isStashSyncMode) isConnected:\(self.isConnected) isEnabled:\(self.isEnabled) intensity:\(intensity)")
                    }
                    return
                }
                if Date().timeIntervalSince(self.lastAudioCommandTime) < 0.05 { return }
                self.setStashSyncVelocity(intensity)
                self.lastAudioCommandTime = Date()
            }
        #endif
    }

    private var hampIsRunning: Bool = false

    private func setStashSyncVelocity(_ intensity: Float) {
        if deviceType == "Oh." {
            if intensity <= 0.05 {
                sendRequest(path: "/hvp/stop", method: "PUT") { _ in }
            } else {
                let amplitude = Double(max(0.0, min(maxAmplitude, Double(intensity) * maxAmplitude)))
                sendRequest(path: "/hvp/state", method: "PUT", params: [
                    "amplitude": amplitude,
                    "frequency": 75,
                    "position": 50
                ]) { _ in }
            }
        } else {
            // HAMP: velocity scaled by maxVelocity cap
            let rawVelocity = Double(intensity) * (maxVelocity / 100.0)
            if intensity <= 0.05 {
                if hampIsRunning {
                    sendRequest(path: "/hamp/velocity", method: "PUT", params: ["velocity": 0.0]) { _ in }
                    sendRequest(path: "/hamp/stop", method: "PUT") { _ in }
                    hampIsRunning = false
                }
            } else {
                let velocity = max(0.01, min(maxVelocity / 100.0, rawVelocity))
                sendRequest(path: "/hamp/velocity", method: "PUT", params: ["velocity": velocity]) { _ in }
                if !hampIsRunning {
                    self.sendRequest(path: "/hamp/start", method: "PUT") { _ in }
                    self.hampIsRunning = true
                }
            }
        }
    }

    // MARK: - Connection

    func checkConnection(completion: ((Bool) -> Void)? = nil) {
        guard !connectionKey.isEmpty else {
            statusMessage = "No connection key"
            isConnected = false
            completion?(false)
            return
        }

        sendRequest(path: "/connected") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let resultObj = json["result"] as? [String: Any],
                       let connected = resultObj["connected"] as? Bool {
                        self.isConnected = connected
                        self.statusMessage = connected ? "Connected" : "Device Offline"
                        AppLog.debug("📲 Handy v3: connected=\(connected)")
                        completion?(connected)
                    } else {
                        self.isConnected = false
                        self.statusMessage = "Offline"
                        completion?(false)
                    }
                case .failure(let error):
                    self.isConnected = false
                    self.statusMessage = "Offline"
                    AppLog.error("❌ Handy v3: checkConnection failed: \(error.localizedDescription)")
                    completion?(false)
                }
            }
        }
    }

    // MARK: - Funscript / HSSP

    func setupScene(funscriptURL: URL, at seconds: Double? = nil) {
        #if DEBUG
        AppLog.debug("📲 Handy v3: setupScene \(redactedURLString(funscriptURL))")
        #endif
        isStashSyncMode = false

        guard isConnected else {
            checkConnection { [weak self] connected in
                if connected { self?.setupScene(funscriptURL: funscriptURL, at: seconds) }
                else { DispatchQueue.main.async { self?.statusMessage = "Connect Device First" } }
            }
            return
        }

        isSyncing = false
        // Always download with ApiKey header and upload to Handy Cloud.
        // Never send Stash URLs (especially with ?apikey=) to handyfeeling.com.
        statusMessage = "Uploading script..."
        uploadToHandyCloud(sourceUrl: funscriptURL) { [weak self] publicUrl in
            if let publicUrl = publicUrl {
                self?.executeHSSPSetup(url: publicUrl, at: seconds)
            } else {
                DispatchQueue.main.async { self?.statusMessage = "Upload Failed" }
            }
        }
    }

    private func executeHSSPSetup(url: URL, at seconds: Double?) {
        #if DEBUG
        AppLog.debug("📲 Handy v3: HSSP setup → \(redactedURLString(url))")
        #endif
        sendRequest(path: "/mode2", method: "PUT", params: ["mode": 1]) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { self.statusMessage = "Mode Error" }
                return
            case .success:
                self.sendRequest(path: "/hssp/setup", method: "PUT", params: ["url": url.absoluteString, "timeout": 5000]) { [weak self] result in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let data):
                            #if DEBUG
                            if let str = String(data: data, encoding: .utf8) {
                                AppLog.debug("📲 Handy v3: HSSP setup response: \(str)")
                            }
                            #endif
                            self.isSyncing = true
                            self.statusMessage = "Synced & Ready"
                            #if DEBUG
                            AppLog.debug("✅ Handy v3: HSSP setup successful")
                            #endif
                            if let seconds = seconds { self.play(at: seconds) }
                        case .failure(let error):
                            self.statusMessage = "Sync Failed"
                            #if DEBUG
                            AppLog.error("❌ Handy v3: HSSP setup failed: \(error.localizedDescription)")
                            #endif
                        }
                    }
                }
            }
        }
    }

    /// Downloads funscript with ApiKey header (never relies on query secrets for third-party handoff).
    private func authenticatedFunscriptRequest(from url: URL) -> URLRequest {
        authenticatedStashRequest(for: url)
    }

    private func uploadToHandyCloud(sourceUrl: URL, completion: @escaping (URL?) -> Void) {
        #if DEBUG
        AppLog.debug("📲 Handy v3 Bridge: downloading \(redactedURLString(sourceUrl))...")
        #endif
        let request = authenticatedFunscriptRequest(from: sourceUrl)
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                #if DEBUG
                let errMsg = error?.localizedDescription ?? "no data"
                AppLog.error("❌ Handy v3 Bridge: download failed: \(errMsg)")
                #endif
                completion(nil)
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                #if DEBUG
                AppLog.error("❌ Handy v3 Bridge: download HTTP \(http.statusCode)")
                #endif
                completion(nil)
                return
            }
            let boundary = "Boundary-\(UUID().uuidString)"
            var uploadRequest = URLRequest(url: URL(string: "https://www.handyfeeling.com/api/sync/upload")!)
            uploadRequest.httpMethod = "POST"
            uploadRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"syncFile\"; filename=\"script.funscript\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            uploadRequest.httpBody = body
            URLSession.shared.dataTask(with: uploadRequest) { data, response, _ in
                guard let data = data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let urlStr = json["url"] as? String,
                      let remoteUrl = URL(string: urlStr) else {
                    #if DEBUG
                    AppLog.error("❌ Handy v3 Bridge: upload failed")
                    #endif
                    completion(nil)
                    return
                }
                completion(remoteUrl)
            }.resume()
        }.resume()
    }

    // MARK: - Playback Control

    func play(at seconds: Double) {
        isPlayingScript = true
        guard isConnected, isSyncing else { return }

        sendRequest(path: "/hssp/play", method: "PUT", params: [
            "startTime": Int(seconds * 1000),
            "serverTime": Int64(Date().timeIntervalSince1970 * 1000)
        ]) { result in
            switch result {
            case .success: AppLog.debug("✅ Handy v3: play acknowledged")
            case .failure(let e): AppLog.error("❌ Handy v3: play failed: \(e.localizedDescription)")
            }
        }
    }

    func pause() {
        isPlayingScript = false

        if isStashSyncMode {
            setStashSyncVelocity(0)
        }

        guard isConnected && isSyncing else { return }
        sendRequest(path: "/hssp/stop", method: "PUT") { result in
            if case .failure(let e) = result { AppLog.error("❌ Handy v3: pause failed: \(e.localizedDescription)") }
            else { AppLog.debug("✅ Handy v3: pause acknowledged") }
        }
    }

    func stop() {
        pause()
        isSyncing = false
    }

    // MARK: - Generic v3 Request

    private func sendRequest(path: String, method: String = "GET", params: [String: Any] = [:], completion: @escaping (Result<Data, Error>) -> Void = { _ in }) {
        guard !connectionKey.isEmpty else { return }

        if path == "/hvp/state" || path == "/hamp/velocity" {
            currentTask?.cancel()
        }

        var urlString = baseURL + path
        if method == "GET", !params.isEmpty, var comps = URLComponents(string: urlString) {
            comps.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            urlString = comps.url?.absoluteString ?? urlString
        }

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 7.0
        request.addValue(connectionKey, forHTTPHeaderField: "X-Connection-Key")
        request.addValue(handyApiKey, forHTTPHeaderField: "X-Api-Key")

        if method != "GET", !params.isEmpty {
            request.httpBody = try? JSONSerialization.data(withJSONObject: params)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                AppLog.error("❌ Handy v3: \(method) \(path) error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
                if path != "/hvp/state" && path != "/hamp/velocity" {
                    AppLog.error("❌ Handy v3: \(method) \(path) [\(http.statusCode)] \(msg)")
                }
                completion(.failure(NSError(domain: "HandyManager", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            completion(.success(data ?? Data()))
        }

        if path == "/hvp/state" || path == "/hamp/velocity" { currentTask = task }
        task.resume()
    }
}

class ButtplugManager: ObservableObject {
    static let shared = ButtplugManager()
    
    @AppStorage("intiface_server_address") var serverAddress: String = "ws://127.0.0.1:12345"
    @AppStorage("intiface_enabled") var isEnabled: Bool = false {
        didSet {
            if !isEnabled && isConnected {
                disconnect()
            }
        }
    }
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var statusMessage: String = "Not Connected"
    @Published var devices: [ButtplugDevice] = []
    
    private var webSocket: URLSessionWebSocketTask?
    private var messageId: Int = 1
    
    @Published var isStashSyncMode: Bool = false {
        didSet {
            if isStashSyncMode {
                isSyncing = false
                setupStashSync()
            } else {
                stashCancellable = nil
                // Only stop if we are not switching to Funscript (isSyncing) mode
                if !isSyncing {
                    stopAllDevices()
                }
            }
        }
    }
    private var stashCancellable: AnyCancellable?
    private var lastAudioCommandTime: Date = .distantPast
    
    // Funscript Sync
    private var currentScript: Funscript?
    private var syncTimer: CADisplayLink?
    private var lastPlaybackTime: Double = 0
    private var lastCommandSentAt: Double = 0
    @Published var isPlayingScript: Bool = false
    @Published var isSyncing: Bool = false
    
    private init() {
        // Optional: Auto-connect if desirable
    }
    
    
    private func setupStashSync() {
        AppLog.debug("📱 Buttplug: setupStashSync() initiated")
        #if !os(tvOS)
        stashCancellable = StashSyncManager.shared.currentIntensityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] intensity in
                guard let self = self, self.isStashSyncMode, self.isConnected, self.isEnabled, !self.devices.isEmpty else { return }
                
                if Date().timeIntervalSince(self.lastAudioCommandTime) < 0.05 { return }
                
                if intensity > 0.05 {
                    self.sendMovement(position: Double(intensity * 100), duration: 50)
                    self.lastAudioCommandTime = Date()
                } else if Date().timeIntervalSince(self.lastAudioCommandTime) > 0.3 {
                    self.stopAllDevices()
                    self.lastAudioCommandTime = Date()
                }
            }
        #endif
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
                AppLog.error("❌ Buttplug: Send failed: \(error)")
                // Do not disconnect immediately on send failure to avoid UI flickering during sync
            }
        }
    }
    
    // MARK: - Funscript Sync Logic
    
    func setupScene(funscriptURL: URL, at seconds: Double? = nil) {
        isStashSyncMode = false // EXCLUSIVITY
        
        if !isConnected {
            connect()
            // We'll return and wait for connection, user can tap again or we could improve this later
            return
        }
        
        statusMessage = "Loading Script..."
        URLSession.shared.dataTask(with: authenticatedStashRequest(for: funscriptURL)) { [weak self] data, response, error in
            guard let self = self, let data = data else { return }
            
            do {
                let script = try JSONDecoder().decode(Funscript.self, from: data)
                DispatchQueue.main.async {
                    self.currentScript = script
                    self.isSyncing = true
                    self.isStashSyncMode = false // EXCLUSIVITY
                    self.statusMessage = "Script Loaded"
                    AppLog.debug("✅ Buttplug: Loaded script with \(script.actions?.count ?? 0) actions")
                    if let seconds = seconds {
                        self.play(at: seconds)
                    }
                }
            } catch {
                AppLog.error("❌ Buttplug: Failed to parse Funscript: \(error)")
                DispatchQueue.main.async {
                    self.statusMessage = "Script Error"
                }
            }
        }.resume()
    }
    
    func play(at seconds: Double) {
        isPlayingScript = true
        guard isConnected, (isSyncing || isStashSyncMode) else {
            AppLog.debug("📱 Buttplug: Play ignored - Connected: \(isConnected), Mode: \(isSyncing ? "Sync" : "Stash")")
            return
        }
        
        if isSyncing, currentScript != nil {
            lastPlaybackTime = seconds
            lastCommandSentAt = 0
            
            syncTimer?.invalidate()
            syncTimer = CADisplayLink(target: self, selector: #selector(updateSync))
            syncTimer?.add(to: .main, forMode: .common)
        }
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
    
    func stop() {
        pause()
        isSyncing = false
        currentScript = nil
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
                AppLog.debug("🎬 Buttplug Sync: Target \(nextAction.pos)% in \(duration)ms (Index: \(nextIndex))")
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
            // Filter LoveSpouse devices from Buttplug if native is handling them or they are deactivated
            if device.name.lowercased().contains("lovespouse") {
                if isStashSyncMode {
                    // In StashSync mode, check if LoveSpouse card button is ON
                    if !LoveSpouseManager.shared.isStashSyncMode { continue }
                } else {
                    // In Funscript mode, check if LoveSpouse global toggle is ON
                    if !LoveSpouseManager.shared.isEnabled { continue }
                }
            }
            
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
                AppLog.error("❌ Buttplug: Receive failed: \(error)")
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
                            AppLog.debug("📱 Buttplug: Device Added: \(name) (Scalar: \(supportsScalar), Linear: \(supportsLinear))")
                        }
                    }
                }
            } else if let deviceRemoved = dict["DeviceRemoved"] as? [String: Any] {
                DispatchQueue.main.async {
                    if let id = deviceRemoved["DeviceIndex"] as? Int {
                        self.devices.removeAll(where: { $0.id == id })
                        AppLog.debug("📱 Buttplug: Device Removed (ID: \(id))")
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
                    AppLog.debug("📱 Buttplug: Found \(self.devices.count) devices")
                }
            } else if let _ = dict["Ok"] as? [String: Any] {
                // Acknowledgement
            } else if let error = dict["Error"] as? [String: Any] {
                AppLog.error("⚠️ Buttplug Error: \(error["ErrorMessage"] ?? "Unknown")")
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

class LoveSpouseManager: NSObject, ObservableObject {
    static let shared = LoveSpouseManager()

    // MARK: - Published State
    @Published var isConnected: Bool = false
    @AppStorage("lovespouse_enabled") var isEnabled: Bool = false {
        didSet {
            if !isEnabled {
                stop()
            }
        }
    }
    /// Currently active program (0 = stopped, 1–3 = speeds, 4–9 = patterns)
    @Published var activeProgram: Int = 0 {
        didSet {
            // Ensure we never have an active program if disabled
            if !isEnabled && activeProgram != 0 {
                activeProgram = 0
            }
        }
    }
    @Published var isSyncing: Bool = false {
        didSet {
            if isSyncing {
                isConnected = true
            }
        }
    }
    @Published var statusMessage: String = "Not Connected"
    @Published var isAdvertising: Bool = false
    
    @Published var isStashSyncMode: Bool = false {
        didSet {
            if isStashSyncMode {
                isSyncing = false
                setupStashSync()
            } else {
                stashCancellable = nil
                // Only stop if we are not switching to Funscript (isSyncing) mode
                if !isSyncing {
                    selectProgram(0)
                }
            }
        }
    }
    private var stashCancellable: AnyCancellable?
    private var lastAudioCommandTime: Date = .distantPast

    // MARK: - Funscript Sync
    private var currentScript: Funscript?
    private var syncTimer: CADisplayLink?
    private var lastPlaybackTime: Double = 0
    private var lastCommandSentAt: Double = 0
    @Published var isPlayingScript: Bool = false

    // MARK: - Private
    private var peripheralManager: CBPeripheralManager!
    private var burstTimer: Timer?
    private let bleQueue = DispatchQueue(label: "com.stashy.lovespouse", qos: .userInitiated)
    private var isAdvertisingActive = false
    
    
    private func setupStashSync() {
        AppLog.debug("📱 LoveSpouse: setupStashSync() initiated")
        #if !os(tvOS)
        stashCancellable = StashSyncManager.shared.currentIntensityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] intensity in
                guard let self = self, self.isStashSyncMode, self.isConnected, self.isEnabled else { return }

                if Date().timeIntervalSince(self.lastAudioCommandTime) < 0.4 { return }
                
                if intensity > 0.05 {
                    self.setLevel(Double(intensity * 100))
                    self.lastAudioCommandTime = Date()
                } else if Date().timeIntervalSince(self.lastAudioCommandTime) > 0.8 {
                    self.selectProgram(0)
                    self.lastAudioCommandTime = Date()
                }
            }
        #endif
    }
    
    // Extracted UUID pairs [UUID5, UUID6] mapped to 0-9
    // Order based on binary sequence 0x6E down to 0x66 observed in PacketLogger
    private let commandUUIDs: [Int: (String, String)] = [
        0: ("9C6E", "0B3D"), // Stop
        1: ("156F", "0B2C"), // Speed 1
        2: ("8E6C", "0B1E"), // Speed 2
        3: ("076D", "0B0F"), // Speed 3
        4: ("B86A", "0B7B"), // Pattern 1 (Button 4)
        5: ("316B", "0B6A"), // Pattern 2 (Button 5)
        6: ("AA68", "0B58"), // Pattern 3 (Button 6)
        7: ("2369", "0B49"), // Pattern 4 (Button 7)
        8: ("D466", "0BB1"), // Pattern 5 (Button 8)
        9: ("5D67", "0BA0")  // Pattern 6 (Button 9)
    ]

    private override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Funscript Integration

    func setupScene(funscriptURL: URL, at seconds: Double? = nil) {
        isStashSyncMode = false // EXCLUSIVITY
        guard isEnabled else { return }
        statusMessage = "Loading Script..."
        URLSession.shared.dataTask(with: authenticatedStashRequest(for: funscriptURL)) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                AppLog.error("❌ LoveSpouse: Network error fetching funscript: \(error)")
                DispatchQueue.main.async { self.statusMessage = "Network Error" }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                AppLog.error("❌ LoveSpouse: Funscript fetch returned HTTP \(http.statusCode) for \(redactedURLString(funscriptURL))")
                DispatchQueue.main.async { self.statusMessage = "Script Error (\(http.statusCode))" }
                return
            }

            guard let data = data, !data.isEmpty else {
                AppLog.error("❌ LoveSpouse: Funscript data empty for \(redactedURLString(funscriptURL))")
                DispatchQueue.main.async { self.statusMessage = "Script Empty" }
                return
            }

            do {
                let script = try JSONDecoder().decode(Funscript.self, from: data)
                DispatchQueue.main.async {
                    self.currentScript = script
                    self.isSyncing = true
                    self.statusMessage = "Script Loaded"
                    AppLog.debug("✅ LoveSpouse: Loaded script with \(script.actions?.count ?? 0) actions")
                    if let seconds = seconds {
                        self.play(at: seconds)
                    }
                }
            } catch {
                AppLog.error("❌ LoveSpouse: Failed to parse Funscript: \(error)")
                if let raw = String(data: data, encoding: .utf8)?.prefix(200) {
                    AppLog.error("❌ LoveSpouse: Raw response: \(raw)")
                }
                DispatchQueue.main.async { self.statusMessage = "Script Error" }
            }
        }.resume()
    }

    func play(at seconds: Double) {
        isPlayingScript = true
        guard isConnected, (isSyncing || isStashSyncMode) else {
            AppLog.debug("📱 LoveSpouse: Play ignored - Connected: \(isConnected), Mode: \(isSyncing ? "Sync" : "Stash")")
            return
        }
        
        if isSyncing, currentScript != nil {
            lastPlaybackTime = seconds
            lastCommandSentAt = 0
            
            syncTimer?.invalidate()
            syncTimer = CADisplayLink(target: self, selector: #selector(updateSync))
            syncTimer?.add(to: .main, forMode: .common)
        }
    }
    
    func pause() {
        isPlayingScript = false
        syncTimer?.invalidate()
        syncTimer = nil
        selectProgram(0) // RESTORED: Ensure device stops physically when video pauses
    }
    
    func stop() {
        isPlayingScript = false
        syncTimer?.invalidate()
        syncTimer = nil
        isSyncing = false
        currentScript = nil
        stopAll()
    }

    @objc private func updateSync() {
        guard isEnabled, isPlayingScript, let script = currentScript, let actions = script.actions, !actions.isEmpty else { return }
        
        let frameDuration = 1.0 / 60.0 // Approximated
        lastPlaybackTime += frameDuration
        
        let currentMs = Int(lastPlaybackTime * 1000)
        
        // Find the index of the next action after currentMs
        guard let nextIndex = actions.firstIndex(where: { $0.at > currentMs }) else {
            // End of script reached
            pause()
            return
        }
        
        // Only send a new command if we haven't sent one for this segment yet
        let nextAction = actions[nextIndex]
        if Double(nextAction.at) != lastCommandSentAt {
            // Map 0-100 position to speed bucket
            setLevel(Double(nextAction.pos))
            lastCommandSentAt = Double(nextAction.at)
        }
    }

    // MARK: - Public API

    /// Direct program selection. Sends a 500ms burst.
    func selectProgram(_ index: Int, force: Bool = false) {
        guard isEnabled else { return }
        if !force && activeProgram == index && isAdvertisingActive {
            return
        }

        guard let uuids = commandUUIDs[index] else { return }
        
        DispatchQueue.main.async {
            self.activeProgram = index
            self.isConnected = true
        }
        
        NSLog("🔵 LoveSpouseManager: Selecting program \(index)")
        startBurst(u5: uuids.0, u6: uuids.1)
    }

    /// Helper for legacy level control (0-100)
    func setLevel(_ level: Double) {
        guard isEnabled else { return }
        let clamped = max(0, min(100, level))
        let targetProgram: Int
        
        if clamped == 0 {
            targetProgram = 0
        } else if clamped < 34 {
            targetProgram = 1
        } else if clamped < 67 {
            targetProgram = 2
        } else {
            targetProgram = 3
        }
        
        // Only send if the program bucket changed
        if targetProgram != activeProgram {
            selectProgram(targetProgram)
        }
    }

    func stopAll() {
        NSLog("🔵 LoveSpouseManager: Ultra-Aggressive Stop Sequence Start")
        isPlayingScript = false
        syncTimer?.invalidate()
        syncTimer = nil
        
        selectProgram(0, force: true) 
        
        // Repeated bursts over a longer period to ensure delivery
        // The toy might be busy or in a state where it missed the first pulse
        let delays = [0.2, 0.5, 1.0, 2.0, 4.0, 6.0, 8.0]
        for delay in delays {
            bleQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.isPlayingScript else { return }
                self.selectProgram(0, force: true)
            }
        }
    }

    func checkConnection(completion: @escaping (Bool) -> Void) {
        completion(peripheralManager.state == .poweredOn)
    }

    // MARK: - Private Burst Logic

    private var pendingBurst: DispatchWorkItem?

    private func startBurst(u5: String, u6: String) {
        bleQueue.async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            self.pendingBurst?.cancel()

            DispatchQueue.main.async {
                self.burstTimer?.invalidate()
                self.burstTimer = nil
            }

            if self.isAdvertisingActive {
                self.peripheralManager.stopAdvertising()
                self.isAdvertisingActive = false
                DispatchQueue.main.async { self.isAdvertising = false }
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, !(self.pendingBurst?.isCancelled ?? true) else { return }

                let services: [CBUUID] = [
                    CBUUID(string: "08F9"),
                    CBUUID(string: "2349"),
                    CBUUID(string: "CBAE"),
                    CBUUID(string: "D1C1"),
                    CBUUID(string: u5),
                    CBUUID(string: u6),
                    // Constant Padding
                    CBUUID(string: "0D0C"), CBUUID(string: "0F0E"), CBUUID(string: "1110"),
                    CBUUID(string: "1312"), CBUUID(string: "1514"), CBUUID(string: "1716"),
                    CBUUID(string: "1918")
                ]

                self.peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: services])
                self.isAdvertisingActive = true
                DispatchQueue.main.async { self.isAdvertising = true }

                if self.activeProgram == 0 {
                    // For "Stop", we advertise for a much longer period (10s) to be safe
                    DispatchQueue.main.async {
                        self.burstTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                            self?.bleQueue.async {
                                guard let self = self else { return }
                                if self.isAdvertisingActive && self.activeProgram == 0 {
                                    self.peripheralManager.stopAdvertising()
                                    self.isAdvertisingActive = false
                                    DispatchQueue.main.async { self.isAdvertising = false }
                                    NSLog("🔵 LoveSpouseManager: Ultra stop burst finished, radio off")
                                }
                            }
                        }
                    }
                } else {
                    NSLog("🔵 LoveSpouseManager: Continuous advertising on (Keep-Alive)")
                }
            }

            self.pendingBurst = workItem
            self.bleQueue.asyncAfter(deadline: .now() + 0.05, execute: workItem)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension LoveSpouseManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let isPoweredOn = (peripheral.state == .poweredOn)
        NSLog("🔵 LoveSpouseManager: BLE State – \(peripheral.state.rawValue)")
        
        DispatchQueue.main.async {
            self.isConnected = isPoweredOn
            self.statusMessage = isPoweredOn ? "Ready" : "Radio Off"
            
            if isPoweredOn && self.isEnabled {
                self.selectProgram(self.activeProgram)
            }
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            NSLog("🔵 LoveSpouseManager: ADV Failed – \(error.localizedDescription)")
        }
    }
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
