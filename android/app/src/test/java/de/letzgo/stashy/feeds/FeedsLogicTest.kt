package de.letzgo.stashy.feeds

import de.letzgo.stashy.data.FeedCriteria
import de.letzgo.stashy.data.FeedQueryKind
import de.letzgo.stashy.data.FeedSortKinds
import de.letzgo.stashy.data.FeedsQuery
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageSortOption
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.ReelsModeConfig
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.ReelsModesCodec
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SceneMarkerSortOption
import de.letzgo.stashy.data.SceneSortOption
import de.letzgo.stashy.ui.feeds.PreloadWindow
import de.letzgo.stashy.ui.feeds.feedMediaSize
import de.letzgo.stashy.ui.feeds.feedShouldFill
import de.letzgo.stashy.ui.feeds.holdSpeedLabel
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReelsModesCodecTest {
    @Test fun defaultsMatchIOS() {
        val d = ReelsModesCodec.defaults()
        assertEquals(listOf("scenes", "markers", "clips", "previews", "pics"), d.map { it.type.name })
        assertTrue(d.all { it.isEnabled })
        assertEquals("dateDesc", d.last().defaultSortOption)
        assertNull(d.first().defaultSortOption)
    }

    @Test fun garbageFallsBackToDefaults() {
        val (modes, repaired) = ReelsModesCodec.decode("not json")
        assertTrue(repaired)
        assertEquals(5, modes.size)
        assertTrue(ReelsModesCodec.decode(null).second)
    }

    @Test fun roundTripKeepsIOSKeys() {
        val list = ReelsModesCodec.withDefaultSort(ReelsModesCodec.defaults(), ReelsModeType.markers, "secondsAsc")
        val json = ReelsModesCodec.encode(list)
        val first = Json.parseToJsonElement(json).jsonArray[0].jsonObject
        assertEquals(setOf("id", "type", "isEnabled", "sortOrder"), first.keys - "defaultSortOption")
        val (decoded, repaired) = ReelsModesCodec.decode(json)
        assertFalse(repaired)
        assertEquals(list, decoded)
        assertEquals("secondsAsc", decoded.first { it.type == ReelsModeType.markers }.defaultSortOption)
    }

    @Test fun decodesSwiftJSONAndAppendsMissingModes() {
        // What Swift's JSONEncoder writes for an older build without Pics.
        val swift = """[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","type":"markers","isEnabled":false,"sortOrder":1},
            {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FE","type":"scenes","isEnabled":true,"sortOrder":0,"defaultSortOption":"dateDesc"},
            {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FD","type":"clips","isEnabled":true,"sortOrder":2},
            {"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FC","type":"previews","isEnabled":true,"sortOrder":3}]"""
        val (modes, repaired) = ReelsModesCodec.decode(swift)
        assertTrue(repaired)
        assertEquals(listOf(ReelsModeType.scenes, ReelsModeType.markers, ReelsModeType.clips, ReelsModeType.previews, ReelsModeType.pics), modes.map { it.type })
        assertEquals(listOf(0, 1, 2, 3, 4), modes.map { it.sortOrder })
        assertEquals("dateDesc", modes.last().defaultSortOption)
        assertEquals(listOf(ReelsModeType.scenes, ReelsModeType.clips, ReelsModeType.previews, ReelsModeType.pics), ReelsModesCodec.enabled(modes))
    }

    @Test fun lastEnabledModeCannotBeDisabled() {
        var modes = ReelsModesCodec.defaults()
        listOf(ReelsModeType.scenes, ReelsModeType.markers, ReelsModeType.clips, ReelsModeType.previews).forEach { modes = ReelsModesCodec.toggle(modes, it) }
        assertEquals(listOf(ReelsModeType.pics), ReelsModesCodec.enabled(modes))
        modes = ReelsModesCodec.toggle(modes, ReelsModeType.pics)
        assertEquals(listOf(ReelsModeType.pics), ReelsModesCodec.enabled(modes))
    }

    @Test fun moveRenumbers() {
        val moved = ReelsModesCodec.move(ReelsModesCodec.defaults(), 4, 0)
        assertEquals(ReelsModeType.pics, moved.first().type)
        assertEquals(listOf(0, 1, 2, 3, 4), moved.map { it.sortOrder })
    }

    @Test fun modeRawMatchesIOSReelsMode() {
        assertEquals(ReelsModeType.pics, ReelsModeType.fromModeRaw("Pics"))
        assertEquals(ReelsModeType.markers, ReelsModeType.fromModeRaw("Markers"))
        assertNull(ReelsModeType.fromModeRaw("nope"))
    }

    @Test fun configDefaultsUseUppercaseIds() {
        val c = ReelsModeConfig(type = ReelsModeType.scenes)
        assertEquals(c.id.uppercase(), c.id)
    }
}

class FeedsQueryTest {
    private val sanitizeIdentity: (JsonObject, Boolean) -> JsonObject = { o, _ -> o }

    @Test fun randomSortUsesSeed() {
        val v = FeedsQuery.variables(FeedQueryKind.Scenes, 2, 20, SceneSortOption.random, 4242, null, sanitize = sanitizeIdentity)
        val f = v["filter"]!!.jsonObject
        assertEquals("random_4242", f["sort"]!!.jsonPrimitive.content)
        assertEquals("DESC", f["direction"]!!.jsonPrimitive.content)
        assertEquals(2, f["page"]!!.jsonPrimitive.content.toInt())
        assertNull(v["scene_filter"])
    }

    @Test fun plainSortAndDirection() {
        val v = FeedsQuery.variables(FeedQueryKind.Markers, 1, 20, SceneMarkerSortOption.secondsAsc, 1, null)
        assertEquals("seconds", v["filter"]!!.jsonObject["sort"]!!.jsonPrimitive.content)
        assertEquals("ASC", v["filter"]!!.jsonObject["direction"]!!.jsonPrimitive.content)
    }

    @Test fun savedFilterUIFormatIsSanitized() {
        val obj = Json.parseToJsonElement(
            """{"tags":{"value":{"items":[{"id":"7","label":"A"},{"id":"9","label":"B"}],"excluded":[],"depth":-1},"modifier":"INCLUDES_ALL"},
               "rating100":{"value":{"value":"60"},"modifier":"GREATER_THAN"},
               "organized":{"value":"true","modifier":"EQUALS"},
               "performers":{"value":{"items":[],"excluded":[]},"modifier":"INCLUDES"}}""",
        ).jsonObject
        val v = FeedsQuery.variables(FeedQueryKind.Scenes, 1, 20, SceneSortOption.dateDesc, 1, SavedFilter("1", "F", "SCENES", objectFilter = obj))
        val sf = v["scene_filter"]!!.jsonObject
        assertEquals(listOf("7", "9"), sf["tags"]!!.jsonObject["value"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertEquals(-1, sf["tags"]!!.jsonObject["depth"]!!.jsonPrimitive.content.toInt())
        assertEquals("INCLUDES_ALL", sf["tags"]!!.jsonObject["modifier"]!!.jsonPrimitive.content)
        assertEquals(60, sf["rating100"]!!.jsonObject["value"]!!.jsonPrimitive.content.toInt())
        assertEquals(true, sf["organized"]!!.jsonPrimitive.content.toBoolean())
        // Empty "Any" multi criterion is omitted.
        assertNull(sf["performers"])
    }

    @Test fun criteriaOverrideFilterKeys() {
        val obj = JsonObject(mapOf("tags" to JsonObject(mapOf("modifier" to JsonPrimitive("EXCLUDES"), "value" to JsonArray(listOf(JsonPrimitive("1")))))))
        val c = FeedCriteria(IdName("p1", "Ann"), listOf(IdName("t2", "x")), IdName("s3", "Studio"))
        val v = FeedsQuery.variables(FeedQueryKind.Scenes, 1, 20, SceneSortOption.dateDesc, 1, SavedFilter("1", objectFilter = obj), criteria = c)
        val sf = v["scene_filter"]!!.jsonObject
        assertEquals("INCLUDES", sf["tags"]!!.jsonObject["modifier"]!!.jsonPrimitive.content)
        assertEquals("t2", sf["tags"]!!.jsonObject["value"]!!.jsonArray[0].jsonPrimitive.content)
        assertEquals("p1", sf["performers"]!!.jsonObject["value"]!!.jsonArray[0].jsonPrimitive.content)
        // MultiCriterionInput (performers) carries no depth.
        assertNull(sf["performers"]!!.jsonObject["depth"])
        assertEquals("s3", sf["studios"]!!.jsonObject["value"]!!.jsonArray[0].jsonPrimitive.content)
    }

    @Test fun markerStudioGoesUnderSceneFilter() {
        val v = FeedsQuery.variables(FeedQueryKind.Markers, 1, 20, SceneMarkerSortOption.random, 5, null, criteria = FeedCriteria(studio = IdName("s1")))
        val mf = v["scene_marker_filter"]!!.jsonObject
        assertNull(mf["studios"])
        assertEquals("s1", mf["scene_filter"]!!.jsonObject["studios"]!!.jsonObject["value"]!!.jsonArray[0].jsonPrimitive.content)
    }

    @Test fun clipsAlwaysCarryTheVideoRegex() {
        val obj = JsonObject(mapOf("path" to JsonObject(mapOf("value" to JsonPrimitive("x"), "modifier" to JsonPrimitive("INCLUDES")))))
        val v = FeedsQuery.variables(FeedQueryKind.Clips, 1, 20, ImageSortOption.random, 9, SavedFilter("2", objectFilter = obj))
        val f = v["image_filter"]!!.jsonObject
        assertEquals(FeedsQuery.VIDEO_REGEX, f["path"]!!.jsonObject["value"]!!.jsonPrimitive.content)
        assertEquals("MATCHES_REGEX", f["path"]!!.jsonObject["modifier"]!!.jsonPrimitive.content)
        assertEquals("random_9", v["filter"]!!.jsonObject["sort"]!!.jsonPrimitive.content)
        // Pics: plain image query without the regex.
        assertNull(FeedsQuery.variables(FeedQueryKind.Pics, 1, 20, ImageSortOption.dateDesc, 1, null)["image_filter"])
    }

    @Test fun stashyLiveFragmentAndAdvancedCriteriaLayerOnTop() {
        val ui = Json.parseToJsonElement("""{"stashy":{"liveFragment":{"organized":true},"sortRaw":"ratingDesc"}}""")
        val filter = SavedFilter("3", objectFilter = JsonObject(mapOf("organized" to JsonPrimitive(false))), uiOptions = ui)
        val live = JsonObject(mapOf("interactive" to JsonPrimitive(true)))
        val sf = FeedsQuery.variables(FeedQueryKind.Previews, 1, 20, SceneSortOption.dateDesc, 1, filter, live)["scene_filter"]!!.jsonObject
        assertEquals("true", sf["organized"]!!.jsonPrimitive.content)
        assertEquals("true", sf["interactive"]!!.jsonPrimitive.content)
        assertEquals(SceneSortOption.ratingDesc, FeedsQuery.resolvedSceneSort(filter))
    }

    @Test fun resolvedSortFromFindFilter() {
        val ff = JsonObject(mapOf("sort" to JsonPrimitive("created_at"), "direction" to JsonPrimitive("ASC")))
        assertEquals(SceneSortOption.createdAtAsc, FeedsQuery.resolvedSceneSort(SavedFilter("4", findFilter = ff)))
        assertEquals(ImageSortOption.createdAtAsc, FeedsQuery.resolvedImageSort(SavedFilter("4", findFilter = ff)))
        val rnd = JsonObject(mapOf("sort" to JsonPrimitive("random_123"), "direction" to JsonPrimitive("DESC")))
        assertEquals(SceneSortOption.random, FeedsQuery.resolvedSceneSort(SavedFilter("5", findFilter = rnd)))
    }

    @Test fun sortKindsPickDirection() {
        assertEquals(SceneSortOption.dateAsc, FeedSortKinds.option(SceneSortOption.entries, "date", true))
        assertEquals(SceneSortOption.random, FeedSortKinds.option(SceneSortOption.entries, "random", true))
        assertEquals(SceneMarkerSortOption.secondsDesc, FeedSortKinds.option(SceneMarkerSortOption.entries, "seconds", false))
        assertEquals(ImageSortOption.titleAsc, FeedSortKinds.option(ImageSortOption.entries, "title", true))
    }

    @Test fun sortRawValuesMatchIOS() {
        assertEquals("lastPlayedAtDesc", SceneSortOption.lastPlayedAtDesc.raw)
        assertEquals("Most Viewed", SceneSortOption.playCountDesc.displayName)
        assertEquals(SceneMarkerSortOption.random, SceneMarkerSortOption.from("random"))
        assertEquals("Date (Newest)", ImageSortOption.dateDesc.displayName)
    }
}

class PreloadWindowTest {
    @Test fun windowPrioritisesNextThenPrevious() {
        assertEquals(listOf(5, 6, 4), PreloadWindow.indices(5, 10, 3))
        assertEquals(listOf(0, 1, 2), PreloadWindow.indices(0, 10, 3))
        assertEquals(listOf(9, 8), PreloadWindow.indices(9, 10, 3))
        assertEquals(emptyList<Int>(), PreloadWindow.indices(-1, 10, 3))
        assertEquals(emptyList<Int>(), PreloadWindow.indices(0, 0, 3))
    }

    @Test fun windowSkipsRowsWithoutMedia() {
        assertEquals(listOf(5, 4, 7), PreloadWindow.indices(5, 10, 3) { it == 6 })
    }

    @Test fun loadMoreNearTheEnd() {
        assertFalse(PreloadWindow.shouldLoadMore(0, 4))
        assertFalse(PreloadWindow.shouldLoadMore(14, 20))
        assertTrue(PreloadWindow.shouldLoadMore(15, 20))
        assertTrue(PreloadWindow.shouldLoadMore(19, 20))
    }

    @Test fun refillAndProbeWindow() {
        assertTrue(PreloadWindow.needsRefill(16, 20))
        assertFalse(PreloadWindow.needsRefill(10, 20))
        val ids = (1..10).map { "marker-$it" }
        assertEquals(listOf("marker-3", "marker-4", "marker-5", "marker-6"), PreloadWindow.probeWindow(ids, "marker-3", emptySet()))
        assertEquals(listOf("marker-5", "marker-6"), PreloadWindow.probeWindow(ids, "marker-3", setOf("marker-3", "marker-4")))
        assertEquals(listOf("marker-1", "marker-2", "marker-3", "marker-4"), PreloadWindow.probeWindow(ids, null, emptySet()))
    }

    @Test fun successorSkipsDroppedRows() {
        val ids = listOf("a", "b", "c", "d")
        assertEquals("d", PreloadWindow.successor(ids, "b", setOf("b", "c")))
        assertEquals("a", PreloadWindow.successor(ids, "d", setOf("d")))
    }
}

class FeedLayoutTest {
    @Test fun immersiveFillFollowsOrientation() {
        assertTrue(feedShouldFill(true, devicePortrait = true, contentLandscape = false))
        assertFalse(feedShouldFill(true, devicePortrait = true, contentLandscape = true))
        assertTrue(feedShouldFill(true, devicePortrait = false, contentLandscape = true))
        assertFalse(feedShouldFill(false, devicePortrait = true, contentLandscape = false))
    }

    @Test fun mediaSizeFillCoversFitContains() {
        // 16:9 video on a 1000×2000 portrait screen.
        val (fw, fh) = feedMediaSize(1000f, 2000f, 16f / 9f, fill = false)
        assertEquals(1000f, fw, 0.01f); assertEquals(562.5f, fh, 0.01f)
        val (cw, ch) = feedMediaSize(1000f, 2000f, 9f / 16f, fill = true)
        assertEquals(1125f, cw, 0.01f); assertEquals(2000f, ch, 0.01f)
    }

    @Test fun holdSpeedLabels() {
        assertEquals("2×", holdSpeedLabel(2f))
        assertEquals("1.5×", holdSpeedLabel(1.5f))
    }
}
