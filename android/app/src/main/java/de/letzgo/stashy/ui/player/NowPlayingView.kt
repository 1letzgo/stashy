package de.letzgo.stashy.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.filled.SkipPrevious
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
import androidx.compose.material.icons.outlined.Info
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.scene.timeBarMarkers

/**
 * iOS: `NowPlayingView` — the mini player's own full view. On top the scene page's player module
 * 1:1 ([ScenePlayerModule] in player-only mode: fullscreen, markers + strip, add marker,
 * subtitles / AI captions, frame tools, PiP), then the scene page's metadata card, the
 * performer / studio pills with "next", and the watchlist. While open, the module owns the
 * player and [MiniPlayerStore.session] is empty; the view is keyed on
 * [MiniPlayerStore.nowPlayingScene], so switching scenes rebuilds the module.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NowPlayingSheet(onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
    if (!MiniPlayerStore.showsNowPlaying) return
    // The sheet is its own window above the app: while the app lock is up it would cover the
    // passcode screen with a playing video. It comes back once unlocked.
    if (de.letzgo.stashy.data.SecurityManager.isAppLocked) return
    val scene = MiniPlayerStore.nowPlayingScene
    LaunchedEffect(scene == null) { if (scene == null) MiniPlayerStore.showsNowPlaying = false }
    if (scene == null) return
    val p = Theme.palette
    ModalBottomSheet(
        onDismissRequest = { MiniPlayerStore.showsNowPlaying = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = p.background,
    ) {
        androidx.compose.runtime.key(scene.id) { NowPlayingContent(scene, onOpen) }
    }
}

@Composable
private fun NowPlayingContent(initial: Scene, onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
    val p = Theme.palette
    // The scene page's model in player-only mode: takes the bar's player (no reload), hands it
    // back on leaving even when paused; a scene the bar does not run starts with autoplay.
    val model = remember { de.letzgo.stashy.ui.scene.SceneDetailModel(initial, autoPlay = true, playerOnly = true) }
    val scene = model.scene
    val watchlist = WatchlistStore.all
    val drag = remember { WatchlistDragState() }
    var sorting by remember { mutableStateOf(false) }
    var confirmClear by remember { mutableStateOf(false) }
    // Scenes deleted elsewhere leave the lists (throttled to once a minute).
    LaunchedEffect(Unit) { WatchlistStore.checkAgainstServer() }
    if (confirmClear) AlertDialog(
        onDismissRequest = { confirmClear = false },
        title = { Text("Clear watchlist?") },
        text = { Text("All scenes are removed from the watchlist. What plays keeps playing.") },
        confirmButton = {
            TextButton({ confirmClear = false; sorting = false; WatchlistStore.clear() }) {
                Text("Clear", color = StashyColors.systemRed)
            }
        },
        dismissButton = { TextButton({ confirmClear = false }) { Text("Cancel") } },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
    )
    // Pinned to the sheet's width: nothing (a long title or description) may widen the content.
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(Modifier.width(maxWidth).fillMaxHeight().navigationBarsPadding()) {
            // Standard chrome: Minimize like Back on the left, Details on the right edge.
            Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = NowPlayingMargin), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { MiniPlayerStore.showsNowPlaying = false }) {
                    Icon(SF.chevronDown, "Minimize", tint = p.text)
                }
                Box(Modifier.weight(1f))
                DetailsPill { onOpen(de.letzgo.stashy.ui.scene.SceneDetailScreen(scene.id, scene, openedFromMiniPlayer = true)) }
            }
            // The scene page's player module with the scene page's gap under its chrome
            // (16 dp top and sides, `SceneDetailScreen`), fixed above the scrolling list.
            Box(Modifier.fillMaxWidth().padding(start = NowPlayingMargin, end = NowPlayingMargin, top = NowPlayingMargin)) {
                de.letzgo.stashy.ui.scene.ScenePlayerModule(model)
            }
            LazyColumn(Modifier.fillMaxSize()) {
                item(key = "info") { InfoRow(scene, onOpen) }
                // Always the scene in the player above, whatever started it (Play, a watchlist
                // row, next, the bar) — never a separately kept list that could drift.
                item(key = "playing-header") {
                    Row(Modifier.fillMaxWidth().height(48.dp).padding(start = NowPlayingMargin, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Now Playing", Modifier.weight(1f), style = IosTypography.headline, color = p.text)
                    }
                }
                playingRows(listOf(scene), scene.id, NowPlayingMargin) { MiniPlayerStore.showInNowPlaying(it) }
                item(key = "header") {
                    // Plain list header on the sheet background: "Watchlist" + red Clear + Sort / Done.
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = NowPlayingMargin, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Watchlist", Modifier.weight(1f), style = IosTypography.headline, color = p.text)
                        if (watchlist.isNotEmpty()) TextButton(onClick = { confirmClear = true }) {
                            Text("Clear", color = StashyColors.systemRed, fontWeight = FontWeight.SemiBold)
                        }
                        if (watchlist.isNotEmpty()) TextButton(onClick = { sorting = !sorting }) {
                            Text(if (sorting) "Done" else "Sort", color = Appearance.tint, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                if (watchlist.isEmpty()) item(key = "empty") {
                    Text(
                        "Add scenes with + on a playing scene or the watchlist button on a scene page. They play here one after another.",
                        Modifier.padding(horizontal = NowPlayingMargin, vertical = 8.dp), fontSize = 13.sp, color = p.secondaryText,
                    )
                } else watchlistRows(watchlist.toList(), scene.id, drag, NowPlayingMargin, sorting) { MiniPlayerStore.showInNowPlaying(it) }
                item(key = "bottom") { Box(Modifier.height(24.dp)) }
            }
        }
    }
}

/** Side margin of Now Playing, like the scene page: player, cards and watchlist rows line up on it. */
private val NowPlayingMargin = 16.dp

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun InfoRow(scene: Scene, onOpen: (de.letzgo.stashy.ui.Screen) -> Unit) {
    val p = Theme.palette
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
        MiniPlayerStore.previousScene(scene.id)?.let { previous ->
            CircleAction(Icons.Filled.SkipPrevious, "Previous") { MiniPlayerStore.showInNowPlaying(previous) }
        }
        MiniPlayerStore.nextScene(scene.id)?.let { next ->
            CircleAction(Icons.Filled.SkipNext, "Next") { MiniPlayerStore.showInNowPlaying(next) }
        }
    }
}

/** iOS `StashyDetailTopBar` trailing action: info icon + "Details" in a tint pill. */
@Composable
private fun DetailsPill(onClick: () -> Unit) {
    Row(
        Modifier.height(32.dp).clip(RoundedCornerShape(50)).background(Appearance.tint.copy(alpha = 0.15f))
            .clickable(onClickLabel = "Open the scene page", onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(Icons.Outlined.Info, null, tint = Appearance.tint, modifier = Modifier.size(16.dp))
        Text("Details", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Appearance.tint, maxLines = 1)
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
