package de.letzgo.stashy.tv

import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.VisualFile
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TvLogicTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    // MARK: grid

    @Test fun gridSpecMatchesTvOSAtFullWidth() {
        // 1920 pt without sidebar → 4 scene columns, 5 image columns (tvOS fixed values).
        assertEquals(4, TvGridSpec(410f, 40f, 4, 2).columnCount(1760f))
        assertEquals(5, TvGridSpec(300f, 30f, 5, 3).columnCount(1760f))
    }

    @Test fun gridSpecShrinksWithWidthButKeepsMinimum() {
        val spec = TvGridSpec(410f, 40f, 4, 2)
        assertEquals(3, spec.columnCount(1400f))
        assertEquals(2, spec.columnCount(300f))
        // n columns only need n-1 gaps: 2×410 + 40 fits exactly.
        assertEquals(2, spec.columnCount(860f))
    }

    // MARK: seeking

    @Test fun seekAcceleratesOnQuickPresses() {
        val acc = TvSeekAccelerator()
        assertEquals(10.0, acc.step(0), 0.0)
        assertEquals(10.0, acc.step(100), 0.0)
        assertFalse(acc.wantsScrub)
        assertEquals(30.0, acc.step(200), 0.0)
        assertTrue(acc.wantsScrub)
        acc.step(300); acc.step(400)
        assertEquals(60.0, acc.step(500), 0.0)
        // A pause longer than 0.5 s starts over.
        assertEquals(10.0, acc.step(2000), 0.0)
        assertFalse(acc.wantsScrub)
    }

    @Test fun holdTrackerTellsTapFromHold() {
        val t = TvHoldTracker(700)
        assertEquals(TvHoldTracker.Result.None, t.keyDown(0, 0))
        assertEquals(TvHoldTracker.Result.Tap, t.keyUp(200))

        assertEquals(TvHoldTracker.Result.None, t.keyDown(1000, 0))
        assertEquals(TvHoldTracker.Result.None, t.keyDown(1400, 1))
        assertEquals(TvHoldTracker.Result.Hold, t.keyDown(1750, 2))
        assertEquals(TvHoldTracker.Result.None, t.keyDown(1800, 3))
        // The release of a hold is not a tap.
        assertEquals(TvHoldTracker.Result.None, t.keyUp(1900))
        assertFalse(t.isPressing)
    }

    @Test fun holdTrackerReleaseAfterThresholdWithoutRepeatsIsHold() {
        val t = TvHoldTracker(700)
        t.keyDown(0, 0)
        assertEquals(TvHoldTracker.Result.Hold, t.keyUp(800))
    }

    // MARK: formatting

    @Test fun timeLabels() {
        assertEquals("0:05", TvFormat.time(5.4))
        assertEquals("12:34", TvFormat.time(754.0))
        assertEquals("1:02:03", TvFormat.time(3723.0))
        assertEquals("--:--", TvFormat.time(null))
        assertEquals("--:--", TvFormat.time(Double.NaN))
        assertEquals("--:--", TvFormat.time(-1.0))
    }

    @Test fun resolutionAndRating() {
        assertEquals("4K", TvFormat.resolution(2160))
        assertEquals("HD", TvFormat.resolution(1080))
        assertEquals("720p", TvFormat.resolution(720))
        assertEquals("SD", TvFormat.resolution(480))
        assertNull(TvFormat.resolution(null))
        assertEquals("Rate", TvFormat.ratingLabel(null))
        assertEquals("Rate", TvFormat.ratingLabel(0))
        assertEquals("3/5", TvFormat.ratingLabel(60))
        assertEquals(5, TvFormat.stars(95))
        assertEquals("4.5", TvFormat.ratingValue(90))
    }

    @Test fun progressOnlyForValidResume() {
        assertEquals(0.5f, TvFormat.progress(50.0, 100.0)!!, 0.0001f)
        assertEquals(1f, TvFormat.progress(150.0, 100.0)!!, 0.0001f)
        assertNull(TvFormat.progress(0.0, 100.0))
        assertNull(TvFormat.progress(10.0, null))
    }

    @Test fun activeMarkerOwnsRangeUntilNextMarker() {
        val starts = listOf(10.0, 60.0, 120.0)
        assertNull(activeMarkerIndex(starts, 5.0))
        assertEquals(0, activeMarkerIndex(starts, 10.0))
        assertEquals(0, activeMarkerIndex(starts, 59.9))
        assertEquals(1, activeMarkerIndex(starts, 60.0))
        assertEquals(2, activeMarkerIndex(starts, 5000.0))
        assertNull(activeMarkerIndex(emptyList(), 1.0))
    }

    // MARK: sorting

    @Test fun everyTvSortOptionExistsInTheSharedCatalog() {
        for (mode in listOf(FilterMode.Scenes, FilterMode.Performers, FilterMode.Studios, FilterMode.Tags, FilterMode.Groups, FilterMode.Galleries, FilterMode.Images)) {
            for ((raw, _) in TvSortLabels.options(mode)) {
                assertTrue("$mode $raw", SortCatalog.option(mode, raw) != null)
            }
            assertTrue(SortCatalog.option(mode, TvSortLabels.defaultRaw(mode)) != null)
        }
        assertEquals("Recently Released", TvSortLabels.label(FilterMode.Scenes, "dateDesc"))
        assertEquals("Most Scenes", TvSortLabels.label(FilterMode.Performers, "sceneCountDesc"))
    }

    // MARK: navigation

    @Test fun stacksPerTabAndReselectPopsToRoot() {
        val s = TvStacks<String>(TvRootTab.fixed)
        s.push(TvRootTab.Scenes, "a"); s.push(TvRootTab.Scenes, "b")
        s.push(TvRootTab.Home, "x")
        assertEquals("b", s.top(TvRootTab.Scenes))
        assertEquals("b", s.pop(TvRootTab.Scenes))
        assertEquals(listOf("a"), s.stack(TvRootTab.Scenes))
        // Re-selecting the active entry pops to its root.
        assertEquals(TvRootTab.Scenes, s.select(TvRootTab.Scenes, TvRootTab.Scenes))
        assertTrue(s.stack(TvRootTab.Scenes).isEmpty())
        // Other tabs keep their pages.
        assertEquals(listOf("x"), s.stack(TvRootTab.Home))
        assertNull(s.pop(TvRootTab.Scenes))
    }

    @Test fun leavingSettingsDropsItsPages() {
        val s = TvStacks<String>(TvRootTab.fixed)
        s.push(TvRootTab.Settings, "servers")
        s.push(TvRootTab.Performers, "p")
        assertEquals(TvRootTab.Home, s.select(TvRootTab.Settings, TvRootTab.Home))
        assertTrue(s.stack(TvRootTab.Settings).isEmpty())
        assertEquals(TvRootTab.Settings, s.select(TvRootTab.Performers, TvRootTab.Settings))
        assertEquals(listOf("p"), s.stack(TvRootTab.Performers))
    }

    @Test fun hiddenActiveSectionFallsBackToHome() {
        val s = TvStacks<String>(TvRootTab.fixed)
        assertEquals(TvRootTab.Home, s.validated(TvRootTab.Tags, TvRootTab.fixed + TvRootTab.Scenes))
        assertEquals(TvRootTab.Scenes, s.validated(TvRootTab.Scenes, TvRootTab.fixed + TvRootTab.Scenes))
        assertEquals(TvRootTab.Settings, s.validated(TvRootTab.Settings, emptySet()))
    }

    // MARK: security

    @Test fun pinHashIsSaltedSha256Hex() {
        assertEquals("0b8db413734a3ea5f35a7ac7c2015367c7d78ff986b981c86c3e40aa1b7870ef", TvPinHash.hash("1234", "SALT-1"))
    }

    // MARK: images

    @Test fun gifAndPerformerPill() {
        val gif = StashImage("1", visualFiles = listOf(VisualFile(basename = "clip.GIF")))
        val still = StashImage("2", paths = ImagePaths(image = "https://h/image/2/image?t=1"), performers = listOf(IdName("p1", "Ann"), IdName("p2", "Bo"), IdName("p3", "Cy")))
        val video = StashImage("3", visualFiles = listOf(VisualFile(typename = "VideoFile", basename = "v.mp4")))
        assertTrue(gif.isGifFile)
        assertFalse(still.isGifFile)
        assertEquals("Ann +2", still.performerPillText)
        assertNull(gif.performerPillText)
        assertEquals(listOf("2"), listOf(gif, still, video).tvStillImages().map { it.id })
        assertEquals("clip.GIF", gif.tvDisplayTitle)
    }

    // MARK: channels

    @Test fun channelIdsSortsAndScopes() {
        assertEquals("channel.recentlyReleased", TvChannel.recentlyReleased.id)
        assertEquals("dateDesc", TvChannel.recentlyReleased.sortRaw)
        assertEquals("createdAtDesc", TvChannel.recentlyAdded.sortRaw)
        assertNull(TvChannel.recentlyAdded.scopeFilter())

        val performer = TvChannel.performer("7", "Ann")
        assertEquals("channel.performers.7", performer.id)
        assertEquals("Performer", performer.subtitle)
        // `performers` is a plain MultiCriterionInput: no depth.
        assertEquals(obj("""{"performers":{"modifier":"INCLUDES","value":["7"]}}"""), performer.scopeFilter())
        // Hierarchical criteria carry depth 0.
        assertEquals(obj("""{"tags":{"modifier":"INCLUDES","value":["3"],"depth":0}}"""), TvChannel.tag("3", "T").scopeFilter())
        assertEquals(obj("""{"studios":{"modifier":"INCLUDES","value":["4"],"depth":0}}"""), TvChannel.studio("4", "S").query().entityFilter())
    }

    @Test fun savedFilterChannelUsesTheFilterAndItsSort() {
        val filter = SavedFilter(
            id = "f1", name = "Favs", mode = "SCENES",
            findFilter = obj("""{"sort":"created_at","direction":"DESC"}"""),
            objectFilter = obj("""{"rating100":{"value":80,"modifier":"GREATER_THAN"}}"""),
        )
        val channel = TvChannel.savedFilter(filter)
        assertEquals("channel.filter.f1", channel.id)
        assertEquals("Saved filter", channel.subtitle)
        assertEquals("createdAtDesc", channel.sortRaw)
        val query = channel.query()
        assertEquals(filter, query.base)
        assertEquals(obj("""{"rating100":{"value":80,"modifier":"GREATER_THAN"}}"""), query.entityFilter())
    }
}
