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
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.PerformerEdit
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

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
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingSceneDownloadOptions` (`sceneBulkDownloadDialog`). */
    private var showSceneDownloadOptions by mutableStateOf(false)
    private var started = false
    private val gridState = LazyGridState()

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Studios, DetailTab.Tags, DetailTab.Groups, DetailTab.Images),
        sceneScope = DetailRepository.scope("performers", performerId),
        galleryScope = DetailRepository.scope("performers", performerId),
        studioScope = DetailRepository.scope("performers", performerId),
        tagScope = DetailRepository.scope("performers", performerId),
        groupScope = DetailRepository.scope("performers", performerId),
        imageScope = DetailRepository.scope("performers", performerId),
        sceneContext = DetailViewContext.Performer,
        previewScenes = preview?.sceneCount ?: 0,
        previewGalleries = preview?.galleryCount ?: 0,
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

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        // iOS: `.task(id: displayPerformer.id)` → `HotOrNotBattleDisplay.fetchRankSlashTotal`.
        LaunchedEffect(performerId) { battleLine = MatchRepository.fetchRankSlashTotal(performerId) }
        if (initialTab == null) AutoSwitchTab(catalog, tab) { tab = it }
        val p = performer

        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, hasTabs = catalog.available.size > 1, header = { Header(p) }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                p?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit performer",
            )
        }

        LinkedSettingsSheets(catalog)
        if (editing && p != null) EditPerformerSheet(p, onDismiss = { editing = false }, onSaved = { performer = it })
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Performer(performerId), performer?.name ?: "", performer?.sceneCount) { showSceneDownloadOptions = false }
        }
    }

    @Composable
    private fun Header(p: Performer?) {
        val name = p?.name ?: ""
        val items = p?.let { DetailFormatting.performer(it, catalog.galleries?.totalCount ?: 0, battleLine) } ?: emptyList()
        DetailHeaderCard(
            title = name,
            imageUrl = p?.let { performerThumbnailURL(it.id, it.imagePath) },
            placeholderIcon = SF.personFill,
            items = items,
            expandable = items.size > 4,
            expanded = expanded,
            onToggle = { expanded = !expanded },
            onFeeds = p?.let { { DetailFeedsLink.navigate(DetailFeedsLink.Target.Performer(it.id, it.name)) } },
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
