package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.ui.player.PlayerMute
import de.letzgo.stashy.ui.tabBarHeight
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.ui.components.AddTagsSheet
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.ui.catalog.StandardLoading
import de.letzgo.stashy.ui.catalog.StatusPlaceholder
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.FeedsTabBarPolicy
import de.letzgo.stashy.ui.TabBarAutoHide
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.stashyGlass
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * iOS: `ReelsView` / `ReelsViewBody` (StashTok) — the Feeds tab.
 *
 * Edge-to-edge vertical pager (one row per screen) with autoplay of the settled row and
 * preloading of its neighbours ([FeedPlayerPool]); the section chrome (feed dropdown, then
 * Delete · sort dropdown · Filter & Sort) floats on top, the info overlay and scrubber sit right above the floating tab bar.
 * Tapping the media hides all chrome including the tab bar, like iOS. With "Auto-hide tab bar"
 * on, a swipe to a later row also slides the bar away (the overlay follows it down); the first
 * row, a tab / mode switch or tapping the chrome back in returns it. Pics is the Images
 * catalog's 1/row feed under the same chrome ([PicsFeed]); loading / empty / error states and
 * Pics sit on the app background like iOS (`StashyThemeFill(.app)`), video rows on black.
 *
 * Known differences to iOS: the AI Motion pill (device control) is not ported (Play policy).
 *
 * Markers play their window of the original scene (`seconds … end_seconds`, else 30 s — see
 * [FeedSegment]) with audio, not Stash's generated marker clip; the scrubber spans that window.
 * Feeds never writes a resume time, so a marker leaves its scene's resume point alone.
 */
@Composable
fun FeedsScreen() {
    val model = FeedsModel
    de.letzgo.stashy.ui.DarkSurfaceBehindSystemBars(model.mode != de.letzgo.stashy.data.ReelsModeType.Pics)
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pool = remember { FeedPlayerPool(context) }

    remember { if (model.isMuted == null) model.isMuted = PlayerMute.initialValue() }
    val muted = model.isMuted ?: true
    VolumeUnmuteEffect(muted) {
        model.isMuted = false
        PlayerMute.remember(false)
    }
    LaunchedEffect(muted) { pool.updateMuted(muted) }

    var isUIVisible by remember { mutableStateOf(true) }
    /** Section chrome faded out while flicking through rows ([FeedsChromeAutoHide]); on top of [isUIVisible]. */
    var chromeScrollHidden by remember { mutableStateOf(false) }
    var showSheet by remember { mutableStateOf(false) }
    var isZoomed by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<FeedItem?>(null) }
    /** iOS `tagEditorTarget` — the row whose `AddTagsSheet` is open. */
    var tagEditorTarget by remember { mutableStateOf<AITagTarget?>(null) }
    /** The row whose "Add Performers" picker is open (overlay "+" after the names). */
    var performerTarget by remember { mutableStateOf<FeedItem?>(null) }
    /** iOS `wasPlayingBeforeTagEditor`. */
    var wasPlayingBeforeTagEditor by remember { mutableStateOf(false) }
    var lifecycleActive by remember { mutableStateOf(true) }

    // Deep link (channel, performer …) or a plain appear.
    LaunchedEffect(FeedsNav.token) {
        val link = FeedsNav.consume()
        if (link != null) {
            pool.teardown()
            model.apply(link)
            isUIVisible = true
        } else model.onAppear()
    }
    // Tab icon tapped again while on Feeds: restart from the top (iOS `reelsWillRemount`).
    val reselects = Nav.reselects[MainTab.Feeds] ?: 0
    val initialReselects = remember { reselects }
    LaunchedEffect(reselects) {
        if (reselects != initialReselects) {
            pool.teardown()
            model.restartFromTop()
            if (model.mode == ReelsModeType.Pics) model.picsListState.scrollToItem(0)
        }
    }

    // Background pauses, foreground resumes. The screen stays on only while a row actually plays
    // (FeedPlayerPool → ScreenAwakeCoordinator), not merely while Feeds is up.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> { lifecycleActive = false; pool.pauseAll() }
                Lifecycle.Event.ON_RESUME -> { lifecycleActive = true; model.isPlaying = true }
                else -> {}
            }
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            Nav.rootHidesTabBar = false
            pool.release()
        }
    }
    LaunchedEffect(isUIVisible) {
        Nav.rootHidesTabBar = !isUIVisible
        // Auto-hide: tapping the chrome back in brings an auto-hidden tab bar with it.
        TabBarAutoHide.apply(FeedsTabBarPolicy.onChromeVisibilityChanged(isUIVisible))
    }

    // Toast-like messages (iOS `ToastManager`).
    var toast by remember { mutableStateOf<String?>(null) }
    // Taking the message over resets `model.message`, which restarts an effect keyed on it and
    // cancelled the hide delay: the toast stayed up. The hide is keyed on the toast instead.
    LaunchedEffect(model.message) {
        model.message?.let { toast = it; model.message = null }
    }
    LaunchedEffect(toast) {
        if (toast != null) { delay(2_000); toast = null }
    }

    val mode = model.mode
    val list = model.list(mode)
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    // Height the tab bar covers (bar + system nav inset, measured in AppShell) while the chrome
    // shows. An auto-hidden bar (Settings › Appearance) slides away; the overlay and scrubber
    // follow it down to the system inset with the bar's own animation.
    val barShown by animateFloatAsState(
        if (TabBarAutoHide.enabled && TabBarAutoHide.hidden) 0f else 1f,
        tween(TabBarAutoHide.ANIMATION_MS), label = "feedsTabBarInset",
    )
    val tabBarOverlap = FeedsTabBarPolicy.overlayInset(isUIVisible, barShown, tabBarHeight().value, navBottom.value).dp
    // Sheets and dialogs keep the bar where it is.
    val overlayOpen = showSheet || tagEditorTarget != null || performerTarget != null || deleteTarget != null || model.pics.isSheetPresented
    // A sheet / dialog or a mode switch always brings swipe-hidden chrome back.
    LaunchedEffect(overlayOpen, mode) { chromeScrollHidden = false }
    // Reduce Motion (animator duration scale 0): fade only, no slide.
    val reduceMotion = remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }

    // Height of the top chrome (bar + criterion chips): Pics content starts below it (iOS safeAreaInset).
    val density = LocalDensity.current
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    var measuredChrome by remember { mutableStateOf<androidx.compose.ui.unit.Dp?>(null) }
    val chromeHeight = measuredChrome ?: (statusTop + FeedsDock.activeHeight + 17.dp)

    // Rows are black; the states and Pics sit on the app background (iOS `StashyThemeFill(.app)`).
    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        val items = model.visibleItems(mode)
        when {
            // Pics keeps the full bar padding while the bar auto-hides, like every other list.
            mode == ReelsModeType.Pics -> PicsFeed(model, topPadding = chromeHeight, bottomPadding = if (isUIVisible) tabBarHeight() else navBottom)
            ServerConfigManager.activeConfig == null -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { model.refetch(mode) })
            items.isEmpty() && list.isLoading -> StandardLoading("Loading feeds...")
            items.isEmpty() && list.error != null -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { model.refetch(mode) })
            items.isEmpty() && list.loadedOnce -> StatusPlaceholder(emptyIcon(mode), emptyTitle(mode), "Reload", { model.refetch(mode) })
            items.isEmpty() -> StandardLoading("Loading feeds...")
            else -> androidx.compose.runtime.key(mode) {
                FeedPager(
                    model = model, mode = mode, items = items, pool = pool,
                    isUIVisible = isUIVisible, isZoomed = isZoomed, lifecycleActive = lifecycleActive,
                    tabBarOverlap = tabBarOverlap,
                    overlayOpen = overlayOpen,
                    onToggleUI = {
                        if (FeedsChromeAutoHide.tapReveals(chromeScrollHidden)) chromeScrollHidden = false
                        else isUIVisible = !isUIVisible
                    },
                    onDragStarted = {
                        if (FeedsChromeAutoHide.hidesOnDrag(mode, overlayOpen, isZoomed)) chromeScrollHidden = true
                    },
                    onZoom = { isZoomed = it },
                    onAddTags = { target ->
                        // iOS `.onChange(of: tagEditorTarget?.id)`: nobody wants a clip looping
                        // with sound behind the tag picker.
                        wasPlayingBeforeTagEditor = model.isPlaying
                        model.isPlaying = false
                        tagEditorTarget = target
                    },
                    onAddPerformers = { item ->
                        wasPlayingBeforeTagEditor = model.isPlaying
                        model.isPlaying = false
                        performerTarget = item
                    },
                )
            }
        }

        // Top chrome: feed dropdown · Delete · sort · Filter & Sort, criterion chips below (iOS `reelsNavBar`).
        // Auto-hide (pager modes only): slides up and fades out together with the tab bar, on
        // the same trigger and animation; rows are full-screen, so the video just gains room.
        val tapAlpha by animateFloatAsState(if (isUIVisible) 1f else 0f, tween(200), label = "chrome")
        // Swipe auto-hide (FeedsChromeAutoHide): a short slide up with the fade, fade only with Reduce Motion.
        val scrollShown by animateFloatAsState(if (chromeScrollHidden) 0f else 1f, tween(if (reduceMotion) 150 else 250), label = "chromeScroll")
        val topShown = FeedsTabBarPolicy.topChromeShownFraction(mode == ReelsModeType.Pics, barShown)
        val chromeAlpha = tapAlpha * topShown * scrollShown
        val scrollSlidePx = with(density) { 16.dp.toPx() }
        Column(
            Modifier.fillMaxWidth().align(Alignment.TopCenter)
                .graphicsLayer {
                    alpha = chromeAlpha
                    translationY = -(1f - topShown) * size.height - (if (reduceMotion) 0f else (1f - scrollShown) * scrollSlidePx)
                }
                .onSizeChanged { with(density) { if (chromeAlpha > 0.99f) measuredChrome = it.height.toDp() } },
        ) {
            if (chromeAlpha > 0.01f) {
                // iOS `reelsNavBar`: Delete (item on screen; not Pics, never markers, only with
                // "Show delete button") · sort menu · Filter & Sort.
                val currentItem = if (mode == ReelsModeType.Pics) null
                    else model.currentIds[mode]?.let { id -> items.firstOrNull { it.id == id } }
                FeedsTopBar(
                    modes = FeedsConfig.enabledModes,
                    selected = mode,
                    onSelect = { m -> pool.teardown(); isZoomed = false; model.selectMode(m) },
                    sort = feedsSortMenuState(model, mode) { pool.teardown() },
                    onDelete = currentItem?.takeIf { FeedsConfig.showsDeleteButton && it.supportsDelete }?.let { item -> { deleteTarget = item } },
                    onFilterSort = { if (mode == ReelsModeType.Pics) model.pics.isSheetPresented = true else showSheet = true },
                )
                val c = model.criteria
                if (!c.isEmpty) FeedsCriterionChips(
                    performer = c.performer, studio = c.studio, tags = c.tags,
                    onClearPerformer = { model.clearPerformer() },
                    onClearStudio = { model.clearStudio() },
                    onRemoveTag = { model.toggleTag(it) },
                )
            }
        }

        AnimatedVisibility(toast != null, Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 64.dp), enter = fadeIn(), exit = fadeOut()) {
            Text(
                toast.orEmpty(), color = Color.White, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold),
                modifier = Modifier.stashyGlass(RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }

    if (showSheet && mode != ReelsModeType.Pics) {
        FeedsFilterSortSheet(
            mode = mode,
            filters = model.filtersFor(mode),
            localPresets = model.localPresets(mode),
            presetRow = model.presetRow(mode),
            presetName = model.presetName(mode),
            selectedFilter = model.filters[mode],
            sort = model.sort(mode),
            sortOptions = model.sortOptions(mode),
            onPresetRow = { pool.teardown(); model.selectPresetRow(mode, it) },
            onSaveOverwrite = { model.saveOverwrite(mode) },
            onSaveAs = { model.saveAs(mode, it) },
            onRename = { model.rename(mode, it) },
            onDelete = { model.deletePreset(mode) },
            deleteConfirmationText = { model.deleteConfirmationText(mode) },
            onSort = { pool.teardown(); model.setSort(mode, it) },
            onCriteriaChanged = { pool.teardown(); model.applyCriteriaDocument(mode) },
            onReset = { pool.teardown(); model.reset(mode) },
            onDismiss = { showSheet = false },
        )
    }

    tagEditorTarget?.let { target ->
        // The rows patch themselves through `AITagSuggestions.events` (iOS *TagsUpdated broadcasts).
        AddTagsSheet(target, onDismiss = {
            tagEditorTarget = null
            if (wasPlayingBeforeTagEditor) { wasPlayingBeforeTagEditor = false; model.isPlaying = true }
        }) { }
    }

    performerTarget?.let { item ->
        // The scene detail's performer picker, add-only (existing ∪ picked via FeedsModel.addPerformers).
        de.letzgo.stashy.ui.scene.PerformersPickerSheet(
            itemKey = item.id,
            current = item.performers.map { de.letzgo.stashy.ui.scene.PickerEntry(it.id, it.name, null, it.thumbnailURL) },
            addOnly = true,
            save = { _, picked -> check(model.addPerformers(item, picked)) },
            onDismiss = {
                performerTarget = null
                if (wasPlayingBeforeTagEditor) { wasPlayingBeforeTagEditor = false; model.isPlaying = true }
            },
        )
    }

    deleteTarget?.let { item ->
        val isImage = item is FeedItem.ClipItem
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text(if (isImage) "Delete image?" else "Delete scene?") },
            text = { Text(if (isImage) "The image is removed from the server. This cannot be undone." else "The scene and its files are removed from the server. This cannot be undone.") },
            confirmButton = { TextButton({ deleteTarget = null; model.delete(item) {} }) { Text("Delete", color = Color(0xFFFF453A)) } },
            dismissButton = { TextButton({ deleteTarget = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun FeedPager(
    model: FeedsModel,
    mode: ReelsModeType,
    items: List<FeedItem>,
    pool: FeedPlayerPool,
    isUIVisible: Boolean,
    isZoomed: Boolean,
    lifecycleActive: Boolean,
    tabBarOverlap: androidx.compose.ui.unit.Dp,
    overlayOpen: Boolean,
    onToggleUI: () -> Unit,
    onDragStarted: () -> Unit,
    onZoom: (Boolean) -> Unit,
    onAddTags: (AITagTarget) -> Unit,
    onAddPerformers: (FeedItem) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val list = model.list(mode)
    val startIndex = remember(mode) { model.currentIds[mode]?.let { id -> items.indexOfFirst { it.id == id } }?.coerceAtLeast(0) ?: 0 }
    val pagerState = rememberPagerState(initialPage = startIndex) { items.size }
    val currentItems by rememberUpdatedState(items)

    // Settled page → session position (iOS `scrollPosition(id:)`).
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }.collect { idx ->
            currentItems.getOrNull(idx)?.let { model.currentIds[mode] = it.id }
        }
    }
    // Auto-hide tab bar (Settings › Appearance): a user swipe on to a later row slides the bar
    // away, the first row brings it back (FeedsTabBarPolicy). Programmatic moves (continuous
    // play, restore) only count when they land on the first row.
    val overlayOpenNow by rememberUpdatedState(overlayOpen)
    val onDragStartedNow by rememberUpdatedState(onDragStarted)
    LaunchedEffect(pagerState) {
        var swiped = false
        launch {
            pagerState.interactionSource.interactions.collect {
                if (it is androidx.compose.foundation.interaction.DragInteraction.Start) {
                    swiped = true
                    // Swipe-hidden chrome stays out while watching; a tap brings it back.
                    onDragStartedNow()
                }
            }
        }
        var from = pagerState.settledPage
        snapshotFlow { pagerState.isScrollInProgress }.collect { inProgress ->
            if (inProgress) return@collect
            val to = pagerState.currentPage
            TabBarAutoHide.apply(FeedsTabBarPolicy.onPageSettled(from, to, swiped, overlayOpenNow))
            from = to
            swiped = false
        }
    }
    val activeId = model.currentIds[mode]
    // New timeline / dropped rows / restore: follow the session id, else start at the top.
    LaunchedEffect(list.generation, activeId, items.size) {
        val idx = items.indexOfFirst { it.id == activeId }
        if (idx >= 0) {
            if (idx != pagerState.currentPage && !pagerState.isScrollInProgress) pagerState.scrollToPage(idx)
        } else if (items.isNotEmpty()) {
            pagerState.scrollToPage(0)
            model.currentIds[mode] = items[0].id
        }
    }

    val activeIndex = items.indexOfFirst { it.id == activeId }
    val activeItem = items.getOrNull(activeIndex)
    val scrolling = pagerState.isScrollInProgress
    val continuous = FeedsConfig.continuousPlay
    val isPlaying = model.isPlaying
    val playingNow = isPlaying && !scrolling && lifecycleActive

    // Bind the preload window to the player pool.
    LaunchedEffect(activeId, items.size, playingNow, continuous) {
        val window = PreloadWindow.indices(activeIndex, items.size, pool.size) { !items[it].isVideo }
            .map { i -> items[i].let { FeedMediaRequest(it.id, it.videoSources, loop = !continuous, segment = it.segment, startSeconds = model.startPosition(it)) } }
        pool.sync(window, activeId, playingNow)
    }
    // Continuous play: the next row when a video ends (iOS `onVideoEnded` → `advanceToNextItem`).
    val currentActive by rememberUpdatedState(activeId)
    DisposableEffect(pool) {
        pool.onEnded = { id ->
            if (id == currentActive) {
                val idx = currentItems.indexOfFirst { it.id == id }
                if (idx >= 0 && idx + 1 < currentItems.size) scope.launch { pagerState.animateScrollToPage(idx + 1) }
            }
        }
        // Previews whose file never got generated are dropped; the next row takes over.
        pool.onUnplayable = { id -> model.dropUnplayable(id) }
        onDispose { pool.onEnded = null; pool.onUnplayable = null }
    }
    // Animated clips advance on a timer with continuous play (iOS `startAnimationAdvanceTimer`).
    LaunchedEffect(activeId, isPlaying, continuous, scrolling) {
        val item = activeItem ?: return@LaunchedEffect
        if (item.isAnimated && continuous && isPlaying && !scrolling) {
            delay(((item.duration ?: 5.0) * 1000).toLong())
            if (activeIndex + 1 < items.size) pagerState.animateScrollToPage(activeIndex + 1)
        }
    }
    // Paging + dead-row probing (iOS `reelItemRow.onAppear`, `probeUpcomingMedia`).
    LaunchedEffect(activeIndex, items.size) {
        if (PreloadWindow.shouldLoadMore(activeIndex, items.size)) model.loadMore(mode)
        model.probeUpcomingMedia()
    }

    // Scrubber state of the active row (iOS `ScrubberState`), play-count credit and checkpoint.
    var time by remember { mutableDoubleStateOf(0.0) }
    var duration by remember { mutableDoubleStateOf(activeItem?.duration ?: 1.0) }
    /** The "Add Marker" sheet's scene + file time, and whether the feed was playing when it opened. */
    var markerDraft by remember { mutableStateOf<FeedsMarkerDraft?>(null) }
    var resumesAfterMarkerSheet by remember { mutableStateOf(false) }
    var seeking by remember { mutableStateOf(false) }
    LaunchedEffect(activeId) {
        time = 0.0
        duration = activeItem?.duration?.takeIf { it > 0 } ?: 1.0
        var watched = 0.0
        var credited = false
        var restored = false
        while (true) {
            val player = pool.player(activeId)
            if (player != null) {
                // iOS `applySavedPlaybackCheckpointIfMatching`.
                if (!restored && player.playbackState == androidx.media3.common.Player.STATE_READY) {
                    restored = true
                    model.checkpoint?.takeIf { it.first == activeId }?.let { pool.seek(activeId, it.second); model.checkpoint = null }
                }
                if (!seeking) time = player.currentPosition / 1000.0
                pool.durations[activeId]?.let { duration = it }
                if (player.isPlaying) {
                    watched += 0.1
                    // iOS `noteReelsWatchProgress`: credit once after "Count as played — Feeds".
                    if (!credited && activeItem?.countsPlays == true && watched >= (if (model.mode == de.letzgo.stashy.data.ReelsModeType.Verticals) de.letzgo.stashy.data.TabManager.playCountVerticalsSeconds.toFloat() else FeedsConfig.playCountFeedsSeconds)) {
                        credited = true
                        activeItem.let { model.creditPlay(it) }
                    }
                }
            }
            delay(100)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            // iOS `savePlaybackCheckpoint` — resumes mid-clip after a tab switch or push.
            val id = model.currentIds[mode]
            model.checkpoint = if (id != null && time > 0.25) id to time else null
        }
    }

    Box(Modifier.fillMaxSize()) {
        VerticalPager(
            state = pagerState,
            beyondViewportPageCount = 1,
            key = { i -> items.getOrNull(i)?.id ?: i },
            userScrollEnabled = !isZoomed,
            modifier = Modifier.fillMaxSize(),
        ) { page ->
            val item = items[page]
            FeedRow(
                item = item,
                player = pool.assignments[item.id],
                isActive = item.id == activeId,
                videoSize = pool.videoSizes[item.id],
                bottomInset = tabBarOverlap,
                isUIVisible = isUIVisible,
                isPlaying = isPlaying,
                isScrolling = scrolling,
                errorMessage = if (pool.failed[item.id] == true || (item.isVideo.not() && !item.isAnimated)) "No playable source" else null,
                onToggleUI = onToggleUI,
                onSkip = { delta ->
                    pool.player(item.id)?.let { p ->
                        // iOS `feedsDoubleTapMarkers`: a whole scene in Scenes jumps to the next / previous marker.
                        if (FeedsConfig.doubleTapJumpsToMarkers && mode == ReelsModeType.Scenes && item is FeedItem.SceneItem && item.segment == null) {
                            val pos = p.currentPosition / 1000.0
                            val known = item.id == activeId && duration > 0
                            val marks = FeedsMarkerTimes.seconds(item.scene).filter { !known || it < duration }
                            val jump = if (delta > 0) marks.firstOrNull { it > pos + 0.5 } else marks.lastOrNull { it < pos - 2.0 }
                            if (jump != null) { pool.seek(item.id, jump); return@let }
                        }
                        val target = (p.currentPosition / 1000.0 + delta).coerceAtLeast(0.0)
                        pool.seek(item.id, if (duration > 0) target.coerceAtMost(duration) else target)
                    }
                },
                onFastForward = { on -> pool.setRate(item.id, if (on) FeedsConfig.holdSpeedFeeds else 1f) },
                onZoomChanged = onZoom,
                onPlay = { model.isPlaying = true },
            )
        }

        // Bottom chrome: info overlay + scrubber right above the tab bar (iOS safeAreaInset bottom).
        val overlayAlpha by animateFloatAsState(if (isUIVisible) 1f else 0f, tween(200), label = "overlay")
        if (activeItem != null && overlayAlpha > 0.01f) {
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().alpha(overlayAlpha)) {
                FeedsInfoOverlay(
                    item = activeItem,
                    mode = mode,
                    isMuted = pool.muted,
                    isPlaying = isPlaying,
                    onPerformerFilter = { p -> model.filterByPerformer(IdName(p.id, p.name)) },
                    // iOS: Clips (and Pics) are image feeds — open the performer on Images.
                    onPerformerOpen = { p ->
                        val images = mode == ReelsModeType.Clips || mode == ReelsModeType.Pics
                        Nav.push(PerformerDetailScreen(p.id, Performer(id = p.id, name = p.name), initialTab = if (images) de.letzgo.stashy.ui.detail.DetailTab.Images else null))
                    },
                    onTitle = {
                        activeItem.titleLinkScene?.let { s ->
                            // iOS parity: a whole playing scene hands its live position (file time)
                            // to the page; the saved resume point is up to ~10 s old or stale after
                            // a paused seek. Markers keep their own start, previews/clips are skipped.
                            var scene = s
                            var continues = false
                            if (activeItem is FeedItem.SceneItem && activeItem.segment == null) {
                                val position = (pool.player(activeItem.id)?.currentPosition ?: 0L) / 1000.0
                                if (position.isFinite() && position > 1.0) { scene = s.copy(resumeTime = position); continues = true }
                            }
                            // With a live position the page continues playback instead of showing the cover.
                            Nav.push(SceneDetailScreen(scene.id, scene, autoPlay = continues))
                        }
                    },
                    onTag = { t -> model.toggleTag(t) },
                    onAddTags = { onAddTags(activeItem.aiTagTarget) },
                    onRemoveTag = { t -> model.removeTag(t.id, activeItem.aiTagTarget) },
                    onOCounter = { m -> model.changeOCounter(activeItem, m) },
                    onRating = { r -> model.setRating(activeItem, r) },
                    onToggleMute = {
                        val new = !pool.muted
                        model.isMuted = new
                        PlayerMute.remember(new)
                    },
                    onTogglePlay = { model.isPlaying = !model.isPlaying },
                    pausesAdvance = activeItem.isAnimated && continuous,
                    // Edit Mode gate like the tag row's "Add tag" (iOS parity).
                    onAddPerformers = if (de.letzgo.stashy.ui.Appearance.isEditModeEnabled && activeItem.canAddPerformers) ({ onAddPerformers(activeItem) }) else null,
                    // Settings › Feeds › "Show Add Marker Button": whole scenes in Scenes only.
                    onAddMarker = if (FeedsConfig.showsAddMarkerButton && mode == ReelsModeType.Scenes && activeItem is FeedItem.SceneItem && activeItem.segment == null) ({
                        val position = (pool.player(activeItem.id)?.currentPosition ?: 0L) / 1000.0
                        resumesAfterMarkerSheet = model.isPlaying
                        model.isPlaying = false
                        markerDraft = FeedsMarkerDraft(activeItem.scene, if (position.isFinite()) maxOf(0.0, position) else maxOf(0.0, time))
                    }) else null,
                )
                if (!activeItem.isAnimated) {
                    // iOS `ReelsView` scrub preview: the scene's sprite sheet + VTT index, like the
                    // scene player. Scenes scrub in scene time; Markers' bar spans the segment
                    // (the player is clipped to it), so the still is read at the matching scene
                    // time. Previews (a generated clip) and scenes without sprites keep the poster.
                    val segment = activeItem.segment
                    val sprites = remember(activeItem.id) { feedScrubSprites(activeItem) }
                    // Fetched as soon as the row is active, so the first scrub already has stills.
                    LaunchedEffect(sprites) { sprites?.prepare() }
                    val previewAt = remember(sprites, segment) {
                        sprites?.let { sp -> { s: Double -> sp.prepare(); sp.thumbnail(segment?.sceneTime(s) ?: s) } }
                    }
                    FeedsScrubber(
                        time = time, duration = duration, placeholderURL = activeItem.posterURL,
                        previewImageAt = previewAt,
                        // iOS: play / pause sits at the bar's trailing end, not in the control stack.
                        playPause = de.letzgo.stashy.ui.player.TimeBarPlayPause(isPlaying) { model.isPlaying = !model.isPlaying },
                        aspectRatio = pool.videoSizes[activeItem.id]?.let { if (it.width > 0 && it.height > 0) it.width.toFloat() / it.height else null } ?: fileAspect(activeItem),
                        // Dots: Feeds › Scenes, whole scenes only (the setting does not matter).
                        markers = if (mode == ReelsModeType.Scenes && activeItem is FeedItem.SceneItem && activeItem.segment == null)
                            FeedsMarkerTimes.seconds(activeItem.scene).map { de.letzgo.stashy.ui.player.TimeBarMarker(it, null) } else emptyList(),
                        onScrub = { s -> seeking = true; time = s; pool.player(activeId)?.playWhenReady = false; pool.seek(activeId, s) },
                        onScrubEnd = { s ->
                            time = s; pool.seek(activeId, s); seeking = false
                            pool.setPlaying(activeId, playingNow)
                        },
                    )
                }
                Spacer(Modifier.height(tabBarOverlap))
            }
        }
    }

    // The scene page's sheet, opened by the overlay's "Add Marker" at the feed player's position.
    markerDraft?.let { draft ->
        de.letzgo.stashy.ui.scene.AddMarkerSheet(
            draft.scene, draft.seconds, null,
            onDismiss = {
                markerDraft = null
                if (resumesAfterMarkerSheet) model.isPlaying = true
                resumesAfterMarkerSheet = false
            },
            // Runs after creation (and again once Stash generated the previews): idempotent.
            onComplete = { FeedsMarkerTimes.add(draft.scene.id, draft.seconds) },
        )
    }
}

/** Feeds › Scenes "Add Marker": what the sheet is opened for. */
private data class FeedsMarkerDraft(val scene: Scene, val seconds: Double)

/**
 * iOS: `FeedsMarkerTimes` — markers created from Feeds, on top of the feed query's
 * `feed_marker_seconds` (kept apart from the scene's real `sceneMarkers`, which the feed never fetches in full).
 */
internal object FeedsMarkerTimes {
    private val added = androidx.compose.runtime.mutableStateMapOf<String, List<Double>>()

    fun add(sceneId: String, seconds: Double) {
        val current = added[sceneId].orEmpty()
        if (current.none { kotlin.math.abs(it - seconds) < 0.001 }) added[sceneId] = current + seconds
    }

    /** All marker times of [scene], sorted: the feed query's plus the ones added here. */
    fun seconds(scene: Scene): List<Double> {
        val base = scene.feedMarkerSeconds?.map { it.seconds } ?: scene.sceneMarkers.orEmpty().map { it.seconds }
        return (base + added[scene.id].orEmpty()).distinct().sorted()
    }
}

/** Sprite sheet of the scene a row scrubs through (Scenes, Markers); null for clips / previews. */
private fun feedScrubSprites(item: FeedItem): de.letzgo.stashy.ui.player.SceneScrubSprites? {
    val paths = when (item) {
        is FeedItem.SceneItem -> item.scene.paths
        is FeedItem.MarkerItem -> item.marker.scene?.paths
        else -> null
    } ?: return null
    return de.letzgo.stashy.ui.player.SceneScrubSprites.create(paths.vtt, paths.sprite)
}

private fun emptyIcon(mode: ReelsModeType) = when (mode) {
    ReelsModeType.Scenes, ReelsModeType.Verticals -> SF.film
    ReelsModeType.Markers -> SF.bookmarkFill
    ReelsModeType.Clips -> SF.photoOnRectangleAngled
    ReelsModeType.Previews -> SF.playRectangle
    ReelsModeType.Pics -> SF.cameraFill
}

private fun emptyTitle(mode: ReelsModeType) = when (mode) {
    ReelsModeType.Scenes, ReelsModeType.Verticals -> "No scenes found"
    ReelsModeType.Markers -> "No markers found"
    ReelsModeType.Clips -> "No clips found"
    ReelsModeType.Previews -> "No previews found"
    ReelsModeType.Pics -> "No images found"
}
