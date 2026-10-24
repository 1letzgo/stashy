package de.letzgo.stashy.ui.player

import de.letzgo.stashy.ui.player.MiniPlayerRules.StartDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MiniPlayerRulesTest {
    @Test fun handsOffOnlyAPlayingStartedSceneWithTheSettingOn() {
        assertTrue(MiniPlayerRules.handsOff(enabled = true, playbackStarted = true, isPlaying = true, isDeleting = false, inPictureInPicture = false))
        assertFalse(MiniPlayerRules.handsOff(enabled = false, playbackStarted = true, isPlaying = true, isDeleting = false, inPictureInPicture = false))
        assertFalse(MiniPlayerRules.handsOff(enabled = true, playbackStarted = false, isPlaying = true, isDeleting = false, inPictureInPicture = false))
        assertFalse(MiniPlayerRules.handsOff(enabled = true, playbackStarted = true, isPlaying = false, isDeleting = false, inPictureInPicture = false))
        assertFalse(MiniPlayerRules.handsOff(enabled = true, playbackStarted = true, isPlaying = true, isDeleting = true, inPictureInPicture = false))
        assertFalse(MiniPlayerRules.handsOff(enabled = true, playbackStarted = true, isPlaying = true, isDeleting = false, inPictureInPicture = true))
    }

    @Test fun pageStartTakesBackItsOwnSceneAndClosesOthers() {
        assertEquals(StartDecision.TakeBack, MiniPlayerRules.onPageStart("7", "7", pageHasPlayer = false))
        assertEquals(StartDecision.CloseOther, MiniPlayerRules.onPageStart("3", "7", pageHasPlayer = false))
        assertEquals(StartDecision.Nothing, MiniPlayerRules.onPageStart(null, "7", pageHasPlayer = false))
        // A page that already runs its own player leaves the bar alone.
        assertEquals(StartDecision.Nothing, MiniPlayerRules.onPageStart("7", "7", pageHasPlayer = true))
        assertEquals(StartDecision.Nothing, MiniPlayerRules.onPageStart("3", "7", pageHasPlayer = true))
    }

    @Test fun dragClosesBeyondThresholds() {
        assertTrue(MiniPlayerRules.closesOnDrag(0f, 41f))
        assertFalse(MiniPlayerRules.closesOnDrag(0f, 40f))
        assertFalse(MiniPlayerRules.closesOnDrag(0f, -200f))
        assertTrue(MiniPlayerRules.closesOnDrag(-121f, 0f))
        assertTrue(MiniPlayerRules.closesOnDrag(121f, 10f))
        assertFalse(MiniPlayerRules.closesOnDrag(120f, 20f))
    }

    @Test fun progressAndSubtitle() {
        assertEquals(0.5f, MiniPlayerRules.progress(30.0, 60.0), 1e-6f)
        assertEquals(0f, MiniPlayerRules.progress(30.0, 0.0), 0f)
        assertEquals(1f, MiniPlayerRules.progress(90.0, 60.0), 0f)
        assertEquals("A, B", MiniPlayerRules.subtitle(listOf("A", " ", "B", "C"), "Studio"))
        assertEquals("Studio", MiniPlayerRules.subtitle(emptyList(), "Studio"))
        assertEquals("", MiniPlayerRules.subtitle(emptyList(), null))
    }
}
