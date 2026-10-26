package de.letzgo.stashy.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfigManager
import kotlinx.coroutines.launch
import de.letzgo.stashy.ui.catalog.CatalogsScreen
import de.letzgo.stashy.ui.feeds.FeedsScreen
import de.letzgo.stashy.ui.search.SearchScreen
import de.letzgo.stashy.ui.settings.SettingsScreen
import de.letzgo.stashy.ui.setup.ServerSetupScreen
import de.letzgo.stashy.ui.tools.ToolsTabScreen

/**
 * Real height of the bottom [NavigationBar] *without* the system navigation-bar inset, measured
 * in [AppShell]. Falls back to the Material 3 container height (80 dp) before the first layout.
 */
internal object TabBarMetrics {
    val fallbackContainerHeight: Dp = 80.dp
    var containerHeight by mutableStateOf(fallbackContainerHeight)
}

/**
 * Height the bottom tab bar covers at the bottom of the window: the bar itself plus the system
 * navigation bar / gesture inset it sits on. Content that scrolls under the bar pads by this.
 */
@Composable
fun tabBarHeight(): Dp {
    val nav = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    return maxOf(TabBarMetrics.containerHeight, TabBarMetrics.fallbackContainerHeight) + nav
}

/**
 * Bottom content padding for every scrolling root above the tab bar: [tabBarHeight] plus
 * [extra] breathing room, so the last card ends fully visible above the bar. The padding stays
 * while the bar auto-hides ([TabBarAutoHide]) — content is never covered, it just gains room.
 */
@Composable
fun bottomBarContentPadding(extra: Dp = BottomBarContentGap): Dp = tabBarHeight() + extra + miniPlayerInset()

/** Room for the mini player bar while it shows above the tab bar (not on Feeds, where it hides). */
@Composable
fun miniPlayerInset(): Dp =
    if (de.letzgo.stashy.ui.player.MiniPlayerStore.session != null && Nav.tab != MainTab.Feeds) MiniPlayerBarHeight + MiniPlayerBarGap else 0.dp

internal val MiniPlayerBarHeight: Dp = 56.dp
internal val MiniPlayerBarGap: Dp = 8.dp

/** Default gap between the last item of a list and the top edge of the tab bar. */
val BottomBarContentGap: Dp = 24.dp

/** True while the floating tab bar is shown, so lists can pad for it. */
val LocalTabBarVisible = compositionLocalOf { true }

/**
 * iOS: `MainTabView` — four tabs in a floating glass bar plus a separate search circle
 * (iOS 26 tab bar with a search role). Each tab has its own back stack ([Nav]).
 */
@Composable
fun AppShell() {
    val p = Theme.palette
    // iOS `ServerConfigChanged`: a switch (or removing the server) ends the mini player.
    val activeServerId = ServerConfigManager.activeConfig?.id
    LaunchedEffect(activeServerId) {
        // Watchlist first: the restored mini player session checks it for "Playing".
        val switched = de.letzgo.stashy.data.WatchlistStore.onServerChanged(activeServerId)
        // First appearance and server switch: restore that server's last mini player session (paused).
        de.letzgo.stashy.ui.player.MiniPlayerStore.onServerChanged(activeServerId)
        // iOS: forced server check on a switch — scenes deleted there leave every list.
        if (switched) de.letzgo.stashy.data.WatchlistStore.checkAgainstServer(force = true)
    }
    // iOS `didBecomeActive`: back in the foreground, scenes deleted on the server (web UI,
    // another device) leave the watchlist and "Playing" (throttled to once a minute).
    val lifecycle = androidx.compose.ui.platform.LocalLifecycleOwner.current.lifecycle
    androidx.compose.runtime.DisposableEffect(lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_START) de.letzgo.stashy.data.WatchlistStore.checkAgainstServer()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    if (ServerConfigManager.activeConfig == null) {
        Box(Modifier.fillMaxSize().background(p.background)) { ServerSetupScreen(onDone = {}) }
        AppUpdateDialog()
        return
    }
    val holder = rememberSaveableStateHolder()
    val stack = Nav.stack()
    val top = stack.lastOrNull()
    BackHandler(enabled = top != null) { Nav.pop() }
    // Android back at a tab root: tool → Tools landing, other tab → Home, catalog → Dashboard,
    // then leave the app (iOS has no back button there; this is the Android convention).
    val toolsSubTab = de.letzgo.stashy.ui.tools.ToolsNav.subTab
    val rootBack = top == null && (
        (Nav.tab == MainTab.Tools && toolsSubTab.isNotEmpty()) || Nav.tab != MainTab.Home || Nav.catalogTab != CatalogTab.Dashboard
    )
    BackHandler(enabled = rootBack) {
        when {
            Nav.tab == MainTab.Tools && toolsSubTab.isNotEmpty() -> de.letzgo.stashy.ui.tools.ToolsNav.subTab = ""
            Nav.tab != MainTab.Home -> Nav.tab = MainTab.Home
            else -> Nav.catalogTab = CatalogTab.Dashboard
        }
    }

    // Auto-hide (Settings › Appearance): the Feeds pager drives the bar itself (page changes,
    // chrome toggle — see FeedsTabBarPolicy), so scroll tracking is off there; Feeds › Pics is a
    // plain list and tracks like the others. Any tab, screen or Feeds mode change shows the bar.
    val autoHideSuspended = top == null && Nav.tab == MainTab.Feeds &&
        de.letzgo.stashy.ui.feeds.FeedsModel.mode != de.letzgo.stashy.data.ReelsModeType.Pics
    SideEffect { TabBarAutoHide.suspended = autoHideSuspended }
    LaunchedEffect(Nav.tab, top?.key, autoHideSuspended) { TabBarAutoHide.show() }
    val density = androidx.compose.ui.platform.LocalDensity.current
    SideEffect { TabBarAutoHide.thresholdPx = with(density) { 24.dp.toPx() } }
    val barHidden = TabBarAutoHide.enabled && TabBarAutoHide.hidden
    val barOffset by animateFloatAsState(if (barHidden) 1f else 0f, tween(TabBarAutoHide.ANIMATION_MS), label = "tabBarAutoHide")

    Box(Modifier.fillMaxSize().background(p.background).nestedScroll(TabBarAutoHide.connection)) {
        AnimatedContent(
            targetState = Nav.tab to top,
            transitionSpec = {
                if (initialState.first != targetState.first) fadeIn() togetherWith fadeOut()
                else if (targetState.second != null && (initialState.second == null || stack.contains(initialState.second)))
                    slideInHorizontally { it } togetherWith slideOutHorizontally { -it / 3 }
                else slideInHorizontally { -it / 3 } togetherWith slideOutHorizontally { it }
            },
            label = "nav",
        ) { (tab, screen) ->
            val key = screen?.key ?: "root-${tab.name}"
            holder.SaveableStateProvider(key) {
                Box(Modifier.fillMaxSize().background(p.background)) {
                    if (screen != null) screen.Content() else TabRoot(tab)
                }
            }
        }
        val showBar = top?.hidesTabBar != true && !(top == null && Nav.rootHidesTabBar)
        AnimatedVisibility(showBar, Modifier.align(Alignment.BottomCenter), enter = fadeIn(), exit = fadeOut()) {
            // Slides down by its own height (system inset included) when auto-hidden.
            FloatingTabBar(Modifier.graphicsLayer { translationY = barOffset * size.height })
        }
        MiniPlayerHost(showBar, barOffset, Modifier.align(Alignment.BottomCenter))
    }
    ShellAlerts()
    AppUpdateDialog()
}

/**
 * iOS: `MiniPlayerHost` — the mini player above the tab bar (follows its auto-hide), hidden on
 * Feeds (which also pauses it, iOS `stashyPauseBackgroundPlayers`) and under full-screen pages.
 * A tap opens the Now Playing view; its "Details" opens the scene page, which takes the player back.
 */
@Composable
private fun MiniPlayerHost(tabBarShown: Boolean, tabBarHideFraction: Float, modifier: Modifier = Modifier) {
    val onFeeds = Nav.tab == MainTab.Feeds
    LaunchedEffect(onFeeds) { if (onFeeds) de.letzgo.stashy.ui.player.MiniPlayerStore.pause() }
    // Settings › stashy+ › Miniplayer & Watchlist off (or stashy+ gone): the bar closes.
    val miniEnabled = de.letzgo.stashy.ui.player.MiniPlayerStore.isEnabled
    LaunchedEffect(miniEnabled) { if (!miniEnabled) de.letzgo.stashy.ui.player.MiniPlayerStore.close(forget = false) }
    val nav = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val barHeight = if (tabBarShown) maxOf(TabBarMetrics.containerHeight, TabBarMetrics.fallbackContainerHeight) * (1f - tabBarHideFraction) else 0.dp
    de.letzgo.stashy.ui.player.MiniPlayerBar(
        visible = tabBarShown && !onFeeds && miniEnabled,
        modifier = modifier.padding(start = 12.dp, end = 12.dp, bottom = nav + barHeight + MiniPlayerBarGap),
    )
    // The bar's own full view; "Details" closes it and opens the scene page, which takes the player.
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    de.letzgo.stashy.ui.player.NowPlayingSheet { screen ->
        // Details / performer / studio: close the sheet, then open the page.
        de.letzgo.stashy.ui.player.MiniPlayerStore.showsNowPlaying = false
        scope.launch {
            kotlinx.coroutines.delay(300)
            Nav.push(screen)
        }
    }
}

/** Which of the iOS `MainTabView` configuration alerts is showing. */
private enum class ShellAlert { IncompleteSetup, AuthExpired }

/**
 * iOS `MainTabView` alerts: "Incomplete Setup" when the active server config lacks details
 * (`checkConfiguration()` on appear) and "Authentication Required" on a 401 ("AuthError401").
 * Both open the active server's configuration in Settings.
 */
@Composable
private fun ShellAlerts() {
    val config = ServerConfigManager.activeConfig
    var incompleteFor by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf<String?>(null) }
    var incompleteDismissed by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(config?.id, config?.hasValidConfig) {
        incompleteFor = config?.takeIf { !it.hasValidConfig && incompleteDismissed != it.id }?.id
    }
    val authFor = de.letzgo.stashy.data.AuthEvents.pendingServerId
    val alert = when {
        incompleteFor != null && incompleteFor == config?.id -> ShellAlert.IncompleteSetup
        authFor != null && authFor == config?.id -> ShellAlert.AuthExpired
        else -> null
    } ?: return
    fun dismiss() {
        when (alert) {
            ShellAlert.IncompleteSetup -> { incompleteDismissed = incompleteFor; incompleteFor = null }
            ShellAlert.AuthExpired -> de.letzgo.stashy.data.AuthEvents.consume()
        }
    }
    fun openServerSettings() {
        dismiss()
        val id = ServerConfigManager.activeConfig?.id
        Nav.tab = MainTab.Settings
        Nav.popToRoot(MainTab.Settings)
        if (id != null) Nav.push(de.letzgo.stashy.ui.settings.ServerFormScreen(id))
    }
    when (alert) {
        ShellAlert.IncompleteSetup -> NativeConfirmDialog(
            "Incomplete Setup", "Your server configuration is missing some details.",
            onDismiss = ::dismiss, confirmLabel = "Check Settings", dismissLabel = null, onConfirm = ::openServerSettings,
        )
        ShellAlert.AuthExpired -> NativeConfirmDialog(
            "Authentication Required", "Your API key is invalid or expired. Please check your server configuration.",
            onDismiss = ::dismiss, confirmLabel = "Update API Key", dismissLabel = null, onConfirm = ::openServerSettings,
        )
    }
}

@Composable
private fun TabRoot(tab: MainTab) {
    when (tab) {
        MainTab.Home -> CatalogsScreen()
        MainTab.Feeds -> FeedsScreen()
        MainTab.Tools -> ToolsTabScreen()
        MainTab.Settings -> SettingsScreen()
        MainTab.Search -> SearchScreen()
    }
}

private data class TabItem(val tab: MainTab, val title: String, val icon: ImageVector, val selectedIcon: ImageVector = icon)

/**
 * Native Material 3 navigation bar (Android look). Same destinations as the iOS tab bar,
 * with Search as fifth destination instead of the separate search circle.
 */
@Composable
private fun FloatingTabBar(modifier: Modifier = Modifier) {
    val p = Theme.palette
    val items = listOf(
        // Material convention: outlined when inactive, filled when selected.
        TabItem(MainTab.Home, "Home", androidx.compose.material.icons.Icons.Outlined.Home, androidx.compose.material.icons.Icons.Filled.Home),
        TabItem(MainTab.Feeds, "Feeds", androidx.compose.material.icons.Icons.Outlined.VideoLibrary, androidx.compose.material.icons.Icons.Filled.VideoLibrary),
        ToolsTab.item(),
        TabItem(MainTab.Settings, "Settings", androidx.compose.material.icons.Icons.Outlined.Settings, androidx.compose.material.icons.Icons.Filled.Settings),
        TabItem(MainTab.Search, "Search", androidx.compose.material.icons.Icons.Outlined.Search, androidx.compose.material.icons.Icons.Filled.Search),
    )
    val density = androidx.compose.ui.platform.LocalDensity.current
    val navInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    NavigationBar(
        // Feeds [bottomBarContentPadding] with the bar's real height (without the system inset).
        modifier = modifier.onSizeChanged { size ->
            val container = with(density) { size.height.toDp() } - navInset
            if (container > 0.dp) TabBarMetrics.containerHeight = container
        },
        containerColor = chromeBarColor(p.secondaryBackground),
        contentColor = p.text,
        tonalElevation = 0.dp,
    ) {
        items.forEach { item ->
            val selected = Nav.tab == item.tab
            NavigationBarItem(
                selected = selected,
                onClick = { Nav.select(item.tab) },
                icon = { Icon(if (selected) item.selectedIcon else item.icon, contentDescription = item.title) },
                // Scales with the font size (sp); one line so a very large scale ellipsizes instead of wrapping mid-word.
                label = { Text(item.title, style = androidx.compose.material3.MaterialTheme.typography.labelMedium, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = p.text,
                    selectedTextColor = p.text,
                    indicatorColor = p.text.copy(alpha = 0.14f),
                    unselectedIconColor = p.secondaryText,
                    unselectedTextColor = p.secondaryText,
                ),
            )
        }
    }
}

/** The Tools slot shows "stashy+" while locked (iOS `TabManager.visibleTabs`). */
private object ToolsTab {
    fun item(): TabItem =
        if (de.letzgo.stashy.data.StashyPlus.isUnlocked) TabItem(MainTab.Tools, "Tools", androidx.compose.material.icons.Icons.Outlined.Inventory2, androidx.compose.material.icons.Icons.Filled.Inventory2)
        else TabItem(MainTab.Tools, "stashy+", androidx.compose.material.icons.Icons.Outlined.AutoAwesome, androidx.compose.material.icons.Icons.Filled.AutoAwesome)
}
