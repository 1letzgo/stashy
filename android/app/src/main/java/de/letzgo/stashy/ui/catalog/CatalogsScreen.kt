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
val CatalogChromeHeight: Dp = 72.dp

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
        // iOS `showTabSwitcher`: only with more than one catalog.
        if (tabs.size > 1) TopNavStrip(tabs)
    }
}

@Composable
private fun TopNavStrip(tabs: List<CatalogTab>) {
    val state = rememberLazyListState()
    LaunchedEffect(Nav.catalogTab) { state.animateScrollToItem(tabs.indexOf(Nav.catalogTab).coerceAtLeast(0)) }
    Box(
        Modifier.fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent)))
            .padding(WindowInsets.statusBars.asPaddingValues())
            .padding(vertical = 10.dp),
    ) {
        LazyRow(
            state = state,
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(tabs) { tab ->
                ChromeChip(tab.icon, tab.title, Nav.catalogTab == tab, onClick = { Nav.catalogTab = tab })
            }
        }
    }
}
