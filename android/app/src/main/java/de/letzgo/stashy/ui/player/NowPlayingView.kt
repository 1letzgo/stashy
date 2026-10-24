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
import de.letzgo.stashy.ui.IosTypography
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
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.material.icons.filled.Business
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.scene.timeBarMarkers

/**
 * iOS: `NowPlayingView` — the mini player's own full view: 16:9 video (tap toggles play), title,
 * performers · studio, scrubber, transport (−10, play/pause, +10, next in watchlist), the
 * watchlist toggle and the watchlist itself (tap plays in place, Edit reorders / removes).
 * Deliberately not the scene page — that one stays reachable through [onOpenDetails].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
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
        NowPlayingContent(session, onOpen)
    }
}

@Composable
private fun NowPlayingContent(session: MiniPlayerStore.Session, onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
    val p = Theme.palette
    val player = session.player
    val scene = session.scene
    val watchlist = WatchlistStore.all
    val drag = remember { WatchlistDragState() }
    var confirmReset by remember { mutableStateOf(false) }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text("Reset watchlist?") },
        text = { Text("All scenes are removed from the watchlist. The playing scene keeps playing.") },
        confirmButton = {
            TextButton({ confirmReset = false; WatchlistStore.clear() }) {
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
            TextButton(onClick = { onOpen(de.letzgo.stashy.ui.scene.SceneDetailScreen(scene.id, scene, openedFromMiniPlayer = true)) }) {
                Text("Details", color = Appearance.tint, fontWeight = FontWeight.SemiBold)
            }
        }
        // The scene page's player, 8 dp side margin, fixed above the scrolling list.
        PlayerSurfaceBlock(session, Modifier.padding(start = NowPlayingMargin, end = NowPlayingMargin, top = 4.dp))
        LazyColumn(Modifier.fillMaxSize()) {
            item(key = "card") { MetadataCard(session) }
            item(key = "info") { InfoRow(session, onOpen) }
            item(key = "header") {
                // Plain list header on the sheet background: "Watchlist" + red Reset.
                Row(Modifier.fillMaxWidth().padding(start = NowPlayingMargin, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Watchlist", Modifier.weight(1f), style = IosTypography.headline, color = p.text)
                    if (watchlist.isNotEmpty()) TextButton(onClick = { confirmReset = true }) {
                        Text("Reset", color = StashyColors.systemRed, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            if (watchlist.isEmpty()) item(key = "empty") {
                Text(
                    "Add scenes with the watchlist button on a scene. They play here one after another.",
                    Modifier.padding(horizontal = NowPlayingMargin, vertical = 8.dp), fontSize = 13.sp, color = p.secondaryText,
                )
            } else watchlistRows(watchlist.toList(), scene.id, drag, NowPlayingMargin) { MiniPlayerStore.play(it) }
            item(key = "bottom") { Box(Modifier.height(24.dp)) }
        }
    }
}

/** Side margin of Now Playing: player, title and watchlist rows line up on it. */
private val NowPlayingMargin = 8.dp

/** The scene page's own player surface (poster, mute, scrubber, markers, transport) as a rounded card. */
@Composable
private fun PlayerSurfaceBlock(session: MiniPlayerStore.Session, modifier: Modifier = Modifier) {
    val player = session.player
    val scene = session.scene
    val sprites = remember(scene.id) { SceneScrubSprites.create(scene.paths?.vtt, scene.paths?.sprite) }
    Box(modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(Tokens.Radius.card)).background(Color.Black)) {
        ScenePlayerSurface(
            player = player,
            posterURL = scene.thumbnailURL,
            isMuted = player.mutedState,
            onMutedChange = { player.isMuted = it },
            onSeek = { MiniPlayerStore.seekTo(it) },
            modifier = Modifier.fillMaxSize(),
            markers = scene.timeBarMarkers,
            scrubSprites = sprites,
        )
    }
}

/** Title + performers · studio, and the round "next" button when the watchlist has a next entry. */
/**
 * iOS: the scene page's `SceneDetailMetadataCard` in Now Playing — the same card (title,
 * details, date · duration · plays · O · rating) on the same rounded secondary background.
 * Rating and O edits go to the server and into a local copy of the scene, which shows them at
 * once and starts over when the bar switches scenes.
 */
@Composable
private fun MetadataCard(session: MiniPlayerStore.Session) {
    val scope = rememberCoroutineScope()
    var scene by remember(session.scene.id) { mutableStateOf(session.scene) }
    var expanded by remember(session.scene.id) { mutableStateOf(false) }
    de.letzgo.stashy.ui.scene.SceneCardContainer(Modifier.fillMaxWidth().padding(start = NowPlayingMargin, end = NowPlayingMargin, top = 12.dp)) {
        de.letzgo.stashy.ui.scene.SceneMetadataCardContent(
            scene = scene,
            isExpanded = expanded,
            onToggleExpanded = { expanded = !expanded },
            onEditTitle = null,
            onIncrementO = {
                val id = scene.id
                scope.launch {
                    val count = runCatching { SceneEditing.mutateOCounter(id, OCounterMutation.Increment) }.getOrNull() ?: return@launch
                    if (scene.id == id) scene = scene.copy(oCounter = count)
                    SceneEvents.post(SceneEvent.OCounterUpdated(id, count))
                }
            },
            onRemoveO = { mutation ->
                val original = scene.oCounter ?: 0
                val id = scene.id
                scene = scene.copy(oCounter = if (mutation == OCounterMutation.Reset) 0 else maxOf(0, original - 1))
                scope.launch {
                    val count = runCatching { SceneEditing.mutateOCounter(id, mutation) }.getOrNull()
                    if (scene.id != id) return@launch
                    if (count != null) {
                        scene = scene.copy(oCounter = count)
                        SceneEvents.post(SceneEvent.OCounterUpdated(id, count))
                    } else scene = scene.copy(oCounter = original)
                }
            },
            onSetRating = { rating ->
                val original = scene
                val rated = scene.copy(rating100 = rating)
                scene = rated
                scope.launch {
                    if (runCatching { SceneEditing.updateRating(rated.id, rating) }.isSuccess) SceneEvents.post(SceneEvent.Updated(rated))
                    else if (scene.id == rated.id) scene = original
                }
            },
        )
    }
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun InfoRow(session: MiniPlayerStore.Session, onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
    val p = Theme.palette
    val scene = session.scene
    val performers = scene.performers.filter { it.name.isNotBlank() }.take(4)
    val studio = scene.studio?.takeIf { it.name.isNotBlank() }
    Row(
        Modifier.fillMaxWidth().padding(start = NowPlayingMargin, end = NowPlayingMargin, top = 12.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            // Performers and studio are links: the sheet closes and their page opens.
            if (performers.isNotEmpty() || studio != null) androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                performers.forEach { performer ->
                    LinkPill(SF.personFill, performer.name) { onOpen(de.letzgo.stashy.ui.detail.PerformerDetailScreen(performer.id, performer)) }
                }
                if (studio != null) {
                    LinkPill(Icons.Filled.Business, studio.name) { onOpen(de.letzgo.stashy.ui.detail.StudioDetailScreen(studio.id, studio)) }
                }
            }
        }
        if (MiniPlayerStore.hasNext) CircleAction(Icons.Filled.SkipNext, "Next in watchlist") { MiniPlayerStore.playNext() }
    }
}

@Composable
private fun CircleAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    val p = Theme.palette
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(p.secondaryBackground).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, label, tint = p.text, modifier = Modifier.size(22.dp)) }
}

/** Performer / studio link styled like the scene page's metadata pills (pill accent at 10 %). */
@Composable
private fun LinkPill(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, onClick: () -> Unit) {
    val accent = Theme.palette.pillAccent
    Row(
        Modifier.height(28.dp).clip(RoundedCornerShape(50)).background(accent.copy(alpha = 0.1f))
            .clickable(onClick = onClick).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, null, tint = accent, modifier = Modifier.size(10.dp))
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
