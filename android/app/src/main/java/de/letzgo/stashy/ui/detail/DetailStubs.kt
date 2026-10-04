package de.letzgo.stashy.ui.detail

import androidx.compose.runtime.Composable
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.scene.PendingLinkContent

// Compile stubs for the scene-detail port only — this file is deleted at merge (real screens live in ui/detail).

class PerformerDetailScreen(val performerId: String, val preview: Performer? = null) : Screen {
    override val key = "performer-$performerId"
    @Composable override fun Content() = PendingLinkContent(preview?.name ?: "Performer")
}

class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"
    @Composable override fun Content() = PendingLinkContent(preview?.name ?: "Studio")
}

class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"
    @Composable override fun Content() = PendingLinkContent(preview?.name ?: "Tag")
}

class GalleryDetailScreen(val galleryId: String, val preview: Gallery? = null) : Screen {
    override val key = "gallery-$galleryId"
    @Composable override fun Content() = PendingLinkContent(preview?.displayTitle ?: "Gallery")
}

class GroupDetailScreen(val groupId: String, val preview: StashGroup? = null) : Screen {
    override val key = "group-$groupId"
    @Composable override fun Content() = PendingLinkContent(preview?.name ?: "Group")
}

class ImageViewerScreen(val images: List<StashImage>, val startIndex: Int) : Screen {
    override val key = "image-${images.getOrNull(startIndex)?.id}"
    override val hidesTabBar = true
    @Composable override fun Content() = PendingLinkContent("Image")
}
