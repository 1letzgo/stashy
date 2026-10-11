@file:OptIn(UnstableApi::class)

package de.letzgo.stashy.ui.player

import android.os.Handler
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/**
 * Pure audio-focus decision (unit-tested). A player only holds the OS audio focus while it is
 * actually audible: allowed to take focus, `playWhenReady` and a volume above zero. Muted or
 * not-playing players must leave other apps (Spotify, podcasts) alone.
 */
object AudioFocusPolicy {
    enum class Action {
        /** Hand focus handling to Media3 now (it requests focus as playback is audible). */
        Acquire,
        /** Drop focus now (muted, not allowed, idle). */
        Release,
        /** Paused but still audible: drop focus after a grace period unless playback resumes. */
        ReleaseLater,
        /** Nothing to change. */
        Keep,
    }

    fun wantsFocus(allowed: Boolean, playWhenReady: Boolean, volume: Float): Boolean =
        allowed && playWhenReady && volume > 0f

    /**
     * Next step for a player that currently [holding] focus handling. A plain pause keeps focus
     * for a short grace period (quick pause / resume must not bounce other apps' focus), while
     * mute, disallow or a player without content releases immediately.
     */
    fun next(
        holding: Boolean,
        allowed: Boolean,
        playWhenReady: Boolean,
        volume: Float,
        idle: Boolean = false,
        ended: Boolean = false,
    ): Action {
        // At the end Media3 keeps playWhenReady = true: count that as paused, not as playing.
        val playing = playWhenReady && !ended
        if (wantsFocus(allowed, playing, volume) && !idle) return if (holding) Action.Keep else Action.Acquire
        if (!holding) return Action.Keep
        val audibleButPaused = allowed && volume > 0f && !playing && !idle
        return if (audibleButPaused) Action.ReleaseLater else Action.Release
    }
}

/**
 * Lazy audio focus for one [ExoPlayer]: every player is built with `handleAudioFocus = false`
 * and this switches Media3's own focus handling on only while playback is audible, so opening
 * the app, card previews and muted Feeds/scene playback never pause other apps' audio.
 * Unmuting mid-playback acquires focus; muting releases it at once, pausing after [pauseGraceMs].
 * Media3 keeps doing the rest (ducking, pause on loss); becoming-noisy is configured separately.
 */
class AudioFocusCoordinator(
    private val player: ExoPlayer,
    private val attributes: AudioAttributes = MEDIA_ATTRIBUTES,
    allowed: Boolean = true,
    private val pauseGraceMs: Long = PAUSE_GRACE_MS,
) : Player.Listener {
    private val handler = Handler(player.applicationLooper)
    private var holding = false
    private var released = false
    private var releasePending = false
    private val delayedRelease = Runnable { releasePending = false; apply(false) }

    /** Whether this player may take focus at all (Feeds: only the active row). */
    var allowed: Boolean = allowed
        set(value) { if (field != value) { field = value; evaluate() } }

    init {
        player.setAudioAttributes(attributes, false)
        player.addListener(this)
        evaluate()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = evaluate()
    override fun onVolumeChanged(volume: Float) = evaluate()
    override fun onPlaybackStateChanged(playbackState: Int) = evaluate()

    fun evaluate() {
        if (released) return
        val action = AudioFocusPolicy.next(
            holding = holding,
            allowed = allowed,
            playWhenReady = player.playWhenReady,
            volume = player.volume,
            idle = player.playbackState == Player.STATE_IDLE,
            ended = player.playbackState == Player.STATE_ENDED,
        )
        when (action) {
            AudioFocusPolicy.Action.Acquire -> apply(true)
            AudioFocusPolicy.Action.Release -> apply(false)
            AudioFocusPolicy.Action.ReleaseLater -> if (!releasePending) {
                releasePending = true
                handler.postDelayed(delayedRelease, pauseGraceMs)
            }
            AudioFocusPolicy.Action.Keep -> cancelPendingRelease()
        }
    }

    private fun cancelPendingRelease() {
        releasePending = false
        handler.removeCallbacks(delayedRelease)
    }

    private fun apply(handle: Boolean) {
        cancelPendingRelease()
        if (released || holding == handle) return
        holding = handle
        // Media3 requests focus when handling turns on during playWhenReady, abandons it when off.
        player.setAudioAttributes(attributes, handle)
    }

    /** Detach before `player.release()` (which abandons any held focus itself). */
    fun release() {
        if (released) return
        cancelPendingRelease()
        player.removeListener(this)
        released = true
    }

    companion object {
        const val PAUSE_GRACE_MS = 15_000L
        val MEDIA_ATTRIBUTES: AudioAttributes =
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build()
    }
}
