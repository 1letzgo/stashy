package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import java.time.LocalDate
import java.time.Period
import java.time.format.DateTimeParseException

/** One label/value cell of the detail header grid (label shown uppercased, 8pt). */
data class DetailItem(val label: String, val value: String)

/** Pure header data builders, 1:1 with the iOS `get*Details` functions. */
object DetailFormatting {

    /** iOS `PerformerDetailView.getPerformerDetails`. */
    fun performer(p: Performer, totalGalleries: Int, battleLine: String? = null): List<DetailItem> {
        val list = mutableListOf<DetailItem>()
        list += DetailItem("SCENES", "${p.sceneCount ?: 0}")
        list += DetailItem("GALLERIES", "${maxOf(p.galleryCount ?: 0, totalGalleries)}")
        list += DetailItem("RATING", p.rating100?.toString() ?: "—")
        if (!battleLine.isNullOrEmpty()) list += DetailItem("BATTLE", battleLine)
        p.gender?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("GENDER", it) }

        val gender = p.gender?.uppercase() ?: ""
        val tits = p.fakeTits?.takeIf { it.isNotEmpty() }?.let { DetailItem("Tits", it) }
        val penis = p.penisLength?.takeIf { it > 0 }?.let { DetailItem("Penis", "${formatSwiftDouble(it)} cm") }
        when {
            gender.contains("FEMALE") -> tits?.let { list += it }
            gender.contains("MALE") || gender == "MAN" -> penis?.let { list += it }
            else -> { tits?.let { list += it }; penis?.let { list += it } }
        }
        p.birthdate?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("BORN", it) }
        p.country?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("COUNTRY", it) }
        p.ethnicity?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("ETHNICITY", it) }
        p.heightCm?.takeIf { it > 0 }?.let { list += DetailItem("HEIGHT", "$it cm") }
        p.weight?.takeIf { it > 0 }?.let { list += DetailItem("WEIGHT", "$it kg") }
        p.measurements?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("MEASUREMENTS", it) }
        p.careerLength?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("CAREER", it) }
        p.tattoos?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("TATTOOS", it) }
        p.piercings?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("PIERCINGS", it) }
        return list
    }

    /** iOS `StudioDetailView.getStudioDetails` (URL is shown on its own row). */
    fun studio(s: Studio, scenes: Int, galleries: Int): List<DetailItem> {
        val list = mutableListOf(DetailItem("SCENES", "$scenes"))
        if (galleries > 0) list += DetailItem("GALLERIES", "$galleries")
        s.performerCount?.takeIf { it > 0 }?.let { list += DetailItem("PERFORMERS", "$it") }
        s.rating100?.let { list += DetailItem("RATING", "$it%") }
        return list
    }

    /** iOS `TagDetailView.getTagDetails`. */
    fun tag(t: Tag, scenes: Int, galleries: Int): List<DetailItem> {
        val list = mutableListOf(DetailItem("SCENES", "$scenes"))
        if (galleries > 0) list += DetailItem("GALLERIES", "$galleries")
        t.performerCount?.takeIf { it > 0 }?.let { list += DetailItem("PERFORMERS", "$it") }
        t.sceneMarkerCount?.takeIf { it > 0 }?.let { list += DetailItem("MARKERS", "$it") }
        t.createdAt?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("CREATED", it.take(10)) }
        t.updatedAt?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("UPDATED", it.take(10)) }
        return list
    }

    /** iOS `GroupDetailView.getGroupDetails`. */
    fun group(g: StashGroup, scenes: Int, galleries: Int): List<DetailItem> {
        val list = mutableListOf(DetailItem("SCENES", "$scenes"))
        if (galleries > 0) list += DetailItem("GALLERIES", "$galleries")
        g.studio?.name?.let { list += DetailItem("STUDIO", it) }
        g.date?.let { list += DetailItem("DATE", it) }
        g.rating100?.let { list += DetailItem("RATING", "$it%") }
        return list
    }

    /**
     * iOS `ImagesView.getGalleryHeaderDetails`, minus STUDIO / PERFORMERS: the opened gallery
     * shows those as the Performers and Studio cards under the header, so the rows would repeat them.
     */
    fun gallery(g: Gallery, totalImages: Int): List<DetailItem> {
        val list = mutableListOf<DetailItem>()
        val count = maxOf(totalImages, g.imageCount ?: 0)
        if (count > 0) list += DetailItem("IMAGES", "$count")
        g.date?.takeIf { it.isNotEmpty() }?.let { list += DetailItem("DATE", it) }
        g.rating100?.let { list += DetailItem("RATING", "$it%") }
        if (g.organized == true) list += DetailItem("ORGANIZED", "Yes")
        return list
    }

    /** iOS `PerformerCardView.ageText` — whole years from `yyyy-MM-dd`, only 1…119. */
    fun age(birthdate: String?, today: LocalDate = LocalDate.now()): String? {
        if (birthdate.isNullOrEmpty()) return null
        val date = try { LocalDate.parse(birthdate) } catch (e: DateTimeParseException) { return null }
        val years = Period.between(date, today).years
        return if (years in 1..119) "$years" else null
    }

    /** Swift prints whole doubles as `16.0`; keep that so the header reads identically. */
    fun formatSwiftDouble(value: Double): String = value.toString()

    /** iOS `StashImage.fileExtension` — basename, then path, then `paths.image` (upper-cased). */
    fun fileExtension(image: StashImage): String? {
        val file = image.visualFiles?.firstOrNull()
        extensionOf(file?.basename)?.let { return it }
        extensionOf(file?.path)?.let { return it }
        extensionOf(image.paths?.image?.substringBefore('?'))?.let { return it }
        return null
    }

    private fun extensionOf(name: String?): String? {
        if (name.isNullOrEmpty()) return null
        val last = name.substringAfterLast('/')
        val dot = last.lastIndexOf('.')
        if (dot <= 0 || dot == last.lastIndex) return null
        return last.substring(dot + 1).uppercase()
    }

    /** iOS `StashImage.isAnimated` (GIF / WebP). */
    fun isAnimated(image: StashImage): Boolean = fileExtension(image).let { it == "GIF" || it == "WEBP" }
}

/** Parsing rules of the iOS edit sheets (`save()`), kept pure for tests. */
object EditParsing {
    fun int(text: String): Int? = text.trim().toIntOrNull()

    /** iOS: `Double(text.replacingOccurrences(of: ",", with: "."))`. */
    fun decimal(text: String): Double? = text.trim().replace(",", ".").toDoubleOrNull()

    /** iOS: `Int(text).map { min(100, max(0, $0)) }`. */
    fun rating(text: String): Int? = int(text)?.coerceIn(0, 100)

    /** iOS: split on ",", trim, drop empties; empty list → nil. */
    fun aliases(text: String): List<String>? = text.split(",").map { it.trim() }.filter { it.isNotEmpty() }.ifEmpty { null }
}
