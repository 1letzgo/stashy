package de.letzgo.stashy.ui.filter

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.ListLivePresetTag
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.stashyGlass

/**
 * iOS: the unified catalog "Settings" sheet (`PerformersCatalogFilterSortSheet`,
 * `SceneLiveFilterSheet`, `ImagesCatalogFilterSortSheet`, `GroupsCatalogFilterSortSheet` …):
 * chrome bar (Reset · Settings · Save · Done), Filter picker card (None / Stash saved filters /
 * on-device presets), Sort card, optional [extraCards], then the criteria editor.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogFilterSortSheet(
    controller: CatalogController<*>,
    extraCards: @Composable () -> Unit = {},
) {
    if (!controller.isSheetPresented) return
    val p = Theme.palette
    LaunchedEffect(Unit) { controller.onSheetAppear() }
    var showSaveChoice by remember { mutableStateOf(false) }
    var nameDialog by remember { mutableStateOf<NameDialog?>(null) }
    var showDelete by remember { mutableStateOf(false) }
    val hasPreset = controller.presetRow.isNotEmpty()

    ModalBottomSheet(
        onDismissRequest = { controller.isSheetPresented = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = p.background,
    ) {
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            SheetChromeBar(
                onReset = { controller.reset() },
                onSave = { showSaveChoice = true },
                onDone = { controller.isSheetPresented = false },
            )
            Spacer(Modifier.height(16.dp))
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                FilterPickerCard(controller)
                if (controller.mode == FilterMode.Groups) GroupSortCard(controller.sort) { controller.changeSort(it) }
                else SortCard(controller.mode, controller.sort) { controller.changeSort(it) }
                extraCards()
                FilterCriteriaEditor(controller.criteria, onChange = { controller.applyLive() })
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    if (showSaveChoice) SaveChoiceDialog(
        presetName = controller.selectedPresetName,
        hasPreset = hasPreset,
        onUpdate = { showSaveChoice = false; controller.saveOverwrite() },
        onSaveAs = { showSaveChoice = false; nameDialog = NameDialog.SaveAs },
        onRename = { showSaveChoice = false; nameDialog = NameDialog.Rename },
        onDelete = { showSaveChoice = false; showDelete = true },
        onCancel = { showSaveChoice = false },
    )
    nameDialog?.let { kind ->
        NameInputDialog(
            title = if (kind == NameDialog.SaveAs) "Save as new" else "Rename",
            message = if (kind == NameDialog.SaveAs) "Save the current sort, filter, and live criteria as a new Stash saved filter." else "Rename this preset or saved filter.",
            initial = if (kind == NameDialog.SaveAs) "" else controller.renameSeed,
            onSave = { name -> nameDialog = null; if (kind == NameDialog.SaveAs) controller.saveAs(name) else controller.rename(name) },
            onCancel = { nameDialog = null },
        )
    }
    if (showDelete) AlertDialog(
        onDismissRequest = { showDelete = false },
        title = { Text("Delete filter?") },
        text = { Text(controller.deleteConfirmationText) },
        confirmButton = { TextButton({ showDelete = false; controller.delete() }) { Text("Delete", color = StashyColors.systemRed) } },
        dismissButton = { TextButton({ showDelete = false }) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
    )
}

private enum class NameDialog { SaveAs, Rename }

/** iOS: `CatalogSettingsSheetChromeBar` — Reset (red) · "Settings" · Save · Done. */
@Composable
private fun SheetChromeBar(onReset: () -> Unit, onSave: () -> Unit, onDone: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ChromePill("Reset", StashyColors.systemRed, onReset)
        Text("Settings", Modifier.weight(1f), style = IosTypography.title3, color = Theme.palette.text, maxLines = 1)
        ChromePill("Save", Color.White, onSave)
        ChromePill("Done", Color.White, onDone)
    }
}

@Composable
private fun ChromePill(title: String, color: Color, onClick: () -> Unit) {
    Text(
        title,
        Modifier.stashyGlass(RoundedCornerShape(50)).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 9.dp),
        style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = color,
    )
}

/** iOS: `filterPickerCard` — None, server filters (section), local presets (section). */
@Composable
fun FilterPickerCard(controller: CatalogController<*>) {
    val entries = buildList {
        add(MenuEntry("", "None", 0))
        controller.serverFilters.forEach { add(MenuEntry(ListLivePresetTag.serverRow(it.id), it.name, 1)) }
        controller.localPresets.forEach { add(MenuEntry(ListLivePresetTag.localRow(it.id), it.name, 2)) }
    }
    ControlCard {
        ControlLabel("Filter")
        Spacer(Modifier.weight(1f))
        MenuPicker(
            controller.presetRow, entries,
            selectedLabel = entries.firstOrNull { it.value == controller.presetRow }?.label ?: controller.selectedFilter?.name ?: "None",
        ) { controller.selectPresetRow(it) }
    }
}

/**
 * iOS: `performerSortCard` / `sortControlsCard` — Asc / Desc chips (disabled for Random or an
 * unmapped server sort) and the sort field menu ("Other (field)" for unknown fields).
 */
@Composable
fun SortCard(mode: FilterMode, sort: SortOption, onChange: (SortOption) -> Unit) {
    val kinds = SortCatalog.fieldKinds(mode)
    val known = kinds.firstOrNull { it.field == sort.field }
    val orderDisabled = sort.isRandom || known == null
    ControlCard {
        ControlLabel("Sort")
        Row(Modifier.alpha(if (orderDisabled) 0.4f else 1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CatalogFilterChip("Asc", sort.isAscending && !orderDisabled) {
                if (!orderDisabled) SortCatalog.optionFor(mode, sort.field, true)?.let(onChange)
            }
            CatalogFilterChip("Desc", !sort.isAscending && !orderDisabled) {
                if (!orderDisabled) SortCatalog.optionFor(mode, sort.field, false)?.let(onChange)
            }
        }
        Spacer(Modifier.weight(1f))
        val entries = buildList {
            if (known == null) add(MenuEntry(sort.field, "Other (${sort.field})"))
            kinds.forEach { add(MenuEntry(it.field, it.menuLabel)) }
        }
        MenuPicker(sort.field, entries) { field ->
            if (kinds.any { it.field == field }) SortCatalog.optionAfterPickingField(mode, sort, field)?.let(onChange)
        }
    }
}

/** iOS: `GroupsCatalogFilterSortSheet` — "Sort" heading and a menu over every `GroupSortOption`. */
@Composable
private fun GroupSortCard(sort: SortOption, onChange: (SortOption) -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Sort", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Theme.palette.secondaryText)
        MenuPicker(sort.raw, SortCatalog.groups.map { MenuEntry(it.raw, it.label) }) { raw ->
            SortCatalog.option(FilterMode.Groups, raw)?.let(onChange)
        }
    }
}

/** iOS: `CatalogSettingsSheetChromeBar` save alert. */
@Composable
private fun SaveChoiceDialog(
    presetName: String?,
    hasPreset: Boolean,
    onUpdate: () -> Unit,
    onSaveAs: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
) {
    val p = Theme.palette
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Save filter") },
        text = {
            Column(Modifier.fillMaxWidth()) {
                if (hasPreset) DialogOption(presetName?.let { "Update \"$it\"" } ?: "Update", Appearance.tint, onUpdate)
                DialogOption("Save as new", Appearance.tint, onSaveAs)
                if (hasPreset) {
                    DialogOption("Rename", Appearance.tint, onRename)
                    DialogOption("Delete", StashyColors.systemRed, onDelete)
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onCancel) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.text,
    )
}

@Composable
private fun DialogOption(label: String, color: Color, action: () -> Unit) = Text(
    label, Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable(onClick = action).padding(vertical = 12.dp),
    style = IosTypography.body, color = color,
)

@Composable
private fun NameInputDialog(title: String, message: String, initial: String, onSave: (String) -> Unit, onCancel: () -> Unit) {
    val p = Theme.palette
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(message, style = IosTypography.footnote, color = p.secondaryText)
                OutlinedTextField(text, { text = it }, singleLine = true, placeholder = { Text("Name") }, keyboardOptions = KeyboardOptions.Default)
            }
        },
        confirmButton = { TextButton({ onSave(text) }, enabled = text.isNotBlank()) { Text("Save") } },
        dismissButton = { TextButton(onCancel) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.text,
    )
}

/** iOS: `imageMediaTypeCard` — Any / Image / Video. */
@Composable
fun ImageMediaTypeCard(kind: ImageListMediaKind, onChange: (ImageListMediaKind) -> Unit) {
    ControlCard {
        ControlLabel("Type")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            CatalogFilterChip("Any", kind == ImageListMediaKind.All) { onChange(ImageListMediaKind.All) }
            CatalogFilterChip("Image", kind == ImageListMediaKind.StillImage) { onChange(ImageListMediaKind.StillImage) }
            CatalogFilterChip("Video", kind == ImageListMediaKind.Video) { onChange(ImageListMediaKind.Video) }
        }
        Spacer(Modifier.weight(1f))
    }
}

/** iOS: `ImageListMediaKind` — live `path` regex criterion for `findImages`. */
enum class ImageListMediaKind {
    All, StillImage, Video;

    val pathCriterion: kotlinx.serialization.json.JsonObject? get() = when (this) {
        All -> null
        StillImage -> de.letzgo.stashy.data.criterion(STILL_REGEX, "MATCHES_REGEX")
        Video -> de.letzgo.stashy.data.criterion(VIDEO_REGEX, "MATCHES_REGEX")
    }

    companion object {
        const val STILL_REGEX = "(?i)\\.(jpe?g|png|webp|gif)$"
        const val VIDEO_REGEX = "(?i)\\.(mp4|mov|m4v|webm|mkv)$"
    }
}
