package de.letzgo.stashy.ui.tools.filters

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.tools.FiltersToolEntry
import de.letzgo.stashy.data.tools.FiltersToolRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Hooks into the filter editor (iOS: `FiltersToolsEditorSheet` with `FilterCriteriaEditorView`),
 * which is ported separately in `ui/filter/`. The editor feature sets these at start-up; while
 * they are null, tapping a filter or a "+" entry shows "Filter editor not available yet".
 * After saving or deleting, the editor should call [FiltersToolState.refresh].
 */
object FiltersToolHooks {
    /** iOS: tap on a row → `editingFilter = filter` (sheet "Edit filter"). */
    @JvmStatic var onEditSavedFilter: ((SavedFilter) -> Unit)? = null

    /**
     * iOS: "+" menu → `createMode = mode; isCreating = true` (sheet "New filter").
     * The argument is the raw Stash `FilterMode` (`SCENES`, `SCENE_MARKERS`, `PERFORMERS`, …).
     */
    @JvmStatic var onCreateFilter: ((mode: String) -> Unit)? = null
}

/**
 * iOS: the saved-filter slice of `StashDBViewModel` used by `FiltersToolsView`
 * (`savedFilters`, `isLoadingSavedFilters`, `fetchSavedFilters`, rename, destroy).
 */
object FiltersToolState {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** iOS: `savedFilters` keyed by id. */
    val filters = mutableStateMapOf<String, FiltersToolEntry>()
    var isLoading by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    /** Server the list belongs to; a different server clears it first. */
    private var serverId: String? = null
    private var isFetching = false

    /** iOS: `fetchSavedFilters()` — ignored while a fetch is running. */
    fun refresh() {
        if (isFetching) return
        isFetching = true
        isLoading = true
        scope.launch {
            try {
                val list = FiltersToolRepository.findSavedFilters()
                filters.clear()
                list.forEach { filters[it.filter.id] = it }
                errorMessage = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = "Failed to load filters: ${e.message}"
            } finally {
                isFetching = false
                isLoading = false
            }
        }
    }

    /** Clears the list when the active server changed. */
    fun syncServer(id: String?) {
        if (id != serverId) {
            filters.clear()
            serverId = id
        }
    }

    /** iOS: `rename(filter:to:)` → `renameSavedFilter`, then refetch. */
    fun rename(entry: FiltersToolEntry, name: String, onResult: (Result<Unit>) -> Unit) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        scope.launch {
            val result = runCatchingNonCancel { FiltersToolRepository.rename(entry, trimmed) }
            result.onSuccess { saved -> filters[saved.filter.id] = saved; refresh() }
            onResult(result.map { })
        }
    }

    /** iOS: `delete(filter:)` → `destroySavedSceneFilter`, then refetch. */
    fun delete(entry: FiltersToolEntry, onResult: (Result<Unit>) -> Unit) {
        scope.launch {
            val result = runCatchingNonCancel { FiltersToolRepository.delete(entry.filter.id) }
            result.onSuccess { filters.remove(entry.filter.id); refresh() }
            onResult(result)
        }
    }

    private suspend fun <T> runCatchingNonCancel(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        Result.failure(e)
    }
}
