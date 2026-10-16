package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.StashImage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Feeds "+" after the performer names: target + `performer_ids` ([FeedPerformerAdd]). */
class FeedPerformerAddTest {

    private val a = Performer(id = "a", name = "A")
    private val b = Performer(id = "b", name = "B")
    private val c = Performer(id = "c", name = "C")

    @Test
    fun sceneGetsExistingUnionPicked() {
        val item = FeedItem.SceneItem(Scene(id = "1", performers = listOf(a, b)))
        val plan = FeedPerformerAdd.forItem(item, listOf("c"))!!
        assertEquals(FeedPerformerAdd.Target.Scene, plan.target)
        assertEquals("1", plan.id)
        assertEquals(listOf("a", "b", "c"), plan.performerIds)
        assertEquals(mapOf("id" to "1", "performer_ids" to listOf("a", "b", "c")), plan.input)
    }

    @Test
    fun noDuplicates() {
        val item = FeedItem.SceneItem(Scene(id = "1", performers = listOf(a, b)))
        assertEquals(listOf("a", "b", "c"), FeedPerformerAdd.forItem(item, listOf("b", "c", "c", "a"))!!.performerIds)
        assertEquals(listOf("x", "y"), FeedPerformerAdd.mergedIds(listOf("x", "x"), listOf("y", "x", "")))
    }

    @Test
    fun emptyRowStillAdds() {
        val plan = FeedPerformerAdd.forItem(FeedItem.SceneItem(Scene(id = "1")), listOf("a", "b"))!!
        assertEquals(listOf("a", "b"), plan.performerIds)
    }

    @Test
    fun markerWritesToParentScene() {
        val marker = FeedItem.MarkerItem(SceneMarker(id = "m9", scene = Scene(id = "s7", performers = listOf(a))))
        val plan = FeedPerformerAdd.forItem(marker, listOf("b"))!!
        assertEquals(FeedPerformerAdd.Target.Scene, plan.target)
        assertEquals("s7", plan.id)
        assertEquals(listOf("a", "b"), plan.performerIds)
        assertTrue(marker.canAddPerformers)
    }

    @Test
    fun markerWithoutSceneHasNoTarget() {
        val marker = FeedItem.MarkerItem(SceneMarker(id = "m9"))
        assertNull(FeedPerformerAdd.forItem(marker, listOf("b")))
        assertFalse(marker.canAddPerformers)
    }

    @Test
    fun imageWithoutLoadedPerformersIsRefused() {
        // performer_ids replaces: writing only the picked ids would wipe unknown performers.
        val clip = FeedItem.ClipItem(StashImage(id = "i1", performers = null))
        assertNull(FeedPerformerAdd.forItem(clip, listOf("a")))
        assertFalse(clip.canAddPerformers)
        assertTrue(FeedItem.ClipItem(StashImage(id = "i1", performers = emptyList())).canAddPerformers)
    }

    @Test
    fun previewIsSceneClipIsImage() {
        assertEquals(FeedPerformerAdd.Target.Scene, FeedPerformerAdd.forItem(FeedItem.PreviewItem(Scene(id = "p")), listOf("a"))!!.target)
        val clip = FeedItem.ClipItem(StashImage(id = "i1", performers = listOf(IdName("a", "A"))))
        val plan = FeedPerformerAdd.forItem(clip, listOf("a", "c"))!!
        assertEquals(FeedPerformerAdd.Target.Image, plan.target)
        assertEquals("i1", plan.id)
        assertEquals(listOf("a", "c"), plan.performerIds)
    }

    @Test
    fun localPatchAppendsOnlyNewOnes() {
        assertEquals(listOf("a", "b", "c"), FeedPerformerAdd.appending(listOf(a, b), listOf(b, c)).map { it.id })
        assertEquals(listOf("a", "c"), FeedPerformerAdd.appendingNames(listOf(IdName("a", "A")), listOf(a, c, c)).map { it.id })
    }
}
