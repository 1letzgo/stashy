package de.letzgo.stashy.data

import de.letzgo.stashy.BuildConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * iOS: `SettingsTransferFile` — servers and app settings as one JSON file, shared with iOS / macOS
 * (format: `docs/settings-transfer-format.md`).
 */
@Serializable
data class SettingsTransferFile(
    val format: String = SettingsTransfer.FORMAT,
    val version: Int = SettingsTransfer.VERSION,
    val exportedAt: String = "",
    val app: AppInfo = AppInfo("android"),
    val includesSecrets: Boolean = false,
    val activeServerId: String? = null,
    val servers: List<Server> = emptyList(),
    val settings: List<Setting> = emptyList(),
) {
    @Serializable
    data class AppInfo(val platform: String, val version: String? = null, val build: String? = null)

    @Serializable
    data class Server(
        val id: String,
        val name: String,
        val serverAddress: String,
        val port: String? = null,
        val serverProtocol: String,
        val subpath: String? = null,
        val apiKey: String? = null,
        val customHeaders: List<Header>? = null,
    )

    @Serializable
    data class Header(val id: String? = null, val name: String, val value: String)

    @Serializable
    data class Setting(val key: String, val type: String, val value: JsonElement)
}

class SettingsTransferException(message: String) : Exception(message)

/** How an imported value is stored in `SharedPreferences`. */
sealed class StoredPref {
    data class BoolValue(val value: Boolean) : StoredPref()
    data class IntValue(val value: Int) : StoredPref()
    data class LongValue(val value: Long) : StoredPref()
    data class FloatValue(val value: Float) : StoredPref()
    data class StringValue(val value: String) : StoredPref()
    data class StringSetValue(val value: Set<String>) : StoredPref()
}

/** iOS: `SettingsTransfer` — the pure rules (filter, typing, file checks) plus export / import. */
object SettingsTransfer {
    const val FORMAT = "stashy-settings"
    const val VERSION = 1

    data class ImportSummary(val servers: Int, val settings: Int, val skipped: Int)

    val json = kotlinx.serialization.json.Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }

    // MARK: Which keys travel

    /** iOS `excludedKeys` plus Android's raw server-list copies. */
    private val excludedKeys = setOf(
        "stashy_server_config", "stashy_saved_servers", "stashy_saved_servers_backup", "stashy_saved_servers_unreadable",
        "totalTipsCount", "kBiometricsEnabled", "kAutoLockOnBackground",
    )

    /** iOS `excludedPrefixes` plus Android state: app lock, self-update, debug / beta switches. */
    private val excludedPrefixes = listOf(
        "stashy_plus_", "mini_player_last_", "cached", "SK", "revenuecat", "license",
        "passcode", "kPasscode", "NS", "Apple", "com.apple", "WebKit", "AK", "PK", "MSV",
        "app_passcode", "app_update_", "downloads_notification_permission",
    )

    fun isTransferable(key: String): Boolean {
        if (key in excludedKeys) return false
        val lower = key.lowercase()
        if ("license" in lower || "passcode" in lower || "debug" in lower || "beta" in lower) return false
        return excludedPrefixes.none { key.startsWith(it) }
    }

    // MARK: Export typing

    /** iOS `entry(for:value:)` for `SharedPreferences` values; null = no portable form. */
    fun exportEntry(key: String, value: Any?): SettingsTransferFile.Setting? = when (value) {
        is Boolean -> SettingsTransferFile.Setting(key, "bool", JsonPrimitive(value))
        is Int -> SettingsTransferFile.Setting(key, "int", JsonPrimitive(value.toLong()))
        is Long -> SettingsTransferFile.Setting(key, "int", JsonPrimitive(value))
        // Via the float's shortest text, so 0.4f travels as 0.4 and not 0.4000000059604645.
        is Float -> SettingsTransferFile.Setting(key, "double", JsonPrimitive(value.toString().toDouble()))
        is Double -> SettingsTransferFile.Setting(key, "double", JsonPrimitive(value))
        is String -> jsonCollection(value)?.let { SettingsTransferFile.Setting(key, "json", it) }
            ?: SettingsTransferFile.Setting(key, "string", JsonPrimitive(value))
        is Set<*> -> SettingsTransferFile.Setting(key, "array", JsonArray(value.filterIsInstance<String>().sorted().map { JsonPrimitive(it) }))
        else -> null
    }

    /** A string holding a JSON array / object (Android keeps encoded collections as strings). */
    private fun jsonCollection(text: String): JsonElement? {
        val t = text.trimStart()
        if (!t.startsWith("[") && !t.startsWith("{")) return null
        return runCatching { json.parseToJsonElement(text) }.getOrNull()?.takeIf { it is JsonArray || it is JsonObject }
    }

    // MARK: Import typing

    /**
     * iOS `apply(_:to:)` — how [entry] is stored here. A key that already exists locally keeps
     * its local type ([existing] = the current `SharedPreferences` value); null = skip.
     */
    fun resolveImport(entry: SettingsTransferFile.Setting, existing: Any?): StoredPref? {
        val v = entry.value
        return when (entry.type) {
            "bool" -> {
                val b = (v as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: return null
                if (existing is String) StoredPref.StringValue(b.toString()) else StoredPref.BoolValue(b)
            }
            "int", "double" -> {
                val p = (v as? JsonPrimitive)?.takeIf { !it.isString } ?: return null
                val d = p.doubleOrNull ?: return null
                if (p.booleanOrNull != null) return null
                when (existing) {
                    is Int -> StoredPref.IntValue(d.toLong().coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt())
                    is Long -> StoredPref.LongValue(d.toLong())
                    is Float -> StoredPref.FloatValue(d.toFloat())
                    is String -> StoredPref.StringValue(jsonNumber(d).content)
                    else -> when {
                        entry.type == "double" -> StoredPref.FloatValue(d.toFloat())
                        d != Math.floor(d) || d.isInfinite() -> StoredPref.FloatValue(d.toFloat())
                        d >= Int.MIN_VALUE && d <= Int.MAX_VALUE -> StoredPref.IntValue(d.toInt())
                        else -> StoredPref.LongValue(p.longOrNull ?: d.toLong())
                    }
                }
            }
            "string" -> {
                val s = (v as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
                when (existing) {
                    is Boolean -> s.toBooleanStrictOrNull()?.let { StoredPref.BoolValue(it) } ?: StoredPref.StringValue(s)
                    is Int -> s.toIntOrNull()?.let { StoredPref.IntValue(it) } ?: StoredPref.StringValue(s)
                    is Long -> s.toLongOrNull()?.let { StoredPref.LongValue(it) } ?: StoredPref.StringValue(s)
                    is Float -> s.toFloatOrNull()?.let { StoredPref.FloatValue(it) } ?: StoredPref.StringValue(s)
                    else -> StoredPref.StringValue(s)
                }
            }
            "json", "array", "dictionary" -> {
                if (v is JsonNull) return null
                if (existing is Set<*> && v is JsonArray && v.all { it is JsonPrimitive && it.isString }) {
                    return StoredPref.StringSetValue(v.map { (it as JsonPrimitive).content }.toSet())
                }
                // One-line JSON, the way the app writes these strings itself.
                StoredPref.StringValue(kotlinx.serialization.json.Json.encodeToString(JsonElement.serializer(), v))
            }
            else -> null
        }
    }

    // MARK: File

    /** Parses and checks a file: right format, not newer than this app understands. */
    fun parse(text: String): SettingsTransferFile {
        val file = runCatching { json.decodeFromString(SettingsTransferFile.serializer(), text) }
            .getOrElse { throw SettingsTransferException("This is not a stashy settings file.") }
        if (file.format != FORMAT) throw SettingsTransferException("This is not a stashy settings file.")
        if (file.version > VERSION) throw SettingsTransferException("This file was made by a newer stashy (format ${file.version}). Update the app first.")
        return file
    }

    /** Builds the file from preference entries and servers (pure; [export] feeds it). */
    fun buildFile(
        prefs: Map<String, *>,
        servers: List<SettingsTransferFile.Server>,
        activeServerId: String?,
        includeSecrets: Boolean,
        exportedAt: String,
        version: String?,
        build: String?,
    ): SettingsTransferFile = SettingsTransferFile(
        exportedAt = exportedAt,
        app = SettingsTransferFile.AppInfo("android", version, build),
        includesSecrets = includeSecrets,
        activeServerId = activeServerId,
        servers = servers,
        settings = prefs.keys.sorted().filter { isTransferable(it) }.mapNotNull { exportEntry(it, prefs[it]) },
    )

    /** A file server as a [ServerConfig]; null for an unknown protocol. */
    fun serverConfig(server: SettingsTransferFile.Server): ServerConfig? {
        val proto = ServerProtocol.entries.firstOrNull { it.name == server.serverProtocol.uppercase() } ?: return null
        if (server.id.isBlank()) return null
        return ServerConfig(
            id = server.id, name = server.name, serverAddress = server.serverAddress,
            port = server.port?.takeIf { it.isNotBlank() }, serverProtocol = proto, subpath = server.subpath?.takeIf { it.isNotBlank() },
        )
    }

    // MARK: Export / import (app state)

    fun export(includeSecrets: Boolean): String {
        val servers = ServerConfigManager.savedServers.map { c ->
            SettingsTransferFile.Server(
                id = c.id, name = c.name, serverAddress = c.serverAddress, port = c.port,
                serverProtocol = c.serverProtocol.name, subpath = c.subpath,
                apiKey = if (includeSecrets) c.apiKey else null,
                customHeaders = if (includeSecrets) c.customHeaders.takeIf { it.isNotEmpty() }?.map { SettingsTransferFile.Header(it.id, it.name, it.value) } else null,
            )
        }
        val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
        val file = buildFile(
            Prefs.prefs.all, servers, ServerConfigManager.activeConfig?.id, includeSecrets, stamp,
            BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString(),
        )
        return json.encodeToString(SettingsTransferFile.serializer(), file)
    }

    fun importFile(text: String): ImportSummary {
        val file = parse(text)
        var settings = 0
        var skipped = 0
        val current = Prefs.prefs.all
        val editor = Prefs.prefs.edit()
        for (entry in file.settings) {
            if (!isTransferable(entry.key)) continue
            when (val stored = resolveImport(entry, current[entry.key])) {
                null -> { skipped++; continue }
                is StoredPref.BoolValue -> editor.putBoolean(entry.key, stored.value)
                is StoredPref.IntValue -> editor.putInt(entry.key, stored.value)
                is StoredPref.LongValue -> editor.putLong(entry.key, stored.value)
                is StoredPref.FloatValue -> editor.putFloat(entry.key, stored.value)
                is StoredPref.StringValue -> editor.putString(entry.key, stored.value)
                is StoredPref.StringSetValue -> editor.putStringSet(entry.key, stored.value)
            }
            settings++
        }
        editor.commit()

        val imported = mutableListOf<ServerConfig>()
        for (server in file.servers) {
            val config = serverConfig(server) ?: run { skipped++; null } ?: continue
            val headers = server.customHeaders?.map { h ->
                ServerHTTPHeader(id = h.id?.takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString().uppercase(), name = h.name, value = h.value)
            }
            // Without secrets in the file, an existing key / headers of this server stay.
            ServerConfigManager.save(config, apiKey = server.apiKey?.takeIf { it.isNotBlank() } ?: config.apiKey, headers = headers)
            imported += config
        }
        val active = file.activeServerId?.let { id -> imported.firstOrNull { it.id == id } }
            ?: imported.firstOrNull()?.takeIf { ServerConfigManager.activeConfig == null }
        if (active != null) ServerConfigManager.activate(active)
        reloadAfterImport()
        return ImportSummary(imported.size, settings, skipped)
    }

    /** Lets the managers that cache settings pick up the new values (the rest after a restart). */
    private fun reloadAfterImport() {
        TabManager.reload()
        WatchlistStore.reload(ServerConfigManager.activeConfig?.id)
        CatalogPrefs.resetSession()
    }

    /** `stashy-settings-YYYY-MM-DD.json`. */
    fun defaultFileName(): String = "stashy-settings-" + SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()) + ".json"
}
