package de.letzgo.stashy.data

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import kotlinx.serialization.builtins.ListSerializer

/** Pure list rules of the watchlist (iOS `WatchlistStore`), kept apart for the unit tests. */
object WatchlistLogic {
    /** The entry after [sceneId]; the first one when [sceneId] is not on the list; null at the end. */
    fun next(scenes: List<Scene>, sceneId: String): Scene? {
        val index = scenes.indexOfFirst { it.id == sceneId }
        if (index < 0) return scenes.firstOrNull()
        return scenes.getOrNull(index + 1)
    }

    /** Removes [scene] when listed, else appends it. */
    fun toggled(scenes: List<Scene>, scene: Scene): List<Scene> =
        if (scenes.any { it.id == scene.id }) scenes.filter { it.id != scene.id } else scenes + scene

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
 * them in order; the scene page and the Now Playing view add and remove entries.
 */
object WatchlistStore {
    val scenes: SnapshotStateList<Scene> = mutableStateListOf()
    private var loadedServerId: String? = null
    private var loaded = false

    private fun key(serverId: String?) = serverId?.let { "scene_watchlist_$it" }

    private fun ensureLoaded() {
        if (!loaded) reload(ServerConfigManager.activeConfig?.id)
    }

    /** Server switched (or first use): read that server's list. */
    fun reload(serverId: String?) {
        loaded = true
        loadedServerId = serverId
        val raw = key(serverId)?.let { Prefs.string(it) }
        val list = raw?.let { runCatching { Json.decodeFromString(ListSerializer(Scene.serializer()), it) }.getOrNull() }.orEmpty()
        scenes.clear()
        scenes.addAll(list)
    }

    /** Reloads only when [serverId] differs from the loaded one. */
    fun onServerChanged(serverId: String?) {
        if (!loaded || serverId != loadedServerId) reload(serverId)
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

    fun toggle(scene: Scene) { ensureLoaded(); replace(WatchlistLogic.toggled(scenes, scene)) }

    fun remove(sceneId: String) { ensureLoaded(); replace(scenes.filter { it.id != sceneId }) }

    fun move(from: Int, to: Int) { ensureLoaded(); replace(WatchlistLogic.moved(scenes, from, to)) }

    fun clear() { ensureLoaded(); replace(emptyList()) }

    fun next(after: String): Scene? { ensureLoaded(); return WatchlistLogic.next(scenes, after) }
}
