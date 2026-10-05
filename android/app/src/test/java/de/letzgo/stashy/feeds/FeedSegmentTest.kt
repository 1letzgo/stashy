package de.letzgo.stashy.feeds

import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneFile
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.ui.feeds.FeedItem
import de.letzgo.stashy.ui.feeds.FeedSegment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FeedSegmentTest {
    @Test fun usesEndSecondsWhenAfterStart() {
        assertEquals(FeedSegment(120.0, 150.5), FeedSegment.forMarker(120.0, 150.5))
        assertEquals(30.5, FeedSegment.forMarker(120.0, 150.5).length, 1e-9)
    }

    @Test fun defaultsToThirtySecondsWithoutEnd() {
        assertEquals(FeedSegment(42.0, 72.0), FeedSegment.forMarker(42.0, null))
    }

    @Test fun ignoresEndNotAfterStart() {
        assertEquals(FeedSegment(42.0, 72.0), FeedSegment.forMarker(42.0, 42.0))
        assertEquals(FeedSegment(42.0, 72.0), FeedSegment.forMarker(42.0, 10.0))
    }

    @Test fun negativeStartClampsToZero() {
        assertEquals(FeedSegment(0.0, 30.0), FeedSegment.forMarker(-3.0, null))
    }

    @Test fun sceneDurationCapsTheEnd() {
        assertEquals(FeedSegment(100.0, 110.0), FeedSegment.forMarker(100.0, null, sceneDuration = 110.0))
        assertEquals(FeedSegment(100.0, 110.0), FeedSegment.forMarker(100.0, 200.0, sceneDuration = 110.0))
        // Within the duration: untouched.
        assertEquals(FeedSegment(100.0, 130.0), FeedSegment.forMarker(100.0, null, sceneDuration = 600.0))
    }

    @Test fun unknownOrBogusDurationDoesNotCap() {
        assertEquals(FeedSegment(100.0, 130.0), FeedSegment.forMarker(100.0, null, sceneDuration = 0.0))
        // Marker past the known end (bad data): keep the default window rather than an empty one.
        assertEquals(FeedSegment(100.0, 130.0), FeedSegment.forMarker(100.0, null, sceneDuration = 90.0))
    }

    @Test fun sceneTimeMapsAndClamps() {
        val s = FeedSegment(100.0, 130.0)
        assertEquals(100.0, s.sceneTime(0.0), 1e-9)
        assertEquals(112.5, s.sceneTime(12.5), 1e-9)
        assertEquals(130.0, s.sceneTime(99.0), 1e-9)
        assertEquals(100.0, s.sceneTime(-1.0), 1e-9)
    }

    @Test fun markerItemSegmentUsesSceneDuration() {
        val scene = Scene(id = "s1", files = listOf(SceneFile(duration = 115.0)))
        val item = FeedItem.MarkerItem(SceneMarker(id = "m1", seconds = 100.0, scene = scene))
        assertEquals(FeedSegment(100.0, 115.0), item.segment)
        assertEquals(15.0, item.duration!!, 1e-9)
    }

    @Test fun onlyMarkersWithSceneHaveSegment() {
        assertNull(FeedItem.MarkerItem(SceneMarker(id = "m1", seconds = 5.0)).segment)
        assertNull(FeedItem.SceneItem(Scene(id = "s1")).segment)
    }
}
