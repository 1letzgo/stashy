package de.letzgo.stashy.ui.scene

import de.letzgo.stashy.ui.uniqueItems
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ripple
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.player.PlaybackFormat
import de.letzgo.stashy.ui.player.PlayerIcons
import de.letzgo.stashy.ui.player.PlayerMenuItem
import de.letzgo.stashy.ui.player.PlayerWindow
import de.letzgo.stashy.ui.player.PreviewSurface
import de.letzgo.stashy.ui.player.ScenePlayerSurface
import de.letzgo.stashy.ui.player.rememberPreviewPlayer
import de.letzgo.stashy.ui.stashyGlass
import de.letzgo.stashy.ui.components.InfoLabel
import de.letzgo.stashy.ui.components.InfoLabelSurface
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val topRounded = RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)

/**
 * iOS: `SceneVideoPlayerCard` — cover with Play / "Resume from …" + "Start from beginning",
 * quality tag and resume bar; long-press plays `paths.preview`; once started the inline
 * [ScenePlayerSurface]; below it the horizontal marker strip.
 */
@Composable
fun SceneVideoPlayerCard(model: SceneDetailModel, extraMenuItems: () -> List<PlayerMenuItem>) {
    val ai = model.aiSubtitles
    val scene = model.scene
    Column {
        val player = model.player
        when {
            model.isPlaybackStarted && player != null -> {
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(topRounded).background(Color.Black)) {
                    if (!model.isFullscreen && !PlayerWindow.isInPictureInPicture) {
                        ScenePlayerSurface(
                            player = player,
                            posterURL = scene.thumbnailURL,
                            isMuted = model.isMuted,
                            onMutedChange = model::updateMuted,
                            onSeek = model::seekTo,
                            modifier = Modifier.fillMaxSize(),
                            onToggleFullscreen = { model.isFullscreen = true },
                            markers = scene.timeBarMarkers,
                            onAddMarker = model::beginAddMarker,
                            extraMenuItems = extraMenuItems,
                            subtitleMenuExtras = ai::menuItems,
                            onHostSubtitleOff = ai::turnOffAISubtitles,
                            onOptionsMenuClosed = ai::optionsMenuClosed,
                            scrubSprites = model.scrubSprites,
                            onPictureInPicture = { PlayerWindow.enterPictureInPicture(player.videoSize) },
                        )
                    }
                }
            }
            scene.originalVideoURL != null -> CoverWithOverlay(model)
            else -> Box(
                Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(topRounded).background(Color.Gray.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(PlayerIcons.film, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(34.dp))
                    Text("Video not available", color = Theme.palette.secondaryText)
                }
            }
        }
        MarkerStrip(scene.sceneMarkers.orEmpty(), playing = model.isPlaybackStarted && player != null, onSeek = model::seekTo)
    }
}

@Composable
private fun CoverWithOverlay(model: SceneDetailModel) {
    val scene = model.scene
    val preview = rememberPreviewPlayer()
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<Job?>(null) }
    val tint = Appearance.tint
    Box(
        Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(topRounded).background(Theme.palette.secondaryBackground)
            .pointerInput(scene.previewURL) {
                detectTapGestures(onPress = {
                    // The preview waits until the press really holds (0.15 s), so a tap on Play stays a tap.
                    pending?.cancel()
                    pending = scope.launch {
                        delay(150)
                        scene.previewURL?.let { preview.start(it); model.isPreviewing = true }
                    }
                    tryAwaitRelease()
                    pending?.cancel()
                    if (model.isPreviewing) { model.isPreviewing = false; preview.stop(release = true) }
                })
            },
    ) {
        val thumb = scene.thumbnailURL
        if (thumb != null) AsyncImage(thumb, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.9f)), contentAlignment = Alignment.Center) {
            Icon(PlayerIcons.film, null, tint = Color.Gray.copy(alpha = 0.5f), modifier = Modifier.size(50.dp))
        }
        if (model.isPreviewing) PreviewSurface(preview, Modifier.fillMaxSize())
        if (!model.isPreviewing) {
            val resume = scene.resumeTime ?: 0.0
            Box(Modifier.align(Alignment.Center)) {
                if (resume > 0) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Row(
                            Modifier.shadow(5.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50)).background(tint)
                                .clickable { model.startPlayback(true) }.padding(horizontal = 20.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(PlayerIcons.resume, null, tint = Color.White, modifier = Modifier.size(20.dp))
                            Text("Resume from ${PlaybackFormat.time(resume)}", color = Color.White, style = IosTypography.body.copy(fontWeight = FontWeight.Bold))
                        }
                        Text(
                            "Start from beginning",
                            Modifier.shadow(3.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50)).background(tint)
                                .clickable { model.startPlayback(false) }.padding(horizontal = 12.dp, vertical = 6.dp),
                            color = Color.White, style = IosTypography.caption.copy(fontWeight = FontWeight.Medium),
                        )
                    }
                } else {
                    Box(
                        Modifier.size(70.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f))
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { model.startPlayback(false) },
                        contentAlignment = Alignment.Center,
                    ) { Icon(PlayerIcons.play, "Play", tint = Color.White, modifier = Modifier.size(40.dp).padding(start = 2.dp)) }
                }
            }
            PlaybackFormat.resolutionLabel(scene.files?.firstOrNull()?.height)?.let { label ->
                Row(
                    Modifier.align(Alignment.TopEnd).padding(10.dp).height(24.dp).stashyGlass(RoundedCornerShape(50)).padding(horizontal = 9.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(PlayerIcons.video, null, tint = Color.White, modifier = Modifier.size(11.dp))
                    Text(label, color = Color.White, style = IosTypography.caption2.copy(fontWeight = FontWeight.Bold))
                }
            }
            val duration = scene.sceneDuration
            if (resume > 0 && duration != null && duration > 0) {
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.25f)))
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth((resume / duration).toFloat().coerceIn(0f, 1f)).height(4.dp).background(tint))
            }
        }
    }
}

/** iOS: `markerScrollView` — 80×45 thumbnails with the time, title below; tap seeks. */
@Composable
private fun MarkerStrip(markers: List<SceneMarker>, playing: Boolean, onSeek: (Double) -> Unit) {
    if (markers.isEmpty()) return
    val p = Theme.palette
    LazyRow(
        Modifier.fillMaxWidth().padding(top = if (playing) 10.dp else 8.dp, bottom = 12.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        uniqueItems(markers.sortedBy { it.seconds }, { it.id }) { marker ->
            Column(Modifier.width(80.dp).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onSeek(marker.seconds) }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(80.dp, 45.dp).clip(RoundedCornerShape(4.dp)).background(Color.Gray.copy(alpha = 0.2f))) {
                    val url = Net.signed(marker.screenshot)
                    if (url != null) AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Icon(PlayerIcons.bookmark, null, tint = p.secondaryText, modifier = Modifier.align(Alignment.Center))
                    Text(
                        PlaybackFormat.time(marker.seconds),
                        Modifier.align(Alignment.BottomEnd).padding(2.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = 4.dp, vertical = 1.dp),
                        style = IosTypography.caption2.copy(fontSize = 8.sp, fontWeight = FontWeight.Bold), color = Color.White,
                    )
                }
                Text(
                    marker.title?.takeIf { it.isNotEmpty() } ?: "Marker at ${PlaybackFormat.time(marker.seconds)}",
                    style = IosTypography.caption2.copy(fontSize = 10.sp, fontWeight = FontWeight.Medium), color = p.text,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * iOS: `SceneDetailMetadataCard` — title (+ edit pencil), collapsible details, and the pill row:
 * date · duration · play count · O-counter (tap +1, long-press "Remove one O" / reset) · rating.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SceneMetadataCard(model: SceneDetailModel, onEditTitle: () -> Unit) {
    val scene = model.scene
    val p = Theme.palette
    val tint = Appearance.tint
    val haptics = LocalHapticFeedback.current
    val hasMarkers = !scene.sceneMarkers.isNullOrEmpty()
    Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, bottom = 12.dp, top = if (hasMarkers) 4.dp else 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Text(scene.displayTitle, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (Appearance.isEditModeEnabled) EditCircleButton(onEditTitle)
        }
        scene.details?.takeIf { it.isNotEmpty() }?.let { details ->
            Box(Modifier.fillMaxWidth()) {
                Text(
                    details, Modifier.fillMaxWidth().padding(bottom = 20.dp), style = IosTypography.body, color = p.text.copy(alpha = 0.8f),
                    maxLines = if (model.isHeaderExpanded) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis,
                )
                ExpandChevron(model.isHeaderExpanded, Modifier.align(Alignment.BottomEnd)) { model.isHeaderExpanded = !model.isHeaderExpanded }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            scene.date?.let { InfoPill(PlayerIcons.calendar, it) }
            scene.sceneDuration?.let { InfoPill(PlayerIcons.clock, PlaybackFormat.time(it)) }
            InfoPill(PlayerIcons.playCircle, "${scene.playCount ?: 0}")
            var menu by remember { mutableStateOf(false) }
            var confirmReset by remember { mutableStateOf(false) }
            val count = scene.oCounter ?: 0
            Box {
                InfoPill(
                    oCounterIcon(Appearance.oCounterIcon, filled = true), "$count",
                    Modifier.combinedClickable(
                        interactionSource = remember { MutableInteractionSource() }, indication = ripple(),
                        onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); model.incrementO() },
                        onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true },
                    ),
                )
                DropdownMenu(menu, onDismissRequest = { menu = false }) {
                    if (count > 0) {
                        DropdownMenuItem(text = { Text("Remove one O") }, leadingIcon = { Icon(PlayerIcons.minusCircle, null) }, onClick = { menu = false; model.removeO(OCounterMutation.Decrement) })
                        if (count > 1) DropdownMenuItem(
                            text = { Text("Reset O-Counter ($count)", color = StashyColors.systemRed) },
                            leadingIcon = { Icon(PlayerIcons.reset, null, tint = StashyColors.systemRed) },
                            onClick = { menu = false; confirmReset = true },
                        )
                    } else DropdownMenuItem(text = { Text("No O recorded") }, onClick = { menu = false }, enabled = false)
                }
            }
            if (confirmReset) AlertDialog(
                onDismissRequest = { confirmReset = false },
                title = { Text("Reset O-Counter?") },
                text = { Text("All $count recorded O entries and their dates are permanently deleted on the server. This cannot be undone.") },
                confirmButton = { TextButton({ confirmReset = false; model.removeO(OCounterMutation.Reset) }) { Text("Remove all $count", color = StashyColors.systemRed) } },
                dismissButton = { TextButton({ confirmReset = false }) { Text("Cancel") } },
            )
            InfoLabelSurface(container = p.pillAccent.copy(alpha = 0.1f)) {
                StarRating(scene.rating100, size = 14.dp, spacing = 2.dp) { model.setRating(it) }
            }
        }
    }
}

/** iOS: metadata `infoPill` — Android: Material label (small-shape surface, `labelMedium`) in the pill accent. [modifier] sits inside the clip (click ripple). */
@Composable
fun InfoPill(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, modifier: Modifier = Modifier, color: Color = Theme.palette.pillAccent) {
    InfoLabel(text, Modifier.clip(MaterialTheme.shapes.small).then(modifier), icon = icon, content = color)
}

/** iOS: `StarRatingView` — 5 stars, tap the current star again to clear. */
@Composable
fun StarRating(rating100: Int?, size: androidx.compose.ui.unit.Dp, spacing: androidx.compose.ui.unit.Dp, onChange: (Int?) -> Unit) {
    val stars = rating100?.let { Math.round(it / 20.0).toInt().coerceIn(0, 5) } ?: 0
    val haptics = LocalHapticFeedback.current
    Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
        for (i in 1..5) {
            Icon(
                if (i <= stars) de.letzgo.stashy.ui.SF.starFill else de.letzgo.stashy.ui.SF.star, null,
                tint = if (i <= stars) Appearance.tint else Color.Gray.copy(alpha = 0.5f),
                modifier = Modifier.size(size).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onChange(if (i == stars) null else i * 20)
                },
            )
        }
    }
}

/** Small tinted chevron circle (expand / collapse). */
@Composable
fun ExpandChevron(expanded: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val tint = Appearance.tint
    Box(
        modifier.size(22.dp).clip(CircleShape).background(tint.copy(alpha = 0.1f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(if (expanded) PlayerIcons.chevronUp else PlayerIcons.chevronDown, null, tint = tint, modifier = Modifier.size(14.dp)) }
}

