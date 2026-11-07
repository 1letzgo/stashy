//
//  SceneRecommendationEngine.swift
//  stashy
//
//  stashy+ — "For You" on Home: a handful of scenes picked from the user's own watch
//  history, each with the reason it was picked.
//

#if !os(tvOS)

import Foundation
import SwiftUI
import Combine

/// One suggested scene and why it is there.
struct SceneRecommendation: Identifiable, Equatable, Codable {
    enum Reason: Equatable, Codable {
        case performer(String)
        case studio(String)
        case tag(String)
        case relatedTag(String)
        case rediscover
        case favorite
        /// Unplayed and close to one scene the user watched a lot.
        case similarTo(String)

        var label: String {
            switch self {
            case .similarTo(let title): return "Like \u{201C}\(title)\u{201D}"
            case .performer(let name): return "More with \(name)"
            case .studio(let name): return "More from \(name)"
            case .tag(let name): return "You like \(name)"
            case .relatedTag(let name): return "Goes with your tags: \(name)"
            case .rediscover: return "Rediscover"
            case .favorite: return "One of your favorites"
            }
        }

        var shortLabel: String {
            switch self {
            case .performer(let name): return name
            case .studio(let name): return name
            case .tag(let name): return name
            case .relatedTag(let name): return name
            case .rediscover: return "Rediscover"
            case .favorite: return "Favorite"
            case .similarTo(let title): return title
            }
        }

        var icon: String {
            switch self {
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            case .relatedTag: return "point.3.connected.trianglepath.dotted"
            case .rediscover: return "arrow.counterclockwise"
            case .favorite: return "heart.fill"
            case .similarTo: return "square.stack.3d.up.fill"
            }
        }
    }

    let scene: Scene
    let reason: Reason
    /// Never played before.
    let isUnwatched: Bool
    let score: Double

    var id: String { scene.id }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scene.id == rhs.scene.id && lhs.reason == rhs.reason && lhs.isUnwatched == rhs.isUnwatched
    }
}

/// What the user can turn in Settings › stashy+ › For You.
enum RecommendationDiscovery: String, CaseIterable, Identifiable {
    /// Only scenes never played.
    case fresh
    /// Mostly unplayed, old favourites may come back.
    case balanced
    /// Leans on scenes with O-Counts and high ratings that have not been played for a while.
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fresh: return "New only"
        case .balanced: return "Balanced"
        case .favorites: return "Favorites"
        }
    }

    var detail: String {
        switch self {
        case .fresh: return "Only scenes you have never played."
        case .balanced: return "Unplayed scenes and scenes you have not played in this period, weighed the same."
        case .favorites: return "Scenes with O-Counts or high ratings you have not played in a while."
        }
    }
}

/// Builds the For You list.
///
/// 1. **Profile** — every scene played in the look-back window is a seed. Its weight grows
///    with recency, replays, O-Counts in the window, how much of it was watched and its rating
///    (a low rating counts against it). Performers, studio and tags of the seeds collect that
///    weight; tags are scaled by rarity (IDF), so "HD" says little and a niche tag a lot.
/// 2. **Candidates** — three plain queries (top performers, top studios, top tags), each in a
///    random order seeded by the day, so the row changes daily but not on every refresh.
/// 3. **Score** — overlap with the profile, per factor weighted by the user's settings, plus a
///    bonus for tags that habitually travel with the favourite tags (the Suggestions
///    statistics, when built). Scenes played within the window never come back; the discovery
///    setting decides how unplayed and old favourites are treated.
/// 4. **Diversify** — greedy pick; a performer or studio already shown makes the next scene
///    with the same reason count less, so one performer cannot fill the row.
///
/// The strongest factor of a pick is its reason. Everything runs against the user's own Stash.
@MainActor
final class SceneRecommendationEngine: ObservableObject {
    static let shared = SceneRecommendationEngine()

    enum State: Equatable {
        case idle
        case loading
        case ready
        /// Nothing in the history yet to learn from.
        case noHistory
        case failed(String)
    }

    // MARK: Settings

    enum Keys {
        static let lookbackDays = "recommendations_lookback_days"
        static let count = "recommendations_count"
        static let performerWeight = "recommendations_weight_performer"
        static let studioWeight = "recommendations_weight_studio"
        static let tagWeight = "recommendations_weight_tag"
        static let oCountWeight = "recommendations_weight_ocount"
        static let ratingWeight = "recommendations_weight_rating"
        static let similarWeight = "recommendations_weight_similar"
        static let discovery = "recommendations_discovery"
    }

    static let lookbackChoices = [7, 14, 30, 60, 90]
    static let countRange = 5...10
    static let weightRange: ClosedRange<Double> = 0...2

    @Published var lookbackDays: Int { didSet { persist(lookbackDays, Keys.lookbackDays) } }
    @Published var count: Int { didSet { persist(count, Keys.count) } }
    @Published var performerWeight: Double { didSet { persist(performerWeight, Keys.performerWeight) } }
    @Published var studioWeight: Double { didSet { persist(studioWeight, Keys.studioWeight) } }
    @Published var tagWeight: Double { didSet { persist(tagWeight, Keys.tagWeight) } }
    @Published var oCountWeight: Double { didSet { persist(oCountWeight, Keys.oCountWeight) } }
    @Published var ratingWeight: Double { didSet { persist(ratingWeight, Keys.ratingWeight) } }
    /// Unplayed scenes close to single watched scenes ("Like …").
    @Published var similarWeight: Double { didSet { persist(similarWeight, Keys.similarWeight) } }
    @Published var discovery: RecommendationDiscovery {
        didSet { persist(discovery.rawValue, Keys.discovery) }
    }

    var hasCustomSettings: Bool {
        lookbackDays != 30 || count != 8 || performerWeight != 1 || studioWeight != 1
            || tagWeight != 1 || oCountWeight != 1 || ratingWeight != 1 || similarWeight != 1
            || discovery != .balanced
    }

    func resetSettings() {
        lookbackDays = 30
        count = 8
        performerWeight = 1
        studioWeight = 1
        tagWeight = 1
        oCountWeight = 1
        ratingWeight = 1
        similarWeight = 1
        discovery = .balanced
    }

    // MARK: Output

    @Published private(set) var recommendations: [SceneRecommendation] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var builtAt: Date?
    /// How many plays the profile was built from — shown in Settings.
    @Published private(set) var seedCount = 0
    /// A visible rebuild is running (Settings shows it; the row keeps its cards meanwhile).
    @Published private(set) var isRefreshing = false

    /// The row belongs to the Recommendations features: it is there whenever Tag Suggestions or
    /// Similar Scenes is on. stashy+ is checked separately (`isAvailable`, `HomeView`).
    @Published private(set) var isFeatureOn = false

    var isAvailable: Bool { StashyPlusManager.isUnlockedNow && isFeatureOn }

    private var cancellables = Set<AnyCancellable>()

    // MARK: Private

    private var buildTask: Task<Void, Never>?
    /// Builds the list for the next app start (or the next refresh) in the background.
    private var prepareTask: Task<Void, Never>?
    /// The next list, ready to show; mirrored to disk per server so a cold start shows it at once.
    private var prepared: PreparedList?
    private var preparedLoadedFor: String?
    /// Settings changed since the last build; the next `refreshIfNeeded` rebuilds.
    private var isStale = false
    private var generation = 0
    private static let freshFor: TimeInterval = 3 * 60 * 60
    private static let historyPageSize = 100
    private static let historyMaxPages = 4
    private static let candidatesPerQuery = 150
    /// A tag on almost every scene still says a little.
    private static let minRarity = 0.15

    private init() {
        let d = UserDefaults.standard
        let lookback = d.integer(forKey: Keys.lookbackDays)
        lookbackDays = Self.lookbackChoices.contains(lookback) ? lookback : 30
        let storedCount = d.integer(forKey: Keys.count)
        count = Self.countRange.contains(storedCount) ? storedCount : 8
        performerWeight = Self.weight(d, Keys.performerWeight)
        studioWeight = Self.weight(d, Keys.studioWeight)
        tagWeight = Self.weight(d, Keys.tagWeight)
        oCountWeight = Self.weight(d, Keys.oCountWeight)
        ratingWeight = Self.weight(d, Keys.ratingWeight)
        similarWeight = Self.weight(d, Keys.similarWeight)
        discovery = RecommendationDiscovery(rawValue: d.string(forKey: Keys.discovery) ?? "") ?? .balanced

        isFeatureOn = AITagSuggestionManager.shared.isEnabled || SimilarScenesFinder.shared.isEnabled
        AITagSuggestionManager.shared.$isEnabled
            .combineLatest(SimilarScenesFinder.shared.$isEnabled)
            .map { $0 || $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                guard let self else { return }
                self.isFeatureOn = on
                if !on { self.reset() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
    }

    private static func weight(_ defaults: UserDefaults, _ key: String) -> Double {
        guard let value = defaults.object(forKey: key) as? Double, weightRange.contains(value) else { return 1 }
        return value
    }

    private func persist(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        isStale = true
    }

    func reset() {
        buildTask?.cancel()
        buildTask = nil
        prepareTask?.cancel()
        prepareTask = nil
        prepared = nil
        preparedLoadedFor = nil
        isRefreshing = false
        generation += 1
        recommendations = []
        builtAt = nil
        seedCount = 0
        state = .idle
    }

    /// Shows a list when nothing is there, the list is older than three hours or a setting changed.
    func refreshIfNeeded() {
        guard isAvailable else { return }
        if buildTask != nil { return }
        if !isStale, let builtAt, Date().timeIntervalSince(builtAt) < Self.freshFor,
           state == .ready || state == .noHistory {
            return
        }
        rebuild()
    }

    /// A new list now: the prepared one when it fits the current settings (instant), else a
    /// visible build. Either way the next list is prepared right after.
    func rebuild() {
        guard isAvailable, ServerConfigManager.shared.activeConfig != nil else { return }
        loadPreparedIfNeeded()
        if !isStale, let next = prepared, next.settings == settingsSignature,
           Date().timeIntervalSince(next.builtAt) < Self.preparedMaxAge, !next.items.isEmpty {
            show(next)
            return
        }
        buildVisible()
    }

    private func show(_ list: PreparedList) {
        generation += 1
        buildTask?.cancel()
        buildTask = nil
        isRefreshing = false
        prepared = nil
        Self.savePrepared(nil)
        recommendations = list.items
        seedCount = list.seedCount
        state = .ready
        builtAt = Date()
        // Shown now: it steps back in the next picks.
        Self.saveRecentPicks(list.items.map(\.id), keeping: Self.loadRecentPicks())
        AppLog.debug("✨ FOR YOU: showing prepared list (\(list.items.count))")
        prepareNext()
    }

    private func buildVisible() {
        buildTask?.cancel()
        prepareTask?.cancel()
        prepareTask = nil
        generation += 1
        let gen = generation
        isStale = false
        isRefreshing = true
        if recommendations.isEmpty { state = .loading }
        buildTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.build()
            guard gen == self.generation, !Task.isCancelled else { return }
            switch outcome {
            case .success(let picks, let seeds):
                self.recommendations = picks
                self.seedCount = seeds
                self.state = picks.isEmpty && seeds == 0 ? .noHistory : .ready
                if !picks.isEmpty {
                    Self.saveRecentPicks(picks.map(\.id), keeping: Self.loadRecentPicks())
                }
            case .failure(let message):
                if self.recommendations.isEmpty { self.state = .failed(message) }
            }
            self.builtAt = Date()
            self.isRefreshing = false
            self.buildTask = nil
            self.prepareNext()
        }
    }

    /// Builds the following list in the background and keeps it (memory + disk) for the next
    /// refresh or app start.
    private func prepareNext() {
        guard isAvailable else { return }
        prepareTask?.cancel()
        let gen = generation
        let signature = settingsSignature
        prepareTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.build()
            guard gen == self.generation, !Task.isCancelled, signature == self.settingsSignature else { return }
            if case .success(let picks, let seeds) = outcome, !picks.isEmpty {
                let list = PreparedList(settings: signature, builtAt: Date(), seedCount: seeds, items: picks)
                self.prepared = list
                Self.savePrepared(list)
                AppLog.debug("✨ FOR YOU: prepared next list (\(picks.count))")
            }
            self.prepareTask = nil
        }
    }

    // MARK: - Prepared list

    struct PreparedList: Codable {
        let settings: String
        let builtAt: Date
        let seedCount: Int
        let items: [SceneRecommendation]
    }

    /// A prepared list older than this is not shown: scenes may have been played meanwhile.
    private static let preparedMaxAge: TimeInterval = 36 * 60 * 60

    /// Everything a list depends on besides the library itself.
    private var settingsSignature: String {
        [String(lookbackDays), String(count), discovery.rawValue,
         performerWeight, studioWeight, tagWeight, oCountWeight, ratingWeight, similarWeight]
            .map { "\($0)" }
            .joined(separator: "|")
    }

    private func loadPreparedIfNeeded() {
        let server = ServerConfigManager.shared.activeConfig?.id.uuidString
        guard preparedLoadedFor != server else { return }
        preparedLoadedFor = server
        prepared = Self.loadPrepared()
    }

    private static var preparedURL: URL? {
        guard let id = ServerConfigManager.shared.activeConfig?.id,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("ForYou", isDirectory: true).appendingPathComponent("\(id.uuidString).json")
    }

    private static func loadPrepared() -> PreparedList? {
        guard let url = preparedURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PreparedList.self, from: data)
    }

    private static func savePrepared(_ list: PreparedList?) {
        guard let url = preparedURL else { return }
        guard let list else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(list).write(to: url, options: .atomic)
            } catch {
                AppLog.error("✨ FOR YOU: could not save prepared list — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Build

    private enum Outcome {
        case success([SceneRecommendation], seeds: Int)
        case failure(String)
    }

    private struct Seed {
        let scene: Scene
        let weight: Double
    }

    private struct Profile {
        var performers: [String: Double] = [:]
        var performerNames: [String: String] = [:]
        var studios: [String: Double] = [:]
        var studioNames: [String: String] = [:]
        var tags: [String: Double] = [:]
        var tagNames: [String: String] = [:]

        var isEmpty: Bool { performers.isEmpty && studios.isEmpty && tags.isEmpty }

        /// Performers and studios: the strongest is 1. Tags: share of all watch weight that
        /// carried the tag, times its rarity — not scaled up, or the most common tag in the
        /// library ("Blowjob") would count as much as the favourite performer.
        mutating func normalize(totalWeight: Double) {
            func scaled(_ map: [String: Double]) -> [String: Double] {
                guard let top = map.values.max(), top > 0 else { return map }
                return map.mapValues { $0 / top }
            }
            performers = scaled(performers)
            studios = scaled(studios)
            if totalWeight > 0 { tags = tags.mapValues { $0 / totalWeight } }
        }

        func top(_ map: [String: Double], _ n: Int) -> [String] {
            map.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(n).map(\.key)
        }
    }

    private func build() async -> Outcome {
        let now = Date()
        let windowStart = now.addingTimeInterval(-Double(lookbackDays) * 86_400)

        #if !os(tvOS)
        // Related-tag bonus reads the shared Suggestions statistics when they exist.
        await AITagSuggestionManager.shared.loadIfNeeded()
        #endif

        let history: [HistoryRow]
        do {
            history = try await fetchHistory(since: windowStart)
        } catch {
            AppLog.error("✨ FOR YOU: history failed — \(error.localizedDescription)")
            return .failure("Could not read your watch history")
        }
        if Task.isCancelled { return .failure("Cancelled") }

        var seeds = history.compactMap { seed(from: $0, windowStart: windowStart, now: now) }
        var usedFallback = false
        if seeds.isEmpty {
            // Nothing played in the window: learn from all-time favourites instead.
            seeds = await fetchFavoriteSeeds()
            usedFallback = true
        }
        guard !seeds.isEmpty else { return .success([], seeds: 0) }

        let totalScenes = await loadTotalSceneCount()
        var profile = Profile()
        for seed in seeds {
            for performer in seed.scene.performers {
                profile.performers[performer.id, default: 0] += seed.weight
                profile.performerNames[performer.id] = performer.name
            }
            if let studio = seed.scene.studio {
                profile.studios[studio.id, default: 0] += seed.weight
                profile.studioNames[studio.id] = studio.name
            }
            for tag in seed.scene.tags ?? [] {
                let r = rarity(of: tag, totalScenes: totalScenes)
                profile.tags[tag.id, default: 0] += seed.weight * r * r
                profile.tagNames[tag.id] = tag.name
            }
        }
        profile.normalize(totalWeight: seeds.reduce(0) { $0 + $1.weight })
        guard !profile.isEmpty else { return .success([], seeds: seeds.count) }

        // Scenes played in the window are what the user just saw — never suggest them again.
        let recentlyPlayed = Set(history.map(\.scene.id))

        let topPerformers = profile.top(profile.performers, 8)
        let topStudios = profile.top(profile.studios, 4)
        let topTags = profile.top(profile.tags, 10)
        // The scenes the user engaged with most, one by one: unplayed scenes close to any of
        // them get their own factor ("Like …").
        var seenAnchor = Set<String>()
        let anchors = Array(seeds
            .sorted { $0.weight > $1.weight }
            .filter { seenAnchor.insert($0.scene.id).inserted }
            .prefix(similarWeight > 0 ? 6 : 0))
        let maxSeedWeight = anchors.first?.weight ?? 1

        async let profileCandidates = fetchCandidates(
            performerIds: performerWeight > 0 ? topPerformers : [],
            studioIds: studioWeight > 0 ? topStudios : [],
            tagIds: tagWeight > 0 ? topTags : [],
            includeFavorites: discovery == .favorites
        )
        async let anchorCandidates = fetchUnwatchedSimilar(to: anchors.map(\.scene), totalScenes: totalScenes)
        var candidates = await profileCandidates
        var candidateIds = Set(candidates.map(\.id))
        let anchorPool = await anchorCandidates
        for scene in anchorPool where candidateIds.insert(scene.id).inserted {
            candidates.append(scene)
        }
        if Task.isCancelled { return .failure("Cancelled") }

        #if !os(tvOS)
        let related = tagWeight > 0
            ? AITagSuggestionManager.shared.relatedTagWeights(for: topTags)
            : [:]
        #else
        let related: [String: Double] = [:]
        #endif

        let scored = candidates.compactMap { candidate -> SceneRecommendation? in
            guard !recentlyPlayed.contains(candidate.id) else { return nil }
            return score(candidate, profile: profile, related: related, anchors: anchors,
                         maxSeedWeight: maxSeedWeight, totalScenes: totalScenes, now: now)
        }
        // What the last list showed steps back, so the next one is a new list. Not excluded:
        // in a small library a strong match may still come back.
        let recentLists = Self.loadRecentPicks()
        let rotated = scored.map { item -> SceneRecommendation in
            guard let index = recentLists.firstIndex(where: { $0.contains(item.id) }) else { return item }
            let factor = index == 0 ? 0.3 : 0.55
            return SceneRecommendation(scene: item.scene, reason: item.reason,
                                       isUnwatched: item.isUnwatched, score: item.score * factor)
        }
        let picks = diversify(rotated)
        #if DEBUG
        for pick in picks {
            AppLog.debug("✨ FOR YOU pick: \(String(format: "%.2f", pick.score)) \(pick.isUnwatched ? "new" : "seen") \(pick.reason.label) — \(pick.scene.displayTitle ?? pick.id)")
        }
        #endif
        AppLog.debug("✨ FOR YOU: \(seeds.count) seeds\(usedFallback ? " (all-time)" : "") → \(candidates.count) candidates → \(picks.count) picks")
        return .success(picks, seeds: seeds.count)
    }

    /// Weight of one watched scene for the profile.
    private func seed(from row: HistoryRow, windowStart: Date, now: Date) -> Seed? {
        let scene = row.scene
        var plays = row.plays.filter { $0 >= windowStart }
        if plays.isEmpty, let last = scene.lastPlayedAt.flatMap(OCountHeatmapLoader.parseTimestamp), last >= windowStart {
            plays = [last]
        }
        let os = row.oStamps.filter { $0 >= windowStart }
        guard let lastEvent = (plays + os).max() else { return nil }

        // Recency: half-life of a third of the window — last week counts most in a month.
        let halfLife = max(2, Double(lookbackDays) / 3) * 86_400
        let age = max(0, now.timeIntervalSince(lastEvent))
        let recency = pow(0.5, age / halfLife)

        var engagement = 1.0
        engagement += 0.4 * Double(min(max(plays.count - 1, 0), 5))
        let oCount = row.hasOHistory ? os.count : ((scene.oCounter ?? 0) > 0 ? 1 : 0)
        engagement += 1.5 * oCountWeight * Double(min(oCount, 4))
        if let duration = scene.sceneDuration, duration > 0, let watched = scene.playDuration, watched > 0 {
            let perPlay = watched / Double(max(scene.playCount ?? plays.count, 1))
            engagement += 0.5 * min(1, perPlay / duration)
        }
        if let rating = scene.rating100 {
            if rating >= 80 {
                engagement += 0.6 * ratingWeight
            } else if rating <= 40 {
                // Rated low: watched, but not liked.
                engagement *= max(0.1, 1 - 0.7 * ratingWeight)
            }
        }
        return Seed(scene: scene, weight: recency * engagement)
    }

    private func score(
        _ candidate: Scene,
        profile: Profile,
        related: [String: Double],
        anchors: [Seed],
        maxSeedWeight: Double,
        totalScenes: Int,
        now: Date
    ) -> SceneRecommendation? {
        let playCount = candidate.playCount ?? 0
        let isUnwatched = playCount == 0 && candidate.lastPlayedAt == nil
        if discovery == .fresh && !isUnwatched { return nil }

        // Performer: best match counts fully, further ones add a little.
        let performerHits = candidate.performers
            .compactMap { p in profile.performers[p.id].map { (p, $0) } }
            .sorted { $0.1 > $1.1 }
        var performerScore = 0.0
        for (index, hit) in performerHits.enumerated() {
            performerScore += index == 0 ? hit.1 : hit.1 * 0.3
        }
        performerScore *= 3.0 * performerWeight

        var studioScore = 0.0
        if let studio = candidate.studio, let affinity = profile.studios[studio.id] {
            studioScore = affinity * 1.5 * studioWeight
        }

        let candidateTags = candidate.tags ?? []
        let tagHits = candidateTags
            .compactMap { t in profile.tags[t.id].map { (t, $0) } }
            .sorted { $0.1 > $1.1 }
        let tagScore = min(tagHits.reduce(0) { $0 + $1.1 }, 1.2) * 2.0 * tagWeight

        var relatedScore = 0.0
        var bestRelated: (tag: Tag, weight: Double)?
        if !related.isEmpty {
            for tag in candidateTags where profile.tags[tag.id] == nil {
                guard let weight = related[tag.id] else { continue }
                let w = weight * rarity(of: tag, totalScenes: totalScenes)
                relatedScore += w
                if w > (bestRelated?.weight ?? 0) { bestRelated = (tag, w) }
            }
            relatedScore = min(relatedScore, 1.0) * 0.6 * tagWeight
        }

        // Closeness to a single watched scene, scaled by how much that scene counted. Every
        // candidate here is unplayed in the window (played ones were dropped before).
        var similarScore = 0.0
        var similarAnchor: Scene?
        if similarWeight > 0 {
            for anchor in anchors {
                let closeness = similarity(candidate, to: anchor.scene, totalScenes: totalScenes)
                let value = closeness * (anchor.weight / max(maxSeedWeight, 0.0001))
                if value > similarScore {
                    similarScore = value
                    similarAnchor = anchor.scene
                }
            }
            similarScore *= 3.0 * similarWeight
        }

        var score = performerScore + studioScore + tagScore + relatedScore + similarScore
        guard score > 0 else { return nil }

        // Quality: the user's own rating of the candidate.
        if let rating = candidate.rating100 {
            score *= 1 + ratingWeight * (Double(rating) - 60) / 200
        }

        let oCounter = candidate.oCounter ?? 0
        let lastPlayed = candidate.lastPlayedAt.flatMap(OCountHeatmapLoader.parseTimestamp)
        let daysSincePlay = lastPlayed.map { now.timeIntervalSince($0) / 86_400 } ?? .infinity
        var isRediscover = false
        switch discovery {
        case .fresh:
            score *= 1.2
        case .balanced:
            // Never played and not played in the window weigh the same.
            if !isUnwatched {
                isRediscover = oCounter > 0 && daysSincePlay > 60
            }
        case .favorites:
            if isUnwatched {
                score *= 0.85
            } else {
                score *= 1 + 0.25 * oCountWeight * Double(min(oCounter, 4))
                if (candidate.rating100 ?? 0) >= 80 { score *= 1 + 0.2 * ratingWeight }
                isRediscover = daysSincePlay > 60
            }
        }

        // Launch-seeded jitter: close scores resolve differently on each app start.
        score *= 1 + 0.35 * Self.jitter(candidate.id)

        let reason: SceneRecommendation.Reason
        let factors: [(Double, SceneRecommendation.Reason?)] = [
            (performerScore, performerHits.first.map { .performer($0.0.name) }),
            (studioScore, candidate.studio.map { .studio($0.name) }),
            (tagScore, tagHits.first.map { .tag($0.0.name) }),
            (relatedScore, bestRelated.map { .relatedTag($0.tag.name) }),
            (similarScore, similarAnchor.map { .similarTo($0.displayTitle ?? "a scene you watched") }),
        ]
        let strongest = factors.filter { $0.1 != nil && $0.0 > 0 }.max { $0.0 < $1.0 }
        if isRediscover {
            reason = discovery == .favorites && oCounter > 0 ? .favorite : .rediscover
        } else if let found = strongest?.1 {
            reason = found
        } else {
            return nil
        }
        return SceneRecommendation(scene: candidate, reason: reason, isUnwatched: isUnwatched, score: score)
    }

    /// Greedy pick; each further scene sharing a performer, studio or reason with the picks
    /// so far loses ground.
    private func diversify(_ scored: [SceneRecommendation]) -> [SceneRecommendation] {
        var pool = scored
        var picks: [SceneRecommendation] = []
        var performerUses: [String: Int] = [:]
        var studioUses: [String: Int] = [:]
        var reasonUses: [String: Int] = [:]

        func adjusted(_ item: SceneRecommendation) -> Double {
            let performerPenalty = item.scene.performers
                .map { performerUses[$0.id] ?? 0 }.max() ?? 0
            let studioPenalty = item.scene.studio.map { studioUses[$0.id] ?? 0 } ?? 0
            let reasonPenalty = reasonUses[item.reason.label] ?? 0
            return item.score
                * pow(0.6, Double(performerPenalty))
                * pow(0.75, Double(studioPenalty))
                * pow(0.7, Double(reasonPenalty))
        }

        while picks.count < count, !pool.isEmpty {
            var bestIndex = 0
            var bestScore = -Double.infinity
            for (index, item) in pool.enumerated() {
                let value = adjusted(item)
                if value > bestScore || (value == bestScore && item.id < pool[bestIndex].id) {
                    bestScore = value
                    bestIndex = index
                }
            }
            let pick = pool.remove(at: bestIndex)
            picks.append(pick)
            for performer in pick.scene.performers { performerUses[performer.id, default: 0] += 1 }
            if let studio = pick.scene.studio { studioUses[studio.id, default: 0] += 1 }
            reasonUses[pick.reason.label, default: 0] += 1
        }
        return picks
    }

    // MARK: - Helpers

    /// 0…1: how close a candidate is to one watched scene. Shared performers weigh most,
    /// then shared rare tags, then the studio.
    private func similarity(_ candidate: Scene, to anchor: Scene, totalScenes: Int) -> Double {
        let anchorPerformers = Set(anchor.performers.map(\.id))
        let sharedPerformers = candidate.performers.filter { anchorPerformers.contains($0.id) }.count
        let performerPart = anchorPerformers.isEmpty ? 0 : min(Double(sharedPerformers), 2) / 2

        let anchorTags = anchor.tags ?? []
        let candidateTagIds = Set((candidate.tags ?? []).map(\.id))
        let anchorMass = anchorTags.reduce(0.0) { $0 + rarity(of: $1, totalScenes: totalScenes) }
        let sharedMass = anchorTags
            .filter { candidateTagIds.contains($0.id) }
            .reduce(0.0) { $0 + rarity(of: $1, totalScenes: totalScenes) }
        let tagPart = anchorMass > 0 ? sharedMass / anchorMass : 0

        let studioPart = (anchor.studio?.id != nil && anchor.studio?.id == candidate.studio?.id) ? 1.0 : 0

        return 0.5 * performerPart + 0.35 * tagPart + 0.15 * studioPart
    }

    /// Device-local (`SettingsTransfer.deviceLocalPrefixes`), one list per server.
    private static let lastPicksPrefix = "recommendations_last_picks_"

    private static var lastPicksKey: String? {
        ServerConfigManager.shared.activeConfig.map { "\(lastPicksPrefix)\($0.id)" }
    }

    /// The last lists shown, newest first.
    private static let rememberedLists = 3

    private static func loadRecentPicks() -> [Set<String>] {
        guard let key = lastPicksKey,
              let stored = UserDefaults.standard.array(forKey: key) as? [[String]] else { return [] }
        return stored.map(Set.init)
    }

    private static func saveRecentPicks(_ ids: [String], keeping previous: [Set<String>]) {
        guard let key = lastPicksKey, !ids.isEmpty else { return }
        let lists = [ids] + previous.prefix(rememberedLists - 1).map { Array($0) }
        UserDefaults.standard.set(lists, forKey: key)
    }

    /// New on every app start: candidate order and jitter change with it, so each launch brings
    /// a different list (and the remembered recent lists push their scenes back).
    private static let sessionSeed = Int.random(in: 0..<100_000_000)

    /// 0…1, stable for a scene within one app run.
    private static func jitter(_ id: String) -> Double {
        var hash: UInt64 = 1_469_598_103_934_665_603 ^ UInt64(truncatingIfNeeded: sessionSeed)
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Double(hash % 10_000) / 10_000
    }

    private var totalSceneCount: Int?

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
        // Without variables the client would send the bare string as the body.
        let response: Response? = try? await GraphQLClient.shared.execute(
            query: "{ stats { scene_count } }", variables: [:]
        )
        let count = response?.data?.stats.scene_count ?? 0
        if count > 0 { totalSceneCount = count }
        return count
    }

    // MARK: - Queries

    /// A watched scene plus its play and O stamps.
    private struct HistoryRow: Decodable {
        let scene: Scene
        let plays: [Date]
        let oStamps: [Date]
        /// The server sent `o_history` — otherwise O-Counts fall back to `o_counter`.
        let hasOHistory: Bool

        private enum Keys: String, CodingKey {
            case play_history, o_history
        }

        init(from decoder: Decoder) throws {
            scene = try Scene(from: decoder)
            let container = try decoder.container(keyedBy: Keys.self)
            let rawPlays = (try? container.decodeIfPresent([String].self, forKey: .play_history)) ?? nil
            let rawOs = (try? container.decodeIfPresent([String].self, forKey: .o_history)) ?? nil
            plays = (rawPlays ?? []).compactMap(OCountHeatmapLoader.parseTimestamp)
            oStamps = (rawOs ?? []).compactMap(OCountHeatmapLoader.parseTimestamp)
            hasOHistory = rawOs != nil
        }
    }

    private struct HistoryResponse: Decodable {
        struct DataBlock: Decodable {
            struct FindScenes: Decodable {
                let count: Int
                let scenes: [HistoryRow]
            }
            let findScenes: FindScenes?
        }
        let data: DataBlock?
    }

    private func fetchHistory(since start: Date) async throws -> [HistoryRow] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sceneFilter: [String: Any] = [
            "last_played_at": ["modifier": "GREATER_THAN", "value": formatter.string(from: start)]
        ]
        do {
            return try await pagedHistory(query: GraphQLQueries.queryWithFragments("findScenesRecommendHistory"),
                                          sceneFilter: sceneFilter)
        } catch {
            if Task.isCancelled { throw error }
            // Older servers without play_history / o_history: the candidate query has neither,
            // and the seed falls back to last_played_at and o_counter.
            AppLog.debug("✨ FOR YOU: history query without stamps — \(error.localizedDescription)")
            return try await pagedHistory(query: GraphQLQueries.queryWithFragments("findScenesRecommendCandidates"),
                                          sceneFilter: sceneFilter)
        }
    }

    private func pagedHistory(query: String, sceneFilter: [String: Any]) async throws -> [HistoryRow] {
        var rows: [HistoryRow] = []
        for page in 1...Self.historyMaxPages {
            let response: HistoryResponse = try await GraphQLClient.shared.execute(
                query: query,
                variables: [
                    "filter": [
                        "page": page,
                        "per_page": Self.historyPageSize,
                        "sort": "last_played_at",
                        "direction": "DESC"
                    ],
                    "scene_filter": sceneFilter
                ]
            )
            guard let block = response.data?.findScenes else {
                throw GraphQLNetworkError.graphQLError(message: "No data")
            }
            rows.append(contentsOf: block.scenes)
            if block.scenes.count < Self.historyPageSize || rows.count >= block.count { break }
        }
        return rows
    }

    /// Cold start: scenes with O-Counts or high ratings, weighted lower than real plays.
    private func fetchFavoriteSeeds() async -> [Seed] {
        async let byO = runCandidateQuery(
            filter: ["o_counter": ["value": 0, "modifier": "GREATER_THAN"]],
            sort: "o_counter", perPage: 60
        )
        async let byRating = runCandidateQuery(
            filter: ["rating100": ["value": 79, "modifier": "GREATER_THAN"]],
            sort: "rating", perPage: 60
        )
        var seen = Set<String>()
        var seeds: [Seed] = []
        for scene in await byO + byRating where seen.insert(scene.id).inserted {
            var weight = 0.5 + 0.3 * oCountWeight * Double(min(scene.oCounter ?? 0, 4))
            if (scene.rating100 ?? 0) >= 80 { weight += 0.4 * ratingWeight }
            seeds.append(Seed(scene: scene, weight: weight))
        }
        return seeds
    }

    private func fetchCandidates(
        performerIds: [String],
        studioIds: [String],
        tagIds: [String],
        includeFavorites: Bool
    ) async -> [Scene] {
        let randomSort = "random_\(Self.sessionSeed)"
        var clauses: [(filter: [String: Any], sort: String)] = []
        if !performerIds.isEmpty {
            clauses.append((["performers": ["value": performerIds, "modifier": "INCLUDES"]], randomSort))
        }
        if !studioIds.isEmpty {
            clauses.append((["studios": ["value": studioIds, "modifier": "INCLUDES", "depth": 0]], randomSort))
        }
        if !tagIds.isEmpty {
            clauses.append((["tags": ["value": tagIds, "modifier": "INCLUDES", "depth": 0]], randomSort))
        }
        if includeFavorites {
            clauses.append((["o_counter": ["value": 0, "modifier": "GREATER_THAN"]], randomSort))
        }
        guard !clauses.isEmpty else { return [] }

        var merged: [Scene] = []
        var seen = Set<String>()
        await withTaskGroup(of: [Scene].self) { group in
            for clause in clauses {
                group.addTask {
                    await self.runCandidateQuery(filter: clause.filter, sort: clause.sort,
                                                 perPage: Self.candidatesPerQuery)
                }
            }
            for await result in group {
                for scene in result where seen.insert(scene.id).inserted {
                    merged.append(scene)
                }
            }
        }
        return merged
    }

    /// Unplayed scenes per anchor: its performers, and its rarest tags together. Makes sure scenes
    /// close to a single watched one are in the pool even when the profile queries miss them.
    private func fetchUnwatchedSimilar(to anchors: [Scene], totalScenes: Int) async -> [Scene] {
        guard !anchors.isEmpty else { return [] }
        // New only asks the server for unplayed scenes; the other modes take any and drop the
        // ones played in the window afterwards.
        let onlyUnplayed = discovery == .fresh
        func scoped(_ filter: [String: Any]) -> [String: Any] {
            guard onlyUnplayed else { return filter }
            return filter.merging(["play_count": ["value": 0, "modifier": "EQUALS"]]) { $1 }
        }
        var filters: [[String: Any]] = []
        for anchor in anchors {
            let performerIds = anchor.performers.map(\.id)
            if !performerIds.isEmpty {
                filters.append(scoped([
                    "performers": ["value": performerIds, "modifier": "INCLUDES"]
                ]))
            }
            let rareTags = (anchor.tags ?? [])
                .sorted { rarity(of: $0, totalScenes: totalScenes) > rarity(of: $1, totalScenes: totalScenes) }
                .prefix(3)
                .map(\.id)
            if rareTags.count >= 2 {
                filters.append(scoped([
                    "tags": ["value": rareTags, "modifier": "INCLUDES_ALL", "depth": 0]
                ]))
            }
        }
        let sort = "random_\(Self.sessionSeed)"
        var merged: [Scene] = []
        var seen = Set<String>()
        await withTaskGroup(of: [Scene].self) { group in
            for filter in filters {
                group.addTask { await self.runCandidateQuery(filter: filter, sort: sort, perPage: 40) }
            }
            for await result in group {
                for scene in result where seen.insert(scene.id).inserted { merged.append(scene) }
            }
        }
        return merged
    }

    private func runCandidateQuery(filter: [String: Any], sort: String, perPage: Int) async -> [Scene] {
        do {
            let response: AltScenesResponse = try await GraphQLClient.shared.execute(
                query: GraphQLQueries.queryWithFragments("findScenesRecommendCandidates"),
                variables: [
                    "filter": ["page": 1, "per_page": perPage, "sort": sort, "direction": "DESC"],
                    "scene_filter": filter
                ]
            )
            return response.data?.findScenes?.scenes ?? []
        } catch {
            AppLog.error("✨ FOR YOU: candidate query failed — \(error.localizedDescription)")
            return []
        }
    }
}

#endif
