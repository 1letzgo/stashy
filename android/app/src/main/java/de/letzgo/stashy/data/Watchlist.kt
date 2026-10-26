package de.letzgo.stashy.data

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

/** Pure list rules of the watchlist (iOS `WatchlistStore`), kept apart for the unit tests. */
object WatchlistLogic {
    /** The entry after [sceneId]; the first one when [sceneId] is not on the list; null at the end. */
    fun next(scenes: List<Scene>, sceneId: String): Scene? {
        val index = scenes.indexOfFirst { it.id == sceneId }
        if (index < 0) return scenes.firstOrNull()
        return scenes.getOrNull(index + 1)
    }

    /** The entry before [sceneId]; null at the top or when it is not on the list. */
    fun previous(scenes: List<Scene>, sceneId: String): Scene? {
        val index = scenes.indexOfFirst { it.id == sceneId }
        return if (index > 0) scenes[index - 1] else null
    }

    /** Removes [scene] when listed, else appends it. */
    fun toggled(scenes: List<Scene>, scene: Scene): List<Scene> =
        if (scenes.any { it.id == scene.id }) scenes.filter { it.id != scene.id } else scenes + scene

    /** [scene] appended when it is not listed yet; the list unchanged otherwise. */
    fun added(scenes: List<Scene>, scene: Scene): List<Scene> =
        if (scenes.any { it.id == scene.id }) scenes else scenes + scene

    /** Swaps [sceneId] with its neighbour [delta] places away; unchanged when out of range. */
    fun shifted(scenes: List<Scene>, sceneId: String, delta: Int): List<Scene> {
        val index = scenes.indexOfFirst { it.id == sceneId }
        val target = index + delta
        if (index < 0 || target !in scenes.indices) return scenes
        val list = scenes.toMutableList()
        list[index] = scenes[target]
        list[target] = scenes[index]
        return list
    }

    /** Moves [sceneId] right behind [currentId] so it plays next (to the front when the current one is not listed). */
    fun movedAfter(scenes: List<Scene>, sceneId: String, currentId: String?): List<Scene> {
        val index = scenes.indexOfFirst { it.id == sceneId }
        if (index < 0 || sceneId == currentId) return scenes
        val list = scenes.toMutableList()
        val scene = list.removeAt(index)
        val anchor = currentId?.let { id -> list.indexOfFirst { it.id == id } }?.takeIf { it >= 0 }
        list.add(anchor?.plus(1) ?: 0, scene)
        return list
    }

    /** Moves the entry at [from] to index [to] of the resulting list (clamped); no-op when out of range. */
    fun moved(scenes: List<Scene>, from: Int, to: Int): List<Scene> {
        if (from !in scenes.indices) return scenes
        val list = scenes.toMutableList()
        val item = list.removeAt(from)
        list.add(to.coerceIn(0, list.size), item)
        return list
    }
}

/**
 * iOS: `WatchlistStore` — scenes queued for the mini player, per server
 * (`scene_watchlist_<serverId>`), kept across launches as full scene snapshots. The bar plays
 * them in order; the scene page and the "Playing" rows of Now Playing add entries. Scenes
 * started with Play are not listed here (they sit in `MiniPlayerStore.playingQueue`).
 */
object WatchlistStore {
    val scenes: SnapshotStateList<Scene> = mutableStateListOf()
    private var loadedServerId: String? = null
    private var loaded = false
    /** Elapsed-realtime ms of the last [checkAgainstServer] run (throttle). */
    private var lastServerCheck: Long? = null
    private var serverCheckJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private fun key(serverId: String?) = serverId?.let { "scene_watchlist_$it" }

    private fun ensureLoaded() {
        if (!loaded) reload(ServerConfigManager.activeConfig?.id)
    }

    /** Server switched (or first use): read that server's list. */
    fun reload(serverId: String?) {
        serverCheckJob?.cancel()
        serverCheckJob = null
        lastServerCheck = null
        loaded = true
        loadedServerId = serverId
        val raw = key(serverId)?.let { Prefs.string(it) }
        val list = raw?.let { runCatching { Json.decodeFromString(ListSerializer(Scene.serializer()), it) }.getOrNull() }.orEmpty()
        scenes.clear()
        scenes.addAll(list)
    }

    /** Reloads only when [serverId] differs from the loaded one; true when it did. */
    fun onServerChanged(serverId: String?): Boolean {
        if (loaded && serverId == loadedServerId) return false
        reload(serverId)
        return true
    }

    private fun persist() {
        val k = key(loadedServerId) ?: return
        Prefs.setString(k, Json.encodeToString(ListSerializer(Scene.serializer()), scenes.toList()))
    }

    private fun replace(list: List<Scene>) {
        scenes.clear()
        scenes.addAll(list)
        persist()
    }

    val all: List<Scene> get() { ensureLoaded(); return scenes }

    fun contains(sceneId: String): Boolean { ensureLoaded(); return scenes.any { it.id == sceneId } }

    fun toggle(scene: Scene) { if (contains(scene.id)) remove(scene.id) else add(scene) }

    /** Appends [scene] (no-op when listed). */
    fun add(scene: Scene) {
        ensureLoaded()
        if (scenes.any { it.id == scene.id }) return
        replace(WatchlistLogic.added(scenes, scene))
    }

    fun shift(sceneId: String, delta: Int) { ensureLoaded(); replace(WatchlistLogic.shifted(scenes, sceneId, delta)) }

    /** iOS `moveAfter` — "Play next". */
    fun moveAfter(sceneId: String, currentId: String?) { ensureLoaded(); replace(WatchlistLogic.movedAfter(scenes, sceneId, currentId)) }

    /** Removing never stops playback: the scene on screen moves to "Playing". */
    fun remove(sceneId: String) {
        ensureLoaded()
        val scene = scenes.firstOrNull { it.id == sceneId } ?: return
        replace(scenes.filter { it.id != sceneId })
        de.letzgo.stashy.ui.player.MiniPlayerStore.watchlistRemoved(scene)
    }

    fun move(from: Int, to: Int) { ensureLoaded(); replace(WatchlistLogic.moved(scenes, from, to)) }

    /** Empties the watchlist; what plays keeps playing (listed under "Playing"). */
    fun clear() {
        ensureLoaded()
        val removed = scenes.toList()
        replace(emptyList())
        removed.forEach { de.letzgo.stashy.ui.player.MiniPlayerStore.watchlistRemoved(it) }
    }

    fun next(after: String): Scene? { ensureLoaded(); return WatchlistLogic.next(scenes, after) }
    fun previous(before: String): Scene? { ensureLoaded(); return WatchlistLogic.previous(scenes, before) }

    // MARK: Server check

    /**
     * iOS `checkAgainstServer(force:)` — looks up every listed scene (watchlist, "Playing", the
     * bar's, Now Playing's) on the server in one `findScenes(ids:)` request per 100. Missing ones
     * were deleted elsewhere and leave every surface ([MiniPlayerStore.sceneDeleted]); found ones
     * refresh their snapshot. Throttled to once a minute unless [force]; a failed request or a
     * missing result block changes nothing.
     */
    fun checkAgainstServer(force: Boolean = false) {
        ensureLoaded()
        val player = de.letzgo.stashy.ui.player.MiniPlayerStore
        val ids = (scenes.map { it.id } + player.playingQueue.map { it.id } +
            listOfNotNull(player.session?.scene?.id, player.nowPlayingScene?.id)).distinct()
        if (ids.isEmpty() || serverCheckJob?.isActive == true) return
        val now = android.os.SystemClock.elapsedRealtime()
        if (!force) lastServerCheck?.let { if (now - it < 60_000) return }
        lastServerCheck = now
        val serverId = loadedServerId
        serverCheckJob = scope.launch {
            val found = fetchScenes(ids) ?: return@launch
            // The active server changed meanwhile: these results belong to the old one.
            if (loadedServerId != serverId || ServerConfigManager.activeConfig?.id != serverId) return@launch
            for (id in ids) if (found[id] == null) player.sceneDeleted(id)
            if (scenes.any { found[it.id] != null }) replace(scenes.map { found[it.id] ?: it })
            player.refreshPlaying(found)
        }
    }

    /** The scenes of [ids] found on the server, or null when any request failed. */
    private suspend fun fetchScenes(ids: List<String>): Map<String, Scene>? {
        val found = HashMap<String, Scene>()
        for (chunk in ids.chunked(100)) {
            val list = runCatching {
                val data = GraphQL.named("findScenesByIds", vars("ids" to chunk, "filter" to mapOf("per_page" to -1)))
                // No result block at all: unknown state, never treat that as "deleted".
                val result = data["findScenes"] as? kotlinx.serialization.json.JsonObject ?: return null
                val element = result["scenes"] ?: return null
                GraphQL.decode(ListSerializer(Scene.serializer()), element)
            }.getOrElse { e ->
                if (e is kotlinx.coroutines.CancellationException) throw e
                return null
            }
            list.forEach { found[it.id] = it }
        }
        return found
    }
}
