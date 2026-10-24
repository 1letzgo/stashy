package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.CoPerformerLogic
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.filterSortSlot
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import kotlinx.coroutines.launch

/**
 * Scenes two performers share (performer detail "Appears with" → co-performer card): a
 * [DetailHeroCard] like the other details — band blurred from the first performer's portrait,
 * both portraits side by side on the band edge (each opens that performer), title "A & B" and
 * the shared scene count — then the scenes catalog list with the filter & sort sheet in the top
 * bar (Scenes tab session sort). `performers INCLUDES_ALL [a, b]` is the fixed scope
 * ([CoPerformerLogic.sharedScenesScope]), so nothing in the sheet can widen the list.
 * [performer] / [other] are list items shown until the full performers have loaded.
 */
class SharedScenesScreen(
    val performerId: String,
    val performerName: String,
    val otherId: String,
    val otherName: String,
    performer: Performer? = null,
    other: Performer? = null,
    /** Shared scene count known from "Appears with"; else the unfiltered list's total. */
    private val sharedScenes: Int? = null,
) : Screen {
    override val key = "shared-scenes-$performerId-$otherId"

    private val scope = screenScope()
    private var started = false
    private val gridState = LazyGridState()
    private val title = "$performerName & $otherName"
    private var first by mutableStateOf(performer)
    private var second by mutableStateOf(other)

    private val scenes = CatalogController<Scene>(
        FilterMode.Scenes, scope,
        tabId = null,
        scope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
        initialSort = CatalogPrefs.resolvedSort(FilterMode.Scenes),
        persistSort = { CatalogPrefs.setSortOption(CatalogPrefs.tabId(FilterMode.Scenes), it.raw) },
    )

    private fun load() {
        scenes.onAppear()
        // Portraits (image paths) of both performers.
        scope.launch { runCatching { DetailRepository.performer(performerId) }.getOrNull()?.let { first = it } }
        scope.launch { runCatching { DetailRepository.performer(otherId) }.getOrNull()?.let { second = it } }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
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

    /** Circle of one performer: the portrait (top-biased crop), tap → that performer's detail. */
    private fun avatar(id: String, name: String, p: Performer?): DetailHero {
        val url = performerThumbnailURL(id, p?.imagePath)
        return DetailHero(
            DetailHero.Style.Cover, url, Color.Black, "Open $name",
            { Nav.push(PerformerDetailScreen(id, p)) },
            backdropAlignment = HeroPortraitBias,
        ) {
            if (url != null) HeroPicture(url, name, ContentScale.Crop, SF.personFill, alignment = HeroPortraitBias)
            else HeroPlaceholder(SF.personFill)
        }
    }

    @Composable
    private fun Header() {
        val list = scenes.list
        // The sheet may narrow the list; the header keeps the real shared count.
        val count = sharedScenes ?: list.totalCount.takeIf { list.loadedOnce && !scenes.isFilterActive }
        DetailHeroCard(
            title = title,
            items = listOf(DetailItem("Shared scenes", count?.toString() ?: "—")),
            description = null,
            expanded = false,
            onToggle = {},
            hero = avatar(performerId, performerName, first),
            secondHero = avatar(otherId, otherName, second),
        )
    }
}
