package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WatchlistLogicTest {
    private val a = Scene(id = "a")
    private val b = Scene(id = "b")
    private val c = Scene(id = "c")
    private fun ids(list: List<Scene>) = list.map { it.id }

    @Test fun nextFollowsTheListAndStartsAtTheTopForUnlistedScenes() {
        val list = listOf(a, b, c)
        assertEquals("b", WatchlistLogic.next(list, "a")?.id)
        assertEquals("c", WatchlistLogic.next(list, "b")?.id)
        assertNull(WatchlistLogic.next(list, "c"))
        assertEquals("a", WatchlistLogic.next(list, "x")?.id)
        assertNull(WatchlistLogic.next(emptyList(), "x"))
    }

    @Test fun toggleAppendsOrRemoves() {
        assertEquals(listOf("a", "b"), ids(WatchlistLogic.toggled(listOf(a), b)))
        assertEquals(listOf("b"), ids(WatchlistLogic.toggled(listOf(a, b), Scene(id = "a", title = "newer snapshot"))))
    }

    @Test fun moveReordersAndClamps() {
        val list = listOf(a, b, c)
        assertEquals(listOf("b", "a", "c"), ids(WatchlistLogic.moved(list, 0, 1)))
        assertEquals(listOf("c", "a", "b"), ids(WatchlistLogic.moved(list, 2, 0)))
        assertEquals(listOf("b", "c", "a"), ids(WatchlistLogic.moved(list, 0, 99)))
        assertEquals(listOf("a", "b", "c"), ids(WatchlistLogic.moved(list, 5, 0)))
    }
}
