package de.letzgo.stashy.ui.tools.filters

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.FiltersLogic
import de.letzgo.stashy.data.tools.FiltersToolEntry
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Chevron
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsBottomPadding
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.showToast
import de.letzgo.stashy.ui.tools.toolsTopPadding

private const val EditorUnavailable = "Filter editor not available yet"

/** iOS: `StashyExpandingDock.circleSize` / `iconSize`. */
private val AddButtonSize = 40.dp
private val AddIconSize = 18.dp

/**
 * iOS: `FiltersToolsView` — Tools › Filters: every saved filter of the server grouped by mode,
 * with search, "+" (new filter per mode), edit (tap), rename and delete (long press; iOS also
 * offers them as swipe actions). Create/edit open the filter editor through [FiltersToolHooks].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FiltersToolView() {
    val p = Theme.palette
    val state = FiltersToolState
    val serverId = ServerConfigManager.activeConfig?.id
    var searchText by remember { mutableStateOf("") }
    var renameTarget by remember { mutableStateOf<FiltersToolEntry?>(null) }
    var renameText by remember { mutableStateOf("") }
    var deleteTarget by remember { mutableStateOf<FiltersToolEntry?>(null) }
    var pulled by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    // iOS: `.onAppear { viewModel.fetchSavedFilters() }` (+ a fresh list per server).
    LaunchedEffect(serverId) {
        state.syncServer(serverId)
        if (serverId != null) state.refresh()
    }
    LaunchedEffect(state.isLoading) { if (!state.isLoading) pulled = false }

    val grouped = FiltersLogic.grouped(state.filters.values, searchText)

    Column(Modifier.fillMaxSize().background(p.background)) {
        // iOS: `FiltersToolsSearchChromeModifier` — search field + "+" menu pinned on top.
        Row(
            Modifier.fillMaxWidth().padding(
                start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding,
                top = toolsTopPadding() + ToolsTokens.menuTopPadding, bottom = Tokens.Spacing.xs + 2.dp,
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
        ) {
            FiltersSearchField("Search filters", searchText, { searchText = it }, Modifier.weight(1f))
            FiltersAddMenu { mode ->
                val hook = FiltersToolHooks.onCreateFilter
                if (hook != null) hook(mode) else showToast(EditorUnavailable)
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                serverId == null -> NoServerPlaceholder(SF.line3HorizontalDecrease, "Connect to a Stash server to manage your saved filters.")
                state.isLoading && state.filters.isEmpty() -> FiltersLoadingView("Loading filters…")
                grouped.isEmpty() -> FiltersEmptyState(searchText.isEmpty())
                else -> PullToRefreshBox(
                    isRefreshing = pulled && state.isLoading,
                    onRefresh = { pulled = true; state.refresh() },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(
                            start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding,
                            top = Tokens.Spacing.sm, bottom = ToolsBottomPadding,
                        ),
                    ) {
                        grouped.forEachIndexed { sectionIndex, section ->
                            if (sectionIndex > 0) item(key = "gap-${section.mode}") { Spacer(Modifier.height(Tokens.Spacing.md)) }
                            item(key = "header-${section.mode}") {
                                // iOS: footnote, secondary, uppercase, zero row insets.
                                Text(
                                    FiltersLogic.modeTitle(section.mode).uppercase(),
                                    style = IosTypography.footnote, color = p.secondaryText,
                                    modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                                )
                            }
                            val count = section.entries.size
                            section.entries.forEachIndexed { index, entry ->
                                item(key = "filter-${entry.filter.id}") {
                                    FilterRow(
                                        entry = entry,
                                        isFirst = index == 0,
                                        isLast = index == count - 1,
                                        onOpen = {
                                            val hook = FiltersToolHooks.onEditSavedFilter
                                            if (hook != null) hook(entry.filter) else showToast(EditorUnavailable)
                                        },
                                        onRename = { renameTarget = entry; renameText = entry.filter.name },
                                        onDelete = { deleteTarget = entry },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    renameTarget?.let { target ->
        RenameFilterDialog(
            text = renameText,
            onTextChange = { renameText = it },
            onDismiss = { renameTarget = null },
            onSave = {
                if (renameText.trim().isNotEmpty()) {
                    state.rename(target, renameText) { result ->
                        renameTarget = null
                        result.onSuccess { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
                            .onFailure { showToast("Rename failed: ${it.message}", long = true) }
                    }
                }
                renameTarget = null
            },
        )
    }

    deleteTarget?.let { target ->
        StashyAlert(
            title = "Delete filter?",
            message = "Delete “${target.filter.name}” from the server?",
            onDismiss = { deleteTarget = null },
            confirmLabel = "Delete",
            destructive = true,
            dismissLabel = "Cancel",
            onConfirm = {
                deleteTarget = null
                state.delete(target) { result ->
                    result.onSuccess { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
                        .onFailure { showToast("Delete failed: ${it.message}", long = true) }
                }
            },
        )
    }
}

/**
 * One filter row of an inset-grouped section: name, criteria summary, chevron. Tap opens the
 * editor; long press shows Rename / Delete (iOS: context menu + swipe actions).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FilterRow(
    entry: FiltersToolEntry,
    isFirst: Boolean,
    isLast: Boolean,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val p = Theme.palette
    val haptics = LocalHapticFeedback.current
    var menuOpen by remember { mutableStateOf(false) }
    val r = Tokens.Radius.small
    val shape = RoundedCornerShape(
        topStart = if (isFirst) r else 0.dp, topEnd = if (isFirst) r else 0.dp,
        bottomStart = if (isLast) r else 0.dp, bottomEnd = if (isLast) r else 0.dp,
    )
    Box(Modifier.fillMaxWidth().clip(shape).background(p.secondaryBackground, shape)) {
        Column {
            if (!isFirst) {
                // iOS: `listRowSeparatorTint(Color.primary.opacity(0.15))`, inset like the text.
                Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(p.text.copy(alpha = 0.15f)))
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 44.dp)
                    .combinedClickable(
                        onClick = onOpen,
                        onLongClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            menuOpen = true
                        },
                    )
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(entry.filter.name, style = IosTypography.body.copy(fontWeight = FontWeight.Medium), color = p.text)
                    Text(
                        FiltersLogic.criteriaSummary(entry),
                        style = IosTypography.caption, color = p.secondaryText,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                Icon(Icons.Chevron, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text("Rename", color = p.text) },
                leadingIcon = { Icon(SF.pencil, null, tint = p.text) },
                onClick = { menuOpen = false; onRename() },
            )
            DropdownMenuItem(
                text = { Text("Delete", color = StashyColors.systemRed) },
                leadingIcon = { Icon(SF.trash, null, tint = StashyColors.systemRed) },
                onClick = { menuOpen = false; onDelete() },
            )
        }
    }
}

/** iOS: `ToolsSearchField`. */
@Composable
private fun FiltersSearchField(prompt: String, text: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Row(
        modifier
            .clip(RoundedCornerShape(Tokens.Radius.card))
            .background(p.secondaryBackground)
            .padding(horizontal = Tokens.Spacing.sm, vertical = Tokens.Spacing.xs + 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
    ) {
        Icon(SF.magnifyingglass, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
        Box(Modifier.weight(1f)) {
            if (text.isEmpty()) Text(prompt, style = IosTypography.body, color = p.secondaryText, maxLines = 1)
            BasicTextField(
                value = text,
                onValueChange = onChange,
                singleLine = true,
                textStyle = IosTypography.body.copy(color = p.text),
                cursorBrush = SolidColor(Appearance.tint),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (text.isNotEmpty()) {
            Icon(
                Icons.Filled.Cancel, "Clear search", tint = p.secondaryText,
                modifier = Modifier.size(18.dp).clip(CircleShape).clickable { onChange("") },
            )
        }
    }
}

/** iOS: `Menu { addMenuItems } label: { ToolsAddButtonLabel() }` — one entry per filter mode. */
@Composable
private fun FiltersAddMenu(onSelect: (mode: String) -> Unit) {
    val p = Theme.palette
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.size(AddButtonSize).clip(CircleShape).background(Appearance.tint).clickable { open = true },
            contentAlignment = Alignment.Center,
        ) {
            Icon(SF.plus, "New filter", tint = Color.White, modifier = Modifier.size(AddIconSize))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            FiltersLogic.listedModes.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(FiltersLogic.modeTitle(mode), color = p.text) },
                    onClick = { open = false; onSelect(mode) },
                )
            }
        }
    }
}

/** iOS: the "Rename filter" alert with a text field. */
@Composable
private fun RenameFilterDialog(text: String, onTextChange: (String) -> Unit, onDismiss: () -> Unit, onSave: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = p.secondaryBackground,
        titleContentColor = p.text,
        textContentColor = p.text,
        title = { Text("Rename filter", style = IosTypography.headline) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                singleLine = true,
                placeholder = { Text("Name", color = p.secondaryText) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = p.text, unfocusedTextColor = p.text,
                    focusedBorderColor = tint, unfocusedBorderColor = p.separator, cursorColor = tint,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = onSave) { Text("Save", color = tint, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel", color = tint) }
        },
    )
}

/** iOS: `StandardLoadingView(message:)`. */
@Composable
private fun FiltersLoadingView(message: String) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(color = p.text)
        Text(message, style = IosTypography.subheadline, color = p.secondaryText)
    }
}

/** iOS: `ContentUnavailableView` — "No filters" / "No matches". */
@Composable
private fun FiltersEmptyState(noSearch: Boolean) {
    val p = Theme.palette
    val icon: ImageVector = if (noSearch) SF.line3HorizontalDecrease else SF.magnifyingglass
    Column(
        Modifier.fillMaxSize().padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(48.dp))
        Spacer(Modifier.width(0.dp).height(4.dp))
        Text(
            if (noSearch) "No filters" else "No matches",
            style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text, textAlign = TextAlign.Center,
        )
        Text(
            if (noSearch) "Create a filter or sync from your Stash server." else "No filters match your search.",
            style = IosTypography.subheadline, color = p.secondaryText, textAlign = TextAlign.Center,
        )
    }
}
