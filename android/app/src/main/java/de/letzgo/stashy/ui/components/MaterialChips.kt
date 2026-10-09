package de.letzgo.stashy.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.scaledIconSize

/**
 * Material 3 replacements for the iOS capsules on regular app surfaces (Android look):
 * selectable pills → [SelectChip] (`FilterChip`), actions → [ActionChip] (`AssistChip`),
 * read-only info → [InfoLabel] (small `Surface` with `labelMedium`). Labels on top of a
 * picture / video keep using `NativeMediaLabel`.
 */

/** Selectable chip (`FilterChip`) in the app accent. [centered] = label fills the chip width (equal-width rows). */
@Composable
fun SelectChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
    centered: Boolean = false,
) {
    val p = Theme.palette
    val accent = nativeAccent()
    FilterChip(
        selected = selected,
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        label = {
            Text(
                label, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = if (centered) TextAlign.Center else null,
                modifier = if (centered) Modifier.fillMaxWidth() else Modifier,
            )
        },
        leadingIcon = icon?.let { { Icon(it, null, Modifier.size(scaledIconSize(FilterChipDefaults.IconSize))) } },
        trailingIcon = trailingIcon?.let { { Icon(it, null, Modifier.size(scaledIconSize(FilterChipDefaults.IconSize))) } },
        colors = FilterChipDefaults.filterChipColors(
            containerColor = Color.Transparent,
            labelColor = p.text,
            iconColor = p.secondaryText,
            selectedContainerColor = accent.copy(alpha = 0.18f),
            selectedLabelColor = p.text,
            selectedLeadingIconColor = accent,
            selectedTrailingIconColor = accent,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = enabled, selected = selected,
            borderColor = p.separator, selectedBorderColor = Color.Transparent,
        ),
    )
}

/** Action chip (`AssistChip`) with an optional accent-coloured leading icon. */
@Composable
fun ActionChip(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    /** Label/icon/border colour over a picture (e.g. white on a hero gradient); null = theme colours. */
    contentColor: Color? = null,
) {
    val p = Theme.palette
    AssistChip(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        label = { Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = icon?.let { { Icon(it, null, Modifier.size(scaledIconSize(AssistChipDefaults.IconSize))) } },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = Color.Transparent,
            labelColor = contentColor ?: p.text,
            leadingIconContentColor = contentColor ?: nativeAccent(),
        ),
        border = AssistChipDefaults.assistChipBorder(enabled = enabled, borderColor = contentColor?.copy(alpha = 0.5f) ?: p.separator),
    )
}

/**
 * Read-only Material label: small-shape `Surface` with `labelMedium` (+ optional icon).
 * [container] defaults to a light wash of [content]; [elevation] lifts it off a picture it overlaps.
 */
@Composable
fun InfoLabel(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    content: Color = Theme.palette.text,
    iconTint: Color = content,
    container: Color = content.copy(alpha = 0.1f),
    elevation: Dp = 0.dp,
) {
    InfoLabelSurface(modifier, container = container, content = content, elevation = elevation) {
        if (icon != null) Icon(icon, null, tint = iconTint, modifier = Modifier.size(scaledIconSize(14.dp)))
        Text(text, style = MaterialTheme.typography.labelMedium, color = content, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Container of [InfoLabel] for custom content (star rating …). */
@Composable
fun InfoLabelSurface(
    modifier: Modifier = Modifier,
    container: Color = Theme.palette.text.copy(alpha = 0.1f),
    content: Color = Theme.palette.text,
    elevation: Dp = 0.dp,
    body: @Composable () -> Unit,
) {
    Surface(modifier, shape = MaterialTheme.shapes.small, color = container, contentColor = content, shadowElevation = elevation) {
        Row(
            Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) { body() }
    }
}
