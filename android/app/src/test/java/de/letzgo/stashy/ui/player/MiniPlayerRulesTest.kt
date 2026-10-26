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

    @Test fun resumeStartSkipsFinishedScenes() {
        assertEquals(120.0, MiniPlayerRules.resumeStart(120.0, 600.0)!!, 0.0)
        org.junit.Assert.assertNull(MiniPlayerRules.resumeStart(580.0, 600.0))
        org.junit.Assert.assertNull(MiniPlayerRules.resumeStart(0.0, 600.0))
        org.junit.Assert.assertNull(MiniPlayerRules.resumeStart(null, 600.0))
        assertEquals(30.0, MiniPlayerRules.resumeStart(30.0, null)!!, 0.0)
    }

    @Test fun creditCarriesOverBetweenPageAndBar() {
        // Page watched 20 s of a 30 s threshold, then handed off: the bar credits after 10 s more.
        val bar = PlayCountCredit(30.0)
        bar.restore(watchedSeconds = 20.0, credited = false)
        assertFalse(bar.onTime(100.0, true, 0.0))
        // Ticks of 1 s: nine more do not reach 30 s, the tenth does.
        for (i in 1..9) assertFalse(bar.onTime(100.0 + i, true, i.toDouble()))
        assertTrue(bar.onTime(110.0, true, 10.0))
        // Handed back already credited: the page never credits it again.
        val page = PlayCountCredit(30.0)
        page.restore(watchedSeconds = bar.watchedSeconds, credited = bar.isCredited)
        assertFalse(page.onStart())
        assertFalse(page.onTime(111.0, true, 11.0))
    }

    private fun scene(id: String) = de.letzgo.stashy.data.Scene(id = id)
    private fun ids(list: List<de.letzgo.stashy.data.Scene>) = list.map { it.id }

    @Test fun nextSceneFollowsTheWatchlistOrStartsItAfterAPlayingScene() {
        val watchlist = listOf(scene("a"), scene("b"), scene("c"))
        // On the watchlist: the next entry, nothing after the last.
        assertEquals("b", MiniPlayerRules.nextScene(watchlist, "a")?.id)
        assertEquals("c", MiniPlayerRules.nextScene(watchlist, "b")?.id)
        org.junit.Assert.assertNull(MiniPlayerRules.nextScene(watchlist, "c"))
        // Started with Play (not listed): the watchlist from the top is "up next".
        assertEquals("a", MiniPlayerRules.nextScene(watchlist, "x")?.id)
        org.junit.Assert.assertNull(MiniPlayerRules.nextScene(emptyList(), "x"))
        // A lone listed scene has nothing after it.
        org.junit.Assert.assertNull(MiniPlayerRules.nextScene(listOf(scene("x")), "x"))
    }

    @Test fun notePlayingKeepsOnlyTheLastScene() {
        val queue = listOf(scene("a"))
        assertEquals(listOf("c"), ids(MiniPlayerRules.notedPlaying(queue, scene("c"))))
        assertEquals(listOf("a"), ids(MiniPlayerRules.notedPlaying(queue, scene("a"))))
        assertEquals(listOf("x"), ids(MiniPlayerRules.notedPlaying(emptyList(), scene("x"))))
    }
}
