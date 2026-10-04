package de.letzgo.stashy.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * UserDefaults counterpart. Keys are the same strings as on iOS (incl. the per-server suffix
 * `<key>_<serverID>`), so settings logic can be ported 1:1.
 * [Secrets] replaces the Keychain (API keys, PIN hash, custom headers).
 */
object Prefs {
    lateinit var prefs: SharedPreferences
        private set
    lateinit var appContext: Context
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        prefs = context.getSharedPreferences("stashy", Context.MODE_PRIVATE)
        Secrets.init(context)
    }

    fun string(key: String): String? = prefs.getString(key, null)
    fun setString(key: String, value: String?) = prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun bool(key: String, default: Boolean = false) = prefs.getBoolean(key, default)
    fun setBool(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    fun int(key: String, default: Int = 0) = prefs.getInt(key, default)
    fun setInt(key: String, value: Int) = prefs.edit().putInt(key, value).apply()
    fun float(key: String, default: Float = 0f) = prefs.getFloat(key, default)
    fun setFloat(key: String, value: Float) = prefs.edit().putFloat(key, value).apply()
    fun has(key: String) = prefs.contains(key)
    fun remove(key: String) = prefs.edit().remove(key).apply()

    /** Per-server key like iOS (`"<key>_<serverID>"`). */
    fun serverKey(key: String): String =
        ServerConfigManager.activeConfig?.id?.let { "${key}_$it" } ?: key
}

/** Keychain counterpart: values encrypted with a Keystore master key. */
object Secrets {
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = try {
            val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
            EncryptedSharedPreferences.create(
                context, "stashy_secure", key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (e: Exception) {
            // Keystore broken (rare, e.g. after restore): fall back to private prefs.
            context.getSharedPreferences("stashy_secure_fallback", Context.MODE_PRIVATE)
        }
    }

    fun get(key: String): String? = prefs.getString(key, null)
    fun set(key: String, value: String?) = prefs.edit().apply { if (value.isNullOrEmpty()) remove(key) else putString(key, value) }.apply()
}
