package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

// Pure Match (Hot or Not) math — no Android APIs, unit tested in `MatchEloTest`.
// Everything here mirrors `HotOrNotSwissMath` in `stashy/HotOrNotToolsView.swift` 1:1, including
// the Ascension-plugin compatible `custom_fields` keys and JSON formats.

/**
 * iOS: `HotOrNotStats` — Ascension plugin `hotornot_stats` (JSON keys `total_matches`, `wins`,
 * `losses`, `draws`, `current_streak`, `best_streak`, `worst_streak`, `last_match`).
 */
data class MatchStats(
    val totalMatches: Int = 0,
    val wins: Int = 0,
    val losses: Int = 0,
    val draws: Int = 0,
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    val worstStreak: Int = 0,
    val lastMatch: String? = null,
) {
    companion object {
        val Empty = MatchStats()
    }
}

/** iOS: `HotOrNotMatchRecord` — one entry of the plugin's `performer_record` JSON array. */
data class MatchRecord(
    val date: String,
    /** `"<opponentId>:<opponentName>"`. */
    val opponent: String,
    /** `true` win, `false` loss, `null` draw (key omitted in JSON). */
    val won: Boolean?,
    val ratingAfter: Int,
)

/**
 * iOS: `HotOrNotViewModel.DuelMode`. [raw] is the persisted value (`stashy.hotOrNot.duelMode`),
 * [ascensionMode] the plugin mode string used by the K factor / outcome math.
 */
enum class MatchDuelMode(val raw: String, val label: String, val ascensionMode: String) {
    HeadToHead("headToHead", "1 vs. 1", "swiss"),
    Placement("placement", "Rise", "gauntlet"),
    Champion("champion", "Legend", "champion");

    companion object {
        /** iOS: `duelMode(migratingPersistedRaw:)` — legacy `swiss` / `gauntlet` values. */
        fun migrating(raw: String?): MatchDuelMode = when (raw) {
            "swiss", "headToHead" -> HeadToHead
            "gauntlet", "placement" -> Placement
            "champion" -> Champion
            else -> HeadToHead
        }
    }
}

/** iOS: `HotOrNotDuelVoteFeedback.Side` — change of `rating100` and the clamped new value. */
data class MatchVoteSide(val delta100: Int, val rating100After: Int)

/** iOS: `HotOrNotDuelVoteFeedback`. */
data class MatchVoteFeedback(val left: MatchVoteSide, val right: MatchVoteSide)

/** Result of one vote / draw: new ratings of both performers plus the per-side feedback. */
data class MatchVoteResult(
    val winnerOld: Int,
    val loserOld: Int,
    val winnerNew: Int,
    val loserNew: Int,
    val gain: Int,
    val loss: Int,
) {
    val winnerDelta: Int get() = winnerNew - winnerOld
    val loserDelta: Int get() = loserNew - loserOld
}

/** iOS: `HotOrNotSwissMath` (math aligned with Ascension `ascension.js` / `math-utils.js`). */
object MatchElo {
    const val STATS_KEY = "hotornot_stats"
    const val RECORD_KEY = "performer_record"
    const val ELO_MATCHES_KEY = "elo_matches"

    /** Unrated performers count as 50 everywhere (`rating100 ?? 50`). */
    const val DEFAULT_RATING = 50
    /** `performer_record` keeps the last 30 matches. */
    const val MAX_RECORDS = 30

    /**
     * Elo spread for the 1–100 `rating100` scale. Deliberate deviation from the Ascension plugin
     * (which divides by 400): a 10-point gap is a ~64 % favourite, 40 points ~91 %.
     */
    const val ELO_SCALE = 40.0

    private val plainJson = Json { ignoreUnknownKeys = true }

    // MARK: Rounding helpers (Swift semantics)

    /** Swift `Double.rounded()` / C `round()` — to nearest, halves away from zero. */
    fun swiftRound(x: Double): Double {
        if (x.isNaN() || x.isInfinite()) return x
        val a = abs(x)
        val f = floor(a)
        val r = if (a - f >= 0.5) f + 1 else f
        return if (x < 0) -r else r
    }

    fun rating(p: Performer): Int = p.rating100 ?: DEFAULT_RATING

    // MARK: Stats parsing

    /**
     * iOS: `intFromStashJSON` — `custom_fields.hotornot_stats` as a structured object: ints,
     * doubles (rounded), numeric strings; anything else 0.
     */
    private fun intFromStashJSON(v: JsonElement?): Int {
        val p = v as? JsonPrimitive ?: return 0
        if (p is JsonNull) return 0
        if (p.isString) return p.content.toIntOrNull() ?: 0
        p.content.toLongOrNull()?.let { return it.toInt() }
        p.content.toDoubleOrNull()?.let { return swiftRound(it).toInt() }
        return 0
    }

    /** Strict `Codable` decode of the plugin JSON string (missing keys = 0; wrong types fail). */
    private fun decodeStatsJson(json: String): MatchStats? {
        val obj = runCatching { plainJson.parseToJsonElement(json) }.getOrNull() as? JsonObject ?: return null
        fun int(key: String): Int? {
            val v = obj[key] ?: return 0
            if (v is JsonNull) return 0
            val p = v as? JsonPrimitive ?: return null
            if (p.isString) return null
            p.content.toLongOrNull()?.let { return it.toInt() }
            val d = p.content.toDoubleOrNull() ?: return null
            return if (d == floor(d)) d.toInt() else null
        }
        val lastMatch: String? = when (val v = obj["last_match"]) {
            null, is JsonNull -> null
            is JsonPrimitive -> if (v.isString) v.content else return null
            else -> return null
        }
        return MatchStats(
            totalMatches = int("total_matches") ?: return null,
            wins = int("wins") ?: return null,
            losses = int("losses") ?: return null,
            draws = int("draws") ?: return null,
            currentStreak = int("current_streak") ?: return null,
            bestStreak = int("best_streak") ?: return null,
            worstStreak = int("worst_streak") ?: return null,
            lastMatch = lastMatch,
        )
    }

    /**
     * iOS: `parseStats(from:)` — `hotornot_stats` as JSON string (plugin), as object (GraphQL),
     * else the legacy `elo_matches` count, else empty.
     */
    fun parseStats(customFields: JsonObject?): MatchStats {
        val fields = customFields ?: return MatchStats.Empty
        val raw = fields[STATS_KEY]
        if (raw is JsonPrimitive && raw !is JsonNull && raw.isString) {
            decodeStatsJson(raw.content)?.let { return it }
        }
        if (raw is JsonObject) {
            return MatchStats(
                totalMatches = intFromStashJSON(raw["total_matches"]),
                wins = intFromStashJSON(raw["wins"]),
                losses = intFromStashJSON(raw["losses"]),
                draws = intFromStashJSON(raw["draws"]),
                currentStreak = intFromStashJSON(raw["current_streak"]),
                bestStreak = intFromStashJSON(raw["best_streak"]),
                worstStreak = intFromStashJSON(raw["worst_streak"]),
                lastMatch = (raw["last_match"] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content,
            )
        }
        val elo = fields[ELO_MATCHES_KEY]
        if (elo is JsonPrimitive && elo !is JsonNull && elo.isString) {
            elo.content.toIntOrNull()?.let { return MatchStats.Empty.copy(totalMatches = it) }
        }
        return MatchStats.Empty
    }

    fun stats(p: Performer): MatchStats = parseStats(p.customFields)

    // MARK: Pairing weights

    /** Parses ISO 8601 with or without fractional seconds (iOS `isoParser` / `isoParserPlain`). */
    fun parseISODate(raw: String): Long? =
        runCatching { OffsetDateTime.parse(raw).toInstant().toEpochMilli() }.getOrNull()

    /** iOS: `recencyWeight(stats:)` — 0.7 without a parsable `last_match`, else `min(1, 1 − e^(−0.2·h))`. */
    fun recencyWeight(stats: MatchStats, nowMillis: Long = System.currentTimeMillis()): Double {
        val raw = stats.lastMatch ?: return 0.7
        val d = parseISODate(raw) ?: return 0.7
        val hours = (nowMillis - d) / 1000.0 / 3600.0
        return min(1.0, 1 - exp(-0.2 * hours))
    }

    /** iOS: `weightedPick(items:weights:)`. */
    fun <T> weightedPick(items: List<T>, weights: List<Double>, random: Random = Random.Default): T? {
        if (items.size != weights.size || items.isEmpty()) return null
        val total = weights.sum()
        if (total <= 0) return items.random(random)
        var r = random.nextDouble(0.0, total)
        for ((i, w) in weights.withIndex()) {
            r -= w
            if (r <= 0) return items[i]
        }
        return items.last()
    }

    // MARK: Elo

    /** iOS: `matchCountForProgressive` — `total_matches` with fallback to played games. */
    fun matchCountForProgressive(stats: MatchStats): Int =
        max(stats.totalMatches, stats.wins + stats.losses + stats.draws)

    /** Expected score of the winner: `1 / (1 + 10^((loser − winner) / 40))`. */
    fun expectedScore(winnerRating: Double, loserRating: Double): Double =
        1 / (1 + 10.0.pow((loserRating - winnerRating) / ELO_SCALE))

    /** iOS: `getProgressiveKFactor(rating:matchCount:mode:)` (`swiss` | `gauntlet` | `champion`). */
    fun progressiveKFactor(rating: Double, matchCount: Int, mode: String): Int {
        val count = max(0, matchCount)
        val experienceFactor = 0.5 + 0.5 / (1 + exp((count - 18).toDouble() / 6))
        var baseK = 32.0 * experienceFactor
        if (rating > 60) {
            val reductionFactor = max(0.5, 1 - (rating - 60) / 70)
            baseK *= reductionFactor
        }
        if (mode == "champion") {
            val k = swiftRound(baseK * 0.85)
            return min(35, max(6, k.toInt()))
        }
        if (mode == "gauntlet") {
            val k = swiftRound(baseK * 1.1)
            return min(45, max(8, k.toInt()))
        }
        return min(40, max(6, swiftRound(baseK).toInt()))
    }

    /** iOS: `getUnderdogMultiplier`. */
    fun underdogMultiplier(winnerRating: Double, loserRating: Double): Double {
        val diff = loserRating - winnerRating
        if (diff > 30) return 1.5
        if (diff > 20) return 1.3
        if (diff > 10) return 1.1
        return 1.0
    }

    /** iOS: `getChallengeProtectionMultiplier` — a lower-rated loser loses less. */
    fun challengeProtectionMultiplier(loserRating: Double, winnerRating: Double): Double {
        val diff = winnerRating - loserRating
        if (diff > 15) {
            if (diff > 30) return 0.7
            if (diff > 25) return 0.8
            if (diff > 20) return 0.85
            return 0.9
        }
        return 1.0
    }

    /**
     * iOS: `calculateMatchOutcome` — returns `(winnerGain, loserLoss)` in `rating100` points.
     * Loser loss is `K × (1 − E_winner)` (iOS deviation from the plugin's `K × E_winner`).
     */
    fun calculateMatchOutcome(
        winnerRating: Double,
        loserRating: Double,
        mode: String,
        winnerMatchCount: Int,
        loserMatchCount: Int,
        winnerStats: MatchStats,
        @Suppress("UNUSED_PARAMETER") loserStats: MatchStats,
        isSpecialChallenge: Boolean = false,
    ): Pair<Int, Int> {
        val expectedWinner = expectedScore(winnerRating, loserRating)
        val winnerK = progressiveKFactor(winnerRating, winnerMatchCount, mode).toDouble()
        val loserK = progressiveKFactor(loserRating, loserMatchCount, mode).toDouble()
        val winnerUnderdogMult = underdogMultiplier(winnerRating, loserRating)
        val lossProtection = if (isSpecialChallenge) 0.1 else challengeProtectionMultiplier(loserRating, winnerRating)
        var winnerGain = swiftRound(winnerK * (1 - expectedWinner) * winnerUnderdogMult)
        var loserLoss = swiftRound(loserK * (1 - expectedWinner) * lossProtection)

        if (mode == "gauntlet") {
            val currentStreak = winnerStats.currentStreak
            if (currentStreak >= 3) {
                val gauntletDampener = max(0.3, 1 - (currentStreak - 3).toDouble() * 0.15)
                winnerGain = ceil(winnerGain * gauntletDampener)
            }
        }
        if (mode == "champion") {
            val winStreak = winnerStats.currentStreak
            if (winStreak >= 5) {
                val streakPenalty = if (winStreak >= 10) 0.4 else 0.7
                winnerGain = ceil(winnerGain * streakPenalty)
            }
        }
        if (winnerRating >= 85) {
            winnerGain = ceil(winnerGain * 0.6)
        } else if (winnerRating >= 70) {
            winnerGain = ceil(winnerGain * 0.8)
        }
        if (winnerRating < loserRating - 20) {
            val ratingDiff2 = loserRating - winnerRating
            val scaleFactor = max(0.3, 1 - (ratingDiff2 - 20) / 100)
            winnerGain = ceil(winnerGain * scaleFactor)
            loserLoss = ceil(loserLoss * scaleFactor)
            loserLoss = min(loserLoss, 5.0)
        }
        if (loserRating < winnerRating - 15) {
            val gap = winnerRating - loserRating
            val mitigationFactor = max(0.2, 1 - gap / 45)
            loserLoss = ceil(loserLoss * mitigationFactor)
            if (gap > 25) loserLoss = min(loserLoss, 3.0)
        }
        return max(1, winnerGain.toInt()) to max(0, loserLoss.toInt())
    }

    /**
     * iOS: `outcomeDraw` — Ascension draw branch with the Head-to-head K curve. Returns
     * `(leftGain, rightLoss)`; both are negative when the left performer was the favourite.
     */
    fun outcomeDraw(leftRating: Double, rightRating: Double, leftMatchCount: Int, rightMatchCount: Int): Pair<Int, Int> {
        val expectedWinner = expectedScore(leftRating, rightRating)
        val wK = progressiveKFactor(leftRating, leftMatchCount, "swiss").toDouble()
        val lK = progressiveKFactor(rightRating, rightMatchCount, "swiss").toDouble()
        val leftGain = swiftRound(wK * (0.5 - expectedWinner)).toInt()
        val rightLoss = swiftRound(lK * (1 - expectedWinner - 0.5)).toInt()
        return leftGain to rightLoss
    }

    /** `min(100, max(1, value))` — the `rating100` range Match writes. */
    fun clampRating100(value: Int): Int = min(100, max(1, value))

    /** iOS: `choose(leftWins:)` — outcome plus the clamped new ratings of winner and loser. */
    fun vote(winner: Performer, loser: Performer, mode: MatchDuelMode): MatchVoteResult {
        val ws = stats(winner)
        val ls = stats(loser)
        val wr = rating(winner).toDouble()
        val lr = rating(loser).toDouble()
        val (gain, loss) = calculateMatchOutcome(
            winnerRating = wr, loserRating = lr, mode = mode.ascensionMode,
            winnerMatchCount = matchCountForProgressive(ws), loserMatchCount = matchCountForProgressive(ls),
            winnerStats = ws, loserStats = ls, isSpecialChallenge = false,
        )
        val oldW = rating(winner)
        val oldL = rating(loser)
        return MatchVoteResult(oldW, oldL, clampRating100(oldW + gain), clampRating100(oldL - loss), gain, loss)
    }

    /** iOS: `skipDraw()` — left takes `+leftGain`, right `−rightLoss` (winner = left, loser = right). */
    fun draw(left: Performer, right: Performer): MatchVoteResult {
        val (lg, rl) = outcomeDraw(
            rating(left).toDouble(), rating(right).toDouble(),
            matchCountForProgressive(stats(left)), matchCountForProgressive(stats(right)),
        )
        val oldL = rating(left)
        val oldR = rating(right)
        return MatchVoteResult(oldL, oldR, clampRating100(oldL + lg), clampRating100(oldR - rl), lg, rl)
    }

    /** Feedback for the two cards; [leftWins] maps winner/loser back to left/right. */
    fun feedback(result: MatchVoteResult, leftWins: Boolean): MatchVoteFeedback {
        val w = MatchVoteSide(result.winnerDelta, result.winnerNew)
        val l = MatchVoteSide(result.loserDelta, result.loserNew)
        return if (leftWins) MatchVoteFeedback(w, l) else MatchVoteFeedback(l, w)
    }

    // MARK: Stats update

    /** iOS: `updateStats(_:won:)` — `won == null` is a draw (streaks untouched). */
    fun updateStats(current: MatchStats, won: Boolean?, nowISO: String = nowISOFractional()): MatchStats {
        var n = current.copy(totalMatches = current.totalMatches + 1, lastMatch = nowISO)
        if (won == null) return n.copy(draws = current.draws + 1)
        n = if (won) {
            n.copy(wins = current.wins + 1, currentStreak = if (current.currentStreak >= 0) current.currentStreak + 1 else 1)
        } else {
            n.copy(losses = current.losses + 1, currentStreak = if (current.currentStreak <= 0) current.currentStreak - 1 else -1)
        }
        return n.copy(
            bestStreak = max(current.bestStreak, n.currentStreak),
            worstStreak = min(current.worstStreak, n.currentStreak),
        )
    }

    private val fractionalFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).withZone(ZoneOffset.UTC)
    private val plainFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).withZone(ZoneOffset.UTC)

    /** iOS `ISO8601DateFormatter` with `.withFractionalSeconds` (stats `last_match`). */
    fun nowISOFractional(nowMillis: Long = System.currentTimeMillis()): String = fractionalFormatter.format(Instant.ofEpochMilli(nowMillis))

    /** iOS default `ISO8601DateFormatter()` (record `date`). */
    fun nowISOPlain(nowMillis: Long = System.currentTimeMillis()): String = plainFormatter.format(Instant.ofEpochMilli(nowMillis))

    // MARK: JSON encoding (Swift JSONEncoder, `.sortedKeys`, compact)

    /** Swift `JSONEncoder` string escaping (it also escapes `/` as `\/`). */
    fun swiftJSONString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) {
            when (c) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '/' -> sb.append("\\/")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '\u000C' -> sb.append("\\f")
                else -> if (c < ' ') sb.append(String.format(Locale.US, "\\u%04x", c.code)) else sb.append(c)
            }
        }
        return sb.append('"').toString()
    }

    /** iOS: `encodeStats` — sorted keys; `last_match` omitted when null. */
    fun encodeStats(s: MatchStats): String {
        val parts = mutableListOf(
            "\"best_streak\":${s.bestStreak}",
            "\"current_streak\":${s.currentStreak}",
            "\"draws\":${s.draws}",
        )
        s.lastMatch?.let { parts += "\"last_match\":${swiftJSONString(it)}" }
        parts += listOf(
            "\"losses\":${s.losses}",
            "\"total_matches\":${s.totalMatches}",
            "\"wins\":${s.wins}",
            "\"worst_streak\":${s.worstStreak}",
        )
        return parts.joinToString(",", "{", "}")
    }

    /** iOS: `parseMatchRecords(from:)` — only a JSON string under `performer_record`; any decode error → empty. */
    fun parseMatchRecords(customFields: JsonObject?): List<MatchRecord> {
        val raw = customFields?.get(RECORD_KEY) as? JsonPrimitive ?: return emptyList()
        if (raw is JsonNull || !raw.isString) return emptyList()
        val arr = runCatching { plainJson.parseToJsonElement(raw.content) }.getOrNull() as? JsonArray ?: return emptyList()
        val out = ArrayList<MatchRecord>(arr.size)
        for (e in arr) {
            val o = e as? JsonObject ?: return emptyList()
            val date = (o["date"] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content ?: return emptyList()
            val opponent = (o["opponent"] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content ?: return emptyList()
            val ratingP = (o["ratingAfter"] as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString } ?: return emptyList()
            val ratingAfter = ratingP.content.toIntOrNull()
                ?: ratingP.content.toDoubleOrNull()?.takeIf { it == floor(it) }?.toInt()
                ?: return emptyList()
            val won: Boolean? = when (val w = o["won"]) {
                null, is JsonNull -> null
                is JsonPrimitive -> if (!w.isString && (w.content == "true" || w.content == "false")) w.content == "true" else return emptyList()
                else -> return emptyList()
            }
            out += MatchRecord(date, opponent, won, ratingAfter)
        }
        return out
    }

    /** Appends [record] and keeps the last [MAX_RECORDS]. */
    fun appendRecord(records: List<MatchRecord>, record: MatchRecord): List<MatchRecord> {
        val all = records + record
        return if (all.size > MAX_RECORDS) all.takeLast(MAX_RECORDS) else all
    }

    /** iOS: `encodeMatchRecords` — sorted keys (`date`, `opponent`, `ratingAfter`, `won`); `won` omitted for draws. */
    fun encodeMatchRecords(records: List<MatchRecord>): String =
        records.joinToString(",", "[", "]") { r ->
            buildString {
                append("{\"date\":").append(swiftJSONString(r.date))
                append(",\"opponent\":").append(swiftJSONString(r.opponent))
                append(",\"ratingAfter\":").append(r.ratingAfter)
                r.won?.let { append(",\"won\":").append(it) }
                append('}')
            }
        }

    /**
     * iOS: `pushPerformerUpdate` — the `PerformerUpdateInput` written after a duel:
     * `{ id, rating100, custom_fields: { partial: { hotornot_stats, performer_record } } }`.
     */
    fun performerUpdateInput(performerId: String, newRating: Int, statsJson: String, recordJson: String): JsonObject =
        buildJsonObject {
            put("id", JsonPrimitive(performerId))
            put("rating100", JsonPrimitive(newRating))
            put("custom_fields", buildJsonObject {
                put("partial", buildJsonObject {
                    put(STATS_KEY, JsonPrimitive(statsJson))
                    put(RECORD_KEY, JsonPrimitive(recordJson))
                })
            })
        }

    /** Builds the full update for [performer] after a match (stats + record appended). */
    fun buildPerformerUpdate(
        performer: Performer,
        newRating: Int,
        won: Boolean?,
        opponentId: String,
        opponentName: String,
        nowMillis: Long = System.currentTimeMillis(),
    ): JsonObject {
        val stats = updateStats(stats(performer), won, nowISOFractional(nowMillis))
        val records = appendRecord(
            parseMatchRecords(performer.customFields),
            MatchRecord(nowISOPlain(nowMillis), "$opponentId:$opponentName", won, newRating),
        )
        return performerUpdateInput(performer.id, newRating, encodeStats(stats), encodeMatchRecords(records))
    }

    // MARK: Card info

    /** iOS: `hotOrNotBattleFixedInfoRows` — fixed 3×2 grid, empty → "—". */
    fun battleInfoRows(p: Performer): List<Pair<String, String>> {
        val dash = "—"
        val rating = "${p.rating100 ?: DEFAULT_RATING}"
        val genderVal = p.gender?.trim()?.takeIf { it.isNotEmpty() } ?: dash
        val scenesVal = "${p.sceneCount ?: 0}"
        val imagesVal = "${p.imageCount ?: 0}"
        val countryVal = p.country?.trim()?.takeIf { it.isNotEmpty() } ?: dash
        fun cm(pl: Double) = String.format(Locale.US, "%.0f cm", pl)
        val titsVal: String = run {
            val g = p.gender?.uppercase() ?: ""
            val tits = p.fakeTits?.trim()?.takeIf { it.isNotEmpty() }
            val pl = p.penisLength?.takeIf { it > 0 }
            if (g.contains("FEMALE")) return@run tits ?: dash
            if (g.contains("MALE") || g == "MAN") return@run pl?.let(::cm) ?: dash
            tits ?: pl?.let(::cm) ?: dash
        }
        return listOf(
            "RATING" to rating,
            "GENDER" to genderVal,
            "SCENES" to scenesVal,
            "IMAGES" to imagesVal,
            "COUNTRY" to countryVal,
            "TITS" to titsVal,
        )
    }

    /** iOS: leaderboard `streakSummaryLine` ("Current +3 · Best +5 · Worst -2"), null when all zero. */
    fun streakSummaryLine(s: MatchStats): String? {
        fun signed(n: Int) = if (n > 0) "+$n" else "$n"
        val parts = listOfNotNull(
            if (s.currentStreak != 0) "Current ${signed(s.currentStreak)}" else null,
            if (s.bestStreak > 0) "Best +${s.bestStreak}" else null,
            if (s.worstStreak < 0) "Worst ${s.worstStreak}" else null,
        )
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }
}

/** Pure pairing helpers of `HotOrNotViewModel` (head-to-head pick, ladder, climb opponent). */
object MatchPairing {
    /** iOS: `ladderSortedPool` — effective rating (pending merged) desc, tie-break `id` asc. */
    fun ladderSorted(list: List<Performer>, pending: Map<String, Int>): List<Performer> =
        list.map { merge(it, pending) }.sortedWith { a, b ->
            val ra = a.rating100 ?: MatchElo.DEFAULT_RATING
            val rb = b.rating100 ?: MatchElo.DEFAULT_RATING
            if (ra != rb) rb.compareTo(ra) else a.id.compareTo(b.id)
        }

    /** iOS: `mergePendingRating`. */
    fun merge(p: Performer, pending: Map<String, Int>): Performer =
        pending[p.id]?.let { p.copy(rating100 = it) } ?: p

    /**
     * iOS: `loadHeadToHeadPairContent` pick — first performer weighted by recency, second
     * weighted among those within 15 rating points (fallback: first other). Returns the two
     * indexes into [list] (server order = rank − 1), or null.
     */
    fun headToHeadIndexes(list: List<Performer>, nowMillis: Long = System.currentTimeMillis(), random: Random = Random.Default): Pair<Int, Int>? {
        if (list.size < 2) return null
        val idx = list.indices.toList()
        val weights = list.map { MatchElo.recencyWeight(MatchElo.stats(it), nowMillis) }
        val s1 = MatchElo.weightedPick(idx, weights, random) ?: return null
        val rating1 = (list[s1].rating100 ?: MatchElo.DEFAULT_RATING).toDouble()
        val similar = idx.filter { it != s1 && abs((list[it].rating100 ?: MatchElo.DEFAULT_RATING).toDouble() - rating1) <= 15 }
        val other = idx.firstOrNull { it != s1 }
        val s2 = if (similar.isEmpty() && other != null) other
        else MatchElo.weightedPick(similar, similar.map { weights[it] }, random) ?: other ?: return null
        return s1 to s2
    }

    /**
     * iOS: climb opponent for Legend / Rise — the up-to-5 lowest-ranked performers above the
     * champion that are not defeated / skipped; null when the ladder is cleared.
     */
    fun climbOpponent(
        ranked: List<Performer>,
        champIdx: Int,
        defeated: Set<String>,
        skippedId: String?,
        random: Random = Random.Default,
    ): Performer? {
        val potential = ranked.withIndex()
            .filter { it.index < champIdx && it.value.id !in defeated && it.value.id != skippedId }
            .map { it.value }
        if (potential.isEmpty()) return null
        val window = min(5, potential.size)
        val rIdx = random.nextInt(0, window)
        return potential[potential.size - 1 - rIdx]
    }
}
