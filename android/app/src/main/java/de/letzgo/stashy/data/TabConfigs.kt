package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.UiText
import de.letzgo.stashy.tr
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
enum class AppTab(private val titleText: UiText) {
    @SerialName("dashboard") Dashboard(UiText(R.string.dashboard)),
    @SerialName("studios") Studios(UiText(R.string.studios)),
    @SerialName("performers") Performers(UiText(R.string.performers)),
    @SerialName("scenes") Scenes(UiText(R.string.scenes)),
    @SerialName("galleries") Galleries(UiText(R.string.galleries)),
    @SerialName("tags") Tags(UiText(R.string.tags)),
    @SerialName("media") Media(UiText(R.string.media)),
    @SerialName("catalogue") Catalogue(UiText(R.string.home)),
    @SerialName("downloads") Downloads(UiText(R.string.downloads)),
    @SerialName("tools") Tools(UiText(R.string.tools)),
    @SerialName("stashyPlus") StashyPlus(UiText("stashy+")),
    @SerialName("reels") Reels(UiText(R.string.feeds)),
    @SerialName("search") Search(UiText(R.string.search)),
    @SerialName("settings") Settings(UiText(R.string.settings)),
    @SerialName("images") Images(UiText(R.string.images)),
    @SerialName("groups") Groups(UiText(R.string.groups)),
    @SerialName("markers") Markers(UiText(R.string.markers)),
    @SerialName("stashline") Stashline(UiText("StashLine")),
    @SerialName("magazine") Magazine(UiText(R.string.magazin));
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = titleText.text

    /** Raw value as stored by iOS. */
    val raw: String get() = name.replaceFirstChar { it.lowercase() }.let { if (this == StashyPlus) "stashyPlus" else it }

    /** Catalog list mode of a catalog tab (iOS `CatalogDefaultFilterMenu.filterMode`, sort enums). */
    val filterMode: FilterMode? get() = when (this) {
        Scenes -> FilterMode.Scenes; Performers -> FilterMode.Performers; Studios -> FilterMode.Studios
        Galleries -> FilterMode.Galleries; Images -> FilterMode.Images; Tags -> FilterMode.Tags
        Groups -> FilterMode.Groups; Markers -> FilterMode.SceneMarkers
        else -> null
    }

    companion object {
        fun fromRaw(raw: String?): AppTab? = entries.firstOrNull { it.raw == raw }

        fun forMode(mode: FilterMode): AppTab? = entries.firstOrNull { it.filterMode == mode }
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
    /** Feeds › Verticals (stashy+): its own default scene filter; portrait is always added. */
    val defaultVerticalFilterId: String? = null,
    val defaultVerticalFilterName: String? = null,
)

/** iOS: `HomeRowType` (raw values and default titles identical). */
@Serializable
enum class HomeRowType(@androidx.annotation.StringRes val titleRes: Int) {
    @SerialName("lastPlayed") LastPlayed(R.string.scenes_last_played),
    @SerialName("lastAdded3Min") LastAdded3Min(R.string.scenes_recently_added),
    @SerialName("newest3Min") Newest3Min(R.string.scenes_new),
    @SerialName("mostViewed3Min") MostViewed3Min(R.string.scenes_most_viewed),
    @SerialName("topCounter3Min") TopCounter3Min(R.string.scenes_top_counter),
    @SerialName("topRating3Min") TopRating3Min(R.string.scenes_top_rated),
    @SerialName("random") Random(R.string.scenes_random),
    @SerialName("statistics") Statistics(R.string.statistics),
    @SerialName("newPerformers") NewPerformers(R.string.performers_new),
    @SerialName("performersHighestSceneCount") PerformersHighestSceneCount(R.string.performers_top),
    @SerialName("newStudios") NewStudios(R.string.studios_new),
    @SerialName("studiosHighestSceneCount") StudiosHighestSceneCount(R.string.studios_top),
    @SerialName("newGalleries") NewGalleries(R.string.galleries_new),
    @SerialName("recentlyUpdatedGalleries") RecentlyUpdatedGalleries(R.string.galleries_recently_updated),
    @SerialName("performersHighestOCount") PerformersHighestOCount(R.string.performers_counter),
    @SerialName("performersHighestRating") PerformersHighestRating(R.string.performers_rating),
    @SerialName("galleriesHighestImageCount") GalleriesHighestImageCount(R.string.galleries_image_count),
    @SerialName("channels") Channels(R.string.channels),
    /** stashy+: "For You" — scenes picked from the user's own watch history (iOS `.recommendations`). */
    @SerialName("recommendations") Recommendations(R.string.scenes_for_you),
    /** stashy+: top played / O-Counted scenes not played for a while (iOS `.forgottenFavorites`). */
    @SerialName("forgottenFavorites") ForgottenFavorites(R.string.scenes_forgotten_favorites);

        /** Default title in the app's language. */
    val defaultTitle: String get() = tr(titleRes)

/** iOS `requiresStashyPlus`: rows hidden from Home and Settings while locked. */
    val requiresStashyPlus get() = this == Channels || this == Recommendations || this == ForgottenFavorites

    val isPerformerRow get() = this in setOf(NewPerformers, PerformersHighestSceneCount, PerformersHighestOCount, PerformersHighestRating)
    val isStudioRow get() = this == NewStudios || this == StudiosHighestSceneCount
    val isGalleryRow get() = this in setOf(NewGalleries, RecentlyUpdatedGalleries, GalleriesHighestImageCount)
    val isSceneRow get() = !isPerformerRow && !isStudioRow && !isGalleryRow && this != Statistics && !requiresStashyPlus
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

/**
 * iOS `HomeRowConfig.displayTitle`: a built-in row's stored title is its default from the day it
 * was created (in that day's language), so it follows the app language; a renamed row keeps its own.
 */
val HomeRowConfig.displayTitle: String
    get() = if (de.letzgo.stashy.AppLanguage.isTranslation(title, type.titleRes)) type.defaultTitle else title

/** iOS: `HomeChannelSourceKind`. */
@Serializable
enum class HomeChannelSourceKind(@androidx.annotation.StringRes private val titleRes: Int) {
    @SerialName("scenes") Scenes(R.string.scenes),
    @SerialName("clips") Clips(R.string.clips);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)
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
enum class ReelsModeType(@androidx.annotation.StringRes private val defaultTitleRes: Int) {
    @SerialName("scenes") Scenes(R.string.scenes),
    @SerialName("markers") Markers(R.string.markers),
    @SerialName("clips") Clips(R.string.clips),
    @SerialName("previews") Previews(R.string.previews),
    @SerialName("pics") Pics(R.string.pics),
    /** stashy+: the Scenes feed with its filter preset to portrait videos (iOS `.verticals`). */
    @SerialName("verticals") Verticals(R.string.verticals);
    /** Read on use: a constant must not freeze its text at class load. */
    val defaultTitle: String get() = tr(defaultTitleRes)

    /** Feed modes behind stashy+. */
    val requiresStashyPlus: Boolean get() = this == Verticals
    /** Loads scenes like the Scenes feed (Verticals only differs by its preset filter). */
    val isSceneFeed: Boolean get() = this == Scenes || this == Verticals

    val title: String get() = defaultTitle
    /** iOS: `ReelsMode.rawValue` ("Scenes", "Markers" …) — the deep-link / session spelling. */
    val modeRaw: String get() = defaultTitle

    companion object {
        fun fromModeRaw(raw: String?): ReelsModeType? =
            entries.firstOrNull { it.defaultTitle == raw || it.defaultTitle.equals(raw, ignoreCase = true) }
    }
}

/** iOS: `ReelsModeConfig`. */
@Serializable
data class ReelsModeConfig(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val type: ReelsModeType,
    val isEnabled: Boolean = true,
    val sortOrder: Int = 0,
    val defaultSortOption: String? = null,
)

/** iOS: `DetailViewContext` (raw values are the persisted key parts). */
enum class DetailViewContext(val raw: String, @androidx.annotation.StringRes private val titleRes: Int) {
    Performer("performer_detail", R.string.performer_scenes),
    Studio("studio_detail", R.string.studio_scenes),
    Tag("tag_detail", R.string.tag_scenes),
    Gallery("gallery_detail", R.string.gallery_images),
    Group("group_detail", R.string.group_scenes);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)

    val settingsRowTitle: String get() = if (this == Gallery) tr(R.string.images_sort) else tr(R.string.scenes_sort)

    companion object {
        fun fromRaw(raw: String?): DetailViewContext? = entries.firstOrNull { it.raw == raw }

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
        TabConfig(AppTab.Magazine, true, 14),
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
        return insertForgottenFavorites(insertRecommendations(order.mapIndexed { i, (type, enabled) -> HomeRowConfig(title = type.defaultTitle, isEnabled = enabled, sortOrder = i, type = type) }))
    }

    /** iOS `ensureRecommendationsRow()`: For You goes right below Last Played, not to the end. */
    private fun insertRecommendations(rows: List<HomeRowConfig>): List<HomeRowConfig> {
        if (rows.any { it.type == HomeRowType.Recommendations }) return rows
        val anchor = rows.indexOfFirst { it.type == HomeRowType.LastPlayed }.let { if (it >= 0) it + 1 else 0 }
        val list = rows.toMutableList()
        list.add(minOf(anchor, list.size), HomeRowConfig(title = HomeRowType.Recommendations.defaultTitle, isEnabled = true, sortOrder = anchor, type = HomeRowType.Recommendations))
        return list.mapIndexed { i, r -> r.copy(sortOrder = i) }
    }

    /** iOS `ensureForgottenFavoritesRow()`: right below For You (or Last Played). */
    private fun insertForgottenFavorites(rows: List<HomeRowConfig>): List<HomeRowConfig> {
        if (rows.any { it.type == HomeRowType.ForgottenFavorites }) return rows
        val after = rows.indexOfFirst { it.type == HomeRowType.Recommendations }.takeIf { it >= 0 }
            ?: rows.indexOfFirst { it.type == HomeRowType.LastPlayed }
        val anchor = if (after >= 0) after + 1 else 0
        val list = rows.toMutableList()
        list.add(minOf(anchor, list.size), HomeRowConfig(title = HomeRowType.ForgottenFavorites.defaultTitle, isEnabled = true, sortOrder = anchor, type = HomeRowType.ForgottenFavorites))
        return list.mapIndexed { i, r -> r.copy(sortOrder = i) }
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
        if (rows.none { it.type == HomeRowType.Recommendations }) {
            val inserted = insertRecommendations(rows)
            rows.clear(); rows.addAll(inserted)
            changed = true
        }
        if (rows.none { it.type == HomeRowType.ForgottenFavorites }) {
            val inserted = insertForgottenFavorites(rows)
            rows.clear(); rows.addAll(inserted)
            changed = true
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
        seconds == 0.0 -> tr(R.string.immediately)
        seconds < 60 -> tr(R.string.arg_seconds_short, seconds.toInt())
        else -> tr(R.string.arg_minutes_short, (seconds / 60).toInt())
    }

    /** iOS `TabManager.holdSpeedLabel`. */
    fun holdSpeedLabel(rate: Double): String = if (rate == Math.rint(rate)) "${rate.toInt()}×" else String.format(java.util.Locale.US, "%.1f×", rate)
}
