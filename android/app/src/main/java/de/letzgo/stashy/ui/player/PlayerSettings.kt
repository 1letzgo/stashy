package de.letzgo.stashy.ui.player

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.ui.graphics.Color
import de.letzgo.stashy.data.Prefs

/**
 * Read side of Settings › Playback (iOS: `TabManager` player properties). Same UserDefaults
 * keys and the same "stored value must be one of the options, else default" rule, so whatever
 * the Settings port writes (Int, Float, Long, Double-as-String or Boolean) is picked up here.
 */
object PlayerSettings {
    val skipOptions = listOf(5.0, 10.0, 15.0, 30.0)
    val holdSpeedOptions = listOf(1.5, 2.0, 2.5, 3.0, 4.0)
    val playCountThresholdOptions = listOf(0.0, 1.0, 5.0, 10.0, 30.0, 60.0, 120.0)
    /** iOS: `TabManager.autoZoomMaximumCrop`. */
    const val AUTO_ZOOM_MAXIMUM_CROP = 0.15
    /** iOS: `AetherSceneSurfaceConstants.speedOptions`. */
    val speedOptions = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)

    /** "Skip interval" (`playerSkipSeconds`, default 10). */
    val skipSeconds: Double get() = option("playerSkipSeconds", skipOptions, 10.0)
    /** "Skip buttons" (`showsPlayerSkipButtons`, default on). */
    val showsSkipButtons: Boolean get() = bool("showsPlayerSkipButtons", true)
    /** "Autozoom" (`playerAutoZoom`, default off). */
    val autoZoom: Boolean get() = bool("playerAutoZoom", false)
    /** "Hold to speed up — Player" (`hold_speed_player`, default 2×). */
    val holdSpeedPlayer: Double get() = option("hold_speed_player", holdSpeedOptions, 2.0)
    /** "Hold to speed up — Feeds" (`hold_speed_feeds`, default 2×). */
    val holdSpeedFeeds: Double get() = option("hold_speed_feeds", holdSpeedOptions, 2.0)
    /** "Count as played — Player" (`play_count_player_seconds`, default 1 s). */
    val playCountPlayerSeconds: Double get() = option("play_count_player_seconds", playCountThresholdOptions, 1.0)
    /** "Count as played — Feeds" (`play_count_feeds_seconds`, default 30 s). */
    val playCountFeedsSeconds: Double get() = option("play_count_feeds_seconds", playCountThresholdOptions, 30.0)
    /** Picture in Picture (`isPiPEnabled`, default on). */
    val isPiPEnabled: Boolean get() = bool("isPiPEnabled", true)

    // Subtitles (Settings › Playback › Subtitles)
    val subtitlesAutoEnabled: Boolean get() = bool("subtitle_auto_enabled", false)
    /** ISO 639-1 code or `any`. */
    val subtitlePreferredLanguage: String get() = Prefs.string("subtitle_preferred_language")?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: "any"
    /** iOS: `SubtitleFontSize.pointSize` (inline; fullscreen ×1.3). */
    val subtitleFontSize: Float get() = when (Prefs.string("subtitle_font_size")) {
        "small" -> 14f; "large" -> 22f; "extraLarge" -> 28f; else -> 18f
    }
    /** iOS: `SubtitleFontFamily.font` (`subtitle_font_family`; Rounded has no Android system face → default). */
    val subtitleFontFamily: androidx.compose.ui.text.font.FontFamily get() = when (Prefs.string("subtitle_font_family")) {
        "serif" -> androidx.compose.ui.text.font.FontFamily.Serif
        "monospaced" -> androidx.compose.ui.text.font.FontFamily.Monospace
        else -> androidx.compose.ui.text.font.FontFamily.Default
    }
    /** iOS: `SubtitleTextColorChoice.color`. */
    val subtitleTextColor: Color get() = when (Prefs.string("subtitle_text_color")) {
        "yellow" -> Color(1f, 0.87f, 0.25f); "cyan" -> Color(0.45f, 0.9f, 1f)
        "green" -> Color(0.45f, 0.95f, 0.5f); "black" -> Color.Black; else -> Color.White
    }
    /** iOS: `SubtitleBackgroundChoice.color` gated by `subtitle_box_enabled`; null = no box (halo). */
    val subtitleBoxColor: Color? get() {
        if (!bool("subtitle_box_enabled", true)) return null
        return when (Prefs.string("subtitle_background_color")) {
            "darkGray" -> Color(0.25f, 0.25f, 0.25f, 0.75f); "white" -> Color.White.copy(alpha = 0.75f)
            "none" -> null; else -> Color.Black.copy(alpha = 0.65f)
        }
    }

    internal fun number(key: String): Double? = when (val v = runCatching { Prefs.prefs.all[key] }.getOrNull()) {
        is Number -> v.toDouble()
        is String -> v.toDoubleOrNull()
        else -> null
    }

    private fun option(key: String, options: List<Double>, default: Double): Double =
        number(key)?.takeIf { it in options } ?: default

    private fun bool(key: String, default: Boolean): Boolean = when (val v = runCatching { Prefs.prefs.all[key] }.getOrNull()) {
        is Boolean -> v
        is String -> v.toBooleanStrictOrNull() ?: default
        else -> default
    }
}

/**
 * iOS: `ScenePlayerMute` — start-up mute state for every player embed. Without headphones
 * playback starts muted (unless Settings › Playback › "Start muted without headphones" is off);
 * otherwise the stored choice (`stashy_scene_player_muted`, default unmuted) applies.
 * [persist] only from an explicit user action (the mute button).
 */
object PlayerMute {
    const val KEY = "stashy_scene_player_muted"
    /** Settings › Playback › Player › "Start muted without headphones" (default on). */
    const val MUTE_WITHOUT_HEADPHONES_KEY = "playbackMuteWithoutHeadphones"

    val muteWithoutHeadphones: Boolean get() = Prefs.bool(MUTE_WITHOUT_HEADPHONES_KEY, true)

    /** The stored manual choice, or null when the user never toggled mute. */
    val storedMuted: Boolean? get() = if (Prefs.has(KEY)) Prefs.bool(KEY) else null

    /**
     * Pure start-up decision: without headphones (and the setting on) always muted, otherwise
     * the user's stored choice, defaulting to sound on.
     */
    fun decide(headphonesConnected: Boolean, muteWithoutHeadphones: Boolean, storedMuted: Boolean?): Boolean {
        if (!headphonesConnected && muteWithoutHeadphones) return true
        return storedMuted ?: false
    }

    fun initialValue(context: Context): Boolean =
        decide(isHeadphonesConnected(context), muteWithoutHeadphones, storedMuted)

    fun persist(muted: Boolean) = Prefs.setBool(KEY, muted)

    /** iOS: `isHeadphonesConnected()` — wired, USB or Bluetooth output. */
    fun isHeadphonesConnected(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val types = buildSet {
            add(AudioDeviceInfo.TYPE_WIRED_HEADPHONES); add(AudioDeviceInfo.TYPE_WIRED_HEADSET)
            add(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP); add(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            add(AudioDeviceInfo.TYPE_USB_HEADSET)
            if (android.os.Build.VERSION.SDK_INT >= 31) { add(AudioDeviceInfo.TYPE_BLE_HEADSET); add(AudioDeviceInfo.TYPE_BLE_SPEAKER) }
        }
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in types }
    }
}
