package de.letzgo.stashy.ui.catalog

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.FindFilter
import de.letzgo.stashy.data.ScenesRepository
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.components.SceneCard
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.scene.SceneDetailScreen

/** iOS: `ScenesView` (catalog root). Filters/sort/layout options come with the catalog port. */
@Composable
fun ScenesCatalog() {
    val scope = rememberCoroutineScope()
    val list = remember { PagedList(scope) { page, per -> ScenesRepository.find(FindFilter(page, per, sort = "created_at")) } }
    LaunchedEffect(Unit) { if (!list.loadedOnce) list.refresh() }
    SceneGrid(list)
}

@Composable
fun SceneGrid(list: PagedList<de.letzgo.stashy.data.Scene>, columns: Int = 1) {
    val p = Theme.palette
    when {
        list.items.isEmpty() && list.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = p.text) }
        list.items.isEmpty() && list.error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(SF.exclamationTriangle, "Could not load", list.error) }
        list.items.isEmpty() && list.loadedOnce -> Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(SF.film, "No Scenes") }
        else -> LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = catalogTopPadding(), bottom = TabBarClearance + 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            itemsIndexed(list.items, key = { _, s -> s.id }) { index, scene ->
                LaunchedEffect(index) { list.onItemShown(index) }
                SceneCard(scene, Modifier.noRippleClickable { Nav.push(SceneDetailScreen(scene.id, scene)) })
            }
            if (list.isLoading) item(span = { GridItemSpan(maxLineSpan) }) {
                Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator(color = p.text) }
            }
        }
    }
}
