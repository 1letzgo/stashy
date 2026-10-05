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
import androidx.compose.material.icons.Icons
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeTextField
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

/** iOS: `StashyExpandingDock.circleSize` / `iconSize`. */
private val AddButtonSize = 48.dp
private val AddIconSize = 24.dp

/**
 * iOS: `FiltersToolsView` — Tools › Filters: every saved filter of the server grouped by mode,
 * with search, "+" (new filter per mode), edit (tap), rename and delete (long press; iOS also
 * offers them as swipe actions). Create/edit open [FiltersToolEditorSheet]; a newly created
 * filter reopens in the editor right after saving (iOS `pendingEditAfterCreate`).
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
    // iOS: `editingFilter` / `isCreating` + `createMode`.
    var editingEntry by remember { mutableStateOf<FiltersToolEntry?>(null) }
    var createMode by remember { mutableStateOf<String?>(null) }
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
            NativeSearchField(searchText, { searchText = it }, "Search filters", Modifier.weight(1f))
            FiltersAddMenu { mode -> createMode = mode }
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
                            if (sectionIndex > 0) item(key = "gap-${section.mode}") { Spacer(Modifier.height(20.dp)) }
                            item(key = "header-${section.mode}") {
                                NativeSectionHeader(FiltersLogic.modeTitle(section.mode))
                            }
                            item(key = "group-${section.mode}") {
                                NativeGroup {
                                    section.entries.forEachIndexed { index, entry ->
                                        if (index > 0) NativeDivider()
                                        FilterRow(
                                            entry = entry,
                                            onOpen = { editingEntry = entry },
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
    }

    editingEntry?.let { entry ->
        FiltersToolEditorSheet(entry = entry, createMode = entry.filter.mode ?: "SCENES", onDismiss = { editingEntry = null })
    }
    createMode?.let { mode ->
        FiltersToolEditorSheet(
            entry = null,
            createMode = mode,
            onDismiss = { createMode = null },
            // iOS: the new filter opens in the editor once the create sheet is gone.
            onSaved = { saved -> createMode = null; editingEntry = saved },
        )
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
 * One filter row of a grouped section: Material list item with name and criteria summary. Tap
 * opens the editor; long press shows Rename / Delete (iOS: context menu + swipe actions).
 */
@Composable
private fun FilterRow(
    entry: FiltersToolEntry,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
) {
    val p = Theme.palette
    val haptics = LocalHapticFeedback.current
    var menuOpen by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        NativeListItem(
            entry.filter.name,
            supporting = FiltersLogic.criteriaSummary(entry),
            supportingMaxLines = 1,
            onClick = onOpen,
            onLongClick = {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                menuOpen = true
            },
        )
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }, containerColor = p.secondaryBackground) {
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
            NativeTextField(text, onTextChange, label = null, placeholder = "Name", autoCorrect = true)
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
