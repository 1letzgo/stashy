package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
    val name: String = tr(R.string.my_stash),
    val serverAddress: String,
    val port: String? = null,
    val serverProtocol: ServerProtocol = ServerProtocol.HTTPS,
    val subpath: String? = null,
    /** Optional second address (`scheme://host[:port][/subpath]`, no trailing slash), used while it answers as Stash. */
    val localURL: String? = null,
) {
    /** The normal (external) address. */
    val externalBaseURL: String get() {
        val effectivePort = port?.takeIf { it.isNotBlank() } ?: serverProtocol.defaultPort
        val scheme = if (serverProtocol == ServerProtocol.HTTPS) "https" else "http"
        val needsPort = effectivePort != serverProtocol.defaultPort
        var url = if (needsPort) "$scheme://$serverAddress:$effectivePort" else "$scheme://$serverAddress"
        subpath?.takeIf { it.isNotEmpty() }?.let { url += if (it.startsWith("/")) it else "/$it" }
        return url
    }

    /** [localURL] while [ServerEndpointSelector] says this server currently uses it, else [externalBaseURL]. */
    val baseURL: String get() = localURL?.takeIf { it.isNotBlank() && ServerEndpointSelector.usesLocal(id) } ?: externalBaseURL

    private val localEndpoint: Endpoint? get() = localURL?.takeIf { it.isNotBlank() }?.let { Endpoint.parse(it) }

    /** True when [host] is this server's external or local host (custom headers / ApiKey go there). */
    fun ownsHost(host: String): Boolean =
        host.equals(serverAddress, ignoreCase = true) || localEndpoint?.host.equals(host, ignoreCase = true)

    /**
     * Rewrites an absolute URL of the other endpoint to [toLocal]'s endpoint. Unchanged without a
     * local address, for foreign hosts, or when the ports/subpath do not match the other endpoint.
     */
    fun addressed(url: String, toLocal: Boolean): String {
        val local = localEndpoint ?: return url
        val external = Endpoint.parse(externalBaseURL) ?: return url
        return if (toLocal) Endpoint.swap(url, external, local) else Endpoint.swap(url, local, external)
    }

    /** [url] on whichever endpoint is in use right now. */
    fun activeAddressed(url: String): String =
        if (localURL == null) url else addressed(url, ServerEndpointSelector.usesLocal(id))

    /** [url] on the external endpoint (stable cache keys). */
    fun canonicalAddressed(url: String): String = addressed(url, toLocal = false)

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
        if (host == null || ownsHost(host)) {
            customHeaders.forEach { headers[it.name.trim()] = it.value.trim() }
        }
        return headers
    }
}

/** A parsed base URL (`scheme://host[:port][/subpath]`); pure, so the address swap is unit-testable. */
internal data class Endpoint(val scheme: String, val host: String, val explicitPort: Int?, val subpath: String) {
    val port: Int get() = explicitPort ?: if (scheme == "https") 443 else 80

    companion object {
        private val pattern = Regex("""^(https?)://(?:[^/?#@]*@)?(\[[^\]]+\]|[^/?#:]+)(?::(\d+))?([^?#]*)(.*)$""", RegexOption.IGNORE_CASE)

        fun parse(url: String): Endpoint? {
            val m = pattern.matchEntire(url.trim()) ?: return null
            val path = m.groupValues[4].let { if (it == "/") "" else it.trimEnd('/') }
            return Endpoint(m.groupValues[1].lowercase(), m.groupValues[2], m.groupValues[3].toIntOrNull(), path)
        }

        /** Moves [url] from [from] to [to] when it belongs to [from]; otherwise returns it as is. */
        fun swap(url: String, from: Endpoint, to: Endpoint): String {
            val m = pattern.matchEntire(url) ?: return url
            val scheme = m.groupValues[1].lowercase()
            val host = m.groupValues[2]
            val explicit = m.groupValues[3].toIntOrNull()
            if (!host.equals(from.host, ignoreCase = true)) return url
            val effective = explicit ?: if (scheme == "https") 443 else 80
            val fromEffective = from.explicitPort ?: if (from.scheme == "https") 443 else 80
            val samePort = effective == fromEffective || (explicit == null && from.explicitPort == null)
            if (!samePort) return url
            val path = m.groupValues[4]
            val rest = when {
                from.subpath.isEmpty() -> path
                path == from.subpath -> ""
                path.startsWith(from.subpath + "/") -> path.removePrefix(from.subpath)
                else -> return url
            }
            val authority = to.host + (to.explicitPort?.let { ":$it" } ?: "")
            return "${to.scheme}://$authority${to.subpath}$rest${m.groupValues[5]}"
        }
    }
}

/** iOS: `ServerConfigManager` — saved servers and the active one. */
object ServerConfigManager {
    private const val SAVED_KEY = "stashy_saved_servers"
    private const val ACTIVE_KEY = "stashy_server_config"
    /** Last list that decoded fine — restored if the main entry is ever missing or unreadable. */
    private const val SAVED_BACKUP_KEY = "stashy_saved_servers_backup"
    private val listSerializer = ListSerializer(ServerConfig.serializer())

    var savedServers by mutableStateOf<List<ServerConfig>>(emptyList())
        private set
    var activeConfig by mutableStateOf<ServerConfig?>(null)
        private set

    fun init() {
        fun decode(raw: String?) = raw?.let { runCatching { Json.decodeFromString(listSerializer, it) }.getOrNull() }
        val main = decode(Prefs.string(SAVED_KEY))
        val backup = decode(Prefs.string(SAVED_BACKUP_KEY))
        if (main == null && Prefs.has(SAVED_KEY)) {
            // Never silently drop an unreadable list: keep the raw text for diagnosis.
            Prefs.commitString("${SAVED_KEY}_unreadable", Prefs.string(SAVED_KEY))
            android.util.Log.w("StashyServers", "saved server list unreadable, using backup (${backup?.size ?: 0})")
        }
        savedServers = when {
            main != null && (main.isNotEmpty() || backup.isNullOrEmpty()) -> main
            else -> backup.orEmpty()
        }
        activeConfig = Prefs.string(ACTIVE_KEY)?.let {
            runCatching { Json.decodeFromString(ServerConfig.serializer(), it) }.getOrNull()
        }
        // The active server always belongs to the list (it was missing when only the setup ran).
        activeConfig?.let { a -> if (savedServers.none { it.id == a.id }) savedServers = savedServers + a }
        if (savedServers.isNotEmpty()) persistList()
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
        persistList()
        if (activeConfig?.id == config.id) activate(config)
    }

    fun activate(config: ServerConfig?) {
        activeConfig = config
        AuthEvents.reset()
        Prefs.commitString(ACTIVE_KEY, config?.let { Json.encodeToString(ServerConfig.serializer(), it) })
        Net.resetConnections()
        // Before the data reload: requests wait for this probe (ServerEndpointSelector.settle()).
        ServerEndpointSelector.refresh(blocking = true)
    }

    fun delete(config: ServerConfig) {
        savedServers = savedServers.filter { it.id != config.id }
        persistList(allowEmpty = true)
        Secrets.set("apikey_${config.id}", null)
        Secrets.set("headers_${config.id}", null)
        // iOS `deleteServer` → `ImageCache.shared.clearCache(forServerID:)`.
        ServerImageCache.clearServerAsync(Prefs.appContext, config.id)
        if (activeConfig?.id == config.id) activate(savedServers.firstOrNull())
    }

    /** Synchronous write of the list plus its backup copy. */
    private fun persistList(allowEmpty: Boolean = false) {
        val json = Json.encodeToString(listSerializer, savedServers)
        Prefs.commitString(SAVED_KEY, json)
        if (savedServers.isNotEmpty() || allowEmpty) Prefs.commitString(SAVED_BACKUP_KEY, json)
    }
}
