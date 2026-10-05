package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.FeedsSceneStartPosition
import de.letzgo.stashy.data.Scene
import kotlin.random.Random

/**
 * Where a Feeds › Scenes row starts playing (Settings › Playback › "Feeds start position"), so
 * the feed does not open on studio intros. Pure — unit tested.
 */
object FeedStartPosition {
    const val SKIP_SECONDS = 30.0
    /** Shorter scenes always start at 0. */
    const val MIN_DURATION = 120.0
    /** A start this close to the end (or later) falls back to 0. */
    const val END_MARGIN = 5.0
    /** Random picks within this share of the duration. */
    const val RANDOM_SHARE = 0.5

    /**
     * Start in seconds: 0 for [FeedsSceneStartPosition.Beginning] (the default), square / vertical files (width <= height), scenes shorter than
     * [MIN_DURATION] (or of unknown duration) and when the computed start is within
     * [END_MARGIN] of the end. Otherwise the earliest marker (none → [SKIP_SECONDS]),
     * [SKIP_SECONDS], or a uniform pick in the first [RANDOM_SHARE] of the duration.
     */
    fun compute(
        setting: FeedsSceneStartPosition,
        duration: Double?,
        width: Int?,
        height: Int?,
        markerSeconds: List<Double>,
        random: Random = Random.Default,
    ): Double {
        val total = duration?.takeIf { it > 0 } ?: return 0.0
        if (width != null && height != null && width > 0 && height > 0 && width <= height) return 0.0
        if (total < MIN_DURATION) return 0.0
        val start = when (setting) {
            FeedsSceneStartPosition.Beginning -> 0.0
            FeedsSceneStartPosition.FirstMarker -> markerSeconds.filter { it >= 0 }.minOrNull() ?: SKIP_SECONDS
            FeedsSceneStartPosition.Skip30 -> SKIP_SECONDS
            FeedsSceneStartPosition.Random -> random.nextDouble() * total * RANDOM_SHARE
        }
        return if (start >= total - END_MARGIN) 0.0 else start
    }

    fun forScene(scene: Scene, setting: FeedsSceneStartPosition, random: Random = Random.Default): Double {
        val file = scene.files?.firstOrNull()
        return compute(setting, scene.sceneDuration, file?.width, file?.height, (scene.feedMarkerSeconds?.map { it.seconds } ?: scene.sceneMarkers.orEmpty().map { it.seconds }), random)
    }
}
