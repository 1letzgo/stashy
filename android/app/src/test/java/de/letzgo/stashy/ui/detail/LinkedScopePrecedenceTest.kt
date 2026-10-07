package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortCatalog
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The detail tabs (iOS `DetailLinked*FilterModel`) layer the entity scope last: no saved filter,
 * preset or criterion from the sheet can widen a performer / studio / tag / group list.
 */
class LinkedScopePrecedenceTest {
    private fun includes(vararg ids: String, modifier: String = "INCLUDES") = buildJsonObject {
        put("value", JsonArray(ids.map { JsonPrimitive(it) }))
        put("modifier", JsonPrimitive(modifier))
    }

    private fun sort(mode: FilterMode) = SortCatalog.option(mode, SortCatalog.defaultRaw(mode))!!

    @Test fun scopeWinsOverLiveCriterionOfTheSameKey() {
        val scope = DetailRepository.scope("performers", "7")
        val live = JsonObject(mapOf("performers" to includes("1", "2", modifier = "INCLUDES_ALL")))
        val f = CatalogQuery(FilterMode.Galleries, sort(FilterMode.Galleries), live = live, scope = scope).entityFilter()!!
        assertEquals(DetailRepository.includes("7"), f["performers"])
    }

    @Test fun scopeWinsOverSavedFilterAndKeepsOtherCriteria() {
        val base = SavedFilter(
            "1", "Mine", "SCENES",
            objectFilter = JsonObject(mapOf(
                "tags" to includes("99"),
                "rating100" to buildJsonObject { put("value", JsonPrimitive(60)); put("modifier", JsonPrimitive("GREATER_THAN")) },
            )),
        )
        val scope = DetailRepository.scope("tags", "5")
        val f = CatalogQuery(FilterMode.Scenes, sort(FilterMode.Scenes), base = base, scope = scope).entityFilter()!!
        assertEquals(DetailRepository.includes("5"), f["tags"])
        assertNotNull(f["rating100"])
    }

    @Test fun childStudioScopeUsesParentsAndNeverFallsBack() {
        val scope = DetailRepository.scope("parents", "3")
        val live = JsonObject(mapOf("parents" to includes("8")))
        val q = CatalogQuery(FilterMode.Studios, sort(FilterMode.Studios), live = live, scope = scope)
        assertEquals(DetailRepository.includes("3"), q.entityFilter()!!["parents"])
        assertNull(DetailRepository.sceneFilterFallback(q))
    }

    @Test fun oldServerFallbackWrapsScopeInScenesFilterLast() {
        val scope = DetailRepository.scope("performers", "7")
        val live = JsonObject(mapOf("scenes_filter" to buildJsonObject { put("title", JsonPrimitive("x")) }))
        val q = CatalogQuery(FilterMode.Tags, sort(FilterMode.Tags), live = live, scope = scope)
        val fallback = DetailRepository.sceneFilterFallback(q)!!
        val f = fallback.entityFilter()!!
        assertEquals(scope, f["scenes_filter"]!!.jsonObject)
        assertNull(f["performers"])
    }

    @Test fun fallbackOnlyForEntityTabsThatHadIt() {
        val scope = DetailRepository.scope("studios", "3")
        for (mode in listOf(FilterMode.Performers, FilterMode.Studios, FilterMode.Tags, FilterMode.Groups)) {
            assertNotNull(mode.raw, DetailRepository.sceneFilterFallback(CatalogQuery(mode, sort(mode), scope = scope)))
        }
        for (mode in listOf(FilterMode.Scenes, FilterMode.Galleries, FilterMode.Images)) {
            assertNull(mode.raw, DetailRepository.sceneFilterFallback(CatalogQuery(mode, sort(mode), scope = scope)))
        }
        assertNull(DetailRepository.sceneFilterFallback(CatalogQuery(FilterMode.Tags, sort(FilterMode.Tags))))
    }

    @Test fun filteredTabStaysVisibleWhenEmpty() {
        assertEquals(0, LinkedCatalog.visibleCount(0, filtered = false))
        assertEquals(1, LinkedCatalog.visibleCount(0, filtered = true))
        assertEquals(12, LinkedCatalog.visibleCount(12, filtered = true))
    }

    @Test fun detailSortDefaultsResolveInSortCatalog() {
        DetailSort.Scene.entries.forEach { assertNotNull(it.raw, SortCatalog.option(FilterMode.Scenes, it.raw)) }
        assertNotNull(SortCatalog.option(FilterMode.Images, DetailSort.Image.DateDesc.raw))
        assertNotNull(SortCatalog.option(FilterMode.Galleries, "dateDesc"))
        assertNotNull(SortCatalog.option(FilterMode.Studios, "nameAsc"))
        assertNotNull(SortCatalog.option(FilterMode.Performers, "nameAsc"))
        assertNotNull(SortCatalog.option(FilterMode.Tags, "sceneCountDesc"))
        assertNotNull(SortCatalog.option(FilterMode.Groups, "nameAsc"))
    }
}
