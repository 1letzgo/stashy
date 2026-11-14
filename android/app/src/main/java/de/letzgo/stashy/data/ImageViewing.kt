package de.letzgo.stashy.data

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Precision
import coil3.size.Size
import coil3.toBitmap
import de.letzgo.stashy.R
import java.util.concurrent.ConcurrentHashMap

/**
 * iOS: image viewing options. Keys are shared with iOS (settings export / iCloud sync):
 * `images_fullscreen_scaling` (fit | fill | auto, legacy `images_fullscreen_immersive`),
 * `images_background` (black | match),
 * `images_grid_fit` and `images_fullscreen_keep_rating`.
 */
enum class ImageScalingMode(val raw: String, @StringRes val titleRes: Int) {
    Fit("fit", R.string.scaling_fit),
    Fill("fill", R.string.scaling_fill),
    Auto("auto", R.string.automatic);

    /** Whether media of this orientation is cropped to cover a space of that orientation. */
    fun fills(mediaIsPortrait: Boolean, spaceIsPortrait: Boolean): Boolean = when (this) {
        Fit -> false
        Fill -> true
        Auto -> mediaIsPortrait == spaceIsPortrait
    }

    companion object {
        /** The stored value, else the former Immersive switch (true → auto, false → fit). */
        fun resolve(stored: String?, legacyImmersive: Boolean): ImageScalingMode =
            entries.firstOrNull { it.raw == stored } ?: if (legacyImmersive) Auto else Fit
    }
}

enum class ImageBackdropMode(val raw: String, @StringRes val titleRes: Int) {
    Black("black", R.string.black),
    Match("match", R.string.match_image);

    companion object {
        fun resolve(stored: String?): ImageBackdropMode = entries.firstOrNull { it.raw == stored } ?: Black
    }
}

object ImageViewing {
    const val SCALING_KEY = "images_fullscreen_scaling"
    const val LEGACY_IMMERSIVE_KEY = "images_fullscreen_immersive"
    const val BACKGROUND_KEY = "images_background"
    const val GRID_FIT_KEY = "images_grid_fit"
    const val KEEP_RATING_KEY = "images_fullscreen_keep_rating"

    /** Bumped by every write here so composables that read a value recompose. */
    private var revision by mutableIntStateOf(0)

    var scaling: ImageScalingMode
        get() { revision; return ImageScalingMode.resolve(Prefs.string(SCALING_KEY), Prefs.bool(LEGACY_IMMERSIVE_KEY, true)) }
        set(v) { Prefs.setString(SCALING_KEY, v.raw); revision++ }

    var backdrop: ImageBackdropMode
        get() { revision; return ImageBackdropMode.resolve(Prefs.string(BACKGROUND_KEY)) }
        set(v) { Prefs.setString(BACKGROUND_KEY, v.raw); revision++ }

    var gridFit: Boolean
        get() { revision; return Prefs.bool(GRID_FIT_KEY, false) }
        set(v) { Prefs.setBool(GRID_FIT_KEY, v); revision++ }

    var keepRating: Boolean
        get() { revision; return Prefs.bool(KEEP_RATING_KEY, false) }
        set(v) { Prefs.setBool(KEEP_RATING_KEY, v); revision++ }

    private val averages = ConcurrentHashMap<String, Int>()

    /** The image's own average colour (1×1 scale of the small image), computed once per URL. */
    suspend fun averageColor(context: Context, url: String): Color? {
        averages[url]?.let { return Color(it) }
        val request = ImageRequest.Builder(context).data(url).size(Size(64, 64)).precision(Precision.INEXACT).allowHardware(false).build()
        val bitmap = (SingletonImageLoader.get(context).execute(request) as? SuccessResult)?.image?.toBitmap() ?: return null
        val argb = android.graphics.Bitmap.createScaledBitmap(bitmap, 1, 1, true).getPixel(0, 0) or 0xFF000000.toInt()
        averages[url] = argb
        return Color(argb)
    }

    /** The backdrop colour behind an image: black or its own average (until known: black). */
    @Composable
    fun backdropColor(url: String?): Color {
        val mode = backdrop
        if (mode != ImageBackdropMode.Match || url == null) return Color.Black
        val context = LocalContext.current.applicationContext
        val color by produceState(averages[url]?.let { Color(it) } ?: Color.Black, url) {
            averageColor(context, url)?.let { value = it }
        }
        return color
    }
}
