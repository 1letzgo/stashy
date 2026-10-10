package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.uniqueItemsIndexed
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.catalog.CatalogChromeSlot
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.ImageFeedGridModel
import de.letzgo.stashy.ui.catalog.ImageMediaKindHolder
import de.letzgo.stashy.ui.filter.CardColumnsCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.filter.ImageListMediaKind
import de.letzgo.stashy.ui.filter.ImageMediaTypeCard
import de.letzgo.stashy.ui.filter.ImagesFeedAutoplaySettingsCard
import de.letzgo.stashy.ui.catalog.imageFeedItems
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.json.JsonObject

/** Scope that outlives recomposition: the Screen object keeps its lists while it is on the stack. */
internal fun screenScope() = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/**
 * The linked lists of one detail screen (iOS: `DetailLinked*FilterModel`s + the
 * `StashDBViewModel` detail arrays). A null scope means the section does not exist there.
 *
 * Every section is a [CatalogController] of its [FilterMode] — the same filter & sort sheet as
 * the Home catalog of that type (saved filters, sort, presets, criteria editor) — with the
 * entity scope layered last (`CatalogQuery.scope`), so nothing in the sheet can widen the list
 * beyond this entity. Sorts are session only; the Settings default filter never applies here
 * (`scope != null`).
 */
internal class LinkedCatalog(
    private val scope: CoroutineScope,
    val order: List<DetailTab>,
    sceneScope: JsonObject? = null,
    galleryScope: JsonObject? = null,
    studioScope: JsonObject? = null,
    performerScope: JsonObject? = null,
    tagScope: JsonObject? = null,
    groupScope: JsonObject? = null,
    imageScope: JsonObject? = null,
    val sceneContext: DetailViewContext? = null,
    /** Scene / gallery counts known from the list item, so the first tab is right before loading. */
    var previewScenes: Int = 0,
    var previewGalleries: Int = 0,
    var previewImages: Int = 0,
    /** 1/row draws the grouped feed (false: always the thumbnail grid, iOS Studio detail). */
    val usesImageFeed: Boolean = true,
    /** Count of sections the owning screen draws itself ([DetailTab.AppearsWith]); 0 hides them. */
    private val screenCount: (DetailTab) -> Int = { 0 },
) {
    /** Per row of the Images section (iOS `CatalogCardColumnScope.images`, set in the images sheet). */
    val imageColumns: Int get() = CatalogPrefs.cardColumns(CatalogCardColumnScope.Images).raw

    private fun <T> controller(
        mode: FilterMode,
        entityScope: JsonObject?,
        sortRaw: String,
        perPage: Int,
        persistSort: (SortOption) -> Unit = {},
        extraLive: () -> JsonObject = { JsonObject(emptyMap()) },
    ): CatalogController<T>? = entityScope?.let { s ->
        CatalogController(
            mode, scope,
            tabId = null,
            scope = s,
            initialSort = SortCatalog.option(mode, sortRaw) ?: SortCatalog.option(mode, SortCatalog.defaultRaw(mode)),
            extraLive = extraLive,
            persistSort = persistSort,
            perPage = perPage,
            fetch = { q, page, per -> DetailRepository.findScoped(q, page, per) },
        )
    }

    /** Scenes (iOS detail scene sort: `DetailViewsSortConfig_<context>`, session override on change). */
    val sceneController = controller<Scene>(
        FilterMode.Scenes, sceneScope,
        sortRaw = sceneContext?.let { DetailViewConfig.sceneSort(it).raw } ?: DetailSort.Scene.DateDesc.raw,
        perPage = 20,
        persistSort = { s -> sceneContext?.let { DetailViewConfig.setSortOption(it, s.raw) } },
    )
    val galleryController = controller<Gallery>(FilterMode.Galleries, galleryScope, "dateDesc", 20)
    val studioController = controller<Studio>(FilterMode.Studios, studioScope, "nameAsc", 20)
    val performerController = controller<Performer>(FilterMode.Performers, performerScope, "nameAsc", 20)
    val tagController = controller<Tag>(FilterMode.Tags, tagScope, "sceneCountDesc", 40)
    val groupController = controller<StashGroup>(FilterMode.Groups, groupScope, "nameAsc", 20)

    /** iOS `liveFilterMediaKind` of the Images section ("Type": Any / Image / Video). */
    val imageKind = ImageMediaKindHolder()
    /**
     * Images section (iOS `DetailLinkedImagesFilterModel`): filter, sort (`dateDesc`, session
     * only), Type and criteria from the images sheet.
     */
    val imageController = controller<StashImage>(
        FilterMode.Images, imageScope, DetailSort.Image.DateDesc.raw, CatalogRepository.pageSize(FilterMode.Images),
        extraLive = { imageKind.kind.pathCriterion?.let { JsonObject(mapOf("path" to it)) } ?: JsonObject(emptyMap()) },
    )

    val scenes: PagedList<Scene>? get() = sceneController?.list
    val galleries: PagedList<Gallery>? get() = galleryController?.list
    val studios: PagedList<Studio>? get() = studioController?.list
    val performers: PagedList<Performer>? get() = performerController?.list
    val tags: PagedList<Tag>? get() = tagController?.list
    val groups: PagedList<StashGroup>? get() = groupController?.list
    val images: PagedList<StashImage>? get() = imageController?.list
    /** Grouped 1/row feed of the Images section (iOS `LinkedImagesCatalogGrid` / `ImagesView(gallery:)`). */
    val imageFeed = ImageFeedGridModel()

    /** Every section except Images (whose sheet adds its own cards). */
    val plainControllers: List<CatalogController<*>> get() =
        listOfNotNull(sceneController, galleryController, studioController, performerController, tagController, groupController)

    private val controllers: List<CatalogController<*>> get() = plainControllers + listOfNotNull(imageController)

    private var started = false

    fun loadAll(force: Boolean = false) {
        if (started && !force) return
        started = true
        // First appearance also loads the saved filters the sheets offer.
        controllers.forEach { c -> if (c.list.loadedOnce) c.refresh() else c.onAppear() }
    }

    fun controller(tab: DetailTab): CatalogController<*>? = when (tab) {
        DetailTab.Scenes -> sceneController
        DetailTab.Galleries -> galleryController
        DetailTab.Studios -> studioController
        DetailTab.Performers -> performerController
        DetailTab.Tags -> tagController
        DetailTab.Groups -> groupController
        DetailTab.Images -> imageController
        DetailTab.AppearsWith -> null
    }

    fun list(tab: DetailTab): PagedList<*>? = controller(tab)?.list

    /** The sheet narrows [tab] (filter, preset, criteria — and Type for Images). */
    fun isFiltered(tab: DetailTab): Boolean {
        val c = controller(tab) ?: return false
        return c.isFilterActive || (tab == DetailTab.Images && imageKind.kind != ImageListMediaKind.All)
    }

    /** iOS `effectiveScenes` — once the first fetch is done the server count wins. */
    val effectiveScenes: Int get() = scenes?.let { if (it.loadedOnce) it.totalCount else maxOf(it.totalCount, previewScenes) } ?: 0
    val effectiveGalleries: Int get() = maxOf(galleries?.totalCount ?: 0, previewGalleries)
    val effectiveImages: Int get() = maxOf(images?.totalCount ?: 0, previewImages)

    fun count(tab: DetailTab): Int = visibleCount(
        when (tab) {
            DetailTab.Scenes -> effectiveScenes
            DetailTab.Galleries -> effectiveGalleries
            DetailTab.Images -> effectiveImages
            DetailTab.AppearsWith -> screenCount(tab)
            else -> list(tab)?.totalCount ?: 0
        },
        isFiltered(tab),
    )

    /** iOS `availableTabs`. */
    val available: List<DetailTab> get() = order.filter { count(it) > 0 }

    val isSettled: Boolean get() = controllers.all { it.list.loadedOnce && !it.list.isLoading }

    /** Top-bar "Settings" of [tab] (iOS filter & sort FAB of the `DetailLinked*` lists). */
    fun settingsSlot(tab: DetailTab): CatalogChromeSlot? {
        val c = controller(tab) ?: return null
        return CatalogChromeSlot(SF.sliderHorizontal3, isFiltered(tab), "Settings") { c.isSheetPresented = true }
    }

    companion object {
        /**
         * A sheet filter that matches nothing keeps its tab (empty state) instead of hiding it,
         * so the auto-switch never jumps away from a list the user is filtering.
         */
        fun visibleCount(total: Int, filtered: Boolean): Int = if (filtered) maxOf(total, 1) else total
    }
}

/**
 * The filter & sort sheets of a detail screen's sections — the Home catalog sheet of each type;
 * the Images one adds Type, Per row (`CatalogCardColumnScope.images`) and feed autoplay
 * (iOS `ImagesCatalogFilterSortSheet`).
 */
@Composable
internal fun LinkedSettingsSheets(catalog: LinkedCatalog) {
    catalog.plainControllers.forEach { CatalogFilterSortSheet(it) }
    val c = catalog.imageController ?: return
    CatalogFilterSortSheet(c, onReset = { catalog.imageKind.kind = ImageListMediaKind.All }) {
        ImageMediaTypeCard(catalog.imageKind.kind) { catalog.imageKind.kind = it; c.applyLive() }
        CardColumnsCard(CatalogCardColumnScope.Images)
        ImagesFeedAutoplaySettingsCard()
    }
}

/**
 * Selected section with iOS auto-switching: when the current section turns out empty after
 * loading, jump to the first one with content.
 */
@Composable
internal fun AutoSwitchTab(catalog: LinkedCatalog, selected: DetailTab, onSelect: (DetailTab) -> Unit) {
    val available = catalog.available
    val selectedList = catalog.list(selected)
    val settledSelected = selectedList == null || (selectedList.loadedOnce && !selectedList.isLoading)
    LaunchedEffect(available, settledSelected) {
        if (selected !in available && settledSelected && available.isNotEmpty()) onSelect(available.first())
    }
}

/**
 * Scrolling content of a detail screen: header spanning the full width, then the selected
 * section as grid (iOS `ScrollView { VStack(spacing: 12) { header; grid } .padding(16) }`).
 */
@Composable
internal fun DetailGrid(
    state: LazyGridState,
    columnsFor: (widthDp: Float) -> Int,
    hasTabs: Boolean = false,
    header: @Composable () -> Unit,
    content: LazyGridScope.() -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = columnsFor(maxWidth.value - 32f)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = detailTopPadding(hasTabs), bottom = bottomBarContentPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            item(key = "header", span = { GridItemSpan(maxLineSpan) }) { header() }
            content()
        }
    }
}

/** Column count per section on the current width (iOS `galleryColumns` / scene list). */
internal fun columnsFor(tab: DetailTab, widthDp: Float, imageColumns: Int): Int = when (tab) {
    DetailTab.Scenes -> adaptiveColumnCount(widthDp, 560f, 1, 4)
    // 1/row is the grouped feed: one flexible column like iOS, whatever the width.
    DetailTab.Images -> if (imageColumns == 1) 1 else adaptiveColumnCount(widthDp, 220f, 2, 8)
    else -> adaptiveColumnCount(widthDp, 220f, 2, 8)
}

/** Paged section with loading footer, empty state and infinite scroll. */
internal fun <T> LazyGridScope.pagedSection(
    list: PagedList<T>,
    key: (T) -> String,
    loadingMessage: String? = null,
    emptyIcon: ImageVector? = null,
    emptyTitle: String? = null,
    item: @Composable (index: Int, T) -> Unit,
) {
    if (list.items.isEmpty()) {
        item(key = "state", span = { GridItemSpan(maxLineSpan) }) {
            when {
                list.isLoading || !list.loadedOnce -> LoadingFooter(loadingMessage)
                emptyIcon != null && emptyTitle != null -> InlineEmptyState(emptyIcon, emptyTitle)
                else -> Box(Modifier)
            }
        }
        return
    }
    uniqueItemsIndexed(list.items, key) { index, value ->
        LaunchedEffect(index, list.items.size) { list.onItemShown(index) }
        item(index, value)
    }
    if (list.isLoading) item(key = "more", span = { GridItemSpan(maxLineSpan) }) { LoadingFooter(loadingMessage?.let { "Loading more ${it.removePrefix("Loading ")}" }) }
}

/** The section grid for [tab] — shared by Performer/Studio/Tag/Group details. */
internal fun LazyGridScope.linkedSection(catalog: LinkedCatalog, tab: DetailTab, gridState: LazyGridState) {
    when (tab) {
        DetailTab.Scenes -> catalog.scenes?.let { l ->
            pagedSection(l, { it.id }, null, SF.film, "No scenes found") { _, s ->
                SceneCard(s, onClick = { Nav.push(SceneDetailScreen(s.id, s)) })
            }
        }
        DetailTab.Galleries -> catalog.galleries?.let { l ->
            pagedSection(l, { it.id }, "Loading galleries...", SF.photoOnRectangle, "No galleries found") { _, g ->
                DetailGalleryCard(g, onClick = { Nav.push(GalleryDetailScreen(g.id, g)) })
            }
        }
        DetailTab.Studios -> catalog.studios?.let { l ->
            pagedSection(l, { it.id }) { _, s -> DetailStudioCard(s, onClick = { Nav.push(StudioDetailScreen(s.id, s)) }) }
        }
        DetailTab.Performers -> catalog.performers?.let { l ->
            pagedSection(l, { it.id }, "Loading performers...") { _, p -> DetailPerformerCard(p, onClick = { Nav.push(PerformerDetailScreen(p.id, p)) }) }
        }
        DetailTab.Tags -> catalog.tags?.let { l ->
            pagedSection(l, { it.id }) { _, t -> DetailTagCard(t, onClick = { Nav.push(TagDetailScreen(t.id, t)) }) }
        }
        DetailTab.Groups -> catalog.groups?.let { l ->
            pagedSection(l, { it.id }) { _, g -> DetailGroupCard(g, onClick = { Nav.push(GroupDetailScreen(g.id, g)) }) }
        }
        DetailTab.Images -> imageSection(catalog, gridState)
        // Drawn by PerformerDetailScreen (not a catalog list).
        DetailTab.AppearsWith -> Unit
    }
}

/**
 * iOS `LinkedImagesCatalogGrid` / `ImagesView(gallery:)`: 1/row is the grouped image feed
 * (sets as swipeable posts, rating + O-counter, muted autoplay; the viewer swipes in post
 * order), otherwise the multi-column thumbnail grid. Tap opens [ImageViewerScreen].
 */
internal fun LazyGridScope.imageSection(catalog: LinkedCatalog, gridState: LazyGridState, currentGalleryId: String? = null) {
    val list = catalog.images ?: return
    imageSection(
        list, useFeed = catalog.imageColumns == 1 && catalog.usesImageFeed, feedModel = catalog.imageFeed,
        sortRaw = catalog.imageController?.sort?.raw ?: "", gridState = gridState, currentGalleryId = currentGalleryId,
    )
}

/** [imageSection] over any image list (the opened gallery drives it from a catalog controller). */
internal fun LazyGridScope.imageSection(
    list: PagedList<StashImage>,
    useFeed: Boolean,
    feedModel: ImageFeedGridModel,
    sortRaw: String,
    gridState: LazyGridState,
    currentGalleryId: String? = null,
) {
    if (!useFeed) {
        pagedSection(list, { it.id }, "Loading images...", SF.cameraFill, "No images found") { index, image ->
            DetailImageCard(image, onClick = { Nav.push(ImageViewerScreen(list.items, index, onLoadMore = { list.loadMore() })) })
        }
        return
    }
    if (list.items.isEmpty()) {
        // Empty / first-load state exactly like the grid.
        pagedSection(list, { it.id }, "Loading images...", SF.cameraFill, "No images found") { _, _ -> }
        return
    }
    imageFeedItems(
        model = feedModel,
        images = list.items,
        sortRaw = sortRaw,
        gridState = gridState,
        onLoadMore = { list.loadMore() },
        onImageUpdated = { updated -> list.patch { if (it.id == updated.id) updated else it } },
        currentGalleryId = currentGalleryId,
    )
    if (list.isLoading) item(key = "more", span = { GridItemSpan(maxLineSpan) }) { LoadingFooter("Loading more images...") }
}
