package de.letzgo.stashy.ui.tools.downloads

import android.net.Uri
import android.view.ViewGroup
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.VerticalAlignBottom
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.DownloadedGallery
import de.letzgo.stashy.data.DownloadedGalleryImage
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeMediaLabelBox
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.TopBarAction
import de.letzgo.stashy.ui.TopBarOverflowMenu
import de.letzgo.stashy.ui.nativeTopBarPadding
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsTokens
import java.io.File

private fun fileUrl(file: File) = "file://${file.absolutePath}"

/**
 * iOS: `DownloadedGalleryDetailView` — offline grid of a downloaded gallery / tag / image set,
 * read straight from disk. Chrome: Back · title · Sync newest · Sync newest N · Delete
 * (Cancel while a sync runs).
 */
class DownloadedGalleryScreen(val entryId: String) : Screen {
    override val key = "downloaded-gallery-$entryId"

    @Composable
    override fun Content() {
        val p = Theme.palette
        val entry = Downloads.galleryDownloads.firstOrNull { it.id == entryId }
        val isSyncing = Downloads.activeDownloads[entryId] != null
        var confirmDelete by remember { mutableStateOf(false) }
        val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
        LaunchedEffect(Unit) { Downloads.backfillMissingImageTitles() }

        Box(Modifier.fillMaxSize().background(p.background)) {
            if (entry != null) {
                val columns = downloadsGridColumns(ideal = 180.dp, minimum = 2, maximum = 6)
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding,
                        top = nativeTopBarPadding() + 16.dp, bottom = bottomInset + 24.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    itemsIndexed(entry.images, key = { _, image -> image.id }) { index, image ->
                        DownloadedImageCell(image) { Nav.push(DownloadedImageViewerScreen(entryId, index)) }
                    }
                }
            } else {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Icon(Icons.Outlined.PhotoLibrary, null, tint = p.secondaryText, modifier = Modifier.size(40.dp))
                    Text("Download no longer available", style = IosTypography.subheadline, color = p.secondaryText)
                }
            }

            // Top chrome: Material app bar — back · title · Cancel (while syncing) or Sync ·
            // "⋮" with Sync newest N and Delete.
            NativeTopBar(entry?.displayTitle ?: "Download") {
                if (isSyncing) {
                    TopBarAction(Icons.Outlined.StopCircle, "Cancel download", tint = StashyColors.systemRed) {
                        Downloads.cancelGalleryDownload(entryId)
                    }
                } else if (entry != null) {
                    if (!entry.isSingleImage) TopBarAction(Icons.Filled.Sync, "Sync newest") { sync(entry, null) }
                    TopBarOverflowMenu { dismiss ->
                        val batch = Downloads.galleryNewestBatchSize
                        if (!entry.isSingleImage && showsSyncNewestBatch(entry.serverImageCount, batch)) {
                            OverflowItem("Sync newest $batch", Icons.Filled.VerticalAlignBottom, dismiss) { sync(entry, batch) }
                        }
                        OverflowItem("Delete", SF.trash, dismiss, color = StashyColors.systemRed) { confirmDelete = true }
                    }
                }
            }
        }

        if (confirmDelete) {
            StashyAlert(
                title = "Delete this download?",
                message = "The downloaded images are removed from this device.",
                onDismiss = { confirmDelete = false },
                confirmLabel = "Delete", destructive = true, dismissLabel = "Cancel",
                onConfirm = {
                    confirmDelete = false
                    Downloads.deleteGalleryDownload(entryId)
                    Nav.pop()
                },
            )
        }
    }

    private fun sync(entry: DownloadedGallery, limit: Int?) {
        if (entry.resolvedKind == DownloadedGallery.Kind.Tag) Downloads.syncTagImages(entryId, limit) else Downloads.syncGallery(entryId, limit)
    }
}

/** Same construction as `GalleryCardView`: square image, 40 % gradient, title in headline. */
@Composable
private fun DownloadedImageCell(image: DownloadedGalleryImage, onClick: () -> Unit) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(
        Modifier.fillMaxWidth().aspectRatio(1f).cardShadow(shape).clip(shape).background(p.secondaryBackground).noRippleClickable(onClick),
    ) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(if (image.isVideo) SF.film else SF.photo, null, tint = p.secondaryText, modifier = Modifier.size(40.dp))
        }
        AsyncImage(fileUrl(Downloads.thumbnailFile(image)), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().fillMaxHeight(0.4f)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))),
        )
        if (image.isVideo) {
            NativeMediaLabelBox(Modifier.align(Alignment.TopEnd).padding(8.dp)) {
                Icon(Icons.Filled.PlayCircle, "Video", tint = Theme.palette.text, modifier = Modifier.size(14.dp))
            }
        }
        Text(
            image.title?.trim()?.takeIf { it.isNotEmpty() } ?: "Untitled",
            style = IosTypography.headline.copy(fontWeight = FontWeight.Medium), color = Color.White,
            maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
        )
    }
}

/**
 * iOS: `DownloadedGalleryFullScreenView` — offline counterpart of the image viewer: vertical
 * paging, tap toggles the chrome, Back · "i / n" on top, performer · title, mute / play and the
 * tag row at the bottom. Videos loop with Media3; only the visible page plays.
 */
class DownloadedImageViewerScreen(val entryId: String, val startIndex: Int) : Screen {
    override val key = "downloaded-viewer-$entryId-$startIndex"
    override val hidesTabBar = true

    @Composable
    override fun Content() {
        val images = Downloads.galleryDownloads.firstOrNull { it.id == entryId }?.images.orEmpty()
        val pager = rememberPagerState(initialPage = startIndex.coerceIn(0, (images.size - 1).coerceAtLeast(0))) { images.size }
        var showUI by remember { mutableStateOf(true) }
        var isMuted by remember { mutableStateOf(Prefs.bool(MUTE_KEY, false)) }
        var isPlaying by remember { mutableStateOf(true) }
        LaunchedEffect(pager.currentPage) { isPlaying = true }

        Box(Modifier.fillMaxSize().background(Color.Black)) {
            VerticalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { images.getOrNull(it)?.id ?: it }) { page ->
                val image = images[page]
                Box(Modifier.fillMaxSize().noRippleClickable { showUI = !showUI }, contentAlignment = Alignment.Center) {
                    val file = Downloads.localFile(image)
                    when {
                        !file.exists() -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(SF.exclamationTriangle, null, tint = Color.White)
                            Text("File missing", color = Color.White)
                        }
                        image.isVideo -> OfflineLoopingVideo(file, active = page == pager.currentPage && isPlaying, muted = isMuted)
                        else -> AsyncImage(fileUrl(file), image.title, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                    }
                }
            }

            AnimatedVisibility(showUI, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopStart)) {
                NativeTopBar(if (images.isNotEmpty()) "${pager.currentPage + 1} / ${images.size}" else "", transparent = true)
            }

            images.getOrNull(pager.currentPage)?.let { current ->
                AnimatedVisibility(showUI, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.BottomStart)) {
                    ViewerInfoOverlay(
                        image = current,
                        isMuted = isMuted,
                        isPlaying = isPlaying,
                        onToggleMute = { isMuted = !isMuted; Prefs.setBool(MUTE_KEY, isMuted) },
                        onTogglePlay = { isPlaying = !isPlaying },
                    )
                }
            }
        }
    }

    private companion object {
        /** Android-local mute preference of the offline viewer. */
        const val MUTE_KEY = "downloads_viewer_muted"
    }
}

/** Performer · title, mute / play stacked on the trailing edge, `#tag` row — fed from the stored metadata. */
@Composable
private fun ViewerInfoOverlay(
    image: DownloadedGalleryImage,
    isMuted: Boolean,
    isPlaying: Boolean,
    onToggleMute: () -> Unit,
    onTogglePlay: () -> Unit,
) {
    val performers = image.performerNames.orEmpty()
    val tags = image.tagNames.orEmpty()
    val title = image.title?.trim().orEmpty()
    val tint = Appearance.tint
    Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 12.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                performers.firstOrNull()?.let { performer ->
                    // No cached profile picture offline — initials stand in.
                    Box(
                        Modifier.size(DownloadsCircleSize).clip(CircleShape).background(tint.copy(alpha = 0.2f)).border(2.dp, tint, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(initials(performer), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.9f))
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    performers.firstOrNull()?.let { performer ->
                        Text(performer, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1)
                        if (title.isNotEmpty()) Text("-", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.6f))
                    }
                    if (title.isNotEmpty()) {
                        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.85f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val enabled = image.isVideo
                // Material tonal icon buttons on a dark scrim (they sit on the picture / video).
                val colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = Color.Black.copy(alpha = 0.45f), contentColor = Color.White,
                    disabledContainerColor = Color.Black.copy(alpha = 0.45f), disabledContentColor = Color.White.copy(alpha = 0.35f),
                )
                FilledTonalIconButton(onToggleMute, Modifier.size(DownloadsCircleSize), enabled = enabled, colors = colors) {
                    Icon(if (isMuted) SF.speakerSlash else SF.speaker, if (isMuted) "Unmute" else "Mute", Modifier.size(18.dp))
                }
                FilledTonalIconButton(onTogglePlay, Modifier.size(DownloadsCircleSize), enabled = enabled, colors = colors) {
                    Icon(if (isPlaying) SF.pauseFill else SF.playFill, if (isPlaying) "Pause" else "Play", Modifier.size(18.dp))
                }
            }
        }
        if (tags.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().padding(top = 6.dp).height(24.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                tags.forEach { tag ->
                    Text(
                        "#$tag", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.8f),
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.3f))
                            .border(0.5.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(50))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
            }
        }
    }
}

private fun initials(name: String): String {
    val letters = name.split(" ").filter { it.isNotEmpty() }.take(2).map { it.first().toString() }
    return if (letters.isEmpty()) "?" else letters.joinToString("").uppercase()
}

/** iOS: `DownloadedGalleryItemView` video branch — local file, looping, aspect fit, no auth. */
@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun OfflineLoopingVideo(file: File, active: Boolean, muted: Boolean) {
    val context = LocalContext.current
    val player = remember(file.path) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
            repeatMode = Player.REPEAT_MODE_ONE
            prepare()
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(active) { player.playWhenReady = active }
    LaunchedEffect(muted) { player.volume = if (muted) 0f else 1f }
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                useController = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShutterBackgroundColor(android.graphics.Color.BLACK)
                this.player = player
            }
        },
        modifier = Modifier.fillMaxSize(),
    )
}
