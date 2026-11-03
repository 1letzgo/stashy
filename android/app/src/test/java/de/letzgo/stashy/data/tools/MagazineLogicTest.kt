package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.VisualFile
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure Magazin logic (iOS `MagazinePageOrder` / `MagazineReadingStore`). */
class MagazineLogicTest {
    private fun image(name: String, type: String = "ImageFile") =
        StashImage(id = name, visualFiles = listOf(VisualFile(typename = type, path = "/x/$name", basename = name)))

    @Test
    fun pagesSortNumericallyAcrossDigitBoundaries() {
        val names = listOf("100.jpg", "10.jpg", "2.jpg", "999.jpg", "1.jpg", "99.jpg", "9.jpg")
        assertEquals(
            listOf("1.jpg", "2.jpg", "9.jpg", "10.jpg", "99.jpg", "100.jpg", "999.jpg"),
            MagazineLogic.pages(names.map(::image)).map { it.id },
        )
    }

    @Test
    fun naturalOrderHandlesCaseAndLeadingZeros() {
        val order = MagazineLogic.naturalOrder
        assertTrue(order.compare("a2", "A10") < 0)
        assertEquals(0, order.compare("007", "7"))
        assertTrue(order.compare("page", "page1") < 0)
    }

    @Test
    fun videosAreNotPages() {
        val pages = MagazineLogic.pages(listOf(image("1.jpg"), image("2.mp4", "VideoFile")))
        assertEquals(listOf("1.jpg"), pages.map { it.id })
    }

    @Test
    fun spreadsHoldTwoPages() {
        assertEquals(0, MagazineLogic.spreadCount(0))
        assertEquals(1, MagazineLogic.spreadCount(1))
        assertEquals(1, MagazineLogic.spreadCount(2))
        assertEquals(6, MagazineLogic.spreadCount(11))
    }

    @Test
    fun progressStartsAfterPageOneAndFillsOnLastSpread() {
        assertNull(MagazineLogic.readFraction(null, 20))
        assertNull(MagazineLogic.readFraction(1, 20))
        assertNull(MagazineLogic.readFraction(5, null))
        assertEquals(0.25f, MagazineLogic.readFraction(5, 20)!!, 0.001f)
        assertEquals(1f, MagazineLogic.readFraction(19, 20)!!, 0.001f)
        assertEquals(1f, MagazineLogic.readFraction(21, 21)!!, 0.001f)
    }

    @Test
    fun readsFieldsWrittenByIos() {
        val fields = JsonObject(mapOf(
            MagazineLogic.PAGE_FIELD to JsonPrimitive(5),
            MagazineLogic.READ_AT_FIELD to JsonPrimitive("2026-11-02T10:51:56Z"),
        ))
        assertEquals(MagazineEntry(5, "2026-11-02T10:51:56Z", true), MagazineLogic.entryFromFields(fields))
        assertNull(MagazineLogic.entryFromFields(JsonObject(emptyMap())))
        assertNull(MagazineLogic.entryFromFields(null))
    }

    @Test
    fun newerPositionWins() {
        val older = MagazineEntry(3, "2026-11-02T10:00:00Z", true)
        val newer = MagazineEntry(9, "2026-11-02T11:00:00Z", false)
        assertTrue(MagazineLogic.remoteWins(older, null))
        assertTrue(MagazineLogic.remoteWins(newer, older))
        assertFalse(MagazineLogic.remoteWins(older, newer))
        assertTrue(MagazineLogic.remoteWins(older, older))
    }

    private val chapters = listOf(MagazineChapter("b", "Two", 8), MagazineChapter("a", "One", 1), MagazineChapter("c", "Three", 17))

    @Test
    fun currentChapterFollowsTheLastVisiblePage() {
        assertEquals("One", MagazineLogic.currentChapter(chapters, MagazineLogic.lastVisiblePage(0, 23))?.title)
        // Spread 7–8 (index 3): the chapter starts on its second page.
        assertEquals("Two", MagazineLogic.currentChapter(chapters, MagazineLogic.lastVisiblePage(3, 23))?.title)
        assertEquals("Three", MagazineLogic.currentChapter(chapters, 22)?.title)
        assertNull(MagazineLogic.currentChapter(listOf(MagazineChapter("x", "Late", 5)), 1))
    }

    @Test
    fun lastVisiblePageStopsAtALoneLastPage() {
        assertEquals(22, MagazineLogic.lastVisiblePage(11, 23))
        assertEquals(21, MagazineLogic.lastVisiblePage(10, 23))
    }

    @Test
    fun chapterPagesAreClampedToTheGallery() {
        assertEquals(7, MagazineLogic.chapterPage(MagazineChapter("b", "Two", 8), 23))
        assertEquals(22, MagazineLogic.chapterPage(MagazineChapter("x", "Past", 99), 23))
        assertEquals(0, MagazineLogic.chapterPage(MagazineChapter("x", "Zero", 0), 23))
    }

    @Test
    fun enteredPageMustBeInTheGallery() {
        assertEquals(11, MagazineLogic.enteredPage(" 12 ", 23))
        assertNull(MagazineLogic.enteredPage("0", 23))
        assertNull(MagazineLogic.enteredPage("24", 23))
        assertNull(MagazineLogic.enteredPage("", 23))
    }

    @Test
    fun coversAreThreePerRowOnPhones() {
        assertEquals(3, MagazineLogic.coverColumns(0f))
        assertEquals(3, MagazineLogic.coverColumns(412f))
        assertEquals(4, MagazineLogic.coverColumns(932f))
    }

    @Test
    fun ratingLabelDropsWholeStarDecimals() {
        assertEquals("4 / 5", MagazineLogic.ratingLabel(80))
        assertEquals("4.5 / 5", MagazineLogic.ratingLabel(90))
    }
}
