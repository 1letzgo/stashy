package de.letzgo.stashy.ui.home

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
import de.letzgo.stashy.data.PerformerEvents
import de.letzgo.stashy.data.LibraryEvent
import de.letzgo.stashy.data.LibraryEvents
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.tools.ForgottenFavorites
import de.letzgo.stashy.data.tools.SceneRecommendations
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import de.letzgo.stashy.data.applyingPerformerEvent
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
    /** iOS `homeRowFreshness`: the whole session — pull to refresh, a server switch or a new default filter clear the rows. */
    private const val FRESHNESS_MS = Long.MAX_VALUE
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
                // For You and Forgotten Favorites hold their own cards: patched in place, never rebuilt.
                SceneRecommendations.applySceneEvent(event)
                ForgottenFavorites.applySceneEvent(event)
                // A deleted scene or a new play / O count moves the statistics.
                if (event is SceneEvent.Deleted || event is SceneEvent.PlayAdded || event is SceneEvent.OCounterUpdated) scheduleStatisticsRefresh()
            }
        }
        // Performer, studio and gallery edits and deletes patch their rows in place (a deleted item leaves).
        scope.launch { LibraryEvents.events.collect { handle(it) } }
        // iOS `patchPerformerImageInLists` (`homeRowPerformers`) and the scene rows' performers.
        scope.launch {
            PerformerEvents.events.collect { event ->
                for ((type, state) in rows.toMap()) {
                    val performers = state.performers.applying(event)
                    val scenes = state.scenes.applyingPerformerEvent(event)
                    if (performers != null || scenes != null) {
                        rows[type] = state.copy(performers = performers ?: state.performers, scenes = scenes ?: state.scenes)
                    }
                }
            }
        }
    }

    private var statsRefreshJob: Job? = null

    /** One quiet statistics fetch after a burst of changes (no skeleton: the old numbers stay until the new ones arrive). */
    private fun scheduleStatisticsRefresh() {
        if (statistics == null) return
        statsRefreshJob?.cancel()
        statsRefreshJob = scope.launch {
            delay(1500)
            while (isLoadingStatistics) delay(300)
            runCatching { DashboardRepository.statistics() }.onSuccess { statistics = it; lastStatsFetch = System.currentTimeMillis() }
        }
    }

    /** Patches (or removes) the one item in every row that shows it; other items and the order stay. */
    private fun <T> List<T>.patched(id: String, idOf: (T) -> String, patch: ((T) -> T)?): List<T>? {
        val i = indexOfFirst { idOf(it) == id }
        if (i < 0) return null
        val next = patch?.invoke(this[i])
        if (next == this[i]) return null
        return toMutableList().apply { if (next == null) removeAt(i) else set(i, next) }
    }

    private fun handle(event: LibraryEvent) {
        for ((type, state) in rows.toMap()) {
            val next = when (event) {
                is LibraryEvent.PerformerPatched -> state.performers.patched(event.id, { it.id }, event.patch)?.let { state.copy(performers = it) }
                is LibraryEvent.PerformerDeleted -> state.performers.patched(event.id, { it.id }, null)?.let { state.copy(performers = it) }
                is LibraryEvent.StudioPatched -> state.studios.patched(event.id, { it.id }, event.patch)?.let { state.copy(studios = it) }
                is LibraryEvent.StudioDeleted -> state.studios.patched(event.id, { it.id }, null)?.let { state.copy(studios = it) }
                is LibraryEvent.GalleryPatched -> state.galleries.patched(event.id, { it.id }, event.patch)?.let { state.copy(galleries = it) }
                is LibraryEvent.GalleryDeleted -> state.galleries.patched(event.id, { it.id }, null)?.let { state.copy(galleries = it) }
                LibraryEvent.StatsChanged -> null
            }
            if (next != null) rows[type] = next
        }
        when (event) {
            is LibraryEvent.PerformerDeleted, is LibraryEvent.StudioDeleted, is LibraryEvent.GalleryDeleted, LibraryEvent.StatsChanged -> scheduleStatisticsRefresh()
            else -> {}
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
                errorMessage = e.message ?: tr(R.string.statistics_could_not_be_loaded)
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
        if (type == HomeRowType.Statistics || type.requiresStashyPlus) return
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
