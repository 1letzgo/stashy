package de.letzgo.stashy.ui.feeds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.FeedSortKinds
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortFieldKind
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import kotlinx.serialization.json.JsonObject

/**
 * Integration points for other ports. The full criteria editor lives in `ui/filter/`; when it
 * registers here, the Feeds Filter & Sort sheet shows it below the playback card (iOS:
 * `FilterCriteriaEditorView(document:onChange:)`) and every change refetches the feed.
 */
object FeedsUiHooks {
    /**
     * `(filterMode, criteria, onChange)`: [filterMode] is the GraphQL `FilterMode` of the active
     * Feeds mode (`SCENES`, `SCENE_MARKERS`, `IMAGES`); [criteria] the current criteria (GraphQL
     * entity-filter shape, layered over the selected saved filter); `onChange(null)` clears.
     */
    var criteriaEditor: (@Composable (filterMode: String, criteria: JsonObject?, onChange: (JsonObject?) -> Unit) -> Unit)? = null
}

private val labelColumnWidth = 80.dp

/** iOS: `catalogFilterSortControlCardChrome()`. */
@Composable
private fun ControlCard(content: @Composable () -> Unit) {
    val p = Theme.palette
    Box(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().heightIn(min = 52.dp)
            .clip(RoundedCornerShape(12.dp)).background(p.secondaryBackground)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

@Composable
private fun CardLabel(text: String) {
    Text(text, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Theme.palette.secondaryText, modifier = Modifier.width(labelColumnWidth), maxLines = 1)
}

/** iOS: `CatalogFilterChip`. */
@Composable
private fun FilterChip(title: String, active: Boolean, onClick: () -> Unit) {
    val p = Theme.palette
    Text(
        title, fontSize = 13.sp, fontWeight = FontWeight.Medium,
        color = if (active) Color.White else p.text,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(if (active) Appearance.tint else p.background)
            .noIndicationClick(onClick).padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/** Menu-style picker (iOS `.pickerStyle(.menu)` — tint-coloured label, checkmark on the current row). */
@Composable
private fun <T> MenuPicker(label: String, options: List<T>, title: (T) -> String, selected: (T) -> Boolean, onPick: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(Modifier.noIndicationClick { open = true }, verticalAlignment = Alignment.CenterVertically) {
            Text(label, color = Appearance.tint, style = IosTypography.body, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(SF.chevronDown, null, tint = Appearance.tint, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            options.forEach { o ->
                DropdownMenuItem(
                    text = { Text(title(o)) },
                    trailingIcon = { if (selected(o)) Icon(SF.checkmark, null) },
                    onClick = { open = false; onPick(o) },
                )
            }
        }
    }
}

/** iOS: `CatalogFilterSortToggleRow`. */
@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    ControlCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CardLabel(label)
            Spacer(Modifier.weight(1f))
            Switch(checked, onChange, colors = SwitchDefaults.colors(checkedTrackColor = Appearance.tint))
        }
    }
}

/**
 * iOS: `SceneLiveFilterSheet` (Scenes, Markers, Previews) / `ImagesCatalogFilterSortSheet`
 * (Clips, Pics) as opened from the Feeds chrome: Filter · Sort · Feeds playback · criteria editor,
 * with the `CatalogSettingsSheetChromeBar` (Reset · Settings · Done) on top.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedsFilterSortSheet(
    mode: ReelsModeType,
    filters: List<SavedFilter>,
    selectedFilter: SavedFilter?,
    sort: FeedSort,
    sortOptions: List<FeedSort>,
    criteria: JsonObject?,
    onFilter: (SavedFilter?) -> Unit,
    onSort: (FeedSort) -> Unit,
    onCriteria: (JsonObject?) -> Unit,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    val p = Theme.palette
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, containerColor = p.background, dragHandle = null) {
        Column(Modifier.fillMaxSize()) {
            // iOS `CatalogSettingsSheetChromeBar`.
            Row(
                Modifier.fillMaxWidth().background(Color(0xFF1C1C1E)).padding(horizontal = FeedsDock.edgePadding, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(Modifier.chromePill().noIndicationClick(onReset).padding(horizontal = 14.dp), Alignment.Center) {
                    Text("Reset", color = Color(0xFFFF453A), style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold))
                }
                Text("Settings", color = Color.White, style = IosTypography.title3, modifier = Modifier.weight(1f), maxLines = 1)
                Box(Modifier.chromePill().noIndicationClick(onDismiss).padding(horizontal = 14.dp), Alignment.Center) {
                    Text("Done", color = Color.White, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold))
                }
            }
            HorizontalDivider(color = Color.White.copy(alpha = 0.15f))
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(top = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                // Filter
                ControlCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CardLabel("Filter")
                        Spacer(Modifier.weight(1f))
                        val options: List<SavedFilter?> = listOf<SavedFilter?>(null) + filters
                        MenuPicker(
                            label = selectedFilter?.name ?: "None",
                            options = options,
                            title = { it?.name ?: "None" },
                            selected = { it?.id == selectedFilter?.id },
                            onPick = { onFilter(it) },
                        )
                    }
                }
                // Sort (iOS `sortControlsCard` / `markerSortControlsCard`)
                ControlCard {
                    val kinds: List<SortFieldKind> = when (mode) {
                        ReelsModeType.Markers -> FeedSortKinds.marker
                        ReelsModeType.Clips, ReelsModeType.Pics -> FeedSortKinds.image
                        else -> FeedSortKinds.scene
                    }
                    val ascending = sort.direction == "ASC"
                    val random = sort.isRandom
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CardLabel("Sort")
                        Row(Modifier.alpha(if (random) 0.4f else 1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            FilterChip("Asc", ascending && !random) { if (!random) FeedSortKinds.option(sortOptions, sort.sortField, true)?.let(onSort) }
                            FilterChip("Desc", !ascending && !random) { if (!random) FeedSortKinds.option(sortOptions, sort.sortField, false)?.let(onSort) }
                        }
                        Spacer(Modifier.weight(1f).width(8.dp))
                        MenuPicker(
                            label = kinds.firstOrNull { it.field == sort.sortField }?.menuLabel ?: sort.sortField,
                            options = kinds,
                            title = { it.menuLabel },
                            selected = { it.field == sort.sortField },
                            onPick = { k ->
                                val asc = if (random) false else ascending
                                FeedSortKinds.option(sortOptions, k.field, asc)?.let(onSort)
                            },
                        )
                    }
                }
                // iOS `FeedsPlaybackSettingsCard` (not part of the Pics / Images sheet).
                if (mode != ReelsModeType.Pics) {
                    ToggleRow("Immersive", FeedsConfig.fillHeight) { FeedsConfig.updateFillHeight(it) }
                    ToggleRow("Continuous", FeedsConfig.continuousPlay) { FeedsConfig.updateContinuousPlay(it) }
                    ToggleRow("Delete button", FeedsConfig.showsDeleteButton) { FeedsConfig.updateShowsDeleteButton(it) }
                }
                FeedsUiHooks.criteriaEditor?.invoke(FeedsModel.filterModeFor(mode), criteria, onCriteria)
            }
        }
    }
}
