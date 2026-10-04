package de.letzgo.stashy.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** iOS: `StashConnectionProbe` + `LoginAuthHelper`. */
object ServerConnection {
    sealed interface Outcome {
        data class Stash(val version: String) : Outcome
        data class Failure(val message: String) : Outcome
    }

    private const val VERSION_QUERY = """{"query":"{ version { version } }"}"""

    /** Only a GraphQL answer carrying Stash's version counts as connected (same rules as iOS). */
    suspend fun probe(baseURL: String, apiKey: String?, headers: List<ServerHTTPHeader> = emptyList()): Outcome = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("$baseURL/graphql")
            .post(VERSION_QUERY.toRequestBody("application/json".toMediaType()))
            .apply {
                apiKey?.takeIf { it.isNotBlank() }?.let { header("ApiKey", it.trim()) }
                headers.filter { it.isUsable }.forEach { header(it.name.trim(), it.value.trim()) }
            }.build()
        try {
            Net.build(15).newCall(request).execute().use { r ->
                if (r.code == 401 || r.code == 403) return@withContext Outcome.Failure("Authentication failed — check the API key and custom headers.")
                val text = r.body?.string().orEmpty()
                val root = runCatching { Json.parseToJsonElement(text).obj }.getOrNull()
                val version = root?.get("data").obj?.get("version").obj?.get("version").stringOrNull
                if (!version.isNullOrEmpty()) return@withContext Outcome.Stash(version)
                val err = root?.get("errors").arr?.firstOrNull().obj?.get("message").stringOrNull
                if (!err.isNullOrEmpty()) return@withContext Outcome.Failure("Stash rejected the request: $err")
                if (r.code !in 200..299) return@withContext Outcome.Failure("Server error: HTTP ${r.code}.")
                if (r.header("Content-Type").orEmpty().lowercase().contains("html"))
                    return@withContext Outcome.Failure("The host answered with a web page, not Stash — likely a login or proxy page. Check the address and custom headers.")
                Outcome.Failure("The host answered, but not as Stash. Check the address, subpath and custom headers.")
            }
        } catch (e: java.net.ConnectException) {
            Outcome.Failure("Cannot connect — check the address and port.")
        } catch (e: java.net.SocketTimeoutException) {
            Outcome.Failure("Connection timed out.")
        } catch (e: java.net.UnknownHostException) {
            Outcome.Failure("Host not found.")
        } catch (e: javax.net.ssl.SSLException) {
            Outcome.Failure("Secure connection failed — check HTTP/HTTPS.")
        } catch (e: Exception) {
            Outcome.Failure(e.message ?: "Unknown error")
        }
    }

    /** Logs in with username/password and reads the API key (`LoginAuthHelper.fetchAPIKey`). */
    suspend fun fetchAPIKey(baseURL: String, username: String, password: String, headers: List<ServerHTTPHeader> = emptyList()): String = withContext(Dispatchers.IO) {
        val client = Net.build(15).newBuilder()
            .cookieJar(MemoryCookieJar())
            .build()
        fun Request.Builder.custom() = apply { headers.filter { it.isUsable }.forEach { header(it.name.trim(), it.value.trim()) } }
        val login = Request.Builder().url("$baseURL/login").custom()
            .post(FormBody.Builder().add("username", username).add("password", password).build()).build()
        client.newCall(login).execute().use { if (it.code != 200) throw Exception("Login failed: Server returned status code ${it.code}") }
        val gql = Request.Builder().url("$baseURL/graphql").custom()
            .post("""{"query": "{ configuration { general { apiKey } } }"}""".toRequestBody("application/json".toMediaType())).build()
        client.newCall(gql).execute().use { r ->
            if (r.code != 200) throw Exception("Login failed: GraphQL request failed: ${r.code}")
            val key = Json.parseToJsonElement(r.body?.string().orEmpty()).obj?.get("data").obj?.get("configuration").obj
                ?.get("general").obj?.get("apiKey").stringOrNull
            if (key.isNullOrEmpty()) throw Exception("API Key not found in server configuration")
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
