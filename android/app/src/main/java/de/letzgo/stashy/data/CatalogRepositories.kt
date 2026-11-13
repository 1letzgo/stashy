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
        val entity = mode.filterEntity
        var merged: JsonObject = base?.filterDict?.let { FilterMapper.sanitize(it, entity = entity) } ?: JsonObject(emptyMap())
        if (!live.isNullOrEmpty()) {
            val m = LinkedHashMap<String, JsonElement>(merged)
            live.forEach { (k, v) -> m[k] = v }
            merged = FilterMapper.sanitize(JsonObject(m), entity = entity)
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
            (l.remove("scene_filter") as? JsonObject)?.let { chips -> FilterMapper.sanitize(chips, entity = FilterMapper.Entity.Scenes).forEach { (k, v) -> sceneNested[k] = v } }
            FilterMapper.sanitize(JsonObject(l), entity = FilterMapper.Entity.Markers).forEach { (k, v) -> marker[k] = v }
            if (sceneNested.isNotEmpty()) marker["scene_filter"] = FilterMapper.sanitize(JsonObject(sceneNested), entity = FilterMapper.Entity.Scenes)
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
            if (nested.isNotEmpty()) out["scene_filter"] = FilterMapper.sanitize(JsonObject(nested), entity = FilterMapper.Entity.Scenes)
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
        // For You: the app's own list (up to 25) on one page; a search narrows it by title.
        if (query.mode == FilterMode.Scenes && query.sort.isForYou) {
            if (page > 1) return Page(0, emptyList())
            val q = query.search.trim()
            val list = de.letzgo.stashy.data.tools.SceneRecommendations.scenesForList()
                .filter { q.isEmpty() || (it.title ?: "").contains(q, ignoreCase = true) }
            @Suppress("UNCHECKED_CAST")
            return Page(list.size, list as List<T>)
        }
        val s = spec<T>(query.mode)
        // Studios by scene count with "Include sub-studio content": one page of every studio,
        // sorted here (the server only counts a studio's own scenes).
        if (query.mode == FilterMode.Studios && SubStudios.sortsBySceneCountAll(query.sort.field, StudioCountsStore.contentDepth != 0)) {
            if (page > 1) return Page(0, emptyList())
            val variables = buildJsonObject {
                put("filter", findFilter(query, 1, -1).json())
                query.entityFilter()?.let { put(s.filterVar, it) }
            }
            val data = GraphQL.data(SubStudios.withSceneCountAll(GraphQLQueries.load(s.document)), variables)
            val obj = data["findStudios"].obj ?: throw GraphQLError.Query("Missing findStudios")
            val studios = GraphQL.decode(ListSerializer(Studio.serializer()), obj["studios"] ?: JsonArray(emptyList()))
            val sorted = SubStudios.sortedBySceneCountAll(studios, query.sort.isAscending)
            @Suppress("UNCHECKED_CAST")
            return Page(obj["count"].stringOrNull?.toIntOrNull() ?: sorted.size, sorted as List<T>)
        }
        // Tags: the counts over all sub-tags while "Include sub-tag content" is on; with the scene
        // count sort (Tags list only) one page of every tag, sorted here.
        if (query.mode == FilterMode.Tags) {
            val include = TagHierarchyStore.includesContent
            val sortsHere = query.scope == null && SubTags.sortsBySceneCountAll(query.sort.field, include)
            if (sortsHere && page > 1) return Page(0, emptyList())
            val variables = buildJsonObject {
                put("filter", findFilter(query, page, if (sortsHere) -1 else perPage).json())
                query.entityFilter()?.let { put(s.filterVar, it) }
            }
            val data = GraphQL.data(SubTags.withCountsAll(GraphQLQueries.load(s.document), include), variables)
            val obj = data["findTags"].obj ?: throw GraphQLError.Query("Missing findTags")
            val tags = GraphQL.decode(ListSerializer(Tag.serializer()), obj["tags"] ?: JsonArray(emptyList()))
            val shown = if (sortsHere) SubTags.sortedBySceneCountAll(tags, query.sort.isAscending) else tags
            @Suppress("UNCHECKED_CAST")
            return Page(obj["count"].stringOrNull?.toIntOrNull() ?: shown.size, shown as List<T>)
        }
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
        labels: Map<FilterMapper.LabelKind, Map<String, String>> = emptyMap(),
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
            // Web UI storage shape, not the query shape (see `FilterMapper.savedObjectFilter`).
            put("object_filter", FilterMapper.savedObjectFilter(objectFilter, mode.filterEntity) { kind, id -> labels[kind]?.get(id) })
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
    Studios, Tags, Groups, Performers, ImageTags, ImageStudios, GalleryStudios, PerformerTags, StudioTags, GalleryTags, MarkerTags, AllTags,
    /** Folder criterion (scenes / images `folder`, galleries `parent_folder`), named by path. */
    Folders;

    /** Entity the picked ids name, for the saved filter's `{id, label}` pairs. */
    val labelKind: FilterMapper.LabelKind get() = when (this) {
        Studios, ImageStudios, GalleryStudios -> FilterMapper.LabelKind.Studio
        Tags, ImageTags, PerformerTags, StudioTags, GalleryTags, MarkerTags, AllTags -> FilterMapper.LabelKind.Tag
        Groups -> FilterMapper.LabelKind.Group
        Performers -> FilterMapper.LabelKind.Performer
        Folders -> FilterMapper.LabelKind.Folder
    }

    companion object {
        /** iOS: `kind(forCriterionKey:mode:)`. */
        fun forCriterion(key: String, mode: FilterMode): PickerKind? {
            val k = key.lowercase()
            when (k) {
                "performer_tags" -> return PerformerTags
                "scene_tags" -> return Tags
                // On studios `parents` are parent studios, not tags.
                "parents" -> return if (mode == FilterMode.Studios) Studios else AllTags
                "children" -> return AllTags
                "folder", "parent_folder" -> return Folders
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
        PickerKind.Folders -> folders(null, 300)
    }

    /**
     * Folders for the Folder criterion (Stash 0.32+), named by their full path like the web UI.
     * Without a search term: the first folders by path.
     */
    private suspend fun folders(pathContains: String?, limit: Int): List<FilterEntityOption> {
        if (!ServerCapabilities.supports032) return emptyList()
        val variables = buildJsonObject {
            put("filter", FindFilter(1, limit, "path", "ASC").json())
            if (!pathContains.isNullOrEmpty()) put("folder_filter", buildJsonObject { put("path", criterion(pathContains, "INCLUDES")) })
        }
        val data = GraphQL.named("findFolderPickerOptions", variables)
        val list = (data["findFolders"].obj?.get("folders") as? JsonArray) ?: return emptyList()
        return list.mapNotNull { el -> el.obj?.let { o -> o["id"].primitiveContent?.let { FilterEntityOption(it, o["path"].primitiveContent ?: "") } } }
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
            PickerKind.Folders -> folders(term, limit)
            else -> names("findTags", "tags", null, filter, null)
        }
    }
}
