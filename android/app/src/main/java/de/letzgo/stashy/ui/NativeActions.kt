package de.letzgo.stashy.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

// Material action building blocks for [NativeTopBar] (Android look of the pushed screens).
//
// Pattern (used by scene detail, the entity detail pages, the image viewers and downloads):
// - at most three frequent actions as `IconButton`s in the app bar (download state, sort,
//   favorite, share …), active states in `Appearance.tint` (destructive/favorite in red);
// - rarer or wordy actions (edit, card columns, delete in lists, set as performer image) go into
//   the trailing "⋮" overflow `DropdownMenu` ([TopBarOverflowMenu]);
// - pickers that were iOS `Menu`s (sort) open a `DropdownMenu` anchored to their icon
//   ([TopBarMenuAction]); confirmations are `AlertDialog`s.
// No floating glass slot bars on pushed screens any more.

/** One app bar action icon. [tint] null = the bar's content colour. */
@Composable
fun TopBarAction(
    icon: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    tint: Color? = null,
    enabled: Boolean = true,
    busy: Boolean = false,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick, modifier = modifier, enabled = enabled && !busy) {
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = tint ?: LocalContentColor.current, strokeWidth = 2.dp)
        else Icon(icon, contentDescription, tint = tint ?: LocalContentColor.current)
    }
}

/** App bar icon that opens a Material `DropdownMenu` anchored to it (sort pickers …). */
@Composable
fun TopBarMenuAction(
    icon: ImageVector,
    contentDescription: String,
    tint: Color? = null,
    content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        TopBarAction(icon, contentDescription, tint = tint) { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = Theme.palette.secondaryBackground) {
            content { open = false }
        }
    }
}

/** Trailing "⋮" overflow menu of the app bar. */
@Composable
fun TopBarOverflowMenu(content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit) {
    TopBarMenuAction(Icons.Filled.MoreVert, "More options", content = content)
}

/** One entry of [TopBarOverflowMenu]. */
@Composable
fun OverflowItem(
    label: String,
    icon: ImageVector? = null,
    dismiss: () -> Unit,
    color: Color? = null,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val c = color ?: Theme.palette.text
    DropdownMenuItem(
        text = { Text(label, color = if (enabled) c else c.copy(alpha = 0.38f)) },
        leadingIcon = icon?.let { { Icon(it, null, tint = if (enabled) c else c.copy(alpha = 0.38f)) } },
        enabled = enabled,
        onClick = { dismiss(); onClick() },
    )
}
