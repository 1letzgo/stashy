package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/**
 * iOS: `FilterCriteriaDocument` — editable `object_filter` for one [FilterMode]. Values are kept
 * in GraphQL shape; [sanitizedObjectFilter] is what goes to the server. Backed by Compose state so
 * the editor recomposes on every change.
 */
class CriteriaDocument(mode: FilterMode, objectFilter: JsonObject = JsonObject(emptyMap()), pinsDefaults: Boolean = false) {
    var mode: FilterMode = mode
        private set

    private var _objectFilter by mutableStateOf(sanitize(objectFilter, mode))
    val objectFilter: JsonObject get() = _objectFilter

    /** Display order per level (key = group path joined with "/", "" = root). */
    private val keyOrders = HashMap<String, MutableList<String>>()

    /** Keys the root editor always shows, even without a value (iOS: pinned defaults). */
    var pinnedKeys: List<String> = if (pinsDefaults) FilterFieldCatalog.defaultCriterionKeys(mode) else emptyList()
        private set

    init {
        keyOrders[""] = defaultSortedKeys(_objectFilter.keys.toList(), mode).toMutableList()
    }

    private fun setFilter(value: JsonObject) {
        _objectFilter = value
        syncKeyOrder()
    }

    private fun syncKeyOrder() {
        val present = _objectFilter.keys
        val order = keyOrders.getOrPut("") { mutableListOf() }
        order.removeAll { it !in present }
        val missing = present.filter { it !in order }
        if (missing.isNotEmpty()) order.addAll(defaultSortedKeys(missing, mode))
    }

    fun displayedCriterionKeys(): List<String> {
        val present = criterionKeys(emptyList())
        return pinnedKeys + present.filter { it !in pinnedKeys }
    }

    /** Nested editors pin nothing. */
    fun reconfigure(mode: FilterMode, objectFilter: JsonObject) {
        this.mode = mode
        pinnedKeys = emptyList()
        keyOrders.clear()
        setFilter(sanitize(objectFilter, mode))
    }

    val isMarkerMode: Boolean get() = mode == FilterMode.SceneMarkers

    val sanitizedObjectFilter: JsonObject get() = stripIncompleteCriteria(sanitize(_objectFilter, mode), mode)

    fun criterionKeys(path: List<String>): List<String> {
        val dict = node(path)
        val present = dict.keys.filter { !isGroupKey(it) }
        val order = keyOrders[orderKey(path)] ?: emptyList<String>()
        val out = order.filter { it in present }.toMutableList()
        out.addAll(defaultSortedKeys(present.filter { it !in out }, mode))
        return out
    }

    val presentKeys: Set<String> get() = _objectFilter.keys

    fun load(dict: JsonObject?) {
        keyOrders.clear()
        setFilter(sanitize(dict ?: JsonObject(emptyMap()), mode))
    }

    fun replaceObjectFilter(dict: JsonObject) = load(dict)

    fun clear() = setFilter(JsonObject(emptyMap()))

    fun value(key: String, path: List<String> = emptyList()): JsonElement? = node(path)[key]

    fun setCriterion(key: String, value: JsonElement?, path: List<String> = emptyList()) {
        if (path.isEmpty()) {
            setFilter(_objectFilter.with(key, value?.let { withRequiredModifier(it, key, mode) }))
            return
        }
        val root = mutate(_objectFilter, path) { node ->
            if (value != null) node[key] = withRequiredModifier(value, key, mode) else node.remove(key)
        }
        if (value != null) noteInsertion(key, path)
        setFilter(root)
    }

    fun removeCriterion(key: String) = setCriterion(key, null)

    fun addDefaultCriterion(field: FilterFieldDescriptor, path: List<String> = emptyList()) {
        if (node(path)[field.key] != null) return
        setCriterion(field.key, field.kind.defaultValue(mode), path)
    }

    // Group tree (AND / OR / NOT nest a filter of the same shape).

    fun node(path: List<String>): JsonObject {
        var current = _objectFilter
        for (step in path) current = current[step] as? JsonObject ?: return JsonObject(emptyMap())
        return current
    }

    fun groupKeys(path: List<String>): List<String> {
        val dict = node(path)
        return GROUP_KEYS.filter { dict[it] != null }
    }

    fun addGroup(group: String, path: List<String>) {
        if (!isGroupKey(group) || node(path)[group] != null) return
        setFilter(mutate(_objectFilter, path) { it[group] = JsonObject(emptyMap()) })
    }

    fun removeGroup(group: String, path: List<String>) {
        setFilter(mutate(_objectFilter, path) { it.remove(group) })
    }

    /** Retypes a group in place; no-op when the target type already exists at that level. */
    fun changeGroupType(path: List<String>, from: String, to: String) {
        if (from == to || !isGroupKey(to)) return
        val parent = node(path)
        val contents = parent[from] as? JsonObject ?: return
        if (parent[to] != null) return
        val root = mutate(_objectFilter, path) { n -> n.remove(from); n[to] = contents }
        keyOrders.remove(orderKey(path + from))?.let { keyOrders[orderKey(path + to)] = it }
        setFilter(root)
    }

    private fun noteInsertion(key: String, path: List<String>) {
        val order = keyOrders.getOrPut(orderKey(path)) { mutableListOf() }
        order.remove(key)
        order.add(key)
    }

    /** Criteria as the base, chip criteria on top; `null` when nothing is active. */
    fun merged(chipFilter: JsonObject = JsonObject(emptyMap())): JsonObject? {
        val dict = LinkedHashMap<String, JsonElement>(sanitizedObjectFilter)
        chipFilter.forEach { (k, v) -> dict[k] = v }
        return if (dict.isEmpty()) null else JsonObject(dict)
    }

    /** `base` first, this document's criteria on top. */
    fun layered(base: JsonObject): JsonObject? {
        val dict = LinkedHashMap<String, JsonElement>(base)
        sanitizedObjectFilter.forEach { (k, v) -> dict[k] = v }
        return if (dict.isEmpty()) null else JsonObject(dict)
    }

    val activeCriterionCount: Int get() = sanitizedObjectFilter.size
    val isEmpty: Boolean get() = sanitizedObjectFilter.isEmpty()

    companion object {
        val GROUP_KEYS = listOf("AND", "OR", "NOT")
        fun isGroupKey(key: String) = key in GROUP_KEYS

        private fun orderKey(path: List<String>) = path.joinToString("/")

        private fun defaultSortedKeys(keys: List<String>, mode: FilterMode): List<String> = keys.sortedWith { a, b ->
            val ia = GROUP_KEYS.indexOf(a).let { if (it < 0) Int.MAX_VALUE else it }
            val ib = GROUP_KEYS.indexOf(b).let { if (it < 0) Int.MAX_VALUE else it }
            if (ia != ib) ia.compareTo(ib)
            else {
                val la = FilterFieldCatalog.field(a, mode)?.label ?: a
                val lb = FilterFieldCatalog.field(b, mode)?.label ?: b
                String.CASE_INSENSITIVE_ORDER.compare(la, lb)
            }
        }

        private fun mutate(dict: JsonObject, path: List<String>, body: (LinkedHashMap<String, JsonElement>) -> Unit): JsonObject {
            val m = LinkedHashMap<String, JsonElement>(dict)
            if (path.isEmpty()) {
                body(m)
            } else {
                val child = m[path.first()] as? JsonObject ?: JsonObject(emptyMap())
                m[path.first()] = mutate(child, path.drop(1), body)
            }
            return JsonObject(m)
        }

        /** Fills in the modifier a criterion requires but the user never touched. */
        private fun withRequiredModifier(value: JsonElement, key: String, mode: FilterMode): JsonElement {
            val dict = value as? JsonObject ?: return value
            if (dict["modifier"] != null) return value
            val field = FilterFieldCatalog.field(key, mode) ?: return value
            val modifier = (field.kind.defaultValue(mode) as? JsonObject)?.get("modifier") ?: return value
            return dict.with("modifier", modifier)
        }

        /** iOS: `sanitizeNonisolated` — `FilterMapper.sanitize` plus scratch-key removal. */
        fun sanitize(dict: JsonObject, mode: FilterMode): JsonObject =
            stripEditorScratchKeys(FilterMapper.sanitize(dict, isMarker = mode == FilterMode.SceneMarkers))

        /** Removes UI scratch values (`value_text` …). */
        fun stripEditorScratchKeys(dict: JsonObject): JsonObject {
            val out = LinkedHashMap<String, JsonElement>()
            for ((key, value) in dict) {
                if (key.endsWith("_text")) continue
                when (value) {
                    is JsonObject -> {
                        val cleaned = stripEditorScratchKeys(value)
                        if (cleaned.isEmpty() && value.isNotEmpty()) continue
                        out[key] = cleaned
                    }
                    is JsonArray -> out[key] = JsonArray(value.map { (it as? JsonObject)?.let(::stripEditorScratchKeys) ?: it })
                    else -> out[key] = value
                }
            }
            return JsonObject(out)
        }

        /** Drops criteria the user opened but did not fill in (Stash would reject the whole query). */
        fun stripIncompleteCriteria(dict: JsonObject, mode: FilterMode): JsonObject {
            val out = LinkedHashMap<String, JsonElement>()
            for ((key, value) in dict) {
                if (isGroupKey(key)) {
                    when (value) {
                        is JsonObject -> stripIncompleteCriteria(value, mode).takeIf { it.isNotEmpty() }?.let { out[key] = it }
                        is JsonArray -> {
                            val cleaned = value.mapNotNull { (it as? JsonObject)?.let { o -> stripIncompleteCriteria(o, mode) }?.takeIf { c -> c.isNotEmpty() } }
                            if (cleaned.isNotEmpty()) out[key] = JsonArray(cleaned)
                        }
                        else -> {}
                    }
                    continue
                }
                val field = FilterFieldCatalog.field(key, mode)
                val criterion = value as? JsonObject
                if (field == null || criterion == null) { out[key] = value; continue }
                if (criterionIsComplete(criterion, field.kind)) out[key] = value
            }
            return JsonObject(out)
        }

        private fun criterionIsComplete(c: JsonObject, kind: CriterionKind): Boolean {
            val modifier = CriterionModifier.from(c["modifier"].stringValue)
            if (modifier != null && !modifier.needsValue) return true
            return when (kind) {
                CriterionKind.string, CriterionKind.date, CriterionKind.timestamp, CriterionKind.resolution, CriterionKind.phashDistance -> {
                    val text = c["value"].stringValue?.trim()
                    if (text.isNullOrEmpty()) false
                    else if (modifier?.needsSecondValue == true) !c["value2"].stringValue?.trim().isNullOrEmpty()
                    else true
                }
                CriterionKind.int, CriterionKind.float, CriterionKind.hierarchicalCount -> {
                    if (c["value"].numberOrNull == null) false
                    else if (modifier?.needsSecondValue == true) c["value2"].numberOrNull != null
                    else true
                }
                CriterionKind.gender, CriterionKind.circumcision ->
                    (c["value_list"] as? JsonArray)?.isNotEmpty() == true ||
                        !c["value"].stringValue.isNullOrEmpty() ||
                        (c["value"] as? JsonArray)?.isNotEmpty() == true
                CriterionKind.orientation -> (c["value"] as? JsonArray)?.isNotEmpty() == true
                CriterionKind.multi, CriterionKind.hierarchicalMulti ->
                    FilterMapper.idStrings(c["value"]).isNotEmpty() || FilterMapper.idStrings(c["excludes"]).isNotEmpty()
                else -> true
            }
        }
    }
}

// MARK: - SavedFilter helpers (iOS: `StashDBViewModel.SavedFilter`)

val SavedFilter.filterMode: FilterMode get() = FilterMode.from(mode)

/** Raw Stash UI filter JSON (legacy `filter` string; `sortby` / `sortdir` live here). */
val SavedFilter.uiFilterJSON: JsonObject? get() =
    filter?.takeIf { it.isNotBlank() }?.let { runCatching { Json.parseToJsonElement(it) as? JsonObject }.getOrNull() }

/** iOS: `filterDict` — `object_filter`, else the UI filter JSON. */
val SavedFilter.filterDict: JsonObject? get() = (objectFilter as? JsonObject) ?: uiFilterJSON

/** iOS: `encodedSortPair` — `find_filter` first, then the UI JSON. */
val SavedFilter.encodedSortPair: Pair<String, String>? get() {
    findFilter?.get("sort").stringValue?.trim()?.takeIf { it.isNotEmpty() }?.let { field ->
        val dir = findFilter?.get("direction").stringValue?.trim()?.takeIf { it.isNotEmpty() } ?: "DESC"
        return field to dir
    }
    val dict = uiFilterJSON ?: return null
    val field = (dict["sort"] ?: dict["sortby"] ?: dict["sortBy"]).stringValue
    val dir = (dict["direction"] ?: dict["sortdir"] ?: dict["sortDirection"] ?: dict["dir"]).stringValue
    return field?.takeIf { it.isNotEmpty() }?.let { it to (dir?.takeIf { d -> d.isNotEmpty() } ?: "DESC") }
}

/** iOS: `StashyCatalogPresetMetadata` / `StashyScenePresetMetadata` (`ui_options.stashy`). */
data class StashyPresetMetadata(val baseSavedFilterId: String?, val liveFragment: JsonObject, val sortRaw: String?)

val SavedFilter.stashyMetadata: StashyPresetMetadata? get() {
    val stashy = (uiOptions as? JsonObject)?.get("stashy") as? JsonObject ?: return null
    return StashyPresetMetadata(
        baseSavedFilterId = stashy["baseSavedFilterId"].stringValue,
        liveFragment = stashy["liveFragment"] as? JsonObject ?: JsonObject(emptyMap()),
        sortRaw = stashy["sortRaw"].stringValue?.trim()?.takeIf { it.isNotEmpty() },
    )
}

/** iOS: `criteriaObjectFilter()` — sanitized criteria for the editor. */
fun SavedFilter.criteriaObjectFilter(): JsonObject = CriteriaDocument.sanitize(filterDict ?: JsonObject(emptyMap()), filterMode)

/** Sort a saved filter carries (stashy `sortRaw`, else `find_filter`). */
fun SavedFilter.resolvedSort(mode: FilterMode): SortOption? = SortCatalog.choice(mode, stashyMetadata?.sortRaw, encodedSortPair)

// MARK: - Preset picker rows (iOS: `ListLivePresetTag`)

/** Preset picker row id: `""` | `server:<stashId>` | `local:<uuid>`. */
object ListLivePresetTag {
    const val SERVER_PREFIX = "server:"
    const val LOCAL_PREFIX = "local:"

    fun serverRow(id: String) = SERVER_PREFIX + id
    fun localRow(uuid: String) = LOCAL_PREFIX + uuid
    fun parseServerId(tagged: String): String? = if (tagged.startsWith(SERVER_PREFIX)) tagged.removePrefix(SERVER_PREFIX) else null
    fun parseLocalId(tagged: String): String? = if (tagged.startsWith(LOCAL_PREFIX)) tagged.removePrefix(LOCAL_PREFIX) else null
}

// MARK: - Local (on-device) presets

/**
 * iOS: `PerformerListLiveFilterPreset`, `SceneLiveFilterPreset`, … — same fields for every list.
 * `createdAt` is seconds since 2001-01-01 like a Swift `Date` encoded by `JSONEncoder`.
 */
@Serializable
data class LocalFilterPreset(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String,
    val createdAt: Double = System.currentTimeMillis() / 1000.0 - 978_307_200.0,
    val sortRaw: String,
    val baseSavedFilterId: String? = null,
    val liveFragmentJSON: String = "{}",
) {
    val liveFragment: JsonObject get() = runCatching { Json.parseToJsonElement(liveFragmentJSON) as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())

    fun renamed(newName: String) = copy(name = newName)

    companion object {
        fun create(name: String, sortRaw: String, baseSavedFilterId: String?, liveFragment: JsonObject, id: String? = null) =
            LocalFilterPreset(id = id ?: UUID.randomUUID().toString().uppercase(), name = name, sortRaw = sortRaw,
                baseSavedFilterId = baseSavedFilterId, liveFragmentJSON = liveFragment.toString())
    }
}

/** iOS: `<Kind>ListLiveFilterPresetStore` — JSON list per server under the same keys. */
object LocalFilterPresetStore {
    /** iOS storage key prefix per list (`<prefix>_<serverId>`). */
    fun keyPrefix(mode: FilterMode): String? = when (mode) {
        FilterMode.Scenes -> "stashy_scene_live_filter_presets"
        FilterMode.Performers -> "stashy_performer_catalog_live_filter_presets"
        FilterMode.Tags -> "stashy_tag_catalog_live_filter_presets"
        FilterMode.Studios -> "stashy_studio_catalog_live_filter_presets"
        FilterMode.Galleries -> "stashy_gallery_catalog_live_filter_presets"
        FilterMode.Images -> "stashy_image_catalog_live_filter_presets"
        FilterMode.SceneMarkers -> "stashy_marker_catalog_live_filter_presets"
        // Groups have no local presets on iOS.
        FilterMode.Groups, FilterMode.Unknown -> null
    }

    private fun key(mode: FilterMode): String? {
        val prefix = keyPrefix(mode) ?: return null
        val server = ServerConfigManager.activeConfig?.id ?: return null
        return "${prefix}_$server"
    }

    fun load(mode: FilterMode): List<LocalFilterPreset> {
        val k = key(mode) ?: return emptyList()
        val raw = Prefs.string(k) ?: return emptyList()
        return decode(raw)
    }

    fun decode(raw: String): List<LocalFilterPreset> =
        runCatching { Json.decodeFromString(ListSerializer(LocalFilterPreset.serializer()), raw) }.getOrDefault(emptyList())

    fun encode(list: List<LocalFilterPreset>): String = Json.encodeToString(ListSerializer(LocalFilterPreset.serializer()), list)

    /** Insert or replace, sorted by name (case-insensitive) like iOS. */
    fun upsert(mode: FilterMode, preset: LocalFilterPreset) {
        val k = key(mode) ?: return
        Prefs.setString(k, encode(upserted(load(mode), preset)))
    }

    fun upserted(all: List<LocalFilterPreset>, preset: LocalFilterPreset): List<LocalFilterPreset> {
        val list = all.toMutableList()
        val idx = list.indexOfFirst { it.id == preset.id }
        if (idx >= 0) list[idx] = preset else list.add(preset)
        return list.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    fun remove(mode: FilterMode, id: String) {
        val k = key(mode) ?: return
        Prefs.setString(k, encode(load(mode).filter { it.id != id }))
    }
}

// MARK: - Save helpers

/**
 * iOS: `mergedSceneObjectFilterForSave(base:live:previousLive:isMarker:)` — base saved filter
 * criteria with the live fragment on top; keys the chips owned before but no longer set are removed.
 */
fun mergedObjectFilterForSave(base: SavedFilter?, live: JsonObject, previousLive: JsonObject = JsonObject(emptyMap()), isMarker: Boolean = false): JsonObject {
    val merged = LinkedHashMap<String, JsonElement>()
    base?.filterDict?.takeIf { it.isNotEmpty() }?.let { merged.putAll(FilterMapper.sanitize(it, isMarker)) }
    val liveSan = FilterMapper.sanitize(live, isMarker)
    liveSan.forEach { (k, v) -> merged[k] = v }
    for (key in previousLive.keys) if (liveSan[key] == null) merged.remove(key)
    return JsonObject(merged)
}

/** Shorthand for an `INCLUDES` multi-id criterion (`{ value: [ids], modifier: INCLUDES }`). */
fun includesCriterion(vararg ids: String, depth: Int? = null): JsonObject = JsonObject(buildMap {
    put("value", JsonArray(ids.map { JsonPrimitive(it) }))
    put("modifier", JsonPrimitive("INCLUDES"))
    if (depth != null) put("depth", JsonPrimitive(depth))
})
