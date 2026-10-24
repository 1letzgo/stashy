package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NameRegexFilterTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test fun keyPerMode() {
        listOf(FilterMode.Performers, FilterMode.Studios, FilterMode.Tags, FilterMode.Groups)
            .forEach { assertEquals("name", NameRegexFilter.key(it)) }
        listOf(FilterMode.Scenes, FilterMode.Galleries, FilterMode.Images)
            .forEach { assertEquals("title", NameRegexFilter.key(it)) }
        assertNull(NameRegexFilter.key(FilterMode.SceneMarkers))
        assertFalse(NameRegexFilter.isSupported(FilterMode.SceneMarkers))
    }

    @Test fun criterionPrefixesCaseInsensitiveAndUsesMatchesRegex() {
        assertEquals(obj("""{"value":"(?i)^anna.*$","modifier":"MATCHES_REGEX"}"""), NameRegexFilter.criterion("^anna.*$"))
        assertEquals(obj("""{"value":"(?i)foo bar","modifier":"MATCHES_REGEX"}"""), NameRegexFilter.criterion("  foo bar "))
    }

    @Test fun blankAndInvalidInputBuildNothing() {
        assertNull(NameRegexFilter.criterion(""))
        assertNull(NameRegexFilter.criterion("   "))
        assertNull(NameRegexFilter.criterion("(unclosed"))
        assertNull(NameRegexFilter.criterion("[a-"))
        assertNull(NameRegexFilter.criterion("*x"))
    }

    @Test fun validation() {
        assertTrue(NameRegexFilter.isValid(""))
        assertTrue(NameRegexFilter.isValid("plain name"))
        assertTrue(NameRegexFilter.isValid("^(a|b)+\\d{2}$"))
        assertFalse(NameRegexFilter.isValid("(abc"))
        assertFalse(NameRegexFilter.isValid("a{2,1}"))
        assertFalse(NameRegexFilter.isValid("\\"))
    }

    @Test fun chipIsKeyedByModeAndEmptyWhenUnsupported() {
        assertEquals(obj("""{"name":{"value":"(?i)x","modifier":"MATCHES_REGEX"}}"""), NameRegexFilter.chip(FilterMode.Performers, "x"))
        assertEquals(obj("""{"title":{"value":"(?i)x","modifier":"MATCHES_REGEX"}}"""), NameRegexFilter.chip(FilterMode.Scenes, "x"))
        assertTrue(NameRegexFilter.chip(FilterMode.SceneMarkers, "x").isEmpty())
        assertTrue(NameRegexFilter.chip(FilterMode.Scenes, "(").isEmpty())
    }

    @Test fun chipWinsOverAdvancedCriterionForSameKey() {
        val doc = CriteriaDocument(FilterMode.Performers, obj("""{"name":{"value":"Bob","modifier":"EQUALS"},"favorite":true}"""))
        val merged = doc.merged(NameRegexFilter.layered(JsonObject(emptyMap()), FilterMode.Performers, "ann"))!!
        assertEquals(obj("""{"value":"(?i)ann","modifier":"MATCHES_REGEX"}"""), merged["name"])
        assertEquals(Json.parseToJsonElement("true"), merged["favorite"])
    }

    @Test fun layeredKeepsOtherChips() {
        val extra = obj("""{"path":{"value":"x","modifier":"MATCHES_REGEX"}}""")
        val out = NameRegexFilter.layered(extra, FilterMode.Images, "beach")
        assertEquals(setOf("path", "title"), out.keys)
        assertEquals(extra, NameRegexFilter.layered(extra, FilterMode.Images, ""))
    }

    @Test fun extractRoundTripsChipFromSavedCriteria() {
        val saved = obj("""{"name":{"value":"(?i)^ann","modifier":"MATCHES_REGEX"},"favorite":true}""")
        val (text, rest) = NameRegexFilter.extract(FilterMode.Tags, saved)
        assertEquals("^ann", text)
        assertEquals(obj("""{"favorite":true}"""), rest)
    }

    @Test fun extractLeavesNonChipCriteriaAlone() {
        val noPrefix = obj("""{"name":{"value":"^ann","modifier":"MATCHES_REGEX"}}""")
        assertEquals("" to noPrefix, NameRegexFilter.extract(FilterMode.Performers, noPrefix))
        val equals = obj("""{"title":{"value":"(?i)x","modifier":"EQUALS"}}""")
        assertEquals("" to equals, NameRegexFilter.extract(FilterMode.Scenes, equals))
        val markers = obj("""{"title":{"value":"(?i)x","modifier":"MATCHES_REGEX"}}""")
        assertEquals("" to markers, NameRegexFilter.extract(FilterMode.SceneMarkers, markers))
    }
}
