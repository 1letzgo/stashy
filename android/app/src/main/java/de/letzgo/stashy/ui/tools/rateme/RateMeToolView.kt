package de.letzgo.stashy.ui.tools.rateme

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
import androidx.compose.material.icons.filled.OpenInFull
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
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.match.MatchActionButton
import de.letzgo.stashy.ui.tools.match.MatchLoadingView
import de.letzgo.stashy.ui.tools.match.MatchPill
import de.letzgo.stashy.ui.tools.match.MatchPillMenuRow
import de.letzgo.stashy.ui.tools.match.MatchPillSpacing
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
            MatchPillMenuRow(
                items = RateMeMode.entries.map { it.label },
                selectedIndex = model.mode.ordinal,
                onSelect = { idx ->
                    if (!model.isSubmitting) {
                        view.performRateMeHaptic(RateMeHaptic.Selection)
                        model.selectMode(RateMeMode.entries[idx])
                    }
                },
            )
            ThemeRow(model) { themePicker = it }
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

/** iOS: `themeChips` — media kind menu (images), fixed themes, performer / studio / tag pickers. */
@Composable
private fun ThemeRow(model: RateMeViewModel, onPick: (RateMeThemePickerKind) -> Unit) {
    val view = LocalView.current
    val state = rememberLazyListState()
    val fixed = model.availableFixedThemes
    val pickers = RateMeThemePickerKind.entries
    val leading = if (model.mode == RateMeMode.Images) 1 else 0

    // A picked performer / studio / tag sits at the far end; bring its pill into view on change.
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
        Modifier.fillMaxWidth().padding(bottom = ToolsTokens.menuBottomPadding),
        state = state,
        contentPadding = PaddingValues(horizontal = ToolsTokens.contentPadding),
        horizontalArrangement = Arrangement.spacedBy(MatchPillSpacing),
        userScrollEnabled = !model.isSubmitting,
    ) {
        if (model.mode == RateMeMode.Images) item(key = "mediaKind") { MediaKindMenu(model) }
        items(fixed, key = { it.id }) { theme ->
            MatchPill(theme.label, selected = model.theme == theme, enabled = !model.isSubmitting) {
                view.performRateMeHaptic(RateMeHaptic.Selection)
                model.selectThemeAsync(theme)
            }
        }
        items(pickers, key = { it.raw }) { kind ->
            val picked = kind.picked(model.theme)
            MatchPill(picked?.label ?: "${kind.title}…", selected = picked != null, enabled = !model.isSubmitting) {
                view.performRateMeHaptic(RateMeHaptic.Selection)
                onPick(kind)
            }
        }
    }
}

/** iOS: `mediaKindMenu` — Any media / Images / Videos as a menu pill (images mode). */
@Composable
private fun MediaKindMenu(model: RateMeViewModel) {
    val p = Theme.palette
    var expanded by remember { mutableStateOf(false) }
    Box {
        MatchPill(
            model.imageMediaKind.title,
            selected = model.imageMediaKind != RateMeImageMediaKind.All,
            enabled = !model.isSubmitting,
        ) { expanded = true }
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
            model.isLoading && item == null -> MatchLoadingView("Loading…", Modifier.fillMaxWidth().heightIn(min = 320.dp))
            item != null -> ItemCard(
                model, item,
                Modifier.fillMaxWidth().weight(1f, fill = false).let { if (isRegular) it.widthIn(max = 720.dp) else it },
                onDelete,
            )
            else -> MatchUnavailableView(
                "Nothing to rate", ModeIcons.getValue(model.mode),
                "All ${model.mode.label.lowercase()} already have a rating.",
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
                    if (filled) SF.starFill else SF.star, "$index stars",
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
        IconButton(
            onClick = {
                view.performRateMeHaptic(RateMeHaptic.Light)
                onDelete()
            },
            enabled = !model.isSubmitting && !model.isDeleting && !model.isLoading,
        ) {
            Icon(Icons.Filled.Delete, "Delete", tint = StashyColors.systemRed, modifier = Modifier.size(22.dp))
        }
    }
}

/** Match `DuelActionsRow` — Skip and Watch / Open, equal weight. */
@Composable
private fun ActionRow(model: RateMeViewModel, item: RateMeItem, hPad: Dp) {
    val view = LocalView.current
    val enabled = !model.isSubmitting && !model.isLoading
    Row(Modifier.fillMaxWidth().padding(horizontal = hPad).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        MatchActionButton("Skip", Icons.Filled.FastForward, prominent = false, enabled = enabled, modifier = Modifier.weight(1f)) {
            view.performRateMeHaptic(RateMeHaptic.Light)
            model.skipAsync()
        }
        if (item.mode == RateMeMode.Scenes) {
            MatchActionButton("Watch", SF.playFill, prominent = true, enabled = enabled, modifier = Modifier.weight(1f), accessibilityLabel = "Watch Scene") {
                view.performRateMeHaptic(RateMeHaptic.Light)
                // Minimal Scene; the detail screen loads the full scene.
                Nav.push(SceneDetailScreen(item.id, Scene(id = item.id, title = item.title, oCounter = item.oCounter)))
            }
        } else {
            item.openableImage?.let { image ->
                MatchActionButton("Open", Icons.Filled.OpenInFull, prominent = true, enabled = enabled, modifier = Modifier.weight(1f), accessibilityLabel = "Open Image") {
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
                        query, { query = it }, "Search ${kind.title}s",
                        Modifier.padding(bottom = 12.dp),
                        loading = RateMePickerOptions.isSearching(storeKind),
                    )
                }
                item { NativeSectionHeader("${kind.title}s") }
                item {
                    NativeGroup {
                        if (RateMePickerOptions.isLoading(storeKind) && options.isEmpty()) {
                            NativeListItem("Loading...", headlineColor = p.secondaryText, leading = {
                                CircularProgressIndicator(Modifier.size(24.dp), color = p.secondaryText, strokeWidth = 2.dp)
                            })
                        } else if (options.isEmpty()) {
                            if (query.isNotEmpty() && !RateMePickerOptions.isSearching(storeKind)) {
                                NativeListItem("No ${kind.title.lowercase()}s match '$query'", headlineColor = p.secondaryText)
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
                if (options.size > 50) item { NativeSectionFooter("Type more to refine...") }
            }
        }
    }
}
