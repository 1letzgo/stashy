package de.letzgo.stashy.data

import android.graphics.Bitmap
import androidx.compose.runtime.mutableStateMapOf
import coil3.SingletonImageLoader
import coil3.asImage
import coil3.memory.MemoryCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Per-entity image cache-busters (iOS: the `?bust=` paths `PerformerImageUpdated` /
 * `SceneCoverUpdated` carry, and `ImageCache.invalidate*`). An image whose content changed on the
 * server while its URL stayed the same (marker screenshots, a performer image before the list is
 * refetched, …) gets a `bust=<stamp>` query item, so its Coil cache key changes and every screen
 * that builds that entity's URL reloads it. Backed by snapshot state: a composable that built the
 * URL recomposes when the stamp changes.
 */
object ImageBusters {
    enum class Kind(val prefix: String) { Scene("scene"), Performer("performer"), Marker("marker") }

    private val stamps = mutableStateMapOf<String, String>()
    private var lastStamp = 0L

    private fun key(kind: Kind, id: String) = "${kind.prefix}:$id"

    fun stamp(kind: Kind, id: String): String? = stamps[key(kind, id)]

    /** A new, strictly increasing stamp for [kind]/[id]; returns it. */
    @Synchronized
    fun bump(kind: Kind, id: String): String {
        val now = System.currentTimeMillis()
        lastStamp = if (now > lastStamp) now else lastStamp + 1
        val s = lastStamp.toString()
        stamps[key(kind, id)] = s
        return s
    }

    /** [url] with the entity's `bust` query item (unchanged when it has none). */
    fun apply(url: String?, kind: Kind, id: String): String? {
        if (url == null) return null
        val s = stamp(kind, id) ?: return url
        return withQueryItem(url, PARAM, s)
    }

    /** Busters are per server: a new server starts clean. */
    fun clear() = stamps.clear()

    const val PARAM = "bust"

    /** Appends (or replaces) `name=value` in [url]'s query, before any fragment ([value] is URL-safe). */
    fun withQueryItem(url: String, name: String, value: String): String {
        val hash = url.indexOf('#')
        val base = if (hash >= 0) url.substring(0, hash) else url
        val tail = if (hash >= 0) url.substring(hash) else ""
        val q = base.indexOf('?')
        val path = if (q >= 0) base.substring(0, q) else base
        val items = if (q >= 0) base.substring(q + 1).split('&').filter { it.isNotEmpty() && it.substringBefore('=') != name } else emptyList()
        return path + "?" + (items + "$name=$value").joinToString("&") + tail
    }
}

/**
 * iOS: `ImageCache.invalidatePerformerProfileImage` / `invalidateSceneCoverImage` /
 * `invalidateMarkerScreenshot` + the `PerformerImageUpdated` / `SceneCoverUpdated` posts.
 * Drops the entity's entries from Coil's memory cache (every size and stamp of its path) and the
 * disk entries of the URLs we know, bumps its [ImageBusters] stamp and tells the lists.
 */
object ImageRefresh {
    /** Path fragments of an entity's image in Stash URLs (old and new route forms). */
    fun pathFragments(kind: ImageBusters.Kind, id: String, sceneId: String? = null): List<String> = when (kind) {
        ImageBusters.Kind.Scene -> listOf("/scene/$id/screenshot")
        ImageBusters.Kind.Performer -> listOf("/performer/$id/image")
        ImageBusters.Kind.Marker -> listOfNotNull(
            "/scenemarker/$id/screenshot",
            "/scene_marker/$id/screenshot",
            sceneId?.let { "/scene/$it/scene_marker/$id/screenshot" },
        )
    }

    /** True when the cache [key] belongs to [serverId] and shows one of [fragments]. */
    fun keyMatches(key: String, serverId: String?, fragments: List<String>): Boolean {
        if (!key.startsWith(ImageCacheKeys.prefix(serverId))) return false
        val path = key.substringBefore('?')
        return fragments.any { f -> path.endsWith(f) || path.contains("$f/") }
    }

    /** A scene's cover changed on the server (frame as cover, identify, upload). */
    fun sceneCoverChanged(sceneId: String, oldURLs: List<String?> = emptyList()): String {
        val stamp = ImageBusters.bump(ImageBusters.Kind.Scene, sceneId)
        val base = ServerConfigManager.activeConfig?.baseURL?.let { "$it/scene/$sceneId/screenshot" }
        invalidate(ImageBusters.Kind.Scene, sceneId, null, oldURLs + base)
        SceneEvents.post(SceneEvent.CoverUpdated(sceneId, stamp))
        return stamp
    }

    /** A performer's image changed; [newImagePath] is the mutation's `image_path` when known. */
    fun performerImageChanged(performerId: String, newImagePath: String?, oldURLs: List<String?> = emptyList()) {
        val stamp = ImageBusters.bump(ImageBusters.Kind.Performer, performerId)
        val base = ServerConfigManager.activeConfig?.baseURL?.let { "$it/performer/$performerId/image" }
        // The plain route and the new path without stamp may hold the old picture on disk.
        invalidate(ImageBusters.Kind.Performer, performerId, null, oldURLs + base + newImagePath)
        PerformerEvents.post(PerformerEvent.ImageUpdated(performerId, newImagePath, stamp))
    }

    /**
     * iOS `seedMarkerThumbnailCache(marker:dataURL:)`: a new marker shows the captured [frame]
     * until Stash generated its screenshot. Bumps the marker's stamp and stores the frame under
     * the URL the cards will ask for.
     */
    fun markerCreated(marker: SceneMarker, frame: Bitmap?) {
        ImageBusters.bump(ImageBusters.Kind.Marker, marker.id)
        if (frame == null) return
        val url = marker.screenshotURL ?: return
        val key = ImageCacheKeys.key(url, ServerConfigManager.activeConfig?.id) ?: return
        val context = runCatching { Prefs.appContext }.getOrNull() ?: return
        MainScope().launch {
            runCatching {
                SingletonImageLoader.get(context).memoryCache?.set(MemoryCache.Key(key), MemoryCache.Value(frame.asImage()))
            }
        }
    }

    /** iOS `invalidateMarkerScreenshot` after the generate job: drop the seed, reload from Stash. */
    fun markerScreenshotReady(marker: SceneMarker, sceneId: String?) {
        val old = marker.screenshotURL
        ImageBusters.bump(ImageBusters.Kind.Marker, marker.id)
        invalidate(ImageBusters.Kind.Marker, marker.id, sceneId, listOf(old, Net.signed(marker.screenshot)))
    }

    private fun invalidate(kind: ImageBusters.Kind, id: String, sceneId: String?, urls: List<String?>) {
        val context = runCatching { Prefs.appContext }.getOrNull() ?: return
        val serverId = ServerConfigManager.activeConfig?.id
        val fragments = pathFragments(kind, id, sceneId)
        val diskKeys = urls.filterNotNull().mapNotNull { ImageCacheKeys.key(it, serverId) }.distinct()
        MainScope().launch {
            runCatching {
                val loader = SingletonImageLoader.get(context)
                loader.memoryCache?.let { mem ->
                    mem.keys.filter { keyMatches(it.key, serverId, fragments) }.forEach { mem.remove(it) }
                }
                val disk = loader.diskCache ?: return@runCatching
                withContext(Dispatchers.IO) { diskKeys.forEach { runCatching { disk.remove(it) } } }
            }
        }
    }
}
