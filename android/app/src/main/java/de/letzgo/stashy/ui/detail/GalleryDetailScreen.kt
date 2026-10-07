package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.ui.tools.downloads.GalleryDownloadOptionsDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/**
 * iOS: `ImagesView(gallery:)` for an opened gallery — chrome bar Back · Edit, the gallery
 * header (cover strip, IMAGES / DATE / STUDIO / PERFORMERS / ORGANIZED, details when
 * expanded), then the image grid (2/row) or the grouped feed (1/row). The top bar's "Settings"
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
            DetailGrid(gridState, { w -> columnsFor(DetailTab.Images, w, columns) }, header = { gallery?.let { Header(it) } }) {
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
        if (showDownloadOptions && g != null) GalleryDownloadOptionsDialog(g) { showDownloadOptions = false }
    }

    /** iOS `openedGalleryHeader`. */
    @Composable
    private fun Header(g: Gallery) {
        val items = DetailFormatting.gallery(g, images.list.totalCount)
        val details = g.details?.takeIf { it.isNotEmpty() }
        DetailHeaderCard(
            title = g.displayTitle,
            imageUrl = g.coverURL,
            placeholderIcon = photoOnRectangleIcon(),
            items = items,
            expandable = items.size > 4 || details != null,
            expanded = expanded,
            onToggle = { expanded = !expanded },
            expandedContent = details?.let { d -> { Text(d, fontSize = 11.sp, color = Theme.palette.secondaryText, modifier = Modifier.padding(top = 4.dp)) } },
        )
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
