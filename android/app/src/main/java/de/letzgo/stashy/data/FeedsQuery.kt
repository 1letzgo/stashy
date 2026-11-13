package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull

/**
 * Hook for the shared filter code. The Feeds queries run saved-filter JSON and advanced criteria
 * through [sanitizer] (tests swap in an identity function).
 */
object FeedsFilterHooks {
    /** iOS: `FilterMapper.sanitize(_:isMarker:)`. */
    @Volatile var sanitizer: (JsonObject, Boolean) -> JsonObject = { dict, isMarker -> FilterMapper.sanitize(dict, isMarker) }
}

/** Performer / tags / studio handed to Feeds (iOS: `selectedPerformer`, `selectedTags`, `selectedStudio`). */
data class FeedCriteria(
    val performer: IdName? = null,
    val tags: List<IdName> = emptyList(),
    val studio: IdName? = null,
) {
    val isEmpty: Boolean get() = performer == null && tags.isEmpty() && studio == null
}

/** Which GraphQL query a Feeds mode runs. */
enum class FeedQueryKind { Scenes, Markers, Clips, Previews, Pics }

/**
 * Pure builders for the Feeds GraphQL variables (iOS: `loadScenesPage`, `loadMarkersPage`,
 * `fetchClips`, `mergeFilterWithCriteria`). Kept free of Android/network code — unit-tested.
 */
object FeedsQuery {
    /** iOS `fetchClips`: video-like and animated image files only. */
    const val VIDEO_REGEX = "(?i).*\\.(mp4|gif|webp|mov|webm|m4v|mkv)$"

    /** File extensions the Clips feed treats as video or animation (iOS `clipExtensions`). */
    val CLIP_EXTENSIONS = listOf("mp4", "gif", "webp", "mov", "webm", "m4v", "mkv")

    /**
     * iOS `clipImageFilter`: one `path INCLUDES` per extension (a plain SQL LIKE), chained with
     * OR and joined to the other criteria with AND. A `MATCHES_REGEX` made Stash run its regex
     * on every image row (about 2 s against 1.2 s per page on a large library). The regex stays
     * only when the criteria use AND / OR / NOT themselves: Stash allows one per level.
     */
    fun applyClipPathCriteria(entity: MutableMap<String, JsonElement>) {
        entity.remove("path")
        if (entity.containsKey("AND") || entity.containsKey("OR") || entity.containsKey("NOT")) {
            entity["path"] = buildJsonObject { put("value", JsonPrimitive(VIDEO_REGEX)); put("modifier", JsonPrimitive("MATCHES_REGEX")) }
            return
        }
        var chain: JsonObject? = null
        for (ext in CLIP_EXTENSIONS.reversed()) {
            val next = chain
            chain = buildJsonObject {
                put("path", buildJsonObject { put("value", JsonPrimitive(".$ext")); put("modifier", JsonPrimitive("INCLUDES")) })
                if (next != null) put("OR", next)
            }
        }
        entity["AND"] = chain!!
    }

    /** iOS per-page sizes (`scenesPerPage` 20 on iPhone, markers/previews/clips 20). */
    const val PER_PAGE = 20

    /** iOS: `"random_<seed>"` for random sorts, the plain field otherwise. */
    fun sortField(sort: FeedSort, seed: Int): String = if (sort.isRandom) "random_$seed" else sort.sortField

    fun findFilter(page: Int, perPage: Int, sort: FeedSort, seed: Int): JsonObject = buildJsonObject {
        put("page", JsonPrimitive(page))
        put("per_page", JsonPrimitive(perPage))
        put("sort", JsonPrimitive(sortField(sort, seed)))
        put("direction", JsonPrimitive(sort.direction))
    }

    /** `ui_options.stashy.liveFragment` of a filter saved by stashy (iOS: `stashyLiveFragment`). */
    fun stashyLiveFragment(filter: SavedFilter?): JsonObject? =
        ((filter?.uiOptions as? JsonObject)?.get("stashy") as? JsonObject)?.get("liveFragment") as? JsonObject

    /** `ui_options.stashy.sortRaw` (iOS: `stashySortRaw`). */
    fun stashySortRaw(filter: SavedFilter?): String? =
        (((filter?.uiOptions as? JsonObject)?.get("stashy") as? JsonObject)?.get("sortRaw") as? JsonPrimitive)?.contentOrNull

    /** iOS: `SavedFilter.resolvedSceneSort` (stashy sortRaw, then `find_filter`). */
    fun resolvedSceneSort(filter: SavedFilter?): SceneSortOption? =
        SceneSortOption.from(stashySortRaw(filter)) ?: filter?.findFilter?.let {
            SceneSortOption.fromGraphQL((it["sort"] as? JsonPrimitive)?.contentOrNull, (it["direction"] as? JsonPrimitive)?.contentOrNull)
        }

    /** iOS: `SavedFilter.resolvedImageSort`. */
    fun resolvedImageSort(filter: SavedFilter?): ImageSortOption? =
        ImageSortOption.from(stashySortRaw(filter)) ?: filter?.findFilter?.let {
            ImageSortOption.fromGraphQL((it["sort"] as? JsonPrimitive)?.contentOrNull, (it["direction"] as? JsonPrimitive)?.contentOrNull)
        }

    /**
     * Saved filter → GraphQL entity filter: sanitized `object_filter`, then the advanced criteria
     * ([live]) on top. `object_filter` already holds the chips merged at save time; the old
     * `ui_options.stashy.liveFragment` copy is not layered on top any more, or it would undo
     * edits made in Stash itself.
     */
    fun entityFilter(
        filter: SavedFilter?,
        live: JsonObject?,
        isMarker: Boolean = false,
        sanitize: (JsonObject, Boolean) -> JsonObject = FeedsFilterHooks.sanitizer,
    ): MutableMap<String, JsonElement> {
        val out = LinkedHashMap<String, JsonElement>()
        (filter?.objectFilter as? JsonObject)?.let { out.putAll(sanitize(it, isMarker)) }
        if (live != null && live.isNotEmpty()) out.putAll(sanitize(live, false))
        return out
    }

    /** iOS: `mergeFilterWithCriteria` — the handed performer / tags / studio replace those keys. */
    fun applyCriteria(target: MutableMap<String, JsonElement>, criteria: FeedCriteria, kind: FeedQueryKind) {
        criteria.performer?.let {
            target["performers"] = buildJsonObject { put("modifier", JsonPrimitive("INCLUDES")); put("value", JsonArray(listOf(JsonPrimitive(it.id)))) }
        }
        if (criteria.tags.isNotEmpty()) {
            target["tags"] = buildJsonObject {
                put("modifier", JsonPrimitive("INCLUDES"))
                put("value", JsonArray(criteria.tags.map { JsonPrimitive(it.id) }))
                put("depth", JsonPrimitive(TagHierarchyStore.contentDepth))
            }
        }
        criteria.studio?.let {
            val studios = buildJsonObject {
                put("modifier", JsonPrimitive("INCLUDES")); put("value", JsonArray(listOf(JsonPrimitive(it.id)))); put("depth", JsonPrimitive(StudioCountsStore.contentDepth))
            }
            if (kind == FeedQueryKind.Markers) {
                // SceneMarkerFilterType has no `studios` — it is a scene criterion there.
                val nested = (target["scene_filter"] as? JsonObject)?.toMutableMap() ?: mutableMapOf()
                nested["studios"] = studios
                target["scene_filter"] = JsonObject(nested)
            } else target["studios"] = studios
        }
    }

    /**
     * Variables for one Feeds page. Scenes and previews share `findScenes`, markers run
     * `findSceneMarkers` (`scene_marker_filter`), clips and pics `findImages` (`image_filter`,
     * clips with the video regex on `path`).
     */
    fun variables(
        kind: FeedQueryKind,
        page: Int,
        perPage: Int,
        sort: FeedSort,
        seed: Int,
        filter: SavedFilter?,
        live: JsonObject? = null,
        criteria: FeedCriteria = FeedCriteria(),
        sanitize: (JsonObject, Boolean) -> JsonObject = FeedsFilterHooks.sanitizer,
    ): JsonObject {
        val isMarker = kind == FeedQueryKind.Markers
        val entity = entityFilter(filter, live, isMarker, sanitize)
        applyCriteria(entity, criteria, kind)
        if (kind == FeedQueryKind.Clips) applyClipPathCriteria(entity)
        val filterVar = when (kind) {
            FeedQueryKind.Scenes, FeedQueryKind.Previews -> "scene_filter"
            FeedQueryKind.Markers -> "scene_marker_filter"
            FeedQueryKind.Clips, FeedQueryKind.Pics -> "image_filter"
        }
        return buildJsonObject {
            put("filter", findFilter(page, perPage, sort, seed))
            if (entity.isNotEmpty()) put(filterVar, JsonObject(entity))
        }
    }
}
