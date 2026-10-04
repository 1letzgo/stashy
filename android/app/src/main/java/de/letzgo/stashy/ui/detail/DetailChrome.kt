package de.letzgo.stashy.ui.detail

import android.widget.Toast
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.floatingShadow
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.stashyGlass
import kotlinx.coroutines.launch

/** iOS: `StashyExpandingDock` metrics. */
internal object Dock {
    val circleSize = 40.dp
    val iconSize = 18.dp
    val activeHeight = 40.dp
    val stackedButtonSize = 48.dp
    const val inactiveIconOpacity = 0.72f
    val edgePadding = 16.dp
    val activeHorizontalPadding = 14.dp
    /** Height of [DetailNavBar] (pill + 8pt vertical padding). */
    val barHeight = 56.dp
}

/** Section icons in the detail chrome bar (iOS `PerformerDetailView.DetailTab` & co.). */
enum class DetailTab(val title: String) {
    Scenes("Scenes"), Galleries("Galleries"), Studios("Studios"), Performers("Performers"),
    Tags("Tags"), Groups("Groups"), Images("Images");

    val icon: ImageVector get() = when (this) {
        Scenes -> SF.film; Galleries -> SF.photoStack; Studios -> SF.building2; Performers -> SF.personFill
        Tags -> SF.tag; Groups -> SF.rectangleStackFill; Images -> SF.photo
    }
}

/** Short status message (iOS `ToastManager.shared.show`). */
internal fun detailToast(message: String) {
    Toast.makeText(Prefs.appContext, message, Toast.LENGTH_SHORT).show()
}

/** Top padding for detail content under [DetailNavBar]. */
@Composable
internal fun detailTopPadding(): Dp = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + Dock.barHeight + Tokens.Chrome.contentTopGap

/** iOS: `StashyChromePillStyle` round icon button (glass, optional tint fill). */
@Composable
internal fun DockIconButton(
    icon: ImageVector,
    contentDescription: String,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    iconTint: Color = Color.White.copy(alpha = Dock.inactiveIconOpacity),
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .size(Dock.circleSize)
            .floatingShadow()
            .stashyGlass(CircleShape, if (selected) Appearance.tint else null)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = if (selected) Color.White else iconTint, modifier = Modifier.size(Dock.iconSize))
    }
}

/** iOS: the tinted "‹ Back" pill (`StashyChromePillStyle(accent: true)`). */
@Composable
internal fun BackPillLabeled(onClick: () -> Unit) {
    Row(
        Modifier
            .height(Dock.activeHeight)
            .floatingShadow(RoundedCornerShape(50))
            .stashyGlass(RoundedCornerShape(50), Appearance.tint)
            .clickable(onClick = onClick)
            .padding(horizontal = Dock.activeHorizontalPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(SF.chevronLeft, null, tint = Color.White, modifier = Modifier.size(Dock.iconSize))
        Text("Back", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
    }
}

/**
 * iOS: the custom detail chrome bar (`StashySectionChromeBar`): Back · section icons ·
 * Favorite · Edit. Section icons only show when more than one section has content.
 */
@Composable
internal fun DetailNavBar(
    tabs: List<DetailTab>,
    selected: DetailTab?,
    onSelect: (DetailTab) -> Unit,
    isFavorite: Boolean? = null,
    favoriteBusy: Boolean = false,
    onFavorite: () -> Unit = {},
    onEdit: (() -> Unit)? = null,
    editLabel: String = "Edit",
) {
    Box(
        Modifier.fillMaxWidth()
            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent)))
            .statusBarsPadding()
            .padding(horizontal = Dock.edgePadding, vertical = 8.dp),
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = Dock.activeHeight), verticalAlignment = Alignment.CenterVertically) {
            BackPillLabeled { Nav.pop() }
            Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
            val showTabs = tabs.size > 1
            if (showTabs) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    tabs.forEach { tab ->
                        DockIconButton(tab.icon, tab.title, selected = tab == selected) { if (tab != selected) onSelect(tab) }
                    }
                }
            }
            val hasActions = isFavorite != null || (onEdit != null && Appearance.isEditModeEnabled)
            if (showTabs && hasActions) Spacer(Modifier.width(7.dp + 6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (isFavorite != null) {
                    DockIconButton(
                        if (isFavorite) SF.heartFill else SF.heart,
                        if (isFavorite) "Remove favorite" else "Add favorite",
                        iconTint = if (isFavorite) StashyColors.systemRed else Color.White.copy(alpha = Dock.inactiveIconOpacity),
                        enabled = !favoriteBusy,
                        onClick = onFavorite,
                    )
                }
                if (onEdit != null && Appearance.isEditModeEnabled) {
                    DockIconButton(SF.pencil, editLabel, onClick = onEdit)
                }
            }
        }
    }
}

/** Optional hook for the "Feeds" pill in detail headers (wired by the Feeds port). */
object DetailFeedsLink {
    sealed interface Target {
        data class Performer(val id: String, val name: String) : Target
        data class Studio(val id: String, val name: String) : Target
        data class Tag(val id: String, val name: String) : Target
    }
    var open: ((Target) -> Unit)? = null

    fun navigate(target: Target) {
        open?.invoke(target) ?: Nav.select(MainTab.Feeds)
    }
}

/** iOS: Feeds pill in the header (`AppTab.reels.icon` + "Feeds"). */
@Composable
internal fun FeedsPill(onClick: () -> Unit) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(Appearance.tint.copy(alpha = 0.15f)).clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(SF.playRectangleOnRectangle, null, tint = Theme.palette.pillAccent, modifier = Modifier.size(13.dp))
        Text("Feeds", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Theme.palette.pillAccent)
    }
}

/** 2-column label/value grid of the detail headers (8pt uppercase label, 11pt medium value). */
@Composable
internal fun DetailItemsGrid(items: List<DetailItem>) {
    val p = Theme.palette
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { d ->
                    Column(Modifier.weight(1f)) {
                        Text(d.label.uppercase(), fontSize = 8.sp, lineHeight = 10.sp, color = p.secondaryText)
                        Text(d.value, fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.Medium, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** Round expand/collapse chevron at the header's bottom-right. */
@Composable
internal fun BoxScope.HeaderExpandButton(expanded: Boolean, onToggle: () -> Unit) {
    Box(
        Modifier.align(Alignment.BottomEnd).padding(8.dp).size(22.dp).clip(CircleShape)
            .background(Appearance.tint.copy(alpha = 0.15f)).clickable(onClick = onToggle),
        contentAlignment = Alignment.Center,
    ) {
        Icon(if (expanded) SF.chevronUp else SF.chevronDown, if (expanded) "Collapse" else "Expand", tint = Theme.palette.pillAccent, modifier = Modifier.size(14.dp))
    }
}

/** Card container shared by all detail headers (secondary background, hairline, shadow). */
@Composable
internal fun HeaderCardFrame(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(
        modifier.fillMaxWidth().cardShadow(shape).clip(shape).background(p.secondaryBackground)
            .border(0.5.dp, p.text.copy(alpha = 0.1f), shape).animateContentSize(),
        content = content,
    )
}

/**
 * iOS: the Performer/Tag/Group/Gallery header — 72pt thumbnail strip flush left (min 115pt),
 * name (title2 bold), optional Feeds pill, the first four details (all when expanded), extra
 * text when expanded and the expand chevron when there is more to show.
 */
@Composable
internal fun DetailHeaderCard(
    title: String,
    imageUrl: String?,
    placeholderIcon: ImageVector,
    items: List<DetailItem>,
    expandable: Boolean,
    expanded: Boolean,
    onToggle: () -> Unit,
    titleMaxLines: Int = 1,
    imageContent: (@Composable BoxScope.() -> Unit)? = null,
    onFeeds: (() -> Unit)? = null,
    expandedContent: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val p = Theme.palette
    val collapsedHeight = 115.dp
    HeaderCardFrame {
        // The text column sets the height; the strip matches it (no intrinsics: Coil's
        // SubcomposeAsyncImage cannot answer intrinsic measurements).
        Box(Modifier.fillMaxWidth().heightIn(min = collapsedHeight)) {
            Box(Modifier.matchParentSize()) {
            Box(
                Modifier.width(72.dp).fillMaxHeight()
                    .background(Color.Gray.copy(alpha = 0.1f)),
            ) {
                if (imageContent != null) imageContent()
                else if (imageUrl != null) {
                    SubcomposeAsyncImage(
                        imageUrl, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter,
                        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(Modifier.size(16.dp), color = p.secondaryText, strokeWidth = 2.dp) } },
                        error = { HeaderPlaceholder(placeholderIcon) },
                    )
                } else HeaderPlaceholder(placeholderIcon)
            }
            }
            Column(
                Modifier.fillMaxWidth().heightIn(min = collapsedHeight).padding(start = 72.dp + 12.dp, end = 12.dp, top = 10.dp, bottom = 10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        title, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text,
                        maxLines = if (expanded) Int.MAX_VALUE else titleMaxLines, overflow = TextOverflow.Ellipsis,
                    )
                    if (onFeeds != null) FeedsPill(onFeeds)
                }
                val visible = if (expanded) items else items.take(4)
                if (visible.isNotEmpty()) DetailItemsGrid(visible)
                if (expanded && expandedContent != null) expandedContent()
                if (expandable) Spacer(Modifier.height(18.dp))
            }
        }
        if (expandable) HeaderExpandButton(expanded, onToggle)
    }
}

@Composable
private fun HeaderPlaceholder(icon: ImageVector) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Icon(icon, null, tint = StashyColors.appAccent.copy(alpha = 0.5f), modifier = Modifier.size(28.dp))
    }
}

/** Header URL row (iOS: "URL" label + tinted link). */
@Composable
internal fun HeaderLink(url: String) {
    val handler = LocalUriHandler.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("URL", fontSize = 8.sp, color = Theme.palette.secondaryText)
        Text(
            url, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Appearance.tint, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.clickable { runCatching { handler.openUri(url) } },
        )
    }
}

/** One slot of the floating list bar (iOS `CatalogChromeSlot`). */
internal class ChromeSlot(val icon: ImageVector, val label: String, val isActive: Boolean = false, val onClick: () -> Unit)

/**
 * iOS: `floatingActionBar` with `CatalogSlotBar` for the embedded list — glass circles at
 * the bottom trailing edge above the tab bar. [sortMenu] is anchored to the filter slot.
 */
@Composable
internal fun BoxScope.DetailSlotBar(slots: List<ChromeSlot>, sortMenu: (@Composable (dismiss: () -> Unit) -> Unit)? = null) {
    if (slots.isEmpty() && sortMenu == null) return
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        Modifier.align(Alignment.BottomEnd).navigationBarsPadding().padding(end = 16.dp, bottom = TabBarClearance - 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        slots.forEach { s ->
            DockIconButton(s.icon, s.label, selected = s.isActive, iconTint = Color.White, onClick = s.onClick)
        }
        if (sortMenu != null) {
            Box {
                DockIconButton(SF.sliderHorizontal3, "Filter and sort", iconTint = Color.White) { menuOpen = true }
                DropdownMenu(menuOpen, onDismissRequest = { menuOpen = false }) { sortMenu { menuOpen = false } }
            }
        }
    }
}

/** Sort entries with a checkmark on the current one (iOS sort `Picker` in the filter sheet). */
@Composable
internal fun <S : SortChoice> SortMenuItems(options: List<S>, current: S, dismiss: () -> Unit, onPick: (S) -> Unit) {
    options.forEach { o ->
        DropdownMenuItem(
            text = { Text(o.label) },
            trailingIcon = { if (o == current) Icon(SF.checkmark, null) },
            onClick = { dismiss(); onPick(o) },
        )
    }
}

// MARK: - Edit sheets

/** A text row of the iOS edit `Form`. */
internal class EditField(
    val label: String,
    initial: String,
    val keyboard: KeyboardType = KeyboardType.Text,
    val multiline: Boolean = false,
) {
    var value by mutableStateOf(initial)
    val trimmed: String get() = value.trim()
    /** iOS `optionalTrimmed`. */
    val optional: String? get() = trimmed.ifEmpty { null }
}

internal class EditSection(val title: String, val fields: List<EditField>)

/**
 * iOS: `Edit…Sheet` — Form with sections, "Save" (enabled with a non-empty first field),
 * destructive "Delete …" row with confirmation "Delete '<name>'? This cannot be undone."
 */
@Composable
internal fun EditEntitySheet(
    title: String,
    sections: List<EditSection>,
    deleteLabel: String,
    deleteTitle: String,
    entityName: String,
    onDismiss: () -> Unit,
    onSave: suspend () -> Boolean,
    onDelete: suspend () -> Unit,
) {
    val p = Theme.palette
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var saving by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val canSave = sections.firstOrNull()?.fields?.firstOrNull()?.trimmed?.isNotEmpty() == true

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(p.background)) {
            Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).statusBarsPadding().padding(top = Dock.barHeight).navigationBarsPadding().padding(16.dp)) {
                sections.forEach { section ->
                    Text(section.title.uppercase(), style = IosTypography.footnote, color = p.secondaryText, modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 6.dp))
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Tokens.Radius.small)).background(p.secondaryBackground).padding(horizontal = 12.dp, vertical = 4.dp)) {
                        section.fields.forEach { f ->
                            OutlinedTextField(
                                value = f.value, onValueChange = { f.value = it },
                                label = { Text(f.label) },
                                singleLine = !f.multiline,
                                minLines = if (f.multiline) 5 else 1,
                                keyboardOptions = KeyboardOptions(keyboardType = f.keyboard),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent,
                                    focusedTextColor = p.text, unfocusedTextColor = p.text, cursorColor = Appearance.tint,
                                    focusedLabelColor = Appearance.tint, unfocusedLabelColor = p.secondaryText,
                                ),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Tokens.Radius.small)).background(p.secondaryBackground)
                        .clickable(enabled = !saving && !deleting) { confirmDelete = true }.padding(14.dp),
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (deleting) CircularProgressIndicator(Modifier.size(18.dp), color = StashyColors.systemRed, strokeWidth = 2.dp)
                    else {
                        Icon(SF.trash, null, tint = StashyColors.systemRed, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(deleteLabel, color = StashyColors.systemRed, style = IosTypography.body)
                    }
                }
                Spacer(Modifier.height(40.dp))
            }
            // iOS `stashyModalSheetChrome(title, onBack:)` + trailing "Save".
            Row(
                Modifier.fillMaxWidth().background(p.background).statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp).height(Dock.activeHeight),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DockIconButton(SF.chevronLeft, "Back", iconTint = Color.White, onClick = onDismiss)
                Text(title, Modifier.weight(1f), style = IosTypography.headline, color = p.text, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Box(
                    Modifier.height(Dock.activeHeight).clip(RoundedCornerShape(50))
                        .background(if (canSave) Appearance.tint else Appearance.tint.copy(alpha = 0.35f))
                        .clickable(enabled = canSave && !saving) {
                            saving = true
                            scope.launch {
                                val ok = onSave()
                                saving = false
                                if (ok) onDismiss()
                            }
                        }
                        .padding(horizontal = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (saving) CircularProgressIndicator(Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                    else Text("Save", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(deleteTitle) },
            text = { Text("Delete '$entityName'? This cannot be undone.") },
            confirmButton = {
                TextButton({
                    confirmDelete = false
                    deleting = true
                    scope.launch {
                        try {
                            onDelete()
                            onDismiss()
                        } catch (e: Exception) {
                            detailToast(e.message ?: "Delete failed")
                        } finally {
                            deleting = false
                        }
                    }
                }) { Text("Delete", color = StashyColors.systemRed) }
            },
            dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

/** Centered loading footer / spinner. */
@Composable
internal fun LoadingFooter(message: String? = null) {
    val p = Theme.palette
    Column(Modifier.fillMaxWidth().padding(vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CircularProgressIndicator(Modifier.size(22.dp), color = p.secondaryText, strokeWidth = 2.dp)
        if (message != null) Text(message, style = IosTypography.caption, color = p.secondaryText)
    }
}

/** iOS: `InlineEmptyStateView(icon:title:)`. */
@Composable
internal fun InlineEmptyState(icon: ImageVector, title: String) {
    val p = Theme.palette
    Column(Modifier.fillMaxWidth().padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(40.dp))
        Text(title, style = IosTypography.headline, color = p.secondaryText)
    }
}
