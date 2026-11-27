package de.letzgo.stashy.tv

import android.view.KeyEvent
import de.letzgo.stashy.data.ReelsModeType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TvFeedLogicTest {

    // MARK: modes

    @Test fun enabledModesKeepSettingsOrderAndDropPhoneOnlyModes() {
        val enabled = listOf(ReelsModeType.Clips, ReelsModeType.Pics, ReelsModeType.Scenes, ReelsModeType.Verticals, ReelsModeType.Markers)
        assertEquals(listOf(ReelsModeType.Clips, ReelsModeType.Scenes, ReelsModeType.Markers), TvFeedLogic.enabledModes(enabled))
    }

    @Test fun enabledModesNeverEmpty() {
        assertEquals(listOf(ReelsModeType.Scenes), TvFeedLogic.enabledModes(emptyList()))
        assertEquals(listOf(ReelsModeType.Scenes), TvFeedLogic.enabledModes(listOf(ReelsModeType.Pics)))
    }

    // MARK: seeking

    @Test fun seekRangeIsWholeFileWithoutSegment() {
        val r = TvFeedLogic.seekRange(null, null, 600.0)
        assertEquals(0.0, r.start, 0.0)
        assertEquals(599.5, r.endInclusive, 0.0)
    }

    @Test fun seekRangeStaysInsideMarkerSegment() {
        val r = TvFeedLogic.seekRange(120.0, 150.0, 600.0)
        assertEquals(120.0, TvFeedLogic.clamp(100.0, r), 0.0)
        assertEquals(149.5, TvFeedLogic.clamp(400.0, r), 0.0)
        assertEquals(130.0, TvFeedLogic.clamp(130.0, r), 0.0)
    }

    @Test fun seekRangeWithUnknownDurationIsOpenEnded() {
        val r = TvFeedLogic.seekRange(null, null, 0.0)
        assertEquals(5000.0, TvFeedLogic.clamp(5000.0, r), 0.0)
        assertEquals(0.0, TvFeedLogic.clamp(-3.0, r), 0.0)
    }

    @Test fun seekRangeNeverInverted() {
        // A segment shorter than the end margin collapses onto its start.
        val r = TvFeedLogic.seekRange(10.0, 10.2, 600.0)
        assertEquals(10.0, r.start, 0.0)
        assertEquals(10.0, r.endInclusive, 0.0)
    }

    @Test fun holdSeekSpeedRampsLikeTvOS() {
        assertEquals(20.0, TvFeedLogic.holdSeekSpeed(0.2), 0.0)
        assertEquals(60.0, TvFeedLogic.holdSeekSpeed(1.5), 0.0)
        assertEquals(60.0, TvFeedLogic.holdSeekSpeed(3.9), 0.0)
        assertEquals(180.0, TvFeedLogic.holdSeekSpeed(4.0), 0.0)
    }

    @Test fun stepLabels() {
        assertEquals("−10 s", TvFeedLogic.stepLabel(-1))
        assertEquals("+10 s", TvFeedLogic.stepLabel(1))
    }

    // MARK: paging

    @Test fun positionLabelUsesServerTotalWhenLarger() {
        assertEquals("", TvFeedLogic.positionLabel(0, 0, 0))
        assertEquals("3 / 20", TvFeedLogic.positionLabel(2, 20, 0))
        assertEquals("3 / 512", TvFeedLogic.positionLabel(2, 20, 512))
        assertEquals("3 / 20", TvFeedLogic.positionLabel(2, 20, 15))
    }

    @Test fun loadsMoreWithinFourOfTheEnd() {
        assertFalse(TvFeedLogic.needsMore(15, 20))
        assertTrue(TvFeedLogic.needsMore(16, 20))
        assertTrue(TvFeedLogic.needsMore(0, 3))
    }

    @Test fun indexAfterRemovalStaysInRange() {
        assertEquals(4, TvFeedLogic.indexAfterRemoval(4, 10))
        assertEquals(8, TvFeedLogic.indexAfterRemoval(9, 9))
        assertEquals(0, TvFeedLogic.indexAfterRemoval(0, 0))
    }

    // MARK: end of an item

    @Test fun continuousPlayMovesOnOnlyWithANextItem() {
        assertEquals(TvFeedLogic.EndAction.Next, TvFeedLogic.endAction(continuousPlay = true, canGoNext = true))
        assertEquals(TvFeedLogic.EndAction.Loop, TvFeedLogic.endAction(continuousPlay = true, canGoNext = false))
        assertEquals(TvFeedLogic.EndAction.Loop, TvFeedLogic.endAction(continuousPlay = false, canGoNext = true))
    }

    @Test fun lastItemWaitsForTheNextPageUnderContinuousPlay() {
        assertEquals(TvFeedLogic.EndAction.AwaitPage, TvFeedLogic.endAction(continuousPlay = true, canGoNext = false, morePages = true))
        // The list is complete: the last item loops (tvOS too; no wrap to the first item).
        assertEquals(TvFeedLogic.EndAction.Loop, TvFeedLogic.endAction(continuousPlay = true, canGoNext = false, morePages = false))
        assertEquals(TvFeedLogic.EndAction.Next, TvFeedLogic.endAction(continuousPlay = true, canGoNext = true, morePages = true))
        // Without continuous play a page coming changes nothing.
        assertEquals(TvFeedLogic.EndAction.Loop, TvFeedLogic.endAction(continuousPlay = false, canGoNext = false, morePages = true))
    }

    @Test fun playerLoopsOnlyForPlainRowsFromZero() {
        assertTrue(TvFeedLogic.playerLoops(hasSegment = false, start = 0.0, continuousPlay = false))
        assertFalse(TvFeedLogic.playerLoops(hasSegment = true, start = 0.0, continuousPlay = false))
        // A random / skip-30 start loops back to its start itself.
        assertFalse(TvFeedLogic.playerLoops(hasSegment = false, start = 30.0, continuousPlay = false))
        assertFalse(TvFeedLogic.playerLoops(hasSegment = false, start = 0.0, continuousPlay = true))
    }

    @Test fun segmentEndFiresJustBeforeTheEnd() {
        assertFalse(TvFeedLogic.reachedSegmentEnd(149.8, 150.0))
        assertTrue(TvFeedLogic.reachedSegmentEnd(149.85, 150.0))
        assertTrue(TvFeedLogic.reachedSegmentEnd(151.0, 150.0))
    }

    // MARK: keys

    @Test fun loadKeySeparatesChannelsFromDefaults() {
        assertEquals("random|-", TvFeedLogic.loadKey(null, null, "random", null))
        assertEquals("dateDesc|42", TvFeedLogic.loadKey(null, null, "dateDesc", "42"))
        assertEquals("channel|channel.performers.7|dateDesc", TvFeedLogic.loadKey("channel.performers.7", "dateDesc", "random", "42"))
    }

    // MARK: rating

    @Test fun ratingStarsToRating100() {
        assertEquals(listOf(5, 4, 3, 2, 1, 0), TvFeedLogic.ratingChoices)
        assertEquals(100, TvFeedLogic.rating100(5))
        assertEquals(20, TvFeedLogic.rating100(1))
        assertNull(TvFeedLogic.rating100(0))
        assertEquals(100, TvFeedLogic.rating100(9))
    }

    // MARK: remote

    @Test fun remoteKeyMap() {
        assertEquals(TvFeedLogic.Key.Previous, TvFeedLogic.key(KeyEvent.KEYCODE_DPAD_UP))
        assertEquals(TvFeedLogic.Key.Next, TvFeedLogic.key(KeyEvent.KEYCODE_DPAD_DOWN))
        assertEquals(TvFeedLogic.Key.SeekBack, TvFeedLogic.key(KeyEvent.KEYCODE_DPAD_LEFT))
        assertEquals(TvFeedLogic.Key.SeekForward, TvFeedLogic.key(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertEquals(TvFeedLogic.Key.OpenOverlay, TvFeedLogic.key(KeyEvent.KEYCODE_DPAD_CENTER))
        assertEquals(TvFeedLogic.Key.OpenOverlay, TvFeedLogic.key(KeyEvent.KEYCODE_ENTER))
        assertEquals(TvFeedLogic.Key.TogglePlay, TvFeedLogic.key(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        assertEquals(TvFeedLogic.Key.Next, TvFeedLogic.key(KeyEvent.KEYCODE_MEDIA_NEXT))
        assertEquals(TvFeedLogic.Key.Previous, TvFeedLogic.key(KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        assertEquals(TvFeedLogic.Key.SeekForward, TvFeedLogic.key(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD))
        assertEquals(TvFeedLogic.Key.SeekBack, TvFeedLogic.key(KeyEvent.KEYCODE_MEDIA_REWIND))
        assertEquals(TvFeedLogic.Key.None, TvFeedLogic.key(KeyEvent.KEYCODE_BACK))
    }

    @Test fun onlyDpadSideKeysHoldToScan() {
        assertTrue(TvFeedLogic.isHoldSeekKey(KeyEvent.KEYCODE_DPAD_LEFT))
        assertTrue(TvFeedLogic.isHoldSeekKey(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertFalse(TvFeedLogic.isHoldSeekKey(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD))
    }
}
