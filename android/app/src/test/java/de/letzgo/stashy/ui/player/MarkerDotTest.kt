package de.letzgo.stashy.ui.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarkerDotTest {
    @Test fun zeroWidthTrackHasNoDotsInsteadOfThrowing() {
        // QA crash: compact bar (6 dp dot) measured at 0 width while PiP closed.
        assertNull(markerDotX(0f, 0.5f, 6f))
        assertNull(markerDotX(5.9f, 0f, 6f))
    }

    @Test fun dotIsCentredOnItsTime() {
        assertEquals(46f, markerDotX(100f, 0.5f, 8f)!!, 0.001f)
    }

    @Test fun dotsAtTheEndsStayInsideTheTrack() {
        assertEquals(0f, markerDotX(100f, 0f, 8f)!!, 0.001f)
        assertEquals(92f, markerDotX(100f, 1f, 8f)!!, 0.001f)
        assertEquals(0f, markerDotX(6f, 0.7f, 6f)!!, 0.001f)
    }
}
