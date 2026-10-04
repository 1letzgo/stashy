package de.letzgo.stashy.ui.player

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * iOS: `ScenePlaybackActivityTracker` — accumulates watched seconds and reports deltas via
 * [onSave] (`sceneSaveActivity`), like Stash web's `trackActivity`. Only continuous playhead
 * movement counts; seeks and skips do not add the jumped gap. Saves every 10 s of watch time,
 * on [stop] and on [flush]. Resume is cleared (0) at ≥ 98 %.
 *
 * Reusable by Feeds: set [updatesResumeTime] = false for marker streams.
 */
class PlaybackActivityTracker(private val scope: CoroutineScope) {
    /** `(resumeTime?, playDurationDelta)`; resume is null when it should not be updated. */
    var onSave: ((Double?, Double) -> Unit)? = null
    var updatesResumeTime = true

    private var job: Job? = null
    private var totalPlayDuration = 0.0
    private var pendingPlayDuration = 0.0
    private var currentTime = 0.0
    private var lastMediaTime: Double? = null
    private var duration = 0.0

    val isRunning: Boolean get() = job != null

    fun setPosition(currentTime: Double, duration: Double) {
        if (currentTime.isFinite() && currentTime >= 0) {
            val last = lastMediaTime
            if (last != null) {
                val jump = currentTime - last
                if (jump < -0.25 || jump > MAX_CONTINUOUS_DELTA) lastMediaTime = currentTime
            } else lastMediaTime = currentTime
            this.currentTime = currentTime
        }
        if (duration.isFinite() && duration > 0) this.duration = duration
    }

    /** Realign after an explicit seek so the skipped range is not counted as watched. */
    fun noteSeek(time: Double) {
        if (!time.isFinite() || time < 0) return
        currentTime = time
        lastMediaTime = time
    }

    fun start() {
        if (job != null) return
        lastMediaTime = currentTime
        job = scope.launch {
            while (isActive) {
                delay(TICK_MS)
                tick()
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        flush()
    }

    fun reset() {
        stop()
        totalPlayDuration = 0.0; pendingPlayDuration = 0.0; currentTime = 0.0; lastMediaTime = null; duration = 0.0
    }

    /** Forces a save (screen left) even if the 10 s interval has not elapsed. */
    fun flush() {
        if (totalPlayDuration <= 0) return
        val delta = pendingPlayDuration
        pendingPlayDuration = 0.0
        var resume: Double? = null
        if (updatesResumeTime) {
            resume = currentTime
            if (duration > 0 && (100.0 / duration) * currentTime >= COMPLETED_RESUME_PERCENT) resume = 0.0
        }
        onSave?.invoke(resume, delta)
    }

    /** One timer tick (1 s on the timer; called directly by the unit tests). */
    internal fun tick() {
        val media = currentTime
        val last = lastMediaTime ?: media
        lastMediaTime = media
        val delta = media - last
        if (delta <= 0 || delta > MAX_CONTINUOUS_DELTA) return
        totalPlayDuration += delta
        pendingPlayDuration += delta
        if (pendingPlayDuration >= SEND_INTERVAL_SECONDS) flush()
    }

    companion object {
        private const val TICK_MS = 1000L
        private const val SEND_INTERVAL_SECONDS = 10.0
        private const val COMPLETED_RESUME_PERCENT = 98.0
        private const val MAX_CONTINUOUS_DELTA = 4.0
    }
}
