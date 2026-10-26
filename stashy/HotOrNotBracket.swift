//
//  HotOrNotBracket.swift
//  stashy
//
//  Match "32:1": single-elimination bracket of 32 performers. Unlike the duel modes no
//  rating is written per pick; once the final is decided every entrant gets a rating from
//  its finishing place, laid over the pool's own rating scale (idea from the cherrypick
//  plugin's `brackets.js`): the further a performer gets, the higher its target.
//
//  Shared with tvOS (`stashyTV/TVMatchView.swift`).
//

import Foundation

// MARK: - State

/// Persisted per server (`HotOrNotBracketStore`). The bracket is fully described by the first
/// round plus the ordered list of picked winners, so undo is `picks.removeLast()`.
struct HotOrNotBracketState: Codable, Equatable {
    struct Pairing: Codable, Equatable {
        let leftId: String
        let rightId: String
    }

    struct Match: Equatable {
        let round: Int
        let index: Int
        let leftId: String
        let rightId: String
        let winnerId: String?

        var loserId: String? {
            guard let winnerId else { return nil }
            return winnerId == leftId ? rightId : leftId
        }
    }

    /// Seed order: index 0 = seed 1 (highest rating at creation).
    var entrants: [HotOrNotPerformerData]
    var firstRound: [Pairing]
    var picks: [String]
    var createdAt: Date
    /// Performers whose result was already written (retry after a partial Apply skips them).
    var appliedIds: [String] = []

    static func == (lhs: HotOrNotBracketState, rhs: HotOrNotBracketState) -> Bool {
        lhs.entrants.map(\.id) == rhs.entrants.map(\.id)
            && lhs.firstRound == rhs.firstRound
            && lhs.picks == rhs.picks
            && lhs.createdAt == rhs.createdAt
            && lhs.appliedIds == rhs.appliedIds
    }

    var size: Int { firstRound.count * 2 }
    var roundCount: Int { HotOrNotBracketMath.roundCount(size: size) }
    var totalMatches: Int { size - 1 }

    func entrant(_ id: String) -> HotOrNotPerformerData? {
        entrants.first { $0.id == id }
    }

    /// All rounds known so far; a round only exists once the previous one is complete.
    var rounds: [[Match]] {
        var result: [[Match]] = []
        var pairs = firstRound.map { ($0.leftId, $0.rightId) }
        var pickIndex = 0
        for round in 0..<roundCount {
            var matches: [Match] = []
            for (i, pair) in pairs.enumerated() {
                let winner = pickIndex < picks.count ? picks[pickIndex] : nil
                if winner != nil { pickIndex += 1 }
                matches.append(Match(round: round, index: i, leftId: pair.0, rightId: pair.1, winnerId: winner))
            }
            result.append(matches)
            guard matches.allSatisfy({ $0.winnerId != nil }), matches.count > 1 else { break }
            pairs = stride(from: 0, to: matches.count, by: 2).map {
                (matches[$0].winnerId!, matches[$0 + 1].winnerId!)
            }
        }
        return result
    }

    var currentMatch: Match? {
        rounds.last?.first { $0.winnerId == nil }
    }

    var isFinished: Bool { picks.count >= totalMatches }

    var championId: String? { isFinished ? picks.last : nil }

    /// Tier per entrant from the round it lost in (only meaningful once finished).
    var tiers: [String: HotOrNotBracketMath.Tier] {
        var out: [String: HotOrNotBracketMath.Tier] = [:]
        let rounds = rounds
        for matches in rounds {
            for m in matches {
                guard let loser = m.loserId else { continue }
                out[loser] = HotOrNotBracketMath.Tier.eliminated(inRound: m.round, roundCount: roundCount)
            }
        }
        if let championId { out[championId] = .champion }
        return out
    }

    /// Played matches of one entrant in order: opponent id + won.
    func results(for id: String) -> [(opponentId: String, won: Bool)] {
        rounds.flatMap { $0 }.compactMap { m in
            guard let w = m.winnerId, m.leftId == id || m.rightId == id else { return nil }
            let opp = m.leftId == id ? m.rightId : m.leftId
            return (opp, w == id)
        }
    }
}

// MARK: - Math

enum HotOrNotBracketMath {
    static let size = 32

    enum Tier: Int, CaseIterable, Comparable {
        case champion = 0
        case finalist
        case semifinal
        case quarterfinal
        case roundOf16
        case roundOf32

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

        /// Lost in `round` (0 = first round) of a bracket with `roundCount` rounds.
        static func eliminated(inRound round: Int, roundCount: Int) -> Tier {
            let fromTop = roundCount - round // 1 = final
            return Tier(rawValue: min(Tier.roundOf32.rawValue, fromTop)) ?? .roundOf32
        }

        var label: String {
            switch self {
            case .champion: return "Champion"
            case .finalist: return "Finalist"
            case .semifinal: return "Semifinal"
            case .quarterfinal: return "Quarterfinal"
            case .roundOf16: return "Round of 16"
            case .roundOf32: return "Round of 32"
            }
        }

        /// 0-based finishing slots out of 32 (champion 0, finalist 1, semis 2–3, …).
        var slots: ClosedRange<Int> {
            switch self {
            case .champion: return 0...0
            case .finalist: return 1...1
            case .semifinal: return 2...3
            case .quarterfinal: return 4...7
            case .roundOf16: return 8...15
            case .roundOf32: return 16...31
            }
        }

        /// Tier floor/ceiling on the rating change: getting further never costs more.
        var deltaBounds: ClosedRange<Int> {
            switch self {
            case .champion: return 3...maxGain
            case .finalist: return 1...maxGain
            case .semifinal: return 0...maxGain
            case .quarterfinal, .roundOf16: return -maxLoss...maxGain
            case .roundOf32: return -maxLoss...0
            }
        }
    }

    static let maxGain = 20
    static let maxLoss = 12

    struct Proposal: Identifiable, Equatable {
        let id: String
        let name: String
        let tier: Tier
        let oldRating: Int
        let newRating: Int
        var delta: Int { newRating - oldRating }
    }

    static func roundCount(size: Int) -> Int {
        var n = 0
        var s = max(1, size)
        while s > 1 { s /= 2; n += 1 }
        return n
    }

    /// Standard seeding pattern, 1-based: [1, 32, 16, 17, 8, 25, …]. Consecutive pairs are the
    /// first-round matches; seeds 1 and 2 can only meet in the final.
    static func seedOrder(_ n: Int) -> [Int] {
        var order = [1]
        while order.count < n {
            let total = order.count * 2 + 1
            order = order.flatMap { [$0, total - $0] }
        }
        return order
    }

    /// Spread across the pool's rating scale: the rating-sorted pool is cut into `size` equal
    /// strata and one entrant is drawn from each, weighted by `recencyWeight` (performers from
    /// the last brackets count a tenth). `pool` must be sorted by rating, descending.
    static func selectEntrants(
        pool: [HotOrNotPerformerData],
        recentIds: Set<String>,
        size: Int = size
    ) -> [HotOrNotPerformerData]? {
        guard pool.count >= size else { return nil }
        var picked: [HotOrNotPerformerData] = []
        for s in 0..<size {
            let lo = s * pool.count / size
            let hi = (s + 1) * pool.count / size
            let stratum = Array(pool[lo..<hi])
            let weights = stratum.map { p -> Double in
                let w = max(0.05, HotOrNotSwissMath.recencyWeight(stats: p.stats))
                return recentIds.contains(p.id) ? w * 0.1 : w
            }
            guard let p = HotOrNotSwissMath.weightedPick(items: stratum, weights: weights) else { return nil }
            picked.append(p)
        }
        return picked
    }

    static func newBracket(
        pool: [HotOrNotPerformerData],
        recentIds: Set<String>,
        size: Int = size
    ) -> HotOrNotBracketState? {
        guard let picked = selectEntrants(pool: pool, recentIds: recentIds, size: size) else { return nil }
        let seeded = picked.sorted {
            let ra = $0.rating100 ?? 50, rb = $1.rating100 ?? 50
            return ra != rb ? ra > rb : $0.id < $1.id
        }
        let order = seedOrder(size)
        let pairs = stride(from: 0, to: size, by: 2).map { i -> HotOrNotBracketState.Pairing in
            let a = seeded[order[i] - 1].id
            let b = seeded[order[i + 1] - 1].id
            return Bool.random()
                ? .init(leftId: a, rightId: b)
                : .init(leftId: b, rightId: a)
        }
        return HotOrNotBracketState(entrants: seeded, firstRound: pairs, picks: [], createdAt: Date())
    }

    /// Rating at quantile `q` (0 = top) of the descending pool ratings.
    static func poolQuantile(_ sortedDesc: [Int], _ q: Double) -> Double {
        guard !sortedDesc.isEmpty else { return 50 }
        let idx = min(sortedDesc.count - 1, max(0, Int(q * Double(sortedDesc.count))))
        return Double(sortedDesc[idx])
    }

    /// Target rating of a tier: mean pool rating at the tier's finishing slots.
    static func target(for tier: Tier, poolRatingsDesc: [Int]) -> Double {
        let slots = tier.slots
        let sum = slots.reduce(0.0) { $0 + poolQuantile(poolRatingsDesc, (Double($1) + 0.5) / Double(size)) }
        return sum / Double(slots.count)
    }

    /// How far a result moves the rating towards the tier target; settled performers move less.
    static func blendWeight(matchCount: Int) -> Double {
        if matchCount < 5 { return 0.6 }
        if matchCount < 15 { return 0.45 }
        return 0.3
    }

    static func newRating(old: Int, tier: Tier, matchCount: Int, poolRatingsDesc: [Int]) -> Int {
        let t = target(for: tier, poolRatingsDesc: poolRatingsDesc)
        let raw = Int((Double(old) + blendWeight(matchCount: matchCount) * (t - Double(old))).rounded())
        let bounds = tier.deltaBounds
        let delta = min(bounds.upperBound, max(bounds.lowerBound, raw - old))
        return min(100, max(1, old + delta))
    }

    /// `current` = freshly loaded entrant data (rating + stats); falls back to the bracket copy.
    static func proposals(
        for state: HotOrNotBracketState,
        current: [String: HotOrNotPerformerData],
        poolRatingsDesc: [Int]
    ) -> [Proposal] {
        let tiers = state.tiers
        return state.entrants.compactMap { e -> Proposal? in
            guard let tier = tiers[e.id] else { return nil }
            let p = current[e.id] ?? e
            let old = p.rating100 ?? 50
            let mc = HotOrNotSwissMath.matchCountForProgressive(p.stats)
            return Proposal(
                id: e.id,
                name: p.displayName,
                tier: tier,
                oldRating: old,
                newRating: newRating(old: old, tier: tier, matchCount: mc, poolRatingsDesc: poolRatingsDesc)
            )
        }
        .sorted { $0.tier != $1.tier ? $0.tier < $1.tier : $0.newRating > $1.newRating }
    }

    static func roundTitle(round: Int, roundCount: Int) -> String {
        switch roundCount - round {
        case 1: return "Final"
        case 2: return "Semifinal"
        case 3: return "Quarterfinal"
        default: return "Round of \(1 << (roundCount - round))"
        }
    }
}

// MARK: - Persistence

enum HotOrNotBracketStore {
    private static let recentLimit = 64

    private static var serverSuffix: String {
        ServerConfigManager.shared.loadConfig()?.id.uuidString ?? "none"
    }

    private static var stateKey: String { "stashy.hotOrNot.bracket_\(serverSuffix)" }
    private static var recentKey: String { "stashy.hotOrNot.bracketRecent_\(serverSuffix)" }

    static func load() -> HotOrNotBracketState? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(HotOrNotBracketState.self, from: data)
    }

    static func save(_ state: HotOrNotBracketState?) {
        if let state, let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: stateKey)
        }
    }

    static func recentIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
    }

    /// Remembers the entrants of the last brackets (newest first, capped) so the next draw prefers others.
    static func rememberEntrants(_ ids: [String]) {
        let old = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        let merged = ids + old.filter { !ids.contains($0) }
        UserDefaults.standard.set(Array(merged.prefix(recentLimit)), forKey: recentKey)
    }
}
