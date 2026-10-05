package de.letzgo.stashy.ui.tools.filters

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CriteriaDocument
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.criteriaObjectFilter
import de.letzgo.stashy.data.filterMode
import de.letzgo.stashy.data.tools.FiltersEditorLogic
import de.letzgo.stashy.data.tools.FiltersLogic
import de.letzgo.stashy.data.tools.FiltersToolEntry
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.filter.ControlCard
import de.letzgo.stashy.ui.filter.ControlLabel
import de.letzgo.stashy.ui.filter.FilterCriteriaEditor
import de.letzgo.stashy.ui.filter.FilterPickerOptionsStore
import de.letzgo.stashy.ui.floatingShadow
import de.letzgo.stashy.ui.stashyGlass
import de.letzgo.stashy.ui.tools.showToast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/** iOS: `StashyExpandingDock.activeHeight` / `activeHorizontalPadding` / `iconSize`. */
private val PillHeight = 40.dp
private val PillPadding = 14.dp

/**
 * iOS: `FiltersToolsEditorSheet` — create or edit one saved filter: "Name" card, "Sort" card
 * (menu over every sort of the mode), then the full criteria editor titled with the mode. One
 * chrome bar (‹ Back · "Edit filter"/"New filter" · Save); Save opens the "Save filter" choice
 * (Update "<name>" / Save · Save as new · Delete · Cancel).
 *
 * [entry] null = new filter of [createMode] (raw Stash `FilterMode`). [onSaved] (create only)
 * receives the saved filter; without it a successful save dismisses the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FiltersToolEditorSheet(
    entry: FiltersToolEntry?,
    createMode: String,
    onDismiss: () -> Unit,
    onSaved: ((FiltersToolEntry) -> Unit)? = null,
) {
    val p = Theme.palette
    val filter = entry?.filter
    val mode = filter?.filterMode ?: FilterMode.from(createMode)
    val modeRaw = filter?.mode ?: createMode
    val document = remember(filter?.id, mode) { CriteriaDocument(mode, filter?.criteriaObjectFilter() ?: JsonObject(emptyMap())) }
    var name by remember(filter?.id) { mutableStateOf(filter?.name ?: "") }
    val sortChoices = remember(mode) { SortCatalog.choices(mode) }
    var selectedSort by remember(filter?.id, mode) { mutableStateOf(FiltersEditorLogic.initialSort(filter, mode)) }
    var isSaving by remember { mutableStateOf(false) }
    var showSaveChoice by remember { mutableStateOf(false) }
    var saveAsName by remember { mutableStateOf<String?>(null) }
    var showDelete by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val isExisting = filter != null
    val trimmedName = name.trim()

    fun save(existingId: String?, saveName: String) {
        val sort = selectedSort ?: return
        val input = FiltersEditorLogic.saveInput(
            mode, existingId, filter, saveName, sort, document.sanitizedObjectFilter, FilterPickerOptionsStore.knownLabels(),
        ) ?: return
        isSaving = true
        scope.launch {
            try {
                val saved = SavedFiltersRepository.save(input)
                // Catalogs, dashboard and Settings read the shared cache (iOS `viewModel.savedFilters`).
                SavedFiltersStore.byId[saved.id] = saved
                SavedFiltersStore.fetch()
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                FiltersToolState.refresh()
                isSaving = false
                val callback = onSaved
                if (callback != null) callback(FiltersToolEntry(saved, saved.filter)) else onDismiss()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                isSaving = false
                showToast("Save failed: ${e.message}", long = true)
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = p.background,
    ) {
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            EditorChromeBar(
                title = if (isExisting) "Edit filter" else "New filter",
                onBack = onDismiss,
                isSaving = isSaving,
                saveDimmed = trimmedName.isEmpty(),
                saveEnabled = trimmedName.isNotEmpty() || isExisting,
                onSave = { showSaveChoice = true },
            )
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 8.dp, bottom = Tokens.Spacing.xl),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                de.letzgo.stashy.ui.filter.ControlGroup {
                ControlCard {
                    ControlLabel("Name")
                    Box(Modifier.weight(1f)) {
                        if (name.isEmpty()) {
                            Text("Filter name", Modifier.fillMaxWidth(), style = de.letzgo.stashy.ui.NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.End)
                        }
                        BasicTextField(
                            value = name,
                            onValueChange = { name = it },
                            singleLine = true,
                            textStyle = de.letzgo.stashy.ui.NativeType.bodyLarge.copy(color = p.text, textAlign = TextAlign.End),
                            cursorBrush = SolidColor(Appearance.tint),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                if (sortChoices.isNotEmpty()) {
                    de.letzgo.stashy.ui.NativeDivider()
                    ControlCard {
                        ControlLabel("Sort")
                        Spacer(Modifier.weight(1f))
                        SortMenu(selectedSort?.raw, sortChoices.map { it.raw to it.label }, selectedSort?.label ?: "Select…") { raw ->
                            sortChoices.firstOrNull { it.raw == raw }?.let { selectedSort = it }
                        }
                    }
                }
                }
                FilterCriteriaEditor(document, onChange = {}, levelTitle = FiltersLogic.modeTitle(modeRaw))
            }
        }
    }

    if (showSaveChoice) {
        SaveFilterChoiceDialog(
            primaryLabel = if (isExisting) "Update \"${filter?.name ?: trimmedName}\"" else "Save",
            primaryEnabled = trimmedName.isNotEmpty(),
            showsDelete = isExisting,
            onPrimary = { showSaveChoice = false; save(filter?.id, trimmedName) },
            onSaveAs = { showSaveChoice = false; saveAsName = FiltersEditorLogic.saveAsSeed(trimmedName) },
            onDelete = { showSaveChoice = false; showDelete = true },
            onCancel = { showSaveChoice = false },
        )
    }

    saveAsName?.let { seed ->
        SaveAsDialog(
            initial = seed,
            onSave = { newName -> saveAsName = null; save(null, newName) },
            onCancel = { saveAsName = null },
        )
    }

    if (showDelete && entry != null) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("Delete filter?") },
            text = { Text("Delete “${entry.filter.name}” from the server?") },
            confirmButton = {
                TextButton({
                    showDelete = false
                    FiltersToolState.delete(entry) { result ->
                        result.onSuccess {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            SavedFiltersStore.byId.remove(entry.filter.id)
                            onDismiss()
                        }.onFailure { showToast("Delete failed: ${it.message}", long = true) }
                    }
                }) { Text("Delete", color = StashyColors.systemRed) }
            },
            dismissButton = { TextButton({ showDelete = false }) { Text("Cancel", color = Appearance.tint) } },
            containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
        )
    }
}

/**
 * iOS: `stashyModalSheetChrome(title, onBack:) { Save }` — Android: Material top app bar of a
 * full-screen editor via [de.letzgo.stashy.ui.NativeSheetTopBar] (close ✕ · title · "Save" text button).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EditorChromeBar(
    title: String,
    onBack: () -> Unit,
    isSaving: Boolean,
    saveDimmed: Boolean,
    saveEnabled: Boolean,
    onSave: () -> Unit,
) {
    de.letzgo.stashy.ui.NativeSheetTopBar(title, onClose = onBack) {
        if (isSaving) de.letzgo.stashy.ui.NativeSheetProgress()
        else de.letzgo.stashy.ui.NativeSheetAction("Save", enabled = saveEnabled, dimmed = saveDimmed, onClick = onSave)
    }
}

/** iOS: the Sort `Menu` — primary label with ⌃⌄, checkmark on the selected sort. */
@Composable
private fun SortMenu(selected: String?, entries: List<Pair<String, String>>, label: String, onSelect: (String) -> Unit) {
    val p = Theme.palette
    var open by remember { mutableStateOf(false) }
    Box {
        // Settings value-picker look: value + Material dropdown arrow.
        Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { open = true }.padding(start = 8.dp, top = 4.dp, bottom = 4.dp)) {
            de.letzgo.stashy.ui.NativeValueLabel(label)
        }
        DropdownMenu(open, onDismissRequest = { open = false }, Modifier.heightIn(max = 480.dp), containerColor = p.secondaryBackground) {
            entries.forEach { (raw, title) ->
                DropdownMenuItem(
                    text = { Text(title, style = IosTypography.body, color = p.text) },
                    leadingIcon = if (raw == selected) ({ Icon(SF.checkmark, null, tint = p.text) }) else null,
                    onClick = { open = false; onSelect(raw) },
                )
            }
        }
    }
}

/** iOS: the "Save filter" alert of the editor (same dialog as the catalog sheets). */
@Composable
private fun SaveFilterChoiceDialog(
    primaryLabel: String,
    primaryEnabled: Boolean,
    showsDelete: Boolean,
    onPrimary: () -> Unit,
    onSaveAs: () -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
) {
    val p = Theme.palette
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Save filter") },
        text = {
            Column(Modifier.fillMaxWidth()) {
                DialogOption(primaryLabel, if (primaryEnabled) Appearance.tint else p.secondaryText, primaryEnabled, onPrimary)
                DialogOption("Save as new", Appearance.tint, true, onSaveAs)
                if (showsDelete) DialogOption("Delete", StashyColors.systemRed, true, onDelete)
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onCancel) { Text("Cancel", color = Appearance.tint) } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.text,
    )
}

@Composable
private fun DialogOption(label: String, color: Color, enabled: Boolean, action: () -> Unit) = Text(
    label,
    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable(enabled = enabled, onClick = action).padding(vertical = 12.dp),
    style = IosTypography.body, color = color,
)

/** iOS: the "Save as new" alert with a name field. */
@Composable
private fun SaveAsDialog(initial: String, onSave: (String) -> Unit, onCancel: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Save as new", style = IosTypography.headline) },
        text = {
            NativeTextField(text, { text = it }, label = null, placeholder = "Name", autoCorrect = true)
        },
        confirmButton = { TextButton({ onSave(text) }) { Text("Save", color = tint, fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton(onCancel) { Text("Cancel", color = tint) } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.text,
    )
}
