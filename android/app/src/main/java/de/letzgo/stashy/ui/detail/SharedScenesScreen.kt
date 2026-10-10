package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.CoPerformerLogic
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.filterSortSlot
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.scene.SceneDetailScreen

/**
 * Scenes two performers share (performer detail "Appears with" → co-performer card), laid out
 * like [DirectorDetailScreen]: scenes catalog list under a small hero titled "A & B", filter &
 * sort sheet in the top bar (Scenes tab session sort). `performers INCLUDES_ALL [a, b]` is the
 * fixed scope ([CoPerformerLogic.sharedScenesScope]), so nothing in the sheet can widen the list.
 */
class SharedScenesScreen(
    val performerId: String,
    val performerName: String,
    val otherId: String,
    val otherName: String,
) : Screen {
    override val key = "shared-scenes-$performerId-$otherId"

    private val scope = screenScope()
    private var started = false
    private val gridState = LazyGridState()
    private val title = "$performerName & $otherName"

    private val scenes = CatalogController<Scene>(
        FilterMode.Scenes, scope,
        tabId = null,
        scope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
        initialSort = CatalogPrefs.resolvedSort(FilterMode.Scenes),
        persistSort = { CatalogPrefs.setSortOption(CatalogPrefs.tabId(FilterMode.Scenes), it.raw) },
    )

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; scenes.onAppear() } }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            PullToRefreshBox(isRefreshing = false, onRefresh = { scenes.refresh() }, modifier = Modifier.fillMaxSize()) {
                DetailGrid(gridState, { w -> columnsFor(DetailTab.Scenes, w, 1) }, header = { Header() }) {
                    pagedSection(scenes.list, { it.id }, "Loading scenes...", SF.film, "No shared scenes") { _, s ->
                        SceneCard(s, onClick = { Nav.push(SceneDetailScreen(s.id, s)) })
                    }
                }
            }
            DetailTopBar(title, emptyList(), null, {}, settings = filterSortSlot(scenes))
        }
        CatalogFilterSortSheet(scenes)
    }

    @Composable
    private fun Header() {
        DetailHeaderCard(
            title = title, imageUrl = null, placeholderIcon = SF.person2,
            items = listOf(DetailItem("Scenes", "${scenes.list.totalCount}")),
            expandable = false, expanded = false, onToggle = {}, titleMaxLines = 2,
            imageContent = {
                Box(Modifier.fillMaxSize().background(Appearance.tint.copy(alpha = 0.12f)), Alignment.Center) {
                    Icon(SF.person2, null, tint = Appearance.tint, modifier = Modifier.size(28.dp))
                }
            },
        )
    }
}
