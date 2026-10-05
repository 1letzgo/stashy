package de.letzgo.stashy.ui.filter

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeGroupShape
import de.letzgo.stashy.ui.NativeSwitch
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.NativeValueLabel
import de.letzgo.stashy.ui.Tokens

/** iOS: `CatalogFilterSortSheetLayout`. */
object FilterSheetLayout {
    val labelColumnWidth = 80.dp
    /** Material list item height (Settings rows). */
    val controlCardMinHeight = 56.dp
}

/** True inside a [ControlGroup]: [ControlCard]s render as plain rows of that group. */
private val LocalControlCardInGroup = compositionLocalOf { false }

/** iOS: `catalogFilterSortControlCardChrome()` — a one-row Material group inside a 16 dp page margin. */
fun Modifier.controlCardChrome(): Modifier = this
    .padding(horizontal = 16.dp)
    .fillMaxWidth()
    .defaultMinSize(minHeight = FilterSheetLayout.controlCardMinHeight)
    .clip(NativeGroupShape)

/**
 * Several control rows in one Material group (Settings look) — put [ControlCard]s inside and
 * separate them with [NativeDivider].
 */
@Composable
fun ControlGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    NativeGroup(modifier.padding(horizontal = 16.dp)) {
        CompositionLocalProvider(LocalControlCardInGroup provides true) { content() }
    }
}

/** One control row (Material list item metrics); standalone it is its own rounded group. */
@Composable
fun ControlCard(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    val p = Theme.palette
    val base = if (LocalControlCardInGroup.current) {
        modifier.fillMaxWidth().defaultMinSize(minHeight = FilterSheetLayout.controlCardMinHeight)
    } else {
        modifier.controlCardChrome().background(p.secondaryBackground)
    }
    Row(
        base.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

/** Headline of the Filter / Sort / Type rows — Material list headline (bodyLarge), ≥ 80 wide. */
@Composable
fun ControlLabel(text: String) {
    Text(
        text, Modifier.widthIn(min = FilterSheetLayout.labelColumnWidth),
        style = NativeType.bodyLarge, color = Theme.palette.text, maxLines = 1,
    )
}

/** iOS: `CatalogFilterChip` — 13pt medium capsule, tint when active. */
@Composable
fun CatalogFilterChip(title: String, isActive: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val p = Theme.palette
    Text(
        title,
        modifier
            .clip(RoundedCornerShape(50))
            .background(if (isActive) Appearance.tint else p.secondaryBackground)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        fontSize = 13.sp, fontWeight = FontWeight.Medium,
        color = if (isActive) Color.White else p.text, maxLines = 1,
    )
}

/** One entry of a [MenuPicker]; `section` > 0 starts a divided group (iOS `Section` in a menu). */
data class MenuEntry<T>(val value: T, val label: String, val section: Int = 0)

/**
 * iOS: `Picker(...).pickerStyle(.menu)` — tinted current label with ⌃⌄ that opens a menu with a
 * checkmark on the selected entry.
 */
@Composable
fun <T> MenuPicker(
    selected: T,
    entries: List<MenuEntry<T>>,
    modifier: Modifier = Modifier,
    selectedLabel: String? = null,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val label = selectedLabel ?: entries.firstOrNull { it.value == selected }?.label ?: ""
    Box(modifier) {
        // Settings value-picker look: value + Material dropdown arrow.
        Box(Modifier.clip(RoundedCornerShape(8.dp)).clickable { open = true }.padding(start = 8.dp, top = 4.dp, bottom = 4.dp)) {
            NativeValueLabel(label)
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = Theme.palette.secondaryBackground) {
            var lastSection = entries.firstOrNull()?.section ?: 0
            entries.forEach { e ->
                if (e.section != lastSection) { HorizontalDivider(color = Theme.palette.separator); lastSection = e.section }
                DropdownMenuItem(
                    text = { Text(e.label, style = IosTypography.body, color = Theme.palette.text) },
                    trailingIcon = if (e.value == selected) ({ Icon(SF.checkmark, null, tint = Theme.palette.text) }) else null,
                    onClick = { open = false; onSelect(e.value) },
                )
            }
        }
    }
}

/** iOS: `filterEditorTextFieldChrome()` — plain field on the page colour, small radius. */
@Composable
fun FilterTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    onCommit: () -> Unit = {},
) {
    val p = Theme.palette
    var focused by remember { mutableStateOf(false) }
    BasicTextField(
        value, onValueChange,
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Tokens.Radius.small - 2.dp))
            .background(p.background)
            .onFocusChanged { if (focused && !it.isFocused) onCommit(); focused = it.isFocused }
            .padding(horizontal = 10.dp, vertical = 8.dp),
        textStyle = IosTypography.body.copy(color = p.text),
        singleLine = true,
        cursorBrush = SolidColor(Appearance.tint),
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { onCommit() }),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = IosTypography.body, color = p.tertiaryText)
                inner()
            }
        },
    )
}

/** Label + switch row in control-card chrome (iOS `CatalogFilterSortToggleRow`). */
@Composable
fun ControlToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    ControlCard {
        ControlLabel(label)
        Spacer(Modifier.weight(1f))
        NativeSwitch(checked, onChange)
    }
}
