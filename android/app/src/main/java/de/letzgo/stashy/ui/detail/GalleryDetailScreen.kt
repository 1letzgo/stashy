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
import de.letzgo.stashy.ui.catalog.ImageFeedGridModel
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
class GalleryDetailScreen(val galleryId: String, val preview: Gallery? = null) : Screen {
    override val key = "gallery-$galleryId"

    private val scope = screenScope()
    private var gallery by mutableStateOf(preview)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingGalleryDownloadOptions` (`GalleryDownloadOptionsAlert`). */
    private var showDownloadOptions by mutableStateOf(false)
    private var started = false
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

    private fun load() {
        images.onAppear()
        // iOS `hydrateOpenedGalleryIfNeeded` — stubs (no cover) get the full row.
        scope.launch { runCatching { DetailRepository.gallery(galleryId) }.getOrNull()?.let { gallery = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            val columns = CatalogPrefs.cardColumns(CatalogCardColumnScope.OpenedGallery).raw
            DetailGrid(gridState, { w -> columnsFor(DetailTab.Images, w, columns) }, header = { gallery?.let { Header(it) } }) {
                imageSection(
                    images.list, useFeed = columns == 1, feedModel = imageFeed, sortRaw = images.sort.raw,
                    gridState = gridState, currentGalleryId = galleryId,
                )
            }
            // iOS `galleryDownloadSlot` (secondary contextual, before filter & sort).
            val download = gallery?.let { imageSetDownloadSlot(it.id, "Download gallery") { showDownloadOptions = true } }
            DetailTopBar(
                gallery?.displayTitle ?: "", emptyList(), null, {}, listOfNotNull(download),
                settings = CatalogChromeSlot(SF.sliderHorizontal3, images.isFilterActive || kind.kind != ImageListMediaKind.All, "Settings") {
                    images.isSheetPresented = true
                },
                onEdit = { editing = true }, editLabel = "Edit gallery",
            )
        }
        CatalogFilterSortSheet(images, onReset = { kind.kind = ImageListMediaKind.All }) {
            ImageMediaTypeCard(kind.kind) { kind.kind = it; images.applyLive() }
            CardColumnsCard(CatalogCardColumnScope.OpenedGallery)
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

private fun photoOnRectangleIcon() = de.letzgo.stashy.ui.SF.photoOnRectangle
