//
//  AITagSuggestionManager.swift
//  stashy
//
//  Tag Suggestion (stashy+): tags proposed from the library's own statistics.
//
//  The whole library is counted once into a local statistics model:
//
//  * how often each performer is tagged with each tag
//  * the same for galleries, for studios, and for the library as a whole
//  * which tags occur *together* on the same item
//
//  Everything a scope knows is ranked and the top N are shown — no threshold, so the
//  list is as long as configured whenever the statistics have that many candidates.
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
        case related     // co-occurrence with the tags the item already has
    }

    let tag: Tag
    let confidence: Double
    let source: Source

    var id: String { tag.id }
}

/// What a suggestion is made for. Scenes, markers, clips and pictures all reach the
/// same statistics; only the write path and the metadata they can offer differ.
struct AITagTarget: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case image
        case scene
        case marker
    }

    let kind: Kind
    let entityId: String
    /// Everything the item carries, primary tag included — used for co-occurrence and
    /// to keep a tag from being suggested twice.
    let tags: [Tag]
    /// A marker's primary tag is set separately in Stash and must stay out of `tag_ids`.
    let primaryTagId: String?
    let performerIds: [String]
    let studioId: String?
    let galleryIds: [String]

    var id: String { "\(kind.rawValue)-\(entityId)" }

    static func image(_ image: StashImage) -> AITagTarget {
        AITagTarget(
            kind: .image,
            entityId: image.id,
            tags: image.tags ?? [],
            primaryTagId: nil,
            performerIds: (image.performers ?? []).map(\.id),
            studioId: image.studio?.id,
            galleryIds: (image.galleries ?? []).map(\.id)
        )
    }

    static func scene(_ scene: Scene) -> AITagTarget {
        AITagTarget(
            kind: .scene,
            entityId: scene.id,
            tags: scene.tags ?? [],
            primaryTagId: nil,
            performerIds: scene.performers.map(\.id),
            studioId: scene.studio?.id,
            galleryIds: (scene.galleries ?? []).map(\.id)
        )
    }

    /// Markers carry their own tags, so they are tagged as themselves — not as their
    /// scene. Their scene still supplies the performers the statistics need.
    static func marker(_ marker: SceneMarker) -> AITagTarget {
        var tags = marker.tags ?? []
        if let primary = marker.primaryTag, !tags.contains(where: { $0.id == primary.id }) {
            tags.insert(primary, at: 0)
        }
        return AITagTarget(
            kind: .marker,
            entityId: marker.id,
            tags: tags,
            primaryTagId: marker.primaryTag?.id,
            performerIds: (marker.scene?.performers ?? []).map(\.id),
            studioId: nil,
            galleryIds: []
        )
    }
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

    /// How many suggestions the chip row shows at most.
    @Published var maxSuggestions: Int {
        didSet { UserDefaults.standard.set(maxSuggestions, forKey: Keys.maxSuggestions) }
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
    private var persistTask: Task<Void, Never>?
    private var didLoadFromDisk = false
    private var serverObserver: NSObjectProtocol?

    /// Tags the user waved away. Ignoring one takes it out of the suggestions until it
    /// is accepted somewhere — the alternative is being wrong about the same tag on
    /// every single clip.
    private var dismissals: [String: Int] = [:]

    private enum Keys {
        static let enabled = "ai_tags_enabled"
        static let maxSuggestions = "ai_tags_max_suggestions"
        static let dismissed = "ai_tags_dismissed"
    }

    private static let modelVersion = 2
    /// One "Ignore Tag" is the answer, not a vote — the tag is out until it is
    /// accepted somewhere.
    private static let dismissStrikes = 1
    /// Laplace-style damping: one of one item is not a certainty.
    private static let smoothing = 1.0
    /// Co-occurrence is only kept for the strongest partners of a tag — the full matrix
    /// is mostly noise and would bloat the file for nothing.
    private static let partnersPerTag = 40
    /// Fewer, larger pages: the build is dominated by round trips, not by the rows
    /// themselves — each item is only ids and tag names.
    private static let pageSize = 500

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.enabled)
        maxSuggestions = defaults.object(forKey: Keys.maxSuggestions) as? Int ?? 8
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
        persistTask?.cancel()
        persistTask = nil
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

    /// Cached suggestions for a target. Tags it meanwhile carries are dropped — a tag
    /// is never suggested twice.
    func cachedSuggestions(for target: AITagTarget) -> [AITagSuggestion]? {
        guard let cached = suggestionCache[target.id] else { return nil }
        let existing = Set(target.tags.map(\.id))
        return cached.filter { !existing.contains($0.tag.id) }
    }

    /// Ranked suggestions for one item, excluding tags it already has. Pure lookups in
    /// the local model — no request while browsing.
    @discardableResult
    func suggestions(for target: AITagTarget, forceRefresh: Bool = false) async -> [AITagSuggestion] {
        guard isActive else { return [] }
        if !forceRefresh, let cached = cachedSuggestions(for: target) { return cached }
        await loadIfNeeded()
        guard let model else { return [] }

        let existingSet = Set(target.tags.map(\.id))
        var scores: [String: (score: Double, source: AITagSuggestion.Source)] = [:]

        func offer(_ tagId: String, _ score: Double, _ source: AITagSuggestion.Source) {
            guard !existingSet.contains(tagId) else { return }
            guard (dismissals[tagId] ?? 0) < Self.dismissStrikes else { return }
            guard let current = scores[tagId] else {
                scores[tagId] = (score, source)
                return
            }
            scores[tagId] = (
                Self.combine(current.score, score),
                score > current.score ? source : current.source
            )
        }

        func absorb(
            _ counts: [String: Int]?,
            _ total: Int?,
            weight: Double,
            source: AITagSuggestion.Source
        ) {
            guard let counts, let total, total > 0 else { return }
            let denominator = Double(total) + Self.smoothing
            for (tagId, count) in counts {
                offer(tagId, weight * Double(count) / denominator, source)
            }
        }

        // 1. What this item's performers are usually tagged with.
        for performerId in target.performerIds {
            absorb(
                model.performerCounts[performerId],
                model.performerTotals[performerId],
                weight: 1.0,
                source: .performer
            )
        }

        // 2. The gallery — usually one shoot, so its tags carry over to its siblings
        //    more reliably than anything else here.
        for galleryId in target.galleryIds {
            absorb(
                model.galleryCounts[galleryId],
                model.galleryTotals[galleryId],
                weight: 0.95,
                source: .gallery
            )
        }

        // 3. The studio — real, but less specific, hence discounted.
        if let studioId = target.studioId {
            absorb(
                model.studioCounts[studioId],
                model.studioTotals[studioId],
                weight: 0.8,
                source: .studio
            )
        }

        // 4. Tags that travel with the ones this item already has. The only signal here
        //    that is about the item itself rather than about who is in it.
        for tag in target.tags {
            absorb(
                model.pairCounts[tag.id],
                model.tagTotals[tag.id],
                weight: 1.0,
                source: .related
            )
        }

        let result = scores
            .compactMap { (tagId, value) -> AITagSuggestion? in
                guard let tag = tagsById[tagId] else { return nil }
                return AITagSuggestion(tag: tag, confidence: min(1, value.score), source: value.source)
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(max(1, maxSuggestions))

        let suggestions = Array(result)
        suggestionCache[target.id] = suggestions
        return suggestions
    }

    /// The server's tag list as captured by the last statistics build. Reusing it saves
    /// the picker a 1000-tag round trip on every open.
    var vocabulary: [Tag] { model?.tags ?? [] }

    /// How often each tag appears on this item's performers, from the statistics model.
    /// Several performers: the strongest count wins. Empty when no model is built.
    func performerTagCounts(for target: AITagTarget) -> [String: Int] {
        guard let model else { return [:] }
        var counts: [String: Int] = [:]
        for performerId in target.performerIds {
            guard let performerCounts = model.performerCounts[performerId] else { continue }
            for (tagId, count) in performerCounts {
                counts[tagId] = max(counts[tagId] ?? 0, count)
            }
        }
        return counts
    }

    /// How two signals for the same tag fold into one score: the stronger carries,
    /// agreement adds a modest bonus, the result never exceeds certainty.
    private static func combine(_ lhs: Double, _ rhs: Double) -> Double {
        min(1, max(lhs, rhs) + 0.15 * min(lhs, rhs))
    }

    // MARK: - Dismissing

    /// Records that the user rejected this tag. Accepting it anywhere clears the record,
    /// so a single misfire never buries a tag for good.
    func dismiss(_ suggestion: AITagSuggestion, on target: AITagTarget) {
        dismissals[suggestion.tag.id, default: 0] += 1
        UserDefaults.standard.set(dismissals, forKey: Keys.dismissed)
        if var cached = suggestionCache[target.id] {
            cached.removeAll { $0.tag.id == suggestion.tag.id }
            suggestionCache[target.id] = cached
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

    func accept(_ suggestion: AITagSuggestion, on target: AITagTarget) async -> [Tag]? {
        await accept([suggestion], on: target)
    }

    /// Adds tags in one mutation — auto-accept would otherwise fire a request per tag.
    func accept(_ accepted: [AITagSuggestion], on target: AITagTarget) async -> [Tag]? {
        let existingIds = Set(target.tags.map(\.id))
        let additions = accepted.map(\.tag).filter { !existingIds.contains($0.id) }
        guard !additions.isEmpty else { return target.tags }
        let newTags = target.tags + additions

        guard await write(tags: newTags, to: target) else { return nil }

        let acceptedIds = Set(additions.map(\.id))
        for tagId in acceptedIds where dismissals[tagId] != nil {
            dismissals[tagId] = nil
        }
        UserDefaults.standard.set(dismissals, forKey: Keys.dismissed)

        if var cached = suggestionCache[target.id] {
            cached.removeAll { acceptedIds.contains($0.tag.id) }
            suggestionCache[target.id] = cached
        }
        return newTags
    }

    /// Writes a tag list to whichever entity the target stands for, folds the change
    /// into the local statistics and broadcasts it so open lists patch themselves
    /// without a refetch.
    @discardableResult
    func write(tags: [Tag], to target: AITagTarget) async -> Bool {
        var input: [String: Any] = ["id": target.entityId]
        let mutation: String
        let notification: String
        let idKey: String

        switch target.kind {
        case .image:
            mutation = GraphQLQueries.imageUpdateTagsMutation
            notification = "ImageTagsUpdated"
            idKey = "imageId"
            input["tag_ids"] = tags.map(\.id)
        case .scene:
            mutation = GraphQLQueries.sceneUpdateTagsMutation
            notification = "SceneTagsUpdated"
            idKey = "sceneId"
            input["tag_ids"] = tags.map(\.id)
        case .marker:
            mutation = GraphQLQueries.sceneMarkerUpdateTagsMutation
            notification = "MarkerTagsUpdated"
            idKey = "markerId"
            // The primary tag lives in its own field; repeating it in tag_ids would
            // duplicate it on the marker.
            input["tag_ids"] = tags.map(\.id).filter { $0 != target.primaryTagId }
        }

        do {
            _ = try await GraphQLClient.shared.performMutation(
                mutation: mutation,
                variables: ["input": input]
            )
        } catch {
            AppLog.error("AITags: tag update failed — \(error.localizedDescription)")
            return false
        }

        // Tagging is how the library grows; the statistics have to grow with it or a
        // performer you just tagged 25 more images for stays at their old numbers until
        // the next full rebuild.
        applyLocalUpdate(target: target, newTags: tags)

        NotificationCenter.default.post(
            name: NSNotification.Name(notification),
            object: nil,
            userInfo: [idKey: target.entityId, "tags": tags]
        )
        return true
    }

    /// Folds one tag change into the in-memory model and schedules a save.
    private func applyLocalUpdate(target: AITagTarget, newTags: [Tag]) {
        guard var model else { return }

        let oldIds = Set(target.tags.map(\.id))
        let newIds = Set(newTags.map(\.id))
        let added = newIds.subtracting(oldIds)
        let removed = oldIds.subtracting(newIds)
        guard !added.isEmpty || !removed.isEmpty else { return }

        // Markers are counted as part of no scope in the build (they are not items), so
        // they only affect the tag vocabulary.
        let countsAsItem = target.kind != .marker
        // The build only counts items that carry at least one tag.
        let wasCounted = countsAsItem && !oldIds.isEmpty
        let isCounted = countsAsItem && !newIds.isEmpty
        let itemDelta = (isCounted ? 1 : 0) - (wasCounted ? 1 : 0)

        func bump(_ counts: inout [String: [String: Int]], _ totals: inout [String: Int], _ ids: [String]) {
            for id in ids {
                if itemDelta != 0 {
                    totals[id] = max(0, (totals[id] ?? 0) + itemDelta)
                }
                var scope = counts[id] ?? [:]
                for tagId in added { scope[tagId, default: 0] += 1 }
                for tagId in removed { scope[tagId] = max(0, (scope[tagId] ?? 0) - 1) }
                counts[id] = scope.filter { $0.value > 0 }
            }
        }

        if countsAsItem {
            bump(&model.performerCounts, &model.performerTotals, target.performerIds)
            bump(&model.galleryCounts, &model.galleryTotals, target.galleryIds)
            if let studioId = target.studioId {
                bump(&model.studioCounts, &model.studioTotals, [studioId])
            }
            model.itemCount = max(0, model.itemCount + itemDelta)

            for tagId in added { model.tagTotals[tagId, default: 0] += 1 }
            for tagId in removed { model.tagTotals[tagId] = max(0, (model.tagTotals[tagId] ?? 0) - 1) }

            // Co-occurrence: an added tag pairs with everything the item now has, a
            // removed one loses its pairs with whatever stayed.
            var pairs = model.pairCounts
            func pair(_ lhs: String, _ rhs: String, by delta: Int) {
                var partners = pairs[lhs] ?? [:]
                partners[rhs] = max(0, (partners[rhs] ?? 0) + delta)
                if partners[rhs] == 0 { partners[rhs] = nil }
                pairs[lhs] = partners.isEmpty ? nil : partners
            }
            for tagId in added {
                for other in newIds where other != tagId {
                    pair(tagId, other, by: 1)
                    pair(other, tagId, by: 1)
                }
            }
            for tagId in removed {
                for other in newIds where other != tagId {
                    pair(tagId, other, by: -1)
                    pair(other, tagId, by: -1)
                }
            }
            model.pairCounts = pairs
        }

        // A tag created from the picker is not in the captured vocabulary yet.
        for tag in newTags where tagsById[tag.id] == nil {
            model.tags.append(tag)
            tagsById[tag.id] = tag
        }

        self.model = model
        itemCount = model.itemCount
        // Every other item's cached suggestions were scored against the old numbers.
        // Recomputing is a handful of dictionary lookups now, so drop the lot rather
        // than serve stale scores for the rest of the session.
        suggestionCache = [:]
        schedulePersist()
    }

    /// Writing the whole model on every accepted tag would burn battery for nothing;
    /// a short idle window collapses a tagging spree into one save.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let model = self.model else { return }
            self.persist(model)
        }
    }

    // MARK: - Bulk actions

    /// What a bulk tag action covers.
    enum BulkScope: Equatable {
        case gallery
        case performer
    }

    struct BulkPlan: Equatable, Identifiable {
        var id: String { "\(scope)-\(tag.id)" }
        let scope: BulkScope
        let tag: Tag
        let imageIds: [String]
        let sceneIds: [String]
        var total: Int { imageIds.count + sceneIds.count }
    }

    /// Collects everything a bulk action would touch, so the user can be asked with a
    /// real number instead of a blind "apply to all".
    func planBulkApply(_ tag: Tag, scope: BulkScope, target: AITagTarget) async -> BulkPlan? {
        let ids: [String]
        switch scope {
        case .gallery: ids = target.galleryIds
        case .performer: ids = target.performerIds
        }
        guard !ids.isEmpty else { return nil }

        let key = scope == .gallery ? "galleries" : "performers"
        let filter: [String: Any] = ["per_page": -1, "sort": "id", "direction": "ASC"]
        let itemFilter: [String: Any] = [key: ["value": ids, "modifier": "INCLUDES"]]

        async let images = fetchIds(
            query: GraphQLQueries.idsImagesQuery,
            variables: ["filter": filter, "image_filter": itemFilter],
            source: .images
        )
        // A gallery holds images; scenes only ever match the performer scope.
        async let scenes: [String] = scope == .performer
            ? fetchIds(
                query: GraphQLQueries.idsScenesQuery,
                variables: ["filter": filter, "scene_filter": itemFilter],
                source: .scenes
              )
            : []

        let plan = BulkPlan(scope: scope, tag: tag, imageIds: await images, sceneIds: await scenes)
        return plan.total > 0 ? plan : nil
    }

    /// Adds the tag to everything the plan covers. Stash's bulk mutations take an ADD
    /// mode, so existing tags on those items are kept.
    @discardableResult
    func applyBulk(_ plan: BulkPlan, target: AITagTarget) async -> Bool {
        var ok = true
        if !plan.imageIds.isEmpty {
            ok = await bulkAdd(
                tagId: plan.tag.id,
                ids: plan.imageIds,
                mutation: GraphQLQueries.bulkImageAddTagsMutation
            ) && ok
        }
        if !plan.sceneIds.isEmpty {
            ok = await bulkAdd(
                tagId: plan.tag.id,
                ids: plan.sceneIds,
                mutation: GraphQLQueries.bulkSceneAddTagsMutation
            ) && ok
        }
        guard ok else { return false }

        applyBulkToModel(plan, target: target)
        // The ids are the only thing that lets open lists patch themselves — without
        // them a feed would keep showing the old tags until it is refetched.
        NotificationCenter.default.post(
            name: NSNotification.Name("BulkTagsApplied"),
            object: nil,
            userInfo: [
                "tag": plan.tag,
                "imageIds": plan.imageIds,
                "sceneIds": plan.sceneIds
            ]
        )
        return true
    }

    private func bulkAdd(tagId: String, ids: [String], mutation: String) async -> Bool {
        // Chunked so a large gallery does not go out as one enormous request.
        for chunk in stride(from: 0, to: ids.count, by: 200).map({ Array(ids[$0..<min($0 + 200, ids.count)]) }) {
            let input: [String: Any] = [
                "ids": chunk,
                "tag_ids": ["ids": [tagId], "mode": "ADD"]
            ]
            do {
                _ = try await GraphQLClient.shared.performMutation(mutation: mutation, variables: ["input": input])
            } catch {
                AppLog.error("AITags: bulk tag update failed — \(error.localizedDescription)")
                return false
            }
        }
        return true
    }

    /// After a bulk apply every item of that scope carries the tag, so its count is its
    /// total. The library-wide total can only be approximated — the items that already
    /// had the tag are not distinguishable here.
    private func applyBulkToModel(_ plan: BulkPlan, target: AITagTarget) {
        guard var model else { return }
        let tagId = plan.tag.id

        switch plan.scope {
        case .gallery:
            for galleryId in target.galleryIds {
                guard let total = model.galleryTotals[galleryId] else { continue }
                model.galleryCounts[galleryId, default: [:]][tagId] = total
            }
        case .performer:
            for performerId in target.performerIds {
                guard let total = model.performerTotals[performerId] else { continue }
                model.performerCounts[performerId, default: [:]][tagId] = total
            }
        }
        model.tagTotals[tagId] = max(model.tagTotals[tagId] ?? 0, plan.total)

        if tagsById[tagId] == nil {
            model.tags.append(plan.tag)
            tagsById[tagId] = plan.tag
        }
        self.model = model
        suggestionCache = [:]
        schedulePersist()
    }

    private func fetchIds(query: String, variables: [String: Any], source: StatsSource) async -> [String] {
        do {
            switch source {
            case .images:
                let response: PerformerImagesResponse = try await GraphQLClient.shared.execute(
                    query: query, variables: variables
                )
                return (response.data?.findImages.images ?? []).map(\.id)
            case .scenes:
                let response: PerformerScenesResponse = try await GraphQLClient.shared.execute(
                    query: query, variables: variables
                )
                return (response.data?.findScenes.scenes ?? []).map(\.id)
            }
        } catch {
            AppLog.error("AITags: bulk id lookup failed — \(error.localizedDescription)")
            return []
        }
    }

    private struct IdOnly: Decodable { let id: String }

    private struct PerformerImagesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindImages: Decodable { let count: Int; let images: [IdOnly] }
            let findImages: FindImages
        }
        let data: DataBlock?
    }

    private struct PerformerScenesResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindScenes: Decodable { let count: Int; let scenes: [IdOnly] }
            let findScenes: FindScenes
        }
        let data: DataBlock?
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
