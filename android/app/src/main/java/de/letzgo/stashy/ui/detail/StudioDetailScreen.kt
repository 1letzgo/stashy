package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `StudioDetailView` — logo header (140pt logo column, PNG/JPG/SVG via Coil like
 * `StudioLogoStore`), sections Scenes · Galleries · Studios (sub-studios) · Performers · Tags ·
 * Groups · Images, favorite and `EditStudioSheet`.
 */
class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"

    private val scope = screenScope()
    private var studio by mutableStateOf(preview)
    private var isFavorite by mutableStateOf(preview?.favorite ?: false)
    private var favoriteBusy by mutableStateOf(false)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingSceneDownloadOptions` (`sceneBulkDownloadDialog`). */
    private var showSceneDownloadOptions by mutableStateOf(false)
    private var started = false
    private val gridState = LazyGridState()

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Studios, DetailTab.Performers, DetailTab.Tags, DetailTab.Groups, DetailTab.Images),
        sceneScope = DetailRepository.scope("studios", studioId),
        galleryScope = DetailRepository.scope("studios", studioId),
        // iOS sends `parent_id`, which Stash's StudioFilterType does not know; `parents` is the real criterion.
        studioScope = DetailRepository.scope("parents", studioId),
        performerScope = DetailRepository.scope("studios", studioId),
        tagScope = DetailRepository.scope("studios", studioId),
        groupScope = DetailRepository.scope("studios", studioId),
        imageScope = DetailRepository.scope("studios", studioId),
        sceneContext = DetailViewContext.Studio,
        previewScenes = preview?.sceneCount ?: 0,
        previewGalleries = preview?.galleryCount ?: 0,
    )

    private var tab by mutableStateOf(
        when {
            (preview?.sceneCount ?: 1) > 0 -> DetailTab.Scenes
            (preview?.galleryCount ?: 0) > 0 -> DetailTab.Galleries
            else -> DetailTab.Scenes
        },
    )

    private fun load() {
        catalog.loadAll(force = true)
        scope.launch {
            runCatching { DetailRepository.studio(studioId) }.getOrNull()?.let {
                studio = it
                isFavorite = it.favorite ?: false
            }
        }
    }

    private fun toggleFavorite() {
        if (favoriteBusy) return
        favoriteBusy = true
        val new = !isFavorite
        isFavorite = new
        scope.launch {
            if (!DetailRepository.setStudioFavorite(studioId, new)) {
                isFavorite = !new
                detailToast("Failed to update favorite")
            } else studio = studio?.copy(favorite = new)
            favoriteBusy = false
        }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        // Studio performers default to Name (A-Z) (iOS `initialSort: .nameAsc`).
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, header = { studio?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            DetailNavBar(
                catalog.available, tab, { tab = it },
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit studio",
            )
            val (slots, menu) = catalog.slots(tab)
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailSlotBar(slots + extra, menu)
        }
        val s = studio
        if (editing && s != null) EditStudioSheet(s, { editing = false }) { studio = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Studio(studioId), studio?.name ?: "") { showSceneDownloadOptions = false }
        }
    }

    /** iOS `headerCard`. */
    @Composable
    private fun Header(s: Studio) {
        val p = Theme.palette
        val details = DetailFormatting.studio(s, catalog.effectiveScenes.coerceAtLeast(s.sceneCount ?: 0), catalog.effectiveGalleries)
        val hasURL = !s.url.isNullOrEmpty()
        val expandable = details.size > 4 || (hasURL && details.size > 2)
        HeaderCardFrame {
            // iOS: details padded by 140 + 12, logo overlaid at the leading edge.
            Box(Modifier.fillMaxWidth().heightIn(min = 115.dp)) {
                Box(Modifier.matchParentSize()) {
                    Box(Modifier.width(140.dp).fillMaxHeight().background(p.studioHeader).padding(8.dp)) {
                        StudioLogo(s, Modifier.fillMaxSize())
                    }
                }
                Column(Modifier.fillMaxWidth().heightIn(min = 115.dp).padding(start = 152.dp, end = 12.dp, top = 10.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            s.name, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text,
                            maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
                        )
                        FeedsPill { DetailFeedsLink.navigate(DetailFeedsLink.Target.Studio(s.id, s.name)) }
                    }
                    val visible = if (expanded) details else details.take(4)
                    if (visible.isNotEmpty()) DetailItemsGrid(visible)
                    if (hasURL && (expanded || details.size <= 2)) HeaderLink(s.url!!)
                    s.details?.takeIf { it.isNotEmpty() }?.let { desc ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            HorizontalDivider(color = p.separator)
                            Text(desc, style = IosTypography.caption, color = p.secondaryText, modifier = Modifier.padding(vertical = 4.dp))
                        }
                    }
                    if (expandable) Spacer(Modifier.height(18.dp))
                }
            }
            if (expandable) HeaderExpandButton(expanded) { expanded = !expanded }
        }
    }

    /** iOS: `EditStudioSheet`. */
    @Composable
    private fun EditStudioSheet(studio: Studio, onDismiss: () -> Unit, onSaved: (Studio) -> Unit) {
        val sections = remember(studio.id) {
            listOf(
                EditSection("Identity", listOf(
                    EditField("Name", studio.name),
                    EditField("URL", studio.url ?: "", KeyboardType.Uri),
                    EditField("Rating (0–100)", studio.rating100?.toString() ?: "", KeyboardType.Number),
                )),
                EditSection("Description", listOf(EditField("Description", studio.details ?: "", multiline = true))),
            )
        }
        val (name, url, rating) = sections[0].fields
        val details = sections[1].fields[0]
        EditEntitySheet(
            title = "Edit Studio", sections = sections,
            deleteLabel = "Delete Studio", deleteTitle = "Delete Studio", entityName = studio.name,
            onDismiss = onDismiss,
            onSave = {
                val r = EditParsing.rating(rating.value)
                val ok = DetailRepository.updateStudio(studio.id, name.trimmed, url.optional, details.optional, r)
                if (ok) {
                    onSaved(studio.copy(name = name.trimmed, url = url.optional, details = details.optional, rating100 = r))
                    detailToast("Studio updated")
                } else detailToast("Failed to update studio")
                ok
            },
            onDelete = {
                DetailRepository.deleteStudio(studio.id)
                detailToast("Studio deleted")
                Nav.pop()
            },
        )
    }
}
