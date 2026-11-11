package de.letzgo.stashy.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext

/**
 * Picks between a server's external address and its optional local address by reachability, not
 * by Wi-Fi name: the local address is used whenever it answers as Stash (iOS: `ServerEndpointSelector`).
 * Same server id, API key and headers either way, so caches and settings stay shared.
 */
object ServerEndpointSelector {
    /** Total cap of one probe. */
    const val PROBE_TIMEOUT_MILLIS = 1800L
    private const val FAILURE_PROBE_MIN_INTERVAL_MILLIS = 10_000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Any()

    @Volatile private var localServerId: String? = null
    @Volatile private var blockingJob: Job? = null
    private var runningJob: Job? = null
    private var lastFailureProbeAt = 0L

    private val _activeUsesLocal = MutableStateFlow(false)
    /** True while the active server talks to its local address (for the UI). */
    val activeUsesLocal: StateFlow<Boolean> = _activeUsesLocal.asStateFlow()

    /** Test seam / reset: forget any local selection. */
    internal fun set(serverId: String?) {
        localServerId = serverId
        _activeUsesLocal.value = serverId != null && serverId == ServerConfigManager.activeConfig?.id
    }

    fun usesLocal(id: String): Boolean = localServerId == id

    /**
     * Probes the active server's local address and sets or clears the selection. A [blocking]
     * probe is awaited by [settle] (every GraphQL request does); others run in the background.
     */
    fun refresh(blocking: Boolean) {
        val config = ServerConfigManager.activeConfig
        val local = config?.localURL?.takeIf { it.isNotBlank() }
        if (config == null || local == null) {
            synchronized(lock) { runningJob?.cancel(); runningJob = null; blockingJob = null }
            set(null)
            return
        }
        synchronized(lock) {
            val keepBlocking = blocking || blockingJob?.isActive == true
            runningJob?.cancel()
            val job = scope.launch {
                val outcome = ServerConnection.probe(local, config.apiKey, config.customHeaders, timeoutMillis = PROBE_TIMEOUT_MILLIS)
                coroutineContext.ensureActive()
                val reachable = outcome is ServerConnection.Outcome.Stash
                val current = ServerConfigManager.activeConfig
                if (current?.id == config.id && current.localURL == config.localURL) {
                    set(if (reachable) config.id else null)
                }
            }
            runningJob = job
            // A blocking probe replaced by a background one stays the one requests wait for.
            blockingJob = if (keepBlocking) job else null
        }
    }

    /** Waits for a running blocking probe (bounded by its timeout). */
    suspend fun settle() {
        blockingJob?.takeIf { it.isActive }?.join()
    }

    /** A request failed with a connection error: re-check, at most once per 10 s. */
    fun noteConnectionFailure() {
        if (ServerConfigManager.activeConfig?.localURL.isNullOrBlank()) return
        val now = System.currentTimeMillis()
        synchronized(lock) {
            if (now - lastFailureProbeAt < FAILURE_PROBE_MIN_INTERVAL_MILLIS) return
            lastFailureProbeAt = now
        }
        refresh(blocking = false)
    }
}
