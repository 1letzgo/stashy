package de.letzgo.stashy.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageFeedPost
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.ImageSessionPrecision
import de.letzgo.stashy.data.ImageSetGrouping
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.VisualFile
import de.letzgo.stashy.ui.catalog.ImageFeedAutoplay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS: `StashImageFilenameKeys` (set grouping of Feeds › Pics / Images 1/row). */
class ImageSetGroupingTest {
    private fun img(
        id: String,
        created: String? = null,
        date: String? = null,
        performers: List<String> = emptyList(),
        galleries: List<String> = emptyList(),
        basename: String? = null,
    ) = StashImage(
        id = id, createdAt = created, date = date,
        performers = performers.map { IdName(it, "P$it") },
        galleries = galleries.map { IdName(it, title = "G$it") },
        visualFiles = basename?.let { listOf(VisualFile("ImageFile", "/data/$it", it, 100, 100)) },
        paths = ImagePaths(image = "/image/$id/image"),
    )

    private fun ids(posts: List<ImageFeedPost>) = posts.map { p -> p.images.map { it.id } }

    @Test fun sessionFromFilename() {
        assertEquals("2026-01-12_12-39-43", ImageSetGrouping.parseSessionFromFilename("042_-_2026-01-12_12-39-43_0"))
        assertEquals("2026-06-24_07-42-44", ImageSetGrouping.parseSessionFromFilename("wolke11-2026-06-24_07-42-44_0"))
        assertNull(ImageSetGrouping.parseSessionFromFilename("IMG_1234"))
        assertEquals("042_-_2026-01-12_12-39-43_0", ImageSetGrouping.filenameStem("/a/b/042_-_2026-01-12_12-39-43_0.jpg?x=1"))
    }

    @Test fun createdKeyAndPrecision() {
        val i = img("1", created = "2026-06-24T07:42:44+02:00")
        assertEquals("2026-06-24_07-42-44", ImageSetGrouping.createdTimestampKey(i))
        val cache = HashMap<String, String>()
        assertEquals("2026-06-24_07", ImageSetGrouping.sessionKey(i, cache, ImageSessionPrecision.Hour))
        // Cache keeps the full key: a different precision needs no reset.
        assertEquals("2026-06-24_07-42", ImageSetGrouping.sessionKey(i, cache, ImageSessionPrecision.Minute))
        assertEquals("2026-06-24", ImageSetGrouping.sessionKey(i, cache, ImageSessionPrecision.Day))
        // Filename fallback when `created_at` is missing.
        assertEquals("2026-01-12_12", ImageSetGrouping.sessionKey(img("2", basename = "042_-_2026-01-12_12-39-43_0.jpg"), cache))
        assertEquals("", ImageSetGrouping.sessionKey(img("3"), cache))
    }

    @Test fun groupsSameSessionAndMetadataInApiOrder() {
        val images = listOf(
            img("a", "2026-01-01T10:05:00Z", performers = listOf("p1"), galleries = listOf("g1")),
            img("b", "2026-01-01T09:00:00Z", performers = listOf("p2")),
            img("c", "2026-01-01T10:40:00Z", performers = listOf("p1"), galleries = listOf("g1")),
            img("d", "2026-01-01T10:41:00Z", performers = listOf("p1"), galleries = listOf("g2")),
        )
        val posts = ImageSetGrouping.buildPosts(images, "dateDesc")
        assertEquals(listOf(listOf("a", "c"), listOf("b"), listOf("d")), ids(posts))
        assertTrue(posts[0].id.startsWith("set|session|2026-01-01_10|p1|g1"))
        assertEquals("single|b", posts[1].id)
        // Minute precision splits the set.
        assertEquals(4, ImageSetGrouping.buildPosts(images, "dateDesc", ImageSessionPrecision.Minute).size)
    }

    @Test fun performerSubsetsMergeButDisjointDoNot() {
        assertTrue(ImageSetGrouping.performersCompatible(setOf("a"), setOf("a", "b")))
        assertFalse(ImageSetGrouping.performersCompatible(setOf("a"), setOf("b")))
        assertFalse(ImageSetGrouping.performersCompatible(emptySet(), setOf("b")))
        assertTrue(ImageSetGrouping.performersCompatible(emptySet(), emptySet()))
    }

    @Test fun noTimestampFallsBackToDayWithMetadata() {
        val images = listOf(
            img("a", date = "2026-02-02", performers = listOf("p")),
            img("b", date = "2026-02-02", performers = listOf("p")),
            img("c", date = "2026-02-02"),
            img("d", date = "2026-02-02"),
        )
        // Images without performers and galleries never group by day alone.
        assertEquals(listOf(listOf("a", "b"), listOf("c"), listOf("d")), ids(ImageSetGrouping.buildPosts(images, "titleAsc")))
    }

    @Test fun randomSortOrDisabledKeepsSingles() {
        val images = listOf(
            img("a", "2026-01-01T10:05:00Z"),
            img("b", "2026-01-01T10:06:00Z"),
        )
        assertEquals(2, ImageSetGrouping.buildPosts(images, "dateDesc").let { it.first().images.size })
        assertEquals(listOf(listOf("a"), listOf("b")), ids(ImageSetGrouping.buildPosts(images, "random")))
        assertEquals(listOf(listOf("a"), listOf("b")), ids(ImageSetGrouping.buildPosts(images, "dateDesc", groupEnabled = false)))
        assertEquals(listOf("single|a", "single|b"), ImageSetGrouping.buildPosts(images, "ratingDesc").map { it.id })
    }

    @Test fun autoplayPicksMostCenteredVisibleVideo() {
        // (id, top, bottom) in viewport coordinates; viewport 0..1000.
        val frames = mapOf("a" to (0f to 300f), "b" to (400f to 700f), "c" to (1200f to 1500f))
        assertEquals("b", ImageFeedAutoplay.target(frames, 0f, 1000f))
        assertEquals("a", ImageFeedAutoplay.target(mapOf("a" to (-100f to 200f), "c" to (1200f to 1500f)), 0f, 1000f))
        assertNull(ImageFeedAutoplay.target(mapOf("c" to (1200f to 1500f)), 0f, 1000f))
    }
}
