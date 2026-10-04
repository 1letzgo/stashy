package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.GraphQLError
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.vars
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.format.DateTimeFormatter

/** iOS: `TimelineKind.savedFilter()` / `saveFilter(_:)` — key `stashy_timeline_kind_filter`. */
object TimelineKindFilter {
    private const val KEY = "stashy_timeline_kind_filter"

    fun saved(): Set<TimelineKind> {
        val stored = Prefs.string(KEY) ?: return TimelineKind.entries.toSet()
        val kinds = stored.split(",").mapNotNull { TimelineKind.from(it.trim()) }.toSet()
        return kinds.ifEmpty { TimelineKind.entries.toSet() }
    }

    fun save(kinds: Set<TimelineKind>) {
        val stored = (kinds.ifEmpty { TimelineKind.entries.toSet() }).map { it.raw }
        Prefs.setString(KEY, stored.joinToString(","))
    }
}

/**
 * iOS: `SessionTimelineLoader` — timeline from Stash server data only (scene `play_history`,
 * `o_history`, markers), loaded in 24 h windows back to 90 days. Live hooks for other features:
 * [scheduleLiveReload] (iOS `ScenePlayAdded`, `SceneMarkerCreated`, `SceneOCounterUpdated`).
 */
object SessionTimelineLoader {
    var sessions by mutableStateOf<List<TimelineSession>>(emptyList())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var isLoadingMore by mutableStateOf(false)
        private set
    var didFail by mutableStateOf(false)
        private set
    var hasMore by mutableStateOf(true)
        private set
    var loadedWindowStart by mutableStateOf<Instant?>(null)
        private set

    var loadedServerID: String? = null
        private set
    private var nextWindowEnd: Instant? = null
    private var consecutiveEmptyWindows = 0
    private var fetchGeneration = 0
    /** Scene `o_history` stamps for the full lookback; filtered per 24 h window when building. */
    private var oStampsCache: List<TimelineOStamp> = emptyList()
    private var liveReloadJob: Job? = null
    private var pendingLiveRefreshOHistory = false
    private var reloadJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Debounced live refresh so rapid O-taps / plays do not stack full pipeline runs. */
    fun scheduleLiveReload(refreshOHistory: Boolean) {
        if (refreshOHistory) pendingLiveRefreshOHistory = true
        liveReloadJob?.cancel()
        liveReloadJob = scope.launch {
            delay(450)
            val refreshO = pendingLiveRefreshOHistory
            pendingLiveRefreshOHistory = false
            reload(refreshO)
        }
    }

    /**
     * Full reload of the latest 24 h window. Runs in the loader's own scope (iOS: unstructured
     * task, so cancelling a pull-to-refresh does not abort the fetch); join the job to wait.
     */
    fun reload(refreshOHistory: Boolean = true): Job {
        // Non-suspending from here on, so cancelling a debounce job that called us is safe.
        liveReloadJob?.cancel()
        liveReloadJob = null
        pendingLiveRefreshOHistory = false
        fetchGeneration++
        val generation = fetchGeneration
        loadedServerID = ServerConfigManager.activeConfig?.id
        isLoading = true
        isLoadingMore = false
        didFail = false
        hasMore = true
        consecutiveEmptyWindows = 0
        nextWindowEnd = Instant.now()
        loadedWindowStart = null
        val shouldRefreshOHistory = refreshOHistory || oStampsCache.isEmpty()
        if (shouldRefreshOHistory) oStampsCache = emptyList()

        val job = scope.launch {
            loadNextWindow(isInitial = true, generation = generation, refreshOHistory = shouldRefreshOHistory)
            if (generation == fetchGeneration) isLoading = false
        }
        reloadJob = job
        return job
    }

    fun loadMore() {
        if (!hasMore || isLoading || isLoadingMore) return
        val generation = fetchGeneration
        isLoadingMore = true
        scope.launch {
            val before = sessions.size
            while (hasMore && sessions.size == before && generation == fetchGeneration) {
                val windowBefore = nextWindowEnd
                loadNextWindow(isInitial = false, generation = generation, refreshOHistory = false)
                if (nextWindowEnd == windowBefore) break // failed window: stop instead of spinning
            }
            if (generation == fetchGeneration) isLoadingMore = false
        }
    }

    fun reset() {
        liveReloadJob?.cancel()
        liveReloadJob = null
        pendingLiveRefreshOHistory = false
        fetchGeneration++
        sessions = emptyList()
        isLoading = false
        isLoadingMore = false
        didFail = false
        hasMore = true
        loadedWindowStart = null
        nextWindowEnd = null
        loadedServerID = null
        consecutiveEmptyWindows = 0
        oStampsCache = emptyList()
    }

    private suspend fun loadNextWindow(isInitial: Boolean, generation: Int, refreshOHistory: Boolean) {
        if (generation != fetchGeneration) return
        val windowEnd = nextWindowEnd ?: return
        val windowStart = windowEnd.minusSeconds(SessionTimelineGrouping.WINDOW_SECONDS)
        val earliest = Instant.now().minusSeconds(SessionTimelineGrouping.MAX_LOOKBACK_SECONDS)
        if (windowEnd <= earliest) {
            hasMore = false
            return
        }
        try {
            val lookbackStart = Instant.now().minusSeconds(SessionTimelineGrouping.MAX_LOOKBACK_SECONDS)
            val (rows, markers) = coroutineScope {
                val raw = async { fetchScenes(windowStart) }
                val markerRows = async { fetchMarkers(windowStart) }
                if (isInitial && (refreshOHistory || oStampsCache.isEmpty())) {
                    oStampsCache = fetchSceneOStamps(lookbackStart)
                }
                raw.await() to markerRows.await()
            }
            if (generation != fetchGeneration) return
            fun inWindow(d: Instant) = d >= windowStart && d < windowEnd
            val built = SessionTimelineGrouping.makeSessions(
                rows,
                oStampsCache.filter { inWindow(it.date) },
                markers.filter { inWindow(it.date) },
                windowStart, windowEnd,
            )
            sessions = if (isInitial) built else SessionTimelineGrouping.mergeWindow(sessions, built)
            if (built.isEmpty()) consecutiveEmptyWindows++ else consecutiveEmptyWindows = 0
            nextWindowEnd = windowStart
            loadedWindowStart = windowStart
            hasMore = windowStart > earliest && consecutiveEmptyWindows < 3
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (generation != fetchGeneration) return
            if (isInitial && sessions.isEmpty()) {
                didFail = true
                hasMore = false
            }
        }
    }

    // MARK: fetching

    private enum class QueryVariant(val extraFields: String) {
        Full("play_history o_history files { duration } tags { id name } performers { id name }"),
        WithoutPlayHistory("o_history files { duration } tags { id name } performers { id name }"),
        Minimal(""),
        RecentUpdated("");

        val usesLastPlayedFilter: Boolean get() = this != RecentUpdated
        val sortField: String get() = if (this == RecentUpdated) "updated_at" else "last_played_at"

        val query: String get() = """
            query FindSessionTimeline(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
              findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) {
                count
                scenes {
                  id title last_played_at play_duration play_count resume_time rating100
                  paths { screenshot }
                  studio { id name }
                  $extraFields
                }
              }
            }
        """.trimIndent()
    }

    private suspend fun fetchScenes(start: Instant): List<TimelineSceneRowData> {
        var lastError: Exception? = null
        for (variant in QueryVariant.entries) {
            try {
                return fetchScenes(start, variant)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                lastError = e
            }
        }
        throw lastError ?: GraphQLError.Query("Query failed")
    }

    private suspend fun fetchScenes(start: Instant, variant: QueryVariant): List<TimelineSceneRowData> {
        var page = 1
        val perPage = 100
        var total = Int.MAX_VALUE
        val rows = mutableListOf<TimelineSceneRowData>()
        while ((page - 1).toLong() * perPage < total) {
            val variables = if (variant.usesLastPlayedFilter) vars(
                "filter" to mapOf("page" to page, "per_page" to perPage, "sort" to variant.sortField, "direction" to "DESC"),
                "scene_filter" to mapOf("last_played_at" to mapOf("modifier" to "GREATER_THAN", "value" to isoString(start))),
            ) else vars(
                "filter" to mapOf("page" to page, "per_page" to perPage, "sort" to variant.sortField, "direction" to "DESC"),
            )
            val data = GraphQL.data(variant.query, variables)
            val result = GraphQL.decode(TLScenesPayload.serializer(), data["findScenes"] ?: JsonObject(emptyMap()))
            val pageRows = result.scenes.orEmpty()
            total = result.count ?: pageRows.size
            rows.addAll(pageRows.mapNotNull { it.toRowData() })
            if (pageRows.size < perPage) break
            page++
            if (page > 30) break
        }
        return rows
    }

    /** All scene O-count action times from Stash `o_history` (independent of play windows). */
    private suspend fun fetchSceneOStamps(start: Instant): List<TimelineOStamp> {
        val query = """
            query FindSceneOHistory(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
              findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) {
                count
                scenes { id title o_history rating100 paths { screenshot } studio { id name } performers { id name } }
              }
            }
        """.trimIndent()
        var page = 1
        val perPage = 200
        var total = Int.MAX_VALUE
        val stamps = mutableListOf<TimelineOStamp>()
        try {
            while ((page - 1).toLong() * perPage < total) {
                val data = GraphQL.data(
                    query,
                    vars(
                        "filter" to mapOf("page" to page, "per_page" to perPage, "sort" to "o_counter", "direction" to "DESC"),
                        "scene_filter" to mapOf("o_counter" to mapOf("value" to 0, "modifier" to "GREATER_THAN")),
                    ),
                )
                val result = GraphQL.decode(TLScenesPayload.serializer(), data["findScenes"] ?: JsonObject(emptyMap()))
                val scenes = result.scenes.orEmpty()
                total = result.count ?: scenes.size
                for (scene in scenes) {
                    val snapshot = scene.snapshot(includeDetails = false) ?: continue
                    scene.oHistory.orEmpty().mapNotNull { OCountHeatmapBucketing.flexibleTime(it) }
                        .filter { it >= start }
                        .forEach { stamps.add(TimelineOStamp(snapshot, it)) }
                }
                if (scenes.size < perPage) break
                page++
                if (page > 100) break
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
        return stamps
    }

    private suspend fun fetchMarkers(start: Instant): List<TimelineFetchedMarker> {
        val query = """
            query TimelineMarkers(${'$'}filter: FindFilterType, ${'$'}scene_marker_filter: SceneMarkerFilterType) {
              findSceneMarkers(filter: ${'$'}filter, scene_marker_filter: ${'$'}scene_marker_filter) {
                count
                scene_markers {
                  id title screenshot created_at
                  scene { id title paths { screenshot } studio { id name } }
                }
              }
            }
        """.trimIndent()
        var page = 1
        val perPage = 100
        var total = Int.MAX_VALUE
        val rows = mutableListOf<TimelineFetchedMarker>()
        try {
            while ((page - 1).toLong() * perPage < total) {
                val data = GraphQL.data(
                    query,
                    vars(
                        "filter" to mapOf("page" to page, "per_page" to perPage, "sort" to "created_at", "direction" to "DESC"),
                        "scene_marker_filter" to mapOf("created_at" to mapOf("modifier" to "GREATER_THAN", "value" to isoString(start))),
                    ),
                )
                val result = GraphQL.decode(TLMarkersPayload.serializer(), data["findSceneMarkers"] ?: JsonObject(emptyMap()))
                val pageRows = result.sceneMarkers.orEmpty().mapNotNull { it.toMarker() }
                total = result.count ?: pageRows.size
                rows.addAll(pageRows)
                if (pageRows.size < perPage) break
                page++
                if (page > 30) break
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
        return rows
    }

    /** iOS: `ISO8601DateFormatter` with `.withInternetDateTime` (UTC, `Z`, no fraction). */
    private fun isoString(date: Instant): String =
        DateTimeFormatter.ISO_INSTANT.format(date.truncatedTo(java.time.temporal.ChronoUnit.SECONDS))
}

// Decoding payloads (iOS: `TimelineScenesResponse`, `TimelineOHistoryResponse`, `TimelineMarkersResponse`).

@Serializable
internal data class TLDuration(val duration: Double? = null)

@Serializable
internal data class TLPaths(val screenshot: String? = null)

@Serializable
internal data class TLSceneRow(
    val id: String? = null,
    val title: String? = null,
    @SerialName("last_played_at") val lastPlayedAt: JsonElement? = null,
    @SerialName("play_duration") val playDuration: Double? = null,
    @SerialName("play_count") val playCount: Int? = null,
    @SerialName("resume_time") val resumeTime: Double? = null,
    val rating100: Int? = null,
    @SerialName("play_history") val playHistory: List<JsonElement>? = null,
    @SerialName("o_history") val oHistory: List<JsonElement>? = null,
    val files: List<TLDuration>? = null,
    val paths: TLPaths? = null,
    val studio: OCNamed? = null,
    val tags: List<OCNamed>? = null,
    val performers: List<OCNamed>? = null,
) {
    /** iOS: `TimelineSceneRow.snapshot` / `TimelineOHistoryResponse.Row.snapshot`. */
    fun snapshot(includeDetails: Boolean = true): TimelineSceneSnapshot? {
        val id = id ?: return null
        val studioModel = studio?.let { s -> val sid = s.id; val n = s.name; if (sid != null && !n.isNullOrEmpty()) IdName(sid, n) else null }
        return TimelineSceneSnapshot(
            id = id,
            title = title?.takeIf { it.trim().isNotEmpty() } ?: "Untitled",
            thumbnailPath = paths?.screenshot,
            duration = if (includeDetails) files?.mapNotNull { it.duration }?.maxOrNull() else null,
            resumeTime = if (includeDetails) resumeTime else null,
            studio = studioModel,
            tags = if (includeDetails) tags.orEmpty().mapNotNull { t -> t.id?.let { tid -> t.name?.let { IdName(tid, it) } } } else emptyList(),
            performers = performers.orEmpty().mapNotNull { p -> p.id?.let { pid -> p.name?.let { IdName(pid, it) } } },
            rating100 = rating100,
        )
    }

    fun toRowData(): TimelineSceneRowData? {
        val snapshot = snapshot() ?: return null
        return TimelineSceneRowData(
            snapshot = snapshot,
            playHistory = playHistory.orEmpty().mapNotNull { OCountHeatmapBucketing.flexibleTime(it) },
            lastPlayedAt = OCountHeatmapBucketing.flexibleTime(lastPlayedAt),
            oHistory = oHistory.orEmpty().mapNotNull { OCountHeatmapBucketing.flexibleTime(it) },
            playDuration = playDuration,
            playCount = playCount,
        )
    }
}

@Serializable
internal data class TLScenesPayload(val count: Int? = null, val scenes: List<TLSceneRow>? = null)

@Serializable
internal data class TLMarkerScene(val id: String? = null, val title: String? = null, val paths: TLPaths? = null, val studio: OCNamed? = null)

@Serializable
internal data class TLMarkerRow(
    val id: String? = null,
    val title: String? = null,
    val screenshot: String? = null,
    @SerialName("created_at") val createdAt: JsonElement? = null,
    val scene: TLMarkerScene? = null,
) {
    /** iOS: `TimelineFetchedMarker.init?(row:)`. */
    fun toMarker(): TimelineFetchedMarker? {
        val id = id?.takeIf { it.isNotEmpty() } ?: return null
        val sc = scene ?: return null
        val sceneId = sc.id?.takeIf { it.isNotEmpty() } ?: return null
        val date = OCountHeatmapBucketing.flexibleTime(createdAt) ?: return null
        val shot = screenshot?.trim()
        val sceneShot = sc.paths?.screenshot?.trim()
        val sid = sc.studio?.id
        val sname = sc.studio?.name
        return TimelineFetchedMarker(
            id = id,
            sceneId = sceneId,
            date = date,
            title = title?.trim()?.takeIf { it.isNotEmpty() },
            sceneTitle = sc.title?.trim()?.takeIf { it.isNotEmpty() },
            thumbnailPath = if (!shot.isNullOrEmpty()) shot else sceneShot,
            studio = if (sid != null && !sname.isNullOrEmpty()) IdName(sid, sname) else null,
        )
    }
}

@Serializable
internal data class TLMarkersPayload(val count: Int? = null, @SerialName("scene_markers") val sceneMarkers: List<TLMarkerRow>? = null)
