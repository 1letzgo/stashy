package de.letzgo.stashy.ui.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.DashboardRepository
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.filterDict
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.HomeRowConfig
import de.letzgo.stashy.data.HomeRowType
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.applying
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashStatistics
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.TabManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

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

    init {
        // iOS `HomeView.sceneLiveUpdates(using:)` — patch the scene rows while a detail covers them.
        scope.launch {
            SceneEvents.events.collect { event ->
                for ((type, state) in rows.toMap()) {
                    state.scenes.applying(event)?.let { rows[type] = state.copy(scenes = it) }
                }
            }
        }
    }

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
        scope.launch { SavedFiltersStore.load(force = true) }
    }

    /** The default dashboard filter, sanitised for `scene_filter` (iOS `fetchScenesForHomeRow`). */
    private fun dashboardSceneFilter(): JsonObject? {
        val id = TabManager.getDefaultFilterId(AppTab.Dashboard) ?: return null
        val saved = SavedFiltersStore.byId[id] ?: return null
        // iOS `filterDict`: `object_filter`, else the legacy UI filter string.
        val raw = saved.filterDict ?: return null
        return JsonObject(FilterMapper.sanitize(raw).filterKeys { it != "sort" && it != "direction" })
    }

    /**
     * iOS `loadHomeRowIfNeeded` — loads unless loaded within [FRESHNESS_MS]; waits while the
     * default dashboard filter is still loading.
     */
    fun loadRowIfNeeded(config: HomeRowConfig, maxAgeMs: Long = FRESHNESS_MS) {
        val type = config.type
        if (type == HomeRowType.Statistics || type == HomeRowType.Channels) return
        val filterId = TabManager.getDefaultFilterId(AppTab.Dashboard)
        if (filterId != null && SavedFiltersStore.byId[filterId] == null && (SavedFiltersStore.isLoading || !SavedFiltersStore.loadedOnce)) {
            if (!SavedFiltersStore.isLoading) scope.launch { SavedFiltersStore.load() }
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

    private var handledFilterChange: Long? = null

    /** iOS `DefaultFilterChanged` — reloads the scene rows once per change of the dashboard filter. */
    fun onDefaultFilterChanged(change: Pair<AppTab, Long>?) {
        if (change == null || change.second == handledFilterChange) return
        handledFilterChange = change.second
        if (change.first == AppTab.Dashboard) clearSceneRows()
    }

    /** Drops the scene rows (iOS `DefaultFilterChanged` for the dashboard). */
    fun clearSceneRows() {
        rows.keys.filter { it.isSceneRow }.forEach { rows.remove(it) }
    }
}
