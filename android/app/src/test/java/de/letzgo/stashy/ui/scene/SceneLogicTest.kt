package de.letzgo.stashy.ui.scene

import de.letzgo.stashy.data.Tag
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SceneLogicTest {
    @Test fun newerUpdatedAtPrefersLaterStamp() {
        assertEquals("2026-05-02T10:00:00Z", SceneDetailModel.newerUpdatedAt("2026-05-01T10:00:00Z", "2026-05-02T10:00:00Z"))
        // A local millisecond cache bust (newer) wins over the server's ISO stamp.
        val bust = "1893456000000" // 2030-01-01
        assertEquals(bust, SceneDetailModel.newerUpdatedAt("2026-05-01T10:00:00+02:00", bust))
        assertEquals("a", SceneDetailModel.newerUpdatedAt("a", null))
        assertEquals("b", SceneDetailModel.newerUpdatedAt(null, "b"))
        assertNull(SceneDetailModel.newerUpdatedAt(null, null))
    }

    @Test fun performerAgeAtSceneDate() {
        assertEquals(25, ageAt("1990-06-15", "2015-06-15"))
        assertEquals(24, ageAt("1990-06-15", "2015-06-14"))
        assertNull(ageAt(null, "2015-06-14"))
        assertNull(ageAt("bad", "2015-06-14"))
    }

    @Test fun tagsByFrequencyThenName() {
        val tags = listOf(Tag("1", "b", sceneCount = 3), Tag("2", "A", sceneCount = 3), Tag("3", "z", sceneCount = 9), Tag("4", "c"))
        assertEquals(listOf("3", "2", "1", "4"), sortedByFrequency(tags).map { it.id })
    }
}
