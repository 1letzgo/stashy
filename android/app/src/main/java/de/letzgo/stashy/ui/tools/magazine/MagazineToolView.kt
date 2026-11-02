package de.letzgo.stashy.ui.tools.magazine

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.MagazineDefaultFilter
import de.letzgo.stashy.data.tools.MagazineLogic
import de.letzgo.stashy.data.tools.MagazineReadingStore
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.GalleriesList
import de.letzgo.stashy.ui.catalog.RetainedCatalogs
import de.letzgo.stashy.ui.catalog.rememberCatalogController
import de.letzgo.stashy.ui.components.GalleryCard
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.flow.distinctUntilChanged

/** Filter state survives switching between tools, separate from the Galleries catalog. */
private object MagazineCatalog {
    private val controllers = HashMap<String?, CatalogController<Gallery>>()

    fun controller(serverId: String?): CatalogController<Gallery> =
        controllers.getOrPut(serverId) {
            CatalogController(FilterMode.Galleries, RetainedCatalogs.scope, defaultFilterIdFor = { MagazineDefaultFilter.id })
        }
}

/** iOS: `MagazineToolsView` — the regular gallery list (filter, sort, presets), opening the reader. */
@Composable
fun MagazineToolView() {
    val serverId = ServerConfigManager.activeConfig?.id
    val c = rememberCatalogController<Gallery>(FilterMode.Galleries, key = "magazine", retain = false) {
        MagazineCatalog.controller(serverId)
    }
    LaunchedEffect(c, MagazineDefaultFilter.id) { c.syncDefaults() }
    LaunchedEffect(c) {
        MagazineReadingStore.ensureLoaded()
        snapshotFlow { c.list.items.map { it.id } }
            .distinctUntilChanged()
            .collect { MagazineReadingStore.sync(it) }
    }
    GalleriesList(c, CatalogCardColumnScope.Galleries, topPadding = toolsTopPadding()) { gallery, aspectRatio ->
        MagazineGalleryCard(gallery, aspectRatio)
    }
}

@Composable
private fun MagazineGalleryCard(gallery: Gallery, aspectRatio: Float) {
    val page = MagazineReadingStore.entries[gallery.id]?.page
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        GalleryCard(
            gallery,
            aspectRatio = aspectRatio,
            progress = MagazineLogic.readFraction(page, gallery.imageCount),
            onLongClick = if ((page ?: 1) > 1) ({ menuOpen = true }) else null,
            onClick = { Nav.push(MagazineReaderScreen(gallery)) },
        )
        DropdownMenu(menuOpen, { menuOpen = false }, containerColor = Theme.palette.secondaryBackground) {
            OverflowItem("Reset position", SF.counterclockwise, { menuOpen = false }) {
                MagazineReadingStore.resetPosition(gallery.id)
            }
        }
    }
}
