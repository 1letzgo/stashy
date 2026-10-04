package de.letzgo.stashy.ui.player

import java.util.Locale
import kotlin.math.roundToLong

/** Pure formatting helpers of the player (iOS: `AetherTimeBar.formatTime`, `widestLabel`, `speedLabel`). */
object PlaybackFormat {
    /** iOS: `AetherTimeBar.formatTime` — `h:mm:ss` from an hour on, else `m:ss`; invalid → `0:00`. */
    fun time(seconds: Double): String {
        if (!seconds.isFinite() || seconds < 0) return "0:00"
        val total = seconds.toLong()
        val h = total / 3600; val m = (total % 3600) / 60; val s = total % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s) else String.format(Locale.US, "%d:%02d", m, s)
    }

    /** iOS: `AetherTimeBar.widestLabel(for:)` — the widest string [time] can produce for this duration. */
    fun widestLabel(duration: Double): String = when {
        duration >= 36000 -> "00:00:00"
        duration >= 3600 -> "0:00:00"
        duration >= 600 -> "00:00"
        else -> "0:00"
    }

    /** iOS: `AetherSceneSurface.speedLabel` — `1×`, `0.75×`, `1.5×`. */
    fun speedLabel(rate: Float): String {
        val rounded = (rate * 100).roundToLong() / 100.0
        val text = if (rounded == Math.rint(rounded)) rounded.toLong().toString()
        else rounded.toBigDecimal().stripTrailingZeros().toPlainString()
        return "$text×"
    }

    /** iOS: `AddMarkerSheet.formatTime` — `DateComponentsFormatter` positional, `.pad`, hours included (`0:01:05`). */
    fun markerTime(seconds: Double): String {
        val total = if (seconds.isFinite() && seconds > 0) seconds.toLong() else 0L
        val h = total / 3600; val m = (total % 3600) / 60; val s = total % 60
        return String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    }

    /** iOS: `AddMarkerSheet.parseTime` — plain seconds, `MM:SS` or `HH:MM:SS`; empty / zero → null. */
    fun parseTime(text: String): Double? {
        if (text.isEmpty()) return null
        text.toDoubleOrNull()?.let { return it }
        val parts = text.split(":").mapNotNull { it.trim().toDoubleOrNull() }.reversed()
        var total = 0.0; var multiplier = 1.0
        for (p in parts) { total += p * multiplier; multiplier *= 60 }
        return if (total > 0) total else null
    }

    /** iOS: cover / player menu quality label from the file height (`4K`, `1080p`, `720p`, `480p`). */
    fun resolutionLabel(height: Int?): String? {
        val h = height?.takeIf { it > 0 } ?: return null
        return when {
            h >= 2160 -> "4K"
            h >= 1080 -> "1080p"
            h >= 720 -> "720p"
            else -> "${h}p"
        }
    }
}
