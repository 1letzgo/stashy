package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageRefreshTest {
    @Test fun withQueryItemAppendsOrReplaces() {
        assertEquals("https://s/x?bust=1", ImageBusters.withQueryItem("https://s/x", "bust", "1"))
        assertEquals("https://s/x?t=5&bust=2", ImageBusters.withQueryItem("https://s/x?t=5", "bust", "2"))
        assertEquals("https://s/x?t=5&bust=3", ImageBusters.withQueryItem("https://s/x?bust=1&t=5", "bust", "3"))
        assertEquals("https://s/x?bust=4#f", ImageBusters.withQueryItem("https://s/x#f", "bust", "4"))
    }

    @Test fun bumpChangesTheUrlAndCacheKey() {
        val url = "https://s/scene/7/scene_marker/42/screenshot"
        assertEquals(url, ImageBusters.apply(url, ImageBusters.Kind.Marker, "unbumped"))
        val first = ImageBusters.bump(ImageBusters.Kind.Marker, "42")
        val a = ImageBusters.apply(url, ImageBusters.Kind.Marker, "42")!!
        val second = ImageBusters.bump(ImageBusters.Kind.Marker, "42")
        val b = ImageBusters.apply(url, ImageBusters.Kind.Marker, "42")!!
        assertNotEquals(first, second)
        assertTrue(second.toLong() > first.toLong())
        assertNotEquals(ImageCacheKeys.key(a, "S"), ImageCacheKeys.key(b, "S"))
        // Kinds are separate: a marker stamp never busts the performer with the same id.
        assertNull(ImageBusters.stamp(ImageBusters.Kind.Performer, "42-none"))
    }

    @Test fun keyMatchingIsScopedToServerAndEntity() {
        val marker = ImageRefresh.pathFragments(ImageBusters.Kind.Marker, "42", "7")
        assertTrue(ImageRefresh.keyMatches("srv:S|https://h/scene/7/scene_marker/42/screenshot?bust=1", "S", marker))
        assertTrue(ImageRefresh.keyMatches("srv:S|https://h/scenemarker/42/screenshot", "S", marker))
        assertFalse(ImageRefresh.keyMatches("srv:T|https://h/scene/7/scene_marker/42/screenshot", "S", marker))
        assertFalse(ImageRefresh.keyMatches("srv:S|https://h/scene/7/scene_marker/142/screenshot", "S", marker))

        val performer = ImageRefresh.pathFragments(ImageBusters.Kind.Performer, "1")
        assertTrue(ImageRefresh.keyMatches("srv:S|https://h/performer/1/image?t=9&width=320", "S", performer))
        assertFalse(ImageRefresh.keyMatches("srv:S|https://h/performer/12/image", "S", performer))
        assertFalse(ImageRefresh.keyMatches("srv:S|https://h/x?u=/performer/1/image", "S", performer))

        val scene = ImageRefresh.pathFragments(ImageBusters.Kind.Scene, "3")
        assertTrue(ImageRefresh.keyMatches("srv:S|https://h/scene/3/screenshot?t=1&width=640", "S", scene))
        assertFalse(ImageRefresh.keyMatches("srv:S|https://h/scene/33/screenshot", "S", scene))
    }
}

class PerformerEventsTest {
    private val p1 = Performer(id = "1", name = "A", imagePath = "https://h/performer/1/image?t=1")
    private val p2 = Performer(id = "2", name = "B", imagePath = "https://h/performer/2/image?t=1")

    @Test fun imageUpdatePatchesOnlyThatPerformer() {
        val e = PerformerEvent.ImageUpdated("1", "https://h/performer/1/image?t=2", "100")
        assertEquals("https://h/performer/1/image?t=2", e.applyTo(p1).imagePath)
        assertSame(p2, e.applyTo(p2))
        // No new path from the server: the item stays (the stamp busts its URL instead).
        val same = PerformerEvent.ImageUpdated("1", null, "100")
        assertSame(p1, same.applyTo(p1))
    }

    @Test fun listApplyingReportsChangesOnly() {
        val list = listOf(p1, p2)
        val e = PerformerEvent.ImageUpdated("2", "https://h/performer/2/image?t=9", "100")
        assertEquals("https://h/performer/2/image?t=9", list.applying(e)!![1].imagePath)
        assertNull(list.applying(PerformerEvent.ImageUpdated("9", "x", "100")))
        assertNull(list.applying(PerformerEvent.ImageUpdated("1", p1.imagePath, "100")))
    }

    @Test fun scenePerformerRowsArePatched() {
        val s1 = Scene(id = "s1", performers = listOf(p1, p2))
        val s2 = Scene(id = "s2", performers = listOf(p2))
        val e = PerformerEvent.ImageUpdated("1", "https://h/performer/1/image?t=3", "100")
        assertNull(e.applyTo(s2))
        assertEquals("https://h/performer/1/image?t=3", e.applyTo(s1)!!.performers[0].imagePath)
        val patched = listOf(s1, s2).applyingPerformerEvent(e)!!
        assertSame(s2, patched[1])
        assertNull(listOf(s2).applyingPerformerEvent(e))
    }
}

class SceneCoverEventTest {
    @Test fun coverUpdateChangesThumbnailStamp() {
        val s = Scene(id = "1", updatedAt = "2026-01-01T00:00:00Z")
        val next = SceneEvent.CoverUpdated("1", "1767225600123").applyTo(s)!!
        assertEquals("1767225600123", next.updatedAt)
        assertNull(listOf(next).applying(SceneEvent.CoverUpdated("1", "1767225600123")))
    }
}
