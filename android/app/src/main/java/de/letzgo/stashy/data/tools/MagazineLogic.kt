package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.StashImage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import java.time.Instant

/** iOS: `MagazineReadingStore.Entry` — [page] is 1-based; on a spread its first page. */
@Serializable
data class MagazineEntry(val page: Int, val readAt: String, val isSynced: Boolean)

/** iOS: `GalleryReaderInfo.Chapter` — [imageIndex] is the 1-based page the chapter starts on. */
@Serializable
data class MagazineChapter(val id: String, val title: String = "", @SerialName("image_index") val imageIndex: Int = 1)

/** iOS: `GalleryReaderInfo`. */
@Serializable
data class MagazineReaderInfo(val chapters: List<MagazineChapter> = emptyList(), val tags: List<IdName> = emptyList())

/** Pure Magazin logic (iOS `MagazinePageOrder`, `MagazineReadingStore`, `MagazineToolsView`). */
object MagazineLogic {
    /** iOS: `MagazineReadingStore.pageField` / `readAtField` — shared across both apps. */
    const val PAGE_FIELD = "stashy_read_page"
    const val READ_AT_FIELD = "stashy_read_at"

    /** iOS: `localizedStandardCompare` — numeric runs by value (`2.jpg` before `10.jpg`), case-insensitive. */
    val naturalOrder: Comparator<String> = Comparator { a, b ->
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            if (a[i].isDigit() && b[j].isDigit()) {
                val endA = digitRunEnd(a, i)
                val endB = digitRunEnd(b, j)
                val numA = a.substring(i, endA).trimStart('0')
                val numB = b.substring(j, endB).trimStart('0')
                if (numA.length != numB.length) return@Comparator numA.length.compareTo(numB.length)
                val digits = numA.compareTo(numB)
                if (digits != 0) return@Comparator digits
                i = endA
                j = endB
            } else {
                val chars = a[i].lowercaseChar().compareTo(b[j].lowercaseChar())
                if (chars != 0) return@Comparator chars
                i++
                j++
            }
        }
        (a.length - i).compareTo(b.length - j)
    }

    private fun digitRunEnd(text: String, start: Int): Int {
        var end = start
        while (end < text.length && text[end].isDigit()) end++
        return end
    }

    /** iOS: `MagazinePageOrder.sorted` — videos left out, file path → name → title → id. */
    fun pages(images: List<StashImage>): List<StashImage> {
        val byKey = compareBy<Pair<StashImage, String>, String>(naturalOrder) { it.second }.thenBy { it.first.id }
        return images.filterNot { it.isVideo }
            .map { it to sortKey(it) }
            .sortedWith(byKey)
            .map { it.first }
    }

    private fun sortKey(image: StashImage): String {
        val file = image.visualFiles?.firstOrNull()
        return file?.path ?: file?.basename ?: image.title ?: image.id
    }

    fun spreadCount(pageCount: Int): Int = (pageCount + 1) / 2

    /** The last page on screen: a chapter can start on a spread's second page. */
    fun lastVisiblePage(spreadIndex: Int, pageCount: Int): Int = minOf(spreadIndex * 2 + 1, pageCount - 1)

    fun currentChapter(chapters: List<MagazineChapter>, lastVisiblePage: Int): MagazineChapter? =
        chapters.sortedBy { it.imageIndex }.lastOrNull { it.imageIndex - 1 <= lastVisiblePage }

    /** 0-based page of a chapter; it can point past the pages kept here (videos are left out). */
    fun chapterPage(chapter: MagazineChapter, pageCount: Int): Int =
        (chapter.imageIndex - 1).coerceIn(0, maxOf(pageCount - 1, 0))

    /** 0-based page the input stands for; null while it is no page of this gallery. */
    fun enteredPage(input: String, pageCount: Int): Int? =
        input.trim().toIntOrNull()?.takeIf { it in 1..pageCount }?.minus(1)

    /** Three covers per row, more only where three would turn into posters (tablets). */
    fun coverColumns(widthDp: Float): Int = maxOf(3, ((widthDp + 12f) / (220f + 12f)).toInt())

    /** iOS: `"%g / 5"` of a 0–100 rating. */
    fun ratingLabel(rating100: Int): String {
        val stars = rating100 / 20.0
        return (if (stars % 1.0 == 0.0) stars.toInt().toString() else stars.toString()) + " / 5"
    }

    /** Page 1 counts as not started; the last spread (which can end one page later) fills the bar. */
    fun readFraction(page: Int?, total: Int?): Float? {
        if (page == null || page <= 1 || total == null || total <= 0) return null
        return if (page + 1 >= total) 1f else page.toFloat() / total
    }

    /** iOS: `MagazineReadingStore.entry(from:)`. */
    fun entryFromFields(fields: JsonObject?): MagazineEntry? {
        val rawPage = fields?.get(PAGE_FIELD) as? JsonPrimitive ?: return null
        val page = rawPage.doubleOrNull?.toInt() ?: return null
        val readAt = (fields[READ_AT_FIELD] as? JsonPrimitive)?.contentOrNull ?: return null
        if (instantOrNull(readAt) == null) return null
        return MagazineEntry(page, readAt, isSynced = true)
    }

    /** The newer `readAt` wins; equal keeps the server's. */
    fun remoteWins(remote: MagazineEntry, local: MagazineEntry?): Boolean {
        val localAt = local?.let { instantOrNull(it.readAt) } ?: return true
        val remoteAt = instantOrNull(remote.readAt) ?: return false
        return remoteAt >= localAt
    }

    private fun instantOrNull(raw: String): Instant? = runCatching { Instant.parse(raw) }.getOrNull()
}
