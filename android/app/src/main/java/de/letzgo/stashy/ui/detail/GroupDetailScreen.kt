package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
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
            val (slots, menu) = catalog.slots(tab)
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(group?.name ?: "", catalog.available, tab, { tab = it }, slots + extra, menu, onEdit = { editing = true }, editLabel = "Edit group")
        }
        val g = group
        if (editing && g != null) EditGroupSheet(g, { editing = false }) { group = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Group(groupId), group?.name ?: "") { showSceneDownloadOptions = false }
        }
    }

    /** iOS `headerView`. */
    @Composable
    private fun Header(g: StashGroup) {
        // iOS shows the loaded scene total here (`viewModel.totalGroupScenes`).
        val items = DetailFormatting.group(g, catalog.scenes?.totalCount ?: 0, catalog.effectiveGalleries)
        val synopsis = g.synopsis?.takeIf { it.isNotEmpty() }
        DetailHeaderCard(
            title = g.name,
            imageUrl = groupThumbnailURL(g),
            placeholderIcon = rectangleStackIcon(),
            items = items,
            expandable = items.size > 4 || synopsis != null,
            expanded = expanded,
            onToggle = { expanded = !expanded },
            titleMaxLines = 2,
            expandedContent = synopsis?.let { s ->
                {
                    Text("SYNOPSIS", fontSize = 8.sp, color = Theme.palette.secondaryText, modifier = Modifier.padding(top = 4.dp))
                    Text(s, fontSize = 11.sp, color = Theme.palette.text)
                }
            },
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
