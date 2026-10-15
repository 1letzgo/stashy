package de.letzgo.stashy.ui.player

import android.app.Activity
import android.os.Looper
import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.media3.common.Player
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Pure keep-screen-on decision (unit-tested). A player keeps the display awake while it intends
 * to play: `playWhenReady`, content loaded (ready or buffering — a short stall must not let the
 * screen dim) and not suppressed (e.g. transient audio-focus loss). Paused, ended, idle or
 * errored players let the screen dim again. Volume does not matter: muted Feeds playback counts.
 */
object ScreenAwakePolicy {
    fun wantsAwake(playWhenReady: Boolean, playbackState: Int, suppressed: Boolean): Boolean =
        playWhenReady && !suppressed &&
            (playbackState == Player.STATE_READY || playbackState == Player.STATE_BUFFERING)
}

/**
 * Set of holders that currently want the screen on (pure, unit-tested). The screen stays on while
 * at least one holder is awake; removing a holder (player released) always drops its vote, so a
 * closed player can never keep the screen on.
 */
class ScreenAwakeRegistry {
    private val awake = HashSet<Any>()

    val isAwake: Boolean get() = awake.isNotEmpty()

    /** Records [holder]'s vote; returns the resulting overall state. */
    fun update(holder: Any, wantsAwake: Boolean): Boolean {
        if (wantsAwake) awake.add(holder) else awake.remove(holder)
        return isAwake
    }

    fun remove(holder: Any): Boolean = update(holder, false)
}

/**
 * App-wide "a video is playing" switch (iOS `isIdleTimerDisabled`). Players report through
 * [ScreenAwakeCoordinator]; [MainActivity] / [TvActivity] mirror [keepOn] into
 * `FLAG_KEEP_SCREEN_ON` while they are started (see [bind]). Main thread only.
 */
object ScreenAwake {
    private val registry = ScreenAwakeRegistry()
    private val state = MutableStateFlow(false)
    val keepOn: StateFlow<Boolean> = state.asStateFlow()

    fun update(holder: Any, wantsAwake: Boolean) {
        check(Looper.myLooper() == Looper.getMainLooper()) { "ScreenAwake is main-thread only" }
        state.value = registry.update(holder, wantsAwake)
    }

    fun remove(holder: Any) = update(holder, false)

    /** Mirrors [keepOn] into the window flag while [activity] is started; clears it on stop. */
    fun <A> bind(activity: A) where A : Activity, A : LifecycleOwner {
        activity.lifecycleScope.launch {
            try {
                activity.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                    try {
                        keepOn.collect { apply(activity, it) }
                    } finally {
                        apply(activity, false)
                    }
                }
            } finally {
                apply(activity, false)
            }
        }
    }

    private fun apply(activity: Activity, on: Boolean) {
        val window = activity.window ?: return
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}

/**
 * Keeps the screen on while [player] plays (see [ScreenAwakePolicy]). Attach to every full
 * playback player (scene, TV, Feeds, image / gallery videos) — never to muted card previews.
 * Call [release] before `player.release()`.
 */
class ScreenAwakeCoordinator(private val player: Player) : Player.Listener {
    private var released = false

    init {
        player.addListener(this)
        evaluate()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) = evaluate()
    override fun onPlaybackStateChanged(playbackState: Int) = evaluate()
    override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) = evaluate()
    override fun onIsPlayingChanged(isPlaying: Boolean) = evaluate()

    private fun evaluate() {
        if (released) return
        ScreenAwake.update(
            this,
            ScreenAwakePolicy.wantsAwake(
                playWhenReady = player.playWhenReady,
                playbackState = player.playbackState,
                suppressed = player.playbackSuppressionReason != Player.PLAYBACK_SUPPRESSION_REASON_NONE,
            ),
        )
    }

    fun release() {
        if (released) return
        released = true
        player.removeListener(this)
        ScreenAwake.remove(this)
    }
}
