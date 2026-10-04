package de.letzgo.stashy.data.tools

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import de.letzgo.stashy.data.AppleDate
import de.letzgo.stashy.data.DownloadedGalleryImage
import de.letzgo.stashy.data.DownloadedScene
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.await
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.max

// ---------------------------------------------------------------------------------------------
// Pending jobs: what a worker needs to (re)run after process death. Android-only files under
// `filesDir/DownloadsPending/<key>.json` (outside `Downloads/`, so they never mix with iOS data).
// ---------------------------------------------------------------------------------------------

/** One queued scene transfer (iOS: the arguments of `startDownload`). */
@Serializable
data class PendingSceneDownload(
    val sceneId: String,
    val title: String,
    val videoURL: String,
    val thumbnailURL: String? = null,
    val ext: String = "mp4",
    /** Metadata committed on success (`downloadDate` is set then). */
    val meta: DownloadedScene,
)

/** One image to fetch for a gallery-like entry. */
@Serializable
data class PendingImage(
    val id: String,
    val url: String,
    val ext: String = "jpg",
    val title: String? = null,
    val createdAt: String? = null,
    val isVideo: Boolean = false,
    val performerNames: List<String> = emptyList(),
    val tagNames: List<String> = emptyList(),
)

/** An image batch (gallery / single image / tag / filter / sync — iOS: `downloadImages`). */
@Serializable
data class PendingImageDownload(
    val entryId: String,
    /** Title shown in the active row. */
    val title: String,
    /** Title stored in the metadata (may be nil like iOS `gallery.title`). */
    val entryTitle: String? = null,
    val mode: String,
    val images: List<PendingImage>,
    val studioName: String? = null,
    val performerNames: List<String> = emptyList(),
    val serverImageCount: Int? = null,
    val sourceKind: String? = null,
) {
    companion object {
        /** New gallery / tag entry. */
        const val MODE_NEW = "new"
        /** Single image entry (`isSingleImage`). */
        const val MODE_IMAGE = "image"
        /** Prepend to an existing entry. */
        const val MODE_SYNC = "sync"
        /** Saved image filter: insert or prepend. */
        const val MODE_FILTER = "filter"
    }
}

/** A worker found alive at startup. */
data class RestoredDownload(val id: String, val title: String, val isScene: Boolean)

object DownloadsPendingStore {
    private const val SCENE_PREFIX = "scene-"
    private const val ENTRY_PREFIX = "entry-"
    private val json get() = de.letzgo.stashy.data.DownloadsMetadataCodec.json

    fun sceneKey(sceneId: String) = SCENE_PREFIX + sceneId
    fun entryKey(entryId: String) = ENTRY_PREFIX + entryId
    fun isSceneKey(key: String) = key.startsWith(SCENE_PREFIX)
    /** Active-download id for a key (scene id or entry id). */
    fun idForKey(key: String) = key.removePrefix(SCENE_PREFIX).removePrefix(ENTRY_PREFIX)

    private fun dir(context: Context) = File(context.filesDir, "DownloadsPending")
    private fun file(context: Context, key: String) = File(dir(context), "$key.json")

    fun writeScene(context: Context, p: PendingSceneDownload) = write(context, sceneKey(p.sceneId), json.encodeToString(PendingSceneDownload.serializer(), p))
    fun writeImages(context: Context, p: PendingImageDownload) = write(context, entryKey(p.entryId), json.encodeToString(PendingImageDownload.serializer(), p))

    fun readScene(context: Context, key: String): PendingSceneDownload? =
        runCatching { json.decodeFromString(PendingSceneDownload.serializer(), file(context, key).readText()) }.getOrNull()
    fun readImages(context: Context, key: String): PendingImageDownload? =
        runCatching { json.decodeFromString(PendingImageDownload.serializer(), file(context, key).readText()) }.getOrNull()

    fun delete(context: Context, key: String) { file(context, key).delete() }

    fun keys(context: Context): List<String> =
        dir(context).listFiles()?.filter { it.name.endsWith(".json") }?.map { it.name.removeSuffix(".json") }.orEmpty()

    /** Download folders of jobs that are still pending — the orphan cleanup must keep them. */
    fun protectedFolders(context: Context): Set<String> = keys(context).map {
        if (isSceneKey(it)) idForKey(it) else Downloads.galleryFolderName(idForKey(it))
    }.toSet()

    private fun write(context: Context, key: String, text: String) {
        dir(context).mkdirs()
        val target = file(context, key)
        val tmp = File(target.path + ".tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
    }
}

/**
 * The transfer engine (iOS: the background `URLSession` of `DownloadManager`). Each job is a
 * unique WorkManager work running [DownloadsWorker] as a `dataSync` foreground service.
 */
object DownloadsEngine {
    const val TAG = "stashy-download"
    internal const val KEY_INPUT = "key"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun workName(key: String) = "stashy-download-$key"

    fun enqueueScene(context: Context, pending: PendingSceneDownload) {
        val app = context.applicationContext
        scope.launch {
            DownloadsPendingStore.writeScene(app, pending)
            enqueue(app, DownloadsPendingStore.sceneKey(pending.sceneId))
        }
    }

    fun enqueueImages(context: Context, pending: PendingImageDownload) {
        val app = context.applicationContext
        scope.launch {
            DownloadsPendingStore.writeImages(app, pending)
            enqueue(app, DownloadsPendingStore.entryKey(pending.entryId))
        }
    }

    private fun enqueue(context: Context, key: String) {
        val request = OneTimeWorkRequestBuilder<DownloadsWorker>()
            .setInputData(workDataOf(KEY_INPUT to key))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .addTag(TAG)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(workName(key), ExistingWorkPolicy.KEEP, request)
    }

    /** User cancel: stops the work and drops the pending job (+ a scene's partial folder). */
    fun cancel(context: Context, key: String) {
        val app = context.applicationContext
        WorkManager.getInstance(app).cancelUniqueWork(workName(key))
        scope.launch {
            DownloadsPendingStore.delete(app, key)
            if (DownloadsPendingStore.isSceneKey(key)) File(Downloads.root, DownloadsPendingStore.idForKey(key)).deleteRecursively()
        }
    }

    /** Startup: pending jobs whose work is still alive come back as active rows; dead ones are dropped. Blocking. */
    fun restore(context: Context): List<RestoredDownload> {
        val wm = runCatching { WorkManager.getInstance(context) }.getOrNull() ?: return emptyList()
        return DownloadsPendingStore.keys(context).mapNotNull { key ->
            val infos = runCatching { wm.getWorkInfosForUniqueWork(workName(key)).get() }.getOrNull().orEmpty()
            if (infos.none { !it.state.isFinished }) {
                DownloadsPendingStore.delete(context, key)
                return@mapNotNull null
            }
            val isScene = DownloadsPendingStore.isSceneKey(key)
            val title = if (isScene) DownloadsPendingStore.readScene(context, key)?.title else DownloadsPendingStore.readImages(context, key)?.title
            RestoredDownload(DownloadsPendingStore.idForKey(key), title ?: "Download", isScene)
        }
    }
}

/** Streams one URL to a file through the authenticated client, with progress and prompt cancel. */
object DownloadsTransfer {
    private val client: OkHttpClient by lazy {
        Net.client.newBuilder().readTimeout(120, TimeUnit.SECONDS).callTimeout(0, TimeUnit.SECONDS).build()
    }

    suspend fun download(url: String, destination: File, onProgress: suspend (written: Long, total: Long) -> Unit) =
        withContext(Dispatchers.IO) {
            val call = client.newCall(Request.Builder().url(url).build())
            coroutineScope {
                // Cancels the HTTP call as soon as the worker is cancelled, even mid-read.
                val watcher = launch { try { awaitCancellation() } finally { call.cancel() } }
                try {
                    val response = call.await()
                    response.use { r ->
                        if (!r.isSuccessful) throw IOException("HTTP ${r.code}")
                        val body = r.body ?: throw IOException("Empty body")
                        val total = body.contentLength()
                        destination.parentFile?.mkdirs()
                        val part = File(destination.path + ".part")
                        body.byteStream().use { input ->
                            part.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                var written = 0L
                                while (true) {
                                    coroutineContext.ensureActive()
                                    val n = input.read(buffer)
                                    if (n < 0) break
                                    output.write(buffer, 0, n)
                                    written += n
                                    onProgress(written, total)
                                }
                            }
                        }
                        if (destination.exists()) destination.delete()
                        if (!part.renameTo(destination)) throw IOException("Could not move file")
                    }
                } catch (e: IOException) {
                    coroutineContext.ensureActive()
                    File(destination.path + ".part").delete()
                    throw e
                } finally {
                    watcher.cancel()
                }
            }
        }
}

/** iOS: `makeThumbnail` — downscaled JPEG (400 px longest edge, quality 80) next to the original. */
object DownloadsThumbnails {
    private const val MAX_PIXEL = 400

    fun make(source: File, isVideo: Boolean, destination: File): Boolean = runCatching {
        val bitmap = (if (isVideo) videoFrame(source) else imageBitmap(source)) ?: return false
        val scaled = scale(bitmap)
        destination.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        true
    }.getOrDefault(false)

    private fun videoFrame(source: File): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(source.path)
            retriever.getFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun imageBitmap(source: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PIXEL) sample *= 2
        val bitmap = BitmapFactory.decodeFile(source.path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        // Like `kCGImageSourceCreateThumbnailWithTransform`: apply the EXIF orientation.
        val degrees = runCatching {
            when (ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        }.getOrDefault(0f)
        if (degrees == 0f) return bitmap
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    private fun scale(bitmap: Bitmap): Bitmap {
        val longest = max(bitmap.width, bitmap.height)
        if (longest <= MAX_PIXEL) return bitmap
        val factor = MAX_PIXEL.toFloat() / longest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * factor).toInt().coerceAtLeast(1), (bitmap.height * factor).toInt().coerceAtLeast(1), true)
    }
}

/** Notification channel "downloads" and the progress notification of the foreground worker. */
object DownloadsNotifications {
    const val CHANNEL_ID = "downloads"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Progress of offline downloads"
                setShowBadge(false)
            },
        )
    }

    fun build(context: Context, title: String, progress: Int?, detail: String?): Notification {
        ensureChannel(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(detail ?: "Downloading")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setProgress(100, progress ?: 0, progress == null)
            .apply { launch?.let { setContentIntent(it) } }
            .build()
    }

    fun foregroundInfo(context: Context, notificationId: Int, title: String, progress: Int?, detail: String?): ForegroundInfo {
        val notification = build(context, title, progress, detail)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }
}

/**
 * The download worker: one scene (thumbnail + original file) or one image batch, run as a
 * foreground service. Progress goes straight into [Downloads] state; on success it commits the
 * metadata, on a user cancel it removes partial files, on a system stop it keeps the pending job
 * so WorkManager can retry.
 */
class DownloadsWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private val key: String get() = inputData.getString(DownloadsEngine.KEY_INPUT).orEmpty()
    private val notificationId: Int get() = 0x5D0000 or (key.hashCode() and 0xFFFF)
    private var lastNotification = 0L

    override suspend fun getForegroundInfo(): ForegroundInfo =
        DownloadsNotifications.foregroundInfo(applicationContext, notificationId, "Downloading", null, null)

    override suspend fun doWork(): Result {
        if (key.isEmpty()) return Result.failure()
        Downloads.init(applicationContext)
        return if (DownloadsPendingStore.isSceneKey(key)) runScene() else runImages()
    }

    private suspend fun foreground(title: String, progress: Int?, detail: String?, force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastNotification < 1000) return
        lastNotification = now
        try {
            setForeground(DownloadsNotifications.foregroundInfo(applicationContext, notificationId, title, progress, detail))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Background start not allowed (API 31+) — the work still runs, just without the service.
        }
    }

    /** True when the work was cancelled by the app (user), not stopped by the system. */
    private fun cancelledByUser(): Boolean = runCatching {
        WorkManager.getInstance(applicationContext).getWorkInfoById(id).get()?.state == WorkInfo.State.CANCELLED
    }.getOrDefault(true)

    private suspend fun main(block: () -> Unit) = withContext(Dispatchers.Main) { block() }

    private suspend fun runScene(): Result {
        val p = DownloadsPendingStore.readScene(applicationContext, key) ?: return Result.failure()
        val id = p.sceneId
        main { Downloads.workerStarted(id, p.title, isScene = true) }
        foreground(p.title, null, null, force = true)
        val folder = File(Downloads.root, id).apply { mkdirs() }
        try {
            p.thumbnailURL?.let { url ->
                try {
                    DownloadsTransfer.download(url, File(folder, "thumbnail.jpg")) { _, _ -> }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // iOS ignores a failed thumbnail.
                }
            }
            main { Downloads.updateActive(id) { it.copy(progress = 0.1) } }
            var lastUi = 0L
            DownloadsTransfer.download(p.videoURL, File(folder, "video.${p.ext}")) { written, total ->
                val now = SystemClock.elapsedRealtime()
                if (now - lastUi >= 250) {
                    lastUi = now
                    val fraction = if (total > 0) written.toDouble() / total else 0.0
                    main {
                        Downloads.updateActive(id) {
                            it.copy(progress = 0.1 + fraction * 0.9, speed = Downloads.sampleSpeed(id, written), downloadedSize = written, totalSize = total)
                        }
                    }
                    val percent = if (total > 0) (fraction * 100).toInt() else null
                    foreground(p.title, percent, percent?.let { "$it%" })
                }
            }
            withContext(NonCancellable + Dispatchers.Main) {
                Downloads.sceneCommitted(p.meta.copy(downloadDate = AppleDate.now()))
            }
            DownloadsPendingStore.delete(applicationContext, key)
            return Result.success()
        } catch (e: CancellationException) {
            withContext(NonCancellable + Dispatchers.IO) {
                if (cancelledByUser()) {
                    folder.deleteRecursively()
                    DownloadsPendingStore.delete(applicationContext, key)
                    withContext(Dispatchers.Main) { Downloads.sceneFailed(id) }
                }
            }
            throw e
        } catch (e: Exception) {
            withContext(NonCancellable + Dispatchers.IO) {
                folder.deleteRecursively()
                DownloadsPendingStore.delete(applicationContext, key)
                withContext(Dispatchers.Main) { Downloads.sceneFailed(id) }
            }
            return Result.failure()
        }
    }

    private suspend fun runImages(): Result {
        val p = DownloadsPendingStore.readImages(applicationContext, key) ?: return Result.failure()
        val id = p.entryId
        main { Downloads.workerStarted(id, p.title, isScene = false) }
        foreground(p.title, 0, null, force = true)
        val folderName = Downloads.galleryFolderName(id)
        val folder = File(Downloads.root, folderName).apply { mkdirs() }
        val written = mutableListOf<File>()
        val stored = mutableListOf<DownloadedGalleryImage>()
        val total = p.images.size
        var bytes = 0L
        try {
            p.images.forEachIndexed { index, image ->
                currentCoroutineContext().ensureActive()
                val fileName = "${image.id}.${image.ext}"
                val destination = File(folder, fileName)
                var lastUi = 0L
                val ok = try {
                    DownloadsTransfer.download(image.url, destination) { w, _ ->
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastUi >= 250) {
                            lastUi = now
                            val base = bytes
                            main { Downloads.updateActive(id) { it.copy(speed = Downloads.sampleSpeed(id, base + w)) } }
                        }
                    }
                    true
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    false
                }
                if (ok) {
                    written += destination
                    val thumbName = "${image.id}_thumb.jpg"
                    val thumbFile = File(folder, thumbName)
                    val thumbRelative = if (DownloadsThumbnails.make(destination, image.isVideo, thumbFile)) {
                        written += thumbFile
                        "$folderName/$thumbName"
                    } else null
                    stored += DownloadedGalleryImage(
                        id = image.id,
                        localPath = "$folderName/$fileName",
                        title = image.title,
                        createdAt = image.createdAt,
                        isVideo = image.isVideo,
                        thumbnailPath = thumbRelative,
                        performerNames = image.performerNames,
                        tagNames = image.tagNames,
                    )
                    bytes += destination.length()
                }
                val done = index + 1
                val snapshotBytes = bytes
                main {
                    Downloads.updateActive(id) {
                        it.copy(progress = max(0.02, done.toDouble() / max(total, 1)), completedUnits = done, totalUnits = total, downloadedSize = snapshotBytes)
                    }
                }
                foreground(p.title, done * 100 / max(total, 1), "$done of $total images", force = done == total)
            }
            withContext(NonCancellable + Dispatchers.Main) { Downloads.imagesCommitted(p, stored.toList()) }
            DownloadsPendingStore.delete(applicationContext, key)
            return Result.success()
        } catch (e: CancellationException) {
            withContext(NonCancellable + Dispatchers.IO) {
                if (cancelledByUser()) {
                    written.forEach { it.delete() }
                    DownloadsPendingStore.delete(applicationContext, key)
                    withContext(Dispatchers.Main) { Downloads.imagesFailed(id) }
                }
            }
            throw e
        } catch (e: Exception) {
            withContext(NonCancellable + Dispatchers.IO) {
                written.forEach { it.delete() }
                DownloadsPendingStore.delete(applicationContext, key)
                withContext(Dispatchers.Main) { Downloads.imagesFailed(id) }
            }
            return Result.failure()
        }
    }
}
