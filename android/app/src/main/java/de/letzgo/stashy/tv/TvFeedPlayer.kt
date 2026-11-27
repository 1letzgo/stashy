package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.feeds.FeedItem
import de.letzgo.stashy.ui.player.StashPlayer
import de.letzgo.stashy.ui.player.VideoSurface
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * iOS: `TVFeedPlayerView` — the full-screen Feeds pager on the D-pad: ▲ / ▼ previous / next item,
 * ◀ / ▶ seek 10 s, holding ◀ / ▶ seeks continuously (20 → 60 → 180 s per second), Play/Pause
 * toggles, ⏭ / ⏮ page, ⏩ / ⏪ seek. Select opens the info overlay (title, Play, Scene Details,
 * O Count, rating, mute, performers, studio, mode switcher, Reshuffle); Back closes the overlay
 * first, then the feed. The Siri Remote's touch-surface scrub has no D-pad counterpart.
 */
@Composable
fun TvFeedPlayer(session: TvFeedSession, onNavigate: (TvFeedDestination) -> Unit, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val inputFocus = remember { FocusRequester() }
    val overlayEntry = remember { FocusRequester() }
    var overlayOpen by remember { mutableStateOf(false) }
    var ratingItem by remember { mutableStateOf<FeedItem?>(null) }
    var showsInfo by remember { mutableStateOf(true) }
    var seekFeedback by remember { mutableStateOf<String?>(null) }
    val feedbackJob = remember { arrayOfNulls<Job>(1) }
    var holdJob by remember { mutableStateOf<Job?>(null) }
    var holdTarget by remember { mutableDoubleStateOf(0.0) }
    /** ◀ / ▶ / Select key-down times: a tap acts on release, a held ◀ / ▶ seeks on. */
    val downAt = remember { HashMap<Int, Long>() }
    var closing by remember { mutableStateOf(false) }

    val item = session.currentItem
    val player = session.player

    fun now() = System.currentTimeMillis()

    fun clearFeedbackLater() {
        feedbackJob[0]?.cancel()
        feedbackJob[0] = scope.launch { delay(800); seekFeedback = null }
    }

    fun flash(label: String) { seekFeedback = label; clearFeedbackLater() }

    fun step(direction: Int) {
        if (overlayOpen) return
        session.seek(by = direction * TvFeedLogic.SEEK_STEP)
        flash(TvFeedLogic.stepLabel(direction))
    }

    fun beginHold(direction: Int) {
        val p = session.player ?: return
        holdJob?.cancel()
        holdTarget = p.currentTime
        feedbackJob[0]?.cancel()
        holdJob = scope.launch {
            var elapsed = 0.0
            while (isActive) {
                delay((TvFeedLogic.HOLD_TICK * 1000).toLong())
                val range = session.seekRange ?: break
                val current = session.player ?: break
                elapsed += TvFeedLogic.HOLD_TICK
                holdTarget = TvFeedLogic.clamp(holdTarget + direction * TvFeedLogic.holdSeekSpeed(elapsed) * TvFeedLogic.HOLD_TICK, range)
                seekFeedback = "${if (direction < 0) "◀◀" else "▶▶"}  ${TvFormat.time(holdTarget)} / ${TvFormat.time(current.duration)}"
                session.seek(to = holdTarget)
            }
        }
    }

    fun endHold() {
        val job = holdJob ?: return
        job.cancel()
        holdJob = null
        session.seek(to = holdTarget)
        clearFeedbackLater()
    }

    fun openOverlay() {
        endHold()
        showsInfo = false
        overlayOpen = true
    }

    fun close() {
        if (closing) return
        closing = true
        onClose()
    }

    BackHandler {
        if (overlayOpen) overlayOpen = false else close()
    }

    // The info strip after every item change (and on open), gone after 4 s.
    LaunchedEffect(item?.id) {
        if (overlayOpen) return@LaunchedEffect
        showsInfo = true
        delay((TvFeedLogic.INFO_SECONDS * 1000).toLong())
        showsInfo = false
    }
    LaunchedEffect(session.message) {
        if (session.message != null) { delay(3000); session.message = null }
    }

    val showsProgress = showsInfo || overlayOpen || holdJob != null || seekFeedback != null

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (player != null) {
            FeedVideoLayer(player, item, session.isSwitching, showsProgress)
        } else {
            item?.posterURL?.let { FeedPoster(it, spinner = true) }
        }

        if (session.isLoading && session.items.isEmpty()) {
            Box(Modifier.align(Alignment.Center)) { TvSpinner(pt(72)) }
        } else if (session.errorMessage != null && session.items.isEmpty()) {
            EmptyState(session.mode, session.errorMessage.orEmpty(), Modifier.align(Alignment.Center))
        }

        seekFeedback?.let {
            Text(
                it,
                Modifier.align(Alignment.Center).clip(RoundedCornerShape(pt(40))).background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = pt(28), vertical = pt(14)),
                style = TvType.title2.copy(fontSize = 17.sp), color = Color.White,
            )
        }

        AnimatedVisibility(showsInfo && !overlayOpen && item != null, Modifier.fillMaxSize(), enter = fadeIn(), exit = fadeOut()) {
            if (item != null) InfoStrip(session, item)
        }

        session.message?.let {
            Text(
                it,
                Modifier.align(Alignment.TopCenter).padding(top = pt(60)).clip(RoundedCornerShape(pt(14))).background(Color.Black.copy(alpha = 0.7f))
                    .padding(horizontal = pt(24), vertical = pt(12)),
                style = TvType.headline, color = Color.White,
            )
        }

        // The remote layer only exists while the overlay is closed, so it never takes the
        // D-pad from the overlay's buttons (same rule as tvOS).
        if (!overlayOpen) {
            Box(
                Modifier.fillMaxSize().focusRequester(inputFocus).onKeyEvent { event ->
                    val native = event.nativeKeyEvent
                    val code = native.keyCode
                    val key = TvFeedLogic.key(code)
                    if (key == TvFeedLogic.Key.None) return@onKeyEvent false
                    when (event.type) {
                        KeyEventType.KeyDown -> {
                            when {
                                TvFeedLogic.isHoldSeekKey(code) -> {
                                    if (native.repeatCount == 0) downAt[code] = now()
                                    else if (holdJob == null && session.player != null) {
                                        val start = downAt[code]
                                        if (start != null && now() - start >= TvFeedLogic.HOLD_THRESHOLD_MS) beginHold(if (key == TvFeedLogic.Key.SeekBack) -1 else 1)
                                    }
                                }
                                key == TvFeedLogic.Key.OpenOverlay -> if (native.repeatCount == 0) downAt[code] = now()
                                native.repeatCount > 0 && (key == TvFeedLogic.Key.Previous || key == TvFeedLogic.Key.Next) -> Unit
                                else -> when (key) {
                                    TvFeedLogic.Key.Previous -> session.previous()
                                    TvFeedLogic.Key.Next -> session.next()
                                    TvFeedLogic.Key.SeekBack -> step(-1)
                                    TvFeedLogic.Key.SeekForward -> step(1)
                                    TvFeedLogic.Key.TogglePlay -> session.togglePlayPause()
                                    TvFeedLogic.Key.Play -> session.play()
                                    TvFeedLogic.Key.Pause -> session.pause()
                                    else -> Unit
                                }
                            }
                            true
                        }
                        KeyEventType.KeyUp -> {
                            val wasDown = downAt.remove(code) != null
                            when {
                                TvFeedLogic.isHoldSeekKey(code) -> if (holdJob != null) endHold() else if (wasDown) step(if (key == TvFeedLogic.Key.SeekBack) -1 else 1)
                                // Opens on release, so the click's own key-up never reaches an overlay button.
                                key == TvFeedLogic.Key.OpenOverlay -> if (wasDown) openOverlay()
                            }
                            true
                        }
                        else -> false
                    }
                }.focusable(),
            )
            TvRequestFocus(inputFocus, "feeds.pager", key = overlayOpen)
        }

        AnimatedVisibility(
            overlayOpen, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) {
            val current = session.currentItem
            Overlay(
                session, current, overlayEntry,
                close = { overlayOpen = false },
                onNavigate = { destination -> overlayOpen = false; onNavigate(destination) },
                onRate = { ratingItem = it },
                onPlayFull = { target, scene -> overlayOpen = false; playInFullPlayer(session, target, scene) },
            )
        }
        if (overlayOpen) TvRequestFocus(overlayEntry, "feeds.overlay", key = overlayOpen, delayMs = 300)
    }

    ratingItem?.let { target ->
        TvOptionDialog(
            tr(R.string.rating),
            TvFeedLogic.ratingChoices.map { TvOption(it, if (it == 0) tr(R.string.empty_rating) else "★".repeat(it)) },
            TvFormat.stars(target.rating100),
            onSelect = { stars -> session.setRating(stars, target) },
            onDismiss = { ratingItem = null },
        )
    }
}

/**
 * iOS `playInFullPlayer` — scenes and previews play the whole scene from the top, markers from
 * the marker, in the regular player. The feed's player is released first: one decoder at a time.
 */
private fun playInFullPlayer(session: TvFeedSession, item: FeedItem, scene: Scene) {
    session.suspendForFullPlayer()
    val model = TvPlaybackModel()
    val start = (item as? FeedItem.MarkerItem)?.marker?.seconds ?: 0.0
    model.setup(scene, start)
    TvNav.push(TvScenePlayerRoute(model) { scene })
}

// MARK: - Video layer

@Composable
private fun FeedVideoLayer(player: StashPlayer, item: FeedItem?, isSwitching: Boolean, showsProgress: Boolean) {
    Box(Modifier.fillMaxSize()) {
        VideoSurface(player, Modifier.fillMaxSize())
        val poster = item?.posterURL
        if ((isSwitching || !player.hasPresentedFrame) && poster != null) FeedPoster(poster, spinner = true)
        val error = player.errorMessage
        if (error != null && !isSwitching) {
            Text(
                error,
                Modifier.align(Alignment.Center).padding(horizontal = pt(80)).clip(RoundedCornerShape(pt(14))).background(Color.Black.copy(alpha = 0.65f))
                    .padding(horizontal = pt(24), vertical = pt(14)),
                style = TvType.headline, color = Color.White, textAlign = TextAlign.Center, maxLines = 3,
            )
        }
        AnimatedVisibility(showsProgress, Modifier.align(Alignment.BottomCenter), enter = fadeIn(), exit = fadeOut()) {
            ProgressLine(player, item)
        }
    }
}

/** Thin progress line; a marker shows its segment, not the whole file. */
@Composable
private fun ProgressLine(player: StashPlayer, item: FeedItem?) {
    val seg = item?.segment
    val time = player.currentTime
    val fraction = if (seg != null && seg.length > 0) ((time - seg.start) / seg.length)
    else if (player.duration > 0) time / player.duration else 0.0
    BoxWithConstraints(Modifier.fillMaxWidth().height(pt(6)).background(Color.White.copy(alpha = 0.18f))) {
        Box(Modifier.fillMaxHeight().width(maxWidth * fraction.coerceIn(0.0, 1.0).toFloat()).background(TvColors.tint))
    }
}

/** Poster while the next item loads: the thumbnail dimmed behind a spinner. */
@Composable
private fun FeedPoster(url: String, spinner: Boolean) {
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        AsyncImage(url, null, Modifier.fillMaxSize().alpha(0.45f), contentScale = ContentScale.Fit)
        if (spinner) TvSpinner(pt(72))
    }
}

// MARK: - Info strip

@Composable
private fun InfoStrip(session: TvFeedSession, item: FeedItem) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = pt(80), end = pt(80), top = pt(50)), verticalAlignment = Alignment.CenterVertically) {
            val channel = session.channel
            Icon(if (channel == null) session.mode.tvIcon else TvIcons.tv, null, Modifier.size(pt(30)), tint = TvColors.tint)
            Spacer(Modifier.width(pt(12)))
            Text(channel?.title ?: session.mode.defaultTitle, style = TvType.headline.copy(fontSize = 12.sp), color = TvColors.tint, maxLines = 1)
            Spacer(Modifier.weight(1f))
            Text(session.positionLabel, style = TvType.headline.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.75f))
        }
        Spacer(Modifier.weight(1f))
        Column(
            Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))))
                .padding(start = pt(80), end = pt(80), top = pt(60), bottom = pt(80)),
            verticalArrangement = Arrangement.spacedBy(pt(10)),
        ) {
            Text(item.tvTitle, style = TvType.title2.copy(fontSize = 20.sp), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
            performerStudioLine(item)?.let {
                Text(it, style = TvType.title3.copy(fontSize = 13.sp), color = Color.White.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(tr(R.string.hint_browse_seek_select_for_info), Modifier.padding(top = pt(6)), style = TvType.caption.copy(fontSize = 11.sp), color = Color.White.copy(alpha = 0.5f))
        }
    }
}

private fun performerStudioLine(item: FeedItem): String? {
    val parts = ArrayList<String>()
    val performers = item.performers.take(4).map { it.name }.filter { it.isNotEmpty() }
    if (performers.isNotEmpty()) parts.add(performers.joinToString(", "))
    item.tvStudio?.second?.let { parts.add(it) }
    if (parts.isEmpty()) item.tvSubtitle?.let { parts.add(it) }
    return parts.takeIf { it.isNotEmpty() }?.joinToString("  ·  ")
}

// MARK: - Overlay

@Composable
private fun Overlay(
    session: TvFeedSession,
    row: FeedItem?,
    entry: FocusRequester,
    close: () -> Unit,
    onNavigate: (TvFeedDestination) -> Unit,
    onRate: (FeedItem) -> Unit,
    onPlayFull: (FeedItem, Scene) -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f), Color.Black.copy(alpha = 0.92f))))
            .padding(start = pt(80), end = pt(80), top = pt(50), bottom = pt(60)),
        verticalArrangement = Arrangement.spacedBy(pt(24)),
    ) {
        if (row != null) {
            Column(verticalArrangement = Arrangement.spacedBy(pt(8))) {
                Text(row.tvTitle, style = TvType.title2.copy(fontSize = 22.sp), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
                row.tvSubtitle?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = TvType.title3.copy(fontSize = 13.sp), color = Color.White.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                val tags = row.tags.take(6).mapNotNull { it.name?.takeIf { n -> n.isNotEmpty() } }
                if (tags.isNotEmpty()) Text(tags.joinToString("  ·  "), style = TvType.caption.copy(fontSize = 11.sp), color = Color.White.copy(alpha = 0.55f), maxLines = 1)
            }
            LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(24)), contentPadding = PaddingValues(vertical = pt(20), horizontal = pt(6))) {
                val scene = row.tvScene
                if (scene != null) {
                    val playLabel = if (row is FeedItem.MarkerItem) tr(R.string.action_play_from_marker) else tr(R.string.action_play_from_start)
                    item(key = "play") { OverlayButton(playLabel, TvIcons.play, Modifier.focusRequester(entry)) { onPlayFull(row, scene) } }
                    item(key = "details") { OverlayButton(tr(R.string.scene_details), TvIcons.info) { onNavigate(TvFeedDestination.Scene(scene.id)) } }
                } else {
                    val playing = session.player?.isPlaying == true
                    item(key = "toggle") {
                        OverlayButton(if (playing) tr(R.string.action_pause) else tr(R.string.action_play), if (playing) TvIcons.pause else TvIcons.play, Modifier.focusRequester(entry)) {
                            session.togglePlayPause()
                        }
                    }
                }
                if (row.sceneID != null || row is FeedItem.ClipItem) {
                    // Same two actions, icons and picker as the scene page.
                    item(key = "o") { OverlayButton("${row.oCounter ?: 0}", TvIcons.heartCircle) { session.addO(row) } }
                    item(key = "rating") {
                        val stars = TvFormat.stars(row.rating100)
                        OverlayButton(if (stars == 0) tr(R.string.action_rate) else "★".repeat(stars), TvIcons.star) { onRate(row) }
                    }
                }
                item(key = "mute") {
                    OverlayButton(if (session.isMuted) tr(R.string.unmute) else tr(R.string.mute), if (session.isMuted) TvIcons.speakerSlash else TvIcons.speaker) {
                        session.toggleMute()
                    }
                }
                row.performers.take(4).forEach { performer ->
                    item(key = "performer.${performer.id}") {
                        OverlayButton(performer.name, TvIcons.person) { onNavigate(TvFeedDestination.Performer(performer.id, performer.name)) }
                    }
                }
                row.tvStudio?.let { (id, name) ->
                    item(key = "studio") { OverlayButton(name, TvIcons.building) { onNavigate(TvFeedDestination.Studio(id, name)) } }
                }
            }
        } else {
            // The feed is empty (or failed): the overlay still offers reload and the mode switch.
            Row { OverlayButton(tr(R.string.action_reload), TvIcons.retry, Modifier.focusRequester(entry)) { close(); session.reload() } }
        }
        ModeRow(session, close)
    }
}

@Composable
private fun ModeRow(session: TvFeedSession, close: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(pt(20)), verticalAlignment = Alignment.CenterVertically) {
        TvFeedLogic.enabledModes(de.letzgo.stashy.data.TabManager.enabledReelsModes).forEach { mode ->
            val selected = mode == session.mode
            TvButton({ close(); session.switchMode(mode) }) {
                Icon(mode.tvIcon, null, Modifier.size(pt(28)), tint = if (selected) TvColors.tint else androidx.tv.material3.LocalContentColor.current)
                Text(mode.defaultTitle, style = TvType.body.copy(fontSize = 12.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal), maxLines = 1)
            }
        }
        Spacer(Modifier.weight(1f))
        TvButton({ close(); session.reload() }) {
            Icon(TvIcons.shuffle, null, Modifier.size(pt(28)))
            Text(tr(R.string.reshuffle), style = TvType.body.copy(fontSize = 12.sp), maxLines = 1)
        }
    }
}

@Composable
private fun OverlayButton(title: String, icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    TvButton(onClick, modifier, contentPadding = PaddingValues(horizontal = pt(26), vertical = pt(14))) {
        Icon(icon, null, Modifier.size(pt(28)))
        Text(title, style = TvType.body.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold), maxLines = 1)
    }
}

// MARK: - Empty state

@Composable
private fun EmptyState(mode: ReelsModeType, message: String, modifier: Modifier) {
    Column(modifier.padding(pt(80)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
        Icon(mode.tvIcon, null, Modifier.size(pt(64)), tint = TvColors.secondary)
        Text(message, style = TvType.title2.copy(fontWeight = FontWeight.Normal), color = TvColors.secondary, textAlign = TextAlign.Center)
        Text(tr(R.string.hint_click_to_switch_modes_or), style = TvType.title3, color = TvColors.tertiary)
    }
}
