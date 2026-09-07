//
//  SimilarScenesFinder.swift
//  stashy
//
//  stashy+ — scenes that resemble the one on screen, found in the user's own library.
//

#if !os(tvOS)
import Foundation
import SwiftUI

/// Finds scenes similar to a given one: same performers, same studio, overlapping tags.
///
/// Everything happens against the user's own Stash — no external service. Stash's
/// `SceneFilterType` supports `OR`, so performers ∪ studio ∪ tags is a single `findScenes`;
/// the ranking then runs locally, where a weighted overlap is cheap and easy to tune.
///
/// When the Suggestions statistics are built, `AITagSuggestionManager.relatedTagWeights(for:)`
/// adds a bonus for *related* tags, so a candidate tagged with something that habitually
/// co-occurs beats one that only shares a common tag. Without statistics the ranking still
/// works, just on plain overlap.
@MainActor
final class SimilarScenesFinder: ObservableObject {
    static let shared = SimilarScenesFinder()

    static let enabledKey = "similar_scenes_enabled"
    static let maxCountKey = "similar_scenes_max"

    /// Own kill switch — independent of tag suggestions.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// How many to show. The card is only worth the space with a handful of entries.
    @Published var maxCount: Int {
        didSet { UserDefaults.standard.set(maxCount, forKey: Self.maxCountKey) }
    }

    /// Upper bound on what the server sends back before local ranking. Generous enough that a
    /// scene with a common tag still has good candidates, small enough to stay cheap.
    private static let candidateLimit = 200

    // Weights: who is in it matters most, then what it is about, then who made it.
    private static let performerWeight = 3.0
    private static let tagWeight = 1.5
    private static let studioWeight = 1.0
    private static let relatedTagWeight = 0.5

    /// Floor for the rarity factor: a tag on almost every scene still says a little.
    private static let minRarity = 0.15

    /// Library scene count, for the rarity factor. Fetched once per session.
    private var totalSceneCount: Int?

    /// Keyed by what the ranking actually depends on, not by scene id: the detail view first
    /// renders the list version of a scene and swaps in the fully loaded one afterwards. Keying
    /// on the id alone cached the empty result of that first, incomplete pass forever.
    /// Results for the scene currently on screen. The detail view drives this — the card only
    /// renders it, so it can never show what an earlier scene loaded.
    @Published private(set) var scenes: [Scene] = []
    @Published private(set) var isLoading = false

    /// Which lookup the published result belongs to; a late answer for an older scene is dropped.
    private var currentKey = ""

    private var cache: [String: [Scene]] = [:]

    /// Identity of the inputs — same scene with more metadata means a different lookup.
    static func signature(for scene: Scene) -> String {
        let performers = scene.performers.map(\.id).sorted().joined(separator: ",")
        let tags = (scene.tags ?? []).map(\.id).sorted().joined(separator: ",")
        return "\(scene.id)|p:\(performers)|t:\(tags)|s:\(scene.studio?.id ?? "")"
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let stored = UserDefaults.standard.integer(forKey: Self.maxCountKey)
        maxCount = (4...8).contains(stored) ? stored : 8
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cache.removeAll() }
        }
    }

    var isActive: Bool { isEnabled && StashyPlusManager.isUnlockedNow }

    func invalidate() {
        cache.removeAll()
        scenes = []
        currentKey = ""
        totalSceneCount = nil
    }

    /// Rarity of a tag, 0.15…1. A tag on three scenes identifies a theme; one on almost every
    /// scene identifies nothing. Classic IDF: `log(N / df) / log(N)`.
    ///
    /// `df` comes straight from `Tag.scene_count`, which the scene detail already loads via
    /// `TagFields` — no statistics needed and exact for scenes, unlike the shared tag model,
    /// which counts images and scenes together.
    private func rarity(of tag: Tag, totalScenes: Int) -> Double {
        let df = max(1, tag.sceneCount ?? 1)
        guard totalScenes > 1, df < totalScenes else { return Self.minRarity }
        let idf = log(Double(totalScenes) / Double(df)) / log(Double(totalScenes))
        return min(1.0, max(Self.minRarity, idf))
    }

    private func loadTotalSceneCount() async -> Int {
        if let totalSceneCount { return totalSceneCount }
        struct Response: Decodable {
            struct DataBlock: Decodable {
                struct Stats: Decodable { let scene_count: Int }
                let stats: Stats
            }
            let data: DataBlock?
        }
        do {
            let response: Response = try await GraphQLClient.shared.execute(
                query: "{ stats { scene_count } }"
            )
            let count = response.data?.stats.scene_count ?? 0
            totalSceneCount = count
            return count
        } catch {
            AppLog.error("🎞️ SIMILAR SCENES: stats query failed — \(error.localizedDescription)")
            totalSceneCount = 0
            return 0
        }
    }

    /// Called by `SceneDetailView` when it opens a scene and again once the full metadata
    /// arrives. Everything the card shows comes from here.
    func load(for scene: Scene) async {
        let key = Self.signature(for: scene)
        currentKey = key
        guard isActive else {
            scenes = []
            return
        }
        if let cached = cache[key] {
            scenes = cached
            return
        }
        isLoading = true
        let found = await similarScenes(for: scene)
        guard currentKey == key else { return }
        scenes = found
        isLoading = false
    }

    // MARK: - Lookup

    func similarScenes(for scene: Scene) async -> [Scene] {
        let key = Self.signature(for: scene)
        if let cached = cache[key] { return cached }
        guard isActive else {
            AppLog.debug("🎞️ SIMILAR SCENES: off — enabled:\(isEnabled) plus:\(StashyPlusManager.isUnlockedNow)")
            return []
        }

        let performerIds = scene.performers.map(\.id)
        let tagIds = (scene.tags ?? []).map(\.id)
        let studioId = scene.studio?.id

        guard !performerIds.isEmpty || !tagIds.isEmpty || studioId != nil else {
            AppLog.debug("🎞️ SIMILAR SCENES: scene \(scene.id) has no performers, tags or studio")
            return []
        }

        // The ranking bonus reads the shared statistics; make sure they are in memory even
        // when tag suggestions are switched off.
        await AITagSuggestionManager.shared.loadIfNeeded()

        let candidates = await fetchCandidates(
            performerIds: performerIds,
            tagIds: tagIds,
            studioId: studioId
        )
        guard !candidates.isEmpty else {
            AppLog.debug("🎞️ SIMILAR SCENES: no candidates for scene \(scene.id)")
            cache[key] = []
            return []
        }

        let ranked = rank(
            candidates: candidates,
            performerIds: Set(performerIds),
            sourceTags: scene.tags ?? [],
            studioId: studioId,
            totalScenes: await loadTotalSceneCount(),
            excluding: scene.id
        )
        cache[key] = ranked
        AppLog.debug("🎞️ SIMILAR SCENES: scene \(scene.id) — \(candidates.count) candidates → \(ranked.count) shown")
        return ranked
    }

    // MARK: - Query

    /// One query per criterion, merged locally.
    ///
    /// Stash can express this as a single nested `OR`, but a filter that a server rejects fails
    /// silently for the user — and only scenes with a single criterion would have worked, which
    /// is exactly what happened. Three plain filters are each a shape the app already uses
    /// everywhere, they run concurrently, and one failing still leaves the others.
    private func fetchCandidates(
        performerIds: [String],
        tagIds: [String],
        studioId: String?
    ) async -> [Scene] {
        var clauses: [(name: String, filter: [String: Any])] = []
        if !performerIds.isEmpty {
            clauses.append(("performers", ["performers": ["value": performerIds, "modifier": "INCLUDES", "depth": 0]]))
        }
        if !tagIds.isEmpty {
            clauses.append(("tags", ["tags": ["value": tagIds, "modifier": "INCLUDES", "depth": 0]]))
        }
        if let studioId {
            clauses.append(("studio", ["studios": ["value": [studioId], "modifier": "INCLUDES", "depth": 0]]))
        }
        guard !clauses.isEmpty else { return [] }

        var merged: [Scene] = []
        var seen = Set<String>()
        await withTaskGroup(of: [Scene].self) { group in
            for clause in clauses {
                group.addTask { await self.runCandidateQuery(named: clause.name, filter: clause.filter) }
            }
            for await result in group {
                for scene in result where !seen.contains(scene.id) {
                    seen.insert(scene.id)
                    merged.append(scene)
                }
            }
        }
        return merged
    }

    private func runCandidateQuery(named name: String, filter: [String: Any]) async -> [Scene] {
        let query = GraphQLQueries.queryWithFragments("findScenesSimilar")
        let variables: [String: Any] = [
            "filter": ["page": 1, "per_page": Self.candidateLimit],
            "scene_filter": filter
        ]
        do {
            let response: AltScenesResponse = try await GraphQLClient.shared.execute(
                query: query,
                variables: variables
            )
            let scenes = response.data?.findScenes?.scenes ?? []
            AppLog.debug("🎞️ SIMILAR SCENES: \(name) → \(scenes.count)")
            return scenes
        } catch {
            AppLog.error("🎞️ SIMILAR SCENES: \(name) query failed — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Ranking

    private func rank(
        candidates: [Scene],
        performerIds: Set<String>,
        sourceTags: [Tag],
        studioId: String?,
        totalScenes: Int,
        excluding sceneId: String
    ) -> [Scene] {
        let tagIds = Set(sourceTags.map(\.id))
        let related = AITagSuggestionManager.shared.relatedTagWeights(for: Array(tagIds))
        // Rarity per source tag — a shared niche tag is worth far more than a shared common one.
        let rarityById: [String: Double] = Dictionary(
            uniqueKeysWithValues: sourceTags.map { ($0.id, rarity(of: $0, totalScenes: totalScenes)) }
        )

        let scored: [(scene: Scene, score: Double)] = candidates.compactMap { candidate in
            guard candidate.id != sceneId else { return nil }

            let candidatePerformers = Set(candidate.performers.map(\.id))
            let candidateTags = Set((candidate.tags ?? []).map(\.id))

            var score = 0.0
            score += Double(candidatePerformers.intersection(performerIds).count) * Self.performerWeight
            score += candidateTags.intersection(tagIds)
                .reduce(0.0) { $0 + Self.tagWeight * (rarityById[$1] ?? Self.minRarity) }
            if let studioId, candidate.studio?.id == studioId { score += Self.studioWeight }

            // Bonus for tags that habitually travel with the source tags. Capped so a heavily
            // tagged scene cannot out-rank one that actually shares a performer.
            if !related.isEmpty {
                let bonus = candidateTags
                    .subtracting(tagIds)
                    .compactMap { related[$0] }
                    .reduce(0, +)
                score += min(bonus, 2.0) * Self.relatedTagWeight
            }

            return score > 0 ? (candidate, score) : nil
        }

        return scored
            .sorted { $0.score == $1.score ? $0.scene.id < $1.scene.id : $0.score > $1.score }
            .prefix(maxCount)
            .map(\.scene)
    }
}
#endif
