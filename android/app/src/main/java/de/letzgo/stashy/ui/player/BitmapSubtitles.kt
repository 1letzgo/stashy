@file:OptIn(UnstableApi::class)

package de.letzgo.stashy.ui.player

import androidx.annotation.OptIn
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi
import kotlin.math.roundToInt

/** Where one picture cue lands inside a `width` × `height` picture rect (pixels). */
data class BitmapCueRect(val left: Float, val top: Float, val width: Float, val height: Float)

/**
 * Placement of a picture-based subtitle (PGS / VobSub / DVB) — the same rules as Media3's
 * `SubtitlePainter.setupBitmapLayout`: [Cue.position] / [Cue.line] are fractions of the frame
 * for the anchor point, [Cue.size] the width fraction, [Cue.bitmapHeight] the height fraction
 * (else the bitmap's aspect), and the anchors say which edge sits on the anchor point.
 */
object BitmapCueLayout {
    fun rect(
        frameW: Float,
        frameH: Float,
        bitmapW: Int,
        bitmapH: Int,
        position: Float,
        positionAnchor: Int,
        line: Float,
        lineType: Int,
        lineAnchor: Int,
        size: Float,
        bitmapHeight: Float,
    ): BitmapCueRect? {
        if (frameW <= 0f || frameH <= 0f || bitmapW <= 0 || bitmapH <= 0) return null
        val unset = Cue.DIMEN_UNSET
        // Unset fields: centred horizontally, bottom-anchored near the bottom edge.
        val pos = if (position == unset) 0.5f else position
        val posAnchor = if (position == unset) Cue.ANCHOR_TYPE_MIDDLE else positionAnchor
        val ln = if (line == unset || lineType != Cue.LINE_TYPE_FRACTION) 0.95f else line
        val lnAnchor = if (line == unset || lineType != Cue.LINE_TYPE_FRACTION) Cue.ANCHOR_TYPE_END else lineAnchor
        val width = frameW * (if (size == unset || size <= 0f) (bitmapW / frameW).coerceAtMost(1f) else size)
        val height = if (bitmapHeight != unset && bitmapHeight > 0f) frameH * bitmapHeight else width * bitmapH / bitmapW
        val anchorX = frameW * pos
        val anchorY = frameH * ln
        val x = when (posAnchor) {
            Cue.ANCHOR_TYPE_END -> anchorX - width
            Cue.ANCHOR_TYPE_MIDDLE -> anchorX - width / 2
            else -> anchorX
        }
        val y = when (lnAnchor) {
            Cue.ANCHOR_TYPE_END -> anchorY - height
            Cue.ANCHOR_TYPE_MIDDLE -> anchorY - height / 2
            else -> anchorY
        }
        return BitmapCueRect(x, y, width, height)
    }
}

/**
 * Draws picture-based cues over the video. Place it exactly over the picture rect (inside
 * [VideoSurface]'s sized box) so the cue fractions map onto the frame, letterboxing excluded.
 */
@Composable
fun BitmapSubtitleLayer(cues: List<Cue>, modifier: Modifier = Modifier) {
    if (cues.isEmpty()) return
    val images: List<Pair<Cue, ImageBitmap>> = remember(cues) {
        cues.mapNotNull { cue -> cue.bitmap?.takeIf { !it.isRecycled }?.let { cue to it.asImageBitmap() } }
    }
    Canvas(modifier) {
        for ((cue, image) in images) {
            val r = BitmapCueLayout.rect(
                size.width, size.height, image.width, image.height,
                cue.position, cue.positionAnchor, cue.line, cue.lineType, cue.lineAnchor, cue.size, cue.bitmapHeight,
            ) ?: continue
            drawImage(
                image,
                srcOffset = IntOffset.Zero,
                srcSize = IntSize(image.width, image.height),
                dstOffset = IntOffset(r.left.roundToInt(), r.top.roundToInt()),
                dstSize = IntSize(r.width.roundToInt().coerceAtLeast(1), r.height.roundToInt().coerceAtLeast(1)),
                filterQuality = FilterQuality.Medium,
            )
        }
    }
}
