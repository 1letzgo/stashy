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
 * still floats above the finger with the time and the marker it is in. Purely value driven —
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
            // Floating still above the thumb, clamped to the bar so it never leaves the surface.
            val labelWidth = with(LocalDensity.current) { (labelStyle.fontSize.toDp() * template.length * 0.62f) }
            val trackStart = 16.dp + labelWidth + 12.dp
            val trackWidth = (maxWidth - trackStart * 2).coerceAtLeast(1.dp)
            val previewW = 120.dp
            val previewH = previewW * 9f / 16f
            val raw = trackStart + trackWidth * progress
            val center = if (maxWidth > previewW) raw.coerceIn(previewW / 2, maxWidth - previewW / 2) else maxWidth / 2
            Column(
                Modifier.offset(x = center - previewW / 2, y = -(previewH + 34.dp)).width(previewW),
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
                        title, Modifier.widthIn(max = previewW + 40.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 7.dp, vertical = 3.dp),
                        style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** Fixed-width label: the template sits invisibly underneath and defines the width. */
@Composable
private fun FixedLabel(text: String, template: String, style: TextStyle) {
    Box(contentAlignment = Alignment.Center) {
        Text(template, Modifier.alpha(0f), style = style, maxLines = 1)
        Text(text, style = style, color = Color.White.copy(alpha = 0.7f), maxLines = 1, softWrap = false)
    }
}
