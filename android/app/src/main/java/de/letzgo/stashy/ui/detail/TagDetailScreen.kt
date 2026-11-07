package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.ui.tools.downloads.TagImagesDownloadDialog
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.SceneBulkDownloadDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
 * iOS: `TagDetailView` (TagsView.swift) — sections Scenes · Galleries · Studios · Groups ·
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
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Studios, DetailTab.Groups, DetailTab.Images),
        sceneScope = DetailRepository.scope("tags", tagId),
        galleryScope = DetailRepository.scope("tags", tagId),
        studioScope = DetailRepository.scope("tags", tagId),
        groupScope = DetailRepository.scope("tags", tagId),
        imageScope = DetailRepository.scope("tags", tagId),
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
                detailToast("Failed to update favorite")
            } else tag = tag?.copy(favorite = new)
            favoriteBusy = false
        }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, hasTabs = catalog.available.size > 1, header = { tag?.let { Header(it) } }) {
                linkedSection(catalog, tab, gridState)
            }
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                // iOS `tagImagesDownloadSlot`.
                DetailTab.Images -> listOf(imageSetDownloadSlot("tag-$tagId", "Download images") { showTagImagesOptions = true })
                else -> emptyList()
            }
            DetailTopBar(
                tag?.name ?: "", catalog.available, tab, { tab = it }, extra,
                settings = catalog.settingsSlot(tab),
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit tag",
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
                DetailHero(DetailHero.Style.Cover, it, Color.Black, "Open image", { fullscreen = HeroImageFullscreenItem(it, t.name) }) {
                    HeroPicture(it, t.name, ContentScale.Crop, SF.number)
                }
            } ?: DetailHero(DetailHero.Style.Cover, null, Color.Black, "Open image", null) { HeroPlaceholder(SF.number) },
            collapsedItemCount = 4,
            titleAccessory = { color -> FeedsPill(color) { DetailFeedsLink.navigate(DetailFeedsLink.Target.Tag(t.id, t.name)) } },
        )
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
                EditSection("Identity", listOf(EditField("Name", tag.name))),
                EditSection("Description", listOf(EditField("Description", tag.description ?: "", multiline = true))),
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
        EditEntitySheet(
            title = "Edit Tag", sections = sections,
            deleteLabel = "Delete Tag", deleteTitle = "Delete Tag", entityName = tag.name,
            onDismiss = onDismiss,
            onSave = {
                // A typed but not yet added alias counts too.
                if (newAlias.isNotBlank()) addAlias()
                val aliasesValue = if (loadedAliases == null) null else aliases
                val ok = DetailRepository.updateTag(tag.id, name.trimmed, description.optional, aliasesValue)
                if (ok) {
                    onSaved(tag.copy(name = name.trimmed, description = description.optional, aliases = aliasesValue ?: tag.aliases))
                    detailToast("Tag updated")
                } else detailToast("Failed to update tag")
                ok
            },
            onDelete = {
                DetailRepository.deleteTag(tag.id)
                detailToast("Tag deleted")
                Nav.pop()
            },
            extraSections = {
                if (loadedAliases != null) {
                    Spacer(Modifier.height(20.dp))
                    NativeSectionHeader("Aliases")
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
                                newAlias, { newAlias = it }, "Add alias",
                                imeAction = ImeAction.Done,
                                keyboardActions = KeyboardActions(onDone = { addAlias() }),
                                trailing = {
                                    IconButton(::addAlias, enabled = newAlias.isNotBlank()) {
                                        Icon(SF.plusCircleFill, "Add alias", tint = if (newAlias.isNotBlank()) Appearance.tint else Theme.palette.secondaryText)
                                    }
                                },
                            )
                        }
                    }
                    NativeSectionFooter("Other names for this tag. Swipe left to remove one.")
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
                Icon(SF.trash, "Remove $label", tint = Color.White)
            }
        },
    ) { content() }
}
