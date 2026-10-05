package de.letzgo.stashy.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS: `stashyGlass(shape:)` / `stashyGlass(shape:tint:)` — Liquid Glass chrome. Android has no
 * backdrop blur for content behind a view, so this is a dark translucent wash plus the hairline
 * stroke iOS draws pre-26, scaled by the user's glass transparency setting.
 */
fun Modifier.stashyGlass(shape: Shape = CircleShape, tint: Color? = null): Modifier {
    // Without a backdrop blur the content behind must be mostly covered, or text under the
    // chrome stays readable through it. Transparency 1 (iOS "pure glass") → 80 % cover.
    val cover = 0.8f + (1f - Appearance.glassTransparency) * 0.18f
    // Tinted glass: the tint sits on top of the dark glass (translucent tints keep their alpha).
    val tintFill = tint?.let { if (it.alpha < 1f) it else it.copy(alpha = 0.6f) }
    return this
        .clip(shape)
        .background(Color(0xFF1C2433).copy(alpha = cover), shape)
        .let { m -> if (tintFill != null) m.background(tintFill, shape) else m }
        .border(0.5.dp, Color.White.copy(alpha = 0.22f), shape)
}

/** iOS: floating shadow (`DesignTokens.Shadow.floating`). */
fun Modifier.floatingShadow(shape: Shape = CircleShape) = this.shadow(6.dp, shape, ambientColor = Color.Black.copy(0.12f), spotColor = Color.Black.copy(0.12f))

/** iOS: `cardShadow()` */
fun Modifier.cardShadow(shape: Shape = RoundedCornerShape(Tokens.Radius.card)) = this.shadow(4.dp, shape, ambientColor = Color.Black.copy(0.1f), spotColor = Color.Black.copy(0.1f))

fun Modifier.noRippleClickable(onClick: () -> Unit): Modifier = this.clickable(
    interactionSource = MutableInteractionSource(), indication = null, onClick = onClick,
)

/** Circular glass icon button (iOS chrome FAB, 36pt by default). */
@Composable
fun GlassIconButton(
    icon: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    tint: Color? = null,
    iconTint: Color = Color.White,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(size)
            .floatingShadow()
            .stashyGlass(CircleShape, tint)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription, tint = iconTint, modifier = Modifier.size(size * 0.45f)) }
}

/** Glass capsule with icon + label (selected chip of the top strip, "Back" pill …). */
@Composable
fun GlassCapsule(
    modifier: Modifier = Modifier,
    tint: Color? = null,
    height: Dp = 44.dp,
    contentPadding: PaddingValues = PaddingValues(horizontal = 16.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier
            .height(height)
            .floatingShadow(RoundedCornerShape(50))
            .stashyGlass(RoundedCornerShape(50), tint)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(contentPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** Small glass badge used on cards (date, duration, counts) — iOS `.stashyGlass(shape: Capsule())`. */
@Composable
fun GlassBadge(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    Row(
        modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.45f))
            .border(0.5.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(50))
            .padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (icon != null) Icon(icon, null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(12.dp))
        Text(text, style = IosTypography.caption.copy(fontWeight = FontWeight.Medium), color = Color.White, maxLines = 1)
    }
}

/** Back pill used by detail screens (iOS hides the nav bar and shows a glass back button). */
@Composable
fun BackPill(onClick: () -> Unit, modifier: Modifier = Modifier) {
    GlassIconButton(Icons.AutoMirrored.Filled.ArrowBackIos, "Back", modifier, onClick = onClick)
}

/** Section header like the dashboard rows ("Scenes - Recently Added ›"). */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    Row(
        modifier
            .fillMaxWidth()
            .let { if (onClick != null) it.noRippleClickable(onClick) else it }
            .padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = IosTypography.title2, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onClick != null) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Chevron, null, tint = p.secondaryText, modifier = Modifier.size(20.dp))
        }
    }
}

/** Selectable chrome chip: selected = tinted glass capsule with label, else icon-only glass circle. */
@Composable
fun ChromeChip(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    if (selected) {
        GlassCapsule(modifier, tint = Color.White.copy(alpha = 0.28f), onClick = onClick) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
            Text(label, style = IosTypography.headline.copy(fontWeight = FontWeight.Medium), color = Color.White)
        }
    } else {
        GlassIconButton(icon, label, modifier, onClick = onClick)
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String? = null, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(48.dp))
        Text(title, style = IosTypography.title3, color = p.text)
        if (message != null) Text(message, style = IosTypography.subheadline, color = p.secondaryText)
    }
}

/**
 * Native Material 3 top tab strip (Android look) — replaces the iOS glass chip strips on
 * Home (catalogs), Tools, Settings and Feeds. Sits under the status bar; [transparent] for the
 * Feeds overlay on video. [selected] = null hides the indicator.
 */
@Composable
fun <T> NativeTabStrip(
    items: List<T>,
    selected: T?,
    title: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    transparent: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    val p = Theme.palette
    val container = if (transparent) Color.Black.copy(alpha = 0.55f) else p.background
    val index = items.indexOf(selected).takeIf { it >= 0 }
    androidx.compose.foundation.layout.Column(
        modifier.fillMaxWidth().background(container)
            .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.statusBars),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.ScrollableTabRow(
                selectedTabIndex = index ?: 0,
                modifier = Modifier.weight(1f),
                containerColor = Color.Transparent,
                contentColor = if (transparent) Color.White else p.text,
                edgePadding = 8.dp,
                divider = {},
                indicator = { positions ->
                    if (index != null && index < positions.size) {
                        androidx.compose.material3.TabRowDefaults.PrimaryIndicator(
                            Modifier.tabIndicatorOffset(positions[index]),
                            width = 32.dp,
                            color = if (transparent) Color.White else Appearance.tint.takeIf { it != StashyColors.defaultTint } ?: p.text,
                        )
                    }
                },
            ) {
                items.forEachIndexed { i, item ->
                    val isSelected = i == index
                    androidx.compose.material3.Tab(
                        selected = isSelected,
                        onClick = { onSelect(item) },
                        text = {
                            Text(
                                title(item),
                                style = androidx.compose.material3.MaterialTheme.typography.titleSmall,
                                maxLines = 1,
                            )
                        },
                        selectedContentColor = if (transparent) Color.White else p.text,
                        unselectedContentColor = if (transparent) Color.White.copy(alpha = 0.7f) else p.secondaryText,
                    )
                }
            }
            if (trailing != null) {
                trailing()
                Spacer(Modifier.width(4.dp))
            }
        }
        if (!transparent) Box(Modifier.fillMaxWidth().height(0.5.dp).background(p.separator))
    }
}

private fun Modifier.tabIndicatorOffset(position: androidx.compose.material3.TabPosition): Modifier =
    with(androidx.compose.material3.TabRowDefaults) { this@tabIndicatorOffset.tabIndicatorOffset(position) }
