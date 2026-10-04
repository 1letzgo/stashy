package de.letzgo.stashy.ui.catalog

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import de.letzgo.stashy.data.CatalogCardColumns
import de.letzgo.stashy.data.CatalogPrefs
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import kotlinx.coroutines.CoroutineScope
import kotlinx.serialization.json.JsonObject

/**
 * iOS: `ScenesView` (catalog tab) — fixed one card per row (16:9), filter & sort as the only
 * slot, Settings default sort/filter, saved filters and on-device presets in the sheet.
 */
@Composable
fun ScenesCatalog() {
    val controller = rememberCatalogController<Scene>(FilterMode.Scenes)
    ScenesList(controller)
}

/**
 * Scene grid + chrome + sheet for any scope (catalog or a detail screen — iOS `ScenesListScope`).
 * Detail screens create their controller with [detailCatalogController].
 */
@Composable
fun ScenesList(controller: CatalogController<Scene>, topPadding: androidx.compose.ui.unit.Dp = catalogTopPadding(), showsFloatingBar: Boolean = true) {
    CatalogScaffold(
        controller,
        CatalogTexts("Loading scenes...", SF.film, "No scenes found", "Load Scenes"),
        CatalogSlots(filterSort = filterSortSlot(controller)),
        columns = { CatalogCardColumns.One.columnCount(it) },
        itemKey = { it.id },
        topPadding = topPadding,
        showsFloatingBar = showsFloatingBar,
    ) { _, scene ->
        SceneCard(scene, Modifier.noRippleClickable { Nav.push(SceneDetailScreen(scene.id, scene)) }, aspectRatio = CatalogCardColumns.One.cardAspectRatio)
    }
    CatalogFilterSortSheet(controller)
}

/**
 * iOS: `DetailViewContext` + `TabManager.resolvedDetailSceneSortFallback` — a list scoped to one
 * entity (e.g. `performers INCLUDES [id]`) whose sort persists per detail context
 * (`performer_detail`, `studio_detail`, `tag_detail`, `gallery_detail`, `group_detail`).
 */
fun <T> detailCatalogController(
    mode: FilterMode,
    scope: CoroutineScope,
    scopeFilter: JsonObject,
    detailContext: String,
): CatalogController<T> {
    val initial = SortCatalog.option(mode, CatalogPrefs.detailSortOption(detailContext)) ?: CatalogPrefs.resolvedSort(mode)
    return CatalogController(
        mode, scope, tabId = null, scope = scopeFilter, initialSort = initial,
        persistSort = { CatalogPrefs.setDetailSortOption(detailContext, it.raw) },
    )
}
