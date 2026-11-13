package de.letzgo.stashy.ui.catalog

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
import de.letzgo.stashy.data.CatalogQuickSortCatalog
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.CriteriaDocument
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.filterEntity
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.LibraryEvent
import de.letzgo.stashy.data.LibraryEvents
import de.letzgo.stashy.data.ListLivePresetTag
import de.letzgo.stashy.data.LocalFilterPreset
import de.letzgo.stashy.data.LocalFilterPresetStore
import de.letzgo.stashy.data.NameRegexFilter
import de.letzgo.stashy.data.Page
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.RandomSeeds
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.PerformerEvents
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.StudioCountsStore
import de.letzgo.stashy.data.SubStudios
import de.letzgo.stashy.data.criteriaObjectFilter
import de.letzgo.stashy.data.filterMode
import de.letzgo.stashy.data.filterDict
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
    /** Page size (detail tabs keep their smaller iOS pages). */
    perPage: Int = CatalogRepository.pageSize(mode),
    /** Page loader; detail tabs route through `DetailRepository.findScoped` (old-server fallback). */
    private val fetch: (suspend (CatalogQuery, Int, Int) -> Page<T>)? = null,
    /** List-specific sorts offered first in the quick bar and the sheet (a group's scene number). */
    val extraSorts: List<SortOption> = emptyList(),
    /** Where the Settings default filter comes from (Magazin keeps its own). */
    private val defaultFilterIdFor: (String) -> String? = CatalogPrefs::defaultFilterId,
    /** A scope that changes while the screen lives (a studio's "Include sub-studio content"); replaces [scope] in the query. */
    private val dynamicScope: (() -> JsonObject)? = null,
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

    /**
     * Committed text of the sheet's "Name or regex" field — a live chip on `name` / `title`
     * (see [NameRegexFilter]); always valid, `""` = off. Layered over the criteria like any chip.
     */
    var nameRegex by mutableStateOf("")
        private set

    val supportsNameRegex: Boolean get() = NameRegexFilter.isSupported(mode)

    /** Applies the field (IME search / Done / clear). Invalid input is rejected and not applied. */
    fun commitNameRegex(input: String): Boolean {
        if (!supportsNameRegex || !NameRegexFilter.isValid(input)) return false
        val text = NameRegexFilter.normalized(input)
        if (text == nameRegex) return true
        nameRegex = text
        applyLive()
        return true
    }

    /**
     * Live chips (Images "Type", the name regex) layered on top of the criteria. Tags: the regex
     * becomes the name-or-alias `AND` group unless the criteria hold a root `AND` of their own.
     */
    private fun liveChips(): JsonObject = NameRegexFilter.layered(extraLive(), mode, nameRegex, criteria.sanitizedObjectFilter)

    /** Loads preset / saved-filter criteria; a chip-shaped name regex goes back into the field. */
    private fun loadCriteria(dict: JsonObject) {
        val (text, rest) = NameRegexFilter.extract(mode, dict)
        nameRegex = text
        criteria.load(rest)
    }

    private fun clearCriteria() {
        nameRegex = ""
        criteria.clear()
    }

    val list = PagedList<T>(coroutineScope, perPage) { page, per ->
        val q = query()
        fetch?.invoke(q, page, per) ?: CatalogRepository.find(q, page, per)
    }

    /** Search term of the last query — the debounced search only refetches when it differs. */
    internal var lastQueriedSearch: String = ""
        private set

    /** A catalog root (not a detail list): Settings defaults and catalog requests apply. */
    val isCatalogRoot: Boolean get() = tabId != null && scope == null

    /** Settings defaults this controller has already reacted to (see [syncDefaults]). */
    private var seenPersistentSort: String? = tabId?.let { CatalogPrefs.persistentSortOption(it) }
    private var seenDefaultFilterId: String? = tabId?.let(defaultFilterIdFor)

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
        // A new gallery cover (`setGalleryCover`) shows in the list without a refresh.
        if (mode == FilterMode.Galleries) coroutineScope.launch {
            LibraryEvents.events.collect { event ->
                if (event is LibraryEvent.GalleryPatched) {
                    @Suppress("UNCHECKED_CAST")
                    (list as PagedList<Gallery>).patch { if (it.id == event.id) event.patch(it) else it }
                }
            }
        }
        // iOS `PerformerImageUpdated` → `patchPerformerImageInLists`.
        if (mode == FilterMode.Performers) coroutineScope.launch {
            PerformerEvents.events.collect { event ->
                @Suppress("UNCHECKED_CAST")
                (list as PagedList<Performer>).patch { event.applyTo(it) }
            }
        }
    }

    /** Passed as `filter:` only while the editor holds no copy of it (iOS `fetchBaseFilter`). */
    private val fetchBaseFilter: SavedFilter? get() = if (criteria.isEmpty && nameRegex.isEmpty()) selectedFilter else null

    fun query(): CatalogQuery {
        lastQueriedSearch = search
        var live = criteria.merged(liveChips())
        // "Hide sub-studios": the Studios list (not a studio's sub-studios tab) shows top-level
        // studios only. An app setting, never part of the criteria document or a saved filter.
        if (mode == FilterMode.Studios && scope == null) {
            val own = JsonObject((fetchBaseFilter?.filterDict ?: JsonObject(emptyMap())) + (live ?: JsonObject(emptyMap())))
            SubStudios.hideCriterion(StudioCountsStore.hideSubStudios, search, own)?.let { live = JsonObject((live ?: JsonObject(emptyMap())) + it) }
        }
        return CatalogQuery(mode, sort, search, fetchBaseFilter, live, dynamicScope?.invoke() ?: scope)
    }

    val serverFilters: List<SavedFilter> get() = SavedFiltersStore.forMode(mode)

    /** iOS: `catalogFilterSortFABActive`. */
    val isFilterActive: Boolean get() = selectedFilter != null || !criteria.isEmpty || nameRegex.isNotEmpty() || presetRow.isNotEmpty()

    val selectedPresetName: String? get() {
        ListLivePresetTag.parseServerId(presetRow)?.let { sid -> return SavedFiltersStore.byId[sid]?.name }
        ListLivePresetTag.parseLocalId(presetRow)?.let { lid -> return localPresets.firstOrNull { it.id == lid }?.name }
        return null
    }

    /** iOS `activePresetName` — the removable preset chip above the list. */
    val activePresetName: String? get() = selectedPresetName ?: selectedFilter?.name

    /** iOS `CatalogListQuickBar` sort chip: [CatalogQuickSortCatalog.next], Random re-rolls via [changeSort]. */
    fun quickSort(field: String) {
        if (extraSorts.any { it.field == field }) {
            // Own fields: the active one flips, otherwise ascending first (1, 2, 3 …).
            val ascending = if (sort.field == field) !sort.isAscending else true
            SortCatalog.optionFor(mode, field, ascending, extraSorts)?.let { changeSort(it) }
            return
        }
        CatalogQuickSortCatalog.next(mode, sort, field)?.let { changeSort(it) }
    }

    /**
     * Bumped on every fresh first-page fetch (sort, filter, search, request, pull to refresh).
     * The list screens key their grid with it, so it returns to the top: the old rows stay until
     * the new first page arrives, and an offset deep in the old list would lie past the end of
     * the new one (iOS ad48c351 `listResetToken`).
     */
    var listResetToken by mutableStateOf(0)
        private set

    /** First page again without rebuilding For You (iOS `performSearch`) — catalog requests. */
    fun refetch() {
        listResetToken++
        list.refresh()
    }

    /** Pull to refresh. Sorted For You, a new For You list is built first — otherwise the list would only re-read the one shown. */
    fun refresh() {
        listResetToken++
        if (mode == FilterMode.Scenes && sort.isForYou) {
            coroutineScope.launch {
                de.letzgo.stashy.data.tools.SceneRecommendations.rebuildAndWait()
                list.refresh()
            }
        } else {
            list.refresh()
        }
    }

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
        val defaultId = tabId?.let(defaultFilterIdFor)
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
        val id = tabId?.let(defaultFilterIdFor) ?: return false
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
        val defId = defaultFilterIdFor(id)
        if (defId != seenDefaultFilterId) {
            seenDefaultFilterId = defId
            val filter = defId?.let { SavedFiltersStore.byId[it] }
            if (filter != null) {
                didApplyDefaultFilter = true
                clearCriteria()
                applyServerFilter(filter)
                presetRow = ListLivePresetTag.serverRow(filter.id)
            } else {
                // No default any more (or not loaded yet — then `onSavedFiltersLoaded` applies it).
                didApplyDefaultFilter = false
                selectedFilter = null
                presetRow = ""
                clearCriteria()
                applyLive()
            }
        }
    }

    /**
     * iOS `NavigationCoordinator.activeSortOption` / `activeSearchText` / `noDefaultFilter` —
     * what a dashboard header, a stats tile or Search "Show All" asked this catalog for.
     * Returns whether the list must be refetched. iOS (54fe29a8): an injected sort always
     * refetches, even when it equals the current one — the catalog list stays warm across
     * visits, so its rows may predate the Home row that linked here.
     */
    fun applyRequest(request: Nav.CatalogRequest): Boolean {
        var changed = false
        request.sort?.let { SortCatalog.option(mode, it) }?.let { s ->
            if (s != sort || s.isRandom) {
                if (s.isRandom && sort.isRandom) RandomSeeds.refresh(mode)
                sort = s
                persistSort(s)
            }
            changed = true
        }
        if (request.noDefaultFilter) {
            didApplyDefaultFilter = true
            val defId = tabId?.let { CatalogPrefs.defaultFilterId(it) }
            if (defId != null && selectedFilter?.id == defId) {
                selectedFilter = null
                presetRow = ""
                clearCriteria()
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
        if (presetRow.isNotEmpty() && criteria.isEmpty && nameRegex.isEmpty()) applyPresetRow(presetRow)
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
        // `object_filter` holds every criterion in the web UI's format (base filter and chips
        // merged when it was saved); the old `ui_options.stashy` copy would override edits made
        // in Stash itself.
        loadCriteria(f.criteriaObjectFilter())
        if (meta != null) {
            val parsed = SortCatalog.option(mode, meta.sortRaw)
            if (parsed != null && parsed != sort) {
                if (parsed.isRandom && sort.isRandom) RandomSeeds.refresh(mode)
                sort = parsed
                persistSort(parsed)
            }
        }
        applyLive()
    }

    private fun applyLocalPreset(p: LocalFilterPreset) {
        val parsed = SortCatalog.option(mode, p.sortRaw) ?: CatalogPrefs.resolvedSort(mode)
        if (parsed != sort) { sort = parsed; persistSort(parsed) }
        val base = p.baseSavedFilterId?.let { SavedFiltersStore.byId[it] }
        selectedFilter = base
        val m = LinkedHashMap<String, JsonElement>(base?.criteriaObjectFilter() ?: JsonObject(emptyMap()))
        FilterMapper.sanitize(p.liveFragment, mode == FilterMode.SceneMarkers, mode.filterEntity).forEach { (k, v) -> m[k] = v }
        loadCriteria(JsonObject(m))
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
        clearCriteria()
        applyLive()
    }

    private val liveFragment: JsonObject get() = criteria.merged(liveChips()) ?: JsonObject(emptyMap())

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
        val merged = mergedObjectFilterForSave(base, liveFragment, previousLive, isMarker = mode == FilterMode.SceneMarkers, mode = mode)
        // A list-only sort (performer "Appears with": Shared scenes) means nothing to Stash.
        val saveSort = SortCatalog.option(mode, sort.raw) ?: SortCatalog.option(mode, SortCatalog.defaultRaw(mode)) ?: sort
        val input = SavedFiltersRepository.saveInput(
            mode, existingId, name, saveSort, merged, liveFragment, base?.id, FilterPickerOptionsStore.knownLabels(),
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
                showToast(tr(R.string.action_save_failed_arg, e.message))
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
                    showToast(tr(R.string.action_rename_failed_arg, e.message))
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
                    clearCriteria()
                    refresh()
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    showToast(tr(R.string.action_delete_failed_arg, e.message))
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
            SavedFiltersStore.byId[sid]?.let { return tr(R.string.hint_remove_arg_from_stash_other, it.name) }
        }
        ListLivePresetTag.parseLocalId(presetRow)?.let { lid ->
            localPresets.firstOrNull { it.id == lid }?.let { return tr(R.string.hint_remove_arg_from_this_device, it.name) }
        }
        return tr(R.string.hint_remove_this_filter_this_cannot)
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
        // `refetch()`, not `refresh()`: sorted For You, the link shows the list
        // the Home row just showed (iOS `performSearch`) instead of building the next one.
        if (changed && wasLoaded) controller.refetch()
        // Requests arriving while this catalog is on screen.
        if (controller.isCatalogRoot && catalogTab != null) {
            snapshotFlow { Nav.catalogRequest }.collect { req ->
                if (req?.tab == catalogTab) Nav.consumeCatalogRequest(catalogTab)?.let { if (controller.applyRequest(it)) controller.refetch() }
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
