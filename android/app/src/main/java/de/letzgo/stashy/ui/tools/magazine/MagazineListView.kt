package de.letzgo.stashy.ui.tools.magazine

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.MagazineDefaultFilter
import de.letzgo.stashy.data.tools.MagazineLogic
import de.letzgo.stashy.data.tools.MagazineReadingStore
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeCardShape
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.GalleriesList
import de.letzgo.stashy.ui.catalog.RetainedCatalogs
import de.letzgo.stashy.ui.catalog.rememberCatalogController
import kotlinx.coroutines.flow.distinctUntilChanged

/** Filter state survives switching between Home tabs, separate from the Galleries catalog. */
private object MagazineControllers {
    private val controllers = HashMap<String?, CatalogController<Gallery>>()

    fun controller(serverId: String?): CatalogController<Gallery> =
        controllers.getOrPut(serverId) {
            CatalogController(FilterMode.Galleries, RetainedCatalogs.scope, defaultFilterIdFor = { MagazineDefaultFilter.id })
        }
}

/** A4. */
private const val COVER_ASPECT_RATIO = 210f / 297f

/**
 * iOS: `MagazineListView` — Home › Magazin: the regular gallery list (filter, sort, presets) as
 * magazine covers, opening the reader. Switched on in Settings › stashy+ or Home Tabs.
 */
@Composable
fun MagazineCatalog() {
    val serverId = ServerConfigManager.activeConfig?.id
    val c = rememberCatalogController<Gallery>(FilterMode.Galleries, key = "magazine", retain = false) {
        MagazineControllers.controller(serverId)
    }
    LaunchedEffect(c, MagazineDefaultFilter.id) { c.syncDefaults() }
    LaunchedEffect(c) {
        MagazineReadingStore.ensureLoaded()
        snapshotFlow { c.list.items.map { it.id } }
            .distinctUntilChanged()
            .collect { MagazineReadingStore.sync(it) }
    }
    GalleriesList(
        c, CatalogCardColumnScope.Galleries,
        card = { gallery, _ -> MagazineCoverCard(gallery) },
        columns = MagazineLogic::coverColumns,
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MagazineCoverCard(gallery: Gallery) {
    val page = MagazineReadingStore.entries[gallery.id]?.page
    val progress = MagazineLogic.readFraction(page, gallery.imageCount)
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        NativeCard(
            Modifier.fillMaxWidth().aspectRatio(COVER_ASPECT_RATIO).clip(NativeCardShape).combinedClickable(
                onLongClick = { if ((page ?: 1) > 1) menuOpen = true },
                onClick = { Nav.push(MagazineReaderScreen(gallery)) },
            ),
        ) {
            AsyncImage(gallery.coverURL, null, Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentScale = ContentScale.Crop)
            Text(
                gallery.displayTitle,
                Modifier.align(Alignment.BottomStart).fillMaxWidth()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))))
                    // Clear of the progress bar.
                    .padding(start = 8.dp, end = 8.dp, top = 20.dp, bottom = 10.dp),
                style = NativeType.labelMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            progress?.let { fraction ->
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp).background(Color.White.copy(alpha = 0.2f))) {
                    Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(5.dp).background(Appearance.tint))
                }
            }
        }
        DropdownMenu(menuOpen, { menuOpen = false }, containerColor = Theme.palette.secondaryBackground) {
            OverflowItem(tr(R.string.action_reset_position), SF.counterclockwise, { menuOpen = false }) {
                MagazineReadingStore.resetPosition(gallery.id)
            }
        }
    }
}
