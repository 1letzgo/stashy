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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.KeyboardType
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `GroupDetailView` (CatalogsView.swift) — sections Scenes · Galleries · Performers ·
 * Studios · Tags · Images; groups have no favorite in the Stash API, so the bar only has Edit.
 */
class GroupDetailScreen(val groupId: String, val preview: StashGroup? = null) : Screen {
    override val key = "group-$groupId"

    private val scope = screenScope()
    private var group by mutableStateOf(preview)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingSceneDownloadOptions` (`sceneBulkDownloadDialog`). */
    private var showSceneDownloadOptions by mutableStateOf(false)
    private var started = false
    private val gridState = LazyGridState()

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Performers, DetailTab.Studios, DetailTab.Tags, DetailTab.Images),
        sceneScope = DetailRepository.scope("groups", groupId),
        galleryScope = DetailRepository.scope("groups", groupId),
        performerScope = DetailRepository.scope("groups", groupId),
        studioScope = DetailRepository.scope("groups", groupId),
        tagScope = DetailRepository.scope("groups", groupId),
        imageScope = DetailRepository.scope("groups", groupId),
        sceneContext = DetailViewContext.Group,
        previewScenes = preview?.sceneCount ?: 0,
    )

    private var tab by mutableStateOf(DetailTab.Scenes)

    private fun load() {
        catalog.loadAll(force = true)
        scope.launch { runCatching { DetailRepository.group(groupId) }.getOrNull()?.let { group = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, hasTabs = catalog.available.size > 1, header = { group?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(group?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab), onEdit = { editing = true }, editLabel = "Edit group")
        }
        LinkedSettingsSheets(catalog)
        val g = group
        if (editing && g != null) EditGroupSheet(g, { editing = false }) { group = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Group(groupId), group?.name ?: "", group?.sceneCount) { showSceneDownloadOptions = false }
        }
    }

    /**
     * iOS `headerView` as a [DetailHeroCard] (like performer / tag / studio): the front cover
     * blurred as the band backdrop with the details on it, sharp in the circle on the band edge
     * (poster -> top-biased crop; tap -> fullscreen cover); name + aliases below, then the
     * the synopsis. Without a cover (or Stash's `default=true` placeholder), a tinted band and the
     * group icon in the circle.
     */
    @Composable
    private fun Header(g: StashGroup) {
        // iOS shows the loaded scene total here (`viewModel.totalGroupScenes`).
        val items = DetailFormatting.group(g, catalog.scenes?.totalCount ?: 0, catalog.effectiveGalleries).toMutableList()
        g.director?.takeIf { it.isNotBlank() }?.let { items += DetailItem("DIRECTOR", it) }
        de.letzgo.stashy.ui.components.formatDuration(g.duration?.toDouble())?.let { items += DetailItem("DURATION", it) }
        g.subGroupCount?.takeIf { it > 0 }?.let { items += DetailItem("SUB-GROUPS", "$it") }
        val thumb = groupThumbnailURL(g)?.takeIf { g.frontImagePath?.contains("default=true") != true }
        val full = g.frontImageURL
        DetailHeroCard(
            title = g.name,
            // iOS shows no aliases in the header (URLs are never shown); they appear only expanded here.
            subtitle = g.aliases?.takeIf { it.isNotBlank() && expanded },
            items = items,
            description = g.synopsis?.takeIf { it.isNotBlank() },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = if (thumb != null && full != null) {
                DetailHero(
                    DetailHero.Style.Cover, thumb, Color.Black, "Open cover", { Nav.push(HeroPictureViewerScreen(full, g.name)) },
                    backdropAlignment = HeroPortraitBias,
                ) { HeroPicture(thumb, g.name, ContentScale.Crop, rectangleStackIcon(), alignment = HeroPortraitBias) }
            } else DetailHero(DetailHero.Style.Cover, null, Color.Black, "Open cover", null) { HeroPlaceholder(rectangleStackIcon()) },
            collapsedItemCount = 4,
            footer = null,
            footerHasMore = !g.aliases.isNullOrBlank(),
        )
    }

    /** iOS: `EditGroupSheet`. */
    @Composable
    private fun EditGroupSheet(group: StashGroup, onDismiss: () -> Unit, onSaved: (StashGroup) -> Unit) {
        val sections = remember(group.id) {
            listOf(
                EditSection("Identity", listOf(
                    EditField("Name", group.name),
                    EditField("Date (YYYY-MM-DD)", group.date ?: "", KeyboardType.Ascii, isDate = true),
                    EditField("Rating (0–100)", group.rating100?.toString() ?: "", KeyboardType.Number),
                )),
                EditSection("Synopsis", listOf(EditField("Synopsis", group.synopsis ?: "", multiline = true))),
            )
        }
        val (name, date, rating) = sections[0].fields
        val synopsis = sections[1].fields[0]
        EditEntitySheet(
            title = "Edit Group", sections = sections,
            deleteLabel = "Delete Group", deleteTitle = "Delete Group", entityName = group.name,
            onDismiss = onDismiss,
            onSave = {
                val r = EditParsing.rating(rating.value)
                val ok = DetailRepository.updateGroup(group.id, name.trimmed, date.optional, synopsis.optional, r)
                if (ok) {
                    onSaved(group.copy(name = name.trimmed, date = date.optional, synopsis = synopsis.optional, rating100 = r))
                    detailToast("Group updated")
                } else detailToast("Failed to update group")
                ok
            },
            onDelete = {
                DetailRepository.deleteGroup(group.id)
                detailToast("Group deleted")
                Nav.pop()
            },
        )
    }
}

private fun rectangleStackIcon() = de.letzgo.stashy.ui.SF.rectangleStack
