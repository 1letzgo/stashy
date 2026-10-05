@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package de.letzgo.stashy.ui.feeds

import android.content.Context
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.IntSize
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import de.letzgo.stashy.data.Net

/** What one feed row wants played (iOS: `ReelItemData.videoURL` + engine options). */
data class FeedMediaRequest(
    val id: String,
    /** Primary source first, then the transcode fallbacks (iOS `fallbackSources`). */
    val sources: List<String>,
    /** iOS: `loopsAtEnd = !reelsContinuousPlay`. */
    val loop: Boolean,
    /**
     * Window of the source to play (Markers: the marker's part of the original scene). Media3
     * clips it natively, so `REPEAT_MODE_ONE` loops the segment, `STATE_ENDED` fires at its end
     * and the player's position / duration are relative to it.
     */
    val segment: FeedSegment? = null,
    /**
     * Where playback starts and every loop restarts (Scenes: Settings "Feeds start position"),
     * in player time. Unlike [segment] the file is not clipped, so the scrubber still spans the
     * whole scene and the intro stays reachable.
     */
    val startSeconds: Double = 0.0,
) {
    val startMs: Long get() = (startSeconds.coerceAtLeast(0.0) * 1000).toLong()
}

/**
 * Small pool of Media3 players for the Feeds tab (iOS: one `AetherSceneEngine` per row plus
 * `ReelsPlayerRegistry`). The active row and its neighbours ([PreloadWindow]) each get a player
 * that is prepared ahead of time, so a swipe lands on a decoded frame.
 *
 * All players fetch through `OkHttpDataSource.Factory(Net.client)` — auth headers, custom
 * headers and the LAN TLS rule apply; URLs are already `Net.signed`. Kept self-contained in
 * `ui/feeds/` so it can be swapped for the shared `ui/player/` engine later.
 */
class FeedPlayerPool(context: Context, val size: Int = 3) {
    private val appContext = context.applicationContext

    private inner class Slot(val player: ExoPlayer) : Player.Listener {
        var request: FeedMediaRequest? = null
        var sourceIndex = 0
        var lastUsed = 0L

        override fun onPlayerError(error: PlaybackException) {
            val req = request ?: return
            if (sourceIndex + 1 < req.sources.size) {
                // iOS: the engine walks the transcode ladder (m3u8, then mp4) before giving up.
                sourceIndex++
                load(this, keepPlayWhenReady = true)
            } else {
                failed[req.id] = true
                onUnplayable?.invoke(req.id)
            }
        }

        override fun onPlaybackStateChanged(state: Int) {
            val req = request ?: return
            if (state == Player.STATE_READY) {
                val d = player.duration
                if (d != C.TIME_UNSET && d > 0) durations[req.id] = d / 1000.0
            }
            if (state == Player.STATE_ENDED && !req.loop) onEnded?.invoke(req.id)
        }

        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            // REPEAT_MODE_ONE wrapped to 0: loop back to the row's start position instead.
            val req = request ?: return
            if (reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION && req.startMs > 0) player.seekTo(req.startMs)
        }

        override fun onRenderedFirstFrame() {
            request?.let { firstFrame[it.id] = true }
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            val req = request ?: return
            if (videoSize.width > 1 && videoSize.height > 1) {
                // Decoded size like iOS `playbackPresentationSize` (Media3 applies container rotation).
                val w = (videoSize.width * videoSize.pixelWidthHeightRatio).toInt()
                videoSizes[req.id] = IntSize(w, videoSize.height)
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            request?.let { playingIds[it.id] = isPlaying }
        }
    }

    // DefaultDataSource on top of OkHttp like `StashPlayer`: network through [Net.client], local
    // downloads (`file://`, scenes and markers of a downloaded scene) from disk.
    private val mediaSourceFactory = DefaultMediaSourceFactory(DefaultDataSource.Factory(appContext, OkHttpDataSource.Factory(Net.client)))
    private val slots = ArrayList<Slot>()

    /** Player per row id — observed by the rows to bind their video surface. */
    val assignments = mutableStateMapOf<String, ExoPlayer>()
    /** Rows that rendered a frame (poster hides then; iOS `ReelItemVideoSurfaceReadiness`). */
    val firstFrame = mutableStateMapOf<String, Boolean>()
    /** Decoded size per row (iOS `playbackPresentationSize`). */
    val videoSizes = mutableStateMapOf<String, IntSize>()
    val durations = mutableStateMapOf<String, Double>()
    val playingIds = mutableStateMapOf<String, Boolean>()
    /** Rows whose every source failed. */
    val failed = mutableStateMapOf<String, Boolean>()

    var onEnded: ((String) -> Unit)? = null
    var onUnplayable: ((String) -> Unit)? = null

    var muted by mutableStateOf(true)
        private set
    private var activeId: String? = null
    private var released = false

    private fun newPlayer(): ExoPlayer {
        // Feeds rows are short-lived: small buffers keep three players cheap.
        val loadControl = DefaultLoadControl.Builder().setBufferDurationsMs(2_000, 20_000, 500, 1_000).build()
        return ExoPlayer.Builder(appContext)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .build().apply {
                volume = if (muted) 0f else 1f
                setAudioAttributes(attributes, false)
            }
    }

    private val attributes = AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build()

    private fun mediaItem(url: String, segment: FeedSegment?): MediaItem {
        val builder = MediaItem.Builder().setUri(url)
        val path = android.net.Uri.parse(url).path.orEmpty()
        if (path.endsWith(".m3u8")) builder.setMimeType(MimeTypes.APPLICATION_M3U8)
        if (segment != null) {
            // ClippingMediaSource caps an end past the file's duration itself.
            builder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs((segment.start * 1000).toLong())
                    .setEndPositionMs((segment.end * 1000).toLong())
                    .build(),
            )
        }
        return builder.build()
    }

    private fun load(slot: Slot, keepPlayWhenReady: Boolean) {
        val req = slot.request ?: return
        val url = req.sources.getOrNull(slot.sourceIndex) ?: return
        val play = keepPlayWhenReady && slot.player.playWhenReady
        slot.player.setMediaItem(mediaItem(url, req.segment), req.startMs)
        slot.player.repeatMode = if (req.loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
        slot.player.prepare()
        slot.player.playWhenReady = play
    }

    /**
     * Binds the window of rows (priority order, see [PreloadWindow.indices]) to players: rows that
     * already own a player keep it, the rest take the least recently used free slot. Players of
     * rows that left the window are stopped. [active] plays when [playing], every other row is
     * paused at its start.
     */
    fun sync(window: List<FeedMediaRequest>, active: String?, playing: Boolean) {
        if (released) return
        val wanted = window.take(size)
        val wantedIds = wanted.map { it.id }.toSet()
        // Free slots whose row left the window.
        slots.forEach { s ->
            val id = s.request?.id
            if (id != null && id !in wantedIds) {
                s.player.stop(); s.player.clearMediaItems()
                assignments.remove(id); firstFrame.remove(id); playingIds.remove(id)
                s.request = null
            }
        }
        for (req in wanted) {
            var slot = slots.firstOrNull { it.request?.id == req.id }
            if (slot == null) {
                slot = slots.firstOrNull { it.request == null }
                    ?: if (slots.size < size) Slot(newPlayer()).also { s -> s.player.addListener(s); slots.add(s) } else null
                    ?: continue
                slot.request = req
                slot.sourceIndex = 0
                failed.remove(req.id)
                firstFrame.remove(req.id)
                assignments[req.id] = slot.player
                load(slot, keepPlayWhenReady = false)
            } else if (slot.request != req) {
                // Same row, new options (continuous play toggled).
                val newWindow = slot.request?.segment != req.segment
                val newStart = slot.request?.startMs != req.startMs
                slot.request = req
                slot.player.repeatMode = if (req.loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                // A different segment (marker edited) needs a re-clipped item.
                if (newWindow) { slot.sourceIndex = 0; load(slot, keepPlayWhenReady = true) }
                else if (newStart && req.id != activeId) slot.player.seekTo(req.startMs)
            }
            slot.lastUsed = SystemClock.elapsedRealtime()
        }
        activeId = active
        slots.forEach { s ->
            val isActive = s.request?.id != null && s.request?.id == active
            s.player.playWhenReady = isActive && playing
            // Rows off screen wait at their start position (0, or the Scenes start setting).
            val start = s.request?.startMs
            if (!isActive && start != null && s.player.currentPosition != start) s.player.seekTo(start)
        }
        applyAudio()
    }

    fun player(id: String?): ExoPlayer? = id?.let { assignments[it] }

    fun setPlaying(id: String?, playing: Boolean) {
        slots.forEach { it.player.playWhenReady = playing && it.request?.id == id && id != null }
    }

    /** iOS: `ReelsPlayerRegistry.pauseAll()`. */
    fun pauseAll() = slots.forEach { it.player.playWhenReady = false }

    fun seek(id: String?, seconds: Double) {
        val p = player(id) ?: return
        // Positions are relative to a clipped segment, so its duration bounds every seek.
        val max = p.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: Long.MAX_VALUE
        p.seekTo((seconds * 1000).toLong().coerceIn(0, max))
    }

    /** Hold-to-speed (iOS: `aether.rate`). Media3 plays any rate natively. */
    fun setRate(id: String?, rate: Float) {
        player(id)?.setPlaybackSpeed(rate)
    }

    fun updateMuted(value: Boolean) {
        muted = value
        applyAudio()
    }

    /** Only the audible active player takes audio focus (iOS: playback vs ambient session). */
    private fun applyAudio() {
        slots.forEach { s ->
            s.player.volume = if (muted) 0f else 1f
            val audible = !muted && s.request?.id == activeId && activeId != null
            s.player.setAudioAttributes(attributes, audible)
        }
    }

    /** iOS: `reelsTeardownAllPlayers` — stop and forget every row (Pics mode, mode switch). */
    fun teardown() {
        slots.forEach { s -> s.player.stop(); s.player.clearMediaItems(); s.request = null }
        assignments.clear(); firstFrame.clear(); playingIds.clear()
    }

    fun release() {
        released = true
        teardown()
        slots.forEach { it.player.release() }
        slots.clear()
    }
}
