package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlin.math.roundToInt

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
 * Catalog facade over [TabManager] (the one store of `AppTabsConfig_<serverId>`, session sorts,
 * `DetailViewsSortConfig_<context>_<serverId>` and `CatalogCardColumns`). Catalog code speaks in
 * `AppTab` raw values (`scenes`, `performers`, …) and [FilterMode]s; Settings writes through
 * [TabManager] directly, so a change there reaches open catalogs via [defaultsVersion].
 */
object CatalogPrefs {
    /** Bumped whenever a persistent default changes (iOS `DefaultSortChanged` / `DefaultFilterChanged`). */
    val defaultsVersion: Int get() = TabManager.defaultsVersion

    fun tabs(): List<TabConfig> { TabManager.ensureLoaded(); return TabManager.tabs }

    /** Lenient decode of iOS `AppTabsConfig` JSON (unknown tab ids are dropped); null if not a list. */
    fun decodeTabs(raw: String): List<TabConfig>? = TabConfigLogic.decodeLenient(raw, TabConfig.serializer())

    fun encodeTabs(tabs: List<TabConfig>): String = Json.encodeToString(ListSerializer(TabConfig.serializer()), tabs)

    /** `AppTab` raw value for a catalog (`scenes`, `performers`, …). */
    fun tabId(mode: FilterMode): String = AppTab.forMode(mode)?.raw ?: "unknown"

    private fun tab(tabId: String): AppTab? = AppTab.fromRaw(tabId)

    fun persistentSortOption(tabId: String): String? = tab(tabId)?.let { TabManager.getPersistentSortOption(it) }

    /** iOS `getSortOption(for:)`: session sort first, then the persistent default. */
    fun sortOption(tabId: String): String? = tab(tabId)?.let { TabManager.getSortOption(it) }

    /** iOS `setSortOption(for:option:)` — session only. */
    fun setSortOption(tabId: String, option: String) { tab(tabId)?.let { TabManager.setSortOption(it, option) } }

    /** iOS `setPersistentSortOption(for:option:)` — Settings › Default Sorting. */
    fun setPersistentSortOption(tabId: String, option: String) { tab(tabId)?.let { TabManager.setPersistentSortOption(it, option) } }

    /** Settings default filter of a catalog; Markers use the marker slot like iOS `MarkersView`. */
    fun defaultFilterId(tabId: String): String? = tab(tabId)?.let {
        if (it == AppTab.Markers) TabManager.getDefaultMarkerFilterId(it) else TabManager.getDefaultFilterId(it)
    }

    fun defaultFilterName(tabId: String): String? = tab(tabId)?.let {
        if (it == AppTab.Markers) TabManager.getDefaultMarkerFilterName(it) else TabManager.getDefaultFilterName(it)
    }

    fun setDefaultFilter(tabId: String, filterId: String?, filterName: String?) {
        val t = tab(tabId) ?: return
        if (t == AppTab.Markers) TabManager.setDefaultMarkerFilter(t, filterId, filterName) else TabManager.setDefaultFilter(t, filterId, filterName)
    }

    /** Resolved catalog sort: session → persistent default → iOS view fallback. */
    fun resolvedSort(mode: FilterMode): SortOption =
        SortCatalog.option(mode, sortOption(tabId(mode))) ?: SortCatalog.option(mode, SortCatalog.defaultRaw(mode))!!

    // Detail sorts (iOS `DetailViewContext`: performer_detail, studio_detail, tag_detail, gallery_detail, group_detail).

    fun persistentDetailSortOption(context: String): String =
        DetailViewContext.fromRaw(context)?.let { TabManager.getPersistentDetailSortOption(it) } ?: "dateDesc"

    fun detailSortOption(context: String): String = TabManager.getDetailSortOption(context) ?: "dateDesc"
    fun setDetailSortOption(context: String, option: String) = TabManager.setDetailSortOption(context, option)
    fun setPersistentDetailSortOption(context: String, option: String) {
        DetailViewContext.fromRaw(context)?.let { TabManager.setPersistentDetailSortOption(it, option) }
    }

    // Card columns (global JSON `{scope: 1|2}` like iOS).

    fun cardColumns(scope: CatalogCardColumnScope): CatalogCardColumns = TabManager.catalogCardColumns(scope)
    fun setCardColumns(scope: CatalogCardColumnScope, columns: CatalogCardColumns) = TabManager.setCatalogCardColumns(columns, scope)
    fun toggleCardColumns(scope: CatalogCardColumnScope) = TabManager.toggleCatalogCardColumns(scope)

    /** Server switch: session state belongs to the old server. */
    fun resetSession() = TabManager.resetSession()
}

/** iOS: `DesignTokens.Grid.adaptiveColumnCount` (poster grids: ideal 220, 2…8 columns). */
fun adaptiveColumnCount(widthDp: Float, ideal: Float = 220f, minimum: Int = 2, maximum: Int = 8): Int {
    if (widthDp <= 0f || ideal <= 0f) return minimum
    return (widthDp / ideal).roundToInt().coerceIn(minimum, maximum)
}
