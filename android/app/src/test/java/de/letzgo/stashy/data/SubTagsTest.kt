package de.letzgo.stashy.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The sub-tag options (iOS `TagHierarchy`). */
class SubTagsTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    private val topLevel = obj("""{"parent_count":{"value":0,"modifier":"EQUALS"}}""")

    @Test fun depthFollowsTheContentSwitch() {
        assertEquals(-1, SubTags.depth(true))
        assertEquals(0, SubTags.depth(false))
        // Settings unreadable (no Prefs in a JVM test): off.
        assertEquals(0, TagHierarchyStore.contentDepth)
    }

    @Test fun hideAddsParentCountZero() {
        assertEquals(topLevel, SubTags.hideCriterion(true, "", null))
        assertEquals(topLevel, SubTags.hideCriterion(true, "  ", obj("""{"favorite":true}""")))
    }

    @Test fun nothingWhenOffSearchingOrUserHasParentCriteria() {
        assertNull(SubTags.hideCriterion(false, "", null))
        assertNull(SubTags.hideCriterion(true, "nature", null))
        assertNull(SubTags.hideCriterion(true, "", obj("""{"parents":{"value":["1"],"modifier":"INCLUDES","depth":0}}""")))
        assertNull(SubTags.hideCriterion(true, "", obj("""{"parent_count":{"value":2,"modifier":"GREATER_THAN"}}""")))
    }

    @Test fun parentCountSurvivesTheSanitizer() {
        val q = CatalogQuery(FilterMode.Tags, SortCatalog.option(FilterMode.Tags, SortCatalog.defaultRaw(FilterMode.Tags))!!, live = topLevel)
        assertEquals(topLevel, q.entityFilter())
    }

    @Test fun hidingSwitchesContentOn() {
        assertTrue(SubTags.includeAfterHideChange(hideNow = true, includeBefore = false))
        assertTrue(SubTags.includeAfterHideChange(hideNow = false, includeBefore = true))
        assertFalse(SubTags.includeAfterHideChange(hideNow = false, includeBefore = false))
    }

    @Test fun scopesCarryTheDepth() {
        assertEquals(obj("""{"tags":{"value":["7"],"modifier":"INCLUDES","depth":-1}}"""), SubTags.tagScope("7", true))
        assertEquals(obj("""{"tags":{"value":["7"],"modifier":"INCLUDES","depth":0}}"""), SubTags.tagScope("7", false))
        assertEquals(obj("""{"parents":{"value":["7"],"modifier":"INCLUDES","depth":0}}"""), SubTags.subTagScope("7"))
    }

    private fun tag(name: String, own: Int?, all: Int?) = Tag(id = name, name = name, sceneCount = own, sceneCountAll = all)

    @Test fun sceneCountSortIsDoneHereOnlyWithIncludeOn() {
        assertTrue(SubTags.sortsBySceneCountAll("scenes_count", true))
        assertFalse(SubTags.sortsBySceneCountAll("scenes_count", false))
        assertFalse(SubTags.sortsBySceneCountAll("name", true))
        assertFalse(SubTags.sortsBySceneCountAll("images_count", true))
    }

    @Test fun sortsBySceneCountAllDescendingWithNameTies() {
        val list = listOf(tag("Plants", 1, 1), tag("Animals", 0, 2), tag("Nature", 0, 3), tag("rabbits", 1, 1), tag("Fantasy", 1, 1))
        assertEquals(
            listOf("Nature", "Animals", "Fantasy", "Plants", "rabbits"),
            SubTags.sortedBySceneCountAll(list, ascending = false).map { it.name },
        )
    }

    @Test fun sortsAscendingAndFallsBackToOwnCount() {
        val list = listOf(tag("B", 5, null), tag("A", 2, null), tag("C", 0, 9), tag("D", null, null))
        assertEquals(listOf("D", "A", "B", "C"), SubTags.sortedBySceneCountAll(list, ascending = true).map { it.name })
        assertEquals(listOf("C", "B", "A", "D"), SubTags.sortedBySceneCountAll(list, ascending = false).map { it.name })
    }

    @Test fun aliasesAreInsertedAfterTagFieldsOnlyWhileIncluding() {
        val doc = "tags {\n      ...TagFields\n      parents { id name }\n    }"
        assertEquals(doc, SubTags.withCountsAll(doc, false))
        val out = SubTags.withCountsAll(doc, true)
        assertTrue(out.contains("...TagFields\n      scene_count_all: scene_count(depth: -1)"))
        for (alias in listOf("image_count_all: image_count", "gallery_count_all: gallery_count", "scene_marker_count_all: scene_marker_count", "performer_count_all: performer_count")) {
            assertTrue(alias, out.contains("$alias(depth: -1)"))
        }
        assertTrue(out.contains("parents { id name }"))
    }

    @Test fun partOfNamesTheFirstParentAndCountsTheRest() {
        assertNull(SubTags.partOfParts(null))
        assertNull(SubTags.partOfParts(emptyList()))
        assertEquals("Animals" to 0, SubTags.partOfParts(listOf(IdName("1", "Animals"))))
        assertEquals("Animals" to 1, SubTags.partOfParts(listOf(IdName("1", "Animals"), IdName("2", "Nature"))))
    }

    @Test fun tagDecodesParentsAndCounts() {
        val t = Json { ignoreUnknownKeys = true }.decodeFromString(
            Tag.serializer(),
            """{"id":"5","name":"Sea Life","parents":[{"id":"2","name":"Animals"},{"id":"1","name":"Nature"}],"child_count":0,"scene_count_all":3}""",
        )
        assertEquals(2, t.parents?.size)
        assertEquals(0, t.childCount)
        assertEquals(3, t.sceneCountAll)
    }
}
