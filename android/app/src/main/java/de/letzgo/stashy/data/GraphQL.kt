package de.letzgo.stashy.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.serializer
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** iOS: `GraphQLNetworkError` (same messages). */
sealed class GraphQLError(message: String) : Exception(message) {
    object NoServerConfig : GraphQLError("Server configuration is missing or incomplete")
    object Unauthorized : GraphQLError("API key is invalid or expired")
    class Server(code: Int, body: String?) : GraphQLError("Server error ($code): ${body?.take(200) ?: "Unknown"}")
    class Query(message: String) : GraphQLError("GraphQL error: $message")
    class Decoding(cause: Throwable) : GraphQLError("Failed to decode response: ${cause.message}")
    class Network(cause: Throwable) : GraphQLError(networkMessage(cause))

    companion object {
        private fun networkMessage(e: Throwable) = when (e) {
            is java.net.ConnectException -> "Server not reachable - check IP/Port/SSL"
            is java.net.SocketTimeoutException -> "Connection timed out - is server running?"
            is java.net.UnknownHostException -> "Host not found"
            else -> "Network error: ${e.message}"
        }
    }
}

/**
 * iOS: `GraphQLQueries` — loads the shared `.graphql` documents from assets and appends every
 * fragment they spread (`...SceneListFields` → `fragment_SceneListFields.graphql`), recursively.
 */
object GraphQLQueries {
    private val cache = ConcurrentHashMap<String, String>()
    private val spread = Regex("""\.\.\.\s*([A-Za-z_][A-Za-z0-9_]*)""")

    fun load(name: String): String = cache.getOrPut(name) {
        val base = raw(name)
        val fragments = linkedMapOf<String, String>()
        collect(base, fragments)
        (listOf(base) + fragments.values).joinToString("\n")
    }

    private fun raw(name: String): String =
        Prefs.appContext.assets.open(if (name.endsWith(".graphql")) name else "$name.graphql").bufferedReader().use { it.readText() }

    private fun collect(doc: String, into: LinkedHashMap<String, String>) {
        spread.findAll(doc).map { it.groupValues[1] }.filter { it != "on" }.forEach { frag ->
            if (frag in into || doc.contains("fragment $frag ")) return@forEach
            val text = runCatching { raw("fragment_$frag") }.getOrNull() ?: return@forEach
            into[frag] = text
            collect(text, into)
        }
    }
}

/** iOS: `GraphQLClient` actor. */
object GraphQL {
    private const val MAX_DATABASE_RETRIES = 3
    private val jsonType = "application/json".toMediaType()

    /** Runs a query (document text) and returns the `data` object. */
    suspend fun data(query: String, variables: JsonObject? = null): JsonObject {
        var attempt = 0
        while (true) {
            try {
                return perform(query, variables)
            } catch (e: DatabaseLocked) {
                attempt++
                if (attempt >= MAX_DATABASE_RETRIES) throw GraphQLError.Query("Database is locked")
                delay(attempt * 500L)
            }
        }
    }

    /** Loads `<name>.graphql` (with fragments) and runs it. */
    suspend fun named(name: String, variables: JsonObject? = null): JsonObject = data(GraphQLQueries.load(name), variables)

    /** Decodes `data.<field>` into [T]. */
    suspend inline fun <reified T> field(query: String, field: String, variables: JsonObject? = null): T {
        val data = data(query, variables)
        val element = data[field] ?: JsonNull
        return try { Json.decodeFromJsonElement(serializer<T>(), element) } catch (e: Exception) { throw GraphQLError.Decoding(e) }
    }

    fun <T> decode(strategy: DeserializationStrategy<T>, element: JsonElement): T =
        try { Json.decodeFromJsonElement(strategy, element) } catch (e: Exception) { throw GraphQLError.Decoding(e) }

    private class DatabaseLocked : Exception()

    private suspend fun perform(query: String, variables: JsonObject?): JsonObject = withContext(Dispatchers.IO) {
        val config = ServerConfigManager.activeConfig?.takeIf { it.hasValidConfig } ?: throw GraphQLError.NoServerConfig
        val body = buildJsonObject {
            put("query", JsonPrimitive(query))
            if (variables != null) put("variables", variables)
        }.toString()
        val request = Request.Builder()
            .url("${config.baseURL}/graphql")
            .post(body.toRequestBody(jsonType))
            .build()
        val call = Net.client.newCall(request).apply { timeout().timeout(Net.GRAPHQL_CALL_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS) }
        val response = try { call.await() } catch (e: IOException) { throw GraphQLError.Network(e) }
        response.use { r ->
            val text = r.body?.string().orEmpty()
            val root = runCatching { Json.parseToJsonElement(text).jsonObject }.getOrNull()
            val errors = (root?.get("errors") as? JsonArray)?.mapNotNull { (it as? JsonObject)?.get("message")?.jsonPrimitive?.contentOrNull }.orEmpty()
            if (errors.any { it.lowercase().contains("database is locked") }) throw DatabaseLocked()
            when (r.code) {
                in 200..299 -> {}
                401 -> throw GraphQLError.Unauthorized
                else -> throw GraphQLError.Server(r.code, text)
            }
            val data = root?.get("data") as? JsonObject
            if (data == null) {
                if (errors.any { it.contains("Cannot query field") }) throw GraphQLError.Query("GraphQL schema not compatible")
                throw GraphQLError.Query(errors.firstOrNull() ?: "Query failed")
            }
            data
        }
    }
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onResponse(call: Call, response: Response) = cont.resume(response)
        override fun onFailure(call: Call, e: IOException) { if (!cont.isCancelled) cont.resumeWithException(e) }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}

// Small helpers for building variables.
fun vars(vararg pairs: Pair<String, Any?>): JsonObject = buildJsonObject { pairs.forEach { (k, v) -> put(k, v.toJson()) } }

fun Any?.toJson(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Number -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Map<*, *> -> buildJsonObject { this@toJson.forEach { (k, v) -> put(k.toString(), v.toJson()) } }
    is Iterable<*> -> JsonArray(this.map { it.toJson() })
    is Array<*> -> JsonArray(this.map { it.toJson() })
    else -> JsonPrimitive(this.toString())
}

val JsonElement?.stringOrNull: String? get() = (this as? JsonPrimitive)?.contentOrNull
val JsonElement?.obj: JsonObject? get() = this as? JsonObject
val JsonElement?.arr: JsonArray? get() = runCatching { this?.jsonArray }.getOrNull()
