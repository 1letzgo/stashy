package de.letzgo.stashy.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.clickable
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeButton
import de.letzgo.stashy.ui.NativeConfirmDialog
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeDropdownValue
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeGroupShape
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeOptionsMenu
import de.letzgo.stashy.ui.NativeSectionFooter
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.NativeSelectRow
import de.letzgo.stashy.ui.NativeSwitch
import de.letzgo.stashy.ui.NativeSwitchItem
import de.letzgo.stashy.ui.NativeTextButton
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.NativeValueLabel
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.nativeTopBarPadding

// iOS: `stashySettingsList()`, `stashyScrollingSectionHeader/Footer`, `stashyGroupedBlockRow`,
// `stashySettingsCardRow`, `stashySettingsDetailChrome` (SharedUtilities / SharedChromeComponents).
// Same structure and order as iOS, drawn with the native Material 3 helpers of `ui/Chrome.kt`
// (section header in the accent colour, grouped 16 dp surfaces, list items, M3 switches,
// radio dropdowns / selection dialogs, AlertDialogs, top app bar).

/** Settings list — 16 dp side margins, 20 dp between sections, room for the tab bar. */
@Composable
fun SettingsList(topPadding: Dp, modifier: Modifier = Modifier, content: LazyListScope.() -> Unit) {
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = topPadding + 12.dp, bottom = TabBarClearance + 28.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
        content = content,
    )
}

/** One grouped section: Material header, rows in one rounded surface with dividers, footer. */
fun LazyListScope.settingsSection(
    header: String? = null,
    footer: String? = null,
    isBeta: Boolean = false,
    key: String? = null,
    rows: @Composable ColumnScope.() -> Unit,
) {
    item(key = key) {
        Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
            if (header != null) SectionHeaderText(header, isBeta)
            SettingsGroup(content = rows)
            if (footer != null) SectionFooterText(footer)
        }
    }
}

@Composable
fun SectionHeaderText(text: String, isBeta: Boolean = false) =
    NativeSectionHeader(text, badge = if (isBeta) ({ BetaBadge() }) else null)

@Composable
fun SectionFooterText(text: String) = NativeSectionFooter(text)

/** iOS `StashyBetaBadge` — one implementation for Settings and Tools ("Beta", 10 pt bold). */
@Composable
fun BetaBadge() = de.letzgo.stashy.ui.tools.BetaBadge()

/** Rounded Material group — children get dividers via [SettingsDivider]. */
@Composable
fun SettingsGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) = NativeGroup(modifier, content)

@Composable
fun SettingsDivider() = NativeDivider()

/** Base row (custom content): 16 dp insets, ≥ 56 dp high like a Material list item. */
@Composable
fun SettingsRow(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    verticalPadding: Dp = 8.dp,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 56.dp)
            .let { if (onClick != null && enabled) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        content = content,
    )
}

/** Leading icon + headline inside a [SettingsRow]. */
@Composable
fun RowScope.SettingsLabel(title: String, icon: ImageVector? = null, color: Color = Theme.palette.text, iconTint: Color = Appearance.tint, modifier: Modifier = Modifier) {
    if (icon != null) Icon(icon, null, tint = iconTint, modifier = Modifier.size(24.dp))
    Text(title, style = NativeType.bodyLarge, color = color, modifier = modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
}

/** Navigation row (iOS NavigationLink): Material list item, [trailing] shown as supporting text. */
@Composable
fun SettingsNavRow(title: String, icon: ImageVector? = null, trailing: String? = null, onClick: () -> Unit) =
    NativeListItem(title, supporting = trailing, icon = icon, onClick = onClick)

/** Material 3 switch in the app colours. */
@Composable
fun SettingsSwitch(checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) = NativeSwitch(checked, onChange, enabled)

@Composable
fun SettingsToggleRow(title: String, checked: Boolean, icon: ImageVector? = null, subtitle: String? = null, enabled: Boolean = true, onChange: (Boolean) -> Unit) =
    NativeSwitchItem(title, checked, supporting = subtitle, icon = icon, enabled = enabled, onCheckedChange = onChange)

/** iOS menu `Picker` row — headline left, value + ▾ right; radio dropdown (or dialog for long lists). */
@Composable
fun <T> SettingsPickerRow(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) = NativeSelectRow(title, options, selected, label, icon = icon, enabled = enabled, onSelect = onSelect)

@Composable
fun MenuValueLabel(text: String, color: Color = Theme.palette.secondaryText) = NativeValueLabel(text)

@Composable
fun <T> OptionsMenu(expanded: Boolean, onDismiss: () -> Unit, options: List<T>, selected: T?, label: (T) -> String, onSelect: (T) -> Unit) =
    NativeOptionsMenu(expanded, onDismiss, options, selected, label, onSelect)

/** Title of the enclosing [CardSettingRow] (title of the selection dialog of a long [MenuValue]). */
private val LocalCardRowTitle = compositionLocalOf<String?> { null }

/**
 * A trailing menu (iOS `Menu { … } label: { Text(value) }`) for the card rows in Dashboard/Feeds
 * settings. [options] are (id, name). Material dropdown with radio items; long lists open a dialog.
 */
@Composable
fun MenuValue(options: List<Pair<String, String>>, currentId: String?, placeholder: String = "None", onSelect: (String) -> Unit) {
    val selected = options.firstOrNull { it.first == currentId }
    NativeDropdownValue(
        options, selected, { it.second },
        title = LocalCardRowTitle.current,
        placeholder = currentId ?: placeholder,
    ) { onSelect(it.first) }
}

/** iOS `settingRow(title) { trailing }` of the Dashboard / Feeds cards. */
@Composable
fun CardSettingRow(title: String, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = NativeType.bodyLarge, color = Theme.palette.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        CompositionLocalProvider(LocalCardRowTitle provides title) { trailing() }
    }
}

/** iOS `stashySettingsCardRow()` — a standalone rounded Material card with a 4 dp gap. */
@Composable
fun SettingsCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().padding(vertical = 4.dp)
            .background(Theme.palette.secondaryBackground, NativeGroupShape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        content = content,
    )
}

@Composable
fun RowProgress() = CircularProgressIndicator(Modifier.size(20.dp), color = nativeAccent(), strokeWidth = 2.dp)

/**
 * iOS `stashySettingsDetailChrome(title)` — pushed settings page under a Material top app bar
 * ([NativeTopBar]: back arrow, title, [trailing] actions); content scrolls underneath.
 */
@Composable
fun SettingsDetailScaffold(
    title: String,
    onBack: () -> Unit = { Nav.pop() },
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable (topPadding: Dp) -> Unit,
) {
    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        content(nativeTopBarPadding())
        NativeTopBar(title, onBack = onBack, actions = {
            if (trailing != null) Box(Modifier.padding(end = 8.dp), contentAlignment = Alignment.Center) { trailing() }
        })
    }
}

/** Top-bar text action (iOS `StashyChromeTrailingTextButton`: Save / Done …) — Material TextButton. */
@Composable
fun ChromeTextButton(title: String, enabled: Boolean = true, onClick: () -> Unit) = NativeTextButton(title, enabled = enabled, onClick = onClick)

/** The Settings tab's top tabs (Settings · Design · Server · stashy+) — Material tab strip. */
@Composable
fun <T> SectionChipStrip(sections: List<T>, selected: T, icon: (T) -> ImageVector, title: (T) -> String, onSelect: (T) -> Unit) {
    de.letzgo.stashy.ui.NativeTabStrip(sections, selected, title, onSelect)
}

/** Primary action (iOS `PrimaryFilledButtonStyle`) — Material filled [NativeButton], full width. */
@Composable
fun PrimaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, leading: ImageVector? = null, trailing: ImageVector? = null, onClick: () -> Unit) =
    NativeButton(title, modifier.fillMaxWidth(), enabled = enabled, busy = busy, leading = leading, trailing = trailing, onClick = onClick)

/** Information alert (title, message, OK) — Material AlertDialog. */
@Composable
fun SimpleAlert(title: String, message: String, onDismiss: () -> Unit) =
    NativeConfirmDialog(title, message, onDismiss, confirmLabel = "OK", dismissLabel = null)

/** Confirmation with a destructive action — Material AlertDialog, confirm in the error colour. */
@Composable
fun ConfirmAlert(title: String, message: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) =
    NativeConfirmDialog(title, message, onDismiss, confirmLabel = confirm, destructive = true, onConfirm = { onConfirm(); onDismiss() })
