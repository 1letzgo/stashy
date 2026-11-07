package de.letzgo.stashy.ui.tools

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.MenuItemColors
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Chevron
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent

// iOS: `ToolsBreadcrumbRow`, `ToolsBreadcrumbContext`, `toolsBreadcrumbChrome` and
// `ToolsRowMenuLabel` (MainTabView.swift). Built like the Home breadcrumb
// (`ui/catalog/HomeBreadcrumb.kt`): grid › tool menu, the tool's own control at the right.

/** iOS: `ToolsBreadcrumbContext` — what a tool needs to draw the Tools row itself. */
class ToolsBreadcrumbContext(
    val tools: List<ToolsTab>,
    val current: ToolsTab,
    /** null = back to the grid. */
    val onSelect: (ToolsTab?) -> Unit,
)

/**
 * iOS: `EnvironmentValues.toolsBreadcrumb` — set by the Tools tab for a tool that draws the row
 * itself ([ToolsBreadcrumbChrome]) with its own control at the right; null everywhere else.
 */
val LocalToolsBreadcrumb = compositionLocalOf<ToolsBreadcrumbContext?> { null }

/**
 * iOS: `toolsBreadcrumbChrome(_:trailing:)` — the Tools row with [trailing] at the right edge.
 * Draws nothing outside the Tools tab. Call it last inside the tool's full-screen Box so it sits
 * on top, at the top edge.
 */
@Composable
fun ToolsBreadcrumbChrome(trailing: @Composable () -> Unit = {}) {
    val context = LocalToolsBreadcrumb.current ?: return
    ToolsBreadcrumbStrip(context, trailing)
}

/**
 * iOS: `ToolsBreadcrumbRow` on a tool page — Tools (grid, not highlighted; tap = back to the
 * grid) › a tinted menu named after the open tool, then the tool's control at the right edge.
 */
@Composable
fun ToolsBreadcrumbStrip(context: ToolsBreadcrumbContext, trailing: @Composable () -> Unit = {}) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxWidth().background(p.background)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { context.onSelect(null) }) {
                Icon(SF.squareGrid2x2, "Tools", tint = p.secondaryText)
            }
            Icon(Icons.Chevron, null, tint = p.tertiaryText, modifier = Modifier.size(18.dp))
            ToolMenu(context)
            Spacer(Modifier.weight(1f))
            trailing()
            Spacer(Modifier.width(4.dp))
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(p.separator))
    }
}

/** iOS: `toolMenu(_:)` — the open tool's name, tinted; the menu lists every tool. */
@Composable
private fun ToolMenu(context: ToolsBreadcrumbContext) {
    var open by remember { mutableStateOf(false) }
    val current = context.current
    Box {
        Row(
            Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(12.dp)).clickable { open = true }
                .padding(horizontal = 10.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Tool, ${current.title}" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(current.title, style = MaterialTheme.typography.titleSmall, color = nativeAccent(), maxLines = 1)
            Icon(SF.chevronUpChevronDown, null, tint = nativeAccent(), modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            context.tools.forEach { tool ->
                ToolsMenuItem(tool.title, tool.icon, checked = tool == current) {
                    open = false
                    if (tool != current) context.onSelect(tool)
                }
            }
        }
    }
}

/**
 * iOS: `ToolsRowMenuLabel` + `Menu` — the control at the right of the Tools row, built like the
 * Home sort menu: [icon] (plus an optional [secondaryIcon]) and the up/down chevron; a tint dot
 * when [isActive] (the control narrows what is shown). [content] fills the dropdown and gets a
 * `dismiss` callback.
 */
@Composable
fun ToolsRowMenu(
    icon: ImageVector,
    accessibilityLabel: String,
    secondaryIcon: ImageVector? = null,
    isActive: Boolean = false,
    enabled: Boolean = true,
    content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit,
) {
    val p = Theme.palette
    val accent = nativeAccent()
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(12.dp))
                .clickable(enabled = enabled) { open = true }
                .padding(horizontal = 8.dp)
                .semantics(mergeDescendants = true) { contentDescription = accessibilityLabel },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            val color = if (enabled) p.text else p.tertiaryText
            BadgedBox(badge = { if (isActive) Badge(containerColor = accent) }) {
                Icon(icon, null, tint = color, modifier = Modifier.size(22.dp))
            }
            if (secondaryIcon != null) Icon(secondaryIcon, null, tint = color, modifier = Modifier.size(14.dp))
            Icon(SF.chevronUpChevronDown, null, tint = color, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            content { open = false }
        }
    }
}

/** iOS: `ToolsRowMenuOption` — one choice of a tool's section menu (Charts' Scenes / Performers …). */
class ToolsRowMenuOption<T>(val value: T, val title: String, val icon: ImageVector)

/**
 * iOS: `ToolsRowPickerMenu` — a tool's section switch as a menu in the Tools row (it was a pill
 * row above the content): the current section's icon collapsed, every section with icon, title
 * and checkmark open. [onSelect] only fires for a different value; haptics are the caller's.
 */
@Composable
fun <T> ToolsRowPickerMenu(
    title: String,
    options: List<ToolsRowMenuOption<T>>,
    selection: T,
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) {
    val current = options.firstOrNull { it.value == selection }
    ToolsRowMenu(
        icon = current?.icon ?: SF.squareGrid2x2,
        accessibilityLabel = "$title, ${current?.title.orEmpty()}",
        enabled = enabled,
    ) { dismiss ->
        options.forEach { option ->
            ToolsMenuItem(option.title, option.icon, checked = option.value == selection) {
                dismiss()
                if (option.value != selection) onSelect(option.value)
            }
        }
    }
}

/** Menu item colours: text, icon and checkmark in the normal content colour, never the accent. */
@Composable
fun toolsMenuItemColors(): MenuItemColors {
    val p = Theme.palette
    return MenuDefaults.itemColors(textColor = p.text, leadingIconColor = p.text, trailingIconColor = p.text)
}

/** One menu entry: icon, title and a trailing checkmark when [checked] (like the Home menus). */
@Composable
fun ToolsMenuItem(title: String, icon: ImageVector?, checked: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, maxLines = 1) },
        leadingIcon = if (icon != null) ({ Icon(icon, null) }) else null,
        trailingIcon = { if (checked) Icon(SF.checkmark, null) },
        onClick = onClick,
        enabled = enabled,
        colors = toolsMenuItemColors(),
    )
}

/** iOS menu `Section("…")` header. */
@Composable
fun ToolsMenuSectionHeader(title: String) {
    Text(
        title, style = MaterialTheme.typography.labelMedium, color = Theme.palette.secondaryText,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 4.dp),
    )
}
