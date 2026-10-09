package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.tools.MatchRepository
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.PerformerEdit
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.ui.Alignment
import de.letzgo.stashy.data.CoPerformersRepository
import de.letzgo.stashy.ui.scene.ScenePerformerTile
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyRow
import de.letzgo.stashy.data.CoPerformerLogic
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.filterSortSlot
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.uniqueItems
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CoPerformer
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.scene.SceneCardContainer
import de.letzgo.stashy.ui.scene.SceneCardEmpty
import de.letzgo.stashy.ui.scene.SceneCardHeader

/**
 * iOS: `PerformerDetailView` — custom chrome bar (Back · sections · Favorite · Edit), header
 * card with portrait strip and the performer facts, then Scenes / Galleries / Studios / Tags /
 * Groups / Images. [preview] is the list item shown until the full performer has loaded.
 * [initialTab] (iOS `initialTab`, e.g. Images from the image feed / Feeds Clips & Pics) opens
 * that section and turns the empty-section auto-switch off, like iOS `preferredInitialTab`.
 */
class PerformerDetailScreen(val performerId: String, val preview: Performer? = null, val initialTab: DetailTab? = null) : Screen {
    override val key = "performer-$performerId"

    private val scope = screenScope()
    private var performer by mutableStateOf(preview)
    private var isFavorite by mutableStateOf(preview?.favorite ?: false)
    private var favoriteBusy by mutableStateOf(false)
    /** iOS `hotOrNotBattleLine` — "rank/total" in the Match pool, null when not listed. */
    private var battleLine by mutableStateOf<String?>(null)
    /** `details` + `urls` (not in the list fragment), loaded with the performer. */
    private var profile by mutableStateOf<de.letzgo.stashy.data.PerformerProfile?>(null)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingSceneDownloadOptions` (`sceneBulkDownloadDialog`). */
    private var showSceneDownloadOptions by mutableStateOf(false)
    private var started = false
    private val gridState = LazyGridState()

    /** "Appears with" (performers sharing scenes), loaded the first time the tab opens; session cache. */
    private var coPerformers by mutableStateOf(CoPerformersRepository.cached(performerId))
    private var coLoading by mutableStateOf(false)
    private var coFailed by mutableStateOf(false)

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Studios, DetailTab.Tags, DetailTab.Groups, DetailTab.Images, DetailTab.AppearsWith),
        sceneScope = DetailRepository.scope("performers", performerId),
        galleryScope = DetailRepository.scope("performers", performerId),
        studioScope = DetailRepository.scope("performers", performerId),
        tagScope = DetailRepository.scope("performers", performerId),
        groupScope = DetailRepository.scope("performers", performerId),
        imageScope = DetailRepository.scope("performers", performerId),
        sceneContext = DetailViewContext.Performer,
        previewScenes = preview?.sceneCount ?: 0,
        previewGalleries = preview?.galleryCount ?: 0,
        // "Appears with" only for a performer with at least one scene.
        screenCount = { tab -> if (tab == DetailTab.AppearsWith && (performer?.sceneCount ?: 0) > 0) 1 else 0 },
    )

    // iOS init: no scene signal → open Galleries instead of an empty Scenes stack.
    private var tab by mutableStateOf(initialTab ?: if ((preview?.sceneCount ?: 1) > 0) DetailTab.Scenes else DetailTab.Galleries)

    init {
        // iOS `PerformerDetailView.onReceive(PerformerImageUpdated)` — the header shows the new picture.
        scope.launch {
            de.letzgo.stashy.data.PerformerEvents.events.collect { event ->
                performer?.let { p -> event.applyTo(p).takeIf { it != p }?.let { performer = it } }
            }
        }
    }

    private fun load() {
        catalog.loadAll(force = true)
        scope.launch {
            runCatching { DetailRepository.performer(performerId) }.getOrNull()?.let {
                performer = it
                isFavorite = it.favorite ?: false
            }
        }
        scope.launch { DetailRepository.performerProfile(performerId)?.let { profile = it } }
    }

    private fun loadCoPerformers(force: Boolean) {
        if (coLoading || (!force && coPerformers != null)) return
        coLoading = true
        coFailed = false
        scope.launch {
            runCatching { CoPerformersRepository.load(performerId, force) }
                .onSuccess { coPerformers = it }
                .onFailure { if (it is kotlinx.coroutines.CancellationException) throw it; coFailed = true }
            coLoading = false
        }
    }

    /**
     * Co-performer selected in the "Appears with" card (default: the first, i.e. most shared
     * scenes) and the list of the scenes both share, shown below the card.
     */
    private var selectedCoId by mutableStateOf<String?>(null)
    private var sharedScenes by mutableStateOf<CatalogController<Scene>?>(null)

    private fun selectCoPerformer(otherId: String) {
        if (otherId == selectedCoId && sharedScenes != null) return
        val previousSort = sharedScenes?.sort ?: catalog.sceneController?.sort
        selectedCoId = otherId
        sharedScenes = CatalogController<Scene>(
            FilterMode.Scenes, scope,
            tabId = null,
            scope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
            initialSort = previousSort,
            persistSort = {},
            perPage = 20,
            fetch = { q, page, per -> DetailRepository.findScoped(q, page, per) },
        ).also { it.onAppear() }
    }

    /**
     * "Appears with" tab: one full-width card in the scene detail "Performers & Studio" style
     * (title, every co-performer in one horizontal row with the shared-scene count as badge), then
     * the scenes shared with the selected one. Tap selects; long-press → "Open performer".
     */
    private fun LazyGridScope.appearsWithSection() {
        val list = coPerformers
        item(key = "appears-with", span = { GridItemSpan(maxLineSpan) }) {
            SceneCardContainer(Modifier.fillMaxWidth()) {
                SceneCardHeader("Appears with", onEdit = null)
                when {
                    list == null && coFailed -> InlineEmptyState(SF.exclamationTriangle, "Couldn't load performers")
                    list == null -> LoadingFooter("Loading performers...")
                    list.isEmpty() -> Box(Modifier.padding(top = 8.dp)) { SceneCardEmpty("No shared scenes") }
                    else -> LazyRow(
                        Modifier.padding(top = 8.dp, bottom = 12.dp),
                        contentPadding = PaddingValues(horizontal = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        uniqueItems(list, { "co-${it.performer.id}" }) { co -> CoPerformerTile(co) }
                    }
                }
            }
        }
        val shared = sharedScenes
        if (!list.isNullOrEmpty() && shared != null) {
            pagedSection(shared.list, { "shared-${it.id}" }, null, SF.film, "No shared scenes") { _, s ->
                SceneCard(s, onClick = { Nav.push(SceneDetailScreen(s.id, s)) })
            }
        }
    }

    @Composable
    private fun CoPerformerTile(co: CoPerformer) {
        var menu by remember { mutableStateOf(false) }
        val other = co.performer
        Box {
            ScenePerformerTile(
                other, "${co.sharedScenes}", selected = other.id == selectedCoId,
                onLongClick = { menu = true },
            ) { selectCoPerformer(other.id) }
            DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = Theme.palette.secondaryBackground) {
                OverflowItem("Open performer", SF.personFill, { menu = false }) { Nav.push(PerformerDetailScreen(other.id, other)) }
            }
        }
    }

    private fun toggleFavorite() {
        if (favoriteBusy) return
        favoriteBusy = true
        val new = !isFavorite
        isFavorite = new
        scope.launch {
            if (!DetailRepository.setPerformerFavorite(performerId, new)) {
                isFavorite = !new
                detailToast("Failed to update favorite")
            }
            favoriteBusy = false
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        // iOS: `.task(id: displayPerformer.id)` → `HotOrNotBattleDisplay.fetchRankSlashTotal`.
        LaunchedEffect(performerId) { battleLine = MatchRepository.fetchRankSlashTotal(performerId) }
        if (initialTab == null) AutoSwitchTab(catalog, tab) { tab = it }
        LaunchedEffect(tab) { if (tab == DetailTab.AppearsWith) loadCoPerformers(force = false) }
        // Preselect the co-performer with the most shared scenes; reselect when a refresh drops the current one.
        LaunchedEffect(tab, coPerformers) {
            val list = coPerformers
            if (tab == DetailTab.AppearsWith && !list.isNullOrEmpty() && list.none { it.performer.id == selectedCoId }) {
                selectCoPerformer(list.first().performer.id)
            }
        }
        val p = performer
        val hasTabs = catalog.available.size > 1
        // Pull-to-refresh only on "Appears with" (the catalog tabs keep their behavior).
        val pullState = rememberPullToRefreshState()
        val appearsWith = tab == DetailTab.AppearsWith

        Box(
            Modifier.fillMaxSize().background(Theme.palette.background)
                .pullToRefresh(coLoading && coPerformers != null, pullState, enabled = appearsWith) { loadCoPerformers(force = true); sharedScenes?.refresh() },
        ) {
            // "Appears with" lays its shared scenes out like the Scenes tab.
            DetailGrid(gridState, { w -> columnsFor(if (appearsWith) DetailTab.Scenes else tab, w, catalog.imageColumns) }, hasTabs = hasTabs, header = { Header(p) }) {
                if (appearsWith) appearsWithSection() else linkedSection(catalog, tab, gridState)
            }
            if (appearsWith) {
                PullToRefreshDefaults.Indicator(
                    state = pullState, isRefreshing = coLoading && coPerformers != null,
                    modifier = Modifier.align(Alignment.TopCenter).padding(top = detailTopPadding(hasTabs)),
                )
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                p?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = if (appearsWith) sharedScenes?.let { filterSortSlot(it) } else catalog.settingsSlot(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit performer",
            )
        }

        LinkedSettingsSheets(catalog)
        sharedScenes?.let { CatalogFilterSortSheet(it) }
        if (editing && p != null) EditPerformerSheet(p, onDismiss = { editing = false }, onSaved = { performer = it })
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Performer(performerId), performer?.name ?: "", performer?.sceneCount) { showSceneDownloadOptions = false }
        }
    }

    /**
     * Header as a [DetailHeroCard] (like tag / studio / gallery): the portrait blurred as the band
     * backdrop with the facts on it, sharp in the circle on the band edge (top-biased crop so the
     * face shows; tap → fullscreen); name + disambiguation + Feeds pill below, then the
     * the details text. The image URL follows [Performer.imagePath], so an image changed via
     * [de.letzgo.stashy.data.PerformerEvents] updates band and circle.
     */
    @Composable
    private fun Header(p: Performer?) {
        val name = p?.name ?: ""
        val items = p?.let { DetailFormatting.performer(it, catalog.galleries?.totalCount ?: 0, battleLine) } ?: emptyList()
        val url = p?.let { performerThumbnailURL(it.id, it.imagePath) }
        val disambiguation = p?.disambiguation?.takeIf { it.isNotBlank() }
        val details = profile?.details?.takeIf { it.isNotBlank() }
        DetailHeroCard(
            title = name,
            // iOS shows no disambiguation / details in the header (URLs are never shown); they appear only expanded here.
            subtitle = disambiguation.takeIf { expanded },
            items = items,
            description = details.takeIf { expanded },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = url?.let {
                DetailHero(
                    DetailHero.Style.Cover, it, Color.Black, "Open image", { Nav.push(HeroPictureViewerScreen(it, name)) },
                    backdropAlignment = HeroPortraitBias,
                ) { HeroPicture(it, name, ContentScale.Crop, SF.personFill, alignment = HeroPortraitBias) }
            } ?: DetailHero(DetailHero.Style.Cover, null, Color.Black, "Open image", null) { HeroPlaceholder(SF.personFill) },
            // iOS: two full rows of the 4-column grid.
            collapsedItemCount = 8,
            titleAccessory = p?.let { perf -> { color -> FeedsPill(color) { DetailFeedsLink.navigate(DetailFeedsLink.Target.Performer(perf.id, perf.name)) } } },
            footer = null,
            footerHasMore = disambiguation != null || details != null,
        )
    }

    /** iOS: `EditPerformerSheet`. */
    @Composable
    private fun EditPerformerSheet(performer: Performer, onDismiss: () -> Unit, onSaved: (Performer) -> Unit) {
        val fields = androidx.compose.runtime.remember(performer.id) {
            listOf(
                EditSection("Identity", listOf(
                    EditField("Name", performer.name),
                    EditField("Disambiguation", performer.disambiguation ?: ""),
                    EditField("Aliases (comma-separated)", performer.aliasList.orEmpty().joinToString(", ")),
                    EditField("Gender", performer.gender ?: ""),
                    EditField("Birthdate (YYYY-MM-DD)", performer.birthdate ?: "", isDate = true),
                    EditField("Country", performer.country ?: ""),
                    EditField("Ethnicity", performer.ethnicity ?: ""),
                )),
                EditSection("Body", listOf(
                    EditField("Height (cm)", performer.heightCm?.toString() ?: "", KeyboardType.Number),
                    EditField("Weight (kg)", performer.weight?.toString() ?: "", KeyboardType.Number),
                    EditField("Measurements", performer.measurements ?: ""),
                    EditField("Fake tits", performer.fakeTits ?: ""),
                    EditField("Penis length (cm)", performer.penisLength?.toString() ?: "", KeyboardType.Decimal),
                )),
                EditSection("Other", listOf(
                    EditField("Career length", performer.careerLength ?: ""),
                    EditField("Tattoos", performer.tattoos ?: ""),
                    EditField("Piercings", performer.piercings ?: ""),
                    EditField("Rating (0–100)", performer.rating100?.toString() ?: "", KeyboardType.Number),
                )),
            )
        }
        val f = fields.flatMap { it.fields }.associateBy { it.label }
        EditEntitySheet(
            title = "Edit Performer", sections = fields,
            deleteLabel = "Delete Performer", deleteTitle = "Delete Performer", entityName = performer.name,
            onDismiss = onDismiss,
            onSave = {
                val edit = PerformerEdit(
                    name = f.getValue("Name").trimmed,
                    disambiguation = f.getValue("Disambiguation").optional,
                    birthdate = f.getValue("Birthdate (YYYY-MM-DD)").optional,
                    country = f.getValue("Country").optional,
                    gender = f.getValue("Gender").optional,
                    ethnicity = f.getValue("Ethnicity").optional,
                    heightCm = EditParsing.int(f.getValue("Height (cm)").value),
                    weight = EditParsing.int(f.getValue("Weight (kg)").value),
                    measurements = f.getValue("Measurements").optional,
                    fakeTits = f.getValue("Fake tits").optional,
                    penisLength = EditParsing.decimal(f.getValue("Penis length (cm)").value),
                    careerLength = f.getValue("Career length").optional,
                    tattoos = f.getValue("Tattoos").optional,
                    piercings = f.getValue("Piercings").optional,
                    aliasList = EditParsing.aliases(f.getValue("Aliases (comma-separated)").value),
                    rating100 = EditParsing.rating(f.getValue("Rating (0–100)").value),
                )
                val ok = DetailRepository.updatePerformer(performer.id, edit)
                if (ok) {
                    onSaved(performer.copy(
                        name = edit.name, disambiguation = edit.disambiguation, birthdate = edit.birthdate, country = edit.country,
                        gender = edit.gender, ethnicity = edit.ethnicity, heightCm = edit.heightCm, weight = edit.weight,
                        measurements = edit.measurements, fakeTits = edit.fakeTits, penisLength = edit.penisLength,
                        careerLength = edit.careerLength, tattoos = edit.tattoos, piercings = edit.piercings,
                        aliasList = edit.aliasList, rating100 = edit.rating100,
                    ))
                    detailToast("Performer updated")
                } else detailToast("Failed to update performer")
                ok
            },
            onDelete = {
                DetailRepository.deletePerformer(performer.id)
                detailToast("Performer deleted")
                Nav.pop()
            },
        )
    }
}
