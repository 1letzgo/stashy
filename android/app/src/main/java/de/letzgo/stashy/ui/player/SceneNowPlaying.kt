@file:OptIn(UnstableApi::class)

package de.letzgo.stashy.ui.player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import coil3.SingletonImageLoader
import coil3.request.ErrorResult
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Precision
import coil3.toBitmap
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import de.letzgo.stashy.data.Scene
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.IOException

/**
 * What the media session shows for a scene (iOS: `MPNowPlayingInfoCenter` of the scene player) —
 * media notification, lock screen, Bluetooth (AVRCP) and other `MediaController`s.
 *
 * Android's media notification / system media controls render only two text lines: `title` and
 * `artist`. So [artist] carries "Performers · Studio" (whichever exists); the separate fields
 * ([performers] as `albumArtist`, [studio] as `albumTitle`, date as release date) are still set
 * for controllers that show more (car head units, AVRCP browsers, Wear).
 */
data class SceneNowPlaying(
    val title: String,
    val performers: String?,
    val studio: String?,
    val date: String?,
    val artworkUrl: String?,
) {
    /** The second line of the notification: "Performers · Studio". */
    val artist: String? get() = listOfNotNull(performers, studio).joinToString(" · ").takeIf { it.isNotEmpty() }

    /** `yyyy-MM-dd` (Stash date) → (year, month, day); missing parts null. */
    val releaseDate: Triple<Int?, Int?, Int?>? get() {
        val parts = date?.trim()?.split('-')?.takeIf { it.isNotEmpty() } ?: return null
        val year = parts.getOrNull(0)?.toIntOrNull()?.takeIf { it in 1..9999 } ?: return null
        val month = parts.getOrNull(1)?.toIntOrNull()?.takeIf { it in 1..12 }
        val day = month?.let { parts.getOrNull(2)?.take(2)?.toIntOrNull()?.takeIf { it in 1..31 } }
        return Triple(year, month, day)
    }

    fun toMediaMetadata(): MediaMetadata = MediaMetadata.Builder()
        .setTitle(title)
        .setDisplayTitle(title)
        .setArtist(artist)
        .setSubtitle(artist)
        .setAlbumArtist(performers)
        .setAlbumTitle(studio)
        .setArtworkUri(artworkUrl?.let { Uri.parse(it) })
        .setMediaType(MediaMetadata.MEDIA_TYPE_VIDEO)
        .setIsPlayable(true)
        .setIsBrowsable(false)
        .apply {
            releaseDate?.let { (y, m, d) -> setReleaseYear(y); setReleaseMonth(m); setReleaseDay(d) }
        }
        .build()

    companion object {
        /**
         * Pure mapping (unit-tested). Title uses the UI fallback ([Scene.displayTitle]: title, else
         * file name). [artworkUrl] defaults to [Scene.thumbnailURL] — the signed screenshot, or the
         * cached poster of a download (`file://`).
         */
        fun of(scene: Scene, artworkUrl: String? = scene.thumbnailURL): SceneNowPlaying = SceneNowPlaying(
            title = scene.displayTitle,
            performers = scene.performers.map { it.name.trim() }.filter { it.isNotEmpty() }
                .joinToString(", ").takeIf { it.isNotEmpty() },
            studio = scene.studio?.name?.trim()?.takeIf { it.isNotEmpty() },
            date = scene.date?.trim()?.takeIf { it.isNotEmpty() },
            artworkUrl = artworkUrl?.takeIf { it.isNotBlank() },
        )
    }
}

/**
 * Artwork for the media session through the app's Coil [coil3.ImageLoader]: the shared
 * authenticated OkHttp client (`ApiKey` + custom headers, LAN self-signed TLS), the per-server
 * image cache, and `file://` posters of downloads. Media3's default loader can do none of that.
 * Downscaled to [MAX_ARTWORK_PX] — notifications and lock screens never need more.
 */
class StashArtworkBitmapLoader(context: Context) : BitmapLoader {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun supportsMimeType(mimeType: String): Boolean = Util.isBitmapFactorySupportedMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        scope.launch {
            runCatching {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_ARTWORK_PX) sample *= 2
                BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
                    ?: throw IOException("Could not decode artwork")
            }.fold({ future.set(it) }, { future.setException(it) })
        }
        return future
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        val job = scope.launch {
            try {
                val request = ImageRequest.Builder(appContext)
                    .data(uri.toString())
                    .size(MAX_ARTWORK_PX)
                    .precision(Precision.INEXACT)
                    // Software bitmap: the notification parcels it to System UI.
                    .allowHardware(false)
                    .build()
                when (val result = SingletonImageLoader.get(appContext).execute(request)) {
                    is SuccessResult -> future.set(result.image.toBitmap())
                    is ErrorResult -> future.setException(result.throwable)
                }
            } catch (t: Throwable) {
                future.setException(t)
            }
        }
        future.addListener({ if (future.isCancelled) job.cancel() }, Runnable::run)
        return future
    }

    companion object {
        const val MAX_ARTWORK_PX = 512
    }
}
