package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.ListLivePresetTag
import de.letzgo.stashy.data.LocalFilterPreset
import de.letzgo.stashy.ui.filter.NameInputDialog
import de.letzgo.stashy.ui.filter.SaveChoiceDialog
import de.letzgo.stashy.data.FeedSortKinds
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortFieldKind
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeSheetAction
import de.letzgo.stashy.ui.NativeSheetTopBar
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.filter.CatalogFilterChip
import de.letzgo.stashy.ui.filter.ControlCard
import de.letzgo.stashy.ui.filter.ControlLabel
import de.letzgo.stashy.ui.filter.ControlToggleRow
import de.letzgo.stashy.ui.filter.FilterCriteriaEditor
import de.letzgo.stashy.ui.filter.MenuEntry
import de.letzgo.stashy.ui.filter.MenuPicker
import de.letzgo.stashy.ui.stashyGlass

/**
 * iOS: `SceneLiveFilterSheet` (Scenes, Markers, Previews) / `ImagesCatalogFilterSortSheet`
 * (Clips) as opened from the Feeds chrome — same chrome and cards as the catalog sheet
 * (`ui/filter`): Reset · Settings · Done, Filter, Sort, the Feeds playback card
 * (`FeedsPlaybackSettingsCard`), then the criteria editor (`FilterCriteriaEditorView`) on the
 * mode's document ([FeedsModel.criteriaDocument]). Pics uses the Images catalog sheet itself
 * (see [PicsFeed]).
 *
 * The Filter menu lists None, the Stash saved filters and the on-device presets of the mode's
 * list (Scenes / Previews → scene filters, Markers → marker filters, Clips → image filters);
 * Save offers Update / Save as new / Rename / Delete like the catalog sheet (iOS
 * `reelsSaveSceneLivePresetOverwrite` & co., [FeedsModel.saveOverwrite]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedsFilterSortSheet(
    mode: ReelsModeType,
    filters: List<SavedFilter>,
    localPresets: List<LocalFilterPreset>,
    presetRow: String,
    presetName: String?,
    selectedFilter: SavedFilter?,
    sort: FeedSort,
    sortOptions: List<FeedSort>,
    onPresetRow: (String) -> Unit,
    onSaveOverwrite: () -> Unit,
    onSaveAs: (String) -> Unit,
    onRename: (String) -> Unit,
    onDelete: () -> Unit,
    deleteConfirmationText: () -> String,
    onSort: (FeedSort) -> Unit,
    onCriteriaChanged: () -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    val p = Theme.palette
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showSaveChoice by remember { mutableStateOf(false) }
    var nameDialog by remember { mutableStateOf<Boolean?>(null) } // true = Save as, false = Rename
    var showDelete by remember { mutableStateOf(false) }
    val hasPreset = presetRow.isNotEmpty()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = p.background) {
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            // iOS `CatalogSettingsSheetChromeBar`.
            de.letzgo.stashy.ui.filter.SheetChromeBar(onReset = onReset, onSave = { showSaveChoice = true }, onDone = onDismiss)
            Spacer(Modifier.height(8.dp))
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Column {
                    de.letzgo.stashy.ui.NativeSectionHeader(tr(R.string.action_filter_and_sort), Modifier.padding(horizontal = 16.dp))
                    de.letzgo.stashy.ui.filter.ControlGroup {
                        // Filter
                        ControlCard {
                            ControlLabel(tr(R.string.filter))
                            Spacer(Modifier.weight(1f))
                            // iOS `filterPickerCard`: None, Stash saved filters, on-device presets.
                            val entries = buildList {
                                add(MenuEntry("", tr(R.string.none), 0))
                                filters.forEach { add(MenuEntry(ListLivePresetTag.serverRow(it.id), it.name, 1)) }
                                localPresets.forEach { add(MenuEntry(ListLivePresetTag.localRow(it.id), it.name, 2)) }
                            }
                            MenuPicker(
                                presetRow, entries,
                                selectedLabel = entries.firstOrNull { it.value == presetRow }?.label ?: presetName ?: selectedFilter?.name ?: tr(R.string.none),
                            ) { onPresetRow(it) }
                        }
                        // Sort (iOS `sortControlsCard` / `markerSortControlsCard`)
                        val kinds: List<SortFieldKind> = when (mode) {
                            ReelsModeType.Markers -> FeedSortKinds.marker
                            ReelsModeType.Clips, ReelsModeType.Pics -> FeedSortKinds.image
                            else -> FeedSortKinds.scene
                        }
                        val ascending = sort.direction == "ASC"
                        val random = sort.isRandom
                        de.letzgo.stashy.ui.NativeDivider()
                        ControlCard {
                            ControlLabel(tr(R.string.action_sort))
                            Row(Modifier.alpha(if (random) 0.4f else 1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                CatalogFilterChip(tr(R.string.asc), ascending && !random) { if (!random) FeedSortKinds.option(sortOptions, sort.sortField, true)?.let(onSort) }
                                CatalogFilterChip(tr(R.string.desc), !ascending && !random) { if (!random) FeedSortKinds.option(sortOptions, sort.sortField, false)?.let(onSort) }
                            }
                            Spacer(Modifier.weight(1f))
                            MenuPicker(sort.sortField, kinds.map { MenuEntry(it.field, it.menuLabel) }) { field ->
                                val asc = if (random) false else ascending
                                FeedSortKinds.option(sortOptions, field, asc)?.let(onSort)
                            }
                        }
                    }
                }
                // iOS `FeedsPlaybackSettingsCard`.
                de.letzgo.stashy.ui.filter.ControlGroup {
                    ControlToggleRow(tr(R.string.immersive), FeedsConfig.fillHeight) { FeedsConfig.updateFillHeight(it) }
                    de.letzgo.stashy.ui.NativeDivider()
                    ControlToggleRow(tr(R.string.continuous), FeedsConfig.continuousPlay) { FeedsConfig.updateContinuousPlay(it) }
                    // "Delete button" lives in Settings › Feeds (app UI, not a per-feed filter option).
                }
                androidx.compose.runtime.key(mode, selectedFilter?.id, presetRow) {
                    FilterCriteriaEditor(FeedsModel.criteriaDocument(mode), onChange = onCriteriaChanged)
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    if (showSaveChoice) SaveChoiceDialog(
        presetName = presetName,
        hasPreset = hasPreset,
        onUpdate = { showSaveChoice = false; onSaveOverwrite() },
        onSaveAs = { showSaveChoice = false; nameDialog = true },
        onRename = { showSaveChoice = false; nameDialog = false },
        onDelete = { showSaveChoice = false; showDelete = true },
        onCancel = { showSaveChoice = false },
    )
    nameDialog?.let { saveAs ->
        NameInputDialog(
            title = if (saveAs) tr(R.string.action_save_as_new) else tr(R.string.action_rename),
            message = when {
                !saveAs -> tr(R.string.hint_renames_selected_stash_saved_filter)
                mode == ReelsModeType.Markers -> tr(R.string.hint_creates_new_marker_filter_on)
                mode == ReelsModeType.Clips -> tr(R.string.hint_saves_sort_filters_and_live)
                else -> tr(R.string.hint_creates_new_scene_filter_on)
            },
            initial = if (saveAs) "" else presetName.orEmpty(),
            onSave = { name -> nameDialog = null; if (saveAs) onSaveAs(name) else onRename(name) },
            onCancel = { nameDialog = null },
        )
    }
    if (showDelete) AlertDialog(
        onDismissRequest = { showDelete = false },
        title = { Text(tr(R.string.confirm_delete_filter)) },
        text = { Text(deleteConfirmationText()) },
        confirmButton = { TextButton({ showDelete = false; onDelete() }) { Text(tr(R.string.action_delete), color = StashyColors.systemRed) } },
        dismissButton = { TextButton({ showDelete = false }) { Text(tr(R.string.action_cancel)) } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
    )
}
