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
}
