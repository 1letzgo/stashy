//
//  ForgottenFavoritesEngine.swift
//  stashy
//
//  stashy+ — "Forgotten Favorites" on Home: scenes among the most played or most O-Counted
//  that have not been played for a while. Worked out from the local scene index alone.
//

#if !os(tvOS)

import Foundation
import SwiftUI
import Combine

/// Which ranking makes a scene a favourite.
enum ForgottenFavoritesRanking: String, CaseIterable, Identifiable {
    case plays
    case oCount
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plays: return "Plays"
        case .oCount: return "O-Count"
        case .both: return "Both"
        }
    }

    var detail: String {
        switch self {
        case .plays: return "Favorites are your most played scenes."
        case .oCount: return "Favorites are your scenes with the highest O-Count."
        case .both: return "Favorites are your most played scenes and those with the highest O-Count."
        }
    }
}

/// One forgotten favourite and when it was last played.
struct ForgottenFavorite: Identifiable, Equatable {
    let scene: Scene
    let lastPlayed: Date?
    let plays: Int
    let oCount: Int

    var id: String { scene.id }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scene.id == rhs.scene.id && lhs.lastPlayed == rhs.lastPlayed
    }

    /// Below the card: how long it has been.
    var label: String {
        guard let lastPlayed else { return plays == 0 ? "Never played" : "Not played in a long time" }
        let days = max(0, Calendar.current.dateComponents([.day], from: lastPlayed, to: Date()).day ?? 0)
        switch days {
        case ..<60: return "Last played \(days) days ago"
        case ..<730: return "Last played \(days / 30) months ago"
        default: return "Last played \(days / 365) years ago"
        }
    }
}

@MainActor
final class ForgottenFavoritesEngine: ObservableObject {
    static let shared = ForgottenFavoritesEngine()

    enum State: Equatable {
        case idle
        case loading
        case ready
        /// No statistics build yet: the scene index does not exist.
        case preparing
    }

    enum Keys {
        static let enabled = "forgotten_favorites_enabled"
        static let days = "forgotten_favorites_days"
        static let pool = "forgotten_favorites_pool"
        static let ranking = "forgotten_favorites_ranking"
    }

    static let dayChoices = [30, 60, 90, 180, 365]
    static let poolChoices = [10, 25, 50, 100]
    /// At most this many cards in the row.
    static let rowLimit = 20

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var days: Int {
        didSet { UserDefaults.standard.set(days, forKey: Keys.days); settingsChanged() }
    }
    @Published var pool: Int {
        didSet { UserDefaults.standard.set(pool, forKey: Keys.pool); settingsChanged() }
    }
    @Published var ranking: ForgottenFavoritesRanking {
        didSet { UserDefaults.standard.set(ranking.rawValue, forKey: Keys.ranking); settingsChanged() }
    }

    var hasCustomSettings: Bool { days != 60 || pool != 25 || ranking != .both }

    func resetSettings() {
        days = 60
        pool = 25
        ranking = .both
    }

    @Published private(set) var items: [ForgottenFavorite] = [] { didSet { updateEmpty() } }
    @Published private(set) var state: State = .idle { didSet { updateEmpty() } }
    /// Built and nothing forgotten: Home leaves the row out (and gives the hero to the next row).
    @Published private(set) var isEmptyAndReady = false

    private func updateEmpty() {
        let empty = state == .ready && items.isEmpty
        if empty != isEmptyAndReady { isEmptyAndReady = empty }
    }
    /// How many scenes made the favourites pool — shown in Settings.
    @Published private(set) var poolCount = 0
    /// Tag Suggestions or Similar Scenes is on: the scene index is built.
    @Published private(set) var hasStatistics = false
    /// The row is shown: the user's switch and the statistics are on. stashy+ is checked apart.
    @Published private(set) var isFeatureOn = false

    var isAvailable: Bool { StashyPlusManager.isUnlockedNow && isFeatureOn }

    private var buildTask: Task<Void, Never>?
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let d = UserDefaults.standard
        isEnabled = d.object(forKey: Keys.enabled) as? Bool ?? true
        let storedDays = d.integer(forKey: Keys.days)
        days = Self.dayChoices.contains(storedDays) ? storedDays : 60
        let storedPool = d.integer(forKey: Keys.pool)
        pool = Self.poolChoices.contains(storedPool) ? storedPool : 25
        ranking = ForgottenFavoritesRanking(rawValue: d.string(forKey: Keys.ranking) ?? "") ?? .both

        hasStatistics = AITagSuggestionManager.shared.isEnabled || SimilarScenesFinder.shared.isEnabled
        isFeatureOn = hasStatistics && isEnabled
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

        // A new scene index fills a row still waiting for the first build.
        AITagSuggestionManager.shared.$lastBuiltAt
            .dropFirst()
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.items.isEmpty, self.state != .idle else { return }
                self.rebuild()
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

    /// A scene changed elsewhere in the app: the cards already shown follow in place and a
    /// deleted scene leaves. The row keeps its picks and order until the next rebuild.
    private func applyLive(_ change: SceneLiveChange) {
        guard items.contains(where: { $0.scene.id == change.sceneId }) else { return }
        items = items.compactMap { item in
            guard item.scene.id == change.sceneId else { return item }
            guard let scene = change.applied(to: item.scene) else { return nil }
            var plays = item.plays, oCount = item.oCount, lastPlayed = item.lastPlayed
            switch change {
            case .playAdded: plays += 1; lastPlayed = Date()
            case .oCounter(_, let count): oCount = count
            default: break
            }
            return ForgottenFavorite(scene: scene, lastPlayed: lastPlayed, plays: plays, oCount: oCount)
        }
    }

    func reset() {
        buildTask?.cancel()
        buildTask = nil
        generation += 1
        items = []
        poolCount = 0
        state = .idle
    }

    /// Within a session the row stays as it is; only an empty one builds.
    func refreshIfNeeded() {
        guard isAvailable, buildTask == nil, state == .idle else { return }
        rebuild()
    }

    /// Settings apply at once: the list is a plain function of the index and the settings.
    private func settingsChanged() {
        guard state != .idle else { return }
        rebuild()
    }

    func rebuild() {
        guard isAvailable else { return }
        buildTask?.cancel()
        generation += 1
        let gen = generation
        if items.isEmpty { state = .loading }
        let days = days, pool = pool, ranking = ranking
        let recent = Self.loadRecentPicks()
        buildTask = Task { [weak self] in
            let index = await AITagSuggestionManager.shared.sceneIndex()
            guard let self, gen == self.generation, !Task.isCancelled else { return }
            guard let index, !index.scenes.isEmpty else {
                self.items = []
                self.poolCount = 0
                self.state = .preparing
                self.buildTask = nil
                // Nothing built yet: start the statistics; the sink above fills the row after.
                Task { await AITagSuggestionManager.shared.ensureStatistics() }
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                Self.pick(from: index.scenes, days: days, pool: pool, ranking: ranking, recent: recent)
            }.value
            guard gen == self.generation, !Task.isCancelled else { return }
            self.items = result.items
            // Shown now: these step back in the next lists.
            Self.saveRecentPicks(result.items.map(\.id), keeping: recent)
            self.poolCount = result.poolCount
            self.state = .ready
            self.buildTask = nil
        }
    }

    /// Pull to refresh on Home: the index may have new plays since the last list.
    func rebuildAndWait() async {
        rebuild()
        await buildTask?.value
    }

    /// The favourites pool (top `pool` per ranking), minus everything played within `days`.
    /// Like For You, every build draws a new random order, and scenes shown in the last
    /// `rememberedLists` lists go to the back, so app start and pull to refresh bring others.
    nonisolated static func pick(from scenes: [LocalSceneIndex.Entry], days: Int, pool: Int,
                                 ranking: ForgottenFavoritesRanking,
                                 recent: [Set<String>] = []) -> (items: [ForgottenFavorite], poolCount: Int) {
        // Best rank (0 = top) a scene reaches in any ranking that applies.
        var rank: [String: Int] = [:]
        func take(_ ranked: [LocalSceneIndex.Entry]) {
            for (position, entry) in ranked.prefix(pool).enumerated() {
                rank[entry.id] = min(rank[entry.id] ?? .max, position)
            }
        }
        if ranking != .oCount {
            take(scenes.filter { $0.pc > 0 }.sorted {
                $0.pc != $1.pc ? $0.pc > $1.pc : $0.oc > $1.oc
            })
        }
        if ranking != .plays {
            take(scenes.filter { $0.oc > 0 }.sorted {
                $0.oc != $1.oc ? $0.oc > $1.oc : $0.pc > $1.pc
            })
        }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let byId = Dictionary(scenes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        struct Candidate {
            let entry: LocalSceneIndex.Entry
            let scene: Scene
            /// In how many of the recent lists it was shown.
            let shown: Int
            let draw: Double
        }
        var candidates: [Candidate] = []
        for id in rank.keys {
            guard let entry = byId[id], let scene = entry.scene else { continue }
            if let last = entry.lp, last > cutoff { continue }
            let shown = recent.reduce(0) { $0 + ($1.contains(id) ? 1 : 0) }
            candidates.append(Candidate(entry: entry, scene: scene, shown: shown, draw: Double.random(in: 0..<1)))
        }
        // Shown in fewer recent lists first, random within each group.
        candidates.sort { $0.shown != $1.shown ? $0.shown < $1.shown : $0.draw < $1.draw }
        let items = candidates.prefix(rowLimit).map {
            ForgottenFavorite(scene: $0.scene, lastPlayed: $0.entry.lp, plays: $0.entry.pc, oCount: $0.entry.oc)
        }
        return (items, rank.count)
    }

    // MARK: Recent lists

    /// Device-local (`SettingsTransfer.deviceLocalPrefixes`), one list per server.
    private static let lastPicksPrefix = "forgotten_favorites_last_picks_"
    private static let rememberedLists = 3

    private static var lastPicksKey: String? {
        ServerConfigManager.shared.activeConfig.map { "\(lastPicksPrefix)\($0.id)" }
    }

    /// The last lists shown, newest first.
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
}

#endif
