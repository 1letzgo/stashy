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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: `DirectorDetailView` — Stash has no director entity (`director` is free text on the
 * scene), so this is the scenes catalog list (iOS `ScenesView(filter: .scenesByDirector, scope:
 * .catalog)`) under a hero modeled on the performer header (megaphone strip, name, SCENES).
 * The top bar's "Settings" opens the scenes filter & sort sheet (sort, saved filters, presets,
 * criteria editor); the sort is the Scenes catalog session sort like iOS. The `director EQUALS`
 * criterion is layered last as a fixed scope, so nothing in the sheet can widen the list, and
 * the Settings default filter never applies here (iOS `hasInjectedFilter`).
 */
class DirectorDetailScreen(val director: String) : Screen {
    override val key = "director-$director"

    private val scope = screenScope()
    private var started = false
    private val gridState = LazyGridState()

    /** iOS `SavedFilter.scenesByDirector`. */
    private val scenes = CatalogController<Scene>(
        FilterMode.Scenes, scope,
        tabId = null,
        scope = directorScope(director),
        initialSort = CatalogPrefs.resolvedSort(FilterMode.Scenes),
        // iOS `persistSceneSort` with `scope == .catalog`: the Scenes tab session sort.
        persistSort = { CatalogPrefs.setSortOption(CatalogPrefs.tabId(FilterMode.Scenes), it.raw) },
    )

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; scenes.onAppear() } }
        Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
            PullToRefreshBox(isRefreshing = false, onRefresh = { scenes.refresh() }, modifier = Modifier.fillMaxSize()) {
                DetailGrid(gridState, { w -> columnsFor(DetailTab.Scenes, w, 1) }, header = { Header() }) {
                    pagedSection(scenes.list, { it.id }, "Loading scenes...", SF.film, "No scenes found") { _, s ->
                        SceneCard(s, onClick = { Nav.push(SceneDetailScreen(s.id, s)) })
                    }
                }
            }
            DetailTopBar(director, emptyList(), null, {}, settings = filterSortSlot(scenes))
        }
        CatalogFilterSortSheet(scenes)
    }

    /** iOS `heroHeader`. */
    @Composable
    private fun Header() {
        DetailHeaderCard(
            title = director, imageUrl = null, placeholderIcon = SF.megaphoneFill,
            items = listOf(DetailItem("Scenes", "${scenes.list.totalCount}")),
            expandable = false, expanded = false, onToggle = {}, titleMaxLines = 2,
            imageContent = {
                Box(Modifier.fillMaxSize().background(Appearance.tint.copy(alpha = 0.12f)), Alignment.Center) {
                    Icon(SF.megaphoneFill, null, tint = Appearance.tint, modifier = Modifier.size(28.dp))
                }
            },
        )
    }

    companion object {
        /**
         * Stash keeps `director` as one free-text field, so a scene with two directors reads
         * "Director A, Director B". The UI shows one entry per name (iOS `SceneDirectors.names`).
         */
        fun directorNames(raw: String?): List<String> =
            raw.orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }.distinct()

        /** Matches [name] as one entry of the comma-separated field (RE2, as Stash uses Go regexp). */
        internal fun directorRegex(name: String): String {
            val escaped = buildString { name.forEach { if (it in "\\.+*?()|[]{}^$") append('\\'); append(it) } }
            return "(^|,)\\s*$escaped\\s*(,|$)"
        }

        /** `director: { value: <regex>, modifier: MATCHES_REGEX }` (Stash `StringCriterionInput`). */
        internal fun directorScope(director: String): JsonObject = buildJsonObject {
            put("director", buildJsonObject { put("value", JsonPrimitive(directorRegex(director))); put("modifier", JsonPrimitive("MATCHES_REGEX")) })
        }
    }
}
