package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/** iOS: `StashConnectionProbe` + `LoginAuthHelper`. */
object ServerConnection {
    sealed interface Outcome {
        data class Stash(val version: String) : Outcome
        data class Failure(val message: String) : Outcome
    }

    private const val VERSION_QUERY = """{"query":"{ version { version } }"}"""

    /** Connection test / login: the shared client with a short overall cap, so a dead host fails fast. */
    private val probeClient by lazy {
        Net.client.newBuilder().readTimeout(30, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()
    }

    /** Only a GraphQL answer carrying Stash's version counts as connected (same rules as iOS). */
    suspend fun probe(baseURL: String, apiKey: String?, headers: List<ServerHTTPHeader> = emptyList(), timeoutMillis: Long? = null): Outcome = withContext(Dispatchers.IO) {
        val client = timeoutMillis?.let { probeClient.newBuilder().readTimeout(it, TimeUnit.MILLISECONDS).callTimeout(it, TimeUnit.MILLISECONDS).build() } ?: probeClient
        val request = Request.Builder().url("$baseURL/graphql").tag(Net.NoRewrite::class.java, Net.NoRewrite)
            .post(VERSION_QUERY.toRequestBody("application/json".toMediaType()))
            .apply {
                apiKey?.takeIf { it.isNotBlank() }?.let { header("ApiKey", it.trim()) }
                headers.filter { it.isUsable }.forEach { header(it.name.trim(), it.value.trim()) }
            }.build()
        try {
            client.newCall(request).execute().use { r ->
                val text = r.body?.string().orEmpty()
                // Stash 0.32+ refuses these before authentication, so "check the API key" would mislead.
                val body = text.lowercase()
                if (r.code == 403 && "public ip" in body) return@withContext Outcome.Failure(tr(R.string.hint_stash_refuses_public_ips_while))
                if (r.code == 400 && "invalid ip" in body) return@withContext Outcome.Failure(tr(R.string.hint_stash_rejected_reverse_proxy_in))
                if (r.code == 401 || r.code == 403) return@withContext Outcome.Failure(tr(R.string.hint_authentication_failed_check_api_key))
                val root = runCatching { Json.parseToJsonElement(text).obj }.getOrNull()
                val version = root?.get("data").obj?.get("version").obj?.get("version").stringOrNull
                if (!version.isNullOrEmpty()) return@withContext Outcome.Stash(version)
                val err = root?.get("errors").arr?.firstOrNull().obj?.get("message").stringOrNull
                if (!err.isNullOrEmpty()) return@withContext Outcome.Failure(tr(R.string.stash_rejected_request_arg, err))
                if (r.code !in 200..299) return@withContext Outcome.Failure(tr(R.string.server_error_http_arg, r.code))
                if (r.header("Content-Type").orEmpty().lowercase().contains("html"))
                    return@withContext Outcome.Failure(tr(R.string.hint_host_answered_with_web_page))
                Outcome.Failure(tr(R.string.hint_host_answered_but_not_as))
            }
        } catch (e: java.net.ConnectException) {
            Outcome.Failure(tr(R.string.error_connect_check_address_and_port))
        } catch (e: java.net.SocketTimeoutException) {
            Outcome.Failure(tr(R.string.connection_timed_out))
        } catch (e: java.net.UnknownHostException) {
            Outcome.Failure(tr(R.string.host_not_found))
        } catch (e: javax.net.ssl.SSLException) {
            Outcome.Failure(tr(R.string.hint_secure_connection_failed_check_http))
        } catch (e: Exception) {
            Outcome.Failure(e.message ?: tr(R.string.unknown_error))
        }
    }

    /** Logs in with username/password and reads the API key (`LoginAuthHelper.fetchAPIKey`). */
    suspend fun fetchAPIKey(baseURL: String, username: String, password: String, headers: List<ServerHTTPHeader> = emptyList()): String = withContext(Dispatchers.IO) {
        val client = probeClient.newBuilder()
            .cookieJar(MemoryCookieJar())
            .build()
        fun Request.Builder.custom() = apply { headers.filter { it.isUsable }.forEach { header(it.name.trim(), it.value.trim()) } }
        val login = Request.Builder().url("$baseURL/login").tag(Net.NoRewrite::class.java, Net.NoRewrite).custom()
            .post(FormBody.Builder().add("username", username).add("password", password).build()).build()
        client.newCall(login).execute().use { if (it.code != 200) throw Exception(tr(R.string.hint_login_failed_server_returned_status, it.code)) }
        val gql = Request.Builder().url("$baseURL/graphql").tag(Net.NoRewrite::class.java, Net.NoRewrite).custom()
            .post("""{"query": "{ configuration { general { apiKey } } }"}""".toRequestBody("application/json".toMediaType())).build()
        client.newCall(gql).execute().use { r ->
            if (r.code != 200) throw Exception(tr(R.string.hint_login_failed_graphql_request_failed, r.code))
            val key = Json.parseToJsonElement(r.body?.string().orEmpty()).obj?.get("data").obj?.get("configuration").obj
                ?.get("general").obj?.get("apiKey").stringOrNull
            if (key.isNullOrEmpty()) throw Exception(tr(R.string.hint_api_key_not_found_in))
            key
        }
    }
}

/** Session cookie for the login → apiKey round trip only. */
private class MemoryCookieJar : CookieJar {
    private val cookies = mutableListOf<Cookie>()
    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) { this.cookies.addAll(cookies) }
    override fun loadForRequest(url: HttpUrl): List<Cookie> = cookies.filter { it.matches(url) }
}

/**
 * iOS: `StashServerCapabilities`. Stash rejects a whole query over one unknown field or sort, so
 * anything newer than the oldest supported server is gated here. Unknown version = off.
 */
object ServerCapabilities {
    private const val VERSION_KEY_PREFIX = "stash_server_version_"

    /** Compose state, so sort menus and editors follow a late answer. */
    var supports032 by androidx.compose.runtime.mutableStateOf(false)
        private set

    fun isAtLeast032(version: String?): Boolean {
        val parts = version?.trim()?.trimStart('v', 'V')?.takeWhile { it.isDigit() || it == '.' }
            ?.split('.')?.mapNotNull { it.toIntOrNull() }.orEmpty()
        if (parts.size < 2) return false
        return parts[0] > 0 || parts[1] >= 32
    }

    /** Call on app start and on a server switch: the last known answer, then the server's own. */
    suspend fun refresh(config: ServerConfig?) {
        StudioCountsStore.clear()
        supports032 = config != null && isAtLeast032(Prefs.string(VERSION_KEY_PREFIX + config.id))
        if (config == null) return
        val outcome = ServerConnection.probe(config.baseURL, config.apiKey, config.customHeaders)
        if (outcome is ServerConnection.Outcome.Stash && ServerConfigManager.activeConfig?.id == config.id) {
            Prefs.setString(VERSION_KEY_PREFIX + config.id, outcome.version)
            supports032 = isAtLeast032(outcome.version)
        }
    }
}
