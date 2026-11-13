package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LastPlayedHiddenTest {
    @Test fun jsonRoundTripAndGarbage() {
        val map = mapOf("12" to 1_700_000_000L, "7" to 1_700_000_100L)
        assertEquals(map, LastPlayedHiddenLogic.decode(LastPlayedHiddenLogic.encode(map)))
        assertTrue(LastPlayedHiddenLogic.decode(null).isEmpty())
        assertTrue(LastPlayedHiddenLogic.decode("not json").isEmpty())
        assertTrue(LastPlayedHiddenLogic.decode("[1,2]").isEmpty())
        assertEquals(mapOf("a" to 5L), LastPlayedHiddenLogic.decode("""{"a":5,"b":"x"}"""))
    }

    @Test fun capKeepsTheNewest500() {
        var map: Map<String, Long> = emptyMap()
        for (i in 1..510) map = LastPlayedHiddenLogic.hiding(map, "s$i", 1000L + i)
        assertEquals(500, map.size)
        assertFalse("s1" in map)
        assertTrue("s510" in map)
    }

    @Test fun hiddenUntilPlayedLater() {
        val hiddenAt = java.time.Instant.parse("2026-01-01T12:00:00Z").epochSecond
        val map = mapOf("1" to hiddenAt)
        assertTrue(LastPlayedHiddenLogic.isHidden(map, "1", "2026-01-01T11:00:00Z"))
        assertTrue(LastPlayedHiddenLogic.isHidden(map, "1", null))
        assertFalse(LastPlayedHiddenLogic.isHidden(map, "1", "2026-01-01T12:00:05Z"))
        assertFalse(LastPlayedHiddenLogic.isHidden(map, "2", "2020-01-01T00:00:00Z"))
    }
}
