package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.coroutines.async
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject

/** iOS: `Statistics` (`stats { … }` + the standalone marker count). */
@Serializable
data class StashStatistics(
    @SerialName("scene_count") val sceneCount: Int = 0,
    @SerialName("image_count") val imageCount: Int = 0,
    @SerialName("gallery_count") val galleryCount: Int = 0,
    @SerialName("performer_count") val performerCount: Int = 0,
    @SerialName("studio_count") val studioCount: Int = 0,
    @SerialName("group_count") val groupCount: Int = 0,
    @SerialName("tag_count") val tagCount: Int = 0,
    @SerialName("total_o_count") val totalOCount: Int? = null,
    @SerialName("total_play_count") val totalPlayCount: Int? = null,
    @SerialName("scenes_played") val scenesPlayed: Int? = null,
    val sceneMarkerCount: Int? = null,
)

/**
 * Dashboard data (iOS: `StashDBViewModel.fetchStatistics`, `fetchSavedFilters`,
 * `fetch{Scenes,Performers,Studios,Galleries}ForHomeRow`).
 */
object DashboardRepository {
    private const val STATS_QUERY = "{ stats { scene_count image_count gallery_count performer_count studio_count group_count tag_count total_o_count total_play_count scenes_played } }"
    private const val MARKER_COUNT_QUERY = "{ findSceneMarkers(filter: { per_page: 1 }) { count } }"
    private const val CACHED_MARKER_COUNT_KEY = "cachedMarkerCount"

    /** Per-kind random seed like iOS (`random_<seed>`), stable for the session. */
    private val seed = (1..1_000_000).random()

    suspend fun statistics(): StashStatistics {
        val stats = GraphQL.decode(StashStatistics.serializer(), GraphQL.data(STATS_QUERY)["stats"] ?: throw GraphQLError.Query(tr(R.string.statistics_could_not_be_loaded)))
        val markers = runCatching { GraphQL.data(MARKER_COUNT_QUERY)["findSceneMarkers"].obj?.get("count").stringOrNull?.toIntOrNull() }.getOrNull()
        markers?.let { Prefs.setInt(Prefs.serverKey(CACHED_MARKER_COUNT_KEY), it) }
        return stats.copy(sceneMarkerCount = markers ?: Prefs.int(Prefs.serverKey(CACHED_MARKER_COUNT_KEY)).takeIf { it > 0 })
    }


    private fun filter(perPage: Int, sort: String, direction: String) = FindFilter(1, perPage, if (sort == "random") "random_$seed" else sort, direction)

    /** iOS `fetchScenesForHomeRow` — [sceneFilter] is the sanitised default dashboard filter. */
    suspend fun scenes(type: HomeRowType, limit: Int, sceneFilter: JsonObject?): List<Scene> {
        val (sort, dir) = when (type) {
            HomeRowType.LastPlayed -> "last_played_at" to "DESC"
            HomeRowType.LastAdded3Min -> "created_at" to "DESC"
            HomeRowType.Newest3Min -> "date" to "DESC"
            HomeRowType.MostViewed3Min -> "play_count" to "DESC"
            HomeRowType.TopCounter3Min -> "o_counter" to "DESC"
            HomeRowType.TopRating3Min -> "rating" to "DESC"
            HomeRowType.Random -> "random" to "DESC"
            else -> return emptyList()
        }
        return ScenesRepository.find(filter(limit, sort, dir), sceneFilter ?: buildJsonObject { }).items
    }

    suspend fun performers(type: HomeRowType, limit: Int): List<Performer> {
        val sort = when (type) {
            HomeRowType.NewPerformers -> "created_at"
            HomeRowType.PerformersHighestSceneCount -> "scenes_count"
            HomeRowType.PerformersHighestOCount -> "o_counter"
            HomeRowType.PerformersHighestRating -> "rating"
            else -> return emptyList()
        }
        return findPage("findPerformers", "findPerformers", "performers", Performer.serializer(), filter(limit, sort, "DESC"), "performer_filter", buildJsonObject { }).items
    }

    suspend fun studios(type: HomeRowType, limit: Int): List<Studio> {
        val sort = when (type) {
            HomeRowType.NewStudios -> "created_at"
            HomeRowType.StudiosHighestSceneCount -> "scenes_count"
            else -> return emptyList()
        }
        return findPage("findStudios", "findStudios", "studios", Studio.serializer(), filter(limit, sort, "DESC")).items
    }

    suspend fun galleries(type: HomeRowType, limit: Int): List<Gallery> {
        val sort = when (type) {
            HomeRowType.NewGalleries -> "created_at"
            HomeRowType.RecentlyUpdatedGalleries -> "updated_at"
            HomeRowType.GalleriesHighestImageCount -> "images_count"
            else -> return emptyList()
        }
        return findPage("findGalleries", "findGalleries", "galleries", Gallery.serializer(), filter(limit, sort, "DESC")).items
    }
}

/** iOS: `StashDBViewModel.search*Async` used by `UniversalSearchView`. */
object UniversalSearchRepository {
    private fun f(q: String, limit: Int, sort: String, dir: String) = FindFilter(1, limit, sort, dir, q)

    suspend fun performers(q: String, limit: Int) = findPage("findPerformers", "findPerformers", "performers", Performer.serializer(), f(q, limit, "name", "ASC")).items
    suspend fun studios(q: String, limit: Int) = findPage("findStudios", "findStudios", "studios", Studio.serializer(), f(q, limit, "name", "ASC")).items
    suspend fun groups(q: String, limit: Int) = findPage("findGroups", "findGroups", "groups", StashGroup.serializer(), f(q, limit, "name", "ASC")).items
    /** Most-used first (Tags catalog scene-count sort). */
    suspend fun tags(q: String, limit: Int) = findPage("findTags", "findTags", "tags", Tag.serializer(), f(q, limit, "scenes_count", "DESC")).items
    /**
     * iOS `searchScenesAsync`: Stash's `q` (title, details, path, …) plus a match on the studio
     * code, which `q` does not cover. Exact code hits lead, then the `q` hits, then partial code hits.
     */
    suspend fun scenes(q: String, limit: Int): List<Scene> = kotlinx.coroutines.coroutineScope {
        val text = async { findPage("findScenes", "findScenes", "scenes", Scene.serializer(), f(q, limit, "date", "DESC")).items }
        val code = async { runCatching { scenesByCode(q, limit) }.getOrDefault(emptyList()) }
        mergeSceneHits(text.await(), code.await(), q, limit)
    }

    /** Scenes whose studio code contains [q] (`code` criterion, INCLUDES), each with its code. */
    private suspend fun scenesByCode(q: String, limit: Int): List<Pair<Scene, String?>> {
        val needle = q.trim()
        if (needle.isEmpty()) return emptyList()
        val variables = buildJsonObject {
            put("filter", FindFilter(1, limit, "date", "DESC").json())
            put("scene_filter", vars("code" to mapOf("value" to needle, "modifier" to "INCLUDES")))
        }
        val list = GraphQL.named("findScenesByCode", variables)["findScenes"].obj?.get("scenes") as? JsonArray ?: return emptyList()
        return list.map { GraphQL.decode(Scene.serializer(), it) to it.obj?.get("code").stringOrNull }
    }

    private fun mergeSceneHits(text: List<Scene>, code: List<Pair<Scene, String?>>, q: String, limit: Int): List<Scene> {
        val needle = q.trim()
        val (exact, partial) = code.partition { it.second?.trim()?.equals(needle, ignoreCase = true) == true }
        return (exact.map { it.first } + text + partial.map { it.first }).distinctBy { it.id }.take(limit)
    }
    suspend fun images(q: String, limit: Int) = findPage("findImages", "findImages", "images", StashImage.serializer(), f(q, limit, "date", "DESC")).items
    suspend fun galleries(q: String, limit: Int) = findPage("findGalleries", "findGalleries", "galleries", Gallery.serializer(), f(q, limit, "date", "DESC")).items
    suspend fun markers(q: String, limit: Int) = findPage("findSceneMarkers", "findSceneMarkers", "scene_markers", SceneMarker.serializer(), f(q, limit, "title", "ASC")).items
}

/** iOS: `StashQueuedJob`. */
@Serializable
data class StashQueuedJob(
    val id: String,
    val status: String,
    val subTasks: List<String>? = null,
    val description: String? = null,
    val progress: Double? = null,
    val startTime: String? = null,
    val endTime: String? = null,
    val addTime: String? = null,
    val error: String? = null,
) {
    val isRunning get() = status == "RUNNING"
    val isQueued get() = status == "READY"
    /** Running or waiting — can still be cancelled. */
    val isActive get() = isRunning || isQueued || status == "STOPPING"
}

/** iOS: `LibraryCleanupCandidate`. */
data class LibraryCleanupCandidate(val id: String, val name: String, val isUnused: Boolean)

/** iOS: server tasks of `StashDBViewModel` (~6900–7300) + `LibraryCleanupRepository`. */
object ServerTasksRepository {
    private val scanOptionKeys = setOf(
        "rescan", "scanGenerateCovers", "scanGeneratePreviews", "scanGenerateImagePreviews",
        "scanGenerateSprites", "scanGeneratePhashes", "scanGenerateImagePhashes",
        "scanGenerateThumbnails", "scanGenerateClipPreviews",
    )

    /** Scan options saved on the server (`ui.taskDefaults.scan`, else `defaults.scan`). */
    private suspend fun serverScanOptions(): Map<String, Boolean> {
        val config = runCatching { GraphQL.named("configurationScanDefaults")["configuration"].obj }.getOrNull() ?: return emptyMap()
        fun bools(el: kotlinx.serialization.json.JsonElement?): Map<String, Boolean> =
            el.obj?.filterKeys { it in scanOptionKeys }?.mapNotNull { (k, v) -> v.stringOrNull?.toBooleanStrictOrNull()?.let { k to it } }?.toMap().orEmpty()
        val fromUI = bools(config["ui"].obj?.get("taskDefaults").obj?.get("scan"))
        return fromUI.ifEmpty { bools(config["defaults"].obj?.get("scan")) }
    }

    /** iOS `triggerLibraryScan` — returns the alert message. */
    suspend fun scan(): Pair<Boolean, String> {
        val options = serverScanOptions()
        return try {
            val job = GraphQL.named("metadataScan", vars("input" to options))["metadataScan"].stringOrNull
            if (!job.isNullOrEmpty()) {
                val enabled = options.values.count { it }
                true to (tr(R.string.library_scan_started_successfully) + if (options.isEmpty()) "" else " (${tr(R.string.arg_server_options_applied, enabled)})")
            } else false to tr(R.string.error_start_library_scan_please_check)
        } catch (e: Exception) {
            false to tr(R.string.error_start_library_scan_please_check)
        }
    }

    /** iOS `triggerIdentify` (library-wide, server defaults). */
    suspend fun identify(): Pair<Boolean, String> {
        val config = try { GraphQL.named("configuration")["configuration"].obj } catch (e: Exception) {
            return false to tr(R.string.error_start_identify_please_check_your)
        }
        val boxes = config?.get("general").obj?.get("stashBoxes").arr.orEmpty().mapNotNull { it.obj }
        if (boxes.isEmpty()) return false to tr(R.string.empty_stash_box_endpoints_configured_on)
        val identify = config?.get("defaults").obj?.get("identify").obj
        val defaultSources = identify?.get("sources").arr.orEmpty().mapNotNull { it.obj }
        val sources: List<Map<String, Any?>> = if (defaultSources.isNotEmpty()) {
            defaultSources.mapNotNull { src ->
                val endpoint = src["source"].obj?.get("stash_box_endpoint").stringOrNull ?: return@mapNotNull null
                buildMap {
                    put("source", mapOf("stash_box_endpoint" to endpoint))
                    src["options"].obj?.let { put("options", identifyOptions(it)) }
                }
            }
        } else boxes.map { mapOf("source" to mapOf("stash_box_endpoint" to it["endpoint"].stringOrNull)) }
        val options: Any = identify?.get("options").obj?.let { identifyOptions(it) } ?: mapOf(
            "fieldOptions" to listOf(
                mapOf("field" to "title", "strategy" to "OVERWRITE"),
                mapOf("field" to "studio", "strategy" to "MERGE", "createMissing" to true),
                mapOf("field" to "performers", "strategy" to "MERGE", "createMissing" to true),
                mapOf("field" to "tags", "strategy" to "MERGE", "createMissing" to true),
            ),
            "setCoverImage" to true, "setOrganized" to false, "includeMalePerformers" to false,
            "skipMultipleMatches" to true, "skipSingleNamePerformers" to true,
        )
        val names = boxes.joinToString(", ") { it["name"].stringOrNull ?: it["endpoint"].stringOrNull.orEmpty() }
        return try {
            GraphQL.named("metadataIdentify", vars("input" to mapOf("sources" to sources, "options" to options, "paths" to emptyList<String>())))
            true to tr(R.string.action_identify_started_using_arg, names)
        } catch (e: Exception) {
            false to tr(R.string.error_start_identify_please_check_your)
        }
    }

    /** iOS `identifyOptionsDict` — only set values; performerGenders wins over includeMalePerformers. */
    private fun identifyOptions(o: JsonObject): Map<String, Any?> = buildMap {
        o["fieldOptions"].arr?.let { fos ->
            put("fieldOptions", fos.mapNotNull { it.obj }.map { f ->
                buildMap {
                    put("field", f["field"].stringOrNull); put("strategy", f["strategy"].stringOrNull)
                    f["createMissing"].stringOrNull?.toBooleanStrictOrNull()?.let { put("createMissing", it) }
                }
            })
        }
        listOf("setCoverImage", "setOrganized", "skipMultipleMatches", "skipSingleNamePerformers").forEach { k ->
            o[k].stringOrNull?.toBooleanStrictOrNull()?.let { put(k, it) }
        }
        listOf("skipMultipleMatchTag", "skipSingleNamePerformerTag").forEach { k -> o[k].stringOrNull?.let { put(k, it) } }
        val genders = o["performerGenders"].arr?.mapNotNull { it.stringOrNull }
        if (!genders.isNullOrEmpty()) put("performerGenders", genders)
        else put("includeMalePerformers", o["includeMalePerformers"].stringOrNull?.toBooleanStrictOrNull() ?: false)
    }

    /** iOS `triggerGenerate` — [flags] are `GenerateMetadataInput` booleans set to true. */
    suspend fun generate(vararg flags: String): Pair<Boolean, String> = try {
        GraphQL.named("metadataGenerate", vars("input" to flags.associateWith { true }))
        true to tr(R.string.action_generate_started_successfully)
    } catch (e: Exception) {
        false to tr(R.string.error_start_generate_please_check_your)
    }

    /** Running first, then stopping, queued, finished (iOS `fetchJobQueue`). */
    suspend fun jobQueue(): List<StashQueuedJob>? = runCatching {
        val list = GraphQL.decode(ListSerializer(StashQueuedJob.serializer()), GraphQL.named("jobQueue")["jobQueue"]?.takeIf { it !is kotlinx.serialization.json.JsonNull } ?: kotlinx.serialization.json.JsonArray(emptyList()))
        fun rank(j: StashQueuedJob) = if (j.isRunning) 0 else if (j.status == "STOPPING") 1 else if (j.isQueued) 2 else 3
        list.sortedWith(compareBy<StashQueuedJob> { rank(it) }.thenBy { it.id.toIntOrNull() ?: 0 })
    }.getOrNull()

    suspend fun stopJob(id: String): Boolean = runCatching { GraphQL.named("stopJob", vars("id" to id))["stopJob"].stringOrNull == "true" }.getOrDefault(false)

    // MARK: Library cleanup

    private fun counted(o: JsonObject): LibraryCleanupCandidate {
        fun n(k: String) = o[k].stringOrNull?.toIntOrNull() ?: 0
        val unused = n("scene_count") == 0 && n("image_count") == 0 && n("gallery_count") == 0 &&
            n("performer_count") == 0 && n("group_count") == 0 && o["child_studios"].arr.isNullOrEmpty()
        return LibraryCleanupCandidate(o["id"].stringOrNull.orEmpty(), o["name"].stringOrNull.orEmpty(), unused)
    }

    /** All pages (500 each, max 60), falling back to the basic query on servers without `group_count`. */
    private suspend fun fetchAll(full: String, basic: String, field: String, list: String): List<LibraryCleanupCandidate> {
        var name = full
        val collected = mutableListOf<JsonObject>()
        var page = 1
        while (true) {
            val obj = try {
                GraphQL.named(name, vars("page" to page, "perPage" to 500))[field].obj
            } catch (e: Exception) {
                if (name == full) { name = basic; collected.clear(); page = 1; continue } else throw e
            }
            val items = obj?.get(list).arr.orEmpty().mapNotNull { it.obj }
            val total = obj?.get("count").stringOrNull?.toIntOrNull() ?: 0
            collected += items
            if (items.size < 500 || (total > 0 && collected.size >= total) || ++page > 60) break
        }
        return collected.map(::counted)
    }

    suspend fun unusedTags(): List<LibraryCleanupCandidate> {
        val all = mutableListOf<Tag>()
        var page = 1
        while (true) {
            val res = findPage("findTags", "findTags", "tags", Tag.serializer(), FindFilter(page, 500, "name", "ASC"))
            all += res.items
            if (res.items.size < 500 || (res.count > 0 && all.size >= res.count) || ++page > 60) break
        }
        return all.filter { (it.sceneCount ?: 0) == 0 && (it.imageCount ?: 0) == 0 && (it.galleryCount ?: 0) == 0 && (it.performerCount ?: 0) == 0 && (it.sceneMarkerCount ?: 0) == 0 }
            .map { LibraryCleanupCandidate(it.id, it.name, true) }
    }

    suspend fun unusedPerformers() = fetchAll("cleanupPerformers", "cleanupPerformersBasic", "findPerformers", "performers").filter { it.isUnused }
    suspend fun unusedStudios() = fetchAll("cleanupStudios", "cleanupStudiosBasic", "findStudios", "studios").filter { it.isUnused }

    /** `tagsDestroy` / `performersDestroy` / `studiosDestroy`. */
    suspend fun destroy(mutation: String, ids: List<String>): Boolean {
        if (ids.isEmpty()) return true
        val ok = GraphQL.named(mutation, vars("ids" to ids))[mutation].stringOrNull == "true"
        if (ok) postDestroyed(mutation, ids)
        return ok
    }

    /** Removes the destroyed items from Home's rows (tags only change the statistics). */
    fun postDestroyed(mutation: String, ids: List<String>) {
        when (mutation) {
            "performersDestroy" -> ids.forEach { LibraryEvents.post(LibraryEvent.PerformerDeleted(it)) }
            "studiosDestroy" -> ids.forEach { LibraryEvents.post(LibraryEvent.StudioDeleted(it)) }
        }
        LibraryEvents.post(LibraryEvent.StatsChanged)
    }
}
