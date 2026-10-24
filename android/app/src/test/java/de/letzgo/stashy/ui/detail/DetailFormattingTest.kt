package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.VisualFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class DetailFormattingTest {

    @Test fun performerFirstRowAndGenderSpecificFields() {
        val p = Performer(
            id = "1", name = "A", sceneCount = 5, galleryCount = 1, rating100 = 80, gender = "FEMALE",
            fakeTits = "Natural", penisLength = 15.0, birthdate = "1990-01-01", heightCm = 165, weight = 0,
        )
        val items = DetailFormatting.performer(p, totalGalleries = 3)
        assertEquals(DetailItem("SCENES", "5"), items[0])
        assertEquals(DetailItem("GALLERIES", "3"), items[1])
        assertEquals(DetailItem("RATING", "80"), items[2])
        assertEquals(DetailItem("GENDER", "FEMALE"), items[3])
        assertEquals(DetailItem("Tits", "Natural"), items[4])
        assertTrue(items.none { it.label == "Penis" })
        assertTrue(items.contains(DetailItem("HEIGHT", "165 cm")))
        assertTrue(items.none { it.label == "WEIGHT" })
    }

    @Test fun performerMaleShowsPenisAndBattle() {
        val p = Performer(id = "1", gender = "MALE", penisLength = 16.0, fakeTits = "x")
        val items = DetailFormatting.performer(p, 0, battleLine = "3/10")
        assertEquals(DetailItem("RATING", "—"), items[2])
        assertEquals(DetailItem("BATTLE", "3/10"), items[3])
        assertTrue(items.contains(DetailItem("Penis", "16.0 cm")))
        assertTrue(items.none { it.label == "Tits" })
    }

    @Test fun performerOtherGenderShowsBoth() {
        val p = Performer(id = "1", gender = "NON_BINARY", penisLength = 10.5, fakeTits = "Fake")
        val labels = DetailFormatting.performer(p, 0).map { it.label }
        assertTrue("Tits" in labels && "Penis" in labels)
    }

    @Test fun studioTagGroupGalleryRows() {
        assertEquals(
            listOf(DetailItem("SCENES", "4"), DetailItem("PERFORMERS", "2")),
            DetailFormatting.studio(Studio("1", performerCount = 2), scenes = 4, galleries = 0),
        )
        val tag = Tag("1", sceneMarkerCount = 3, createdAt = "2025-02-03T10:00:00Z")
        assertEquals(
            listOf(DetailItem("SCENES", "1"), DetailItem("GALLERIES", "2"), DetailItem("MARKERS", "3"), DetailItem("CREATED", "2025-02-03")),
            DetailFormatting.tag(tag, 1, 2),
        )
        val group = StashGroup("1", studio = IdName("9", name = "Studio"), date = "2020-01-01", rating100 = 60)
        assertEquals(
            listOf(DetailItem("SCENES", "7"), DetailItem("STUDIO", "Studio"), DetailItem("DATE", "2020-01-01"), DetailItem("RATING", "60%")),
            DetailFormatting.group(group, 7, 0),
        )
        // Studio / performers are cards under the gallery header, not header rows.
        val gallery = Gallery("1", imageCount = 12, studio = Studio("9", "S"), performers = listOf(Performer("1", "A"), Performer("2", "B")), organized = true)
        assertEquals(
            listOf(DetailItem("IMAGES", "12"), DetailItem("ORGANIZED", "Yes")),
            DetailFormatting.gallery(gallery, 5),
        )
    }

    @Test fun ageInWholeYears() {
        val today = LocalDate.of(2026, 10, 4)
        assertEquals("36", DetailFormatting.age("1990-10-04", today))
        assertEquals("35", DetailFormatting.age("1990-10-05", today))
        assertNull(DetailFormatting.age("2026-01-01", today))
        assertNull(DetailFormatting.age("garbage", today))
        assertNull(DetailFormatting.age(null, today))
    }

    @Test fun fileExtensionAndAnimation() {
        val gif = StashImage("1", visualFiles = listOf(VisualFile(basename = "clip.gif")))
        assertEquals("GIF", DetailFormatting.fileExtension(gif))
        assertTrue(DetailFormatting.isAnimated(gif))
        val fromPath = StashImage("2", visualFiles = listOf(VisualFile(path = "/a/b/photo.jpeg")))
        assertEquals("JPEG", DetailFormatting.fileExtension(fromPath))
        assertFalse(DetailFormatting.isAnimated(fromPath))
        val fromUrl = StashImage("3", paths = ImagePaths(image = "https://h/image/3/x.webp?t=1"))
        assertEquals("WEBP", DetailFormatting.fileExtension(fromUrl))
        assertNull(DetailFormatting.fileExtension(StashImage("4", paths = ImagePaths(image = "https://h/image/4/image?t=1"))))
    }

    @Test fun editParsing() {
        assertEquals(165, EditParsing.int(" 165 "))
        assertNull(EditParsing.int("abc"))
        assertEquals(15.5, EditParsing.decimal("15,5")!!, 0.0001)
        assertEquals(100, EditParsing.rating("140"))
        assertEquals(0, EditParsing.rating("-3"))
        assertNull(EditParsing.rating(""))
        assertEquals(listOf("Jane Doe", "J.D."), EditParsing.aliases(" Jane Doe , ,J.D."))
        assertNull(EditParsing.aliases(" , "))
    }

    @Test fun gridAndRatingHelpers() {
        assertEquals(2, adaptiveColumnCount(358f, 220f, 2, 8))
        assertEquals(4, adaptiveColumnCount(900f, 220f, 2, 8))
        assertEquals(2, adaptiveColumnCount(0f, 220f, 2, 8))
        assertEquals(1, adaptiveColumnCount(358f, 560f, 1, 4))
        assertEquals(0, starsFromRating(null))
        assertEquals(3, starsFromRating(50))
        assertEquals(5, starsFromRating(100))
        assertEquals("1:05", formatClock(65_000))
        assertEquals("1:01:01", formatClock(3_661_000))
    }

    @Test fun sortOptionsMatchIos() {
        assertEquals(DetailSort.Scene.DateDesc, DetailSort.Scene.from("dateDesc"))
        assertEquals("o_counter", DetailSort.Scene.OCounterDesc.field)
        assertEquals("Most Viewed", DetailSort.Scene.PlayCountDesc.label)
        assertEquals(DetailSort.Image.DateDesc, DetailSort.Image.from("dateDesc"))
        assertEquals("DetailViewsSortConfig_performer_detail_ABC", DetailViewConfig.key(DetailViewContext.Performer, "ABC"))
        assertEquals("Images Sort", DetailViewContext.Gallery.settingsRowTitle)
    }
}
