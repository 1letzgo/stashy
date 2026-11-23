package de.letzgo.stashy.data

import java.net.URLDecoder

/**
 * iOS: `StashyDeepLink` (`StashyDeepLink.swift`) — one parsed `stashy://` link. Pure (no
 * `android.net.Uri`), so the JVM unit tests read it exactly like the app does.
 *
 *     stashy://scene/1234            scene page, no playback
 *     stashy://scene/1234?t=754.5    scene page, plays from 754.5 s at once
 *     stashy://marker/567[?t=…]      the marker's scene, plays from the marker (or `t`)
 *     …&server=<name or URL>         on that configured server (switched to first)
 *
 * Phone only: the TV launch path never reads it.
 */
data class DeepLink(
    val target: Target,
    /** Start time in seconds; null when absent, not a number, negative or not finite. */
    val time: Double?,
    /** The `server` parameter as given (a server name or address), trimmed; null when absent or empty. */
    val server: String?,
) {
    sealed interface Target {
        data class Scene(val id: String) : Target
        data class Marker(val id: String) : Target
    }

    enum class Error { WrongScheme, UnknownPath, InvalidId }

    sealed interface Result {
        data class Ok(val link: DeepLink) : Result
        data class Failed(val error: Error) : Result
    }

    /**
     * What a link does (iOS `StashyLinkRoute`), the rule for consecutive links:
     * - The scene's page is the one on top ([InPlace]): it stays (no new page, Back unchanged).
     *   A start time seeks there and plays; no start time changes nothing.
     * - Otherwise one fresh page opens on the Home root ([Open]). A start time plays from there,
     *   over any resume point, earlier link or running player of the scene; without one the page
     *   shows its cover (or carries on with the mini player's video of that scene, no seek).
     * Every link's start time is used once ([OnceStart]).
     */
    sealed interface Route {
        data class InPlace(val start: Double?) : Route
        data class Open(val autoPlay: Boolean, val startAt: Double?) : Route
    }

    companion object {
        const val SCHEME = "stashy"

        fun parse(raw: String?): Result {
            val text = raw?.trim().orEmpty()
            val colon = text.indexOf(':')
            if (colon <= 0 || !text.substring(0, colon).equals(SCHEME, ignoreCase = true)) return Result.Failed(Error.WrongScheme)
            var rest = text.substring(colon + 1).substringBefore('#')
            val query = rest.substringAfter('?', "")
            rest = rest.substringBefore('?')
            // `stashy://scene/12`, `stashy:///scene/12` and `stashy:scene/12` read the same.
            val parts = rest.split('/').filter { it.isNotEmpty() }
            val kind = parts.firstOrNull()?.lowercase() ?: return Result.Failed(Error.UnknownPath)
            if (kind != "scene" && kind != "marker") return Result.Failed(Error.UnknownPath)
            val id = parts.getOrNull(1)
            if (parts.size != 2 || id.isNullOrEmpty() || !id.all { it in '0'..'9' }) return Result.Failed(Error.InvalidId)

            val params = query.split('&').filter { it.isNotEmpty() }.associate { pair ->
                val name = decode(pair.substringBefore('=')).lowercase()
                name to decode(pair.substringAfter('=', "")).trim()
            }
            return Result.Ok(
                DeepLink(
                    target = if (kind == "scene") Target.Scene(id) else Target.Marker(id),
                    time = parseTime(params["t"]),
                    server = params["server"]?.takeIf { it.isNotEmpty() },
                ),
            )
        }

        private fun decode(s: String): String =
            runCatching { URLDecoder.decode(s.replace("+", "%2B"), "UTF-8") }.getOrDefault(s)

        /** `754`, `754.5` → seconds. Anything else (empty, `abc`, `-3`, `1e3`, `NaN`) counts as absent. */
        fun parseTime(raw: String?): Double? {
            if (raw.isNullOrEmpty() || !raw.all { it in '0'..'9' || it == '.' }) return null
            return raw.toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }
        }

        fun route(sceneId: String, start: Double?, frontSceneId: String?): Route =
            if (frontSceneId != null && frontSceneId == sceneId) Route.InPlace(start)
            else Route.Open(autoPlay = start != null, startAt = start)

        /** Never past the scene's end (one second before it, so the player does not open on the last frame). */
        fun clamp(seconds: Double, duration: Double?): Double {
            if (duration == null || duration <= 0) return maxOf(0.0, seconds)
            return minOf(maxOf(0.0, seconds), maxOf(0.0, duration - 1))
        }

        /**
         * Whether the `server` parameter names this server: its name (case-insensitive) or one of
         * its addresses (regular or local). Scheme and host case, a trailing slash and a default
         * port do not matter; a value without a scheme matches either scheme.
         */
        fun serverMatches(value: String, name: String, addresses: List<String>): Boolean {
            val wanted = value.trim()
            if (wanted.isEmpty()) return false
            if (wanted.equals(name.trim(), ignoreCase = true)) return true
            val wantedKey = addressKey(wanted) ?: return false
            return addresses.any { address ->
                val key = addressKey(address) ?: return@any false
                if (wantedKey.scheme == null) key.rest == wantedKey.rest else key == wantedKey
            }
        }

        private data class AddressKey(val scheme: String?, val rest: String)

        private fun addressKey(raw: String): AddressKey? {
            val text = raw.trim()
            val schemeEnd = text.indexOf("://")
            val scheme = if (schemeEnd > 0) text.substring(0, schemeEnd).lowercase() else null
            val afterScheme = if (schemeEnd > 0) text.substring(schemeEnd + 3) else text
            val authority = afterScheme.substringBefore('/').substringBefore('?')
            var path = afterScheme.substring(authority.length).substringBefore('?').substringBefore('#')
            path = path.trimEnd('/')
            if (authority.isEmpty()) return null
            val host = authority.substringBeforeLast(':').takeIf { authority.contains(':') && !authority.endsWith(']') } ?: authority
            var port = if (host.length < authority.length) authority.substring(host.length + 1).toIntOrNull() else null
            if (host.isEmpty()) return null
            if ((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) port = null
            val rest = host.lowercase() + (port?.let { ":$it" } ?: "") + path
            return AddressKey(scheme, rest)
        }
    }
}

/** A link's start time, handed out once: coming back to the page never jumps to it again. */
class OnceStart(private var value: Double?) {
    fun take(): Double? = value.also { value = null }
}
