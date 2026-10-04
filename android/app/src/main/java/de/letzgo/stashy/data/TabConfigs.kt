package de.letzgo.stashy.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import java.util.UUID

// Models and pure logic of iOS `TabManager.swift` (serialisation shapes identical to the
// Swift `Codable` output, so the stored JSON reads the same on both platforms). The stateful
// part with persistence is [TabManager].

/** iOS: `AppTab` (raw values identical). */
@Serializable
enum class AppTab(val title: String) {
    @SerialName("dashboard") Dashboard("Dashboard"),
    @SerialName("studios") Studios("Studios"),
    @SerialName("performers") Performers("Performers"),
    @SerialName("scenes") Scenes("Scenes"),
    @SerialName("galleries") Galleries("Galleries"),
    @SerialName("tags") Tags("Tags"),
    @SerialName("media") Media("Media"),
    @SerialName("catalogue") Catalogue("Home"),
    @SerialName("downloads") Downloads("Downloads"),
    @SerialName("tools") Tools("Tools"),
    @SerialName("stashyPlus") StashyPlus("stashy+"),
    @SerialName("reels") Reels("Feeds"),
    @SerialName("search") Search("Search"),
    @SerialName("settings") Settings("Settings"),
    @SerialName("images") Images("Images"),
    @SerialName("groups") Groups("Groups"),
    @SerialName("markers") Markers("Markers"),
    @SerialName("stashline") Stashline("StashLine");

    /** Raw value as stored by iOS. */
    val raw: String get() = name.replaceFirstChar { it.lowercase() }.let { if (this == StashyPlus) "stashyPlus" else it }

    companion object {
        fun fromRaw(raw: String?): AppTab? = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS: `TabConfig` — `defaultSortOption` is stored under `sortOption` like on iOS. */
@Serializable
data class TabConfig(
    val id: AppTab,
    val isVisible: Boolean,
    val sortOrder: Int,
    @SerialName("sortOption") val defaultSortOption: String? = null,
    val defaultFilterId: String? = null,
    val defaultFilterName: String? = null,
    val defaultMarkerFilterId: String? = null,
    val defaultMarkerFilterName: String? = null,
    val defaultClipFilterId: String? = null,
    val defaultClipFilterName: String? = null,
    val defaultPreviewFilterId: String? = null,
    val defaultPreviewFilterName: String? = null,
)

/** iOS: `HomeRowType` (raw values and default titles identical). */
@Serializable
enum class HomeRowType(val defaultTitle: String) {
    @SerialName("lastPlayed") LastPlayed("Scenes - Last Played"),
    @SerialName("lastAdded3Min") LastAdded3Min("Scenes - Recently Added"),
    @SerialName("newest3Min") Newest3Min("Scenes - New"),
    @SerialName("mostViewed3Min") MostViewed3Min("Scenes - Most Viewed"),
    @SerialName("topCounter3Min") TopCounter3Min("Scenes - Top Counter"),
    @SerialName("topRating3Min") TopRating3Min("Scenes - Top Rated"),
    @SerialName("random") Random("Scenes - Random"),
    @SerialName("statistics") Statistics("Statistics"),
    @SerialName("newPerformers") NewPerformers("Performers - New"),
    @SerialName("performersHighestSceneCount") PerformersHighestSceneCount("Performers - Top"),
    @SerialName("newStudios") NewStudios("Studios - New"),
    @SerialName("studiosHighestSceneCount") StudiosHighestSceneCount("Studios - Top"),
    @SerialName("newGalleries") NewGalleries("Galleries - New"),
    @SerialName("recentlyUpdatedGalleries") RecentlyUpdatedGalleries("Galleries - Recently Updated"),
    @SerialName("performersHighestOCount") PerformersHighestOCount("Performers - Counter"),
    @SerialName("performersHighestRating") PerformersHighestRating("Performers - Rating"),
    @SerialName("galleriesHighestImageCount") GalleriesHighestImageCount("Galleries - Image Count"),
    @SerialName("channels") Channels("Channels");

    val isPerformerRow get() = this in setOf(NewPerformers, PerformersHighestSceneCount, PerformersHighestOCount, PerformersHighestRating)
    val isStudioRow get() = this == NewStudios || this == StudiosHighestSceneCount
    val isGalleryRow get() = this in setOf(NewGalleries, RecentlyUpdatedGalleries, GalleriesHighestImageCount)
    val isSceneRow get() = !isPerformerRow && !isStudioRow && !isGalleryRow && this != Statistics && this != Channels
}

/** iOS: `HomeRowConfig` (UUID encoded as uppercase string like Swift). */
@Serializable
data class HomeRowConfig(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val title: String,
    val isEnabled: Boolean,
    val sortOrder: Int,
    val type: HomeRowType,
)

/** iOS: `HomeChannelSourceKind`. */
@Serializable
enum class HomeChannelSourceKind(val title: String) {
    @SerialName("scenes") Scenes("Scenes"),
    @SerialName("clips") Clips("Clips");
    val raw get() = name.lowercase()
}

/** iOS: `HomeChannelItemConfig` — one saved filter in the dashboard Channels row. */
@Serializable
data class HomeChannelItemConfig(
    val filterId: String,
    val destination: HomeChannelSourceKind,
    val isEnabled: Boolean,
    val sortOrder: Int,
) {
    val id: String get() = "${destination.raw}.$filterId"
}

/** iOS: `ReelsModeType`. */
@Serializable
enum class ReelsModeType(val defaultTitle: String) {
    @SerialName("scenes") Scenes("Scenes"),
    @SerialName("markers") Markers("Markers"),
    @SerialName("clips") Clips("Clips"),
    @SerialName("previews") Previews("Previews"),
    @SerialName("pics") Pics("Pics");
}

/** iOS: `ReelsModeConfig`. */
@Serializable
data class ReelsModeConfig(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val type: ReelsModeType,
    val isEnabled: Boolean,
    val sortOrder: Int,
    val defaultSortOption: String? = null,
)

/** iOS: `DetailViewContext` (raw values are the persisted key parts). */
enum class DetailViewContext(val raw: String, val title: String) {
    Performer("performer_detail", "Performer Scenes"),
    Studio("studio_detail", "Studio Scenes"),
    Tag("tag_detail", "Tag Scenes"),
    Gallery("gallery_detail", "Gallery Images"),
    Group("group_detail", "Group Scenes");

    val settingsRowTitle: String get() = if (this == Gallery) "Images Sort" else "Scenes Sort"

    companion object {
        fun forTab(tab: AppTab): DetailViewContext? = when (tab) {
            AppTab.Performers -> Performer
            AppTab.Studios -> Studio
            AppTab.Tags -> Tag
            AppTab.Galleries -> Gallery
            AppTab.Groups -> Group
            else -> null
        }
    }
}

/** Pure functions behind `TabManager` (unit-tested). */
object TabConfigLogic {
    /** iOS: default `tabs` of `loadConfig()`. */
    fun defaultTabs(): List<TabConfig> = listOf(
        TabConfig(AppTab.Dashboard, true, 0),
        TabConfig(AppTab.Studios, true, 1, "sceneCountDesc"),
        TabConfig(AppTab.Performers, true, 2, "sceneCountDesc"),
        TabConfig(AppTab.Scenes, true, 3, "dateDesc"),
        TabConfig(AppTab.Galleries, true, 4, "dateDesc"),
        TabConfig(AppTab.Images, true, 5, "dateDesc"),
        TabConfig(AppTab.Tags, true, 6, "sceneCountDesc"),
        TabConfig(AppTab.Media, true, 6),
        TabConfig(AppTab.Catalogue, true, 7),
        TabConfig(AppTab.Downloads, false, 100),
        TabConfig(AppTab.Tools, true, 8),
        TabConfig(AppTab.Reels, true, 10, "random"),
        TabConfig(AppTab.Settings, true, 9),
        TabConfig(AppTab.Groups, true, 11, "nameAsc"),
        TabConfig(AppTab.Markers, true, 12, "createdAtDesc"),
        TabConfig(AppTab.Stashline, true, 13, "dateDesc"),
    )

    private val sortMigrations = mapOf("scenes_count" to "sceneCountDesc", "name" to "nameAsc", "date" to "dateDesc")

    /** Decodes elements one by one — entries with unknown ids are dropped instead of failing the list. */
    fun <T> decodeLenient(json: String?, serializer: kotlinx.serialization.KSerializer<T>): List<T>? {
        if (json.isNullOrBlank()) return null
        val array = runCatching { Json.parseToJsonElement(json) as? JsonArray }.getOrNull() ?: return null
        return array.mapNotNull { el: JsonElement -> runCatching { Json.decodeFromJsonElement(serializer, el) }.getOrNull() }
    }

    /** iOS `loadConfig()` migrations. Returns the tabs and whether they must be saved. */
    fun normalizeTabs(decoded: List<TabConfig>?): Pair<List<TabConfig>, Boolean> {
        if (decoded == null) return defaultTabs() to true
        var needsSave = false
        val tabs = decoded.sortedBy { it.sortOrder }.filter { it.id != AppTab.StashyPlus }.toMutableList()
        val maxOrder = tabs.maxOfOrNull { it.sortOrder } ?: 0
        tabs.indexOfFirst { it.id == AppTab.Downloads }.takeIf { it >= 0 }?.let { i ->
            if (tabs[i].isVisible) { tabs[i] = tabs[i].copy(isVisible = false, sortOrder = maxOf(maxOrder, 100)); needsSave = true }
        }
        for (i in tabs.indices) {
            val migrated = tabs[i].defaultSortOption?.let { sortMigrations[it] }
            if (migrated != null) { tabs[i] = tabs[i].copy(defaultSortOption = migrated); needsSave = true }
        }
        tabs.indexOfFirst { it.id == AppTab.Dashboard }.takeIf { it >= 0 }?.let { tabs[it] = tabs[it].copy(sortOrder = 0, isVisible = true) }
        for (tab in defaultTabs()) {
            if (tabs.none { it.id == tab.id }) { tabs.add(tab); needsSave = true }
        }
        return tabs to needsSave
    }

    /** iOS: default rows of `loadHomeRows()`. */
    fun defaultHomeRows(): List<HomeRowConfig> {
        val order = listOf(
            HomeRowType.LastPlayed to true, HomeRowType.Statistics to true, HomeRowType.LastAdded3Min to true,
            HomeRowType.NewPerformers to true, HomeRowType.PerformersHighestSceneCount to true,
            HomeRowType.NewStudios to true, HomeRowType.StudiosHighestSceneCount to true,
            HomeRowType.NewGalleries to true, HomeRowType.RecentlyUpdatedGalleries to true,
            HomeRowType.GalleriesHighestImageCount to true, HomeRowType.Newest3Min to true,
            HomeRowType.PerformersHighestOCount to true, HomeRowType.PerformersHighestRating to true,
            HomeRowType.MostViewed3Min to true, HomeRowType.Random to true,
            HomeRowType.TopCounter3Min to false, HomeRowType.TopRating3Min to false, HomeRowType.Channels to true,
        )
        return order.mapIndexed { i, (type, enabled) -> HomeRowConfig(title = type.defaultTitle, isEnabled = enabled, sortOrder = i, type = type) }
    }

    /** iOS: the `ensure…Row()` order (types appended when missing, with their default enabled state). */
    private val ensureOrder = listOf(
        HomeRowType.Statistics to true, HomeRowType.LastPlayed to true, HomeRowType.MostViewed3Min to true,
        HomeRowType.Random to true, HomeRowType.TopCounter3Min to false, HomeRowType.TopRating3Min to false,
        HomeRowType.NewPerformers to true, HomeRowType.PerformersHighestSceneCount to true,
        HomeRowType.NewStudios to true, HomeRowType.StudiosHighestSceneCount to true,
        HomeRowType.RecentlyUpdatedGalleries to true, HomeRowType.PerformersHighestOCount to true,
        HomeRowType.PerformersHighestRating to true, HomeRowType.GalleriesHighestImageCount to true,
        HomeRowType.Channels to true,
    )

    /**
     * iOS `loadHomeRows()` for decoded data: dedupe by type, renumber, reset titles, add missing
     * rows, and (once per server, [promoteLastPlayed]) move Last Played to the top.
     */
    fun normalizeHomeRows(decoded: List<HomeRowConfig>?, promoteLastPlayed: Boolean): Pair<List<HomeRowConfig>, Boolean> {
        if (decoded == null) return defaultHomeRows() to true
        val seen = mutableSetOf<HomeRowType>()
        val unique = decoded.sortedBy { it.sortOrder }.filter { seen.add(it.type) }
        var changed = unique.size != decoded.size
        val rows = unique.mapIndexed { i, r -> r.copy(sortOrder = i, title = r.type.defaultTitle) }.toMutableList()
        for ((type, enabled) in ensureOrder) {
            if (rows.none { it.type == type }) {
                rows.add(HomeRowConfig(title = type.defaultTitle, isEnabled = enabled, sortOrder = rows.size, type = type))
                changed = true
            }
        }
        if (promoteLastPlayed) {
            val idx = rows.indexOfFirst { it.type == HomeRowType.LastPlayed }
            if (idx >= 0) {
                val row = rows.removeAt(idx)
                rows.add(0, row.copy(isEnabled = true))
                for (i in rows.indices) rows[i] = rows[i].copy(sortOrder = i)
                changed = true
            }
        }
        return rows to changed
    }

    /** iOS `syncHomeChannelItems(with:)`. [filters] are (id, name, mode) of the server's saved filters. */
    fun syncChannelItems(
        current: List<HomeChannelItemConfig>,
        filters: List<Triple<String, String, String?>>,
        legacyKindEnabled: Map<HomeChannelSourceKind, Boolean> = emptyMap(),
    ): List<HomeChannelItemConfig> {
        val eligible = filters.filter { it.third.equals("SCENES", true) || it.third.equals("IMAGES", true) }
        if (eligible.isEmpty()) return current
        val existingIds = current.map { it.id }.toSet()
        val result = current.sortedBy { it.sortOrder }.filter { item -> eligible.any { it.first == item.filterId } }.toMutableList()
        for (f in eligible.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.second })) {
            val dest = if (f.third.equals("IMAGES", true)) HomeChannelSourceKind.Clips else HomeChannelSourceKind.Scenes
            val id = "${dest.raw}.${f.first}"
            if (id !in existingIds) result.add(HomeChannelItemConfig(f.first, dest, legacyKindEnabled[dest] ?: true, result.size))
        }
        return result.mapIndexed { i, it -> it.copy(sortOrder = i) }
    }

    /** iOS: default Feeds modes. */
    fun defaultReelsModes(): List<ReelsModeConfig> = listOf(
        ReelsModeConfig(type = ReelsModeType.Scenes, isEnabled = true, sortOrder = 0),
        ReelsModeConfig(type = ReelsModeType.Markers, isEnabled = true, sortOrder = 1),
        ReelsModeConfig(type = ReelsModeType.Clips, isEnabled = true, sortOrder = 2),
        ReelsModeConfig(type = ReelsModeType.Previews, isEnabled = true, sortOrder = 3),
        ReelsModeConfig(type = ReelsModeType.Pics, isEnabled = true, sortOrder = 4, defaultSortOption = "dateDesc"),
    )

    fun normalizeReelsModes(decoded: List<ReelsModeConfig>?): Pair<List<ReelsModeConfig>, Boolean> {
        if (decoded == null) return defaultReelsModes() to true
        val modes = decoded.sortedBy { it.sortOrder }.toMutableList()
        var changed = false
        for (t in ReelsModeType.entries) if (modes.none { it.type == t }) {
            modes.add(ReelsModeConfig(type = t, isEnabled = true, sortOrder = modes.size, defaultSortOption = if (t == ReelsModeType.Pics) "dateDesc" else null))
            changed = true
        }
        return (if (changed) modes.mapIndexed { i, m -> m.copy(sortOrder = i) } else modes) to changed
    }

    /** Reorders [list] by moving index [from] to [to] (Compose drag/menu helper, like `move(fromOffsets:toOffset:)`). */
    fun <T> move(list: List<T>, from: Int, to: Int): List<T> {
        if (from !in list.indices) return list
        val m = list.toMutableList()
        val item = m.removeAt(from)
        m.add(to.coerceIn(0, m.size), item)
        return m
    }

    /** iOS `TabManager.playCountThresholdLabel`. */
    fun playCountThresholdLabel(seconds: Double): String = when {
        seconds == 0.0 -> "Immediately"
        seconds < 60 -> "${seconds.toInt()} s"
        else -> "${(seconds / 60).toInt()} min"
    }

    /** iOS `TabManager.holdSpeedLabel`. */
    fun holdSpeedLabel(rate: Double): String = if (rate == Math.rint(rate)) "${rate.toInt()}×" else String.format(java.util.Locale.US, "%.1f×", rate)
}
