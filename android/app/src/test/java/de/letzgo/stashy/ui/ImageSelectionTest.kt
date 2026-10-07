package de.letzgo.stashy.ui

import de.letzgo.stashy.data.ImageDeletion
import de.letzgo.stashy.ui.catalog.ImageDeleteOutcome
import de.letzgo.stashy.ui.catalog.ImageSelection
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageSelectionTest {
    @Test fun beginStartsEmptyAndEndClears() {
        val s = ImageSelection().begin().toggle("1").toggle("2")
        assertTrue(s.isActive)
        assertEquals(setOf("1", "2"), s.selectedIds)
        assertEquals(ImageSelection(), s.end())
        assertEquals(0, s.end().begin().count)
    }

    @Test fun toggleAddsAndRemoves() {
        val s = ImageSelection().begin().toggle("a").toggle("b").toggle("a")
        assertEquals(setOf("b"), s.selectedIds)
        assertTrue(s.isSelected("b"))
        assertFalse(s.isSelected("a"))
    }

    @Test fun nothingChangesOutsideSelectionMode() {
        val idle = ImageSelection()
        assertEquals(idle, idle.toggle("1"))
        assertEquals(idle, idle.selectAll(listOf("1", "2")))
    }

    @Test fun selectAllTakesEveryLoadedImageOnce() {
        val s = ImageSelection().begin().toggle("x").selectAll(listOf("1", "2", "2", "3"))
        assertEquals(setOf("1", "2", "3"), s.selectedIds)
        assertEquals(3, s.count)
    }

    @Test fun afterDeleteEndsModeOnFullSuccessAndKeepsFailuresSelected() {
        val s = ImageSelection().begin().selectAll(listOf("1", "2", "3"))
        assertEquals(ImageSelection(), s.afterDelete(emptySet()))
        val partial = s.afterDelete(setOf("2"))
        assertTrue(partial.isActive)
        assertEquals(setOf("2"), partial.selectedIds)
    }

    @Test fun outcomeMessagesMatchIos() {
        assertEquals("1 image deleted", ImageDeleteOutcome(1, emptySet()).message)
        assertEquals("3 images deleted", ImageDeleteOutcome(3, emptySet()).message)
        assertEquals("2 of 3 deleted — 1 failed", ImageDeleteOutcome(3, setOf("x")).message)
        assertEquals("Delete 4 images?", ImageDeleteOutcome.confirmTitle(4))
    }

    @Test fun deleteAllReportsFailuresAndExceptions() = runBlocking {
        val calls = mutableListOf<String>()
        val failed = ImageDeletion.deleteAll(listOf("1", "2", "3", "4", "1"), parallelism = 2) { id ->
            synchronized(calls) { calls += id }
            when (id) {
                "2" -> false
                "4" -> throw IllegalStateException("boom")
                else -> true
            }
        }
        assertEquals(setOf("2", "4"), failed)
        assertEquals(listOf("1", "2", "3", "4"), calls.sorted())
    }
}
