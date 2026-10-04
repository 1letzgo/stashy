package de.letzgo.stashy.ui.player.ai

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.android.gms.tasks.Task
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * iOS: `SceneCaptionTranslator` — on-device translation of caption sentences. Apple's
 * Translation framework becomes ML Kit's on-device translator; its language packs (~30 MB per
 * language) are, like on iOS, only downloaded after an explicit "Download … language pack" tap —
 * captions keep running untranslated meanwhile.
 */
class CaptionTranslator {
    /** iOS: `SceneCaptionTranslator.Availability`. */
    sealed class Availability {
        data object Ready : Availability()
        data object NeedsDownload : Availability()
        data class SourceUnsupported(val code: String) : Availability()
        data class TargetUnsupported(val code: String) : Availability()
        data class PairUnsupported(val source: String, val target: String) : Availability()
    }

    private data class Request(val id: Long, val key: String, val text: String)

    var isEnabled by mutableStateOf(false); private set
    var needsLanguageDownload by mutableStateOf(false); private set
    var isDownloadingLanguagePack by mutableStateOf(false); private set
    var statusMessage by mutableStateOf<String?>(null); private set
    /** Upper-case target code for the "Download XX language pack" row. */
    var targetCode by mutableStateOf<String?>(null); private set

    /** Delivers `(cueId, translatedText)` on the main thread. */
    var onTranslated: ((Long, String) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var translator: Translator? = null
    private var worker: Job? = null
    private var queue = Channel<Request>(capacity = MAX_QUEUED, onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST)
    private val cache = LinkedHashMap<String, String>()
    private var ready = false

    companion object {
        private const val MAX_QUEUED = 60
        private const val MAX_CACHE = 400

        fun mlKitCode(code: String?): String? {
            val c = SubtitleTargetLanguage.canonicalCode(code) ?: return null
            return TranslateLanguage.fromLanguageTag(if (c == "nb") "no" else c)
        }

        /** iOS: `availability(from:to:)` — names the actual culprit, as the toasts do. */
        suspend fun availability(source: String?, target: String): Availability {
            val src = mlKitCode(source) ?: return Availability.SourceUnsupported((SubtitleTargetLanguage.canonicalCode(source) ?: source ?: "?").uppercase())
            val tgt = mlKitCode(target) ?: return Availability.TargetUnsupported(target.uppercase())
            if (src == tgt) return Availability.PairUnsupported(src.uppercase(), tgt.uppercase())
            return if (isDownloaded(src) && isDownloaded(tgt)) Availability.Ready else Availability.NeedsDownload
        }

        private suspend fun isDownloaded(language: String): Boolean {
            if (language == TranslateLanguage.ENGLISH) return true
            val models = runCatching { RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java).awaitTask() }.getOrNull() ?: return false
            return models.any { it.language == language }
        }

        /** Settings: remove every downloaded translation pack. */
        suspend fun deleteAllModels() {
            val manager = RemoteModelManager.getInstance()
            val models = runCatching { manager.getDownloadedModels(TranslateRemoteModel::class.java).awaitTask() }.getOrNull() ?: return
            models.filter { it.language != TranslateLanguage.ENGLISH }.forEach { runCatching { manager.deleteDownloadedModel(it).awaitTask() } }
        }
    }

    /** iOS: `activate(source:target:downloadApproved:)`. */
    fun activate(source: String?, target: String, downloadApproved: Boolean = false) {
        val src = mlKitCode(source)
        val tgt = mlKitCode(target)
        if (src == null || tgt == null) { deactivate(); return }
        deactivate()
        isEnabled = true
        targetCode = (SubtitleTargetLanguage.canonicalCode(target) ?: target).uppercase()
        val client = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(src).setTargetLanguage(tgt).build())
        translator = client
        queue = Channel(capacity = MAX_QUEUED, onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST)
        val jobs = queue
        worker = scope.launch {
            ready = isDownloaded(src) && isDownloaded(tgt)
            if (!ready) {
                if (!downloadApproved) { needsLanguageDownload = true; return@launch }
                if (!downloadModels(client)) return@launch
            }
            for (job in jobs) {
                val translated = runCatching { client.translate(job.text).awaitTask() }
                    .onFailure { statusMessage = it.localizedMessage }
                    .getOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                store(job.key, translated)
                onTranslated?.invoke(job.id, translated)
            }
        }
    }

    private suspend fun downloadModels(client: Translator): Boolean {
        isDownloadingLanguagePack = true
        needsLanguageDownload = false
        val ok = runCatching { client.downloadModelIfNeeded(DownloadConditions.Builder().build()).awaitTask() }
            .onFailure { statusMessage = it.localizedMessage ?: "Language pack download failed" }.isSuccess
        isDownloadingLanguagePack = false
        ready = ok
        if (!ok) needsLanguageDownload = true
        return ok
    }

    /** iOS: `approveDownload()` — the user tapped "Download … language pack". */
    fun approveDownload() {
        val client = translator ?: return
        if (!isEnabled || isDownloadingLanguagePack) return
        val jobs = queue
        worker?.cancel()
        worker = scope.launch {
            if (!downloadModels(client)) return@launch
            for (job in jobs) {
                val translated = runCatching { client.translate(job.text).awaitTask() }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                store(job.key, translated)
                onTranslated?.invoke(job.id, translated)
            }
        }
    }

    fun deactivate() {
        worker?.cancel(); worker = null
        queue.close()
        translator?.close(); translator = null
        cache.clear()
        isEnabled = false
        needsLanguageDownload = false
        isDownloadingLanguagePack = false
        statusMessage = null
        targetCode = null
        ready = false
    }

    /** iOS: `requestTranslation(id:text:)` — cache hits answer at once. */
    fun requestTranslation(id: Long, text: String) {
        if (!isEnabled) return
        val key = text.trim().lowercase()
        if (key.isEmpty()) return
        cache[key]?.let { hit -> scope.launch { onTranslated?.invoke(id, hit) }; return }
        // Queued even while the pack is missing: an approved download then translates the backlog.
        queue.trySend(Request(id, key, text))
    }

    private fun store(key: String, value: String) {
        if (cache.size >= MAX_CACHE) cache.clear()
        cache[key] = value
    }
}

/** `Task` → suspend (no play-services coroutines dependency needed). */
suspend fun <T> Task<T>.awaitTask(): T = suspendCancellableCoroutine { cont ->
    addOnSuccessListener { cont.resume(it) }
    addOnFailureListener { cont.resumeWithException(it) }
    addOnCanceledListener { cont.cancel() }
}
