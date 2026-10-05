package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.ui.tools.downloads.TagImagesDownloadDialog
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * iOS: `TagDetailView` (TagsView.swift) — sections Scenes · Galleries · Studios · Groups ·
 * Images, favorite, `EditTagSheet`.
 */
class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"

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
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, header = { tag?.let { Header(it) } }) {
                linkedSection(catalog, tab)
            }
            DetailNavBar(
                catalog.available, tab, { tab = it },
                isFavorite = isFavorite, favoriteBusy = favoriteBusy, onFavorite = ::toggleFavorite,
                onEdit = { editing = true }, editLabel = "Edit tag",
            )
            val (slots, menu) = catalog.slots(tab)
            // iOS: the scenes tab adds `SceneBulkDownloadChrome.slot` (contextual, before filter & sort).
            val extra = when (tab) {
                DetailTab.Scenes -> listOf(sceneBulkDownloadSlot { showSceneDownloadOptions = true })
                // iOS `tagImagesDownloadSlot`.
                DetailTab.Images -> listOf(imageSetDownloadSlot("tag-$tagId", "Download images") { showTagImagesOptions = true })
                else -> emptyList()
            }
            DetailSlotBar(slots + extra, menu)
        }
        val t = tag
        if (editing && t != null) EditTagSheet(t, { editing = false }) { tag = it }
        if (showSceneDownloadOptions) {
            SceneBulkDownloadDialog(Downloads.SceneDownloadScope.Tag(tagId), tag?.name ?: "") { showSceneDownloadOptions = false }
        }
        if (showTagImagesOptions) {
            TagImagesDownloadDialog(tagId, tag?.name ?: "") { showTagImagesOptions = false }
        }
    }

    /** iOS `tagHeaderView`. */
    @Composable
    private fun Header(t: Tag) {
        val items = DetailFormatting.tag(t, catalog.effectiveScenes, catalog.effectiveGalleries)
        val desc = t.description?.takeIf { it.isNotEmpty() }
        DetailHeaderCard(
            title = t.name,
            imageUrl = null,
            placeholderIcon = SF.number,
            items = items,
            expandable = items.size > 4 || desc != null,
            expanded = expanded,
            onToggle = { expanded = !expanded },
            imageContent = { TagImage(t, Modifier.fillMaxSize()) },
            onFeeds = { DetailFeedsLink.navigate(DetailFeedsLink.Target.Tag(t.id, t.name)) },
            expandedContent = desc?.let { d -> { Text(d, fontSize = 11.sp, color = Theme.palette.secondaryText, modifier = Modifier.padding(top = 4.dp)) } },
        )
    }

    /** iOS: `EditTagSheet`. */
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
        EditEntitySheet(
            title = "Edit Tag", sections = sections,
            deleteLabel = "Delete Tag", deleteTitle = "Delete Tag", entityName = tag.name,
            onDismiss = onDismiss,
            onSave = {
                val ok = DetailRepository.updateTag(tag.id, name.trimmed, description.optional)
                if (ok) {
                    onSaved(tag.copy(name = name.trimmed, description = description.optional))
                    detailToast("Tag updated")
                } else detailToast("Failed to update tag")
                ok
            },
            onDelete = {
                DetailRepository.deleteTag(tag.id)
                detailToast("Tag deleted")
                Nav.pop()
            },
        )
    }
}
