package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class SceneEventsTest {
    private val a = Scene(id = "1", title = "A", resumeTime = 10.0, playCount = 2, oCounter = 1, rating100 = 40, updatedAt = "2026-05-01T10:00:00Z")
    private val b = Scene(id = "2", title = "B")

    @Test fun patchesOnlyTheMatchingScene() {
        assertSame(b, SceneEvent.PlayAdded("1").applyTo(b))
        assertEquals(3, SceneEvent.PlayAdded("1").applyTo(a)?.playCount)
        assertEquals(42.5, SceneEvent.ResumeTimeUpdated("1", 42.5).applyTo(a)?.resumeTime)
        assertEquals(5, SceneEvent.OCounterUpdated("1", 5).applyTo(a)?.oCounter)
        assertEquals("123456789012", SceneEvent.CoverUpdated("1", "123456789012").applyTo(a)?.updatedAt)
        assertNull(SceneEvent.Deleted("1").applyTo(a))
    }

    @Test fun mergeKeepsListCountersLikeIos() {
        val edited = Scene(id = "1", title = "New", playCount = 0, oCounter = 0, resumeTime = 0.0, rating100 = 80, updatedAt = "2026-04-01T10:00:00Z")
        val merged = SceneEvent.Updated(edited).applyTo(a)!!
        assertEquals("New", merged.title)
        assertEquals(80, merged.rating100)
        assertEquals(2, merged.playCount) // list keeps its own counters
        assertEquals(10.0, merged.resumeTime)
        assertEquals("2026-05-01T10:00:00Z", merged.updatedAt) // newer stamp wins
    }

    @Test fun listApplyingRemovesAndReportsNoChange() {
        val list = listOf(a, b)
        assertEquals(listOf(b), list.applying(SceneEvent.Deleted("1")))
        assertNull(list.applying(SceneEvent.Deleted("9")))
        assertNull(list.applying(SceneEvent.OCounterUpdated("1", 1))) // unchanged
    }
}
