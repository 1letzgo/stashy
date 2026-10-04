package de.letzgo.stashy.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Page
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
