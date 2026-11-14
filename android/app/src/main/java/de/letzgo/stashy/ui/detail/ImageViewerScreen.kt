package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ArrowCircleDown
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.data.tools.AITagUpdateEvent
import de.letzgo.stashy.ui.components.AITagSuggestionBar
import de.letzgo.stashy.ui.components.AddTagsSheet
import de.letzgo.stashy.ui.components.TagChipRow
import de.letzgo.stashy.ui.components.TagChips
import de.letzgo.stashy.ui.components.showsTagRow
import de.letzgo.stashy.ui.tools.downloads.DownloadGlyph
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.TopBarAction
import de.letzgo.stashy.ui.TopBarOverflowMenu
import android.content.Context
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.layout
import de.letzgo.stashy.data.ImageViewing
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.await
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.stashyGlass
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.oCounterIcon
import androidx.compose.foundation.interaction.MutableInteractionSource
import de.letzgo.stashy.ui.feeds.AddPerformerButton
import de.letzgo.stashy.ui.feeds.ChromePillIconButton
import de.letzgo.stashy.ui.feeds.StackedPill
import de.letzgo.stashy.ui.feeds.noIndicationClick
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File

/**
 * iOS: `FullScreenImageView` + `GalleryItemView` — full-screen pager over [images] (vertical
 * paging like iOS), pinch / double-tap zoom, clips (`isVideo`) played with Media3 (loop, mute,
 * play/pause, scrubber), GIF/WebP animated by Coil, and the iOS chrome: Back · Share · Set as
 * performer image · Delete on top; performer, title, O-counter, rating, mute, play and tags at
 * the bottom. Tap toggles the chrome.
 *
 * When [images] is a `SnapshotStateList` (a detail grid passes its `PagedList.items`) edits and
 * deletes land in the caller's list, like the iOS `Binding`; [onLoadMore] pages further.
 */
class ImageViewerScreen(
    val images: List<StashImage>,
    val startIndex: Int,
    val onLoadMore: (() -> Unit)? = null,
) : Screen {
    override val key = "image-viewer-${images.getOrNull(startIndex)?.id ?: startIndex}"
    override val hidesTabBar = true

    private val items: SnapshotStateList<StashImage> =
        (images as? SnapshotStateList<StashImage>) ?: mutableStateListOf<StashImage>().also { it.addAll(images) }

    private var currentIndex by mutableStateOf(startIndex.coerceIn(0, (images.size - 1).coerceAtLeast(0)))
    private var showUI by mutableStateOf(true)
    private var zoomed by mutableStateOf(false)
    private var isMuted by mutableStateOf(true)
    private var isPlaying by mutableStateOf(true)
    private var player by mutableStateOf<ExoPlayer?>(null)
    private var position by mutableLongStateOf(0L)
    private var duration by mutableLongStateOf(0L)
    private var seeking by mutableStateOf(false)
    private var confirmDelete by mutableStateOf(false)
    private var performerImageTargets by mutableStateOf<List<IdName>>(emptyList())
    /** Galleries the "Set as gallery cover" alert offers (non-empty = alert shown). */
    private var galleryCoverTargets by mutableStateOf<List<IdName>>(emptyList())
    /** iOS `tagEditorImage` — the picture whose `AddTagsSheet` is open. */
    private var tagEditorImage by mutableStateOf<StashImage?>(null)
    /** iOS `wasPlayingBeforeTagEditor`. */
    private var wasPlayingBeforeTagEditor = false
    /** The picture whose add-only performer picker ("+" after the performer name) is open. */
    private var performerEditorImage by mutableStateOf<StashImage?>(null)

    /** iOS `@AppStorage` keys of the fullscreen viewer. */
    private val continuousPlay get() = Prefs.bool("images_fullscreen_continuous", false)
    private val continuousSeconds get() = Prefs.int("images_fullscreen_continuous_duration", 3).coerceAtLeast(1)

    private val current: StashImage? get() = items.getOrNull(currentIndex)

    @OptIn(ExperimentalFoundationApi::class)
    @Composable
    override fun Content() {
        val context = LocalContext.current
        de.letzgo.stashy.ui.DarkSurfaceBehindSystemBars()
        val scope = rememberCoroutineScope()
        LaunchedEffect(Unit) { isMuted = initialMute() }
        // iOS `ImageTagsUpdated` / `BulkTagsApplied` → `patchImageTagsInLists` / `patchBulkAppliedTag`.
        LaunchedEffect(Unit) {
            AITagSuggestions.events.collect { event ->
                when (event) {
                    is AITagUpdateEvent.TagsUpdated -> if (event.kind == AITagTarget.Kind.Image) {
                        replace(event.entityId) { it.copy(tags = event.tags.map { t -> IdName(t.id, t.name) }) }
                    }
                    is AITagUpdateEvent.BulkTagsApplied -> event.imageIds.forEach { id ->
                        replace(id) { img ->
                            if (img.tags.orEmpty().any { it.id == event.tag.id }) img
                            else img.copy(tags = img.tags.orEmpty() + IdName(event.tag.id, event.tag.name))
                        }
                    }
                }
            }
        }
        val pager = rememberPagerState(initialPage = currentIndex) { items.size }

        LaunchedEffect(pager) {
            snapshotFlow { pager.currentPage }.collect { page ->
                if (page != currentIndex) {
                    currentIndex = page
                    // iOS: videos start playing on a new item unless a paused continuous run.
                    if (!continuousPlay) isPlaying = true
                    position = 0; duration = 0
                }
                if (page >= items.size - 2) onLoadMore?.invoke()
            }
        }
        // Continuous play for stills / animations: advance after the configured duration.
        LaunchedEffect(currentIndex, isPlaying, items.size) {
            val image = current ?: return@LaunchedEffect
            if (!continuousPlay || !isPlaying) return@LaunchedEffect
            if (image.isVideo && !DetailFormatting.isAnimated(image)) return@LaunchedEffect
            delay(continuousSeconds * 1000L)
            // Own scope: the page switch happens halfway through the scroll animation and
            // restarts this effect (`currentIndex` changes) — run in the effect, the animation
            // was cancelled and the pager stuck between two images.
            scope.launch { advance(pager) }
        }

        Box(Modifier.fillMaxSize().background(Color.Black)) {
            if (items.isEmpty()) {
                LaunchedEffect(Unit) { Nav.pop() }
            } else {
                VerticalPager(
                    state = pager,
                    modifier = Modifier.fillMaxSize(),
                    userScrollEnabled = !zoomed,
                    beyondViewportPageCount = 1,
                    key = { items.getOrNull(it)?.id ?: "page-$it" },
                ) { page ->
                    val image = items.getOrNull(page) ?: return@VerticalPager
                    ViewerPage(image, active = page == pager.currentPage, onEnded = { scope.launch { advance(pager) } })
                }
            }

            AnimatedVisibility(showUI, Modifier.align(Alignment.TopCenter), enter = fadeIn(), exit = fadeOut()) { TopBar(context) }
            // iOS `fastForwardOverlay` (top 130, glass capsule with `chevron.right.2`).
            AnimatedVisibility(fastForwarding, Modifier.align(Alignment.TopCenter).padding(top = 130.dp), enter = fadeIn(), exit = fadeOut()) {
                Box(Modifier.stashyGlass(RoundedCornerShape(50)).padding(horizontal = 22.dp, vertical = 14.dp)) {
                    Icon(SF.chevronRight2, "2×", tint = Color.White, modifier = Modifier.size(32.dp))
                }
            }
            // "Keep Rating Visible": the overlay stays composed with the chrome hidden, so the
            // O Count and rating pills keep their place; everything else fades out (BottomOverlay).
            val keepRating = ImageViewing.keepRating
            if (showUI || keepRating) Box(Modifier.align(Alignment.BottomCenter)) {
                // Over the media: font scale capped at OverlayMaxFontScale (like Feeds).
                current?.let { de.letzgo.stashy.ui.CappedFontScale { BottomOverlay(it, chrome = showUI) } }
            }
        }

        tagEditorImage?.let { image ->
            AddTagsSheet(AITagTarget.image(image), onDismiss = { closeTagEditor() }) { updated ->
                replace(image.id) { it.copy(tags = updated.map { t -> IdName(t.id, t.name) }) }
            }
        }
        performerEditorImage?.let { image ->
            AddImagePerformersSheet(image, onDismiss = { closePerformerEditor() }) { updated -> replace(image.id) { updated } }
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text(tr(R.string.confirm_really_delete_image)) },
                text = { Text(tr(R.string.hint_this_image_will_be_permanently)) },
                confirmButton = { TextButton({ confirmDelete = false; scope.launch { deleteCurrent(pager) } }) { Text(tr(R.string.action_delete), color = StashyColors.systemRed) } },
                dismissButton = { TextButton({ confirmDelete = false }) { Text(tr(R.string.action_cancel)) } },
            )
        }
        if (performerImageTargets.isNotEmpty()) {
            val targets = performerImageTargets
            AlertDialog(
                onDismissRequest = { performerImageTargets = emptyList() },
                title = { Text(tr(R.string.confirm_set_as_performer_image)) },
                text = {
                    Column {
                        Text(tr(R.string.hint_update_profile_picture_for_selected))
                        if (targets.size > 1) targets.forEach { t ->
                            TextButton({ performerImageTargets = emptyList(); scope.launch { setPerformerImage(t) } }) { Text(t.name ?: tr(R.string.performer)) }
                        }
                    }
                },
                confirmButton = {
                    if (targets.size == 1) TextButton({ performerImageTargets = emptyList(); scope.launch { setPerformerImage(targets[0]) } }) { Text(tr(R.string.okay)) }
                },
                dismissButton = { TextButton({ performerImageTargets = emptyList() }) { Text(tr(R.string.action_cancel)) } },
            )
        }
        if (galleryCoverTargets.isNotEmpty()) {
            val targets = galleryCoverTargets
            AlertDialog(
                onDismissRequest = { galleryCoverTargets = emptyList() },
                title = { Text(tr(R.string.confirm_set_as_gallery_cover)) },
                text = {
                    Column {
                        Text(if (targets.size == 1) tr(R.string.hint_use_this_image_as_cover) else tr(R.string.hint_choose_which_gallery_gets_this))
                        if (targets.size > 1) targets.forEach { t ->
                            TextButton({ galleryCoverTargets = emptyList(); scope.launch { setGalleryCover(t) } }) { Text(t.name?.takeIf { it.isNotBlank() } ?: tr(R.string.untitled_gallery)) }
                        }
                    }
                },
                confirmButton = {
                    if (targets.size == 1) TextButton({ galleryCoverTargets = emptyList(); scope.launch { setGalleryCover(targets[0]) } }) { Text(tr(R.string.okay)) }
                },
                dismissButton = { TextButton({ galleryCoverTargets = emptyList() }) { Text(tr(R.string.action_cancel)) } },
            )
        }
    }

    private suspend fun advance(pager: PagerState) {
        val next = pager.currentPage + 1
        if (next < items.size) pager.animateScrollToPage(next)
        if (next + 1 >= items.size) onLoadMore?.invoke()
    }

    // MARK: Pages

    @Composable
    private fun ViewerPage(image: StashImage, active: Boolean, onEnded: () -> Unit) {
        val animated = DetailFormatting.isAnimated(image)
        val portraitDevice = LocalConfiguration.current.let { it.screenHeightDp > it.screenWidthDp }
        val portraitImage = image.visualFiles?.firstOrNull()?.let { (it.height ?: 0) > (it.width ?: 0) } ?: false
        // iOS `shouldFill`: the scaling mode (Fit / Fill / Automatic = orientation matches the device).
        val fill = ImageViewing.scaling.fills(portraitImage, portraitDevice)
        val backdrop = ImageViewing.backdropColor(image.thumbnailURL ?: image.imageURL)
        val isClip = image.isVideo && !animated
        Box(Modifier.fillMaxSize().background(backdrop)) {
            ZoomableBox(
                onTap = { showUI = !showUI },
                onZoomChange = { zoomed = it },
                zoomEnabled = !isClip,
                onHold = if (isClip) ({ holdFastForward(it) }) else null,
                onDoubleTapAt = if (isClip) ({ x, w -> skipOnDoubleTap(x, w) }) else null,
            ) {
                if (image.isVideo && !animated) {
                    VideoPage(image, active, fill, onEnded)
                } else {
                    SubcomposeAsyncImage(
                        image.imageURL, image.title, Modifier.fillMaxSize(),
                        contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Color.White) } },
                        error = {
                            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(SF.exclamationTriangle, null, tint = Color.White, modifier = Modifier.size(40.dp))
                                Text(tr(R.string.error_load_image), color = Color.White)
                            }
                        },
                    )
                }
            }
        }
    }

    /** iOS `isFastForwarding` (press-and-hold 2× on a playing clip). */
    private var fastForwarding by mutableStateOf(false)
    private var rateBeforeFastForward = 1f

    /** iOS `setFastForwarding`: 2× while held, previous rate restored on release. */
    private fun holdFastForward(active: Boolean) {
        val exo = player ?: return
        if (active == fastForwarding) return
        if (active) {
            if (!isPlaying) return
            rateBeforeFastForward = exo.playbackParameters.speed
            exo.setPlaybackSpeed(2f)
        } else {
            exo.setPlaybackSpeed(rateBeforeFastForward)
        }
        fastForwarding = active
    }

    /** iOS `handleDoubleTapSkip`: outer thirds skip ±`playerSkipSeconds`, the middle does nothing. */
    private fun skipOnDoubleTap(x: Float, width: Float): Boolean {
        val exo = player ?: return false
        val third = width / 3f
        val deltaMs = (de.letzgo.stashy.ui.player.PlayerSettings.skipSeconds * 1000).toLong()
        val delta = when {
            x < third -> -deltaMs
            x > width - third -> deltaMs
            else -> return false
        }
        val dur = exo.duration.takeIf { it > 0 }
        val target = (exo.currentPosition + delta).coerceAtLeast(0).let { t -> dur?.let { minOf(t, it) } ?: t }
        exo.seekTo(target)
        position = target
        return true
    }

    @Composable
    private fun VideoPage(image: StashImage, active: Boolean, fill: Boolean, onEnded: () -> Unit) {
        val context = LocalContext.current
        // The player is sized to the video's own aspect ratio when fitted, so the bars around it
        // are the page's backdrop (Background setting), not the player's black letterbox.
        val file = image.visualFiles?.firstOrNull()
        val aspect = if ((file?.width ?: 0) > 0 && (file?.height ?: 0) > 0) file!!.width!!.toFloat() / file.height!! else null
        val frame = if (!fill && aspect != null) Modifier.fillMaxSize().wrapContentSize().aspectRatio(aspect, matchHeightConstraintsFirst = false) else Modifier.fillMaxSize()
        Box(frame) {
            SubcomposeAsyncImage(image.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = if (fill) ContentScale.Crop else ContentScale.Fit)
            if (!active) return@Box
            val exo = remember(image.id) {
                ExoPlayer.Builder(context)
                    .setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(Net.client)))
                    .build().apply {
                        setMediaItem(MediaItem.fromUri(image.imageURL ?: ""))
                        repeatMode = if (continuousPlay) Player.REPEAT_MODE_OFF else Player.REPEAT_MODE_ONE
                        volume = if (isMuted) 0f else 1f
                        playWhenReady = isPlaying
                        prepare()
                    }
            }
            DisposableEffect(exo) {
                val listener = object : Player.Listener {
                    override fun onPlaybackStateChanged(state: Int) {
                        if (state == Player.STATE_ENDED && continuousPlay) onEnded()
                    }
                }
                exo.addListener(listener)
                // Lazy audio focus: a muted / paused clip leaves other apps' audio alone.
                val audioFocus = de.letzgo.stashy.ui.player.AudioFocusCoordinator(exo)
                val screenAwake = de.letzgo.stashy.ui.player.ScreenAwakeCoordinator(exo)
                player = exo
                onDispose {
                    audioFocus.release()
                    screenAwake.release()
                    exo.removeListener(listener)
                    if (player === exo) { player = null; fastForwarding = false }
                    exo.release()
                }
            }
            LaunchedEffect(exo, isMuted) { exo.volume = if (isMuted) 0f else 1f }
            LaunchedEffect(exo, isPlaying) { exo.playWhenReady = isPlaying }
            LaunchedEffect(exo) {
                while (true) {
                    if (!seeking) position = exo.currentPosition.coerceAtLeast(0)
                    duration = exo.duration.takeIf { it > 0 } ?: 0
                    delay(250)
                }
            }
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = false
                        setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                        player = exo
                    }
                },
                update = { it.resizeMode = if (fill) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    // MARK: Chrome

    /**
     * Transparent Material top app bar over the picture: back · share · download state ·
     * delete; "Set as performer image" in the "⋮" overflow (only with performers).
     */
    @Composable
    private fun TopBar(context: Context) {
        val image = current
        val scope = rememberCoroutineScope()
        NativeTopBar("", transparent = true) {
            TopBarAction(SF.squareAndArrowUp, tr(R.string.action_share)) { image?.let { scope.launch { share(context, it) } } }
            // iOS: per-image download (`downloadManager.downloadImage`, entry `image-<id>`) — check in the
            // accent when stored, arrow while downloading (both disabled), else the download glyph.
            if (image != null) {
                val entryId = "image-${image.id}"
                val isDownloaded = Downloads.isGalleryDownloaded(entryId)
                val isDownloading = Downloads.activeDownloads[entryId] != null
                TopBarAction(
                    when {
                        isDownloaded -> Icons.Filled.CheckCircle
                        isDownloading -> Icons.Outlined.ArrowCircleDown
                        else -> DownloadGlyph
                    },
                    when {
                        isDownloaded -> tr(R.string.downloaded)
                        isDownloading -> tr(R.string.downloading)
                        else -> tr(R.string.action_download)
                    },
                    tint = if (isDownloaded) Appearance.tint else null,
                    enabled = !isDownloaded && !isDownloading,
                ) { Downloads.downloadImage(image) }
            }
            TopBarAction(SF.trash, tr(R.string.action_delete)) { confirmDelete = true }
            if (!image?.galleries.isNullOrEmpty()) {
                TopBarAction(SF.photoStack, tr(R.string.action_set_as_gallery_cover)) { galleryCoverTargets = image?.galleries.orEmpty() }
            }
            if (!image?.performers.isNullOrEmpty()) {
                TopBarOverflowMenu { dismiss ->
                    OverflowItem(tr(R.string.action_set_as_performer_image), SF.personCropCircleBadgePlus, dismiss) { performerImageTargets = image?.performers.orEmpty() }
                }
            }
        }
    }

    @Composable
    private fun BottomOverlay(image: StashImage, chrome: Boolean) {
        /** Fades a part out with the chrome but keeps its space (not placed, so no taps) — the pills stay where they are. */
        fun Modifier.chromePart(): Modifier = composed {
            val a by animateFloatAsState(if (chrome) 1f else 0f, tween(250), label = "chromePart")
            alpha(a).layout { m, c ->
                val pl = m.measure(c)
                layout(pl.width, pl.height) { if (a > 0f) pl.place(0, 0) }
            }
        }
        val isVideo = image.isVideo && !DetailFormatting.isAnimated(image)
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = if (isVideo) 0.dp else 8.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = Dock.edgePadding), verticalAlignment = Alignment.Bottom) {
                Row(Modifier.weight(1f).chromePart(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    image.performers?.firstOrNull()?.let { performer ->
                        PerformerAvatar(performer) { openPerformer(performer) }
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        val first = image.performers?.firstOrNull()
                        // "+" right after the name (alone without performers), like the Feeds overlay.
                        val canAdd = ImagePerformerAdd.canAdd(image)
                        if (first != null || canAdd) Row(verticalAlignment = Alignment.CenterVertically) {
                            first?.let { performer ->
                                Text(
                                    performer.name ?: "", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f, fill = false).clickable { openPerformer(performer) },
                                )
                            }
                            if (canAdd) AddPerformerButton(leading = first == null) { openPerformerEditor(image) }
                        }
                        val title = image.title?.takeIf { it.isNotEmpty() }
                        val gallery = image.galleries?.firstOrNull()
                        if (title != null) {
                            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.85f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        } else if (gallery != null) {
                            Text(
                                gallery.title ?: tr(R.string.unknown_gallery), fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.85f), maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.clickable { Nav.push(GalleryDetailScreen(gallery.id, Gallery(gallery.id, title = gallery.title ?: tr(R.string.gallery)))) },
                            )
                        }
                    }
                }
                Spacer(Modifier.width(8.dp))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OCounterButton(image)
                    RatingButton(image)
                    // Same buttons as the Feeds control stack ([FeedsInfoOverlay]).
                    Column(Modifier.chromePart(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ChromePillIconButton(if (isMuted) SF.speakerSlashFill else SF.speakerWave2Fill, if (isMuted) tr(R.string.unmute) else tr(R.string.mute), enabled = isVideo) {
                        isMuted = !isMuted; de.letzgo.stashy.ui.player.PlayerMute.remember(isMuted)
                    }
                    ChromePillIconButton(if (isPlaying) SF.pauseFill else SF.playFill, if (isPlaying) tr(R.string.action_pause) else tr(R.string.action_play), enabled = isVideo || continuousPlay) {
                        isPlaying = !isPlaying
                    }
                    }
                }
            }
            Box(Modifier.chromePart()) { Column { TagRow(image); if (isVideo) Scrubber() } }
        }
    }

    private fun openPerformer(p: IdName) = Nav.push(PerformerDetailScreen(p.id, Performer(p.id, name = p.name ?: "")))

    @Composable
    private fun PerformerAvatar(p: IdName, onClick: () -> Unit) {
        Box(
            Modifier.size(Dock.circleSize).clip(CircleShape).background(Appearance.tint.copy(alpha = 0.2f))
                .border(2.dp, Appearance.tint, CircleShape).clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            SubcomposeAsyncImage(
                performerThumbnailURL(p.id, null), p.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter,
                error = { Icon(SF.personFill, null, tint = Color.White.copy(alpha = 0.7f)) },
            )
        }
    }

    /** O-counter pill; long press = iOS `oCounterRemovalMenu`. */
    @OptIn(ExperimentalFoundationApi::class)
    @Composable
    private fun OCounterButton(image: StashImage) {
        val count = image.oCounter ?: 0
        val scope = rememberCoroutineScope()
        var menu by remember { mutableStateOf(false) }
        var confirmReset by remember { mutableStateOf(false) }
        Box {
            // The Feeds O-Counter pill ([FeedsRateChrome]): same icon, count and active state.
            StackedPill(
                icon = oCounterIcon(Appearance.oCounterIcon, filled = count > 0),
                value = "$count",
                active = count > 0,
                contentDescription = tr(R.string.o_count),
                modifier = Modifier.combinedClickable(
                    interactionSource = remember { MutableInteractionSource() }, indication = null,
                    onClick = { scope.launch { changeOCounter(image.id, OCounterMutation.Increment) } },
                    onLongClick = { menu = true },
                ),
            )
            DropdownMenu(menu, { menu = false }) {
                if (count > 0) {
                    DropdownMenuItem({ Text(tr(R.string.action_remove_one_o)) }, leadingIcon = { Icon(SF.minusCircle, null) }, onClick = {
                        menu = false; scope.launch { changeOCounter(image.id, OCounterMutation.Decrement) }
                    })
                    if (count > 1) DropdownMenuItem({ Text(tr(R.string.action_reset_o_count_arg, count), color = StashyColors.systemRed) }, leadingIcon = { Icon(SF.arrowCounterclockwise, null, tint = StashyColors.systemRed) }, onClick = {
                        menu = false; confirmReset = true
                    })
                } else {
                    DropdownMenuItem({ Text(tr(R.string.empty_o_recorded)) }, enabled = false, onClick = {})
                }
            }
        }
        if (confirmReset) {
            AlertDialog(
                onDismissRequest = { confirmReset = false },
                title = { Text(tr(R.string.confirm_reset_o_count)) },
                text = { Text(tr(R.string.hint_all_arg_recorded_o_entries, count)) },
                confirmButton = { TextButton({ confirmReset = false; scope.launch { changeOCounter(image.id, OCounterMutation.Reset) } }) { Text(tr(R.string.action_remove_all_arg, count), color = StashyColors.systemRed) } },
                dismissButton = { TextButton({ confirmReset = false }) { Text(tr(R.string.action_cancel)) } },
            )
        }
    }

    /** Rating pill with the iOS menu: Clear Rating · ★ … ★★★★★. */
    @Composable
    private fun RatingButton(image: StashImage) {
        val stars = starsFromRating(image.rating100)
        val scope = rememberCoroutineScope()
        var menu by remember { mutableStateOf(false) }
        Box {
            StackedPill(SF.starFill, "$stars", stars > 0, Modifier.noIndicationClick { menu = true }, contentDescription = tr(R.string.rating))
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem({ Text(tr(R.string.action_clear_rating)) }, trailingIcon = { if (stars == 0) Icon(SF.checkmark, null) }, onClick = {
                    menu = false; scope.launch { setRating(image.id, 0) }
                })
                HorizontalDivider()
                (1..5).forEach { s ->
                    DropdownMenuItem({ Text("★".repeat(s)) }, trailingIcon = { if (stars == s) Icon(SF.checkmark, null) }, onClick = {
                        menu = false; scope.launch { setRating(image.id, s * 20) }
                    })
                }
            }
        }
    }

    /**
     * Hashtag row: the shared Material [TagChipRow] — pinned "Add tag" (edit mode), `#tag` chips
     * (tap does nothing, long press → "Remove tag" in edit mode) and the Tag Suggestion chips
     * inline (stashy+). iOS `showsTagRow`: it also exists for an untagged picture — and only then.
     */
    @Composable
    private fun TagRow(image: StashImage) {
        val tags = image.tags.orEmpty()
        val scope = rememberCoroutineScope()
        if (!showsTagRow(tags)) return
        TagChipRow(
            itemId = image.id,
            tags = tags,
            // 8 dp visual gap above the chips; the 40 dp touch row already adds 4 dp.
            modifier = Modifier.padding(top = 8.dp - TagChips.touchInset).padding(horizontal = Dock.edgePadding),
            onAddTag = { openTagEditor(image) },
            onRemoveTag = { tag -> scope.launch { removeTag(image, tag) } },
        ) {
            // iOS: `AITagSuggestionBar(target: .image(image))` — chips inline after the tags (stashy+).
            AITagSuggestionBar(AITagTarget.image(image)) { newTags ->
                replace(image.id) { it.copy(tags = newTags.map { t -> IdName(t.id, t.name) }) }
            }
        }
    }

    /** iOS `IsolatedScrubberBar` (clips only). */
    @Composable
    private fun Scrubber() {
        val total = duration.coerceAtLeast(1L)
        var dragValue by remember { mutableFloatStateOf(0f) }
        Row(Modifier.fillMaxWidth().padding(horizontal = Dock.edgePadding, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(formatClock(if (seeking) (dragValue * total).toLong() else position), fontSize = 11.sp, color = Color.White.copy(alpha = 0.8f))
            Slider(
                value = if (seeking) dragValue else (position.toFloat() / total).coerceIn(0f, 1f),
                onValueChange = { seeking = true; dragValue = it },
                onValueChangeFinished = { player?.seekTo((dragValue * total).toLong()); position = (dragValue * total).toLong(); seeking = false },
                colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.White, inactiveTrackColor = Color.White.copy(alpha = 0.3f)),
                modifier = Modifier.weight(1f),
            )
            Text(formatClock(duration), fontSize = 11.sp, color = Color.White.copy(alpha = 0.8f))
        }
    }

    // MARK: Actions (optimistic like iOS, rolled back on failure)

    /** iOS `.onChange(of: tagEditorImage?.id)`: nobody wants a clip looping with sound behind the picker. */
    private fun openTagEditor(image: StashImage) {
        wasPlayingBeforeTagEditor = isPlaying
        isPlaying = false
        tagEditorImage = image
    }

    private fun closeTagEditor() {
        tagEditorImage = null
        if (wasPlayingBeforeTagEditor) { wasPlayingBeforeTagEditor = false; isPlaying = true }
    }

    /** Like the tag editor: slideshow / clip pause while the picker is open, resume on close. */
    private fun openPerformerEditor(image: StashImage) {
        if (image.performers == null) return
        wasPlayingBeforeTagEditor = isPlaying
        isPlaying = false
        performerEditorImage = image
    }

    private fun closePerformerEditor() {
        performerEditorImage = null
        if (wasPlayingBeforeTagEditor) { wasPlayingBeforeTagEditor = false; isPlaying = true }
    }

    private fun replace(id: String, transform: (StashImage) -> StashImage) {
        val i = items.indexOfFirst { it.id == id }
        if (i >= 0) items[i] = transform(items[i])
    }

    private suspend fun changeOCounter(id: String, mutation: OCounterMutation) {
        val original = items.firstOrNull { it.id == id }?.oCounter ?: 0
        val optimistic = when (mutation) {
            OCounterMutation.Increment -> original + 1
            OCounterMutation.Decrement -> (original - 1).coerceAtLeast(0)
            OCounterMutation.Reset -> 0
        }
        replace(id) { it.copy(oCounter = optimistic) }
        val result = DetailRepository.imageOCounter(id, mutation)
        replace(id) { it.copy(oCounter = result ?: original) }
        if (result == null) detailToast(tr(R.string.error_update_o_count))
    }

    private suspend fun setRating(id: String, rating: Int) {
        val original = items.firstOrNull { it.id == id }?.rating100
        val value = rating.takeIf { it > 0 }
        replace(id) { it.copy(rating100 = value) }
        if (!DetailRepository.setImageRating(id, value)) {
            replace(id) { it.copy(rating100 = original) }
            detailToast(tr(R.string.error_save_rating))
        }
    }

    private suspend fun removeTag(image: StashImage, tag: IdName) {
        val remaining = image.tags.orEmpty().filter { it.id != tag.id }
        if (DetailRepository.setImageTags(image.id, remaining.map { it.id })) {
            replace(image.id) { it.copy(tags = remaining) }
            detailToast(tr(R.string.removed_arg, tag.name))
        } else detailToast(tr(R.string.error_remove_tag))
    }

    private suspend fun deleteCurrent(pager: PagerState) {
        val index = pager.currentPage
        val image = items.getOrNull(index) ?: return
        if (!DetailRepository.deleteImage(image.id)) {
            detailToast(tr(R.string.error_delete_image))
            return
        }
        detailToast(tr(R.string.image_deleted))
        items.removeAll { it.id == image.id }
        // An emptied list pops via the `items.isEmpty()` branch in Content.
        if (items.isNotEmpty() && index >= items.size - 1) onLoadMore?.invoke()
    }

    private suspend fun setPerformerImage(performer: IdName) {
        val image = current ?: return
        val ext = DetailFormatting.fileExtension(image)
        val url = if (ext in listOf("JPG", "JPEG", "PNG", "WEBP")) image.imageURL else image.thumbnailURL
        if (url == null) return
        val updated = DetailRepository.setPerformerImage(performer.id, url)
        if (updated != null) {
            // iOS: `invalidatePerformerProfileImage` + `PerformerImageUpdated` — every list,
            // header and card showing this performer reloads its image.
            de.letzgo.stashy.data.ImageRefresh.performerImageChanged(performer.id, updated.imagePath)
            detailToast(tr(R.string.performer_image_updated))
        } else detailToast(tr(R.string.error_update_performer_image))
    }

    private suspend fun setGalleryCover(gallery: IdName) {
        val image = current ?: return
        val cover = de.letzgo.stashy.data.GalleryCover(image.id, image.paths)
        // An older Stash (before 0.28) answers with an error: show it, change nothing.
        val result = runCatching { DetailRepository.setGalleryCover(gallery.id, image.id, cover) }
        if (result.getOrDefault(false)) detailToast(tr(R.string.gallery_cover_updated))
        else detailToast(result.exceptionOrNull()?.message?.takeIf { it.isNotBlank() } ?: tr(R.string.error_update_gallery_cover))
    }

    /** iOS `shareCurrentImage` — downloads the original and hands it to the share sheet. */
    private suspend fun share(context: Context, image: StashImage) {
        val url = image.imageURL ?: return
        val file = withContext(Dispatchers.IO) {
            runCatching {
                Net.client.newCall(Request.Builder().url(url).build()).await().use { r ->
                    if (!r.isSuccessful) return@runCatching null
                    val type = r.header("Content-Type") ?: ""
                    val isVideo = type.contains("video") || url.lowercase().contains(".mp4")
                    val ext = if (isVideo) "mp4" else (DetailFormatting.fileExtension(image)?.lowercase() ?: "jpg")
                    val dir = File(context.cacheDir, "share").apply { mkdirs() }
                    File(dir, "image-${image.id}.$ext").also { f -> r.body?.byteStream()?.use { input -> f.outputStream().use { input.copyTo(it) } } } to
                        (if (isVideo) "video/mp4" else type.ifEmpty { "image/*" })
                }
            }.getOrNull()
        } ?: return
        val uri = FileProvider.getUriForFile(context, context.packageName + ".detailshare", file.first)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = file.second
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private companion object {
        /** iOS `ScenePlayerMute.initialValue`. */
        fun initialMute(): Boolean = de.letzgo.stashy.ui.player.PlayerMute.initialValue()
    }
}

/** `m:ss` / `h:mm:ss` for the scrubber labels. */
internal fun formatClock(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
}

/**
 * Pinch / double-tap zoom container (iOS `ZoomableScrollView`). Single-finger drags pass
 * through to the pager while not zoomed; [onTap] toggles the chrome.
 */
@Composable
internal fun ZoomableBox(
    onTap: () -> Unit,
    onZoomChange: (Boolean) -> Unit,
    zoomEnabled: Boolean = true,
    /** iOS `onLongPress(pressing)`: true on hold, false on release (video 2×). */
    onHold: ((Boolean) -> Unit)? = null,
    /** iOS `onDoubleTap(location)` → skip; returns whether it handled the tap (outer thirds of a video). */
    onDoubleTapAt: ((x: Float, width: Float) -> Boolean)? = null,
    /**
     * iOS `onContentTap`: called first with the tap in the content's own coordinates (zoom and
     * pan taken out), the content's size and the tap's height on the screen (0 top … 1 bottom);
     * returning true claims the tap, so [onTap] is not called.
     */
    onTapAt: ((point: Offset, size: androidx.compose.ui.geometry.Size, viewportY: Float) -> Boolean)? = null,
    content: @Composable () -> Unit,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val currentOnTapAt by androidx.compose.runtime.rememberUpdatedState(onTapAt)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        fun clamp(o: Offset, s: Float): Offset {
            val maxX = (w * (s - 1f)) / 2f
            val maxY = (h * (s - 1f)) / 2f
            return Offset(o.x.coerceIn(-maxX, maxX), o.y.coerceIn(-maxY, maxY))
        }
        Box(
            Modifier.fillMaxSize()
                .pointerInput(zoomEnabled, onHold != null, onDoubleTapAt != null) {
                    var holding = false
                    detectTapGestures(
                        onTap = { tap ->
                            // Undo the layer's scale (around the centre) and translation.
                            val point = Offset((tap.x - w / 2f - offset.x) / scale + w / 2f, (tap.y - h / 2f - offset.y) / scale + h / 2f)
                            val claimed = currentOnTapAt?.invoke(point, androidx.compose.ui.geometry.Size(w, h), if (h > 0f) tap.y / h else 0f) == true
                            if (!claimed) onTap()
                        },
                        onLongPress = if (onHold == null) null else { _ -> holding = true; onHold(true) },
                        onPress = {
                            tryAwaitRelease()
                            if (holding) { holding = false; onHold?.invoke(false) }
                        },
                        onDoubleTap = { tap ->
                            if (onDoubleTapAt?.invoke(tap.x, w) == true) return@detectTapGestures
                            if (!zoomEnabled) return@detectTapGestures
                            if (scale > 1f) { scale = 1f; offset = Offset.Zero; onZoomChange(false) }
                            else {
                                scale = 2.5f
                                offset = clamp(Offset((w / 2f - tap.x) * 1.5f, (h / 2f - tap.y) * 1.5f), scale)
                                onZoomChange(true)
                            }
                        },
                    )
                }
                .pointerInput(zoomEnabled) {
                    if (!zoomEnabled) return@pointerInput
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        do {
                            val event = awaitPointerEvent()
                            if (event.changes.size > 1 || scale > 1f) {
                                val zoom = event.calculateZoom()
                                val pan = event.calculatePan()
                                scale = (scale * zoom).coerceIn(1f, 5f)
                                offset = clamp(offset + pan, scale)
                                event.changes.forEach { if (it.positionChanged()) it.consume() }
                                onZoomChange(scale > 1f)
                            }
                        } while (event.changes.any { it.pressed })
                        if (scale <= 1.02f) { scale = 1f; offset = Offset.Zero; onZoomChange(false) }
                    }
                }
                .graphicsLayer(scaleX = scale, scaleY = scale, translationX = offset.x, translationY = offset.y),
        ) { content() }
    }
}
