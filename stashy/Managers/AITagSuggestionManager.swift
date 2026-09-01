//
//  AITagSuggestionManager.swift
//  stashy
//
//  Tag suggestions ("AI Tags", stashy+) from the library's own statistics.
//
//  The whole library is counted once into a local statistics model:
//
//  * how often each performer is tagged with each tag
//  * the same for galleries, for studios, and for the library as a whole
//  * which tags occur *together* on the same item
//
//  Suggestions are then plain lookups — no network round trip while browsing, no
//  image analysis, nothing that leaves the device. Co-occurrence is what makes a
//  suggestion specific to the item rather than to its performer: statistics about a
//  performer answer the same for every clip they are in, while the tags an item
//  already carries say something about this item alone.
//

#if !os(tvOS)

import Foundation
import Combine
import SwiftUI

// MARK: - Model

struct AITagSuggestion: Identifiable, Equatable {
    enum Source: String, Codable {
        case performer   // how often this performer carries the tag
        case gallery     // how often this gallery carries the tag
        case studio      // how often this studio carries the tag
        case library     // how often the whole library carries the tag
        case related     // co-occurrence with the tags the item already has
    }

    let tag: Tag
    let confidence: Double
    let source: Source

    var id: String { tag.id }
}

/// Everything counted from the library, persisted per server.
struct AITagStatsModel: Codable {
    var version: Int
    var builtAt: Date
    var itemCount: Int
    var tags: [Tag]
    /// performer id → tag id → number of that performer's items carrying the tag
    var performerCounts: [String: [String: Int]]
    var performerTotals: [String: Int]
    var galleryCounts: [String: [String: Int]]
    var galleryTotals: [String: Int]
    var studioCounts: [String: [String: Int]]
    var studioTotals: [String: Int]
    /// tag id → co-occurring tag id → number of items carrying both
    var pairCounts: [String: [String: Int]]
    var tagTotals: [String: Int]
}

// MARK: - Manager

@MainActor
final class AITagSuggestionManager: ObservableObject {

    static let shared = AITagSuggestionManager()

    enum ModelState: Equatable {
        case idle
        case loading
        case building(processed: Int, total: Int)
        case ready(items: Int)
        case failed(String)
    }

    // MARK: Settings (kill-switch first — default OFF)

    /// Master kill switch. While false nothing here touches Reels or the fullscreen viewer.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled { cancelWork() }
        }
    }

    /// A tag has to appear on at least this share of the related items before it is
    /// suggested. Below 50% a suggestion is wrong more often than right — that is
    /// exactly where act tags live: the performer does them regularly, just not here.
    @Published var minShare: Double {
        didSet { UserDefaults.standard.set(minShare, forKey: Keys.minShare) }
    }

    /// How many suggestions the chip row shows at most.
    @Published var maxSuggestions: Int {
        didSet { UserDefaults.standard.set(maxSuggestions, forKey: Keys.maxSuggestions) }
    }

    /// Apply high-confidence suggestions without a tap. Writes to the server, so it is
    /// off unless the user turns it on.
    @Published var autoAccept: Bool {
        didSet { UserDefaults.standard.set(autoAccept, forKey: Keys.autoAccept) }
    }

    @Published var autoAcceptThreshold: Double {
        didSet { UserDefaults.standard.set(autoAcceptThreshold, forKey: Keys.autoAcceptThreshold) }
    }

    // MARK: Published state

    @Published private(set) var state: ModelState = .idle
    @Published private(set) var lastBuiltAt: Date?
    @Published private(set) var itemCount: Int = 0

    /// Available and allowed to run right now.
    var isActive: Bool { isEnabled && StashyPlusManager.isUnlockedNow }

    var hasModel: Bool {
        if case .ready = state { return true }
        return false
    }

    var buildProgress: Double {
        if case .building(let processed, let total) = state, total > 0 {
            return min(1, Double(processed) / Double(total))
        }
        return 0
    }

    // MARK: Private state

    private var model: AITagStatsModel?
    private var tagsById: [String: Tag] = [:]
    private var buildTask: Task<Void, Never>?
    private var didLoadFromDisk = false
    private var serverObserver: NSObjectProtocol?

    /// How often the user waved a tag away. Two strikes and it stops being offered —
    /// the alternative is being wrong about the same tag on every single clip.
    private var dismissals: [String: Int] = [:]

    private enum Keys {
        static let enabled = "ai_tags_enabled"
        static let minShare = "ai_tags_stats_min_share"
        static let maxSuggestions = "ai_tags_max_suggestions"
        static let autoAccept = "ai_tags_auto_accept"
        static let autoAcceptThreshold = "ai_tags_auto_accept_threshold"
        static let dismissed = "ai_tags_dismissed"
    }

    private static let modelVersion = 2
    private static let dismissStrikes = 2
    /// Laplace-style damping: one of one item is not a certainty.
    private static let smoothing = 1.0
    /// Co-occurrence is only kept for the strongest partners of a tag — the full matrix
    /// is mostly noise and would bloat the file for nothing.
    private static let partnersPerTag = 40
    private static let pageSize = 250

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.enabled)
        minShare = defaults.object(forKey: Keys.minShare) as? Double ?? 0.5
        maxSuggestions = defaults.object(forKey: Keys.maxSuggestions) as? Int ?? 8
        autoAccept = defaults.bool(forKey: Keys.autoAccept)
        autoAcceptThreshold = defaults.object(forKey: Keys.autoAcceptThreshold) as? Double ?? 0.8
        dismissals = defaults.dictionary(forKey: Keys.dismissed) as? [String: Int] ?? [:]

        serverObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleServerChange() }
        }
    }

    deinit {
        if let serverObserver {
            NotificationCenter.default.removeObserver(serverObserver)
        }
    }

    // MARK: - Lifecycle

    /// Each server keeps its own model on the device — tag IDs are server-specific, so
    /// switching servers loads that server's model instead of deleting anything.
    private func handleServerChange() {
        cancelWork()
        model = nil
        tagsById = [:]
        suggestionCache = [:]
        didLoadFromDisk = false
        lastBuiltAt = nil
        itemCount = 0
        state = .idle
        Task { await loadIfNeeded() }
    }

    func cancelWork() {
        buildTask?.cancel()
        buildTask = nil
        if case .building = state { state = restingState() }
    }

    private func restingState() -> ModelState {
        guard let model else { return .idle }
        return .ready(items: model.itemCount)
    }

    func loadIfNeeded() async {
        guard !didLoadFromDisk, isActive else { return }
        guard let url = Self.modelURL() else { return }
        didLoadFromDisk = true
        state = .loading

        let loaded: AITagStatsModel? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AITagStatsModel.self, from: data)
        }.value

        guard let loaded, loaded.version == Self.modelVersion else {
            if loaded != nil { try? FileManager.default.removeItem(at: url) }
            state = .idle
            return
        }
        apply(loaded)
    }

    private func apply(_ loaded: AITagStatsModel) {
        model = loaded
        tagsById = Dictionary(loaded.tags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        lastBuiltAt = loaded.builtAt
        itemCount = loaded.itemCount
        suggestionCache = [:]
        state = .ready(items: loaded.itemCount)
    }

    // MARK: - Building

    func rebuild() {
        guard isActive, buildTask == nil else { return }
        buildTask = Task { [weak self] in
            await self?.performBuild()
            await MainActor.run { self?.buildTask = nil }
        }
    }

    func deleteModel() {
        cancelWork()
        model = nil
        tagsById = [:]
        suggestionCache = [:]
        lastBuiltAt = nil
        itemCount = 0
        state = .idle
        if let url = Self.modelURL() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func performBuild() async {
        state = .building(processed: 0, total: 0)

        let tags: [Tag]
        do {
            tags = try await fetchAllTags()
        } catch {
            AppLog.error("AITags: tag list failed — \(error.localizedDescription)")
            state = .failed("Could not read the tag list")
            return
        }

        var performerCounts: [String: [String: Int]] = [:]
        var performerTotals: [String: Int] = [:]
        var galleryCounts: [String: [String: Int]] = [:]
        var galleryTotals: [String: Int] = [:]
        var studioCounts: [String: [String: Int]] = [:]
        var studioTotals: [String: Int] = [:]
        var pairCounts: [String: [String: Int]] = [:]
        var tagTotals: [String: Int] = [:]
        var processed = 0
        var expected = 0

        func absorb(_ item: StatsItem) {
            let tagIds = (item.tags ?? []).map(\.id)
            guard !tagIds.isEmpty else { return }

            for tagId in tagIds {
                tagTotals[tagId, default: 0] += 1
            }
            for tagId in tagIds {
                for other in tagIds where other != tagId {
                    pairCounts[tagId, default: [:]][other, default: 0] += 1
                }
            }
            for performer in item.performers ?? [] {
                performerTotals[performer.id, default: 0] += 1
                for tagId in tagIds {
                    performerCounts[performer.id, default: [:]][tagId, default: 0] += 1
                }
            }
            for gallery in item.galleries ?? [] {
                galleryTotals[gallery.id, default: 0] += 1
                for tagId in tagIds {
                    galleryCounts[gallery.id, default: [:]][tagId, default: 0] += 1
                }
            }
            if let studioId = item.studio?.id {
                studioTotals[studioId, default: 0] += 1
                for tagId in tagIds {
                    studioCounts[studioId, default: [:]][tagId, default: 0] += 1
                }
            }
        }

        // Scenes first: in most libraries they carry the richer vocabulary.
        for source in [StatsSource.scenes, StatsSource.images] {
            var page = 1
            while true {
                if Task.isCancelled { break }
                do {
                    let batch = try await fetchStatsPage(source: source, page: page)
                    if page == 1 { expected += batch.count }
                    guard !batch.items.isEmpty else { break }
                    batch.items.forEach(absorb)
                    processed += batch.items.count
                    state = .building(processed: processed, total: max(expected, processed))
                    if batch.items.count < Self.pageSize { break }
                    page += 1
                } catch {
                    AppLog.error("AITags: \(source.rawValue) page \(page) failed — \(error.localizedDescription)")
                    break
                }
            }
        }

        guard !Task.isCancelled else {
            state = restingState()
            return
        }
        guard processed > 0 else {
            state = .failed("No tagged scenes or images found")
            return
        }

        // Trim the co-occurrence matrix: only the strongest partners survive.
        for (tagId, partners) in pairCounts {
            let kept = partners
                .filter { $0.value >= 2 }
                .sorted { $0.value > $1.value }
                .prefix(Self.partnersPerTag)
            pairCounts[tagId] = kept.isEmpty ? nil : Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }

        let built = AITagStatsModel(
            version: Self.modelVersion,
            builtAt: Date(),
            itemCount: processed,
            tags: tags,
            performerCounts: performerCounts,
            performerTotals: performerTotals,
            galleryCounts: galleryCounts,
            galleryTotals: galleryTotals,
            studioCounts: studioCounts,
            studioTotals: studioTotals,
            pairCounts: pairCounts,
            tagTotals: tagTotals
        )
        apply(built)
        persist(built)
        AppLog.debug("AITags: statistics model built from \(processed) items")
    }

    private func persist(_ built: AITagStatsModel) {
        guard let url = Self.modelURL() else { return }
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(built)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLog.error("AITags: could not persist model — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionCache: [String: [AITagSuggestion]] = [:]

    /// Cached suggestions for an image. Tags it meanwhile carries are dropped — a tag
    /// is never suggested twice.
    func cachedSuggestions(for image: StashImage) -> [AITagSuggestion]? {
        guard let cached = suggestionCache[image.id] else { return nil }
        let existing = Set((image.tags ?? []).map(\.id))
        return cached.filter { !existing.contains($0.tag.id) }
    }

    /// Ranked suggestions for one item, excluding tags it already has. Pure lookups in
    /// the local model — no request while browsing.
    @discardableResult
    func suggestions(for image: StashImage, forceRefresh: Bool = false) async -> [AITagSuggestion] {
        guard isActive else { return [] }
        if !forceRefresh, let cached = cachedSuggestions(for: image) { return cached }
        await loadIfNeeded()
        guard let model else { return [] }

        let existing = (image.tags ?? []).map(\.id)
        let existingSet = Set(existing)
        var scores: [String: (score: Double, source: AITagSuggestion.Source)] = [:]

        func offer(_ tagId: String, _ score: Double, _ source: AITagSuggestion.Source) {
            guard !existingSet.contains(tagId) else { return }
            guard (dismissals[tagId] ?? 0) < Self.dismissStrikes else { return }
            guard score >= minShare else { return }
            guard let current = scores[tagId] else {
                scores[tagId] = (score, source)
                return
            }
            scores[tagId] = (
                Self.combine(current.score, score),
                score > current.score ? source : current.source
            )
        }

        // 1. What this performer is usually tagged with.
        for performer in image.performers ?? [] {
            guard let counts = model.performerCounts[performer.id],
                  let total = model.performerTotals[performer.id], total > 0 else { continue }
            let denominator = Double(total) + Self.smoothing
            for (tagId, count) in counts {
                offer(tagId, Double(count) / denominator, .performer)
            }
        }

        // 2. The gallery an image belongs to — usually one shoot, so its tags carry over
        //    to its siblings more reliably than anything else here.
        for gallery in image.galleries ?? [] {
            guard let counts = model.galleryCounts[gallery.id],
                  let total = model.galleryTotals[gallery.id], total > 0 else { continue }
            let denominator = Double(total) + Self.smoothing
            for (tagId, count) in counts {
                offer(tagId, 0.95 * Double(count) / denominator, .gallery)
            }
        }

        // 3. The same for the studio — real, but less specific, hence discounted.
        if let studioId = image.studio?.id,
           let counts = model.studioCounts[studioId],
           let total = model.studioTotals[studioId], total > 0 {
            let denominator = Double(total) + Self.smoothing
            for (tagId, count) in counts {
                offer(tagId, 0.8 * Double(count) / denominator, .studio)
            }
        }

        // 4. The library as a whole. Only tags you put on nearly everything survive the
        //    minimum share here, which is exactly what this scope is good for.
        if model.itemCount > 0 {
            let denominator = Double(model.itemCount) + Self.smoothing
            for (tagId, count) in model.tagTotals {
                offer(tagId, 0.6 * Double(count) / denominator, .library)
            }
        }

        // 5. Tags that travel with the ones this item already has. The only signal here
        //    that is about the item itself rather than about who is in it.
        for tagId in existing {
            guard let partners = model.pairCounts[tagId],
                  let total = model.tagTotals[tagId], total > 0 else { continue }
            let denominator = Double(total) + Self.smoothing
            for (partnerId, count) in partners {
                offer(partnerId, Double(count) / denominator, .related)
            }
        }

        let result = scores
            .compactMap { (tagId, value) -> AITagSuggestion? in
                guard let tag = tagsById[tagId] else { return nil }
                return AITagSuggestion(tag: tag, confidence: min(1, value.score), source: value.source)
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(max(1, maxSuggestions))

        let suggestions = Array(result)
        suggestionCache[image.id] = suggestions
        return suggestions
    }

    /// How two signals for the same tag fold into one score: the stronger carries,
    /// agreement adds a modest bonus, the result never exceeds certainty.
    private static func combine(_ lhs: Double, _ rhs: Double) -> Double {
        min(1, max(lhs, rhs) + 0.15 * min(lhs, rhs))
    }

    // MARK: - Dismissing

    /// Records that the user rejected this tag. Accepting it anywhere clears the record,
    /// so a single misfire never buries a tag for good.
    func dismiss(_ suggestion: AITagSuggestion, on image: StashImage) {
        dismissals[suggestion.tag.id, default: 0] += 1
        UserDefaults.standard.set(dismissals, forKey: Keys.dismissed)
        if var cached = suggestionCache[image.id] {
            cached.removeAll { $0.tag.id == suggestion.tag.id }
            suggestionCache[image.id] = cached
        }
    }

    var dismissedTagCount: Int {
        dismissals.filter { $0.value >= Self.dismissStrikes }.count
    }

    func resetDismissals() {
        dismissals = [:]
        UserDefaults.standard.removeObject(forKey: Keys.dismissed)
        suggestionCache = [:]
    }

    // MARK: - Accepting

    /// Adds the tag to the image on the server. Returns the image's new tag list.
    func accept(_ suggestion: AITagSuggestion, on image: StashImage) async -> [Tag]? {
        await accept([suggestion], on: image)
    }

    /// Adds several tags in one mutation — auto-accept would otherwise fire a request per tag.
    func accept(_ accepted: [AITagSuggestion], on image: StashImage) async -> [Tag]? {
        let existing = image.tags ?? []
        let existingIds = Set(existing.map(\.id))
        let additions = accepted.map(\.tag).filter { !existingIds.contains($0.id) }
        guard !additions.isEmpty else { return existing }
        let newTags = existing + additions

        let mutation = GraphQLQueries.imageUpdateTagsMutation
        let variables: [String: Any] = ["input": ["id": image.id, "tag_ids": newTags.map(\.id)]]

        do {
            let response: ImageUpdateResponse = try await GraphQLClient.shared.execute(
                query: mutation,
                variables: variables
            )
            guard response.data?.imageUpdate?.id != nil else { return nil }
        } catch {
            AppLog.error("AITags: imageUpdate failed — \(error.localizedDescription)")
            return nil
        }

        let acceptedIds = Set(additions.map(\.id))
        for tagId in acceptedIds where dismissals[tagId] != nil {
            dismissals[tagId] = nil
        }
        UserDefaults.standard.set(dismissals, forKey: Keys.dismissed)

        if var cached = suggestionCache[image.id] {
            cached.removeAll { acceptedIds.contains($0.tag.id) }
            suggestionCache[image.id] = cached
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("ImageTagsUpdated"),
            object: nil,
            userInfo: ["imageId": image.id, "tags": newTags]
        )
        return newTags
    }

    // MARK: - GraphQL

    private enum StatsSource: String {
        case scenes
        case images
    }

    private struct StatsItem: Decodable {
        struct Reference: Decodable { let id: String }
        let id: String
        let tags: [Tag]?
        let performers: [Reference]?
        let studio: Reference?
        let galleries: [Reference]?
    }

    private struct StatsBatch {
        let items: [StatsItem]
        let count: Int
    }

    private struct StatsScenesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindScenes: Decodable {
                let count: Int
                let scenes: [StatsItem]
            }
            let findScenes: FindScenes
        }
        let data: DataBlock?
    }

    private struct StatsImagesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindImages: Decodable {
                let count: Int
                let images: [StatsItem]
            }
            let findImages: FindImages
        }
        let data: DataBlock?
    }

    private struct TagsResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindTags: Decodable { let tags: [Tag] }
            let findTags: FindTags
        }
        let data: DataBlock?
    }

    private struct ImageUpdateResponse: Decodable {
        struct DataBlock: Decodable {
            struct Updated: Decodable { let id: String }
            let imageUpdate: Updated?
        }
        let data: DataBlock?
    }

    private func fetchAllTags() async throws -> [Tag] {
        let query = GraphQLQueries.queryWithFragments("findTags")
        let variables: [String: Any] = [
            "filter": ["per_page": -1, "sort": "name", "direction": "ASC"]
        ]
        let response: TagsResponse = try await GraphQLClient.shared.execute(query: query, variables: variables)
        return response.data?.findTags.tags ?? []
    }

    private func fetchStatsPage(source: StatsSource, page: Int) async throws -> StatsBatch {
        let filter: [String: Any] = [
            "page": page,
            "per_page": Self.pageSize,
            "sort": "id",
            "direction": "ASC"
        ]
        let scope: [String: Any] = ["tag_count": ["value": 0, "modifier": "GREATER_THAN"]]

        switch source {
        case .scenes:
            let response: StatsScenesResponse = try await GraphQLClient.shared.execute(
                query: GraphQLQueries.statsScenesQuery,
                variables: ["filter": filter, "scene_filter": scope]
            )
            return StatsBatch(
                items: response.data?.findScenes.scenes ?? [],
                count: response.data?.findScenes.count ?? 0
            )
        case .images:
            let response: StatsImagesResponse = try await GraphQLClient.shared.execute(
                query: GraphQLQueries.statsImagesQuery,
                variables: ["filter": filter, "image_filter": scope]
            )
            return StatsBatch(
                items: response.data?.findImages.images ?? [],
                count: response.data?.findImages.count ?? 0
            )
        }
    }

    // MARK: - Storage

    /// Keyed by host and port rather than the config's UUID: re-adding or re-editing a
    /// server keeps its model instead of silently starting from zero.
    private static func modelURL() -> URL? {
        guard let config = ServerConfigManager.shared.activeConfig else { return nil }
        let host = config.serverAddress.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        let port = config.port ?? config.serverProtocol.defaultPort
        let key = "\(host):\(port)"
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")

        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AITagStats", isDirectory: true)
            .appendingPathComponent("\(key).json")
    }
}

#endif
