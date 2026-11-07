package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import de.letzgo.stashy.data.CoAppearanceCounts
import de.letzgo.stashy.data.CoPerformerLogic
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/**
 * What two performers share (performer detail "Appears with" → co-performer card), iOS
 * `SharedAppearancesView`: a [DetailHeroCard] like the other details — band blurred from the first
 * performer's portrait, both portraits side by side on the band edge (each opens that performer),
 * title "A & B" and the shared counts — then Scenes · Galleries · Images in the section dropdown,
 * each with its filter & sort sheet. `performers INCLUDES_ALL [a, b]` is the fixed scope
 * ([CoPerformerLogic.sharedScenesScope]), so nothing in a sheet can widen a list.
 * [performer] / [other] are list items shown until the full performers have loaded.
 */
class SharedAppearancesScreen(
    val performerId: String,
    val performerName: String,
    val otherId: String,
    val otherName: String,
    performer: Performer? = null,
    other: Performer? = null,
    /** Counts known from "Appears with"; null shows the lists' totals. */
    private val shared: CoAppearanceCounts? = null,
) : Screen {
    override val key = "shared-$performerId-$otherId"

    private val scope = screenScope()
    private var started = false
    private val gridState = LazyGridState()
    private val title = "$performerName & $otherName"
    private var first by mutableStateOf(performer)
    private var second by mutableStateOf(other)

    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes, DetailTab.Galleries, DetailTab.Images),
        sceneScope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
        galleryScope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
        imageScope = CoPerformerLogic.sharedScenesScope(performerId, otherId),
        previewScenes = shared?.scenes ?: 0,
        previewGalleries = shared?.galleries ?: 0,
        previewImages = shared?.images ?: 0,
    )

    private var tab by mutableStateOf(
        when {
            shared == null || shared.scenes > 0 -> DetailTab.Scenes
            shared.galleries > 0 -> DetailTab.Galleries
            else -> DetailTab.Images
        },
    )

    private fun load() {
        catalog.loadAll(force = true)
        // Portraits (image paths) of both performers.
        scope.launch { runCatching { DetailRepository.performer(performerId) }.getOrNull()?.let { first = it } }
        scope.launch { runCatching { DetailRepository.performer(otherId) }.getOrNull()?.let { second = it } }
    }

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; load() } }
        AutoSwitchTab(catalog, tab) { tab = it }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(tab, w, catalog.imageColumns) }, hasTabs = catalog.available.size > 1, header = { Header() }) {
                linkedSection(catalog, tab, gridState)
            }
            DetailTopBar(title, catalog.available, tab, { tab = it }, settings = catalog.settingsSlot(tab))
        }
        LinkedSettingsSheets(catalog)
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
        // The sheets may narrow the lists; the header keeps the counts from "Appears with".
        val counts = shared ?: CoAppearanceCounts(
            scenes = catalog.list(DetailTab.Scenes)?.totalCount ?: 0,
            galleries = catalog.list(DetailTab.Galleries)?.totalCount ?: 0,
        )
        val items = buildList {
            if (counts.scenes > 0) add(DetailItem("Shared scenes", counts.scenes.toString()))
            if (counts.galleries > 0) add(DetailItem("Shared galleries", counts.galleries.toString()))
            if (counts.images > 0) add(DetailItem("Shared images", counts.images.toString()))
        }
        DetailHeroCard(
            title = title,
            items = items,
            description = null,
            expanded = false,
            onToggle = {},
            hero = avatar(performerId, performerName, first),
            secondHero = avatar(otherId, otherName, second),
        )
    }
}
