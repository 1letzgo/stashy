package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.ReelsModeType
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `reelsUpdateChromeAutoHide` gates ([FeedsChromeAutoHide]). */
class FeedsChromeAutoHideTest {

    @Test
    fun dragHidesInVideoModes() {
        for (mode in ReelsModeType.entries.filter { it != ReelsModeType.Pics }) {
            assertTrue(mode.name, FeedsChromeAutoHide.hidesOnDrag(mode, overlayOpen = false, zoomed = false))
        }
    }

    @Test
    fun picsNeverHides() {
        assertFalse(FeedsChromeAutoHide.hidesOnDrag(ReelsModeType.Pics, overlayOpen = false, zoomed = false))
    }

    @Test
    fun sheetOrZoomKeepsChrome() {
        assertFalse(FeedsChromeAutoHide.hidesOnDrag(ReelsModeType.Scenes, overlayOpen = true, zoomed = false))
        assertFalse(FeedsChromeAutoHide.hidesOnDrag(ReelsModeType.Scenes, overlayOpen = false, zoomed = true))
    }

    @Test
    fun tapRevealsOnlyHiddenChrome() {
        assertTrue(FeedsChromeAutoHide.tapReveals(scrollHidden = true))
        assertFalse(FeedsChromeAutoHide.tapReveals(scrollHidden = false))
    }
}
