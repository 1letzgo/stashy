//
//  HotOrNotToolsView.swift
//  stashy
//
//  Match: duel modes 1 vs. 1 / Rise / Legend + Charts leaderboard; rating math aligned with
//  Ascension plugin (`ascension.js` calculateMatchOutcome / getProgressiveKFactor).
//  (hotornot_stats, rating100, performer_record).
//

#if !os(tvOS)
import Foundation
import SwiftUI

// MARK: - Plugin-compatible stats

private struct HotOrNotStats: Codable, Equatable {
    var total_matches: Int
    var wins: Int
    var losses: Int
    var draws: Int
    var current_streak: Int
    var best_streak: Int
    var worst_streak: Int
    var last_match: String?

    init(
        total_matches: Int,
        wins: Int,
        losses: Int,
        draws: Int,
        current_streak: Int,
        best_streak: Int,
        worst_streak: Int,
        last_match: String?
    ) {
        self.total_matches = total_matches
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.current_streak = current_streak
        self.best_streak = best_streak
        self.worst_streak = worst_streak
        self.last_match = last_match
    }

    static let empty = HotOrNotStats(
        total_matches: 0, wins: 0, losses: 0, draws: 0,
        current_streak: 0, best_streak: 0, worst_streak: 0, last_match: nil
    )

    enum CodingKeys: String, CodingKey {
        case total_matches, wins, losses, draws, current_streak, best_streak, worst_streak, last_match
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total_matches = try c.decodeIfPresent(Int.self, forKey: .total_matches) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        draws = try c.decodeIfPresent(Int.self, forKey: .draws) ?? 0
        current_streak = try c.decodeIfPresent(Int.self, forKey: .current_streak) ?? 0
        best_streak = try c.decodeIfPresent(Int.self, forKey: .best_streak) ?? 0
        worst_streak = try c.decodeIfPresent(Int.self, forKey: .worst_streak) ?? 0
        last_match = try c.decodeIfPresent(String.self, forKey: .last_match)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total_matches, forKey: .total_matches)
        try c.encode(wins, forKey: .wins)
        try c.encode(losses, forKey: .losses)
        try c.encode(draws, forKey: .draws)
        try c.encode(current_streak, forKey: .current_streak)
        try c.encode(best_streak, forKey: .best_streak)
        try c.encode(worst_streak, forKey: .worst_streak)
        try c.encodeIfPresent(last_match, forKey: .last_match)
    }
}

private struct HotOrNotMatchRecord: Codable, Equatable {
    let date: String
    let opponent: String
    let won: Bool?
    let ratingAfter: Int
}

// MARK: - Math (matches plugin math-utils.js)

private enum HotOrNotSwissMath {

    /// Stash `custom_fields` may encode `hotornot_stats` as a JSON **string** (plugin) or as a structured **object** (GraphQL).
    private static func intFromStashJSON(_ v: StashJSONValue?) -> Int {
        guard let v else { return 0 }
        switch v {
        case .int(let i): return i
        case .double(let d): return Int(d.rounded())
        case .string(let s): return Int(s) ?? 0
        default: return 0
        }
    }

    private static func stringFromStashJSON(_ v: StashJSONValue?) -> String? {
        guard let v else { return nil }
        if case .string(let s) = v { return s }
        return nil
    }

    static func parseStats(from customFields: [String: StashJSONValue]?) -> HotOrNotStats {
        guard let fields = customFields else { return .empty }
        if case .string(let json) = fields["hotornot_stats"],
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(HotOrNotStats.self, from: data) {
            return decoded
        }
        if case .object(let obj) = fields["hotornot_stats"] {
            return HotOrNotStats(
                total_matches: intFromStashJSON(obj["total_matches"]),
                wins: intFromStashJSON(obj["wins"]),
                losses: intFromStashJSON(obj["losses"]),
                draws: intFromStashJSON(obj["draws"]),
                current_streak: intFromStashJSON(obj["current_streak"]),
                best_streak: intFromStashJSON(obj["best_streak"]),
                worst_streak: intFromStashJSON(obj["worst_streak"]),
                last_match: stringFromStashJSON(obj["last_match"])
            )
        }
        if case .string(let elo) = fields["elo_matches"], let n = Int(elo) {
            var s = HotOrNotStats.empty
            s.total_matches = n
            return s
        }
        return .empty
    }

    static func recencyWeight(stats: HotOrNotStats) -> Double {
        guard let raw = stats.last_match else { return 0.7 }
        let d = Self.isoParser.date(from: raw)
            ?? Self.isoParserPlain.date(from: raw)
        guard let d else { return 0.7 }
        let hours = Date().timeIntervalSince(d) / 3600
        return min(1, 1 - exp(-0.2 * hours))
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func weightedPick<T>(items: [T], weights: [Double]) -> T? {
        guard items.count == weights.count, !items.isEmpty else { return nil }
        let total = weights.reduce(0, +)
        if total <= 0 { return items.randomElement() }
        var r = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return items[i] }
        }
        return items.last
    }

    /// Match count for Ascension `getProgressiveKFactor` (`total_matches` with fallback to played games).
    static func matchCountForProgressive(_ stats: HotOrNotStats) -> Int {
        max(stats.total_matches, stats.wins + stats.losses + stats.draws)
    }

    /// Ascension `getProgressiveKFactor` (`ascension.js`). `mode` is `"swiss" | "gauntlet" | "champion"` (internal).
    static func getProgressiveKFactor(rating: Double, matchCount: Int, mode: String) -> Int {
        let count = max(0, matchCount)
        let experienceFactor = 0.5 + 0.5 / (1 + exp(Double(count - 18) / 6))
        var baseK = 32.0 * experienceFactor
        if rating > 60 {
            let reductionFactor = max(0.5, 1 - (rating - 60) / 70)
            baseK *= reductionFactor
        }
        if mode == "champion" {
            let kFactor = (baseK * 0.85).rounded()
            return min(35, max(6, Int(kFactor)))
        }
        if mode == "gauntlet" {
            let kFactor = (baseK * 1.1).rounded()
            return min(45, max(8, Int(kFactor)))
        }
        return min(40, max(6, Int(baseK.rounded())))
    }

    static func getUnderdogMultiplier(winnerRating: Double, loserRating: Double) -> Double {
        let ratingDiff = loserRating - winnerRating
        if ratingDiff > 30 { return 1.5 }
        if ratingDiff > 20 { return 1.3 }
        if ratingDiff > 10 { return 1.1 }
        return 1
    }

    /// When the loser is rated below the winner, reduce how many points the loser loses.
    static func getChallengeProtectionMultiplier(loserRating: Double, winnerRating: Double) -> Double {
        let ratingDiff = winnerRating - loserRating
        if ratingDiff > 15 {
            if ratingDiff > 30 { return 0.7 }
            if ratingDiff > 25 { return 0.8 }
            if ratingDiff > 20 { return 0.85 }
            return 0.9
        }
        return 1
    }

    /// Ascension `calculateMatchOutcome` (`ascension.js`). `mode`: `"swiss"` (Head-to-head), `"gauntlet"` (Placement), `"champion"`.
    static func calculateMatchOutcome(
        winnerRating: Double,
        loserRating: Double,
        mode: String,
        winnerMatchCount: Int,
        loserMatchCount: Int,
        winnerStats: HotOrNotStats,
        loserStats: HotOrNotStats,
        isSpecialChallenge: Bool = false
    ) -> (winnerGain: Int, loserLoss: Int) {
        let ratingDiff = loserRating - winnerRating
        let expectedWinner = 1 / (1 + pow(10, ratingDiff / 400))
        let winnerK = Double(getProgressiveKFactor(rating: winnerRating, matchCount: winnerMatchCount, mode: mode))
        let loserK = Double(getProgressiveKFactor(rating: loserRating, matchCount: loserMatchCount, mode: mode))
        let winnerUnderdogMult = getUnderdogMultiplier(winnerRating: winnerRating, loserRating: loserRating)
        let lossProtection = isSpecialChallenge ? 0.1 : getChallengeProtectionMultiplier(loserRating: loserRating, winnerRating: winnerRating)
        var winnerGain = (winnerK * (1 - expectedWinner) * winnerUnderdogMult).rounded()
        var loserLoss = (loserK * expectedWinner * lossProtection).rounded()

        if mode == "gauntlet" {
            let currentStreak = winnerStats.current_streak
            if currentStreak >= 3 {
                let gauntletDampener = max(0.3, 1 - Double(currentStreak - 3) * 0.15)
                winnerGain = Darwin.ceil(winnerGain * gauntletDampener)
            }
        }
        if mode == "champion" {
            let winStreak = winnerStats.current_streak
            if winStreak >= 5 {
                let streakPenalty = winStreak >= 10 ? 0.4 : 0.7
                winnerGain = Darwin.ceil(winnerGain * streakPenalty)
            }
        }
        if winnerRating >= 85 {
            winnerGain = Darwin.ceil(winnerGain * 0.6)
        } else if winnerRating >= 70 {
            winnerGain = Darwin.ceil(winnerGain * 0.8)
        }
        if winnerRating < loserRating - 20 {
            let ratingDiff2 = loserRating - winnerRating
            let scaleFactor = max(0.3, 1 - (ratingDiff2 - 20) / 100)
            winnerGain = Darwin.ceil(winnerGain * scaleFactor)
            loserLoss = Darwin.ceil(loserLoss * scaleFactor)
            loserLoss = min(loserLoss, 5)
        }
        if loserRating < winnerRating - 15 {
            let gap = winnerRating - loserRating
            let mitigationFactor = max(0.2, 1 - gap / 45)
            loserLoss = Darwin.ceil(loserLoss * mitigationFactor)
            if gap > 25 {
                loserLoss = min(loserLoss, 3)
            }
        }

        return (max(1, Int(winnerGain)), max(0, Int(loserLoss)))
    }

    /// Draw / skip: same as Ascension `handleComparison` draw branch (Head-to-head K curve).
    static func outcomeDraw(
        leftRating: Double,
        rightRating: Double,
        leftMatchCount: Int,
        rightMatchCount: Int
    ) -> (leftGain: Int, rightLoss: Int) {
        let ratingDiff = rightRating - leftRating
        let expectedWinner = 1 / (1 + pow(10, ratingDiff / 400))
        let wK = Double(getProgressiveKFactor(rating: leftRating, matchCount: leftMatchCount, mode: "swiss"))
        let lK = Double(getProgressiveKFactor(rating: rightRating, matchCount: rightMatchCount, mode: "swiss"))
        let leftGain = Int(round(wK * (0.5 - expectedWinner)))
        let rightLoss = Int(round(lK * (1 - expectedWinner - 0.5)))
        return (leftGain, rightLoss)
    }

    #if DEBUG
    /// Xcode-Konsole: Filter `[HotOrNot ELO]`. `ascensionMode` = plugin string `swiss` / `gauntlet` / `champion`.
    static func logDuelVoteDebugLine(
        duelLabel: String,
        ascensionMode: String,
        winnerDisplay: String,
        loserDisplay: String,
        winnerRating: Double,
        loserRating: Double,
        winnerStats: HotOrNotStats,
        loserStats: HotOrNotStats,
        gain: Int,
        loss: Int
    ) {
        let mcW = matchCountForProgressive(winnerStats)
        let mcL = matchCountForProgressive(loserStats)
        let ratingDiff = loserRating - winnerRating
        let ew = 1 / (1 + pow(10, ratingDiff / 400))
        let eStr = String(format: "%.4f", ew)
        let wK = getProgressiveKFactor(rating: winnerRating, matchCount: mcW, mode: ascensionMode)
        let lK = getProgressiveKFactor(rating: loserRating, matchCount: mcL, mode: ascensionMode)
        AppLog.debug(
            "[HotOrNot ELO] \(duelLabel) [\(ascensionMode)] \(winnerDisplay) vs \(loserDisplay) rW=\(String(format: "%.1f", winnerRating)) rL=\(String(format: "%.1f", loserRating)) E=\(eStr) Kw=\(wK) Kl=\(lK) mcW=\(mcW) mcL=\(mcL) W(tm/w/l/d)=\(winnerStats.total_matches)/\(winnerStats.wins)/\(winnerStats.losses)/\(winnerStats.draws) L(tm/w/l/d)=\(loserStats.total_matches)/\(loserStats.wins)/\(loserStats.losses)/\(loserStats.draws) → gain=\(gain) loss=\(loss)"
        )
    }

    static func logDrawSkipDebugLine(
        duelLabel: String,
        leftDisplay: String,
        rightDisplay: String,
        leftRating: Double,
        rightRating: Double,
        leftStats: HotOrNotStats,
        rightStats: HotOrNotStats,
        leftGain: Int,
        rightLoss: Int
    ) {
        let mcL = matchCountForProgressive(leftStats)
        let mcR = matchCountForProgressive(rightStats)
        let ratingDiff = rightRating - leftRating
        let ew = 1 / (1 + pow(10, ratingDiff / 400))
        let eStr = String(format: "%.4f", ew)
        let kLeft = getProgressiveKFactor(rating: leftRating, matchCount: mcL, mode: "swiss")
        let kRight = getProgressiveKFactor(rating: rightRating, matchCount: mcR, mode: "swiss")
        AppLog.debug(
            "[HotOrNot ELO] draw/skip \(duelLabel) \(leftDisplay) vs \(rightDisplay) rL=\(String(format: "%.1f", leftRating)) rR=\(String(format: "%.1f", rightRating)) E(left wins)=\(eStr) K_left=\(kLeft) K_right=\(kRight) mcL=\(mcL) mcR=\(mcR) L(tm/w/l/d)=\(leftStats.total_matches)/\(leftStats.wins)/\(leftStats.losses)/\(leftStats.draws) R(tm/w/l/d)=\(rightStats.total_matches)/\(rightStats.wins)/\(rightStats.losses)/\(rightStats.draws) → dL=\(leftGain) dR=\(rightLoss)"
        )
    }
    #endif

    static func updateStats(_ current: HotOrNotStats, won: Bool?) -> HotOrNotStats {
        var n = current
        n.total_matches = (current.total_matches) + 1
        n.last_match = Self.nowISO()
        if won == nil {
            n.draws = (current.draws) + 1
            return n
        }
        if won == true {
            n.wins = (current.wins) + 1
            if current.current_streak >= 0 {
                n.current_streak = (current.current_streak) + 1
            } else {
                n.current_streak = 1
            }
        } else {
            n.losses = (current.losses) + 1
            if current.current_streak <= 0 {
                n.current_streak = (current.current_streak) - 1
            } else {
                n.current_streak = -1
            }
        }
        n.best_streak = max(current.best_streak, n.current_streak)
        n.worst_streak = min(current.worst_streak, n.current_streak)
        return n
    }

    private static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static func encodeStats(_ s: HotOrNotStats) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(s), encoding: .utf8) ?? "{}"
    }

    static func parseMatchRecords(from customFields: [String: StashJSONValue]?) -> [HotOrNotMatchRecord] {
        guard let fields = customFields,
              case .string(let raw) = fields["performer_record"],
              let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([HotOrNotMatchRecord].self, from: data)) ?? []
    }

    static func encodeMatchRecords(_ records: [HotOrNotMatchRecord]) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(records), encoding: .utf8) ?? "[]"
    }
}

// MARK: - GraphQL response types

private struct HotOrNotPerformerData: Codable {
    let id: String
    let name: String
    let disambiguation: String?
    let birthdate: String?
    let country: String?
    let image_path: String?
    let scene_count: Int?
    let image_count: Int?
    let gallery_count: Int?
    let gender: String?
    let ethnicity: String?
    let height_cm: Int?
    let weight: Int?
    let measurements: String?
    let fake_tits: String?
    let penis_length: Double?
    let career_length: String?
    let tattoos: String?
    let piercings: String?
    let alias_list: [String]?
    let favorite: Bool?
    let rating100: Int?
    let o_counter: Int?
    let custom_fields: [String: StashJSONValue]?

    var stats: HotOrNotStats { HotOrNotSwissMath.parseStats(from: custom_fields) }

    /// Nur `name` (ohne Disambiguation) für Match-Karten und Listen.
    var displayName: String { name }

    /// Minimal `Performer` for pushing `PerformerDetailView` from Match (detail loads full data).
    func toPerformerStub() -> Performer {
        Performer(
            id: id,
            name: name,
            disambiguation: disambiguation,
            birthdate: birthdate,
            country: country,
            imagePath: image_path,
            sceneCount: scene_count ?? 0,
            imageCount: image_count,
            galleryCount: gallery_count,
            gender: gender,
            ethnicity: ethnicity,
            height: height_cm,
            weight: weight,
            measurements: measurements,
            fakeTits: fake_tits,
            penis_length: penis_length,
            careerLength: career_length,
            tattoos: tattoos,
            piercings: piercings,
            aliasList: alias_list,
            favorite: favorite,
            rating100: rating100,
            createdAt: nil,
            updatedAt: nil,
            oCounter: o_counter
        )
    }

    func replacingRating100(_ newRating: Int) -> HotOrNotPerformerData {
        HotOrNotPerformerData(
            id: id,
            name: name,
            disambiguation: disambiguation,
            birthdate: birthdate,
            country: country,
            image_path: image_path,
            scene_count: scene_count,
            image_count: image_count,
            gallery_count: gallery_count,
            gender: gender,
            ethnicity: ethnicity,
            height_cm: height_cm,
            weight: weight,
            measurements: measurements,
            fake_tits: fake_tits,
            penis_length: penis_length,
            career_length: career_length,
            tattoos: tattoos,
            piercings: piercings,
            alias_list: alias_list,
            favorite: favorite,
            rating100: newRating,
            o_counter: o_counter,
            custom_fields: custom_fields
        )
    }
}

/// Fixed 3×2 grid for battle cards: same fields always; empty → "—".
private func hotOrNotBattleFixedInfoRows(_ p: HotOrNotPerformerData) -> [(label: String, value: String)] {
    let dash = "—"
    let rating = "\(p.rating100 ?? 50)"
    let genderVal: String = {
        guard let g = p.gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty else { return dash }
        return g
    }()
    let scenesVal = "\(p.scene_count ?? 0)"
    let imagesVal = "\(p.image_count ?? 0)"
    let countryVal: String = {
        guard let c = p.country?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return dash }
        return c
    }()
    let titsVal: String = {
        let g = p.gender?.uppercased() ?? ""
        if g.contains("FEMALE") {
            if let t = p.fake_tits?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            return dash
        }
        if g.contains("MALE") || g == "MAN" {
            if let pl = p.penis_length, pl > 0 { return String(format: "%.0f cm", pl) }
            return dash
        }
        if let t = p.fake_tits?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let pl = p.penis_length, pl > 0 { return String(format: "%.0f cm", pl) }
        return dash
    }()
    return [
        ("RATING", rating),
        ("GENDER", genderVal),
        ("SCENES", scenesVal),
        ("IMAGES", imagesVal),
        ("COUNTRY", countryVal),
        ("TITS", titsVal)
    ]
}

/// Clips the performer photo: only the **top** corners match the card radius; the **bottom** edge stays square (no rounding).
private struct HotOrNotPhotoTopClipShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width * 0.5, rect.height * 0.5)
        var p = Path()
        guard r > 0 else {
            p.addRect(rect)
            return p
        }
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

/// Row below each duel column; opens `PerformerDetailView` (label is only “Profile”).
private struct HotOrNotProfileLinkCard: View {
    let performer: HotOrNotPerformerData

    var body: some View {
        NavigationLink {
            PerformerDetailView(performer: performer.toPerformerStub())
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile, \(performer.displayName)")
    }
}

private struct HotOrNotBattleColumn: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let rank: Int?
    let voteFeedback: HotOrNotDuelVoteFeedback.Side?
    let choose: () -> Void

    private var rows: [(label: String, value: String)] {
        hotOrNotBattleFixedInfoRows(performer)
    }

    private var cardCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        Button(action: choose) {
            ZStack {
                VStack(alignment: .leading, spacing: 0) {
                    photoStack
                    VStack(alignment: .leading, spacing: 8) {
                        nameBlock
                        detailGrid
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

                if let vote = voteFeedback {
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(voteTint(for: vote.delta100))
                    VStack(spacing: 6) {
                        Text(signedDeltaText(vote.delta100))
                            .font(.system(size: 30, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        Text("Score")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .textCase(.uppercase)
                        Text("\(vote.rating100After)")
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Choose \(performer.displayName)")
    }

    private func voteTint(for delta100: Int) -> Color {
        if delta100 > 0 { return Color.green.opacity(0.42) }
        if delta100 < 0 { return Color.red.opacity(0.42) }
        return Color.gray.opacity(0.35)
    }

    private func signedDeltaText(_ delta100: Int) -> String {
        if delta100 > 0 { return "+\(delta100)" }
        return "\(delta100)"
    }

    private var photoStack: some View {
        let r = cardCornerRadius
        return ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    Color.gray.opacity(DesignTokens.Opacity.placeholder)
                    photoOverlay
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            rankBadge
        }
        .clipShape(HotOrNotPhotoTopClipShape(cornerRadius: r))
    }

    @ViewBuilder
    private var photoOverlay: some View {
        if let url = model.thumbnailURL(for: performer) {
            CustomAsyncImage(url: url) { loader in
                if loader.isLoading {
                    InlineSpinner(scale: .medium)
                } else if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }

    @ViewBuilder
    private var rankBadge: some View {
        if let rank {
            Text("#\(rank)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
    }

    private var nameBlock: some View {
        Text(performer.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, detail in
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.label)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(detail.value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Rise starter: same card shell as duel (`HotOrNotBattleColumn`), but only photo + name + rating row (no detail grid, no rank).
private struct HotOrNotGauntletStarterPickCard: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let onPick: () -> Void

    private var ratingText: String {
        "\(performer.rating100 ?? 50)"
    }

    private var cardCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                photoStack
                VStack(alignment: .leading, spacing: 8) {
                    nameBlock
                    ratingOnlyRow
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityLabel("Pick \(performer.displayName) as Rise starter")
    }

    private var photoStack: some View {
        let r = cardCornerRadius
        return GeometryReader { geo in
            ZStack {
                Color.gray.opacity(DesignTokens.Opacity.placeholder)
                photoOverlay
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(HotOrNotPhotoTopClipShape(cornerRadius: r))
    }

    @ViewBuilder
    private var photoOverlay: some View {
        if let url = model.thumbnailURL(for: performer) {
            CustomAsyncImage(url: url) { loader in
                if loader.isLoading {
                    InlineSpinner(scale: .medium)
                } else if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }

    private var nameBlock: some View {
        Text(performer.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Same label/value typography as one cell in `HotOrNotBattleColumn`’s `detailGrid`, but only rating.
    private var ratingOnlyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RATING")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(ratingText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HotOrNotFindResult: Codable {
    let count: Int
    let performers: [HotOrNotPerformerData]
}

private struct HotOrNotFindData: Codable {
    let findPerformers: HotOrNotFindResult
}

private struct HotOrNotFindResponse: Codable {
    let data: HotOrNotFindData?
}

// MARK: - Battle rank (Performer detail header; same pool as Charts)

/// Paginates `findPerformers` for Hot or Not leaderboards. Not isolated to `@MainActor` so `HotOrNotBattleDisplay` can use the same value in Swift 6.
private enum HotOrNotLeaderboardPaging {
    static let perPage = 50
}

enum HotOrNotBattleDisplay {
    private static let gendersKey = "stashy.hotOrNot.selectedGenders"
    private static let client = GraphQLClient.shared

    static func loadGenders() -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: gendersKey),
           let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
            return Set(arr)
        }
        return ["FEMALE"]
    }

    static func saveGenders(_ genders: Set<String>) {
        let arr = Array(genders).sorted()
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: gendersKey)
        }
    }

    private static func performerFilter(genders: Set<String>) -> [String: Any] {
        [
            "gender": ["value_list": Array(genders).sorted(), "modifier": "INCLUDES"],
            "NOT": ["is_missing": "image"] as [String: Any]
        ]
    }

    /// Same query/sort as `HotOrNotViewModel.refreshLeaderboard` — `rank/total` in the Match pool, or `nil` if not listed or on error.
    static func fetchRankSlashTotal(performerId: String) async -> String? {
        let genders = loadGenders()
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let perPage = HotOrNotLeaderboardPaging.perPage
        var totalCount = 0
        var page = 1
        do {
            while true {
                let variables: [String: Any] = [
                    "performer_filter": performerFilter(genders: genders),
                    "filter": [
                        "page": page,
                        "per_page": perPage,
                        "sort": "rating",
                        "direction": "DESC"
                    ] as [String: Any]
                ]
                let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
                let list = res.data?.findPerformers.performers ?? []
                if page == 1 {
                    totalCount = res.data?.findPerformers.count ?? list.count
                }
                if let idx = list.firstIndex(where: { $0.id == performerId }) {
                    let rank = (page - 1) * perPage + idx + 1
                    return "\(rank)/\(max(totalCount, rank))"
                }
                if list.count < perPage || page * perPage >= totalCount { break }
                page += 1
            }
        } catch {
            return nil
        }
        return nil
    }
}

private struct HotOrNotMutationData: Codable {
    let performerUpdate: HotOrNotUpdated?
}

private struct HotOrNotUpdated: Codable {
    let id: String
}

private struct HotOrNotMutationResponse: Codable {
    let data: HotOrNotMutationData?
}

/// Per-side duel outcome: `delta100` is the change in Stash `rating100` (Ascension-style math / server update); `rating100After` is the clamped new value.
private struct HotOrNotDuelVoteFeedback: Equatable {
    struct Side: Equatable {
        let delta100: Int
        let rating100After: Int
    }

    let left: Side
    let right: Side
}

// MARK: - ViewModel

@MainActor
private final class HotOrNotViewModel: ObservableObject {
    enum Section: String, CaseIterable {
        case battle = "Game"
        case leaderboard = "Charts"
        case settings = "Settings"
    }

    /// Persisted `rawValue`: `headToHead` | `placement` | `champion` (legacy `swiss` / `gauntlet` migrated on load).
    enum DuelMode: String, CaseIterable, Identifiable {
        case headToHead
        case placement
        case champion

        var id: String { rawValue }

        var label: String {
            switch self {
            case .headToHead: return "1 vs. 1"
            case .placement: return "Rise"
            case .champion: return "Legend"
            }
        }

        /// Ascension `calculateMatchOutcome` / `getProgressiveKFactor` mode string.
        var ascensionMode: String {
            switch self {
            case .headToHead: return "swiss"
            case .placement: return "gauntlet"
            case .champion: return "champion"
            }
        }
    }

    private static let duelModeDefaultsKey = "stashy.hotOrNot.duelMode"

    @Published var section: Section = .battle
    @Published var duelMode: DuelMode = .headToHead {
        didSet { UserDefaults.standard.set(duelMode.rawValue, forKey: Self.duelModeDefaultsKey) }
    }
    @Published var selectedGenders: Set<String> = HotOrNotBattleDisplay.loadGenders() {
        didSet { HotOrNotBattleDisplay.saveGenders(selectedGenders) }
    }
    @Published var left: HotOrNotPerformerData?
    @Published var right: HotOrNotPerformerData?
    @Published var rankLeft: Int?
    @Published var rankRight: Int?
    @Published var leaderboard: [HotOrNotPerformerData] = []
    /// Total performers in pool (`findPerformers.count`); leaderboard rows are paginated (`HotOrNotLeaderboardPaging.perPage`).
    @Published var leaderboardTotalCount: Int = 0
    @Published var isLoadingMoreLeaderboard = false
    @Published var isLoadingPair = false
    @Published var isSubmitting = false
    @Published var isLoadingBoard = false
    @Published var errorMessage: String?
    @Published var poolCount: Int = 0
    /// Shown on battle cards after a vote/draw; same `delta100` / `rating100After` as written via `performerUpdate`.
    @Published var duelFeedback: HotOrNotDuelVoteFeedback?

    // Climb state (plugin `gauntletChampion` / `gauntletWins` / `gauntletDefeated` / `gauntletFalling*`).
    @Published var climbChampion: HotOrNotPerformerData?
    @Published var climbWins: Int = 0
    @Published var climbDefeatedIds: Set<String> = []
    @Published var climbSkippedId: String?
    @Published var climbFalling: Bool = false
    @Published var climbFallingItem: HotOrNotPerformerData?
    @Published var climbVictory: HotOrNotPerformerData?
    @Published var placementStarters: [HotOrNotPerformerData] = []
    @Published var isLoadingPlacementStarters = false

    /// Inline Rise starter grid (no sheet): need picks before the first duel.
    var needsPlacementStarterSelection: Bool {
        duelMode == .placement && climbChampion == nil && !climbFalling && climbVictory == nil
    }

    private let client = GraphQLClient.shared
    private static let duelFeedbackDurationNs: UInt64 = 1_200_000_000
    /// Last successfully loaded Charts `filter.page` (1-based); 0 = not loaded.
    private var lastLeaderboardPageLoaded = 0

    var leaderboardHasMore: Bool {
        !leaderboard.isEmpty && leaderboard.count < leaderboardTotalCount
    }
    /// `findPerformers` right after `performerUpdate` can still return old `rating100`; overlay last pushed values until reload finishes.
    private var pendingRating100ByPerformerId: [String: Int] = [:]

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.duelModeDefaultsKey) {
            duelMode = Self.duelMode(migratingPersistedRaw: raw)
        }
    }

    /// Maps legacy `swiss` / `gauntlet` saved values to Ascension-style mode ids.
    private static func duelMode(migratingPersistedRaw raw: String) -> DuelMode {
        switch raw {
        case "swiss", "headToHead": return .headToHead
        case "gauntlet", "placement": return .placement
        case "champion": return .champion
        default:
            return DuelMode(rawValue: raw) ?? .headToHead
        }
    }

    private var performerFilter: [String: Any] {
        let f: [String: Any] = [
            "gender": ["value_list": Array(selectedGenders).sorted(), "modifier": "INCLUDES"],
            "NOT": ["is_missing": "image"] as [String: Any]
        ]
        return f
    }

    func toggleGender(_ code: String) {
        if selectedGenders.contains(code) {
            if selectedGenders.count > 1 { selectedGenders.remove(code) }
        } else {
            selectedGenders.insert(code)
        }
    }

    func thumbnailURL(for p: HotOrNotPerformerData) -> URL? {
        if let path = p.image_path, path.hasPrefix("http://") || path.hasPrefix("https://") {
            return signedURL(URL(string: path))
        }
        guard let config = ServerConfigManager.shared.loadConfig(), config.hasValidConfig else { return nil }
        let s = "\(config.baseURL)/performer/\(p.id)/image"
        return signedURL(URL(string: s))
    }

    private func mergePendingRating(_ p: HotOrNotPerformerData) -> HotOrNotPerformerData {
        if let r = pendingRating100ByPerformerId[p.id] {
            return p.replacingRating100(r)
        }
        return p
    }

    /// Pool by **effective** `rating100` (pending updates merged), descending. Stable tie-break on `id` so ladder / ranks match the UI.
    private func ladderSortedPool(_ list: [HotOrNotPerformerData]) -> [HotOrNotPerformerData] {
        list.map { mergePendingRating($0) }.sorted { a, b in
            let ra = a.rating100 ?? 50
            let rb = b.rating100 ?? 50
            if ra != rb { return ra > rb }
            return a.id < b.id
        }
    }

    func loadDuelPair() async {
        duelFeedback = nil
        if climbVictory != nil {
            left = nil
            right = nil
            rankLeft = nil
            rankRight = nil
            return
        }
        switch duelMode {
        case .headToHead:
            await loadHeadToHeadPairContent()
        case .placement:
            if climbChampion == nil && !climbFalling {
                isLoadingPair = false
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                await preparePlacementStarters()
                return
            }
            await loadClimbPair(isPlacement: true)
        case .champion:
            await loadClimbPair(isPlacement: false)
        }
    }

    private func loadHeadToHeadPairContent() async {
        isLoadingPair = true
        errorMessage = nil
        defer { isLoadingPair = false }

        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": -1, "sort": "rating", "direction": "DESC"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            poolCount = res.data?.findPerformers.count ?? list.count
            guard list.count >= 2 else {
                errorMessage = "Not enough performers with images for the selected genders."
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }
            let weighted = list.enumerated().map { idx, p -> (Int, HotOrNotPerformerData, Double) in
                (idx, p, HotOrNotSwissMath.recencyWeight(stats: p.stats))
            }
            let w1 = weighted.map { $0.2 }
            guard let s1 = HotOrNotSwissMath.weightedPick(items: weighted, weights: w1) else { return }
            let rating1 = Double(s1.1.rating100 ?? 50)
            let similar = weighted.filter { $0.0 != s1.0 && abs(Double($0.1.rating100 ?? 50) - rating1) <= 15 }
            let s2: (Int, HotOrNotPerformerData, Double)
            if similar.isEmpty, let other = weighted.first(where: { $0.0 != s1.0 }) {
                s2 = other
            } else if let picked = HotOrNotSwissMath.weightedPick(items: similar, weights: similar.map { $0.2 }) {
                s2 = picked
            } else if let other = weighted.first(where: { $0.0 != s1.0 }) {
                s2 = other
            } else {
                return
            }
            left = mergePendingRating(s1.1)
            right = mergePendingRating(s2.1)
            rankLeft = s1.0 + 1
            rankRight = s2.0 + 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Legend / Rise pairing (climb ladder).
    private func loadClimbPair(isPlacement: Bool) async {
        isLoadingPair = true
        errorMessage = nil
        defer { isLoadingPair = false }

        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": -1, "sort": "rating", "direction": "DESC"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            poolCount = res.data?.findPerformers.count ?? list.count
            guard list.count >= 2 else {
                errorMessage = "Not enough performers with images for the selected genders."
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }

            if let cid = climbChampion?.id, let live = list.first(where: { $0.id == cid }) {
                climbChampion = mergePendingRating(live)
            }

            let ranked = ladderSortedPool(list)

            if isPlacement, climbFalling, let fall = climbFallingItem {
                let candidates = ranked.filter {
                    $0.id != fall.id && !climbDefeatedIds.contains($0.id) && $0.id != climbSkippedId
                }
                if let opp = candidates.randomElement() {
                    left = mergePendingRating(fall)
                    right = mergePendingRating(opp)
                    rankLeft = ranked.firstIndex { $0.id == fall.id }.map { $0 + 1 }
                    rankRight = ranked.firstIndex { $0.id == opp.id }.map { $0 + 1 }
                } else if climbSkippedId != nil {
                    climbSkippedId = nil
                    await loadClimbPair(isPlacement: true)
                    return
                } else {
                    let resolved = ranked.first(where: { $0.id == fall.id }) ?? mergePendingRating(fall)
                    climbVictory = resolved
                    left = nil
                    right = nil
                    rankLeft = nil
                    rankRight = nil
                }
                climbSkippedId = nil
                return
            }

            if climbChampion == nil {
                let shuffled = ranked.shuffled()
                left = mergePendingRating(shuffled[0])
                right = mergePendingRating(shuffled[1])
                rankLeft = ranked.firstIndex { $0.id == shuffled[0].id }.map { $0 + 1 }
                rankRight = ranked.firstIndex { $0.id == shuffled[1].id }.map { $0 + 1 }
                climbSkippedId = nil
                return
            }

            guard let champ = climbChampion else { return }
            guard let champIdx = ranked.firstIndex(where: { $0.id == champ.id }) else {
                errorMessage = "Legend run performer is no longer in this pool. Run reset."
                resetClimbStatePreservingMode()
                await loadDuelPair()
                return
            }

            let potential = ranked.enumerated()
                .filter { $0.offset < champIdx && !climbDefeatedIds.contains($0.element.id) && $0.element.id != climbSkippedId }
                .map { $0.element }

            if potential.isEmpty {
                if climbSkippedId != nil {
                    climbSkippedId = nil
                    await loadClimbPair(isPlacement: isPlacement)
                    return
                }
                climbVictory = ranked[champIdx]
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }

            let window = min(5, potential.count)
            let rIdx = Int.random(in: 0..<window)
            let opponent = potential[potential.count - 1 - rIdx]
            left = mergePendingRating(ranked[champIdx])
            right = mergePendingRating(opponent)
            rankLeft = champIdx + 1
            rankRight = (ranked.firstIndex { $0.id == opponent.id } ?? 0) + 1
            climbSkippedId = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetClimbStatePreservingMode() {
        climbChampion = nil
        climbWins = 0
        climbDefeatedIds = []
        climbSkippedId = nil
        climbVictory = nil
        climbFalling = false
        climbFallingItem = nil
        placementStarters = []
        pendingRating100ByPerformerId.removeAll()
    }

    func startNewClimbRun() {
        resetClimbStatePreservingMode()
        Task { await loadDuelPair() }
    }

    func preparePlacementStarters() async {
        isLoadingPlacementStarters = true
        errorMessage = nil
        defer { isLoadingPlacementStarters = false }
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": 100, "sort": "random"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            placementStarters = Array(list.shuffled().prefix(6))
            if placementStarters.isEmpty {
                errorMessage = "No performers to pick as a Rise starter."
            }
        } catch {
            errorMessage = error.localizedDescription
            placementStarters = []
        }
    }

    func pickPlacementStarter(_ p: HotOrNotPerformerData) {
        climbChampion = p
        climbWins = 0
        climbDefeatedIds = []
        climbFalling = false
        climbFallingItem = nil
        climbSkippedId = nil
        Task { await loadDuelPair() }
    }

    private func applyClimbAfterVote(winner: HotOrNotPerformerData, loser: HotOrNotPerformerData, newWinnerRating: Int, newLoserRating: Int) {
        switch duelMode {
        case .headToHead:
            break
        case .champion:
            if climbChampion?.id == winner.id {
                climbDefeatedIds.insert(loser.id)
                climbWins += 1
                climbChampion = winner.replacingRating100(newWinnerRating)
            } else {
                climbChampion = winner.replacingRating100(newWinnerRating)
                climbWins = 1
            }
        case .placement:
            if climbChampion?.id == winner.id {
                climbDefeatedIds.insert(loser.id)
                climbWins += 1
                climbChampion = winner.replacingRating100(newWinnerRating)
            } else if !climbFalling {
                climbFalling = true
                climbFallingItem = loser.replacingRating100(newLoserRating)
                climbDefeatedIds = [winner.id]
            } else {
                climbDefeatedIds.insert(winner.id)
            }
        }
    }

    func refreshLeaderboard() async {
        isLoadingBoard = true
        errorMessage = nil
        defer { isLoadingBoard = false }
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": [
                "page": 1,
                "per_page": HotOrNotLeaderboardPaging.perPage,
                "sort": "rating",
                "direction": "DESC"
            ] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            let count = res.data?.findPerformers.count ?? list.count
            leaderboard = list
            leaderboardTotalCount = count
            lastLeaderboardPageLoaded = list.isEmpty ? 0 : 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreLeaderboard() async {
        guard leaderboardHasMore, !isLoadingMoreLeaderboard, !isLoadingBoard else { return }
        let nextPage = lastLeaderboardPageLoaded + 1
        guard nextPage >= 2 else { return }
        isLoadingMoreLeaderboard = true
        defer { isLoadingMoreLeaderboard = false }
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": [
                "page": nextPage,
                "per_page": HotOrNotLeaderboardPaging.perPage,
                "sort": "rating",
                "direction": "DESC"
            ] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            if list.isEmpty { return }
            let existing = Set(leaderboard.map(\.id))
            let appended = list.filter { !existing.contains($0.id) }
            leaderboard.append(contentsOf: appended)
            lastLeaderboardPageLoaded = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func choose(leftWins: Bool) async {
        guard let l = left, let r = right else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let winner = leftWins ? l : r
        let loser = leftWins ? r : l
        let wr = Double(winner.rating100 ?? 50)
        let lr = Double(loser.rating100 ?? 50)

        let mcW = HotOrNotSwissMath.matchCountForProgressive(winner.stats)
        let mcL = HotOrNotSwissMath.matchCountForProgressive(loser.stats)
        let modeStr = duelMode.ascensionMode
        let o = HotOrNotSwissMath.calculateMatchOutcome(
            winnerRating: wr,
            loserRating: lr,
            mode: modeStr,
            winnerMatchCount: mcW,
            loserMatchCount: mcL,
            winnerStats: winner.stats,
            loserStats: loser.stats,
            isSpecialChallenge: false
        )
        let gain = o.winnerGain
        let loss = o.loserLoss
        #if DEBUG
        HotOrNotSwissMath.logDuelVoteDebugLine(
            duelLabel: duelMode.label,
            ascensionMode: modeStr,
            winnerDisplay: winner.displayName,
            loserDisplay: loser.displayName,
            winnerRating: wr,
            loserRating: lr,
            winnerStats: winner.stats,
            loserStats: loser.stats,
            gain: gain,
            loss: loss
        )
        #endif
        let oldW = winner.rating100 ?? 50
        let oldL = loser.rating100 ?? 50
        let newW = min(100, max(1, oldW + gain))
        let newL = min(100, max(1, oldL - loss))
        let deltaW = newW - oldW
        let deltaL = newL - oldL
        let feedback: HotOrNotDuelVoteFeedback = if leftWins {
            HotOrNotDuelVoteFeedback(
                left: .init(delta100: deltaW, rating100After: newW),
                right: .init(delta100: deltaL, rating100After: newL)
            )
        } else {
            HotOrNotDuelVoteFeedback(
                left: .init(delta100: deltaL, rating100After: newL),
                right: .init(delta100: deltaW, rating100After: newW)
            )
        }
        do {
            try await pushPerformerUpdate(
                performer: winner,
                newRating: newW,
                won: true,
                opponentId: loser.id,
                opponentName: loser.name
            )
            try await pushPerformerUpdate(
                performer: loser,
                newRating: newL,
                won: false,
                opponentId: winner.id,
                opponentName: winner.name
            )
            pendingRating100ByPerformerId[winner.id] = newW
            pendingRating100ByPerformerId[loser.id] = newL
            applyClimbAfterVote(winner: winner, loser: loser, newWinnerRating: newW, newLoserRating: newL)
            HapticManager.light()
            withAnimation(.easeOut(duration: 0.18)) {
                duelFeedback = feedback
            }
            try await Task.sleep(nanoseconds: Self.duelFeedbackDurationNs)
            withAnimation(.easeOut(duration: 0.15)) {
                duelFeedback = nil
            }
            await loadDuelPair()
            pendingRating100ByPerformerId.removeValue(forKey: winner.id)
            pendingRating100ByPerformerId.removeValue(forKey: loser.id)
            if section == .leaderboard { await refreshLeaderboard() }
        } catch {
            pendingRating100ByPerformerId.removeValue(forKey: winner.id)
            pendingRating100ByPerformerId.removeValue(forKey: loser.id)
            errorMessage = error.localizedDescription
        }
    }

    func skipDraw() async {
        guard duelMode != .champion else { return }
        guard let l = left, let r = right else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let lr = Double(l.rating100 ?? 50)
        let rr = Double(r.rating100 ?? 50)
        let (lg, rrLoss) = HotOrNotSwissMath.outcomeDraw(
            leftRating: lr,
            rightRating: rr,
            leftMatchCount: HotOrNotSwissMath.matchCountForProgressive(l.stats),
            rightMatchCount: HotOrNotSwissMath.matchCountForProgressive(r.stats)
        )
        #if DEBUG
        HotOrNotSwissMath.logDrawSkipDebugLine(
            duelLabel: duelMode.label,
            leftDisplay: l.displayName,
            rightDisplay: r.displayName,
            leftRating: lr,
            rightRating: rr,
            leftStats: l.stats,
            rightStats: r.stats,
            leftGain: lg,
            rightLoss: rrLoss
        )
        #endif
        let oldL = l.rating100 ?? 50
        let oldR = r.rating100 ?? 50
        let newL = min(100, max(1, oldL + lg))
        let newR = min(100, max(1, oldR - rrLoss))
        let feedback = HotOrNotDuelVoteFeedback(
            left: .init(delta100: newL - oldL, rating100After: newL),
            right: .init(delta100: newR - oldR, rating100After: newR)
        )
        if duelMode == .placement {
            climbSkippedId = r.id
        }
        do {
            try await pushPerformerUpdate(performer: l, newRating: newL, won: nil, opponentId: r.id, opponentName: r.name)
            try await pushPerformerUpdate(performer: r, newRating: newR, won: nil, opponentId: l.id, opponentName: l.name)
            pendingRating100ByPerformerId[l.id] = newL
            pendingRating100ByPerformerId[r.id] = newR
            HapticManager.light()
            withAnimation(.easeOut(duration: 0.18)) {
                duelFeedback = feedback
            }
            try await Task.sleep(nanoseconds: Self.duelFeedbackDurationNs)
            withAnimation(.easeOut(duration: 0.15)) {
                duelFeedback = nil
            }
            await loadDuelPair()
            pendingRating100ByPerformerId.removeValue(forKey: l.id)
            pendingRating100ByPerformerId.removeValue(forKey: r.id)
            if section == .leaderboard { await refreshLeaderboard() }
        } catch {
            pendingRating100ByPerformerId.removeValue(forKey: l.id)
            pendingRating100ByPerformerId.removeValue(forKey: r.id)
            errorMessage = error.localizedDescription
        }
    }

    private func pushPerformerUpdate(
        performer: HotOrNotPerformerData,
        newRating: Int,
        won: Bool?,
        opponentId: String,
        opponentName: String
    ) async throws {
        let stats = HotOrNotSwissMath.updateStats(performer.stats, won: won)
        let statsJson = try HotOrNotSwissMath.encodeStats(stats)
        var records = HotOrNotSwissMath.parseMatchRecords(from: performer.custom_fields)
        let opponentField = "\(opponentId):\(opponentName)"
        records.append(HotOrNotMatchRecord(
            date: ISO8601DateFormatter().string(from: Date()),
            opponent: opponentField,
            won: won,
            ratingAfter: newRating
        ))
        if records.count > 30 { records = Array(records.suffix(30)) }
        let recordJson = try HotOrNotSwissMath.encodeMatchRecords(records)

        let partial: [String: Any] = [
            "hotornot_stats": statsJson,
            "performer_record": recordJson
        ]
        let input: [String: Any] = [
            "id": performer.id,
            "rating100": newRating,
            "custom_fields": ["partial": partial] as [String: Any]
        ]
        let mutation = """
        mutation HotOrNotPerformerUpdate($input: PerformerUpdateInput!) {
          performerUpdate(input: $input) { id rating100 }
        }
        """
        let res: HotOrNotMutationResponse = try await client.execute(
            query: mutation,
            variables: ["input": input]
        )
        if res.data?.performerUpdate == nil {
            throw NSError(domain: "HotOrNot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }
    }
}

// MARK: - UI

struct HotOrNotToolsView: View {
    @StateObject private var model = HotOrNotViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Avoids re-running `loadDuelPair` when returning from `NavigationLink` (e.g. Profile): `.task` restarts after disappear/reappear.
    @State private var didRunInitialHotOrNotLoad = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            if let err = model.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Tools.contentPadding)
            }

            ToolsPillMenuRow(
                items: HotOrNotViewModel.Section.allCases.map {
                    ToolsPillMenuRow.Item(id: $0.rawValue, title: $0.rawValue)
                },
                selectionID: model.section.rawValue,
                accessibilityLabel: "Match section"
            ) { id in
                if let section = HotOrNotViewModel.Section(rawValue: id) {
                    model.section = section
                }
            }

            switch model.section {
            case .battle:
                battleContent
            case .leaderboard:
                leaderboardContent
            case .settings:
                HotOrNotPoolSettingsView(viewModel: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if shouldShowDuelActionsAboveFloatingBar {
                    hotOrNotDuelActionsRow
                        .toolsHorizontalPadding(horizontalSizeClass)
                }
                // Mode pills only while playing — not on Charts / Settings.
                if model.section == .battle {
                    hotOrNotBottomChrome
                }
            }
        }
        .onAppear {
            guard !didRunInitialHotOrNotLoad else { return }
            didRunInitialHotOrNotLoad = true
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.selectedGenders) { _, _ in
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.duelMode) { _, _ in
            model.resetClimbStatePreservingMode()
            Task { await model.loadDuelPair() }
        }
        .onChange(of: model.section) { _, newSection in
            if newSection == .leaderboard {
                Task { await model.refreshLeaderboard() }
            }
        }
    }

    /// Gleiche Logik wie der Zweig in `battleContent` mit Karten + Aktionen (kein Sieger-/Rise-Start-UI).
    private var shouldShowDuelActionsAboveFloatingBar: Bool {
        guard model.section == .battle else { return false }
        guard model.climbVictory == nil else { return false }
        guard !model.needsPlacementStarterSelection else { return false }
        if model.isLoadingPair && model.left == nil { return false }
        return model.left != nil && model.right != nil
    }

    /// Zeile mit Draw, New pair, Stop — direkt über dem unteren Modus/Charts-Chrome (Scroll-Bereich bleibt frei).
    @ViewBuilder
    private var hotOrNotDuelActionsRow: some View {
        HStack(spacing: 10) {
            if model.duelMode == .champion {
                Button {
                    HapticManager.light()
                    model.startNewClimbRun()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
                .accessibilityLabel("End Legend run")
            } else {
                Button {
                    Task { await model.skipDraw() }
                } label: {
                    Label("Draw", systemImage: "equal.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
            }

            if model.duelMode == .placement {
                Button(action: {}) {
                    Label("New pair", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityLabel("New pair, not available in Rise")

                Button {
                    HapticManager.light()
                    model.startNewClimbRun()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
                .disabled(model.isSubmitting)
                .accessibilityLabel("End Rise run")
            } else {
                Button {
                    Task { await model.loadDuelPair() }
                } label: {
                    Label("New pair", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
                .disabled(model.isSubmitting || model.isLoadingPair)
            }
        }
    }

    /// Bottom chrome: duel mode pills only.
    private var hotOrNotBottomChrome: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            hotOrNotDuelModeChip(.headToHead)
            hotOrNotDuelModeChip(.placement)
            hotOrNotDuelModeChip(.champion)
        }
        .padding(.horizontal, StashyExpandingDock.edgePadding)
        .padding(.bottom, DesignTokens.Chrome.fabBottomPadding)
    }

    private func hotOrNotDuelModeChip(_ mode: HotOrNotViewModel.DuelMode) -> some View {
        let selected = model.section == .battle && model.duelMode == mode
        return Button {
            HapticManager.selection()
            model.section = .battle
            if model.duelMode != mode {
                model.duelMode = mode
            }
        } label: {
            Text(mode.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(height: StashyExpandingDock.activeHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? appearance.tintColor : Color.secondary.opacity(0.15))
                        .shadow(
                            color: selected ? appearance.tintColor.opacity(0.35) : .clear,
                            radius: 6,
                            x: 0,
                            y: 3
                        )
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(mode.label) mode\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var placementStarterInline: some View {
        VStack(spacing: 10) {
            if model.isLoadingPlacementStarters && model.placementStarters.isEmpty {
                StandardLoadingView(message: "Loading starters...")
                    .frame(minHeight: 220)
            } else if model.placementStarters.isEmpty {
                ContentUnavailableView(
                    "No starters",
                    systemImage: "person.2.slash",
                    description: Text(model.errorMessage ?? "")
                )
            } else {
                LazyVGrid(
                    columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass, compact: 3, regular: 3, spacing: 12),
                    spacing: 12
                ) {
                    ForEach(Array(model.placementStarters.prefix(6)), id: \.id) { p in
                        HotOrNotGauntletStarterPickCard(
                            model: model,
                            performer: p,
                            onPick: { model.pickPlacementStarter(p) }
                        )
                    }
                }
            }
        }
    }

    private var battleContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let victor = model.climbVictory {
                    VStack(spacing: 12) {
                        Text("Legend!")
                            .font(.title2.weight(.bold))
                        Text(victor.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("\(model.climbWins) wins · cleared the ladder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            model.startNewClimbRun()
                        } label: {
                            Text("New run")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.tintColor)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondaryAppBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .cardShadow()
                } else if model.needsPlacementStarterSelection {
                    placementStarterInline
                } else if model.isLoadingPair && model.left == nil {
                    StandardLoadingView(message: "Loading pair...")
                        .frame(minHeight: 320)
                } else if let l = model.left, let r = model.right {
                    HStack(alignment: .top, spacing: isRegular ? 20 : 10) {
                        VStack(spacing: 10) {
                            HotOrNotBattleColumn(
                                model: model,
                                performer: l,
                                rank: model.rankLeft,
                                voteFeedback: model.duelFeedback?.left,
                                choose: { Task { await model.choose(leftWins: true) } }
                            )
                            HotOrNotProfileLinkCard(performer: l)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 10) {
                            HotOrNotBattleColumn(
                                model: model,
                                performer: r,
                                rank: model.rankRight,
                                voteFeedback: model.duelFeedback?.right,
                                choose: { Task { await model.choose(leftWins: false) } }
                            )
                            HotOrNotProfileLinkCard(performer: r)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: isRegular ? 920 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
        }
    }

    private var leaderboardContent: some View {
        Group {
            if model.isLoadingBoard && model.leaderboard.isEmpty {
                StandardLoadingView(message: "Loading charts...")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        LazyVGrid(columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass), spacing: 12) {
                            ForEach(Array(model.leaderboard.enumerated()), id: \.element.id) { index, p in
                                NavigationLink {
                                    PerformerDetailView(performer: p.toPerformerStub())
                                } label: {
                                    HotOrNotLeaderboardCard(model: model, performer: p, place: index + 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if model.leaderboardHasMore {
                            PaginationLoadingFooter()
                                .onAppear {
                                    Task { await model.loadMoreLeaderboard() }
                                }
                        }
                    }
                    .toolsHorizontalPadding(horizontalSizeClass)
                    .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                }
            }
        }
    }
}

// MARK: - Leaderboard card

private struct HotOrNotLeaderboardCard: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let place: Int

    private static let thumbWidth: CGFloat = 68
    private static let thumbHeight: CGFloat = 90

    private var s: HotOrNotStats { performer.stats }

    private var ratingDisplay: String {
        "\(performer.rating100 ?? 50)"
    }

    private var streakSummaryLine: String? {
        let parts: [String] = [
            s.current_streak != 0 ? "Current \(streakSigned(s.current_streak))" : nil,
            s.best_streak > 0 ? "Best +\(s.best_streak)" : nil,
            s.worst_streak < 0 ? "Worst \(s.worst_streak)" : nil
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func streakSigned(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }

    private var thumbCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: Self.thumbWidth)
            VStack(alignment: .leading, spacing: 6) {
                Text(performer.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                hotOrNotStatsBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            thumbnailWithRank
                .frame(width: Self.thumbWidth)
                .frame(maxHeight: .infinity)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
    }

    private var thumbnailClip: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: thumbCornerRadius,
            bottomLeadingRadius: thumbCornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
    }

    private var thumbnailWithRank: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailClip
                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    photoOverlay
                }
                .clipShape(thumbnailClip)

            Text("#\(place)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding([.trailing, .bottom], 4)
        }
        .frame(minWidth: Self.thumbWidth, maxWidth: Self.thumbWidth, maxHeight: .infinity)
    }

    private var hotOrNotStatsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                leaderboardStatColumn(title: "Rating", value: ratingDisplay)
                leaderboardStatColumn(title: "Duels", value: "\(s.total_matches)")
                leaderboardStatColumn(title: "W", value: "\(s.wins)")
                leaderboardStatColumn(title: "L", value: "\(s.losses)")
                leaderboardStatColumn(title: "D", value: "\(s.draws)")
            }

            if let streak = streakSummaryLine {
                Text(streak)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func leaderboardStatColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var photoOverlay: some View {
        Group {
            if let url = model.thumbnailURL(for: performer) {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(scale: .medium)
                    } else if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(minWidth: Self.thumbWidth, maxWidth: .infinity, minHeight: Self.thumbHeight, maxHeight: .infinity)
        .clipped()
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.title2)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }
}

// MARK: - Pool settings (inline Settings section)

private struct HotOrNotPoolSettingsView: View {
    @ObservedObject var viewModel: HotOrNotViewModel
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let genderRows: [(code: String, label: String)] = [
        ("FEMALE", "Female"),
        ("MALE", "Male"),
        ("TRANSGENDER_FEMALE", "Transgender (female)"),
        ("TRANSGENDER_MALE", "Transgender (male)"),
        ("NON_BINARY", "Non-binary"),
        ("INTERSEX", "Intersex")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Genders in pool")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(Self.genderRows.enumerated()), id: \.element.code) { index, row in
                        Toggle(isOn: genderBinding(code: row.code)) {
                            Text(row.label)
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(appearance.tintColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)

                        if index < Self.genderRows.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .cardShadow()
                .toolsHorizontalPadding(horizontalSizeClass)
                .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func genderBinding(code: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedGenders.contains(code) },
            set: { newValue in
                let was = viewModel.selectedGenders.contains(code)
                guard newValue != was else { return }
                viewModel.toggleGender(code)
            }
        )
    }
}

#endif
