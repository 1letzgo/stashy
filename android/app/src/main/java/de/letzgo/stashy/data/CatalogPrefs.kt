package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlin.math.roundToInt

/** iOS: `CatalogTabConfig` — one entry of `AppTabsConfig_<serverId>` (same JSON keys). */
@Serializable
data class CatalogTabConfig(
    val id: String,
    val isVisible: Boolean = true,
    val sortOrder: Int = 0,
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

/** iOS: `CatalogCardColumns` — 1 or 2 cards per row (Galleries / Images). */
enum class CatalogCardColumns(val raw: Int) {
    One(1), Two(2);

    val next: CatalogCardColumns get() = if (this == One) Two else One
    /** 1/row → 16:9, 2/row → 1:1. */
    val cardAspectRatio: Float get() = if (this == One) 16f / 9f else 1f
    val idealCardWidth: Float get() = if (this == One) 480f else 260f
    val accessibilityLabel: String get() = if (this == One) "One card per row" else "Two cards per row"
    val settingsLabel: String get() = if (this == One) "1 per Row" else "2 per Row"

    /** iOS: `gridItems(width:)` — the toggle picks the card size, width decides the count. */
    fun columnCount(widthDp: Float): Int =
        if (widthDp > 0) maxOf(raw, minOf(raw * 3, (widthDp / idealCardWidth).roundToInt())) else raw

    companion object { fun from(raw: Int?) = entries.firstOrNull { it.raw == raw } }
}

/** iOS: `CatalogCardColumnScope` — independent persistence of the 1/2 toggle. */
enum class CatalogCardColumnScope(val raw: String) {
    Galleries("galleries"), Images("images"), OpenedGallery("openedGallery");
    companion object {
        fun from(tab: AppTab): CatalogCardColumnScope? = when (tab) {
            AppTab.Galleries -> Galleries
            AppTab.Images -> Images
            else -> null
        }
    }
}

/**
 * Catalog part of iOS `TabManager`: per-server tab config (`AppTabsConfig_<serverId>` — default
 * sort and default saved filter per catalog), session sort (not persisted, like iOS
 * `sessionSortOptions`), detail sorts (`DetailViewsSortConfig_<context>_<serverId>`) and the
 * card-column toggles (`CatalogCardColumns`, global). Settings writes through the same setters.
 */
object CatalogPrefs {
    private const val TABS_KEY = "AppTabsConfig"
    private const val DETAIL_SORT_KEY = "DetailViewsSortConfig"
    private const val COLUMNS_KEY = "CatalogCardColumns"

    /** Bumped whenever a persistent default changes (iOS `DefaultSortChanged` / `DefaultFilterChanged`). */
    var defaultsVersion by mutableIntStateOf(0)
        private set

    private val sessionSorts = mutableStateMapOf<String, String>()
    private val sessionDetailSorts = mutableStateMapOf<String, String>()

    /** iOS default tab list (`TabManager.loadConfig` fallback). */
    val defaultTabs: List<CatalogTabConfig> = listOf(
        CatalogTabConfig("dashboard", true, 0, null),
        CatalogTabConfig("studios", true, 1, "sceneCountDesc"),
        CatalogTabConfig("performers", true, 2, "sceneCountDesc"),
        CatalogTabConfig("scenes", true, 3, "dateDesc"),
        CatalogTabConfig("galleries", true, 4, "dateDesc"),
        CatalogTabConfig("images", true, 5, "dateDesc"),
        CatalogTabConfig("tags", true, 6, "sceneCountDesc"),
        CatalogTabConfig("media", true, 6, null),
        CatalogTabConfig("catalogue", true, 7, null),
        CatalogTabConfig("downloads", false, 100, null),
        CatalogTabConfig("tools", true, 8, null),
        CatalogTabConfig("reels", true, 10, "random"),
        CatalogTabConfig("settings", true, 9, null),
        CatalogTabConfig("groups", true, 11, "nameAsc"),
        CatalogTabConfig("markers", true, 12, "createdAtDesc"),
        CatalogTabConfig("stashline", true, 13, "dateDesc"),
    )

    private val sortMigrations = mapOf("scenes_count" to "sceneCountDesc", "name" to "nameAsc", "date" to "dateDesc")

    fun tabs(): List<CatalogTabConfig> {
        if (defaultsVersion < 0) return defaultTabs // read for recomposition
        val raw = Prefs.string(Prefs.serverKey(TABS_KEY)) ?: Prefs.string(TABS_KEY)
        val decoded = raw?.let { decodeTabs(it) } ?: return defaultTabs
        return decoded.map { t -> t.defaultSortOption?.let { sortMigrations[it] }?.let { t.copy(defaultSortOption = it) } ?: t }
    }

    fun decodeTabs(raw: String): List<CatalogTabConfig>? =
        runCatching { Json.decodeFromString(ListSerializer(CatalogTabConfig.serializer()), raw) }.getOrNull()

    fun encodeTabs(tabs: List<CatalogTabConfig>): String = Json.encodeToString(ListSerializer(CatalogTabConfig.serializer()), tabs)

    private fun saveTabs(tabs: List<CatalogTabConfig>) {
        Prefs.setString(Prefs.serverKey(TABS_KEY), encodeTabs(tabs))
        defaultsVersion++
    }

    private fun update(tabId: String, change: (CatalogTabConfig) -> CatalogTabConfig) {
        val list = tabs().toMutableList()
        val idx = list.indexOfFirst { it.id == tabId }
        if (idx >= 0) list[idx] = change(list[idx]) else list.add(change(CatalogTabConfig(tabId)))
        saveTabs(list)
    }

    /** `AppTab` raw value for a catalog (`scenes`, `performers`, …). */
    fun tabId(mode: FilterMode): String = when (mode) {
        FilterMode.Scenes -> "scenes"; FilterMode.Performers -> "performers"; FilterMode.Studios -> "studios"
        FilterMode.Galleries -> "galleries"; FilterMode.Images -> "images"; FilterMode.Tags -> "tags"
        FilterMode.Groups -> "groups"; FilterMode.SceneMarkers -> "markers"; FilterMode.Unknown -> "unknown"
    }

    fun persistentSortOption(tabId: String): String? = tabs().firstOrNull { it.id == tabId }?.defaultSortOption

    /** iOS `getSortOption(for:)`: session sort first, then the persistent default. */
    fun sortOption(tabId: String): String? = sessionSorts[tabId] ?: persistentSortOption(tabId)

    /** iOS `setSortOption(for:option:)` — session only. */
    fun setSortOption(tabId: String, option: String) { sessionSorts[tabId] = option }

    /** iOS `setPersistentSortOption(for:option:)` — Settings › Default Sorting. */
    fun setPersistentSortOption(tabId: String, option: String) {
        sessionSorts[tabId] = option
        update(tabId) { it.copy(defaultSortOption = option) }
    }

    fun defaultFilterId(tabId: String): String? = tabs().firstOrNull { it.id == tabId }?.defaultFilterId
    fun defaultFilterName(tabId: String): String? = tabs().firstOrNull { it.id == tabId }?.defaultFilterName

    fun setDefaultFilter(tabId: String, filterId: String?, filterName: String?) =
        update(tabId) { it.copy(defaultFilterId = filterId, defaultFilterName = filterName) }

    /** Resolved catalog sort: session → persistent default → iOS view fallback. */
    fun resolvedSort(mode: FilterMode): SortOption =
        SortCatalog.option(mode, sortOption(tabId(mode))) ?: SortCatalog.option(mode, SortCatalog.defaultRaw(mode))!!

    // Detail sorts (iOS `DetailViewContext`: performer_detail, studio_detail, tag_detail, gallery_detail, group_detail).

    fun persistentDetailSortOption(context: String): String =
        Prefs.string(Prefs.serverKey("${DETAIL_SORT_KEY}_$context")) ?: Prefs.string("${DETAIL_SORT_KEY}_$context") ?: "dateDesc"

    fun detailSortOption(context: String): String = sessionDetailSorts[context] ?: persistentDetailSortOption(context)
    fun setDetailSortOption(context: String, option: String) { sessionDetailSorts[context] = option }
    fun setPersistentDetailSortOption(context: String, option: String) {
        sessionDetailSorts[context] = option
        Prefs.setString(Prefs.serverKey("${DETAIL_SORT_KEY}_$context"), option)
        defaultsVersion++
    }

    // Card columns (global JSON `{scope: 1|2}` like iOS).

    private val columnsState = mutableStateOf(loadColumns())

    private fun loadColumns(): Map<CatalogCardColumnScope, CatalogCardColumns> {
        val raw = runCatching { Prefs.string(COLUMNS_KEY) }.getOrNull()
        val map = raw?.let {
            runCatching { Json.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), it) }.getOrNull()
        } ?: emptyMap()
        val loaded = HashMap<CatalogCardColumnScope, CatalogCardColumns>()
        CatalogCardColumnScope.entries.forEach { s -> CatalogCardColumns.from(map[s.raw])?.let { loaded[s] = it } }
        if (loaded[CatalogCardColumnScope.OpenedGallery] == null) loaded[CatalogCardColumnScope.Images]?.let { loaded[CatalogCardColumnScope.OpenedGallery] = it }
        CatalogCardColumnScope.entries.forEach { s -> if (loaded[s] == null) loaded[s] = CatalogCardColumns.Two }
        return loaded
    }

    fun cardColumns(scope: CatalogCardColumnScope): CatalogCardColumns = columnsState.value[scope] ?: CatalogCardColumns.Two

    fun setCardColumns(scope: CatalogCardColumnScope, columns: CatalogCardColumns) {
        val next = columnsState.value.toMutableMap().apply { put(scope, columns) }
        columnsState.value = next
        Prefs.setString(COLUMNS_KEY, Json.encodeToString(MapSerializer(String.serializer(), Int.serializer()), next.mapKeys { it.key.raw }.mapValues { it.value.raw }))
    }

    fun toggleCardColumns(scope: CatalogCardColumnScope) = setCardColumns(scope, cardColumns(scope).next)

    /** Server switch: session state belongs to the old server. */
    fun resetSession() {
        sessionSorts.clear()
        sessionDetailSorts.clear()
        defaultsVersion++
    }
}

/** iOS: `DesignTokens.Grid.adaptiveColumnCount` (poster grids: ideal 220, 2…8 columns). */
fun adaptiveColumnCount(widthDp: Float, ideal: Float = 220f, minimum: Int = 2, maximum: Int = 8): Int {
    if (widthDp <= 0f || ideal <= 0f) return minimum
    return (widthDp / ideal).roundToInt().coerceIn(minimum, maximum)
}
