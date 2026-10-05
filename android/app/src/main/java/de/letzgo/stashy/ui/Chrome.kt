package de.letzgo.stashy.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.material3.Typography
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS: `stashyGlass(shape:)` / `stashyGlass(shape:tint:)` — Liquid Glass chrome. Android has no
 * backdrop blur for content behind a view, so this is a dark translucent wash plus the hairline
 * stroke iOS draws pre-26, scaled by the user's glass transparency setting.
 */
fun Modifier.stashyGlass(shape: Shape = CircleShape, tint: Color? = null): Modifier {
    // Without a backdrop blur the content behind must be mostly covered, or text under the
    // chrome stays readable through it. Transparency 1 (iOS "pure glass") → 80 % cover.
    val cover = 0.8f + (1f - Appearance.glassTransparency) * 0.18f
    // Tinted glass: the tint sits on top of the dark glass (translucent tints keep their alpha).
    val tintFill = tint?.let { if (it.alpha < 1f) it else it.copy(alpha = 0.6f) }
    return this
        .clip(shape)
        .background(Color(0xFF1C2433).copy(alpha = cover), shape)
        .let { m -> if (tintFill != null) m.background(tintFill, shape) else m }
        .border(0.5.dp, Color.White.copy(alpha = 0.22f), shape)
}

/** iOS: floating shadow (`DesignTokens.Shadow.floating`). */
fun Modifier.floatingShadow(shape: Shape = CircleShape) = this.shadow(6.dp, shape, ambientColor = Color.Black.copy(0.12f), spotColor = Color.Black.copy(0.12f))

/** iOS: `cardShadow()` */
fun Modifier.cardShadow(shape: Shape = RoundedCornerShape(Tokens.Radius.card)) = this.shadow(4.dp, shape, ambientColor = Color.Black.copy(0.1f), spotColor = Color.Black.copy(0.1f))

fun Modifier.noRippleClickable(onClick: () -> Unit): Modifier = this.clickable(
    interactionSource = MutableInteractionSource(), indication = null, onClick = onClick,
)

/** Circular glass icon button (iOS chrome FAB, 36pt by default). */
@Composable
fun GlassIconButton(
    icon: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    tint: Color? = null,
    iconTint: Color = Color.White,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(size)
            .floatingShadow()
            .stashyGlass(CircleShape, tint)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription, tint = iconTint, modifier = Modifier.size(size * 0.45f)) }
}

/** Glass capsule with icon + label (selected chip of the top strip, "Back" pill …). */
@Composable
fun GlassCapsule(
    modifier: Modifier = Modifier,
    tint: Color? = null,
    height: Dp = 44.dp,
    contentPadding: PaddingValues = PaddingValues(horizontal = 16.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier
            .height(height)
            .floatingShadow(RoundedCornerShape(50))
            .stashyGlass(RoundedCornerShape(50), tint)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(contentPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** Small label used on cards (date, duration, counts) — Android look: [NativeMediaLabel]. */
@Composable
fun GlassBadge(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null) =
    NativeMediaLabel(text, modifier, icon)

/** Back pill used by detail screens (iOS hides the nav bar and shows a glass back button). */
@Composable
fun BackPill(onClick: () -> Unit, modifier: Modifier = Modifier) {
    GlassIconButton(Icons.AutoMirrored.Filled.ArrowBackIos, "Back", modifier, onClick = onClick)
}

/** Section header like the dashboard rows ("Scenes - Recently Added ›"). */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    Row(
        modifier
            .fillMaxWidth()
            .let { if (onClick != null) it.noRippleClickable(onClick) else it }
            .padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = IosTypography.title2, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onClick != null) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Chevron, null, tint = p.secondaryText, modifier = Modifier.size(20.dp))
        }
    }
}

/** Selectable chrome chip: selected = tinted glass capsule with label, else icon-only glass circle. */
@Composable
fun ChromeChip(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    if (selected) {
        GlassCapsule(modifier, tint = Color.White.copy(alpha = 0.28f), onClick = onClick) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
            Text(label, style = IosTypography.headline.copy(fontWeight = FontWeight.Medium), color = Color.White)
        }
    } else {
        GlassIconButton(icon, label, modifier, onClick = onClick)
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, message: String? = null, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(modifier.padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(48.dp))
        Text(title, style = IosTypography.title3, color = p.text)
        if (message != null) Text(message, style = IosTypography.subheadline, color = p.secondaryText)
    }
}

/**
 * Native Material 3 top tab strip (Android look) — replaces the iOS glass chip strips on
 * Home (catalogs), Tools, Settings and Feeds. Sits under the status bar; [transparent] for the
 * Feeds overlay on video. [selected] = null hides the indicator. With [icon], tabs show only their
 * icon and the selected one icon + label (like the iOS chip strip).
 */
@Composable
fun <T> NativeTabStrip(
    items: List<T>,
    selected: T?,
    title: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    transparent: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    icon: ((T) -> androidx.compose.ui.graphics.vector.ImageVector)? = null,
    /** Icon mode only: this item stays fixed at the left edge, the others scroll past it (iOS `pinnedItemID`). */
    pinnedLeading: T? = null,
) {
    val p = Theme.palette
    val container = if (transparent) Color.Black.copy(alpha = 0.55f) else p.background
    val index = items.indexOf(selected).takeIf { it >= 0 }
    androidx.compose.foundation.layout.Column(
        modifier.fillMaxWidth().background(container)
            .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.statusBars),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) {
                CompactIconTabs(items, index, title, icon, onSelect, transparent, pinnedLeading, Modifier.weight(1f))
            } else
            androidx.compose.material3.ScrollableTabRow(
                selectedTabIndex = index ?: 0,
                modifier = Modifier.weight(1f),
                containerColor = Color.Transparent,
                contentColor = if (transparent) Color.White else p.text,
                edgePadding = 8.dp,
                divider = {},
                indicator = { positions ->
                    if (index != null && index < positions.size) {
                        androidx.compose.material3.TabRowDefaults.PrimaryIndicator(
                            Modifier.tabIndicatorOffset(positions[index]),
                            width = 32.dp,
                            color = if (transparent) Color.White else Appearance.tint.takeIf { it != StashyColors.defaultTint } ?: p.text,
                        )
                    }
                },
            ) {
                items.forEachIndexed { i, item ->
                    val isSelected = i == index
                    androidx.compose.material3.Tab(
                        selected = isSelected,
                        onClick = { onSelect(item) },
                        text = {
                            if (icon == null) {
                                Text(title(item), style = androidx.compose.material3.MaterialTheme.typography.titleSmall, maxLines = 1)
                            } else {
                                // Icon only, label only on the selected tab (iOS top strip).
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    modifier = Modifier.animateContentSize(),
                                ) {
                                    Icon(icon(item), if (isSelected) null else title(item), modifier = Modifier.size(22.dp))
                                    if (isSelected) Text(title(item), style = androidx.compose.material3.MaterialTheme.typography.titleSmall, maxLines = 1)
                                }
                            }
                        },
                        selectedContentColor = if (transparent) Color.White else p.text,
                        unselectedContentColor = if (transparent) Color.White.copy(alpha = 0.7f) else p.secondaryText,
                    )
                }
            }
            if (trailing != null) {
                trailing()
                Spacer(Modifier.width(4.dp))
            }
        }
        if (!transparent) Box(Modifier.fillMaxWidth().height(0.5.dp).background(p.separator))
    }
}

/**
 * Icon tabs for [NativeTabStrip]: icon only, the selected tab icon + label with the Material
 * primary indicator under it. Own row because ScrollableTabRow forces 90dp per tab, which spreads
 * icon-only tabs far apart. [pinned] sits outside the scrolling row at the left edge.
 */
@Composable
private fun <T> CompactIconTabs(
    items: List<T>,
    index: Int?,
    title: (T) -> String,
    icon: (T) -> androidx.compose.ui.graphics.vector.ImageVector,
    onSelect: (T) -> Unit,
    transparent: Boolean,
    pinned: T?,
    modifier: Modifier,
) {
    val p = Theme.palette
    val colors = CompactTabColors(
        selected = if (transparent) Color.White else p.text,
        unselected = if (transparent) Color.White.copy(alpha = 0.7f) else p.secondaryText,
        indicator = if (transparent) Color.White else Appearance.tint.takeIf { it != StashyColors.defaultTint } ?: p.text,
    )
    val pinnedItem = pinned?.takeIf { it in items }
    val scrolling = if (pinnedItem != null) items.filter { it != pinnedItem } else items
    val selectedItem = index?.let { items.getOrNull(it) }
    val scrollIndex = selectedItem?.let { scrolling.indexOf(it) }?.takeIf { it >= 0 }
    val state = androidx.compose.foundation.lazy.rememberLazyListState()
    androidx.compose.runtime.LaunchedEffect(scrollIndex) { scrollIndex?.let { state.animateScrollToItem((it - 1).coerceAtLeast(0)) } }
    Row(modifier.height(48.dp), verticalAlignment = Alignment.CenterVertically) {
        if (pinnedItem != null) {
            Spacer(Modifier.width(8.dp))
            CompactIconTab(pinnedItem, pinnedItem == selectedItem, title, icon, onSelect, colors)
        }
        androidx.compose.foundation.lazy.LazyRow(
            Modifier.weight(1f).height(48.dp),
            state = state,
            contentPadding = PaddingValues(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(scrolling.size) { i ->
                val item = scrolling[i]
                CompactIconTab(item, item == selectedItem, title, icon, onSelect, colors)
            }
        }
    }
}

private data class CompactTabColors(val selected: Color, val unselected: Color, val indicator: Color)

@Composable
private fun <T> CompactIconTab(
    item: T,
    isSelected: Boolean,
    title: (T) -> String,
    icon: (T) -> androidx.compose.ui.graphics.vector.ImageVector,
    onSelect: (T) -> Unit,
    colors: CompactTabColors,
) {
    val color = if (isSelected) colors.selected else colors.unselected
    Box(
        Modifier.height(48.dp).clip(RoundedCornerShape(12.dp))
            .clickable(role = androidx.compose.ui.semantics.Role.Tab) { onSelect(item) }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.animateContentSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon(item), if (isSelected) null else title(item), tint = color, modifier = Modifier.size(22.dp))
            if (isSelected) Text(title(item), style = androidx.compose.material3.MaterialTheme.typography.titleSmall, color = color, maxLines = 1)
        }
        if (isSelected) Box(
            Modifier.align(Alignment.BottomCenter).width(32.dp).height(3.dp)
                .background(colors.indicator, RoundedCornerShape(topStart = 3.dp, topEnd = 3.dp)),
        )
    }
}

private fun Modifier.tabIndicatorOffset(position: androidx.compose.material3.TabPosition): Modifier =
    with(androidx.compose.material3.TabRowDefaults) { this@tabIndicatorOffset.tabIndicatorOffset(position) }

/** Height of [NativeTopBar] below the status bar (Material small top app bar). */
val NativeTopBarHeight: Dp = 64.dp

/** Top padding for content under a [NativeTopBar] overlay (status bar + bar). */
@Composable
fun nativeTopBarPadding(): Dp =
    androidx.compose.foundation.layout.WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + NativeTopBarHeight

/**
 * Native Material 3 top app bar (Android look) — replaces the iOS "Back" glass pill and the
 * floating round chrome buttons on pushed screens. Back arrow left, [title], [actions] right
 * (use `androidx.compose.material3.IconButton`). [transparent] for screens with a hero/backdrop
 * (scrim instead of the solid background).
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun NativeTopBar(
    title: String,
    onBack: (() -> Unit)? = { Nav.pop() },
    modifier: Modifier = Modifier,
    transparent: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val p = Theme.palette
    val content = if (transparent) Color.White else p.text
    androidx.compose.material3.TopAppBar(
        title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = androidx.compose.material3.MaterialTheme.typography.titleLarge) },
        modifier = modifier,
        navigationIcon = {
            if (onBack != null) androidx.compose.material3.IconButton(onClick = onBack) {
                Icon(androidx.compose.material.icons.Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = content)
            }
        },
        actions = actions,
        colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
            containerColor = if (transparent) Color.Black.copy(alpha = 0.35f) else p.background,
            titleContentColor = content,
            navigationIconContentColor = content,
            actionIconContentColor = content,
        ),
    )
}

// MARK: - Native Material 3 building blocks (settings-style lists, menus, dialogs)
//
// Shared by Settings, Server setup, stashy+ and the tools' settings pages; reusable by every
// screen that moves to the native Android look. Colours come from `Theme.palette` and
// `Appearance.tint` ([nativeAccent]); type sizes from the Material 3 baseline scale
// ([NativeType]) — the app's own `MaterialTheme` typography maps the iOS Dynamic Type sizes.

/** Material 3 baseline type scale (bodyLarge 16 sp, bodyMedium 14 sp, titleSmall 14 sp medium …). */
val NativeType: Typography = Typography()

/** Shape of grouped Material surfaces (settings groups, cards). */
val NativeGroupShape: Shape = RoundedCornerShape(16.dp)

/** Accent for native controls: the user's tint; the iOS default gray falls back to the text colour. */
@Composable
fun nativeAccent(): Color = Appearance.tint.takeIf { it != StashyColors.defaultTint } ?: Theme.palette.text

/** Readable content colour on an [accent] fill (white on dark fills, dark on light ones). */
@Composable
fun onNativeAccent(accent: Color = nativeAccent()): Color {
    if (accent.luminance() <= 0.5f) return Color.White
    val bg = Theme.palette.background
    return if (bg.luminance() < 0.3f) bg else Color.Black
}

/** Material section header above a settings group: titleSmall in the accent colour (not uppercase). */
@Composable
fun NativeSectionHeader(title: String, modifier: Modifier = Modifier, badge: (@Composable () -> Unit)? = null) {
    Row(
        modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = NativeType.titleSmall, color = nativeAccent())
        badge?.invoke()
    }
}

/** Supporting text under a settings group (bodySmall, secondary). */
@Composable
fun NativeSectionFooter(text: String, modifier: Modifier = Modifier) {
    Text(
        text, style = NativeType.bodySmall, color = Theme.palette.secondaryText,
        modifier = modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp),
    )
}

/** Grouped Material surface (16 dp corners, secondary background). */
@Composable
fun NativeGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(NativeGroupShape).background(Theme.palette.secondaryBackground), content = content)
}

/** Divider between rows of a [NativeGroup]. */
@Composable
fun NativeDivider(startInset: Dp = 16.dp) =
    HorizontalDivider(Modifier.padding(start = startInset), thickness = 1.dp, color = Theme.palette.separator.copy(alpha = 0.5f))

/**
 * Material list item (like `ListItem`, sized for settings): optional leading icon (24 dp),
 * headline (bodyLarge), supporting text (bodyMedium), trailing content. 56 dp high, 72 dp with
 * supporting text. Whole row clickable when [onClick] is set.
 */
@Composable
fun NativeListItem(
    headline: String,
    modifier: Modifier = Modifier,
    supporting: String? = null,
    icon: ImageVector? = null,
    iconTint: Color = Appearance.tint,
    headlineColor: Color = Theme.palette.text,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    val p = Theme.palette
    val alpha = if (enabled) 1f else 0.38f
    Row(
        modifier.fillMaxWidth()
            .heightIn(min = if (supporting != null) 72.dp else 56.dp)
            .let { if (onClick != null) it.clickable(enabled = enabled, onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        when {
            leading != null -> leading()
            icon != null -> Icon(icon, null, tint = iconTint.copy(alpha = iconTint.alpha * alpha), modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(headline, style = NativeType.bodyLarge, color = headlineColor.copy(alpha = headlineColor.alpha * alpha), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (supporting != null) Text(supporting, style = NativeType.bodyMedium, color = p.secondaryText.copy(alpha = p.secondaryText.alpha * alpha), maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (trailing != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = trailing)
    }
}

/** Material 3 switch in the app colours. */
@Composable
fun NativeSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, enabled: Boolean = true) {
    val p = Theme.palette
    val accent = nativeAccent()
    val onAccent = onNativeAccent(accent)
    Switch(
        checked, onCheckedChange, enabled = enabled,
        colors = SwitchDefaults.colors(
            checkedTrackColor = accent, checkedThumbColor = onAccent, checkedBorderColor = accent,
            uncheckedTrackColor = p.background, uncheckedThumbColor = p.secondaryText, uncheckedBorderColor = p.secondaryText,
            disabledCheckedTrackColor = accent.copy(alpha = 0.38f), disabledCheckedThumbColor = onAccent.copy(alpha = 0.6f),
            disabledCheckedBorderColor = Color.Transparent,
            disabledUncheckedTrackColor = p.background.copy(alpha = 0.5f), disabledUncheckedThumbColor = p.secondaryText.copy(alpha = 0.38f),
            disabledUncheckedBorderColor = p.secondaryText.copy(alpha = 0.2f),
        ),
    )
}

/** List item with a trailing [NativeSwitch]; tapping the row toggles. */
@Composable
fun NativeSwitchItem(
    headline: String,
    checked: Boolean,
    modifier: Modifier = Modifier,
    supporting: String? = null,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    onCheckedChange: (Boolean) -> Unit,
) = NativeListItem(
    headline, modifier, supporting = supporting, icon = icon, enabled = enabled,
    onClick = { onCheckedChange(!checked) },
    trailing = { NativeSwitch(checked, onCheckedChange, enabled) },
)

/** Lists longer than this open a [NativeSelectionDialog] instead of an anchored dropdown. */
const val NativeMenuMaxItems = 8

/** Material radio button in the accent colour. */
@Composable
fun NativeRadio(selected: Boolean, onClick: (() -> Unit)? = null) {
    RadioButton(
        selected, onClick,
        colors = RadioButtonDefaults.colors(selectedColor = nativeAccent(), unselectedColor = Theme.palette.secondaryText),
    )
}

/** Anchored Material dropdown with radio-style items (put it in a `Box` with its anchor). */
@Composable
fun <T> NativeOptionsMenu(expanded: Boolean, onDismiss: () -> Unit, options: List<T>, selected: T?, label: (T) -> String, onSelect: (T) -> Unit) {
    DropdownMenu(expanded, onDismiss, containerColor = Theme.palette.secondaryBackground, shape = RoundedCornerShape(12.dp)) {
        options.forEach { o ->
            DropdownMenuItem(
                text = { Text(label(o), style = NativeType.bodyLarge, color = Theme.palette.text) },
                leadingIcon = { NativeRadio(o == selected) },
                onClick = { onSelect(o); onDismiss() },
            )
        }
    }
}

/** Material single-choice dialog (radio list) for long option lists, e.g. languages. Picking closes it. */
@Composable
fun <T> NativeSelectionDialog(title: String?, options: List<T>, selected: T?, label: (T) -> String, onDismiss: () -> Unit, onSelect: (T) -> Unit) {
    val p = Theme.palette
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = (options.indexOf(selected) - 3).coerceAtLeast(0))
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.text,
        title = title?.let { { Text(it, style = NativeType.headlineSmall) } },
        text = {
            LazyColumn(Modifier.heightIn(max = 440.dp), state = listState) {
                items(options.size) { i ->
                    val o = options[i]
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable { onSelect(o); onDismiss() },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeRadio(o == selected)
                        Spacer(Modifier.width(8.dp))
                        Text(label(o), style = NativeType.bodyLarge, color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onDismiss) { Text("Cancel", color = nativeAccent(), style = NativeType.labelLarge) } },
    )
}

/** Trailing value of a select row: current value + Material dropdown arrow (replaces iOS ⌃⌄). */
@Composable
fun NativeValueLabel(text: String, enabled: Boolean = true) {
    val c = Theme.palette.secondaryText.let { if (enabled) it else it.copy(alpha = it.alpha * 0.38f) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = NativeType.bodyMedium, color = c, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 180.dp))
        Icon(Icons.Filled.ArrowDropDown, null, tint = c, modifier = Modifier.size(24.dp))
    }
}

/**
 * Value label + its picker: an anchored radio dropdown for short lists, a [NativeSelectionDialog]
 * for lists longer than [NativeMenuMaxItems]. [open] is owned by the caller (row or label click).
 */
@Composable
fun <T> NativeValuePicker(
    open: Boolean,
    onOpenChange: (Boolean) -> Unit,
    title: String?,
    options: List<T>,
    selected: T?,
    label: (T) -> String,
    valueText: String = selected?.let(label) ?: "None",
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) {
    Box {
        NativeValueLabel(valueText, enabled)
        if (options.size <= NativeMenuMaxItems) NativeOptionsMenu(open, { onOpenChange(false) }, options, selected, label, onSelect)
    }
    if (open && options.size > NativeMenuMaxItems) NativeSelectionDialog(title, options, selected, label, { onOpenChange(false) }, onSelect)
}

/** Settings row with a value picker (iOS menu `Picker`): headline left, value + ▾ right. */
@Composable
fun <T> NativeSelectRow(
    headline: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    supporting: String? = null,
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    NativeListItem(
        headline, modifier, supporting = supporting, icon = icon, enabled = enabled, onClick = { open = true },
        trailing = { NativeValuePicker(open, { open = it }, headline, options, selected, label, enabled = enabled, onSelect = onSelect) },
    )
}

/** Standalone trailing dropdown (value + ▾) that opens its own menu/dialog on tap. */
@Composable
fun <T> NativeDropdownValue(
    options: List<T>,
    selected: T?,
    label: (T) -> String,
    modifier: Modifier = Modifier,
    title: String? = null,
    placeholder: String = "None",
    enabled: Boolean = true,
    onSelect: (T) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box(modifier.clip(RoundedCornerShape(8.dp)).clickable(enabled = enabled) { open = true }.padding(start = 8.dp, top = 4.dp, bottom = 4.dp)) {
        NativeValuePicker(open, { open = it }, title, options, selected, label, valueText = selected?.let(label) ?: placeholder, enabled = enabled, onSelect = onSelect)
    }
}

/**
 * Material 3 alert / confirmation: title, text, TextButton confirm (error colour when
 * [destructive]) and optional dismiss. [onConfirm] does not dismiss by itself.
 */
@Composable
fun NativeConfirmDialog(
    title: String,
    text: String?,
    onDismiss: () -> Unit,
    confirmLabel: String = "OK",
    destructive: Boolean = false,
    dismissLabel: String? = "Cancel",
    icon: ImageVector? = null,
    onConfirm: () -> Unit = onDismiss,
) {
    val p = Theme.palette
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
        iconContentColor = if (destructive) StashyColors.systemRed else nativeAccent(),
        icon = icon?.let { { Icon(it, null) } },
        title = { Text(title, style = NativeType.headlineSmall) },
        text = text?.let { { Text(it, style = NativeType.bodyMedium) } },
        confirmButton = {
            TextButton(onConfirm) {
                Text(confirmLabel, style = NativeType.labelLarge, color = if (destructive) StashyColors.systemRed else nativeAccent())
            }
        },
        dismissButton = dismissLabel?.let { { TextButton(onDismiss) { Text(it, style = NativeType.labelLarge, color = nativeAccent()) } } },
    )
}

/** Material outlined text field in the app colours (secret fields get a show/hide toggle). */
@Composable
fun NativeTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String?,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    secret: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    monospaced: Boolean = false,
    supportingText: String? = null,
    isError: Boolean = false,
    leadingIcon: ImageVector? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val p = Theme.palette
    val accent = nativeAccent()
    var revealed by remember { mutableStateOf(false) }
    OutlinedTextField(
        value, onValueChange, modifier.fillMaxWidth(),
        singleLine = true,
        textStyle = NativeType.bodyLarge.copy(fontFamily = if (monospaced) FontFamily.Monospace else null),
        label = label?.let { { Text(it) } },
        placeholder = placeholder?.let { { Text(it, maxLines = 1, overflow = TextOverflow.Ellipsis) } },
        leadingIcon = leadingIcon?.let { { Icon(it, null) } },
        trailingIcon = when {
            trailing != null -> trailing
            secret -> {
                {
                    IconButton({ revealed = !revealed }) {
                        Icon(if (revealed) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, if (revealed) "Hide" else "Show")
                    }
                }
            }
            else -> null
        },
        supportingText = supportingText?.let { { Text(it) } },
        isError = isError,
        visualTransformation = if (secret && !revealed) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (secret) KeyboardType.Password else keyboard, autoCorrectEnabled = false),
        shape = RoundedCornerShape(12.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = p.text, unfocusedTextColor = p.text,
            focusedBorderColor = accent, unfocusedBorderColor = p.secondaryText.copy(alpha = 0.5f),
            focusedLabelColor = accent, unfocusedLabelColor = p.secondaryText,
            cursorColor = accent, focusedPlaceholderColor = p.tertiaryText, unfocusedPlaceholderColor = p.tertiaryText,
            focusedLeadingIconColor = p.secondaryText, unfocusedLeadingIconColor = p.secondaryText,
            focusedTrailingIconColor = p.secondaryText, unfocusedTrailingIconColor = p.secondaryText,
            focusedSupportingTextColor = p.secondaryText, unfocusedSupportingTextColor = p.secondaryText,
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
        ),
    )
}

/** Material text-input dialog (AlertDialog + [NativeTextField]). */
@Composable
fun NativeTextInputDialog(
    title: String,
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
    label: String? = null,
    message: String? = null,
    confirmLabel: String = "Save",
    secret: Boolean = false,
) {
    val p = Theme.palette
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
        title = { Text(title, style = NativeType.headlineSmall) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (message != null) Text(message, style = NativeType.bodyMedium)
                NativeTextField(text, { text = it }, label, secret = secret)
            }
        },
        confirmButton = { TextButton({ onConfirm(text) }) { Text(confirmLabel, style = NativeType.labelLarge, color = nativeAccent()) } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel", style = NativeType.labelLarge, color = nativeAccent()) } },
    )
}

/** Material filled button in the accent colour, optional spinner / leading / trailing icon. */
@Composable
fun NativeButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    busy: Boolean = false,
    leading: ImageVector? = null,
    trailing: ImageVector? = null,
    onClick: () -> Unit,
) {
    val accent = nativeAccent()
    val p = Theme.palette
    Button(
        onClick, modifier.heightIn(min = 48.dp), enabled = enabled && !busy,
        colors = ButtonDefaults.buttonColors(
            containerColor = accent, contentColor = onNativeAccent(accent),
            disabledContainerColor = p.text.copy(alpha = 0.12f), disabledContentColor = p.text.copy(alpha = 0.38f),
        ),
    ) {
        if (busy) { CircularProgressIndicator(Modifier.size(18.dp), color = p.text.copy(alpha = 0.6f), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)) }
        if (leading != null) { Icon(leading, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = NativeType.labelLarge)
        if (trailing != null) { Spacer(Modifier.width(8.dp)); Icon(trailing, null, Modifier.size(18.dp)) }
    }
}

/** Material filled tonal button (secondary actions). */
@Composable
fun NativeTonalButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, leading: ImageVector? = null, onClick: () -> Unit) {
    val p = Theme.palette
    FilledTonalButton(
        onClick, modifier.heightIn(min = 48.dp), enabled = enabled,
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = nativeAccent().copy(alpha = 0.16f), contentColor = p.text,
            disabledContainerColor = p.text.copy(alpha = 0.12f), disabledContentColor = p.text.copy(alpha = 0.38f),
        ),
    ) {
        if (leading != null) { Icon(leading, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, style = NativeType.labelLarge)
    }
}

/** Material text button in the accent colour (top-bar "Save", inline "Retry" …). */
@Composable
fun NativeTextButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, color: Color = nativeAccent(), onClick: () -> Unit) {
    TextButton(onClick, modifier, enabled = enabled) {
        Text(text, style = NativeType.labelLarge, color = if (enabled) color else Theme.palette.text.copy(alpha = 0.38f))
    }
}
