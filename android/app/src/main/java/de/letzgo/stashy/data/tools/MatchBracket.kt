package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Prefs
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

// Match "32:1" — single-elimination bracket of 32 performers. Mirrors `stashy/HotOrNotBracket.swift`
// 1:1 and is unit tested in `MatchBracketTest`. No rating is written per pick: once the final is
// decided every entrant gets a rating from its finishing place, laid over the pool's rating scale
// (idea from the cherrypick plugin's `brackets.js`) — the further a performer gets, the higher.

/**
 * iOS: `HotOrNotBracketState`. The bracket is fully described by the first round plus the ordered
 * list of picked winners, so undo is dropping the last pick.
 */
@Serializable
data class MatchBracketState(
    /** Seed order: index 0 = seed 1 (highest rating at creation). */
    val entrants: List<Performer>,
    val firstRound: List<Pairing>,
    val picks: List<String> = emptyList(),
    val createdAt: Long,
    /** Performers whose result was already written (a retry after a partial Apply skips them). */
    val appliedIds: List<String> = emptyList(),
) {
    @Serializable
    data class Pairing(val leftId: String, val rightId: String)

    data class Match(val round: Int, val index: Int, val leftId: String, val rightId: String, val winnerId: String?) {
        val loserId: String? get() = winnerId?.let { if (it == leftId) rightId else leftId }
    }

    val size: Int get() = firstRound.size * 2
    val roundCount: Int get() = MatchBracket.roundCount(size)
    val totalMatches: Int get() = size - 1

    fun entrant(id: String): Performer? = entrants.firstOrNull { it.id == id }

    /** All rounds known so far; a round only exists once the previous one is complete. */
    val rounds: List<List<Match>> get() {
        val result = mutableListOf<List<Match>>()
        var pairs = firstRound.map { it.leftId to it.rightId }
        var pickIndex = 0
        for (round in 0 until roundCount) {
            val matches = pairs.mapIndexed { i, (l, r) ->
                val winner = picks.getOrNull(pickIndex)
                if (winner != null) pickIndex++
                Match(round, i, l, r, winner)
            }
            result += matches
            if (matches.any { it.winnerId == null } || matches.size <= 1) break
            pairs = matches.chunked(2).map { it[0].winnerId!! to it[1].winnerId!! }
        }
        return result
    }

    val currentMatch: Match? get() = rounds.lastOrNull()?.firstOrNull { it.winnerId == null }

    val isFinished: Boolean get() = picks.size >= totalMatches

    val championId: String? get() = if (isFinished) picks.lastOrNull() else null

    /** Tier per entrant from the round it lost in (only meaningful once finished). */
    val tiers: Map<String, MatchBracket.Tier> get() {
        val out = mutableMapOf<String, MatchBracket.Tier>()
        for (m in rounds.flatten()) {
            val loser = m.loserId ?: continue
            out[loser] = MatchBracket.Tier.eliminated(m.round, roundCount)
        }
        championId?.let { out[it] = MatchBracket.Tier.Champion }
        return out
    }

    /** Played matches of one entrant in order: opponent id + won. */
    fun results(id: String): List<Pair<String, Boolean>> =
        rounds.flatten().mapNotNull { m ->
            val w = m.winnerId ?: return@mapNotNull null
            if (m.leftId != id && m.rightId != id) return@mapNotNull null
            (if (m.leftId == id) m.rightId else m.leftId) to (w == id)
        }
}

/** iOS: `HotOrNotBracketMath`. */
object MatchBracket {
    const val SIZE = 32
    const val MAX_GAIN = 20
    const val MAX_LOSS = 12

    enum class Tier(val label: String, val slots: IntRange, val deltaBounds: IntRange) {
        Champion("Champion", 0..0, 3..MAX_GAIN),
        Finalist("Finalist", 1..1, 1..MAX_GAIN),
        Semifinal("Semifinal", 2..3, 0..MAX_GAIN),
        Quarterfinal("Quarterfinal", 4..7, -MAX_LOSS..MAX_GAIN),
        RoundOf16("Round of 16", 8..15, -MAX_LOSS..MAX_GAIN),
        RoundOf32("Round of 32", 16..31, -MAX_LOSS..0);

        companion object {
            /** Lost in [round] (0 = first round) of a bracket with [roundCount] rounds. */
            fun eliminated(round: Int, roundCount: Int): Tier =
                entries[min(RoundOf32.ordinal, roundCount - round)]
        }
    }

    data class Proposal(val id: String, val name: String, val tier: Tier, val oldRating: Int, val newRating: Int) {
        val delta: Int get() = newRating - oldRating
    }

    fun roundCount(size: Int): Int {
        var n = 0
        var s = max(1, size)
        while (s > 1) { s /= 2; n++ }
        return n
    }

    /** Standard seeding, 1-based: [1, 32, 16, 17, 8, 25, …]; seeds 1 and 2 can only meet in the final. */
    fun seedOrder(n: Int): List<Int> {
        var order = listOf(1)
        while (order.size < n) {
            val total = order.size * 2 + 1
            order = order.flatMap { listOf(it, total - it) }
        }
        return order
    }

    /**
     * Spread across the pool's rating scale: the rating-sorted pool (descending) is cut into
     * [size] equal strata and one entrant is drawn from each, weighted by `recencyWeight`
     * (entrants of the last brackets count a tenth).
     */
    fun selectEntrants(
        pool: List<Performer>,
        recentIds: Set<String>,
        size: Int = SIZE,
        nowMillis: Long = System.currentTimeMillis(),
        random: Random = Random.Default,
    ): List<Performer>? {
        if (pool.size < size) return null
        return (0 until size).map { s ->
            val stratum = pool.subList(s * pool.size / size, (s + 1) * pool.size / size)
            val weights = stratum.map { p ->
                val w = max(0.05, MatchElo.recencyWeight(MatchElo.stats(p), nowMillis))
                if (p.id in recentIds) w * 0.1 else w
            }
            MatchElo.weightedPick(stratum, weights, random) ?: return null
        }
    }

    fun newBracket(
        pool: List<Performer>,
        recentIds: Set<String>,
        size: Int = SIZE,
        nowMillis: Long = System.currentTimeMillis(),
        random: Random = Random.Default,
    ): MatchBracketState? {
        val picked = selectEntrants(pool, recentIds, size, nowMillis, random) ?: return null
        val seeded = picked.sortedWith { a, b ->
            val ra = MatchElo.rating(a)
            val rb = MatchElo.rating(b)
            if (ra != rb) rb.compareTo(ra) else a.id.compareTo(b.id)
        }
        val order = seedOrder(size)
        val pairs = (0 until size step 2).map { i ->
            val a = seeded[order[i] - 1].id
            val b = seeded[order[i + 1] - 1].id
            if (random.nextBoolean()) MatchBracketState.Pairing(a, b) else MatchBracketState.Pairing(b, a)
        }
        return MatchBracketState(entrants = seeded, firstRound = pairs, createdAt = nowMillis)
    }

    /** Rating at quantile [q] (0 = top) of the descending pool ratings. */
    fun poolQuantile(sortedDesc: List<Int>, q: Double): Double {
        if (sortedDesc.isEmpty()) return MatchElo.DEFAULT_RATING.toDouble()
        val idx = min(sortedDesc.size - 1, max(0, (q * sortedDesc.size).toInt()))
        return sortedDesc[idx].toDouble()
    }

    /** Target rating of a tier: mean pool rating at the tier's finishing slots. */
    fun target(tier: Tier, poolRatingsDesc: List<Int>): Double =
        tier.slots.sumOf { poolQuantile(poolRatingsDesc, (it + 0.5) / SIZE) } / (tier.slots.last - tier.slots.first + 1)

    /** How far a result moves the rating towards the tier target; settled performers move less. */
    fun blendWeight(matchCount: Int): Double = when {
        matchCount < 5 -> 0.6
        matchCount < 15 -> 0.45
        else -> 0.3
    }

    fun newRating(old: Int, tier: Tier, matchCount: Int, poolRatingsDesc: List<Int>): Int {
        val t = target(tier, poolRatingsDesc)
        val raw = MatchElo.swiftRound(old + blendWeight(matchCount) * (t - old)).toInt()
        val delta = (raw - old).coerceIn(tier.deltaBounds)
        return MatchElo.clampRating100(old + delta)
    }

    /** [current] = freshly loaded entrant data (rating + stats); falls back to the bracket copy. */
    fun proposals(state: MatchBracketState, current: Map<String, Performer>, poolRatingsDesc: List<Int>): List<Proposal> {
        val tiers = state.tiers
        return state.entrants.mapNotNull { e ->
            val tier = tiers[e.id] ?: return@mapNotNull null
            val p = current[e.id] ?: e
            val old = MatchElo.rating(p)
            val mc = MatchElo.matchCountForProgressive(MatchElo.stats(p))
            Proposal(e.id, p.name, tier, old, newRating(old, tier, mc, poolRatingsDesc))
        }.sortedWith(compareBy<Proposal> { it.tier.ordinal }.thenByDescending { it.newRating })
    }

    fun roundTitle(round: Int, roundCount: Int): String = when (roundCount - round) {
        1 -> "Final"
        2 -> "Semifinal"
        3 -> "Quarterfinal"
        else -> "Round of ${1 shl (roundCount - round)}"
    }

    /** iOS: `bracketStatusLine` — "Round of 32 · Match 3/16". */
    fun statusLine(state: MatchBracketState): String? {
        val m = state.currentMatch ?: return null
        return "${roundTitle(m.round, state.roundCount)} · Match ${m.index + 1}/${state.rounds[m.round].size}"
    }

    /**
     * Builds the `performerUpdate` input for one entrant's whole run: stats folded over every
     * match, one `performer_record` entry per match.
     */
    fun performerUpdate(
        performer: Performer,
        newRating: Int,
        matches: List<Triple<String, String, Boolean>>,
        nowMillis: Long = System.currentTimeMillis(),
    ): kotlinx.serialization.json.JsonObject {
        var stats = MatchElo.stats(performer)
        var records = MatchElo.parseMatchRecords(performer.customFields)
        for ((oppId, oppName, won) in matches) {
            stats = MatchElo.updateStats(stats, won, MatchElo.nowISOFractional(nowMillis))
            records = MatchElo.appendRecord(records, MatchRecord(MatchElo.nowISOPlain(nowMillis), "$oppId:$oppName", won, newRating))
        }
        return MatchElo.performerUpdateInput(performer.id, newRating, MatchElo.encodeStats(stats), MatchElo.encodeMatchRecords(records))
    }
}

/** iOS: `HotOrNotBracketStore` — per-server state + recently played entrants. */
object MatchBracketStore {
    private const val STATE_KEY = "stashy.hotOrNot.bracket"
    private const val RECENT_KEY = "stashy.hotOrNot.bracketRecent"
    private const val RECENT_LIMIT = 64

    fun load(): MatchBracketState? {
        val raw = Prefs.string(Prefs.serverKey(STATE_KEY)) ?: return null
        return runCatching { Json.decodeFromString(MatchBracketState.serializer(), raw) }.getOrNull()
    }

    fun save(state: MatchBracketState?) {
        Prefs.setString(Prefs.serverKey(STATE_KEY), state?.let { Json.encodeToString(MatchBracketState.serializer(), it) })
    }

    fun recentIds(): Set<String> = recentList().toSet()

    fun rememberEntrants(ids: List<String>) {
        val merged = ids + recentList().filter { it !in ids }
        Prefs.setString(
            Prefs.serverKey(RECENT_KEY),
            Json.encodeToString(ListSerializer(String.serializer()), merged.take(RECENT_LIMIT)),
        )
    }

    private fun recentList(): List<String> {
        val raw = Prefs.string(Prefs.serverKey(RECENT_KEY)) ?: return emptyList()
        return runCatching { Json.decodeFromString(ListSerializer(String.serializer()), raw) }.getOrNull().orEmpty()
    }
}
