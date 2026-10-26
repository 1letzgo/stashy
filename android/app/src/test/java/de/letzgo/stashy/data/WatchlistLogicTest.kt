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

    @Test fun addAppendsANewSceneAndKeepsListedOnes() {
        assertEquals(listOf("a", "b", "c"), ids(WatchlistLogic.added(listOf(a, b), c)))
        assertEquals(listOf("a", "b"), ids(WatchlistLogic.added(listOf(a, b), Scene(id = "b", title = "snapshot"))))
        assertEquals(listOf("a"), ids(WatchlistLogic.added(emptyList(), a)))
    }

    @Test fun shiftSwapsWithNeighbour() {
        val list = listOf(a, b, c)
        assertEquals(listOf("b", "a", "c"), ids(WatchlistLogic.shifted(list, "a", 1)))
        assertEquals(listOf("a", "c", "b"), ids(WatchlistLogic.shifted(list, "c", -1)))
        assertEquals(listOf("a", "b", "c"), ids(WatchlistLogic.shifted(list, "a", -1)))
        assertEquals(listOf("a", "b", "c"), ids(WatchlistLogic.shifted(list, "x", 1)))
    }

    @Test fun moveAfterPutsSceneBehindThePlayingOne() {
        val d = Scene(id = "d")
        val list = listOf(a, b, c, d)
        assertEquals(listOf("a", "d", "b", "c"), ids(WatchlistLogic.movedAfter(list, "d", "a")))
        assertEquals(listOf("b", "c", "a", "d"), ids(WatchlistLogic.movedAfter(list, "a", "c")))
        // Playing scene not listed: to the front. The playing one itself never moves.
        assertEquals(listOf("c", "a", "b", "d"), ids(WatchlistLogic.movedAfter(list, "c", "x")))
        assertEquals(listOf("a", "b", "c", "d"), ids(WatchlistLogic.movedAfter(list, "b", "b")))
    }
}
