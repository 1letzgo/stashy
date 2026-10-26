package de.letzgo.stashy.data

import kotlinx.serialization.Serializable

/**
 * iOS: `MiniPlayerStore` "Last session" — the scene the mini player ran last, per server
 * (`mini_player_last_<serverId>`), with its position, so the bar comes back (paused) after a
 * restart.
 */
object MiniPlayerLastSession {
    @Serializable
    data class Saved(val scene: Scene, val position: Double)

    /** Seconds of position change between two saves while playing. */
    const val SAVE_INTERVAL_SECONDS = 5.0

    fun key(serverId: String?): String? = serverId?.takeIf { it.isNotBlank() }?.let { "mini_player_last_$it" }

    /** A scene page that stops without handing over forgets the saved session only when it is that scene. */
    fun forgetsFor(savedSceneId: String?, stoppedSceneId: String): Boolean = savedSceneId != null && savedSceneId == stoppedSceneId

    /** Whether a playing position moved far enough from the last saved one to save again. */
    fun isDueForSave(lastSaved: Double?, position: Double): Boolean =
        position.isFinite() && position >= 0 && (lastSaved == null || kotlin.math.abs(position - lastSaved) >= SAVE_INTERVAL_SECONDS)

    fun load(serverId: String?): Saved? {
        val raw = key(serverId)?.let { Prefs.string(it) } ?: return null
        return runCatching { Json.decodeFromString(Saved.serializer(), raw) }.getOrNull()
    }

    fun save(serverId: String?, scene: Scene, position: Double) {
        val k = key(serverId) ?: return
        Prefs.setString(k, Json.encodeToString(Saved.serializer(), Saved(scene, maxOf(0.0, position))))
    }

    fun forget(serverId: String?) {
        key(serverId)?.let { Prefs.setString(it, null) }
    }
}
