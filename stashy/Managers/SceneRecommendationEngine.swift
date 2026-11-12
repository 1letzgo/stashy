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
            case .similarTo(let title): return tr("like_arg", title)
            case .performer(let name): return tr("more_with_arg", name)
            case .studio(let name): return tr("more_from_arg", name)
            case .tag(let name): return tr("you_like_arg", name)
            case .relatedTag(let name): return tr("goes_with_your_tags_arg", name)
            case .rediscover: return tr("rediscover")
            case .favorite: return tr("one_of_your_favorites")
            }
        }

        var shortLabel: String {
            switch self {
            case .performer(let name): return name
            case .studio(let name): return name
            case .tag(let name): return name
            case .relatedTag(let name): return name
            case .rediscover: return tr("rediscover")
            case .favorite: return tr("favourite")
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
        case .fresh: return tr("new_only")
        case .balanced: return tr("balanced")
        case .favorites: return tr("favorites")
        }
    }

    var detail: String {
        switch self {
        case .fresh: return tr("hint_only_scenes_you_have_never")
        case .balanced: return tr("hint_unplayed_scenes_and_scenes_you")
        case .favorites: return tr("hint_scenes_with_o_counts_or")
        }
    }
}

/// One performer, studio or tag the user turned up, down or off for For You
/// (Settings › For You › Adjustments, or the ··· menu below a For You card). Ids are the server's,
/// so the list is kept per server.
struct RecommendationAdjustment: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case performer
        case studio
        case tag

        var id: String { rawValue }

        var title: String {
            switch self {
            case .performer: return tr("performers")
            case .studio: return tr("studios")
            case .tag: return tr("tags")
            }
        }

        var addTitle: String {
            switch self {
            case .performer: return tr("action_add_performer")
            case .studio: return tr("action_add_studio")
            case .tag: return tr("action_add_tag")
            }
        }

        var icon: String {
            switch self {
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            }
        }
    }

    let kind: Kind
    let itemId: String
    var name: String
    /// 0 hides it; below 1 fewer scenes with it, above 1 more.
    var factor: Double

    var id: String { "\(kind.rawValue):\(itemId)" }
    var isHidden: Bool { factor < RecommendationAdjustment.hiddenBelow }

    static let range: ClosedRange<Double> = 0...3
    static let hiddenBelow = 0.05
    /// The card menu's steps.
    static let less = 0.5
    static let more = 2.0

    static func label(_ factor: Double) -> String {
        factor < hiddenBelow ? tr("hidden") : String(format: "%.1f×", factor)
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
        static let enabled = "recommendations_enabled"
        /// Per server: `recommendations_adjustments_<serverID>`, JSON.
        static let adjustmentsPrefix = "recommendations_adjustments_"
    }

    static let lookbackChoices = [7, 14, 30, 60, 90]
    static let countRange = 5...10
    /// The For You sort of the Scenes list shows this many; Home shows the first `count`.
    nonisolated static let listLimit = 25
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
    /// The user's own switch for the row (Settings › Recommendations). On by default.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    // MARK: Adjustments

    /// The user's per-item adjustments for the active server.
    @Published private(set) var adjustments: [RecommendationAdjustment] = []

    func adjustment(_ kind: RecommendationAdjustment.Kind, _ itemId: String) -> RecommendationAdjustment? {
        adjustments.first { $0.kind == kind && $0.itemId == itemId }
    }

    /// Adds or changes one; a new one goes to the top of its list.
    func setAdjustment(_ kind: RecommendationAdjustment.Kind, id itemId: String, name: String, factor: Double) {
        let value = min(max(factor, RecommendationAdjustment.range.lowerBound), RecommendationAdjustment.range.upperBound)
        if let index = adjustments.firstIndex(where: { $0.kind == kind && $0.itemId == itemId }) {
            guard adjustments[index].factor != value || adjustments[index].name != name else { return }
            adjustments[index].factor = value
            adjustments[index].name = name
        } else {
            adjustments.insert(RecommendationAdjustment(kind: kind, itemId: itemId, name: name, factor: value), at: 0)
        }
        saveAdjustments()
    }

    func removeAdjustment(_ kind: RecommendationAdjustment.Kind, id itemId: String) {
        let before = adjustments.count
        adjustments.removeAll { $0.kind == kind && $0.itemId == itemId }
        if adjustments.count != before { saveAdjustments() }
    }

    func removeAllAdjustments() {
        guard !adjustments.isEmpty else { return }
        adjustments = []
        saveAdjustments()
    }

    /// From a card's menu: the change shows now. A hidden item takes its cards off the row at
    /// once, then a new list is built (the row keeps its cards meanwhile).
    func applyAdjustmentsNow() {
        let adjust = Adjust(adjustments)
        let kept = recommendations.filter { !adjust.hides($0.scene) }
        if kept.count != recommendations.count { recommendations = kept }
        rebuild()
    }

    private static var adjustmentsKey: String? {
        ServerConfigManager.shared.activeConfig.map { "\(Keys.adjustmentsPrefix)\($0.id)" }
    }

    private static func loadAdjustments() -> [RecommendationAdjustment] {
        guard let key = adjustmentsKey, let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([RecommendationAdjustment].self, from: data) else { return [] }
        return list
    }

    private func saveAdjustments() {
        isStale = true
        prepared = nil
        guard let key = Self.adjustmentsKey else { return }
        if adjustments.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(adjustments), let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: key)
        }
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

    /// Tag Suggestions or Similar Scenes is on: the statistics the row draws on are there.
    @Published private(set) var hasStatistics = false
    /// The row is shown: the user's switch is on and so is Tag Suggestions or Similar Scenes.
    /// stashy+ is checked separately (`isAvailable`, `HomeView`).
    @Published private(set) var isFeatureOn = false {
        didSet { Self.isFeatureOnNow = isFeatureOn }
    }
    /// `isFeatureOn` for code off the main actor (the scene sort list).
    nonisolated(unsafe) static var isFeatureOnNow = false

    var isAvailable: Bool { StashyPlusManager.isUnlockedNow && isFeatureOn }

    private var cancellables = Set<AnyCancellable>()

    // MARK: Private

    private var buildTask: Task<Void, Never>?
    /// Builds the list for the next app start (or the next refresh) in the background.
    private var prepareTask: Task<Void, Never>?
    /// The next list, ready to show; mirrored to disk per server so a cold start shows it at once.
    private var prepared: PreparedList?
    private var preparedLoadedFor: String?
    /// Settings changed since the last build: the next list (pull to refresh, Refresh, app start)
    /// is built fresh instead of taking the prepared one.
    private var isStale = false
    private var generation = 0
    /// A tag on almost every scene still says a little.
    nonisolated private static let minRarity = 0.15

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

        isEnabled = d.object(forKey: Keys.enabled) as? Bool ?? true
        adjustments = Self.loadAdjustments()
        hasStatistics = AITagSuggestionManager.shared.isEnabled || SimilarScenesFinder.shared.isEnabled
        isFeatureOn = hasStatistics && isEnabled
        Self.isFeatureOnNow = isFeatureOn
        let statistics = AITagSuggestionManager.shared.$isEnabled
            .combineLatest(SimilarScenesFinder.shared.$isEnabled)
            .map { $0 || $1 }
        statistics
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.hasStatistics = $0 }
            .store(in: &cancellables)
        statistics
            .combineLatest($isEnabled)
            .map { $0 && $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                guard let self else { return }
                self.isFeatureOn = on
                if !on { self.reset() }
            }
            .store(in: &cancellables)

        // A finished statistics build is a new scene index: the next list reads it, and a row
        // still waiting for the first build gets its list now.
        AITagSuggestionManager.shared.$lastBuiltAt
            .dropFirst()
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isStale = true
                self.prepared = nil
                if self.recommendations.isEmpty { self.rebuild() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }

        SceneLiveChange.observeForever { [weak self] change in self?.applyLive(change) }
    }

    /// A scene changed elsewhere in the app: the cards already shown follow in place (progress,
    /// plays, O count, metadata, cover) and a deleted scene leaves. No rebuild, no new order.
    private func applyLive(_ change: SceneLiveChange) {
        guard recommendations.contains(where: { $0.scene.id == change.sceneId }) else { return }
        recommendations = recommendations.compactMap { item in
            guard item.scene.id == change.sceneId else { return item }
            guard let scene = change.applied(to: item.scene) else { return nil }
            return SceneRecommendation(scene: scene, reason: item.reason, isUnwatched: item.isUnwatched, score: item.score)
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
        // A new server has its own ids, so its own adjustments.
        adjustments = Self.loadAdjustments()
    }

    /// Within a session the list stays as it is: only an empty row builds one. A new list comes
    /// at the next app start, on pull to refresh or with Refresh in Settings; changed settings
    /// apply from then on.
    func refreshIfNeeded() {
        guard isAvailable else { return }
        if buildTask != nil { return }
        if state == .ready || state == .noHistory { return }
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

    /// What Home shows: the first `count` of the list.
    var homeItems: [SceneRecommendation] { Array(recommendations.prefix(count)) }

    /// The For You sort of the Scenes list: the current list (up to `listLimit`), built first
    /// when there is none yet.
    func scenesForList() async -> [Scene] {
        if recommendations.isEmpty { await rebuildAndWait() }
        return recommendations.map(\.scene)
    }

    /// Pull to refresh on Home: a new list, returning once it is on screen so the spinner
    /// stays until then (a visible build takes a few seconds).
    func rebuildAndWait() async {
        rebuild()
        await buildTask?.value
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
        Self.saveRecentPicks(list.items.prefix(count).map(\.id), keeping: Self.loadRecentPicks())
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
                    Self.saveRecentPicks(picks.prefix(self.count).map(\.id), keeping: Self.loadRecentPicks())
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
            + "|" + adjustments.map { "\($0.id)=\($0.factor)" }.sorted().joined(separator: ",")
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

    nonisolated private enum Outcome {
        case success([SceneRecommendation], seeds: Int)
        case failure(String)
    }

    /// What scoring needs of one scene — from the local index or from a server scene.
    nonisolated private struct RecItem {
        let id: String
        let title: String?
        let performers: [(id: String, name: String)]
        let studio: (id: String, name: String)?
        let tagIds: [String]
        let playCount: Int
        let oCounter: Int
        let rating: Int?
        let lastPlayedAt: Date?
        let playDuration: Double?
        let duration: Double?

        init(entry: LocalSceneIndex.Entry, performerNames: [String: String], studioNames: [String: String]) {
            id = entry.id
            title = entry.title
            performers = entry.p.map { ($0, performerNames[$0] ?? tr("this_performer")) }
            studio = entry.s.map { ($0, studioNames[$0] ?? tr("this_studio")) }
            tagIds = entry.t
            playCount = entry.pc
            oCounter = entry.oc
            rating = entry.r
            lastPlayedAt = entry.lp
            playDuration = entry.pd
            duration = entry.d
        }

        var isUnwatched: Bool { playCount == 0 && lastPlayedAt == nil }
    }

    /// Tag names and how many scenes carry each tag, for labels and the rarity weighting.
    nonisolated private struct Vocabulary {
        var tagNames: [String: String] = [:]
        var tagScenes: [String: Int] = [:]
        var totalScenes = 0

        func rarity(_ tagId: String) -> Double {
            let df = max(1, tagScenes[tagId] ?? 1)
            guard totalScenes > 1, df < totalScenes else { return SceneRecommendationEngine.minRarity }
            let idf = log(Double(totalScenes) / Double(df)) / log(Double(totalScenes))
            return min(1.0, max(SceneRecommendationEngine.minRarity, idf))
        }
    }

    nonisolated private struct Seed {
        let item: RecItem
        let weight: Double
    }

    nonisolated private struct Scored {
        let item: RecItem
        let reason: SceneRecommendation.Reason
        let score: Double
    }

    nonisolated private struct Profile {
        var performers: [String: Double] = [:]
        var performerNames: [String: String] = [:]
        var studios: [String: Double] = [:]
        var tags: [String: Double] = [:]

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

    /// One watched scene, seen as an anchor: its performers, studio and tags with their rarity.
    nonisolated private struct Anchor {
        let item: RecItem
        let weight: Double
        let performerIds: Set<String>
        let tagMass: [String: Double]
        let totalMass: Double
    }

    private func build() async -> Outcome {
        Self.sessionSeed = Int.random(in: 0..<100_000_000)
        // Everything comes from the Suggestions statistics on this device: the scene index for
        // the candidates and their cards, the tag pairs for the related-tag bonus.
        await AITagSuggestionManager.shared.loadIfNeeded()
        guard let index = await AITagSuggestionManager.shared.sceneIndex(), !index.scenes.isEmpty else {
            return .failure(Self.preparingMessage)
        }
        let cfg = makeBuildConfig()
        // Scoring the whole library takes a noticeable moment: off the main thread, or Home
        // stalls while it scrolls right after start (this runs once more for the next list).
        return await Task.detached(priority: .userInitiated) {
            Self.buildLocal(index, cfg)
        }.value
    }

    /// Everything a build reads from the engine and the statistics, copied on the main actor so
    /// the scoring can run elsewhere.
    nonisolated private struct BuildConfig: @unchecked Sendable {
        let lookbackDays: Int
        let count: Int
        let discovery: RecommendationDiscovery
        let performerWeight: Double
        let studioWeight: Double
        let tagWeight: Double
        let oCountWeight: Double
        let ratingWeight: Double
        let similarWeight: Double
        let adjust: Adjust
        let sessionSeed: Int
        let recentLists: [Set<String>]
        let knownTagNames: [String: String]
        let pairCounts: [String: [String: Int]]
        let tagTotals: [String: Int]

        /// Same as `AITagSuggestionManager.relatedTagWeights`, on the copied statistics.
        func relatedTagWeights(_ tagIds: [String]) -> [String: Double] {
            var weights: [String: Double] = [:]
            for tagId in tagIds {
                guard let partners = pairCounts[tagId] else { continue }
                let total = Double(tagTotals[tagId] ?? 0)
                guard total > 0 else { continue }
                for (partner, count) in partners where !tagIds.contains(partner) {
                    weights[partner] = max(weights[partner] ?? 0, min(1.0, Double(count) / total))
                }
            }
            return weights
        }
    }

    private func makeBuildConfig() -> BuildConfig {
        #if !os(tvOS)
        let manager = AITagSuggestionManager.shared
        var names: [String: String] = [:]
        for tag in manager.knownTags { names[tag.id] = tag.name }
        let stats = manager.relatedTagStatistics
        #else
        let names: [String: String] = [:]
        let stats: (pairs: [String: [String: Int]], totals: [String: Int]) = ([:], [:])
        #endif
        return BuildConfig(
            lookbackDays: lookbackDays, count: count, discovery: discovery,
            performerWeight: performerWeight, studioWeight: studioWeight, tagWeight: tagWeight,
            oCountWeight: oCountWeight, ratingWeight: ratingWeight, similarWeight: similarWeight,
            adjust: Adjust(adjustments), sessionSeed: Self.sessionSeed,
            recentLists: Self.loadRecentPicks(), knownTagNames: names,
            pairCounts: stats.pairs, tagTotals: stats.totals
        )
    }

    /// Shown until the first statistics build on this device is done.
    static var preparingMessage: String { tr("hint_getting_your_library_ready_on") }

    /// The whole library from the device's scene index — no server request.
    nonisolated private static func buildLocal(_ index: LocalSceneIndex, _ cfg: BuildConfig) -> Outcome {
        let started = Date()
        let now = Date()
        let windowStart = now.addingTimeInterval(-Double(cfg.lookbackDays) * 86_400)

        let entries = index.scenes.filter { $0.scene != nil }
        let items = entries.map {
            RecItem(entry: $0, performerNames: index.performerNames, studioNames: index.studioNames)
        }
        var vocabulary = Vocabulary()
        vocabulary.tagNames = cfg.knownTagNames
        vocabulary.tagNames.merge(index.tagNames ?? [:]) { _, indexed in indexed }
        vocabulary.totalScenes = items.count
        for item in items {
            for tagId in item.tagIds { vocabulary.tagScenes[tagId, default: 0] += 1 }
        }

        var seeds = items.compactMap { item -> Seed? in
            guard let last = item.lastPlayedAt, last >= windowStart else { return nil }
            return Self.seed(item, plays: [last], oStamps: nil, windowStart: windowStart, now: now, cfg: cfg)
        }
        var usedFallback = false
        if seeds.isEmpty {
            seeds = Self.favoriteSeeds(from: items, cfg: cfg)
            usedFallback = true
        }
        guard !seeds.isEmpty else { return .success([], seeds: 0) }
        let recentlyPlayed = Set(items.filter { ($0.lastPlayedAt ?? .distantPast) >= windowStart }.map(\.id))

        let picks = Self.rank(items, seeds: seeds, excluding: recentlyPlayed, vocabulary: vocabulary,
                              adjust: cfg.adjust, now: now, cfg: cfg)
        let scenes = Dictionary(entries.compactMap { e in e.scene.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let recommendations = picks.compactMap { pick -> SceneRecommendation? in
            guard let scene = scenes[pick.item.id] else { return nil }
            return SceneRecommendation(scene: scene, reason: pick.reason,
                                       isUnwatched: pick.item.isUnwatched, score: pick.score)
        }
        AppLog.debug("✨ FOR YOU: \(seeds.count) seeds\(usedFallback ? " (all-time)" : "") → \(items.count) scenes → \(recommendations.count) picks in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        return .success(recommendations, seeds: seeds.count)
    }

    nonisolated private static func makeProfile(_ seeds: [Seed], vocabulary: Vocabulary, adjust: Adjust) -> Profile {
        var profile = Profile()
        for seed in seeds {
            // A hidden item learns nothing from the history; the rest of its scene still counts.
            for performer in seed.item.performers where !adjust.hidesPerformer(performer.id) {
                profile.performers[performer.id, default: 0] += seed.weight
                profile.performerNames[performer.id] = performer.name
            }
            if let studio = seed.item.studio, !adjust.hidesStudio(studio.id) {
                profile.studios[studio.id, default: 0] += seed.weight
            }
            for tagId in seed.item.tagIds where !adjust.hidesTag(tagId) {
                let r = vocabulary.rarity(tagId)
                profile.tags[tagId, default: 0] += seed.weight * r * r
            }
        }
        profile.normalize(totalWeight: seeds.reduce(0) { $0 + $1.weight })
        adjust.boost(&profile)
        return profile
    }

    /// The user's adjustments, as lookups for one build.
    nonisolated private struct Adjust {
        var performers: [String: Double] = [:]
        var studios: [String: Double] = [:]
        var tags: [String: Double] = [:]

        init(_ list: [RecommendationAdjustment]) {
            for entry in list {
                switch entry.kind {
                case .performer: performers[entry.itemId] = entry.factor
                case .studio: studios[entry.itemId] = entry.factor
                case .tag: tags[entry.itemId] = entry.factor
                }
            }
        }

        var isEmpty: Bool { performers.isEmpty && studios.isEmpty && tags.isEmpty }

        func hidesPerformer(_ id: String) -> Bool { (performers[id] ?? 1) < RecommendationAdjustment.hiddenBelow }
        func hidesStudio(_ id: String) -> Bool { (studios[id] ?? 1) < RecommendationAdjustment.hiddenBelow }
        func hidesTag(_ id: String) -> Bool { (tags[id] ?? 1) < RecommendationAdjustment.hiddenBelow }

        func hides(_ item: RecItem) -> Bool {
            guard !isEmpty else { return false }
            return item.performers.contains { hidesPerformer($0.id) }
                || item.studio.map { hidesStudio($0.id) } == true
                || item.tagIds.contains { hidesTag($0) }
        }

        func hides(_ scene: Scene) -> Bool {
            guard !isEmpty else { return false }
            return scene.performers.contains { hidesPerformer($0.id) }
                || scene.studio.map { hidesStudio($0.id) } == true
                || (scene.tags ?? []).contains { hidesTag($0.id) }
        }

        /// Every adjusted item on the scene multiplies its score.
        func multiplier(_ item: RecItem) -> Double {
            guard !isEmpty else { return 1 }
            var value = 1.0
            for performer in item.performers { value *= performers[performer.id] ?? 1 }
            if let studio = item.studio { value *= studios[studio.id] ?? 1 }
            for tagId in item.tagIds { value *= tags[tagId] ?? 1 }
            return min(max(value, 0.05), 8)
        }

        /// Turned up: in the profile even without plays, so scenes with it become candidates
        /// the history alone would not bring (3× counts like the favourite performer).
        func boost(_ profile: inout Profile) {
            for (id, factor) in performers where factor > 1 {
                profile.performers[id] = max(profile.performers[id] ?? 0, min(1, (factor - 1) / 2))
            }
            for (id, factor) in studios where factor > 1 {
                profile.studios[id] = max(profile.studios[id] ?? 0, min(1, (factor - 1) / 2))
            }
            for (id, factor) in tags where factor > 1 {
                profile.tags[id] = max(profile.tags[id] ?? 0, 0.25 * min(1, (factor - 1) / 2))
            }
        }
    }

    /// Scores every candidate, steps back what the last lists showed and picks a diverse list.
    nonisolated private static func rank(_ candidates: [RecItem], seeds: [Seed], excluding recentlyPlayed: Set<String>,
                                         vocabulary: Vocabulary, adjust: Adjust, now: Date, cfg: BuildConfig) -> [Scored] {
        let profile = Self.makeProfile(seeds, vocabulary: vocabulary, adjust: adjust)
        guard !profile.isEmpty else { return [] }
        let topTags = profile.top(profile.tags, 10)
        // The scenes the user engaged with most, one by one: scenes close to any of them get
        // their own factor ("Like …").
        var seenAnchor = Set<String>()
        let anchors = seeds
            .sorted { $0.weight > $1.weight }
            .filter { !adjust.hides($0.item) && seenAnchor.insert($0.item.id).inserted }
            .prefix(cfg.similarWeight > 0 ? 6 : 0)
            .map { seed -> Anchor in
                var mass: [String: Double] = [:]
                for tagId in seed.item.tagIds { mass[tagId] = vocabulary.rarity(tagId) }
                return Anchor(item: seed.item, weight: seed.weight, performerIds: Set(seed.item.performers.map(\.id)),
                              tagMass: mass, totalMass: mass.values.reduce(0, +))
            }
        let maxSeedWeight = anchors.first?.weight ?? 1

        let related = cfg.tagWeight > 0 ? cfg.relatedTagWeights(topTags) : [:]

        let scored = candidates.compactMap { candidate -> Scored? in
            guard !recentlyPlayed.contains(candidate.id), !adjust.hides(candidate) else { return nil }
            guard let scored = Self.score(candidate, profile: profile, related: related, anchors: anchors,
                                     maxSeedWeight: maxSeedWeight, vocabulary: vocabulary, now: now, cfg: cfg) else { return nil }
            let factor = adjust.multiplier(candidate)
            return factor == 1 ? scored : Scored(item: scored.item, reason: scored.reason, score: scored.score * factor)
        }
        // What the last lists showed steps back, so the next one is a new list. Not excluded:
        // in a small library a strong match may still come back.
        let recentLists = cfg.recentLists
        let rotated = scored.map { item -> Scored in
            guard let index = recentLists.firstIndex(where: { $0.contains(item.item.id) }) else { return item }
            return Scored(item: item.item, reason: item.reason, score: item.score * (index == 0 ? 0.3 : 0.55))
        }
        let picks = Self.diversify(rotated, cfg: cfg)
        #if DEBUG
        for pick in picks.prefix(cfg.count) {
            AppLog.debug("✨ FOR YOU pick: \(String(format: "%.2f", pick.score)) \(pick.item.isUnwatched ? "new" : "seen") \(pick.reason.label) — \(pick.item.title ?? pick.item.id)")
        }
        #endif
        return picks
    }

    /// Weight of one watched scene for the profile.
    nonisolated private static func seed(_ item: RecItem, plays allPlays: [Date], oStamps: [Date]?, windowStart: Date, now: Date, cfg: BuildConfig) -> Seed? {
        var plays = allPlays.filter { $0 >= windowStart }
        if plays.isEmpty, let last = item.lastPlayedAt, last >= windowStart {
            plays = [last]
        }
        let os = (oStamps ?? []).filter { $0 >= windowStart }
        guard let lastEvent = (plays + os).max() else { return nil }

        // Recency: half-life of a third of the window — last week counts most in a month.
        let halfLife = max(2, Double(cfg.lookbackDays) / 3) * 86_400
        let age = max(0, now.timeIntervalSince(lastEvent))
        let recency = pow(0.5, age / halfLife)

        var engagement = 1.0
        // Without play stamps (local index) the play count stands in for the replays.
        let replays = oStamps == nil && plays.count <= 1 ? min(item.playCount - 1, 3) : plays.count - 1
        engagement += 0.4 * Double(min(max(replays, 0), 5))
        let oCount = oStamps != nil ? os.count : (item.oCounter > 0 ? 1 : 0)
        engagement += 1.5 * cfg.oCountWeight * Double(min(oCount, 4))
        if let duration = item.duration, duration > 0, let watched = item.playDuration, watched > 0 {
            let perPlay = watched / Double(max(item.playCount, plays.count, 1))
            engagement += 0.5 * min(1, perPlay / duration)
        }
        if let rating = item.rating {
            if rating >= 80 {
                engagement += 0.6 * cfg.ratingWeight
            } else if rating <= 40 {
                // Rated low: watched, but not liked.
                engagement *= max(0.1, 1 - 0.7 * cfg.ratingWeight)
            }
        }
        return Seed(item: item, weight: recency * engagement)
    }

    /// Cold start: scenes with O-Counts or high ratings, weighted lower than real plays.
    nonisolated private static func favoriteSeeds(from items: [RecItem], cfg: BuildConfig) -> [Seed] {
        items
            .filter { $0.oCounter > 0 || ($0.rating ?? 0) >= 80 }
            .map { item -> Seed in
                var weight = 0.5 + 0.3 * cfg.oCountWeight * Double(min(item.oCounter, 4))
                if (item.rating ?? 0) >= 80 { weight += 0.4 * cfg.ratingWeight }
                return Seed(item: item, weight: weight)
            }
            .sorted { $0.weight > $1.weight }
            .prefix(120)
            .map { $0 }
    }

    nonisolated private static func score(
        _ candidate: RecItem,
        profile: Profile,
        related: [String: Double],
        anchors: [Anchor],
        maxSeedWeight: Double,
        vocabulary: Vocabulary,
        now: Date,
        cfg: BuildConfig
    ) -> Scored? {
        let isUnwatched = candidate.isUnwatched
        if cfg.discovery == .fresh && !isUnwatched { return nil }

        // Performer: best match counts fully, further ones add a little.
        let performerHits = candidate.performers
            .compactMap { p in profile.performers[p.id].map { (p, $0) } }
            .sorted { $0.1 > $1.1 }
        var performerScore = 0.0
        for (index, hit) in performerHits.enumerated() {
            performerScore += index == 0 ? hit.1 : hit.1 * 0.3
        }
        performerScore *= 3.0 * cfg.performerWeight

        var studioScore = 0.0
        if let studio = candidate.studio, let affinity = profile.studios[studio.id] {
            studioScore = affinity * 1.5 * cfg.studioWeight
        }

        let tagHits = candidate.tagIds
            .compactMap { t in profile.tags[t].map { (t, $0) } }
            .sorted { $0.1 > $1.1 }
        let tagScore = min(tagHits.reduce(0) { $0 + $1.1 }, 1.2) * 2.0 * cfg.tagWeight

        var relatedScore = 0.0
        var bestRelated: (tagId: String, weight: Double)?
        if !related.isEmpty {
            for tagId in candidate.tagIds where profile.tags[tagId] == nil {
                guard let weight = related[tagId] else { continue }
                let w = weight * vocabulary.rarity(tagId)
                relatedScore += w
                if w > (bestRelated?.weight ?? 0) { bestRelated = (tagId, w) }
            }
            relatedScore = min(relatedScore, 1.0) * 0.6 * cfg.tagWeight
        }

        // Closeness to a single watched scene, scaled by how much that scene counted.
        var similarScore = 0.0
        var similarAnchor: RecItem?
        if cfg.similarWeight > 0, !anchors.isEmpty {
            let candidatePerformers = candidate.performers.map(\.id)
            for anchor in anchors where anchor.item.id != candidate.id {
                let shared = candidatePerformers.filter { anchor.performerIds.contains($0) }.count
                let performerPart = anchor.performerIds.isEmpty ? 0 : min(Double(shared), 2) / 2
                let sharedMass = candidate.tagIds.reduce(0.0) { $0 + (anchor.tagMass[$1] ?? 0) }
                let tagPart = anchor.totalMass > 0 ? sharedMass / anchor.totalMass : 0
                let studioPart = (anchor.item.studio?.id != nil && anchor.item.studio?.id == candidate.studio?.id) ? 1.0 : 0
                let closeness = 0.5 * performerPart + 0.35 * tagPart + 0.15 * studioPart
                let value = closeness * (anchor.weight / max(maxSeedWeight, 0.0001))
                if value > similarScore {
                    similarScore = value
                    similarAnchor = anchor.item
                }
            }
            similarScore *= 3.0 * cfg.similarWeight
        }

        var score = performerScore + studioScore + tagScore + relatedScore + similarScore
        guard score > 0 else { return nil }

        // Quality: the user's own rating of the candidate.
        if let rating = candidate.rating {
            score *= 1 + cfg.ratingWeight * (Double(rating) - 60) / 200
        }

        let daysSincePlay = candidate.lastPlayedAt.map { now.timeIntervalSince($0) / 86_400 } ?? .infinity
        var isRediscover = false
        switch cfg.discovery {
        case .fresh:
            score *= 1.2
        case .balanced:
            // Never played and not played in the window weigh the same.
            if !isUnwatched {
                isRediscover = candidate.oCounter > 0 && daysSincePlay > 60
            }
        case .favorites:
            if isUnwatched {
                score *= 0.85
            } else {
                score *= 1 + 0.25 * cfg.oCountWeight * Double(min(candidate.oCounter, 4))
                if (candidate.rating ?? 0) >= 80 { score *= 1 + 0.2 * cfg.ratingWeight }
                isRediscover = daysSincePlay > 60
            }
        }

        // Per-build jitter: close scores resolve differently in every list.
        score *= 1 + 0.35 * Self.jitter(candidate.id, seed: cfg.sessionSeed)

        let tagName = { (id: String) in vocabulary.tagNames[id] ?? tr("this_tag") }
        let factors: [(Double, SceneRecommendation.Reason?)] = [
            (performerScore, performerHits.first.map { .performer($0.0.name) }),
            (studioScore, candidate.studio.map { .studio($0.name) }),
            (tagScore, tagHits.first.map { .tag(tagName($0.0)) }),
            (relatedScore, bestRelated.map { .relatedTag(tagName($0.tagId)) }),
            (similarScore, similarAnchor.map { .similarTo($0.title ?? tr("scene_you_watched")) }),
        ]
        let strongest = factors.filter { $0.1 != nil && $0.0 > 0 }.max { $0.0 < $1.0 }
        let reason: SceneRecommendation.Reason
        if isRediscover {
            reason = cfg.discovery == .favorites && candidate.oCounter > 0 ? .favorite : .rediscover
        } else if let found = strongest?.1 {
            reason = found
        } else {
            return nil
        }
        return Scored(item: candidate, reason: reason, score: score)
    }

    /// Greedy pick; each further scene sharing a performer, studio or reason with the picks
    /// so far loses ground.
    nonisolated private static func diversify(_ scored: [Scored], cfg: BuildConfig) -> [Scored] {
        // Only the best few hundred can make the list; the greedy pass is quadratic.
        var pool = Array(scored.sorted { $0.score > $1.score }.prefix(600))
        var picks: [Scored] = []
        var performerUses: [String: Int] = [:]
        var studioUses: [String: Int] = [:]
        var reasonUses: [String: Int] = [:]
        // Balanced keeps never-played and played-before scenes level: the pool holds far more
        // unplayed scenes, so equal scores alone would fill the list with NEW ones.
        var newPicks = 0
        var seenPicks = 0
        let balances = cfg.discovery == .balanced && pool.contains { !$0.item.isUnwatched }

        func adjusted(_ entry: Scored) -> Double {
            let performerPenalty = entry.item.performers.map { performerUses[$0.id] ?? 0 }.max() ?? 0
            let studioPenalty = entry.item.studio.map { studioUses[$0.id] ?? 0 } ?? 0
            let reasonPenalty = reasonUses[entry.reason.label] ?? 0
            let lead = balances ? (entry.item.isUnwatched ? newPicks - seenPicks : seenPicks - newPicks) : 0
            return entry.score
                * pow(0.5, Double(max(lead, 0)))
                * pow(0.6, Double(performerPenalty))
                * pow(0.75, Double(studioPenalty))
                * pow(0.7, Double(reasonPenalty))
        }

        while picks.count < max(cfg.count, Self.listLimit), !pool.isEmpty {
            var bestIndex = 0
            var bestScore = -Double.infinity
            for (index, entry) in pool.enumerated() {
                let value = adjusted(entry)
                if value > bestScore || (value == bestScore && entry.item.id < pool[bestIndex].item.id) {
                    bestScore = value
                    bestIndex = index
                }
            }
            let pick = pool.remove(at: bestIndex)
            picks.append(pick)
            for performer in pick.item.performers { performerUses[performer.id, default: 0] += 1 }
            if let studio = pick.item.studio { studioUses[studio.id, default: 0] += 1 }
            reasonUses[pick.reason.label, default: 0] += 1
            if pick.item.isUnwatched { newPicks += 1 } else { seenPicks += 1 }
        }
        return picks
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

    /// New for every build: candidate order and jitter change with it, so each list (app start,
    /// pull to refresh, Refresh in Settings) differs, and the remembered recent lists push their
    /// scenes back.
    private static var sessionSeed = Int.random(in: 0..<100_000_000)

    /// 0…1, stable for a scene within one build.
    nonisolated private static func jitter(_ id: String, seed: Int) -> Double {
        var hash: UInt64 = 1_469_598_103_934_665_603 ^ UInt64(truncatingIfNeeded: seed)
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Double(hash % 10_000) / 10_000
    }
}

#endif
