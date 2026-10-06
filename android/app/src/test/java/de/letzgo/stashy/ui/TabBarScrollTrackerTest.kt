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
