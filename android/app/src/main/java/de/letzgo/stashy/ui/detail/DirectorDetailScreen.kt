package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: `DirectorDetailView` — Stash has no director entity, so this lists the scenes whose
 * free-text `director` EQUALS the name, under a hero modeled on the performer header.
 */
class DirectorDetailScreen(val director: String) : Screen {
    override val key = "director-$director"

    private val scope = screenScope()
    private var started = false
    private val gridState = LazyGridState()

    /** iOS `SavedFilter.scenesByDirector`. */
    private val catalog = LinkedCatalog(
        scope,
        order = listOf(DetailTab.Scenes),
        sceneScope = buildJsonObject {
            put("director", buildJsonObject { put("value", JsonPrimitive(director)); put("modifier", JsonPrimitive("EQUALS")) })
        },
    )

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; catalog.loadAll(force = true) } }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            DetailGrid(gridState, { w -> columnsFor(DetailTab.Scenes, w, 1) }, header = {
                DetailHeaderCard(
                    title = director, imageUrl = null, placeholderIcon = SF.megaphoneFill,
                    items = listOf(DetailItem("Scenes", "${catalog.scenes?.totalCount ?: 0}")),
                    expandable = false, expanded = false, onToggle = {}, titleMaxLines = 2,
                    imageContent = {
                        Box(Modifier.fillMaxSize().background(Appearance.tint.copy(alpha = 0.12f)), Alignment.Center) {
                            Icon(SF.megaphoneFill, null, tint = Appearance.tint, modifier = Modifier.size(28.dp))
                        }
                    },
                )
            }) {
                linkedSection(catalog, DetailTab.Scenes)
            }
            DetailNavBar(emptyList(), null, {})
            val (slots, menu) = catalog.slots(DetailTab.Scenes)
            DetailSlotBar(slots, menu)
        }
    }
}
