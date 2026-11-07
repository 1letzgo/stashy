package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.FilterMapper
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
 * Stash web UI / object filter into a GraphQL `*_filter` input. Same mapper as the lists, so a
 * filter saved in Stash's web UI (resolution "1440p", gender labels, …) syncs the same files.
 */
object DownloadFilterSanitizer {
    fun sanitize(dict: JsonObject): JsonObject = FilterMapper.sanitize(dict)
}
