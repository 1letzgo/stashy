package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MiniPlayerLastSessionTest {
    @Test fun keyIsPerServer() {
        assertEquals("mini_player_last_abc", MiniPlayerLastSession.key("abc"))
        assertNull(MiniPlayerLastSession.key(null))
        assertNull(MiniPlayerLastSession.key(""))
    }

    @Test fun forgetsOnlyTheMatchingScene() {
        assertTrue(MiniPlayerLastSession.forgetsFor("7", "7"))
        assertFalse(MiniPlayerLastSession.forgetsFor("3", "7"))
        assertFalse(MiniPlayerLastSession.forgetsFor(null, "7"))
    }

    @Test fun savesEveryFiveSecondsOfPositionChange() {
        assertTrue(MiniPlayerLastSession.isDueForSave(null, 0.0))
        assertFalse(MiniPlayerLastSession.isDueForSave(10.0, 14.9))
        assertTrue(MiniPlayerLastSession.isDueForSave(10.0, 15.0))
        assertTrue(MiniPlayerLastSession.isDueForSave(10.0, 2.0))
        assertFalse(MiniPlayerLastSession.isDueForSave(10.0, Double.NaN))
    }
}
