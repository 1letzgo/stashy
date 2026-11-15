package de.letzgo.stashy.ui.player

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Two-finger pinch zoom for the scene player (iOS `PlayerPinchZoom.swift`): the picture zooms
 * around the pinch point up to 4×, one finger pans it while zoomed, a pinch back below 1× springs
 * home. Only the video layer is transformed (a `graphicsLayer`, read in the draw phase, so a pinch
 * neither recomposes nor relayouts the surface); controls and captions stay as they are.
 *
 * Fullscreen landscape: a pinch from fit that ends near the fill scale snaps into "fill" (the
 * state the fill button sets), a pinch closed while filled goes back to fit.
 */
class PlayerZoomState(private val scope: CoroutineScope) {
    var scale by mutableFloatStateOf(1f); private set
    var offsetX by mutableFloatStateOf(0f); private set
    var offsetY by mutableFloatStateOf(0f); private set
    /** Changes only at the end of a gesture or on a reset, never per pinch step. */
    var isZoomed by mutableStateOf(false); private set

    /** Surface size in px and the picture size at 1× for the current gravity. */
    var surfaceSize: Size = Size.Zero
    private var pictureSize: Size = Size.Zero
    private var rawScale = 1f
    private var pinchStartScale: Float? = null
    private var animation: Job? = null

    val isPinching: Boolean get() = pinchStartScale != null

    fun reset(animated: Boolean = true) {
        pinchStartScale = null
        isZoomed = false
        if (scale == 1f && offsetX == 0f && offsetY == 0f) return
        if (animated) animateTo(1f, 0f, 0f) else set(1f, 0f, 0f)
    }

    fun beginPinch(picture: Size) {
        animation?.cancel()
        pinchStartScale = scale
        rawScale = scale
        pictureSize = picture
    }

    /** [centroid] in surface px (top-left origin); [pan] the centroid's movement this event. */
    fun pinchBy(zoom: Float, centroid: Offset, pan: Offset) {
        if (pinchStartScale == null) return
        rawScale *= zoom
        val shown = when {
            rawScale < 1f -> max(0.5f, 1f - (1f - rawScale) * 0.5f)
            rawScale > MAX_SCALE -> MAX_SCALE + (rawScale - MAX_SCALE) * 0.3f
            else -> rawScale
        }
        val ratio = shown / scale
        // Keep the point under the fingers where it is, and let it follow them.
        val cx = centroid.x - surfaceSize.width / 2
        val cy = centroid.y - surfaceSize.height / 2
        val x = cx - ratio * (cx - offsetX) + pan.x
        val y = cy - ratio * (cy - offsetY) + pan.y
        val (clampedX, clampedY) = clamped(x, y, shown)
        set(shown, clampedX, clampedY)
    }

    enum class Outcome { SnapToFill, BackToFit, Free }

    /**
     * [fills] is true only where fill is offered and on; [fillScale] is the scale at which the
     * fitted picture covers the surface, null when fill is not offered or already on.
     */
    fun endPinch(fills: Boolean, fillScale: Float?): Outcome {
        val startScale = pinchStartScale ?: scale
        pinchStartScale = null
        val startedAtOne = startScale <= 1.01f
        if (startedAtOne && fills && scale < 0.95f) {
            isZoomed = false
            animateTo(1f, 0f, 0f)
            return Outcome.BackToFit
        }
        if (startedAtOne && fillScale != null && fillScale > 1.02f && scale > 1.02f && abs(scale / fillScale - 1f) < 0.18f) {
            // The crop takes over; the transform goes back at once so the picture is not
            // scaled twice for a frame.
            isZoomed = false
            set(1f, 0f, 0f)
            return Outcome.SnapToFill
        }
        if (scale <= 1.05f) {
            reset()
            return Outcome.Free
        }
        val target = min(scale, MAX_SCALE)
        val (x, y) = clamped(offsetX, offsetY, target)
        isZoomed = true
        animateTo(target, x, y)
        return Outcome.Free
    }

    fun panBy(pan: Offset, picture: Size) {
        if (!isZoomed || isPinching) return
        animation?.cancel()
        pictureSize = picture
        val (x, y) = clamped(offsetX + pan.x, offsetY + pan.y, scale)
        set(scale, x, y)
    }

    /** Along an axis where the picture is larger than the surface no gap shows; else centred. */
    private fun clamped(x: Float, y: Float, scale: Float): Pair<Float, Float> {
        val picture = if (pictureSize.width > 0 && pictureSize.height > 0) pictureSize else surfaceSize
        val maxX = max(0f, (picture.width * scale - surfaceSize.width) / 2)
        val maxY = max(0f, (picture.height * scale - surfaceSize.height) / 2)
        return x.coerceIn(-maxX, maxX) to y.coerceIn(-maxY, maxY)
    }

    private fun set(s: Float, x: Float, y: Float) {
        if (scale != s) scale = s
        if (offsetX != x) offsetX = x
        if (offsetY != y) offsetY = y
    }

    private fun animateTo(s: Float, x: Float, y: Float) {
        animation?.cancel()
        val fromS = scale; val fromX = offsetX; val fromY = offsetY
        animation = scope.launch {
            animate(0f, 1f, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)) { t, _ ->
                set(fromS + (s - fromS) * t, fromX + (x - fromX) * t, fromY + (y - fromY) * t)
            }
        }
    }

    companion object {
        const val MAX_SCALE = 4f

        /** Visible picture size inside [surface] at 1× for a source size and the current gravity. */
        fun pictureSize(surface: Size, source: Pair<Int, Int>?, fills: Boolean): Size {
            if (source == null || source.first <= 0 || source.second <= 0 || surface.width <= 0 || surface.height <= 0) return surface
            val (w, h) = source
            val s = if (fills) max(surface.width / w, surface.height / h) else min(surface.width / w, surface.height / h)
            // A filled picture is cropped to the surface: only that part can be panned to.
            return Size(min(w * s, surface.width), min(h * s, surface.height))
        }
    }
}

/** The video layer's transform. Reads the zoom only in the draw phase. */
fun Modifier.playerZoomTransform(state: PlayerZoomState): Modifier = graphicsLayer {
    scaleX = state.scale
    scaleY = state.scale
    translationX = state.offsetX
    translationY = state.offsetY
}

/**
 * Pinch and / or one-finger pan (only while zoomed). Runs in the Initial pass and consumes only
 * what it uses: taps, double taps and the hold stay untouched, a pinch or a pan cancels them, and
 * an unzoomed one-finger drag is left to the page's scroll.
 * The pinch goes on the surface itself (a parent of the controls, so it also starts over a
 * control: they are up while paused, and a touch on one never reached a sibling below); the pan
 * only on the tap layer, so a drag on the time bar or volume slider stays a scrub.
 */
fun Modifier.playerPinchZoomGestures(
    state: PlayerZoomState,
    pictureSize: () -> Size,
    handlesPinch: Boolean = true,
    handlesPan: Boolean = true,
    onPinchBegan: () -> Unit = {},
    onPinchEnded: () -> Unit = {},
): Modifier = pointerInput(state, handlesPinch, handlesPan) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        var pinching = false
        var panning = false
        var panDistance = 0f
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            val pressed = event.changes.count { it.pressed }
            if (pressed == 0) break
            if (pressed >= 2) {
                if (!handlesPinch) { pinching = true; continue }
                if (!pinching) {
                    pinching = true
                    state.beginPinch(pictureSize())
                    onPinchBegan()
                }
                val centroid = event.calculateCentroid(useCurrent = true)
                if (centroid != Offset.Unspecified) {
                    state.pinchBy(event.calculateZoom(), centroid, event.calculatePan())
                }
                event.changes.forEach { if (it.positionChanged()) it.consume() }
            } else if (handlesPan && !pinching && state.isZoomed) {
                val pan = event.calculatePan()
                if (!panning) {
                    panDistance += pan.getDistance()
                    if (panDistance > viewConfiguration.touchSlop) panning = true
                }
                if (panning) {
                    state.panBy(pan, pictureSize())
                    event.changes.forEach { if (it.positionChanged()) it.consume() }
                }
            }
        }
        if (pinching && handlesPinch) onPinchEnded()
    }
}

/** Latest size / end callbacks for a pinch modifier set up above the values they read. */
class PlayerZoomHandlers {
    var pictureSize: () -> Size = { Size.Zero }
    var onPinchEnded: () -> Unit = {}
}
