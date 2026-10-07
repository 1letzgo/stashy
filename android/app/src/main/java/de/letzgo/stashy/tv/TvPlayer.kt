package de.letzgo.stashy.tv

import de.letzgo.stashy.ui.uniqueItemsIndexed
import android.os.SystemClock
import android.view.KeyEvent as AndroidKeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.player.PlayCountCredit
import de.letzgo.stashy.ui.player.PlaybackActivityTracker
import de.letzgo.stashy.ui.player.PlayerSettings
import de.letzgo.stashy.ui.player.SceneNowPlaying
import de.letzgo.stashy.ui.player.SceneScrubSprites
import de.letzgo.stashy.ui.player.StashPlayer
import de.letzgo.stashy.ui.player.SubtitleOverlay
import de.letzgo.stashy.ui.player.VideoSurface
import de.letzgo.stashy.ui.scene.captionURL
import de.letzgo.stashy.ui.scene.transcodeFallbackURLs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * iOS: `TVAetherPlaybackModel` — one player per session on top of the shared [StashPlayer]
 * (Media3 with the transcode ladder), resume/activity saving like the phone player
 * ([PlaybackActivityTracker]: watched time + resume every 10 s and on leave, cleared at 98 %),
 * the play credit after Settings › Count As Played, server captions and the channel hand-over.
 */
class TvPlaybackModel {
    companion object {
        private val live = java.util.Collections.newSetFromMap(java.util.WeakHashMap<TvPlaybackModel, Boolean>())

        /** Pauses every TV player (app left via Home / another app in front). */
        fun pauseAll() = live.toList().forEach { it.player?.pause() }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    var player by mutableStateOf<StashPlayer?>(null); private set
    val hasPlayer: Boolean get() = player != null
    var scene by mutableStateOf<Scene?>(null); private set
    var sprites by mutableStateOf<SceneScrubSprites?>(null); private set
    /** Called when the current item finishes (channel continuous play). */
    var onPlaybackEnded: (() -> Unit)? = null

    private val tracker = PlaybackActivityTracker(scope)
    private val credited = HashSet<String>()
    /** Count-as-played: real watch time of the current item, not its playhead (resume ≠ watched). */
    private val playCredit = PlayCountCredit(0.0)

    private fun ensurePlayer(): StashPlayer = player ?: StashPlayer(Prefs.appContext, StashPlayer.Role.Main).also { p ->
        p.autoSelectsPreferredSubtitleTrack = true
        p.onTime = { t, d -> onTime(p, t, d) }
        p.onPlayingChanged = { playing ->
            if (p.hasFirstFrame) {
                tracker.setPosition(p.currentTime, effectiveDuration(p))
                if (playing) tracker.start() else tracker.stop()
            }
        }
        p.onReachedEnd = { onPlaybackEnded?.invoke() }
        // No MediaSession/PlaybackService on TV: playback must not continue in the background
        // (Home button) — TvActivity.onStop pauses via [pauseAll].
        player = p
        live.add(this)
    }

    private fun effectiveDuration(p: StashPlayer) = if (p.duration > 0) p.duration else scene?.sceneDuration ?: 0.0

    /** First load of a session. */
    fun setup(scene: Scene, startAt: Double, subtitle: String? = scene.studio?.name) {
        val url = scene.streamURL ?: return
        val p = ensurePlayer()
        configure(p, scene)
        p.load(url, startAt.takeIf { it > 0.25 }, autoplay = true)
        registerCaptions(p, scene)
    }

    /** Channel hand-over: same player, next item. */
    fun playNext(scene: Scene, subtitle: String? = scene.studio?.name) {
        val p = player ?: return setup(scene, 0.0, subtitle)
        tracker.reset()
        configure(p, scene)
        p.load(scene.streamURL ?: return, null, autoplay = true)
        registerCaptions(p, scene)
    }

    private fun configure(p: StashPlayer, scene: Scene) {
        this.scene = scene
        val sceneId = scene.id
        tracker.updatesResumeTime = true
        tracker.onSave = { resume, played ->
            scope.launch {
                val ok = runCatching { SceneEditing.saveActivity(sceneId, resume, played) }.isSuccess
                if (ok && resume != null) SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, resume))
            }
        }
        p.fallbackSources = scene.transcodeFallbackURLs
        p.fallbackDeclaredDuration = scene.sceneDuration
        p.nowPlaying = SceneNowPlaying.of(scene)
        sprites = SceneScrubSprites.create(scene.paths?.vtt, scene.paths?.sprite)?.also { it.prepare(scope) }
        playCredit.reset()
        playCredit.thresholdSeconds = playThreshold
        if (playCredit.onStart()) credit(sceneId)
    }

    private val playThreshold: Double get() = maxOf(0.0, TabManager.playCountPlayerSeconds)

    private fun onTime(p: StashPlayer, t: Double, d: Double) {
        // The outgoing item's clock is not this item's playhead (hand-over in flight).
        if (!p.hasFirstFrame || t < 0) return
        tracker.setPosition(t, if (d > 0) d else scene?.sceneDuration ?: 0.0)
        if (p.isPlaying) tracker.start()
        val id = scene?.id ?: return
        playCredit.thresholdSeconds = playThreshold
        if (playCredit.onTime(t, p.isPlaying, SystemClock.elapsedRealtime() / 1000.0)) credit(id)
    }

    /** Credits the play once per scene, after [playThreshold] seconds actually watched ([PlayCountCredit]). */
    private fun credit(sceneId: String) {
        if (!credited.add(sceneId)) return
        if (!de.letzgo.stashy.data.TabManager.tracksActivity(sceneId)) return
        scope.launch {
            runCatching { SceneEditing.addPlay(sceneId) }
            SceneEvents.post(SceneEvent.PlayAdded(sceneId))
        }
    }

    private fun registerCaptions(p: StashPlayer, scene: Scene) {
        scene.captions.orEmpty().forEach { caption ->
            val url = captionURL(caption, scene) ?: return@forEach
            val code = caption.languageCode?.takeIf { it.isNotEmpty() && it != "00" }
            val name = code?.let { Locale(it).getDisplayLanguage(Locale.ENGLISH).takeIf { n -> n.isNotEmpty() && n != it } ?: it.uppercase() } ?: "Captions"
            p.addExternalSubtitleTrack(url, name, code)
        }
    }

    fun seek(seconds: Double) {
        val p = player ?: return
        p.seek(seconds)
        tracker.noteSeek(seconds)
        playCredit.noteSeek()
    }

    /** Back on the player: save and pause, keep the player until the page is gone. */
    fun suspend() {
        tracker.stop()
        player?.pause()
    }

    fun clear() {
        tracker.stop()
        credited.clear()
        playCredit.reset()
        player?.release()
        player = null
        sprites = null
    }
}

// MARK: - Player screen

private enum class PanelTarget { Nav, Audio, Subtitles, Extra }

/**
 * iOS: `TVAetherPlayerView` / `TVAetherPlayerContent` — full-screen video with the Siri-Remote
 * transport translated to the D-pad: Select / Play-Pause toggles, Left/Right seek (presses
 * within 0.5 s accelerate 10 → 30 → 60 s, the third quick press switches to a sprite-preview
 * scrub that commits on Select or after 1 s), Fast-forward / Rewind skip the Settings skip
 * interval, Down opens the options panel (channel Prev/Next, audio, subtitles, markers or Up
 * Next), Up shows the transport, holding Up/Down switches the channel's scene. Back closes the
 * panel, then the scrub, then the transport, then the player. Controls hide after 4 s.
 */
@Composable
fun TvPlayerScreen(
    model: TvPlaybackModel,
    title: String,
    subtitle: String,
    posterURL: String?,
    onExit: () -> Unit,
    canGoPrevious: Boolean = false,
    canGoNext: Boolean = false,
    onPrevious: () -> Unit = {},
    onNext: () -> Unit = {},
    panelExtra: (@Composable (close: () -> Unit, entry: FocusRequester?) -> Unit)? = null,
) {
    val player = model.player
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (player == null) {
            TvPlayerError(null, onExit)
        } else {
            TvPlayerContent(model, player, title, subtitle, posterURL, onExit, canGoPrevious, canGoNext, onPrevious, onNext, panelExtra)
        }
    }
}

@Composable
private fun TvPlayerContent(
    model: TvPlaybackModel,
    player: StashPlayer,
    title: String,
    subtitle: String,
    posterURL: String?,
    onExit: () -> Unit,
    canGoPrevious: Boolean,
    canGoNext: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    panelExtra: (@Composable (close: () -> Unit, entry: FocusRequester?) -> Unit)?,
) {
    val scope = rememberCoroutineScope()
    val playerFocus = remember { FocusRequester() }
    val panelEntry = remember { FocusRequester() }
    val closer = remember { FocusRequester() }
    var showTransport by remember { mutableStateOf(true) }
    var panelOpen by remember { mutableStateOf(false) }
    var panelOpenedAt by remember { mutableLongStateOf(0L) }
    var hideToken by remember { mutableIntStateOf(0) }
    var scrubbing by remember { mutableStateOf(false) }
    var scrubTarget by remember { mutableStateOf(0.0) }
    var scrubCommit by remember { mutableStateOf<Job?>(null) }
    var lastHoldAt by remember { mutableLongStateOf(0L) }
    val accelerator = remember { TvSeekAccelerator() }
    val holdUp = remember { TvHoldTracker() }
    val holdDown = remember { TvHoldTracker() }
    val channelMode = canGoPrevious || canGoNext

    fun reveal() { showTransport = true; hideToken++ }
    fun now() = System.currentTimeMillis()

    LaunchedEffect(hideToken, player.isPlaying, scrubbing, panelOpen) {
        delay(4000)
        // Paused, the timeline stays (like Apple's player).
        if (!scrubbing && !panelOpen && player.isPlaying) showTransport = false
    }

    fun commitScrub() {
        if (!scrubbing) return
        scrubCommit?.cancel(); scrubCommit = null
        scrubbing = false
        accelerator.reset()
        model.seek(scrubTarget)
        reveal()
    }

    fun cancelScrub() {
        scrubCommit?.cancel(); scrubCommit = null
        scrubbing = false
        accelerator.reset()
    }

    fun step(delta: Double) {
        reveal()
        val duration = player.duration
        val upper = if (duration.isFinite() && duration > 0) duration - 0.5 else Double.MAX_VALUE
        if (!scrubbing && accelerator.wantsScrub) {
            scrubbing = true
            scrubTarget = player.currentTime
        }
        if (scrubbing) {
            scrubTarget = (scrubTarget + delta).coerceIn(0.0, upper)
            scrubCommit?.cancel()
            scrubCommit = scope.launch { delay(1000); commitScrub() }
        } else {
            model.seek((player.currentTime + delta).coerceIn(0.0, upper))
        }
    }

    fun skip(delta: Double) {
        cancelScrub()
        val duration = player.duration
        val upper = if (duration.isFinite() && duration > 0) duration - 0.5 else Double.MAX_VALUE
        model.seek((player.currentTime + delta).coerceIn(0.0, upper))
        reveal()
    }

    fun togglePlay() {
        if (scrubbing) { commitScrub(); return }
        player.togglePlayPause()
        reveal()
    }

    fun openPanel() {
        cancelScrub()
        panelOpenedAt = now()
        panelOpen = true
    }

    fun closePanel() { panelOpen = false }

    fun holdSwitch(action: () -> Unit) {
        lastHoldAt = now()
        cancelScrub()
        if (panelOpen) closePanel()
        action()
    }

    fun verticalTap(down: Boolean) {
        if (panelOpen || now() - lastHoldAt < 1000) return
        if (down) openPanel() else reveal()
    }

    fun handleExit() {
        when {
            panelOpen -> closePanel()
            scrubbing -> cancelScrub()
            showTransport -> showTransport = false
            else -> onExit()
        }
    }

    BackHandler { handleExit() }

    TvRequestFocus(playerFocus, "player", delayMs = 50)
    LaunchedEffect(player.hasFirstFrame) { if (player.hasFirstFrame && !panelOpen) { runCatching { playerFocus.requestFocus() }; reveal() } }
    LaunchedEffect(panelOpen) {
        delay(300)
        if (panelOpen) runCatching { panelEntry.requestFocus() }
        else { runCatching { playerFocus.requestFocus() }; reveal() }
    }

    val hasNav = channelMode
    val firstTarget = when {
        hasNav -> PanelTarget.Nav
        player.audioTracks.isNotEmpty() -> PanelTarget.Audio
        player.subtitleTracks.isNotEmpty() -> PanelTarget.Subtitles
        else -> PanelTarget.Extra
    }

    Box(
        Modifier.fillMaxSize().onPreviewKeyEvent { event ->
            if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
            val native = event.nativeKeyEvent
            if (native.repeatCount > 0 && native.keyCode != AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD && native.keyCode != AndroidKeyEvent.KEYCODE_MEDIA_REWIND) return@onPreviewKeyEvent false
            when (native.keyCode) {
                AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, AndroidKeyEvent.KEYCODE_HEADSETHOOK -> { togglePlay(); true }
                AndroidKeyEvent.KEYCODE_MEDIA_PLAY -> { if (!player.isPlaying) togglePlay() else reveal(); true }
                AndroidKeyEvent.KEYCODE_MEDIA_PAUSE -> { if (player.isPlaying) togglePlay() else reveal(); true }
                AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { skip(PlayerSettings.skipSeconds); true }
                AndroidKeyEvent.KEYCODE_MEDIA_REWIND -> { skip(-PlayerSettings.skipSeconds); true }
                AndroidKeyEvent.KEYCODE_MEDIA_NEXT, AndroidKeyEvent.KEYCODE_MEDIA_SKIP_FORWARD ->
                    { if (canGoNext) holdSwitch(onNext) else skip(PlayerSettings.skipSeconds); true }
                AndroidKeyEvent.KEYCODE_MEDIA_PREVIOUS, AndroidKeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD ->
                    { if (canGoPrevious) holdSwitch(onPrevious) else skip(-PlayerSettings.skipSeconds); true }
                else -> false
            }
        },
    ) {
        VideoSurface(player, Modifier.fillMaxSize(), showsBitmapSubtitles = true)

        if (!player.hasPresentedFrame) {
            Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                if (posterURL != null) AsyncImage(posterURL, null, Modifier.fillMaxSize().alpha(0.35f), contentScale = ContentScale.Fit)
                TvSpinner(pt(72))
            }
        }

        Box(Modifier.align(Alignment.BottomCenter).padding(horizontal = pt(80)).padding(bottom = if (showTransport && !panelOpen) pt(260) else pt(90))) {
            SubtitleOverlay(player.currentSubtitleText, 1.1f)
        }

        player.errorMessage?.let { message ->
            Text(
                message,
                Modifier.align(Alignment.BottomCenter).padding(bottom = pt(220)).clip(RoundedCornerShape(pt(14))).background(Color.Black.copy(alpha = 0.65f))
                    .padding(horizontal = pt(24), vertical = pt(14)),
                style = TvType.headline.copy(fontSize = 14.sp), color = Color.White, textAlign = TextAlign.Center, maxLines = 3,
            )
        }

        AnimatedVisibility(showTransport && !panelOpen, Modifier.align(Alignment.BottomCenter), enter = fadeIn(), exit = fadeOut()) {
            TransportOverlay(model, player, title, subtitle, scrubbing, scrubTarget, channelMode, canGoPrevious, canGoNext)
        }

        // The remote layer only exists while the panel is closed, so it never sits over the
        // panel's buttons (same rule as tvOS).
        if (!panelOpen) {
            Box(
                Modifier.fillMaxSize().focusRequester(playerFocus).onKeyEvent { event ->
                    val native = event.nativeKeyEvent
                    val code = native.keyCode
                    if (event.type == KeyEventType.KeyDown) {
                        when (code) {
                            AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_NUMPAD_ENTER -> {
                                if (native.repeatCount == 0) togglePlay(); true
                            }
                            AndroidKeyEvent.KEYCODE_DPAD_LEFT -> { step(-accelerator.step(now(), 10.0)); true }
                            AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> { step(accelerator.step(now(), 10.0)); true }
                            AndroidKeyEvent.KEYCODE_DPAD_UP -> {
                                if (holdUp.keyDown(now(), native.repeatCount) == TvHoldTracker.Result.Hold && canGoPrevious) holdSwitch(onPrevious)
                                true
                            }
                            AndroidKeyEvent.KEYCODE_DPAD_DOWN -> {
                                if (holdDown.keyDown(now(), native.repeatCount) == TvHoldTracker.Result.Hold && canGoNext) holdSwitch(onNext)
                                true
                            }
                            else -> false
                        }
                    } else if (event.type == KeyEventType.KeyUp) {
                        when (code) {
                            AndroidKeyEvent.KEYCODE_DPAD_UP -> {
                                val r = holdUp.keyUp(now())
                                if (r == TvHoldTracker.Result.Tap || (r == TvHoldTracker.Result.Hold && !canGoPrevious)) verticalTap(false)
                                else if (r == TvHoldTracker.Result.Hold) holdSwitch(onPrevious)
                                true
                            }
                            AndroidKeyEvent.KEYCODE_DPAD_DOWN -> {
                                val r = holdDown.keyUp(now())
                                if (r == TvHoldTracker.Result.Tap || (r == TvHoldTracker.Result.Hold && !canGoNext)) verticalTap(true)
                                else if (r == TvHoldTracker.Result.Hold) holdSwitch(onNext)
                                true
                            }
                            AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_NUMPAD_ENTER,
                            AndroidKeyEvent.KEYCODE_DPAD_LEFT, AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> true
                            else -> false
                        }
                    } else false
                }.focusable(),
            )
        }

        AnimatedVisibility(
            panelOpen, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) {
            Column(
                Modifier.fillMaxWidth().background(Color.Black.copy(alpha = 0.9f)).padding(horizontal = pt(60), vertical = pt(40)),
                verticalArrangement = Arrangement.spacedBy(pt(26)),
            ) {
                // "Up" out of the top row lands here and closes the panel.
                Box(
                    Modifier.fillMaxWidth().height(1.dp).focusRequester(closer).onFocusChanged {
                        if (it.isFocused && panelOpen) {
                            if (now() - panelOpenedAt < 600) runCatching { panelEntry.requestFocus() } else closePanel()
                        }
                    }.focusable(),
                )
                if (hasNav) {
                    Row(horizontalArrangement = Arrangement.spacedBy(pt(24))) {
                        if (canGoPrevious) PanelButton("Previous", TvIcons.backwardEnd, Modifier.focusRequester(panelEntry)) { closePanel(); onPrevious() }
                        if (canGoNext) PanelButton("Next", TvIcons.forwardEnd, if (!canGoPrevious) Modifier.focusRequester(panelEntry) else Modifier) { closePanel(); onNext() }
                    }
                }
                if (player.audioTracks.isNotEmpty()) {
                    TrackRow("Audio", firstTarget == PanelTarget.Audio, panelEntry) {
                        itemsIndexed(player.audioTracks) { i, track ->
                            val active = track.id == player.activeAudioTrackId
                            PanelButton(if (active) "✓ ${track.label}" else track.label, TvIcons.speaker, if (i == 0 && it) Modifier.focusRequester(panelEntry) else Modifier) {
                                player.selectAudioTrack(track.id)
                            }
                        }
                    }
                }
                if (player.subtitleTracks.isNotEmpty()) {
                    TrackRow("Subtitles", firstTarget == PanelTarget.Subtitles, panelEntry) {
                        item {
                            val off = player.activeSubtitleTrackId == null
                            PanelButton(if (off) "✓ Off" else "Off", TvIcons.captionsOutline, if (it) Modifier.focusRequester(panelEntry) else Modifier) { player.clearSubtitle() }
                        }
                        itemsIndexed(player.subtitleTracks) { _, track ->
                            val active = track.id == player.activeSubtitleTrackId
                            PanelButton(if (active) "✓ ${track.label}" else track.label, TvIcons.captions) { player.selectSubtitleTrack(track.id) }
                        }
                    }
                }
                panelExtra?.invoke({ closePanel() }, if (firstTarget == PanelTarget.Extra) panelEntry else null)
            }
        }
    }
}

@Composable
private fun TrackRow(heading: String, isEntry: Boolean, @Suppress("UNUSED_PARAMETER") entry: FocusRequester, content: androidx.compose.foundation.lazy.LazyListScope.(Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(pt(12))) {
        Text(heading, style = TvType.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Bold), color = Color.White.copy(alpha = 0.6f))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(18)), contentPadding = PaddingValues(vertical = pt(6))) { content(isEntry) }
    }
}

@Composable
private fun PanelButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    TvButton(onClick, modifier, contentPadding = PaddingValues(horizontal = pt(26), vertical = pt(14))) {
        Icon(icon, null, Modifier.size(pt(28)))
        Text(title, style = TvType.body.copy(fontSize = 12.sp, fontWeight = FontWeight.SemiBold), maxLines = 1)
    }
}

@Composable
private fun TransportOverlay(
    model: TvPlaybackModel,
    player: StashPlayer,
    title: String,
    subtitle: String,
    scrubbing: Boolean,
    scrubTarget: Double,
    channelMode: Boolean,
    canGoPrevious: Boolean,
    canGoNext: Boolean,
) {
    val displayed = if (scrubbing) scrubTarget else player.currentTime
    Column(
        Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))))
            .padding(start = pt(80), end = pt(80), top = pt(40), bottom = pt(70)),
        verticalArrangement = Arrangement.spacedBy(pt(18)),
    ) {
        if (scrubbing) {
            model.sprites?.thumbnail(scrubTarget)?.let { image ->
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    androidx.compose.foundation.Image(
                        image, null,
                        Modifier.width(pt(320)).clip(RoundedCornerShape(pt(10))).border(1.dp, Color.White.copy(alpha = 0.6f), RoundedCornerShape(pt(10))),
                        contentScale = ContentScale.FillWidth,
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(pt(16))) {
            Text(title.ifEmpty { "Untitled Scene" }, Modifier.weight(1f, fill = false), style = TvType.title3.copy(fontSize = 17.sp, fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) Text(subtitle, Modifier.weight(1f, fill = false), style = TvType.body.copy(fontSize = 12.sp), color = Color.White.copy(alpha = 0.65f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.weight(1f))
            if (player.isUsingTranscodeFallback) {
                Text("Transcode", Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.15f)).padding(horizontal = pt(14), vertical = pt(6)),
                    style = TvType.caption.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = 0.8f))
            }
            Icon(if (player.isPlaying) TvIcons.play else TvIcons.pause, null, Modifier.size(pt(28)), tint = Color.White.copy(alpha = 0.8f))
        }
        val duration = player.duration.coerceAtLeast(0.001)
        val progress = (displayed / duration).coerceIn(0.0, 1.0).toFloat()
        Box(Modifier.fillMaxWidth().height(pt(8)).clip(CircleShape).background(Color.White.copy(alpha = 0.25f))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(progress).clip(CircleShape).background(if (scrubbing) Color.White else TvColors.tint))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(TvFormat.time(displayed), style = TvType.body.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.85f))
            Spacer(Modifier.weight(1f))
            if (channelMode) {
                Row(horizontalArrangement = Arrangement.spacedBy(pt(20))) {
                    val hint = TvType.caption.copy(fontSize = 10.sp)
                    if (canGoPrevious) Text("⏮ Hold ▲ Prev", style = hint, color = Color.White.copy(alpha = 0.5f))
                    if (canGoNext) Text("⏭ Hold ▼ Next", style = hint, color = Color.White.copy(alpha = 0.5f))
                    Text("▼ Options", style = hint, color = Color.White.copy(alpha = 0.5f))
                }
                Spacer(Modifier.weight(1f))
            }
            Text(TvFormat.time(player.duration.takeIf { it > 0 }), style = TvType.body.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.85f))
        }
    }
}

/** iOS: `TVPlayerErrorView` — the player could not be created; offers the way back. */
@Composable
fun TvPlayerError(message: String?, onDismiss: () -> Unit) {
    val focus = remember { FocusRequester() }
    BackHandler { onDismiss() }
    Column(Modifier.fillMaxSize().background(Color.Black), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24), Alignment.CenterVertically)) {
        Icon(TvIcons.warning, null, Modifier.size(pt(80)), tint = TvColors.secondary)
        Text("Unable to play this scene", style = TvType.title2.copy(fontWeight = FontWeight.Normal), color = Color.White.copy(alpha = 0.7f))
        if (message != null) Text(message, Modifier.padding(horizontal = pt(80)), style = TvType.callout, color = TvColors.secondary, textAlign = TextAlign.Center)
        TvButton(onDismiss, Modifier.focusRequester(focus)) { Text("Close", style = TvType.title3) }
    }
    TvRequestFocus(focus, "player.close")
}

// MARK: - Marker rail

/**
 * iOS: `TVMarkerRailView` — the scene's markers in the player's down panel; the marker that
 * holds the playhead is outlined, selecting one seeks there and closes the panel.
 */
@Composable
fun TvMarkerRail(markers: List<SceneMarker>, currentTime: Double, entry: FocusRequester?, onSelect: (SceneMarker) -> Unit, close: () -> Unit) {
    val sorted = remember(markers) { markers.sortedBy { it.seconds } }
    val active = activeMarkerIndex(sorted.map { it.seconds }, currentTime)
    Column(verticalArrangement = Arrangement.spacedBy(pt(12))) {
        Text("Markers", style = TvType.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Bold), color = Color.White.copy(alpha = 0.6f))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(10), vertical = pt(24))) {
            uniqueItemsIndexed(sorted, { it.id }) { i, marker ->
                val isActive = i == active
                Column(Modifier.width(pt(300))) {
                    TvCardButton({ onSelect(marker); close() }, if (i == 0 && entry != null) Modifier.focusRequester(entry) else Modifier, radius = pt(8)) {
                        Box(
                            Modifier.width(pt(300)).height(pt(169)).clip(RoundedCornerShape(pt(8)))
                                .then(if (isActive) Modifier.border(2.dp, TvColors.tint.copy(alpha = 0.9f), RoundedCornerShape(pt(8))) else Modifier),
                        ) {
                            TvImage(markerThumbnail(marker), Modifier.fillMaxSize(), TvIcons.bookmarkOutline)
                            Text(
                                TvFormat.time(marker.seconds),
                                Modifier.align(Alignment.BottomEnd).padding(pt(10)).clip(RoundedCornerShape(pt(6))).background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = pt(10), vertical = pt(4)),
                                style = TvType.caption.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold), color = Color.White,
                            )
                        }
                    }
                    Text(
                        marker.displayTitle, Modifier.padding(top = pt(10)),
                        style = TvType.caption.copy(fontSize = 11.sp, fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = if (isActive) 0.95f else 0.7f),
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** Marker screenshot URL (signed). */
fun markerThumbnail(marker: SceneMarker): String? = de.letzgo.stashy.data.Net.signed(marker.screenshot)

// MARK: - Routes

/** The single-scene player of the scene detail (iOS: its `fullScreenCover`). */
class TvScenePlayerRoute(private val model: TvPlaybackModel, private val sceneProvider: () -> Scene?) : TvRoute {
    override val key = "player.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()

    @Composable
    override fun Content() {
        val scene = model.scene ?: sceneProvider()
        TvPlayerScreen(
            model = model,
            title = scene?.displayTitle ?: "Untitled Scene",
            subtitle = scene?.studio?.name.orEmpty(),
            posterURL = scene?.thumbnailURL,
            onExit = { model.suspend(); TvNav.pop() },
            panelExtra = scene?.sceneMarkers?.takeIf { it.isNotEmpty() }?.let { markers ->
                { close, entry ->
                    TvMarkerRail(markers, model.player?.currentTime ?: 0.0, entry, { m -> model.seek(m.seconds); model.player?.play() }, close)
                }
            },
        )
    }

    override fun onRemoved() = model.clear()
}

/** iOS: `TVChannelPlayerView` — continuous playback with Prev/Next and the Up Next rail. */
class TvChannelPlayerRoute(channel: TvChannel) : TvRoute {
    private val session = TvChannelSession(channel)
    private var started = false
    override val key = "channel.${channel.id}.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!started) { started = true; session.start() } }
        val close = { session.stop(); TvNav.pop(); Unit }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val error = session.errorMessage
            when {
                error != null -> {
                    val focus = remember { FocusRequester() }
                    BackHandler { close() }
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
                        Icon(TvIcons.filmOutline, null, Modifier.size(pt(64)), tint = TvColors.secondary)
                        Text(error, style = TvType.title2.copy(fontWeight = FontWeight.Normal), color = TvColors.secondary)
                        TvButton(close, Modifier.focusRequester(focus)) { Text("Close", style = TvType.title3) }
                    }
                    TvRequestFocus(focus, "player.close")
                }
                session.player.hasPlayer -> {
                    val scene = session.currentScene
                    val label = session.indexLabel
                    TvPlayerScreen(
                        model = session.player,
                        title = scene?.displayTitle ?: "Untitled",
                        subtitle = if (label.isEmpty()) session.channel.title else "${session.channel.title} · $label",
                        posterURL = scene?.thumbnailURL,
                        onExit = close,
                        canGoPrevious = session.canGoPrevious,
                        canGoNext = session.canGoNext,
                        onPrevious = { session.playPrevious() },
                        onNext = { session.playNext() },
                        panelExtra = { closePanel, entry -> TvUpNextRail(session, entry, closePanel) },
                    )
                }
                else -> {
                    BackHandler { close() }
                    Box(Modifier.align(Alignment.Center)) { TvSpinner(pt(72)) }
                    // Focus anchor so Back reaches the handler while loading.
                    Box(Modifier.size(1.dp).focusable())
                }
            }
        }
    }

    override fun onRemoved() = session.teardown()
}

/** iOS: `TVChannelUpNextView` — what the channel plays next; selecting jumps there. */
@Composable
private fun TvUpNextRail(session: TvChannelSession, entry: FocusRequester?, close: () -> Unit) {
    val start = session.currentIndex + 1
    Box(Modifier.height(pt(360))) {
        if (start >= session.scenes.size) {
            LaunchedEffect(Unit) { session.loadMoreForBrowsing() }
            Text("End of channel", Modifier.align(Alignment.Center), style = TvType.title3, color = TvColors.secondary)
        } else {
            val entries = session.scenes.subList(start, session.scenes.size).toList()
            LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(50), vertical = pt(30))) {
                itemsIndexed(entries, key = { i, s -> "${start + i}-${s.id}" }) { i, scene ->
                    val index = start + i
                    LaunchedEffect(index) { if (index >= session.scenes.size - 3) session.loadMoreForBrowsing() }
                    TvSceneTile(
                        scene, { session.play(index, fromUpNext = true); close() },
                        if (i == 0 && entry != null) Modifier.focusRequester(entry) else Modifier,
                        width = pt(340), height = pt(191), showsFocusPreview = false,
                    )
                }
            }
        }
    }
}
