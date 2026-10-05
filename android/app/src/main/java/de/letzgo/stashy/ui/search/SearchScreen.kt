package de.letzgo.stashy.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.UniversalSearchRepository
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.components.ActionChip
import de.letzgo.stashy.ui.components.InfoLabel
import de.letzgo.stashy.ui.components.formatDuration
import de.letzgo.stashy.ui.home.DashboardSceneCard
import de.letzgo.stashy.ui.home.DetailLinks
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.noRippleClickable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

/** Per-category limits (iOS `UniversalSearchView`). */
private const val SCENES_LIMIT = 20
private const val IMAGES_LIMIT = 20
private const val PERFORMERS_LIMIT = 20
private const val GALLERIES_LIMIT = 20
private const val TAGS_LIMIT = 50
private const val STUDIOS_LIMIT = 50
private const val GROUPS_LIMIT = 20
private const val MARKERS_LIMIT = 20

private data class SearchResults(
    val performers: List<Performer> = emptyList(), val studios: List<Studio> = emptyList(), val tags: List<Tag> = emptyList(),
    val scenes: List<Scene> = emptyList(), val images: List<StashImage> = emptyList(), val galleries: List<Gallery> = emptyList(),
    val groups: List<StashGroup> = emptyList(), val markers: List<SceneMarker> = emptyList(),
) {
    val isEmpty get() = performers.isEmpty() && studios.isEmpty() && tags.isEmpty() && scenes.isEmpty() && images.isEmpty() && galleries.isEmpty() && groups.isEmpty() && markers.isEmpty()
}

/** Results survive tab switches like the iOS search tab's state. */
private object SearchState {
    var results by mutableStateOf(SearchResults())
    var resultsFor by mutableStateOf("")
}

/**
 * iOS: `UniversalSearchView` — one field searching all eight entity types in parallel (300 ms
 * debounce, min. 2 characters), sections in the user's catalogue order, "Show All" opens the
 * catalog with the query.
 */
@Composable
fun SearchScreen() {
    val p = Theme.palette
    var text by rememberSaveable { mutableStateOf("") }
    var searching by rememberSaveable { mutableStateOf(false) }
    val query = text.trim()
    val focus = LocalFocusManager.current

    LaunchedEffect(query) {
        if (query.length < 2) { SearchState.results = SearchResults(); SearchState.resultsFor = ""; searching = false; return@LaunchedEffect }
        if (query == SearchState.resultsFor) return@LaunchedEffect
        searching = true
        delay(300)
        val r = coroutineScope {
            fun <T> go(block: suspend () -> List<T>) = async { runCatching { block() }.getOrDefault(emptyList()) }
            val performers = go { UniversalSearchRepository.performers(query, PERFORMERS_LIMIT) }
            val studios = go { UniversalSearchRepository.studios(query, STUDIOS_LIMIT) }
            val tags = go { UniversalSearchRepository.tags(query, TAGS_LIMIT) }
            val scenes = go { UniversalSearchRepository.scenes(query, SCENES_LIMIT) }
            val images = go { UniversalSearchRepository.images(query, IMAGES_LIMIT) }
            val galleries = go { UniversalSearchRepository.galleries(query, GALLERIES_LIMIT) }
            val groups = go { UniversalSearchRepository.groups(query, GROUPS_LIMIT) }
            val markers = go { UniversalSearchRepository.markers(query, MARKERS_LIMIT) }
            SearchResults(performers.await(), studios.await(), tags.await(), scenes.await(), images.await(), galleries.await(), groups.await(), markers.await())
        }
        SearchState.results = r
        SearchState.resultsFor = query
        searching = false
    }

    Box(Modifier.fillMaxSize().background(p.background)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
            Text("Search", style = IosTypography.headline, color = p.text, modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 12.dp))
            // iOS `.searchable(prompt: "Search everything...")`
            de.letzgo.stashy.ui.NativeSearchField(
                text, { text = it }, "Search everything...",
                Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
                keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }),
            )
            when {
                ServerConfigManager.activeConfig == null -> Placeholder(SFS.serverRack, "Server not reachable", null) { Nav.select(MainTab.Settings) }
                query.isEmpty() -> Placeholder(SF.magnifyingglass, "Search Your Library", "Find scenes, images, performers, studios, tags, galleries, groups and markers")
                else -> Results(query, searching)
            }
        }
    }
}

@Composable
private fun Placeholder(icon: ImageVector, title: String, message: String?, onRetry: (() -> Unit)? = null) {
    val p = Theme.palette
    Column(Modifier.fillMaxSize().padding(bottom = TabBarClearance), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically)) {
        Icon(icon, null, tint = p.secondaryText.copy(alpha = 0.5f), modifier = Modifier.size(60.dp))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text)
            message?.let { Text(it, style = IosTypography.body, color = p.secondaryText, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 40.dp)) }
            onRetry?.let {
                Text("Retry Connection", style = IosTypography.headline, color = Color.White,
                    modifier = Modifier.background(Appearance.tint, RoundedCornerShape(Tokens.Radius.button)).clickable(onClick = it).padding(horizontal = 20.dp, vertical = 12.dp))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Results(query: String, searching: Boolean) {
    val p = Theme.palette
    val r = SearchState.results
    // iOS `orderedSections`: visible catalogue tabs in the user's order; Images follow Scenes.
    val order = setOf(AppTab.Scenes, AppTab.Performers, AppTab.Studios, AppTab.Tags, AppTab.Galleries, AppTab.Groups, AppTab.Markers)
    val sections = TabManager.tabs.filter { it.id in order && it.isVisible }.sortedBy { it.sortOrder }.map { it.id }.let { s ->
        if (AppTab.Scenes in s) s.flatMap { if (it == AppTab.Scenes) listOf(it, AppTab.Images) else listOf(it) } else s + AppTab.Images
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 16.dp, bottom = TabBarClearance + 16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        if (searching) {
            item { Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(22.dp), color = p.secondaryText, strokeWidth = 2.dp)
                Text("  Searching...", style = IosTypography.subheadline, color = p.secondaryText)
            } }
            return@LazyColumn
        }
        sections.forEach { section ->
            when (section) {
                AppTab.Performers -> if (r.performers.isNotEmpty()) item("performers") {
                    Section("Performers", r.performers.size, PERFORMERS_LIMIT, { Nav.openCatalog(CatalogTab.Performers, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.performers, key = { it.id }) { PerformerBubble(it) }
                        }
                    }
                }
                AppTab.Studios -> if (r.studios.isNotEmpty()) item("studios") {
                    Section("Studios", r.studios.size, STUDIOS_LIMIT, { Nav.openCatalog(CatalogTab.Studios, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.studios, key = { it.id }) { StudioTile(it) }
                        }
                    }
                }
                AppTab.Tags -> if (r.tags.isNotEmpty()) item("tags") {
                    Section("Tags", r.tags.size, TAGS_LIMIT, { Nav.openCatalog(CatalogTab.Tags, search = query) }) {
                        FlowRow(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            r.tags.forEach { t -> ActionChip("${t.name} (${t.sceneCount ?: 0})", { DetailLinks.tag(t) }, icon = SFS.tagFill) }
                        }
                    }
                }
                AppTab.Scenes -> if (r.scenes.isNotEmpty()) item("scenes") {
                    Section("Scenes", r.scenes.size, SCENES_LIMIT, { Nav.openCatalog(CatalogTab.Scenes, search = query, noDefaultFilter = true) }) {
                        LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.scenes, key = { it.id }) { DashboardSceneCard(it, false, 125.dp * 16 / 9, 125.dp, onClick = { DetailLinks.scene(it) }) }
                        }
                    }
                }
                AppTab.Images -> if (r.images.isNotEmpty()) item("images") {
                    Section("Images", r.images.size, IMAGES_LIMIT, { Nav.openCatalog(CatalogTab.Images, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.images, key = { it.id }) { img ->
                                PillTile(img.thumbnailURL, 140, 140, if (img.isVideo) SFS.playRectangle else SF.photo, img.title ?: "Image", SF.photo) { DetailLinks.image(r.images, img) }
                            }
                        }
                    }
                }
                AppTab.Galleries -> if (r.galleries.isNotEmpty()) item("galleries") {
                    Section("Galleries", r.galleries.size, GALLERIES_LIMIT, { Nav.openCatalog(CatalogTab.Galleries, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.galleries, key = { it.id }) { g -> PillTile(g.coverURL, 140, 100, SF.photoStack, g.displayTitle, SF.photoStack) { DetailLinks.gallery(g) } }
                        }
                    }
                }
                AppTab.Groups -> if (r.groups.isNotEmpty()) item("groups") {
                    Section("Groups", r.groups.size, GROUPS_LIMIT, { Nav.openCatalog(CatalogTab.Groups, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.groups, key = { it.id }) { g -> PillTile(g.frontImageURL, 100, 133, SF.rectangleStackFill, g.name, SF.rectangleStackFill) { DetailLinks.group(g) } }
                        }
                    }
                }
                AppTab.Markers -> if (r.markers.isNotEmpty()) item("markers") {
                    Section("Markers", r.markers.size, MARKERS_LIMIT, { Nav.openCatalog(CatalogTab.Markers, search = query) }) {
                        LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(r.markers.filter { it.scene != null }, key = { it.id }) { MarkerCard(it) }
                        }
                    }
                }
                else -> {}
            }
        }
        if (r.isEmpty && SearchState.resultsFor == query) item("none") {
            Column(Modifier.fillMaxWidth().padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(SFS.docMagnifyingglass, null, tint = p.secondaryText, modifier = Modifier.size(50.dp))
                Text("No results for \"$query\"", style = IosTypography.body, color = p.secondaryText)
            }
        }
    }
}

/** iOS `sectionHeader(title:count:limit:)` — "Title (n)" and "Show All ›" when the limit was hit. */
@Composable
private fun Section(title: String, count: Int, limit: Int, onShowAll: () -> Unit, content: @Composable () -> Unit) {
    val p = Theme.palette
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().noRippleClickable(onShowAll).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = IosTypography.headline, color = p.text)
            Text(" ($count)", style = IosTypography.subheadline, color = p.secondaryText)
            Spacer(Modifier.weight(1f))
            if (count >= limit) {
                Text("Show All", style = IosTypography.subheadline, color = Appearance.tint)
                Icon(SFS.chevronRight, null, tint = Appearance.tint, modifier = Modifier.padding(start = 4.dp).size(12.dp))
            }
        }
        content()
    }
}

/** iOS `InfoPill` — name label hanging off a tile: Material label on the surface, lifted by 2 dp. */
@Composable
private fun InfoPill(text: String, icon: ImageVector? = null, modifier: Modifier = Modifier) = InfoLabel(
    text, modifier, icon = icon, content = Theme.palette.text, iconTint = nativeAccent(),
    container = Theme.palette.secondaryBackground, elevation = 2.dp,
)

/** iOS `performerCard` — 80 pt circle on a tint ring, name pill overlapping the bottom. */
@Composable
private fun PerformerBubble(performer: Performer) {
    Box(Modifier.width(100.dp).noRippleClickable { DetailLinks.performer(performer) }, contentAlignment = Alignment.TopCenter) {
        Box(Modifier.size(88.dp).background(Appearance.tint, CircleShape).padding(4.dp).clip(CircleShape).background(Appearance.tint.copy(alpha = 0.4f)), contentAlignment = Alignment.Center) {
            Icon(SFS.personCircleFill, null, tint = Appearance.tint.copy(alpha = 0.4f), modifier = Modifier.size(80.dp))
            AsyncImage(performer.imageURL, null, Modifier.size(80.dp).clip(CircleShape), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
        }
        InfoPill(performer.name, modifier = Modifier.padding(top = 80.dp).widthIn(max = 100.dp))
    }
}

/** iOS `studioCard` — logo on a 120×90 tinted tile, name pill below. */
@Composable
private fun StudioTile(studio: Studio) {
    Box(Modifier.noRippleClickable { DetailLinks.studio(studio) }, contentAlignment = Alignment.TopCenter) {
        Box(Modifier.size(120.dp, 90.dp).clip(RoundedCornerShape(Tokens.Radius.card)).background(Appearance.tint).padding(8.dp), contentAlignment = Alignment.Center) {
            if (studio.hasImage) AsyncImage(studio.imageURL, studio.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            else Icon(SF.building2, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(32.dp))
        }
        InfoPill(studio.name, modifier = Modifier.padding(top = 82.dp).widthIn(max = 120.dp))
    }
}

/** iOS image / gallery / group cards — cover with an [InfoPill] hanging off the bottom edge. */
@Composable
private fun PillTile(url: String?, w: Int, h: Int, pillIcon: ImageVector, title: String, placeholder: ImageVector, onClick: () -> Unit) {
    Box(Modifier.noRippleClickable(onClick), contentAlignment = Alignment.BottomCenter) {
        Box(Modifier.size(w.dp, h.dp).clip(RoundedCornerShape(Tokens.Radius.card)).background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(placeholder, null, tint = Theme.palette.secondaryText)
            AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
        InfoPill(title, pillIcon, modifier = Modifier.offset(y = 8.dp).zIndex(1f).widthIn(max = w.dp))
    }
}

/** iOS `searchMarkerCard` — 160×90 thumb with timestamp, title and primary tag below. */
@Composable
private fun MarkerCard(marker: SceneMarker) {
    val p = Theme.palette
    Column(Modifier.width(160.dp).noRippleClickable { DetailLinks.marker(marker) }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(160.dp, 90.dp).clip(RoundedCornerShape(Tokens.Radius.card)).background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(SF.bookmarkFill, null, tint = p.secondaryText)
            AsyncImage(de.letzgo.stashy.data.Net.signed(marker.screenshot), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Text(formatDuration(marker.seconds) ?: "0:00", fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 2.dp))
        }
        Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(marker.title?.takeIf { it.isNotBlank() } ?: marker.scene?.title ?: "Unknown Marker", style = IosTypography.caption.copy(fontWeight = FontWeight.Bold), color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            marker.primaryTag?.name?.let {
                Text(it, fontSize = 9.sp, fontWeight = FontWeight.Medium, color = Appearance.tint,
                    modifier = Modifier.background(Appearance.tint.copy(alpha = 0.1f), RoundedCornerShape(4.dp)).padding(horizontal = 4.dp, vertical = 1.dp))
            }
        }
    }
}
