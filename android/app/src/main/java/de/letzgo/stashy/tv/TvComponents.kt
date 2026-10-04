package de.letzgo.stashy.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Glow
import androidx.tv.material3.Icon
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import kotlinx.coroutines.delay

/** SF Symbol names used by `stashyTV`, mapped to Material icons. */
object TvIcons {
    val search = Icons.Filled.Search
    val home = Icons.Filled.Home
    val film = Icons.Filled.Movie
    val filmOutline = Icons.Outlined.Movie
    val person3 = Icons.Filled.Groups
    val person = Icons.Filled.Person
    val person2 = Icons.Filled.People
    val building = Icons.Filled.Business
    val tag = Icons.Filled.Sell
    val stack = Icons.Filled.ViewCarousel
    val photoStack = Icons.Filled.PhotoLibrary
    val photo = Icons.Filled.Image
    val gear = Icons.Filled.Settings
    val server = Icons.Filled.Dns
    val play = Icons.Filled.PlayArrow
    val pause = Icons.Filled.Pause
    val restart = Icons.Filled.Replay
    val noStream = Icons.Filled.Cancel
    val heartCircle = Icons.Filled.Favorite
    val heart = Icons.Filled.Favorite
    val star = Icons.Filled.Star
    val clock = Icons.Outlined.Schedule
    val tv = Icons.Filled.Tv
    val bookmark = Icons.Filled.Bookmark
    val bookmarkOutline = Icons.Outlined.BookmarkBorder
    val sort = Icons.Filled.SwapVert
    val filter = Icons.Outlined.FilterAlt
    val filterFill = Icons.Filled.FilterAlt
    val arrowRightCircle = Icons.Filled.ArrowCircleRight
    val retry = Icons.Filled.Refresh
    val lock = Icons.Filled.Lock
    val delete = Icons.AutoMirrored.Filled.Backspace
    val check = Icons.Filled.Check
    val checkSeal = Icons.Filled.Verified
    val checkCircle = Icons.Filled.CheckCircle
    val warning = Icons.Filled.Warning
    val plus = Icons.Filled.Add
    val minusCircle = Icons.Filled.RemoveCircle
    val plusCircle = Icons.Filled.AddCircle
    val sparklesTv = Icons.Filled.LiveTv
    val playTv = Icons.Filled.SmartDisplay
    val brush = Icons.Filled.Brush
    val gridGroup = Icons.Filled.Dashboard
    val captions = Icons.Filled.ClosedCaption
    val captionsOutline = Icons.Outlined.ClosedCaption
    val speaker = Icons.AutoMirrored.Filled.VolumeUp
    val playCircle = Icons.Outlined.PlayCircle
    val drive = Icons.Filled.Storage
    val info = Icons.Outlined.Info
    val backwardEnd = Icons.Filled.SkipPrevious
    val forwardEnd = Icons.Filled.SkipNext
    val chevronDown = Icons.Filled.KeyboardArrowDown
    val plusFolder = Icons.Filled.CreateNewFolder
    val stackFilm = Icons.Filled.VideoLibrary
    val magnifier = Icons.Filled.Search
    val clear = Icons.Filled.Cancel
}

// MARK: - Focus memory

/**
 * Remembers the focused element of a screen so focus lands on the same card when the screen
 * comes back (tvOS restores focus when a pushed page pops). [restore] is armed by [TvNav].
 */
class TvFocusMemory {
    var lastKey: String? = null
    var restore = false
    /** Set once the screen placed its opening focus. */
    var didInitialFocus = false
}

/** Focus memory of the screen being shown (the top route or the tab root), provided by the shell. */
val LocalTvFocusMemory = androidx.compose.runtime.compositionLocalOf<TvFocusMemory?> { null }

/** Tracks focus for [key] and re-requests it when [memory] is restoring to that key. */
fun Modifier.tvFocusMemory(memory: TvFocusMemory, key: String): Modifier = composed {
    val requester = remember { FocusRequester() }
    LaunchedEffect(key) {
        if (memory.restore && memory.lastKey == key) {
            delay(30)
            if (runCatching { requester.requestFocus() }.isSuccess) memory.restore = false
        }
    }
    this.focusRequester(requester).onFocusChanged { if (it.hasFocus) memory.lastKey = key }
}

/**
 * Opening focus: requests [requester] while the user has not focused anything remembered on
 * this screen yet and no restore is pending. Re-runs when [requester] changes (a loading
 * anchor handing over to the real first control, like tvOS moving focus to Play after load).
 */
@Composable
fun TvInitialFocus(memory: TvFocusMemory, requester: FocusRequester, enabled: Boolean = true) {
    LaunchedEffect(enabled, requester) {
        if (!enabled || memory.lastKey != null || memory.restore || TvNav.sidebarFocused) return@LaunchedEffect
        delay(60)
        if (runCatching { requester.requestFocus() }.isSuccess) memory.didInitialFocus = true
    }
}

// MARK: - Buttons

/**
 * tvOS `.buttonStyle(.card)` around artwork: lifts (scale) with a soft shadow glow on focus.
 * The content draws its own artwork; the surface is transparent.
 */
@Composable
fun TvCardButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
    radius: Dp = pt(10),
    focusedScale: Float = 1.08f,
    content: @Composable BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier,
        shape = ClickableSurfaceDefaults.shape(shape),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.Transparent, focusedContainerColor = Color.Transparent,
            pressedContainerColor = Color.Transparent, contentColor = Color.White, focusedContentColor = Color.White,
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = focusedScale),
        glow = ClickableSurfaceDefaults.glow(focusedGlow = Glow(Color.Black.copy(alpha = 0.6f), 16.dp)),
        content = content,
    )
}

/**
 * tvOS standard / `.card` text button: grey platter, white with dark text on focus.
 */
@Composable
fun TvButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    radius: Dp = pt(12),
    focusedScale: Float = 1.06f,
    contentPadding: androidx.compose.foundation.layout.PaddingValues = androidx.compose.foundation.layout.PaddingValues(horizontal = pt(24), vertical = pt(10)),
    content: @Composable RowScope.() -> Unit,
) {
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        enabled = enabled,
        modifier = modifier,
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(radius)),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.1f), contentColor = Color.White,
            focusedContainerColor = Color.White, focusedContentColor = Color.Black,
            pressedContainerColor = Color.White.copy(alpha = 0.85f), pressedContentColor = Color.Black,
            disabledContainerColor = Color.White.copy(alpha = 0.05f), disabledContentColor = Color.White.copy(alpha = 0.4f),
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = focusedScale),
        glow = ClickableSurfaceDefaults.glow(focusedGlow = Glow(Color.Black.copy(alpha = 0.5f), 10.dp)),
    ) {
        Row(Modifier.padding(contentPadding), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(12)), content = content)
    }
}

/** Icon + text label of the catalog chrome buttons (iOS `TVChromeButtonLabel`). */
@Composable
fun TvChromeButton(icon: ImageVector, text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TvButton(onClick, modifier) {
        Icon(icon, null, Modifier.size(pt(30)))
        Text(text, style = TvType.headline, maxLines = 1)
    }
}

/**
 * A tvOS `List` row: faint platter, white with dark text when focused. [trailing] is the value
 * column (secondary text); [onLongClick] = tvOS context menu (long Select).
 */
@Composable
fun TvListRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    value: String? = null,
    subtitle: String? = null,
    leading: ImageVector? = null,
    leadingTint: Color? = null,
    trailingIcon: ImageVector? = null,
    trailingTint: Color? = null,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    onFocus: (() -> Unit)? = null,
) {
    var focused by remember { mutableStateOf(false) }
    val memory = LocalTvFocusMemory.current
    Surface(
        onClick = onClick,
        onLongClick = onLongClick,
        enabled = enabled,
        modifier = modifier.then(if (memory != null) Modifier.tvFocusMemory(memory, "row.$title") else Modifier)
            .fillMaxWidth().onFocusChanged { focused = it.isFocused; if (it.isFocused) onFocus?.invoke() },
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(pt(14))),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = Color.White.copy(alpha = 0.06f), contentColor = if (destructive) TvColors.red else Color.White,
            focusedContainerColor = Color.White, focusedContentColor = if (destructive) TvColors.red else Color.Black,
            pressedContainerColor = Color.White.copy(alpha = 0.85f), pressedContentColor = Color.Black,
            disabledContainerColor = Color.White.copy(alpha = 0.03f), disabledContentColor = Color.White.copy(alpha = 0.35f),
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.03f),
        glow = ClickableSurfaceDefaults.glow(focusedGlow = Glow(Color.Black.copy(alpha = 0.5f), 10.dp)),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = pt(72)).padding(horizontal = pt(28), vertical = pt(12)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(pt(20)),
        ) {
            if (leading != null) Icon(leading, null, Modifier.size(pt(36)), tint = if (focused) LocalContentColor.current else (leadingTint ?: LocalContentColor.current))
            Column(Modifier.weight(1f)) {
                Text(title, style = TvType.body.copy(fontWeight = FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitle != null) Text(subtitle, style = TvType.caption, color = LocalContentColor.current.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (value != null) Text(value, style = TvType.body, color = LocalContentColor.current.copy(alpha = 0.6f), maxLines = 1)
            if (trailingIcon != null) Icon(trailingIcon, null, Modifier.size(pt(32)), tint = if (focused) LocalContentColor.current else (trailingTint ?: LocalContentColor.current))
        }
    }
}

/** tvOS `Toggle` in a List: the row shows "On" / "Off" on the right. */
@Composable
fun TvToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, leading: ImageVector? = null, enabled: Boolean = true, onFocus: (() -> Unit)? = null) {
    TvListRow(title, { onChange(!checked) }, modifier, value = if (checked) "On" else "Off", leading = leading, leadingTint = TvColors.tint, enabled = enabled, onFocus = onFocus)
}

/** List section header (small grey caption above the rows). */
@Composable
fun TvSectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(start = pt(28), top = pt(28), bottom = pt(10)), style = TvType.caption.copy(fontWeight = FontWeight.SemiBold), color = TvColors.secondary)
}

/** Footer text under a list section. */
@Composable
fun TvSectionFooter(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(start = pt(28), end = pt(28), top = pt(10)), style = TvType.caption, color = TvColors.secondary)
}

// MARK: - Option dialog (tvOS `confirmationDialog`)

data class TvOption<T>(val value: T, val label: String)

/**
 * tvOS `confirmationDialog` with a flat option list: the title on top, one button per option
 * ("✓ " marks the selection), Cancel at the end. Back dismisses.
 */
@Composable
fun <T> TvOptionDialog(title: String, options: List<TvOption<T>>, selected: T?, onSelect: (T) -> Unit, onDismiss: () -> Unit, extra: List<Pair<String, () -> Unit>> = emptyList()) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)), contentAlignment = Alignment.Center) {
            Column(
                Modifier.width(pt(760)).clip(RoundedCornerShape(pt(28))).background(Color(0xFF2A2F38)).padding(pt(40)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(title, style = TvType.headline, color = TvColors.secondary, textAlign = TextAlign.Center)
                Spacer(Modifier.size(pt(24)))
                val initial = remember { FocusRequester() }
                val selectedIndex = options.indexOfFirst { it.value == selected }.coerceAtLeast(0)
                val listState = androidx.compose.foundation.lazy.rememberLazyListState(initialFirstVisibleItemIndex = selectedIndex)
                LazyColumn(Modifier.heightIn(max = pt(760)), state = listState, verticalArrangement = Arrangement.spacedBy(pt(12))) {
                    itemsIndexed(options) { i, option ->
                        val isSelected = option.value == selected
                        TvButton(
                            { onSelect(option.value); onDismiss() },
                            Modifier.fillMaxWidth().then(if (i == selectedIndex) Modifier.focusRequester(initial) else Modifier),
                            focusedScale = 1.03f,
                        ) {
                            Text(if (isSelected) "✓ ${option.label}" else option.label, Modifier.fillMaxWidth(), style = TvType.headline, textAlign = TextAlign.Center, maxLines = 1)
                        }
                    }
                    items(extra.size) { i ->
                        val (label, action) = extra[i]
                        TvButton({ action(); onDismiss() }, Modifier.fillMaxWidth(), focusedScale = 1.03f) {
                            Text(label, Modifier.fillMaxWidth(), style = TvType.headline, textAlign = TextAlign.Center)
                        }
                    }
                    item {
                        TvButton(onDismiss, Modifier.fillMaxWidth().padding(top = pt(12)), focusedScale = 1.03f) {
                            Text("Cancel", Modifier.fillMaxWidth(), style = TvType.headline.copy(fontWeight = FontWeight.Bold), textAlign = TextAlign.Center)
                        }
                    }
                }
                LaunchedEffect(Unit) { delay(80); runCatching { initial.requestFocus() } }
            }
        }
    }
}

/** Two-button confirmation (tvOS destructive `confirmationDialog`). */
@Composable
fun TvConfirmDialog(title: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    TvOptionDialog(title, listOf(TvOption(true, confirmLabel)), null, { onConfirm() }, onDismiss = onDismiss)
}

/** A settings list row with a value that opens a [TvOptionDialog] (iOS `TVSettingsPickerRow`). */
@Composable
fun <T> TvPickerRow(title: String, options: List<TvOption<T>>, selection: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, leading: ImageVector? = null, onFocus: (() -> Unit)? = null) {
    var open by remember { mutableStateOf(false) }
    TvListRow(title, { open = true }, modifier, value = options.firstOrNull { it.value == selection }?.label ?: "—", leading = leading, leadingTint = TvColors.tint, enabled = enabled, onFocus = onFocus)
    if (open) TvOptionDialog(title, options, selection, onSelect, onDismiss = { open = false })
}

// MARK: - States

/** iOS: `TVConnectionErrorView`. */
@Composable
fun TvConnectionError(title: String = "Server not reachable", subtitle: String? = null, modifier: Modifier = Modifier, focus: FocusRequester? = null, onRetry: () -> Unit) {
    Column(modifier.fillMaxWidth().padding(vertical = pt(120)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(32))) {
        Icon(TvIcons.server, null, Modifier.size(pt(80)), tint = TvColors.tint)
        Text(title, style = TvType.title, textAlign = TextAlign.Center)
        if (!subtitle.isNullOrEmpty()) Text(subtitle, Modifier.padding(horizontal = pt(80)), style = TvType.title3, color = TvColors.secondary, textAlign = TextAlign.Center)
        TvButton(onRetry, if (focus != null) Modifier.focusRequester(focus) else Modifier) { Text("Retry Connection", style = TvType.title3) }
    }
}

@Composable
fun TvLoading(text: String? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = pt(80)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(20))) {
        TvSpinner(pt(64))
        if (text != null) Text(text, style = TvType.title3, color = TvColors.secondary)
    }
}

/** A small indeterminate spinner (tvOS `ProgressView`). */
@Composable
fun TvSpinner(size: Dp = pt(40), color: Color = Color.White) {
    androidx.compose.material3.CircularProgressIndicator(Modifier.size(size), color = color, strokeWidth = size / 12)
}

@Composable
fun TvEmpty(icon: ImageVector, title: String, modifier: Modifier = Modifier, buttonLabel: String = "Retry", focus: FocusRequester? = null, onRetry: (() -> Unit)?) {
    Column(modifier.fillMaxWidth().padding(vertical = pt(100)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
        Icon(icon, null, Modifier.size(pt(80)), tint = TvColors.secondary)
        Text(title, style = TvType.title2.copy(fontWeight = FontWeight.SemiBold), color = TvColors.secondary, textAlign = TextAlign.Center)
        if (onRetry != null) TvButton(onRetry, if (focus != null) Modifier.focusRequester(focus) else Modifier) {
            if (buttonLabel == "Retry") Icon(TvIcons.retry, null, Modifier.size(pt(32)))
            Text(buttonLabel, style = TvType.title3)
        }
    }
}

/** Black 60 % pill with bold caption (studio / duration / count badges on the cards). */
@Composable
fun TvPill(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, mono: Boolean = false, uppercase: Boolean = false) {
    Row(
        modifier.clip(RoundedCornerShape(pt(8))).background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = pt(12), vertical = pt(6)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(6)),
    ) {
        if (icon != null) Icon(icon, null, Modifier.size(pt(22)), tint = Color.White)
        if (text.isNotEmpty()) Text(
            if (uppercase) text.uppercase() else text,
            style = (if (mono) TvType.monoCaption else TvType.caption.copy(fontWeight = FontWeight.Bold)).copy(letterSpacing = if (uppercase) 1.sp else 0.sp),
            color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Star + "4.5" rating badge. */
@Composable
fun TvRatingBadge(rating100: Int, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(3))) {
        Icon(TvIcons.star, null, Modifier.size(pt(20)), tint = TvColors.star)
        Text(TvFormat.ratingValue(rating100), style = TvType.caption2, color = Color.White)
    }
}

/** Remote image over a grey placeholder with a fallback symbol (tvOS `CustomAsyncImage` + placeholder). */
@Composable
fun TvImage(url: String?, modifier: Modifier = Modifier, placeholderIcon: ImageVector? = null, placeholderColor: Color = TvColors.placeholder, contentScale: ContentScale = ContentScale.Crop, iconSize: Dp = pt(36)) {
    Box(modifier.background(placeholderColor), contentAlignment = Alignment.Center) {
        if (url == null) {
            if (placeholderIcon != null) Icon(placeholderIcon, null, Modifier.size(iconSize), tint = TvColors.secondary)
        } else {
            var failed by remember(url) { mutableStateOf(false) }
            if (failed && placeholderIcon != null) Icon(placeholderIcon, null, Modifier.size(iconSize), tint = TvColors.secondary)
            AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = contentScale, onError = { failed = true })
        }
    }
}

/** Section heading with tinted icon and count capsule (iOS `sectionHeading`). */
@Composable
fun TvSectionHeading(icon: ImageVector, title: String, count: Int? = null, modifier: Modifier = Modifier, large: Boolean = false) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(12))) {
        Icon(icon, null, Modifier.size(pt(34)), tint = TvColors.tint)
        Text(title, style = if (large) TvType.title2 else TvType.title3.copy(fontWeight = FontWeight.Bold), color = Color.White)
        if (count != null && count > 0) {
            Text(
                "$count", Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.06f)).padding(horizontal = pt(10), vertical = pt(3)),
                style = TvType.caption.copy(fontWeight = FontWeight.Bold), color = TvColors.secondary,
            )
        }
    }
}

/** Label / value pair of the detail info grid (`TVGridSpec.infoColumns`: 240 pt label column). */
@Composable
fun TvInfoRow(label: String, value: @Composable () -> Unit) {
    Row(Modifier.padding(vertical = pt(6)), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(pt(240)), style = TvType.title3, color = TvColors.secondary)
        value()
    }
}

@Composable
fun TvInfoRow(label: String, value: String) = TvInfoRow(label) { Text(value, style = TvType.title3, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis) }

// MARK: - Text input

/**
 * A text field for the remote: shown as a list row; Select starts editing (the TV keyboard
 * opens), Done ends it. Typing never starts by merely moving focus across the field.
 */
@Composable
fun TvTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Done,
    onSubmit: (() -> Unit)? = null,
    autoEdit: Boolean = false,
    leading: ImageVector? = null,
) {
    var editing by remember { mutableStateOf(autoEdit) }
    val rowFocus = remember { FocusRequester() }
    val fieldFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    var returnFocus by remember { mutableStateOf(false) }
    if (editing) {
        var hadFocus by remember { mutableStateOf(false) }
        // Back ends editing instead of leaving the page.
        androidx.activity.compose.BackHandler { editing = false; returnFocus = true; keyboard?.hide() }
        Row(
            modifier.fillMaxWidth().heightIn(min = pt(72)).clip(RoundedCornerShape(pt(14))).background(Color.White)
                .border(2.dp, TvColors.tint, RoundedCornerShape(pt(14))).padding(horizontal = pt(28), vertical = pt(12)),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(20)),
        ) {
            if (leading != null) Icon(leading, null, Modifier.size(pt(36)), tint = Color.Black)
            BasicTextField(
                value, onValueChange,
                Modifier.weight(1f).focusRequester(fieldFocus).onFocusChanged {
                    if (it.isFocused) hadFocus = true
                    else if (hadFocus) { editing = false; returnFocus = true }
                },
                textStyle = TvType.body.copy(color = Color.Black),
                singleLine = true,
                cursorBrush = SolidColor(Color.Black),
                visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                    keyboardType = if (secure) KeyboardType.Password else keyboardType, imeAction = imeAction,
                ),
                keyboardActions = KeyboardActions(onAny = { editing = false; returnFocus = true; keyboard?.hide(); onSubmit?.invoke() }),
                decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (value.isEmpty()) Text(label, style = TvType.body, color = Color.Black.copy(alpha = 0.4f))
                        inner()
                    }
                },
            )
        }
        LaunchedEffect(Unit) {
            delay(50)
            runCatching { fieldFocus.requestFocus() }
            keyboard?.show()
        }
    } else {
        val shown = when {
            value.isEmpty() -> null
            secure -> "•".repeat(value.length.coerceAtMost(12))
            else -> value
        }
        TvListRow(
            title = shown ?: label, onClick = { editing = true },
            modifier = modifier.focusRequester(rowFocus),
            value = if (shown != null) label else null,
            leading = leading, leadingTint = TvColors.tint,
        )
        LaunchedEffect(returnFocus) {
            if (returnFocus) { delay(50); runCatching { rowFocus.requestFocus() }; returnFocus = false }
        }
    }
}

/** A tvOS segmented picker: one button per option, the selected one marked. */
@Composable
fun <T> TvSegmented(options: List<TvOption<T>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(pt(12))) {
        options.forEach { option ->
            val isSelected = option.value == selected
            Surface(
                onClick = { onSelect(option.value) },
                shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(pt(12))),
                colors = ClickableSurfaceDefaults.colors(
                    containerColor = if (isSelected) Color.White.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.08f),
                    contentColor = Color.White, focusedContainerColor = Color.White, focusedContentColor = Color.Black,
                ),
                scale = ClickableSurfaceDefaults.scale(focusedScale = 1.05f),
            ) {
                Text(option.label, Modifier.widthIn(min = pt(140)).padding(horizontal = pt(24), vertical = pt(12)), style = TvType.headline, textAlign = TextAlign.Center)
            }
        }
    }
}
