package de.letzgo.stashy.data

import android.content.Context
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.tools.DownloadsEngine
import de.letzgo.stashy.data.tools.DownloadsFetch
import de.letzgo.stashy.data.tools.DownloadsPendingStore
import de.letzgo.stashy.data.tools.PendingImage
import de.letzgo.stashy.data.tools.PendingImageDownload
import de.letzgo.stashy.data.tools.PendingSceneDownload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.io.File
import kotlinx.serialization.json.Json as KJson

// ---------------------------------------------------------------------------------------------
// Metadata models — same JSON shape as iOS (`downloads_metadata.json`,
// `gallery_downloads_metadata.json`), so field names must not change.
// ---------------------------------------------------------------------------------------------

/**
 * iOS: `DownloadedScene` (StashDBViewModel.swift). Paths are relative to [Downloads.root]
 * (`"<sceneId>/video.mp4"`, `"<sceneId>/thumbnail.jpg"`) exactly like iOS writes them.
 * [downloadDate] is Swift's default `JSONEncoder` date: seconds since 2001-01-01 UTC ([AppleDate]).
 */
@Serializable
data class DownloadedScene(
    val id: String,
    val title: String? = null,
    val details: String? = null,
    val date: String? = null,
    val studioName: String? = null,
    val performerNames: List<String> = emptyList(),
    val downloadDate: Double = 0.0,
    val localVideoPath: String = "",
    val localThumbnailPath: String = "",
    val duration: Double? = null,
    /** Where offline playback stopped (seconds); null once watched to the end. */
    val resumeTime: Double? = null,
) {
    val downloadDateMillis: Long get() = AppleDate.toEpochMillis(downloadDate)

    /** A [Scene] built from the metadata, for pushing the scene detail offline. */
    fun toScene(): Scene = Scene(
        id = id,
        title = title,
        details = details,
        date = date,
        duration = duration,
        resumeTime = resumeTime,
        studio = studioName?.let { Studio(id = "", name = it) },
        performers = performerNames.map { Performer(id = "", name = it) },
    )
}

/** iOS: `DownloadedGallery` — a downloaded gallery, tag image set, filter set or single image. */
@Serializable
data class DownloadedGallery(
    val id: String,
    val title: String? = null,
    val studioName: String? = null,
    val performerNames: List<String> = emptyList(),
    val downloadDate: Double = 0.0,
    val localCoverPath: String? = null,
    val images: List<DownloadedGalleryImage> = emptyList(),
    val isSingleImage: Boolean = false,
    /** "gallery" | "image" | "tag"; optional like iOS. */
    val sourceKind: String? = null,
    /** Server image count at download time ("50 of 400"). */
    val serverImageCount: Int? = null,
) {
    /** iOS: `DownloadedGallery.Kind`. */
    enum class Kind(val raw: String) { Gallery("gallery"), Image("image"), Tag("tag") }

    val resolvedKind: Kind get() =
        Kind.entries.firstOrNull { it.raw == sourceKind } ?: if (isSingleImage) Kind.Image else Kind.Gallery

    val displayTitle: String get() {
        val trimmed = title?.trim().orEmpty()
        if (trimmed.isNotEmpty()) return trimmed
        return when (resolvedKind) {
            Kind.Image -> "Untitled image"
            Kind.Tag -> "Untitled tag"
            Kind.Gallery -> "Untitled gallery"
        }
    }

    val mayHaveMore: Boolean get() = serverImageCount?.let { it > images.size } ?: false
    val downloadDateMillis: Long get() = AppleDate.toEpochMillis(downloadDate)
}

/** iOS: `DownloadedGalleryImage`. */
@Serializable
data class DownloadedGalleryImage(
    val id: String,
    val localPath: String,
    val title: String? = null,
    val createdAt: String? = null,
    val isVideo: Boolean = false,
    val thumbnailPath: String? = null,
    val performerNames: List<String>? = null,
    val tagNames: List<String>? = null,
)

/** iOS: `ActiveDownload` — progress of one transfer (scene bytes or image units). */
data class ActiveDownload(
    val id: String,
    val title: String,
    val progress: Double,
    val totalSize: Long = 0,
    val downloadedSize: Long = 0,
    /** Bytes per second; 0 until the first sample. */
    val speed: Double = 0.0,
    /** Image downloads count files: "7 of 50 images". */
    val completedUnits: Int = 0,
    val totalUnits: Int = 0,
)

/** Swift `Date` ↔ Double seconds since the reference date 2001-01-01T00:00:00Z. */
object AppleDate {
    /** Seconds between 1970-01-01 and 2001-01-01. */
    const val REFERENCE_OFFSET_SECONDS = 978_307_200.0

    fun fromEpochMillis(millis: Long): Double = millis / 1000.0 - REFERENCE_OFFSET_SECONDS
    fun toEpochMillis(reference: Double): Long = ((reference + REFERENCE_OFFSET_SECONDS) * 1000.0).toLong()
    fun now(): Double = fromEpochMillis(System.currentTimeMillis())
}

/**
 * Encoder/decoder for the two metadata files. Pure Kotlin (unit-tested). Defaults are encoded
 * (iOS needs `performerNames`, `isSingleImage` … present); nil optionals are omitted like
 * Swift's synthesized `encodeIfPresent`.
 */
object DownloadsMetadataCodec {
    val json = KJson {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
        coerceInputValues = true
        isLenient = true
    }
    private val scenes = ListSerializer(DownloadedScene.serializer())
    private val galleries = ListSerializer(DownloadedGallery.serializer())

    fun encodeScenes(list: List<DownloadedScene>): String = json.encodeToString(scenes, list)
    fun decodeScenes(text: String): List<DownloadedScene> = json.decodeFromString(scenes, text)
    fun encodeGalleries(list: List<DownloadedGallery>): String = json.encodeToString(galleries, list)
    fun decodeGalleries(text: String): List<DownloadedGallery> = json.decodeFromString(galleries, text)

    /** iOS: `updateLocalResumeTime` rule — ≤ 1 s or ≥ 98 % clears the position. */
    fun resolvedResumeTime(seconds: Double, duration: Double?): Double? {
        var resume: Double? = if (seconds > 1) seconds else null
        if (duration != null && duration > 0 && (100.0 / duration) * seconds >= 98) resume = null
        return resume
    }

    /** iOS: `Scene.downloadFileExtension` — file format, else the stream path's extension, else mp4. */
    fun sceneFileExtension(format: String?, streamPath: String?): String {
        format?.lowercase()?.filter { it.isLetterOrDigit() }?.take(5)?.takeIf { it.isNotEmpty() }?.let { return it }
        streamPath?.substringBefore('?')?.let { clean ->
            val last = clean.substringAfterLast('/')
            if (last.contains('.')) {
                last.substringAfterLast('.').lowercase().filter { it.isLetterOrDigit() }.take(5).takeIf { it.isNotEmpty() }?.let { return it }
            }
        }
        return "mp4"
    }

    /** iOS: `StashImage.fileExtension` (lowercased, "jpg" fallback as the downloader uses it). */
    fun imageFileExtension(basename: String?, path: String?, imagePath: String?): String {
        fun ext(name: String?): String? {
            val last = name?.substringBefore('?')?.substringAfterLast('/') ?: return null
            if (!last.contains('.')) return null
            return last.substringAfterLast('.').takeIf { it.isNotEmpty() }
        }
        return (ext(basename) ?: ext(path) ?: ext(imagePath))?.lowercase() ?: "jpg"
    }

    /**
     * Title stored for a downloaded image: the trimmed server title, else the file name without
     * its extension (Stash's own UI falls back to the file name too). iOS: `StashImage.downloadTitle`.
     */
    fun imageTitle(title: String?, basename: String?, path: String?): String? {
        title?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val name = basename?.trim()?.takeIf { it.isNotEmpty() }
            ?: path?.substringBefore('?')?.trimEnd('/', '\\')?.substringAfterLast('/')?.substringAfterLast('\\')?.trim()?.takeIf { it.isNotEmpty() }
            ?: return null
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(0, dot) else name
    }
}

/**
 * iOS: `DownloadManager` (+ `LocalDownloadStore`). Offline scenes and image sets under
 * `filesDir/Downloads/` with the iOS layout: `<sceneId>/thumbnail.jpg`, `<sceneId>/video.<ext>`,
 * `gallery-<entryId>/<imageId>.<ext>` (+ `<imageId>_thumb.jpg`), metadata JSON next to them.
 * Transfers run in a WorkManager foreground worker ([DownloadsEngine]); all state below is
 * Compose state, mutated on the main thread only.
 */
object Downloads {
    const val METADATA_FILE = "downloads_metadata.json"
    const val GALLERY_METADATA_FILE = "gallery_downloads_metadata.json"
    /** iOS: `maxParallelSceneDownloads`. */
    const val MAX_PARALLEL_SCENE_DOWNLOADS = 2
    /** iOS: `TabManager.downloadBatchSizeOptions`. */
    val batchSizeOptions = listOf(5, 10, 25, 50, 100, 200)

    val root: File get() = File(Prefs.appContext.filesDir, "Downloads")

    var downloads by mutableStateOf<List<DownloadedScene>>(emptyList())
        private set
    var galleryDownloads by mutableStateOf<List<DownloadedGallery>>(emptyList())
        private set
    /** id → transfer (scenes, galleries `<id>`, `image-<id>`, `tag-<id>`, `filter-<id>`). */
    var activeDownloads by mutableStateOf<Map<String, ActiveDownload>>(emptyMap())
        private set
    /** Scene ids waiting for one of the [MAX_PARALLEL_SCENE_DOWNLOADS] slots. */
    var queuedSceneIds by mutableStateOf<Set<String>>(emptySet())
        private set

    /** Thread-safe mirror of the downloaded scene ids (read by `Scene.thumbnailURL` / `streamURL`). */
    @Volatile var downloadedSceneIDs: Set<String> = emptySet()
        private set
    @Volatile private var videoPaths: Map<String, String> = emptyMap()

    @Volatile private var loaded = false
    /** Lazy so plain JVM unit tests that touch `Scene.thumbnailURL` never resolve `Dispatchers.Main`. */
    private val scope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }
    @OptIn(ExperimentalCoroutinesApi::class)
    private val writer by lazy { Dispatchers.IO.limitedParallelism(1) }

    private val sceneQueue = ArrayDeque<Scene>()
    private val runningSceneIds = mutableSetOf<String>()
    /**
     * One token per started image entry. A fetch whose token is gone (cancelled) or replaced
     * (cancelled and started again) drops its result — iOS: `cancelledEntries`.
     */
    private val entryTokens = mutableMapOf<String, Long>()
    private var tokenCounter = 0L
    private val speedSamples = mutableMapOf<String, Pair<Long, Long>>()

    /** iOS: `galleryNewestBatchSize` (Settings › Downloads, `download_batch_size`). */
    val galleryNewestBatchSize: Int get() =
        Prefs.int("download_batch_size", 50).takeIf { it in batchSizeOptions } ?: 50
    /** iOS: `sceneNewestBatchSize` (`scene_download_batch_size`). */
    val sceneNewestBatchSize: Int get() =
        Prefs.int("scene_download_batch_size", 5).takeIf { it in batchSizeOptions } ?: 5

    // MARK: - Startup

    /** Loads the metadata (cheap, synchronous) and restores in-flight workers. Call from `Application.onCreate`. */
    fun init(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            val dir = File(context.applicationContext.filesDir, "Downloads").apply { mkdirs() }
            val galleries = runCatching { DownloadsMetadataCodec.decodeGalleries(File(dir, GALLERY_METADATA_FILE).readText()) }.getOrNull()
            val scenes = runCatching { DownloadsMetadataCodec.decodeScenes(File(dir, METADATA_FILE).readText()) }.getOrNull()
            galleries?.let { galleryDownloads = it }
            scenes?.let { setScenes(it) }
            loaded = true
            val appContext = context.applicationContext
            scope.launch {
                val pending = withContext(Dispatchers.IO) { DownloadsEngine.restore(appContext) }
                pending.forEach { (id, title, isScene) ->
                    if (activeDownloads[id] == null) activeDownloads = activeDownloads + (id to ActiveDownload(id, title, 0.02))
                    if (isScene) runningSceneIds += id
                }
                // iOS cleans up only after scene metadata decoded.
                if (scenes != null) withContext(Dispatchers.IO) { cleanupIncompleteDownloads(dir) }
            }
        }
    }

    private fun ensureLoaded() { if (!loaded) runCatching { init(Prefs.appContext) } }

    /** iOS: `cleanupIncompleteDownloads` — folders without metadata (and no pending worker) go. */
    private fun cleanupIncompleteDownloads(dir: File) {
        val keep = downloads.map { it.id }.toMutableSet()
        keep += galleryDownloads.map { galleryFolderName(it.id) }
        keep += DownloadsPendingStore.protectedFolders(Prefs.appContext)
        dir.listFiles()?.filter { it.isDirectory && it.name !in keep }?.forEach { it.deleteRecursively() }
    }

    private fun setScenes(list: List<DownloadedScene>) {
        downloads = list
        downloadedSceneIDs = list.map { it.id }.toSet()
        videoPaths = list.associate { it.id to it.localVideoPath }
    }

    private fun saveMetadata() {
        val snapshot = downloads
        val dir = root
        scope.launch(writer) { writeAtomically(File(dir, METADATA_FILE), DownloadsMetadataCodec.encodeScenes(snapshot)) }
    }

    private fun saveGalleryMetadata() {
        val snapshot = galleryDownloads
        val dir = root
        scope.launch(writer) { writeAtomically(File(dir, GALLERY_METADATA_FILE), DownloadsMetadataCodec.encodeGalleries(snapshot)) }
    }

    private fun writeAtomically(file: File, text: String) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.path + ".tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        }
    }

    // MARK: - Lookups (any thread)

    fun isDownloaded(id: String): Boolean { ensureLoaded(); return id in downloadedSceneIDs }

    fun localThumbnail(id: String): String? {
        if (!isDownloaded(id)) return null
        return File(root, "$id/thumbnail.jpg").takeIf { it.exists() }?.let { "file://${it.absolutePath}" }
    }

    fun localVideo(id: String): String? = localVideoFile(id)?.let { "file://${it.absolutePath}" }

    /** iOS: `LocalDownloadStore.videoURL` — metadata path first, then any `video.*` in the folder. */
    fun localVideoFile(id: String): File? {
        if (!isDownloaded(id)) return null
        videoPaths[id]?.takeIf { it.isNotEmpty() }?.let { File(root, it) }?.takeIf { it.exists() }?.let { return it }
        return File(root, id).listFiles()?.firstOrNull { it.nameWithoutExtension == "video" }
    }

    fun localThumbnailFile(scene: DownloadedScene): File = File(root, scene.localThumbnailPath)

    fun downloadedScene(id: String): DownloadedScene? = downloads.firstOrNull { it.id == id }

    /** Stored offline playback position (seconds), for the player's resume. */
    fun resumeTime(sceneId: String): Double? = downloads.firstOrNull { it.id == sceneId }?.resumeTime

    fun isGalleryDownloaded(id: String) = galleryDownloads.any { it.id == id }
    fun downloadedGallery(id: String): DownloadedGallery? = galleryDownloads.firstOrNull { it.id == id }
    fun localFile(image: DownloadedGalleryImage): File = File(root, image.localPath)
    /** Grid preview, falling back to the full file for entries without one. */
    fun thumbnailFile(image: DownloadedGalleryImage): File =
        image.thumbnailPath?.let { File(root, it) }?.takeIf { it.exists() } ?: localFile(image)
    fun localCoverFile(gallery: DownloadedGallery): File? = gallery.localCoverPath?.let { File(root, it) }

    /** Folder of a gallery-like entry; prefixed so it never collides with a scene id. */
    fun galleryFolderName(id: String) = "gallery-$id"

    // MARK: - Scene downloads

    /** iOS: `downloadScene(_:)` — queued, at most two transfer at once. */
    fun downloadScene(scene: Scene) {
        ensureLoaded()
        onMain {
            val id = scene.id
            if (isDownloaded(id) || activeDownloads[id] != null) return@onMain
            if (sceneQueue.any { it.id == id }) return@onMain
            if (!requireDownloadEntitlement()) return@onMain
            sceneQueue.addLast(scene)
            queuedSceneIds = queuedSceneIds + id
            activeDownloads = activeDownloads + (id to ActiveDownload(id, scene.title ?: "Unknown Scene", 0.0))
            startNextQueuedScenesIfPossible()
        }
    }

    private fun startNextQueuedScenesIfPossible() {
        while (runningSceneIds.size < MAX_PARALLEL_SCENE_DOWNLOADS && sceneQueue.isNotEmpty()) {
            val next = sceneQueue.removeFirst()
            queuedSceneIds = queuedSceneIds - next.id
            runningSceneIds += next.id
            startDownload(next)
        }
    }

    private fun startDownload(scene: Scene) {
        val id = scene.id
        val title = scene.title ?: "Unknown Scene"
        activeDownloads = activeDownloads + (id to ActiveDownload(id, title, 0.05))
        val ext = DownloadsMetadataCodec.sceneFileExtension(scene.files?.firstOrNull()?.format, scene.paths?.stream)
        val videoURL = Net.signed(scene.paths?.stream ?: ServerConfigManager.activeConfig?.let { "${it.baseURL}/scene/$id/stream" })
        if (videoURL == null) {
            activeDownloads = activeDownloads - id
            finishSceneDownload(id)
            return
        }
        val meta = DownloadedScene(
            id = id, title = scene.title, details = scene.details, date = scene.date,
            studioName = scene.studio?.name, performerNames = scene.performers.map { it.name },
            downloadDate = 0.0, localVideoPath = "$id/video.$ext", localThumbnailPath = "$id/thumbnail.jpg",
            duration = scene.sceneDuration,
        )
        val pending = PendingSceneDownload(id, title, videoURL, scene.thumbnailURL, ext, meta)
        DownloadsEngine.enqueueScene(Prefs.appContext, pending)
    }

    /** A slot came free — finished, failed or cancelled. */
    private fun finishSceneDownload(id: String) {
        speedSamples.remove(id)
        runningSceneIds -= id
        queuedSceneIds = queuedSceneIds - id
        sceneQueue.removeAll { it.id == id }
        startNextQueuedScenesIfPossible()
    }

    /** iOS: `SceneDownloadScope` — whose scenes a bulk download takes. */
    sealed class SceneDownloadScope {
        data class Performer(val id: String) : SceneDownloadScope()
        data class Studio(val id: String) : SceneDownloadScope()
        data class Tag(val id: String) : SceneDownloadScope()
        data class Group(val id: String) : SceneDownloadScope()
        /** A saved scene filter, already sanitised into a `scene_filter` fragment. */
        data class SavedFilter(val filter: JsonObject) : SceneDownloadScope()

        val sceneFilter: JsonObject get() = when (this) {
            is Performer -> criterion("performers", id, depth = false)
            is Studio -> criterion("studios", id, depth = true)
            is Tag -> criterion("tags", id, depth = true)
            is Group -> criterion("groups", id, depth = false)
            is SavedFilter -> filter
        }

        private fun criterion(key: String, id: String, depth: Boolean) = buildJsonObject {
            put(key, buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(id))))
                put("modifier", JsonPrimitive("INCLUDES"))
                if (depth) put("depth", JsonPrimitive(0))
            })
        }
    }

    /** iOS: `downloadScenes(for:limit:scopeName:)` — newest first, skips what is already here. */
    fun downloadScenes(scope: SceneDownloadScope, limit: Int?, scopeName: String) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            this.scope.launch {
                val scenes = DownloadsFetch.scenes(scope.sceneFilter, limit)
                val pending = scenes.filter { !isDownloaded(it.id) && activeDownloads[it.id] == null }
                if (pending.isEmpty()) {
                    notify(if (scenes.isEmpty()) "No scenes for $scopeName" else "All scenes already downloaded")
                    return@launch
                }
                notify("Downloading ${pending.size} scene(s) from $scopeName")
                pending.forEach { downloadScene(it) }
            }
        }
    }

    // MARK: - Resume (offline playback)

    /** iOS: `updateLocalResumeTime` — past 98 % the position is dropped. */
    fun updateLocalResumeTime(id: String, seconds: Double, duration: Double?) {
        onMain {
            val index = downloads.indexOfFirst { it.id == id }
            if (index < 0) return@onMain
            val resume = DownloadsMetadataCodec.resolvedResumeTime(seconds, duration ?: downloads[index].duration)
            if (downloads[index].resumeTime == resume) return@onMain
            setScenes(downloads.toMutableList().also { it[index] = it[index].copy(resumeTime = resume) })
            saveMetadata()
        }
    }

    /** For the player: remembers where offline playback of [sceneId] stopped. */
    fun saveResumeTime(sceneId: String, seconds: Double, duration: Double? = null) =
        updateLocalResumeTime(sceneId, seconds, duration)

    // MARK: - Delete / cancel

    fun deleteDownload(id: String) {
        onMain {
            if (downloads.none { it.id == id }) return@onMain
            setScenes(downloads.filter { it.id != id })
            saveMetadata()
            scope.launch(Dispatchers.IO) { File(root, id).deleteRecursively() }
        }
    }

    fun deleteGalleryDownload(id: String) {
        onMain {
            if (galleryDownloads.none { it.id == id }) return@onMain
            galleryDownloads = galleryDownloads.filter { it.id != id }
            saveGalleryMetadata()
            scope.launch(Dispatchers.IO) { File(root, galleryFolderName(id)).deleteRecursively() }
        }
    }

    /** Cancel for whatever the Active / Queued rows show. */
    fun cancelActiveDownload(id: String) {
        onMain {
            if (id in runningSceneIds || sceneQueue.any { it.id == id } || id in queuedSceneIds) cancelDownload(id)
            else cancelGalleryDownload(id)
        }
    }

    /** Cancels a scene transfer (running or still waiting for a slot) and drops partial data. */
    fun cancelDownload(id: String) {
        onMain {
            if (activeDownloads[id] == null) return@onMain
            if (sceneQueue.any { it.id == id } && id !in runningSceneIds) {
                sceneQueue.removeAll { it.id == id }
                queuedSceneIds = queuedSceneIds - id
                activeDownloads = activeDownloads - id
                return@onMain
            }
            DownloadsEngine.cancel(Prefs.appContext, DownloadsPendingStore.sceneKey(id))
            activeDownloads = activeDownloads - id
            finishSceneDownload(id)
        }
    }

    /** Stops a running gallery / tag / image download and discards what was fetched. */
    fun cancelGalleryDownload(id: String) {
        onMain {
            if (activeDownloads[id] == null) return@onMain
            entryTokens.remove(id)
            DownloadsEngine.cancel(Prefs.appContext, DownloadsPendingStore.entryKey(id))
            activeDownloads = activeDownloads - id
            if (!isGalleryDownloaded(id)) scope.launch(Dispatchers.IO) { File(root, galleryFolderName(id)).deleteRecursively() }
            notify("Download cancelled")
        }
    }

    // MARK: - Images, galleries, tags, filters

    /** iOS: `downloadImage(_:)` — one image as its own entry `image-<id>`. */
    fun downloadImage(image: StashImage) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            val entryId = "image-${image.id}"
            if (isGalleryDownloaded(entryId) || activeDownloads[entryId] != null) return@onMain
            val fileTitle = image.downloadTitle
            val title = fileTitle ?: "Image"
            activeDownloads = activeDownloads + (entryId to ActiveDownload(entryId, title, 0.05))
            enqueueImages(
                PendingImageDownload(
                    entryId = entryId, title = title, entryTitle = fileTitle, mode = PendingImageDownload.MODE_IMAGE,
                    images = listOf(pendingImage(image) ?: run { activeDownloads = activeDownloads - entryId; notify("Download failed"); return@onMain }),
                    studioName = image.studio?.name, performerNames = image.performers.orEmpty().mapNotNull { it.name },
                    serverImageCount = 1, sourceKind = DownloadedGallery.Kind.Image.raw,
                ),
            )
        }
    }

    /** iOS: `downloadGallery(_:limit:)` — `limit` caps to the newest N images. */
    fun downloadGallery(gallery: Gallery, limit: Int?) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            val id = gallery.id
            if (isGalleryDownloaded(id) || activeDownloads[id] != null) return@onMain
            val title = gallery.title?.takeIf { it.isNotEmpty() } ?: "Gallery"
            activeDownloads = activeDownloads + (id to ActiveDownload(id, title, 0.02))
            fetchThenEnqueue(id, onEmpty = "Gallery has no images", isError = true, fetch = { DownloadsFetch.galleryImages(id, limit) }) { images, total ->
                PendingImageDownload(
                    entryId = id, title = title, entryTitle = gallery.title, mode = PendingImageDownload.MODE_NEW,
                    images = images, studioName = gallery.studio?.name, performerNames = gallery.performers.orEmpty().map { it.name },
                    serverImageCount = total, sourceKind = DownloadedGallery.Kind.Gallery.raw,
                )
            }
        }
    }

    /** iOS: `downloadTagImages(tagId:tagName:limit:)` — stored as entry `tag-<id>`. */
    fun downloadTagImages(tagId: String, tagName: String, limit: Int?) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            val entryId = "tag-$tagId"
            if (isGalleryDownloaded(entryId) || activeDownloads[entryId] != null) return@onMain
            activeDownloads = activeDownloads + (entryId to ActiveDownload(entryId, tagName, 0.02))
            fetchThenEnqueue(entryId, onEmpty = "No images for this tag", isError = true, fetch = { DownloadsFetch.tagImages(tagId, limit) }) { images, total ->
                PendingImageDownload(
                    entryId = entryId, title = tagName, entryTitle = tagName, mode = PendingImageDownload.MODE_NEW,
                    images = images, serverImageCount = total, sourceKind = DownloadedGallery.Kind.Tag.raw,
                )
            }
        }
    }

    /** iOS: `syncGallery(id:limit:)` — fetches the newest images and stores the new ones. */
    fun syncGallery(id: String, limit: Int? = null) = syncEntry(id, limit, expectTag = false)

    /** iOS: `syncTagImages(entryId:limit:)`. */
    fun syncTagImages(entryId: String, limit: Int? = null) = syncEntry(entryId, limit, expectTag = true)

    private fun syncEntry(id: String, limit: Int?, expectTag: Boolean) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            val existing = downloadedGallery(id) ?: return@onMain
            if (expectTag && existing.resolvedKind != DownloadedGallery.Kind.Tag) return@onMain
            if (!expectTag && existing.isSingleImage) return@onMain
            if (activeDownloads[id] != null) return@onMain
            activeDownloads = activeDownloads + (id to ActiveDownload(id, existing.displayTitle, 0.02))
            val known = existing.images.map { it.id }.toSet()
            val token = newToken(id)
            scope.launch {
                val (images, total) = if (expectTag) DownloadsFetch.tagImages(id.removePrefix("tag-"), limit) else DownloadsFetch.galleryImages(id, limit)
                if (isStale(id, token)) return@launch
                val fresh = images.filter { it.id !in known }
                if (fresh.isEmpty()) {
                    activeDownloads = activeDownloads - id
                    updateGallery(id) { it.copy(serverImageCount = total) }
                    notify("Already up to date")
                    return@launch
                }
                enqueueImages(PendingImageDownload(
                    entryId = id, title = existing.displayTitle, entryTitle = existing.title, mode = PendingImageDownload.MODE_SYNC,
                    images = fresh.mapNotNull { pendingImage(it) }, serverImageCount = total, sourceKind = existing.sourceKind,
                ))
            }
        }
    }

    /** iOS: `downloadFilterImages` — newest images of a saved image filter, entry `filter-<id>`. */
    fun downloadFilterImages(filterId: String, filterName: String, imageFilter: JsonObject, limit: Int?) {
        ensureLoaded()
        onMain {
            if (!requireDownloadEntitlement()) return@onMain
            val entryId = "filter-$filterId"
            if (activeDownloads[entryId] != null) return@onMain
            val known = downloadedGallery(entryId)?.images?.map { it.id }?.toSet().orEmpty()
            activeDownloads = activeDownloads + (entryId to ActiveDownload(entryId, filterName, 0.02))
            val token = newToken(entryId)
            scope.launch {
                val (images, total) = DownloadsFetch.filterImages(imageFilter, limit)
                if (isStale(entryId, token)) return@launch
                val fresh = images.filter { it.id !in known }
                if (fresh.isEmpty()) {
                    activeDownloads = activeDownloads - entryId
                    notify(if (images.isEmpty()) "No images for this filter" else "Already up to date")
                    return@launch
                }
                enqueueImages(PendingImageDownload(
                    entryId = entryId, title = filterName, entryTitle = filterName, mode = PendingImageDownload.MODE_FILTER,
                    images = fresh.mapNotNull { pendingImage(it) }, serverImageCount = total,
                    sourceKind = DownloadedGallery.Kind.Tag.raw,
                ))
            }
        }
    }

    private var titleBackfillRunning = false
    private var titleBackfillDone = false

    /**
     * Images downloaded before the file-name fallback were stored with `title = null` and showed
     * "Untitled". Looks them up once per launch — matched by id AND `created_at`, so another active
     * server can never rename them — and stores the file-name title. Offline it retries next time.
     */
    fun backfillMissingImageTitles() {
        ensureLoaded()
        onMain {
            if (titleBackfillDone || titleBackfillRunning) return@onMain
            val missing = galleryDownloads.flatMap { entry -> entry.images.filter { it.title.isNullOrBlank() && it.createdAt != null } }
            if (missing.isEmpty()) { titleBackfillDone = true; return@onMain }
            titleBackfillRunning = true
            scope.launch {
                val found = DownloadsFetch.imageDownloadTitles(missing.map { it.id }.distinct())
                titleBackfillRunning = false
                if (found == null) return@launch
                // Done once every candidate resolved; a miss (e.g. another server active) retries later.
                titleBackfillDone = missing.all { found[it.id]?.first == it.createdAt }
                var changed = false
                galleryDownloads = galleryDownloads.map { entry ->
                    var entryChanged = false
                    val images = entry.images.map { image ->
                        val hit = found[image.id]
                        if (image.title.isNullOrBlank() && hit != null && hit.first == image.createdAt) {
                            entryChanged = true
                            image.copy(title = hit.second)
                        } else image
                    }
                    if (!entryChanged) return@map entry
                    changed = true
                    val title = if (entry.isSingleImage && entry.title.isNullOrBlank()) images.firstOrNull()?.title else entry.title
                    entry.copy(images = images, title = title)
                }
                if (changed) saveGalleryMetadata()
            }
        }
    }

    private fun fetchThenEnqueue(
        entryId: String,
        onEmpty: String,
        isError: Boolean,
        fetch: suspend () -> Pair<List<StashImage>, Int>,
        build: (List<PendingImage>, Int) -> PendingImageDownload,
    ) {
        val token = newToken(entryId)
        scope.launch {
            val (images, total) = fetch()
            if (isStale(entryId, token)) return@launch
            val pending = images.mapNotNull { pendingImage(it) }
            if (pending.isEmpty()) {
                activeDownloads = activeDownloads - entryId
                notify(onEmpty, isError)
                return@launch
            }
            enqueueImages(build(pending, total))
        }
    }

    private fun newToken(entryId: String): Long = (++tokenCounter).also { entryTokens[entryId] = it }

    private fun isStale(entryId: String, token: Long): Boolean =
        entryTokens[entryId] != token || activeDownloads[entryId] == null

    private fun enqueueImages(pending: PendingImageDownload) {
        DownloadsEngine.enqueueImages(Prefs.appContext, pending)
    }

    private fun pendingImage(image: StashImage): PendingImage? {
        val url = image.imageURL ?: return null
        val file = image.visualFiles?.firstOrNull()
        return PendingImage(
            id = image.id,
            url = url,
            ext = DownloadsMetadataCodec.imageFileExtension(file?.basename, file?.path, image.paths?.image),
            title = image.downloadTitle,
            createdAt = image.createdAt,
            isVideo = image.isVideo,
            performerNames = image.performers.orEmpty().mapNotNull { it.name },
            tagNames = image.tags.orEmpty().mapNotNull { it.name },
        )
    }

    private fun updateGallery(id: String, transform: (DownloadedGallery) -> DownloadedGallery) {
        val index = galleryDownloads.indexOfFirst { it.id == id }
        if (index < 0) return
        galleryDownloads = galleryDownloads.toMutableList().also { it[index] = transform(it[index]) }
        saveGalleryMetadata()
    }

    // MARK: - Worker callbacks (main thread)

    internal fun workerStarted(id: String, title: String, isScene: Boolean) {
        if (activeDownloads[id] == null) activeDownloads = activeDownloads + (id to ActiveDownload(id, title, if (isScene) 0.05 else 0.02))
        if (isScene) { runningSceneIds += id; queuedSceneIds = queuedSceneIds - id }
    }

    internal fun updateActive(id: String, transform: (ActiveDownload) -> ActiveDownload) {
        val current = activeDownloads[id] ?: return
        activeDownloads = activeDownloads + (id to transform(current))
    }

    /** iOS: `sampleSpeed` — bytes/s, sampled at most once a second. */
    internal fun sampleSpeed(id: String, written: Long): Double {
        val now = System.currentTimeMillis()
        val previous = speedSamples[id] ?: run { speedSamples[id] = now to written; return 0.0 }
        val elapsed = (now - previous.first) / 1000.0
        if (elapsed < 1) return activeDownloads[id]?.speed ?: 0.0
        speedSamples[id] = now to written
        val delta = (written - previous.second).toDouble()
        return if (delta > 0) delta / elapsed else 0.0
    }

    internal fun sceneCommitted(meta: DownloadedScene) {
        setScenes(downloads.filter { it.id != meta.id } + meta)
        activeDownloads = activeDownloads - meta.id
        saveMetadata()
        finishSceneDownload(meta.id)
    }

    internal fun sceneFailed(id: String) {
        activeDownloads = activeDownloads - id
        finishSceneDownload(id)
    }

    /** Commits stored images of an image worker (iOS completion blocks of the image downloads). */
    internal fun imagesCommitted(p: PendingImageDownload, stored: List<DownloadedGalleryImage>) {
        val id = p.entryId
        entryTokens.remove(id)
        activeDownloads = activeDownloads - id
        speedSamples.remove(id)
        when (p.mode) {
            PendingImageDownload.MODE_SYNC -> {
                if (galleryDownloads.none { it.id == id }) return
                updateGallery(id) { it.copy(images = stored + it.images, downloadDate = AppleDate.now(), serverImageCount = p.serverImageCount) }
                notify("Added ${stored.size} new image(s)")
            }
            PendingImageDownload.MODE_FILTER -> {
                if (stored.isEmpty()) {
                    if (!isGalleryDownloaded(id)) File(root, galleryFolderName(id)).deleteRecursively()
                    notify("Download failed", true); return
                }
                if (isGalleryDownloaded(id)) {
                    updateGallery(id) { it.copy(images = stored + it.images, downloadDate = AppleDate.now(), serverImageCount = p.serverImageCount) }
                } else {
                    galleryDownloads = listOf(DownloadedGallery(
                        id = id, title = p.entryTitle, downloadDate = AppleDate.now(),
                        localCoverPath = stored.first().localPath, images = stored, isSingleImage = false,
                        sourceKind = p.sourceKind, serverImageCount = p.serverImageCount,
                    )) + galleryDownloads
                    saveGalleryMetadata()
                }
                notify("Added ${stored.size} image(s) from ${p.title}")
            }
            else -> {
                if (stored.isEmpty()) {
                    File(root, galleryFolderName(id)).deleteRecursively()
                    notify("Download failed", true); return
                }
                val single = p.mode == PendingImageDownload.MODE_IMAGE
                galleryDownloads = galleryDownloads.filter { it.id != id } + DownloadedGallery(
                    id = id, title = p.entryTitle, studioName = p.studioName, performerNames = p.performerNames,
                    downloadDate = AppleDate.now(), localCoverPath = stored.first().thumbnailPath ?: stored.first().localPath,
                    images = stored, isSingleImage = single, sourceKind = p.sourceKind, serverImageCount = p.serverImageCount,
                )
                saveGalleryMetadata()
                notify(if (single) "Image downloaded" else "Downloaded ${stored.size} image(s)")
            }
        }
    }

    internal fun imagesFailed(id: String) {
        entryTokens.remove(id)
        activeDownloads = activeDownloads - id
        speedSamples.remove(id)
    }

    // MARK: - Helpers

    /** iOS: `requireDownloadEntitlement()` — stashy+ gate with toast and paywall. */
    fun requireDownloadEntitlement(): Boolean {
        if (StashyPlus.isUnlocked) return true
        de.letzgo.stashy.ui.tools.showToast("Downloads are part of stashy+ — unlock in Settings")
        runCatching { de.letzgo.stashy.ui.tools.openStashyPlusPaywall() }
        return false
    }

    @Suppress("UNUSED_PARAMETER")
    private fun notify(message: String, isError: Boolean = false) = onMain { de.letzgo.stashy.ui.tools.showToast(message) }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else scope.launch { block() }
    }
}
