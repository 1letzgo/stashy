package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen

// Placeholders so callers compile until the detail screens are ported (replaced at merge).

@Composable
private fun StubContent(title: String) {
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(SF.cubeBox, title, "Coming soon") }
        BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
    }
}

/** iOS: `PerformerDetailView`. */
class PerformerDetailScreen(val performerId: String, val preview: Performer? = null) : Screen {
    override val key = "performer-$performerId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Performer")
}

/** iOS: `StudioDetailView`. */
class StudioDetailScreen(val studioId: String, val preview: Studio? = null) : Screen {
    override val key = "studio-$studioId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Studio")
}

/** iOS: `TagDetailView`. */
class TagDetailScreen(val tagId: String, val preview: Tag? = null) : Screen {
    override val key = "tag-$tagId"
    @Composable override fun Content() = StubContent(preview?.name ?: "Tag")
}
