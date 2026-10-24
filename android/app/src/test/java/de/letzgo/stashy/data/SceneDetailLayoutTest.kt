package de.letzgo.stashy.data

import de.letzgo.stashy.data.SceneDetailCard.Details
import de.letzgo.stashy.data.SceneDetailCard.Galleries
import de.letzgo.stashy.data.SceneDetailCard.Groups
import de.letzgo.stashy.data.SceneDetailCard.Heatmap
import de.letzgo.stashy.data.SceneDetailCard.PerformersStudio
import de.letzgo.stashy.data.SceneDetailCard.SimilarScenes
import de.letzgo.stashy.data.SceneDetailCard.Tags
import org.junit.Assert.assertEquals
import org.junit.Test

class SceneDetailLayoutTest {
    @Test fun emptyPrefsGiveDefaultOrder() {
        assertEquals(SceneDetailCard.entries, SceneDetailLayoutLogic.resolveOrder(SceneDetailLayoutLogic.parse(null)))
        assertEquals(SceneDetailCard.entries, SceneDetailLayoutLogic.resolveOrder(SceneDetailLayoutLogic.parse(" , ")))
    }

    @Test fun storedOrderWinsAndMissingCardsAreAppendedInDefaultOrder() {
        val order = SceneDetailLayoutLogic.resolveOrder(SceneDetailLayoutLogic.parse("tags,bogus,details,tags,galleries"))
        assertEquals(listOf(Tags, Details, Galleries, Heatmap, SimilarScenes, PerformersStudio, Groups), order)
    }

    @Test fun encodeRoundTrips() {
        val ids = listOf("galleries", "details")
        assertEquals(ids, SceneDetailLayoutLogic.parse(SceneDetailLayoutLogic.encode(ids)))
        assertEquals(setOf(Tags), SceneDetailLayoutLogic.resolveHidden(listOf("tags", "unknown")))
    }

    @Test fun moveReorders() {
        assertEquals(listOf("b", "c", "a"), SceneDetailLayoutLogic.move(listOf("a", "b", "c"), 0, 2))
        assertEquals(listOf("a", "b", "c"), SceneDetailLayoutLogic.move(listOf("a", "b", "c"), 0, 5))
    }

    @Test fun landscapePairsAdjacentHalfWidthCards() {
        val order = SceneDetailCard.entries
        assertEquals(order.map { listOf(it) }, SceneDetailLayoutLogic.rows(order, emptySet(), landscape = false))
        val rows = SceneDetailLayoutLogic.rows(order, setOf(Heatmap), landscape = true)
        assertEquals(listOf(listOf(Details), listOf(SimilarScenes), listOf(PerformersStudio), listOf(Groups, Tags), listOf(Galleries)), rows)
        // Not adjacent once something sits between them → each full width.
        val split = listOf(Groups, Galleries, Tags)
        assertEquals(listOf(listOf(Groups), listOf(Galleries), listOf(Tags)), SceneDetailLayoutLogic.rows(split, emptySet(), landscape = true))
        // A hidden card in between doesn't break the pair.
        assertEquals(listOf(listOf(Groups, Tags)), SceneDetailLayoutLogic.rows(split, setOf(Galleries), landscape = true))
    }
}
