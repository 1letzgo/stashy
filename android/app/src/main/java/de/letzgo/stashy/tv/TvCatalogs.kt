package de.letzgo.stashy.tv

import de.letzgo.stashy.ui.uniqueItemsIndexed
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.applySceneEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * State of one TV catalog grid (iOS: the `@State`s of `TVScenesView`, `TVPerformersView` … with
 * their own `StashDBViewModel`): sort, saved filter, the paged list, default filter applied
 * once per lifetime, and a focus reset only after a deliberate sort/filter change.
 */
class TvCatalogModel<T>(val mode: FilterMode, initialSort: String? = null, private val keyOf: (T) -> String) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val tab: AppTab = AppTab.forMode(mode)!!
    var sort by mutableStateOf(resolve(initialSort ?: TabManager.getSortOption(tab)))
    var filter by mutableStateOf<SavedFilter?>(null); private set
    /** Bumped on a deliberate sort or filter change; the grid then moves focus to the first card. */
    var focusResetToken by mutableIntStateOf(0); private set
    val focus = TvFocusMemory()
    private var didApplyDefaultFilter = false
    private var started = false

    val list = PagedList<T>(scope, CatalogRepository.pageSize(mode)) { page, perPage ->
        CatalogRepository.find(CatalogQuery(mode, sort, base = filter), page, perPage)
    }

    init {
        if (mode == FilterMode.Scenes) {
            @Suppress("UNCHECKED_CAST") val scenes = list as PagedList<Scene>
            scope.launch { SceneEvents.events.collect { scenes.applySceneEvent(it) } }
        }
    }

    fun key(item: T) = keyOf(item)

    private fun resolve(raw: String?): SortOption =
        SortCatalog.option(mode, raw) ?: SortCatalog.option(mode, TvSortLabels.defaultRaw(mode))!!

    /** First appearance: saved filters (for the default filter) then the first page. */
    fun start() {
        if (started) return
        started = true
        if (ServerConfigManager.activeConfig?.hasValidConfig != true) return
        scope.launch {
            val defaultId = TabManager.getDefaultFilterId(tab)
            if (defaultId != null) {
                SavedFiltersStore.load()
                // Another screen may be loading them already: wait for that load.
                while (SavedFiltersStore.isLoading) delay(50)
            } else launch { SavedFiltersStore.load() }
            applyDefaultFilterIfNeeded()
            if (list.items.isEmpty()) list.refresh()
        }
    }

    private fun applyDefaultFilterIfNeeded() {
        if (didApplyDefaultFilter) return
        didApplyDefaultFilter = true
        if (filter != null) return
        val id = TabManager.getDefaultFilterId(tab) ?: return
        filter = SavedFiltersStore.byId[id]
    }

    fun changeSort(raw: String) {
        val next = resolve(raw)
        if (next.isRandom) de.letzgo.stashy.data.RandomSeeds.refresh(mode)
        sort = next
        focusResetToken++
        list.refresh()
    }

    fun changeFilter(next: SavedFilter?) {
        filter = next
        focusResetToken++
        list.refresh()
    }

    fun reload() {
        if (ServerConfigManager.activeConfig?.hasValidConfig != true) return
        list.refresh()
    }

    fun dispose() = scope.cancel()

    val savedFilters: List<SavedFilter> get() { SavedFiltersStore.version; return SavedFiltersStore.forMode(mode) }
}

/** iOS: `STVHeaderView` with `TVOptionPickerButton` (Sort By) and `TVFilterPickerButton`. */
@Composable
fun TvCatalogHeader(model: TvCatalogModel<*>, modifier: Modifier = Modifier, sortFocus: FocusRequester? = null) {
    var sortOpen by remember { mutableStateOf(false) }
    var filterOpen by remember { mutableStateOf(false) }
    Row(modifier.padding(vertical = pt(30)), horizontalArrangement = Arrangement.spacedBy(pt(24)), verticalAlignment = Alignment.CenterVertically) {
        val sortLabel = TvSortLabels.options(model.mode).firstOrNull { it.first == model.sort.raw }?.second ?: model.sort.label
        TvChromeButton(TvIcons.sort, sortLabel, { sortOpen = true }, if (sortFocus != null) Modifier.focusRequester(sortFocus) else Modifier)
        TvChromeButton(if (model.filter != null) TvIcons.filterFill else TvIcons.filter, model.filter?.name ?: "No Filter", { filterOpen = true })
    }
    if (sortOpen) {
        TvOptionDialog(
            "Sort By", TvSortLabels.options(model.mode).map { TvOption(it.first, it.second) }, model.sort.raw,
            { model.changeSort(it) }, { sortOpen = false },
        )
    }
    if (filterOpen) {
        val none = "\u0000none"
        TvOptionDialog(
            "Filter", listOf(TvOption(none, "No Filter")) + model.savedFilters.map { TvOption(it.id, it.name) }, model.filter?.id ?: none,
            { id -> model.changeFilter(if (id == none) null else SavedFiltersStore.byId[id]) }, { filterOpen = false },
        )
    }
}

/**
 * iOS: `TVCatalogGrid` — config / error / loading / empty / content states, width-adaptive
 * columns ([TvGridSpec]), paging two rows before the end, focus reset to the first card only
 * after a deliberate sort or filter change.
 */
@Composable
fun <T> TvCatalogGrid(
    model: TvCatalogModel<T>,
    columnWidth: Dp,
    maxColumns: Int,
    spacing: Dp = pt(40),
    minColumns: Int = 2,
    emptyIcon: ImageVector,
    emptyTitle: String,
    loadingText: String,
    errorTitle: String,
    items: List<T> = model.list.items,
    autoFocusFirst: Boolean = false,
    card: @Composable (item: T, modifier: Modifier) -> Unit,
) {
    LaunchedEffect(Unit) { model.start() }
    val list = model.list
    val hasConfig = ServerConfigManager.activeConfig?.hasValidConfig == true
    val headerFocus = remember { FocusRequester() }
    val firstFocus = remember { FocusRequester() }
    Box(Modifier.fillMaxSize().background(TvColors.background)) {
        when {
            !hasConfig -> TvConnectionError(subtitle = "Add a server in Settings.") { model.reload() }
            items.isEmpty() && list.error != null && !list.isLoading -> Column(Modifier.padding(horizontal = pt(60))) {
                TvCatalogHeader(model, sortFocus = headerFocus)
                TvConnectionError(errorTitle, list.error) { model.reload() }
                if (autoFocusFirst) TvInitialFocus(model.focus, headerFocus, name = "catalog.sort")
            }
            items.isEmpty() && (list.isLoading || !list.loadedOnce) -> TvLoading(loadingText, Modifier.align(Alignment.Center))
            items.isEmpty() -> Column(Modifier.padding(horizontal = pt(60))) {
                TvCatalogHeader(model, sortFocus = headerFocus)
                TvEmpty(emptyIcon, emptyTitle) { model.reload() }
                if (autoFocusFirst) TvInitialFocus(model.focus, headerFocus, name = "catalog.sort")
            }
            else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                val horizontal = pt(60)
                val spec = TvGridSpec(columnWidth.value, spacing.value, maxColumns, minOf(minColumns, maxColumns))
                val columns = spec.columnCount((maxWidth - horizontal * 2).value)
                val state: LazyGridState = rememberLazyGridState()
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    state = state,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = horizontal, end = horizontal, bottom = pt(140)),
                    horizontalArrangement = Arrangement.spacedBy(spacing, Alignment.Start),
                    verticalArrangement = Arrangement.spacedBy(spacing),
                ) {
                    item(span = { GridItemSpan(maxLineSpan) }, key = "header") { TvCatalogHeader(model, sortFocus = headerFocus) }
                    uniqueItemsIndexed(items, { model.key(it) }) { index, item ->
                        LaunchedEffect(index, items.size) {
                            if (index >= items.size - columns * 2) list.loadMore()
                        }
                        val key = model.key(item)
                        card(item, Modifier.tvFocusMemory(model.focus, key).then(if (index == 0) Modifier.focusRequester(firstFocus) else Modifier))
                    }
                    if (list.isLoading && items.isNotEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }, key = "more") { TvLoading() }
                    }
                }
                LaunchedEffect(model.focusResetToken) {
                    if (model.focusResetToken == 0) return@LaunchedEffect
                    // Wait for the refetch, then put focus on the first card (never on a refetch the user did not ask for).
                    while (list.isLoading) delay(50)
                    state.scrollToItem(0)
                    delay(60)
                    runCatching { firstFocus.requestFocus() }
                }
                if (autoFocusFirst) TvInitialFocus(model.focus, firstFocus, name = "catalog.firstCard")
            }
        }
    }
}

// MARK: - Catalog roots

/** iOS: `TVScenesView` (also pushed by "See All" with a fixed sort). */
@Composable
fun TvScenesGrid(model: TvCatalogModel<Scene>, autoFocusFirst: Boolean = false) {
    TvCatalogGrid(
        model, pt(410), 4, emptyIcon = TvIcons.filmOutline, emptyTitle = "No scenes found",
        loadingText = "Loading scenes…", errorTitle = "Error loading scenes", autoFocusFirst = autoFocusFirst,
    ) { scene, modifier -> TvSceneTile(scene, { TvNav.push(TvSceneDetailRoute(scene.id, scene)) }, modifier) }
}

@Composable
fun TvPerformersGrid(model: TvCatalogModel<Performer>) {
    TvCatalogGrid(model, pt(260), 6, emptyIcon = TvIcons.person3, emptyTitle = "No Performers Found", loadingText = "Loading performers…", errorTitle = "Error loading performers") { p, modifier ->
        TvPerformerCard(p, { TvNav.push(TvPerformerDetailRoute(p.id, p.name)) }, modifier)
    }
}

@Composable
fun TvStudiosGrid(model: TvCatalogModel<Studio>) {
    TvCatalogGrid(model, pt(410), 4, emptyIcon = TvIcons.building, emptyTitle = "No Studios Found", loadingText = "Loading studios…", errorTitle = "Error loading studios") { s, modifier ->
        TvStudioCard(s, { TvNav.push(TvStudioDetailRoute(s.id, s.name)) }, modifier)
    }
}

@Composable
fun TvTagsGrid(model: TvCatalogModel<Tag>) {
    TvCatalogGrid(model, pt(400), 4, emptyIcon = TvIcons.tag, emptyTitle = "No Tags Found", loadingText = "Loading tags…", errorTitle = "Error loading tags") { t, modifier ->
        TvTagCard(t, { TvNav.push(TvTagDetailRoute(t.id, t.name)) }, modifier)
    }
}

@Composable
fun TvGroupsGrid(model: TvCatalogModel<StashGroup>) {
    TvCatalogGrid(model, pt(260), 6, emptyIcon = TvIcons.stack, emptyTitle = "No Groups Found", loadingText = "Loading groups…", errorTitle = "Error loading groups") { g, modifier ->
        TvGroupCard(g, { TvNav.push(TvGroupDetailRoute(g.id, g.name)) }, modifier)
    }
}

@Composable
fun TvGalleriesGrid(model: TvCatalogModel<Gallery>) {
    TvCatalogGrid(model, pt(410), 4, emptyIcon = TvIcons.photoStack, emptyTitle = "No Galleries Found", loadingText = "Loading galleries…", errorTitle = "Error loading galleries") { g, modifier ->
        TvGalleryCard(g, { TvNav.push(TvGalleryDetailRoute(g.id, g.displayTitle, g)) }, modifier)
    }
}

/** iOS: `TVImagesView` — still images only, the viewer pages through the grid's own list. */
@Composable
fun TvImagesGrid(model: TvCatalogModel<StashImage>) {
    val stills = model.list.items.tvStillImages()
    TvCatalogGrid(
        model, pt(300), 5, spacing = pt(30), emptyIcon = TvIcons.photo, emptyTitle = "No Images Found",
        loadingText = "Loading images…", errorTitle = "Error loading images", items = stills,
    ) { image, modifier ->
        TvImageTile(image, {
            TvNav.push(TvImageViewerRoute(image.id, image.tvDisplayTitle ?: "Untitled", { model.list.items.tvStillImages() }, { model.list.loadMore() }, { model.list.hasMore }))
        }, modifier)
    }
}

/** "See All" from a dashboard row (iOS `TVSceneListLink` → `TVScenesView(sortBy:)`). */
class TvScenesRoute(sortRaw: String) : TvRoute {
    private val model = TvCatalogModel<Scene>(FilterMode.Scenes, sortRaw) { it.id }
    override val key = "scenes.$sortRaw.${System.nanoTime()}"
    override val focus: TvFocusMemory get() = model.focus

    @Composable
    override fun Content() = TvScenesGrid(model, autoFocusFirst = true)

    override fun onRemoved() = model.dispose()
}
