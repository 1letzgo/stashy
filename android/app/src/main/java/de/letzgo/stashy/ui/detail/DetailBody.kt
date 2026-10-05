package de.letzgo.stashy.ui.detail

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import de.letzgo.stashy.data.FindFilter
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.TabBarClearance
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
 */
internal class LinkedCatalog(
    private val scope: CoroutineScope,
    val order: List<DetailTab>,
    private val sceneScope: JsonObject? = null,
    private val galleryScope: JsonObject? = null,
    private val studioScope: JsonObject? = null,
    private val performerScope: JsonObject? = null,
    private val tagScope: JsonObject? = null,
    private val groupScope: JsonObject? = null,
    private val imageScope: JsonObject? = null,
    val sceneContext: DetailViewContext? = null,
    /** Scene / gallery counts known from the list item, so the first tab is right before loading. */
    var previewScenes: Int = 0,
    var previewGalleries: Int = 0,
    var previewImages: Int = 0,
    /** 1/row draws the grouped feed (false: always the thumbnail grid, iOS Studio detail). */
    val usesImageFeed: Boolean = true,
) {
    var sceneSort by mutableStateOf(sceneContext?.let { DetailViewConfig.sceneSort(it) } ?: DetailSort.Scene.DateDesc)
    var gallerySort by mutableStateOf(DetailSort.Gallery.DateDesc)
    var studioSort by mutableStateOf(DetailSort.Studio.NameAsc)
    var performerSort by mutableStateOf(DetailSort.Performer.NameAsc)
    var tagSort by mutableStateOf(DetailSort.Tag.SceneCountDesc)
    /** Per row of the Images section (iOS `CatalogCardColumnScope.images`, set in the images sheet). */
    val imageColumns: Int get() = CatalogPrefs.cardColumns(CatalogCardColumnScope.Images).raw

    val scenes = sceneScope?.let { s -> PagedList<Scene>(scope, 20) { page, per -> DetailRepository.scenes(DetailSort.findFilter(page, per, sceneSort), s) } }
    val galleries = galleryScope?.let { s -> PagedList<Gallery>(scope, 20) { page, per -> DetailRepository.galleries(DetailSort.findFilter(page, per, gallerySort), s) } }
    val studios = studioScope?.let { s -> PagedList<Studio>(scope, 20) { page, per -> DetailRepository.studios(DetailSort.findFilter(page, per, studioSort), s) } }
    val performers = performerScope?.let { s -> PagedList<Performer>(scope, 20) { page, per -> DetailRepository.performers(DetailSort.findFilter(page, per, performerSort), s) } }
    val tags = tagScope?.let { s -> PagedList<Tag>(scope, 40) { page, per -> DetailRepository.tags(DetailSort.findFilter(page, per, tagSort), s) } }
    val groups = groupScope?.let { s -> PagedList<StashGroup>(scope, 20) { page, per -> DetailRepository.groups(FindFilter(page, per, "name", "ASC"), s) } }
    /** iOS `liveFilterMediaKind` of the Images section ("Type": Any / Image / Video). */
    val imageKind = ImageMediaKindHolder()
    /**
     * Images section (iOS `DetailLinkedImagesFilterModel`): filter, sort (`dateDesc`, session
     * only), Type and criteria from the images sheet; [imageScope] is layered last, so nothing
     * in the sheet can widen the list beyond this entity.
     */
    val imageController = imageScope?.let { s ->
        CatalogController<StashImage>(
            FilterMode.Images, scope,
            tabId = null,
            scope = s,
            initialSort = SortCatalog.option(FilterMode.Images, DetailSort.Image.DateDesc.raw),
            extraLive = { imageKind.kind.pathCriterion?.let { JsonObject(mapOf("path" to it)) } ?: JsonObject(emptyMap()) },
            persistSort = {},
        )
    }
    val images: PagedList<StashImage>? = imageController?.list
    /** Grouped 1/row feed of the Images section (iOS `LinkedImagesCatalogGrid` / `ImagesView(gallery:)`). */
    val imageFeed = ImageFeedGridModel()

    private var started = false

    fun loadAll(force: Boolean = false) {
        if (started && !force) return
        started = true
        listOfNotNull(scenes, galleries, studios, performers, tags, groups).forEach { it.refresh() }
        // First appearance also loads the saved filters the images sheet offers.
        imageController?.let { c -> if (c.list.loadedOnce) c.refresh() else c.onAppear() }
    }

    fun list(tab: DetailTab): PagedList<*>? = when (tab) {
        DetailTab.Scenes -> scenes; DetailTab.Galleries -> galleries; DetailTab.Studios -> studios
        DetailTab.Performers -> performers; DetailTab.Tags -> tags; DetailTab.Groups -> groups; DetailTab.Images -> images
    }

    /** iOS `effectiveScenes` — once the first fetch is done the server count wins. */
    val effectiveScenes: Int get() = scenes?.let { if (it.loadedOnce) it.totalCount else maxOf(it.totalCount, previewScenes) } ?: 0
    val effectiveGalleries: Int get() = maxOf(galleries?.totalCount ?: 0, previewGalleries)
    val effectiveImages: Int get() {
        val total = maxOf(images?.totalCount ?: 0, previewImages)
        // A sheet filter / Type that matches nothing keeps the tab (empty state), no auto-switch away.
        return if (imagesFiltered) maxOf(total, 1) else total
    }

    /** The images sheet narrows the list (filter, preset, criteria or Type). */
    val imagesFiltered: Boolean get() = imageController?.let { it.isFilterActive || imageKind.kind != ImageListMediaKind.All } ?: false

    fun count(tab: DetailTab): Int = when (tab) {
        DetailTab.Scenes -> effectiveScenes
        DetailTab.Galleries -> effectiveGalleries
        DetailTab.Images -> effectiveImages
        else -> list(tab)?.totalCount ?: 0
    }

    /** iOS `availableTabs`. */
    val available: List<DetailTab> get() = order.filter { count(it) > 0 }

    val isSettled: Boolean get() = listOfNotNull(scenes, galleries, studios, performers, tags, groups, images).all { it.loadedOnce && !it.isLoading }

    fun changeSceneSort(s: DetailSort.Scene) {
        if (s == DetailSort.Scene.Random && sceneSort == DetailSort.Scene.Random) DetailSort.refreshRandomSeed()
        sceneSort = s
        sceneContext?.let { DetailViewConfig.setSortOption(it, s.raw) }
        scenes?.refresh()
    }

    fun <S : SortChoice> resort(tab: DetailTab, old: S, new: S, apply: (S) -> Unit) {
        if (new.field == "random" && old.field == "random") DetailSort.refreshRandomSeed()
        apply(new)
        list(tab)?.refresh()
    }

    /** Footer slots + sort menu for [tab] (iOS `*DetailListSlots`). */
    fun slots(tab: DetailTab): Pair<List<ChromeSlot>, (@Composable (() -> Unit) -> Unit)?> = when (tab) {
        DetailTab.Scenes -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Scene.entries, sceneSort, d) { changeSceneSort(it) } }
        DetailTab.Galleries -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Gallery.entries, gallerySort, d) { resort(tab, gallerySort, it) { s -> gallerySort = s } } }
        DetailTab.Studios -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Studio.entries, studioSort, d) { resort(tab, studioSort, it) { s -> studioSort = s } } }
        DetailTab.Performers -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Performer.entries, performerSort, d) { resort(tab, performerSort, it) { s -> performerSort = s } } }
        DetailTab.Tags -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Tag.entries, tagSort, d) { resort(tab, tagSort, it) { s -> tagSort = s } } }
        // Images: no sort menu — the top bar's Settings opens the images sheet ([imagesSettingsSlot]).
        DetailTab.Groups, DetailTab.Images -> emptyList<ChromeSlot>() to null
    }

    /** Top-bar "Settings" of the Images section (iOS filter & sort FAB of `LinkedImagesCatalogGrid`). */
    fun imagesSettingsSlot(tab: DetailTab): CatalogChromeSlot? {
        val c = imageController ?: return null
        if (tab != DetailTab.Images) return null
        return CatalogChromeSlot(SF.sliderHorizontal3, imagesFiltered, "Settings") {
            c.isSheetPresented = true
        }
    }
}

/**
 * iOS `ImagesCatalogFilterSortSheet` of a detail screen's Images section: filter & sort, Type,
 * Per row (`CatalogCardColumnScope.images`), feed autoplay and the criteria editor.
 */
@Composable
internal fun LinkedImagesSettingsSheet(catalog: LinkedCatalog) {
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
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = detailTopPadding(hasTabs), bottom = TabBarClearance + 16.dp),
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
