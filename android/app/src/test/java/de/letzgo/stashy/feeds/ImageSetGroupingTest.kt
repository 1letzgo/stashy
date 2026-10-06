package de.letzgo.stashy.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageFeedPost
import de.letzgo.stashy.data.ImageGroupMode
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.ImageSetGrouping
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.VisualFile
import de.letzgo.stashy.ui.catalog.ImageFeedAutoplay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS: `StashImageSetGrouping` (set grouping of Feeds › Pics / Images 1/row), mirrored in stashyTests. */
class ImageSetGroupingTest {
    private fun img(
        id: String,
        created: String? = null,
        performers: List<String> = emptyList(),
        galleries: List<String> = emptyList(),
        studio: String? = null,
        basename: String? = null,
        video: Boolean = false,
    ) = StashImage(
        id = id, createdAt = created,
        performers = performers.map { IdName(it, "P$it") },
        galleries = galleries.map { IdName(it, title = "G$it") },
        studio = studio?.let { IdName(it, "S$it") },
        visualFiles = listOf(
            VisualFile(if (video) "VideoFile" else "ImageFile", "/data/${basename ?: "$id.jpg"}", basename ?: "$id.jpg", 100, 100),
        ),
        paths = ImagePaths(image = "/image/$id/image"),
    )

    private fun ids(posts: List<ImageFeedPost>) = posts.map { p -> p.images.map { it.id } }
    private fun group(vararg images: StashImage, sort: String = "dateDesc", mode: ImageGroupMode = ImageGroupMode.GallerySession, gap: Int = 10) =
        ImageSetGrouping.buildPosts(images.toList(), sort, mode, gap)

    // MARK: timestamps

    @Test fun parsesCreatedAtVariantsToEpoch() {
        val utc = ImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44Z")!!
        assertEquals(utc, ImageSetGrouping.parseCreatedAt("2026-06-24T09:42:44+02:00"))
        assertEquals(utc, ImageSetGrouping.parseCreatedAt("2026-06-24 07:42:44 +0000"))
        assertEquals(utc, ImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44.517Z"))
        assertEquals(utc, ImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44"))
        assertEquals(1_782_286_964L, utc)
        assertNull(ImageSetGrouping.parseCreatedAt("yesterday"))
        assertNull(ImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44+2"))
        assertNull(ImageSetGrouping.parseCreatedAt(null))
    }

    @Test fun filenameSessionParsing() {
        assertEquals("2026-01-12_12-39-43", ImageSetGrouping.parseSessionFromFilename("042_-_2026-01-12_12-39-43_0"))
        assertEquals("2026-06-24_07-42-44", ImageSetGrouping.parseSessionFromFilename("wolke11-2026-06-24_07-42-44_0"))
        assertNull(ImageSetGrouping.parseSessionFromFilename("IMG_1234"))
        assertEquals("042_-_2026-01-12_12-39-43_0", ImageSetGrouping.filenameStem("/a/b/042_-_2026-01-12_12-39-43_0.jpg?x=1"))
        assertEquals(ImageSetGrouping.parseCreatedAt("2026-06-24T07:42:44Z"), ImageSetGrouping.parseFilenameSession("2026-06-24_07-42-44"))
    }

    // MARK: rules

    @Test fun onlyConsecutiveImagesGroup() {
        val a = img("a", "2026-01-01T10:00:00Z", galleries = listOf("g1"))
        val b = img("b", "2026-01-01T10:00:30Z", galleries = listOf("g2"))
        val c = img("c", "2026-01-01T10:01:00Z", galleries = listOf("g1"))
        assertEquals(listOf(listOf("a"), listOf("b"), listOf("c")), ids(group(a, b, c)))
    }

    @Test fun galleryIntersectionJoinsIndependentOfTime() {
        val a = img("a", "2026-01-01T10:00:00Z", galleries = listOf("g1", "g2"))
        val b = img("b", "2025-03-01T10:00:00Z", galleries = listOf("g2", "g3"))
        val c = img("c", null, galleries = listOf("g3"))
        val d = img("d", "2026-01-01T10:00:00Z", galleries = listOf("g9"))
        assertEquals(listOf(listOf("a", "b", "c"), listOf("d")), ids(group(a, b, c, d)))
        // Pure gallery mode uses the same rule.
        assertEquals(listOf(listOf("a", "b", "c"), listOf("d")), ids(group(a, b, c, d, mode = ImageGroupMode.Gallery)))
    }

    @Test fun mixedGalleryAndNoGalleryNeverJoin() {
        val a = img("a", "2026-01-01T10:00:00Z", performers = listOf("p"), galleries = listOf("g1"))
        val b = img("b", "2026-01-01T10:00:01Z", performers = listOf("p"))
        val c = img("c", "2026-01-01T10:00:02Z", performers = listOf("p"), galleries = listOf("g1"))
        assertEquals(listOf(listOf("a"), listOf("b"), listOf("c")), ids(group(a, b, c)))
    }

    @Test fun looseUntaggedImagesNeverGroup() {
        val a = img("a", "2026-01-01T10:00:00Z")
        val b = img("b", "2026-01-01T10:00:00Z")
        assertEquals(listOf(listOf("a"), listOf("b")), ids(group(a, b)))
    }

    @Test fun equalNonEmptyPerformersWithinGapJoin() {
        val a = img("a", "2026-01-01T10:00:00Z", performers = listOf("p1", "p2"))
        val b = img("b", "2026-01-01T10:05:00Z", performers = listOf("p2", "p1"))
        val c = img("c", "2026-01-01T10:06:00Z", performers = listOf("p1"))
        assertEquals(listOf(listOf("a", "b"), listOf("c")), ids(group(a, b, c)))
        // Gallery-only mode never groups loose images.
        assertEquals(3, group(a, b, c, mode = ImageGroupMode.Gallery).size)
    }

    @Test fun performersComparedToFirstImageNoTransitiveDrift() {
        // [A] ~ [A,B] ~ [B] chains are not possible: every image must equal the first one.
        val a = img("a", "2026-01-01T10:00:00Z", performers = listOf("A"))
        val ab = img("ab", "2026-01-01T10:01:00Z", performers = listOf("A", "B"))
        val b = img("b", "2026-01-01T10:02:00Z", performers = listOf("B"))
        assertEquals(listOf(listOf("a"), listOf("ab"), listOf("b")), ids(group(a, ab, b)))
    }

    @Test fun studioRule() {
        val a = img("a", "2026-01-01T10:00:00Z", studio = "s1")
        val b = img("b", "2026-01-01T10:01:00Z", studio = "s1")
        val c = img("c", "2026-01-01T10:02:00Z", studio = "s2")
        val d = img("d", "2026-01-01T10:03:00Z", studio = "s2", performers = listOf("p"))
        assertEquals(listOf(listOf("a", "b"), listOf("c"), listOf("d")), ids(group(a, b, c, d)))
    }

    @Test fun gapBoundaryAgainstLastImage() {
        val a = img("a", "2026-01-01T10:00:00Z", performers = listOf("p"))
        val b = img("b", "2026-01-01T10:10:00Z", performers = listOf("p"))   // exactly 10 min → joins
        val c = img("c", "2026-01-01T10:20:00Z", performers = listOf("p"))   // 10 min after b (20 after a) → joins
        val d = img("d", "2026-01-01T10:30:01Z", performers = listOf("p"))   // 10 min 1 s → new post
        assertEquals(listOf(listOf("a", "b", "c"), listOf("d")), ids(group(a, b, c, d)))
        assertEquals(4, group(a, b, c, d, gap = 2).size)
        assertEquals(1, group(a, b, c, d, gap = 60).size)
        // Descending order works the same (absolute gap).
        assertEquals(listOf(listOf("d"), listOf("c", "b", "a")), ids(group(d, c, b, a)))
    }

    @Test fun filenameFallbackAndMissingTimestamp() {
        val a = img("a", null, performers = listOf("p"), basename = "042_-_2026-01-12_12-39-43_0.jpg")
        val b = img("b", "2026-01-12T12:41:00Z", performers = listOf("p"))
        val c = img("c", "garbage", performers = listOf("p"), basename = "wolke-2026-01-12_12-45-00_0.jpg")
        val d = img("d", null, performers = listOf("p"))
        assertEquals(listOf(listOf("a", "b", "c"), listOf("d")), ids(group(a, b, c, d)))
    }

    @Test fun setsAreCappedAtThirty() {
        val images = (0 until 65).map { img("i$it", null, galleries = listOf("g")) }
        val posts = ImageSetGrouping.buildPosts(images, "dateDesc", ImageGroupMode.GallerySession, 10)
        assertEquals(listOf(30, 30, 5), posts.map { it.images.size })
        assertEquals(listOf("set|i0", "set|i30", "set|i60"), posts.map { it.id })
    }

    @Test fun setsRespectAConfiguredMaxSize() {
        val images = (0 until 25).map { img("i$it", null, galleries = listOf("g")) }
        val ten = ImageSetGrouping.buildPosts(images, "dateDesc", ImageGroupMode.GallerySession, 10, maxSetSize = 10)
        assertEquals(listOf(10, 10, 5), ten.map { it.images.size })
        assertEquals(listOf("set|i0", "set|i10", "set|i20"), ten.map { it.id })
        assertEquals(listOf(25), ImageSetGrouping.buildPosts(images, "dateDesc", ImageGroupMode.GallerySession, 10, maxSetSize = 100).map { it.images.size })
        // canJoin itself: a post of 20 is full at 20, not at 50.
        val post = images.take(20)
        assertFalse(ImageSetGrouping.canJoin(post, images[20], ImageGroupMode.Gallery, 10, maxSetSize = 20))
        assertTrue(ImageSetGrouping.canJoin(post, images[20], ImageGroupMode.Gallery, 10, maxSetSize = 50))
    }

    @Test fun clipAndPhotoNeverShareASet() {
        val a = img("a", "2026-01-01T10:00:00Z", galleries = listOf("g"))
        val v = img("v", "2026-01-01T10:00:01Z", galleries = listOf("g"), video = true)
        val w = img("w", "2026-01-01T10:00:02Z", galleries = listOf("g"), video = true)
        assertEquals(listOf(listOf("a"), listOf("v", "w")), ids(group(a, v, w)))
    }

    @Test fun unsupportedSortsAndOffKeepSingles() {
        val a = img("a", "2026-01-01T10:00:00Z", galleries = listOf("g"))
        val b = img("b", "2026-01-01T10:00:01Z", galleries = listOf("g"))
        for (sort in listOf("dateAsc", "dateDesc", "createdAtAsc", "createdAtDesc")) assertEquals(1, group(a, b, sort = sort).size)
        for (sort in listOf("titleAsc", "titleDesc", "random", "ratingDesc", null)) {
            assertEquals(listOf("single|a", "single|b"), ImageSetGrouping.buildPosts(listOf(a, b), sort).map { it.id })
        }
        assertEquals(listOf("single|a", "single|b"), group(a, b, mode = ImageGroupMode.Off).map { it.id })
    }

    @Test fun appendingAPageOnlyExtendsTheLastPost() {
        val page1 = listOf(
            img("a", "2026-01-01T10:00:00Z", galleries = listOf("g1")),
            img("b", "2026-01-01T10:00:01Z", galleries = listOf("g1")),
            img("c", "2026-01-01T09:00:00Z", performers = listOf("p")),
        )
        val page2 = listOf(
            img("d", "2026-01-01T09:01:00Z", performers = listOf("p")),
            img("e", "2026-01-01T08:00:00Z", galleries = listOf("g1")),
        )
        val first = ImageSetGrouping.buildPosts(page1, "dateDesc")
        val both = ImageSetGrouping.buildPosts(page1 + page2, "dateDesc")
        assertEquals(listOf("set|a", "single|c"), first.map { it.id })
        assertEquals(listOf("set|a", "set|c", "single|e"), both.map { it.id })
        assertEquals(first[0], both[0]) // earlier posts unchanged; "e" (gallery g1) does not reach back to "a"
    }

    // MARK: settings

    @Test fun migrationAndGapNormalization() {
        assertEquals(ImageGroupMode.Off, ImageSetGrouping.migratedMode(false))
        assertEquals(ImageGroupMode.GallerySession, ImageSetGrouping.migratedMode(true))
        assertEquals(ImageGroupMode.GallerySession, ImageSetGrouping.migratedMode(null))
        assertEquals(ImageGroupMode.Gallery, ImageGroupMode.from("gallery"))
        assertEquals(ImageGroupMode.GallerySession, ImageGroupMode.from("bogus"))
        assertEquals(listOf("off", "gallery", "gallerySession"), ImageGroupMode.entries.map { it.raw })
        assertEquals(2, ImageSetGrouping.normalizedGap(2))
        assertEquals(60, ImageSetGrouping.normalizedGap(60))
        assertEquals(10, ImageSetGrouping.normalizedGap(5))
        assertEquals(10, ImageSetGrouping.normalizedGap(null))
        assertEquals("stashline_group_max_size", ImageSetGrouping.MAX_SIZE_KEY)
        assertEquals(listOf(10, 20, 30, 50, 100), ImageSetGrouping.maxSizeOptions)
        assertEquals(10, ImageSetGrouping.normalizedMaxSize(10))
        assertEquals(100, ImageSetGrouping.normalizedMaxSize(100))
        assertEquals(30, ImageSetGrouping.normalizedMaxSize(40))
        assertEquals(30, ImageSetGrouping.normalizedMaxSize(null))
    }

    @Test fun autoplayPicksMostCenteredVisibleVideo() {
        // (id, top, bottom) in viewport coordinates; viewport 0..1000.
        val frames = mapOf("a" to (0f to 300f), "b" to (400f to 700f), "c" to (1200f to 1500f))
        assertEquals("b", ImageFeedAutoplay.target(frames, 0f, 1000f))
        assertEquals("a", ImageFeedAutoplay.target(mapOf("a" to (-100f to 200f), "c" to (1200f to 1500f)), 0f, 1000f))
        assertNull(ImageFeedAutoplay.target(mapOf("c" to (1200f to 1500f)), 0f, 1000f))
    }
}
