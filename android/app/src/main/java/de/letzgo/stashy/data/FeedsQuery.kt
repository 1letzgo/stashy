package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Hook for the shared filter port (`ui/filter/`). The Feeds queries run saved-filter JSON and
 * advanced criteria through [sanitizer]; the filter agent can replace it with its full
 * `FilterMapper` port at merge without touching the Feeds code.
 */
object FeedsFilterHooks {
    /** iOS: `FilterMapper.sanitize(_:isMarker:)`. Default = [FeedFilterMapper.sanitize]. */
    @Volatile var sanitizer: (JsonObject, Boolean) -> JsonObject = { dict, isMarker -> FeedFilterMapper.sanitize(dict, isMarker) }
}

/**
 * Compact port of iOS `FilterMapper.sanitize`: turns a saved filter's `object_filter` (Stash web
 * UI storage format, `value: { items, excluded, depth }`) into GraphQL `*FilterType` input.
 * Covers the criterion shapes the Feeds need; the full mapper comes with the filter port.
 */
object FeedFilterMapper {
    private val invalidTopKeys = setOf("id", "sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection", "type", "inputType", "criterionOption")
    private val multiSelect = setOf("performers", "studios", "tags", "galleries", "scenes", "groups", "movies", "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups")
    private val hierarchical = setOf("tags", "studios", "groups", "movies", "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups")
    private val stringExtraction = setOf("is_missing", "has_markers", "has_chapters")
    private val booleanFields = setOf("interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite", "filter_favorites", "has_image", "ignore_auto_tag")
    private val intFields = setOf("rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id")
    private val singleEnum = setOf("gender", "ethnicity", "fake_tits", "hair_color", "eye_color", "career_length")
    private val sceneSpecific = setOf("orientation", "duration", "rating100", "organized", "performers", "studios", "movies")

    fun sanitize(dict: JsonObject, isMarker: Boolean = false): JsonObject {
        val out = LinkedHashMap<String, JsonElement>()
        // 1. Legacy `c` criteria array (Stash UI).
        (dict["c"] as? JsonArray)?.forEach { item ->
            val obj = item as? JsonObject ?: return@forEach
            var key = (obj["id"] as? JsonPrimitive)?.contentOrNull ?: return@forEach
            if (key == "rating") key = "rating100"
            val processed = processCriterion(key, obj) ?: return@forEach
            if (isMarker && key in sceneSpecific) {
                val nested = (out["scene_filter"] as? JsonObject)?.toMutableMap() ?: mutableMapOf()
                nested[key] = processed
                out["scene_filter"] = JsonObject(nested)
            } else out[key] = processed
        }
        for ((key, value) in dict) {
            if (key == "c" || key in invalidTopKeys) continue
            out[key] = when {
                key == "AND" || key == "OR" || key == "NOT" -> when (value) {
                    is JsonObject -> sanitize(value)
                    is JsonArray -> JsonArray(value.map { (it as? JsonObject)?.let { o -> sanitize(o) } ?: it })
                    else -> value
                }
                key.endsWith("_filter") -> (value as? JsonObject)?.let { sanitize(it) } ?: value
                value is JsonObject -> processCriterion(key, value) ?: continue
                else -> value
            }
        }
        omitEmptyMultiIdCriteria(out)
        return JsonObject(out)
    }

    private fun omitEmptyMultiIdCriteria(dict: MutableMap<String, JsonElement>) {
        for (key in listOf("tags", "studios", "groups", "performers", "galleries", "scenes", "movies")) {
            val c = dict[key] as? JsonObject ?: continue
            val modifier = (c["modifier"] as? JsonPrimitive)?.contentOrNull?.uppercase().orEmpty()
            if (modifier == "IS_NULL" || modifier == "NOT_NULL") continue
            if (idStrings(c["value"]).isEmpty() && idStrings(c["excludes"]).isEmpty()) dict.remove(key)
        }
        (dict["scene_filter"] as? JsonObject)?.let { nested ->
            val m = nested.toMutableMap()
            omitEmptyMultiIdCriteria(m)
            if (m.isEmpty()) dict.remove("scene_filter") else dict["scene_filter"] = JsonObject(m)
        }
    }

    private fun processCriterion(key: String, dict: JsonObject): JsonElement? {
        val sub = dict.toMutableMap()
        listOf("id", "type", "inputType", "criterionOption").forEach { sub.remove(it) }
        (sub["value"] as? JsonObject)?.let { v ->
            when {
                v["value"] != null -> sub["value"] = v["value"]!!
                v["id"] != null -> sub["value"] = v["id"]!!
                else -> {
                    val items = v["items"] as? JsonArray
                    if (items != null && items.isNotEmpty()) {
                        sub["value"] = items
                        v["depth"]?.let { sub["depth"] = it }
                    }
                    val excluded = v["excluded"] as? JsonArray
                    if (excluded != null && excluded.isNotEmpty()) {
                        sub["excludes"] = excluded
                        if (sub["depth"] == null) v["depth"]?.let { sub["depth"] = it }
                    }
                    if ((items == null || items.isEmpty()) && sub["value"] is JsonObject) sub.remove("value")
                }
            }
        }
        (sub["value2"] as? JsonObject)?.get("value")?.let { sub["value2"] = it }
        (sub["excludes"] as? JsonObject)?.let { e ->
            when {
                e["value"] != null -> sub["excludes"] = e["value"]!!
                e["id"] != null -> sub["excludes"] = e["id"]!!
                else -> (e["items"] as? JsonArray)?.let { sub["excludes"] = it }
            }
        }
        if (key in stringExtraction) {
            val v = sub["value"]
            return JsonPrimitive(when (v) {
                is JsonArray -> (v.firstOrNull() as? JsonPrimitive)?.contentOrNull.orEmpty()
                is JsonPrimitive -> v.contentOrNull.orEmpty()
                else -> ""
            })
        }
        if (key == "orientation") {
            sub["value"] = when (val v = sub["value"]) {
                is JsonArray -> JsonArray(v.mapNotNull { el ->
                    ((el as? JsonPrimitive)?.contentOrNull ?: ((el as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull)?.uppercase()?.let { JsonPrimitive(it) }
                })
                is JsonPrimitive -> JsonArray(listOf(JsonPrimitive(v.content.uppercase())))
                else -> v ?: JsonNull
            }
            sub.remove("modifier")
        }
        if (key == "resolution" || key == "average_resolution") {
            (sub["value"] as? JsonPrimitive)?.takeIf { it.isString }?.let { sub["value"] = JsonPrimitive(it.content.uppercase()) }
        }
        if (key in intFields || key.endsWith("_count")) {
            sub["value"]?.let { sub["value"] = castToInt(it) }
            sub["value2"]?.let { sub["value2"] = castToInt(it) }
            val mod = (sub["modifier"] as? JsonPrimitive)?.contentOrNull
            if ((mod == "IS_NULL" || mod == "NOT_NULL") && sub["value"] == null) sub["value"] = JsonPrimitive(0)
        }
        if (key in multiSelect) {
            if (sub["value"] != null) sub["value"] = JsonArray(idStrings(sub["value"]).map { JsonPrimitive(it) })
            if (sub["excludes"] != null) sub["excludes"] = JsonArray(idStrings(sub["excludes"]).map { JsonPrimitive(it) })
            if (key in hierarchical) {
                if (sub["depth"] == null && idStrings(sub["value"]).isNotEmpty()) sub["depth"] = JsonPrimitive(0)
            } else sub.remove("depth")
        }
        if (key in singleEnum) {
            when (val v = sub["value"]) {
                is JsonArray -> (v.firstOrNull() as? JsonPrimitive)?.contentOrNull?.let { sub["value"] = JsonPrimitive(it.uppercase()) }
                is JsonPrimitive -> if (v.isString) sub["value"] = JsonPrimitive(v.content.uppercase())
                else -> {}
            }
        }
        if (key in booleanFields) {
            sub["value"]?.let { v ->
                val p = v as? JsonPrimitive
                val b = p?.booleanOrNull ?: p?.contentOrNull?.lowercase()?.let { it == "true" || it == "1" || it == "yes" } ?: false
                return JsonPrimitive(b)
            }
        }
        return JsonObject(sub)
    }

    private fun castToInt(v: JsonElement): JsonElement {
        val p = v as? JsonPrimitive ?: return v
        p.intOrNull?.let { return JsonPrimitive(it) }
        p.doubleOrNull?.let { return JsonPrimitive(it.toInt()) }
        p.longOrNull?.let { return JsonPrimitive(it) }
        return v
    }

    /** iOS: `FilterMapper.idStrings(from:)`. */
    fun idStrings(value: JsonElement?): List<String> = when (value) {
        null, JsonNull -> emptyList()
        is JsonObject -> when {
            value["items"] != null -> idStrings(value["items"])
            value["id"] != null -> idStrings(value["id"])
            else -> emptyList()
        }
        is JsonArray -> value.mapNotNull { idString(it) }
        is JsonPrimitive -> listOfNotNull(idString(value))
    }

    private fun idString(value: JsonElement): String? = when (value) {
        is JsonPrimitive -> value.contentOrNull?.trim()?.takeIf { it.isNotEmpty() && value !is JsonNull }
        is JsonObject -> value["id"]?.let { idString(it) } ?: value["value"]?.let { idString(it) }
        else -> null
    }
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
     * Saved filter → GraphQL entity filter: sanitized `object_filter`, its stashy live fragment on
     * top, then the advanced criteria ([live]) on top of that (iOS order in `loadScenesPage`).
     */
    fun entityFilter(
        filter: SavedFilter?,
        live: JsonObject?,
        isMarker: Boolean = false,
        sanitize: (JsonObject, Boolean) -> JsonObject = FeedsFilterHooks.sanitizer,
    ): MutableMap<String, JsonElement> {
        val out = LinkedHashMap<String, JsonElement>()
        (filter?.objectFilter as? JsonObject)?.let { out.putAll(sanitize(it, isMarker)) }
        stashyLiveFragment(filter)?.let { out.putAll(sanitize(it, false)) }
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
                put("depth", JsonPrimitive(0))
            }
        }
        criteria.studio?.let {
            val studios = buildJsonObject {
                put("modifier", JsonPrimitive("INCLUDES")); put("value", JsonArray(listOf(JsonPrimitive(it.id)))); put("depth", JsonPrimitive(0))
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
        if (kind == FeedQueryKind.Clips) {
            entity.remove("path")
            val path = buildJsonObject { put("value", JsonPrimitive(VIDEO_REGEX)); put("modifier", JsonPrimitive("MATCHES_REGEX")) }
            val ordered = LinkedHashMap<String, JsonElement>()
            ordered["path"] = path
            ordered.putAll(entity)
            entity.clear(); entity.putAll(ordered)
        }
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
