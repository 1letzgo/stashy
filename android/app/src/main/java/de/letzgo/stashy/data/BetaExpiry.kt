package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import de.letzgo.stashy.BuildConfig
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Beta expiry of sideload builds (`BuildConfig.EXPIRES_AT`, 0 = never; Play builds never expire).
 * The clock used is the later of the device clock and the latest `Date` header any server sent
 * ([recordServerDate], fed by [Net]) — turning the device clock back doesn't revive a build.
 */
object BetaExpiry {
    private const val TRUSTED_TIME_KEY = "beta_trusted_time"

    val expiresAt: Long get() = BuildConfig.EXPIRES_AT

    private val trustedTime: Long get() = Prefs.prefs.getLong(TRUSTED_TIME_KEY, 0L)

    fun now(): Long = maxOf(System.currentTimeMillis(), trustedTime)

    val isExpired: Boolean get() = expiresAt > 0 && now() > expiresAt

    /** Observable flag for the UI; [refresh] on start/resume and after server responses. */
    var expired by androidx.compose.runtime.mutableStateOf(isExpired)
        private set

    fun refresh() { expired = isExpired }

    /** Remaining whole days (null = no expiry). */
    val daysLeft: Long? get() = expiresAt.takeIf { it > 0 }?.let { ((it - now()) / 86_400_000L).coerceAtLeast(0) }

    val expiryText: String get() = SimpleDateFormat("d MMM yyyy", Locale.ENGLISH).format(Date(expiresAt))

    /** Called for every HTTP response; keeps the latest server time seen. */
    fun recordServerDate(header: String?) {
        if (expiresAt <= 0 || header == null) return
        val t = AppUpdate.parseHttpDate(header) ?: return
        if (t > trustedTime && t < System.currentTimeMillis() + 365L * 86_400_000L) {
            Prefs.prefs.edit().putLong(TRUSTED_TIME_KEY, t).apply()
        }
    }
}
