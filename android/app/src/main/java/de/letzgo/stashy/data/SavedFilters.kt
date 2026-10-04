package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * iOS: `StashDBViewModel.savedFilters` + `isLoadingSavedFilters` / `fetchSavedFilters()` — the
 * server's saved filters, one cache for catalogs, dashboard, channels and Settings. Cleared when
 * the active server changes.
 */
object SavedFiltersStore {
    val byId = mutableStateMapOf<String, SavedFilter>()
    var isLoading by mutableStateOf(false)
        private set
    var loadedOnce by mutableStateOf(false)
        private set
    /** Bumped after every finished load or reset (the map instance itself never changes). */
    var version by mutableIntStateOf(0)
        private set
    private var loadedFor: String? = null
    private val defaultScope: CoroutineScope = MainScope()

    /** Loads unless already loaded for the active server ([force] reloads). Returns at once while a load runs. */
    suspend fun load(force: Boolean = false) {
        val server = ServerConfigManager.activeConfig?.id
        if (loadedOnce && server != loadedFor) reset()
        if (isLoading || (!force && loadedOnce)) return
        isLoading = true
        run(server)
    }

    /** iOS `fetchSavedFilters()` — fire and forget, always reloads. */
    fun fetch(scope: CoroutineScope = defaultScope) {
        if (isLoading) return
        val server = ServerConfigManager.activeConfig?.id
        if (loadedOnce && server != loadedFor) reset()
        isLoading = true
        scope.launch { run(server) }
    }

    private suspend fun run(server: String?) {
        try {
            val list = SavedFiltersRepository.all()
            byId.clear()
            list.forEach { byId[it.id] = it }
            loadedFor = server
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
        } finally {
            isLoading = false
            loadedOnce = true
            version++
        }
    }

    /** Filters of one catalog mode, by name. */
    fun forMode(mode: FilterMode): List<SavedFilter> =
        byId.values.filter { it.filterMode == mode }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    /** Filters of one raw mode (`SCENES`, `IMAGES`, `SCENE_MARKERS` …), by name. */
    fun ofMode(mode: String): List<SavedFilter> = forMode(FilterMode.from(mode))

    fun reset() {
        byId.clear()
        loadedOnce = false
        loadedFor = null
        version++
    }
}
