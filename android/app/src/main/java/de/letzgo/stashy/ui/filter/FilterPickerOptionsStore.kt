package de.letzgo.stashy.ui.filter

import androidx.compose.runtime.mutableStateMapOf
import de.letzgo.stashy.data.FilterEntityOption
import de.letzgo.stashy.data.FilterPickerRepository
import de.letzgo.stashy.data.PickerKind
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * iOS: `FilterPickerOptionsStore` — shared, cached entity options (studios / tags / groups /
 * performers) for the criteria editor's multi-pickers, plus server-side name search whose hits
 * are merged on top of the cached "most used" list.
 */
object FilterPickerOptionsStore {
    private val scope = MainScope()
    private val options = mutableStateMapOf<PickerKind, List<FilterEntityOption>>()
    private val loading = mutableStateMapOf<PickerKind, Boolean>()
    private val searchResults = mutableStateMapOf<PickerKind, List<FilterEntityOption>>()
    private val searching = mutableStateMapOf<PickerKind, Boolean>()
    private val searchJobs = HashMap<PickerKind, Job>()

    fun invalidate() {
        options.clear(); loading.clear(); searchResults.clear(); searching.clear()
        searchJobs.values.forEach { it.cancel() }; searchJobs.clear()
    }

    fun isLoading(kind: PickerKind) = loading[kind] == true
    fun isSearching(kind: PickerKind) = searching[kind] == true
    fun searchHits(kind: PickerKind): List<FilterEntityOption> = searchResults[kind] ?: emptyList()

    /** id → name over every cached list (labels for the web UI's `{id,label}` pairs). */
    fun knownLabels(): Map<String, String> {
        val out = HashMap<String, String>()
        options.values.forEach { l -> l.forEach { out[it.id] = it.name } }
        searchResults.values.forEach { l -> l.forEach { out[it.id] = it.name } }
        return out
    }

    fun availableOptions(kind: PickerKind): List<FilterEntityOption> {
        val base = options[kind] ?: emptyList()
        val extra = searchResults[kind] ?: return base
        val seen = base.map { it.id }.toMutableSet()
        return base + extra.filter { seen.add(it.id) }
    }

    fun load(kind: PickerKind) {
        if (!options[kind].isNullOrEmpty() || loading[kind] == true) return
        loading[kind] = true
        scope.launch {
            try {
                options[kind] = FilterPickerRepository.load(kind)
            } catch (_: Exception) {
                options[kind] = emptyList()
            } finally {
                loading[kind] = false
            }
        }
    }

    /** Name search (≥ 2 characters); only the newest call per kind is applied. */
    fun search(kind: PickerKind, query: String) {
        searchJobs[kind]?.cancel()
        val term = query.trim()
        if (term.length < 2) { searching[kind] = false; return }
        searching[kind] = true
        searchJobs[kind] = scope.launch {
            try {
                val hits = FilterPickerRepository.search(kind, term)
                val merged = (searchResults[kind] ?: emptyList()).toMutableList()
                val seen = merged.map { it.id }.toMutableSet()
                hits.forEach { if (seen.add(it.id)) merged.add(it) }
                searchResults[kind] = merged
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
            } finally {
                // A newer keystroke owns the spinner now.
                if (searchJobs[kind] === coroutineContext[Job]) searching[kind] = false
            }
        }
    }
}
