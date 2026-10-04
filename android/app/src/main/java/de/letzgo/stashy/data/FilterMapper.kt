package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject

// Small JSON helpers used by the filter code (the iOS side works on `[String: Any]`).

/** `JsonObject` from a mutable map, keeping insertion order. */
fun jsonObjectOf(map: Map<String, JsonElement>): JsonObject = JsonObject(LinkedHashMap(map))

fun JsonObject.with(key: String, value: JsonElement?): JsonObject {
    val m = LinkedHashMap<String, JsonElement>(this)
    if (value == null) m.remove(key) else m[key] = value
    return JsonObject(m)
}

fun JsonObject.without(key: String): JsonObject = with(key, null)

val JsonElement?.isJsonNull: Boolean get() = this == null || this is JsonNull

/** Primitive string content (also for numbers/bools); `null` for objects/arrays/null. */
val JsonElement?.primitiveContent: String? get() = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content

/** Number value of a non-string primitive (`5`, `5.0`), else `null` (iOS `is Int || is Double`). */
val JsonElement?.numberOrNull: Double? get() {
    val p = this as? JsonPrimitive ?: return null
    if (p is JsonNull || p.isString) return null
    if (p.booleanOrNull != null) return null
    return p.content.toDoubleOrNull()
}

val JsonElement?.boolOrNull: Boolean? get() {
    val p = this as? JsonPrimitive ?: return null
    if (p is JsonNull || p.isString) return null
    return p.booleanOrNull
}

/** String value of a string primitive only (iOS `as? String`). */
val JsonElement?.stringValue: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

/** Number primitive keeping Int-ness like iOS (`5` stays `5`, not `5.0`). */
fun jsonNumber(value: Double): JsonPrimitive =
    if (value == Math.floor(value) && !value.isInfinite() && kotlin.math.abs(value) < 1e15) JsonPrimitive(value.toLong()) else JsonPrimitive(value)

/**
 * iOS: `FilterMapper` (SharedUtilities.swift) — sanitizes Stash UI / saved-filter criteria into the
 * GraphQL shape, and rewrites GraphQL criteria into the web UI storage shape for saving.
 */
object FilterMapper {
    private val logicKeys = setOf("AND", "OR", "NOT")

    fun sanitize(dict: JsonObject, isMarker: Boolean = false): JsonObject {
        var newDict = LinkedHashMap<String, JsonElement>(dict)

        // 1. Stash UI `c` criteria array.
        val criteria = newDict["c"] as? JsonArray
        if (criteria != null) {
            val fromC = LinkedHashMap<String, JsonElement>()
            for (el in criteria) {
                val item = el as? JsonObject ?: continue
                var key = item["id"].stringValue ?: continue
                if (key == "rating") key = "rating100"
                val processed: JsonElement =
                    if (item["c"] != null || item["AND"] != null || item["OR"] != null || item["NOT"] != null) sanitize(item, false)
                    else processCriterion(key, item)
                if (isMarker && isSceneSpecificKey(key)) {
                    val nested = LinkedHashMap<String, JsonElement>((fromC["scene_filter"] as? JsonObject) ?: JsonObject(emptyMap()))
                    nested[key] = processed
                    fromC["scene_filter"] = JsonObject(nested)
                } else {
                    fromC[key] = processed
                }
            }
            newDict.remove("c")
            val combined = LinkedHashMap(fromC)
            newDict.forEach { (k, v) -> combined[k] = v }
            newDict = combined
        }

        // 2. UI-only top-level keys.
        listOf("id", "sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection", "type", "inputType", "criterionOption")
            .forEach { newDict.remove(it) }

        // 3. Recurse.
        for ((key, value) in newDict.entries.toList()) {
            if (key in logicKeys) {
                when (value) {
                    is JsonArray -> newDict[key] = JsonArray(value.map { (it as? JsonObject)?.let { o -> sanitize(o, false) } ?: it })
                    is JsonObject -> newDict[key] = sanitize(value, false)
                    else -> {}
                }
                continue
            }
            if (key.endsWith("_filter")) {
                if (value is JsonObject) newDict[key] = sanitize(value, false)
                continue
            }
            if (value is JsonObject) newDict[key] = processCriterion(key, value)
        }
        omitEmptyMultiIdCriteria(newDict)
        return JsonObject(newDict)
    }

    private val omitKeys = listOf("tags", "studios", "groups", "performers", "galleries", "scenes", "movies")

    /** `INCLUDES` with no ids = "Any": drop the criterion (exclude-only criteria survive). */
    private fun omitEmptyMultiIdCriteria(dict: LinkedHashMap<String, JsonElement>) {
        for (key in omitKeys) {
            val criterion = dict[key] as? JsonObject ?: continue
            val modifier = criterion["modifier"].primitiveContent?.uppercase() ?: ""
            if (modifier == "IS_NULL" || modifier == "NOT_NULL") continue
            if (idStrings(criterion["value"]).isEmpty() && idStrings(criterion["excludes"]).isEmpty()) dict.remove(key)
        }
        val nested = dict["scene_filter"] as? JsonObject
        if (nested != null) {
            val m = LinkedHashMap<String, JsonElement>(nested)
            omitEmptyMultiIdCriteria(m)
            if (m.isEmpty()) dict.remove("scene_filter") else dict["scene_filter"] = JsonObject(m)
        }
    }

    private fun isSceneSpecificKey(key: String) =
        key in setOf("orientation", "duration", "rating100", "organized", "performers", "studios", "movies")

    val uiMultiSelectFields = setOf("performers", "studios", "tags", "galleries", "scenes", "groups", "movies")
    private val uiHierarchicalFields = setOf("tags", "studios", "groups", "movies")
    private val uiScalarCriterionFields = setOf(
        "is_missing", "has_markers", "has_chapters", "interactive", "organized", "favorite", "performer_favorite",
        "studio_favorite", "gallery_favorite", "filter_favorites", "has_image", "ignore_auto_tag",
    )

    /** GraphQL-shaped criteria → web UI storage shape (`value: { items, excluded, depth }`). */
    fun uiObjectFilter(dict: JsonObject, labels: Map<String, String> = emptyMap()): JsonObject {
        val out = LinkedHashMap<String, JsonElement>()
        for ((key, value) in dict) {
            val criterion = value as? JsonObject
            if (criterion == null) {
                if (key in uiScalarCriterionFields && value is JsonPrimitive && value !is JsonNull) {
                    val text = value.booleanOrNull?.let { if (it) "true" else "false" } ?: value.content
                    out[key] = buildJsonObject { put("value", JsonPrimitive(text)); put("modifier", JsonPrimitive("EQUALS")) }
                } else {
                    out[key] = value
                }
                continue
            }
            if (key in logicKeys || key.endsWith("_filter")) {
                out[key] = uiObjectFilter(criterion, labels)
                continue
            }
            if (key !in uiMultiSelectFields) {
                out[key] = criterion
                continue
            }
            fun entries(raw: JsonElement?) = JsonArray(idStrings(raw).map { id ->
                buildJsonObject { put("id", JsonPrimitive(id)); put("label", JsonPrimitive(labels[id] ?: id)) }
            })
            val uiValue = LinkedHashMap<String, JsonElement>()
            uiValue["items"] = entries(criterion["value"])
            uiValue["excluded"] = entries(criterion["excludes"])
            if (key in uiHierarchicalFields) uiValue["depth"] = criterion["depth"] ?: JsonPrimitive(0)
            val rewritten = LinkedHashMap<String, JsonElement>()
            rewritten["value"] = JsonObject(uiValue)
            criterion["modifier"]?.let { rewritten["modifier"] = it }
            out[key] = JsonObject(rewritten)
        }
        return JsonObject(out)
    }

    private val stringExtractionFields = setOf("is_missing", "has_markers", "has_chapters")
    private val intFields = setOf("rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id")
    private val multiSelectFields = setOf(
        "performers", "studios", "tags", "galleries", "scenes", "groups", "movies",
        "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups",
    )
    private val hierarchicalFields = setOf(
        "tags", "studios", "groups", "movies", "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups",
    )
    private val singleEnumFields = setOf("gender", "ethnicity", "fake_tits", "hair_color", "eye_color", "career_length")
    private val booleanFields = setOf(
        "interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite",
        "filter_favorites", "has_image", "ignore_auto_tag",
    )

    fun processCriterion(key: String, dict: JsonObject): JsonElement {
        val sub = LinkedHashMap<String, JsonElement>(dict)
        listOf("id", "type", "inputType", "criterionOption").forEach { sub.remove(it) }

        (sub["value"] as? JsonObject)?.let { valueDict ->
            when {
                valueDict["value"] != null -> sub["value"] = valueDict["value"]!!
                valueDict["id"] != null -> sub["value"] = valueDict["id"]!!
                else -> {
                    val items = jsonArray(valueDict["items"])
                    if (items.isNotEmpty()) {
                        sub["value"] = JsonArray(items)
                        valueDict["depth"]?.let { sub["depth"] = it }
                    }
                    val excluded = jsonArray(valueDict["excluded"])
                    if (excluded.isNotEmpty()) {
                        sub["excludes"] = JsonArray(excluded)
                        if (sub["depth"] == null) valueDict["depth"]?.let { sub["depth"] = it }
                    }
                }
            }
        }
        (sub["value2"] as? JsonObject)?.get("value")?.let { sub["value2"] = it }
        (sub["excludes"] as? JsonObject)?.let { ex ->
            when {
                ex["value"] != null -> sub["excludes"] = ex["value"]!!
                ex["id"] != null -> sub["excludes"] = ex["id"]!!
                else -> {
                    val items = jsonArray(ex["items"])
                    if (items.isNotEmpty()) {
                        sub["excludes"] = JsonArray(items)
                        if (sub["depth"] == null) ex["depth"]?.let { sub["depth"] = it }
                    }
                }
            }
        }

        if (key in stringExtractionFields) {
            val v = sub["value"]
            (v as? JsonObject)?.get("value").stringValue?.let { return JsonPrimitive(it) }
            (v as? JsonArray)?.firstOrNull().stringValue?.let { return JsonPrimitive(it) }
            v.stringValue?.let { return JsonPrimitive(it) }
            sub["id"].stringValue?.let { return JsonPrimitive(it) }
            return JsonPrimitive("")
        }

        if (key == "orientation") {
            when (val v = sub["value"]) {
                is JsonArray -> sub["value"] = JsonArray(v.mapNotNull { item ->
                    item.stringValue?.uppercase()?.let { JsonPrimitive(it) }
                        ?: (item as? JsonObject)?.get("id").stringValue?.uppercase()?.let { JsonPrimitive(it) }
                })
                else -> v.stringValue?.let { sub["value"] = JsonArray(listOf(JsonPrimitive(it.uppercase()))) }
            }
            sub.remove("modifier")
        }

        if (key == "resolution" || key == "average_resolution") {
            sub["value"].stringValue?.let { sub["value"] = JsonPrimitive(it.uppercase()) }
        }

        if (key in intFields || key.endsWith("_count")) {
            sub["value"]?.let { sub["value"] = castToInt(it) }
            sub["value2"]?.let { sub["value2"] = castToInt(it) }
            val mod = sub["modifier"].stringValue
            if ((mod == "IS_NULL" || mod == "NOT_NULL") && sub["value"] == null) sub["value"] = JsonPrimitive(0)
        }

        if (key in multiSelectFields) {
            if (sub["value"] != null) sub["value"] = JsonArray(idStrings(sub["value"]).map { JsonPrimitive(it) })
            if (sub["excludes"] != null) sub["excludes"] = JsonArray(idStrings(sub["excludes"]).map { JsonPrimitive(it) })
            if (key in hierarchicalFields) {
                if (sub["depth"] == null && idStrings(sub["value"]).isNotEmpty()) sub["depth"] = JsonPrimitive(0)
            } else {
                sub.remove("depth")
            }
        }

        if (key in singleEnumFields) {
            val v = sub["value"]
            val first = (v as? JsonArray)?.firstOrNull().stringValue
            if (first != null) sub["value"] = JsonPrimitive(first.uppercase())
            else v.stringValue?.let { sub["value"] = JsonPrimitive(it.uppercase()) }
        }

        if (key in booleanFields) {
            sub["value"]?.let { return JsonPrimitive(castToBool(it)) }
        }
        return JsonObject(sub)
    }

    private fun castToBool(value: JsonElement): Boolean {
        val p = value as? JsonPrimitive ?: return false
        if (p is JsonNull) return false
        if (p.isString) return p.content.lowercase() == "true" || p.content == "1" || p.content.lowercase() == "yes"
        p.booleanOrNull?.let { return it }
        return (p.content.toDoubleOrNull() ?: 0.0) != 0.0
    }

    private fun castToInt(value: JsonElement): JsonElement {
        val p = value as? JsonPrimitive ?: return value
        if (p is JsonNull) return value
        if (p.isString) return p.content.toLongOrNull()?.let { JsonPrimitive(it) } ?: value
        if (p.booleanOrNull != null) return value
        return p.content.toDoubleOrNull()?.let { JsonPrimitive(it.toLong()) } ?: value
    }

    fun jsonArray(value: JsonElement?): List<JsonElement> = (value as? JsonArray)?.toList() ?: emptyList()

    fun idString(value: JsonElement?): String? = when (value) {
        null, is JsonNull -> null
        is JsonPrimitive -> if (value.isString) value.content.trim().takeIf { it.isNotEmpty() }
            else value.content.toDoubleOrNull()?.toLong()?.toString()
        is JsonObject -> when {
            value["id"] != null -> idString(value["id"])
            value["value"] != null -> idString(value["value"])
            else -> null
        }
        else -> null
    }

    /** IDs from a criterion `value` / `items` / single string or number. */
    fun idStrings(value: JsonElement?): List<String> {
        if (value == null || value is JsonNull) return emptyList()
        if (value is JsonObject) {
            if (value["items"] != null) return idStrings(value["items"])
            if (value["id"] != null) return idStrings(value["id"])
        }
        val arr = jsonArray(value)
        if (arr.isNotEmpty()) return arr.mapNotNull { idString(it) }
        return idString(value)?.let { listOf(it) } ?: emptyList()
    }
}
