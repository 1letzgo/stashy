package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
        list += DetailItem(tr(R.string.scenes).uppercase(), "${p.sceneCount ?: 0}")
        list += DetailItem(tr(R.string.galleries).uppercase(), "${maxOf(p.galleryCount ?: 0, totalGalleries)}")
        list += DetailItem(tr(R.string.rating).uppercase(), p.rating100?.toString() ?: "—")
        if (!battleLine.isNullOrEmpty()) list += DetailItem(tr(R.string.battle).uppercase(), battleLine)
        p.gender?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.gender).uppercase(), it) }

        val gender = p.gender?.uppercase() ?: ""
        val tits = p.fakeTits?.takeIf { it.isNotEmpty() }?.let { DetailItem(tr(R.string.tits), it) }
        val penis = p.penisLength?.takeIf { it > 0 }?.let { DetailItem(tr(R.string.penis), "${formatSwiftDouble(it)} cm") }
        when {
            gender.contains("FEMALE") -> tits?.let { list += it }
            gender.contains("MALE") || gender == "MAN" -> penis?.let { list += it }
            else -> { tits?.let { list += it }; penis?.let { list += it } }
        }
        p.birthdate?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.born).uppercase(), it) }
        p.country?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.country).uppercase(), it) }
        p.ethnicity?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.ethnicity).uppercase(), it) }
        p.heightCm?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.height).uppercase(), "$it cm") }
        p.weight?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.weight).uppercase(), "$it kg") }
        p.measurements?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.measurements).uppercase(), it) }
        p.careerLength?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.career).uppercase(), it) }
        p.tattoos?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.tattoos).uppercase(), it) }
        p.piercings?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.piercings).uppercase(), it) }
        return list
    }

    /** iOS `StudioDetailView.getStudioDetails` (URL is shown on its own row). */
    fun studio(s: Studio, scenes: Int, galleries: Int, counts: de.letzgo.stashy.data.StudioDisplayCounts? = null): List<DetailItem> {
        val allCounts = counts?.takeIf { de.letzgo.stashy.data.StudioCountsStore.includeSubStudios }
        val list = mutableListOf(DetailItem(tr(R.string.scenes).uppercase(), "${allCounts?.scenes ?: scenes}"))
        (allCounts?.galleries ?: galleries).takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.galleries).uppercase(), "$it") }
        (counts?.performers ?: s.performerCount)?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.performers).uppercase(), "$it") }
        counts?.oCount?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.o_count).uppercase(), "$it") }
        s.rating100?.let { list += DetailItem(tr(R.string.rating).uppercase(), "$it%") }
        return list
    }

    /** iOS `TagDetailView.getTagDetails`. */
    fun tag(t: Tag, scenes: Int, galleries: Int): List<DetailItem> {
        val list = mutableListOf(DetailItem(tr(R.string.scenes).uppercase(), "$scenes"))
        if (galleries > 0) list += DetailItem(tr(R.string.galleries).uppercase(), "$galleries")
        t.performerCount?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.performers).uppercase(), "$it") }
        t.sceneMarkerCount?.takeIf { it > 0 }?.let { list += DetailItem(tr(R.string.markers).uppercase(), "$it") }
        t.aliases?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.aliases).uppercase(), it.joinToString(", ")) }
        t.createdAt?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.created).uppercase(), it.take(10)) }
        t.updatedAt?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.updated).uppercase(), it.take(10)) }
        return list
    }

    /** iOS `GroupDetailView.getGroupDetails`. */
    fun group(g: StashGroup, scenes: Int, galleries: Int): List<DetailItem> {
        val list = mutableListOf(DetailItem(tr(R.string.scenes).uppercase(), "$scenes"))
        if (galleries > 0) list += DetailItem(tr(R.string.galleries).uppercase(), "$galleries")
        g.studio?.name?.let { list += DetailItem(tr(R.string.studio).uppercase(), it) }
        g.date?.let { list += DetailItem(tr(R.string.date).uppercase(), it) }
        g.rating100?.let { list += DetailItem(tr(R.string.rating).uppercase(), "$it%") }
        return list
    }

    /**
     * iOS `ImagesView.getGalleryHeaderDetails`, minus STUDIO / PERFORMERS: the opened gallery
     * shows those as the Performers and Studio cards under the header, so the rows would repeat them.
     */
    fun gallery(g: Gallery, totalImages: Int): List<DetailItem> {
        val list = mutableListOf<DetailItem>()
        val count = maxOf(totalImages, g.imageCount ?: 0)
        if (count > 0) list += DetailItem(tr(R.string.images).uppercase(), "$count")
        g.date?.takeIf { it.isNotEmpty() }?.let { list += DetailItem(tr(R.string.date).uppercase(), it) }
        g.rating100?.let { list += DetailItem(tr(R.string.rating).uppercase(), "$it%") }
        if (g.organized == true) list += DetailItem(tr(R.string.organized).uppercase(), tr(R.string.yes))
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

    /**
     * iOS `EditTagSheet.addAlias`: [input] trimmed and appended unless blank, a case-insensitive
     * duplicate or equal to [name] (Stash rejects both).
     */
    fun addingAlias(aliases: List<String>, input: String, name: String): List<String> {
        val alias = input.trim()
        if (alias.isEmpty()) return aliases
        val existing = (aliases + name.trim()).map { it.lowercase() }.toSet()
        return if (alias.lowercase() in existing) aliases else aliases + alias
    }
}
