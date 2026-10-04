package de.letzgo.stashy.ui.tools.rateme

import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import de.letzgo.stashy.data.Net

/**
 * iOS: `AetherPreviewPlayer` + `AetherPreviewSurface(fill: false)` as used by `RateMeMediaView` —
 * a muted, looping preview drawn aspect-fit into the media box. A `TextureView` (not
 * `SurfaceView`) so the card's rounded clip applies. [onFirstFrame] lets the caller fade it in.
 */
@OptIn(UnstableApi::class)
@Composable
internal fun RateMePreviewVideo(url: String, modifier: Modifier = Modifier, onFirstFrame: () -> Unit = {}) {
    val context = LocalContext.current
    var videoAspect by remember(url) { mutableStateOf<Float?>(null) }
    val player = remember(url) {
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(Net.client)))
            .build()
            .apply {
                volume = 0f
                repeatMode = Player.REPEAT_MODE_ONE
                setMediaItem(MediaItem.fromUri(url))
                prepare()
                playWhenReady = true
            }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    videoAspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
                }
            }
            override fun onRenderedFirstFrame() = onFirstFrame()
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
        }
    }
    Box(modifier, contentAlignment = Alignment.Center) {
        val aspect = videoAspect
        AndroidView(
            factory = { ctx -> TextureView(ctx).also { player.setVideoTextureView(it) } },
            modifier = if (aspect != null) Modifier.aspectRatio(aspect) else Modifier.fillMaxSize(),
        )
    }
}
