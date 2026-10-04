package de.letzgo.stashy.ui.detail

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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.DetailRepository
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
    imageContext: DetailViewContext? = null,
    /** Scene / gallery counts known from the list item, so the first tab is right before loading. */
    var previewScenes: Int = 0,
    var previewGalleries: Int = 0,
    var previewImages: Int = 0,
) {
    var sceneSort by mutableStateOf(sceneContext?.let { DetailViewConfig.sceneSort(it) } ?: DetailSort.Scene.DateDesc)
    var gallerySort by mutableStateOf(DetailSort.Gallery.DateDesc)
    var studioSort by mutableStateOf(DetailSort.Studio.NameAsc)
    var performerSort by mutableStateOf(DetailSort.Performer.NameAsc)
    var tagSort by mutableStateOf(DetailSort.Tag.SceneCountDesc)
    var imageSort by mutableStateOf(imageContext?.let { DetailViewConfig.imageSort(it) } ?: DetailSort.Image.DateDesc)
    var imageColumns by mutableIntStateOf(CardColumnsPrefs.columns(if (imageContext == DetailViewContext.Gallery) "openedGallery" else "images"))

    val scenes = sceneScope?.let { s -> PagedList<Scene>(scope, 20) { page, per -> DetailRepository.scenes(DetailSort.findFilter(page, per, sceneSort), s) } }
    val galleries = galleryScope?.let { s -> PagedList<Gallery>(scope, 20) { page, per -> DetailRepository.galleries(DetailSort.findFilter(page, per, gallerySort), s) } }
    val studios = studioScope?.let { s -> PagedList<Studio>(scope, 20) { page, per -> DetailRepository.studios(DetailSort.findFilter(page, per, studioSort), s) } }
    val performers = performerScope?.let { s -> PagedList<Performer>(scope, 20) { page, per -> DetailRepository.performers(DetailSort.findFilter(page, per, performerSort), s) } }
    val tags = tagScope?.let { s -> PagedList<Tag>(scope, 40) { page, per -> DetailRepository.tags(DetailSort.findFilter(page, per, tagSort), s) } }
    val groups = groupScope?.let { s -> PagedList<StashGroup>(scope, 20) { page, per -> DetailRepository.groups(FindFilter(page, per, "name", "ASC"), s) } }
    val images = imageScope?.let { s -> PagedList<StashImage>(scope, 40) { page, per -> DetailRepository.images(DetailSort.findFilter(page, per, imageSort), s) } }

    private var started = false

    fun loadAll(force: Boolean = false) {
        if (started && !force) return
        started = true
        listOfNotNull(scenes, galleries, studios, performers, tags, groups, images).forEach { it.refresh() }
    }

    fun list(tab: DetailTab): PagedList<*>? = when (tab) {
        DetailTab.Scenes -> scenes; DetailTab.Galleries -> galleries; DetailTab.Studios -> studios
        DetailTab.Performers -> performers; DetailTab.Tags -> tags; DetailTab.Groups -> groups; DetailTab.Images -> images
    }

    /** iOS `effectiveScenes` — once the first fetch is done the server count wins. */
    val effectiveScenes: Int get() = scenes?.let { if (it.loadedOnce) it.totalCount else maxOf(it.totalCount, previewScenes) } ?: 0
    val effectiveGalleries: Int get() = maxOf(galleries?.totalCount ?: 0, previewGalleries)
    val effectiveImages: Int get() = maxOf(images?.totalCount ?: 0, previewImages)

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
    fun slots(tab: DetailTab, imageScopeKey: String = "images"): Pair<List<ChromeSlot>, (@Composable (() -> Unit) -> Unit)?> = when (tab) {
        DetailTab.Scenes -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Scene.entries, sceneSort, d) { changeSceneSort(it) } }
        DetailTab.Galleries -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Gallery.entries, gallerySort, d) { resort(tab, gallerySort, it) { s -> gallerySort = s } } }
        DetailTab.Studios -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Studio.entries, studioSort, d) { resort(tab, studioSort, it) { s -> studioSort = s } } }
        DetailTab.Performers -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Performer.entries, performerSort, d) { resort(tab, performerSort, it) { s -> performerSort = s } } }
        DetailTab.Tags -> emptyList<ChromeSlot>() to { d -> SortMenuItems(DetailSort.Tag.entries, tagSort, d) { resort(tab, tagSort, it) { s -> tagSort = s } } }
        DetailTab.Groups -> emptyList<ChromeSlot>() to null
        DetailTab.Images -> listOf(
            ChromeSlot(if (imageColumns == 1) SF.rectangleGrid1x2 else SF.squareGrid2x2, if (imageColumns == 1) "One card per row" else "Two cards per row") {
                imageColumns = CardColumnsPrefs.toggle(imageScopeKey)
            },
        ) to { d -> SortMenuItems(DetailSort.Image.entries, imageSort, d) { resort(tab, imageSort, it) { s -> imageSort = s } } }
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
    header: @Composable () -> Unit,
    content: LazyGridScope.() -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = columnsFor(maxWidth.value - 32f)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = state,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = detailTopPadding(), bottom = TabBarClearance + 64.dp),
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
    DetailTab.Images -> if (imageColumns == 1) adaptiveColumnCount(widthDp, 560f, 1, 3) else adaptiveColumnCount(widthDp, 220f, 2, 8)
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
    itemsIndexed(list.items, key = { _, it -> key(it) }) { index, value ->
        LaunchedEffect(index, list.items.size) { list.onItemShown(index) }
        item(index, value)
    }
    if (list.isLoading) item(key = "more", span = { GridItemSpan(maxLineSpan) }) { LoadingFooter(loadingMessage?.let { "Loading more ${it.removePrefix("Loading ")}" }) }
}

/** The section grid for [tab] — shared by Performer/Studio/Tag/Group details. */
internal fun LazyGridScope.linkedSection(catalog: LinkedCatalog, tab: DetailTab) {
    when (tab) {
        DetailTab.Scenes -> catalog.scenes?.let { l ->
            pagedSection(l, { it.id }, null, SF.film, "No scenes found") { _, s ->
                SceneCard(s, Modifier.noRippleClickable { Nav.push(SceneDetailScreen(s.id, s)) })
            }
        }
        DetailTab.Galleries -> catalog.galleries?.let { l ->
            pagedSection(l, { it.id }, "Loading galleries...", SF.photoOnRectangle, "No galleries found") { _, g ->
                DetailGalleryCard(g, Modifier.noRippleClickable { Nav.push(GalleryDetailScreen(g.id, g)) })
            }
        }
        DetailTab.Studios -> catalog.studios?.let { l ->
            pagedSection(l, { it.id }) { _, s -> DetailStudioCard(s, Modifier.noRippleClickable { Nav.push(StudioDetailScreen(s.id, s)) }) }
        }
        DetailTab.Performers -> catalog.performers?.let { l ->
            pagedSection(l, { it.id }, "Loading performers...") { _, p -> DetailPerformerCard(p, Modifier.noRippleClickable { Nav.push(PerformerDetailScreen(p.id, p)) }) }
        }
        DetailTab.Tags -> catalog.tags?.let { l ->
            pagedSection(l, { it.id }) { _, t -> DetailTagCard(t, Modifier.noRippleClickable { Nav.push(TagDetailScreen(t.id, t)) }) }
        }
        DetailTab.Groups -> catalog.groups?.let { l ->
            pagedSection(l, { it.id }) { _, g -> DetailGroupCard(g, Modifier.noRippleClickable { Nav.push(GroupDetailScreen(g.id, g)) }) }
        }
        DetailTab.Images -> catalog.images?.let { l -> imageSection(l, catalog.imageColumns) }
    }
}

/** iOS `LinkedImagesCatalogGrid` (multi-column) / 1-per-row cards; tap opens the viewer. */
internal fun LazyGridScope.imageSection(list: PagedList<StashImage>, columns: Int) {
    pagedSection(list, { it.id }, "Loading images...", SF.cameraFill, "No images found") { index, image ->
        val aspect = if (columns == 1) (image.aspectRatio ?: 1f).coerceIn(0.56f, 1.78f) else 1f
        DetailImageCard(image, Modifier.noRippleClickable { Nav.push(ImageViewerScreen(list.items, index, onLoadMore = { list.loadMore() })) }, aspect)
    }
}

