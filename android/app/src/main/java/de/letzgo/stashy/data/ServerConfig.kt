package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.BuildConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.util.UUID

/** iOS: `ServerProtocol` (raw values identical). */
@Serializable
enum class ServerProtocol(val defaultPort: String) {
    @kotlinx.serialization.SerialName("HTTP") HTTP("80"),
    @kotlinx.serialization.SerialName("HTTPS") HTTPS("443");
}

/** iOS: `ServerHTTPHeader` — custom header for SSO / reverse proxies. */
@Serializable
data class ServerHTTPHeader(val id: String = UUID.randomUUID().toString().uppercase(), val name: String, val value: String) {
    val isUsable: Boolean get() {
        val n = name.trim()
        if (n.isEmpty() || value.trim().isEmpty()) return false
        if (n.lowercase() in reservedNames) return false
        return n.all { it.isLetterOrDigit() || it in "!#$%&'*+-.^_`|~" } && !value.contains('\n') && !value.contains('\r')
    }
    companion object {
        val reservedNames = setOf(
            "host", "content-length", "content-type", "connection", "transfer-encoding",
            "upgrade", "range", "accept-encoding", "te", "trailer", "keep-alive", "proxy-connection",
        )
    }
}

/** iOS: `ServerConfig` — same JSON shape (`stashy_saved_servers`, `stashy_server_config`). */
@Serializable
data class ServerConfig(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String = "My Stash",
    val serverAddress: String,
    val port: String? = null,
    val serverProtocol: ServerProtocol = ServerProtocol.HTTPS,
    val subpath: String? = null,
) {
    val baseURL: String get() {
        val effectivePort = port?.takeIf { it.isNotBlank() } ?: serverProtocol.defaultPort
        val scheme = if (serverProtocol == ServerProtocol.HTTPS) "https" else "http"
        val needsPort = effectivePort != serverProtocol.defaultPort
        var url = if (needsPort) "$scheme://$serverAddress:$effectivePort" else "$scheme://$serverAddress"
        subpath?.takeIf { it.isNotEmpty() }?.let { url += if (it.startsWith("/")) it else "/$it" }
        return url
    }

    val hasValidConfig: Boolean get() = serverAddress.isNotEmpty()

    /** iOS keeps the key in the Keychain (`apikey_<id>`). */
    val apiKey: String? get() = Secrets.get("apikey_$id")?.trim()?.takeIf { it.isNotEmpty() }

    val customHeaders: List<ServerHTTPHeader> get() =
        Secrets.get("headers_$id")?.let {
            runCatching { Json.decodeFromString(ListSerializer(ServerHTTPHeader.serializer()), it) }.getOrNull()
        }.orEmpty().filter { it.isUsable }

    /** iOS: `requestHeaders(for:)` — custom headers only go to this server's host. */
    fun requestHeaders(host: String? = null): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        apiKey?.let { headers["ApiKey"] = it }
        if (host == null || host.equals(serverAddress, ignoreCase = true)) {
            customHeaders.forEach { headers[it.name.trim()] = it.value.trim() }
        }
        return headers
    }
}

/** iOS: `ServerConfigManager` — saved servers and the active one. */
object ServerConfigManager {
    private const val SAVED_KEY = "stashy_saved_servers"
    private const val ACTIVE_KEY = "stashy_server_config"

    var savedServers by mutableStateOf<List<ServerConfig>>(emptyList())
        private set
    var activeConfig by mutableStateOf<ServerConfig?>(null)
        private set

    fun init() {
        savedServers = Prefs.string(SAVED_KEY)?.let {
            runCatching { Json.decodeFromString(ListSerializer(ServerConfig.serializer()), it) }.getOrNull()
        }.orEmpty()
        activeConfig = Prefs.string(ACTIVE_KEY)?.let {
            runCatching { Json.decodeFromString(ServerConfig.serializer(), it) }.getOrNull()
        }
        if (activeConfig == null && BuildConfig.DEBUG && BuildConfig.DEBUG_SERVER.isNotBlank()) seedDebugServer()
    }

    /** Debug builds: server from android/local.properties, so the emulator starts connected. */
    private fun seedDebugServer() {
        val uri = android.net.Uri.parse(BuildConfig.DEBUG_SERVER)
        val https = uri.scheme == "https"
        val config = ServerConfig(
            id = "DEBUG-SERVER",
            name = "Debug Stash",
            serverAddress = uri.host ?: return,
            port = if (uri.port > 0) uri.port.toString() else null,
            serverProtocol = if (https) ServerProtocol.HTTPS else ServerProtocol.HTTP,
            subpath = uri.path?.trimEnd('/')?.takeIf { it.isNotEmpty() },
        )
        save(config, apiKey = BuildConfig.DEBUG_API_KEY.takeIf { it.isNotBlank() })
        activate(config)
    }

    fun save(config: ServerConfig, apiKey: String? = config.apiKey, headers: List<ServerHTTPHeader>? = null) {
        Secrets.set("apikey_${config.id}", apiKey)
        headers?.let { Secrets.set("headers_${config.id}", Json.encodeToString(ListSerializer(ServerHTTPHeader.serializer()), it.filter { h -> h.isUsable })) }
        savedServers = savedServers.filter { it.id != config.id } + config
        Prefs.setString(SAVED_KEY, Json.encodeToString(ListSerializer(ServerConfig.serializer()), savedServers))
        if (activeConfig?.id == config.id) activate(config)
    }

    fun activate(config: ServerConfig?) {
        activeConfig = config
        Prefs.setString(ACTIVE_KEY, config?.let { Json.encodeToString(ServerConfig.serializer(), it) })
        Net.resetConnections()
    }

    fun delete(config: ServerConfig) {
        savedServers = savedServers.filter { it.id != config.id }
        Prefs.setString(SAVED_KEY, Json.encodeToString(ListSerializer(ServerConfig.serializer()), savedServers))
        Secrets.set("apikey_${config.id}", null)
        Secrets.set("headers_${config.id}", null)
        if (activeConfig?.id == config.id) activate(savedServers.firstOrNull())
    }
}
