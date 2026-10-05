package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortCatalog
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FiltersEditorLogicTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test fun defaultSortPerMode() {
        assertEquals("name" to "ASC", FiltersEditorLogic.defaultSortPair(FilterMode.Performers))
        assertEquals("name" to "ASC", FiltersEditorLogic.defaultSortPair(FilterMode.Tags))
        assertEquals("seconds" to "ASC", FiltersEditorLogic.defaultSortPair(FilterMode.SceneMarkers))
        assertEquals("date" to "DESC", FiltersEditorLogic.defaultSortPair(FilterMode.Images))
    }

    @Test fun initialSortPrefersStashyRawThenFindFilterThenDefault() {
        val withRaw = SavedFilter("1", "A", "SCENES", findFilter = obj("""{"sort":"date","direction":"ASC"}"""),
            uiOptions = obj("""{"stashy":{"sortRaw":"ratingDesc"}}"""))
        assertEquals("ratingDesc", FiltersEditorLogic.initialSort(withRaw, FilterMode.Scenes)?.raw)
        val withPair = SavedFilter("2", "B", "SCENES", findFilter = obj("""{"sort":"date","direction":"ASC"}"""))
        assertEquals("dateAsc", FiltersEditorLogic.initialSort(withPair, FilterMode.Scenes)?.raw)
        val randomPair = SavedFilter("3", "C", "SCENES", findFilter = obj("""{"sort":"random_1234","direction":"DESC"}"""))
        assertEquals("random", FiltersEditorLogic.initialSort(randomPair, FilterMode.Scenes)?.raw)
        assertEquals("dateDesc", FiltersEditorLogic.initialSort(null, FilterMode.Images)?.raw)
        assertEquals("nameAsc", FiltersEditorLogic.initialSort(null, FilterMode.Tags)?.raw)
        // Every mode the "+" menu offers resolves to a sort.
        FiltersLogic.listedModes.forEach { raw ->
            assertTrue(raw, FiltersEditorLogic.initialSort(null, FilterMode.from(raw)) != null)
        }
    }

    @Test fun saveAsSeed() {
        assertEquals("Faves copy", FiltersEditorLogic.saveAsSeed("  Faves "))
        assertEquals("", FiltersEditorLogic.saveAsSeed("  "))
    }

    @Test fun saveInputKeepsLiveFragmentOnUpdateOnly() {
        val existing = SavedFilter("7", "Old", "TAGS",
            uiOptions = obj("""{"stashy":{"liveFragment":{"favorite":true},"sortRaw":"nameAsc"}}"""))
        val sort = SortCatalog.option(FilterMode.Tags, "nameDesc")!!
        val update = FiltersEditorLogic.saveInput(FilterMode.Tags, "7", existing, " New ", sort, obj("""{"favorite":true}"""))!!
        assertEquals(JsonPrimitive("7"), update["id"])
        assertEquals(JsonPrimitive("New"), update["name"])
        assertEquals(JsonPrimitive("TAGS"), update["mode"])
        assertEquals(obj("""{"sort":"name","direction":"DESC"}"""), update["find_filter"])
        val stashy = update["ui_options"]!!.jsonObject["stashy"]!!.jsonObject
        assertEquals(obj("""{"favorite":true}"""), stashy["liveFragment"])
        assertEquals(JsonPrimitive("nameDesc"), stashy["sortRaw"])

        val copy = FiltersEditorLogic.saveInput(FilterMode.Tags, null, existing, "Copy", sort, JsonObject(emptyMap()))!!
        assertNull(copy["id"])
        assertEquals(JsonObject(emptyMap()), copy["ui_options"]!!.jsonObject["stashy"]!!.jsonObject["liveFragment"])
        assertNull(FiltersEditorLogic.saveInput(FilterMode.Tags, null, null, "  ", sort, JsonObject(emptyMap())))
    }

    @Test fun saveInputWritesSeededRandomSort() {
        val random = SortCatalog.option(FilterMode.Scenes, "random")!!
        val input = FiltersEditorLogic.saveInput(FilterMode.Scenes, null, null, "R", random, JsonObject(emptyMap()))!!
        val sort = (input["find_filter"]!!.jsonObject["sort"] as JsonPrimitive).content
        assertTrue(sort, sort.startsWith("random_"))
        assertEquals(JsonPrimitive("random"), input["ui_options"]!!.jsonObject["stashy"]!!.jsonObject["sortRaw"])
    }
}
