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
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.catalog.Pending

// Placeholders so the Tools port compiles; the detail agent replaces this file.

@Composable
private fun StubContent(title: String) {
    Box(Modifier.fillMaxSize()) {
        Pending(title)
        BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
    }
}

class PerformerDetailScreen(val performerId: String, val preview: Performer? = null) : Screen {
    override val key = "performer-$performerId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Performer")
}

class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Studio")
}

class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Tag")
}

class GalleryDetailScreen(val galleryId: String, val preview: Gallery? = null) : Screen {
    override val key = "gallery-$galleryId"
    @Composable override fun Content() = StubContent(preview?.displayTitle ?: "Gallery")
}

class ImageViewerScreen(val images: List<StashImage>, val startIndex: Int) : Screen {
    override val key = "images-${images.getOrNull(startIndex)?.id}"
    override val hidesTabBar = true
    @Composable override fun Content() = StubContent("Image")
}
