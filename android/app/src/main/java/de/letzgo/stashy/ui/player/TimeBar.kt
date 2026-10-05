package de.letzgo.stashy.ui.player

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.stashyGlass

/** A marker on the time bar (iOS: `AetherTimeBarMarker`). */
data class TimeBarMarker(val seconds: Double, val title: String?)

/** iOS: `AetherTimeBar.markerLabelWindow` — the scrub preview names a marker up to 60 s after its start. */
internal fun markerAt(markers: List<TimeBarMarker>, time: Double): TimeBarMarker? {
    val last = markers.sortedBy { it.seconds }.lastOrNull { it.seconds <= time } ?: return null
    return if (time - last.seconds <= 60) last else null
}

/**
 * iOS: `AetherTimeBar` — the shared scrub bar: capsule with elapsed time left, a Material 3
 * [Slider] in the middle (accent progress, marker dots on the track), remaining time right; while scrubbing a 120 pt
 * still (video aspect) floats just above the finger with the time and the marker it is in. Purely value driven —
 * the caller owns state and side effects (Scene Detail, Feeds and image fullscreen share it).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeBar(
    currentTime: Double,
    duration: Double,
    isScrubbing: Boolean,
    previewImage: ImageBitmap?,
    previewPlaceholderURL: String?,
    markers: List<TimeBarMarker>,
    modifier: Modifier = Modifier,
    isCompact: Boolean = false,
    /** Video aspect (w / h) for the still while no sprite tile is shown; the tile's own size wins. */
    previewAspectRatio: Float? = null,
    onScrubChanged: (Double) -> Unit,
    onScrubEnded: (Double) -> Unit,
) {
    val dur = maxOf(duration, 0.0)
    val shown = maxOf(0.0, currentTime)
    val remaining = maxOf(0.0, dur - shown)
    val template = PlaybackFormat.widestLabel(dur)
    val barHeight = if (isCompact) 36.dp else 44.dp
    val progress = if (dur > 0) (shown / dur).coerceIn(0.0, 1.0).toFloat() else 0f
    val labelStyle = TextStyle(fontSize = if (isCompact) 10.sp else 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
    val tint = Appearance.tint
    val changed by rememberUpdatedState(onScrubChanged)
    val ended by rememberUpdatedState(onScrubEnded)
    var lastScrub by remember { mutableStateOf(0.0) }
    val interaction = remember { MutableInteractionSource() }

    BoxWithConstraints(modifier.height(barHeight)) {
        Row(
            Modifier.fillMaxSize().stashyGlass(RoundedCornerShape(50)).padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            FixedLabel(PlaybackFormat.time(shown), template, labelStyle)
            // Material 3 slider; the marker dots ride on its track.
            val colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = tint,
                inactiveTrackColor = Color.White.copy(alpha = 0.28f),
            )
            Slider(
                value = progress,
                onValueChange = { f -> if (dur > 0) { lastScrub = f * dur; changed(lastScrub) } },
                onValueChangeFinished = { if (dur > 0) ended(lastScrub) },
                enabled = dur > 0,
                colors = colors,
                modifier = Modifier.weight(1f),
                interactionSource = interaction,
                // Stock M3 thumb is 44 dp tall — too high for a bar inside a 44 dp capsule.
                thumb = {
                    SliderDefaults.Thumb(
                        interactionSource = interaction,
                        colors = colors,
                        enabled = dur > 0,
                        thumbSize = DpSize(4.dp, if (isCompact) 14.dp else 18.dp),
                    )
                },
                track = { state ->
                    BoxWithConstraints(contentAlignment = Alignment.CenterStart) {
                        SliderDefaults.Track(
                            sliderState = state,
                            colors = colors,
                            enabled = dur > 0,
                            drawStopIndicator = null,
                            modifier = Modifier.height(if (isCompact) 4.dp else 6.dp),
                        )
                        if (dur > 0) {
                            val trackW = maxWidth
                            val dot = if (isCompact) 6.dp else 8.dp
                            markers.filter { it.seconds in 0.0..dur }.forEach { m ->
                                val x = (trackW * (m.seconds / dur).toFloat() - dot / 2).coerceIn(0.dp, trackW - dot)
                                Box(
                                    Modifier.offset(x = x).size(dot).shadow(1.dp, CircleShape).clip(CircleShape)
                                        .background(Color.White).border(1.dp, tint, CircleShape),
                                )
                            }
                        }
                    }
                },
            )
            FixedLabel("-" + PlaybackFormat.time(remaining), "-$template", labelStyle)
        }
        if (isScrubbing && dur > 0) {
            // Floating still just above the thumb, clamped to the bar so it never leaves the surface.
            // Measured unbounded: the bar's own 36/44 dp height must not squash the still (that
            // clamp is what made it ~3:1), and placed by its bottom edge a small gap above the bar.
            val labelWidth = with(LocalDensity.current) { (labelStyle.fontSize.toDp() * template.length * 0.62f) }
            val trackStart = 16.dp + labelWidth + 12.dp
            val trackWidth = (maxWidth - trackStart * 2).coerceAtLeast(1.dp)
            val aspect = scrubPreviewAspect(previewImage?.let { it.width to it.height }, previewAspectRatio)
            val (pw, ph) = scrubPreviewSize(aspect)
            val previewW = pw.dp
            val previewH = ph.dp
            val center = trackStart + trackWidth * progress
            val barW = maxWidth
            Column(
                Modifier.layout { measurable, _ ->
                    val placeable = measurable.measure(Constraints())
                    layout(0, 0) {
                        val half = placeable.width / 2
                        val maxX = (barW.roundToPx() - placeable.width).coerceAtLeast(0)
                        val x = (center.roundToPx() - half).coerceIn(0, maxX)
                        placeable.place(x, -placeable.height - SCRUB_PREVIEW_GAP.roundToPx())
                    }
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Box(
                    Modifier.size(previewW, previewH).shadow(6.dp, RoundedCornerShape(6.dp)).clip(RoundedCornerShape(6.dp))
                        .background(Color.Black.copy(alpha = 0.7f)).border(0.5.dp, Color.White.copy(alpha = 0.75f), RoundedCornerShape(6.dp)),
                ) {
                    if (previewImage != null) Image(previewImage, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else if (previewPlaceholderURL != null) AsyncImage(previewPlaceholderURL, null, Modifier.fillMaxSize().alpha(0.55f), contentScale = ContentScale.Crop)
                }
                Text(PlaybackFormat.time(shown), style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace), color = Color.White)
                markerAt(markers, shown)?.title?.takeIf { it.isNotEmpty() }?.let { title ->
                    Text(
                        title, Modifier.widthIn(max = maxOf(previewW, 120.dp) + 40.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 7.dp, vertical = 3.dp),
                        style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

private val SCRUB_PREVIEW_GAP = 8.dp

/**
 * Aspect ratio (w / h) of the scrub still: the sprite tile itself when one is shown, else the
 * caller's video / file aspect, else 16:9. Degenerate values fall through to the next source.
 */
internal fun scrubPreviewAspect(imageSize: Pair<Int, Int>?, fallback: Float?): Float {
    imageSize?.let { (w, h) -> if (w > 0 && h > 0) return w.toFloat() / h }
    if (fallback != null && fallback.isFinite() && fallback > 0f) return fallback
    return 16f / 9f
}

/**
 * Size (dp) of the scrub still for [aspect]: landscape keeps iOS's 120 pt width, portrait keeps a
 * 120 pt height; extreme ratios are clamped so the still stays readable.
 */
internal fun scrubPreviewSize(aspect: Float): Pair<Float, Float> {
    val a = aspect.coerceIn(0.4f, 2.6f)
    return if (a >= 1f) 120f to 120f / a else 120f * a to 120f
}

/** Fixed-width label: the template sits invisibly underneath and defines the width. */
@Composable
private fun FixedLabel(text: String, template: String, style: TextStyle) {
    Box(contentAlignment = Alignment.Center) {
        Text(template, Modifier.alpha(0f), style = style, maxLines = 1)
        Text(text, style = style, color = Color.White.copy(alpha = 0.7f), maxLines = 1, softWrap = false)
    }
}
