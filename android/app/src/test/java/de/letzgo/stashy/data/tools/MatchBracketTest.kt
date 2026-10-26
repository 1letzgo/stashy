package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class MatchBracketTest {
    private fun performer(id: String, rating: Int?) = Performer(id = id, name = "P$id", rating100 = rating)

    /** 100 performers rated 100 … 1, sorted descending like the pool query. */
    private val pool = (0 until 100).map { performer("$it", 100 - it) }
    private val poolRatings = pool.map { it.rating100!! }

    private fun bracket(seed: Int = 1) = MatchBracket.newBracket(pool, emptySet(), random = Random(seed))!!

    /** Plays the whole bracket, the higher seed (lower entrant index) always winning. */
    private fun playChalk(state: MatchBracketState): MatchBracketState {
        var s = state
        while (true) {
            val m = s.currentMatch ?: break
            val li = s.entrants.indexOfFirst { it.id == m.leftId }
            val ri = s.entrants.indexOfFirst { it.id == m.rightId }
            s = s.copy(picks = s.picks + if (li < ri) m.leftId else m.rightId)
        }
        return s
    }

    @Test fun seedOrderKeepsTopSeedsApart() {
        val order = MatchBracket.seedOrder(32)
        assertEquals(32, order.size)
        assertEquals((1..32).toSet(), order.toSet())
        assertEquals(listOf(1, 32, 16, 17), order.take(4))
        // Every first-round pair sums to 33.
        order.chunked(2).forEach { assertEquals(33, it[0] + it[1]) }
        // Seeds 1 and 2 sit in different halves.
        assertTrue(order.indexOf(1) < 16 && order.indexOf(2) >= 16)
    }

    @Test fun selectionTakesOnePerStratum() {
        val picked = MatchBracket.selectEntrants(pool, emptySet(), random = Random(7))!!
        assertEquals(32, picked.size)
        assertEquals(32, picked.map { it.id }.toSet().size)
        picked.forEachIndexed { s, p ->
            val idx = pool.indexOf(p)
            assertTrue(idx >= s * 100 / 32 && idx < (s + 1) * 100 / 32)
        }
    }

    @Test fun tooSmallPoolGivesNull() {
        assertNull(MatchBracket.newBracket(pool.take(31), emptySet()))
    }

    @Test fun bracketHas31MatchesAndAChampion() {
        val done = playChalk(bracket())
        assertTrue(done.isFinished)
        assertEquals(31, done.picks.size)
        assertEquals(5, done.rounds.size)
        assertEquals(listOf(16, 8, 4, 2, 1), done.rounds.map { it.size })
        assertEquals(done.entrants[0].id, done.championId)
        val tiers = done.tiers
        assertEquals(32, tiers.size)
        assertEquals(1, tiers.values.count { it == MatchBracket.Tier.Champion })
        assertEquals(1, tiers.values.count { it == MatchBracket.Tier.Finalist })
        assertEquals(2, tiers.values.count { it == MatchBracket.Tier.Semifinal })
        assertEquals(4, tiers.values.count { it == MatchBracket.Tier.Quarterfinal })
        assertEquals(8, tiers.values.count { it == MatchBracket.Tier.RoundOf16 })
        assertEquals(16, tiers.values.count { it == MatchBracket.Tier.RoundOf32 })
        // Champion played 5 matches, all won.
        assertEquals(List(5) { true }, done.results(done.championId!!).map { it.second })
    }

    @Test fun undoDropsLastPick() {
        val b = bracket()
        val m = b.currentMatch!!
        val picked = b.copy(picks = b.picks + m.leftId)
        assertEquals(1, picked.rounds[0].count { it.winnerId != null })
        val undone = picked.copy(picks = picked.picks.dropLast(1))
        assertEquals(m, undone.currentMatch)
    }

    @Test fun furtherIsBetterForEqualStart() {
        val tiers = MatchBracket.Tier.entries
        for (old in listOf(10, 50, 90)) {
            for (mc in listOf(0, 10, 40)) {
                val ratings = tiers.map { MatchBracket.newRating(old, it, mc, poolRatings) }
                // Champion ≥ Finalist ≥ … ≥ Round of 32.
                ratings.zipWithNext().forEach { (better, worse) -> assertTrue("$old/$mc $ratings", better >= worse) }
            }
        }
    }

    @Test fun tierBoundsHold() {
        for (old in 1..100) {
            for (tier in MatchBracket.Tier.entries) {
                val delta = MatchBracket.newRating(old, tier, 0, poolRatings) - old
                if (old in 4..80) assertTrue("$tier $old $delta", delta in tier.deltaBounds)
                assertTrue(delta <= MatchBracket.MAX_GAIN && delta >= -MatchBracket.MAX_LOSS)
            }
            assertTrue(MatchBracket.newRating(old, MatchBracket.Tier.RoundOf32, 0, poolRatings) <= old)
            assertTrue(MatchBracket.newRating(old, MatchBracket.Tier.Semifinal, 0, poolRatings) >= old)
        }
        // Low-rated champion gains the most it can.
        assertEquals(10 + MatchBracket.MAX_GAIN, MatchBracket.newRating(10, MatchBracket.Tier.Champion, 0, poolRatings))
        // Top-rated champion still gains.
        assertTrue(MatchBracket.newRating(100, MatchBracket.Tier.Champion, 0, poolRatings) == 100)
        assertTrue(MatchBracket.newRating(95, MatchBracket.Tier.Champion, 40, poolRatings) >= 98)
    }

    @Test fun proposalsCoverAllEntrants() {
        val done = playChalk(bracket())
        val props = MatchBracket.proposals(done, emptyMap(), poolRatings)
        assertEquals(32, props.size)
        assertEquals(MatchBracket.Tier.Champion, props.first().tier)
        assertTrue(props.zipWithNext().all { (a, b) -> a.tier.ordinal <= b.tier.ordinal })
    }

    @Test fun statusLine() {
        val b = bracket()
        assertEquals("Round of 32 · Match 1/16", MatchBracket.statusLine(b))
        var s = b
        repeat(30) { s = s.copy(picks = s.picks + s.currentMatch!!.leftId) }
        assertEquals("Final · Match 1/1", MatchBracket.statusLine(s))
        s = s.copy(picks = s.picks + s.currentMatch!!.leftId)
        assertNull(MatchBracket.statusLine(s))
        assertFalse(s.picks.isEmpty())
    }

    @Test fun performerUpdateFoldsAllMatches() {
        val input = MatchBracket.performerUpdate(
            performer("1", 50), 60,
            listOf(Triple("2", "P2", true), Triple("3", "P3", false)),
            nowMillis = 0,
        )
        val partial = (input["custom_fields"] as kotlinx.serialization.json.JsonObject)["partial"] as kotlinx.serialization.json.JsonObject
        val stats = MatchElo.parseStats(kotlinx.serialization.json.buildJsonObject { put(MatchElo.STATS_KEY, partial[MatchElo.STATS_KEY]!!) })
        assertEquals(2, stats.totalMatches)
        assertEquals(1, stats.wins)
        assertEquals(1, stats.losses)
        val records = MatchElo.parseMatchRecords(kotlinx.serialization.json.buildJsonObject { put(MatchElo.RECORD_KEY, partial[MatchElo.RECORD_KEY]!!) })
        assertEquals(listOf("2:P2", "3:P3"), records.map { it.opponent })
        assertNotNull(records.all { it.ratingAfter == 60 })
    }
}
