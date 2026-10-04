package de.letzgo.stashy.ui.player

import android.view.TextureView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.max
import kotlin.math.min

/**
 * Draws a [StashPlayer]'s picture (iOS: `AetherVideoSurface` / `AetherPlayerSurface`). Black
 * backdrop, aspect-fit by default, [fill] crops to fill (iOS `.resizeAspectFill`), [topAligned]
 * pins a crop to the top like the card previews. Uses a `TextureView`, so it composes and clips
 * like any view and the frame can be captured ([StashPlayer.captureFrame]).
 * Only one surface should show a player at a time (the last one attached wins).
 */
@Composable
fun VideoSurface(player: StashPlayer, modifier: Modifier = Modifier, fill: Boolean = false, topAligned: Boolean = false) {
    val density = LocalDensity.current
    BoxWithConstraints(modifier.background(Color.Black).clipToBounds(), contentAlignment = if (topAligned) Alignment.TopCenter else Alignment.Center) {
        val size = player.videoSize
        val boxW = constraints.maxWidth.toFloat()
        val boxH = constraints.maxHeight.toFloat()
        val viewModifier = if (size != null && boxW > 0 && boxH > 0 && boxW.isFinite() && boxH.isFinite()) {
            val (w, h) = size
            val scale = if (fill) max(boxW / w, boxH / h) else min(boxW / w, boxH / h)
            with(density) { Modifier.requiredSize((w * scale).toDp(), (h * scale).toDp()) }
        } else Modifier.fillMaxSize()
        Box(viewModifier) {
            AndroidView(
                factory = { ctx ->
                    TextureView(ctx).also { view ->
                        runCatching { player.exo.setVideoTextureView(view) }
                        player.textureView = view
                    }
                },
                update = { view ->
                    if (player.textureView !== view) {
                        runCatching { player.exo.setVideoTextureView(view) }
                        player.textureView = view
                    }
                },
                onRelease = { view ->
                    if (player.textureView === view) {
                        runCatching { player.exo.clearVideoTextureView(view) }
                        player.textureView = null
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
