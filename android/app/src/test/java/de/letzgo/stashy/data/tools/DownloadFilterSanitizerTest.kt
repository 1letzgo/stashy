package de.letzgo.stashy.data.tools

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** Port of iOS `FilterMapper.sanitize` used by the download sync jobs. */
class DownloadFilterSanitizerTest {
    private fun obj(text: String) = Json.parseToJsonElement(text) as JsonObject

    @Test
    fun webUiItemsBecomeGraphQLIds() {
        val out = DownloadFilterSanitizer.sanitize(obj(
            """{"tags":{"value":{"items":[{"id":"5","label":"A"}],"excluded":[{"id":"9","label":"B"}],"depth":-1},"modifier":"INCLUDES_ALL"},
                "performers":{"value":{"items":[],"excluded":[]},"modifier":"INCLUDES"},
                "rating100":{"value":"80","modifier":"GREATER_THAN"},
                "organized":{"value":"true","modifier":"EQUALS"},
                "sortby":"date","mode":"SCENES"}"""
        ))
        val tags = out["tags"]!!.jsonObject
        assertEquals(listOf("5"), tags["value"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(listOf("9"), tags["excludes"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("-1", tags["depth"]!!.jsonPrimitive.content)
        // Empty "Any" multi criterion is dropped.
        assertNull(out["performers"])
        assertEquals("80", out["rating100"]!!.jsonObject["value"]!!.jsonPrimitive.content)
        assertEquals(true, out["organized"]!!.jsonPrimitive.content.toBoolean())
        assertFalse("mode" in out)
        assertEquals("date", out["sortby"]!!.jsonPrimitive.content)
    }

    @Test
    fun criteriaArrayIsMapped() {
        val out = DownloadFilterSanitizer.sanitize(obj(
            """{"c":[{"id":"rating","value":{"value":60},"modifier":"EQUALS","type":"rating"},
                     {"id":"is_missing","value":"cover"},
                     {"id":"orientation","value":["landscape"],"modifier":"INCLUDES"}]}"""
        ))
        assertEquals("60", out["rating100"]!!.jsonObject["value"]!!.jsonPrimitive.content)
        assertEquals("cover", out["is_missing"]!!.jsonPrimitive.content)
        val orientation = out["orientation"]!!.jsonObject
        assertEquals("LANDSCAPE", orientation["value"]!!.jsonArray[0].jsonPrimitive.content)
        assertNull(orientation["modifier"])
        assertNull(out["c"])
    }

    @Test
    fun nullModifierKeepsCriterion() {
        val out = DownloadFilterSanitizer.sanitize(obj("""{"studios":{"modifier":"IS_NULL"}}"""))
        assertEquals("IS_NULL", out["studios"]!!.jsonObject["modifier"]!!.jsonPrimitive.content)
    }
}
