package de.letzgo.stashy.data.tools

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** Pure RateMe logic (iOS `RateMeViewModel` / `StarRatingView` in `stashy/RateMeToolsView.swift`). */
class RateMeLogicTest {
    private val perf = RateMeTheme.Performer(RateMeOption("12", "Jane"))
    private val studio = RateMeTheme.Studio(RateMeOption("3", "Acme"))
    private val tag = RateMeTheme.Tag(RateMeOption("9", "Outdoor"))

    @Test
    fun persistedRawValues() {
        assertEquals(RateMeMode.Scenes, RateMeMode.from("scenes"))
        assertEquals(RateMeMode.Images, RateMeMode.from("images"))
        assertNull(RateMeMode.from("bogus"))
        assertEquals(RateMeImageMediaKind.StillImage, RateMeImageMediaKind.from("stillImage"))
        assertEquals(listOf("all", "stillImage", "video"), RateMeImageMediaKind.entries.map { it.raw })
        assertEquals(listOf("Any media", "Images", "Videos"), RateMeImageMediaKind.entries.map { it.title })
    }

    @Test
    fun themeIdsAndLabels() {
        assertEquals("random", RateMeTheme.Random.id)
        assertEquals("mostPlayed", RateMeTheme.MostPlayed.id)
        assertEquals("performer-12", perf.id)
        assertEquals("studio-3", studio.id)
        assertEquals("tag-9", tag.id)
        assertEquals("Most played", RateMeTheme.MostPlayed.label)
        assertEquals("Jane", perf.label)
    }

    @Test
    fun fixedThemesPerMode() {
        assertEquals(listOf(RateMeTheme.Random, RateMeTheme.Newest, RateMeTheme.MostPlayed), RateMeLogic.availableFixedThemes(RateMeMode.Scenes))
        assertEquals(listOf(RateMeTheme.Random, RateMeTheme.Newest), RateMeLogic.availableFixedThemes(RateMeMode.Images))
    }

    @Test
    fun unratedFilters() {
        assertEquals("""{"rating100":{"modifier":"IS_NULL","value":0}}""", RateMeLogic.unratedFilter(RateMeTheme.Newest).toString())
        assertEquals(
            """{"performers":{"value":["12"],"modifier":"INCLUDES"},"rating100":{"modifier":"IS_NULL","value":0}}""",
            RateMeLogic.unratedFilter(perf).toString(),
        )
        assertEquals(
            """{"studios":{"value":["3"],"modifier":"INCLUDES","depth":0},"rating100":{"modifier":"IS_NULL","value":0}}""",
            RateMeLogic.unratedFilter(studio).toString(),
        )
        assertEquals(
            """{"tags":{"value":["9"],"modifier":"INCLUDES","depth":0},"rating100":{"modifier":"IS_NULL","value":0}}""",
            RateMeLogic.unratedFilter(tag).toString(),
        )
        val video = RateMeLogic.unratedImageFilter(RateMeTheme.Random, RateMeImageMediaKind.Video)
        assertEquals("""{"value":"(?i)\\.(mp4|mov|m4v|webm|mkv)${'$'}","modifier":"MATCHES_REGEX"}""", video["path"].toString())
        assertNull(RateMeLogic.unratedImageFilter(RateMeTheme.Random, RateMeImageMediaKind.All)["path"])
        assertEquals("(?i)\\.(jpe?g|png|webp|gif)$", RateMeImageMediaKind.STILL_IMAGE_PATH_REGEX)
    }

    @Test
    fun pageFilterSorts() {
        assertEquals("""{"per_page":20,"sort":"created_at","direction":"DESC"}""", RateMeLogic.pageFilter(RateMeTheme.Newest).toString())
        assertEquals("""{"per_page":20,"sort":"play_count","direction":"DESC"}""", RateMeLogic.pageFilter(RateMeTheme.MostPlayed).toString())
        val (sort, dir) = RateMeLogic.sort(perf, Random(1))
        assertTrue(sort, Regex("random_\\d{1,8}").matches(sort))
        assertEquals("ASC", dir)
        assertTrue(RateMeLogic.sort(RateMeTheme.Random).first.startsWith("random_"))
    }

    @Test
    fun skipResetOnlyForFixedSorts() {
        assertTrue(RateMeLogic.resetsSkipsOnExhaustedPage(RateMeTheme.Newest, RateMeMode.Scenes))
        assertTrue(RateMeLogic.resetsSkipsOnExhaustedPage(RateMeTheme.MostPlayed, RateMeMode.Scenes))
        assertFalse(RateMeLogic.resetsSkipsOnExhaustedPage(RateMeTheme.MostPlayed, RateMeMode.Images))
        assertTrue(RateMeLogic.resetsSkipsOnExhaustedPage(RateMeTheme.Newest, RateMeMode.Images))
        assertFalse(RateMeLogic.resetsSkipsOnExhaustedPage(RateMeTheme.Random, RateMeMode.Scenes))
        assertFalse(RateMeLogic.resetsSkipsOnExhaustedPage(perf, RateMeMode.Scenes))
    }

    @Test
    fun videoDetection() {
        assertTrue(RateMeLogic.isVideoImage("clip.MP4", null, null))
        assertTrue(RateMeLogic.isVideoImage(null, "/data/a/b.webm", null))
        assertTrue(RateMeLogic.isVideoImage(null, null, "https://h/x/clip.mov?apikey=1"))
        assertFalse(RateMeLogic.isVideoImage("photo.jpg", "/data/photo.jpg", "https://h/image/5/image?t=1"))
        assertFalse(RateMeLogic.isVideoImage(null, null, null))
        assertFalse(RateMeLogic.isVideoImage("noext", null, null))
    }

    @Test
    fun aspectAndNames() {
        assertEquals(1.5f, RateMeLogic.imageAspect(1500, 1000, false), 0f)
        assertEquals(16f / 9f, RateMeLogic.imageAspect(null, 1000, true), 0f)
        assertEquals(1f, RateMeLogic.imageAspect(0, 0, false), 0f)
        assertEquals("Jane, Joe", RateMeLogic.joinedNames(listOf(" Jane ", null, "", "Joe")))
        assertNull(RateMeLogic.joinedNames(listOf(null, "  ")))
        assertEquals("Untitled scene", RateMeLogic.displayTitle("  ", RateMeMode.Scenes))
        assertEquals("Untitled image", RateMeLogic.displayTitle(null, RateMeMode.Images))
        assertEquals("Beach", RateMeLogic.displayTitle(" Beach ", RateMeMode.Images))
    }

    @Test
    fun messages() {
        assertEquals("No unrated scenes left in Random.", RateMeLogic.noneLeftMessage(RateMeMode.Scenes, RateMeTheme.Random))
        assertEquals("No unrated images left in Jane.", RateMeLogic.noneLeftMessage(RateMeMode.Images, perf))
        assertEquals("Really delete scene and files?", RateMeLogic.deleteConfirmationTitle(RateMeMode.Scenes))
        assertEquals(
            "‘this image’ and all associated files will be permanently deleted. This action cannot be undone.",
            RateMeLogic.deleteConfirmationMessage(RateMeMode.Images, null),
        )
    }

    @Test
    fun pickerKinds() {
        assertEquals(RateMePickerKind.Performers, RateMeThemePickerKind.Performer.storeKind(RateMeMode.Images))
        assertEquals(RateMePickerKind.Studios, RateMeThemePickerKind.Studio.storeKind(RateMeMode.Scenes))
        assertEquals(RateMePickerKind.ImageStudios, RateMeThemePickerKind.Studio.storeKind(RateMeMode.Images))
        assertEquals(RateMePickerKind.Tags, RateMeThemePickerKind.Tag.storeKind(RateMeMode.Scenes))
        assertEquals(RateMePickerKind.ImageTags, RateMeThemePickerKind.Tag.storeKind(RateMeMode.Images))
        assertEquals(perf, RateMeThemePickerKind.Performer.picked(perf))
        assertNull(RateMeThemePickerKind.Studio.picked(perf))
        assertNull(RateMeThemePickerKind.Tag.picked(RateMeTheme.Random))
        assertEquals(tag, RateMeThemePickerKind.Tag.theme(RateMeOption("9", "Outdoor")))
    }

    @Test
    fun starRating() {
        assertEquals(0, RateMeLogic.stars(null))
        assertEquals(0, RateMeLogic.stars(9))
        assertEquals(1, RateMeLogic.stars(10)) // round(0.5) = 1 (away from zero)
        assertEquals(3, RateMeLogic.stars(60))
        assertEquals(4, RateMeLogic.stars(70)) // 3.5 → 4
        assertEquals(5, RateMeLogic.stars(100))
        assertNull(RateMeLogic.rating100FromStars(0))
        assertEquals(80, RateMeLogic.rating100FromStars(4))
        // Tapping the current star clears; another star sets stars × 20.
        assertNull(RateMeLogic.ratingAfterTap(60, 3))
        assertEquals(100, RateMeLogic.ratingAfterTap(60, 5))
        assertEquals(20, RateMeLogic.ratingAfterTap(null, 1))
    }

    @Test
    fun mutationInputs() {
        assertEquals("""{"id":"5","rating100":null}""", RateMeRepository.ratingInput("5", null).toString())
        assertEquals("""{"id":"5","rating100":80}""", RateMeRepository.ratingInput("5", 80).toString())
        assertEquals("""{"id":"5","delete_file":true,"delete_generated":true}""", RateMeRepository.destroyInput("5").toString())
    }
}
