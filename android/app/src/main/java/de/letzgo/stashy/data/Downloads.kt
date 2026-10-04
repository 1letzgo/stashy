package de.letzgo.stashy.data

import java.io.File

/**
 * Offline downloads (iOS: `DownloadManager`). Minimal lookup here; the download engine
 * (WorkManager) lives in the downloads feature. Layout mirrors iOS: `Downloads/<sceneId>/…`.
 */
object Downloads {
    val root: File get() = File(Prefs.appContext.filesDir, "Downloads")

    @Volatile var downloadedSceneIDs: Set<String> = emptySet()

    fun isDownloaded(id: String) = id in downloadedSceneIDs

    fun localThumbnail(id: String): String? {
        if (id !in downloadedSceneIDs) return null
        return File(root, "$id/thumbnail.jpg").takeIf { it.exists() }?.let { "file://${it.absolutePath}" }
    }

    fun localVideo(id: String): String? {
        if (id !in downloadedSceneIDs) return null
        return File(root, id).listFiles()?.firstOrNull { it.name.startsWith("video") }?.let { "file://${it.absolutePath}" }
    }
}
