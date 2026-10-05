package de.letzgo.stashy.data

import android.net.Uri
import kotlinx.serialization.json.Json as KJson
import okhttp3.ConnectionPool
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import java.net.Socket
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

/** Shared JSON setup: lenient like the iOS decoders (unknown keys ignored, nulls → defaults). */
val Json = KJson {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
    isLenient = true
}

/**
 * HTTP stack (iOS: `StashSessionFactory` + `StashTrustDelegate`). One OkHttp client for GraphQL,
 * images (Coil), the player (Media3) and downloads. Requests to the active server get the
 * `ApiKey` and custom headers automatically.
 */
object Net {
    private val authInterceptor = Interceptor { chain ->
        val request = chain.request()
        val config = ServerConfigManager.activeConfig
        if (config == null || !request.url.host.equals(config.serverAddress, ignoreCase = true)) {
            return@Interceptor chain.proceed(request)
        }
        val builder = request.newBuilder()
        config.requestHeaders(request.url.host).forEach { (name, value) ->
            if (request.header(name) == null) builder.header(name, value)
        }
        chain.proceed(builder.build())
    }

    @Volatile private var pool = ConnectionPool()

    val client: OkHttpClient by lazy { build(30) }

    fun build(timeoutSeconds: Long): OkHttpClient {
        val trust = LocalTrustManager(systemTrustManager())
        val ssl = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        return OkHttpClient.Builder()
            .connectTimeout(timeoutSeconds, TimeUnit.SECONDS)
            .readTimeout(timeoutSeconds * 2, TimeUnit.SECONDS)
            .connectionPool(pool)
            .sslSocketFactory(ssl.socketFactory, trust)
            .hostnameVerifier { host, session ->
                LocalHosts.acceptsSelfSigned(host) ||
                    javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier().verify(host, session)
            }
            .addInterceptor(authInterceptor)
            // Latest server time for the beta expiry (device clock can be turned back).
            .addNetworkInterceptor { chain -> chain.proceed(chain.request()).also { BetaExpiry.recordServerDate(it.header("Date")) } }
            .build()
    }

    /** iOS: `GraphQLClient.cancelAllRequests()` on a server switch. */
    fun resetConnections() {
        runCatching { client.dispatcher.cancelAll(); client.connectionPool.evictAll() }
    }

    private fun systemTrustManager(): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /** iOS: `signedURL(_:)` — appends `apikey=` for players/images that can't send headers. */
    fun signed(url: String?): String? {
        if (url.isNullOrBlank()) return null
        val key = ServerConfigManager.activeConfig?.apiKey ?: return url
        if (url.lowercase().contains("apikey=")) return url
        return Uri.parse(url).buildUpon().appendQueryParameter("apikey", key).build().toString()
    }
}

/** iOS: `StashTrustDelegate.acceptsSelfSigned(host:)` — LAN, mDNS and Tailscale only. */
object LocalHosts {
    fun acceptsSelfSigned(rawHost: String): Boolean {
        var host = rawHost.lowercase().trim('[', ']')
        host.indexOf('%').takeIf { it >= 0 }?.let { host = host.substring(0, it) }
        if (host == "localhost" || host.endsWith(".local")) return true
        if (host.contains(":")) return isLocalIPv6(host)
        val octets = host.split(".").mapNotNull { it.toIntOrNull() }
        if (octets.size != 4 || octets.any { it !in 0..255 }) return false
        val (a, b) = octets[0] to octets[1]
        return a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b in 16..31) || (a == 100 && b in 64..127)
    }

    private fun isLocalIPv6(host: String): Boolean {
        if (host == "::1") return true
        val first = host.split(":").firstOrNull()?.toIntOrNull(16) ?: return false
        return (first and 0xFE00) == 0xFC00 || (first and 0xFFC0) == 0xFE80
    }
}

/**
 * System validation first; a failing chain is accepted only when the peer is a local host
 * (same rule as iOS). Public hosts always get standard TLS validation.
 */
private class LocalTrustManager(private val system: X509TrustManager) : X509ExtendedTrustManager() {
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) {
        val host = (socket as? javax.net.ssl.SSLSocket)?.handshakeSession?.peerHost ?: socket?.inetAddress?.hostAddress
        check(chain, authType, host)
    }
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) =
        check(chain, authType, engine?.peerHost)
    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = check(chain, authType, null)

    private fun check(chain: Array<out X509Certificate>, authType: String, host: String?) {
        try {
            system.checkServerTrusted(chain, authType)
        } catch (e: Exception) {
            if (host == null || !LocalHosts.acceptsSelfSigned(host)) throw e
        }
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) = system.checkClientTrusted(chain, authType)
    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) = system.checkClientTrusted(chain, authType)
    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = system.checkClientTrusted(chain, authType)
    override fun getAcceptedIssuers(): Array<X509Certificate> = system.acceptedIssuers
}
