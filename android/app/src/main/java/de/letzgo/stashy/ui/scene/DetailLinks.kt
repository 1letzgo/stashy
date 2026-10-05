package de.letzgo.stashy.ui.scene

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.GroupStub
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SceneGalleryStub
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.detail.GalleryDetailScreen
import de.letzgo.stashy.ui.detail.GroupDetailScreen
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.detail.StudioDetailScreen
import de.letzgo.stashy.ui.detail.TagDetailScreen

/** Where the scene detail cards navigate (iOS `NavigationLink`s of the scene cards). */
internal object DetailLinks {
    // Downloaded scenes carry performers / studios / tags without ids (offline metadata): no
    // detail screen to open for those, so the tap does nothing.

    /** iOS: `PerformerDetailView(performer:)`. */
    fun performer(performer: Performer) { if (performer.id.isNotEmpty()) Nav.push(PerformerDetailScreen(performer.id, performer)) }
    /** iOS: `DirectorDetailView(director:)` — no Android screen yet, placeholder. */
    fun director(name: String) = Nav.push(PendingLinkScreen("director-$name", name))
    /** iOS: `StudioDetailView(studio:)`. */
    fun studio(studio: Studio) { if (studio.id.isNotEmpty()) Nav.push(StudioDetailScreen(studio.id, studio)) }
    /** iOS: `TagDetailView(selectedTag:)`. */
    fun tag(tag: Tag) { if (tag.id.isNotEmpty()) Nav.push(TagDetailScreen(tag.id, tag)) }
    /** iOS: `GroupDetailView(selectedGroup:)`. */
    fun group(group: GroupStub) = Nav.push(
        GroupDetailScreen(group.id, StashGroup(id = group.id, name = group.name, frontImagePath = group.frontImagePath, updatedAt = group.updatedAt)),
    )
    /** iOS: `ImagesView(gallery:)`. */
    fun gallery(g: SceneGalleryStub) = Nav.push(
        GalleryDetailScreen(g.id, Gallery(id = g.id, title = g.title, date = g.date, imageCount = g.imageCount, updatedAt = g.updatedAt, cover = g.cover)),
    )
    /** iOS: `FullScreenImageView(images:selectedImageId:)`. */
    fun image(images: List<StashImage>, selectedId: String) =
        Nav.push(ImageViewerScreen(images, images.indexOfFirst { it.id == selectedId }.coerceAtLeast(0)))
}

/** Placeholder page for targets that don't exist on Android yet (director detail). */
internal class PendingLinkScreen(override val key: String, private val title: String) : Screen {
    @Composable override fun Content() = PendingLinkContent(title)
}

@Composable
fun PendingLinkContent(title: String) {
    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        EmptyState(SF.sparkles, title, "Coming soon", Modifier.align(Alignment.Center))
        de.letzgo.stashy.ui.NativeTopBar(title)
    }
}
