package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Tag
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AITagCooccurrenceTest {

    private val a = Tag(id = "A", name = "Alpha")
    private val b = Tag(id = "B", name = "Beta")
    private val c = Tag(id = "C", name = "Gamma")

    /**
     * 1: [A,B] P, G, S · 2: [A,B] P, S · 3: [A,C] P · 4: untagged · 5: [B,C] Q
     */
    private fun builder(): Pair<AITagStatsBuilder, Int> {
        val builder = AITagStatsBuilder()
        val items = listOf(
            AITagStatsItem(listOf("A", "B"), listOf("P"), listOf("G"), "S"),
            AITagStatsItem(listOf("A", "B"), listOf("P"), studioId = "S"),
            AITagStatsItem(listOf("A", "C"), listOf("P")),
            AITagStatsItem(emptyList(), listOf("P"), studioId = "S"),
            AITagStatsItem(listOf("B", "C"), listOf("Q")),
        )
        val counted = items.count { builder.absorb(it) }
        return builder to counted
    }

    private fun model(tags: List<Tag> = listOf(a, b, c)): AITagStatsModel {
        val (builder, counted) = builder()
        return builder.build(tags, counted, builtAt = 0.0)
    }

    private fun sceneTarget(tags: List<Tag> = emptyList(), performers: List<String> = listOf("P"), studio: String? = null, galleries: List<String> = emptyList()) =
        AITagTarget(AITagTarget.Kind.Scene, "1", tags, performerIds = performers, studioId = studio, galleryIds = galleries)

    // MARK: Counting

    @Test
    fun countsTagsPerScopeAndSkipsUntaggedItems() {
        val (builder, counted) = builder()
        assertEquals(4, counted)
        assertEquals(mapOf("A" to 3, "B" to 3, "C" to 2), builder.tagTotals.toMap())
        assertEquals(3, builder.performerTotals["P"])
        assertEquals(1, builder.performerTotals["Q"])
        assertEquals(mapOf("A" to 3, "B" to 2, "C" to 1), builder.performerCounts["P"]?.toMap())
        assertEquals(mapOf("A" to 1, "B" to 1), builder.galleryCounts["G"]?.toMap())
        assertEquals(2, builder.studioTotals["S"])
        assertEquals(mapOf("A" to 2, "B" to 2), builder.studioCounts["S"]?.toMap())
    }

    @Test
    fun countsCooccurrenceInBothDirections() {
        val (builder, _) = builder()
        assertEquals(mapOf("B" to 2, "C" to 1), builder.pairCounts["A"]?.toMap())
        assertEquals(mapOf("A" to 2, "C" to 1), builder.pairCounts["B"]?.toMap())
        assertEquals(mapOf("A" to 1, "B" to 1), builder.pairCounts["C"]?.toMap())
    }

    @Test
    fun trimKeepsOnlyPartnersSeenTwiceStrongestFirst() {
        val m = model()
        assertEquals(mapOf("A" to mapOf("B" to 2), "B" to mapOf("A" to 2)), m.pairCounts)
        val trimmed = AITagStatsMath.trimPairs(mapOf("X" to mapOf("a" to 2, "b" to 5, "c" to 3, "d" to 1)), limit = 2)
        assertEquals(listOf("b", "c"), trimmed["X"]?.keys?.toList())
    }

    // MARK: Scoring

    @Test
    fun performerScoresAreSmoothedAndRanked() {
        val result = AITagStatsMath.suggest(model(), sceneTarget())
        assertEquals(listOf("A", "B", "C"), result.map { it.tag.id })
        assertEquals(0.75, result[0].confidence, 1e-9)   // 3 / (3 + 1)
        assertEquals(0.5, result[1].confidence, 1e-9)
        assertEquals(0.25, result[2].confidence, 1e-9)
        assertTrue(result.all { it.source == AITagSuggestion.Source.Performer })
    }

    @Test
    fun existingTagsAreNeverSuggestedAndRelatedSignalsCombine() {
        val result = AITagStatsMath.suggest(model(), sceneTarget(tags = listOf(a)))
        assertEquals(listOf("B", "C"), result.map { it.tag.id })
        // performer 2/4 = 0.5 and related 2/(3+1) = 0.5 → 0.5 + 0.15 · 0.5
        assertEquals(0.575, result[0].confidence, 1e-9)
        assertEquals(AITagSuggestion.Source.Performer, result[0].source)
    }

    @Test
    fun strongerSignalNamesTheSource() {
        val result = AITagStatsMath.suggest(model(), sceneTarget(studio = "S")).associateBy { it.tag.id }
        val studioB = 0.8 * 2 / 3.0
        assertEquals(AITagSuggestion.Source.Studio, result.getValue("B").source)
        assertEquals(studioB + 0.15 * 0.5, result.getValue("B").confidence, 1e-9)
        assertEquals(AITagSuggestion.Source.Performer, result.getValue("A").source)
        assertEquals(0.75 + 0.15 * (0.8 * 2 / 3.0), result.getValue("A").confidence, 1e-9)
    }

    @Test
    fun galleryWeightApplies() {
        val result = AITagStatsMath.suggest(model(), sceneTarget(performers = emptyList(), galleries = listOf("G")))
        assertEquals(setOf("A", "B"), result.map { it.tag.id }.toSet())
        assertTrue(result.all { it.source == AITagSuggestion.Source.Gallery })
        assertEquals(0.95 * 1 / 2.0, result[0].confidence, 1e-9)
    }

    @Test
    fun combineNeverExceedsCertainty() {
        assertEquals(1.0, AITagStatsMath.combine(0.95, 0.9), 1e-9)
        assertEquals(0.6 + 0.15 * 0.2, AITagStatsMath.combine(0.2, 0.6), 1e-9)
    }

    @Test
    fun dismissedTagsAndUnknownTagsAreDropped() {
        val dismissed = AITagStatsMath.suggest(model(), sceneTarget(), dismissals = mapOf("B" to 1))
        assertEquals(listOf("A", "C"), dismissed.map { it.tag.id })
        val noC = AITagStatsMath.suggest(model(tags = listOf(a, b)), sceneTarget())
        assertEquals(listOf("A", "B"), noC.map { it.tag.id })
    }

    @Test
    fun maxSuggestionsCapsTheListButShowsAtLeastOne() {
        assertEquals(listOf("A"), AITagStatsMath.suggest(model(), sceneTarget(), maxSuggestions = 1).map { it.tag.id })
        assertEquals(1, AITagStatsMath.suggest(model(), sceneTarget(), maxSuggestions = 0).size)
        assertEquals(2, AITagStatsMath.suggest(model(), sceneTarget(), maxSuggestions = 2).size)
    }

    @Test
    fun relatedTagWeightsAreShareOfTheSourceTag() {
        val weights = AITagStatsMath.relatedTagWeights(model(), listOf("A"))
        assertEquals(mapOf("B" to 2 / 3.0), weights)
        assertTrue(AITagStatsMath.relatedTagWeights(null, listOf("A")).isEmpty())
        // Partners that are themselves source tags are skipped.
        assertTrue(AITagStatsMath.relatedTagWeights(model(), listOf("A", "B")).isEmpty())
    }

    // MARK: Local updates

    @Test
    fun addingATagUpdatesCountsAndPairs() {
        val m = model(tags = listOf(a, b))
        val updated = AITagStatsMath.applyLocalUpdate(m, sceneTarget(tags = listOf(a)), listOf(a, c))!!
        assertEquals(2, updated.performerCounts["P"]?.get("C"))
        assertEquals(3, updated.performerTotals["P"])          // was counted, still counted
        assertEquals(m.itemCount, updated.itemCount)
        assertEquals(3, updated.tagTotals["C"])
        assertEquals(1, updated.pairCounts["A"]?.get("C"))
        assertEquals(1, updated.pairCounts["C"]?.get("A"))
        assertTrue(updated.tags.any { it.id == "C" })           // vocabulary grows
    }

    @Test
    fun firstTagMakesTheItemCount() {
        val m = model()
        val updated = AITagStatsMath.applyLocalUpdate(m, sceneTarget(), listOf(a))!!
        assertEquals(4, updated.performerTotals["P"])
        assertEquals(m.itemCount + 1, updated.itemCount)
    }

    @Test
    fun noChangeReturnsNullAndMarkersOnlyTouchTheVocabulary() {
        val m = model(tags = listOf(a, b))
        assertNull(AITagStatsMath.applyLocalUpdate(m, sceneTarget(tags = listOf(a)), listOf(a)))
        val marker = AITagTarget(AITagTarget.Kind.Marker, "m1", listOf(a), primaryTagId = "A", performerIds = listOf("P"))
        val updated = AITagStatsMath.applyLocalUpdate(m, marker, listOf(a, c))!!
        assertEquals(m.performerCounts, updated.performerCounts)
        assertEquals(m.tagTotals, updated.tagTotals)
        assertTrue(updated.tags.any { it.id == "C" })
    }

    // MARK: Persistence

    @Test
    fun statsFileRoundTrips() {
        val m = model().copy(builtAt = 812_345_678.5)
        val text = AITagStatsMath.encode(m)
        for (key in listOf("version", "builtAt", "itemCount", "tags", "performerCounts", "performerTotals", "galleryCounts",
            "galleryTotals", "studioCounts", "studioTotals", "pairCounts", "tagTotals")) {
            assertTrue("missing $key", text.contains("\"$key\""))
        }
        assertEquals(m, AITagStatsMath.decode(text))
    }

    @Test
    fun decodesAnIosShapedFile() {
        val ios = """
            {"version":2,"builtAt":0,"itemCount":1,
             "tags":[{"id":"1","name":"Plants","scene_count":1}],
             "performerCounts":{"7":{"1":1}},"performerTotals":{"7":1},
             "galleryCounts":{},"galleryTotals":{},"studioCounts":{"3":{"1":1}},"studioTotals":{"3":1},
             "pairCounts":{},"tagTotals":{"1":1}}
        """.trimIndent()
        val m = AITagStatsMath.decode(ios)!!
        assertEquals(AITagStatsMath.MODEL_VERSION, m.version)
        assertEquals("Plants", m.tags.single().name)
        assertEquals(1, m.tags.single().sceneCount)
        assertEquals(978_307_200_000L, m.builtAtMillis)
        assertNull(AITagStatsMath.decode("not json"))
    }

    @Test
    fun dismissalsRoundTrip() {
        val map = mapOf("A" to 1, "B" to 3)
        assertEquals(map, AITagStatsMath.decodeDismissals(AITagStatsMath.encodeDismissals(map)))
        assertTrue(AITagStatsMath.decodeDismissals(null).isEmpty())
    }

    @Test
    fun storageKeyMirrorsIos() {
        assertEquals("stash_local_9999", AITagStatsMath.storageKey(" Stash.Local ", "9999"))
        assertEquals("192_168_1_5_443", AITagStatsMath.storageKey("192.168.1.5", "443"))
        assertNull(AITagStatsMath.storageKey("  ", "443"))
        assertFalse(AITagStatsMath.storageKey("a-b", "1")!!.contains("-"))
    }
}
