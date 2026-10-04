package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.DownloadsMetadataCodec
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import java.util.UUID

/**
 * iOS: `DownloadSyncJob` (DownloadSyncJobs.swift) — a server saved filter plus how many of its
 * newest items one run fetches. Same JSON shape (`id`, `filterId`, `filterName`, `kind`, `amount`).
 */
@Serializable
data class DownloadSyncJob(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val filterId: String,
    val filterName: String,
    val kind: Kind,
    /** 0 = everything the filter matches. */
    val amount: Int,
) {
    @Serializable
    enum class Kind {
        @SerialName("scenes") Scenes,
        @SerialName("images") Images;

        val label: String get() = if (this == Scenes) "scenes" else "images"
    }

    val downloadsEverything: Boolean get() = amount <= 0
    /** Subtitle of the job pill. */
    val amountLabel: String get() = if (downloadsEverything) "all ${kind.label}" else "newest $amount ${kind.label}"
}

/** iOS: `DownloadSyncJobStore` — jobs per server under `download_sync_jobs_<serverId>`. */
object DownloadSyncJobStore {
    private val serializer = ListSerializer(DownloadSyncJob.serializer())

    var jobs by mutableStateOf<List<DownloadSyncJob>>(emptyList())
        private set

    private val storageKey: String get() = "download_sync_jobs_${ServerConfigManager.activeConfig?.id ?: "none"}"

    fun load() {
        jobs = Prefs.string(storageKey)?.let { runCatching { DownloadsMetadataCodec.json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()
    }

    private fun save() = Prefs.setString(storageKey, DownloadsMetadataCodec.json.encodeToString(serializer, jobs))

    fun add(job: DownloadSyncJob) { jobs = jobs + job; save() }

    fun update(job: DownloadSyncJob) {
        if (jobs.none { it.id == job.id }) return
        jobs = jobs.map { if (it.id == job.id) job else it }
        save()
    }

    fun remove(job: DownloadSyncJob) { jobs = jobs.filter { it.id != job.id }; save() }
}

/** The bits of iOS `StashDBViewModel.SavedFilter` the sync jobs need. */
@Serializable
data class DownloadSavedFilter(
    val id: String,
    val name: String = "",
    /** iOS `FilterMode` raw value: "SCENES", "IMAGES" … */
    val mode: String? = null,
    val filter: String? = null,
    @SerialName("object_filter") val objectFilter: JsonElement? = null,
) {
    val isScenes: Boolean get() = mode == "SCENES"
    val isImages: Boolean get() = mode == "IMAGES"

    /** iOS: `filterDict` — `object_filter` when present, else the UI filter JSON string. */
    val filterDict: JsonObject? get() {
        if (objectFilter != null && objectFilter !is JsonNull) return objectFilter as? JsonObject
        val text = filter?.takeIf { it.isNotBlank() } ?: return null
        return runCatching { de.letzgo.stashy.data.Json.parseToJsonElement(text) as? JsonObject }.getOrNull()
    }
}

/** iOS: `fetchSavedFilters` (`GraphQLQueries.findSavedFiltersQuery`). */
object DownloadSavedFilters {
    private const val QUERY = "query GetAllFilterDefinitions { findSavedFilters { id name mode filter object_filter ui_options find_filter { sort direction } } }"

    /** id → filter; empty map on error. */
    suspend fun fetch(): Map<String, DownloadSavedFilter> = runCatching {
        val data = GraphQL.data(QUERY)
        val list = GraphQL.decode(ListSerializer(DownloadSavedFilter.serializer()), data["findSavedFilters"] ?: JsonArray(emptyList()))
        list.associateBy { it.id }
    }.getOrDefault(emptyMap())
}

/** iOS: `DownloadSyncJobRunner`. */
object DownloadSyncJobRunner {
    fun run(job: DownloadSyncJob, filters: Map<String, DownloadSavedFilter>) {
        val filter = filters[job.filterId] ?: run {
            de.letzgo.stashy.ui.tools.showToast("Filter for ${job.filterName} is gone")
            return
        }
        val criteria = DownloadFilterSanitizer.sanitize(filter.filterDict ?: JsonObject(emptyMap()))
        val limit = if (job.downloadsEverything) null else job.amount
        when (job.kind) {
            DownloadSyncJob.Kind.Scenes -> Downloads.downloadScenes(Downloads.SceneDownloadScope.SavedFilter(criteria), limit, job.filterName)
            DownloadSyncJob.Kind.Images -> Downloads.downloadFilterImages(job.filterId, job.filterName, criteria, limit)
        }
    }

    fun runAll(jobs: List<DownloadSyncJob>, filters: Map<String, DownloadSavedFilter>) = jobs.forEach { run(it, filters) }
}

/**
 * iOS: `FilterMapper.sanitize` (SharedUtilities.swift) for scene/image saved filters — turns a
 * Stash UI / object filter into a GraphQL `*_filter` input. Pure Kotlin (unit-tested); the
 * marker-only branch is left out because jobs never run marker filters.
 */
object DownloadFilterSanitizer {
    private val invalidTopKeys = listOf("id", "sort", "direction", "mode", "displayMode", "zoomIndex", "sortDirection", "type", "inputType", "criterionOption")
    private val logicKeys = setOf("AND", "OR", "NOT")
    private val stringExtractionFields = setOf("is_missing", "has_markers", "has_chapters")
    private val intFields = setOf("rating", "rating100", "play_count", "resume_time", "scene_count", "duration", "o_counter", "id")
    private val multiSelectFields = setOf(
        "performers", "studios", "tags", "galleries", "scenes", "groups", "movies",
        "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups",
    )
    private val hierarchicalFields = setOf(
        "tags", "studios", "groups", "movies",
        "performer_tags", "scene_tags", "parents", "children", "containing_groups", "sub_groups",
    )
    private val singleEnumFields = setOf("gender", "ethnicity", "fake_tits", "hair_color", "eye_color", "career_length")
    private val booleanFields = setOf("interactive", "organized", "favorite", "performer_favorite", "studio_favorite", "gallery_favorite", "filter_favorites", "has_image", "ignore_auto_tag")

    fun sanitize(dict: JsonObject): JsonObject {
        var map = LinkedHashMap<String, JsonElement>(dict)

        // 1. The Stash UI `c` criteria array; remaining GraphQL keys win over it.
        val criteria = map["c"]
        if (criteria is JsonArray && criteria.all { it is JsonObject }) {
            val fromC = LinkedHashMap<String, JsonElement>()
            for (element in criteria) {
                val item = element as JsonObject
                var key = (item["id"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: continue
                if (key == "rating") key = "rating100"
                val isLogic = item["c"] != null || item["AND"] != null || item["OR"] != null || item["NOT"] != null
                fromC[key] = if (isLogic) sanitize(item) else processCriterion(key, item)
            }
            map.remove("c")
            val combined = LinkedHashMap(fromC)
            combined.putAll(map)
            map = combined
        }

        // 2. UI-only top-level keys.
        invalidTopKeys.forEach { map.remove(it) }

        // 3. Everything else, recursively.
        for (key in map.keys.toList()) {
            val value = map[key] ?: continue
            if (key in logicKeys) {
                when (value) {
                    is JsonArray -> if (value.all { it is JsonObject }) map[key] = JsonArray(value.map { sanitize(it as JsonObject) })
                    is JsonObject -> map[key] = sanitize(value)
                    else -> {}
                }
                continue
            }
            if (key.endsWith("_filter")) {
                if (value is JsonObject) map[key] = sanitize(value)
                continue
            }
            if (value is JsonObject) map[key] = processCriterion(key, value)
        }

        omitEmptyMultiIdCriteria(map)
        return JsonObject(map)
    }

    /** `INCLUDES` with no ids is "Any" — drop it; IS_NULL / NOT_NULL and pure excludes survive. */
    private fun omitEmptyMultiIdCriteria(map: MutableMap<String, JsonElement>) {
        for (key in listOf("tags", "studios", "groups", "performers", "galleries", "scenes", "movies")) {
            val criterion = map[key] as? JsonObject ?: continue
            val modifier = (criterion["modifier"] as? JsonPrimitive)?.content?.uppercase().orEmpty()
            if (modifier == "IS_NULL" || modifier == "NOT_NULL") continue
            if (idStrings(criterion["value"]).isEmpty() && idStrings(criterion["excludes"]).isEmpty()) map.remove(key)
        }
        val nested = map["scene_filter"] as? JsonObject ?: return
        val inner = LinkedHashMap<String, JsonElement>(nested)
        omitEmptyMultiIdCriteria(inner)
        if (inner.isEmpty()) map.remove("scene_filter") else map["scene_filter"] = JsonObject(inner)
    }

    private fun processCriterion(key: String, dict: JsonObject): JsonElement {
        val sub = LinkedHashMap<String, JsonElement>(dict)
        listOf("id", "type", "inputType", "criterionOption").forEach { sub.remove(it) }

        // Unwrap `{ value: … }`, `{ id: … }` and the web UI's `{ items, excluded, depth }`.
        (sub["value"] as? JsonObject)?.let { valueDict ->
            when {
                valueDict["value"] != null -> sub["value"] = valueDict.getValue("value")
                valueDict["id"] != null -> sub["value"] = valueDict.getValue("id")
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
        (sub["excludes"] as? JsonObject)?.let { excludesDict ->
            when {
                excludesDict["value"] != null -> sub["excludes"] = excludesDict.getValue("value")
                excludesDict["id"] != null -> sub["excludes"] = excludesDict.getValue("id")
                else -> {
                    val items = jsonArray(excludesDict["items"])
                    if (items.isNotEmpty()) {
                        sub["excludes"] = JsonArray(items)
                        if (sub["depth"] == null) excludesDict["depth"]?.let { sub["depth"] = it }
                    }
                }
            }
        }

        if (key in stringExtractionFields) {
            val v = sub["value"]
            ((v as? JsonObject)?.get("value") as? JsonPrimitive)?.takeIf { it.isString }?.let { return it }
            ((v as? JsonArray)?.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.let { return it }
            (v as? JsonPrimitive)?.takeIf { it.isString }?.let { return it }
            return JsonPrimitive("")
        }

        if (key == "orientation") {
            when (val v = sub["value"]) {
                is JsonArray -> sub["value"] = JsonArray(v.mapNotNull { item ->
                    when {
                        item is JsonPrimitive && item.isString -> JsonPrimitive(item.content.uppercase())
                        item is JsonObject -> (item["id"] as? JsonPrimitive)?.takeIf { it.isString }?.let { JsonPrimitive(it.content.uppercase()) }
                        else -> null
                    }
                })
                is JsonPrimitive -> if (v.isString) sub["value"] = JsonArray(listOf(JsonPrimitive(v.content.uppercase())))
                else -> {}
            }
            sub.remove("modifier")
        }

        if (key == "resolution" || key == "average_resolution") {
            (sub["value"] as? JsonPrimitive)?.takeIf { it.isString }?.let { sub["value"] = JsonPrimitive(it.content.uppercase()) }
        }

        if (key in intFields || key.endsWith("_count")) {
            sub["value"]?.let { sub["value"] = castToInt(it) }
            sub["value2"]?.let { sub["value2"] = castToInt(it) }
            val modifier = (sub["modifier"] as? JsonPrimitive)?.content
            if ((modifier == "IS_NULL" || modifier == "NOT_NULL") && sub["value"] == null) sub["value"] = JsonPrimitive(0)
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
            when (val v = sub["value"]) {
                is JsonArray -> (v.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.let { sub["value"] = JsonPrimitive(it.content.uppercase()) }
                is JsonPrimitive -> if (v.isString) sub["value"] = JsonPrimitive(v.content.uppercase())
                else -> {}
            }
        }

        if (key in booleanFields) {
            sub["value"]?.let { return JsonPrimitive(castToBool(it)) }
        }

        return JsonObject(sub)
    }

    private fun castToBool(value: JsonElement): Boolean {
        val p = value as? JsonPrimitive ?: return false
        if (p.isString) return p.content.lowercase().let { it == "true" || it == "1" || it == "yes" }
        p.booleanOrNull?.let { return it }
        p.longOrNull?.let { return it != 0L }
        return false
    }

    private fun castToInt(value: JsonElement): JsonElement {
        val p = value as? JsonPrimitive ?: return value
        if (p is JsonNull) return value
        if (p.isString) return p.content.toIntOrNull()?.let { JsonPrimitive(it) } ?: value
        p.longOrNull?.let { return JsonPrimitive(it) }
        p.doubleOrNull?.let { return JsonPrimitive(it.toLong()) }
        return value
    }

    private fun jsonArray(value: JsonElement?): List<JsonElement> = (value as? JsonArray)?.toList().orEmpty()

    private fun idString(value: JsonElement): String? = when (value) {
        is JsonNull -> null
        is JsonPrimitive -> {
            if (value.isString) value.content.trim().takeIf { it.isNotEmpty() }
            else value.longOrNull?.toString() ?: value.doubleOrNull?.toLong()?.toString()
        }
        is JsonObject -> value["id"]?.let { idString(it) } ?: value["value"]?.let { idString(it) }
        else -> null
    }

    /** IDs from a criterion `value` / `items` / single string or number. */
    fun idStrings(value: JsonElement?): List<String> {
        if (value == null) return emptyList()
        if (value is JsonObject) {
            if (value["items"] != null) return idStrings(value["items"])
            if (value["id"] != null) return idStrings(value["id"])
        }
        val array = jsonArray(value)
        if (array.isNotEmpty()) return array.mapNotNull { idString(it) }
        return idString(value)?.let { listOf(it) }.orEmpty()
    }
}
