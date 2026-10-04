package de.letzgo.stashy.data

/** iOS: `ServerConfig.detectProtocol(from:)` / `parseAddress(_:)` (address field of the server forms). */
object ServerAddress {
    data class Parsed(val host: String, val port: String?, val subpath: String?)

    /** Strips a typed/pasted `http(s)://` and reports the protocol it implied. */
    fun detectProtocol(input: String): Pair<ServerProtocol?, String> {
        val cleaned = input.trim()
        val lower = cleaned.lowercase()
        return when {
            lower.startsWith("https://") -> ServerProtocol.HTTPS to cleaned.drop(8)
            lower.startsWith("http://") -> ServerProtocol.HTTP to cleaned.drop(7)
            else -> null to cleaned
        }
    }

    /** "1.2.3.4:9999/stash" → host 1.2.3.4, port 9999, subpath /stash. */
    fun parse(input: String): Parsed {
        val address = detectProtocol(input).second
        val uri = runCatching { java.net.URI("http://$address") }.getOrNull() ?: return Parsed(address, null, null)
        val host = uri.host ?: return Parsed(address, null, null)
        val port = uri.port.takeIf { it > 0 }?.toString()
        var path = uri.rawPath.orEmpty()
        path = if (path == "/") "" else path.removeSuffix("/")
        return Parsed(host, port, path.ifEmpty { null })
    }

    /** iOS `currentBaseURL` of the form. */
    fun baseURL(input: String, proto: ServerProtocol): String {
        val parsed = parse(input)
        val config = ServerConfig(serverAddress = parsed.host, port = parsed.port, serverProtocol = proto, subpath = parsed.subpath)
        return config.baseURL
    }

    /** iOS edit form: address string rebuilt from a saved config (host[:port][/subpath]). */
    fun display(config: ServerConfig): String {
        var s = config.serverAddress
        config.port?.takeIf { it.isNotBlank() }?.let { s += ":$it" }
        config.subpath?.takeIf { it.isNotEmpty() }?.let { s += if (it.startsWith("/")) it else "/$it" }
        return s
    }
}
