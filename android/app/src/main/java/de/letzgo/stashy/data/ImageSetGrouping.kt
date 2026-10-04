package de.letzgo.stashy.data

/**
 * iOS: `StashImageSessionPrecision` — how exactly the `created` timestamp has to match for two
 * images to land in one set. Raw values are the iOS ones (`stashline_group_session_precision`).
 */
enum class ImageSessionPrecision(val raw: String, val displayName: String, val keyLength: Int) {
    Day("day", "Same day", 10),       // 2026-01-12
    Hour("hour", "Same hour", 13),    // 2026-01-12_12
    Minute("minute", "Same minute", 16); // 2026-01-12_12-39

    companion object {
        fun from(raw: String?): ImageSessionPrecision = entries.firstOrNull { it.raw == raw } ?: Hour
    }
}

/** One post of the 1/row image feed: a single image or a set (iOS `(id: String, images: [StashImage])`). */
data class ImageFeedPost(val id: String, val images: List<StashImage>)

/**
 * iOS: `StashImageFilenameKeys` (StashImageDateSort.swift) — session keys and set grouping for
 * the 1/row image feed (Feeds › Pics, Images at 1/row). Pure, unit-tested. Feed order always
 * trusts the Stash API; grouping never reorders across posts.
 */
object ImageSetGrouping {
    private val stashSession = Regex("""(?<=_-_).+(?=_\d+$)""")
    private val importerSession = Regex("""\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?=_\d+$)""")
    private val groupingSorts = setOf("dateAsc", "dateDesc", "createdAtAsc", "createdAtDesc", "titleAsc", "titleDesc")

    /** iOS `filenameStem(from:)` — last path component without extension and query. */
    fun filenameStem(path: String): String {
        val raw = path.substringBefore('?')
        val last = raw.trimEnd('/').substringAfterLast('/')
        val dot = last.lastIndexOf('.')
        return if (dot > 0) last.substring(0, dot) else last
    }

    /** iOS `parseSessionFromFilename(_:)`. */
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

    /** iOS `createdTimestampKey(for:)`: `2026-06-24T07:42:44Z` → `2026-06-24_07-42-44`. */
    fun createdTimestampKey(image: StashImage): String? {
        val raw = image.createdAt?.trim() ?: return null
        if (raw.length < 19) return null
        val day = raw.take(10)
        if (day.length != 10 || day.getOrNull(4) != '-') return null
        val time = raw.substring(11).take(8).replace(':', '-')
        if (time.length != 8) return null
        return "${day}_$time"
    }

    /**
     * iOS `sessionKey(for:cache:precision:)` — the full timestamp is cached, so a precision change
     * needs no cache reset. Empty string = no timestamp.
     */
    fun sessionKey(image: StashImage, cache: MutableMap<String, String>, precision: ImageSessionPrecision = ImageSessionPrecision.Hour): String {
        cache[image.id]?.let { return it.take(precision.keyLength) }
        createdTimestampKey(image)?.let { cache[image.id] = it; return it.take(precision.keyLength) }
        for (raw in filenameCandidates(image)) {
            parseSessionFromFilename(filenameStem(raw))?.let { cache[image.id] = it; return it.take(precision.keyLength) }
        }
        cache[image.id] = ""
        return ""
    }

    /** iOS `createdDayKey(for:)` — `date`, else the `created_at` day. */
    fun createdDayKey(image: StashImage): String {
        image.date?.takeIf { it.isNotEmpty() }?.let { return it.take(10) }
        image.createdAt?.takeIf { it.length >= 10 }?.let { return it.take(10) }
        return ""
    }

    private fun performerIds(image: StashImage): Set<String> = image.performers.orEmpty().map { it.id }.toSet()
    private fun performerKey(image: StashImage): String = performerIds(image).sorted().joinToString(",")
    private fun galleryKey(image: StashImage): String = image.galleries.orEmpty().map { it.id }.sorted().joinToString(",")

    /** iOS `performersCompatible` — equal or subset performer sets; empty only matches empty. */
    fun performersCompatible(a: Set<String>, b: Set<String>): Boolean {
        if (a == b) return true
        if (a.isEmpty() || b.isEmpty()) return a.isEmpty() && b.isEmpty()
        return b.containsAll(a) || a.containsAll(b)
    }

    /** iOS `supportsGrouping(for:)` — only date / created / title sorts keep sets together. */
    fun supportsGrouping(sortRaw: String?): Boolean = sortRaw in groupingSorts

    /**
     * iOS `buildPosts(from:sort:precision:groupEnabled:sessionCache:)`: two images share a post
     * when they were added in the same window **and** belong together by their metadata (same
     * galleries, compatible performers). Images without a timestamp fall back to the same day
     * plus the same metadata rules. Post and frame order follow API order; post ids are stable
     * (first image of the set) so a set keeps its identity while later pages add frames.
     */
    fun buildPosts(
        images: List<StashImage>,
        sortRaw: String?,
        precision: ImageSessionPrecision = ImageSessionPrecision.Hour,
        groupEnabled: Boolean = true,
        sessionCache: MutableMap<String, String> = HashMap(),
    ): List<ImageFeedPost> {
        if (!groupEnabled || !supportsGrouping(sortRaw)) return images.map { ImageFeedPost("single|${it.id}", listOf(it)) }

        val n = images.size
        val sessions = images.map { sessionKey(it, sessionCache, precision) }
        val days = images.map { createdDayKey(it) }
        val galleries = images.map { galleryKey(it) }
        val performerSets = images.map { performerIds(it) }

        val parent = IntArray(n) { it }
        fun find(x: Int): Int {
            var i = x
            while (parent[i] != i) { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        fun union(a: Int, b: Int) {
            val ra = find(a); val rb = find(b)
            if (ra != rb) parent[rb] = ra
        }

        for (i in 0 until n) {
            for (j in i + 1 until n) {
                // Metadata first: it holds for every pair, whatever the timestamps say.
                if (galleries[i] != galleries[j] || !performersCompatible(performerSets[i], performerSets[j])) continue
                val sharesSession = sessions[i].isNotEmpty() && sessions[i] == sessions[j]
                // No timestamp on either side: the metadata alone carries the set, on one day.
                val sharesDay = sessions[i].isEmpty() && sessions[j].isEmpty() &&
                    days[i].isNotEmpty() && days[i] == days[j] &&
                    (performerSets[i].isNotEmpty() || galleries[i].isNotEmpty())
                if (sharesSession || sharesDay) union(i, j)
            }
        }

        val members = LinkedHashMap<Int, MutableList<Int>>()
        for (i in 0 until n) members.getOrPut(find(i)) { mutableListOf() }.add(i)

        return members.values.map { indices ->
            val seed = indices.first()
            val image = images[seed]
            val key = if (sessions[seed].isEmpty()) "day|${days[seed]}" else "session|${sessions[seed]}"
            val id = if (indices.size == 1) "single|${image.id}" else "set|$key|${performerKey(image)}|${galleries[seed]}"
            ImageFeedPost(id, indices.map { images[it] })
        }
    }
}
