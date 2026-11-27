package de.letzgo.stashy.tv

import de.letzgo.stashy.data.ReelsModeType

/**
 * Pure logic of Android TV Feeds (no Compose, no Android), unit tested. Each piece names its
 * tvOS counterpart in `TVFeedSession.swift` / `TVFeedPlayerView.swift`.
 */
object TvFeedLogic {
    /** iOS `ReelsModeType.tvFeedModes`: Pics is an image slideshow, Verticals a phone feed. */
    val tvFeedModes = listOf(ReelsModeType.Scenes, ReelsModeType.Markers, ReelsModeType.Clips, ReelsModeType.Previews)

    /** iOS `tvEnabledFeedModes`: the Settings › Feeds order and switches, limited to [tvFeedModes]. Never empty. */
    fun enabledModes(enabled: List<ReelsModeType>): List<ReelsModeType> =
        enabled.filter { it in tvFeedModes }.ifEmpty { listOf(ReelsModeType.Scenes) }

    /** ◀ / ▶ step (iOS `TVFeedSession.seekStep`). */
    const val SEEK_STEP = 10.0

    /** iOS `TVRemoteSeekHoldRecognizer.minimumPressDuration`: a ◀ / ▶ held this long seeks continuously. */
    const val HOLD_THRESHOLD_MS = 400L

    /** iOS `TVHoldSeekSpeed.tick` (s). */
    const val HOLD_TICK = 0.15

    /** iOS `TVHoldSeekSpeed.secondsPerSecond(heldFor:)` — 20 → 60 → 180 s per second held. */
    fun holdSeekSpeed(heldFor: Double): Double = when {
        heldFor < 1.5 -> 20.0
        heldFor < 4.0 -> 60.0
        else -> 180.0
    }

    /** Info strip auto-hide after an item change (iOS `revealInfo`, 4 s). */
    const val INFO_SECONDS = 4.0

    /** An item whose player failed before its first frame is skipped after this grace (iOS 4 s). */
    const val UNPLAYABLE_GRACE_MS = 4_000L

    /**
     * iOS `seekRange`: a marker row moves inside its segment, every other row in the whole file
     * (0.5 s short of the end, so a seek never lands on the end itself).
     */
    fun seekRange(segmentStart: Double?, segmentEnd: Double?, duration: Double): ClosedFloatingPointRange<Double> {
        var lower = 0.0
        var upper = if (duration.isFinite() && duration > 0) duration - 0.5 else Double.MAX_VALUE
        if (segmentStart != null && segmentEnd != null) {
            lower = segmentStart
            upper = segmentEnd - 0.5
        }
        return lower..maxOf(lower, upper)
    }

    fun clamp(target: Double, range: ClosedFloatingPointRange<Double>): Double = target.coerceIn(range.start, range.endInclusive)

    /** iOS `positionLabel`: "3 / 120" with the server's total when it knows more than is loaded. */
    fun positionLabel(index: Int, loaded: Int, total: Int): String {
        if (loaded <= 0) return ""
        return "${index + 1} / ${if (total > loaded) total else loaded}"
    }

    /** iOS `loadMoreIfNeeded`: the next page once the playhead item is within 4 of the end. */
    fun needsMore(index: Int, count: Int): Boolean = index >= count - 4

    /** What a finished item (or a marker's segment end) does. */
    enum class EndAction { Next, Loop, AwaitPage }

    /**
     * iOS `handleReachedEnd`: continuous play moves on while there is a next item, otherwise loop.
     * Beyond tvOS (which replays the last loaded item while its next page is still loading): with
     * [morePages] the last item waits for that page and the feed moves on when it lands.
     */
    fun endAction(continuousPlay: Boolean, canGoNext: Boolean, morePages: Boolean = false): EndAction = when {
        !continuousPlay -> EndAction.Loop
        canGoNext -> EndAction.Next
        morePages -> EndAction.AwaitPage
        else -> EndAction.Loop
    }

    /**
     * iOS `engine.loopsAtEnd`: the player loops on its own only for rows that start at 0 and have
     * no segment; rows with a start position loop back to it themselves (the player would restart at 0).
     */
    fun playerLoops(hasSegment: Boolean, start: Double, continuousPlay: Boolean): Boolean =
        !hasSegment && start <= 0 && !continuousPlay

    /** A marker row ends this close before its segment end (iOS `segment.end - 0.15`). */
    fun reachedSegmentEnd(time: Double, segmentEnd: Double): Boolean = time >= segmentEnd - 0.15

    /** iOS `skipUnplayable`: the index that plays after the current row was dropped. */
    fun indexAfterRemoval(removedIndex: Int, newCount: Int): Int = removedIndex.coerceAtMost(maxOf(0, newCount - 1))

    /**
     * iOS `fetchIfNeeded` key: the sort + filter a mode's list was fetched with. A channel has its
     * own key, so leaving it for the Feeds defaults (or another channel) fetches anew.
     */
    fun loadKey(channelId: String?, channelSort: String?, sortRaw: String, filterId: String?): String =
        if (channelId != null) "channel|$channelId|$channelSort" else "$sortRaw|${filterId ?: "-"}"

    /** Rating dialog choices in stars, top first; 0 = "No Rating" (iOS `[5, 4, 3, 2, 1, 0]`). */
    val ratingChoices = listOf(5, 4, 3, 2, 1, 0)

    /** Stars → `rating100` written to Stash; 0 clears the rating (null). */
    fun rating100(stars: Int): Int? = stars.coerceIn(0, 5).takeIf { it > 0 }?.times(20)

    /** "−10 s" / "+10 s" (iOS `flashSeek`). */
    fun stepLabel(direction: Int): String = if (direction < 0) "−${SEEK_STEP.toInt()} s" else "+${SEEK_STEP.toInt()} s"

    /** Remote input of the pager, by Android key code (iOS `handleMove`, `onPlayPauseCommand`, Select). */
    enum class Key { Previous, Next, SeekBack, SeekForward, OpenOverlay, TogglePlay, Play, Pause, None }

    /**
     * The pager's key map with the overlay closed. D-pad: ▲ / ▼ previous / next item, ◀ / ▶ seek
     * (the caller turns a held ◀ / ▶ into continuous seeking), Select opens the overlay. Media keys:
     * Play/Pause, ⏭ / ⏮ next / previous item, ⏩ / ⏪ seek.
     */
    fun key(code: Int): Key = when (code) {
        android.view.KeyEvent.KEYCODE_DPAD_UP, android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS, android.view.KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD,
        android.view.KeyEvent.KEYCODE_CHANNEL_UP, android.view.KeyEvent.KEYCODE_PAGE_UP -> Key.Previous
        android.view.KeyEvent.KEYCODE_DPAD_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_NEXT, android.view.KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD,
        android.view.KeyEvent.KEYCODE_CHANNEL_DOWN, android.view.KeyEvent.KEYCODE_PAGE_DOWN -> Key.Next
        android.view.KeyEvent.KEYCODE_DPAD_LEFT, android.view.KeyEvent.KEYCODE_MEDIA_REWIND -> Key.SeekBack
        android.view.KeyEvent.KEYCODE_DPAD_RIGHT, android.view.KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> Key.SeekForward
        android.view.KeyEvent.KEYCODE_DPAD_CENTER, android.view.KeyEvent.KEYCODE_ENTER, android.view.KeyEvent.KEYCODE_NUMPAD_ENTER -> Key.OpenOverlay
        android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, android.view.KeyEvent.KEYCODE_HEADSETHOOK -> Key.TogglePlay
        android.view.KeyEvent.KEYCODE_MEDIA_PLAY -> Key.Play
        android.view.KeyEvent.KEYCODE_MEDIA_PAUSE -> Key.Pause
        else -> Key.None
    }

    /** True for the D-pad ◀ / ▶, which tell tap (step) from hold (continuous seek); media ⏪ / ⏩ always step. */
    fun isHoldSeekKey(code: Int): Boolean =
        code == android.view.KeyEvent.KEYCODE_DPAD_LEFT || code == android.view.KeyEvent.KEYCODE_DPAD_RIGHT
}
