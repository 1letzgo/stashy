package de.letzgo.stashy.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.BackPill
import de.letzgo.stashy.ui.ChromeChip
import de.letzgo.stashy.ui.Chevron
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens

// iOS: `stashySettingsList()`, `stashyScrollingSectionHeader/Footer`, `stashyGroupedBlockRow`,
// `stashySettingsCardRow`, `stashySettingsDetailChrome` (SharedUtilities / SharedChromeComponents).

/** Height of the settings detail bar (Back · title). */
private val DetailBarHeight = 60.dp

/** iOS `stashySettingsList()` — 20pt side margins, 24pt between sections, room for the tab bar. */
@Composable
fun SettingsList(topPadding: Dp, modifier: Modifier = Modifier, content: LazyListScope.() -> Unit) {
    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = topPadding + 20.dp, bottom = TabBarClearance + 28.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
        content = content,
    )
}

/** One grouped section: uppercase header, rows in one rounded block with separators, footer. */
fun LazyListScope.settingsSection(
    header: String? = null,
    footer: String? = null,
    isBeta: Boolean = false,
    key: String? = null,
    rows: @Composable ColumnScope.() -> Unit,
) {
    item(key = key) {
        Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            if (header != null) SectionHeaderText(header, isBeta)
            SettingsGroup(content = rows)
            if (footer != null) SectionFooterText(footer)
        }
    }
}

@Composable
fun SectionHeaderText(text: String, isBeta: Boolean = false) {
    val p = Theme.palette
    Row(Modifier.padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text.uppercase(), style = IosTypography.footnote, color = p.secondaryText)
        if (isBeta) BetaBadge()
    }
}

@Composable
fun SectionFooterText(text: String) {
    Text(text, style = IosTypography.footnote, color = Theme.palette.secondaryText, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
}

/** iOS `StashyBetaBadge` — one implementation for Settings and Tools ("Beta", 10 pt bold). */
@Composable
fun BetaBadge() = de.letzgo.stashy.ui.tools.BetaBadge()

/** Rounded block (`stashyGroupedBlockRow`) — children get separators via [SettingsDivider]. */
@Composable
fun SettingsGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(Theme.palette.secondaryBackground, RoundedCornerShape(Tokens.Radius.small)),
        content = content,
    )
}

@Composable
fun SettingsDivider() = HorizontalDivider(Modifier.padding(start = 16.dp), thickness = 0.5.dp, color = Theme.palette.separator)

/** Base row: 16pt insets, ≥ 44pt high. */
@Composable
fun SettingsRow(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    verticalPadding: Dp = 11.dp,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 44.dp)
            .let { if (onClick != null && enabled) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

/** iOS `Label(title, systemImage:)` inside a row — tinted icon + primary text. */
@Composable
fun RowScope.SettingsLabel(title: String, icon: ImageVector? = null, color: Color = Theme.palette.text, iconTint: Color = Appearance.tint, modifier: Modifier = Modifier) {
    if (icon != null) Icon(icon, null, tint = iconTint, modifier = Modifier.size(22.dp))
    Text(title, style = IosTypography.body, color = color, modifier = modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
}

/** NavigationLink row with a chevron. */
@Composable
fun SettingsNavRow(title: String, icon: ImageVector? = null, trailing: String? = null, onClick: () -> Unit) {
    val p = Theme.palette
    SettingsRow(onClick = onClick) {
        SettingsLabel(title, icon)
        if (trailing != null) Text(trailing, style = IosTypography.body, color = p.secondaryText, maxLines = 1)
        Icon(Icons.Chevron, null, tint = p.tertiaryText, modifier = Modifier.size(20.dp))
    }
}

/** iOS `Toggle` tinted with the accent. */
@Composable
fun SettingsSwitch(checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Switch(
        checked, onChange, enabled = enabled,
        colors = SwitchDefaults.colors(
            checkedTrackColor = Appearance.tint, checkedThumbColor = Color.White, checkedBorderColor = Color.Transparent,
            uncheckedTrackColor = Theme.palette.separator, uncheckedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent,
        ),
    )
}

@Composable
fun SettingsToggleRow(title: String, checked: Boolean, icon: ImageVector? = null, subtitle: String? = null, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    SettingsRow(verticalPadding = 6.dp) {
        if (icon != null) Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = IosTypography.body, color = if (enabled) Theme.palette.text else Theme.palette.secondaryText)
            if (subtitle != null) Text(subtitle, style = IosTypography.caption, color = Theme.palette.secondaryText)
        }
        SettingsSwitch(checked, enabled, onChange)
    }
}

/** iOS menu `Picker` row — label left, current value + ⇅ right, options in a dropdown. */
@Composable
fun <T> SettingsPickerRow(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    SettingsRow(onClick = { open = true }, enabled = enabled) {
        SettingsLabel(title, icon, color = if (enabled) Theme.palette.text else Theme.palette.secondaryText)
        Box {
            MenuValueLabel(label(selected))
            OptionsMenu(open, { open = false }, options, selected, label, onSelect)
        }
    }
}

@Composable
fun MenuValueLabel(text: String, color: Color = Theme.palette.secondaryText) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = IosTypography.subheadline, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 200.dp))
        Icon(Icons.Filled.UnfoldMore, null, tint = color, modifier = Modifier.size(16.dp))
    }
}

@Composable
fun <T> OptionsMenu(expanded: Boolean, onDismiss: () -> Unit, options: List<T>, selected: T?, label: (T) -> String, onSelect: (T) -> Unit) {
    DropdownMenu(expanded, onDismiss, containerColor = Theme.palette.secondaryBackground) {
        options.forEach { o ->
            DropdownMenuItem(
                text = { Text(label(o), color = Theme.palette.text) },
                trailingIcon = { if (o == selected) Icon(Icons.Filled.Check, null, tint = Theme.palette.text) },
                onClick = { onSelect(o); onDismiss() },
            )
        }
    }
}

/**
 * A trailing menu (iOS `Menu { … } label: { Text(value) }`) for the card rows in Dashboard/Feeds
 * settings. [options] are (id, name).
 */
@Composable
fun MenuValue(options: List<Pair<String, String>>, currentId: String?, placeholder: String = "None", onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.clickable { open = true }) {
        MenuValueLabel(options.firstOrNull { it.first == currentId }?.second ?: currentId ?: placeholder)
        OptionsMenu(open, { open = false }, options, options.firstOrNull { it.first == currentId }, { it.second }) { onSelect(it.first) }
    }
}

/** iOS `settingRow(title) { trailing }` of the Dashboard / Feeds cards. */
@Composable
fun CardSettingRow(title: String, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 36.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = IosTypography.subheadline, color = Theme.palette.secondaryText, maxLines = 1, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** iOS `stashySettingsCardRow()` — a standalone rounded card with 4pt vertical gap. */
@Composable
fun SettingsCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().padding(vertical = 4.dp)
            .background(Theme.palette.secondaryBackground, RoundedCornerShape(Tokens.Radius.small))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        content = content,
    )
}

@Composable
fun RowProgress() = CircularProgressIndicator(Modifier.size(20.dp), color = Theme.palette.secondaryText, strokeWidth = 2.dp)

/**
 * iOS `stashySettingsDetailChrome(title)` — pushed settings page with a glass Back button and
 * the title in a floating bar; content scrolls underneath.
 */
@Composable
fun SettingsDetailScaffold(
    title: String,
    onBack: () -> Unit = { Nav.pop() },
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable (topPadding: Dp) -> Unit,
) {
    val p = Theme.palette
    val status = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        content(status + DetailBarHeight)
        Box(
            Modifier.fillMaxWidth()
                .background(Brush.verticalGradient(listOf(p.background, p.background.copy(alpha = 0.85f), Color.Transparent)))
                .padding(top = status).height(DetailBarHeight).padding(horizontal = 16.dp),
        ) {
            BackPill(onBack, Modifier.align(Alignment.CenterStart))
            Text(
                title, style = IosTypography.headline, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).padding(horizontal = 64.dp),
            )
            if (trailing != null) Box(Modifier.align(Alignment.CenterEnd)) { trailing() }
        }
    }
}

/** iOS `StashyChromeTrailingTextButton` (Save / Done …). */
@Composable
fun ChromeTextButton(title: String, enabled: Boolean = true, onClick: () -> Unit) {
    de.letzgo.stashy.ui.GlassCapsule(onClick = if (enabled) onClick else null, tint = if (enabled) Appearance.tint else null) {
        Text(title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = if (enabled) 1f else 0.5f))
    }
}

/**
 * iOS `stashySectionChrome` + `SettingsCategoryRow` — the floating chip strip over the
 * Settings tab (selected section as labelled capsule, the others as glass circles).
 */
@Composable
fun <T> SectionChipStrip(sections: List<T>, selected: T, icon: (T) -> ImageVector, title: (T) -> String, onSelect: (T) -> Unit) {
    de.letzgo.stashy.ui.NativeTabStrip(sections, selected, title, onSelect)
}

/** Primary filled button (iOS `PrimaryFilledButtonStyle`). */
@Composable
fun PrimaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, leading: ImageVector? = null, trailing: ImageVector? = null, onClick: () -> Unit) {
    Row(
        modifier.fillMaxWidth().height(52.dp)
            .background(if (enabled) Appearance.tint else Color.Gray.copy(alpha = 0.3f), RoundedCornerShape(Tokens.Radius.button))
            .let { if (enabled && !busy) it.clickable(onClick = onClick) else it },
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (busy) { CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)) }
        if (leading != null) { Icon(leading, null, tint = Color.White, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)) }
        Text(title, style = IosTypography.headline, color = Color.White)
        if (trailing != null) { Spacer(Modifier.width(6.dp)); Icon(trailing, null, tint = Color.White, modifier = Modifier.size(18.dp)) }
    }
}

/** iOS-style alert (title, message, OK). */
@Composable
fun SimpleAlert(title: String, message: String, onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { androidx.compose.material3.TextButton(onDismiss) { Text("OK", color = Appearance.tint) } },
        title = { Text(title) }, text = { Text(message) },
        containerColor = Theme.palette.secondaryBackground, titleContentColor = Theme.palette.text, textContentColor = Theme.palette.secondaryText,
    )
}

/** Confirmation with a destructive action. */
@Composable
fun ConfirmAlert(title: String, message: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { androidx.compose.material3.TextButton({ onConfirm(); onDismiss() }) { Text(confirm, color = Color(0xFFFF453A)) } },
        dismissButton = { androidx.compose.material3.TextButton(onDismiss) { Text("Cancel", color = Appearance.tint) } },
        title = { Text(title) }, text = { Text(message) },
        containerColor = Theme.palette.secondaryBackground, titleContentColor = Theme.palette.text, textContentColor = Theme.palette.secondaryText,
    )
}
