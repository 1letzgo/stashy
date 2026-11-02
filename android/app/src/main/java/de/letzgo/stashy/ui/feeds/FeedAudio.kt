package de.letzgo.stashy.ui.feeds

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext

/**
 * iOS: `HardwareVolumeMonitor` / `UnmuteOnHardwareVolume`. A hardware volume press while muted
 * unmutes, seen through a settings observer on the media volume.
 */
@Composable
fun VolumeUnmuteEffect(isMuted: Boolean, onUnmute: () -> Unit) {
    val context = LocalContext.current
    val muted by rememberUpdatedState(isMuted)
    val unmute by rememberUpdatedState(onUnmute)
    DisposableEffect(Unit) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val handler = Handler(Looper.getMainLooper())

        // The first sample is the baseline (iOS `HardwareVolumeMonitor`).
        var lastVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val volumeObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                val v = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (v == lastVolume) return
                lastVolume = v
                if (muted) unmute()
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, volumeObserver)

        onDispose { context.contentResolver.unregisterContentObserver(volumeObserver) }
    }
}
