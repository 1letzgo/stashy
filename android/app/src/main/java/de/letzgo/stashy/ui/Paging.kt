package de.letzgo.stashy.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Page
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Infinite-scroll list state (iOS pattern: `currentPage`, `hasMorePages`, `isLoadingMore`).
 * `loader(page)` gets 1-based pages, like Stash's `FindFilterType.page`.
 */
class PagedList<T>(
    private val scope: CoroutineScope,
    val pageSize: Int = 40,
    private val loader: suspend (page: Int, perPage: Int) -> Page<T>,
) {
    val items = mutableStateListOf<T>()
    var totalCount by mutableStateOf(0); private set
    var isLoading by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set
    var loadedOnce by mutableStateOf(false); private set
    private var page = 0
    private var job: Job? = null

    val hasMore: Boolean get() = !loadedOnce || items.size < totalCount

    fun refresh() {
        job?.cancel()
        page = 0
        isLoading = false
        load(reset = true)
    }

    fun loadMore() {
        if (isLoading || !hasMore) return
        load(reset = false)
    }

    /**
     * Patches loaded items in place (live updates); [transform] returns null to drop an item,
     * which also lowers [totalCount].
     */
    fun patch(transform: (T) -> T?) {
        var removed = 0
        for (i in items.indices.reversed()) {
            val old = items[i]
            val new = transform(old)
            when {
                new == null -> { items.removeAt(i); removed++ }
                new != old -> items[i] = new
            }
        }
        if (removed > 0) totalCount = maxOf(0, totalCount - removed)
    }

    /** Call from the list when item [index] becomes visible. */
    fun onItemShown(index: Int) { if (index >= items.size - 8) loadMore() }

    private fun load(reset: Boolean) {
        isLoading = true
        error = null
        val next = page + 1
        job = scope.launch {
            try {
                val result = loader(next, pageSize)
                if (reset) items.clear()
                items.addAll(result.items)
                totalCount = result.count
                page = next
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Unknown error"
            } finally {
                loadedOnce = true
                isLoading = false
            }
        }
    }
}

/** iOS `sceneLiveUpdates(using:)` for one scene list. */
fun PagedList<Scene>.applySceneEvent(event: SceneEvent) = patch { event.applyTo(it) }
