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

    @Test fun markerListsOpenOnTheMarkerAtOrBeforeThePlayhead() {
        val starts = listOf(10.0, 60.0, 120.0)
        assertEquals(0, TvMarkerNav.entryIndex(starts, 0.0))
        assertEquals(0, TvMarkerNav.entryIndex(starts, 10.0))
        assertEquals(1, TvMarkerNav.entryIndex(starts, 90.0))
        assertEquals(2, TvMarkerNav.entryIndex(starts, 5000.0))
        assertNull(TvMarkerNav.entryIndex(emptyList(), 1.0))
    }

    // Markers as in the station's scene: 1:00, 3:00, 5:18, 6:50, 8:00, 9:30.
    private val qaStarts = listOf(60.0, 180.0, 318.0, 410.0, 480.0, 570.0)

    private fun targets(playhead: Double, jump: TvMarkerNav.Jump? = null, nowMs: Long = 100_000) =
        TvMarkerNav.targets(qaStarts, playhead, jump, nowMs)

    @Test fun markerTargetsWithoutAJumpFollowThePlayhead() {
        // Before the first marker: no previous, next is the first.
        assertEquals(TvMarkerNav.Targets(null, 0), targets(10.0))
        // Well into 6:50 after normal playback: Previous restarts it, Next is 8:00.
        assertEquals(TvMarkerNav.Targets(3, 4), targets(440.0))
        // 2 s into 6:50 without a jump: Previous goes one back.
        assertEquals(TvMarkerNav.Targets(2, 4), targets(412.0))
        // After the last marker: no next.
        assertEquals(TvMarkerNav.Targets(5, null), targets(600.0))
    }

    @Test fun markerTargetsCountFromTheMarkerJustReachedDespiteKeyframeOvershoot() {
        // Next jumped to 6:50 (index 3); the seek landed on a keyframe 4 s late and played 1.5 s.
        val jump = TvMarkerNav.Jump(3, atMs = 100_000)
        assertEquals(TvMarkerNav.Targets(2, 4), targets(415.5, jump, nowMs = 106_000))
        // Seek still in flight: the player reports the old position (1:10) — still index 3.
        assertEquals(TvMarkerNav.Targets(2, 4), targets(70.0, jump, nowMs = 100_500))
        // Landed a keyframe early (6:47): still index 3.
        assertEquals(TvMarkerNav.Targets(2, 4), targets(407.0, jump, nowMs = 104_000))
    }

    @Test fun repeatedPreviousWalksBack() {
        var jump = TvMarkerNav.Jump(3, atMs = 0)
        var now = 0L
        var playhead = 414.0 // 6:50 + overshoot
        val visited = mutableListOf<Int>()
        repeat(3) {
            now += 1500
            val previous = TvMarkerNav.targets(qaStarts, playhead, jump, now).previous!!
            visited += previous
            jump = TvMarkerNav.Jump(previous, now)
            playhead = qaStarts[previous] + 4 // lands 4 s late
        }
        assertEquals(listOf(2, 1, 0), visited)
        // At the first marker: no previous.
        assertNull(TvMarkerNav.targets(qaStarts, playhead, jump, now + 1500).previous)
    }

    @Test fun watchingOnOrSeekingEndsTheJumpWindow() {
        val jump = TvMarkerNav.Jump(3, atMs = 0)
        // 20 s watched past 6:50: Previous restarts 6:50.
        assertEquals(TvMarkerNav.Targets(3, 4), targets(430.0, jump, nowMs = 25_000))
        // Played on into 8:00: counts from the playhead, not the old jump.
        assertEquals(TvMarkerNav.Targets(3, 5), targets(481.0, jump, nowMs = 12_000))
        // A manual seek elsewhere (far from 6:50) after the seek landed: the playhead rules.
        assertEquals(TvMarkerNav.Targets(1, 2), targets(200.0, jump, nowMs = 10_000))
    }

    @Test fun currentMarkerIsTheOneTheRailFollows() {
        fun current(playhead: Double, jump: TvMarkerNav.Jump? = null, nowMs: Long = 100_000) =
            TvMarkerNav.currentIndex(qaStarts, playhead, jump, nowMs)
        // No jump: the marker at or before the playhead; none before the first.
        assertNull(current(30.0))
        assertEquals(0, current(60.0))
        assertEquals(2, current(400.0))
        assertEquals(5, current(900.0))
        // Next pressed to 6:50, seek still in flight (old position 5:20): already 6:50.
        assertEquals(3, current(320.0, TvMarkerNav.Jump(3, atMs = 0), nowMs = 500))
        // Keyframe landed 3 s early (6:47, still inside 5:18): the jumped marker, not 5:18.
        assertEquals(3, current(407.0, TvMarkerNav.Jump(3, atMs = 0), nowMs = 5_000))
        // Played on into 8:00: playback crossed a marker, the playhead rules again.
        assertEquals(4, current(481.0, TvMarkerNav.Jump(3, atMs = 0), nowMs = 80_000))
        // Next all the way to the last marker, then Previous back to the first: current always
        // equals the jumped index, so the rail centers that card.
        var jump: TvMarkerNav.Jump? = null
        var playhead = 0.0
        var now = 100_000L
        while (true) {
            val next = TvMarkerNav.targets(qaStarts, playhead, jump, now).next ?: break
            jump = TvMarkerNav.Jump(next, now); now += 1500; playhead = qaStarts[next] + 2
            assertEquals(next, current(playhead, jump, now))
        }
        assertEquals(5, jump!!.index)
        while (true) {
            val previous = TvMarkerNav.targets(qaStarts, playhead, jump, now).previous ?: break
            jump = TvMarkerNav.Jump(previous, now); now += 1500; playhead = qaStarts[previous] + 4
            assertEquals(previous, current(playhead, jump, now))
        }
        assertEquals(0, jump!!.index)
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
        assertEquals("Saved Filter", channel.subtitle)
        assertEquals("createdAtDesc", channel.sortRaw)
        val query = channel.query()
        assertEquals(filter, query.base)
        assertEquals(obj("""{"rating100":{"value":80,"modifier":"GREATER_THAN"}}"""), query.entityFilter())
        // Feeds starts from the same filter and sort (iOS `feedStart`).
        val start = channel.feedStart
        assertEquals(filter, start.filter)
        assertNull(start.scope)
        assertEquals("createdAtDesc", start.sortRaw)
        assertEquals("Favs", start.title)
    }

    @Test fun entityChannelHandsItsCriterionToFeeds() {
        val start = TvChannel.performer("7", "Ann").feedStart
        assertEquals("channel.performers.7", start.id)
        assertNull(start.filter)
        assertEquals(obj("""{"performers":{"modifier":"INCLUDES","value":["7"]}}"""), start.scope)
        assertEquals("dateDesc", start.sortRaw)
        assertNull(TvChannel.recentlyAdded.feedStart.scope)
        assertEquals("createdAtDesc", TvChannel.recentlyAdded.feedStart.sortRaw)
    }

    @Test fun hiddenFeedsFallsBackToHome() {
        val s = TvStacks<String>(TvRootTab.fixed)
        assertEquals(TvRootTab.Home, s.validated(TvRootTab.Feeds, TvRootTab.fixed))
        assertEquals(TvRootTab.Feeds, s.validated(TvRootTab.Feeds, TvRootTab.fixed + TvRootTab.Feeds))
        assertFalse(TvRootTab.Feeds.isLibrary)
    }
}
