package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickFiltersTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject
    private fun sort(mode: FilterMode, raw: String) = SortCatalog.option(mode, raw)!!

    @Test fun tappingInactiveFieldUsesNaturalDirection() {
        val current = sort(FilterMode.Performers, "sceneCountDesc")
        assertEquals("nameAsc", CatalogQuickSortCatalog.next(FilterMode.Performers, current, "name")?.raw)
        assertEquals("ratingDesc", CatalogQuickSortCatalog.next(FilterMode.Performers, current, "rating")?.raw)
    }

    @Test fun tappingActiveFieldFlipsDirection() {
        val desc = sort(FilterMode.Scenes, "dateDesc")
        assertEquals("dateAsc", CatalogQuickSortCatalog.next(FilterMode.Scenes, desc, "date")?.raw)
        val asc = sort(FilterMode.Scenes, "dateAsc")
        assertEquals("dateDesc", CatalogQuickSortCatalog.next(FilterMode.Scenes, asc, "date")?.raw)
    }

    @Test fun randomStaysRandomAndIsActive() {
        val random = sort(FilterMode.Tags, "random")
        assertEquals("random", CatalogQuickSortCatalog.next(FilterMode.Tags, random, "random")?.raw)
        assertTrue(CatalogQuickSortCatalog.isActive(random, "random"))
        assertFalse(CatalogQuickSortCatalog.isActive(random, "name"))
    }

    @Test fun availableFieldsDropSortsTheCatalogLacks() {
        // Images have no O-count sort; galleries sort by `images_count`.
        assertFalse(CatalogQuickSortCatalog.availableFields(FilterMode.Images).any { it.field == "o_counter" })
        assertTrue(CatalogQuickSortCatalog.availableFields(FilterMode.Galleries).any { it.field == "images_count" })
        assertTrue(CatalogQuickSortCatalog.availableFields(FilterMode.Groups).any { it.field == "random" })
    }

    @Test fun activeLabelMatchesRegardlessOfKeyOrderAndNumberType() {
        assertEquals("3★+", QuickFilterCatalog.activeLabel("rating100", obj("""{"value":59.0,"modifier":"GREATER_THAN"}"""), FilterMode.Scenes))
        assertEquals("Female", QuickFilterCatalog.activeLabel("gender", obj("""{"value_list":["FEMALE"],"modifier":"INCLUDES"}"""), FilterMode.Performers))
        assertEquals("< 10 min", QuickFilterCatalog.activeLabel("duration", obj("""{"modifier":"LESS_THAN","value":600}"""), FilterMode.Scenes))
        assertEquals("Favorites", QuickFilterCatalog.activeLabel("filter_favorites", JsonPrimitive(true), FilterMode.Performers))
        assertNull(QuickFilterCatalog.activeLabel("rating100", obj("""{"value":50,"modifier":"GREATER_THAN"}"""), FilterMode.Scenes))
        assertNull(QuickFilterCatalog.activeLabel("rating100", obj("""{"value":"59","modifier":"GREATER_THAN"}"""), FilterMode.Scenes))
    }

    @Test fun sectionsSkipKeysTheModeDoesNotKnow() {
        val keys = QuickFilterCatalog.sections(FilterMode.Scenes).map { it.key }
        assertEquals(listOf("tags", "rating100", "duration", "resolution", "organized", "play_count"), keys)
        assertTrue(QuickFilterCatalog.sections(FilterMode.Tags).none { it.key == "tags" })
    }

    @Test fun advancedOnlyCountIgnoresQuickRepresentableCriteria() {
        val dict = obj("""{"rating100":{"value":79,"modifier":"GREATER_THAN"},"tags":{"value":["1"],"modifier":"INCLUDES_ALL","depth":0},"o_counter":{"value":2,"modifier":"GREATER_THAN"},"organized":{"value":"x"}}""")
        assertEquals(2, QuickFilterCatalog.advancedOnlyCount(dict, FilterMode.Scenes))
    }

    @Test fun chipLabelUsesNamesThenSummary() {
        val tags = obj("""{"value":["1"],"excludes":["2"],"modifier":"INCLUDES","depth":0}""")
        assertEquals("#Blonde, −#Solo", QuickFilterCatalog.chipLabel("tags", tags, FilterMode.Scenes, mapOf("1" to "Blonde", "2" to "Solo")))
        assertEquals("Tags: 1 selected, 1 excluded", QuickFilterCatalog.chipLabel("tags", tags, FilterMode.Scenes, emptyMap()))
        assertEquals("O-Count: > 2", QuickFilterCatalog.chipLabel("o_counter", obj("""{"value":2,"modifier":"GREATER_THAN"}"""), FilterMode.Scenes, emptyMap()))
    }

    @Test fun toggledEntityCriterionKeepsExcludesAndDefaultsToAll() {
        val first = QuickFilterCatalog.toggledEntityCriterion(JsonObject(emptyMap()), "5", hierarchical = true)!!
        assertEquals(obj("""{"value":["5"],"modifier":"INCLUDES_ALL","depth":0}"""), first)
        assertNull(QuickFilterCatalog.toggledEntityCriterion(first, "5", hierarchical = true))
        val withExclude = obj("""{"value":["5"],"excludes":["9"],"modifier":"INCLUDES","depth":2}""")
        assertEquals(
            obj("""{"value":[],"excludes":["9"],"modifier":"INCLUDES","depth":2}"""),
            QuickFilterCatalog.toggledEntityCriterion(withExclude, "5", hierarchical = true),
        )
    }
}
