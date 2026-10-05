package de.letzgo.stashy.ui.tools.rateme

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.RateMeImageMediaKind
import de.letzgo.stashy.data.tools.RateMeItem
import de.letzgo.stashy.data.tools.RateMeLogic
import de.letzgo.stashy.data.tools.RateMeMode
import de.letzgo.stashy.data.tools.RateMeOption
import de.letzgo.stashy.data.tools.RateMePickerOptions
import de.letzgo.stashy.data.tools.RateMeTheme
import de.letzgo.stashy.data.tools.RateMeThemePickerKind
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.components.SelectChip
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsBottomPadding
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// iOS: `RateMeToolsView` (`stashy/RateMeToolsView.swift`).

/** iOS: `StashyExpandingDock.activeHeight` / `itemSpacing`. */
private val PillSpacing: Dp = 10.dp

private fun View.performRateMeHaptic(kind: RateMeHaptic) {
    performHapticFeedback(
        when (kind) {
            RateMeHaptic.Light -> HapticFeedbackConstants.CONTEXT_CLICK
            RateMeHaptic.Selection -> HapticFeedbackConstants.CLOCK_TICK
            RateMeHaptic.Success -> if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK
        },
    )
}

private val ModeIcons = mapOf(RateMeMode.Scenes to SF.film, RateMeMode.Images to SF.photo)

private fun themeIcon(theme: RateMeTheme): ImageVector = when (theme) {
    RateMeTheme.Random -> SF.shuffle
    RateMeTheme.Newest -> SF.sparkles
    RateMeTheme.MostPlayed -> Icons.Outlined.PlayCircle
    is RateMeTheme.Performer -> SF.personFill
    is RateMeTheme.Studio -> Icons.Filled.Business
    is RateMeTheme.Tag -> Icons.Filled.Sell
}

private fun pickerIcon(kind: RateMeThemePickerKind): ImageVector = when (kind) {
    RateMeThemePickerKind.Performer -> SF.personFill
    RateMeThemePickerKind.Studio -> Icons.Filled.Business
    RateMeThemePickerKind.Tag -> Icons.Filled.Sell
}

/**
 * iOS: `RateMeToolsView` — random unrated scenes / images with a star rating, O-counter,
 * delete, Skip and Watch / Open. Root composable hosted full screen by the Tools tab.
 */
@Composable
fun RateMeToolView() {
    val config = ServerConfigManager.activeConfig
    if (config == null) {
        NoServerPlaceholder(SF.starFill, "Select a server first to use RateMe.")
        return
    }
    val model: RateMeViewModel = viewModel(key = "rateme-${config.id}")
    val view = LocalView.current
    DisposableEffect(model, view) {
        model.haptic = { view.performRateMeHaptic(it) }
        onDispose { model.haptic = null }
    }
    LaunchedEffect(model) { model.onAppear() }

    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var themePicker by remember { mutableStateOf<RateMeThemePickerKind?>(null) }
    val isRegular = LocalConfiguration.current.screenWidthDp >= 600
    val hPad = if (isRegular) Tokens.Spacing.xl else ToolsTokens.contentPadding

    Column(Modifier.fillMaxSize().padding(top = toolsTopPadding())) {
        val err = model.errorMessage
        if (err != null && model.item == null) {
            Text(
                err, style = IosTypography.footnote, color = StashyColors.systemRed, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(horizontal = ToolsTokens.contentPadding),
            )
        }

        // One row: the Scenes / Images switch stays put on the left, the themes scroll behind it.
        Row(
            Modifier.fillMaxWidth().padding(top = ToolsTokens.menuTopPadding, bottom = ToolsTokens.menuBottomPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PillSpacing),
        ) {
            ModeToggle(model, Modifier.padding(start = ToolsTokens.contentPadding))
            ThemeChips(model, Modifier.weight(1f)) { themePicker = it }
        }

        Content(model, hPad, isRegular) { showDeleteConfirmation = true }
    }

    themePicker?.let { kind ->
        ThemePickerSheet(kind, model.mode, onDismiss = { themePicker = null }) { option ->
            themePicker = null
            model.selectThemeAsync(kind.theme(option))
        }
    }

    if (showDeleteConfirmation) {
        StashyAlert(
            title = RateMeLogic.deleteConfirmationTitle(model.mode),
            message = RateMeLogic.deleteConfirmationMessage(model.mode, model.item?.title),
            onDismiss = { showDeleteConfirmation = false },
            confirmLabel = "Delete",
            destructive = true,
            dismissLabel = "Cancel",
            onConfirm = {
                showDeleteConfirmation = false
                model.deleteCurrentAsync()
            },
        )
    }
}

// MARK: - Chrome

/** iOS: `modeToggle` — Scenes / Images as a Material segmented button with icons. */
@Composable
private fun ModeToggle(model: RateMeViewModel, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val accent = nativeAccent()
    val view = LocalView.current
    val modes = RateMeMode.entries
    SingleChoiceSegmentedButtonRow(modifier) {
        modes.forEachIndexed { index, mode ->
            val selected = model.mode == mode
            SegmentedButton(
                selected = selected,
                onClick = {
                    if (!selected) {
                        view.performRateMeHaptic(RateMeHaptic.Selection)
                        model.selectMode(mode)
                    }
                },
                shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                enabled = !model.isSubmitting,
                modifier = Modifier.width(56.dp),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = accent.copy(alpha = 0.18f), activeContentColor = p.text,
                    inactiveContainerColor = Color.Transparent, inactiveContentColor = p.text.copy(alpha = 0.7f),
                    activeBorderColor = p.separator, inactiveBorderColor = p.separator,
                    disabledActiveContainerColor = accent.copy(alpha = 0.18f), disabledActiveContentColor = p.text.copy(alpha = 0.6f),
                    disabledActiveBorderColor = p.separator, disabledInactiveBorderColor = p.separator,
                ),
                icon = {},
            ) { Icon(ModeIcons.getValue(mode), mode.label, modifier = Modifier.size(18.dp)) }
        }
    }
}

/** iOS: `themeChips` — media kind menu (images), fixed themes, performer / studio / tag pickers. */
@Composable
private fun ThemeChips(model: RateMeViewModel, modifier: Modifier, onPick: (RateMeThemePickerKind) -> Unit) {
    val view = LocalView.current
    val state = rememberLazyListState()
    val fixed = model.availableFixedThemes
    val pickers = RateMeThemePickerKind.entries
    val leading = if (model.mode == RateMeMode.Images) 1 else 0

    // A picked performer / studio / tag sits at the far end; bring its chip into view on change.
    var lastThemeId by remember { mutableStateOf(model.theme.id) }
    LaunchedEffect(model.theme) {
        if (model.theme.id == lastThemeId) return@LaunchedEffect
        lastThemeId = model.theme.id
        val theme = model.theme
        val index = leading + when (theme) {
            is RateMeTheme.Performer -> fixed.size + pickers.indexOf(RateMeThemePickerKind.Performer)
            is RateMeTheme.Studio -> fixed.size + pickers.indexOf(RateMeThemePickerKind.Studio)
            is RateMeTheme.Tag -> fixed.size + pickers.indexOf(RateMeThemePickerKind.Tag)
            else -> fixed.indexOf(theme).coerceAtLeast(0)
        }
        val viewport = state.layoutInfo.viewportSize.width
        state.animateScrollToItem(index, -viewport / 3)
    }

    LazyRow(
        modifier,
        state = state,
        contentPadding = PaddingValues(end = ToolsTokens.contentPadding),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        userScrollEnabled = !model.isSubmitting,
    ) {
        if (model.mode == RateMeMode.Images) item(key = "mediaKind") { MediaKindMenu(model) }
        items(fixed, key = { it.id }) { theme ->
            ThemeChip(theme.label, themeIcon(theme), selected = model.theme == theme, enabled = !model.isSubmitting) {
                view.performRateMeHaptic(RateMeHaptic.Selection)
                model.selectThemeAsync(theme)
            }
        }
        items(pickers, key = { it.raw }) { kind ->
            val picked = kind.picked(model.theme)
            ThemeChip(picked?.label ?: "${kind.title}…", pickerIcon(kind), selected = picked != null, enabled = !model.isSubmitting) {
                view.performRateMeHaptic(RateMeHaptic.Selection)
                onPick(kind)
            }
        }
    }
}

/** iOS: `themeChip` — Material `FilterChip` with icon. */
@Composable
private fun ThemeChip(title: String, icon: ImageVector, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    SelectChip(title, selected, onClick, enabled = enabled, icon = icon)
}

/** iOS: `mediaKindMenu` — Any media / Images / Videos as a compact menu chip (images mode). */
@Composable
private fun MediaKindMenu(model: RateMeViewModel) {
    val p = Theme.palette
    var expanded by remember { mutableStateOf(false) }
    val selected = model.imageMediaKind != RateMeImageMediaKind.All
    Box {
        SelectChip(
            model.imageMediaKind.title, selected, { expanded = true },
            enabled = !model.isSubmitting, trailingIcon = Icons.Filled.KeyboardArrowDown,
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = p.secondaryBackground) {
            RateMeImageMediaKind.entries.forEach { kind ->
                DropdownMenuItem(
                    text = { Text(kind.title, style = IosTypography.body, color = p.text) },
                    leadingIcon = {
                        if (kind == model.imageMediaKind) Icon(Icons.Filled.Check, null, tint = p.text, modifier = Modifier.size(18.dp))
                        else Spacer(Modifier.size(18.dp))
                    },
                    onClick = {
                        expanded = false
                        model.selectImageMediaKind(kind)
                    },
                )
            }
        }
    }
}

// MARK: - Content

/** Card chrome: secondary fill, 0.5 pt primary stroke at 10 %, card shadow. */
@Composable
private fun Modifier.rateMeCard(): Modifier {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    return this
        .cardShadow(shape)
        .clip(shape)
        .background(p.secondaryBackground, shape)
        .border(0.5.dp, p.text.copy(alpha = 0.1f), shape)
}

@Composable
private fun Content(model: RateMeViewModel, hPad: Dp, isRegular: Boolean, onDelete: () -> Unit) {
    val p = Theme.palette
    Box(
        Modifier
            .fillMaxSize()
            .padding(horizontal = hPad)
            .padding(bottom = ToolsBottomPadding + ToolsTokens.menuBottomPadding),
        contentAlignment = Alignment.TopCenter,
    ) {
        val item = model.item
        when {
            model.isLoading && item == null -> Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
            ) {
                CircularProgressIndicator(color = p.secondaryText)
                Text("Loading…", style = IosTypography.subheadline, color = p.secondaryText)
            }
            item != null -> Column(
                Modifier.fillMaxSize().let { if (isRegular) it.widthIn(max = 720.dp) else it },
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Media at the top taking the height it needs (up to what is free); rating and
                // Skip / Open pinned to the bottom so they never move between items.
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                    MediaCard(model, item)
                }
                RatingRow(model, item, onDelete)
                ActionRow(model, item)
            }
            else -> Column(
                Modifier.fillMaxSize().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
            ) {
                Icon(ModeIcons.getValue(model.mode), null, tint = p.secondaryText, modifier = Modifier.size(44.dp))
                Text("Nothing to rate", style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = p.text)
                Text(
                    model.errorMessage ?: "All ${model.mode.label.lowercase()} already have a rating.",
                    style = IosTypography.subheadline, color = p.secondaryText, textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** iOS: `mediaCard` — media with title / performers on a bottom gradient. */
@Composable
private fun MediaCard(model: RateMeViewModel, item: RateMeItem) {
    val aspect = item.aspectRatio ?: if (item.mode == RateMeMode.Scenes) 16f / 9f else 1f
    val shadow = Shadow(Color.Black.copy(alpha = 0.5f), Offset(0f, 2f), 4f)
    Box(
        Modifier
            .aspectRatio(aspect)
            .rateMeCard()
            .alpha(if (model.isSubmitting) 0.85f else 1f),
    ) {
        RateMeMediaView(item, Modifier.fillMaxSize())
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.7f))))
                .padding(start = 12.dp, end = 12.dp, top = 28.dp, bottom = 10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                item.title, style = IosTypography.headline.copy(shadow = shadow), color = Color.White,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            item.performerNames?.let {
                Text(
                    it, style = IosTypography.subheadline.copy(shadow = shadow), color = Color.White.copy(alpha = 0.8f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** iOS: `RateMeMediaView` — thumbnail (fit), autoplaying muted preview after 0.35 s, play badge. */
@Composable
private fun RateMeMediaView(item: RateMeItem, modifier: Modifier) {
    val p = Theme.palette
    val playback = item.playbackURL
    var isPreviewing by remember(item.id) { mutableStateOf(false) }
    var firstFrame by remember(item.id) { mutableStateOf(false) }
    LaunchedEffect(item.id, playback) {
        isPreviewing = false
        if (playback != null) {
            delay(350)
            isPreviewing = true
        }
    }
    var state by remember(item.thumbnailURL) { mutableStateOf<AsyncImagePainter.State?>(null) }
    Box(modifier.background(Color.Black.copy(alpha = 0.08f)), contentAlignment = Alignment.Center) {
        val url = item.thumbnailURL
        if (url != null) {
            AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit, onState = { state = it })
        }
        when {
            url == null || state is AsyncImagePainter.State.Error ->
                Icon(ModeIcons.getValue(item.mode), null, tint = p.secondaryText, modifier = Modifier.size(48.dp))
            state == null || state is AsyncImagePainter.State.Loading ->
                CircularProgressIndicator(Modifier.size(22.dp), color = p.secondaryText, strokeWidth = 2.dp)
        }

        if (isPreviewing && playback != null) {
            // The video is laid out at once (it needs a surface) and faded in on its first frame.
            val videoAlpha by animateFloatAsState(if (firstFrame) 1f else 0f, tween(200), label = "preview")
            RateMePreviewVideo(
                playback,
                Modifier.fillMaxSize().alpha(videoAlpha),
                onFirstFrame = { firstFrame = true },
            )
        }

        if (playback != null && !isPreviewing) {
            Box(
                Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.4f)).padding(12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/** iOS: `StarRatingView(rating100:isInteractive:size:spacing:)` — 5 stars, same star clears. */
@Composable
private fun StarRating(rating100: Int?, interactive: Boolean, size: Dp, spacing: Dp, onChange: (Int?) -> Unit) {
    val view = LocalView.current
    val stars = RateMeLogic.stars(rating100)
    Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
        for (index in 1..5) {
            val filled = index <= stars
            Icon(
                if (filled) SF.starFill else SF.star, "$index stars",
                tint = if (filled) Appearance.tint else Color.Gray.copy(alpha = 0.5f),
                modifier = Modifier
                    .size(size)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (!interactive) return@clickable
                        view.performRateMeHaptic(RateMeHaptic.Selection)
                        onChange(RateMeLogic.ratingAfterTap(rating100, index))
                    },
            )
        }
    }
}

/** iOS: `ratingRow` — stars, O-counter, delete. */
@Composable
private fun RatingRow(model: RateMeViewModel, item: RateMeItem, onDelete: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    val view = LocalView.current
    val inner = RoundedCornerShape(Tokens.Radius.card)
    Row(
        Modifier
            .fillMaxWidth()
            .rateMeCard()
            .alpha(if (model.isSubmitting) 0.85f else 1f)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.weight(1f)) {
            StarRating(model.draftRating100, interactive = !model.isSubmitting && !model.isDeleting, size = 24.dp, spacing = 4.dp) {
                model.submitRatingAsync(it)
            }
        }
        val oEnabled = !model.isSubmitting && !model.isIncrementingO && !model.isDeleting
        Row(
            Modifier
                .height(44.dp)
                .clip(inner)
                .background(p.background, inner)
                .clickable(enabled = oEnabled) { model.incrementOCounterAsync() }
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                oCounterIcon(Appearance.oCounterIcon, filled = item.oCounter > 0),
                "O-Counter ${item.oCounter}, tap to increment",
                tint = if (item.oCounter > 0) tint else p.secondaryText,
                modifier = Modifier.size(20.dp),
            )
            Text(
                "${item.oCounter}",
                style = IosTypography.body.merge(TextStyle(fontFeatureSettings = "tnum")).copy(fontWeight = FontWeight.Bold),
                color = p.text, maxLines = 1,
            )
        }
        Box(
            Modifier
                .size(44.dp)
                .clip(inner)
                .background(p.background, inner)
                .clickable(enabled = !model.isSubmitting && !model.isDeleting && !model.isLoading) {
                    view.performRateMeHaptic(RateMeHaptic.Light)
                    onDelete()
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Delete, "Delete", tint = StashyColors.systemRed, modifier = Modifier.size(20.dp))
        }
    }
}

/** iOS: `actionRow` — Skip and Watch / Open side by side, same height. */
@Composable
private fun ActionRow(model: RateMeViewModel, item: RateMeItem) {
    val p = Theme.palette
    val tint = Appearance.tint
    val view = LocalView.current
    val shape = RoundedCornerShape(Tokens.Radius.card)
    val enabled = !model.isSubmitting && !model.isLoading
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ActionButton("Skip", Icons.Filled.FastForward, p.text, p.secondaryBackground, shape, enabled, Modifier.weight(1f)) {
            view.performRateMeHaptic(RateMeHaptic.Light)
            model.skipAsync()
        }
        if (item.mode == RateMeMode.Scenes) {
            ActionButton("Watch", SF.playFill, Color.White, tint, shape, enabled, Modifier.weight(1f)) {
                view.performRateMeHaptic(RateMeHaptic.Light)
                // Minimal Scene; the detail screen loads the full scene.
                Nav.push(SceneDetailScreen(item.id, Scene(id = item.id, title = item.title, oCounter = item.oCounter)))
            }
        } else {
            item.openableImage?.let { image ->
                ActionButton("Open", Icons.Filled.OpenInFull, Color.White, tint, shape, enabled, Modifier.weight(1f)) {
                    view.performRateMeHaptic(RateMeHaptic.Light)
                    Nav.push(ImageViewerScreen(listOf(image), 0))
                }
            }
        }
    }
}

@Composable
private fun ActionButton(
    title: String,
    icon: ImageVector,
    fg: Color,
    bg: Color,
    shape: RoundedCornerShape,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier
            .height(46.dp)
            .clip(shape)
            .background(bg, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else 0.5f),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = fg, modifier = Modifier.size(17.dp))
        Spacer(Modifier.width(6.dp))
        Text(title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = fg)
    }
}

// MARK: - Theme picker

/**
 * iOS: `RateMeThemePickerSheet` — performer / studio / tag for a theme from the shared picker
 * options (most used first, name search for the long tail), in a modal sheet with Back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThemePickerSheet(
    kind: RateMeThemePickerKind,
    mode: RateMeMode,
    onDismiss: () -> Unit,
    onPick: (RateMeOption) -> Unit,
) {
    val p = Theme.palette
    val view = LocalView.current
    val storeKind = kind.storeKind(mode)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }

    LaunchedEffect(storeKind) { RateMePickerOptions.load(storeKind) }
    LaunchedEffect(query) { RateMePickerOptions.search(storeKind, query) }

    val all = RateMePickerOptions.availableOptions(storeKind)
    val term = query.trim()
    val options = if (term.isEmpty()) all else all.filter { it.name.contains(term, ignoreCase = true) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = p.background,
        dragHandle = null,
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 400.dp).imePadding()) {
            // iOS `stashyModalSheetChrome(title, onBack:)`.
            // Material sheet header: close ✕ · title.
            Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.IconButton(onClick = {
                    scope.launch {
                        sheetState.hide()
                        onDismiss()
                    }
                }) { Icon(de.letzgo.stashy.ui.SF.xmark, "Close", tint = p.text) }
                Text(
                    kind.title, style = androidx.compose.material3.MaterialTheme.typography.titleLarge, color = p.text,
                    modifier = Modifier.weight(1f).padding(start = 4.dp),
                )
            }
            LazyColumn(
                Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 32.dp),
            ) {
                item {
                    Text(
                        "Search ${kind.title}s".uppercase(), style = IosTypography.footnote, color = p.secondaryText,
                        modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
                    )
                }
                item {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .background(p.secondaryBackground, RoundedCornerShape(topStart = Tokens.Radius.small, topEnd = Tokens.Radius.small))
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                    ) {
                        if (query.isEmpty()) Text("Search...", style = IosTypography.body, color = p.tertiaryText)
                        BasicTextField(
                            value = query,
                            onValueChange = { query = it },
                            singleLine = true,
                            textStyle = IosTypography.body.copy(color = p.text),
                            cursorBrush = SolidColor(Appearance.tint),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                val rowBg = Modifier.fillMaxWidth().background(p.secondaryBackground)
                if (RateMePickerOptions.isLoading(storeKind) && options.isEmpty()) {
                    item {
                        Row(rowBg.padding(16.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(18.dp), color = p.secondaryText, strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text("Loading...", style = IosTypography.subheadline, color = p.secondaryText)
                        }
                    }
                } else {
                    items(options.take(50), key = { it.id }) { option ->
                        Column(rowBg) {
                            Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(p.separator))
                            Text(
                                option.name, style = IosTypography.body, color = p.text,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        view.performRateMeHaptic(RateMeHaptic.Selection)
                                        onPick(option)
                                    }
                                    .padding(horizontal = 16.dp, vertical = 12.dp),
                            )
                        }
                    }
                    if (options.size > 50) {
                        item { Text("Type more to refine...", style = IosTypography.caption, color = p.secondaryText, modifier = rowBg.padding(16.dp)) }
                    }
                    if (RateMePickerOptions.isSearching(storeKind)) {
                        item {
                            Box(rowBg.padding(12.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(18.dp), color = p.secondaryText, strokeWidth = 2.dp)
                            }
                        }
                    } else if (query.isNotEmpty() && options.isEmpty()) {
                        item {
                            Text(
                                "No ${kind.title.lowercase()}s match '$query'", style = IosTypography.body, color = p.secondaryText,
                                modifier = rowBg.padding(16.dp),
                            )
                        }
                    }
                }
                item {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(Tokens.Radius.small)
                            .background(p.secondaryBackground, RoundedCornerShape(bottomStart = Tokens.Radius.small, bottomEnd = Tokens.Radius.small)),
                    )
                }
            }
        }
    }
}
