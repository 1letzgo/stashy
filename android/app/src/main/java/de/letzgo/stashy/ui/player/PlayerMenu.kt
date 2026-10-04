package de.letzgo.stashy.ui.player

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Theme

/** iOS: `PlayerMenuItem` — rows of the player's "…" options menu, as data. */
sealed class PlayerMenuItem {
    abstract val id: String
    data class Separator(override val id: String, val title: String? = null) : PlayerMenuItem()
    data class Action(
        override val id: String,
        val title: String,
        val icon: ImageVector? = null,
        val isChecked: Boolean = false,
        val isDisabled: Boolean = false,
        val keepsMenuOpen: Boolean = false,
        val onClick: () -> Unit,
    ) : PlayerMenuItem()
    data class Info(override val id: String, val title: String, val icon: ImageVector? = null) : PlayerMenuItem()
    data class Submenu(override val id: String, val title: String, val icon: ImageVector? = null, val items: List<PlayerMenuItem>) : PlayerMenuItem()
}

/**
 * iOS: `PlayerMenuButton` (UIKit `UIMenu`). A dropdown whose submenus open in place with a back
 * row, like the iOS inline-expanding menus. [items] is re-evaluated on every recomposition, so
 * checkmarks follow the player state while it is open.
 */
@Composable
fun PlayerMenu(expanded: Boolean, onDismiss: () -> Unit, items: () -> List<PlayerMenuItem>) {
    val path = remember { mutableStateListOf<String>() }
    val p = Theme.palette
    DropdownMenu(expanded = expanded, onDismissRequest = { path.clear(); onDismiss() }) {
        var level = items()
        var title: String? = null
        for (id in path) {
            val sub = level.filterIsInstance<PlayerMenuItem.Submenu>().firstOrNull { it.id == id } ?: break
            level = sub.items; title = sub.title
        }
        if (title != null) {
            DropdownMenuItem(
                text = { Text(title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold)) },
                leadingIcon = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null) },
                onClick = { path.removeAt(path.lastIndex) },
            )
            HorizontalDivider()
        }
        level.forEach { item ->
            when (item) {
                is PlayerMenuItem.Separator -> {
                    HorizontalDivider()
                    item.title?.let { Text(it, Modifier.padding(horizontal = 16.dp, vertical = 6.dp), style = IosTypography.caption, color = p.secondaryText) }
                }
                is PlayerMenuItem.Info -> DropdownMenuItem(
                    text = { Text(item.title, color = p.secondaryText) },
                    leadingIcon = item.icon?.let { { Icon(it, null) } },
                    onClick = {}, enabled = false,
                )
                is PlayerMenuItem.Action -> DropdownMenuItem(
                    text = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(item.title)
                            if (item.isChecked) { Spacer(Modifier.width(8.dp)); Icon(Icons.Filled.Check, null, Modifier.size(16.dp)) }
                        }
                    },
                    leadingIcon = item.icon?.let { { Icon(it, null) } },
                    enabled = !item.isDisabled,
                    onClick = {
                        item.onClick()
                        if (!item.keepsMenuOpen) { path.clear(); onDismiss() }
                    },
                )
                is PlayerMenuItem.Submenu -> DropdownMenuItem(
                    text = { Text(item.title) },
                    leadingIcon = item.icon?.let { { Icon(it, null) } },
                    trailingIcon = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) },
                    onClick = { path.add(item.id) },
                )
            }
        }
    }
}
