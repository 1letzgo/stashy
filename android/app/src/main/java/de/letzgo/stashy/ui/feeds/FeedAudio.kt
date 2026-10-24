package de.letzgo.stashy.ui.feeds

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.ui.player.PlayerMute

/**
 * iOS: `ScenePlayerMute` + `HardwareVolumeMonitor` / `UnmuteOnHardwareVolume`.
 *
 * Without headphones playback starts muted (unless "Start muted without headphones" is off);
 * otherwise the stored choice (`stashy_scene_player_muted`, default unmuted) applies. Unplugging mutes at once, plugging in
 * restores the stored choice, and a hardware volume press while muted unmutes (and persists).
 */
object FeedAudio {
    const val MUTE_KEY = "stashy_scene_player_muted"

    private val headphoneTypes = buildSet {
        add(AudioDeviceInfo.TYPE_WIRED_HEADSET); add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES)
        add(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP); add(AudioDeviceInfo.TYPE_USB_HEADSET)
        if (Build.VERSION.SDK_INT >= 31) { add(AudioDeviceInfo.TYPE_BLE_HEADSET); add(AudioDeviceInfo.TYPE_BLE_SPEAKER) }
    }

    fun isHeadphonesConnected(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in headphoneTypes }
    }

    /** iOS: `ScenePlayerMute.initialValue()`. */
    fun initialMuted(context: Context): Boolean =
        PlayerMute.decide(isHeadphonesConnected(context), PlayerMute.muteWithoutHeadphones, PlayerMute.storedMuted)

    /** iOS: `ScenePlayerMute.persist(_:)` — only from explicit user actions. */
    fun persist(muted: Boolean) = Prefs.setBool(MUTE_KEY, muted)
}

/**
 * Keeps the feed's mute state tied to the audio route: AudioDeviceCallback +
 * ACTION_HEADSET_PLUG / ACTION_AUDIO_BECOMING_NOISY for headphones, and a settings observer on
 * the media volume for the hardware volume keys.
 */
@Composable
fun HeadphoneMuteEffect(isMuted: Boolean, onMutedChange: (Boolean) -> Unit) {
    val context = LocalContext.current
    val muted by rememberUpdatedState(isMuted)
    val setMuted by rememberUpdatedState(onMutedChange)
    DisposableEffect(Unit) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val handler = Handler(Looper.getMainLooper())
        var connected = FeedAudio.isHeadphonesConnected(context)

        fun reevaluate() {
            val now = FeedAudio.isHeadphonesConnected(context)
            if (now == connected) return
            connected = now
            // Unplugged: muted, unless "Start muted without headphones" is off (then the stored choice).
            setMuted(FeedAudio.initialMuted(context))
        }

        val deviceCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = reevaluate()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = reevaluate()
        }
        am.registerAudioDeviceCallback(deviceCallback, handler)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                    connected = false
                    setMuted(true)
                } else reevaluate()
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)

        // Hardware volume buttons: the first sample is the baseline (iOS `HardwareVolumeMonitor`).
        var lastVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val volumeObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                val v = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (v == lastVolume) return
                lastVolume = v
                if (muted) {
                    setMuted(false)
                    FeedAudio.persist(false)
                }
            }
        }
        context.contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, volumeObserver)

        onDispose {
            am.unregisterAudioDeviceCallback(deviceCallback)
            runCatching { context.unregisterReceiver(receiver) }
            context.contentResolver.unregisterContentObserver(volumeObserver)
        }
    }
}
