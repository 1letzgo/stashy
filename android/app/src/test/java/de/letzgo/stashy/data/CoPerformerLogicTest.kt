package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoPerformerLogicTest {

    @Test fun countsSharedScenesExcludingSelf() {
        val scenes = listOf(
            listOf("me", "a", "b"),
            listOf("me", "a"),
            listOf("a", "me", "c"),
            listOf("me"),
        )
        assertEquals(mapOf("a" to 3, "b" to 1, "c" to 1), CoPerformerLogic.count(scenes, "me"))
    }

    @Test fun duplicateIdInOneSceneCountsOnce() {
        assertEquals(mapOf("a" to 1), CoPerformerLogic.count(listOf(listOf("me", "a", "a")), "me"))
    }

    @Test fun noScenesOrSoloScenesGiveNothing() {
        assertTrue(CoPerformerLogic.count(emptyList(), "me").isEmpty())
        assertTrue(CoPerformerLogic.count(listOf(listOf("me"), emptyList()), "me").isEmpty())
    }

    @Test fun sortsByCountDescThenName() {
        val performers = listOf(
            Performer("1", "zoe"), Performer("2", "Anna"), Performer("3", "bella"), Performer("4", "Carl"),
        )
        val counts = mapOf("1" to 5, "2" to 2, "3" to 2, "4" to 7)
        val result = CoPerformerLogic.sorted(performers, counts)
        assertEquals(listOf("Carl", "zoe", "Anna", "bella"), result.map { it.performer.name })
        assertEquals(listOf(7, 5, 2, 2), result.map { it.sharedScenes })
    }

    @Test fun dropsPerformersWithoutCountAndDuplicates() {
        val performers = listOf(Performer("1", "A"), Performer("1", "A"), Performer("2", "B"))
        val result = CoPerformerLogic.sorted(performers, mapOf("1" to 1))
        assertEquals(listOf(CoPerformer(Performer("1", "A"), 1)), result)
    }
}
