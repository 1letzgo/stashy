package de.letzgo.stashy.data.tools

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.GraphQLError
import de.letzgo.stashy.data.vars
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: the saved-filter calls of `StashDBViewModel` used by Tools › Filters
 * (`fetchSavedFilters`, `renameSavedFilter`, `destroySavedSceneFilter`), query strings copied from
 * `GraphQLQueries.swift`.
 */
object FiltersToolRepository {
    /** iOS: `GraphQLQueries.findSavedFiltersQuery`. */
    const val FIND_SAVED_FILTERS =
        "query GetAllFilterDefinitions { findSavedFilters { id name mode filter object_filter ui_options find_filter { sort direction } } }"

    /** iOS: `GraphQLQueries.saveCatalogFilterMutation` (same selection as `saveSceneFilterMutation`). */
    val SAVE_FILTER = """
        mutation SaveCatalogFilter(${'$'}input: SaveFilterInput!) {
          saveFilter(input: ${'$'}input) {
            id
            name
            mode
            filter
            object_filter
            ui_options
            find_filter { sort direction }
          }
        }
    """

    /** iOS: `GraphQLQueries.destroySavedFilterMutation`. */
    val DESTROY_FILTER = """
        mutation DestroySavedSceneFilter(${'$'}input: DestroyFilterInput!) {
          destroySavedFilter(input: ${'$'}input)
        }
    """

    suspend fun findSavedFilters(): List<FiltersToolEntry> {
        val data = GraphQL.data(FIND_SAVED_FILTERS)
        val rows = data["findSavedFilters"] as? JsonArray ?: throw GraphQLError.Query(tr(R.string.error_saved_filters_data_missing))
        return FiltersLogic.entries(rows)
    }

    /** iOS: `renameSavedFilter(_:to:)`. Throws when the name is empty or the server rejects it. */
    suspend fun rename(entry: FiltersToolEntry, name: String): FiltersToolEntry {
        val input = FiltersLogic.renameInput(entry, name) ?: throw GraphQLError.Query(tr(R.string.name_is_empty))
        val data = GraphQL.data(SAVE_FILTER, vars("input" to input))
        val saved = data["saveFilter"]?.let { FiltersLogic.entry(it) } ?: throw GraphQLError.Query(tr(R.string.action_save_filter_response_missing_data))
        return saved
    }

    /** iOS: `destroySavedSceneFilter(id:)`. */
    suspend fun delete(id: String) {
        val data = GraphQL.data(DESTROY_FILTER, buildJsonObject { put("input", buildJsonObject { put("id", JsonPrimitive(id)) }) })
        val ok = (data["destroySavedFilter"] as? JsonPrimitive)?.booleanOrNull == true
        if (!ok) throw GraphQLError.Query(tr(R.string.error_delete_saved_filter))
    }
}
