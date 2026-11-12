package de.letzgo.stashy.ui.tools.rateme

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
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
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeSectionFooter
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.scaledIconSize
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tabBarHeight
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsBreadcrumbChrome
import de.letzgo.stashy.ui.tools.ToolsMenuItem
import de.letzgo.stashy.ui.tools.ToolsMenuSectionHeader
import de.letzgo.stashy.ui.tools.ToolsRowMenu
import de.letzgo.stashy.ui.tools.ToolsRowMenuOption
import de.letzgo.stashy.ui.tools.ToolsCrumbPickerMenu
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.match.MatchActionButton
import de.letzgo.stashy.ui.tools.match.MatchLoadingView
import de.letzgo.stashy.ui.tools.match.MatchPill
import de.letzgo.stashy.ui.tools.match.MatchUnavailableView
import de.letzgo.stashy.ui.tools.match.matchCard
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// iOS: `RateMeToolsView` (`stashy/RateMeToolsView.swift`). Layout follows the Match tool.

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

/**
 * iOS: `RateMeToolsView` — random unrated scenes / images with a star rating, O-counter,
 * delete, Skip and Watch / Open. Root composable hosted full screen by the Tools tab.
 */
@Composable
fun RateMeToolView() {
    val config = ServerConfigManager.activeConfig
    if (config == null) {
        Box(Modifier.fillMaxSize()) {
            NoServerPlaceholder(SF.starFill, tr(R.string.hint_select_server_first_to_use_rateme))
            ToolsBreadcrumbChrome()
        }
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
    val density = LocalDensity.current
    var bottomChromePx by remember { mutableIntStateOf(0) }
    val bottomChrome = with(density) { bottomChromePx.toDp() }
    val isRegular = LocalConfiguration.current.screenWidthDp >= 600
    val hPad = if (isRegular) Tokens.Spacing.xl else ToolsTokens.contentPadding
    val item = model.item

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().padding(top = toolsTopPadding())) {
            model.errorMessage?.let { err ->
                Text(
                    err, style = IosTypography.footnote, color = StashyColors.systemRed, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = ToolsTokens.contentPadding),
                )
            }
            // The air the Scenes / Images pills used to give (they moved into the Tools row).
            Spacer(Modifier.height(ToolsTokens.menuTopPadding))
            val bottom = bottomBarContentPadding() + if (item != null) bottomChrome else 0.dp
            Content(model, hPad, isRegular, bottom) { showDeleteConfirmation = true }
        }

        // Match `DuelActionsRow` — Skip / Watch above the tab bar.
        if (item != null) {
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(bottom = tabBarHeight())
                    .onSizeChanged { bottomChromePx = it.height },
            ) {
                ActionRow(model, item, hPad)
            }
        }
        // iOS: `toolsBreadcrumbChrome { modeMenu; themeMenu }` — Scenes / Images, then theme (and
        // media kind) in the Tools row.
        ToolsBreadcrumbChrome(
            crumb = {
                ToolsCrumbPickerMenu(
                    title = tr(R.string.rateme_section),
                    options = RateMeMode.entries.map { ToolsRowMenuOption(it, it.label, ModeIcons.getValue(it)) },
                    selection = model.mode,
                    label = model.mode.label,
                    enabled = !model.isSubmitting,
                    active = true,
                ) { mode ->
                    if (mode != model.mode && !model.isSubmitting) {
                        view.performRateMeHaptic(RateMeHaptic.Selection)
                        model.selectMode(mode)
                    }
                }
            },
        ) {
            ThemeMenu(model) { themePicker = it }
        }
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
            confirmLabel = tr(R.string.action_delete),
            destructive = true,
            dismissLabel = tr(R.string.action_cancel),
            onConfirm = {
                showDeleteConfirmation = false
                model.deleteCurrentAsync()
            },
        )
    }
}

// MARK: - Chrome

/**
 * iOS: `themeMenu` — the round's theme (and in Images the media kind) as one menu at the right of
 * the Tools row; it was a chip row above the card. Performer / Studio / Tag open their picker
 * sheet ([onPick]) and show the picked name once set. Label: the current theme's icon, with a
 * tint dot while Images is narrowed to one media kind.
 */
@Composable
private fun ThemeMenu(model: RateMeViewModel, onPick: (RateMeThemePickerKind) -> Unit) {
    val view = LocalView.current
    ToolsRowMenu(
        icon = themeIcon(model.theme),
        accessibilityLabel = tr(R.string.arg_theme, model.theme.label),
        isActive = model.mode == RateMeMode.Images && model.imageMediaKind != RateMeImageMediaKind.All,
        enabled = !model.isSubmitting,
    ) { dismiss ->
        ToolsMenuSectionHeader(tr(R.string.theme))
        model.availableFixedThemes.forEach { theme ->
            ToolsMenuItem(theme.label, themeIcon(theme), checked = model.theme == theme) {
                dismiss()
                view.performRateMeHaptic(RateMeHaptic.Selection)
                model.selectThemeAsync(theme)
            }
        }
        HorizontalDivider()
        ToolsMenuSectionHeader(tr(R.string.only))
        RateMeThemePickerKind.entries.forEach { kind ->
            val picked = kind.picked(model.theme)
            ToolsMenuItem(picked?.label ?: "${kind.title}…", pickerIcon(kind), checked = picked != null) {
                dismiss()
                view.performRateMeHaptic(RateMeHaptic.Selection)
                onPick(kind)
            }
        }
        if (model.mode == RateMeMode.Images) {
            HorizontalDivider()
            ToolsMenuSectionHeader(tr(R.string.media))
            RateMeImageMediaKind.entries.forEach { kind ->
                ToolsMenuItem(kind.title, null, checked = kind == model.imageMediaKind) {
                    dismiss()
                    if (kind != model.imageMediaKind) model.selectImageMediaKind(kind)
                }
            }
        }
    }
}

/** iOS: `RateMeViewModel.Theme.icon`. */
private fun themeIcon(theme: RateMeTheme): ImageVector = when (theme) {
    RateMeTheme.Random -> SF.shuffle
    RateMeTheme.Newest -> SF.sparkles
    RateMeTheme.MostPlayed -> Icons.Outlined.PlayCircle
    is RateMeTheme.Performer -> SF.personFill
    is RateMeTheme.Studio -> Icons.Filled.Business
    is RateMeTheme.Tag -> Icons.Filled.Sell
}

/** iOS: `ThemePickerKind.icon`. */
private fun pickerIcon(kind: RateMeThemePickerKind): ImageVector = when (kind) {
    RateMeThemePickerKind.Performer -> SF.personFill
    RateMeThemePickerKind.Studio -> Icons.Filled.Business
    RateMeThemePickerKind.Tag -> Icons.Filled.Sell
}

// MARK: - Content

/**
 * Match `BattleContent` padding, but no scroll: the media shrinks to the height left above the
 * action row, so the card (rating included) always ends above the buttons (iOS `content`).
 */
@Composable
private fun Content(model: RateMeViewModel, hPad: Dp, isRegular: Boolean, bottom: Dp, onDelete: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .padding(horizontal = hPad)
            .padding(bottom = bottom + ToolsTokens.menuBottomPadding),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val item = model.item
        when {
            model.isLoading && item == null -> MatchLoadingView(tr(R.string.loading), Modifier.fillMaxWidth().heightIn(min = 320.dp))
            item != null -> ItemCard(
                model, item,
                Modifier.fillMaxWidth().weight(1f, fill = false).let { if (isRegular) it.widthIn(max = 720.dp) else it },
                onDelete,
            )
            else -> MatchUnavailableView(
                tr(R.string.nothing_to_rate), ModeIcons.getValue(model.mode),
                tr(if (model.mode == RateMeMode.Scenes) R.string.hint_all_scenes_already_have_rating else R.string.hint_all_images_already_have_rating),
                Modifier.fillMaxWidth().heightIn(min = 320.dp),
            )
        }
    }
}

/** iOS: `mediaCard` + `ratingRow` — media, then title / performers and stars, O-counter, delete. */
@Composable
private fun ItemCard(model: RateMeViewModel, item: RateMeItem, modifier: Modifier, onDelete: () -> Unit) {
    val p = Theme.palette
    val aspect = item.aspectRatio ?: if (item.mode == RateMeMode.Scenes) 16f / 9f else 1f
    Column(modifier.matchCard().alpha(if (model.isSubmitting) 0.85f else 1f)) {
        Box(Modifier.fillMaxWidth().weight(1f, fill = false), contentAlignment = Alignment.Center) {
            RateMeMediaView(item, Modifier.aspectRatio(aspect))
        }
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                item.title, style = IosTypography.headline.copy(fontWeight = FontWeight.Bold), color = p.text,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            item.performerNames?.let {
                Text(it, style = IosTypography.subheadline, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            RatingRow(model, item, onDelete)
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
    // Stars follow the font scale (capped 1.5×); each is a gap-less cell ≥ 48 dp tall.
    val star = scaledIconSize(size, maxScale = 1.5f)
    Row {
        for (index in 1..5) {
            val filled = index <= stars
            Box(
                Modifier
                    .heightIn(min = 48.dp)
                    .width(star + spacing)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (!interactive) return@clickable
                        view.performRateMeHaptic(RateMeHaptic.Selection)
                        onChange(RateMeLogic.ratingAfterTap(rating100, index))
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (filled) SF.starFill else SF.star, tr(R.string.action_rate_arg_stars, index),
                    tint = if (filled) Appearance.tint else Color.Gray.copy(alpha = 0.5f),
                    modifier = Modifier.size(star),
                )
            }
        }
    }
}

/** iOS: `ratingRow` — stars left; O-counter and delete as plain icon buttons on the right. */
@Composable
private fun RatingRow(model: RateMeViewModel, item: RateMeItem, onDelete: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    val view = LocalView.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
            StarRating(model.draftRating100, interactive = !model.isSubmitting && !model.isDeleting, size = 24.dp, spacing = 4.dp) {
                model.submitRatingAsync(it)
            }
        }
        val oEnabled = !model.isSubmitting && !model.isIncrementingO && !model.isDeleting
        Row(
            Modifier
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(50))
                .clickable(enabled = oEnabled) { model.incrementOCounterAsync() }
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                oCounterIcon(Appearance.oCounterIcon, filled = item.oCounter > 0),
                tr(R.string.hint_o_count_arg_tap_to_increment, item.oCounter),
                tint = if (item.oCounter > 0) tint else p.secondaryText,
                modifier = Modifier.size(20.dp),
            )
            Text(
                "${item.oCounter}",
                style = IosTypography.body.merge(TextStyle(fontFeatureSettings = "tnum")).copy(fontWeight = FontWeight.Bold),
                color = p.text, maxLines = 1,
            )
        }
        IconButton(
            onClick = {
                view.performRateMeHaptic(RateMeHaptic.Light)
                onDelete()
            },
            enabled = !model.isSubmitting && !model.isDeleting && !model.isLoading,
        ) {
            Icon(Icons.Filled.Delete, tr(R.string.action_delete), tint = StashyColors.systemRed, modifier = Modifier.size(22.dp))
        }
    }
}

/** Match `DuelActionsRow` — Skip and Watch / Open, equal weight. */
@Composable
private fun ActionRow(model: RateMeViewModel, item: RateMeItem, hPad: Dp) {
    val view = LocalView.current
    val enabled = !model.isSubmitting && !model.isLoading
    Row(Modifier.fillMaxWidth().padding(horizontal = hPad).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MatchActionButton(tr(R.string.action_skip), Icons.Filled.FastForward, prominent = false, enabled = enabled, modifier = Modifier.weight(1f)) {
            view.performRateMeHaptic(RateMeHaptic.Light)
            model.skipAsync()
        }
        if (item.mode == RateMeMode.Scenes) {
            MatchActionButton(tr(R.string.watch), SF.playFill, prominent = true, enabled = enabled, modifier = Modifier.weight(1f), accessibilityLabel = tr(R.string.watch_scene)) {
                view.performRateMeHaptic(RateMeHaptic.Light)
                // Minimal Scene; the detail screen loads the full scene.
                Nav.push(SceneDetailScreen(item.id, Scene(id = item.id, title = item.title, oCounter = item.oCounter)))
            }
        } else {
            item.openableImage?.let { image ->
                MatchActionButton(tr(R.string.action_open), Icons.Filled.OpenInFull, prominent = true, enabled = enabled, modifier = Modifier.weight(1f), accessibilityLabel = tr(R.string.action_open_image)) {
                    view.performRateMeHaptic(RateMeHaptic.Light)
                    Nav.push(ImageViewerScreen(listOf(image), 0))
                }
            }
        }
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
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 400.dp).imePadding()) {
            // iOS `stashyModalSheetChrome(title, onBack:)` → Material sheet top bar.
            de.letzgo.stashy.ui.NativeSheetTopBar(kind.title, onClose = {
                scope.launch {
                    sheetState.hide()
                    onDismiss()
                }
            })
            LazyColumn(
                Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
            ) {
                item {
                    NativeSearchField(
                        query, { query = it }, kind.searchTitle,
                        Modifier.padding(bottom = 12.dp),
                        loading = RateMePickerOptions.isSearching(storeKind),
                    )
                }
                item { NativeSectionHeader(when (kind) { RateMeThemePickerKind.Performer -> tr(R.string.performers); RateMeThemePickerKind.Studio -> tr(R.string.studios); RateMeThemePickerKind.Tag -> tr(R.string.tags) }) }
                item {
                    NativeGroup {
                        if (RateMePickerOptions.isLoading(storeKind) && options.isEmpty()) {
                            NativeListItem(tr(R.string.loading) + "…", headlineColor = p.secondaryText, leading = {
                                CircularProgressIndicator(Modifier.size(24.dp), color = p.secondaryText, strokeWidth = 2.dp)
                            })
                        } else if (options.isEmpty()) {
                            if (query.isNotEmpty() && !RateMePickerOptions.isSearching(storeKind)) {
                                NativeListItem(tr(R.string.empty_results_for_arg, query), headlineColor = p.secondaryText)
                            }
                        } else {
                            options.take(50).forEachIndexed { index, option ->
                                if (index > 0) NativeDivider()
                                NativeListItem(option.name, onClick = {
                                    view.performRateMeHaptic(RateMeHaptic.Selection)
                                    onPick(option)
                                })
                            }
                        }
                    }
                }
                if (options.size > 50) item { NativeSectionFooter(tr(R.string.type_more_to_refine_menu)) }
            }
        }
    }
}
