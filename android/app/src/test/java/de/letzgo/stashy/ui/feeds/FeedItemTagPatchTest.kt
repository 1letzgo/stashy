package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.data.tools.AITagUpdateEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `patch*TagsInLists` / `patchBulkAppliedTag` applied to one Feeds row ([FeedItem.applying]). */
class FeedItemTagPatchTest {

    private val a = Tag(id = "a", name = "A")
    private val b = Tag(id = "b", name = "B")

    @Test
    fun sceneAndPreviewTakeSceneUpdates() {
        val event = AITagUpdateEvent.TagsUpdated(AITagTarget.Kind.Scene, "1", listOf(a, b))
        val scene = FeedItem.SceneItem(Scene(id = "1", tags = listOf(a)))
        assertEquals(listOf("a", "b"), (scene.applying(event) as FeedItem.SceneItem).scene.tags!!.map { it.id })
        val preview = FeedItem.PreviewItem(Scene(id = "1"))
        assertEquals(listOf("a", "b"), (preview.applying(event) as FeedItem.PreviewItem).scene.tags!!.map { it.id })
        assertNull(FeedItem.SceneItem(Scene(id = "2")).applying(event))
    }

    @Test
    fun kindMustMatch() {
        // An image with the same id as a scene is a different entity.
        val event = AITagUpdateEvent.TagsUpdated(AITagTarget.Kind.Image, "1", listOf(a))
        assertNull(FeedItem.SceneItem(Scene(id = "1")).applying(event))
        assertEquals(listOf("a"), (FeedItem.ClipItem(StashImage(id = "1")).applying(event) as FeedItem.ClipItem).image.tags!!.map { it.id })
    }

    @Test
    fun markerKeepsPrimaryTagOutOfTags() {
        val marker = FeedItem.MarkerItem(SceneMarker(id = "m", primaryTag = IdName("p", "P"), tags = listOf(IdName("a", "A"))))
        val event = AITagUpdateEvent.TagsUpdated(AITagTarget.Kind.Marker, "m", listOf(Tag(id = "p", name = "P"), a, b))
        val patched = marker.applying(event) as FeedItem.MarkerItem
        assertEquals(listOf("a", "b"), patched.marker.tags!!.map { it.id })
        assertEquals("p", patched.marker.primaryTag?.id)
        // The overlay still lists the primary tag first.
        assertEquals(listOf("p", "a", "b"), patched.tags.map { it.id })
    }

    @Test
    fun bulkAddsOnceToScenesAndImagesOnly() {
        val event = AITagUpdateEvent.BulkTagsApplied(b, imageIds = listOf("i"), sceneIds = listOf("s"))
        val scene = FeedItem.SceneItem(Scene(id = "s", tags = listOf(a)))
        assertEquals(listOf("a", "b"), (scene.applying(event) as FeedItem.SceneItem).scene.tags!!.map { it.id })
        // Already tagged → untouched.
        assertNull(FeedItem.SceneItem(Scene(id = "s", tags = listOf(b))).applying(event))
        val clip = FeedItem.ClipItem(StashImage(id = "i"))
        assertEquals(listOf("b"), (clip.applying(event) as FeedItem.ClipItem).image.tags!!.map { it.id })
        assertNull(FeedItem.MarkerItem(SceneMarker(id = "s")).applying(event))
        assertNull(FeedItem.ClipItem(StashImage(id = "s")).applying(event))
    }

    @Test
    fun aiTagTargetPerKind() {
        assertEquals(AITagTarget.Kind.Scene, FeedItem.PreviewItem(Scene(id = "1")).aiTagTarget.kind)
        assertEquals(AITagTarget.Kind.Image, FeedItem.ClipItem(StashImage(id = "1")).aiTagTarget.kind)
        val marker = FeedItem.MarkerItem(SceneMarker(id = "m", primaryTag = IdName("p", "P"))).aiTagTarget
        assertEquals(AITagTarget.Kind.Marker, marker.kind)
        assertEquals("p", marker.primaryTagId)
    }
}
