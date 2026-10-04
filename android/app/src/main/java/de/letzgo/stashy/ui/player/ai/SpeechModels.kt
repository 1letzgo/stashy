package de.letzgo.stashy.ui.player.ai

import android.content.Context
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.await
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.vosk.Model
import java.io.File
import java.util.Locale
import java.util.zip.ZipInputStream
import kotlin.coroutines.coroutineContext

/**
 * The on-device speech models (iOS: SpeechTranscriber locales + `AssetInventory` downloads).
 * Android has no system speech-to-text that accepts a PCM stream with word timings, so stashy
 * uses Vosk (Kaldi) with its small per-language models. Like iOS's language packs they are
 * never fetched without an explicit "Download" tap and live in `filesDir/speech-models/`.
 */
object SpeechModelCatalog {
    /** One downloadable model; [code] is the scene-language base it serves. */
    data class Entry(val code: String, val modelName: String, val megabytes: Int) {
        val url: String get() = "https://alphacephei.com/vosk/models/$modelName.zip"
        val sizeText: String get() = "$megabytes MB"
        val displayName: String get() = SubtitleTargetLanguage.displayName(code)
    }

    /** Vosk's current "small" (mobile) models, from alphacephei.com/vosk/models/model-list.json. */
    val entries: List<Entry> = listOf(
        Entry("ar", "vosk-model-small-ar-0.3", 104),
        Entry("ca", "vosk-model-small-ca-0.4", 43),
        Entry("cs", "vosk-model-small-cs-0.4-rhasspy", 46),
        Entry("de", "vosk-model-small-de-0.15", 46),
        Entry("en", "vosk-model-small-en-us-0.15", 41),
        Entry("en-gb", "vosk-model-small-en-gb-0.15", 43),
        Entry("en-in", "vosk-model-small-en-in-0.4", 38),
        Entry("eo", "vosk-model-small-eo-0.42", 44),
        Entry("es", "vosk-model-small-es-0.42", 40),
        Entry("fa", "vosk-model-small-fa-0.42", 53),
        Entry("fr", "vosk-model-small-fr-0.22", 42),
        Entry("gu", "vosk-model-small-gu-0.42", 108),
        Entry("hi", "vosk-model-small-hi-0.22", 44),
        Entry("it", "vosk-model-small-it-0.22", 50),
        Entry("ja", "vosk-model-small-ja-0.22", 50),
        Entry("ka", "vosk-model-small-ka-0.42", 46),
        Entry("kk", "vosk-model-small-kz-0.42", 60),
        Entry("ko", "vosk-model-small-ko-0.22", 87),
        Entry("ky", "vosk-model-small-ky-0.42", 51),
        Entry("nl", "vosk-model-small-nl-0.22", 40),
        Entry("pl", "vosk-model-small-pl-0.22", 53),
        Entry("pt", "vosk-model-small-pt-0.3", 32),
        Entry("ru", "vosk-model-small-ru-0.22", 46),
        Entry("sv", "vosk-model-small-sv-rhasspy-0.15", 303),
        Entry("te", "vosk-model-small-te-0.42", 60),
        Entry("tg", "vosk-model-small-tg-0.22", 52),
        Entry("tr", "vosk-model-small-tr-0.3", 37),
        Entry("uk", "vosk-model-small-uk-v3-small", 144),
        Entry("uz", "vosk-model-small-uz-0.22", 51),
        Entry("vi", "vosk-model-small-vn-0.4", 34),
        Entry("zh", "vosk-model-small-cn-0.22", 44),
    )

    /** Languages without spaces between words — their words are joined without a blank. */
    val unspacedLanguages = setOf("zh", "ja")

    /**
     * iOS: `SpeechTranscriptionLocaleResolver.supportedLocaleMatching` — exact regional model
     * first (`en-GB`), then the language. Never falls back to another language (a Czech scene must
     * not be transcribed with the German model).
     */
    fun entry(sceneTag: String?): Entry? {
        val tag = sceneTag?.trim()?.lowercase()?.replace('_', '-')?.takeIf { it.isNotEmpty() } ?: return null
        entries.firstOrNull { it.code == tag }?.let { return it }
        val base = SubtitleTargetLanguage.languageCode(tag) ?: return null
        if (base == "yue") return null   // Cantonese is not Mandarin.
        val region = tag.split('-').drop(1).firstOrNull { it.length == 2 }
        if (region != null) entries.firstOrNull { it.code == "$base-$region" }?.let { return it }
        return entries.firstOrNull { it.code == base }
    }

    /** iOS: `sceneLanguagePickerOptions()` — one row per language, sorted by name. */
    fun pickerOptions(display: Locale = Locale.getDefault()): List<Pair<String, String>> =
        entries.map { it.code }.filter { !it.contains('-') }
            .map { it to SubtitleTargetLanguage.displayName(it, display) }
            .sortedBy { it.second.lowercase(display) }

    /** iOS: `SpeechTranscriberAvailability.matchingPickerId` — stored tag → picker row. */
    fun matchingPickerId(stored: String?, optionIds: List<String>): String? {
        val needle = stored?.replace('_', '-')?.lowercase() ?: return null
        optionIds.firstOrNull { it.lowercase() == needle }?.let { return it }
        val base = SubtitleTargetLanguage.languageCode(needle) ?: return null
        return optionIds.firstOrNull { it == base }
    }
}

object SpeechModelStore {
    private val mutex = Mutex()
    private var loaded: Pair<String, Model>? = null

    private fun root(context: Context) = File(context.filesDir, "speech-models")
    private fun dir(context: Context, entry: SpeechModelCatalog.Entry) = File(root(context), entry.modelName)

    fun isInstalled(context: Context, entry: SpeechModelCatalog.Entry): Boolean =
        File(dir(context, entry), ".complete").exists()

    /** Bytes used by all downloaded speech models (Settings). */
    fun installedBytes(context: Context): Long = root(context).walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    fun deleteAll(context: Context) {
        loaded?.second?.let { runCatching { it.close() } }
        loaded = null
        root(context).deleteRecursively()
    }

    /**
     * Downloads and unpacks [entry] (zip with one top-level folder). [progress] gets 0…1 on the
     * caller's dispatcher-agnostic callback. Cancellable; a partial download leaves nothing behind.
     */
    suspend fun download(context: Context, entry: SpeechModelCatalog.Entry, progress: (Double) -> Unit) = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (isInstalled(context, entry)) return@withLock
            val target = dir(context, entry)
            val staging = File(root(context), entry.modelName + ".partial")
            staging.deleteRecursively(); staging.mkdirs()
            try {
                Net.client.newCall(Request.Builder().url(entry.url).build()).await().use { response ->
                    if (!response.isSuccessful) throw IllegalStateException("Speech model download failed (HTTP ${response.code})")
                    val body = response.body ?: throw IllegalStateException("Speech model download failed")
                    val total = body.contentLength().takeIf { it > 0 } ?: (entry.megabytes * 1_000_000L)
                    val counting = CountingStream(body.byteStream()) { read -> progress((read.toDouble() / total).coerceIn(0.0, 0.99)) }
                    ZipInputStream(counting.buffered()).use { zip ->
                        while (true) {
                            coroutineContext.ensureActive()
                            val e = zip.nextEntry ?: break
                            // Strip the zip's top-level folder; refuse path traversal.
                            val rel = e.name.substringAfter('/', "").takeIf { it.isNotEmpty() } ?: continue
                            val out = File(staging, rel)
                            if (!out.canonicalPath.startsWith(staging.canonicalPath)) continue
                            if (e.isDirectory) { out.mkdirs(); continue }
                            out.parentFile?.mkdirs()
                            out.outputStream().use { zip.copyTo(it) }
                        }
                    }
                }
                File(staging, ".complete").writeText(entry.modelName)
                target.deleteRecursively()
                if (!staging.renameTo(target)) throw IllegalStateException("Could not install speech model")
                progress(1.0)
            } finally {
                staging.deleteRecursively()
            }
        }
    }

    /** Loads (and keeps one) Vosk model; a few hundred ms to seconds, so off the main thread. */
    suspend fun load(context: Context, entry: SpeechModelCatalog.Entry): Model = withContext(Dispatchers.IO) {
        mutex.withLock {
            loaded?.let { (name, model) -> if (name == entry.modelName) return@withLock model }
            loaded?.second?.let { runCatching { it.close() } }
            loaded = null
            val model = Model(dir(context, entry).absolutePath)
            loaded = entry.modelName to model
            model
        }
    }

    private class CountingStream(private val inner: java.io.InputStream, private val onRead: (Long) -> Unit) : java.io.InputStream() {
        private var count = 0L
        private var lastReport = 0L
        private fun note(n: Int) { if (n > 0) { count += n; if (count - lastReport > 256_000) { lastReport = count; onRead(count) } } }
        override fun read(): Int = inner.read().also { if (it >= 0) note(1) }
        override fun read(b: ByteArray, off: Int, len: Int): Int = inner.read(b, off, len).also { note(it) }
        override fun close() = inner.close()
    }
}
