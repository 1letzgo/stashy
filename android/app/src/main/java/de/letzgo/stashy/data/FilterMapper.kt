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
 * iOS: `FilterMapper` (SharedUtilities.swift) — two-way codec between the query format the app
 * edits and sends (GraphQL `*FilterType`) and the format Stash's web UI saves in `object_filter`.
 * [sanitize] reads any saved shape (web UI, older app saves, the legacy `c` array) into the query
 * format; [savedObjectFilter] writes the web UI's shape, so a filter saved here opens unchanged in
 * Stash and the other way round.
 */
object FilterMapper {
    private val logicKeys = setOf("AND", "OR", "NOT")

    /** The list a filter belongs to. A few keys mean different things per list (`parents`). */
    enum class Entity { Scenes, Performers, Studios, Galleries, Images, Groups, Tags, Markers }

    /** Entity a picked id names, for the `{id, label}` pairs the web UI stores. */
    enum class LabelKind { Tag, Studio, Performer, Group, Gallery, Scene, Folder }

    /** How the web UI stores a criterion (`ui/v2.5/src/models/list-filter/criteria`, Stash 0.32+). */
    sealed class SavedFamily {
        /** `{value:{items,excluded,depth}, modifier}` */
        data class Hierarchical(val kind: LabelKind) : SavedFamily()
        /** `{value:{items,excluded}, modifier}` */
        object PerformerItems : SavedFamily()
        /** `{value:[{id,label}], modifier}` */
        data class LabeledIds(val kind: LabelKind) : SavedFamily()
        object Resolution : SavedFamily()
        object Orientation : SavedFamily()
        object Gender : SavedFamily()
        object Circumcised : SavedFamily()
        object Captions : SavedFamily()
        /** `{value:"true"|"false", modifier:EQUALS}` ↔ Bool */
        object BooleanValue : SavedFamily()
        /** `{value:"…", modifier:EQUALS}` ↔ bare String */
        object StringValue : SavedFamily()
        /** `{value:{value,value2}, modifier}` */
        object Date : SavedFamily()
        object Timestamp : SavedFamily()
        /** `{value:{endpoint,stashID}, modifier}` */
        object StashID : SavedFamily()
        /** `{value:{value,distance}, modifier}` */
        object Phash : SavedFamily()
        /** `{value:{phash,url,stash_id,title,distance}, modifier:EQUALS}` */
        object Duplicated : SavedFamily()
        /** Stored as queried (custom_fields, app-only keys). */
        object Passthrough : SavedFamily()
        /** Numbers → nested range, strings stay flat. */
        object Generic : SavedFamily()
    }

    fun savedFamily(key: String, entity: Entity?): SavedFamily = when (key) {
        "tags", "scene_tags", "performer_tags", "children" -> SavedFamily.Hierarchical(LabelKind.Tag)
        "parents" -> if (entity == Entity.Studios) SavedFamily.LabeledIds(LabelKind.Studio) else SavedFamily.Hierarchical(LabelKind.Tag)
        "studios" -> SavedFamily.Hierarchical(LabelKind.Studio)
        "groups", "movies", "containing_groups", "sub_groups" -> SavedFamily.Hierarchical(LabelKind.Group)
        "folder", "parent_folder" -> SavedFamily.Hierarchical(LabelKind.Folder)
        "performers" -> SavedFamily.PerformerItems
        "galleries" -> SavedFamily.LabeledIds(LabelKind.Gallery)
        "scenes" -> SavedFamily.LabeledIds(LabelKind.Scene)
        "resolution", "average_resolution" -> SavedFamily.Resolution
        "orientation" -> SavedFamily.Orientation
        "gender" -> SavedFamily.Gender
        "circumcised" -> SavedFamily.Circumcised
        "captions" -> SavedFamily.Captions
        "organized", "interactive", "performer_favorite", "filter_favorites", "favorite",
        "ignore_auto_tag", "is_zip", "studio_favorite", "gallery_favorite", "has_image" -> SavedFamily.BooleanValue
        "has_markers", "has_chapters", "is_missing" -> SavedFamily.StringValue
        "date", "production_date", "birthdate", "death_date", "career_start", "career_end", "scene_date" -> SavedFamily.Date
        "created_at", "updated_at", "last_played_at", "scene_created_at", "scene_updated_at" -> SavedFamily.Timestamp
        "stash_id_endpoint" -> SavedFamily.StashID
        "phash_distance" -> SavedFamily.Phash
        "duplicated" -> SavedFamily.Duplicated
        "custom_fields", "stash_ids_endpoint", "id" -> SavedFamily.Passthrough
        else -> SavedFamily.Generic
    }

    /** `*_filter` sub-filter key → the list it filters. */
    fun subFilterEntity(key: String): Entity? = when (key) {
        "scene_filter", "scenes_filter" -> Entity.Scenes
        "performers_filter" -> Entity.Performers
        "studios_filter" -> Entity.Studios
        "galleries_filter" -> Entity.Galleries
        "images_filter" -> Entity.Images
        "groups_filter", "movies_filter" -> Entity.Groups
        "tags_filter" -> Entity.Tags
        "markers_filter" -> Entity.Markers
        else -> null
    }

    // MARK: - Load (saved → query)

    /**
     * Saved filter / editor criteria → GraphQL shape. Tolerant of the web UI's format, older app
     * saves (query format) and numeric ids; running it twice changes nothing.
     */
    fun sanitize(dict: JsonObject, isMarker: Boolean = false, entity: Entity? = null): JsonObject {
        val entity = entity ?: if (isMarker) Entity.Markers else null
        var newDict = LinkedHashMap<String, JsonElement>(dict)
        // Legacy key (Stash renamed movies → groups); the web UI reads it as groups too.
        if (newDict["movies"] != null && newDict["groups"] == null) {
            newDict["groups"] = newDict.remove("movies")!!
        }

        // 1. Stash UI `c` criteria array.
        val criteria = newDict["c"] as? JsonArray
        if (criteria != null) {
            val fromC = LinkedHashMap<String, JsonElement>()
            for (el in criteria) {
                val item = el as? JsonObject ?: continue
                var key = item["id"].stringValue ?: continue
                if (key == "rating") key = "rating100"
                val processed: JsonElement =
                    if (item["c"] != null || item["AND"] != null || item["OR"] != null || item["NOT"] != null) sanitize(item, false, entity)
                    else processCriterion(key, item, entity)
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
                    is JsonArray -> newDict[key] = JsonArray(value.map { (it as? JsonObject)?.let { o -> sanitize(o, false, entity) } ?: it })
                    is JsonObject -> newDict[key] = sanitize(value, false, entity)
                    else -> {}
                }
                continue
            }
            if (key.endsWith("_filter")) {
                // `files_filter` / `folders_filter` are file-level types: their keys are not the
                // list criteria handled here, so they pass through untouched.
                if (value is JsonObject) {
                    newDict[key] = if (key == "files_filter" || key == "folders_filter") value
                    else sanitize(value, false, subFilterEntity(key))
                }
                continue
            }
            if (value is JsonObject) {
                newDict[key] = processCriterion(key, value, entity)
            } else if (savedFamily(key, entity) == SavedFamily.BooleanValue && value.stringValue != null) {
                newDict[key] = JsonPrimitive(castToBool(value))
            }
        }
        omitEmptyMultiIdCriteria(newDict)
        return JsonObject(newDict)
    }

    /**
     * Last step before a query leaves the app. The Folder criterion (scenes, images) lives under
     * its web UI key `folder` in the app's filters; GraphQL wants it as `files_filter.parent_folder`.
     * Saved filters (`object_filter`) keep the web UI key.
     */
    fun queryVariables(variables: JsonObject): JsonObject {
        var changed = false
        val out = LinkedHashMap<String, JsonElement>(variables)
        for ((key, value) in variables) {
            if (!key.endsWith("_filter") || key == "object_filter" || key == "find_filter") continue
            val filter = value as? JsonObject ?: continue
            val hoisted = hoistFolder(filter)
            if (hoisted !== filter) { out[key] = hoisted; changed = true }
        }
        return if (changed) JsonObject(out) else variables
    }

    /** Returns [dict] itself when nothing moved. */
    private fun hoistFolder(dict: JsonObject): JsonObject {
        var out: LinkedHashMap<String, JsonElement>? = null
        fun mutable() = out ?: LinkedHashMap<String, JsonElement>(dict).also { out = it }
        for ((key, value) in dict) {
            if (key in logicKeys || (key.endsWith("_filter") && key != "files_filter")) {
                when (value) {
                    is JsonObject -> hoistFolder(value).let { if (it !== value) mutable()[key] = it }
                    is JsonArray -> {
                        val mapped = value.map { el -> (el as? JsonObject)?.let { hoistFolder(it) } ?: el }
                        if (mapped.indices.any { mapped[it] !== value[it] }) mutable()[key] = JsonArray(mapped)
                    }
                    else -> {}
                }
            }
        }
        val folder = dict["folder"] as? JsonObject
        if (folder != null) {
            val m = mutable()
            m.remove("folder")
            val files = LinkedHashMap<String, JsonElement>((m["files_filter"] as? JsonObject) ?: JsonObject(emptyMap()))
            files["parent_folder"] = folder
            m["files_filter"] = JsonObject(files)
        }
        return out?.let { JsonObject(it) } ?: dict
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

    // MARK: - Value maps, exactly as the web UI writes them (`src/utils/*.ts`)

    val resolutionLabels: List<Pair<String, String>> = listOf(
        "144p" to "VERY_LOW", "240p" to "LOW", "360p" to "R360P", "480p" to "STANDARD",
        "540p" to "WEB_HD", "720p" to "STANDARD_HD", "1080p" to "FULL_HD", "1440p" to "QUAD_HD",
        "4k" to "FOUR_K", "5k" to "FIVE_K", "6k" to "SIX_K", "7k" to "SEVEN_K", "8k" to "EIGHT_K",
        "Huge" to "HUGE",
    )
    val genderLabels: List<Pair<String, String>> = listOf(
        "Male" to "MALE", "Female" to "FEMALE", "Transgender Male" to "TRANSGENDER_MALE",
        "Transgender Female" to "TRANSGENDER_FEMALE", "Intersex" to "INTERSEX", "Non-Binary" to "NON_BINARY",
    )
    val circumcisedLabels: List<Pair<String, String>> = listOf("Uncut" to "UNCUT", "Cut" to "CUT")
    val orientationLabels: List<Pair<String, String>> = listOf("Landscape" to "LANDSCAPE", "Portrait" to "PORTRAIT", "Square" to "SQUARE")
    val captionLabels: List<Pair<String, String>> = listOf(
        "Deutsche" to "de", "English" to "en", "Español" to "es", "Français" to "fr",
        "Italiano" to "it", "日本" to "ja", "한국인" to "ko", "Holandés" to "nl",
        "Português" to "pt", "Русский" to "ru", "Unknown" to "00",
    )

    private fun norm(s: String) = s.lowercase().replace("-", "_").replace(" ", "_")

    /** Saved label or query value (any case, `-` / space / `_` alike) → query value. */
    fun queryValue(raw: String, map: List<Pair<String, String>>): String? {
        val n = norm(raw)
        return map.firstOrNull { norm(it.first) == n || norm(it.second) == n }?.second
    }

    /** Query value (or a label already) → the label the web UI saves. */
    fun savedLabel(raw: String, map: List<Pair<String, String>>): String {
        val value = queryValue(raw, map) ?: return raw
        return map.firstOrNull { it.second == value }?.first ?: raw
    }

    private fun stringList(raw: JsonElement?): List<String> {
        raw.stringValue?.let { return listOf(it) }
        return jsonArray(raw).mapNotNull { item ->
            item.stringValue ?: (item as? JsonObject)?.let { it["id"].stringValue ?: it["label"].stringValue }
        }
    }

    private val timestampShape = Regex("""^\d{4}-\d{2}-\d{2} \d{2}:\d{2}""")

    /** "2024-01-31T13:45" / "2024-01-31 13:45:00" → the web UI's "2024-01-31 13:45". */
    fun savedTimestamp(raw: String): String {
        val t = raw.trim().replace("T", " ")
        return if (t.length >= 16 && timestampShape.containsMatchIn(t)) t.take(16) else t
    }

    /** The web UI's "2024-01-31 13:45" → GraphQL "2024-01-31T13:45" (date-only stays as is). */
    fun queryTimestamp(raw: String): String {
        val t = raw.trim()
        return if (timestampShape.containsMatchIn(t)) t.replace(" ", "T") else t
    }

    // MARK: - Save (query → saved)

    /**
     * Rewrites a query-shaped filter (what the app edits and sends) into the web UI's storage
     * format. The server stores `object_filter` without looking at it; the web UI saves display
     * values (`"1440p"`, `["Female"]`, `"English"`, ranges nested in `value`) and maps them to
     * GraphQL only when it queries. [sanitize] is the way back. [label] names an id for the
     * `{id, label}` pairs (null → the id, which the web UI re-resolves).
     */
    fun savedObjectFilter(
        dict: JsonObject,
        entity: Entity?,
        label: (LabelKind, String) -> String? = { _, _ -> null },
    ): JsonObject {
        val out = LinkedHashMap<String, JsonElement>()
        for ((key, value) in dict) {
            if (key in logicKeys) {
                out[key] = when (value) {
                    is JsonObject -> savedObjectFilter(value, entity, label)
                    is JsonArray -> JsonArray(value.map { (it as? JsonObject)?.let { o -> savedObjectFilter(o, entity, label) } ?: it })
                    else -> value
                }
                continue
            }
            if (key == "files_filter" && value is JsonObject) {
                val files = LinkedHashMap<String, JsonElement>(value)
                // The web UI's Folder criterion (scenes / images) is `files_filter.parent_folder`.
                val folder = files["parent_folder"] as? JsonObject
                if ((entity == Entity.Scenes || entity == Entity.Images) && folder != null) {
                    out["folder"] = savedCriterion("folder", folder, entity, label)
                    files.remove("parent_folder")
                }
                if (files.isNotEmpty()) out[key] = JsonObject(files)
                continue
            }
            if (key.endsWith("_filter")) {
                out[key] = if (value is JsonObject) savedObjectFilter(value, subFilterEntity(key), label) else value
                continue
            }
            val savedKey = if (key == "movies") "groups" else key
            out[savedKey] = savedCriterion(key, value, entity, label)
        }
        return JsonObject(out)
    }

    private fun savedCriterion(key: String, value: JsonElement, entity: Entity?, label: (LabelKind, String) -> String?): JsonElement {
        val family = savedFamily(key, entity)
        fun s(v: String) = JsonPrimitive(v)
        // Bare scalars (GraphQL `organized: true`, `is_missing: "cover"`).
        val c = value as? JsonObject ?: return when {
            family == SavedFamily.BooleanValue && value is JsonPrimitive && value !is JsonNull -> {
                val b = value.boolOrNull ?: (value.stringValue?.lowercase() == "true")
                JsonObject(linkedMapOf("value" to s(if (b) "true" else "false"), "modifier" to s("EQUALS")))
            }
            family == SavedFamily.StringValue && value is JsonPrimitive && value !is JsonNull ->
                JsonObject(linkedMapOf("value" to s(value.content), "modifier" to s("EQUALS")))
            else -> value
        }
        val modifier = c["modifier"]
        fun withModifier(v: JsonElement, default: String?): JsonObject {
            val r = linkedMapOf<String, JsonElement>("value" to v)
            if (modifier != null) r["modifier"] = modifier else if (default != null) r["modifier"] = s(default)
            return JsonObject(r)
        }
        fun entries(raw: JsonElement?, kind: LabelKind) = JsonArray(idStrings(raw).map { id ->
            JsonObject(linkedMapOf("id" to s(id), "label" to s(label(kind, id) ?: id)))
        })
        // Already in the saved shape (a criterion the app never touched): keep it.
        (c["value"] as? JsonObject)?.let { v ->
            if (v["items"] != null || v["value"] != null || v["endpoint"] != null || v["stashID"] != null) return c
        }

        return when (family) {
            is SavedFamily.Hierarchical -> {
                val v = linkedMapOf<String, JsonElement>(
                    "items" to entries(c["value"], family.kind),
                    "excluded" to entries(c["excludes"], family.kind),
                    "depth" to (c["depth"] ?: JsonPrimitive(0)),
                )
                withModifier(JsonObject(v), "INCLUDES")
            }
            SavedFamily.PerformerItems -> withModifier(
                JsonObject(linkedMapOf("items" to entries(c["value"], LabelKind.Performer), "excluded" to entries(c["excludes"], LabelKind.Performer))),
                "INCLUDES",
            )
            is SavedFamily.LabeledIds -> {
                val items = entries(c["value"], family.kind)
                val excluded = entries(c["excludes"], family.kind)
                // No `excluded` in this shape: an exclude-only criterion becomes EXCLUDES.
                if (items.isEmpty() && excluded.isNotEmpty()) {
                    JsonObject(linkedMapOf("value" to excluded, "modifier" to s("EXCLUDES")))
                } else {
                    val r = LinkedHashMap<String, JsonElement>(withModifier(items, "INCLUDES"))
                    if (excluded.isNotEmpty()) r["excludes"] = JsonArray(idStrings(c["excludes"]).map { s(it) })
                    JsonObject(r)
                }
            }
            SavedFamily.Resolution -> {
                val raw = c["value"].stringValue ?: return c
                withModifier(s(savedLabel(raw, resolutionLabels)), "EQUALS")
            }
            SavedFamily.Orientation -> JsonObject(linkedMapOf(
                "value" to JsonArray(stringList(c["value"]).map { s(savedLabel(it, orientationLabels)) }),
                "modifier" to s("EQUALS"),
            ))
            SavedFamily.Gender -> withModifier(JsonArray(stringList(c["value_list"] ?: c["value"]).map { s(savedLabel(it, genderLabels)) }), "INCLUDES")
            SavedFamily.Circumcised -> withModifier(JsonArray(stringList(c["value"]).map { s(savedLabel(it, circumcisedLabels)) }), "INCLUDES")
            SavedFamily.Captions -> {
                val raw = c["value"].stringValue ?: return c
                withModifier(s(savedLabel(raw, captionLabels)), "INCLUDES")
            }
            SavedFamily.BooleanValue, SavedFamily.StringValue -> {
                val v = c["value"] as? JsonPrimitive ?: return c
                if (v is JsonNull) return c
                val text = v.boolOrNull?.let { if (it) "true" else "false" } ?: v.content
                JsonObject(linkedMapOf("value" to s(text), "modifier" to s("EQUALS")))
            }
            SavedFamily.Date, SavedFamily.Timestamp -> {
                val isTime = family == SavedFamily.Timestamp
                fun fmt(x: JsonElement?): JsonElement? {
                    val str = x.stringValue ?: return x
                    return s(if (isTime) savedTimestamp(str) else str)
                }
                val inner = LinkedHashMap<String, JsonElement>()
                fmt(c["value"])?.let { inner["value"] = it }
                fmt(c["value2"])?.let { inner["value2"] = it }
                withModifier(JsonObject(inner), if (isTime) "GREATER_THAN" else "EQUALS")
            }
            SavedFamily.StashID -> {
                val inner = LinkedHashMap<String, JsonElement>()
                c["endpoint"]?.let { inner["endpoint"] = it }
                (c["stash_id"] ?: c["value"])?.let { inner["stashID"] = it }
                withModifier(JsonObject(inner), "EQUALS")
            }
            SavedFamily.Phash -> {
                val inner = LinkedHashMap<String, JsonElement>()
                c["value"]?.let { inner["value"] = it }
                inner["distance"] = c["distance"] ?: JsonPrimitive(0)
                withModifier(JsonObject(inner), "EQUALS")
            }
            SavedFamily.Duplicated -> {
                val inner = LinkedHashMap<String, JsonElement>()
                for (k in listOf("phash", "url", "stash_id", "title", "distance")) c[k]?.let { inner[k] = it }
                // App-written `{duplicated: true}` = duplicate phash, as the web UI reads it.
                if (inner["phash"] == null) c["duplicated"].boolOrNull?.let { inner["phash"] = JsonPrimitive(it) }
                JsonObject(linkedMapOf("value" to JsonObject(inner), "modifier" to s("EQUALS")))
            }
            SavedFamily.Passthrough -> c
            SavedFamily.Generic -> {
                // Numbers / ratings / durations: the range lives inside `value`.
                if (c["value"].numberOrNull != null || c["value2"].numberOrNull != null) {
                    val inner = LinkedHashMap<String, JsonElement>()
                    c["value"]?.let { inner["value"] = it }
                    c["value2"]?.let { inner["value2"] = it }
                    val r = LinkedHashMap<String, JsonElement>(c)
                    r.remove("value2")
                    r["value"] = JsonObject(inner)
                    if (r["modifier"] == null) r["modifier"] = s("EQUALS")
                    JsonObject(r)
                } else c
            }
        }
    }

    // MARK: - One criterion

    private val stringExtractionFields = setOf("is_missing", "has_markers", "has_chapters")
    private val intFields = setOf("rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id")
    private val multiSelectFields = setOf(
        "performers", "studios", "tags", "galleries", "scenes", "groups", "movies",
        "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups",
        "folder", "parent_folder",
    )
    private val hierarchicalFields = setOf(
        "tags", "studios", "groups", "movies", "performer_tags", "scene_tags", "containing_groups", "sub_groups",
        "folder", "parent_folder",
    )
    private val booleanFields = setOf(
        "interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite",
        "filter_favorites", "has_image", "ignore_auto_tag", "is_zip",
    )

    fun processCriterion(key: String, dict: JsonObject, entity: Entity? = null): JsonElement {
        val sub = LinkedHashMap<String, JsonElement>(dict)
        listOf("id", "type", "inputType", "criterionOption").forEach { sub.remove(it) }

        // Shapes whose saved `value` object is not a range or an id list.
        when (savedFamily(key, entity)) {
            SavedFamily.StashID -> {
                val out = LinkedHashMap<String, JsonElement>()
                out["modifier"] = sub["modifier"] ?: JsonPrimitive("EQUALS")
                val v = sub["value"]
                if (v is JsonObject) {
                    v["endpoint"].stringValue?.takeIf { it.isNotEmpty() }?.let { out["endpoint"] = JsonPrimitive(it) }
                    (v["stashID"] ?: v["stash_id"]).stringValue?.takeIf { it.isNotEmpty() }?.let { out["stash_id"] = JsonPrimitive(it) }
                } else {
                    v.stringValue?.takeIf { it.isNotEmpty() }?.let { out["stash_id"] = JsonPrimitive(it) }
                }
                sub["endpoint"]?.let { out["endpoint"] = it }
                sub["stash_id"]?.let { out["stash_id"] = it }
                return JsonObject(out)
            }
            SavedFamily.Phash -> {
                val v = sub["value"]
                if (v is JsonObject) {
                    sub["value"] = v["value"] ?: JsonPrimitive("")
                    sub["distance"] = v["distance"] ?: sub["distance"] ?: JsonPrimitive(0)
                }
                return JsonObject(sub)
            }
            SavedFamily.Duplicated -> {
                // DuplicationCriterionInput has no modifier.
                val v = sub["value"]
                if (v is JsonObject) return v
                v.stringValue?.let { return JsonObject(mapOf("phash" to JsonPrimitive(castToBool(JsonPrimitive(it))))) }
                sub.remove("modifier")
                return JsonObject(sub)
            }
            else -> {}
        }

        (sub["value"] as? JsonObject)?.let { valueDict ->
            when {
                valueDict["value"] != null -> {
                    // Ranges (numbers, dates, timestamps) keep both ends inside `value`.
                    sub["value"] = valueDict["value"]!!
                    valueDict["value2"]?.let { sub["value2"] = it }
                }
                valueDict["id"] != null -> sub["value"] = valueDict["id"]!!
                else -> {
                    val items = jsonArray(valueDict["items"])
                    if (items.isNotEmpty()) {
                        sub["value"] = JsonArray(items)
                        valueDict["depth"]?.let { sub["depth"] = it }
                    }
                    // The web UI nests its exclusions inside `value` as `excluded`.
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

        // The web UI saves "1440p" / "4k"; GraphQL wants QUAD_HD / FOUR_K.
        if (key == "resolution" || key == "average_resolution") {
            sub["value"].stringValue?.let { sub["value"] = JsonPrimitive(queryValue(it, resolutionLabels) ?: it.uppercase()) }
        }

        // Saved "Cut" / "Uncut" → CUT / UNCUT.
        if (key == "circumcised") {
            sub["value"] = JsonArray(stringList(sub["value"]).map { JsonPrimitive(queryValue(it, circumcisedLabels) ?: it.uppercase()) })
            if (sub["modifier"] == null) sub["modifier"] = JsonPrimitive("INCLUDES")
        }

        // Saved ["Female", "Transgender Female"] (or a legacy single value) → value_list enums.
        if (key == "gender") {
            val raw = sub["value_list"] ?: sub["value"]
            sub["value_list"] = JsonArray(stringList(raw).map { JsonPrimitive(queryValue(it, genderLabels) ?: it.uppercase()) })
            sub.remove("value")
            if (sub["modifier"] == null) sub["modifier"] = JsonPrimitive("INCLUDES")
        }

        // Saved display name ("English") → language code ("en").
        if (key == "captions") {
            sub["value"].stringValue?.let { sub["value"] = JsonPrimitive(queryValue(it, captionLabels) ?: it) }
        }

        // Saved "2024-01-31 13:45" → GraphQL "2024-01-31T13:45".
        if (savedFamily(key, entity) == SavedFamily.Timestamp) {
            sub["value"].stringValue?.let { sub["value"] = JsonPrimitive(queryTimestamp(it)) }
            sub["value2"].stringValue?.let { sub["value2"] = JsonPrimitive(queryTimestamp(it)) }
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
            } else if (key == "parents" || key == "children") {
                // Tag parents / children are hierarchical; studio parents are a plain
                // MultiCriterionInput that rejects `depth`.
                if (entity == Entity.Studios) sub.remove("depth")
            } else {
                sub.remove("depth")
            }
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

/** The list [FilterMapper] encodes and decodes saved criteria for (iOS `FilterMode.filterEntity`). */
val FilterMode.filterEntity: FilterMapper.Entity? get() = when (this) {
    FilterMode.Scenes -> FilterMapper.Entity.Scenes
    FilterMode.Performers -> FilterMapper.Entity.Performers
    FilterMode.Studios -> FilterMapper.Entity.Studios
    FilterMode.Galleries -> FilterMapper.Entity.Galleries
    FilterMode.Images -> FilterMapper.Entity.Images
    FilterMode.Tags -> FilterMapper.Entity.Tags
    FilterMode.Groups -> FilterMapper.Entity.Groups
    FilterMode.SceneMarkers -> FilterMapper.Entity.Markers
    FilterMode.Unknown -> null
}
