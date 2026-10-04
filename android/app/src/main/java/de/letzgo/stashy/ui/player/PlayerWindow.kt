package de.letzgo.stashy.ui.player

import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.os.Build
import android.util.Rational
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.PictureInPictureModeChangedInfo
import androidx.core.util.Consumer
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import de.letzgo.stashy.MainActivity

/**
 * Window-level player chrome on `MainActivity` (no changes to the activity itself):
 * immersive fullscreen, orientation (iOS `requestGeometryUpdate` / `releaseOrientationOverride`)
 * and Picture in Picture (iOS `AVPictureInPictureController`; started only from the button,
 * never automatically, like iOS `canStartPictureInPictureAutomaticallyFromInline = false`).
 */
object PlayerWindow {
    /** True while the activity is in Picture-in-Picture mode; the scene renders only the video then. */
    var isInPictureInPicture by mutableStateOf(false)
        private set

    private var didOverrideOrientation = false

    /** Hides / shows status and navigation bars (the iOS fullscreen cover hides the status bar). */
    fun setImmersive(on: Boolean) {
        val activity = MainActivity.current ?: return
        val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        if (on) {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else controller.show(WindowInsetsCompat.Type.systemBars())
    }

    /** Landscape for landscape videos when fullscreen opens; portrait videos keep the device orientation. */
    fun lockLandscape(landscape: Boolean) {
        val activity = MainActivity.current ?: return
        didOverrideOrientation = true
        activity.requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    /** iOS rotate button: flips between portrait and landscape regardless of the rotation lock. */
    fun toggleOrientation() {
        val activity = MainActivity.current ?: return
        val landscape = activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        lockLandscape(!landscape)
    }

    /** iOS `releaseOrientationOverride` — back to the app's normal orientation when fullscreen closes. */
    fun releaseOrientation() {
        if (!didOverrideOrientation) return
        didOverrideOrientation = false
        MainActivity.current?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    fun enterPictureInPicture(videoSize: Pair<Int, Int>?): Boolean {
        val activity = MainActivity.current ?: return false
        val builder = PictureInPictureParams.Builder()
        videoSize?.let { (w, h) ->
            // Android caps PiP aspect ratios at 2.39:1 either way.
            val ratio = (w.toDouble() / h).coerceIn(1 / 2.39, 2.39)
            builder.setAspectRatio(Rational((ratio * 1000).toInt(), 1000))
        }
        if (Build.VERSION.SDK_INT >= 31) builder.setSeamlessResizeEnabled(true)
        return runCatching { activity.enterPictureInPictureMode(builder.build()) }.getOrDefault(false)
    }

    /** Tracks PiP mode for as long as the caller is composed. */
    @Composable
    fun ObservePictureInPicture() {
        DisposableEffect(Unit) {
            val activity = MainActivity.current
            val listener = Consumer<PictureInPictureModeChangedInfo> { isInPictureInPicture = it.isInPictureInPictureMode }
            activity?.addOnPictureInPictureModeChangedListener(listener)
            isInPictureInPicture = activity?.isInPictureInPictureMode == true
            onDispose { activity?.removeOnPictureInPictureModeChangedListener(listener) }
        }
    }
}
