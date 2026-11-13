package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

/** Pure rules of [LastPlayedHidden] (sceneId → epoch seconds when it was hidden), kept apart for the unit tests. */
object LastPlayedHiddenLogic {
    const val MAX_ENTRIES = 500

    /** `{ "<sceneId>": <epoch seconds> }`; garbage or a non-object gives an empty map. */
    fun decode(raw: String?): Map<String, Long> {
        if (raw.isNullOrBlank()) return emptyMap()
        val obj = runCatching { Json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return emptyMap()
        val out = LinkedHashMap<String, Long>()
        for ((id, value) in obj) {
            val p = value as? JsonPrimitive ?: continue
            val seconds = p.longOrNull ?: p.doubleOrNull?.toLong() ?: continue
            out[id] = seconds
        }
        return capped(out)
    }

    fun encode(map: Map<String, Long>): String =
        Json.encodeToString(JsonObject.serializer(), buildJsonObject { capped(map).forEach { (id, at) -> put(id, JsonPrimitive(at)) } })

    /** At most [MAX_ENTRIES], dropping the oldest hide times first. */
    fun capped(map: Map<String, Long>, max: Int = MAX_ENTRIES): Map<String, Long> {
        if (map.size <= max) return map
        return map.entries.sortedByDescending { it.value }.take(max).associate { it.key to it.value }
    }

    /** [map] with [sceneId] hidden at [nowSeconds] (capped). */
    fun hiding(map: Map<String, Long>, sceneId: String, nowSeconds: Long): Map<String, Long> =
        capped(LinkedHashMap(map).apply { remove(sceneId); put(sceneId, nowSeconds) })

    /**
     * Hidden unless the scene was played after it was hidden: a play from another device
     * (`last_played_at` later than the hide time) brings it back. An unreadable stamp keeps it hidden.
     */
    fun isHidden(map: Map<String, Long>, sceneId: String, lastPlayedAt: String?): Boolean {
        val hiddenAt = map[sceneId] ?: return false
        val played = lastPlayedAt?.let(SceneStamps::parseUpdatedAt) ?: return true
        return played / 1000 <= hiddenAt
    }
}

/**
 * iOS counterpart: the local "Remove from Last Played" hide. Nothing changes on the server; the
 * Home row "Last Played" simply skips the scene until it is played again. Per server
 * (`last_played_hidden_<serverID>`), JSON `{ "<sceneId>": <epoch seconds> }`, at most 500 entries.
 */
object LastPlayedHidden {
    private const val PREFIX = "last_played_hidden_"

    private class Snapshot(val serverId: String?, val map: Map<String, Long>)

    private var snapshot by mutableStateOf(load(currentServerId()))

    private fun currentServerId(): String? = runCatching { ServerConfigManager.activeConfig?.id }.getOrNull()
    private fun load(serverId: String?): Snapshot =
        Snapshot(serverId, serverId?.let { runCatching { Prefs.string("$PREFIX$it") }.getOrNull() }.let(LastPlayedHiddenLogic::decode))

    /** The hidden scenes of the active server (observable; follows a server switch). */
    val entries: Map<String, Long> get() {
        val s = snapshot
        return if (s.serverId == currentServerId()) s.map else load(currentServerId()).map
    }

    fun isHidden(sceneId: String, lastPlayedAt: String?): Boolean = LastPlayedHiddenLogic.isHidden(entries, sceneId, lastPlayedAt)

    fun hide(sceneId: String) = update(LastPlayedHiddenLogic.hiding(entries, sceneId, System.currentTimeMillis() / 1000))

    fun unhide(sceneId: String) {
        val current = entries
        if (sceneId in current) update(current - sceneId)
    }

    private fun update(map: Map<String, Long>) {
        val serverId = currentServerId() ?: return
        snapshot = Snapshot(serverId, map)
        runCatching { Prefs.setString("$PREFIX$serverId", if (map.isEmpty()) null else LastPlayedHiddenLogic.encode(map)) }
    }
}

/**
 * "Mark as Finished": clears the resume point on the server (`sceneSaveActivity` with
 * `resume_time: 0, playDuration: 0`, also when "Track activity" is off — it is an explicit
 * action) and never adds a play. Optimistic: lists are patched at once through
 * [SceneEvent.ResumeTimeUpdated]; on failure the old position is posted back and [onFailure] runs.
 */
object SceneMarkAsFinished {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun run(sceneId: String, previousResume: Double, onFailure: () -> Unit) {
        SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, 0.0))
        runCatching { Downloads.updateLocalResumeTime(sceneId, 0.0, null) }
        scope.launch {
            val ok = runCatching { SceneEditing.clearResumeTime(sceneId) }.isSuccess
            if (!ok) {
                SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, previousResume))
                runCatching { Downloads.updateLocalResumeTime(sceneId, previousResume, null) }
                onFailure()
            }
        }
    }
}
