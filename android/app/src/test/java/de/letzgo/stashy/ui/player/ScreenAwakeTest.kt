package de.letzgo.stashy.ui.player

import androidx.media3.common.Player
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAwakeTest {
    @Test fun awakeOnlyWhileIntendingToPlay() {
        assertTrue(ScreenAwakePolicy.wantsAwake(playWhenReady = true, playbackState = Player.STATE_READY, suppressed = false))
        // A buffering stall mid-playback must not let the screen dim.
        assertTrue(ScreenAwakePolicy.wantsAwake(playWhenReady = true, playbackState = Player.STATE_BUFFERING, suppressed = false))
    }

    @Test fun pausedEndedIdleOrSuppressedLetTheScreenDim() {
        assertFalse(ScreenAwakePolicy.wantsAwake(playWhenReady = false, playbackState = Player.STATE_READY, suppressed = false))
        assertFalse(ScreenAwakePolicy.wantsAwake(playWhenReady = true, playbackState = Player.STATE_ENDED, suppressed = false))
        assertFalse(ScreenAwakePolicy.wantsAwake(playWhenReady = true, playbackState = Player.STATE_IDLE, suppressed = false))
        assertFalse(ScreenAwakePolicy.wantsAwake(playWhenReady = true, playbackState = Player.STATE_READY, suppressed = true))
    }

    @Test fun registryStaysAwakeWhileAnyHolderPlays() {
        val r = ScreenAwakeRegistry()
        val a = Any(); val b = Any()
        assertFalse(r.isAwake)
        assertTrue(r.update(a, true))
        assertTrue(r.update(b, true))
        assertTrue(r.update(a, false))
        assertFalse(r.update(b, false))
    }

    @Test fun repeatedVotesAreIdempotent() {
        val r = ScreenAwakeRegistry()
        val a = Any()
        r.update(a, true); r.update(a, true)
        assertFalse(r.update(a, false))
        assertFalse(r.update(a, false))
    }

    @Test fun removingAHolderAlwaysDropsItsVote() {
        val r = ScreenAwakeRegistry()
        val a = Any(); val b = Any()
        r.update(a, true)
        assertFalse(r.remove(a))
        // Removing an unknown / already removed holder leaves others untouched.
        r.update(b, true)
        assertTrue(r.remove(a))
        assertFalse(r.remove(b))
    }
}
