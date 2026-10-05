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
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `ImagesView(gallery:)` for an opened gallery — chrome bar Back · Edit, the gallery
 * header (cover strip, IMAGES / DATE / STUDIO / PERFORMERS / ORGANIZED, details when
 * expanded), then the image grid with the 1/2-per-row toggle (`openedGallery` scope) and sort.
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

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Images),
        imageScope = DetailRepository.scope("galleries", galleryId),
        imageContext = DetailViewContext.Gallery,
        previewImages = preview?.imageCount ?: 0,
    )

    private fun load() {
        catalog.loadAll(force = true)
        // iOS `hydrateOpenedGalleryIfNeeded` — stubs (no cover) get the full row.
        scope.launch { runCatching { DetailRepository.gallery(galleryId) }.getOrNull()?.let { gallery = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(DetailTab.Images, w, catalog.imageColumns) }, header = { gallery?.let { Header(it) } }) {
                imageSection(catalog, gridState, currentGalleryId = galleryId)
            }
            DetailNavBar(emptyList(), null, {}, onEdit = { editing = true }, editLabel = "Edit gallery")
            val (slots, menu) = catalog.slots(DetailTab.Images, imageScopeKey = "openedGallery")
            // iOS `galleryDownloadSlot` (secondary contextual, before filter & sort).
            val download = gallery?.let { imageSetDownloadSlot(it.id, "Download gallery") { showDownloadOptions = true } }
            DetailSlotBar(slots + listOfNotNull(download), menu)
        }
        val g = gallery
        if (editing && g != null) EditGallerySheet(g, { editing = false }) { gallery = it }
        if (showDownloadOptions && g != null) GalleryDownloadOptionsDialog(g) { showDownloadOptions = false }
    }

    /** iOS `openedGalleryHeader`. */
    @Composable
    private fun Header(g: Gallery) {
        val items = DetailFormatting.gallery(g, catalog.images?.totalCount ?: 0)
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
                    EditField("Date (YYYY-MM-DD)", gallery.date ?: "", KeyboardType.Ascii),
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
