package de.letzgo.stashy.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp

// System font scale (accessibility) helpers.
//
// Rule of the app: every text is sized in `sp` (MaterialTheme / NativeType styles) and every
// container around text wraps it (`heightIn(min = …)` + padding, never a fixed `height`), so
// text and its tappable control grow together with the device font size. Icons sitting next to
// text use [scaledIconSize] so a pill does not end up with a huge label and a tiny glyph.
//
// Exception: overlays on top of video / full-screen media (Feeds info overlay, player chrome)
// scale too, but through [CappedFontScale] at [OverlayMaxFontScale] so captions never cover
// most of the picture.

/** Max font scale applied to text drawn over video (Feeds overlay, player chrome). */
const val OverlayMaxFontScale: Float = 1.3f

/**
 * [base] grown like a `base.value.sp` text would at the current font scale (follows Android 14's
 * non-linear scaling), never smaller than [base] and capped at [maxScale] × [base].
 */
@Composable
fun scaledIconSize(base: Dp, maxScale: Float = 2f): Dp {
    val d = LocalDensity.current
    if (d.fontScale <= 1f) return base
    val scaled = with(d) { base.value.sp.toDp() }
    return scaled.coerceIn(base, base * maxScale)
}

/** Current font scale, capped to [max] (for sizes that should follow text only up to a limit). */
@Composable
fun cappedFontScale(max: Float = 2f): Float = LocalDensity.current.fontScale.coerceIn(1f, max)

/**
 * Lets [content] follow the system font scale only up to [maxScale] (video overlays). Below the
 * cap nothing changes, so the device's own (non-linear) scaling stays in effect.
 */
@Composable
fun CappedFontScale(maxScale: Float = OverlayMaxFontScale, content: @Composable () -> Unit) {
    val d = LocalDensity.current
    if (d.fontScale <= maxScale) content()
    else CompositionLocalProvider(LocalDensity provides Density(d.density, maxScale), content = content)
}

/**
 * [base] lines at the default font size, one more once the font scale is noticeably larger —
 * for single-line labels in fixed-width cells, which would otherwise ellipsize after a few letters.
 */
@Composable
fun scaledMaxLines(base: Int = 1): Int = if (LocalDensity.current.fontScale > 1.15f) base + 1 else base
