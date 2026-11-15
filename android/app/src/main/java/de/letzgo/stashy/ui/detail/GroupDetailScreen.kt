package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.ContainingGroupEntry
import de.letzgo.stashy.data.GroupStub
import de.letzgo.stashy.data.LibraryEvent
import de.letzgo.stashy.data.LibraryEvents
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.ui.Alignment
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSectionFooter
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.scene.EntityPickerSheet
import de.letzgo.stashy.ui.scene.PickerEntry
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
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Groups, DetailTab.Performers, DetailTab.Studios, DetailTab.Tags, DetailTab.Images),
        sceneScope = DetailRepository.scope("groups", groupId),
        galleryScope = DetailRepository.scope("groups", groupId),
        performerScope = DetailRepository.scope("groups", groupId),
        studioScope = DetailRepository.scope("groups", groupId),
        tagScope = DetailRepository.scope("groups", groupId),
        imageScope = DetailRepository.scope("groups", groupId),
        // Direct sub-groups: the Groups section exists only when there is at least one.
        groupScope = DetailRepository.subGroupScope(groupId),
        sceneExtraSorts = de.letzgo.stashy.data.GroupSceneSort.options,
        sceneContext = DetailViewContext.Group,
        previewScenes = preview?.sceneCount ?: 0,
    )

    private var tab by mutableStateOf(DetailTab.Scenes)
    private var parents by mutableStateOf<List<GroupStub>>(emptyList())

    private fun load() {
        catalog.loadAll(force = true)
        scope.launch { runCatching { DetailRepository.group(groupId) }.getOrNull()?.let { group = it } }
        scope.launch { runCatching { DetailRepository.containingGroups(groupId) }.getOrNull()?.let { parents = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        // Another group moved into or out of this one (or this one's parents changed elsewhere):
        // header counts, "In: …" and the Groups section reload. The edited group itself takes
        // the result from its sheet.
        LaunchedEffect(Unit) {
            LibraryEvents.events.collect { event ->
                if (event is LibraryEvent.GroupHierarchyChanged && event.id != groupId) load()
            }
        }
        AutoSwitchTab(catalog, tab) { tab = it }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, header = { group?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                else -> emptyList()
            }
            DetailTopBar(group?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab), sort = catalog.controller(tab), onEdit = { editing = true }, editLabel = tr(R.string.action_edit_group))
        }
        LinkedSettingsSheets(catalog)
        val g = group
        if (editing && g != null) EditGroupSheet(g, { editing = false }, onParentsSaved = { parents = it }) { group = it }
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
        g.director?.takeIf { it.isNotBlank() }?.let { items += DetailItem(tr(R.string.director), it) }
        de.letzgo.stashy.ui.components.formatDuration(g.duration?.toDouble())?.let { items += DetailItem(tr(R.string.duration), it) }
        g.subGroupCount?.takeIf { it > 0 }?.let { items += DetailItem("SUB-GROUPS", "$it") }
        val thumb = groupThumbnailURL(g)?.takeIf { g.frontImagePath?.contains("default=true") != true }
        val full = g.frontImageURL
        var fullscreen by remember { mutableStateOf<HeroImageFullscreenItem?>(null) }
        fullscreen?.let { HeroImageFullscreen(it) { fullscreen = null } }
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
                    DetailHero.Style.Cover, thumb, Color.Black, tr(R.string.action_open_cover), { fullscreen = HeroImageFullscreenItem(full, g.name) },
                    backdropAlignment = HeroPortraitBias,
                ) { HeroPicture(thumb, g.name, ContentScale.Crop, rectangleStackIcon(), alignment = HeroPortraitBias) }
            } else DetailHero(DetailHero.Style.Cover, null, Color.Black, tr(R.string.action_open_cover), null) { HeroPlaceholder(rectangleStackIcon()) },
            collapsedItemCount = 4,
            footer = parents.takeIf { it.isNotEmpty() }?.let { list ->
                { ParentGroupLinks(list) }
            },
            footerHasMore = !g.aliases.isNullOrBlank(),
        )
    }

    /** "In: <parent>" — one tappable row per containing group, opening that group's detail. */
    @Composable
    private fun ParentGroupLinks(list: List<GroupStub>) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(tr(R.string.in_label), fontSize = 11.sp, color = Theme.palette.secondaryText)
            list.forEach { parent ->
                Text(
                    parent.name, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = de.letzgo.stashy.ui.textAccent(),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.clickable { Nav.push(GroupDetailScreen(parent.id)) },
                )
            }
        }
    }

    /**
     * iOS: `EditGroupSheet`. "Containing Groups" (the groups this one sits in, each with an
     * optional description) is sent only once it was loaded, so a failed load never clears it.
     */
    @Composable
    private fun EditGroupSheet(group: StashGroup, onDismiss: () -> Unit, onParentsSaved: (List<GroupStub>) -> Unit, onSaved: (StashGroup) -> Unit) {
        val sections = remember(group.id) {
            listOf(
                EditSection(tr(R.string.identity), listOf(
                    EditField(tr(R.string.name), group.name),
                    EditField(tr(R.string.date_yyyy_mm_dd), group.date ?: "", KeyboardType.Ascii, isDate = true),
                    EditField(tr(R.string.rating_0_100), group.rating100?.toString() ?: "", KeyboardType.Number),
                )),
                EditSection(tr(R.string.synopsis), listOf(EditField(tr(R.string.synopsis), group.synopsis ?: "", multiline = true))),
            )
        }
        val (name, date, rating) = sections[0].fields
        val synopsis = sections[1].fields[0]
        // Null until loaded; the descriptions are edited in place.
        var loadedParents by remember(group.id) { mutableStateOf<List<ContainingGroupEntry>?>(null) }
        var parentEntries by remember(group.id) { mutableStateOf<List<ContainingGroupEntry>>(emptyList()) }
        // The group itself and everything below it may not contain it.
        var excludedParentIds by remember(group.id) { mutableStateOf(setOf(group.id)) }
        var pickingParents by remember { mutableStateOf(false) }
        LaunchedEffect(group.id) {
            runCatching { DetailRepository.containingGroupEntries(group.id) }
                .onSuccess { loadedParents = it; parentEntries = it }
                .onFailure { detailToast(tr(R.string.error_load_all_group_fields)) }
        }
        LaunchedEffect(group.id) {
            // Unknown descendants: the server refuses a loop anyway, so the picker stays usable.
            runCatching { DetailRepository.descendantGroupIds(group.id) }.onSuccess { excludedParentIds = it + group.id }
        }
        if (pickingParents) {
            EntityPickerSheet(
                tr(R.string.containing_groups), tr(R.string.search_groups), parentEntries.map { it.group.id }.toSet(), multiple = true,
                showsAll = true, allowsCreate = false, actionTitle = tr(R.string.action_done),
                load = {
                    DetailRepository.allGroupsByName().filter { it.id !in excludedParentIds }.map { g ->
                        val n = g.subGroupCount ?: 0
                        PickerEntry(g.id, g.name, if (n > 0) tr(if (n == 1) R.string.arg_count_sub_group else R.string.arg_count_sub_groups, n) else null)
                    }
                },
                create = { error("not offered") }, createFailedText = tr(R.string.error_create_group),
                // Nothing is written here: the sheet's Save sends the list with the other fields.
                save = {}, saveFailedText = tr(R.string.error_update_group),
                onSaved = { picked ->
                    // Kept entries keep their description; new ones follow in the picked order.
                    val kept = parentEntries.filter { e -> picked.any { it.id == e.group.id } }
                    val added = picked.filter { p -> kept.none { it.group.id == p.id } }.map { ContainingGroupEntry(GroupStub(it.id, it.name), null) }
                    parentEntries = kept + added
                },
                onDismiss = { pickingParents = false },
            )
        }
        EditEntitySheet(
            title = tr(R.string.action_edit_group), sections = sections,
            deleteLabel = tr(R.string.action_delete_group), deleteTitle = tr(R.string.action_delete_group), entityName = group.name,
            onDismiss = onDismiss,
            onSave = {
                val r = EditParsing.rating(rating.value)
                val sentParents = if (loadedParents != null) parentEntries else null
                val ok = DetailRepository.updateGroup(group.id, name.trimmed, date.optional, synopsis.optional, r, sentParents)
                if (ok) {
                    // Compared as sent (trimmed descriptions), so a stray space is no move.
                    fun sig(list: List<ContainingGroupEntry>?) = list?.map { it.group.id to it.description?.trim().orEmpty() }
                    if (sentParents != null && sig(sentParents) != sig(loadedParents)) {
                        onParentsSaved(sentParents.map { it.group })
                        DetailRepository.groupHierarchyChanged(group.id)
                    }
                    onSaved(group.copy(name = name.trimmed, date = date.optional, synopsis = synopsis.optional, rating100 = r))
                    detailToast(tr(R.string.group_updated))
                } else detailToast(tr(R.string.error_update_group))
                ok
            },
            onDelete = {
                DetailRepository.deleteGroup(group.id)
                detailToast(tr(R.string.group_deleted))
                Nav.pop()
            },
            extraSections = {
                if (loadedParents != null) {
                    Spacer(Modifier.height(20.dp))
                    NativeSectionHeader(tr(R.string.containing_groups))
                    NativeGroup {
                        parentEntries.forEach { entry ->
                            Column(Modifier.padding(horizontal = 4.dp, vertical = 4.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    NativeListItem(entry.group.name, Modifier.weight(1f), icon = SF.rectangleStack)
                                    IconButton({ parentEntries = parentEntries.filter { it.group.id != entry.group.id } }) {
                                        Icon(SFS.minusCircleFill, tr(R.string.action_remove_arg, entry.group.name), tint = StashyColors.systemRed)
                                    }
                                }
                                NativeTextField(
                                    entry.description.orEmpty(),
                                    { text -> parentEntries = parentEntries.map { if (it.group.id == entry.group.id) it.copy(description = text) else it } },
                                    tr(R.string.description),
                                    autoCorrect = true,
                                )
                            }
                            NativeDivider()
                        }
                        NativeListItem(tr(R.string.action_add_group), icon = SF.plusCircleFill, onClick = { pickingParents = true })
                    }
                    NativeSectionFooter(tr(R.string.hint_containing_groups))
                }
            },
        )
    }
}

private fun rectangleStackIcon() = de.letzgo.stashy.ui.SF.rectangleStack
