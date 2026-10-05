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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.IconButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme

/**
 * iOS: `ReelsModeSettingsView` (Settings → Feeds): per mode on/off, order, default sort and
 * default filter (same keys as iOS: `ReelsModesConfig_<server>`, `AppTabsConfig_<server>`).
 * The "Show Feeds Tab" toggle belongs to the tab configuration of the settings port. Reordering
 * uses up/down buttons instead of iOS' drag handles.
 */
class FeedsModeSettingsScreen : Screen {
    override val key = "settings-feeds"
    @Composable override fun Content() = FeedsModeSettings()
}

@Composable
fun FeedsModeSettings() {
    val p = Theme.palette
    var filters by remember { mutableStateOf<List<SavedFilter>?>(null) }
    LaunchedEffect(Unit) { filters = runCatching { FeedsRepository.savedFilters() }.getOrDefault(emptyList()) }
    val modes = FeedsConfig.modes
    Column(Modifier.fillMaxSize().background(p.background)) {
        Row(Modifier.statusBarsPadding().padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconButton({ Nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = p.text) }
            Text("Feeds", style = IosTypography.title3, color = p.text)
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Modes", style = IosTypography.footnote.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText)
            modes.forEachIndexed { index, cfg ->
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(p.secondaryBackground).padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(cfg.type.icon, null, tint = Appearance.tint, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(cfg.type.title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Appearance.tint, modifier = Modifier.weight(1f))
                        Icon(SF.chevronUp, "Move up", tint = p.secondaryText.copy(alpha = if (index > 0) 1f else 0.3f), modifier = Modifier.size(28.dp).noIndicationClick { if (index > 0) FeedsConfig.moveMode(index, index - 1) })
                        Icon(SF.chevronDown, "Move down", tint = p.secondaryText.copy(alpha = if (index < modes.lastIndex) 1f else 0.3f), modifier = Modifier.size(28.dp).noIndicationClick { if (index < modes.lastIndex) FeedsConfig.moveMode(index, index + 1) })
                        Spacer(Modifier.width(8.dp))
                        Switch(cfg.isEnabled, { FeedsConfig.toggleMode(cfg.type) }, colors = SwitchDefaults.colors(checkedTrackColor = Appearance.tint))
                    }
                    if (cfg.isEnabled) {
                        HorizontalDivider(Modifier.padding(vertical = 8.dp), color = p.separator)
                        SettingRow("Default Sort") {
                            val options = FeedsModel.sortOptions(cfg.type)
                            val current = FeedsModel.defaultSort(cfg.type)
                            SettingMenu(current.displayName, options.map { it.displayName to it.raw }, current.raw) { FeedsConfig.setDefaultSort(cfg.type, it) }
                        }
                        SettingRow("Default Filter") {
                            val list = filters?.filter { it.mode == FeedsModel.filterModeFor(cfg.type) }?.sortedBy { it.name }
                            val currentId = FeedsConfig.defaultFilterId(cfg.type)
                            if (list != null && list.isEmpty()) Text("No filters found", style = IosTypography.subheadline, color = p.secondaryText)
                            else SettingMenu(
                                list?.firstOrNull { it.id == currentId }?.name ?: "None",
                                listOf("None" to "") + list.orEmpty().map { it.name to it.id },
                                currentId ?: "",
                            ) { id -> FeedsConfig.setDefaultFilter(cfg.type, id.ifEmpty { null }, list?.firstOrNull { it.id == id }?.name) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingRow(title: String, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosTypography.subheadline, color = Theme.palette.secondaryText, modifier = Modifier.weight(1f), maxLines = 1)
        trailing()
    }
}

@Composable
private fun SettingMenu(label: String, options: List<Pair<String, String>>, selected: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Text(label, style = IosTypography.subheadline, color = Theme.palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.noIndicationClick { open = true })
        DropdownMenu(open, onDismissRequest = { open = false }) {
            options.forEach { (title, value) ->
                DropdownMenuItem(text = { Text(title) }, trailingIcon = { if (value == selected) Icon(SF.checkmark, null) }, onClick = { open = false; onPick(value) })
            }
        }
    }
}
