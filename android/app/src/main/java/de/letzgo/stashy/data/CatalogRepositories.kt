package de.letzgo.stashy.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * What a catalog list asks the server for (iOS: the `fetch<Entity>(sortBy:searchQuery:filter:liveFilter:)`
 * family in `StashDBViewModel`). [base] is the selected saved filter (only sent while the criteria
 * editor is empty), [live] the editor criteria, [scope] a fixed detail-screen restriction such as
 * `performers INCLUDES [id]` that always wins.
 */
data class CatalogQuery(
    val mode: FilterMode,
    val sort: SortOption,
    val search: String = "",
    val base: SavedFilter? = null,
    val live: JsonObject? = null,
    val scope: JsonObject? = null,
) {
    /** Entity filter variable (`scene_filter`, `performer_filter`, …) or `null` when empty. */
    fun entityFilter(): JsonObject? {
        if (mode == FilterMode.SceneMarkers) return markerFilter()
        var merged: JsonObject = base?.filterDict?.let { FilterMapper.sanitize(it) } ?: JsonObject(emptyMap())
        if (!live.isNullOrEmpty()) {
            val m = LinkedHashMap<String, JsonElement>(merged)
            live.forEach { (k, v) -> m[k] = v }
            merged = FilterMapper.sanitize(JsonObject(m))
        }
        if (!scope.isNullOrEmpty()) {
            val m = LinkedHashMap<String, JsonElement>(merged)
            scope.forEach { (k, v) -> m[k] = v }
            merged = JsonObject(m)
        }
        return merged.takeIf { it.isNotEmpty() }
    }

    /**
     * iOS `loadMarkersPage`: saved filter sanitized as marker filter; live `scene_filter` chips go
     * into `scene_filter`, every other live key is a marker-level criterion.
     */
    private fun markerFilter(): JsonObject? {
        val marker = LinkedHashMap<String, JsonElement>(base?.filterDict?.let { FilterMapper.sanitize(it, isMarker = true) } ?: JsonObject(emptyMap()))
        if (!live.isNullOrEmpty()) {
            val l = LinkedHashMap<String, JsonElement>(live)
            val sceneNested = LinkedHashMap<String, JsonElement>((marker["scene_filter"] as? JsonObject) ?: JsonObject(emptyMap()))
            (l.remove("scene_filter") as? JsonObject)?.let { chips -> FilterMapper.sanitize(chips).forEach { (k, v) -> sceneNested[k] = v } }
            FilterMapper.sanitize(JsonObject(l)).forEach { (k, v) -> marker[k] = v }
            if (sceneNested.isNotEmpty()) marker["scene_filter"] = FilterMapper.sanitize(JsonObject(sceneNested))
        }
        scope?.forEach { (k, v) -> marker[k] = v }
        if (marker.isEmpty()) return null
        return normalizeSceneMarkerFilter(JsonObject(marker))
    }

    companion object {
        private val hoistFromRoot = setOf(
            "rating100", "organized", "interactive", "orientation", "performer_count", "resolution",
            "performer_favorite", "o_counter", "studios", "groups", "movies",
        )

        /** iOS: `normalizeSceneMarkerFilterForQuery` — hoists scene-only root keys into `scene_filter`. */
        fun normalizeSceneMarkerFilter(markerFilter: JsonObject): JsonObject {
            val out = LinkedHashMap<String, JsonElement>(markerFilter)
            val nested = LinkedHashMap<String, JsonElement>((out["scene_filter"] as? JsonObject) ?: JsonObject(emptyMap()))
            for (key in hoistFromRoot) out.remove(key)?.let { nested[key] = it }
            if (nested.isNotEmpty()) out["scene_filter"] = FilterMapper.sanitize(JsonObject(nested))
            return FilterMapper.sanitize(JsonObject(out), isMarker = true)
        }
    }
}

/** Per-mode wiring of the shared `.graphql` list documents (+ iOS page sizes). */
object CatalogRepository {
    private class Spec<T>(val document: String, val listField: String, val filterVar: String, val serializer: KSerializer<T>, val perPage: Int)

    @Suppress("UNCHECKED_CAST")
    private fun <T> spec(mode: FilterMode): Spec<T> = when (mode) {
        FilterMode.Scenes -> Spec("findScenes", "scenes", "scene_filter", Scene.serializer(), 20)
        FilterMode.Performers -> Spec("findPerformers", "performers", "performer_filter", Performer.serializer(), 50)
        FilterMode.Studios -> Spec("findStudios", "studios", "studio_filter", Studio.serializer(), 500)
        FilterMode.Tags -> Spec("findTags", "tags", "tag_filter", Tag.serializer(), 500)
        FilterMode.Galleries -> Spec("findGalleries", "galleries", "gallery_filter", Gallery.serializer(), 20)
        FilterMode.Images -> Spec("findImages", "images", "image_filter", StashImage.serializer(), 100)
        FilterMode.Groups -> Spec("findGroups", "groups", "group_filter", StashGroup.serializer(), 20)
        FilterMode.SceneMarkers -> Spec("findSceneMarkers", "scene_markers", "scene_marker_filter", SceneMarker.serializer(), 20)
        FilterMode.Unknown -> error("No catalog for UNKNOWN")
    } as Spec<T>

    fun pageSize(mode: FilterMode): Int = spec<Any>(mode).perPage

    fun findFilter(query: CatalogQuery, page: Int, perPage: Int) = FindFilter(
        page = page, perPage = perPage,
        sort = RandomSeeds.sortField(query.mode, query.sort),
        direction = query.sort.direction,
        q = query.search.takeIf { it.isNotBlank() },
    )

    /** Loads one page of [query] (1-based). The caller casts to the entity type of `query.mode`. */
    suspend fun <T> find(query: CatalogQuery, page: Int, perPage: Int = pageSize(query.mode)): Page<T> {
        val s = spec<T>(query.mode)
        val document = s.document
        return findPage(document, document, s.listField, s.serializer, findFilter(query, page, perPage), s.filterVar, query.entityFilter())
    }
}

/** iOS: `findSavedFilters` / `saveFilter` / `destroySavedFilter` (queries inline in `GraphQLQueries.swift`). */
object SavedFiltersRepository {
    const val FIND_QUERY = "query GetAllFilterDefinitions { findSavedFilters { id name mode filter object_filter ui_options find_filter { sort direction } } }"

    const val SAVE_MUTATION = """mutation SaveCatalogFilter(${'$'}input: SaveFilterInput!) {
  saveFilter(input: ${'$'}input) {
    id
    name
    mode
    filter
    object_filter
    ui_options
    find_filter { sort direction }
  }
}"""

    const val DESTROY_MUTATION = """mutation DestroySavedSceneFilter(${'$'}input: DestroyFilterInput!) {
  destroySavedFilter(input: ${'$'}input)
}"""

    suspend fun all(): List<SavedFilter> {
        val data = GraphQL.data(FIND_QUERY)
        return GraphQL.decode(ListSerializer(SavedFilter.serializer()), data["findSavedFilters"] ?: JsonArray(emptyList()))
    }

    /** Builds the `SaveFilterInput` iOS sends (`saveFullObjectFilter` / `saveCatalogSavedFilter`). */
    fun saveInput(
        mode: FilterMode,
        existingId: String?,
        name: String,
        sort: SortOption,
        objectFilter: JsonObject,
        liveFragment: JsonObject?,
        baseSavedFilterId: String? = null,
        labels: Map<String, String> = emptyMap(),
    ): JsonObject {
        val stashy = LinkedHashMap<String, JsonElement>()
        stashy["liveFragment"] = liveFragment ?: JsonObject(emptyMap())
        stashy["sortRaw"] = JsonPrimitive(sort.raw)
        baseSavedFilterId?.let { stashy["baseSavedFilterId"] = JsonPrimitive(it) }
        return buildJsonObject {
            existingId?.let { put("id", JsonPrimitive(it)) }
            put("mode", JsonPrimitive(mode.raw))
            put("name", JsonPrimitive(name.trim()))
            put("find_filter", buildJsonObject {
                put("sort", JsonPrimitive(RandomSeeds.sortField(mode, sort)))
                put("direction", JsonPrimitive(sort.direction))
            })
            put("object_filter", FilterMapper.uiObjectFilter(objectFilter, labels))
            put("ui_options", buildJsonObject { put("stashy", JsonObject(stashy)) })
        }
    }

    suspend fun save(input: JsonObject): SavedFilter {
        val data = GraphQL.data(SAVE_MUTATION, buildJsonObject { put("input", input) })
        val saved = data["saveFilter"] ?: throw GraphQLError.Query("Save filter response missing data")
        return GraphQL.decode(SavedFilter.serializer(), saved)
    }

    suspend fun destroy(id: String) {
        val data = GraphQL.data(DESTROY_MUTATION, buildJsonObject { put("input", buildJsonObject { put("id", JsonPrimitive(id)) }) })
        if (data["destroySavedFilter"].primitiveContent != "true") throw GraphQLError.Query("Could not delete saved filter")
    }
}

/**
 * iOS: `FilterPickerOptionsStore.Kind` + the `fetch*ForFilterPicker` / `searchFilterPickerOptions`
 * queries — "most used" entity lists for the criteria editor's multi-pickers.
 */
enum class PickerKind {
    Studios, Tags, Groups, Performers, ImageTags, ImageStudios, GalleryStudios, PerformerTags, StudioTags, GalleryTags, MarkerTags, AllTags;

    companion object {
        /** iOS: `kind(forCriterionKey:mode:)`. */
        fun forCriterion(key: String, mode: FilterMode): PickerKind? {
            val k = key.lowercase()
            when (k) {
                "performer_tags" -> return PerformerTags
                "scene_tags" -> return Tags
                "parents", "children" -> return AllTags
            }
            if ("tag" in k) return when (mode) {
                FilterMode.Performers -> PerformerTags
                FilterMode.Studios -> StudioTags
                FilterMode.Galleries -> GalleryTags
                FilterMode.Images -> ImageTags
                FilterMode.SceneMarkers -> MarkerTags
                else -> Tags
            }
            if ("studio" in k) return when (mode) {
                FilterMode.Images -> ImageStudios
                FilterMode.Galleries -> GalleryStudios
                else -> Studios
            }
            if ("group" in k || "movie" in k) return Groups
            if ("performer" in k) return Performers
            return null
        }
    }
}

object FilterPickerRepository {
    private const val MAX = 50

    private fun countFilter(field: String) = buildJsonObject { put(field, criterion(0, "GREATER_THAN")) }

    private suspend fun names(document: String, listField: String, filterVar: String?, filter: FindFilter, entity: JsonObject?): List<FilterEntityOption> {
        val variables = buildJsonObject {
            put("filter", filter.json())
            if (filterVar != null && entity != null) put(filterVar, entity)
        }
        val data = GraphQL.named(document, variables)
        val list = (data[document].obj?.get(listField) as? JsonArray) ?: return emptyList()
        return list.mapNotNull { el -> el.obj?.let { o -> o["id"].primitiveContent?.let { FilterEntityOption(it, o["name"].primitiveContent ?: "") } } }
    }

    private suspend fun tags(countField: String?, sort: String, direction: String = "DESC") =
        names("findTags", "tags", "tag_filter", FindFilter(1, MAX, sort, direction), countField?.let { countFilter(it) })

    suspend fun load(kind: PickerKind): List<FilterEntityOption> = when (kind) {
        PickerKind.Studios -> names("findStudios", "studios", "studio_filter", FindFilter(1, MAX, "scenes_count", "DESC"), countFilter("scene_count"))
        PickerKind.ImageStudios -> names("findStudios", "studios", "studio_filter", FindFilter(1, MAX, "images_count", "DESC"), countFilter("image_count"))
        PickerKind.GalleryStudios -> names("findStudios", "studios", "studio_filter", FindFilter(1, MAX, "galleries_count", "DESC"), countFilter("gallery_count"))
        PickerKind.Tags -> tags("scene_count", "scenes_count")
        PickerKind.ImageTags -> tags("image_count", "images_count")
        PickerKind.PerformerTags -> tags("performer_count", "performers_count")
        PickerKind.GalleryTags -> tags("gallery_count", "galleries_count")
        PickerKind.MarkerTags -> tags("marker_count", "scene_markers_count")
        PickerKind.StudioTags -> tags("studio_count", "name", "ASC")
        PickerKind.AllTags -> tags(null, "name", "ASC")
        PickerKind.Groups -> names("findGroups", "groups", "group_filter", FindFilter(1, 1000, "scenes_count", "DESC"), countFilter("scene_count"))
        PickerKind.Performers -> names("findPerformers", "performers", "performer_filter", FindFilter(1, 1000, "scenes_count", "DESC"), null)
    }

    /** iOS: `searchFilterPickerOptions` — name search over the full list (60 hits). */
    suspend fun search(kind: PickerKind, query: String, limit: Int = 60): List<FilterEntityOption> {
        val term = query.trim()
        if (term.isEmpty()) return emptyList()
        val filter = FindFilter(1, limit, sort = null, q = term)
        return when (kind) {
            PickerKind.Studios, PickerKind.ImageStudios, PickerKind.GalleryStudios -> names("findStudios", "studios", null, filter, null)
            PickerKind.Groups -> names("findGroups", "groups", null, filter, null)
            PickerKind.Performers -> names("findPerformers", "performers", null, filter, null)
            else -> names("findTags", "tags", null, filter, null)
        }
    }
}
