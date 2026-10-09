package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.ui.tools.downloads.GalleryDownloadOptionsDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.data.CatalogCardColumns
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.catalog.CatalogChromeSlot
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.ImageDeleteConfirmation
import de.letzgo.stashy.ui.catalog.ImageFeedGridModel
import de.letzgo.stashy.ui.catalog.ImageSelectionController
import de.letzgo.stashy.ui.catalog.SelectableImageCell
import de.letzgo.stashy.ui.PagedList
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SelectAll
import de.letzgo.stashy.ui.catalog.ImageMediaKindHolder
import de.letzgo.stashy.ui.filter.CardColumnsCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.filter.ImageListMediaKind
import de.letzgo.stashy.ui.filter.ImageMediaTypeCard
import de.letzgo.stashy.ui.filter.ImagesFeedAutoplaySettingsCard
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.scene.EditPerformersSheet
import de.letzgo.stashy.ui.scene.EditStudioSheet
import de.letzgo.stashy.ui.scene.ScenePerformersStudioCard
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.ui.StashyColors
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/**
 * iOS: `ImagesView(gallery:)` for an opened gallery — chrome bar Back · Edit, one header card
 * with the cover as a hero and the gallery title + IMAGES / DATE / ORGANIZED overlaid on it
 * (plain card without a picture; description below, expandable), the scene-detail Performers & Studio card (only when set), then the image grid (2/row) or the grouped feed (1/row). The top bar's "Settings"
 * opens the images filter & sort sheet (iOS `ImagesCatalogFilterSortSheet` with
 * `DetailLinkedImagesFilterModel(scope: .gallery(id))`): filter, sort, Type, Per row
 * (`openedGallery` scope), autoplay toggles and the criteria editor. The `galleries` INCLUDES
 * scope is layered last, so no saved filter or criterion can widen the list beyond this gallery.
 * Tapping an image opens [ImageViewerScreen].
 */
class GalleryDetailScreen(
    val galleryId: String,
    val preview: Gallery? = null,
    /** iOS `forceOneColumnFeed` (opened from an image-feed avatar): 1/row until the sheet's "Per row" is used. */
    val forceOneColumnFeed: Boolean = false,
) : Screen {
    override val key = "gallery-$galleryId"

    private val scope = screenScope()
    private var gallery by mutableStateOf(preview)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** Performers / Studio card pencils (`galleryUpdate` performer_ids / studio_id). */
    private var editingPerformers by mutableStateOf(false)
    private var editingStudio by mutableStateOf(false)
    /** iOS `showingGalleryDownloadOptions` (`GalleryDownloadOptionsAlert`). */
    private var showDownloadOptions by mutableStateOf(false)
    private var started = false
    /** iOS `ignoreForcedOneColumnFeed`. */
    private var ignoreForcedColumns by mutableStateOf(false)
    private val forcedColumns: CatalogCardColumns? get() = if (forceOneColumnFeed && !ignoreForcedColumns) CatalogCardColumns.One else null
    private val gridState = LazyGridState()

    /** iOS `liveFilterMediaKind` ("Type": Any / Image / Video). */
    private val kind = ImageMediaKindHolder()
    private val images = CatalogController<StashImage>(
        FilterMode.Images, scope,
        tabId = null,
        scope = DetailRepository.scope("galleries", galleryId),
        initialSort = SortCatalog.option(FilterMode.Images, DetailViewConfig.imageSort(DetailViewContext.Gallery).raw),
        extraLive = { kind.kind.pathCriterion?.let { JsonObject(mapOf("path" to it)) } ?: JsonObject(emptyMap()) },
        persistSort = { DetailViewConfig.setSortOption(DetailViewContext.Gallery, it.raw) },
    )
    /** Grouped 1/row feed (iOS `ImagesView(gallery:)` one-column layout). */
    private val imageFeed = ImageFeedGridModel()
    /** iOS `isSelectionMode` / `selectedImageIds` (multi-select + bulk delete). */
    private val selection = ImageSelectionController()

    private fun load() {
        images.onAppear()
        // iOS `hydrateOpenedGalleryIfNeeded` — stubs (no cover) get the full row.
        scope.launch { runCatching { DetailRepository.gallery(galleryId) }.getOrNull()?.let { gallery = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        androidx.activity.compose.BackHandler(enabled = selection.isActive) { selection.end() }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            val columns = (forcedColumns ?: CatalogPrefs.cardColumns(CatalogCardColumnScope.OpenedGallery)).raw
            DetailGrid(gridState, { w -> columnsFor(DetailTab.Images, w, columns) }, header = { gallery?.let { HeaderWithCards(it) } }) {
                // iOS: while selecting, 1/row drops the grouped feed for per-image cards.
                if (selection.isActive) selectableImageSection(images.list, selection)
                else imageSection(
                    images.list, useFeed = columns == 1, feedModel = imageFeed, sortRaw = images.sort.raw,
                    gridState = gridState, currentGalleryId = galleryId,
                )
            }
            if (selection.isActive) {
                // iOS `CatalogSelectionChrome`: Select all · Delete · Done.
                DetailTopBar(
                    "${selection.state.count} Selected", emptyList(), null, {},
                    listOf(
                        ChromeSlot(Icons.Filled.SelectAll, "Select all") { selection.selectAll(images.list.items) },
                        ChromeSlot(SF.trash, "Delete") { selection.requestDelete() },
                        ChromeSlot(SF.checkmark, "Done", isActive = true) { selection.end() },
                    ),
                )
            } else {
                // iOS `galleryDownloadSlot` (secondary contextual, before filter & sort).
                val download = gallery?.let { imageSetDownloadSlot(it.id, "Download gallery") { showDownloadOptions = true } }
                val select = ChromeSlot(SF.checkmarkCircle, "Select images") { selection.begin() }
                DetailTopBar(
                    gallery?.displayTitle ?: "", emptyList(), null, {}, listOfNotNull(select, download),
                    settings = CatalogChromeSlot(SF.sliderHorizontal3, images.isFilterActive || kind.kind != ImageListMediaKind.All, "Settings") {
                        images.isSheetPresented = true
                    },
                    onEdit = { editing = true }, editLabel = "Edit gallery",
                )
            }
        }
        ImageDeleteConfirmation(selection, images.list)
        CatalogFilterSortSheet(images, onReset = { kind.kind = ImageListMediaKind.All }) {
            ImageMediaTypeCard(kind.kind) { kind.kind = it; images.applyLive() }
            CardColumnsCard(CatalogCardColumnScope.OpenedGallery, forced = forcedColumns) { ignoreForcedColumns = true }
            ImagesFeedAutoplaySettingsCard()
        }
        val g = gallery
        if (editing && g != null) EditGallerySheet(g, { editing = false }) { gallery = it }
        if (editingPerformers && g != null) EditPerformersSheet(
            g.performers.orEmpty().map { it.id }.toSet(), { DetailRepository.updateGalleryPerformers(g.id, it) },
            { editingPerformers = false },
        ) { picked -> gallery = gallery?.copy(performers = picked) }
        if (editingStudio && g != null) EditStudioSheet(
            g.studio?.id, { DetailRepository.updateGalleryStudio(g.id, it) },
            { editingStudio = false },
        ) { picked -> gallery = gallery?.copy(studio = picked) }
        if (showDownloadOptions && g != null) GalleryDownloadOptionsDialog(g) { showDownloadOptions = false }
    }

    /**
     * Hero header, then the scene detail's Performers & Studio card (full width). The card only
     * shows when the gallery has a studio or performers — or in edit mode, empty, so they can be
     * assigned via its pencil menu.
     */
    @Composable
    private fun HeaderWithCards(g: Gallery) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            HeroHeader(g)
            ScenePerformersStudioCard(
                g.date, g.studio, g.performers.orEmpty(), director = null,
                onEditStudio = { editingStudio = true }, onEditPerformers = { editingPerformers = true },
            )
        }
    }

    /** The gallery cover, else the first loaded image (with its list index and whether it is the cover); null without any picture. */
    private fun heroImage(g: Gallery): Triple<StashImage, Int, Boolean>? {
        val items = images.list.items
        val cover = g.cover?.takeIf { it.paths != null && it.id != null }
        val coverIndex = cover?.id?.let { id -> items.indexOfFirst { it.id == id } } ?: -1
        val image = when {
            coverIndex >= 0 -> items[coverIndex]
            cover != null -> StashImage(id = cover.id!!, paths = cover.paths)
            else -> items.firstOrNull()
        } ?: return null
        return Triple(image, coverIndex, cover != null)
    }

    /**
     * iOS `openedGalleryHeader` merged with the cover hero ([DetailHeroCard]): the cover (thumbnail)
     * blurred as the band backdrop and center-cropped in the circle before the title; tapping the
     * band opens the fullscreen viewer. Details and description (three lines, expandable) below on
     * the card. Without a picture, all on the plain card.
     */
    @Composable
    private fun HeroHeader(g: Gallery) {
        val hero = heroImage(g)
        // A video clip as cover fails to decode as a picture, so it uses the thumbnail.
        val url = hero?.first?.let { img -> (if (img.isVideo) null else img.imageURL) ?: img.thumbnailURL }
        DetailHeroCard(
            title = g.displayTitle,
            items = DetailFormatting.gallery(g, images.list.totalCount),
            description = g.details?.takeIf { it.isNotEmpty() },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = if (hero != null && url != null) {
                val (image, coverIndex, isCover) = hero
                val thumb = image.thumbnailURL
                DetailHero(DetailHero.Style.Cover, thumb ?: url, Color.Black, "Open image", { openHero(image, coverIndex, isCover) }) {
                    // 72dp circle: the thumbnail is plenty; full picture only when there is none.
                    SubcomposeAsyncImage(
                        thumb ?: url, g.displayTitle, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.Center,
                        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), color = Color.White.copy(alpha = 0.7f), strokeWidth = 2.dp) } },
                        error = {
                            Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), Alignment.Center) {
                                Icon(photoOnRectangleIcon(), null, tint = StashyColors.appAccent.copy(alpha = 0.5f), modifier = Modifier.size(28.dp))
                            }
                        },
                    )
                }
            } else null,
        )
    }

    /** Viewer on the hero picture: inside the loaded list when it is there, else just that picture. */
    private fun openHero(image: StashImage, coverIndex: Int, isCover: Boolean) {
        val list = images.list
        val index = when {
            coverIndex >= 0 -> coverIndex
            !isCover && list.items.isNotEmpty() -> 0
            else -> -1
        }
        if (index >= 0) Nav.push(ImageViewerScreen(list.items, index, onLoadMore = { list.loadMore() }))
        else Nav.push(ImageViewerScreen(listOf(image), 0))
    }

    /** iOS: `EditGallerySheet`. */
    @Composable
    private fun EditGallerySheet(gallery: Gallery, onDismiss: () -> Unit, onSaved: (Gallery) -> Unit) {
        val sections = remember(gallery.id) {
            listOf(
                EditSection("Identity", listOf(
                    EditField("Title", gallery.title ?: ""),
                    EditField("Date (YYYY-MM-DD)", gallery.date ?: "", KeyboardType.Ascii, isDate = true),
                )),
                EditSection("Details", listOf(EditField("Details", gallery.details ?: "", multiline = true))),
            )
        }
        val (title, date) = sections[0].fields
        val details = sections[1].fields[0]
        EditEntitySheet(
            title = "Edit Gallery", sections = sections,
            deleteLabel = "Delete Gallery", deleteTitle = "Delete Gallery", entityName = gallery.title ?: "",
            onDismiss = onDismiss,
            onSave = {
                val ok = DetailRepository.updateGallery(gallery.id, title.trimmed, date.optional, details.optional)
                if (ok) {
                    onSaved(gallery.copy(title = title.trimmed, date = date.optional, details = details.optional))
                    detailToast("Gallery updated")
                } else detailToast("Failed to update gallery")
                ok
            },
            onDelete = {
                DetailRepository.deleteGallery(gallery.id)
                detailToast("Gallery deleted")
                Nav.pop()
            },
        )
    }
}

/** [imageSection] in selection mode: per-image cards with the selection overlay (iOS `imageCell`). */
private fun LazyGridScope.selectableImageSection(list: PagedList<StashImage>, selection: ImageSelectionController) {
    pagedSection(list, { it.id }, "Loading images...", SF.cameraFill, "No images found") { _, image ->
        SelectableImageCell(selection.state.isSelected(image.id), { selection.toggle(image.id) }) {
            DetailImageCard(image)
        }
    }
}

private fun photoOnRectangleIcon() = de.letzgo.stashy.ui.SF.photoOnRectangle
