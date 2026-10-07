package de.letzgo.stashy.data

import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import okio.FileSystem
import okio.Path
import kotlinx.coroutines.launch

/**
 * Disk cache split into one directory per server, like iOS `ImageCacheManager`
 * (`StashyImageCache/<serverID>/`). Routing uses the server id inside the cache key written by
 * [ImageCacheKeys] (`srv:<serverId>|…`); keys without that prefix land in a shared directory.
 * Clearing one server's images never touches another server's cache.
 */
class ServerScopedDiskCache(
    private val base: Path,
    private val maxSizePerServer: Long,
    override val fileSystem: FileSystem = FileSystem.SYSTEM,
) : DiskCache {
    private val caches = HashMap<String, DiskCache>()
    private val lock = Any()

    init {
        // The single pre-split cache lived directly in [base] (journal + entry files): drop it.
        runCatching { fileSystem.list(base).filter { fileSystem.metadataOrNull(it)?.isRegularFile == true }.forEach { fileSystem.delete(it) } }
    }

    override val directory: Path get() = base
    override val maxSize: Long get() = maxSizePerServer
    override val size: Long get() = synchronized(lock) { caches.values.sumOf { it.size } }

    private fun cacheFor(key: String): DiskCache = cacheForDir(directoryName(ImageCacheKeys.serverId(key)))

    private fun cacheForDir(dir: String): DiskCache = synchronized(lock) {
        caches.getOrPut(dir) {
            DiskCache.Builder()
                .fileSystem(fileSystem)
                .directory(base.resolve(dir))
                .maxSizeBytes(maxSizePerServer)
                .build()
        }
    }

    override fun openSnapshot(key: String): DiskCache.Snapshot? = cacheFor(key).openSnapshot(key)
    override fun openEditor(key: String): DiskCache.Editor? = cacheFor(key).openEditor(key)
    override fun remove(key: String): Boolean = cacheFor(key).remove(key)

    /** Every server's images. */
    override fun clear() {
        synchronized(lock) {
            caches.values.forEach { it.clear() }
            // Directories of servers not opened this session; open caches own theirs.
            val open = caches.keys
            runCatching { fileSystem.list(base).filter { it.name !in open }.forEach { fileSystem.deleteRecursively(it) } }
        }
    }

    /** Only [serverId]'s images (iOS `clearCache(forServerID:)`). */
    fun clearServer(serverId: String) {
        val dir = directoryName(serverId)
        val open = synchronized(lock) { caches[dir] }
        if (open != null) open.clear() else runCatching { fileSystem.deleteRecursively(base.resolve(dir)) }
    }

    override fun shutdown() = synchronized(lock) { caches.values.forEach { it.shutdown() }; caches.clear() }

    companion object {
        internal const val SHARED_DIR = "_shared"

        /** File-system safe directory for a server id; null → the shared directory. */
        internal fun directoryName(serverId: String?): String =
            serverId?.takeIf { it.isNotEmpty() && it != "none" }?.replace(Regex("[^A-Za-z0-9_-]"), "_") ?: SHARED_DIR
    }
}

/** iOS `ImageCache.shared.clearCurrentServerCache()` / `clearCache(forServerID:)`. */
object ServerImageCache {
    /** Drops the memory and disk entries of [serverId] only (disk work runs on IO). */
    suspend fun clearServer(context: android.content.Context, serverId: String) {
        val loader = SingletonImageLoader.get(context)
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
            loader.memoryCache?.let { mem ->
                val prefix = ImageCacheKeys.prefix(serverId)
                mem.keys.filter { it.key.startsWith(prefix) }.forEach { mem.remove(it) }
            }
        }
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            when (val disk = loader.diskCache) {
                is ServerScopedDiskCache -> disk.clearServer(serverId)
                null -> {}
                else -> disk.clear()
            }
        }
    }

    /** Fire-and-forget [clearServer] (server deleted). */
    fun clearServerAsync(context: android.content.Context, serverId: String) {
        kotlinx.coroutines.MainScope().launch { runCatching { clearServer(context, serverId) } }
    }

    /** "Clear Image Cache" in Settings: the active server's images; false without a server. */
    suspend fun clearActiveServer(context: android.content.Context): Boolean {
        val id = ServerConfigManager.activeConfig?.id ?: return false
        clearServer(context, id)
        return true
    }
}
