package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.encodedSortPair
import de.letzgo.stashy.data.stashyMetadata
import kotlinx.serialization.json.JsonObject

/**
 * Pure logic of the Tools › Filters editor (iOS: `FiltersToolsEditorSheet` in
 * `FiltersToolsView.swift` and the `saveFullObjectFilter` call it makes). Free of Android APIs.
 */
object FiltersEditorLogic {
    /** iOS: `FiltersToolsEditorSheet.defaultSort(for:)`. */
    fun defaultSortPair(mode: FilterMode): Pair<String, String> = when (mode) {
        FilterMode.Performers, FilterMode.Tags, FilterMode.Studios -> "name" to "ASC"
        FilterMode.SceneMarkers -> "seconds" to "ASC"
        else -> "date" to "DESC"
    }

    /**
     * iOS: the editor's initial `selectedSortRaw` — the filter's stashy `sortRaw`, then its
     * `find_filter` pair, then the mode default, then the first choice of the mode.
     */
    fun initialSort(filter: SavedFilter?, mode: FilterMode): SortOption? =
        SortCatalog.choice(mode, filter?.stashyMetadata?.sortRaw, filter?.encodedSortPair)
            ?: SortCatalog.choice(mode, null, defaultSortPair(mode))
            ?: SortCatalog.choices(mode).firstOrNull()

    /** iOS: "Save as new" seeds the name field with "<name> copy" (empty when there is no name). */
    fun saveAsSeed(name: String): String = name.trim().let { if (it.isEmpty()) "" else "$it copy" }

    /**
     * iOS: `saveFullObjectFilter(mode:existingId:name:sortField:sortDirection:sortRaw:objectFilter:randomSeedKind:)`
     * as the editor calls it — no live fragment is passed, so an update keeps the stored
     * `ui_options.stashy.liveFragment` of [existing] (a new filter gets `{}`); random sorts are
     * written as `random_<seed>`. Returns null for an empty name.
     */
    fun saveInput(
        mode: FilterMode,
        existingId: String?,
        existing: SavedFilter?,
        name: String,
        sort: SortOption,
        objectFilter: JsonObject,
        labels: Map<String, String> = emptyMap(),
    ): JsonObject? {
        if (name.trim().isEmpty()) return null
        val liveFragment = existing?.takeIf { existingId != null && it.id == existingId }?.stashyMetadata?.liveFragment
        return SavedFiltersRepository.saveInput(mode, existingId, name, sort, objectFilter, liveFragment, null, labels)
    }
}
