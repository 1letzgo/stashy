package de.letzgo.stashy.ui.catalog

import android.widget.Toast
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.CriteriaDocument
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.ListLivePresetTag
import de.letzgo.stashy.data.LocalFilterPreset
import de.letzgo.stashy.data.LocalFilterPresetStore
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.RandomSeeds
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.criteriaObjectFilter
import de.letzgo.stashy.data.filterMode
import de.letzgo.stashy.data.mergedObjectFilterForSave
import de.letzgo.stashy.data.stashyMetadata
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.filter.FilterPickerOptionsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** iOS: `StashDBViewModel.savedFilters` + `fetchSavedFilters()` — one cache for every list. */
object SavedFiltersStore {
    val byId = mutableStateMapOf<String, SavedFilter>()
    var isLoading by mutableStateOf(false)
        private set
    var loadedOnce by mutableStateOf(false)
        private set
    private var job: Job? = null

    fun fetch(scope: CoroutineScope) {
        if (isLoading) return
        isLoading = true
        job = scope.launch {
            try {
                val list = SavedFiltersRepository.all()
                byId.clear()
                list.forEach { byId[it.id] = it }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (_: Exception) {
            } finally {
                isLoading = false
                loadedOnce = true
            }
        }
    }

    fun forMode(mode: FilterMode): List<SavedFilter> =
        byId.values.filter { it.filterMode == mode }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    fun reset() { byId.clear(); loadedOnce = false }
}

/** iOS: `ToastManager.shared.show(…)` for save/rename/delete failures. */
internal fun showToast(text: String) {
    runCatching { Toast.makeText(Prefs.appContext, text, Toast.LENGTH_SHORT).show() }
}

/**
 * State of one catalog list with the unified "Filter & Sort" sheet (iOS: the per-view state in
 * `PerformersView`, `ScenesView`, … plus `DetailLinked*FilterModel`): sort, the selected saved
 * filter / local preset (`presetRow` = `""` | `server:<id>` | `local:<uuid>`), the criteria
 * document, paging. [scope] restricts the list for detail screens (e.g. a performer's galleries);
 * [tabId] (`AppTab` raw value) enables the persisted defaults of a catalog root.
 */
class CatalogController<T>(
    val mode: FilterMode,
    private val coroutineScope: CoroutineScope,
    val tabId: String? = CatalogPrefs.tabId(mode),
    val scope: JsonObject? = null,
    initialSort: SortOption? = null,
    /** Extra live criteria layered under the editor (Images "Type" chip). */
    private val extraLive: () -> JsonObject = { JsonObject(emptyMap()) },
    /** Where a session sort change goes (catalog tab vs. detail context). */
    private val persistSort: (SortOption) -> Unit = { s -> tabId?.let { CatalogPrefs.setSortOption(it, s.raw) } },
) {
    var sort by mutableStateOf(initialSort ?: CatalogPrefs.resolvedSort(mode))
        private set
    var search by mutableStateOf("")
    var selectedFilter by mutableStateOf<SavedFilter?>(null)
        private set
    var presetRow by mutableStateOf("")
        private set
    val criteria = CriteriaDocument(mode, pinsDefaults = true)
    var localPresets by mutableStateOf(LocalFilterPresetStore.load(mode))
        private set
    var isSheetPresented by mutableStateOf(false)
    private var didApplyDefaultFilter = false

    val list = PagedList<T>(coroutineScope, CatalogRepository.pageSize(mode)) { page, per ->
        CatalogRepository.find(query(), page, per)
    }

    /** Passed as `filter:` only while the editor holds no copy of it (iOS `fetchBaseFilter`). */
    private val fetchBaseFilter: SavedFilter? get() = if (criteria.isEmpty) selectedFilter else null

    fun query(): CatalogQuery {
        val extra = extraLive()
        return CatalogQuery(mode, sort, search, fetchBaseFilter, criteria.merged(extra), scope)
    }

    val serverFilters: List<SavedFilter> get() = SavedFiltersStore.forMode(mode)

    /** iOS: `catalogFilterSortFABActive`. */
    val isFilterActive: Boolean get() = selectedFilter != null || !criteria.isEmpty || presetRow.isNotEmpty()

    val selectedPresetName: String? get() {
        ListLivePresetTag.parseServerId(presetRow)?.let { sid -> return SavedFiltersStore.byId[sid]?.name }
        ListLivePresetTag.parseLocalId(presetRow)?.let { lid -> return localPresets.firstOrNull { it.id == lid }?.name }
        return null
    }

    fun refresh() = list.refresh()

    /** iOS `changeSortOption(to:)` — Random twice reshuffles. */
    fun changeSort(option: SortOption) {
        if (option.isRandom && sort.isRandom) RandomSeeds.refresh(mode)
        sort = option
        persistSort(option)
        refresh()
    }

    /** First appearance: saved filters, Settings default filter, then the first page. */
    fun onAppear() {
        if (!SavedFiltersStore.loadedOnce) SavedFiltersStore.fetch(coroutineScope)
        if (applySettingsDefaultFilterIfNeeded()) { refresh(); return }
        val defaultId = tabId?.let { CatalogPrefs.defaultFilterId(it) }
        if ((defaultId == null || SavedFiltersStore.loadedOnce) && !list.loadedOnce) refresh()
    }

    /** iOS `onChange(of: savedFilters)`: the default filter may only resolve once the list arrived. */
    fun onSavedFiltersLoaded() {
        if (selectedFilter != null) return
        if (applySettingsDefaultFilterIfNeeded()) refresh()
        else if (!list.loadedOnce && !list.isLoading) refresh()
    }

    private fun applySettingsDefaultFilterIfNeeded(): Boolean {
        if (didApplyDefaultFilter || selectedFilter != null || scope != null) return false
        val id = tabId?.let { CatalogPrefs.defaultFilterId(it) } ?: return false
        val filter = SavedFiltersStore.byId[id] ?: return false
        selectedFilter = filter
        didApplyDefaultFilter = true
        presetRow = ListLivePresetTag.serverRow(filter.id)
        return true
    }

    /** Settings changed the default sort / filter (iOS `DefaultSortChanged` / `DefaultFilterChanged`). */
    fun onDefaultsChanged() {
        val id = tabId ?: return
        val persistent = SortCatalog.option(mode, CatalogPrefs.persistentSortOption(id))
        if (persistent != null && persistent != sort) { sort = persistent }
        val defId = CatalogPrefs.defaultFilterId(id)
        if (defId != null && defId != selectedFilter?.id) {
            SavedFiltersStore.byId[defId]?.let { selectedFilter = it; presetRow = ListLivePresetTag.serverRow(it.id); criteria.clear() }
        }
        refresh()
    }

    /** Sheet opened: re-apply the selected row so the editor shows its criteria (iOS sheet `onAppear`). */
    fun onSheetAppear() {
        localPresets = LocalFilterPresetStore.load(mode)
        if (presetRow.isNotEmpty() && criteria.isEmpty) applyPresetRow(presetRow)
    }

    /** iOS `handle…PresetSelectionChange`. */
    fun selectPresetRow(row: String) {
        presetRow = row
        if (row.isEmpty()) {
            selectedFilter = null
            applyLive()
            return
        }
        applyPresetRow(row)
    }

    private fun applyPresetRow(row: String) {
        ListLivePresetTag.parseServerId(row)?.let { sid -> SavedFiltersStore.byId[sid]?.let { applyServerFilter(it) }; return }
        ListLivePresetTag.parseLocalId(row)?.let { lid -> localPresets.firstOrNull { it.id == lid }?.let { applyLocalPreset(it) } }
    }

    /** iOS `applyServerSceneSavedFilter` / `applyServer<Kind>SavedFilter`. */
    private fun applyServerFilter(f: SavedFilter) {
        selectedFilter = f
        val meta = f.stashyMetadata
        val isMarker = mode == FilterMode.SceneMarkers
        if (meta != null) {
            val base = meta.baseSavedFilterId?.let { SavedFiltersStore.byId[it] }
            val merged: JsonObject = when {
                base != null -> {
                    val m = LinkedHashMap<String, JsonElement>(base.criteriaObjectFilter())
                    FilterMapper.sanitize(meta.liveFragment, isMarker).forEach { (k, v) -> m[k] = v }
                    JsonObject(m)
                }
                meta.liveFragment.isNotEmpty() -> FilterMapper.sanitize(meta.liveFragment, isMarker)
                else -> f.criteriaObjectFilter()
            }
            criteria.load(merged)
            val parsed = SortCatalog.option(mode, meta.sortRaw)
            if (parsed != null && parsed != sort) {
                if (parsed.isRandom && sort.isRandom) RandomSeeds.refresh(mode)
                sort = parsed
                persistSort(parsed)
            }
        } else {
            criteria.load(f.criteriaObjectFilter())
        }
        applyLive()
    }

    private fun applyLocalPreset(p: LocalFilterPreset) {
        val parsed = SortCatalog.option(mode, p.sortRaw) ?: CatalogPrefs.resolvedSort(mode)
        if (parsed != sort) { sort = parsed; persistSort(parsed) }
        val base = p.baseSavedFilterId?.let { SavedFiltersStore.byId[it] }
        selectedFilter = base
        val m = LinkedHashMap<String, JsonElement>(base?.criteriaObjectFilter() ?: JsonObject(emptyMap()))
        FilterMapper.sanitize(p.liveFragment, mode == FilterMode.SceneMarkers).forEach { (k, v) -> m[k] = v }
        criteria.load(JsonObject(m))
        applyLive()
    }

    /** iOS `applyLiveFilter()` — editor edits refetch immediately. */
    fun applyLive() {
        persistSort(sort)
        refresh()
    }

    /** iOS sheet "Reset". */
    fun reset() {
        presetRow = ""
        selectedFilter = null
        criteria.clear()
        applyLive()
    }

    private val liveFragment: JsonObject get() = criteria.merged(extraLive()) ?: JsonObject(emptyMap())

    /** "Update <name>" — overwrites the selected server filter or local preset. */
    fun saveOverwrite() {
        val sid = ListLivePresetTag.parseServerId(presetRow)
        if (sid != null) {
            val existing = SavedFiltersStore.byId[sid] ?: return
            saveServer(existing.id, existing.name)
            return
        }
        val lid = ListLivePresetTag.parseLocalId(presetRow) ?: return
        val old = localPresets.firstOrNull { it.id == lid } ?: return
        LocalFilterPresetStore.upsert(mode, LocalFilterPreset.create(old.name, sort.raw, selectedFilter?.id, liveFragment, id = old.id))
        localPresets = LocalFilterPresetStore.load(mode)
    }

    /** "Save as new" — always a Stash saved filter (iOS). */
    fun saveAs(name: String) {
        if (name.isBlank()) return
        saveServer(null, name)
    }

    private fun saveServer(existingId: String?, name: String) {
        val previousLive = existingId?.let { SavedFiltersStore.byId[it]?.stashyMetadata?.liveFragment } ?: JsonObject(emptyMap())
        val base = selectedFilter?.takeIf { it.id != existingId }
        val merged = mergedObjectFilterForSave(base, liveFragment, previousLive, isMarker = mode == FilterMode.SceneMarkers)
        val input = SavedFiltersRepository.saveInput(
            mode, existingId, name, sort, merged, liveFragment, base?.id, FilterPickerOptionsStore.knownLabels(),
        )
        coroutineScope.launch {
            try {
                val saved = SavedFiltersRepository.save(input)
                SavedFiltersStore.byId[saved.id] = saved
                if (existingId == null) {
                    presetRow = ListLivePresetTag.serverRow(saved.id)
                    selectedFilter = saved
                }
                SavedFiltersStore.fetch(coroutineScope)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                showToast("Save failed: ${e.message}")
            }
        }
    }

    fun rename(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val sid = ListLivePresetTag.parseServerId(presetRow)
        if (sid != null) {
            val existing = SavedFiltersStore.byId[sid] ?: return
            // Rename keeps criteria, sort and stashy metadata (iOS `renameSavedFilter`).
            val sortForRename = de.letzgo.stashy.data.SortCatalog.choice(mode, existing.stashyMetadata?.sortRaw, null) ?: sort
            val input = SavedFiltersRepository.saveInput(
                existing.filterMode, existing.id, trimmed, sortForRename, existing.criteriaObjectFilter(),
                existing.stashyMetadata?.liveFragment, existing.stashyMetadata?.baseSavedFilterId, FilterPickerOptionsStore.knownLabels(),
            )
            coroutineScope.launch {
                try {
                    val saved = SavedFiltersRepository.save(input)
                    SavedFiltersStore.byId[saved.id] = saved
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    showToast("Rename failed: ${e.message}")
                }
            }
            return
        }
        val lid = ListLivePresetTag.parseLocalId(presetRow) ?: return
        val p = localPresets.firstOrNull { it.id == lid } ?: return
        LocalFilterPresetStore.upsert(mode, p.renamed(trimmed))
        localPresets = LocalFilterPresetStore.load(mode)
    }

    fun delete() {
        val sid = ListLivePresetTag.parseServerId(presetRow)
        if (sid != null) {
            coroutineScope.launch {
                try {
                    SavedFiltersRepository.destroy(sid)
                    SavedFiltersStore.byId.remove(sid)
                    if (selectedFilter?.id == sid) selectedFilter = null
                    presetRow = ""
                    criteria.clear()
                    refresh()
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    showToast("Delete failed: ${e.message}")
                }
            }
            return
        }
        val lid = ListLivePresetTag.parseLocalId(presetRow) ?: return
        LocalFilterPresetStore.remove(mode, lid)
        localPresets = LocalFilterPresetStore.load(mode)
        presetRow = ""
    }

    /** iOS `delete…ConfirmationText`. */
    val deleteConfirmationText: String get() {
        ListLivePresetTag.parseServerId(presetRow)?.let { sid ->
            SavedFiltersStore.byId[sid]?.let { return "Remove “${it.name}” from Stash? Other devices will lose this saved filter." }
        }
        ListLivePresetTag.parseLocalId(presetRow)?.let { lid ->
            localPresets.firstOrNull { it.id == lid }?.let { return "Remove “${it.name}” from this device? This cannot be undone." }
        }
        return "Remove this filter? This cannot be undone."
    }

    /** Current name for the rename dialog. */
    val renameSeed: String get() = selectedPresetName ?: ""
}

/**
 * Remembers a [CatalogController] and wires its lifecycle: first load, saved-filter arrival,
 * Settings default changes, server switches and the debounced search (0.5 s like iOS).
 */
@OptIn(FlowPreview::class)
@Composable
fun <T> rememberCatalogController(
    mode: FilterMode,
    key: Any? = null,
    /** Catalog roots keep their list warm across sub-tab switches (iOS shares one view model). */
    retain: Boolean = key == null,
    factory: (CoroutineScope) -> CatalogController<T> = { CatalogController(mode, it) },
): CatalogController<T> {
    val localScope = rememberCoroutineScope()
    val serverId = ServerConfigManager.activeConfig?.id
    val controller = remember(mode, key, serverId) {
        if (retain) RetainedCatalogs.get(mode, serverId) { factory(RetainedCatalogs.scope) } else factory(localScope)
    }
    LaunchedEffect(controller) {
        CatalogSearchDeepLink.consume(mode)?.let { controller.search = it }
        controller.onAppear()
    }
    LaunchedEffect(controller) {
        snapshotFlow { SavedFiltersStore.loadedOnce to SavedFiltersStore.byId.size }
            .distinctUntilChanged().drop(1)
            .collect { controller.onSavedFiltersLoaded() }
    }
    LaunchedEffect(controller) {
        snapshotFlow { CatalogPrefs.defaultsVersion }.distinctUntilChanged().drop(1).collect { controller.onDefaultsChanged() }
    }
    LaunchedEffect(controller) {
        snapshotFlow { controller.search }.distinctUntilChanged().drop(1).debounce(500).collect { controller.refresh() }
    }
    LaunchedEffect(serverId) {
        // A different server invalidates the shared saved-filter cache and picker options.
        if (lastServerId != null && serverId != lastServerId) {
            SavedFiltersStore.reset(); FilterPickerOptionsStore.invalidate(); CatalogPrefs.resetSession()
            SavedFiltersStore.fetch(RetainedCatalogs.scope)
        }
        lastServerId = serverId
    }
    return controller
}

/** Catalog-root controllers that outlive their composition (one per mode and server). */
object RetainedCatalogs {
    val scope: CoroutineScope = kotlinx.coroutines.MainScope()
    private val cache = HashMap<String, CatalogController<*>>()

    @Suppress("UNCHECKED_CAST")
    fun <T> get(mode: FilterMode, serverId: String?, create: () -> CatalogController<T>): CatalogController<T> {
        val k = "${mode.raw}|$serverId"
        return cache.getOrPut(k) { create() } as CatalogController<T>
    }
}

private var lastServerId: String? = null

/**
 * iOS: `NavigationCoordinator.activeSearchText` — Search › "Show all" opens a catalog with a
 * search term. Call [open] from the search screen; the catalog consumes it on appear.
 */
object CatalogSearchDeepLink {
    private val pending = HashMap<FilterMode, String>()

    fun open(tab: de.letzgo.stashy.ui.CatalogTab, text: String) {
        modeFor(tab)?.let { pending[it] = text }
        de.letzgo.stashy.ui.Nav.openCatalog(tab)
    }

    fun consume(mode: FilterMode): String? = pending.remove(mode)

    fun modeFor(tab: de.letzgo.stashy.ui.CatalogTab): FilterMode? = when (tab) {
        de.letzgo.stashy.ui.CatalogTab.Scenes -> FilterMode.Scenes
        de.letzgo.stashy.ui.CatalogTab.Images -> FilterMode.Images
        de.letzgo.stashy.ui.CatalogTab.Galleries -> FilterMode.Galleries
        de.letzgo.stashy.ui.CatalogTab.Performers -> FilterMode.Performers
        de.letzgo.stashy.ui.CatalogTab.Studios -> FilterMode.Studios
        de.letzgo.stashy.ui.CatalogTab.Tags -> FilterMode.Tags
        de.letzgo.stashy.ui.CatalogTab.Groups -> FilterMode.Groups
        de.letzgo.stashy.ui.CatalogTab.Markers -> FilterMode.SceneMarkers
        de.letzgo.stashy.ui.CatalogTab.Dashboard -> null
    }
}
