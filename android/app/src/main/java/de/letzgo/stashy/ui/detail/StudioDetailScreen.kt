package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
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
import androidx.compose.ui.layout.ContentScale
import de.letzgo.stashy.ui.SF
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `StudioDetailView` — logo hero header (PNG/JPG/SVG via Coil like `StudioLogoStore`), sections Scenes · Galleries · Studios (sub-studios) · Performers · Tags ·
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
        // iOS `StudioDetailView.imageGrid` stays a thumbnail grid even at 1/row.
        usesImageFeed = false,
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
            DetailGrid(gridState, { w -> columnsFor(tab, w, if (catalog.usesImageFeed) catalog.imageColumns else 2) }, hasTabs = catalog.available.size > 1, header = { studio?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                studio?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit studio",
            )
        }
        LinkedSettingsSheets(catalog)
        val s = studio
        if (editing && s != null) EditStudioSheet(s, { editing = false }) { studio = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Studio(studioId), studio?.name ?: "", studio?.sceneCount) { showSceneDownloadOptions = false }
        }
    }

    /**
     * iOS `headerCard` as a [DetailHeroCard]: the logo blurred as the band backdrop and, never
     * cropped (fit, inset on the dark studio backdrop), in the circle before the name + Feeds pill
     * (tap → fullscreen); details, URL and description below on the card. Without a logo, all on
     * the plain card.
     */
    @Composable
    private fun Header(s: Studio) {
        val p = Theme.palette
        val url = s.imageURL?.takeIf { s.hasImage }
        DetailHeroCard(
            title = s.name,
            items = DetailFormatting.studio(s, catalog.effectiveScenes.coerceAtLeast(s.sceneCount ?: 0), catalog.effectiveGalleries),
            description = s.details?.takeIf { it.isNotEmpty() },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = url?.let {
                DetailHero(DetailHero.Style.Logo, it, p.studioHeader, "Open logo", { Nav.push(HeroPictureViewerScreen(it, s.name, p.studioHeader, inset = true)) }) {
                    HeroPicture(it, s.name, ContentScale.Fit, SF.building2)
                }
            },
            collapsedItemCount = 4,
            titleAccessory = { color -> FeedsPill(color) { DetailFeedsLink.navigate(DetailFeedsLink.Target.Studio(s.id, s.name)) } },
            footer = s.url?.takeIf { it.isNotEmpty() }?.let { link -> { HeaderLink(link) } },
        )
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
