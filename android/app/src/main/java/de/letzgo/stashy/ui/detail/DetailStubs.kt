package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.catalog.Pending

// Compile stubs for the detail screens built in wave 2 (deleted at merge).

@Composable
private fun Stub(title: String) = Box(Modifier.fillMaxSize()) {
    Pending(title)
    BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
}

class PerformerDetailScreen(val performerId: String, val preview: Performer? = null) : Screen {
    override val key = "performer-$performerId"
    @Composable override fun Content() = Stub(preview?.name ?: "Performer")
}

class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"
    @Composable override fun Content() = Stub(preview?.name ?: "Studio")
}

class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"
    @Composable override fun Content() = Stub(preview?.name ?: "Tag")
}

class GalleryDetailScreen(val galleryId: String, val preview: Gallery? = null) : Screen {
    override val key = "gallery-$galleryId"
    @Composable override fun Content() = Stub(preview?.displayTitle ?: "Gallery")
}

class GroupDetailScreen(val groupId: String, val preview: StashGroup? = null) : Screen {
    override val key = "group-$groupId"
    @Composable override fun Content() = Stub(preview?.name ?: "Group")
}

class ImageViewerScreen(val images: List<StashImage>, val startIndex: Int) : Screen {
    override val key = "images-${images.getOrNull(startIndex)?.id}"
    override val hidesTabBar = true
    @Composable override fun Content() = Stub("Image")
}
