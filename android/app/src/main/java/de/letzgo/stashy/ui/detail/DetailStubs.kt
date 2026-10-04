package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen

// Placeholder detail screens pushed by the catalogs. A later port replaces their `Content()`;
// keep the constructor signatures (the catalogs and other features construct them).

@Composable
private fun PlaceholderDetail(icon: ImageVector, title: String) {
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(icon, title, "Coming soon") }
        BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
    }
}

/** iOS: `PerformerDetailView(performer:)`. [preview] is the list item shown while loading. */
class PerformerDetailScreen(val performerId: String, val preview: Performer? = null) : Screen {
    override val key = "performer-$performerId"
    @Composable override fun Content() = PlaceholderDetail(SF.personFill, preview?.name ?: "Performer")
}

/** iOS: `StudioDetailView(studio:)`. */
class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"
    @Composable override fun Content() = PlaceholderDetail(SF.building2, preview?.name ?: "Studio")
}

/** iOS: `TagDetailView(selectedTag:)`. */
class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"
    @Composable override fun Content() = PlaceholderDetail(SF.tag, preview?.name ?: "Tag")
}

/** iOS: `ImagesView(gallery:)` — the images of one gallery. */
class GalleryDetailScreen(val galleryId: String, val preview: Gallery? = null) : Screen {
    override val key = "gallery-$galleryId"
    @Composable override fun Content() = PlaceholderDetail(SF.photoStack, preview?.displayTitle ?: "Gallery")
}

/** iOS: `GroupDetailView(selectedGroup:)`. */
class GroupDetailScreen(val groupId: String, val preview: StashGroup? = null) : Screen {
    override val key = "group-$groupId"
    @Composable override fun Content() = PlaceholderDetail(SF.rectangleStackFill, preview?.name ?: "Group")
}

/**
 * iOS: `FullScreenImageView` — swipeable full-screen viewer over [images] starting at
 * [startIndex] (the list the user tapped in, already loaded).
 */
class ImageViewerScreen(val images: List<StashImage>, val startIndex: Int) : Screen {
    override val key = "image-viewer-${images.getOrNull(startIndex)?.id ?: "none"}"
    override val hidesTabBar: Boolean get() = true
    @Composable override fun Content() = PlaceholderDetail(SF.photo, images.getOrNull(startIndex)?.title ?: "Image")
}
