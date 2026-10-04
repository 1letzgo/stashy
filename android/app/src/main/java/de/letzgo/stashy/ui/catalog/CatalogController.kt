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
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.criteriaObjectFilter
import de.letzgo.stashy.data.filterMode
import de.letzgo.stashy.data.mergedObjectFilterForSave
import de.letzgo.stashy.data.stashyMetadata
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.applySceneEvent
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

    /** Search term of the last query — the debounced search only refetches when it differs. */
    internal var lastQueriedSearch: String = ""
        private set

    /** A catalog root (not a detail list): Settings defaults and catalog requests apply. */
    val isCatalogRoot: Boolean get() = tabId != null && scope == null

    /** Settings defaults this controller has already reacted to (see [syncDefaults]). */
    private var seenPersistentSort: String? = tabId?.let { CatalogPrefs.persistentSortOption(it) }
    private var seenDefaultFilterId: String? = tabId?.let { CatalogPrefs.defaultFilterId(it) }

    init {
        // iOS `sceneLiveUpdates(using:)`: resume time, play count, O-count, edits, cover, delete.
        // Collected in the controller's own scope so a retained catalog keeps up while a scene
        // detail covers it (only the top screen is composed).
        if (mode == FilterMode.Scenes) coroutineScope.launch {
            SceneEvents.events.collect { event ->
                @Suppress("UNCHECKED_CAST")
                (list as PagedList<Scene>).applySceneEvent(event)
            }
        }
    }

    /** Passed as `filter:` only while the editor holds no copy of it (iOS `fetchBaseFilter`). */
    private val fetchBaseFilter: SavedFilter? get() = if (criteria.isEmpty) selectedFilter else null

    fun query(): CatalogQuery {
        lastQueriedSearch = search
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

    /**
     * Settings changed this catalog's default sort (iOS `DefaultSortChanged` → `changeSortOption`)
     * or default filter (iOS `DefaultFilterChanged`: select the new default, or none). Runs on
     * every [CatalogPrefs.defaultsVersion] bump and when the catalog reappears, because Settings
     * is another tab and only the top screen is composed.
     */
    fun syncDefaults() {
        val id = tabId ?: return
        if (!isCatalogRoot) return
        val persistentRaw = CatalogPrefs.persistentSortOption(id)
        if (persistentRaw != seenPersistentSort) {
            seenPersistentSort = persistentRaw
            SortCatalog.option(mode, persistentRaw)?.let { if (it != sort || it.isRandom) changeSort(it) }
        }
        val defId = CatalogPrefs.defaultFilterId(id)
        if (defId != seenDefaultFilterId) {
            seenDefaultFilterId = defId
            val filter = defId?.let { SavedFiltersStore.byId[it] }
            if (filter != null) {
                didApplyDefaultFilter = true
                criteria.clear()
                applyServerFilter(filter)
                presetRow = ListLivePresetTag.serverRow(filter.id)
            } else {
                // No default any more (or not loaded yet — then `onSavedFiltersLoaded` applies it).
                didApplyDefaultFilter = false
                selectedFilter = null
                presetRow = ""
                criteria.clear()
                applyLive()
            }
        }
    }

    /**
     * iOS `NavigationCoordinator.activeSortOption` / `activeSearchText` / `noDefaultFilter` —
     * what a dashboard header, a stats tile or Search "Show All" asked this catalog for.
     * Returns whether the list must be refetched.
     */
    fun applyRequest(request: Nav.CatalogRequest): Boolean {
        var changed = false
        request.sort?.let { SortCatalog.option(mode, it) }?.let { s ->
            if (s != sort || s.isRandom) {
                if (s.isRandom && sort.isRandom) RandomSeeds.refresh(mode)
                sort = s
                persistSort(s)
                changed = true
            }
        }
        if (request.noDefaultFilter) {
            didApplyDefaultFilter = true
            val defId = tabId?.let { CatalogPrefs.defaultFilterId(it) }
            if (defId != null && selectedFilter?.id == defId) {
                selectedFilter = null
                presetRow = ""
                criteria.clear()
                changed = true
            }
        }
        request.search?.let { text ->
            if (text != search) { search = text; changed = true }
        }
        return changed
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
        val catalogTab = CatalogTab.forMode(mode)
        // A pending request (dashboard header, Search "Show All") goes in before the first load.
        val pending = if (controller.isCatalogRoot && catalogTab != null) Nav.consumeCatalogRequest(catalogTab) else null
        val changed = pending?.let { controller.applyRequest(it) } ?: false
        controller.syncDefaults()
        val wasLoaded = controller.list.loadedOnce
        controller.onAppear()
        if (changed && wasLoaded) controller.refresh()
        // Requests arriving while this catalog is on screen.
        if (controller.isCatalogRoot && catalogTab != null) {
            snapshotFlow { Nav.catalogRequest }.collect { req ->
                if (req?.tab == catalogTab) Nav.consumeCatalogRequest(catalogTab)?.let { if (controller.applyRequest(it)) controller.refresh() }
            }
        }
    }
    LaunchedEffect(controller) {
        snapshotFlow { SavedFiltersStore.loadedOnce to SavedFiltersStore.byId.size }
            .distinctUntilChanged().drop(1)
            .collect { controller.onSavedFiltersLoaded() }
    }
    LaunchedEffect(controller) {
        snapshotFlow { CatalogPrefs.defaultsVersion }.distinctUntilChanged().drop(1).collect { controller.syncDefaults() }
    }
    LaunchedEffect(controller) {
        snapshotFlow { controller.search }.distinctUntilChanged().drop(1).debounce(500).collect {
            if (it != controller.lastQueriedSearch) controller.refresh()
        }
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
