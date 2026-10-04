package de.letzgo.stashy.ui.player

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.await
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request

/**
 * iOS: `SceneScrubSprites` — Stash's scrubber sprite sheet (one JPEG grid + a WebVTT index) as
 * the scrub preview's source. Reading a tile costs nothing, so the time bar shows a still under
 * the finger from the first second. [prepare] fetches sheet + index once; [thumbnail] returns
 * null while loading or when the scene has no sprites ([isUnavailable]).
 */
class SceneScrubSprites private constructor(private val vttURL: String, private val spriteURL: String) {
    private var tiles: List<SpriteTile> = emptyList()
    private var sheet: Bitmap? = null
    private var job: Job? = null
    private val cropped = HashMap<SpriteTile, ImageBitmap>()
    var isUnavailable = false; private set

    fun prepare(scope: CoroutineScope = MainScope()) {
        if (job != null || isUnavailable) return
        job = scope.launch {
            val (vtt, bytes) = withContext(Dispatchers.IO) {
                val a = async { load(vttURL) }
                val b = async { load(spriteURL) }
                a.await()?.toString(Charsets.UTF_8) to b.await()
            }
            val bitmap = bytes?.let { withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(it, 0, it.size) } }
            val parsed = vtt?.let { WebVtt.parseSpriteTiles(it) }.orEmpty()
            if (bitmap == null || parsed.isEmpty()) { isUnavailable = true; return@launch }
            tiles = parsed
            sheet = bitmap
        }
    }

    fun thumbnail(seconds: Double): ImageBitmap? {
        val sheet = sheet ?: return null
        val tile = WebVtt.tileAt(tiles, seconds) ?: return null
        cropped[tile]?.let { return it }
        if (tile.x + tile.width > sheet.width || tile.y + tile.height > sheet.height) return null
        val image = Bitmap.createBitmap(sheet, tile.x, tile.y, tile.width, tile.height).asImageBitmap()
        cropped[tile] = image
        return image
    }

    private suspend fun load(url: String): ByteArray? = runCatching {
        Net.client.newCall(Request.Builder().url(url).build()).await().use { if (it.isSuccessful) it.body?.bytes() else null }
    }.getOrNull()

    companion object {
        /** nil when the scene has no `paths.vtt` / `paths.sprite` (iOS failable init). */
        fun create(vttPath: String?, spritePath: String?): SceneScrubSprites? {
            if (vttPath.isNullOrEmpty() || vttPath == "null" || spritePath.isNullOrEmpty() || spritePath == "null") return null
            return SceneScrubSprites(Net.signed(vttPath) ?: return null, Net.signed(spritePath) ?: return null)
        }
    }
}
