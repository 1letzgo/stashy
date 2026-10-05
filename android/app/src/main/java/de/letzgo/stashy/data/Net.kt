package de.letzgo.stashy.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.Uri
import kotlinx.serialization.json.Json as KJson
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
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
 * the player (Media3) and downloads; images (Coil) use a sibling on its own dispatcher. Both
 * share DNS, fast fallback, TLS and the connection pool. Requests to the active server get the
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

    /** Per connect attempt. Fast fallback starts the next address after 250 ms anyway. */
    private const val CONNECT_TIMEOUT_SECONDS = 10L
    private const val READ_TIMEOUT_SECONDS = 60L
    /** Whole-call cap for GraphQL (connect + server work + body); streams/downloads have none. */
    const val GRAPHQL_CALL_TIMEOUT_SECONDS = 90L

    private val pool = ConnectionPool()

    private val debugLog: ((String) -> Unit)? =
        if (de.letzgo.stashy.BuildConfig.DEBUG) { msg -> android.util.Log.d("StashyNet", msg) } else null

    /** Resolver shared by every client (IPv6-failure memory must be global, not per client). */
    val dns = StashDns(log = debugLog)

    /**
     * The one base client: GraphQL, Media3, downloads, app update, probes. Every other client is
     * `client.newBuilder()…` so DNS, fast fallback, TLS, auth and the pool stay identical.
     */
    val client: OkHttpClient by lazy { build() }

    /**
     * Images (Coil) on their own dispatcher: a dashboard enqueues dozens of thumbnails for the
     * server host at once, and with one shared dispatcher (5 per host by default) GraphQL calls
     * queued behind them — every one of them waiting out a slow connect.
     */
    val imageClient: OkHttpClient by lazy {
        client.newBuilder().dispatcher(Dispatcher().apply { maxRequestsPerHost = 8 }).build()
    }

    private fun build(): OkHttpClient {
        val trust = LocalTrustManager(systemTrustManager())
        val ssl = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        return OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            // Happy Eyeballs (RFC 8305) like iOS URLSession: IPv6 and IPv4 attempts race instead of
            // the next address waiting for the previous one's connect timeout.
            .fastFallback(true)
            .dns(dns)
            .eventListenerFactory { NetEventListener(dns, debugLog) }
            .dispatcher(Dispatcher().apply { maxRequestsPerHost = 16 })
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
        runCatching { client.dispatcher.cancelAll(); imageClient.dispatcher.cancelAll(); pool.evictAll() }
        dns.forgetFailures()
    }

    @Volatile private var defaultNetwork: Network? = null

    /**
     * Drops idle pooled connections and the IPv6-failure memory when the default network changes
     * (Wi-Fi ↔ mobile, VPN up/down): sockets from the old network would only fail on first use.
     */
    fun watchNetworkChanges(context: Context) {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    val previous = defaultNetwork
                    defaultNetwork = network
                    if (previous != null && previous != network) onNetworkChanged("default network changed")
                }

                override fun onLost(network: Network) {
                    if (network == defaultNetwork) onNetworkChanged("default network lost")
                }
            })
        }
    }

    private fun onNetworkChanged(reason: String) {
        debugLog?.invoke("$reason: evicting idle connections")
        pool.evictAll()
        dns.forgetFailures()
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
