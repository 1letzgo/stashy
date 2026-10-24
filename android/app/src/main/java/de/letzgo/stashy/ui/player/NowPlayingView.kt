package de.letzgo.stashy.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.AlertDialog
import de.letzgo.stashy.ui.StashyColors
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.WatchlistStore
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens

/**
 * iOS: `NowPlayingView` — the mini player's own full view: 16:9 video (tap toggles play), title,
 * performers · studio, scrubber, transport (−10, play/pause, +10, next in watchlist), the
 * watchlist toggle and the watchlist itself (tap plays in place, Edit reorders / removes).
 * Deliberately not the scene page — that one stays reachable through [onOpenDetails].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(onOpenDetails: (Scene) -> Unit) {
    if (!MiniPlayerStore.showsNowPlaying) return
    val session = MiniPlayerStore.session
    LaunchedEffect(session == null) { if (session == null) MiniPlayerStore.showsNowPlaying = false }
    if (session == null) return
    val p = Theme.palette
    ModalBottomSheet(
        onDismissRequest = { MiniPlayerStore.showsNowPlaying = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = p.background,
    ) {
        NowPlayingContent(session, onOpenDetails)
    }
}

@Composable
private fun NowPlayingContent(session: MiniPlayerStore.Session, onOpenDetails: (Scene) -> Unit) {
    val p = Theme.palette
    val player = session.player
    val scene = session.scene
    val watchlist = WatchlistStore.all
    var editing by remember { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text("Reset watchlist?") },
        text = { Text("All scenes are removed from the watchlist. The playing scene keeps playing.") },
        confirmButton = {
            TextButton({ confirmReset = false; editing = false; WatchlistStore.clear() }) {
                Text("Reset", color = StashyColors.systemRed)
            }
        },
        dismissButton = { TextButton({ confirmReset = false }) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
    )
    Column(Modifier.fillMaxSize().navigationBarsPadding()) {
        // Toolbar: minimize · Details.
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { MiniPlayerStore.showsNowPlaying = false }) {
                Icon(SF.chevronDown, "Minimize", tint = p.text)
            }
            Box(Modifier.weight(1f))
            TextButton(onClick = { onOpenDetails(scene) }) {
                Text("Details", color = Appearance.tint, fontWeight = FontWeight.SemiBold)
            }
        }
        LazyColumn(Modifier.fillMaxSize()) {
            item(key = "player") { PlayerBlock(session) }
            item(key = "header") {
                Row(Modifier.fillMaxWidth().padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    NativeSectionHeader("Watchlist", Modifier.weight(1f))
                    if (watchlist.isNotEmpty()) TextButton(onClick = { confirmReset = true }) {
                        Text("Reset", color = StashyColors.systemRed, fontWeight = FontWeight.SemiBold)
                    }
                    if (watchlist.isNotEmpty()) TextButton(onClick = { editing = !editing }) {
                        Text(if (editing) "Done" else "Edit", color = Appearance.tint, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            if (watchlist.isEmpty()) item(key = "empty") {
                Text(
                    "Add scenes with the watchlist button on a scene. They play here one after another.",
                    Modifier.padding(horizontal = 16.dp, vertical = 8.dp), fontSize = 13.sp, color = p.secondaryText,
                )
            } else itemsIndexed(watchlist, key = { _, s -> "w-${s.id}" }) { index, entry ->
                WatchlistRow(
                    entry, isCurrent = entry.id == scene.id, editing = editing,
                    canMoveUp = index > 0, canMoveDown = index < watchlist.lastIndex,
                    onPlay = { MiniPlayerStore.play(entry) },
                    onMoveUp = { WatchlistStore.move(index, index - 1) },
                    onMoveDown = { WatchlistStore.move(index, index + 1) },
                    onDelete = { WatchlistStore.remove(entry.id) },
                )
            }
            item(key = "bottom") { Box(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun PlayerBlock(session: MiniPlayerStore.Session) {
    val p = Theme.palette
    val player = session.player
    val scene = session.scene
    var scrubTime by remember { mutableStateOf<Double?>(null) }
    val playing = player.isPlaying || (player.playWhenReady && !player.didEnd)
    val hasNext = MiniPlayerStore.hasNext
    val subtitle = listOf(
        scene.performers.take(3).joinToString(", ") { it.name },
        scene.studio?.name.orEmpty(),
    ).filter { it.isNotBlank() }.joinToString(" · ")
    Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        VideoSurface(
            player,
            Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(Tokens.Radius.card))
                .clickable { MiniPlayerStore.togglePlayPause() },
        )
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(scene.displayTitle, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) Text(subtitle, fontSize = 14.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        // Scrubber (the player's own TimeBar is drawn for a dark video backdrop).
        val duration = maxOf(player.duration, 0.0)
        val shown = scrubTime ?: player.currentTime
        Column {
            Slider(
                value = if (duration > 0) (shown / duration).coerceIn(0.0, 1.0).toFloat() else 0f,
                onValueChange = { if (duration > 0) scrubTime = it * duration },
                onValueChangeFinished = { scrubTime?.let { MiniPlayerStore.seekTo(it) }; scrubTime = null },
                enabled = duration > 0,
                colors = SliderDefaults.colors(thumbColor = Appearance.tint, activeTrackColor = Appearance.tint, inactiveTrackColor = p.secondaryText.copy(alpha = 0.3f)),
            )
            Row(Modifier.fillMaxWidth()) {
                Text(PlaybackFormat.time(shown), fontSize = 12.sp, color = p.secondaryText)
                Box(Modifier.weight(1f))
                Text("-" + PlaybackFormat.time(maxOf(0.0, duration - shown)), fontSize = 12.sp, color = p.secondaryText)
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TransportButton(Icons.Filled.Replay10, "Back 10 seconds") { MiniPlayerStore.seekBy(-10.0) }
            TransportButton(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (playing) "Pause" else "Play", size = 40) { MiniPlayerStore.togglePlayPause() }
            TransportButton(Icons.Filled.Forward10, "Forward 10 seconds") { MiniPlayerStore.seekBy(10.0) }
            TransportButton(Icons.Filled.SkipNext, "Next in watchlist", enabled = hasNext) { MiniPlayerStore.playNext() }
        }
        WatchlistToggle(scene)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TransportButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    size: Int = 28,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Box(
        Modifier.weight(1f).heightIn(min = 48.dp).clickable(enabled = enabled, onClick = onClick).alpha(if (enabled) 1f else 0.35f),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, label, tint = Theme.palette.text, modifier = Modifier.size(size.dp))
    }
}

/** iOS: `WatchlistToggleRow` — "Add to watchlist" / "On watchlist" pill. */
@Composable
private fun WatchlistToggle(scene: Scene) {
    val p = Theme.palette
    val listed = WatchlistStore.contains(scene.id)
    val color = if (listed) Appearance.tint else p.text
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(
            Modifier.height(34.dp).clip(RoundedCornerShape(50)).background(p.secondaryBackground)
                .clickable { WatchlistStore.toggle(scene) }.padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(if (listed) WatchlistIcons.listed else WatchlistIcons.add, null, tint = color, modifier = Modifier.size(18.dp))
            Text(if (listed) "On watchlist" else "Add to watchlist", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = color)
        }
    }
}

@Composable
private fun WatchlistRow(
    scene: Scene,
    isCurrent: Boolean,
    editing: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onPlay: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onDelete: () -> Unit,
) {
    val p = Theme.palette
    val performers = scene.performers.take(2).joinToString(", ") { it.name }
    Row(
        Modifier.fillMaxWidth().clickable(enabled = !editing, onClick = onPlay).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(width = 80.dp, height = 45.dp).clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) {
            AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            if (isCurrent) Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).padding(6.dp)) {
                Icon(SF.speakerWave2Fill, "Now playing", tint = Color.White, modifier = Modifier.size(14.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(scene.displayTitle, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (isCurrent) Appearance.tint else p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (performers.isNotEmpty()) Text(performers, fontSize = 12.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (editing) {
            IconButton(onClick = onMoveUp, enabled = canMoveUp, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.KeyboardArrowUp, "Move up", tint = if (canMoveUp) p.text else p.secondaryText.copy(alpha = 0.4f))
            }
            IconButton(onClick = onMoveDown, enabled = canMoveDown, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.KeyboardArrowDown, "Move down", tint = if (canMoveDown) p.text else p.secondaryText.copy(alpha = 0.4f))
            }
            IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Delete, "Remove from watchlist", tint = de.letzgo.stashy.ui.StashyColors.systemRed)
            }
        }
    }
}
