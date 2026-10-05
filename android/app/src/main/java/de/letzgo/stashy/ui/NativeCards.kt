package de.letzgo.stashy.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Material 3 card building blocks (Android look of the iOS cards).
//
// - Every content card is an `ElevatedCard` ([NativeCard]): 12 dp corners, Material elevation on
//   the tonal surface `Theme.palette.secondaryBackground` instead of the iOS shadow, ripple on
//   tap via the card's own `onClick` (never `noRippleClickable`).
// - Hero items (first dashboard row) use the Material carousel corner radius ([NativeHeroShape]).
// - Labels over images ([NativeMediaLabel]) are small Material labels: a translucent surface
//   container with `labelSmall`/`labelMedium` text, 8 dp corners — no glass capsules.
// - Long-press previews (`ScenePreviewOnHold`) sit inside the card content and observe the
//   pointer without consuming it, so the card's ripple + tap keep working.

/** Corner radius of grid/row cards (Material medium shape). */
val NativeCardShape: Shape = RoundedCornerShape(12.dp)

/** Large rounded items of the hero row (Material carousel item shape). */
val NativeHeroShape: Shape = RoundedCornerShape(28.dp)

/** Shape of the small labels on top of media. */
val NativeLabelShape: Shape = RoundedCornerShape(8.dp)

/**
 * Material 3 elevated card; the content is a [Box] filling the card. [onClick] null = not
 * clickable (the caller handles taps).
 */
@Composable
fun NativeCard(
    modifier: Modifier = Modifier,
    shape: Shape = NativeCardShape,
    onClick: (() -> Unit)? = null,
    container: Color = Theme.palette.secondaryBackground,
    elevation: Dp = 1.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = CardDefaults.elevatedCardColors(containerColor = container, contentColor = Theme.palette.text)
    val el = CardDefaults.elevatedCardElevation(defaultElevation = elevation, pressedElevation = elevation, focusedElevation = elevation, hoveredElevation = elevation + 1.dp)
    if (onClick != null) {
        ElevatedCard(onClick = onClick, modifier = modifier, shape = shape, colors = colors, elevation = el) {
            Box(Modifier.fillMaxSize(), content = content)
        }
    } else {
        ElevatedCard(modifier = modifier, shape = shape, colors = colors, elevation = el) {
            Box(Modifier.fillMaxSize(), content = content)
        }
    }
}

/** Translucent surface container behind labels on images (readable on any photo). */
@Composable
fun nativeLabelContainer(): Color = Theme.palette.secondaryBackground.copy(alpha = 0.82f)

/**
 * Small Material label over media (date, duration, counts, studio name, file type). [small]
 * uses `labelSmall`, otherwise `labelMedium`.
 */
@Composable
fun NativeMediaLabel(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, small: Boolean = false) {
    NativeMediaLabelBox(modifier, small) {
        if (icon != null) Icon(icon, null, tint = Theme.palette.text, modifier = Modifier.size(if (small) 12.dp else 14.dp))
        Text(
            text, style = if (small) NativeType.labelSmall else NativeType.labelMedium,
            color = Theme.palette.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Container of [NativeMediaLabel] for custom content. [scrim] = dark scrim instead of the
 * surface container (studio logos, which are drawn for dark backgrounds).
 */
@Composable
fun NativeMediaLabelBox(modifier: Modifier = Modifier, small: Boolean = false, scrim: Boolean = false, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.clip(NativeLabelShape).background(if (scrim) Color.Black.copy(alpha = 0.55f) else nativeLabelContainer())
            .padding(horizontal = if (small) 6.dp else 8.dp, vertical = if (small) 2.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        content = content,
    )
}
