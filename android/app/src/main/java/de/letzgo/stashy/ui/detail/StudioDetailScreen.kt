package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.ui.filter.LocalShowsSubStudioContentOption
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
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.StudioCountsStore
import de.letzgo.stashy.data.SubStudios
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `StudioDetailView` — logo hero header (PNG/JPG/SVG via Coil like `StudioLogoStore`), sections Scenes · Galleries · Studios (sub-studios) · Performers · Tags ·
 * Groups · Images, favorite and `EditStudioSheet`.
 */
class StudioDetailScreen(val studioId: String, val preview: Studio? = null, private val filterPerformerId: String? = null) : Screen {
    override val key = "studio-$studioId" + (filterPerformerId?.let { "-p$it" } ?: "")

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
        sceneScope = SubStudios.studioScope(FilterMode.Scenes, studioId, false),
        galleryScope = SubStudios.studioScope(FilterMode.Galleries, studioId, false),
        // iOS sends `parent_id`, which Stash's StudioFilterType does not know; `parents` is the real criterion.
        studioScope = DetailRepository.scope("parents", studioId),
        performerScope = SubStudios.studioScope(FilterMode.Performers, studioId, false),
        tagScope = SubStudios.studioScope(FilterMode.Tags, studioId, false),
        groupScope = SubStudios.studioScope(FilterMode.Groups, studioId, false),
        imageScope = SubStudios.studioScope(FilterMode.Images, studioId, false),
        studioContentId = studioId,
        sceneContext = DetailViewContext.Studio,
        // iOS `StudioDetailView.imageGrid` stays a thumbnail grid even at 1/row.
        usesImageFeed = false,
        previewScenes = preview?.sceneCount ?: 0,
        previewGalleries = preview?.galleryCount ?: 0,
    )

    init { catalog.startFilteredOnPerformer(filterPerformerId) }

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
                detailToast(tr(R.string.error_update_favorite))
            } else studio = studio?.copy(favorite = new)
            favoriteBusy = false
        }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        // "Include sub-studio content" (any filter sheet of this page) reloads every section.
        val includesContent = StudioCountsStore.includeSubStudios
        var seenInclude by remember { mutableStateOf(includesContent) }
        LaunchedEffect(includesContent) { if (includesContent != seenInclude) { seenInclude = includesContent; catalog.loadAll(force = true) } }
        CompositionLocalProvider(LocalShowsSubStudioContentOption provides true) { Body() }
    }

    @Composable
    private fun Body() {
        // Studio performers default to Name (A-Z) (iOS `initialSort: .nameAsc`).
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, if (catalog.usesImageFeed) catalog.imageColumns else 2) }, header = { studio?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                studio?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab), sort = catalog.controller(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = tr(R.string.action_edit_studio),
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
     * iOS `headerCard` as a [DetailHeroCard]: the logo blurred as the band backdrop (with the
     * details on it) and, never cropped (fit, inset on the dark studio backdrop), in the circle on
     * the band edge (tap → fullscreen); name + Feeds pill, URL and description below. Without a
     * logo, a tinted band and the studio icon in the circle.
     */
    @Composable
    private fun Header(s: Studio) {
        val p = Theme.palette
        val url = s.imageURL?.takeIf { s.hasImage }
        var fullscreen by remember { mutableStateOf<HeroImageFullscreenItem?>(null) }
        fullscreen?.let { HeroImageFullscreen(it) { fullscreen = null } }
        DetailHeroCard(
            title = s.name,
            items = DetailFormatting.studio(s, catalog.effectiveScenes.coerceAtLeast(s.sceneCount ?: 0), catalog.effectiveGalleries, de.letzgo.stashy.data.rememberStudioCounts(s, refresh = true)),
            description = s.details?.takeIf { it.isNotEmpty() },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = url?.let {
                DetailHero(DetailHero.Style.Logo, it, p.studioHeader, tr(R.string.action_open_logo), { fullscreen = HeroImageFullscreenItem(it, s.name, p.studioHeader, inset = true) }) {
                    HeroPicture(it, s.name, ContentScale.Fit, SF.building2)
                }
            } ?: DetailHero(DetailHero.Style.Cover, null, p.studioHeader, tr(R.string.action_open_logo), null) { HeroPlaceholder(SF.building2) },
            collapsedItemCount = 4,
            titleAccessory = { color -> FeedsPill(color) { DetailFeedsLink.navigate(DetailFeedsLink.Target.Studio(s.id, s.name)) } },
            footer = run {
                val link = s.url?.takeIf { it.isNotEmpty() }
                val parent = s.parentStudio
                if (link == null && parent == null) null else {
                    {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            parent?.let { PartOfLink(it) }
                            link?.let { HeaderLink(it) }
                        }
                    }
                }
            },
        )
    }

    /** "Part of <parent>" — opens the parent's studio page (like the group page's "In: …" link). */
    @Composable
    private fun PartOfLink(parent: IdName) {
        val color = de.letzgo.stashy.ui.textAccent()
        Row(
            Modifier.clickable { Nav.push(StudioDetailScreen(parent.id, Studio(id = parent.id, name = parent.name ?: ""))) },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(SF.building2, null, Modifier.size(14.dp), tint = color)
            Text(tr(R.string.arg_part_of, parent.name ?: ""), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Icon(de.letzgo.stashy.ui.SFS.chevronRight, null, Modifier.size(9.dp), tint = color)
        }
    }

    /** iOS: `EditStudioSheet`. */
    @Composable
    private fun EditStudioSheet(studio: Studio, onDismiss: () -> Unit, onSaved: (Studio) -> Unit) {
        val sections = remember(studio.id) {
            listOf(
                EditSection(tr(R.string.identity), listOf(
                    EditField(tr(R.string.name), studio.name),
                    EditField("URL", studio.url ?: "", KeyboardType.Uri),
                    EditField(tr(R.string.rating_0_100), studio.rating100?.toString() ?: "", KeyboardType.Number),
                )),
                EditSection(tr(R.string.description), listOf(EditField(tr(R.string.description), studio.details ?: "", multiline = true))),
            )
        }
        val (name, url, rating) = sections[0].fields
        val details = sections[1].fields[0]
        EditEntitySheet(
            title = tr(R.string.action_edit_studio), sections = sections,
            deleteLabel = tr(R.string.action_delete_studio), deleteTitle = tr(R.string.action_delete_studio), entityName = studio.name,
            onDismiss = onDismiss,
            onSave = {
                val r = EditParsing.rating(rating.value)
                val ok = DetailRepository.updateStudio(studio.id, name.trimmed, url.optional, details.optional, r)
                if (ok) {
                    onSaved(studio.copy(name = name.trimmed, url = url.optional, details = details.optional, rating100 = r))
                    detailToast(tr(R.string.studio_updated))
                } else detailToast(tr(R.string.error_update_studio))
                ok
            },
            onDelete = {
                DetailRepository.deleteStudio(studio.id)
                detailToast(tr(R.string.studio_deleted))
                Nav.pop()
            },
        )
    }
}
