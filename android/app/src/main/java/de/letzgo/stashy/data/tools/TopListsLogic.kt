package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToLong

// Pure ranking / paging / formatting logic of the Charts tool (iOS: `TopListsToolsView.swift`).
// Free of Android APIs so plain JUnit tests can run it.

/** iOS: `topListPageSize`. */
const val TOP_LIST_PAGE_SIZE = 25

/** Label + server sort field of one ranking (iOS: `TopListsMetricLabel` + `sort`). All rankings sort DESC. */
interface TopListsMetric {
    val label: String
    /** GraphQL `FindFilterType.sort` field (iOS: `<X>SortOption.sortField`). */
    val sortField: String
    val direction: String get() = "DESC"
}

/** iOS: `SceneTopMetric` (raw values identical). */
enum class TopListsSceneMetric(val raw: String, override val label: String, override val sortField: String) : TopListsMetric {
    Views("views", "Views", "play_count"),
    OCount("oCount", "O-Count", "o_counter"),
    WatchTime("watchTime", "Watch Time", "play_duration"),
    Rating("rating", "Rating", "rating"),
}

/** iOS: `PerformerTopMetric`. */
enum class TopListsPerformerMetric(val raw: String, override val label: String, override val sortField: String) : TopListsMetric {
    OCount("oCount", "O-Count", "o_counter"),
    Scenes("scenes", "Scenes", "scenes_count"),
    Rating("rating", "Rating", "rating"),
    Images("images", "Images", "images_count"),
    Galleries("galleries", "Galleries", "galleries_count"),
}

/** iOS: `StudioTopMetric`. */
enum class TopListsStudioMetric(val raw: String, override val label: String, override val sortField: String) : TopListsMetric {
    Scenes("scenes", "Scenes", "scenes_count"),
    Galleries("galleries", "Galleries", "galleries_count"),
    Rating("rating", "Rating", "rating"),
    Images("images", "Images", "images_count"),
}

/** iOS: `TagTopMetric`. */
enum class TopListsTagMetric(val raw: String, override val label: String, override val sortField: String) : TopListsMetric {
    Scenes("scenes", "Scenes", "scenes_count"),
    Images("images", "Images", "images_count"),
    Galleries("galleries", "Galleries", "galleries_count"),
    Markers("markers", "Markers", "scene_markers_count"),
}

/** iOS: `TopListPage` — paging cursor of one ranking. */
data class TopListPage(val nextPage: Int, val hasMore: Boolean) {
    /** iOS: `loadMore…` — cursor after appending a further page. */
    fun afterLoadMore(incomingCount: Int, listCount: Int, total: Int): TopListPage =
        TopListPage(nextPage + 1, incomingCount > 0 && listCount < total)

    companion object {
        /** iOS: `afterFirstPage(count:total:)`. */
        fun afterFirstPage(count: Int, total: Int) = TopListPage(2, count > 0 && count < total)
        /** iOS: `exhausted` — first page failed. */
        val exhausted = TopListPage(1, false)
    }
}

object TopListsLogic {
    /** iOS: `appendUnique(_:onto:)` — appends items whose id is not in [list] yet, keeping order. */
    fun <T> appendUnique(list: List<T>, incoming: List<T>, id: (T) -> String): List<T> {
        val seen = list.mapTo(HashSet()) { id(it) }
        val out = list.toMutableList()
        for (item in incoming) if (seen.add(id(item))) out += item
        return out
    }

    /** iOS: `TopListsFormat.count` — decimal grouping in the current locale. */
    fun formatCount(value: Int, locale: Locale = Locale.getDefault()): String =
        NumberFormat.getIntegerInstance(locale).format(value)

    /** iOS: `TopListsFormat.duration` — `2h 5m` / `42m`. */
    fun formatDuration(seconds: Double): String {
        val total = seconds.roundToLong()
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        return if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
    }

    /** Rating column value (`—` when unrated). */
    fun formatRating(rating100: Int?): String = rating100?.toString() ?: "—"

    // MARK: Live patches (iOS: notification observers of `TopListsViewModel`)

    /** Replaces the O-count of scene [sceneId]; unchanged list when absent or equal. */
    fun withSceneOCounter(list: List<Scene>, sceneId: String, oCounter: Int): List<Scene> {
        val idx = list.indexOfFirst { it.id == sceneId }
        if (idx < 0 || list[idx].oCounter == oCounter) return list
        return list.toMutableList().also { it[idx] = it[idx].copy(oCounter = oCounter) }
    }

    /** Adds [delta] to the O-count of every performer in [ids]. */
    fun bumpPerformersOCounter(list: List<Performer>, ids: Collection<String>, delta: Int): List<Performer> {
        if (delta == 0 || ids.isEmpty()) return list
        return list.map { if (it.id in ids) it.copy(oCounter = (it.oCounter ?: 0) + delta) else it }
    }

    /** Stable sort, highest O-count first (iOS re-sorts the O-count ranking after a patch). */
    fun sortScenesByOCounter(list: List<Scene>): List<Scene> = list.sortedByDescending { it.oCounter ?: 0 }
    fun sortPerformersByOCounter(list: List<Performer>): List<Performer> = list.sortedByDescending { it.oCounter ?: 0 }
    fun sortScenesByRating(list: List<Scene>): List<Scene> = list.sortedByDescending { it.rating100 ?: 0 }

    /** Replaces the cover cache-buster of scene [sceneId]. */
    fun withSceneUpdatedAt(list: List<Scene>, sceneId: String, updatedAt: String): List<Scene> {
        val idx = list.indexOfFirst { it.id == sceneId }
        if (idx < 0 || list[idx].updatedAt == updatedAt) return list
        return list.toMutableList().also { it[idx] = it[idx].copy(updatedAt = updatedAt) }
    }

    /** iOS: `Scene.mergingListMetadata(from:)` — merges an edited scene into a list item. */
    fun mergeSceneListMetadata(old: Scene, new: Scene): Scene {
        val mergedFiles = when {
            new.files?.any { (it.duration ?: 0.0) > 0 } == true -> new.files
            old.files?.any { (it.duration ?: 0.0) > 0 } == true -> old.files
            else -> new.files ?: old.files
        }
        return old.copy(
            title = new.title ?: old.title,
            details = new.details ?: old.details,
            director = new.director ?: old.director,
            date = new.date?.takeIf { it.isNotEmpty() } ?: old.date,
            duration = new.duration ?: old.duration ?: mergedFiles?.mapNotNull { it.duration }?.maxOrNull(),
            studio = new.studio ?: old.studio,
            performers = if (new.performers.isEmpty()) old.performers else new.performers,
            files = mergedFiles,
            tags = new.tags ?: old.tags,
            galleries = new.galleries ?: old.galleries,
            groups = new.groups ?: old.groups,
            organized = new.organized ?: old.organized,
            rating100 = new.rating100 ?: old.rating100,
            updatedAt = newerUpdatedAt(new.updatedAt, old.updatedAt),
            stashIds = new.stashIds ?: old.stashIds,
        )
    }

    /** iOS: `Scene.newerUpdatedAt` — ISO-8601 timestamps compare lexicographically. */
    fun newerUpdatedAt(a: String?, b: String?): String? = when {
        a == null -> b
        b == null -> a
        else -> if (a >= b) a else b
    }

    /** Merges a patch into a list; returns the same list when [sceneId] is absent. */
    fun mergeScene(list: List<Scene>, scene: Scene): List<Scene> {
        val idx = list.indexOfFirst { it.id == scene.id }
        if (idx < 0) return list
        return list.toMutableList().also { it[idx] = mergeSceneListMetadata(it[idx], scene) }
    }
}
