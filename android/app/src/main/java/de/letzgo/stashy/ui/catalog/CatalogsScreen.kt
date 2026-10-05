package de.letzgo.stashy.ui.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.ChromeChip
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.home.DashboardScreen

/** Space the top chrome strip covers; catalog content adds it as top padding. */
val CatalogChromeHeight: Dp = 49.dp

/** Top padding for content under the floating chrome strip (status bar + strip + gap). */
@Composable
fun catalogTopPadding(): Dp = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + CatalogChromeHeight + 8.dp

/**
 * iOS: `CatalogsView.sortedVisibleTabs` — dashboard + the visible catalogs in the user's order
 * (Settings › Dashboard › Home Tabs); a deep link may target a hidden catalog, which is then
 * appended so its chip shows.
 */
private fun sortedVisibleTabs(current: CatalogTab): List<CatalogTab> {
    val tabs = TabManager.visibleCatalogTabs.mapNotNull { CatalogTab.from(it) }.toMutableList()
    if (current !in tabs) tabs.add(current)
    return tabs
}

/**
 * iOS: `CatalogsView` — Home tab. Floating chip strip on top (`StashyTopNavStrip`): the
 * selected catalog as glass capsule with label, the others as glass circles.
 */
@Composable
fun CatalogsScreen() {
    val p = Theme.palette
    Box(Modifier.fillMaxSize().background(p.background)) {
        when (Nav.catalogTab) {
            CatalogTab.Dashboard -> DashboardScreen()
            CatalogTab.Scenes -> ScenesCatalog()
            CatalogTab.Images -> ImagesCatalog()
            CatalogTab.Galleries -> GalleriesCatalog()
            CatalogTab.Performers -> PerformersCatalog()
            CatalogTab.Studios -> StudiosCatalog()
            CatalogTab.Tags -> TagsCatalog()
            CatalogTab.Groups -> GroupsCatalog()
            CatalogTab.Markers -> MarkersCatalog()
        }
        val tabs = sortedVisibleTabs(Nav.catalogTab)
        // iOS `showTabSwitcher`: only with more than one catalog — on Android the strip also
        // carries the catalog's top actions (columns, quick menu), so it stays for those.
        if (tabs.size > 1 || CatalogTopActions.hasActions) TopNavStrip(tabs)
    }
}

/**
 * Catalog switcher (iOS: `StashyTopNavStrip`) as native Material tabs; the trailing slot holds
 * the visible catalog's top actions ([CatalogTopActions], see [CatalogTopActionIcons]).
 */
@Composable
private fun TopNavStrip(tabs: List<CatalogTab>) {
    val actions = CatalogTopActions.slots
    de.letzgo.stashy.ui.NativeTabStrip(
        tabs, Nav.catalogTab, { it.title }, { Nav.catalogTab = it },
        trailing = if (actions != null && CatalogTopActions.hasActions) ({ androidx.compose.foundation.layout.Row { CatalogTopActionIcons(actions) } }) else null,
    )
}
