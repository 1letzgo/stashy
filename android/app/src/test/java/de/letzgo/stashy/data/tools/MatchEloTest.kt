package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Elo / stats math of Match, checked against values computed by hand from the Swift formulas in
 * `HotOrNotSwissMath` (`stashy/HotOrNotToolsView.swift`, Ascension-compatible, scale 40).
 */
class MatchEloTest {
    private val eps = 1e-6

    private fun performer(id: String, rating: Int?, customFields: JsonObject? = null, name: String = "P$id") =
        Performer(id = id, name = name, rating100 = rating, customFields = customFields)

    private fun statsFields(json: String) = buildJsonObject { put(MatchElo.STATS_KEY, JsonPrimitive(json)) }

    // MARK: Rounding

    @Test
    fun swiftRoundRoundsHalvesAwayFromZero() {
        assertEquals(16.0, MatchElo.swiftRound(15.5), 0.0)
        assertEquals(15.0, MatchElo.swiftRound(15.49), 0.0)
        assertEquals(-16.0, MatchElo.swiftRound(-15.5), 0.0)
        assertEquals(-6.0, MatchElo.swiftRound(-6.2339), 0.0)
        assertEquals(1.0, MatchElo.swiftRound(0.5), 0.0)
        assertEquals(0.0, MatchElo.swiftRound(0.49999999999999994), 0.0)
    }

    @Test
    fun swiftRoundTwoAndAHalfIsThree() {
        // Swift `(2.5).rounded()` == 3 (toNearestOrAwayFromZero), unlike Kotlin `round(2.5)` == 2.
        assertEquals(3.0, MatchElo.swiftRound(2.5), 0.0)
    }

    // MARK: Expected score

    @Test
    fun expectedScoreUsesScale40() {
        assertEquals(40.0, MatchElo.ELO_SCALE, 0.0)
        assertEquals(0.5, MatchElo.expectedScore(50.0, 50.0), eps)
        assertEquals(0.6400649998, MatchElo.expectedScore(60.0, 50.0), eps)
        assertEquals(0.3599350002, MatchElo.expectedScore(50.0, 60.0), eps)
        assertEquals(1.0 / 1.1, MatchElo.expectedScore(80.0, 40.0), eps)
        assertEquals(0.2402530734, MatchElo.expectedScore(40.0, 60.0), eps)
        // Symmetry: E(a,b) + E(b,a) == 1
        assertEquals(1.0, MatchElo.expectedScore(33.0, 71.0) + MatchElo.expectedScore(71.0, 33.0), eps)
    }

    // MARK: K factor

    @Test
    fun progressiveKFactorTable() {
        // rating, match count, mode → K (hand-computed from getProgressiveKFactor)
        val table = listOf(
            Triple(50, 0, "swiss") to 31, Triple(50, 0, "gauntlet") to 34, Triple(50, 0, "champion") to 27,
            Triple(50, 5, "swiss") to 30, Triple(50, 5, "gauntlet") to 33, Triple(50, 5, "champion") to 26,
            Triple(50, 18, "swiss") to 24, Triple(50, 18, "gauntlet") to 26, Triple(50, 18, "champion") to 20,
            Triple(50, 30, "swiss") to 18, Triple(50, 30, "gauntlet") to 20, Triple(50, 30, "champion") to 15,
            Triple(50, 100, "swiss") to 16, Triple(50, 100, "gauntlet") to 18, Triple(50, 100, "champion") to 14,
            Triple(74, 18, "swiss") to 19, Triple(74, 18, "gauntlet") to 21, Triple(74, 18, "champion") to 16,
            Triple(90, 0, "swiss") to 18, Triple(90, 18, "swiss") to 14, Triple(90, 30, "champion") to 9,
            Triple(95, 18, "swiss") to 12, Triple(95, 18, "gauntlet") to 13, Triple(95, 18, "champion") to 10,
            Triple(100, 100, "swiss") to 8, Triple(100, 100, "gauntlet") to 9, Triple(100, 100, "champion") to 7,
        )
        for ((args, expected) in table) {
            val (rating, count, mode) = args
            assertEquals("K($rating, $count, $mode)", expected, MatchElo.progressiveKFactor(rating.toDouble(), count, mode))
        }
    }

    @Test
    fun kFactorRatingSixtyIsNotReducedAndNegativeCountIsZero() {
        assertEquals(MatchElo.progressiveKFactor(50.0, 18, "swiss"), MatchElo.progressiveKFactor(60.0, 18, "swiss"))
        assertEquals(31, MatchElo.progressiveKFactor(50.0, -5, "swiss"))
        // Unknown mode strings use the swiss branch.
        assertEquals(24, MatchElo.progressiveKFactor(50.0, 18, "whatever"))
    }

    @Test
    fun matchCountFallsBackToPlayedGames() {
        assertEquals(7, MatchElo.matchCountForProgressive(MatchStats(totalMatches = 3, wins = 4, losses = 2, draws = 1)))
        assertEquals(10, MatchElo.matchCountForProgressive(MatchStats(totalMatches = 10, wins = 1, losses = 1, draws = 1)))
        assertEquals(0, MatchElo.matchCountForProgressive(MatchStats.Empty))
    }

    @Test
    fun multipliers() {
        assertEquals(1.0, MatchElo.underdogMultiplier(50.0, 60.0), 0.0)
        assertEquals(1.1, MatchElo.underdogMultiplier(50.0, 61.0), 0.0)
        assertEquals(1.1, MatchElo.underdogMultiplier(40.0, 60.0), 0.0)
        assertEquals(1.3, MatchElo.underdogMultiplier(30.0, 60.0), 0.0)
        assertEquals(1.5, MatchElo.underdogMultiplier(20.0, 60.0), 0.0)
        assertEquals(1.0, MatchElo.underdogMultiplier(80.0, 20.0), 0.0)

        assertEquals(1.0, MatchElo.challengeProtectionMultiplier(loserRating = 45.0, winnerRating = 60.0), 0.0)
        assertEquals(0.9, MatchElo.challengeProtectionMultiplier(loserRating = 44.0, winnerRating = 60.0), 0.0)
        assertEquals(0.85, MatchElo.challengeProtectionMultiplier(loserRating = 39.0, winnerRating = 60.0), 0.0)
        assertEquals(0.8, MatchElo.challengeProtectionMultiplier(loserRating = 34.0, winnerRating = 60.0), 0.0)
        assertEquals(0.7, MatchElo.challengeProtectionMultiplier(loserRating = 29.0, winnerRating = 60.0), 0.0)
    }

    // MARK: Outcome

    private fun outcome(w: Int, l: Int, mode: String, wmc: Int, lmc: Int, streak: Int = 0, special: Boolean = false) =
        MatchElo.calculateMatchOutcome(
            w.toDouble(), l.toDouble(), mode, wmc, lmc,
            MatchStats(currentStreak = streak), MatchStats.Empty, special,
        )

    @Test
    fun outcomeEvenMatch() {
        // E = 0.5, K = 31 → round(15.5) = 16 each.
        assertEquals(16 to 16, outcome(50, 50, "swiss", 0, 0))
    }

    @Test
    fun outcomeUnderdogWins() {
        // 40 beats 60 (count 18): E = 0.24025, K 24/24, underdog ×1.1 → gain round(20.057) = 20, loss round(18.234) = 18.
        assertEquals(20 to 18, outcome(40, 60, "swiss", 18, 18))
        // 30 beats 60: ×1.3 → 26 / 20; gap > 20 scales by 0.9 → ceil 24 / ceil 18 capped at 5.
        assertEquals(24 to 5, outcome(30, 60, "swiss", 18, 18))
        assertEquals(19 to 5, outcome(10, 90, "swiss", 0, 0))
    }

    @Test
    fun outcomeFavouriteWins() {
        // 80 beats 40: E = 0.90909, Kw 17 (rating reduction), Kl 24, protection 0.7
        // gain round(1.545) = 2 → ×0.8 ceil 2; loss round(1.527) = 2 → mitigation 0.2 ceil 1, cap 3.
        assertEquals(2 to 1, outcome(80, 40, "swiss", 18, 18))
        assertEquals(6 to 3, outcome(60, 40, "swiss", 18, 18))
        assertEquals(4 to 2, outcome(65, 40, "swiss", 18, 18))
        assertEquals(7 to 2, outcome(55, 35, "swiss", 3, 40))
        // Gain never drops below 1, loss never below 0.
        assertEquals(1 to 0, outcome(100, 1, "swiss", 100, 100))
    }

    @Test
    fun outcomeHighRatedWinnerIsDamped() {
        // 90 vs 90: K 14 → 7 / 7, winner ≥ 85 → ceil(4.2) = 5.
        assertEquals(5 to 7, outcome(90, 90, "swiss", 18, 18))
        // 72 vs 70: winner ≥ 70 → ×0.8.
        assertEquals(8 to 10, outcome(72, 70, "swiss", 18, 18))
        assertEquals(5 to 8, outcome(99, 99, "swiss", 0, 0))
    }

    @Test
    fun outcomeGauntletStreakDampener() {
        assertEquals(17 to 17, outcome(50, 50, "gauntlet", 0, 0, streak = 2))
        assertEquals(17 to 17, outcome(50, 50, "gauntlet", 7, 7, streak = 3))
        // streak 5: max(0.3, 1 − 2·0.15) = 0.7 → ceil(11.9) = 12
        assertEquals(12 to 17, outcome(50, 50, "gauntlet", 0, 0, streak = 5))
        // streak 10: dampener floor 0.3 → ceil(5.1) = 6
        assertEquals(6 to 17, outcome(50, 50, "gauntlet", 0, 0, streak = 10))
    }

    @Test
    fun outcomeChampionStreakPenalty() {
        assertEquals(14 to 14, outcome(50, 50, "champion", 0, 0, streak = 4))
        assertEquals(10 to 14, outcome(50, 50, "champion", 0, 0, streak = 5))
        assertEquals(10 to 13, outcome(50, 50, "champion", 7, 7, streak = 6))
        assertEquals(6 to 14, outcome(50, 50, "champion", 0, 0, streak = 10))
    }

    @Test
    fun outcomeSpecialChallengeProtectsLoser() {
        assertEquals(16 to 2, outcome(50, 50, "swiss", 0, 0, special = true))
    }

    // MARK: Draw

    @Test
    fun drawOutcome() {
        assertEquals(0 to 0, MatchElo.outcomeDraw(50.0, 50.0, 0, 0))
        // Underdog on the left gains, the favourite on the right loses.
        assertEquals(6 to 6, MatchElo.outcomeDraw(40.0, 60.0, 18, 18))
        // Favourite on the left: negative values (left loses, right gains).
        assertEquals(-6 to -6, MatchElo.outcomeDraw(60.0, 40.0, 18, 18))
        assertEquals(13 to 6, MatchElo.outcomeDraw(30.0, 70.0, 0, 50))
    }

    @Test
    fun drawAppliesToRatings() {
        val l = performer("1", 60, statsFields("""{"total_matches":18}"""))
        val r = performer("2", 40, statsFields("""{"total_matches":18}"""))
        val res = MatchElo.draw(l, r)
        assertEquals(54, res.winnerNew)
        assertEquals(46, res.loserNew)
        val fb = MatchElo.feedback(res, leftWins = true)
        assertEquals(MatchVoteSide(-6, 54), fb.left)
        assertEquals(MatchVoteSide(6, 46), fb.right)
    }

    // MARK: Votes / rating100

    @Test
    fun voteUsesDefaultRatingAndClamps() {
        // Unrated performers count as 50.
        val res = MatchElo.vote(performer("1", null), performer("2", null), MatchDuelMode.HeadToHead)
        assertEquals(50, res.winnerOld)
        assertEquals(66, res.winnerNew)
        assertEquals(34, res.loserNew)
        assertEquals(16, res.winnerDelta)
        assertEquals(-16, res.loserDelta)

        // 99 vs 99: +5 → clamped to 100 (delta +1).
        val top = MatchElo.vote(performer("1", 99), performer("2", 99), MatchDuelMode.HeadToHead)
        assertEquals(100, top.winnerNew)
        assertEquals(1, top.winnerDelta)
        assertEquals(91, top.loserNew)

        // 10 beats 3: loss 12 → clamped to 1 (delta −2).
        val bottom = MatchElo.vote(performer("1", 10), performer("2", 3), MatchDuelMode.HeadToHead)
        assertEquals(22, bottom.winnerNew)
        assertEquals(1, bottom.loserNew)
        assertEquals(-2, bottom.loserDelta)
    }

    @Test
    fun voteUsesModeAndStats() {
        val streaky = statsFields("""{"current_streak":5,"total_matches":0}""")
        val res = MatchElo.vote(performer("1", 50, streaky), performer("2", 50), MatchDuelMode.Placement)
        assertEquals(12, res.gain)
        assertEquals(17, res.loss)
        val legend = MatchElo.vote(performer("1", 50, streaky), performer("2", 50), MatchDuelMode.Champion)
        assertEquals(10, legend.gain)
        assertEquals(14, legend.loss)
    }

    @Test
    fun feedbackMapsWinnerToSide() {
        val res = MatchVoteResult(winnerOld = 50, loserOld = 50, winnerNew = 66, loserNew = 34, gain = 16, loss = 16)
        assertEquals(MatchVoteFeedback(MatchVoteSide(16, 66), MatchVoteSide(-16, 34)), MatchElo.feedback(res, leftWins = true))
        assertEquals(MatchVoteFeedback(MatchVoteSide(-16, 34), MatchVoteSide(16, 66)), MatchElo.feedback(res, leftWins = false))
    }

    @Test
    fun clampRating100() {
        assertEquals(1, MatchElo.clampRating100(-9))
        assertEquals(1, MatchElo.clampRating100(0))
        assertEquals(57, MatchElo.clampRating100(57))
        assertEquals(100, MatchElo.clampRating100(104))
    }

    // MARK: Stats

    @Test
    fun updateStatsStreaks() {
        val now = "2026-10-04T10:00:00.000Z"
        var s = MatchElo.updateStats(MatchStats.Empty, true, now)
        assertEquals(MatchStats(1, 1, 0, 0, 1, 1, 0, now), s)
        s = MatchElo.updateStats(s, true, now)
        assertEquals(2, s.currentStreak); assertEquals(2, s.bestStreak)
        s = MatchElo.updateStats(s, false, now)
        assertEquals(-1, s.currentStreak); assertEquals(2, s.bestStreak); assertEquals(-1, s.worstStreak)
        s = MatchElo.updateStats(s, false, now)
        assertEquals(-2, s.currentStreak); assertEquals(-2, s.worstStreak)
        s = MatchElo.updateStats(s, null, now)
        // Draws keep the streak.
        assertEquals(-2, s.currentStreak)
        assertEquals(MatchStats(5, 2, 2, 1, -2, 2, -2, now), s)
        s = MatchElo.updateStats(s, true, now)
        assertEquals(1, s.currentStreak)
        assertEquals(2, s.bestStreak)
    }

    @Test
    fun encodeStatsSortedCompact() {
        val s = MatchStats(5, 2, 2, 1, -2, 2, -2, "2026-10-04T10:00:00.000Z")
        assertEquals(
            """{"best_streak":2,"current_streak":-2,"draws":1,"last_match":"2026-10-04T10:00:00.000Z","losses":2,"total_matches":5,"wins":2,"worst_streak":-2}""",
            MatchElo.encodeStats(s),
        )
        assertEquals(
            """{"best_streak":0,"current_streak":0,"draws":0,"losses":0,"total_matches":0,"wins":0,"worst_streak":0}""",
            MatchElo.encodeStats(MatchStats.Empty),
        )
    }

    @Test
    fun parseStatsFromPluginString() {
        val json = """{"best_streak":2,"current_streak":-2,"draws":1,"last_match":"2026-10-04T10:00:00.000Z","losses":2,"total_matches":5,"wins":2,"worst_streak":-2}"""
        assertEquals(MatchStats(5, 2, 2, 1, -2, 2, -2, "2026-10-04T10:00:00.000Z"), MatchElo.parseStats(statsFields(json)))
        // Missing keys decode as 0, unknown keys are ignored.
        assertEquals(MatchStats(totalMatches = 3), MatchElo.parseStats(statsFields("""{"total_matches":3,"elo":1200}""")))
        // Round trip.
        val s = MatchStats(9, 5, 3, 1, 2, 4, -3, null)
        assertEquals(s, MatchElo.parseStats(statsFields(MatchElo.encodeStats(s))))
    }

    @Test
    fun parseStatsFromObject() {
        val obj = buildJsonObject {
            put(MatchElo.STATS_KEY, buildJsonObject {
                put("total_matches", JsonPrimitive(7))
                put("wins", JsonPrimitive(3.6))
                put("losses", JsonPrimitive("2"))
                put("draws", JsonPrimitive("x"))
                put("current_streak", JsonPrimitive(-2.5))
                put("last_match", JsonPrimitive(12))
            })
        }
        // Doubles rounded half away from zero, numeric strings parsed, rest 0; non-string last_match → null.
        assertEquals(MatchStats(7, 4, 2, 0, -3, 0, 0, null), MatchElo.parseStats(obj))
    }

    @Test
    fun parseStatsFallbacks() {
        assertEquals(MatchStats.Empty, MatchElo.parseStats(null))
        assertEquals(MatchStats.Empty, MatchElo.parseStats(JsonObject(emptyMap())))
        val legacy = buildJsonObject { put(MatchElo.ELO_MATCHES_KEY, JsonPrimitive("12")) }
        assertEquals(MatchStats(totalMatches = 12), MatchElo.parseStats(legacy))
        // Broken plugin string falls through to elo_matches.
        val broken = buildJsonObject {
            put(MatchElo.STATS_KEY, JsonPrimitive("{not json"))
            put(MatchElo.ELO_MATCHES_KEY, JsonPrimitive("4"))
        }
        assertEquals(MatchStats(totalMatches = 4), MatchElo.parseStats(broken))
        // Wrong types inside the string make the Codable decode fail (Swift: try? → nil).
        val wrongType = buildJsonObject { put(MatchElo.STATS_KEY, JsonPrimitive("""{"wins":"3"}""")) }
        assertEquals(MatchStats.Empty, MatchElo.parseStats(wrongType))
        // elo_matches as a number is ignored (iOS only reads the string form).
        assertEquals(MatchStats.Empty, MatchElo.parseStats(buildJsonObject { put(MatchElo.ELO_MATCHES_KEY, JsonPrimitive(12)) }))
    }

    // MARK: Records

    @Test
    fun encodeRecordsSortedAndDrawOmitsWon() {
        val records = listOf(
            MatchRecord("2026-10-04T10:00:00Z", "2:Jane Doe", true, 66),
            MatchRecord("2026-10-04T10:01:00Z", "3:A/B", null, 64),
            MatchRecord("2026-10-04T10:02:00Z", "4:\"Q\"", false, 60),
        )
        assertEquals(
            "[" +
                """{"date":"2026-10-04T10:00:00Z","opponent":"2:Jane Doe","ratingAfter":66,"won":true},""" +
                """{"date":"2026-10-04T10:01:00Z","opponent":"3:A\/B","ratingAfter":64},""" +
                """{"date":"2026-10-04T10:02:00Z","opponent":"4:\"Q\"","ratingAfter":60,"won":false}""" +
                "]",
            MatchElo.encodeMatchRecords(records),
        )
        assertEquals("[]", MatchElo.encodeMatchRecords(emptyList()))
    }

    @Test
    fun parseRecordsRoundTripAndErrors() {
        val records = listOf(
            MatchRecord("2026-10-04T10:00:00Z", "2:Jane", true, 66),
            MatchRecord("2026-10-04T10:01:00Z", "3:A/B", null, 64),
        )
        val fields = buildJsonObject { put(MatchElo.RECORD_KEY, JsonPrimitive(MatchElo.encodeMatchRecords(records))) }
        assertEquals(records, MatchElo.parseMatchRecords(fields))
        assertTrue(MatchElo.parseMatchRecords(null).isEmpty())
        assertTrue(MatchElo.parseMatchRecords(buildJsonObject { put(MatchElo.RECORD_KEY, JsonPrimitive("nope")) }).isEmpty())
        // Not a string (structured array) → iOS ignores it.
        assertTrue(MatchElo.parseMatchRecords(buildJsonObject { put(MatchElo.RECORD_KEY, JsonArray(emptyList())) }).isEmpty())
        // One bad entry fails the whole decode.
        val bad = """[{"date":"d","opponent":"o","ratingAfter":1},{"date":"d","ratingAfter":2}]"""
        assertTrue(MatchElo.parseMatchRecords(buildJsonObject { put(MatchElo.RECORD_KEY, JsonPrimitive(bad)) }).isEmpty())
    }

    @Test
    fun appendRecordKeepsLast30() {
        val many = (1..30).map { MatchRecord("d$it", "o", true, it) }
        val next = MatchElo.appendRecord(many, MatchRecord("d31", "o", false, 31))
        assertEquals(30, next.size)
        assertEquals("d2", next.first().date)
        assertEquals("d31", next.last().date)
        assertEquals(2, MatchElo.appendRecord(listOf(many[0]), many[1]).size)
    }

    @Test
    fun buildPerformerUpdateWritesAscensionFields() {
        val existing = buildJsonObject {
            put(MatchElo.STATS_KEY, JsonPrimitive("""{"best_streak":1,"current_streak":1,"draws":0,"losses":0,"total_matches":1,"wins":1,"worst_streak":0}"""))
            put(MatchElo.RECORD_KEY, JsonPrimitive("""[{"date":"2026-10-03T09:00:00Z","opponent":"9:Old","ratingAfter":55,"won":true}]"""))
        }
        val p = performer("7", 55, existing)
        val input = MatchElo.buildPerformerUpdate(p, newRating = 61, won = true, opponentId = "8", opponentName = "Jane", nowMillis = 0L)
        assertEquals("7", input["id"]!!.jsonPrimitive.content)
        assertEquals(61, input["rating100"]!!.jsonPrimitive.int)
        val partial = input["custom_fields"]!!.jsonObject["partial"]!!.jsonObject
        assertEquals(setOf("hotornot_stats", "performer_record"), partial.keys)
        assertEquals(
            """{"best_streak":2,"current_streak":2,"draws":0,"last_match":"1970-01-01T00:00:00.000Z","losses":0,"total_matches":2,"wins":2,"worst_streak":0}""",
            partial["hotornot_stats"]!!.jsonPrimitive.content,
        )
        assertEquals(
            """[{"date":"2026-10-03T09:00:00Z","opponent":"9:Old","ratingAfter":55,"won":true},""" +
                """{"date":"1970-01-01T00:00:00Z","opponent":"8:Jane","ratingAfter":61,"won":true}]""",
            partial["performer_record"]!!.jsonPrimitive.content,
        )
        // Values are JSON strings (plugin format), not structured objects.
        assertTrue(partial["hotornot_stats"]!!.jsonPrimitive.isString)
        // Re-parsing what we wrote yields the updated stats.
        val written = JsonObject(mapOf(MatchElo.STATS_KEY to partial["hotornot_stats"]!!))
        assertEquals(2, MatchElo.parseStats(written).wins)
    }

    @Test
    fun drawUpdateHasNoWonKeyAndCountsDraw() {
        val input = MatchElo.buildPerformerUpdate(performer("1", 50), 50, won = null, opponentId = "2", opponentName = "X", nowMillis = 0L)
        val partial = input["custom_fields"]!!.jsonObject["partial"]!!.jsonObject
        assertEquals("""[{"date":"1970-01-01T00:00:00Z","opponent":"2:X","ratingAfter":50}]""", partial["performer_record"]!!.jsonPrimitive.content)
        assertTrue(partial["hotornot_stats"]!!.jsonPrimitive.content.contains("\"draws\":1"))
    }

    // MARK: Dates / recency

    @Test
    fun isoFormats() {
        assertEquals("1970-01-01T00:00:00.000Z", MatchElo.nowISOFractional(0))
        assertEquals("1970-01-01T00:00:00Z", MatchElo.nowISOPlain(0))
        assertEquals("2026-10-04T10:00:00.123Z", MatchElo.nowISOFractional(1_791_108_000_123L))
        assertEquals(1_791_108_000_123L, MatchElo.parseISODate("2026-10-04T10:00:00.123Z"))
        assertEquals(1_791_108_000_000L, MatchElo.parseISODate("2026-10-04T10:00:00Z"))
        assertEquals(1_791_108_000_000L, MatchElo.parseISODate("2026-10-04T12:00:00+02:00"))
        assertNull(MatchElo.parseISODate("yesterday"))
    }

    @Test
    fun recencyWeight() {
        val now = 1_791_108_000_000L
        assertEquals(0.7, MatchElo.recencyWeight(MatchStats.Empty, now), 0.0)
        assertEquals(0.7, MatchElo.recencyWeight(MatchStats(lastMatch = "garbage"), now), 0.0)
        assertEquals(0.0, MatchElo.recencyWeight(MatchStats(lastMatch = "2026-10-04T10:00:00.000Z"), now), eps)
        assertEquals(0.6321205588, MatchElo.recencyWeight(MatchStats(lastMatch = "2026-10-04T05:00:00Z"), now), eps)
        assertEquals(1.0, MatchElo.recencyWeight(MatchStats(lastMatch = "2026-09-01T00:00:00Z"), now), 1e-6)
    }

    @Test
    fun weightedPick() {
        assertNull(MatchElo.weightedPick(emptyList<Int>(), emptyList()))
        assertNull(MatchElo.weightedPick(listOf(1, 2), listOf(1.0)))
        // Zero total → uniform random element.
        assertTrue(MatchElo.weightedPick(listOf(1, 2), listOf(0.0, 0.0), Random(1)) in setOf(1, 2))
        // A zero-weight first item is (practically) never picked.
        val rnd = Random(42)
        repeat(200) { assertEquals(2, MatchElo.weightedPick(listOf(1, 2), listOf(0.0, 1.0), rnd)) }
        // Heavily weighted item dominates.
        val counts = IntArray(2)
        val r2 = Random(7)
        repeat(2000) { counts[MatchElo.weightedPick(listOf(0, 1), listOf(0.1, 0.9), r2)!!]++ }
        assertTrue(counts[1] in 1700..1900)
    }

    // MARK: Modes / cards

    @Test
    fun duelModeMigration() {
        assertEquals(MatchDuelMode.HeadToHead, MatchDuelMode.migrating("swiss"))
        assertEquals(MatchDuelMode.HeadToHead, MatchDuelMode.migrating("headToHead"))
        assertEquals(MatchDuelMode.Placement, MatchDuelMode.migrating("gauntlet"))
        assertEquals(MatchDuelMode.Placement, MatchDuelMode.migrating("placement"))
        assertEquals(MatchDuelMode.Champion, MatchDuelMode.migrating("champion"))
        assertEquals(MatchDuelMode.HeadToHead, MatchDuelMode.migrating(null))
        assertEquals(MatchDuelMode.HeadToHead, MatchDuelMode.migrating("bogus"))
        assertEquals(listOf("swiss", "gauntlet", "champion"), MatchDuelMode.entries.map { it.ascensionMode })
        assertEquals(listOf("1 vs. 1", "Rise", "Legend"), MatchDuelMode.entries.map { it.label })
        assertEquals(listOf("headToHead", "placement", "champion"), MatchDuelMode.entries.map { it.raw })
    }

    @Test
    fun battleInfoRows() {
        val female = Performer(id = "1", name = "A", gender = "FEMALE", sceneCount = 3, imageCount = null, country = " DE ", fakeTits = "Natural", rating100 = 72)
        assertEquals(
            listOf("RATING" to "72", "GENDER" to "FEMALE", "SCENES" to "3", "IMAGES" to "0", "COUNTRY" to "DE", "TITS" to "Natural"),
            MatchElo.battleInfoRows(female),
        )
        val male = Performer(id = "2", name = "B", gender = "MALE", penisLength = 15.4, fakeTits = "Fake")
        assertEquals("15 cm", MatchElo.battleInfoRows(male).last().second)
        assertEquals("50", MatchElo.battleInfoRows(male).first().second)
        val transFemale = Performer(id = "3", name = "C", gender = "TRANSGENDER_FEMALE", penisLength = 12.0)
        assertEquals("—", MatchElo.battleInfoRows(transFemale).last().second)
        val unknown = Performer(id = "4", name = "D", gender = "  ", country = "", penisLength = 0.0)
        val rows = MatchElo.battleInfoRows(unknown)
        assertEquals("—", rows[1].second)
        assertEquals("—", rows[4].second)
        assertEquals("—", rows[5].second)
        val other = Performer(id = "5", name = "E", gender = "NON_BINARY", penisLength = 9.6)
        assertEquals("10 cm", MatchElo.battleInfoRows(other).last().second)
    }

    @Test
    fun streakSummaryLine() {
        assertNull(MatchElo.streakSummaryLine(MatchStats.Empty))
        assertEquals("Current +3 · Best +5 · Worst -2", MatchElo.streakSummaryLine(MatchStats(currentStreak = 3, bestStreak = 5, worstStreak = -2)))
        assertEquals("Current -1 · Worst -1", MatchElo.streakSummaryLine(MatchStats(currentStreak = -1, worstStreak = -1)))
    }

    // MARK: Pairing

    @Test
    fun ladderSortedUsesPendingAndIdTieBreak() {
        val list = listOf(performer("3", 50), performer("1", 70), performer("2", 50), performer("4", null))
        assertEquals(listOf("1", "2", "3", "4"), MatchPairing.ladderSorted(list, emptyMap()).map { it.id })
        val pending = MatchPairing.ladderSorted(list, mapOf("4" to 90))
        assertEquals(listOf("4", "1", "2", "3"), pending.map { it.id })
        assertEquals(90, pending.first().rating100)
    }

    @Test
    fun climbOpponentWindow() {
        val ranked = (0 until 10).map { performer("$it", 100 - it) }
        val seen = mutableSetOf<String>()
        val rnd = Random(3)
        repeat(300) { seen += MatchPairing.climbOpponent(ranked, 8, emptySet(), null, rnd)!!.id }
        // The five lowest-ranked performers above the champion (indices 3…7).
        assertEquals(setOf("3", "4", "5", "6", "7"), seen)
        // Defeated / skipped are excluded.
        val only = MatchPairing.climbOpponent(ranked, 3, setOf("0", "2"), "1", rnd)
        assertNull(only)
        assertEquals("1", MatchPairing.climbOpponent(ranked, 3, setOf("0", "2"), null, rnd)!!.id)
        assertNull(MatchPairing.climbOpponent(ranked, 0, emptySet(), null, rnd))
    }

    @Test
    fun headToHeadIndexes() {
        assertNull(MatchPairing.headToHeadIndexes(listOf(performer("1", 50))))
        val two = listOf(performer("1", 90), performer("2", 10))
        val (a, b) = MatchPairing.headToHeadIndexes(two, random = Random(1))!!
        assertFalse(a == b)
        // Second pick stays within 15 points when such a performer exists.
        val list = listOf(performer("1", 90), performer("2", 80), performer("3", 20), performer("4", 15))
        val rnd = Random(5)
        repeat(200) {
            val (i, j) = MatchPairing.headToHeadIndexes(list, random = rnd)!!
            assertFalse(i == j)
            val ri = list[i].rating100!!
            val rj = list[j].rating100!!
            assertTrue("$ri vs $rj", kotlin.math.abs(ri - rj) <= 15)
        }
    }

    @Test
    fun performerFilterJson() {
        val f = MatchRepository.performerFilter(setOf("MALE", "FEMALE"))
        assertEquals(
            """{"gender":{"value_list":["FEMALE","MALE"],"modifier":"INCLUDES"},"NOT":{"is_missing":"image"}}""",
            f.toString(),
        )
    }
}
