package de.letzgo.stashy.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The sub-studio options (iOS `StudioCountsStore.hidesSubStudios` / `contentDepth`). */
class SubStudiosTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    private val parentsIsNull = obj("""{"parents":{"modifier":"IS_NULL"}}""")

    @Test fun depthFollowsTheContentSwitch() {
        assertEquals(-1, SubStudios.depth(true))
        assertEquals(0, SubStudios.depth(false))
    }

    @Test fun hideAddsParentsIsNull() {
        assertEquals(parentsIsNull, SubStudios.hideCriterion(true, "", null))
        assertEquals(parentsIsNull, SubStudios.hideCriterion(true, "  ", obj("""{"favorite":true}""")))
    }

    @Test fun nothingWhenOffSearchingOrUserHasParents() {
        assertNull(SubStudios.hideCriterion(false, "", null))
        assertNull(SubStudios.hideCriterion(true, "blender", null))
        assertNull(SubStudios.hideCriterion(true, "", obj("""{"parents":{"value":["1"],"modifier":"INCLUDES"}}""")))
    }

    @Test fun withHideKeepsTheUsersCriteria() {
        val own = obj("""{"favorite":true}""")
        assertEquals(obj("""{"favorite":true,"parents":{"modifier":"IS_NULL"}}"""), SubStudios.withHide(own, true, ""))
        assertEquals(parentsIsNull, SubStudios.withHide(null, true, ""))
        assertEquals(own, SubStudios.withHide(own, false, ""))
        assertNull(SubStudios.withHide(null, true, "x"))
    }

    @Test fun hidingSwitchesContentOn() {
        assertTrue(SubStudios.includeAfterHideChange(hideNow = true, includeBefore = false))
        assertTrue(SubStudios.includeAfterHideChange(hideNow = false, includeBefore = true))
        assertFalse(SubStudios.includeAfterHideChange(hideNow = false, includeBefore = false))
    }

    @Test fun studioScopeCarriesDepthAndTagsGoThroughScenes() {
        val scenes = SubStudios.studioScope(FilterMode.Scenes, "7", true)
        assertEquals(obj("""{"studios":{"value":["7"],"modifier":"INCLUDES","depth":-1}}"""), scenes)
        assertEquals(scenes, SubStudios.studioScope(FilterMode.Images, "7", true))
        assertEquals(obj("""{"studios":{"value":["7"],"modifier":"INCLUDES","depth":0}}"""), SubStudios.studioScope(FilterMode.Performers, "7", false))
        assertEquals(
            obj("""{"scenes_filter":{"studios":{"value":["7"],"modifier":"INCLUDES","depth":-1}}}"""),
            SubStudios.studioScope(FilterMode.Tags, "7", true),
        )
    }

    @Test fun isNullSurvivesTheSanitizer() {
        val q = CatalogQuery(FilterMode.Studios, SortCatalog.option(FilterMode.Studios, SortCatalog.defaultRaw(FilterMode.Studios))!!, live = parentsIsNull)
        assertEquals(parentsIsNull, q.entityFilter())
    }

    private fun studio(name: String, own: Int?, all: Int?) = Studio(id = name, name = name, sceneCount = own, sceneCountAll = all)

    @Test fun sceneCountSortIsDoneHereOnlyWithIncludeOn() {
        assertTrue(SubStudios.sortsBySceneCountAll("scenes_count", true))
        assertFalse(SubStudios.sortsBySceneCountAll("scenes_count", false))
        assertFalse(SubStudios.sortsBySceneCountAll("name", true))
        assertFalse(SubStudios.sortsBySceneCountAll("galleries_count", true))
    }

    @Test fun sortsBySceneCountAllDescendingWithNameTies() {
        val list = listOf(
            studio("Blender Shorts", 1, 1), studio("Apple Samples", 1, 2), studio("Blender", 1, 3),
            studio("Blender Open Movies", 0, 1), studio("durian Project", 1, 1), studio("Apple HLS", 1, 1),
        )
        assertEquals(
            listOf("Blender", "Apple Samples", "Apple HLS", "Blender Open Movies", "Blender Shorts", "durian Project"),
            SubStudios.sortedBySceneCountAll(list, ascending = false).map { it.name },
        )
    }

    @Test fun sortsAscendingAndFallsBackToOwnCount() {
        val list = listOf(studio("B", 5, null), studio("A", 2, null), studio("C", 0, 9), studio("D", null, null))
        assertEquals(listOf("D", "A", "B", "C"), SubStudios.sortedBySceneCountAll(list, ascending = true).map { it.name })
        assertEquals(listOf("C", "B", "A", "D"), SubStudios.sortedBySceneCountAll(list, ascending = false).map { it.name })
    }

    @Test fun aliasIsInsertedAfterStudioFields() {
        val out = SubStudios.withSceneCountAll("studios {\n      ...StudioFields\n    }")
        assertTrue(out.contains("...StudioFields\n      scene_count_all: scene_count(depth: -1)"))
    }
}
