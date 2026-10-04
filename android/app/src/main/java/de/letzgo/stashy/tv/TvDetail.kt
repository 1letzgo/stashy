package de.letzgo.stashy.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.applySceneEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/** Scenes of one entity scope (iOS `fetch<Entity>Scenes`: date desc, the scope always wins). */
class TvScopedScenes(scope: CoroutineScope, sceneScope: JsonObject) {
    val list = PagedList<Scene>(scope, CatalogRepository.pageSize(FilterMode.Scenes)) { page, perPage ->
        CatalogRepository.find(CatalogQuery(FilterMode.Scenes, SortCatalog.option(FilterMode.Scenes, "dateDesc")!!, scope = sceneScope), page, perPage)
    }
    init { scope.launch { SceneEvents.events.collect { list.applySceneEvent(it) } } }
}

/** Base of the detail routes: own coroutine scope and focus memory. */
abstract class TvDetailRoute : TvRoute {
    protected val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    override val focus = TvFocusMemory()
    override fun onRemoved() = scope.cancel()
}

/**
 * iOS: `TVGenericDetailView` — hero image (400 pt high) beside name, "Play as Channel"
 * (stashy+), details and the info grid; below, the entity's scenes in a width-adaptive grid.
 * Opening focus sits in the header so the page does not scroll down on open.
 */
@Composable
fun TvGenericDetail(
    name: String,
    details: String?,
    isLoading: Boolean,
    heroAspect: Float,
    placeholderIcon: ImageVector,
    heroURL: String?,
    channel: TvChannel?,
    scenes: PagedList<Scene>,
    memory: TvFocusMemory,
    heroOverride: (@Composable () -> Unit)? = null,
    infoGrid: @Composable () -> Unit,
) {
    LaunchedEffect(Unit) { if (!scenes.loadedOnce && !scenes.isLoading) scenes.refresh() }
    val headerFocus = remember { FocusRequester() }
    val emptyFocus = remember { FocusRequester() }
    val firstCard = remember { FocusRequester() }
    val showsChannel = channel != null && StashyPlus.isUnlocked
    val sceneSpec = TvGridSpec.scenes
    BoxWithConstraints(Modifier.fillMaxSize().background(TvColors.background)) {
        val horizontal = pt(60)
        val columns = sceneSpec.columnCount((maxWidth - horizontal * 2).value)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            state = rememberLazyGridState(),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = horizontal, end = horizontal, top = pt(40), bottom = pt(120)),
            horizontalArrangement = Arrangement.spacedBy(pt(40)),
            verticalArrangement = Arrangement.spacedBy(pt(40)),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "header") {
                Row(horizontalArrangement = Arrangement.spacedBy(pt(50))) {
                    Box(Modifier.width(pt(400 * heroAspect)).height(pt(400)).clip(RoundedCornerShape(pt(14)))) {
                        if (heroOverride != null) heroOverride() else TvImage(heroURL, Modifier.fillMaxSize(), placeholderIcon, iconSize = pt(56))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(pt(16))) {
                        Text(name, style = TvType.largeTitle, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        if (showsChannel) {
                            TvButton({ TvNav.push(TvChannelPlayerRoute(channel!!)) }, Modifier.focusRequester(headerFocus).tvFocusMemory(memory, "channel")) {
                                Icon(TvIcons.playTv, null, Modifier.size(pt(30)))
                                Text("Play as Channel", style = TvType.headline)
                            }
                        }
                        if (isLoading) TvSpinner(pt(48))
                        else {
                            details?.takeIf { it.isNotEmpty() }?.let { Text(it, style = TvType.body, color = TvColors.secondary, maxLines = 6, overflow = TextOverflow.Ellipsis) }
                            Box(Modifier.fillMaxWidth().height(1.dp).background(TvColors.secondary.copy(alpha = 0.4f)))
                            Column { infoGrid() }
                        }
                    }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }, key = "scenesHeading") {
                TvSectionHeading(TvIcons.film, "Scenes", scenes.totalCount.takeIf { it > 0 }, large = true)
            }
            val items = scenes.items
            when {
                items.isEmpty() && (scenes.isLoading || !scenes.loadedOnce) -> item(span = { GridItemSpan(maxLineSpan) }, key = "loading") { TvLoading() }
                items.isEmpty() -> item(span = { GridItemSpan(maxLineSpan) }, key = "empty") {
                    Column(Modifier.fillMaxWidth().padding(vertical = pt(60)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(16))) {
                        Icon(TvIcons.filmOutline, null, Modifier.size(pt(48)), tint = TvColors.secondary)
                        Text("No scenes found", style = TvType.title3, color = TvColors.secondary)
                        // Focus anchor of an empty page (Back must have a target).
                        TvButton({ TvNav.pop() }, Modifier.focusRequester(emptyFocus)) { Text("Back", style = TvType.title3) }
                    }
                }
                else -> itemsIndexed(items, key = { _, s -> s.id }) { index, scene ->
                    LaunchedEffect(index, items.size) { if (index >= items.size - columns * 2) scenes.loadMore() }
                    val first = if (index == 0) Modifier.focusRequester(firstCard) else Modifier
                    TvSceneTile(scene, { TvNav.push(TvSceneDetailRoute(scene.id, scene)) }, first.tvFocusMemory(memory, scene.id))
                }
            }
        }
    }
    // Opening focus: "Play as Channel", else the first scene, else Back on an empty page.
    val loaded = scenes.loadedOnce && !scenes.isLoading
    when {
        showsChannel -> TvInitialFocus(memory, headerFocus, name = "detail.channel")
        scenes.items.isNotEmpty() -> TvInitialFocus(memory, firstCard, name = "detail.firstScene")
        loaded -> TvInitialFocus(memory, emptyFocus, name = "detail.back")
    }
}

// MARK: - Performer

/** iOS: `TVPerformerDetailView`. */
class TvPerformerDetailRoute(private val id: String, private val name: String) : TvDetailRoute() {
    override val key = "performer.$id.${System.nanoTime()}"
    private var performer by mutableStateOf<Performer?>(null)
    private var loading by mutableStateOf(true)
    private val scenes = TvScopedScenes(scope, DetailRepository.scope("performers", id))

    init { scope.launch { performer = runCatching { DetailRepository.performer(id) }.getOrNull(); loading = false } }

    @Composable
    override fun Content() {
        val p = performer
        TvGenericDetail(
            p?.name ?: name, null, loading, 2f / 3f, TvIcons.person, p?.imageURL,
            TvChannel.performer(id, p?.name ?: name), scenes.list, focus,
        ) {
            if (p != null) {
                p.gender?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("Gender", it.lowercase().replace('_', ' ').replaceFirstChar { c -> c.uppercase() }) }
                p.country?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("Country", it) }
                p.ethnicity?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("Ethnicity", it.lowercase().replaceFirstChar { c -> c.uppercase() }) }
                p.birthdate?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("Birthdate", it) }
                TvInfoRow("Scenes", "${p.sceneCount ?: 0}")
                p.rating100?.let { r -> TvInfoRow("Rating") { RatingValue(r) } }
                if (p.favorite == true) TvInfoRow("Favorite") { Icon(TvIcons.heart, null, Modifier.size(pt(36)), tint = TvColors.red) }
            }
        }
    }
}

@Composable
private fun RatingValue(rating100: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(5))) {
        Icon(TvIcons.star, null, Modifier.size(pt(32)), tint = TvColors.star)
        Text(TvFormat.ratingValue(rating100), style = TvType.title3, color = Color.White)
    }
}

// MARK: - Studio

/** iOS: `TVStudioDetailView` — the hero is the studio logo, fitted. */
class TvStudioDetailRoute(private val id: String, private val name: String) : TvDetailRoute() {
    override val key = "studio.$id.${System.nanoTime()}"
    private var studio by mutableStateOf<Studio?>(null)
    private var loading by mutableStateOf(true)
    private val scenes = TvScopedScenes(scope, DetailRepository.scope("studios", id))

    init { scope.launch { studio = runCatching { DetailRepository.studio(id) }.getOrNull(); loading = false } }

    @Composable
    override fun Content() {
        val s = studio
        TvGenericDetail(
            s?.name ?: name, s?.details, loading, 16f / 9f, TvIcons.building, null,
            TvChannel.studio(id, s?.name ?: name), scenes.list, focus,
            heroOverride = {
                val logo = s?.imageURL?.takeIf { s.hasImage }
                    ?: de.letzgo.stashy.data.ServerConfigManager.activeConfig?.let { Net.signed("${it.baseURL}/studio/$id/image") }
                TvImage(logo, Modifier.fillMaxSize().background(TvColors.placeholder).padding(pt(24)), TvIcons.building, Color.Transparent, ContentScale.Fit, pt(48))
            },
        ) {
            if (s != null) {
                TvInfoRow("Scenes", "${s.sceneCount ?: 0}")
                s.performerCount?.takeIf { it > 0 }?.let { TvInfoRow("Performers", "$it") }
                s.galleryCount?.takeIf { it > 0 }?.let { TvInfoRow("Galleries", "$it") }
                s.rating100?.let { r -> TvInfoRow("Rating") { RatingValue(r) } }
                if (s.favorite == true) TvInfoRow("Favorite") { Icon(TvIcons.heart, null, Modifier.size(pt(36)), tint = TvColors.red) }
                s.url?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("URL") { Text(it, style = TvType.callout, color = TvColors.tint, maxLines = 1, overflow = TextOverflow.Ellipsis) } }
            }
        }
    }
}

// MARK: - Tag

/** iOS: `TVTagDetailView`. */
class TvTagDetailRoute(private val id: String, private val name: String) : TvDetailRoute() {
    override val key = "tag.$id.${System.nanoTime()}"
    private var tag by mutableStateOf<Tag?>(null)
    private var loading by mutableStateOf(true)
    private val scenes = TvScopedScenes(scope, DetailRepository.scope("tags", id))

    init { scope.launch { tag = runCatching { DetailRepository.tag(id) }.getOrNull(); loading = false } }

    @Composable
    override fun Content() {
        val t = tag
        TvGenericDetail(
            t?.name ?: name, t?.description, loading, 16f / 9f, TvIcons.tag, t?.imageURL?.takeIf { t.hasImage },
            TvChannel.tag(id, t?.name ?: name), scenes.list, focus,
        ) {
            if (scenes.list.totalCount > 0) TvInfoRow("Scenes", "${scenes.list.totalCount}")
        }
    }
}

// MARK: - Group

/** iOS: `TVGroupDetailView` — Front / Back cover switch. */
class TvGroupDetailRoute(private val id: String, private val name: String) : TvDetailRoute() {
    override val key = "group.$id.${System.nanoTime()}"
    private var group by mutableStateOf<StashGroup?>(null)
    private var loading by mutableStateOf(true)
    private var back by mutableStateOf(false)
    private val scenes = TvScopedScenes(scope, DetailRepository.scope("groups", id))

    init {
        scope.launch {
            group = runCatching { DetailRepository.group(id) }.getOrNull()
            loading = false
            // Picked side has no image → the other one.
            val g = group
            if (g != null && g.frontImagePath == null && g.backImagePath != null) back = true
        }
    }

    private fun coverURL(g: StashGroup?, back: Boolean): String? {
        val base = de.letzgo.stashy.data.ServerConfigManager.activeConfig?.baseURL ?: return null
        val path = if (back) g?.backImagePath else g?.frontImagePath
        val raw = when {
            path == null -> "$base/group/$id/${if (back) "backimage" else "frontimage"}"
            path.startsWith("http") -> path
            else -> base + path
        }
        return Net.signed(raw)
    }

    @Composable
    override fun Content() {
        val g = group
        TvGenericDetail(
            g?.name ?: name, g?.synopsis, loading, 16f / 9f, TvIcons.stack, null,
            TvChannel.group(id, g?.name ?: name), scenes.list, focus,
            heroOverride = {
                if (g != null) TvImage(coverURL(g, back), Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.12f)), TvIcons.stack, TvColors.background, ContentScale.Fit, pt(56))
                else Box(Modifier.fillMaxSize().background(TvColors.background))
            },
        ) {
            if (g != null) {
                TvInfoRow("Cover") {
                    Row(horizontalArrangement = Arrangement.spacedBy(pt(14))) {
                        TvButton({ back = false }, contentPadding = PaddingValues(horizontal = pt(18), vertical = pt(8))) { Text(if (!back) "✓ Front" else "Front", style = TvType.headline) }
                        TvButton({ back = true }, contentPadding = PaddingValues(horizontal = pt(18), vertical = pt(8))) { Text(if (back) "✓ Back" else "Back", style = TvType.headline) }
                    }
                }
            }
            if (scenes.list.totalCount > 0) TvInfoRow("Scenes", "${scenes.list.totalCount}")
        }
    }
}

// MARK: - Gallery

/** iOS: `TVGalleryDetailView` — header with cover and info, then the still images. */
class TvGalleryDetailRoute(private val id: String, private val title: String, initial: Gallery? = null) : TvDetailRoute() {
    override val key = "gallery.$id.${System.nanoTime()}"
    private var gallery by mutableStateOf(initial)
    private var loading by mutableStateOf(initial == null)
    val images = PagedList<StashImage>(scope, 60) { page, perPage ->
        CatalogRepository.find(CatalogQuery(FilterMode.Images, SortCatalog.option(FilterMode.Images, "dateDesc")!!, scope = DetailRepository.scope("galleries", id)), page, perPage)
    }

    init {
        scope.launch { runCatching { DetailRepository.gallery(id) }.getOrNull()?.let { gallery = it }; loading = false }
        images.refresh()
    }

    @Composable
    override fun Content() {
        val g = gallery
        val stills = images.items.tvStillImages()
        val spec = TvGridSpec.images
        val emptyFocus = remember { FocusRequester() }
        BoxWithConstraints(Modifier.fillMaxSize().background(TvColors.background)) {
            val horizontal = pt(60)
            val columns = spec.columnCount((maxWidth - horizontal * 2).value)
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = horizontal, end = horizontal, top = pt(40), bottom = pt(120)),
                horizontalArrangement = Arrangement.spacedBy(pt(30)),
                verticalArrangement = Arrangement.spacedBy(pt(30)),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "header") {
                    Row(horizontalArrangement = Arrangement.spacedBy(pt(50)), modifier = Modifier.padding(bottom = pt(10))) {
                        TvImage(g?.coverURL, Modifier.width(pt(400)).height(pt(225)).clip(RoundedCornerShape(pt(14))), TvIcons.photoStack, iconSize = pt(56))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(pt(16))) {
                            Text(g?.displayTitle ?: title, style = TvType.largeTitle, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            if (loading) TvSpinner(pt(48))
                            else if (g != null) {
                                g.details?.takeIf { it.isNotEmpty() }?.let { Text(it, style = TvType.body, color = TvColors.secondary, maxLines = 6, overflow = TextOverflow.Ellipsis) }
                                Box(Modifier.fillMaxWidth().height(1.dp).background(TvColors.secondary.copy(alpha = 0.4f)))
                                g.imageCount?.let { TvInfoRow("Images", "$it") }
                                g.date?.takeIf { it.isNotEmpty() }?.let { TvInfoRow("Date", it) }
                                g.studio?.name?.let { TvInfoRow("Studio", it) }
                            }
                        }
                    }
                }
                when {
                    images.items.isEmpty() && (images.isLoading || !images.loadedOnce) -> item(span = { GridItemSpan(maxLineSpan) }, key = "loading") { TvLoading() }
                    stills.isEmpty() -> item(span = { GridItemSpan(maxLineSpan) }, key = "empty") {
                        Column(Modifier.fillMaxWidth().padding(vertical = pt(60)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(16))) {
                            Icon(TvIcons.photo, null, Modifier.size(pt(48)), tint = TvColors.secondary)
                            Text(if (images.items.isEmpty()) "No images in this gallery" else "No supported images in this gallery", style = TvType.title3, color = TvColors.secondary)
                            if (images.items.isNotEmpty()) Text("Only unsupported or animated formats (e.g. GIF) were found.", style = TvType.body, color = TvColors.tertiary)
                            TvButton({ TvNav.pop() }, Modifier.focusRequester(emptyFocus)) { Text("Back", style = TvType.title3) }
                        }
                    }
                    else -> itemsIndexed(stills, key = { _, i -> i.id }) { index, image ->
                        LaunchedEffect(index, stills.size) { if (index >= stills.size - 3 && images.hasMore) images.loadMore() }
                        TvImageTile(
                            image,
                            { TvNav.push(TvImageViewerRoute(image.id, image.tvDisplayTitle ?: "Untitled", { images.items.tvStillImages() }, { images.loadMore() }, { images.hasMore })) },
                            Modifier.tvFocusMemory(focus, image.id).then(if (index == 0) Modifier.focusRequester(emptyFocus) else Modifier),
                        )
                    }
                }
            }
        }
        TvInitialFocus(focus, emptyFocus, enabled = stills.isNotEmpty() || (images.loadedOnce && !images.isLoading), name = "gallery.first")
    }
}
