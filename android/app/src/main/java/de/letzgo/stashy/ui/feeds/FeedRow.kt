package de.letzgo.stashy.ui.feeds

import android.view.TextureView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.exoplayer.ExoPlayer
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.stashyGlass

/**
 * iOS: `shouldFill` — Immersive fills the screen when the content's orientation matches the
 * device's (portrait clip on a portrait phone, landscape clip in landscape).
 */
fun feedShouldFill(fillSetting: Boolean, devicePortrait: Boolean, contentLandscape: Boolean): Boolean =
    fillSetting && (if (devicePortrait) !contentLandscape else contentLandscape)

/** Media size inside a container (pure, unit-tested): fill = cover, fit = contain. */
fun feedMediaSize(containerW: Float, containerH: Float, aspect: Float, fill: Boolean): Pair<Float, Float> {
    if (containerW <= 0f || containerH <= 0f || aspect <= 0f) return containerW to containerH
    val containerAspect = containerW / containerH
    val widthBound = if (fill) containerAspect > aspect else containerAspect < aspect
    return if (widthBound) containerW to containerW / aspect else containerH * aspect to containerH
}

/**
 * iOS: `ReelItemView` media layer + gestures (`ZoomableScrollView`): one feed page.
 *
 * - tap toggles the chrome (ignored in the top 120 / bottom 160 pt like iOS),
 * - double tap on the outer thirds skips by `playerSkipSeconds`, in the middle zooms,
 * - long press holds fast forward at `hold_speed_feeds`,
 * - pinch zooms (the pager stops paging while zoomed).
 */
@Composable
fun FeedRow(
    item: FeedItem,
    player: ExoPlayer?,
    isActive: Boolean,
    videoSize: IntSize?,
    bottomInset: Dp,
    isUIVisible: Boolean,
    isPlaying: Boolean,
    isScrolling: Boolean,
    errorMessage: String?,
    onToggleUI: () -> Unit,
    onSkip: (Double) -> Unit,
    onFastForward: (Boolean) -> Unit,
    onZoomChanged: (Boolean) -> Unit,
    onPlay: () -> Unit,
) {
    val config = LocalConfiguration.current
    val devicePortrait = config.screenHeightDp > config.screenWidthDp
    val contentLandscape = videoSize?.let { it.width > it.height } ?: !item.isPortrait
    val fill = feedShouldFill(FeedsConfig.fillHeight, devicePortrait, contentLandscape)
    val inset = if (fill && isUIVisible) bottomInset else 0.dp

    var scale by remember(item.id, devicePortrait) { mutableFloatStateOf(1f) }
    var offset by remember(item.id, devicePortrait) { mutableStateOf(Offset.Zero) }
    var fastForwarding by remember(item.id) { mutableStateOf(false) }
    val zoomCallback by rememberUpdatedState(onZoomChanged)
    val playingNow by rememberUpdatedState(isPlaying)
    val toggleUI by rememberUpdatedState(onToggleUI)
    val skipBy by rememberUpdatedState(onSkip)
    val fastForward by rememberUpdatedState(onFastForward)
    LaunchedEffect(isActive) { if (!isActive) { scale = 1f; offset = Offset.Zero } }
    LaunchedEffect(scale > 1f) { if (isActive) zoomCallback(scale > 1f) }

    val density = LocalDensity.current
    val skip = FeedsConfig.playerSkipSeconds.toDouble()

    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black).clipToBounds()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val availH = (h - with(density) { inset.toPx() }).coerceAtLeast(1f)
        val aspect = videoSize?.let { it.width.toFloat() / it.height } ?: fileAspect(item)
        val (mw, mh) = feedMediaSize(w, if (fill) availH else h, aspect, fill)
        val mediaModifier = Modifier
            .align(if (fill) Alignment.TopCenter else Alignment.Center)
            .requiredSize(with(density) { mw.toDp() }, with(density) { mh.toDp() })
            .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y }

        if (item.isAnimated) {
            // GIF / animated WebP clips: Coil's animated decoder (iOS `AnimatedWebView`).
            SubcomposeAsyncImage(
                model = item.videoURL, contentDescription = item.title,
                contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                alignment = if (fill) Alignment.TopCenter else Alignment.Center,
                loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Color.White) } },
                error = { Box(Modifier.fillMaxSize(), Alignment.Center) { Icon(SF.exclamationTriangle, null, tint = Color.White) } },
                modifier = Modifier.fillMaxWidth().height(with(density) { (if (fill) availH else h).toDp() }).align(Alignment.TopCenter)
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y },
            )
        } else if (player != null) {
            Box(mediaModifier) { VideoSurface(player) }
        }

        // Gesture layer.
        Box(
            Modifier.fillMaxSize()
                .pointerInput(item.id, mw, mh, w) {
                    // Pinch zoom (two fingers) and panning while zoomed; single-finger drags at
                    // scale 1 fall through to the pager.
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        do {
                            val event = awaitPointerEvent()
                            val pressed = event.changes.count { it.pressed }
                            if (pressed >= 2 || scale > 1f) {
                                val newScale = (scale * event.calculateZoom()).coerceIn(1f, 4f)
                                val maxX = (mw * newScale - w).coerceAtLeast(0f) / 2f
                                val maxY = (mh * newScale - h).coerceAtLeast(0f) / 2f
                                val pan = offset + event.calculatePan()
                                scale = newScale
                                offset = if (newScale <= 1.01f) Offset.Zero else Offset(pan.x.coerceIn(-maxX, maxX), pan.y.coerceIn(-maxY, maxY))
                                if (newScale <= 1.01f) scale = 1f
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        } while (event.changes.any { it.pressed })
                    }
                }
                .pointerInput(item.id, isActive) {
                    val topZone = 120.dp.toPx()
                    val bottomZone = 160.dp.toPx()
                    detectTapGestures(
                        onTap = { pos ->
                            if (pos.y in 0f..topZone) return@detectTapGestures
                            if (pos.y > size.height - bottomZone) return@detectTapGestures
                            toggleUI()
                        },
                        onDoubleTap = { pos ->
                            val third = size.width / 3f
                            when {
                                item.isVideo && pos.x < third -> skipBy(-skip)
                                item.isVideo && pos.x > size.width - third -> skipBy(skip)
                                else -> if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2f
                            }
                        },
                        onLongPress = {
                            if (item.isVideo && playingNow) {
                                fastForwarding = true
                                fastForward(true)
                            }
                        },
                        onPress = {
                            tryAwaitRelease()
                            if (fastForwarding) {
                                fastForwarding = false
                                fastForward(false)
                            }
                        },
                    )
                },
        )

        if (errorMessage != null) {
            Column(
                Modifier.fillMaxSize().padding(horizontal = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
            ) {
                Icon(SF.exclamationTriangle, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(28.dp))
                Text(errorMessage, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, textAlign = TextAlign.Center)
            }
        }

        // iOS `fastForwardOverlay`: below the chip row (top 200).
        AnimatedVisibility(fastForwarding, Modifier.align(Alignment.TopCenter).padding(top = 200.dp), enter = fadeIn(), exit = fadeOut()) {
            Row(
                Modifier.stashyGlass(RoundedCornerShape(50)).padding(horizontal = 22.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(SF.chevronRight2, null, tint = Color.White, modifier = Modifier.size(32.dp))
                Text(holdSpeedLabel(FeedsConfig.holdSpeedFeeds), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }

        // iOS `playButtonOverlay` (`CenterPlayButton`): a bare 60 pt `play.fill`, white 70 % with
        // a soft shadow, no circle; the whole page is the tap target.
        if (item.isVideo && !isPlaying && isUIVisible && !isScrolling && isActive) {
            Box(Modifier.fillMaxSize().noIndicationClick(onPlay), contentAlignment = Alignment.Center) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(SF.playFill, null, tint = Color.Black.copy(alpha = 0.25f), modifier = Modifier.size(84.dp).blur(10.dp))
                    Icon(SF.playFill, "Play", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(84.dp))
                }
            }
        }
    }
}

/** iOS: `TabManager.holdSpeedLabel` ("2×", "1.5×"). */
fun holdSpeedLabel(speed: Float): String =
    if (speed % 1f == 0f) "${speed.toInt()}×" else "${String.format(java.util.Locale.US, "%.2f", speed).trimEnd('0').trimEnd('.')}×"

private fun fileAspect(item: FeedItem): Float {
    val files = when (item) {
        is FeedItem.SceneItem -> item.scene.files?.firstOrNull()?.let { it.width to it.height }
        is FeedItem.PreviewItem -> item.scene.files?.firstOrNull()?.let { it.width to it.height }
        is FeedItem.MarkerItem -> item.marker.scene?.files?.firstOrNull()?.let { it.width to it.height }
        is FeedItem.ClipItem -> item.image.visualFiles?.firstOrNull()?.let { it.width to it.height }
    }
    val (w, h) = files ?: (null to null)
    return if ((w ?: 0) > 0 && (h ?: 0) > 0) w!!.toFloat() / h!! else if (item.isPortrait) 9f / 16f else 16f / 9f
}

/** TextureView bound to [player] (scales with the zoom transform, unlike a SurfaceView). */
@Composable
private fun VideoSurface(player: ExoPlayer) {
    var view by remember { mutableStateOf<TextureView?>(null) }
    AndroidView(factory = { TextureView(it).also { tv -> view = tv } }, modifier = Modifier.fillMaxSize())
    DisposableEffect(player, view) {
        val v = view
        if (v != null) player.setVideoTextureView(v)
        onDispose { if (v != null) player.clearVideoTextureView(v) }
    }
}
