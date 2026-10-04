package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TabConfigLogicTest {
    /** JSON as iOS `JSONEncoder` writes `[HomeRowConfig]`. */
    private val iosHomeRows = """
        [{"id":"A1B2C3D4-0000-0000-0000-000000000001","title":"x","isEnabled":true,"sortOrder":1,"type":"statistics"},
         {"id":"A1B2C3D4-0000-0000-0000-000000000002","title":"y","isEnabled":false,"sortOrder":0,"type":"lastAdded3Min"},
         {"id":"A1B2C3D4-0000-0000-0000-000000000003","title":"dup","isEnabled":true,"sortOrder":2,"type":"statistics"},
         {"id":"A1B2C3D4-0000-0000-0000-000000000004","title":"z","isEnabled":true,"sortOrder":3,"type":"someFutureRow"}]
    """.trimIndent()

    @Test fun decodesIosHomeRowsLeniently() {
        val rows = TabConfigLogic.decodeLenient(iosHomeRows, HomeRowConfig.serializer())!!
        assertEquals(3, rows.size) // unknown type dropped
        assertEquals(HomeRowType.Statistics, rows[0].type)
        assertNull(TabConfigLogic.decodeLenient("not json", HomeRowConfig.serializer()))
    }

    @Test fun normalizesHomeRowsLikeIos() {
        val decoded = TabConfigLogic.decodeLenient(iosHomeRows, HomeRowConfig.serializer())
        val (rows, changed) = TabConfigLogic.normalizeHomeRows(decoded, promoteLastPlayed = true)
        assertTrue(changed)
        assertEquals(rows.map { it.type }.toSet().size, rows.size) // deduped
        assertEquals(HomeRowType.LastPlayed, rows.first().type) // promoted and enabled
        assertTrue(rows.first().isEnabled)
        assertEquals(rows.indices.toList(), rows.map { it.sortOrder })
        assertTrue(rows.all { it.title == it.type.defaultTitle })
        assertFalse(rows.first { it.type == HomeRowType.TopCounter3Min }.isEnabled) // ensured rows keep iOS defaults
        assertTrue(rows.any { it.type == HomeRowType.Channels })
    }

    @Test fun defaultHomeRowsMatchIos() {
        val rows = TabConfigLogic.defaultHomeRows()
        assertEquals(18, rows.size)
        assertEquals(listOf(HomeRowType.LastPlayed, HomeRowType.Statistics, HomeRowType.LastAdded3Min), rows.take(3).map { it.type })
        assertFalse(rows.first { it.type == HomeRowType.TopRating3Min }.isEnabled)
    }

    @Test fun encodesHomeRowsWithIosKeys() {
        val json = Json.encodeToString(ListSerializer(HomeRowConfig.serializer()), TabConfigLogic.defaultHomeRows().take(1))
        val obj = Json.parseToJsonElement(json).jsonArray[0].jsonObject
        assertEquals(setOf("id", "title", "isEnabled", "sortOrder", "type"), obj.keys)
        assertEquals("lastPlayed", obj["type"]!!.jsonPrimitive.content)
    }

    @Test fun tabConfigUsesSortOptionKeyAndMigrates() {
        val legacy = """[{"id":"scenes","isVisible":true,"sortOrder":3,"sortOption":"date"},
            {"id":"downloads","isVisible":true,"sortOrder":4},{"id":"dashboard","isVisible":false,"sortOrder":5},{"id":"home","isVisible":true,"sortOrder":1}]"""
        val (tabs, save) = TabConfigLogic.normalizeTabs(TabConfigLogic.decodeLenient(legacy, TabConfig.serializer()))
        assertTrue(save)
        assertEquals("dateDesc", tabs.first { it.id == AppTab.Scenes }.defaultSortOption)
        assertFalse(tabs.first { it.id == AppTab.Downloads }.isVisible)
        assertTrue(tabs.first { it.id == AppTab.Dashboard }.isVisible)
        assertEquals(TabConfigLogic.defaultTabs().map { it.id }.toSet(), tabs.map { it.id }.toSet())
        val encoded = Json.encodeToString(TabConfig.serializer(), tabs.first { it.id == AppTab.Scenes })
        assertTrue(encoded.contains("\"sortOption\":\"dateDesc\""))
        assertFalse(encoded.contains("defaultFilterId")) // nil fields omitted like Swift
    }

    @Test fun syncsChannelItems() {
        val current = listOf(HomeChannelItemConfig("2", HomeChannelSourceKind.Scenes, false, 0), HomeChannelItemConfig("9", HomeChannelSourceKind.Scenes, true, 1))
        val filters = listOf(Triple("2", "Zeta", "SCENES"), Triple("3", "alpha", "IMAGES"), Triple("4", "Perf", "PERFORMERS"))
        val result = TabConfigLogic.syncChannelItems(current, filters)
        assertEquals(listOf("scenes.2", "clips.3"), result.map { it.id })
        assertFalse(result[0].isEnabled) // existing choice kept
        assertEquals(listOf(0, 1), result.map { it.sortOrder })
    }

    @Test fun reelsModesGetMissingModes() {
        val (modes, changed) = TabConfigLogic.normalizeReelsModes(listOf(ReelsModeConfig(type = ReelsModeType.Markers, isEnabled = true, sortOrder = 0)))
        assertTrue(changed)
        assertEquals(ReelsModeType.entries.size, modes.size)
        assertEquals("dateDesc", modes.first { it.type == ReelsModeType.Pics }.defaultSortOption)
    }

    @Test fun moveAndLabels() {
        assertEquals(listOf("b", "c", "a"), TabConfigLogic.move(listOf("a", "b", "c"), 0, 2))
        assertEquals("Immediately", TabConfigLogic.playCountThresholdLabel(0.0))
        assertEquals("30 s", TabConfigLogic.playCountThresholdLabel(30.0))
        assertEquals("2 min", TabConfigLogic.playCountThresholdLabel(120.0))
        assertEquals("2×", TabConfigLogic.holdSpeedLabel(2.0))
        assertEquals("2.5×", TabConfigLogic.holdSpeedLabel(2.5))
    }

    @Test fun parsesServerAddresses() {
        assertEquals(ServerAddress.Parsed("192.168.1.10", "9999", "/stash"), ServerAddress.parse("http://192.168.1.10:9999/stash/"))
        assertEquals(ServerAddress.Parsed("stash.example.com", null, null), ServerAddress.parse("stash.example.com"))
        assertEquals(ServerProtocol.HTTPS to "x.y", ServerAddress.detectProtocol(" HTTPS://x.y "))
        assertEquals("http://h:9999/s", ServerAddress.baseURL("h:9999/s", ServerProtocol.HTTP))
    }

    @Test fun sanitizesWebUiSavedFilter() {
        val raw = Json.parseToJsonElement("""
            {"tags":{"value":{"items":[{"id":"5","label":"x"}],"excluded":[{"id":"7","label":"y"}],"depth":-1},"modifier":"INCLUDES"},
             "performers":{"value":{"items":[],"excluded":[]},"modifier":"INCLUDES"},
             "organized":{"value":"true","modifier":"EQUALS"},
             "rating100":{"value":{"value":"60"},"modifier":"GREATER_THAN"},
             "sort":"date"}
        """).jsonObject
        val out: JsonObject = FilterMapper.sanitize(raw)
        val tags = out["tags"]!!.jsonObject
        assertEquals(listOf("5"), tags["value"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(listOf("7"), tags["excludes"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals("-1", tags["depth"]!!.jsonPrimitive.content)
        assertFalse(out.containsKey("performers")) // empty "Any" criterion dropped
        assertEquals("true", out["organized"]!!.jsonPrimitive.content)
        assertEquals(60, out["rating100"]!!.jsonObject["value"]!!.jsonPrimitive.content.toInt())
        assertFalse(out.containsKey("sort"))
    }
}
