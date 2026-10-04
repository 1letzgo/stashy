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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
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
import de.letzgo.stashy.ui.catalog.CatalogsScreen
import de.letzgo.stashy.ui.feeds.FeedsScreen
import de.letzgo.stashy.ui.search.SearchScreen
import de.letzgo.stashy.ui.settings.SettingsScreen
import de.letzgo.stashy.ui.setup.ServerSetupScreen
import de.letzgo.stashy.ui.tools.ToolsTabScreen

/** Height the floating tab bar occupies; screens add it as bottom content padding. */
val TabBarClearance: Dp = 96.dp

/** True while the floating tab bar is shown, so lists can pad for it. */
val LocalTabBarVisible = compositionLocalOf { true }

/**
 * iOS: `MainTabView` — four tabs in a floating glass bar plus a separate search circle
 * (iOS 26 tab bar with a search role). Each tab has its own back stack ([Nav]).
 */
@Composable
fun AppShell() {
    val p = Theme.palette
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

    Box(Modifier.fillMaxSize().background(p.background)) {
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
            FloatingTabBar()
        }
    }
    AppUpdateDialog()
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

private data class TabItem(val tab: MainTab, val title: String, val icon: ImageVector)

@Composable
private fun FloatingTabBar() {
    val items = listOf(
        TabItem(MainTab.Home, "Home", SF.squareGrid2x2Fill),
        TabItem(MainTab.Feeds, "Feeds", SF.playRectangleOnRectangle),
        ToolsTab.item(),
        TabItem(MainTab.Settings, "Settings", SF.gear),
    )
    Row(
        Modifier.navigationBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.weight(1f).height(64.dp).floatingShadow(RoundedCornerShape(50)).stashyGlass(RoundedCornerShape(50)).padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEach { item ->
                val selected = Nav.tab == item.tab
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .let { if (selected) it.background(Color.White.copy(alpha = 0.16f), RoundedCornerShape(50)) else it }
                        .clickable { Nav.select(item.tab) },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    val color = if (selected) Color.White else Color.White.copy(alpha = 0.85f)
                    Icon(item.icon, item.title, tint = color, modifier = Modifier.size(26.dp))
                    Text(item.title, style = IosTypography.caption2, color = color)
                }
            }
        }
        val searchSelected = Nav.tab == MainTab.Search
        GlassIconButton(
            SF.magnifyingglass, "Search", size = 64.dp,
            tint = if (searchSelected) Color.White.copy(alpha = 0.22f) else null,
        ) { Nav.select(MainTab.Search) }
    }
}

/** The Tools slot shows "stashy+" while locked (iOS `TabManager.visibleTabs`). */
private object ToolsTab {
    fun item(): TabItem =
        if (de.letzgo.stashy.data.StashyPlus.isUnlocked) TabItem(MainTab.Tools, "Tools", SF.cubeBox)
        else TabItem(MainTab.Tools, "stashy+", SF.sparkles)
}
