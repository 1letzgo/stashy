package de.letzgo.stashy.ui.player

/**
 * Settings › Playback › "Count as played": credits a play only once [thresholdSeconds] of
 * playback were actually watched in this session. Counts continuous playhead movement while
 * playing — never the playhead position itself (a resume at 5:00 is not 5 minutes watched)
 * and never a seek or skip distance. Pausing stops the accumulation. Each step counts at most
 * the wall-clock time that passed, so hold-to-fast-forward does not count double.
 *
 * Pure state machine: feed it [onTime] from the player clock (with a monotonic `now`, e.g.
 * `SystemClock.elapsedRealtime() / 1000.0`) and [noteSeek] on explicit seeks; [onTime] returns
 * true exactly once, when the credit is due.
 */
class PlayCountCredit(thresholdSeconds: Double) {
    var thresholdSeconds: Double = maxOf(0.0, thresholdSeconds)

    var watchedSeconds: Double = 0.0; private set
    var isCredited: Boolean = false; private set
    private var anchor: Double? = null
    private var anchorClock: Double? = null

    /** Player clock tick. Returns true when the play should be credited now (once). */
    fun onTime(position: Double, isPlaying: Boolean, now: Double): Boolean {
        if (isCredited) return false
        if (!position.isFinite() || position < 0) return false
        if (!isPlaying) {
            // Paused / buffering / loading: nothing counts, the next tick re-anchors.
            anchor = null
            anchorClock = null
            return false
        }
        val last = anchor
        val lastClock = anchorClock
        anchor = position
        anchorClock = now
        if (last != null && lastClock != null) {
            val delta = position - last
            val elapsed = now - lastClock
            if (delta > 0 && delta <= MAX_CONTINUOUS_DELTA && elapsed > 0) watchedSeconds += minOf(delta, elapsed)
        }
        return checkDue()
    }

    /** Called right when playback starts — a threshold of 0 ("immediately") credits here. */
    fun onStart(): Boolean {
        if (isCredited) return false
        return checkDue()
    }

    /** Explicit seek / skip: realign so the jumped gap is not counted as watched. */
    fun noteSeek() {
        // Re-anchored by the next playing tick: the jumped gap and the seek's own time never count.
        anchor = null
        anchorClock = null
    }

    /** New item / new session. */
    fun reset() {
        watchedSeconds = 0.0
        isCredited = false
        anchor = null
        anchorClock = null
    }

    private fun checkDue(): Boolean {
        if (watchedSeconds + EPSILON < thresholdSeconds) return false
        isCredited = true
        return true
    }

    companion object {
        /** Player ticks every 200–500 ms; a larger step is a seek/jump, not watching. */
        const val MAX_CONTINUOUS_DELTA = 2.0
        private const val EPSILON = 1e-6
    }
}
