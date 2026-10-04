package de.letzgo.stashy.tv

import de.letzgo.stashy.data.FilterMode
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Pure logic of the Android TV surface (no Compose, no Android), kept here so it can be unit
 * tested. Each piece names its tvOS counterpart.
 */

/**
 * iOS: `TVGridSpec` — fixed card width, column count from the width the container reports
 * (the sidebar takes some of it), never more than [maxColumns].
 */
data class TvGridSpec(
    val columnWidth: Float,
    val spacing: Float,
    val maxColumns: Int,
    val minColumns: Int = 1,
    val horizontalPadding: Float = 0f,
) {
    fun columnCount(availableWidth: Float): Int {
        // +spacing: n columns only have n-1 gaps.
        val usable = availableWidth - 2 * horizontalPadding + spacing
        val fitting = floor(usable / (columnWidth + spacing)).toInt()
        return fitting.coerceAtMost(maxColumns).coerceAtLeast(minColumns)
    }

    companion object {
        /** tvOS points → Android TV dp (1920 pt ≙ 960 dp). */
        const val PT = 0.5f
        /** Scene cards — catalog and detail pages (410 pt, max 4, min 2). */
        val scenes = TvGridSpec(410 * PT, 40 * PT, 4, 2)
        /** Image cards in the Images catalog and the gallery detail (300 pt, max 5, min 3). */
        val images = TvGridSpec(300 * PT, 30 * PT, 5, 3)
    }
}

/**
 * iOS: `stepSeconds()` of `TVAetherPlayerContent` — repeated Left/Right presses within 0.5 s
 * accelerate 10 → 30 → 60 s; from the third quick press on, the player switches to a
 * preview-first scrub that only commits on Select or after 1 s idle.
 */
class TvSeekAccelerator(private val window: Long = 500) {
    var streak = 0; private set
    private var lastMove = Long.MIN_VALUE / 2

    /** Seconds for a press at [nowMs]. [base] is the first rung (10 s on tvOS). */
    fun step(nowMs: Long, base: Double = 10.0): Double {
        streak = if (nowMs - lastMove < window) streak + 1 else 1
        lastMove = nowMs
        return when {
            streak >= 6 -> 60.0
            streak >= 3 -> 30.0
            else -> base
        }
    }

    /** True once the streak asks for scrub mode (third quick press). */
    val wantsScrub: Boolean get() = streak >= 3

    fun reset() { streak = 0 }
}

/**
 * iOS: `TVRemoteHoldRecognizer` — tap vs. hold of the Up/Down clicks. Android reports a held
 * key as repeated KEY_DOWNs; the hold fires once the key has been down for [thresholdMs]
 * (0.7 s like tvOS), a release before that is a tap. Taps act on release, so a hold can complete.
 */
class TvHoldTracker(private val thresholdMs: Long = 700) {
    enum class Result { None, Hold, Tap }

    private var downAt: Long? = null
    private var fired = false

    val isPressing: Boolean get() = downAt != null

    fun keyDown(nowMs: Long, repeatCount: Int): Result {
        if (repeatCount == 0 || downAt == null) {
            downAt = nowMs
            fired = false
            return Result.None
        }
        val start = downAt ?: return Result.None
        if (!fired && nowMs - start >= thresholdMs) {
            fired = true
            return Result.Hold
        }
        return Result.None
    }

    fun keyUp(nowMs: Long): Result {
        val start = downAt ?: return Result.None
        downAt = null
        if (fired) { fired = false; return Result.None }
        // A release past the threshold without a repeat in between still counts as a hold.
        return if (nowMs - start >= thresholdMs) Result.Hold else Result.Tap
    }

    fun cancel() { downAt = null; fired = false }
}

object TvFormat {
    /** iOS: `formatDuration` / `timeLabel` — `m:ss` or `h:mm:ss`, `--:--` when unknown. */
    fun time(seconds: Double?): String {
        if (seconds == null || !seconds.isFinite() || seconds < 0) return "--:--"
        val total = seconds.toInt()
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    /** iOS: `resolutionString(for:)` of `TVSceneDetailView`. */
    fun resolution(height: Int?): String? = when {
        height == null -> null
        height >= 2160 -> "4K"
        height >= 1080 -> "HD"
        height >= 720 -> "720p"
        else -> "SD"
    }

    /** `rating100` → stars 0…5 (rounded). */
    fun stars(rating100: Int?): Int = if (rating100 == null || rating100 <= 0) 0 else (rating100 / 20.0).roundToInt()

    /** iOS: `ratingLabel(for:)` — "Rate" or "3/5". */
    fun ratingLabel(rating100: Int?): String = stars(rating100).let { if (it == 0) "Rate" else "$it/5" }

    /** Card badge rating like tvOS: `rating100 / 20` with one decimal. */
    fun ratingValue(rating100: Int): String = String.format(java.util.Locale.US, "%.1f", rating100 / 20.0)

    /** Resume progress 0…1, null when nothing to show. */
    fun progress(resume: Double?, duration: Double?): Float? {
        if (resume == null || duration == null || resume <= 0 || duration <= 0 || !resume.isFinite() || !duration.isFinite()) return null
        return (resume / duration).coerceIn(0.0, 1.0).toFloat()
    }
}

/**
 * iOS: `TVMarkerRailView.activeMarkerID` — the marker whose range (`seconds` up to the next
 * marker's start) holds the playhead; the last marker owns everything after it.
 * [starts] must be sorted ascending. Returns an index into [starts] or null.
 */
fun activeMarkerIndex(starts: List<Double>, currentTime: Double): Int? {
    for (i in starts.indices) {
        val upper = if (i + 1 < starts.size) starts[i + 1] else Double.MAX_VALUE
        if (currentTime >= starts[i] && currentTime < upper) return i
    }
    return null
}

/** iOS: the per-catalog sort pickers of `TVScenesView`, `TVPerformersView` … (order and labels). */
object TvSortLabels {
    val scenes = listOf(
        "random" to "Random", "dateDesc" to "Recently Released", "dateAsc" to "Oldest First",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "lastPlayedAtDesc" to "Recently Played", "lastPlayedAtAsc" to "Least Recently Played",
        "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)",
        "durationDesc" to "Longest First", "durationAsc" to "Shortest First",
        "playCountDesc" to "Most Viewed", "playCountAsc" to "Least Viewed",
        "oCounterDesc" to "O Count (High-Low)", "oCounterAsc" to "O Count (Low-High)",
        "ratingDesc" to "Highest Rated", "ratingAsc" to "Lowest Rated",
    )
    val performers = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Most Scenes", "sceneCountAsc" to "Least Scenes",
        "birthdateDesc" to "Youngest First", "birthdateAsc" to "Oldest First",
        "oCountDesc" to "O Count (High-Low)", "oCountAsc" to "O Count (Low-High)",
        "ratingDesc" to "Highest Rated", "ratingAsc" to "Lowest Rated",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )
    val studios = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Most Scenes", "sceneCountAsc" to "Least Scenes",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )
    val tags = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Most Scenes", "sceneCountAsc" to "Least Scenes",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )
    val groups = listOf(
        "random" to "Random", "nameAsc" to "Name (A-Z)", "nameDesc" to "Name (Z-A)",
        "sceneCountDesc" to "Most Scenes", "sceneCountAsc" to "Least Scenes",
        "dateDesc" to "Newest First", "dateAsc" to "Oldest First",
        "ratingDesc" to "Highest Rated", "ratingAsc" to "Lowest Rated",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )
    val galleries = listOf(
        "random" to "Random", "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)",
        "dateDesc" to "Newest First", "dateAsc" to "Oldest First",
        "imageCountDesc" to "Most Images", "imageCountAsc" to "Least Images",
        "ratingDesc" to "Highest Rated", "ratingAsc" to "Lowest Rated",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )
    val images = listOf(
        "random" to "Random", "titleAsc" to "Title (A-Z)", "titleDesc" to "Title (Z-A)",
        "dateDesc" to "Newest First", "dateAsc" to "Oldest First",
        "ratingDesc" to "Highest Rated", "ratingAsc" to "Lowest Rated",
        "createdAtDesc" to "Recently Added", "createdAtAsc" to "Oldest Added",
        "updatedAtDesc" to "Recently Updated", "updatedAtAsc" to "Least Recently Updated",
    )

    fun options(mode: FilterMode): List<Pair<String, String>> = when (mode) {
        FilterMode.Scenes -> scenes
        FilterMode.Performers -> performers
        FilterMode.Studios -> studios
        FilterMode.Tags -> tags
        FilterMode.Groups -> groups
        FilterMode.Galleries -> galleries
        FilterMode.Images -> images
        else -> emptyList()
    }

    /** tvOS fallback sort of each catalog when nothing is configured. */
    fun defaultRaw(mode: FilterMode): String = when (mode) {
        FilterMode.Scenes, FilterMode.Galleries, FilterMode.Images -> "dateDesc"
        else -> "nameAsc"
    }

    fun label(mode: FilterMode, raw: String): String = options(mode).firstOrNull { it.first == raw }?.second ?: raw
}

/**
 * iOS: `TVNavigationStore` + the selection binding of `TVMainTabView` — one back stack per
 * sidebar entry, kept outside the view tree. Generic so the rules can be tested without Compose.
 */
class TvStacks<R>(private val roots: Set<TvRootTab>) {
    private val stacks = HashMap<TvRootTab, List<R>>()

    fun stack(tab: TvRootTab): List<R> = stacks[tab].orEmpty()
    fun top(tab: TvRootTab): R? = stacks[tab]?.lastOrNull()
    fun hasPushedPages(tab: TvRootTab) = stack(tab).isNotEmpty()

    fun push(tab: TvRootTab, route: R) { stacks[tab] = stack(tab) + route }

    /** Returns the popped route, null at the root. */
    fun pop(tab: TvRootTab): R? {
        val s = stack(tab)
        if (s.isEmpty()) return null
        stacks[tab] = s.dropLast(1)
        return s.last()
    }

    fun popToRoot(tab: TvRootTab) { stacks[tab] = emptyList() }

    /** Server switch: pushed pages belong to the old server (their ids). */
    fun reset() = stacks.clear()

    /**
     * Sidebar selection. Re-selecting the active entry pops to its root; leaving Settings
     * pops its pushed pages (they are not sticky on tvOS). Returns the new selected tab.
     */
    fun select(current: TvRootTab, target: TvRootTab): TvRootTab {
        if (target == current) {
            popToRoot(target)
            return target
        }
        if (current == TvRootTab.Settings) popToRoot(TvRootTab.Settings)
        return target
    }

    /** iOS: hiding the active library section falls back to Home. */
    fun validated(current: TvRootTab, visible: Set<TvRootTab>): TvRootTab =
        if (current in visible || current in roots) current else TvRootTab.Home
}

/** iOS: `TVRootTab` — the sidebar entries. */
enum class TvRootTab(val title: String) {
    Search("Search"), Home("Home"),
    Scenes("Scenes"), Performers("Performers"), Studios("Studios"), Tags("Tags"),
    Groups("Groups"), Galleries("Galleries"), Images("Images"),
    Settings("Settings");

    val isLibrary: Boolean get() = this !in setOf(Search, Home, Settings)

    companion object {
        /** Always visible (the iOS `live` set: home, search, settings). */
        val fixed = setOf(Search, Home, Settings)
        val library = listOf(Scenes, Performers, Studios, Tags, Groups, Galleries, Images)
    }
}

/** iOS: `StashImage.isGifFile` — any of the file names / paths / title ending in `.gif`. */
val de.letzgo.stashy.data.StashImage.isGifFile: Boolean get() {
    val candidates = listOf(visualFiles?.firstOrNull()?.basename, visualFiles?.firstOrNull()?.path, paths?.image, paths?.preview, paths?.thumbnail, title)
    return candidates.any { c -> c?.substringBefore('?')?.lowercase()?.endsWith(".gif") == true }
}

/** iOS: `StashImage.performerPillText` — first performer, "+n" for the rest. */
val de.letzgo.stashy.data.StashImage.performerPillText: String? get() {
    val list = performers.orEmpty()
    val first = list.firstOrNull()?.name ?: return null
    return if (list.size > 1) "$first +${list.size - 1}" else first
}

/** iOS: `StashImage.displayTitle` — title, else the file name. */
val de.letzgo.stashy.data.StashImage.tvDisplayTitle: String? get() =
    title?.takeIf { it.isNotBlank() } ?: visualFiles?.firstOrNull()?.basename?.takeIf { it.isNotBlank() }

/** Still images only (tvOS hides GIFs and videos in every image grid and the viewer). */
fun List<de.letzgo.stashy.data.StashImage>.tvStillImages() = filter { !it.isGifFile && !it.isVideo }

/** iOS: `TVSecurityManager.sha256Hex` — PIN hash `sha256(pin + ":" + salt)`, lowercase hex. */
object TvPinHash {
    fun hash(pin: String, salt: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest("$pin:$salt".toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
