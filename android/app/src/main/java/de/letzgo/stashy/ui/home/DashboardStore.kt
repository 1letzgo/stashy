package de.letzgo.stashy.ui.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.DashboardRepository
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.HomeRowConfig
import de.letzgo.stashy.data.HomeRowType
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersCache
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashStatistics
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.obj
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** iOS: `HomeRowStore` — one dashboard row's items and load state. */
data class HomeRowState(
    val scenes: List<Scene> = emptyList(),
    val performers: List<Performer> = emptyList(),
    val studios: List<Studio> = emptyList(),
    val galleries: List<Gallery> = emptyList(),
    val isLoading: Boolean = true,
    val lastLoadedAt: Long? = null,
) {
    val isEmpty get() = scenes.isEmpty() && performers.isEmpty() && studios.isEmpty() && galleries.isEmpty()
}

/**
 * Dashboard data kept warm across tab switches (iOS: the shared `StashDBViewModel` of
 * `HomeView` — statistics, home row caches, saved filters). Reset when the server changes.
 */
object DashboardStore {
    /** iOS `homeRowFreshness`: a row loaded within 60 s is not refetched on appear. */
    private const val FRESHNESS_MS = 60_000L
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var statistics by mutableStateOf<StashStatistics?>(null); private set
    var isLoadingStatistics by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    private val rows = mutableStateMapOf<HomeRowType, HomeRowState>()
    private val fetching = mutableSetOf<HomeRowType>()
    private var serverId: String? = null
    private var lastStatsFetch = 0L

    fun row(type: HomeRowType): HomeRowState = rows[type] ?: HomeRowState()

    /** Clears everything when the active server differs from the loaded one. */
    fun syncServer() {
        val id = ServerConfigManager.activeConfig?.id
        if (id != serverId) { serverId = id; reset() }
    }

    fun reset() {
        statistics = null; errorMessage = null; rows.clear(); fetching.clear(); lastStatsFetch = 0
    }

    /** iOS `fetchStatistics` (skips calls within 3 s). */
    fun loadStatistics(force: Boolean = false) {
        if (isLoadingStatistics) return
        if (!force && System.currentTimeMillis() - lastStatsFetch < 3000) return
        isLoadingStatistics = true
        errorMessage = null
        scope.launch {
            try {
                statistics = DashboardRepository.statistics()
            } catch (e: Exception) {
                errorMessage = e.message ?: "Statistics could not be loaded"
            } finally {
                lastStatsFetch = System.currentTimeMillis()
                isLoadingStatistics = false
            }
        }
    }

    /** iOS `initializeServerConnection` + pull-to-refresh: drop the row caches and reload. */
    fun refreshAll() {
        rows.clear(); fetching.clear()
        loadStatistics(force = true)
        scope.launch { SavedFiltersCache.load(force = true) }
    }

    /** The default dashboard filter, sanitised for `scene_filter` (iOS `fetchScenesForHomeRow`). */
    private fun dashboardSceneFilter(): JsonObject? {
        val id = TabManager.getDefaultFilterId(AppTab.Dashboard) ?: return null
        val saved = SavedFiltersCache.filters[id] ?: return null
        // iOS `filterDict`: `object_filter`, else the legacy UI filter string.
        val raw = saved.objectFilter.obj?.takeIf { it.isNotEmpty() }
            ?: saved.filter?.let { runCatching { de.letzgo.stashy.data.Json.parseToJsonElement(it).obj }.getOrNull() }
            ?: return null
        return JsonObject(DashboardFilterMapper.sanitize(raw).filterKeys { it != "sort" && it != "direction" })
    }

    /**
     * iOS `loadHomeRowIfNeeded` — loads unless loaded within [FRESHNESS_MS]; waits while the
     * default dashboard filter is still loading.
     */
    fun loadRowIfNeeded(config: HomeRowConfig, maxAgeMs: Long = FRESHNESS_MS) {
        val type = config.type
        if (type == HomeRowType.Statistics || type == HomeRowType.Channels) return
        val filterId = TabManager.getDefaultFilterId(AppTab.Dashboard)
        if (filterId != null && SavedFiltersCache.filters[filterId] == null && (SavedFiltersCache.isLoading || !SavedFiltersCache.loadedOnce)) {
            if (!SavedFiltersCache.isLoading) scope.launch { SavedFiltersCache.load() }
            return
        }
        val state = row(type)
        val loadedAt = state.lastLoadedAt
        if (!state.isEmpty && loadedAt != null && System.currentTimeMillis() - loadedAt < maxAgeMs) return
        if (type in fetching) return
        fetching += type
        rows[type] = state.copy(isLoading = true)
        scope.launch {
            val limit = 10
            val next = try {
                when {
                    type.isPerformerRow -> HomeRowState(performers = DashboardRepository.performers(type, limit))
                    type.isStudioRow -> HomeRowState(studios = DashboardRepository.studios(type, limit))
                    type.isGalleryRow -> HomeRowState(galleries = DashboardRepository.galleries(type, limit))
                    else -> HomeRowState(scenes = DashboardRepository.scenes(type, limit, dashboardSceneFilter()))
                }.copy(isLoading = false, lastLoadedAt = System.currentTimeMillis())
            } catch (e: Exception) {
                (rows[type] ?: HomeRowState()).copy(isLoading = false, lastLoadedAt = System.currentTimeMillis())
            }
            rows[type] = next
            fetching -= type
        }
    }

    /** Drops the scene rows (iOS `DefaultFilterChanged` for the dashboard). */
    fun clearSceneRows() {
        rows.keys.filter { it.isSceneRow }.forEach { rows.remove(it) }
    }
}

/** iOS `SavedFilter.resolvedSceneSort` → `SceneSortOption(graphqlField:direction:)` raw value. */
fun SavedFilter.sceneSortRaw(): String? {
    val field = (findFilter?.get("sort") as? JsonPrimitive)?.contentOrNull?.lowercase() ?: return null
    if (field.startsWith("random")) return "random"
    val asc = (findFilter["direction"] as? JsonPrimitive)?.contentOrNull?.uppercase() == "ASC"
    val base = when (field) {
        "date" -> "date"; "created_at" -> "createdAt"; "title" -> "title"; "duration" -> "duration"
        "last_played_at" -> "lastPlayedAt"; "play_count" -> "playCount"; "play_duration" -> "playDuration"
        "o_counter" -> "oCounter"; "rating", "rating100" -> "rating"
        else -> return null
    }
    return base + if (asc) "Asc" else "Desc"
}

/** iOS `SavedFilter.resolvedImageSort` → `ImageSortOption` raw value. */
fun SavedFilter.imageSortRaw(): String? {
    val field = (findFilter?.get("sort") as? JsonPrimitive)?.contentOrNull?.lowercase() ?: return null
    if (field.startsWith("random")) return "random"
    val asc = (findFilter["direction"] as? JsonPrimitive)?.contentOrNull?.uppercase() == "ASC"
    val base = when (field) {
        "title" -> "title"; "date" -> "date"; "rating", "rating100" -> "rating"; "created_at" -> "createdAt"; "updated_at" -> "updatedAt"
        else -> return null
    }
    return base + if (asc) "Asc" else "Desc"
}
