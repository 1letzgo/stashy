package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoPerformerLogicTest {

    private fun Map<String, Int>.scenes() = mapValues { CoAppearanceCounts(scenes = it.value) }

    @Test fun countsGalleriesAndLooseImagesOnly() {
        val scenes = listOf(CoAppearanceRow(null, listOf("me", "a")))
        val galleries = listOf(CoAppearanceRow("g1", listOf("me", "a", "b")), CoAppearanceRow("g2", listOf("me", "c")))
        val images = listOf(
            CoAppearanceRow(null, listOf("me", "a"), listOf("g1")), // inside a shared gallery → not again
            CoAppearanceRow(null, listOf("me", "a")),               // loose → counts
            CoAppearanceRow(null, listOf("me", "d"), listOf("g2")), // gallery without d → counts
        )
        assertEquals(
            mapOf(
                "a" to CoAppearanceCounts(scenes = 1, galleries = 1, images = 1),
                "b" to CoAppearanceCounts(galleries = 1),
                "c" to CoAppearanceCounts(galleries = 1),
                "d" to CoAppearanceCounts(images = 1),
            ),
            CoPerformerLogic.countAll(scenes, galleries, images, "me"),
        )
    }

    @Test fun countsSharedScenesExcludingSelf() {
        val scenes = listOf(
            listOf("me", "a", "b"),
            listOf("me", "a"),
            listOf("a", "me", "c"),
            listOf("me"),
        )
        assertEquals(mapOf("a" to 3, "b" to 1, "c" to 1), CoPerformerLogic.count(scenes, "me"))
    }

    @Test fun duplicateIdInOneSceneCountsOnce() {
        assertEquals(mapOf("a" to 1), CoPerformerLogic.count(listOf(listOf("me", "a", "a")), "me"))
    }

    @Test fun noScenesOrSoloScenesGiveNothing() {
        assertTrue(CoPerformerLogic.count(emptyList(), "me").isEmpty())
        assertTrue(CoPerformerLogic.count(listOf(listOf("me"), emptyList()), "me").isEmpty())
    }

    @Test fun sortsByCountDescThenName() {
        val performers = listOf(
            Performer("1", "zoe"), Performer("2", "Anna"), Performer("3", "bella"), Performer("4", "Carl"),
        )
        val counts = mapOf("1" to 5, "2" to 2, "3" to 2, "4" to 7)
        val result = CoPerformerLogic.sorted(performers, counts.scenes())
        assertEquals(listOf("Carl", "zoe", "Anna", "bella"), result.map { it.performer.name })
        assertEquals(listOf(7, 5, 2, 2), result.map { it.shared.total })
    }

    private fun performerSort(raw: String) = SortCatalog.option(FilterMode.Performers, raw)!!

    private val favorite = JsonObject(mapOf("filter_favorites" to JsonPrimitive(true)))

    private val coAppearance = DetailRepository.includes("7")

    @Test fun sharedSortRequestsCoAppearanceAndFilterByNameWithoutIds() {
        val q = CatalogQuery(FilterMode.Performers, CoPerformerSort.Desc, live = favorite)
        val r = CoPerformerLogic.performerRequest("7", q)
        // Stash ignores performer_filter / sort / paging when ids is passed.
        assertNull(r["ids"])
        val pf = r["performer_filter"]!!.jsonObject
        assertEquals(JsonPrimitive(true), pf["filter_favorites"])
        assertEquals(coAppearance, pf["performers"])
        val f = r["filter"]!!.jsonObject
        assertEquals("name", f["sort"]!!.jsonPrimitive.content)
        assertEquals("ASC", f["direction"]!!.jsonPrimitive.content)
        assertEquals(-1, f["per_page"]!!.jsonPrimitive.content.toInt())
    }

    @Test fun serverSortIsSentAsFindFilter() {
        val q = CatalogQuery(FilterMode.Performers, performerSort("ratingDesc"), live = favorite)
        val r = CoPerformerLogic.performerRequest("7", q)
        assertNull(r["ids"])
        val f = r["filter"]!!.jsonObject
        assertEquals("rating", f["sort"]!!.jsonPrimitive.content)
        assertEquals("DESC", f["direction"]!!.jsonPrimitive.content)
        assertEquals(-1, f["per_page"]!!.jsonPrimitive.content.toInt())
    }

    @Test fun noFilterStillSendsCoAppearanceCriterion() {
        val r = CoPerformerLogic.performerRequest("7", CatalogQuery(FilterMode.Performers, CoPerformerSort.Default))
        assertEquals(JsonObject(mapOf("performers" to coAppearance)), r["performer_filter"])
    }

    @Test fun coAppearanceWinsOverAPerformersCriterionFromTheSheet() {
        val live = JsonObject(mapOf("performers" to DetailRepository.includes("99")))
        val r = CoPerformerLogic.performerRequest("7", CatalogQuery(FilterMode.Performers, CoPerformerSort.Default, live = live))
        assertEquals(coAppearance, r["performer_filter"]!!.jsonObject["performers"])
    }

    @Test fun savedFilterIsSentAsPerformerFilter() {
        val saved = SavedFilter("9", "Faves", "PERFORMERS", objectFilter = favorite)
        val q = CatalogQuery(FilterMode.Performers, CoPerformerSort.Default, base = saved)
        val pf = CoPerformerLogic.performerRequest("7", q)["performer_filter"]!!.jsonObject
        assertEquals(JsonPrimitive(true), pf["filter_favorites"])
        assertEquals(coAppearance, pf["performers"])
    }

    @Test fun resultIsIntersectedWithSharedSceneIds() {
        // Stash co-appearance also matches image / gallery partners: "4" has no shared scene.
        val server = listOf(Performer("4", "img only"), Performer("1", "a"), Performer("2", "b"))
        val counts = mapOf("1" to 1, "2" to 3, "3" to 2)
        assertEquals(listOf("1", "2"), CoPerformerLogic.ordered(server, counts.scenes(), performerSort("nameAsc")).map { it.performer.id })
        assertEquals(listOf(3, 1), CoPerformerLogic.ordered(server, counts.scenes(), CoPerformerSort.Desc).map { it.shared.total })
    }

    @Test fun orderedBySharedAscendingOrKeepsServerOrder() {
        val performers = listOf(Performer("1", "zoe"), Performer("2", "Anna"), Performer("3", "bella"), Performer("4", "x"))
        val counts = mapOf("1" to 5, "2" to 2, "3" to 2)
        assertEquals(listOf("Anna", "bella", "zoe"), CoPerformerLogic.ordered(performers, counts.scenes(), CoPerformerSort.Asc).map { it.performer.name })
        assertEquals(listOf("zoe", "Anna", "bella"), CoPerformerLogic.ordered(performers, counts.scenes(), CoPerformerSort.Desc).map { it.performer.name })
        // Server sort: server order kept, performers without a shared scene dropped.
        assertEquals(listOf("zoe", "Anna", "bella"), CoPerformerLogic.ordered(performers, counts.scenes(), performerSort("nameDesc")).map { it.performer.name })
    }

    @Test fun cacheKeyChangesWithFilterAndSort() {
        val plain = CatalogQuery(FilterMode.Performers, CoPerformerSort.Desc)
        val keys = setOf(
            CoPerformerLogic.cacheKey("s|7", plain),
            CoPerformerLogic.cacheKey("s|7", plain.copy(sort = CoPerformerSort.Asc)),
            CoPerformerLogic.cacheKey("s|7", plain.copy(live = favorite)),
            CoPerformerLogic.cacheKey("s|7", plain.copy(sort = performerSort("nameAsc"))),
        )
        assertEquals(4, keys.size)
        assertTrue(keys.all { it.startsWith("s|7|") })
    }

    @Test fun sheetSortPickerOffersSharedScenesFirst() {
        val kinds = SortCatalog.fieldKinds(FilterMode.Performers, CoPerformerSort.options)
        assertEquals(SortFieldKind(CoPerformerSort.FIELD, "Most shared"), kinds.first())
        assertEquals(1, kinds.count { it.field == CoPerformerSort.FIELD })
        assertEquals(CoPerformerSort.Asc, SortCatalog.optionFor(FilterMode.Performers, CoPerformerSort.FIELD, true, CoPerformerSort.options))
        assertEquals(performerSort("nameAsc"), SortCatalog.optionFor(FilterMode.Performers, "name", true, CoPerformerSort.options))
        // Picking Shared scenes keeps the direction; picking a performer field from it does too.
        assertEquals(CoPerformerSort.Asc, SortCatalog.optionAfterPickingField(FilterMode.Performers, performerSort("nameAsc"), CoPerformerSort.FIELD, CoPerformerSort.options))
        assertEquals(performerSort("nameDesc"), SortCatalog.optionAfterPickingField(FilterMode.Performers, CoPerformerSort.Desc, "name", CoPerformerSort.options))
    }

    @Test fun dropsPerformersWithoutCountAndDuplicates() {
        val performers = listOf(Performer("1", "A"), Performer("1", "A"), Performer("2", "B"))
        val result = CoPerformerLogic.sorted(performers, mapOf("1" to 1).scenes())
        assertEquals(listOf(CoPerformer(Performer("1", "A"), CoAppearanceCounts(scenes = 1))), result)
    }
}
