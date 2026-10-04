package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.SavedFilter
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FiltersLogicTest {

    private fun obj(json: String) = Json.parseToJsonElement(json).jsonObject

    private fun entry(id: String, name: String, mode: String?, objectFilter: String? = null, findFilter: String? = null, ui: String? = null, legacy: String? = null) =
        FiltersToolEntry(
            SavedFilter(
                id = id, name = name, mode = mode,
                findFilter = findFilter?.let { obj(it) },
                objectFilter = objectFilter?.let { obj(it) },
                uiOptions = ui?.let { obj(it) },
            ),
            legacy,
        )

    @Test fun groupsByModeInListedOrderSortedByName() {
        val entries = listOf(
            entry("1", "zeta", "SCENES"),
            entry("2", "Alpha", "PERFORMERS"),
            entry("3", "beta", "scenes"),
            entry("4", "Marker A", "SCENE_MARKERS"),
            entry("5", "Weird", "SOMETHING"),
            entry("6", "Gamma", "GROUPS"),
        )
        val grouped = FiltersLogic.grouped(entries, "")
        assertEquals(listOf("SCENES", "SCENE_MARKERS", "PERFORMERS", "GROUPS"), grouped.map { it.mode })
        assertEquals(listOf("beta", "zeta"), grouped[0].entries.map { it.filter.name })
        assertEquals(listOf("Scenes", "Markers", "Performers", "Groups"), grouped.map { FiltersLogic.modeTitle(it.mode) })
    }

    @Test fun searchIsTrimmedAndCaseInsensitive() {
        val entries = listOf(entry("1", "Favourite Scenes", "SCENES"), entry("2", "Tall", "PERFORMERS"))
        val grouped = FiltersLogic.grouped(entries, "  FAV ")
        assertEquals(1, grouped.size)
        assertEquals("1", grouped[0].entries.single().filter.id)
        assertTrue(FiltersLogic.grouped(entries, "nothing").isEmpty())
    }

    @Test fun modeTitles() {
        assertEquals("Markers", FiltersLogic.modeTitle("SCENE_MARKERS"))
        assertEquals("Other", FiltersLogic.modeTitle("UNKNOWN"))
        assertEquals("Other", FiltersLogic.modeTitle("nope"))
    }

    @Test fun criteriaSummaryUsesCatalogLabels() {
        val e = entry("1", "x", "SCENES", objectFilter = """{"tags":{"value":[]},"rating100":{"value":60},"studios":{},"o_counter":null,"duration_text":"12"}""")
        // Sorted keys: rating100, tags (studios empty, o_counter null, *_text scratch dropped).
        assertEquals("Rating, Tags", FiltersLogic.criteriaSummary(e))
        assertEquals("No criteria", FiltersLogic.criteriaSummary(entry("2", "y", "SCENES", objectFilter = "{}")))
    }

    @Test fun criteriaSummaryTruncatesAfterFour() {
        val e = entry("1", "x", "PERFORMERS", objectFilter = """{"a1":{"v":1},"a2":{"v":1},"a3":{"v":1},"a4":{"v":1},"a5":{"v":1}}""")
        assertEquals("a1, a2, a3, a4…", FiltersLogic.criteriaSummary(e))
    }

    @Test fun sortPairFromFindFilterThenLegacy() {
        assertEquals("created_at" to "ASC", FiltersLogic.encodedSortPair(entry("1", "x", "SCENES", findFilter = """{"sort":"created_at","direction":"ASC"}""")))
        assertEquals("title" to "DESC", FiltersLogic.encodedSortPair(entry("1", "x", "SCENES", findFilter = """{"sort":"title"}""")))
        assertEquals("date" to "ASC", FiltersLogic.encodedSortPair(entry("1", "x", "SCENES", legacy = """{"sortby":"date","sortdir":"ASC"}""")))
        assertNull(FiltersLogic.encodedSortPair(entry("1", "x", "SCENES", findFilter = """{"sort":" "}""")))
    }

    @Test fun renameInputKeepsCriteriaSortAndUiOptions() {
        val e = entry(
            "7", "Old", "scenes",
            objectFilter = """{"rating100":{"value":80,"modifier":"GREATER_THAN"}}""",
            findFilter = """{"sort":"random_123","direction":"DESC"}""",
            ui = """{"other":1,"stashy":{"sortRaw":"random"}}""",
        )
        val input = FiltersLogic.renameInput(e, "  New name ")!!
        assertEquals("7", input["id"]!!.jsonPrimitive.content)
        assertEquals("SCENES", input["mode"]!!.jsonPrimitive.content)
        assertEquals("New name", input["name"]!!.jsonPrimitive.content)
        assertEquals(obj("""{"sort":"random_123","direction":"DESC"}"""), input["find_filter"])
        assertEquals(obj("""{"rating100":{"value":80,"modifier":"GREATER_THAN"}}"""), input["object_filter"])
        assertEquals(obj("""{"other":1,"stashy":{"sortRaw":"random","liveFragment":{}}}"""), input["ui_options"])
        assertNull(FiltersLogic.renameInput(e, "   "))
    }

    @Test fun renameInputDefaultsSortToDateDesc() {
        val input = FiltersLogic.renameInput(entry("1", "x", "PERFORMERS"), "y")!!
        assertEquals(obj("""{"sort":"date","direction":"DESC"}"""), input["find_filter"])
        assertEquals(JsonObject(emptyMap()), input["object_filter"])
    }

    @Test fun parsesServerRowsWithLegacyFilter() {
        val rows = Json.parseToJsonElement(
            """[{"id":"1","name":"MarkerTest","mode":"SCENE_MARKERS","filter":"{\"sortby\":\"seconds\"}","object_filter":{},"ui_options":{},"find_filter":{"sort":"created_at","direction":"DESC"}}, 5]""",
        ) as JsonArray
        val entries = FiltersLogic.entries(rows)
        assertEquals(1, entries.size)
        assertEquals("MarkerTest", entries[0].filter.name)
        assertEquals("""{"sortby":"seconds"}""", entries[0].legacyFilter)
        assertEquals(JsonPrimitive("created_at"), entries[0].filter.findFilter?.get("sort"))
    }
}
