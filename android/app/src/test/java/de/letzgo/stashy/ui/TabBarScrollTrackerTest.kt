package de.letzgo.stashy.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TabBarScrollTrackerTest {
    private val threshold = 50f

    @Test fun smallScrollsDoNothing() {
        val t = TabBarScrollTracker()
        assertNull(t.onScroll(-20f, 0f, threshold))
        assertNull(t.onScroll(-20f, 0f, threshold))
    }

    @Test fun scrollingDownPastThresholdHides() {
        val t = TabBarScrollTracker()
        assertNull(t.onScroll(-30f, 0f, threshold))
        assertEquals(true, t.onScroll(-30f, 0f, threshold))
    }

    @Test fun scrollingUpPastThresholdShows() {
        val t = TabBarScrollTracker()
        t.onScroll(-60f, 0f, threshold)
        assertNull(t.onScroll(30f, 0f, threshold))
        assertEquals(false, t.onScroll(30f, 0f, threshold))
    }

    @Test fun directionChangeRestartsDistance() {
        val t = TabBarScrollTracker()
        assertNull(t.onScroll(-40f, 0f, threshold))
        assertNull(t.onScroll(40f, 0f, threshold))
        // Only 20 px down since the turn: still below the threshold.
        assertNull(t.onScroll(-20f, 0f, threshold))
    }

    @Test fun pullAtTopEdgeShowsImmediately() {
        val t = TabBarScrollTracker()
        t.onScroll(-60f, 0f, threshold)
        assertEquals(false, t.onScroll(0f, 5f, threshold))
    }

    @Test fun shortContentNeverHides() {
        // Content that cannot scroll consumes nothing; a drag down the list is all "available".
        val t = TabBarScrollTracker()
        assertNull(t.onScroll(0f, -80f, threshold))
        assertNull(t.onScroll(0f, -80f, threshold))
    }
}

class FeedsTabBarPolicyTest {
    @Test fun userSwipeToLaterRowHides() {
        assertEquals(true, FeedsTabBarPolicy.onPageSettled(3, 4, userSwipe = true, overlayOpen = false))
    }

    @Test fun swipeBackToEarlierRowLeavesBar() {
        assertNull(FeedsTabBarPolicy.onPageSettled(4, 3, userSwipe = true, overlayOpen = false))
    }

    @Test fun firstRowShows() {
        assertEquals(false, FeedsTabBarPolicy.onPageSettled(1, 0, userSwipe = true, overlayOpen = false))
        // Programmatic restart from the top too.
        assertEquals(false, FeedsTabBarPolicy.onPageSettled(7, 0, userSwipe = false, overlayOpen = false))
    }

    @Test fun programmaticAdvanceLeavesBar() {
        assertNull(FeedsTabBarPolicy.onPageSettled(2, 3, userSwipe = false, overlayOpen = false))
    }

    @Test fun cancelledSwipeLeavesBar() {
        assertNull(FeedsTabBarPolicy.onPageSettled(2, 2, userSwipe = true, overlayOpen = false))
    }

    @Test fun neverHidesWhileSheetOrDialogOpen() {
        assertNull(FeedsTabBarPolicy.onPageSettled(2, 3, userSwipe = true, overlayOpen = true))
    }

    @Test fun chromeComingBackShowsBar() {
        assertEquals(false, FeedsTabBarPolicy.onChromeVisibilityChanged(true))
        assertNull(FeedsTabBarPolicy.onChromeVisibilityChanged(false))
    }

    @Test fun overlayInsetFollowsBar() {
        assertEquals(100f, FeedsTabBarPolicy.overlayInset(true, 1f, 100f, 20f), 0.001f)
        assertEquals(20f, FeedsTabBarPolicy.overlayInset(true, 0f, 100f, 20f), 0.001f)
        assertEquals(60f, FeedsTabBarPolicy.overlayInset(true, 0.5f, 100f, 20f), 0.001f)
        // Chrome hidden: only the system inset, whatever the bar does.
        assertEquals(20f, FeedsTabBarPolicy.overlayInset(false, 1f, 100f, 20f), 0.001f)
    }
}
