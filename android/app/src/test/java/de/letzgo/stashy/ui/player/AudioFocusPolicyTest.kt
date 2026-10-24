package de.letzgo.stashy.ui.player

import de.letzgo.stashy.ui.player.AudioFocusPolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioFocusPolicyTest {
    @Test fun wantsFocusOnlyWhenAudiblePlayback() {
        assertTrue(AudioFocusPolicy.wantsFocus(allowed = true, playWhenReady = true, volume = 1f))
        assertFalse(AudioFocusPolicy.wantsFocus(allowed = true, playWhenReady = true, volume = 0f))
        assertFalse(AudioFocusPolicy.wantsFocus(allowed = true, playWhenReady = false, volume = 1f))
        assertFalse(AudioFocusPolicy.wantsFocus(allowed = false, playWhenReady = true, volume = 1f))
    }

    @Test fun mutedPlaybackNeverAcquires() {
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = true, volume = 0f))
    }

    @Test fun previewNeverAcquiresEvenWhenAudible() {
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = false, allowed = false, playWhenReady = true, volume = 1f))
    }

    @Test fun audiblePlaybackAcquiresOnce() {
        assertEquals(Action.Acquire, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = true, volume = 1f))
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = true, volume = 1f))
    }

    @Test fun unmuteMidPlaybackAcquires() {
        assertEquals(Action.Acquire, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = true, volume = 0.5f))
    }

    @Test fun muteReleasesImmediately() {
        assertEquals(Action.Release, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = true, volume = 0f))
    }

    @Test fun pauseReleasesAfterGrace() {
        assertEquals(Action.ReleaseLater, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = false, volume = 1f))
    }

    @Test fun mutedPauseReleasesImmediately() {
        assertEquals(Action.Release, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = false, volume = 0f))
    }

    @Test fun disallowReleasesImmediately() {
        assertEquals(Action.Release, AudioFocusPolicy.next(holding = true, allowed = false, playWhenReady = true, volume = 1f))
    }

    @Test fun idlePlayerReleasesAndNeverAcquires() {
        assertEquals(Action.Release, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = true, volume = 1f, idle = true))
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = true, volume = 1f, idle = true))
    }

    @Test fun notHoldingPausedStaysQuiet() {
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = false, volume = 1f))
    }

    @Test fun endedPlaybackReleasesAfterGraceAndNeverAcquires() {
        assertEquals(Action.ReleaseLater, AudioFocusPolicy.next(holding = true, allowed = true, playWhenReady = true, volume = 1f, ended = true))
        assertEquals(Action.Keep, AudioFocusPolicy.next(holding = false, allowed = true, playWhenReady = true, volume = 1f, ended = true))
    }
}
