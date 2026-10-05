package de.letzgo.stashy.data

import kotlin.math.abs

/**
 * iOS: `StashImageGroupMode` — how the 1/row image feeds bundle images into sets. Raw values are
 * the iOS ones (`stashline_group_mode`).
 */
enum class ImageGroupMode(val raw: String, val displayName: String) {
    Off("off", "Off"),
    Gallery("gallery", "By gallery"),
    GallerySession("gallerySession", "By gallery + session");

    companion object {
        fun from(raw: String?): ImageGroupMode = entries.firstOrNull { it.raw == raw } ?: GallerySession
    }
}

/** One post of the 1/row image feed: a single image or a set (iOS `(id: String, images: [StashImage])`). */
data class ImageFeedPost(val id: String, val images: List<StashImage>)

/**
 * iOS: `StashImageSetGrouping` (StashImageDateSort.swift) — set grouping for the 1/row image feeds
 * (Feeds › Pics, Images at 1/row, detail image lists). Pure, unit-tested, mirrored 1:1 in Swift.
 *
 * Only **consecutive** images (API order) can form a set: the list is walked once and an image
 * joins the current (last) post when [canJoin] allows it, otherwise it starts a new post. A new
 * page can therefore only extend the last post; everything above stays as it was.
 */
object ImageSetGrouping {
    const val MAX_SET_SIZE = 30
    const val MODE_KEY = "stashline_group_mode"
    const val GAP_KEY = "stashline_group_gap_minutes"
    const val LEGACY_SETS_KEY = "stashline_group_sets"
    val gapOptions = listOf(2, 10, 60)
    const val DEFAULT_GAP_MINUTES = 10

    private val stashSession = Regex("""(?<=_-_).+(?=_\d+$)""")
    private val importerSession = Regex("""\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?=_\d+$)""")
    private val groupingSorts = setOf("dateAsc", "dateDesc", "createdAtAsc", "createdAtDesc")

    // MARK: settings

    /** First read of `stashline_group_mode`: the old on/off switch decides (missing = on). */
    fun migratedMode(legacyGroupSets: Boolean?): ImageGroupMode =
        if (legacyGroupSets == false) ImageGroupMode.Off else ImageGroupMode.GallerySession

    /** Only 2 / 10 / 60 are offered; anything else falls back to 10. */
    fun normalizedGap(minutes: Int?): Int = minutes?.takeIf { it in gapOptions } ?: DEFAULT_GAP_MINUTES

    // MARK: filename timestamps

    /** iOS `filenameStem(from:)` — last path component without extension and query. */
    fun filenameStem(path: String): String {
        val raw = path.substringBefore('?')
        val last = raw.trimEnd('/').substringAfterLast('/')
        val dot = last.lastIndexOf('.')
        return if (dot > 0) last.substring(0, dot) else last
    }

    /** iOS `parseSessionFromFilename(_:)` → `yyyy-MM-dd_HH-mm-ss`. */
    fun parseSessionFromFilename(filename: String): String? {
        // Stash: "042_-_2026-01-12_12-39-43_0" -> "2026-01-12_12-39-43"
        if (filename.contains("_-_")) stashSession.find(filename)?.let { return it.value }
        // Importer: "wolke11-2026-06-24_07-42-44_0" -> "2026-06-24_07-42-44"
        return importerSession.find(filename)?.value
    }

    /** iOS `filenameCandidates(for:)`. */
    fun filenameCandidates(image: StashImage): List<String> = buildList {
        image.visualFiles?.forEach { f ->
            f.basename?.takeIf { it.isNotEmpty() }?.let { add(it) }
            f.path?.takeIf { it.isNotEmpty() }?.let { add(it) }
        }
        image.paths?.image?.takeIf { it.isNotEmpty() }?.let { add(it) }
        image.title?.takeIf { it.isNotEmpty() }?.let { add(it) }
    }

    // MARK: timestamps (epoch seconds, hand-parsed so Swift and Kotlin agree exactly)

    /**
     * `created_at` → epoch seconds. Accepts `2026-06-24T07:42:44Z`, `…+02:00`, `…+0200`,
     * fractional seconds and `2026-06-24 07:42:44 +0000`; no zone = UTC. Anything else → null.
     */
    fun parseCreatedAt(raw: String?): Long? {
        val s = raw?.trim() ?: return null
        val base = parseFields(s, dateSep = '-', mid = setOf('T', ' '), timeSep = ':') ?: return null
        var i = 19
        if (i < s.length && s[i] == '.') {
            i++
            while (i < s.length && s[i].isAsciiDigit()) i++
        }
        val zone = s.substring(i).trim()
        val offset = when {
            zone.isEmpty() || zone == "Z" || zone == "z" -> 0L
            else -> parseOffset(zone) ?: return null
        }
        return base - offset
    }

    /** Filename session `yyyy-MM-dd_HH-mm-ss` → epoch seconds, read as UTC. */
    fun parseFilenameSession(key: String): Long? =
        if (key.length != 19) null else parseFields(key, dateSep = '-', mid = setOf('_'), timeSep = '-')

    /** `created_at`, else a timestamp in the file name; null = none (the image never joins by time). */
    fun timestamp(image: StashImage): Long? {
        parseCreatedAt(image.createdAt)?.let { return it }
        for (raw in filenameCandidates(image)) {
            val key = parseSessionFromFilename(filenameStem(raw)) ?: continue
            parseFilenameSession(key)?.let { return it }
        }
        return null
    }

    private fun Char.isAsciiDigit() = this in '0'..'9'

    private fun num(s: String, from: Int, len: Int): Int? {
        var v = 0
        for (k in from until from + len) {
            val c = s.getOrNull(k) ?: return null
            if (!c.isAsciiDigit()) return null
            v = v * 10 + (c - '0')
        }
        return v
    }

    /** Fixed layout `yyyy?MM?dd?HH?mm?ss` (first 19 characters) → epoch seconds (UTC). */
    private fun parseFields(s: String, dateSep: Char, mid: Set<Char>, timeSep: Char): Long? {
        if (s.length < 19) return null
        if (s[4] != dateSep || s[7] != dateSep || s[10] !in mid || s[13] != timeSep || s[16] != timeSep) return null
        val y = num(s, 0, 4) ?: return null
        val mo = num(s, 5, 2) ?: return null
        val d = num(s, 8, 2) ?: return null
        val h = num(s, 11, 2) ?: return null
        val mi = num(s, 14, 2) ?: return null
        val se = num(s, 17, 2) ?: return null
        if (mo !in 1..12 || d !in 1..31 || h > 23 || mi > 59 || se > 60) return null
        return daysFromCivil(y, mo, d) * 86_400L + h * 3_600L + mi * 60L + se
    }

    /** `+02:00` / `-0530` → seconds east of UTC. */
    private fun parseOffset(z: String): Long? {
        val sign = when (z.firstOrNull()) { '+' -> 1L; '-' -> -1L; else -> return null }
        val body = z.substring(1).replace(":", "")
        if (body.length != 4) return null
        val h = num(body, 0, 2) ?: return null
        val m = num(body, 2, 2) ?: return null
        if (h > 23 || m > 59) return null
        return sign * (h * 3_600L + m * 60L)
    }

    /** Howard Hinnant's days_from_civil (proleptic Gregorian). */
    private fun daysFromCivil(year: Int, month: Int, day: Int): Long {
        val y = (if (month <= 2) year - 1 else year).toLong()
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val mp = (month + if (month > 2) -3 else 9).toLong()
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    // MARK: grouping

    /** iOS `supportsGrouping(for:)` — only the date / created sorts keep a set's images adjacent. */
    fun supportsGrouping(sortRaw: String?): Boolean = sortRaw in groupingSorts

    private fun galleryIds(image: StashImage): Set<String> = image.galleries.orEmpty().map { it.id }.toSet()
    private fun performerIds(image: StashImage): Set<String> = image.performers.orEmpty().map { it.id }.toSet()
    private fun studioId(image: StashImage): String = image.studio?.id.orEmpty()

    /**
     * Whether [image] may join [post] (non-empty, API order):
     * - at most [MAX_SET_SIZE] images; a clip and a photo never share a set;
     * - galleries first, against the post's last image: both have galleries → join when they
     *   share one; exactly one has galleries → no join;
     * - [ImageGroupMode.GallerySession], both without galleries: performers equal to the post's
     *   first image and non-empty, or same non-empty studio with equal performers — and the
     *   `created_at` gap to the post's last image ≤ [gapMinutes]. Untagged loose images never join.
     */
    fun canJoin(post: List<StashImage>, image: StashImage, mode: ImageGroupMode, gapMinutes: Int): Boolean {
        if (mode == ImageGroupMode.Off) return false
        val first = post.firstOrNull() ?: return false
        val last = post.last()
        if (post.size >= MAX_SET_SIZE) return false
        if (first.isVideo != image.isVideo) return false

        val lastGalleries = galleryIds(last)
        val galleries = galleryIds(image)
        if (lastGalleries.isNotEmpty() && galleries.isNotEmpty()) return lastGalleries.any { it in galleries }
        if (lastGalleries.isNotEmpty() || galleries.isNotEmpty()) return false
        if (mode != ImageGroupMode.GallerySession) return false

        val firstPerformers = performerIds(first)
        val performers = performerIds(image)
        if (firstPerformers != performers) return false
        val firstStudio = studioId(first)
        val sameStudio = firstStudio.isNotEmpty() && firstStudio == studioId(image)
        if (performers.isEmpty() && !sameStudio) return false

        val t0 = timestamp(last) ?: return false
        val t1 = timestamp(image) ?: return false
        return abs(t1 - t0) <= gapMinutes * 60L
    }

    /**
     * Walks [images] in API order and builds the feed posts. Ids are `single|<imageId>` /
     * `set|<firstImageId>`, so a set keeps its id while a later page extends it.
     */
    fun buildPosts(
        images: List<StashImage>,
        sortRaw: String?,
        mode: ImageGroupMode = ImageGroupMode.GallerySession,
        gapMinutes: Int = DEFAULT_GAP_MINUTES,
    ): List<ImageFeedPost> {
        if (mode == ImageGroupMode.Off || !supportsGrouping(sortRaw)) {
            return images.map { ImageFeedPost("single|${it.id}", listOf(it)) }
        }
        val groups = ArrayList<MutableList<StashImage>>()
        for (image in images) {
            val current = groups.lastOrNull()
            if (current != null && canJoin(current, image, mode, gapMinutes)) current.add(image)
            else groups.add(mutableListOf(image))
        }
        return groups.map { g ->
            val id = if (g.size == 1) "single|${g[0].id}" else "set|${g[0].id}"
            ImageFeedPost(id, g.toList())
        }
    }
}
