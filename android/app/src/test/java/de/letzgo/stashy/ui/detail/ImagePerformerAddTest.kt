package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.ui.feeds.FeedPerformerAdd
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** The "+" after the performer names on a picture (viewer, image feed header): [ImagePerformerAdd]. */
class ImagePerformerAddTest {

    private val a = Performer(id = "a", name = "A")
    private val b = Performer(id = "b", name = "B")
    private val c = Performer(id = "c", name = "C")
    private val image = StashImage(id = "9", performers = listOf(IdName("a", "A"), IdName("b", "B")))

    @Test
    fun gatedByEditModeAndLoadedPerformers() {
        assertTrue(ImagePerformerAdd.canAdd(image, editMode = true))
        assertFalse(ImagePerformerAdd.canAdd(image, editMode = false))
        assertTrue(ImagePerformerAdd.canAdd(StashImage(id = "1", performers = emptyList()), editMode = true))
        assertFalse(ImagePerformerAdd.canAdd(StashImage(id = "1", performers = null), editMode = true))
    }

    @Test
    fun planIsExistingUnionPickedWithoutDuplicates() {
        val plan = ImagePerformerAdd.plan(image, listOf(b, c, c, a))!!
        assertEquals(FeedPerformerAdd.Target.Image, plan.target)
        assertEquals(mapOf("id" to "9", "performer_ids" to listOf("a", "b", "c")), plan.input)
        assertEquals(listOf(c), ImagePerformerAdd.newPerformers(image, listOf(b, c, c, a)))
    }

    @Test
    fun unloadedPerformersAreRefused() = runBlocking {
        val unloaded = StashImage(id = "1", performers = null)
        assertNull(ImagePerformerAdd.plan(unloaded, listOf(a)))
        var wrote = false
        try {
            ImagePerformerAdd.add(unloaded, listOf(a)) { _, _ -> wrote = true; emptyList() }
            fail("expected refusal")
        } catch (e: IllegalStateException) { }
        assertFalse(wrote)
    }

    @Test
    fun addWritesMergedIdsAndPatchesImage() = runBlocking {
        var sent: Pair<String, List<String>>? = null
        val updated = ImagePerformerAdd.add(image, listOf(c, a)) { id, ids -> sent = id to ids; ids.map { IdName(it, it.uppercase()) } }
        assertEquals("9" to listOf("a", "b", "c"), sent)
        assertEquals(listOf("a", "b", "c"), updated.performers!!.map { it.id })
    }

    @Test
    fun serverListMissingIdsFallsBackToLocalAppend() = runBlocking {
        val updated = ImagePerformerAdd.add(image, listOf(c)) { _, _ -> emptyList() }
        assertEquals(listOf(IdName("a", "A"), IdName("b", "B"), IdName("c", "C")), updated.performers)
    }

    @Test
    fun nothingNewWritesNothing() = runBlocking {
        val same = ImagePerformerAdd.add(image, listOf(a, b)) { _, _ -> fail("no write expected"); emptyList() }
        assertSame(image, same)
    }

    @Test
    fun writeFailureKeepsImage() = runBlocking {
        try {
            ImagePerformerAdd.add(image, listOf(c)) { _, _ -> throw RuntimeException("boom") }
            fail("expected failure")
        } catch (e: RuntimeException) { }
        assertEquals(listOf("a", "b"), image.performers!!.map { it.id })
    }

    @Test
    fun toastText() {
        assertEquals("Added C", ImagePerformerAdd.toastText(listOf(c)))
        assertEquals("Added 2 performers", ImagePerformerAdd.toastText(listOf(a, c)))
    }
}
