@file:OptIn(UnstableApi::class)

package de.letzgo.stashy.ui.player

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.await
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.util.UUID
import kotlin.math.min

/** Which rung of the source ladder plays (iOS: `AetherSceneEngine.SourceKind`). */
enum class SourceKind { Original, HlsTranscode, Mp4Transcode; val isTranscode get() = this != Original }

/** A selectable audio or subtitle track for the player's options menu (iOS: `TrackInfo`). */
data class PlayerTrack(val id: String, val label: String, val language: String?, val isExternal: Boolean = false)

/**
 * The scene player — Android replacement for iOS `AetherSceneEngine` (+ AetherEngine).
 *
 * iOS plays the ORIGINAL file of any codec through its own FFmpeg engine. Android uses Media3
 * ExoPlayer on the shared [Net.client] (OkHttpDataSource, so the `ApiKey` header, custom headers
 * and LAN self-signed TLS apply) and plays the original whenever the device can decode it. When it
 * cannot — container not recognised (WMV, AVI …), decoder init failure, no supported video/audio
 * track, or no first frame within 20 s — it walks the same transcode ladder iOS uses as fallback
 * ([fallbackSources]: Stash's `stream.m3u8` HLS transcode first, then the progressive
 * `stream.mp4?start=` transcode) and keeps the playhead. [isUsingTranscodeFallback] drives the
 * "Transcode" tag, [onTranscodeFallback] the toast.
 *
 * All state is Compose state, so surfaces just read it. Reusable outside the scene detail
 * (Feeds): construct with [Role.Preview] for a muted looping player without audio focus or media
 * session, set [loops] / [isMuted], [load] and put a [VideoSurface] on screen.
 */
class StashPlayer(context: Context, val role: Role = Role.Main) {
    enum class Role { Main, Preview }

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    val exo: ExoPlayer = ExoPlayer.Builder(appContext)
        .setRenderersFactory(DefaultRenderersFactory(appContext).setEnableDecoderFallback(true))
        .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(appContext, OkHttpDataSource.Factory(Net.client))))
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            role == Role.Main,
        )
        .setHandleAudioBecomingNoisy(role == Role.Main)
        .build()

    // MARK: Published state

    var currentTime by mutableDoubleStateOf(0.0); private set
    var duration by mutableDoubleStateOf(0.0); private set
    var isPlaying by mutableStateOf(false); private set
    var isBuffering by mutableStateOf(false); private set
    var hasFirstFrame by mutableStateOf(false); private set
    /** Latched once any frame of this title was shown; survives fallback reloads (iOS `hasPresentedFrame`). */
    var hasPresentedFrame by mutableStateOf(false); private set
    var didEnd by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    /** Display size of the picture (pixel aspect applied), null until known. */
    var videoSize by mutableStateOf<Pair<Int, Int>?>(null); private set
    var sourceKind by mutableStateOf(SourceKind.Original); private set
    val isUsingTranscodeFallback: Boolean get() = sourceKind.isTranscode
    var audioTracks by mutableStateOf<List<PlayerTrack>>(emptyList()); private set
    var activeAudioTrackId by mutableStateOf<String?>(null); private set
    var subtitleTracks by mutableStateOf<List<PlayerTrack>>(emptyList()); private set
    var activeSubtitleTrackId by mutableStateOf<String?>(null); private set
    /** The cue covering the playhead (embedded text track or a server caption). */
    var currentSubtitleText by mutableStateOf<String?>(null); private set
    var currentURL: String? = null; private set

    var isMuted: Boolean = false
        set(value) { field = value; exo.volume = if (value) 0f else 1f; mutedState = value }
    var mutedState by mutableStateOf(false); private set
    var rate: Float
        get() = rateState
        set(value) { rateState = value; exo.setPlaybackSpeed(value) }
    var rateState by mutableFloatStateOf(1f); private set
    var loops: Boolean = false
        set(value) { field = value; exo.repeatMode = if (value) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF }

    // MARK: Host knobs / callbacks

    /** Transcodes to fall back to, in order (iOS `Scene.transcodeFallbackURLs`). Empty disables the ladder. */
    var fallbackSources: List<String> = emptyList()
    /** Duration of the item for the progressive transcode rung (its origin cannot be measured). */
    var fallbackDeclaredDuration: Double? = null
    /** Pick the preferred subtitle track (Settings › Subtitles) once tracks are known. */
    var autoSelectsPreferredSubtitleTrack = false
    var onTime: ((Double, Double) -> Unit)? = null
    var onPlayingChanged: ((Boolean) -> Unit)? = null
    var onFirstFrame: (() -> Unit)? = null
    var onReachedEnd: (() -> Unit)? = null
    var onTranscodeFallback: ((SourceKind) -> Unit)? = null

    /** Set by [VideoSurface]; used for frame capture. */
    internal var textureView: TextureView? = null

    private var rung = -1
    private var switching = false
    private var sourceTimeOffset = 0.0
    private var lastAutoplay = true
    private var watchdog: Job? = null
    private var ticker: Job? = null
    private var externalCaptions = listOf<ExternalCaption>()
    private var externalCues: List<SubtitleCue> = emptyList()
    private var embeddedCueText: String? = null
    private var didAutoSelectSubtitle = false
    private var released = false
    private var session: MediaSession? = null

    private data class ExternalCaption(val track: PlayerTrack, val url: String)

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(playing: Boolean) {
            isPlaying = playing
            onPlayingChanged?.invoke(playing)
            // Only players that opted into background audio (phone) start the service; TV never does.
            if (playing && role == Role.Main && session != null) PlaybackService.ensureStarted(appContext)
        }

        override fun onPlaybackStateChanged(state: Int) {
            isBuffering = state == Player.STATE_BUFFERING
            if (state == Player.STATE_READY) { errorMessage = null; refreshDuration() }
            if (state == Player.STATE_ENDED) { didEnd = true; onReachedEnd?.invoke() }
        }

        override fun onRenderedFirstFrame() {
            watchdog?.cancel()
            if (!hasFirstFrame) { hasFirstFrame = true; hasPresentedFrame = true; onFirstFrame?.invoke() }
        }

        override fun onVideoSizeChanged(size: VideoSize) {
            if (size.width > 0 && size.height > 0) videoSize = (size.width * size.pixelWidthHeightRatio).toInt() to size.height
        }

        override fun onPlayerError(error: PlaybackException) {
            if (!escalate("player error: ${error.errorCodeName}")) {
                errorMessage = error.localizedMessage ?: "Playback failed"
            }
        }

        override fun onTracksChanged(tracks: Tracks) {
            if (tracks.groups.isEmpty()) return
            // Like the iOS ladder's "audio dropped, no pipeline": a type the file carries but the
            // device can't decode means the original can't play properly here.
            for (type in listOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO)) {
                val groups = tracks.groups.filter { it.type == type }
                if (groups.isNotEmpty() && groups.none { it.isSupported(true) }) {
                    if (escalate("no supported ${if (type == C.TRACK_TYPE_VIDEO) "video" else "audio"} track")) return
                }
            }
            publishTracks(tracks)
        }

        override fun onCues(cueGroup: CueGroup) {
            embeddedCueText = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n").trim().takeIf { it.isNotEmpty() }
            updateSubtitleText()
        }
    }

    init {
        exo.addListener(listener)
        if (role == Role.Preview) { isMuted = true }
        ticker = scope.launch {
            while (isActive) {
                tick()
                delay(if (role == Role.Main) 200 else 500)
            }
        }
    }

    // MARK: Loading

    /** Loads [url] (the original). Resets the ladder; [startAt] in seconds. */
    fun load(url: String, startAt: Double? = null, autoplay: Boolean = true) {
        rung = -1
        switching = false
        sourceKind = SourceKind.Original
        hasPresentedFrame = false
        externalCues = emptyList()
        didAutoSelectSubtitle = false
        performLoad(url, startAt, autoplay, SourceKind.Original)
    }

    private fun performLoad(url: String, startAt: Double?, autoplay: Boolean, kind: SourceKind) {
        currentURL = url
        lastAutoplay = autoplay
        hasFirstFrame = false
        didEnd = false
        errorMessage = null
        sourceKind = kind
        sourceTimeOffset = 0.0
        var target = url
        if (kind == SourceKind.Mp4Transcode && startAt != null && startAt > 0.25) {
            target = Uri.parse(url).buildUpon().appendQueryParameter("start", String.format(java.util.Locale.US, "%.3f", startAt)).build().toString()
            sourceTimeOffset = startAt
        }
        val item = MediaItem.Builder().setUri(target).setMediaMetadata(
            androidx.media3.common.MediaMetadata.Builder().setTitle(mediaTitle).setArtworkUri(mediaArtworkURL?.let { Uri.parse(it) }).build(),
        ).apply {
            if (kind == SourceKind.HlsTranscode || url.substringBefore('?').endsWith(".m3u8")) setMimeType(MimeTypes.APPLICATION_M3U8)
        }.build()
        exo.setMediaItem(item, if (kind != SourceKind.Mp4Transcode && startAt != null && startAt > 0) (startAt * 1000).toLong() else 0L)
        exo.prepare()
        exo.playWhenReady = autoplay
        armWatchdog(url)
    }

    /** iOS: `escalateToFallback` — next rung once, keeping playhead and transport intent. */
    private fun escalate(reason: String): Boolean {
        if (switching) return true
        val next = rung + 1
        if (next >= fallbackSources.size) return false
        val url = fallbackSources[next]
        val kind = if (url.substringBefore('?').endsWith(".m3u8")) SourceKind.HlsTranscode else SourceKind.Mp4Transcode
        val position = currentTime
        val autoplay = exo.playWhenReady || lastAutoplay
        switching = true
        watchdog?.cancel()
        android.util.Log.w("StashPlayer", "fallback → $kind: $reason")
        scope.launch {
            rung = next
            performLoad(url, position.takeIf { it > 0.25 }, autoplay, kind)
            switching = false
            onTranscodeFallback?.invoke(kind)
        }
        return true
    }

    private fun armWatchdog(url: String) {
        watchdog?.cancel()
        if (url.startsWith("file:") || rung + 1 >= fallbackSources.size || role != Role.Main) return
        watchdog = scope.launch {
            delay(FIRST_FRAME_WATCHDOG_MS)
            if (!hasFirstFrame && exo.playbackState != Player.STATE_ENDED) escalate("no first frame within 20s")
        }
    }

    // MARK: Transport

    fun play() { if (exo.playbackState == Player.STATE_ENDED) seek(0.0); exo.play() }
    fun pause() = exo.pause()
    fun togglePlayPause() = if (exo.playWhenReady && exo.playbackState != Player.STATE_ENDED) pause() else play()
    val playWhenReady: Boolean get() = exo.playWhenReady

    fun seek(seconds: Double) {
        val target = maxOf(0.0, seconds)
        currentTime = target
        if (sourceKind == SourceKind.Mp4Transcode) {
            // A progressive transcode can't seek: Stash serves a shifted one via `?start=`.
            performLoad(fallbackSources.getOrNull(rung) ?: return, target, exo.playWhenReady, SourceKind.Mp4Transcode)
        } else {
            exo.seekTo((target * 1000).toLong())
        }
    }

    fun stop() {
        exo.stop()
        exo.clearMediaItems()
        currentURL = null
        isPlaying = false
        hasFirstFrame = false
    }

    fun release() {
        if (released) return
        released = true
        watchdog?.cancel(); ticker?.cancel()
        scope.coroutineContext[Job]?.cancel()
        session?.let { PlaybackService.detach(it); it.release() }
        session = null
        exo.removeListener(listener)
        exo.release()
        textureView = null
    }

    // MARK: Media session (lock screen, notification, headset buttons, PiP controls)

    /** Exposes this player through a `MediaSession` + [PlaybackService] (background audio like iOS). */
    fun enableMediaSession() {
        if (session != null || role != Role.Main) return
        val s = MediaSession.Builder(appContext, exo).setId("stashy-" + UUID.randomUUID()).build()
        session = s
        PlaybackService.attach(s)
    }

    /** Title / artwork shown in the media notification; applied on the next [load]. */
    var mediaTitle: String? = null
    var mediaArtworkURL: String? = null

    // MARK: Tracks

    private fun publishTracks(tracks: Tracks) {
        val audio = mutableListOf<PlayerTrack>()
        var activeAudio: String? = null
        val embeddedText = mutableListOf<PlayerTrack>()
        var activeText: String? = null
        tracks.groups.forEachIndexed { g, group ->
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i, true)) continue
                val f = group.getTrackFormat(i)
                val id = "$g:$i"
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> {
                        val parts = listOfNotNull(f.label ?: f.language?.uppercase(), f.sampleMimeType?.substringAfter('/')?.uppercase(), f.channelCount.takeIf { it > 0 }?.let { "${it}ch" })
                        audio += PlayerTrack(id, parts.joinToString(" · ").ifEmpty { "Audio" }, f.language)
                        if (group.isTrackSelected(i)) activeAudio = id
                    }
                    C.TRACK_TYPE_TEXT -> {
                        var name = f.label ?: f.language?.uppercase() ?: "Subtitles"
                        if (f.selectionFlags and C.SELECTION_FLAG_FORCED != 0) name += " · Forced"
                        embeddedText += PlayerTrack(id, name, f.language)
                        if (group.isTrackSelected(i)) activeText = id
                    }
                }
            }
        }
        audioTracks = audio
        activeAudioTrackId = activeAudio
        subtitleTracks = embeddedText + externalCaptions.map { it.track }
        if (activeSubtitleTrackId?.startsWith("ext:") != true) activeSubtitleTrackId = activeText
        autoSelectSubtitleIfNeeded()
    }

    fun selectAudioTrack(id: String) {
        val (g, i) = id.split(":").map { it.toInt() }
        val group = exo.currentTracks.groups.getOrNull(g) ?: return
        exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i)).build()
        activeAudioTrackId = id
    }

    /** null = Off. Embedded tracks go through ExoPlayer, `ext:` tracks are fetched and drawn by us. */
    fun selectSubtitleTrack(id: String?) {
        activeSubtitleTrackId = id
        externalCues = emptyList()
        if (id == null || id.startsWith("ext:")) {
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
            embeddedCueText = null
            id?.let { loadExternal(it) }
        } else {
            val (g, i) = id.split(":").map { it.toInt() }
            val group = exo.currentTracks.groups.getOrNull(g) ?: return
            exo.trackSelectionParameters = exo.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i)).build()
        }
        updateSubtitleText()
    }

    fun clearSubtitle() = selectSubtitleTrack(null)

    /** iOS: `addExternalSubtitleTrack` — a server caption (Stash `paths.caption?lang=&type=`). */
    fun addExternalSubtitleTrack(url: String, name: String, language: String?) {
        val track = PlayerTrack("ext:${externalCaptions.size}", "$name · External", language, isExternal = true)
        externalCaptions = externalCaptions + ExternalCaption(track, url)
        subtitleTracks = subtitleTracks.filterNot { it.isExternal } + externalCaptions.map { it.track }
        autoSelectSubtitleIfNeeded()
    }

    private fun autoSelectSubtitleIfNeeded() {
        if (!autoSelectsPreferredSubtitleTrack || didAutoSelectSubtitle || activeSubtitleTrackId != null || isLiveCaptionsActive) return
        if (!PlayerSettings.subtitlesAutoEnabled || subtitleTracks.isEmpty()) return
        val preferred = PlayerSettings.subtitlePreferredLanguage
        val pick = if (preferred == "any") subtitleTracks.first()
        else subtitleTracks.firstOrNull { it.language?.lowercase()?.startsWith(preferred) == true } ?: return
        didAutoSelectSubtitle = true
        selectSubtitleTrack(pick.id)
    }

    private fun loadExternal(id: String) {
        val caption = externalCaptions.firstOrNull { it.track.id == id } ?: return
        scope.launch {
            val text = withContext(Dispatchers.IO) {
                runCatching { Net.client.newCall(Request.Builder().url(caption.url).build()).await().use { if (it.isSuccessful) it.body?.string() else null } }.getOrNull()
            }
            if (activeSubtitleTrackId != id) return@launch
            externalCues = WebVtt.parseCues(text.orEmpty())
            updateSubtitleText()
        }
    }

    private fun updateSubtitleText() {
        val id = activeSubtitleTrackId
        currentSubtitleText = when {
            id == null -> null
            id.startsWith("ext:") -> WebVtt.cueText(externalCues, currentTime)
            else -> embeddedCueText
        }
    }

    // MARK: AI captions (iOS: the live channel of `SubtitleController`)

    /** On-device captions own the subtitle overlay — one subtitle at a time. */
    var isLiveCaptionsActive by mutableStateOf(false); private set
    var liveCaptionText by mutableStateOf<String?>(null); private set

    /** What the subtitle overlay draws: the AI line while live captions run, else the track's cue. */
    val displayedSubtitleText: String? get() = if (isLiveCaptionsActive) liveCaptionText else currentSubtitleText

    /** iOS: `beginLiveCaptions` + `engine.clearSubtitle()`. */
    fun beginLiveCaptions() {
        if (activeSubtitleTrackId != null) clearSubtitle()
        isLiveCaptionsActive = true
        liveCaptionText = null
    }

    /** iOS: `pushLiveCaption` (timeline-synced: "" clears). */
    fun pushLiveCaption(text: String) {
        if (!isLiveCaptionsActive) return
        liveCaptionText = text.replace('\n', ' ').trim().ifEmpty { null }
    }

    fun endLiveCaptions() {
        isLiveCaptionsActive = false
        liveCaptionText = null
    }

    // MARK: Clock

    private fun refreshDuration() {
        val declared = fallbackDeclaredDuration
        duration = if (sourceKind == SourceKind.Mp4Transcode && declared != null && declared > 0) declared
        else exo.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.let { it / 1000.0 + sourceTimeOffset } ?: declared ?: 0.0
    }

    private fun tick() {
        if (released || currentURL == null) return
        val pos = exo.currentPosition / 1000.0 + sourceTimeOffset
        if (exo.playbackState != Player.STATE_IDLE) currentTime = pos
        refreshDuration()
        if (activeSubtitleTrackId?.startsWith("ext:") == true) updateSubtitleText()
        onTime?.invoke(currentTime, duration)
    }

    // MARK: Frame capture

    /** iOS: `captureFrame(at:maxSize:)` — the frame on screen, scaled into [maxSize]². */
    fun captureFrame(maxSize: Int = 1920): Bitmap? {
        val view = textureView ?: return null
        if (!view.isAvailable) return null
        val (w, h) = videoSize ?: (view.width to view.height)
        if (w <= 0 || h <= 0) return null
        val scale = min(1.0, maxSize.toDouble() / maxOf(w, h))
        return runCatching { view.getBitmap((w * scale).toInt().coerceAtLeast(1), (h * scale).toInt().coerceAtLeast(1)) }.getOrNull()
    }

    companion object {
        private const val FIRST_FRAME_WATCHDOG_MS = 20_000L
    }
}
