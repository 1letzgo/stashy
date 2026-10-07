package de.letzgo.stashy.ui.catalog

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import de.letzgo.stashy.ui.StashyColors
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.itemsIndexed as gridItemsIndexed
import androidx.compose.runtime.State
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageFeedPost
import de.letzgo.stashy.data.ImageGroupMode
import de.letzgo.stashy.data.ImageSetGrouping
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.detail.GalleryDetailScreen
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.player.PreviewSurface
import de.letzgo.stashy.ui.player.rememberPreviewPlayer
import de.letzgo.stashy.ui.NativeMediaLabel
import de.letzgo.stashy.ui.components.onLongPress
import de.letzgo.stashy.ui.components.TagChipRow
import de.letzgo.stashy.ui.components.TagChipStyle
import de.letzgo.stashy.ui.components.TagChips
import de.letzgo.stashy.ui.components.showsTagRow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * iOS: `StashImage.oneColumnFeedAspectRatio` — landscape keeps its own ratio, portrait is
 * always 3:4, square / unknown 1:1.
 */
val StashImage.oneColumnFeedAspectRatio: Float get() {
    val f = visualFiles?.firstOrNull() ?: return 1f
    val w = f.width ?: 0; val h = f.height ?: 0
    if (w <= 0 || h <= 0) return 1f
    return when {
        w > h -> w.toFloat() / h
        h > w -> 9f / 12f
        else -> 1f
    }
}

/** iOS: `ImagesViewBody.recomputeAutoplayTarget` — the visible video card closest to the viewport centre. */
object ImageFeedAutoplay {
    /** [frames]: id → (top, bottom) in viewport coordinates. */
    fun target(frames: Map<String, Pair<Float, Float>>, viewportTop: Float, viewportBottom: Float): String? {
        val mid = (viewportTop + viewportBottom) / 2f
        return frames.filter { (_, f) -> f.second > viewportTop && f.first < viewportBottom }
            .minByOrNull { (_, f) -> abs((f.first + f.second) / 2f - mid) }?.key
    }
}

/**
 * iOS: the 1/row layout of `ImagesViewBody` (`oneColumnFeedPosts` + `ImageGroupCatalogCell`), shared
 * by Feeds › Pics and the Images catalog: one post per row, images of one import set grouped
 * into a swipeable post with a thumb strip (Settings › Content › "Group into sets" /
 * "Session gap" / "Max set size", keys `stashline_group_mode` / `stashline_group_gap_minutes` /
 * `stashline_group_max_size`), muted
 * autoplay of the most centred video while the list is idle (`images_feed_video_autoplay`),
 * rating + O-counter on every post, tap opens [ImageViewerScreen] over the posts' flattened
 * order. [onImageUpdated] writes optimistic edits back to the caller's list.
 */
@Composable
fun ImageFeedList(
    images: List<StashImage>,
    sortRaw: String?,
    isLoading: Boolean,
    onLoadMore: () -> Unit,
    contentPadding: PaddingValues,
    onImageUpdated: (StashImage) -> Unit,
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    currentGalleryId: String? = null,
    showsRate: Boolean = true,
    /** Optional first row (e.g. the catalog's search chip). */
    header: (@Composable () -> Unit)? = null,
) {
    val mode = TabManager.stashlineGroupMode
    val gap = TabManager.stashlineGroupGapMinutes
    val maxSize = TabManager.stashlineGroupMaxSize
    val snapshot = images.toList()
    val posts = remember(snapshot, sortRaw, mode, gap, maxSize) { buildFeedPosts(snapshot, sortRaw, mode, gap, maxSize) }
    val flattened = remember(posts) { posts.flatMap { it.images } }

    // Visible image per post (iOS `visibleImageId` of each cell, hoisted for the autoplay pick).
    val visibleIds = remember { mutableStateMapOf<String, String>() }
    val scrolling = state.isScrollInProgress
    val autoplayId by remember(posts) {
        derivedStateOf {
            if (!TabManager.imagesFeedVideoAutoplay || state.isScrollInProgress) return@derivedStateOf null
            val info = state.layoutInfo
            val frames = HashMap<String, Pair<Float, Float>>()
            info.visibleItemsInfo.forEach { item ->
                val post = posts.firstOrNull { it.id == item.key } ?: return@forEach
                val visible = post.images.firstOrNull { it.id == visibleIds[post.id] } ?: post.images.first()
                if (visible.isVideo) frames[visible.id] = item.offset.toFloat() to (item.offset + item.size).toFloat()
            }
            ImageFeedAutoplay.target(frames, info.viewportStartOffset.toFloat(), info.viewportEndOffset.toFloat())
        }
    }

    fun open(image: StashImage) = openFeedImage(images, flattened, image, onLoadMore)

    LazyColumn(
        modifier.fillMaxSize(),
        state = state,
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(Tokens.Grid.spacing),
    ) {
        if (header != null) item(key = "header") { header() }
        itemsIndexed(posts, key = { _, p -> p.id }) { index, post ->
            LaunchedEffect(index, posts.size) { if (index >= posts.size - 3) onLoadMore() }
            ImageFeedPostCard(
                post = post,
                visibleId = visibleIds[post.id],
                onVisibleChange = { visibleIds[post.id] = it },
                autoplayImageId = if (scrolling) null else autoplayId,
                currentGalleryId = currentGalleryId,
                showsRate = showsRate,
                onOpen = ::open,
                onImageUpdated = onImageUpdated,
            )
        }
        if (isLoading && posts.isNotEmpty()) item(key = "loading") {
            Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator(color = Theme.palette.secondaryText) }
        }
    }
}

/** iOS `oneColumnFeedPosts`; lazy keys must be unique (iOS ids collide only in degenerate data). */
private fun buildFeedPosts(
    images: List<StashImage>,
    sortRaw: String?,
    mode: ImageGroupMode,
    gapMinutes: Int,
    maxSetSize: Int,
): List<ImageFeedPost> {
    val built = ImageSetGrouping.buildPosts(images, sortRaw, mode, gapMinutes, maxSetSize)
    val seen = HashSet<String>()
    return built.map { p -> if (seen.add(p.id)) p else p.copy(id = "${p.id}#${p.images.first().id}") }
}

/**
 * iOS `fullScreenFeedBinding`: the viewer swipes in post order. When that is the API order,
 * the caller's list itself goes in so deletes / edits land there.
 */
private fun openFeedImage(images: List<StashImage>, flattened: List<StashImage>, image: StashImage, onLoadMore: () -> Unit) {
    val source: List<StashImage> = if (images is SnapshotStateList && flattened == images.toList()) images else flattened
    val index = source.indexOfFirst { it.id == image.id }.coerceAtLeast(0)
    Nav.push(ImageViewerScreen(source, index, onLoadMore = onLoadMore))
}

/**
 * iOS: `LinkedImagesCatalogGrid` in 1/row mode (Performer / Tag detail) and
 * `ImagesView(gallery:)` — the same grouped feed as [ImageFeedList], emitted as items of the
 * detail screen's `LazyVerticalGrid` (which also carries the header). The holder lives as long
 * as the screen: memoised posts (the grid builder is not composable), the visible image per
 * post and the autoplay pick over the grid's layout.
 */
class ImageFeedGridModel {
    val visibleIds = mutableStateMapOf<String, String>()
    private var memoKey: List<Any?>? = null
    private var postsById: Map<String, ImageFeedPost> = emptyMap()
    var posts: List<ImageFeedPost> = emptyList(); private set
    var flattened: List<StashImage> = emptyList(); private set
    private var autoplayState: Pair<LazyGridState, State<String?>>? = null

    fun update(images: List<StashImage>, sortRaw: String?) {
        val mode = TabManager.stashlineGroupMode
        val gap = TabManager.stashlineGroupGapMinutes
        val maxSize = TabManager.stashlineGroupMaxSize
        val snapshot = images.toList()
        val key = listOf(snapshot, sortRaw, mode, gap, maxSize)
        if (key == memoKey) return
        memoKey = key
        posts = buildFeedPosts(snapshot, sortRaw, mode, gap, maxSize)
        postsById = posts.associateBy { it.id }
        flattened = posts.flatMap { it.images }
    }

    /** iOS `recomputeAutoplayTarget`: only while idle, the video post closest to the viewport centre. */
    fun autoplay(state: LazyGridState): State<String?> {
        autoplayState?.takeIf { it.first === state }?.let { return it.second }
        val derived = derivedStateOf {
            if (!TabManager.imagesFeedVideoAutoplay || state.isScrollInProgress) return@derivedStateOf null
            val info = state.layoutInfo
            val frames = HashMap<String, Pair<Float, Float>>()
            info.visibleItemsInfo.forEach { item ->
                val post = (item.key as? String)?.let { postsById[it] } ?: return@forEach
                val visible = post.images.firstOrNull { it.id == visibleIds[post.id] } ?: post.images.first()
                if (visible.isVideo) frames[visible.id] = item.offset.y.toFloat() to (item.offset.y + item.size.height).toFloat()
            }
            ImageFeedAutoplay.target(frames, info.viewportStartOffset.toFloat(), info.viewportEndOffset.toFloat())
        }
        autoplayState = state to derived
        return derived
    }

    fun open(images: List<StashImage>, image: StashImage, onLoadMore: () -> Unit) = openFeedImage(images, flattened, image, onLoadMore)
}

/**
 * Emits the feed posts of [images] into a single-column detail grid (iOS 1/row
 * `LazyVGrid(columns: [GridItem(.flexible())])`); [onLoadMore] fires near the end.
 */
fun LazyGridScope.imageFeedItems(
    model: ImageFeedGridModel,
    images: List<StashImage>,
    sortRaw: String?,
    gridState: LazyGridState,
    onLoadMore: () -> Unit,
    onImageUpdated: (StashImage) -> Unit,
    currentGalleryId: String? = null,
    showsRate: Boolean = true,
) {
    model.update(images, sortRaw)
    val posts = model.posts
    gridItemsIndexed(posts, key = { _, p -> p.id }, span = { _, _ -> GridItemSpan(maxLineSpan) }) { index, post ->
        LaunchedEffect(index, posts.size) { if (index >= posts.size - 3) onLoadMore() }
        val autoplayId by model.autoplay(gridState)
        ImageFeedPostCard(
            post = post,
            visibleId = model.visibleIds[post.id],
            onVisibleChange = { model.visibleIds[post.id] = it },
            autoplayImageId = if (gridState.isScrollInProgress) null else autoplayId,
            currentGalleryId = currentGalleryId,
            showsRate = showsRate,
            onOpen = { model.open(images, it, onLoadMore) },
            onImageUpdated = onImageUpdated,
        )
    }
}

private val cardShape = RoundedCornerShape(Tokens.Radius.card)
private val textShadow = Shadow(Color.Black.copy(alpha = 0.35f), androidx.compose.ui.geometry.Offset(0f, 1f), 1f)

/**
 * iOS: `ImageGroupCatalogCell` — header over the orientation-aware hero (set: horizontal pager),
 * "i/n" pill bottom-left, rating + O-counter bottom-right, tag row, thumb strip for sets.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ImageFeedPostCard(
    post: ImageFeedPost,
    visibleId: String?,
    onVisibleChange: (String) -> Unit,
    autoplayImageId: String?,
    currentGalleryId: String?,
    showsRate: Boolean,
    onOpen: (StashImage) -> Unit,
    onImageUpdated: (StashImage) -> Unit,
) {
    val p = Theme.palette
    val images = post.images
    val visibleIndex = images.indexOfFirst { it.id == visibleId }.coerceAtLeast(0)
    val visible = images[visibleIndex]
    // A set keeps one frame — its tallest image — so the height never jumps while swiping;
    // wider images are letterboxed in it instead of cropped.
    val ratio = if (images.size > 1) images.minOf { it.oneColumnFeedAspectRatio } else visible.oneColumnFeedAspectRatio

    Column(Modifier.fillMaxWidth().cardShadow(cardShape).clip(cardShape).background(p.secondaryBackground)) {
        Box(Modifier.fillMaxWidth().aspectRatio(ratio)) {
            if (images.size > 1) {
                val pager = rememberPagerState(initialPage = visibleIndex) { images.size }
                LaunchedEffect(pager) { snapshotFlow { pager.currentPage }.collect { onVisibleChange(images.getOrNull(it)?.id ?: return@collect) } }
                LaunchedEffect(visibleIndex) { if (pager.currentPage != visibleIndex && !pager.isScrollInProgress) pager.animateScrollToPage(visibleIndex) }
                HorizontalPager(pager, Modifier.fillMaxSize(), key = { images.getOrNull(it)?.id ?: it }) { page ->
                    val img = images[page]
                    FeedHero(img, autoplay = img.id == visible.id && autoplayImageId == img.id, fit = img.oneColumnFeedAspectRatio > ratio + 0.01f) { onOpen(img) }
                }
            } else {
                FeedHero(visible, autoplay = autoplayImageId == visible.id) { onOpen(visible) }
            }
            FeedHeader(visible, currentGalleryId)
            Row(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(8.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (images.size > 1) {
                    NativeMediaLabel("${visibleIndex + 1}/${images.size}", Modifier.padding(bottom = 8.dp))
                }
                Spacer(Modifier.weight(1f))
                if (showsRate) FeedRateChrome(visible, onImageUpdated)
            }
        }

        TagRow(visible, bottomPadding = if (images.size > 1) 0.dp else 8.dp, onImageUpdated = onImageUpdated)

        if (images.size > 1) {
            val strip = rememberLazyListState()
            LaunchedEffect(visibleIndex) { strip.animateScrollToItem((visibleIndex - 2).coerceAtLeast(0)) }
            LazyRow(
                state = strip,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(images, key = { _, it -> it.id }) { i, img ->
                    GroupThumb(img, selected = i == visibleIndex) { onVisibleChange(img.id) }
                }
            }
        }
    }
}

/** iOS: `ImageThumbnailCard(showsOverlayChrome: false, allowsVideoAutoplay:)` — top-cropped hero with muted autoplay. */
@Composable
private fun FeedHero(image: StashImage, autoplay: Boolean, fit: Boolean = false, onClick: () -> Unit) {
    val preview = rememberPreviewPlayer()
    var previewing by remember(image.id) { mutableStateOf(false) }
    val allowed by rememberUpdatedState(autoplay)
    // iOS `scheduleVideoAutoplayIfNeeded`: start after 0.5 s of idle settle; stop at once.
    LaunchedEffect(image.id, autoplay) {
        val url = image.imageURL
        if (!autoplay || !image.isVideo || url == null) {
            previewing = false
            preview.stop(release = true)
            return@LaunchedEffect
        }
        delay(500)
        if (allowed) { preview.start(url); previewing = true }
    }
    Box(Modifier.fillMaxSize().background(if (fit) Color.Black else Color.Gray.copy(alpha = 0.1f)).noRippleClickable(onClick), contentAlignment = Alignment.Center) {
        SubcomposeAsyncImage(
            model = image.thumbnailURL, contentDescription = image.title,
            contentScale = if (fit) ContentScale.Fit else ContentScale.Crop, alignment = if (fit) Alignment.Center else Alignment.TopCenter,
            loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Theme.palette.secondaryText, modifier = Modifier.size(24.dp)) } },
            error = { Box(Modifier.fillMaxSize(), Alignment.Center) { Icon(SF.photo, null, tint = Theme.palette.secondaryText) } },
            modifier = Modifier.fillMaxSize(),
        )
        AnimatedVisibility(previewing && preview.hasFirstFrame, Modifier.fillMaxSize(), enter = fadeIn(tween(200)), exit = fadeOut(tween(0))) {
            PreviewSurface(preview, Modifier.fillMaxSize(), fill = !fit, topAligned = !fit)
        }
        if (image.isVideo && !(previewing && preview.hasFirstFrame)) {
            Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.4f)).padding(12.dp)) {
                Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(24.dp))
            }
        }
    }
}

/** iOS: `ImageCatalogFeedHeader` — avatars · performer names / studio · date over a top gradient. */
@Composable
private fun FeedHeader(image: StashImage, currentGalleryId: String?) {
    val performers = image.performers.orEmpty()
    val gallery = image.galleries?.let { gs -> if (currentGalleryId != null) gs.firstOrNull { it.id != currentGalleryId } else gs.firstOrNull() }
    val openGallery: (() -> Unit)? = gallery?.let { g -> { Nav.push(GalleryDetailScreen(g.id, Gallery(id = g.id, title = g.title ?: g.name ?: "Gallery"), forceOneColumnFeed = true)) } }
    // iOS: `PerformerDetailView(performer:initialTab: .images)`.
    fun openPerformer(p: IdName) = Nav.push(PerformerDetailScreen(p.id, Performer(id = p.id, name = p.name.orEmpty()), initialTab = de.letzgo.stashy.ui.detail.DetailTab.Images))
    val nameStyle = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold, shadow = textShadow)
    val smallStyle = IosTypography.caption2.copy(shadow = textShadow)

    Row(
        Modifier.fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.75f), Color.Black.copy(alpha = 0.35f), Color.Transparent)))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy((-10).dp)) {
            // Avatar → gallery in the 1/row feed (not performer detail), like iOS.
            if (performers.isEmpty()) Avatar(null, null, onClick = openGallery)
            else performers.forEach { pf -> Avatar(pf, performerImageURL(pf.id), onClick = openGallery ?: { openPerformer(pf) }) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            when {
                performers.isEmpty() -> Text(image.title ?: "Unknown", style = nameStyle, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                else -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    performers.forEachIndexed { i, pf ->
                        Text(
                            pf.name.orEmpty(), style = nameStyle, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false).noRippleClickable { openPerformer(pf) },
                        )
                        if (i < performers.size - 1) Text("&", style = IosTypography.subheadline, color = Color.White.copy(alpha = 0.75f))
                    }
                }
            }
            image.studio?.name?.let { Text(it, style = smallStyle, color = Color.White.copy(alpha = 0.85f), maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
        image.date?.let { Text(it, style = smallStyle, color = Color.White.copy(alpha = 0.85f), maxLines = 1) }
    }
}

/** Performer portrait (`/performer/<id>/image`, like the Feeds overlay). */
private fun performerImageURL(id: String): String? = ServerConfigManager.activeConfig?.baseURL?.let { Net.signed("$it/performer/$id/image") }

@Composable
private fun Avatar(performer: IdName?, url: String?, onClick: (() -> Unit)?) {
    Box(
        Modifier.size(36.dp).clip(CircleShape).background(Appearance.tint.copy(alpha = 0.35f))
            .border(2.dp, Color.White.copy(alpha = 0.9f), CircleShape)
            .let { if (onClick != null) it.noRippleClickable(onClick) else it },
        contentAlignment = Alignment.Center,
    ) {
        if (performer == null) Icon(SF.personFill, null, tint = Color.White, modifier = Modifier.size(14.dp))
        else {
            Text(performer.name.orEmpty().take(1).uppercase(), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
            if (url != null) AsyncImage(url, performer.name, contentScale = ContentScale.Crop, modifier = Modifier.size(36.dp).clip(CircleShape))
        }
    }
}

/**
 * iOS: `ImageGroupCatalogCell.tagRow` — the shared Material [TagChipRow] as in Feeds: pinned
 * "Add tag" (edit mode, opens `AddTagsSheet`), scrolling `#tag` chips (long press → "Remove tag"
 * in edit mode) and the stashy+ Tag Suggestion chips inline after the tags. Shown when there are
 * tags, edit mode is on or Tag Suggestion is active (iOS `showsTagRow`). The row sits on the
 * themed post card (not on the picture), so it uses [TagChipStyle.Surface].
 */
@Composable
private fun TagRow(image: StashImage, bottomPadding: androidx.compose.ui.unit.Dp, onImageUpdated: (StashImage) -> Unit) {
    val tags = image.tags.orEmpty()
    if (!showsTagRow(tags)) return
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var editor by androidx.compose.runtime.remember(image.id) { androidx.compose.runtime.mutableStateOf(false) }
    // 8 dp visual gaps around the 32 dp chips; the 40 dp touch row already adds 4 dp per side.
    TagChipRow(
        itemId = image.id,
        tags = tags,
        style = TagChipStyle.Surface,
        modifier = Modifier
            .padding(top = 8.dp - TagChips.touchInset, bottom = (bottomPadding - TagChips.touchInset).coerceAtLeast(0.dp))
            .padding(horizontal = 12.dp),
        onAddTag = { editor = true },
        onRemoveTag = { tag ->
            scope.launch {
                val remaining = tags.filter { it.id != tag.id }
                if (de.letzgo.stashy.data.DetailRepository.setImageTags(image.id, remaining.map { it.id })) {
                    onImageUpdated(image.copy(tags = remaining))
                }
            }
        },
    ) {
        // iOS: `AITagSuggestionBar(target: .image(image))` — chips inline after the tags (stashy+).
        de.letzgo.stashy.ui.components.AITagSuggestionBar(de.letzgo.stashy.data.tools.AITagTarget.image(image), style = TagChipStyle.Surface) { newTags ->
            onImageUpdated(image.copy(tags = newTags.map { t -> de.letzgo.stashy.data.IdName(t.id, t.name) }))
        }
    }
    if (editor) {
        de.letzgo.stashy.ui.components.AddTagsSheet(de.letzgo.stashy.data.tools.AITagTarget.image(image), onDismiss = { editor = false }) { updated ->
            editor = false
            onImageUpdated(image.copy(tags = updated.map { t -> de.letzgo.stashy.data.IdName(t.id, t.name) }))
        }
    }
}

/** iOS: `ImageGroupThumbView` — 56 pt square, tint border when selected, play badge for videos. */
@Composable
private fun GroupThumb(image: StashImage, selected: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(Tokens.Radius.small)
    Box(
        Modifier.size(56.dp).clip(shape).background(Theme.palette.studioHeader)
            .let { if (selected) it.border(2.dp, Appearance.tint, shape) else it }
            .noRippleClickable(onClick),
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(image.thumbnailURL, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().padding(if (selected) 2.dp else 0.dp).clip(shape))
        if (image.isVideo) Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.4f)).padding(4.dp)) {
            Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(12.dp))
        }
    }
}

/** iOS: `ImageGroupCatalogCell.rateChrome` — rating menu left, O-counter right (tap +1, long press menu). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FeedRateChrome(image: StashImage, onImageUpdated: (StashImage) -> Unit) {
    val scope = rememberCoroutineScope()
    val oCount = image.oCounter ?: 0
    val stars = ((image.rating100 ?: 0) / 20.0).roundToInt().coerceIn(0, 5)
    var ratingMenu by remember { mutableStateOf(false) }
    var oMenu by remember { mutableStateOf(false) }

    fun setRating(s: Int) {
        val original = image.rating100
        val r = if (s > 0) s * 20 else null
        onImageUpdated(image.copy(rating100 = r))
        scope.launch {
            if (!FeedsRepository.updateImageRating(image.id, r)) {
                onImageUpdated(image.copy(rating100 = original))
                showToast("Failed to save rating")
            }
        }
    }
    fun changeO(m: FeedsRepository.OMutation) {
        val optimistic = when (m) {
            FeedsRepository.OMutation.Increment -> oCount + 1
            FeedsRepository.OMutation.Decrement -> (oCount - 1).coerceAtLeast(0)
            FeedsRepository.OMutation.Reset -> 0
        }
        onImageUpdated(image.copy(oCounter = optimistic))
        scope.launch {
            val count = FeedsRepository.mutateOCounter(image.id, isImage = true, m)
            onImageUpdated(image.copy(oCounter = count ?: oCount))
            if (count == null) showToast("Failed to update O-Counter")
        }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
        Box {
            RatePill(SF.starFill, "$stars", stars > 0, onClick = { ratingMenu = true })
            DropdownMenu(ratingMenu, onDismissRequest = { ratingMenu = false }) {
                DropdownMenuItem(text = { Text("Clear Rating") }, trailingIcon = { if (stars == 0) Icon(SF.checkmark, null) }, onClick = { ratingMenu = false; setRating(0) })
                HorizontalDivider()
                for (s in 1..5) DropdownMenuItem(
                    text = { Text("★".repeat(s)) }, trailingIcon = { if (stars == s) Icon(SF.checkmark, null) },
                    onClick = { ratingMenu = false; setRating(s) },
                )
            }
        }
        Box {
            RatePill(
                oCounterIcon(Appearance.oCounterIcon, filled = oCount > 0), "$oCount", oCount > 0,
                onClick = { changeO(FeedsRepository.OMutation.Increment) },
                onLongClick = { if (oCount > 0) oMenu = true },
            )
            DropdownMenu(oMenu, onDismissRequest = { oMenu = false }) {
                DropdownMenuItem(text = { Text("Remove one") }, onClick = { oMenu = false; changeO(FeedsRepository.OMutation.Decrement) })
                DropdownMenuItem(text = { Text("Reset") }, onClick = { oMenu = false; changeO(FeedsRepository.OMutation.Reset) })
            }
        }
    }
}

/** Rating / O-counter of a post — Material `AssistChip` in the over-media look of the tag chips. */
@Composable
private fun RatePill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    value: String,
    active: Boolean,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    AssistChip(
        onClick = onClick,
        label = { Text(value, style = MaterialTheme.typography.labelLarge, maxLines = 1) },
        leadingIcon = { Icon(icon, null, Modifier.size(AssistChipDefaults.IconSize)) },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = Color.Black.copy(alpha = 0.45f),
            labelColor = Color.White,
            leadingIconContentColor = Color.White.copy(alpha = if (active) 1f else 0.72f),
        ),
        border = AssistChipDefaults.assistChipBorder(enabled = true, borderColor = Color.White.copy(alpha = 0.25f)),
        modifier = if (onLongClick != null) Modifier.onLongPress(onLongClick) else Modifier,
    )
}
