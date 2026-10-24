package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * App-wide "the server answered 401" event (iOS: the `"AuthError401"` notification posted by
 * `GraphQLClient`, observed by `MainTabView`). A burst of failing requests shows one alert:
 * once per server configuration until the server or its API key changes.
 */
object AuthEvents {
    /** Server id whose 401 alert is waiting to be shown; null while nothing is pending. */
    var pendingServerId by mutableStateOf<String?>(null)
        private set

    private val gate = AuthAlertGate()

    /** Called by the GraphQL client on HTTP 401 (any thread). */
    fun reportUnauthorized(serverId: String?) {
        if (serverId == null || !gate.shouldShow(serverId)) return
        val post = { pendingServerId = serverId }
        val main = android.os.Looper.getMainLooper()
        if (android.os.Looper.myLooper() == main) post() else android.os.Handler(main).post(post)
    }

    /** The alert was dismissed (either button). */
    fun consume() { pendingServerId = null }

    /** The server config changed (switch, new API key): a new 401 may alert again. */
    fun reset() {
        gate.reset()
        pendingServerId = null
    }
}

/** Debounce of [AuthEvents]: one alert per server until [reset]. Pure logic, unit-tested. */
class AuthAlertGate {
    private var shownFor: String? = null

    @Synchronized fun shouldShow(serverId: String): Boolean {
        if (shownFor == serverId) return false
        shownFor = serverId
        return true
    }

    @Synchronized fun reset() { shownFor = null }
}
