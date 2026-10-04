package de.letzgo.stashy.ui.home

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * iOS: `FilterMapper.sanitize` (SharedUtilities.swift) — turns a saved filter's web-UI
 * `object_filter` into the GraphQL filter shape. Ported here for the dashboard's default
 * filter only; keep it in step with the catalog's filter mapping.
 */
object DashboardFilterMapper {
    private val invalidTopKeys = setOf("id", "sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection", "type", "inputType", "criterionOption")
    private val multiSelect = setOf("performers", "studios", "tags", "galleries", "scenes", "groups", "movies", "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups")
    private val hierarchical = setOf("tags", "studios", "groups", "movies", "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups")
    private val emptyMultiKeys = setOf("tags", "studios", "groups", "performers", "galleries", "scenes", "movies")
    private val stringExtraction = setOf("is_missing", "has_markers", "has_chapters")
    private val booleanFields = setOf("interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite", "filter_favorites", "has_image", "ignore_auto_tag")
    private val singleEnum = setOf("gender", "ethnicity", "fake_tits", "hair_color", "eye_color", "career_length")
    private val intFields = setOf("rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id")

    fun sanitize(dict: JsonObject): JsonObject {
        val map = LinkedHashMap<String, JsonElement>(dict)
        // Stash UI "c" criteria array.
        (map["c"] as? JsonArray)?.let { criteria ->
            val fromC = LinkedHashMap<String, JsonElement>()
            criteria.mapNotNull { it as? JsonObject }.forEach { item ->
                var key = (item["id"] as? JsonPrimitive)?.contentOrNull ?: return@forEach
                if (key == "rating") key = "rating100"
                fromC[key] = if (item.containsKey("c") || item.containsKey("AND") || item.containsKey("OR") || item.containsKey("NOT")) sanitize(item) else processCriterion(key, item)
            }
            map.remove("c")
            fromC.putAll(map)
            map.clear(); map.putAll(fromC)
        }
        invalidTopKeys.forEach { map.remove(it) }
        for ((key, value) in map.toMap()) {
            when {
                key in setOf("AND", "OR", "NOT") -> map[key] = when (value) {
                    is JsonArray -> JsonArray(value.map { (it as? JsonObject)?.let(::sanitize) ?: it })
                    is JsonObject -> sanitize(value)
                    else -> value
                }
                key.endsWith("_filter") -> (value as? JsonObject)?.let { map[key] = sanitize(it) }
                value is JsonObject -> map[key] = processCriterion(key, value)
            }
        }
        for (k in emptyMultiKeys) {
            val c = map[k] as? JsonObject ?: continue
            val mod = (c["modifier"] as? JsonPrimitive)?.contentOrNull?.uppercase().orEmpty()
            if (mod == "IS_NULL" || mod == "NOT_NULL") continue
            if (ids(c["value"]).isEmpty() && ids(c["excludes"]).isEmpty()) map.remove(k)
        }
        return JsonObject(map)
    }

    private fun processCriterion(key: String, dict: JsonObject): JsonElement {
        val sub = LinkedHashMap<String, JsonElement>(dict)
        listOf("id", "type", "inputType", "criterionOption").forEach { sub.remove(it) }
        (sub["value"] as? JsonObject)?.let { v ->
            when {
                v.containsKey("value") -> sub["value"] = v["value"]!!
                v.containsKey("id") -> sub["value"] = v["id"]!!
                else -> {
                    (v["items"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { sub["value"] = it; v["depth"]?.let { d -> sub["depth"] = d } }
                    (v["excluded"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { sub["excludes"] = it; if (sub["depth"] == null) v["depth"]?.let { d -> sub["depth"] = d } }
                }
            }
        }
        (sub["value2"] as? JsonObject)?.get("value")?.let { sub["value2"] = it }
        (sub["excludes"] as? JsonObject)?.let { e ->
            when {
                e.containsKey("value") -> sub["excludes"] = e["value"]!!
                e.containsKey("id") -> sub["excludes"] = e["id"]!!
                else -> (e["items"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { sub["excludes"] = it }
            }
        }
        if (key in stringExtraction) {
            val v = sub["value"]
            return JsonPrimitive(
                (v as? JsonPrimitive)?.contentOrNull ?: ((v as? JsonArray)?.firstOrNull() as? JsonPrimitive)?.contentOrNull
                    ?: (sub["id"] as? JsonPrimitive)?.contentOrNull ?: "",
            )
        }
        if (key == "orientation") {
            val v = sub["value"]
            sub["value"] = JsonArray(
                when (v) {
                    is JsonArray -> v.mapNotNull { (it as? JsonPrimitive)?.contentOrNull ?: ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull }
                    is JsonPrimitive -> listOfNotNull(v.contentOrNull)
                    else -> emptyList()
                }.map { JsonPrimitive(it.uppercase()) },
            )
            sub.remove("modifier")
        }
        if (key == "resolution" || key == "average_resolution") (sub["value"] as? JsonPrimitive)?.contentOrNull?.let { sub["value"] = JsonPrimitive(it.uppercase()) }
        if (key in intFields || key.endsWith("_count")) {
            sub["value"]?.let { sub["value"] = castInt(it) }
            sub["value2"]?.let { sub["value2"] = castInt(it) }
            val mod = (sub["modifier"] as? JsonPrimitive)?.contentOrNull
            if ((mod == "IS_NULL" || mod == "NOT_NULL") && sub["value"] == null) sub["value"] = JsonPrimitive(0)
        }
        if (key in multiSelect) {
            if (sub["value"] != null) sub["value"] = JsonArray(ids(sub["value"]).map(::JsonPrimitive))
            if (sub["excludes"] != null) sub["excludes"] = JsonArray(ids(sub["excludes"]).map(::JsonPrimitive))
            if (key in hierarchical) { if (sub["depth"] == null && ids(sub["value"]).isNotEmpty()) sub["depth"] = JsonPrimitive(0) } else sub.remove("depth")
        }
        if (key in singleEnum) {
            val v = sub["value"]
            ((v as? JsonArray)?.firstOrNull() as? JsonPrimitive ?: v as? JsonPrimitive)?.contentOrNull?.let { sub["value"] = JsonPrimitive(it.uppercase()) }
        }
        if (key in booleanFields) sub["value"]?.let { return JsonPrimitive(castBool(it)) }
        return JsonObject(sub)
    }

    private fun castInt(v: JsonElement): JsonElement {
        val p = v as? JsonPrimitive ?: return v
        p.intOrNull?.let { return JsonPrimitive(it) }
        p.doubleOrNull?.let { return JsonPrimitive(it.toInt()) }
        return v
    }

    private fun castBool(v: JsonElement): Boolean {
        val p = v as? JsonPrimitive ?: return false
        p.booleanOrNull?.let { return it }
        val s = p.contentOrNull?.lowercase() ?: return false
        return s == "true" || s == "1" || s == "yes"
    }

    /** iOS `idStrings(from:)`. */
    fun ids(v: JsonElement?): List<String> = when (v) {
        null, JsonNull -> emptyList()
        is JsonArray -> v.flatMap { ids(it) }
        is JsonObject -> when {
            v.containsKey("items") -> ids(v["items"])
            v.containsKey("id") -> ids(v["id"])
            v.containsKey("value") -> ids(v["value"])
            else -> emptyList()
        }
        is JsonPrimitive -> listOfNotNull(v.contentOrNull?.trim()?.takeIf { it.isNotEmpty() })
    }
}
