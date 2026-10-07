package de.letzgo.stashy.ui.player

import androidx.compose.foundation.layout.heightIn
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.ui.stashyGlass
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.min

/**
 * iOS: `AetherSceneSurface` — the scene player with its own transport (the engine has no system
 * controls): poster + spinner until the first frame, error label, subtitle overlay, centre group
 * (marker jumps · skip · play/pause · skip · marker jumps), top row (fullscreen / close, rotate,
 * PiP · options menu, volume capsule / mute), bottom (Transcode tag, fill button, add marker,
 * [TimeBar] with sprite scrub preview and marker dots). Single tap toggles the controls, double tap
 * on the outer thirds skips ±`playerSkipSeconds`, holding runs `hold_speed_player` forward (or
 * backwards on the left third). Controls hide after 5 s while playing.
 *
 * All seeks go through [onSeek], so the host's activity tracker sees them (iOS behaviour).
 */
@Composable
fun ScenePlayerSurface(
    player: StashPlayer,
    posterURL: String?,
    isMuted: Boolean,
    onMutedChange: (Boolean) -> Unit,
    onSeek: (Double) -> Unit,
    modifier: Modifier = Modifier,
    onToggleFullscreen: (() -> Unit)? = null,
    isFullscreen: Boolean = false,
    markers: List<TimeBarMarker> = emptyList(),
    onAddMarker: (() -> Unit)? = null,
    extraMenuItems: () -> List<PlayerMenuItem> = { emptyList() },
    /** iOS `subtitleMenuExtras` — the host's AI Subtitles submenu, right after Subtitles. */
    subtitleMenuExtras: () -> List<PlayerMenuItem> = { emptyList() },
    /** iOS `onHostSubtitleOff` — picking one of the video's tracks ends AI captions. */
    onHostSubtitleOff: () -> Unit = {},
    onOptionsMenuClosed: () -> Unit = {},
    scrubSprites: SceneScrubSprites? = null,
    onRotate: (() -> Unit)? = null,
    onPictureInPicture: (() -> Unit)? = null,
    showsControls: Boolean = true,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val seek by rememberUpdatedState(onSeek)
    val mutedNow by rememberUpdatedState(isMuted)
    val mutedChange by rememberUpdatedState(onMutedChange)

    var controlsVisible by remember { mutableStateOf(true) }
    var hideToken by remember { mutableIntStateOf(0) }
    var menuOpen by remember { mutableStateOf(false) }
    var isScrubbing by remember { mutableStateOf(false) }
    var scrubSeconds by remember { mutableStateOf(0.0) }
    var scrubImage by remember { mutableStateOf<ImageBitmap?>(null) }
    var fillsScreen by remember { mutableStateOf(false) }
    var isFastForwarding by remember { mutableStateOf(false) }
    var isRewinding by remember { mutableStateOf(false) }
    var rateBeforeFastForward by remember { mutableFloatStateOf(1f) }
    var rewindJob by remember { mutableStateOf<Job?>(null) }
    var wasPlayingBeforeRewind by remember { mutableStateOf(false) }
    var volumeLevel by remember { mutableFloatStateOf(systemVolume(context)) }

    val displayedTime = if (isScrubbing) scrubSeconds else player.currentTime
    val playing = player.isPlaying

    fun scheduleHide() {
        val token = ++hideToken
        if (menuOpen) return
        scope.launch {
            delay(5000)
            if (hideToken == token && !isScrubbing && !menuOpen && player.isPlaying) controlsVisible = false
        }
    }
    fun reveal() { controlsVisible = true; scheduleHide() }
    fun tick() = haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)

    fun skip(delta: Double) {
        tick()
        val d = player.duration
        val raw = player.currentTime + delta
        seek(if (d > 0) raw.coerceIn(0.0, d) else maxOf(0.0, raw))
        reveal()
    }

    fun setFastForwarding(active: Boolean) {
        if (active == isFastForwarding) return
        if (active) {
            if (!player.isPlaying) return
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            rateBeforeFastForward = player.rate
            // ExoPlayer runs any rate natively, so the iOS seek boost above 2× is not needed.
            player.rate = PlayerSettings.holdSpeedPlayer.toFloat()
        } else player.rate = rateBeforeFastForward
        isFastForwarding = active
    }

    fun setRewinding(active: Boolean) {
        if (active == isRewinding) return
        if (active) {
            if (!player.hasFirstFrame || player.currentTime <= 0) return
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            wasPlayingBeforeRewind = player.playWhenReady
            player.pause()
            var position = player.currentTime
            val step = 0.25 * PlayerSettings.holdSpeedPlayer
            isRewinding = true
            rewindJob = scope.launch {
                while (isActive) {
                    delay(250)
                    position = maxOf(0.0, position - step)
                    seek(position)
                    if (position <= 0) break
                }
            }
            return
        }
        rewindJob?.cancel(); rewindJob = null
        if (wasPlayingBeforeRewind) player.play()
        isRewinding = false
    }

    // Paused from outside: bring the controls up; playing again lets them fade.
    LaunchedEffect(playing) {
        if (playing) { if (controlsVisible) scheduleHide() }
        else if (!isRewinding && !isScrubbing && !isFastForwarding) controlsVisible = true
    }
    LaunchedEffect(player.hasFirstFrame) { if (player.hasFirstFrame) reveal() }
    LaunchedEffect(Unit) { player.autoSelectsPreferredSubtitleTrack = true; scheduleHide() }

    // Hardware volume buttons move the slider (and unmute, iOS `unmutesOnHardwareVolume`).
    // `Settings.System` fires for every system-settings write (rotation, brightness, …), not just
    // volume, so react only when the media stream's index really moved — comparing against the
    // slider's float level (rounded by `setSystemVolume`) unmuted the player and filled the
    // volume bar on an orientation change.
    DisposableEffect(Unit) {
        var lastIndex = systemVolumeIndex(context)
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                val index = systemVolumeIndex(context)
                if (index == lastIndex) return
                lastIndex = index
                val level = systemVolume(context)
                volumeLevel = level
                if (level > 0 && mutedNow) mutedChange(false)
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        onDispose {
            context.contentResolver.unregisterContentObserver(observer)
            rewindJob?.cancel()
        }
    }

    // Player chrome over video: text follows the font scale only up to OverlayMaxFontScale (1.3×).
    de.letzgo.stashy.ui.CappedFontScale {
    BoxWithConstraints(modifier.background(Color.Black)) {
        val surfaceW = maxWidth
        val surfaceH = maxHeight
        val isLandscape = surfaceW > surfaceH
        val isCompact = isFullscreen || surfaceH < 260.dp
        val skipSize = if (isCompact) 44.dp else 66.dp
        val playSize = if (isCompact) 64.dp else 96.dp
        val chrome = if (isCompact) 34.dp else 42.dp
        val glyph = if (isCompact) 15.dp else 18.dp
        val centerSpacing = if (isCompact) 24.dp else 70.dp
        val allowsFill = isFullscreen && isLandscape
        val source = player.videoSize

        // Autozoom (Settings › Playback): fill by itself while the crop stays ≤ 15 %.
        val cropFraction = source?.let { (w, h) ->
            val video = w.toDouble() / h; val screen = (surfaceW / surfaceH).toDouble()
            1 - min(video / screen, screen / video)
        }
        LaunchedEffect(allowsFill, cropFraction) {
            if (!allowsFill && fillsScreen) fillsScreen = false
            if (PlayerSettings.autoZoom && allowsFill && !fillsScreen && cropFraction != null && cropFraction <= PlayerSettings.AUTO_ZOOM_MAXIMUM_CROP) fillsScreen = true
        }
        // Fullscreen landscape: keep the controls inside a pillarboxed picture (min 520 pt wide).
        val horizontalInset: Dp = if (isFullscreen && !fillsScreen && source != null && isLandscape) {
            val videoW = min(surfaceW.value, surfaceH.value * source.first / source.second)
            val inset = maxOf(0f, (surfaceW.value - videoW) / 2)
            min(inset, maxOf(0f, (surfaceW.value - 520f) / 2)).dp
        } else 0.dp

        VideoSurface(player, Modifier.fillMaxSize(), fill = fillsScreen, showsBitmapSubtitles = true)

        if (!player.hasPresentedFrame) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (posterURL != null) AsyncImage(posterURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.size(32.dp))
            }
        }

        player.errorMessage?.let { msg ->
            Text(
                msg, Modifier.align(Alignment.BottomCenter).padding(bottom = 46.dp).clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.65f)).padding(horizontal = 10.dp, vertical = 6.dp),
                style = TextStyle(fontSize = 12.sp), color = Color.White, textAlign = TextAlign.Center, maxLines = 3,
            )
        }

        SubtitleOverlay(player.displayedSubtitleText, if (isFullscreen) 1.3f else 1f, Modifier.align(Alignment.BottomCenter))

        if (isFastForwarding || isRewinding) {
            Row(
                Modifier.align(Alignment.TopCenter).padding(top = if (isFullscreen) chrome + 28.dp else 12.dp)
                    .stashyGlass(RoundedCornerShape(50)).padding(horizontal = if (isCompact) 16.dp else 22.dp, vertical = if (isCompact) 10.dp else 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(if (isRewinding) PlayerIcons.fastRewind else PlayerIcons.fastForward, null, tint = Color.White, modifier = Modifier.size(if (isCompact) 22.dp else 32.dp))
                Text(PlaybackFormat.speedLabel(PlayerSettings.holdSpeedPlayer.toFloat()), color = Color.White, style = TextStyle(fontSize = if (isCompact) 15.sp else 20.sp, fontWeight = FontWeight.Bold))
            }
        }

        if (!showsControls) return@BoxWithConstraints

        // Tap regions: thirds; outer ones take a double tap (±skip) and holding rewinds / fast-forwards.
        Row(
            Modifier.fillMaxSize().pointerInput(allowsFill) {
                if (!allowsFill) return@pointerInput
                detectTransformGestures { _, _, zoom, _ ->
                    if (abs(zoom - 1f) > 0.1f) {
                        val fills = zoom > 1f
                        if (fills != fillsScreen) { fillsScreen = fills; reveal() }
                    }
                }
            },
        ) {
            listOf(-1, 0, 1).forEach { region ->
                Box(
                    Modifier.weight(1f).fillMaxHeight().pointerInput(region, player) {
                        detectTapGestures(
                            onDoubleTap = if (region != 0) { _ -> skip(region * PlayerSettings.skipSeconds) } else null,
                            onTap = { if (!menuOpen) { if (controlsVisible) { hideToken++; controlsVisible = false } else reveal() } },
                            onPress = {
                                val arm = scope.launch {
                                    delay(600)
                                    if (region == -1) setRewinding(true) else setFastForwarding(true)
                                }
                                tryAwaitRelease()
                                arm.cancel()
                                setFastForwarding(false)
                                setRewinding(false)
                            },
                        )
                    },
                )
            }
        }

        val controlsAlpha by animateFloatAsState(if (controlsVisible) 1f else 0f, tween(200), label = "controls")
        val hidden = controlsAlpha == 0f && !controlsVisible
        if (!hidden) Box(Modifier.fillMaxSize().alpha(controlsAlpha).padding(horizontal = horizontalInset)) {
            // Centre group.
            val markerSeconds = markers.map { it.seconds }.sorted()
            val showsMarkerJumps = markerSeconds.isNotEmpty() && player.hasPresentedFrame
            val previous = markerSeconds.lastOrNull { it < displayedTime - 1 }
            val next = markerSeconds.firstOrNull { it > displayedTime + 0.5 }
            Row(
                Modifier.align(Alignment.Center),
                horizontalArrangement = Arrangement.spacedBy(if (showsMarkerJumps) centerSpacing * 0.6f else centerSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (showsMarkerJumps) GlassCircle(PlayerIcons.previousMarker, skipSize, if (isCompact) 18.dp else 24.dp, "Previous marker", enabled = previous != null) { previous?.let { tick(); seek(it); reveal() } }
                if (PlayerSettings.showsSkipButtons) SkipButton(false, skipSize, isCompact) { skip(-PlayerSettings.skipSeconds) }
                val showsAsPlaying = isFastForwarding || playing || (player.playWhenReady && player.isBuffering)
                GlassCircle(if (showsAsPlaying) PlayerIcons.pause else PlayerIcons.play, playSize, if (isCompact) 30.dp else 44.dp, if (showsAsPlaying) "Pause" else "Play") {
                    tick(); player.togglePlayPause(); reveal()
                }
                if (PlayerSettings.showsSkipButtons) SkipButton(true, skipSize, isCompact) { skip(PlayerSettings.skipSeconds) }
                if (showsMarkerJumps) GlassCircle(PlayerIcons.nextMarker, skipSize, if (isCompact) 18.dp else 24.dp, "Next marker", enabled = next != null) { next?.let { tick(); seek(it); reveal() } }
            }

            // Top row.
            Row(
                Modifier.fillMaxWidth().align(Alignment.TopStart).padding(start = 16.dp, end = 16.dp, top = 12.dp),
                verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (onToggleFullscreen != null) {
                    GlassCircle(if (isFullscreen) PlayerIcons.close else PlayerIcons.expand, chrome, glyph, if (isFullscreen) "Close" else "Full screen") {
                        tick(); onToggleFullscreen(); reveal()
                    }
                }
                if (isFullscreen && onRotate != null) GlassCircle(PlayerIcons.rotate, chrome, glyph, "Rotate") { tick(); onRotate(); reveal() }
                if (onPictureInPicture != null && PlayerSettings.isPiPEnabled && supportsPiP(context)) {
                    GlassCircle(PlayerIcons.pipEnter, chrome, glyph, "Start Picture in Picture") { tick(); onPictureInPicture() }
                }
                Spacer(Modifier.weight(1f))
                Box {
                    GlassCircle(PlayerIcons.options, chrome, glyph, "More options") { menuOpen = true; reveal() }
                    if (abs(player.rateState - 1f) > 0.001f) {
                        Text(
                            PlaybackFormat.speedLabel(player.rateState), Modifier.align(Alignment.BottomCenter).padding(bottom = 1.dp),
                            style = TextStyle(fontSize = 8.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace), color = Color.White,
                        )
                    }
                    PlayerMenu(menuOpen, onDismiss = { menuOpen = false; onOptionsMenuClosed(); reveal() }) {
                        playerMenuItems(player, onChanged = { reveal() }, onHostSubtitleOff = onHostSubtitleOff) + subtitleMenuExtras() + extraMenuItems()
                    }
                }
                val showsSlider = !isCompact || isFullscreen
                val sliderWidth = when {
                    !showsSlider -> null
                    surfaceW > 560.dp -> 210.dp
                    surfaceW > 420.dp -> 130.dp
                    else -> null
                }
                if (sliderWidth != null) {
                    Row(
                        Modifier.width(sliderWidth).height(chrome).stashyGlass(RoundedCornerShape(50)).padding(start = 16.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        VolumeSlider(if (isMuted) 0f else volumeLevel, Modifier.weight(1f)) { level ->
                            volumeLevel = level
                            if (level > 0 && isMuted) onMutedChange(false)
                            setSystemVolume(context, level)
                            reveal()
                        }
                        MuteGlyph(isMuted, chrome, glyph) { tick(); PlayerMute.persist(!isMuted); onMutedChange(!isMuted); reveal() }
                    }
                } else {
                    Box(Modifier.size(chrome).stashyGlass(CircleShape)) {
                        MuteGlyph(isMuted, chrome, glyph) { tick(); PlayerMute.persist(!isMuted); onMutedChange(!isMuted); reveal() }
                    }
                }
            }

            // Bottom: options above the full-width time bar.
            Column(
                Modifier.fillMaxWidth().align(Alignment.BottomCenter).padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                    if (player.isUsingTranscodeFallback) {
                        Box(Modifier.heightIn(min = chrome).stashyGlass(RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 2.dp), contentAlignment = Alignment.Center) {
                            Text("Transcode", color = Color.White, style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold))
                        }
                    }
                    if (allowsFill) GlassCircle(if (fillsScreen) PlayerIcons.fit else PlayerIcons.fill, chrome, glyph, if (fillsScreen) "Fit to screen" else "Fill screen") {
                        tick(); fillsScreen = !fillsScreen; reveal()
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (onAddMarker != null) GlassCircle(PlayerIcons.addMarker, chrome, glyph, "Add marker") { tick(); onAddMarker(); reveal() }
                    TimeBar(
                        currentTime = displayedTime,
                        duration = maxOf(player.duration, 0.0),
                        isScrubbing = isScrubbing,
                        previewImage = scrubImage,
                        previewPlaceholderURL = posterURL,
                        previewAspectRatio = source?.let { (w, h) -> if (w > 0 && h > 0) w.toFloat() / h else null },
                        markers = markers,
                        isCompact = isCompact,
                        modifier = Modifier.weight(1f),
                        onScrubChanged = { s ->
                            scrubSprites?.prepare()
                            isScrubbing = true
                            scrubSeconds = s
                            scrubSprites?.thumbnail(s)?.let { scrubImage = it }
                            reveal()
                        },
                        onScrubEnded = { s ->
                            scrubSeconds = s
                            isScrubbing = false
                            scrubImage = null
                            seek(s)
                            reveal()
                        },
                    )
                }
            }
        }
    }
    }
}

/** Speed · Audio · Subtitles rows of the options menu (iOS `playerMenuItems`, before the host rows). */
fun playerMenuItems(player: StashPlayer, onChanged: () -> Unit = {}, onHostSubtitleOff: () -> Unit = {}): List<PlayerMenuItem> {
    val items = mutableListOf<PlayerMenuItem>()
    val rate = player.rateState
    items += PlayerMenuItem.Submenu(
        "player.speed",
        if (abs(rate - 1f) > 0.001f) "Playback Speed (${PlaybackFormat.speedLabel(rate)})" else "Playback Speed",
        PlayerIcons.speed,
        PlayerSettings.speedOptions.map { option ->
            PlayerMenuItem.Action("player.speed.$option", PlaybackFormat.speedLabel(option), isChecked = abs(rate - option) < 0.001f) {
                player.rate = option; onChanged()
            }
        },
    )
    if (player.audioTracks.size > 1) {
        items += PlayerMenuItem.Submenu("player.audio", "Audio", PlayerIcons.audio, player.audioTracks.map { t ->
            PlayerMenuItem.Action("player.audio.${t.id}", t.label, isChecked = player.activeAudioTrackId == t.id) { player.selectAudioTrack(t.id); onChanged() }
        })
    }
    if (player.subtitleTracks.isNotEmpty()) {
        val current = player.subtitleTracks.firstOrNull { it.id == player.activeSubtitleTrackId }?.label ?: "Off"
        items += PlayerMenuItem.Submenu(
            "player.subtitles", "Subtitles: $current", PlayerIcons.subtitles,
            listOf(PlayerMenuItem.Action("player.subtitle.off", "Off", isChecked = player.activeSubtitleTrackId == null) { player.clearSubtitle(); onChanged() }) +
                player.subtitleTracks.map { t ->
                    PlayerMenuItem.Action("player.subtitle.${t.id}", t.label, isChecked = player.activeSubtitleTrackId == t.id) { onHostSubtitleOff(); player.selectSubtitleTrack(t.id); onChanged() }
                },
        )
    }
    return items
}

/**
 * iOS: `StashySubtitleText` with the Settings › Subtitles style. A gap between two cues shorter
 * than 0.35 s is bridged instead of blanking the line.
 */
@Composable
fun SubtitleOverlay(text: String?, scale: Float, modifier: Modifier = Modifier) {
    var shown by remember { mutableStateOf(text) }
    LaunchedEffect(text) {
        if (text != null) shown = text else { delay(350); shown = null }
    }
    val line = shown ?: return
    val box = PlayerSettings.subtitleBoxColor
    val style = TextStyle(
        fontSize = (PlayerSettings.subtitleFontSize * scale).sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
        fontFamily = PlayerSettings.subtitleFontFamily,
        shadow = if (box == null) Shadow(Color.Black.copy(alpha = 0.9f), blurRadius = 3f * scale) else null,
    )
    Box(modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp)) {
        Text(
            line,
            Modifier.then(if (box != null) Modifier.clip(RoundedCornerShape((8 * scale).dp)).background(box).padding(horizontal = (12 * scale).dp, vertical = (7 * scale).dp) else Modifier),
            style = style, color = PlayerSettings.subtitleTextColor, maxLines = 3,
        )
    }
}

@Composable
private fun GlassCircle(icon: ImageVector, size: Dp, glyph: Dp, description: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(size).stashyGlass(CircleShape).alpha(if (enabled) 1f else 0.4f)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, description, tint = Color.White, modifier = Modifier.size(glyph)) }
}

@Composable
private fun SkipButton(forward: Boolean, size: Dp, compact: Boolean, onClick: () -> Unit) {
    val seconds = PlayerSettings.skipSeconds.toInt()
    Box(
        Modifier.size(size).stashyGlass(CircleShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(PlayerIcons.skip, if (forward) "Forward $seconds seconds" else "Back $seconds seconds", tint = Color.White,
            modifier = Modifier.size(if (compact) 30.dp else 40.dp).scale(scaleX = if (forward) -1f else 1f, scaleY = 1f))
        Text("$seconds", Modifier.offset(y = 1.dp), color = Color.White, style = TextStyle(fontSize = if (compact) 9.sp else 12.sp, fontWeight = FontWeight.Bold))
    }
}

@Composable
private fun MuteGlyph(muted: Boolean, size: Dp, glyph: Dp, onClick: () -> Unit) {
    Box(
        Modifier.size(size).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(if (muted) PlayerIcons.muted else PlayerIcons.unmuted, if (muted) "Unmute" else "Mute", tint = Color.White, modifier = Modifier.size(glyph)) }
}

/** Thin custom track (iOS draws its own: the stock slider can't be this thin). */
@Composable
private fun VolumeSlider(level: Float, modifier: Modifier, onChange: (Float) -> Unit) {
    val change by rememberUpdatedState(onChange)
    BoxWithConstraints(
        modifier.height(22.dp).pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown()
                val w = size.width.toFloat().coerceAtLeast(1f)
                change((down.position.x / w).coerceIn(0f, 1f))
                while (true) {
                    val e = awaitPointerEvent()
                    val c = e.changes.firstOrNull { it.id == down.id } ?: break
                    if (!c.pressed) break
                    change((c.position.x / w).coerceIn(0f, 1f)); c.consume()
                }
            }
        },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.3f)))
        Box(Modifier.fillMaxWidth(level.coerceIn(0f, 1f)).height(4.dp).clip(CircleShape).background(Color.White))
    }
}

private fun systemVolume(context: Context): Float {
    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
    return am.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max
}

private fun systemVolumeIndex(context: Context): Int =
    (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager).getStreamVolume(AudioManager.STREAM_MUSIC)

private fun setSystemVolume(context: Context, level: Float) {
    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    runCatching { am.setStreamVolume(AudioManager.STREAM_MUSIC, (level * max).toInt(), 0) }
}

private fun supportsPiP(context: Context) = context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
