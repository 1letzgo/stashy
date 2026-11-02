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

    // MARK: Tags — name or alias (iOS `searchesAliases`)

    private val aliasGroup = """{"AND":{"name":{"value":"(?i)ann","modifier":"MATCHES_REGEX"},"OR":{"aliases":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}}}}"""

    @Test fun tagsChipSearchesNameOrAliasInsideAnd() {
        assertTrue(NameRegexFilter.searchesAliases(FilterMode.Tags))
        assertEquals(obj(aliasGroup), NameRegexFilter.chip(FilterMode.Tags, " ann "))
        // ANDed with the other criteria once merged onto the document.
        val doc = CriteriaDocument(FilterMode.Tags, obj("""{"favorite":true}"""))
        val merged = doc.merged(NameRegexFilter.layered(JsonObject(emptyMap()), FilterMode.Tags, "ann", doc.sanitizedObjectFilter))!!
        assertEquals(obj("""{"favorite":true}""" ).plusAll(obj(aliasGroup)), merged)
    }

    @Test fun tagsAliasGroupReadsBack() {
        assertEquals("ann", NameRegexFilter.aliasSearchPattern(FilterMode.Tags, obj(aliasGroup)))
        val saved = obj("""{"favorite":true}""").plusAll(obj(aliasGroup))
        val (text, rest) = NameRegexFilter.extract(FilterMode.Tags, saved)
        assertEquals("ann", text)
        assertEquals(obj("""{"favorite":true}"""), rest)
        // An AND that only resembles the group stays in the criteria.
        val mismatch = obj("""{"AND":{"name":{"value":"(?i)ann","modifier":"MATCHES_REGEX"},"OR":{"aliases":{"value":"(?i)bob","modifier":"MATCHES_REGEX"}}}}""")
        assertNull(NameRegexFilter.aliasSearchPattern(FilterMode.Tags, mismatch))
        assertEquals("" to mismatch, NameRegexFilter.extract(FilterMode.Tags, mismatch))
        val extraKey = obj("""{"AND":{"name":{"value":"(?i)ann","modifier":"MATCHES_REGEX"},"OR":{"aliases":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}},"favorite":true}}""")
        assertEquals("" to extraKey, NameRegexFilter.extract(FilterMode.Tags, extraKey))
    }

    @Test fun tagsClearingRemovesTheGroup() {
        assertTrue(NameRegexFilter.chip(FilterMode.Tags, "").isEmpty())
        val base = obj("""{"favorite":true}""")
        assertEquals(base, NameRegexFilter.layered(base, FilterMode.Tags, "  "))
        // Saving with the field cleared drops the group the previous save held.
        val saved = mergedObjectFilterForSave(null, base, previousLive = obj(aliasGroup))
        assertEquals(base, saved)
    }

    @Test fun tagsFallBackToNameWhenCriteriaHoldTheirOwnAnd() {
        val foreign = obj("""{"AND":{"favorite":true}}""")
        val chip = NameRegexFilter.chip(FilterMode.Tags, "ann", foreign)
        assertEquals(obj("""{"name":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}}"""), chip)
        val doc = CriteriaDocument(FilterMode.Tags, foreign)
        val merged = doc.merged(NameRegexFilter.layered(JsonObject(emptyMap()), FilterMode.Tags, "ann", doc.sanitizedObjectFilter))!!
        assertEquals(setOf("AND", "name"), merged.keys)
        assertEquals(foreign["AND"], merged["AND"])
        // The field's own group may be replaced by a new pattern.
        assertEquals(
            obj(aliasGroup.replace("ann", "bob")),
            NameRegexFilter.chip(FilterMode.Tags, "bob", obj(aliasGroup)),
        )
        // A legacy root `name` regex still reads back into the field.
        val legacy = obj("""{"name":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}}""")
        assertEquals("ann" to JsonObject(emptyMap()), NameRegexFilter.extract(FilterMode.Tags, legacy))
    }

    @Test fun nonTagModesKeepTheRootCriterion() {
        val modes = listOf(FilterMode.Performers, FilterMode.Studios, FilterMode.Groups, FilterMode.Scenes, FilterMode.Galleries, FilterMode.Images)
        modes.forEach { mode ->
            assertFalse(NameRegexFilter.searchesAliases(mode))
            val key = NameRegexFilter.key(mode)!!
            assertEquals(obj("""{"$key":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}}"""), NameRegexFilter.chip(mode, "ann"))
            assertEquals(obj("""{"$key":{"value":"(?i)ann","modifier":"MATCHES_REGEX"}}"""), NameRegexFilter.chip(mode, "ann", JsonObject(emptyMap())))
            val group = obj(aliasGroup.replace("\"name\"", "\"$key\""))
            assertNull(NameRegexFilter.aliasSearchPattern(mode, group))
            assertEquals("" to group, NameRegexFilter.extract(mode, group))
        }
        assertFalse(NameRegexFilter.searchesAliases(FilterMode.SceneMarkers))
        assertTrue(NameRegexFilter.chip(FilterMode.SceneMarkers, "ann").isEmpty())
    }

    private fun JsonObject.plusAll(other: JsonObject): JsonObject = JsonObject(LinkedHashMap(this).apply { putAll(other) })
}
