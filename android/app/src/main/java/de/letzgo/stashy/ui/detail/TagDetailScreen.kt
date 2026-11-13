package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.tools.downloads.TagImagesDownloadDialog
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.LibraryEvent
import de.letzgo.stashy.data.LibraryEvents
import de.letzgo.stashy.data.SubTags
import de.letzgo.stashy.data.TagHierarchyStore
import de.letzgo.stashy.ui.filter.LocalShowsSubTagContentOption
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSectionFooter
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.NativeTextField
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
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `TagDetailView` (TagsView.swift) — sections Scenes · Galleries · Sub-Tags · Studios · Groups ·
 * Images, favorite, `EditTagSheet`.
 */
class TagDetailScreen(val tagId: String, val preview: Tag? = null, private val filterPerformerId: String? = null) : Screen {
    override val key = "tag-$tagId" + (filterPerformerId?.let { "-p$it" } ?: "")

    private val scope = screenScope()
    private var tag by mutableStateOf(preview)
    private var isFavorite by mutableStateOf(preview?.favorite ?: false)
    private var favoriteBusy by mutableStateOf(false)
    private var expanded by mutableStateOf(false)
    private var editing by mutableStateOf(false)
    /** iOS `showingSceneDownloadOptions` (`sceneBulkDownloadDialog`). */
    private var showSceneDownloadOptions by mutableStateOf(false)
    /** iOS `showingTagDownloadOptions` (the "Tag images" alert). */
    private var showTagImagesOptions by mutableStateOf(false)
    private var started = false
    private val gridState = LazyGridState()

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Tags, DetailTab.Studios, DetailTab.Groups, DetailTab.Images),
        // The depth of "Include sub-tag content" is read at query time (`tagContentId`).
        sceneScope = SubTags.tagScope(tagId, false),
        galleryScope = SubTags.tagScope(tagId, false),
        studioScope = SubTags.tagScope(tagId, false),
        groupScope = SubTags.tagScope(tagId, false),
        imageScope = SubTags.tagScope(tagId, false),
        // The direct sub-tags, by name.
        tagScope = SubTags.subTagScope(tagId),
        tagSortRaw = "nameAsc",
        tagContentId = tagId,
        sceneContext = DetailViewContext.Tag,
        previewScenes = preview?.sceneCount ?: 0,
        previewGalleries = preview?.galleryCount ?: 0,
        previewImages = preview?.imageCount ?: 0,
    )

    init { catalog.startFilteredOnPerformer(filterPerformerId) }

    private var tab by mutableStateOf(
        when {
            preview == null -> DetailTab.Scenes
            (preview.sceneCount ?: 0) > 0 -> DetailTab.Scenes
            (preview.galleryCount ?: 0) > 0 -> DetailTab.Galleries
            (preview.imageCount ?: 0) > 0 -> DetailTab.Images
            else -> DetailTab.Scenes
        },
    )

    private fun load() {
        catalog.loadAll(force = true)
        scope.launch {
            runCatching { DetailRepository.tag(tagId) }.getOrNull()?.let {
                tag = it
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
            if (!DetailRepository.setTagFavorite(tagId, new)) {
                isFavorite = !new
                detailToast(tr(R.string.error_update_favorite))
            } else tag = tag?.copy(favorite = new)
            favoriteBusy = false
        }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        // "Include sub-tag content" (any filter sheet of this page) reloads every section and the tag's counts.
        val includesContent = TagHierarchyStore.includeSubTagContent
        var seenInclude by remember { mutableStateOf(includesContent) }
        LaunchedEffect(includesContent) { if (includesContent != seenInclude) { seenInclude = includesContent; load() } }
        // A tag moved in the hierarchy (another tag's parents): this page's header links may be stale.
        LaunchedEffect(Unit) {
            LibraryEvents.events.collect { event ->
                if (event is LibraryEvent.TagParentsChanged && event.id != tagId) {
                    runCatching { DetailRepository.tag(tagId) }.getOrNull()?.let { tag = it }
                }
            }
        }
        CompositionLocalProvider(LocalShowsSubTagContentOption provides true) { Body() }
    }

    @Composable
    private fun Body() {
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, header = { tag?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                // iOS `tagImagesDownloadSlot`.
                DetailTab.Images -> listOf(imageSetDownloadSlot("tag-$tagId", tr(R.string.action_download_images)) { showTagImagesOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                tag?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab), sort = catalog.controller(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = tr(R.string.action_edit_tag),
                tabTitle = { if (it == DetailTab.Tags) tr(R.string.sub_tags) else it.title },
            )
        }
        LinkedSettingsSheets(catalog)
        val t = tag
        if (editing && t != null) EditTagSheet(t, { editing = false }) { tag = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Tag(tagId), tag?.name ?: "", tag?.sceneCount) { showSceneDownloadOptions = false }
        }
        if (showTagImagesOptions) {
            TagImagesDownloadDialog(tagId, tag?.name ?: "", tag?.imageCount) { showTagImagesOptions = false }
        }
    }

    /**
     * iOS `tagHeaderView` as a [DetailHeroCard]: the tag image blurred as the band backdrop (with
     * the details on it) and center-cropped in the circle on the band edge (tap → fullscreen); name
     * + Feeds pill and description below. Without an image (or Stash's `default=true`
     * placeholder), a tinted band and the tag icon in the circle.
     */
    @Composable
    private fun Header(t: Tag) {
        val url = t.imageURL?.takeIf { t.hasImage }
        var fullscreen by remember { mutableStateOf<HeroImageFullscreenItem?>(null) }
        fullscreen?.let { HeroImageFullscreen(it) { fullscreen = null } }
        DetailHeroCard(
            title = t.name,
            items = DetailFormatting.tag(t, catalog.effectiveScenes, catalog.effectiveGalleries),
            description = t.description?.takeIf { it.isNotEmpty() },
            expanded = expanded,
            onToggle = { expanded = !expanded },
            hero = url?.let {
                DetailHero(DetailHero.Style.Cover, it, Color.Black, tr(R.string.action_open_image), { fullscreen = HeroImageFullscreenItem(it, t.name) }) {
                    HeroPicture(it, t.name, ContentScale.Crop, SF.number)
                }
            } ?: DetailHero(DetailHero.Style.Cover, null, Color.Black, tr(R.string.action_open_image), null) { HeroPlaceholder(SF.number) },
            collapsedItemCount = 4,
            titleAccessory = { color -> FeedsPill(color) { DetailFeedsLink.navigate(DetailFeedsLink.Target.Tag(t.id, t.name)) } },
            footer = t.parents?.takeIf { it.isNotEmpty() }?.let { parents ->
                {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { parents.forEach { PartOfLink(it) } }
                }
            },
        )
    }

    /** "Part of <parent>" — one line per parent, opens that tag's page. */
    @Composable
    private fun PartOfLink(parent: IdName) {
        val color = de.letzgo.stashy.ui.textAccent()
        Row(
            Modifier.clickable { Nav.push(TagDetailScreen(parent.id, Tag(id = parent.id, name = parent.name ?: ""))) },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(SF.tag, null, Modifier.size(14.dp), tint = color)
            Text(tr(R.string.arg_part_of, parent.name ?: ""), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Icon(de.letzgo.stashy.ui.SFS.chevronRight, null, Modifier.size(9.dp), tint = color)
        }
    }

    /**
     * iOS: `EditTagSheet`. The Aliases section only appears when the tag came with its aliases
     * (`findTag`): saving an empty list over unloaded ones would delete them, so `aliases` is only
     * sent in that case.
     */
    @Composable
    private fun EditTagSheet(tag: Tag, onDismiss: () -> Unit, onSaved: (Tag) -> Unit) {
        val sections = remember(tag.id) {
            listOf(
                EditSection(tr(R.string.identity), listOf(EditField(tr(R.string.name), tag.name))),
                EditSection(tr(R.string.description), listOf(EditField(tr(R.string.description), tag.description ?: "", multiline = true))),
            )
        }
        val name = sections[0].fields[0]
        val description = sections[1].fields[0]
        val loadedAliases = tag.aliases
        var aliases by remember(tag.id) { mutableStateOf(loadedAliases.orEmpty()) }
        var newAlias by remember(tag.id) { mutableStateOf("") }
        fun addAlias() {
            aliases = EditParsing.addingAlias(aliases, newAlias, name.value)
            newAlias = ""
        }
        // The parents are written as soon as they are picked, like a scene's tags.
        var parents by remember(tag.id) { mutableStateOf(tag.parents.orEmpty()) }
        var pickingParents by remember { mutableStateOf(false) }
        if (pickingParents) {
            de.letzgo.stashy.ui.scene.EditParentTagsSheet(
                tagId = tag.id, current = parents,
                save = { ids -> if (!DetailRepository.setTagParents(tag.id, ids)) error("tagUpdate failed") },
                onDismiss = { pickingParents = false },
                onSaved = { picked ->
                    parents = picked
                    DetailRepository.tagParentsChanged(tag.id)
                    onSaved(tag.copy(parents = picked))
                },
            )
        }
        EditEntitySheet(
            title = tr(R.string.action_edit_tag), sections = sections,
            deleteLabel = tr(R.string.action_delete_tag), deleteTitle = tr(R.string.action_delete_tag), entityName = tag.name,
            onDismiss = onDismiss,
            onSave = {
                // A typed but not yet added alias counts too.
                if (newAlias.isNotBlank()) addAlias()
                val aliasesValue = if (loadedAliases == null) null else aliases
                val ok = DetailRepository.updateTag(tag.id, name.trimmed, description.optional, aliasesValue)
                if (ok) {
                    onSaved(tag.copy(name = name.trimmed, description = description.optional, aliases = aliasesValue ?: tag.aliases, parents = parents))
                    detailToast(tr(R.string.tag_updated))
                } else detailToast(tr(R.string.error_update_tag))
                ok
            },
            onDelete = {
                DetailRepository.deleteTag(tag.id)
                detailToast(tr(R.string.tag_deleted))
                Nav.pop()
            },
            extraSections = {
                Spacer(Modifier.height(20.dp))
                NativeSectionHeader(tr(R.string.parent_tags))
                NativeGroup {
                    NativeListItem(
                        parents.joinToString(", ") { it.name ?: "" }.ifEmpty { tr(R.string.none) },
                        icon = SF.tag,
                        onClick = { pickingParents = true },
                    )
                }
                if (loadedAliases != null) {
                    Spacer(Modifier.height(20.dp))
                    NativeSectionHeader(tr(R.string.aliases))
                    NativeGroup {
                        aliases.forEachIndexed { index, alias ->
                            key(alias) {
                                SwipeToRemoveAlias(alias, onRemove = { aliases = aliases - alias }) {
                                    NativeListItem(alias, Modifier.background(Theme.palette.secondaryBackground))
                                }
                            }
                            if (index < aliases.lastIndex) NativeDivider()
                        }
                        if (aliases.isNotEmpty()) NativeDivider()
                        Column(Modifier.padding(horizontal = 4.dp, vertical = 4.dp)) {
                            NativeTextField(
                                newAlias, { newAlias = it }, tr(R.string.action_add_alias),
                                imeAction = ImeAction.Done,
                                keyboardActions = KeyboardActions(onDone = { addAlias() }),
                                trailing = {
                                    IconButton(::addAlias, enabled = newAlias.isNotBlank()) {
                                        Icon(SF.plusCircleFill, tr(R.string.action_add_alias), tint = if (newAlias.isNotBlank()) Appearance.tint else Theme.palette.secondaryText)
                                    }
                                },
                            )
                        }
                    }
                    NativeSectionFooter(tr(R.string.hint_other_names_for_this_tag))
                }
            },
        )
    }
}

/** iOS `.onDelete` on the alias rows — swipe left removes the alias. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToRemoveAlias(label: String, onRemove: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) { onRemove(); true } else false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(StashyColors.systemRed).padding(end = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(SF.trash, tr(R.string.action_remove_arg, label), tint = Color.White)
            }
        },
    ) { content() }
}
