package de.letzgo.stashy.ui.scene

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.catalog.Pending

/** iOS: `SceneDetailView`. [preview] is the list item, shown while the full scene loads. */
class SceneDetailScreen(val sceneId: String, val preview: Scene? = null) : Screen {
    override val key = "scene-$sceneId"
    @Composable override fun Content() {
        Box(Modifier.fillMaxSize()) {
            Pending(preview?.displayTitle ?: "Scene")
            BackPill({ Nav.pop() }, Modifier.statusBarsPadding().padding(16.dp))
        }
    }
}
