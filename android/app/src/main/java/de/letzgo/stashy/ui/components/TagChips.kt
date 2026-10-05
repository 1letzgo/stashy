package de.letzgo.stashy.ui.components

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.ChipColors
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme

/**
 * Native Material 3 tag chips — one look for every tag row (Feeds overlay, image viewer, Pics posts).
 * iOS: the `#tag` capsules + `AITagSuggestionBar` chips of `reelsInfoOverlay` / `ImageGroupCatalogCell.tagRow`.
 *
 * Metrics: 32 dp chips (Material default) in a 40 dp row — the touch target is held at 40 dp
 * ([TagChipRowHeight]) instead of 48 dp so the row stays compact; 8 dp between chips.
 */
object TagChips {
    /** Visual chip height (Material 3 default). */
    val chipHeight = 32.dp
    /** Row height incl. the touch target around the 32 dp chip. */
    val rowHeight = 40.dp
    val spacing = 8.dp
    /** Visual gap the 40 dp touch target already adds above / below the chip. */
    val touchInset = (rowHeight - chipHeight) / 2
}

/** Where the chips sit: on a picture / video ([OverMedia]) or on a themed card ([Surface]). */
enum class TagChipStyle { OverMedia, Surface }

/** iOS `showsTagRow`: Tag Suggestion (stashy+) and the manual "+" share the row, so it also exists for an untagged item. */
fun showsTagRow(tags: List<IdName>, editMode: Boolean = Appearance.isEditModeEnabled): Boolean =
    tags.isNotEmpty() || editMode || AITagSuggestions.isActive

/**
 * The shared tag row: pinned "Add tag" chip (edit mode, [onAddTag]), then the tags and the
 * inline [suggestions] in one horizontal scroll — fresh scroll position per [itemId]
 * (iOS `.id(item.id)`). Long press on a tag offers "Remove tag" in edit mode when [onRemoveTag]
 * is set and [canRemove] allows it. Callers decide visibility ([showsTagRow]).
 */
@Composable
fun TagChipRow(
    itemId: String,
    tags: List<IdName>,
    modifier: Modifier = Modifier,
    style: TagChipStyle = TagChipStyle.OverMedia,
    editMode: Boolean = Appearance.isEditModeEnabled,
    onAddTag: (() -> Unit)? = null,
    onTagClick: (IdName) -> Unit = {},
    onRemoveTag: ((IdName) -> Unit)? = null,
    canRemove: (IdName) -> Boolean = { true },
    suggestions: (@Composable RowScope.() -> Unit)? = null,
) {
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides TagChips.rowHeight) {
        Row(
            // Min height, not fixed: chips grow with the font scale and must not be clipped.
            modifier.fillMaxWidth().heightIn(min = TagChips.rowHeight),
            horizontalArrangement = Arrangement.spacedBy(TagChips.spacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (editMode && onAddTag != null) AddTagChip(style, onAddTag)
            key(itemId) {
                Row(
                    Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(TagChips.spacing),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    tags.forEach { tag ->
                        key(tag.id) {
                            TagChip(
                                tag = tag,
                                style = style,
                                onClick = { onTagClick(tag) },
                                onRemove = if (editMode && onRemoveTag != null && canRemove(tag)) ({ onRemoveTag(tag) }) else null,
                            )
                        }
                    }
                    suggestions?.invoke(this)
                }
            }
        }
    }
}

/** "+" → `AssistChip` with the Add icon; opens `AddTagsSheet`. */
@Composable
fun AddTagChip(style: TagChipStyle, onClick: () -> Unit) {
    AssistChip(
        onClick = onClick,
        label = { Text("Add tag", style = MaterialTheme.typography.labelLarge, maxLines = 1) },
        leadingIcon = { Icon(SF.plus, null, Modifier.size(AssistChipDefaults.IconSize)) },
        colors = tagChipColors(style),
        border = tagChipBorder(style),
    )
}

/** One existing tag: `AssistChip` `#name`; long press → "Remove tag" (iOS context menu) when [onRemove] is set. */
@Composable
fun TagChip(tag: IdName, style: TagChipStyle, onClick: () -> Unit, onRemove: (() -> Unit)?) {
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    Box {
        AssistChip(
            onClick = onClick,
            label = { Text("#${tag.name.orEmpty()}", style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            colors = tagChipColors(style),
            border = tagChipBorder(style),
            modifier = if (onRemove != null) Modifier.onLongPress {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                menu = true
            } else Modifier,
        )
        DropdownMenu(menu, { menu = false }, containerColor = Theme.palette.secondaryBackground) {
            DropdownMenuItem(
                { Text("Remove tag", color = StashyColors.systemRed) },
                leadingIcon = { Icon(SF.trash, null, tint = StashyColors.systemRed) },
                onClick = { menu = false; onRemove?.invoke() },
            )
        }
    }
}

/**
 * One Tag Suggestion: `SuggestionChip` with the sparkles (spinner while it is being added),
 * `#name` and the confidence; tinted so it reads as a suggestion next to the tags.
 */
@Composable
fun TagSuggestionChip(
    name: String,
    detail: String?,
    style: TagChipStyle,
    accepting: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    onLongPress: () -> Unit,
) {
    val colors = suggestionChipColors(style)
    SuggestionChip(
        onClick = onClick,
        enabled = enabled,
        label = {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("#$name", style = MaterialTheme.typography.labelLarge, maxLines = 1)
                if (detail != null) {
                    Text(detail, style = MaterialTheme.typography.labelSmall, color = colors.labelColor.copy(alpha = 0.6f), maxLines = 1)
                }
            }
        },
        icon = {
            if (accepting) {
                CircularProgressIndicator(Modifier.size(14.dp), color = colors.labelColor, strokeWidth = 1.5.dp)
            } else {
                Icon(SF.sparkles, null, Modifier.size(SuggestionChipDefaults.IconSize))
            }
        },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = colors.container,
            labelColor = colors.labelColor,
            iconContentColor = colors.labelColor,
            // A pending accept disables the row; keep the chips readable meanwhile.
            disabledContainerColor = colors.container,
            disabledLabelColor = colors.labelColor.copy(alpha = 0.6f),
            disabledIconContentColor = colors.labelColor,
        ),
        border = SuggestionChipDefaults.suggestionChipBorder(enabled = true, borderColor = colors.border),
        modifier = Modifier.onLongPress(onLongPress),
    )
}

/** Hint text in the row ("No tag suggestions"), vertically centred like the chips. */
@Composable
fun TagRowHint(text: String, style: TagChipStyle) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = if (style == TagChipStyle.OverMedia) Color.White.copy(alpha = 0.6f) else Theme.palette.secondaryText,
        maxLines = 1,
    )
}

// MARK: - Colours

@Composable
private fun tagChipColors(style: TagChipStyle): ChipColors = when (style) {
    TagChipStyle.OverMedia -> AssistChipDefaults.assistChipColors(
        containerColor = Color.Black.copy(alpha = 0.45f),
        labelColor = Color.White,
        leadingIconContentColor = Color.White,
    )
    TagChipStyle.Surface -> AssistChipDefaults.assistChipColors(
        containerColor = Color.Transparent,
        labelColor = Theme.palette.text,
        leadingIconContentColor = de.letzgo.stashy.ui.nativeAccent(),
    )
}

@Composable
private fun tagChipBorder(style: TagChipStyle) = AssistChipDefaults.assistChipBorder(
    enabled = true,
    borderColor = if (style == TagChipStyle.OverMedia) Color.White.copy(alpha = 0.25f) else Theme.palette.separator,
)

private data class SuggestionColors(val container: Color, val labelColor: Color, val border: Color)

@Composable
private fun suggestionChipColors(style: TagChipStyle): SuggestionColors {
    val tint = Appearance.tint
    return when (style) {
        TagChipStyle.OverMedia -> SuggestionColors(tint.copy(alpha = 0.35f), Color.White, tint.copy(alpha = 0.6f))
        TagChipStyle.Surface -> SuggestionColors(tint.copy(alpha = 0.18f), Theme.palette.text, tint.copy(alpha = 0.5f))
    }
}

// MARK: - Long press

/**
 * Long press on a Material chip, whose own `onClick` cannot take one: watches the gesture in the
 * initial pass (before the chip's clickable), fires after the long-press timeout and then eats
 * the rest of the gesture so the tap does not fire too. Movement beyond touch slop (scrolling
 * the row) cancels it.
 */
internal fun Modifier.onLongPress(onLongPress: () -> Unit): Modifier = composed {
    val current by rememberUpdatedState(onLongPress)
    Modifier.pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val slop = viewConfiguration.touchSlop
            val finished = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                while (true) {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    val change = event.changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull true
                    if (!change.pressed || change.isConsumed) return@withTimeoutOrNull true
                    if ((change.position - down.position).getDistance() > slop) return@withTimeoutOrNull true
                }
                @Suppress("UNREACHABLE_CODE") true
            }
            if (finished == null) {
                current()
                do {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    event.changes.forEach { it.consume() }
                } while (event.changes.any { it.pressed })
            }
        }
    }
}
