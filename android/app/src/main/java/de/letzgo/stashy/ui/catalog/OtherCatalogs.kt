package de.letzgo.stashy.ui.catalog

import de.letzgo.stashy.ui.bottomBarContentPadding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.data.CatalogCardColumns
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.PerformerBadgeType
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.adaptiveColumnCount
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.components.GalleryCard
import de.letzgo.stashy.ui.components.GroupCard
import de.letzgo.stashy.ui.components.ImageCard
import de.letzgo.stashy.ui.components.MarkerCard
import de.letzgo.stashy.ui.components.PerformerCard
import de.letzgo.stashy.ui.components.StudioCard
import de.letzgo.stashy.ui.components.TagCard
import de.letzgo.stashy.ui.detail.GalleryDetailScreen
import de.letzgo.stashy.ui.detail.GroupDetailScreen
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.detail.StudioDetailScreen
import de.letzgo.stashy.ui.detail.TagDetailScreen
import de.letzgo.stashy.ui.filter.CardColumnsCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.filter.ImageListMediaKind
import de.letzgo.stashy.ui.filter.ImageMediaTypeCard
import de.letzgo.stashy.ui.filter.ImagesFeedAutoplaySettingsCard
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import kotlinx.serialization.json.JsonObject

/** Poster grids: ideal card width 220, 2…8 columns (iOS `DesignTokens.Grid.adaptiveColumns`). */
private val posterColumns: (Float) -> Int = { adaptiveColumnCount(it) }

/** iOS: `PerformersView` — 9:12 cards, count pill follows the sort. */
@Composable
fun PerformersCatalog() {
    val c = rememberCatalogController<Performer>(FilterMode.Performers)
    PerformersList(c)
}

@Composable
fun PerformersList(c: CatalogController<Performer>, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding()) {
    CatalogScaffold(
        c, CatalogTexts("Loading performers...", SF.person3, "No performers found", "Load Performers"),
        CatalogSlots(filterSort = filterSortSlot(c)), posterColumns, { it.id }, topPadding,
    ) { _, performer ->
        PerformerCard(performer, badgeType = PerformerBadgeType.forSort(c.sort), onClick = { Nav.push(PerformerDetailScreen(performer.id, performer)) })
    }
    CatalogFilterSortSheet(c)
}

/** iOS: `StudiosView` — logo cards, 500 per page. */
@Composable
fun StudiosCatalog() {
    val c = rememberCatalogController<Studio>(FilterMode.Studios)
    StudiosList(c)
}

@Composable
fun StudiosList(c: CatalogController<Studio>, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding()) {
    CatalogScaffold(
        c, CatalogTexts("Loading studios...", SF.building2, "No studios found", "Load Studios"),
        CatalogSlots(filterSort = filterSortSlot(c)), posterColumns, { it.id }, topPadding,
    ) { _, studio ->
        StudioCard(studio, onClick = { Nav.push(StudioDetailScreen(studio.id, studio)) })
    }
    CatalogFilterSortSheet(c)
}

/** iOS: `TagsView`. */
@Composable
fun TagsCatalog() {
    val c = rememberCatalogController<Tag>(FilterMode.Tags)
    TagsList(c)
}

@Composable
fun TagsList(c: CatalogController<Tag>, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding()) {
    CatalogScaffold(
        c, CatalogTexts("Loading tags...", SF.tag, "No tags found", "Load Tags"),
        CatalogSlots(filterSort = filterSortSlot(c)), posterColumns, { it.id }, topPadding,
    ) { _, tag ->
        TagCard(tag, onClick = { Nav.push(TagDetailScreen(tag.id, tag)) })
    }
    CatalogFilterSortSheet(c)
}

/** iOS: `GroupsView` (CatalogsView.swift) — sorting via the filter & sort sheet (sort menu, no local presets). */
@Composable
fun GroupsCatalog() {
    val c = rememberCatalogController<StashGroup>(FilterMode.Groups)
    CatalogScaffold(
        c, CatalogTexts("Loading groups...", SF.rectangleStackFill, "No groups found", "Load Groups"),
        CatalogSlots(filterSort = filterSortSlot(c)), posterColumns, { it.id },
    ) { _, group ->
        GroupCard(group, onClick = { Nav.push(GroupDetailScreen(group.id, group)) })
    }
    CatalogFilterSortSheet(c)
}

/** iOS: `MarkersView` — 16:9 marker cards; tap opens the scene at the marker time. */
@Composable
fun MarkersCatalog() {
    val c = rememberCatalogController<SceneMarker>(FilterMode.SceneMarkers)
    CatalogScaffold(
        c, CatalogTexts("Loading markers...", SF.bookmarkFill, "No markers found", "Load Markers"),
        CatalogSlots(filterSort = filterSortSlot(c)), posterColumns, { it.id },
    ) { _, marker ->
        MarkerCard(marker, onClick = {
            marker.scene?.let { scene -> Nav.push(SceneDetailScreen(scene.id, scene.copy(resumeTime = marker.seconds), autoPlay = true)) }
        })
    }
    CatalogFilterSortSheet(c)
}

/** iOS: `GalleriesView` — 1/2 per row (Settings), 16:9 or square cards. */
@Composable
fun GalleriesCatalog() {
    val c = rememberCatalogController<Gallery>(FilterMode.Galleries)
    GalleriesList(c, CatalogCardColumnScope.Galleries)
}

@Composable
fun GalleriesList(c: CatalogController<Gallery>, columnScope: CatalogCardColumnScope, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding()) {
    val cols = CatalogPrefs.cardColumns(columnScope)
    CatalogScaffold(
        c, CatalogTexts("Loading galleries...", SF.photoStack, "No galleries found", "Reload"),
        CatalogSlots(filterSort = filterSortSlot(c)),
        columns = { cols.columnCount(it) }, itemKey = { it.id }, topPadding = topPadding, gridKey = cols,
    ) { _, gallery ->
        GalleryCard(gallery, aspectRatio = cols.cardAspectRatio, onClick = { Nav.push(GalleryDetailScreen(gallery.id, gallery)) })
    }
    CatalogFilterSortSheet(c)
}

/** Images "Type" chip state per controller (iOS `DetailLinkedImagesFilterModel.liveFilterMediaKind`). */
class ImageMediaKindHolder { var kind by mutableStateOf(ImageListMediaKind.All) }

/**
 * iOS: `ImagesView` (catalog root) — 1/2 per row (Settings): square cards at 2/row, the grouped
 * image feed at 1/row ([ImageFeedList]: sets, header with performers / studio / date, rating +
 * O-counter, tags, thumb strip, muted clip autoplay); "Type" (Any / Image / Video) and the feed
 * autoplay switch in the sheet; tap opens the full-screen viewer.
 */
@Composable
fun ImagesCatalog() {
    val holder = androidx.compose.runtime.remember { imagesKindHolder }
    val c = rememberCatalogController<StashImage>(FilterMode.Images) { scope ->
        CatalogController(FilterMode.Images, scope, extraLive = { holder.kind.pathCriterion?.let { JsonObject(mapOf("path" to it)) } ?: JsonObject(emptyMap()) })
    }
    ImagesList(c, holder, CatalogCardColumnScope.Images)
}

private val imagesKindHolder = ImageMediaKindHolder()

@Composable
fun ImagesList(c: CatalogController<StashImage>, holder: ImageMediaKindHolder, columnScope: CatalogCardColumnScope, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding()) {
    val cols = CatalogPrefs.cardColumns(columnScope)
    CatalogScaffold(
        c, CatalogTexts("Loading images...", SF.photo, "No images found", "Reload"),
        CatalogSlots(
            filterSort = de.letzgo.stashy.ui.catalog.CatalogChromeSlot(SF.sliderHorizontal3, c.isFilterActive || holder.kind != ImageListMediaKind.All, "Settings") { c.isSheetPresented = true },
        ),
        columns = { cols.columnCount(it) }, itemKey = { it.id }, topPadding = topPadding, gridKey = cols,
        // iOS `usesOneColumnFeedLayout`: 1/row is the grouped feed, not a grid of cards.
        listBody = if (cols == CatalogCardColumns.One) { top ->
            ImageFeedList(
                images = c.list.items,
                sortRaw = c.sort.raw,
                isLoading = c.list.isLoading,
                onLoadMore = { c.list.loadMore() },
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = top, bottom = bottomBarContentPadding()),
                onImageUpdated = { updated -> c.list.patch { if (it.id == updated.id) updated else it } },
                header = if (c.search.isNotEmpty()) ({
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { SearchClearChip(c.search, { c.search = "" }) }
                }) else null,
            )
        } else null,
    ) { index, image ->
        ImageCard(image, aspectRatio = 1f, onClick = { Nav.push(ImageViewerScreen(c.list.items.toList(), index)) })
    }
    CatalogFilterSortSheet(c, onReset = { holder.kind = ImageListMediaKind.All }) {
        ImageMediaTypeCard(holder.kind) { holder.kind = it; c.applyLive() }
        CardColumnsCard(columnScope)
        ImagesFeedAutoplaySettingsCard()
    }
}
