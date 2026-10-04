package de.letzgo.stashy.ui.player.ai

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.ui.player.StashPlayer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Recognizer
import kotlin.math.abs
import kotlin.math.max

/**
 * iOS: `SceneLiveTranscriptionController` — AI captions for the scene player.
 *
 * iOS feeds SpeechAnalyzer from audio fetched ahead of the playhead; Android does the same with
 * Vosk: [TranscodeAudioSource] pulls Stash's 240p transcode in ~45 s chunks up to a minute ahead
 * of the playhead (captions only — playback never switches source), decodes the audio to 16 kHz
 * mono PCM and feeds one continuous [Recognizer]. Final results become SRT-like cues on the media
 * timeline ([LiveCaptionTimeline]); the playhead clock picks the cue to show. Seeks outside the
 * transcribed range restart the feed there; falling 12 s behind does too.
 */
class LiveTranscriber(private val context: Context) {
    sealed class ModelProbe {
        data object Ready : ModelProbe()
        data class NeedsDownload(val languageName: String, val sizeText: String) : ModelProbe()
        data class Unsupported(val languageName: String) : ModelProbe()
    }

    // MARK: Published state (Compose)

    var mode by mutableStateOf(SceneTeleprompterMode.Off); private set
    var isTeleprompterModeActive by mutableStateOf(false); private set
    var isPreparing by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    var needsSpeechModelDownload by mutableStateOf(false); private set
    /** Name of the speech model being offered / fetched, for the download hint. */
    var downloadingModelLanguage by mutableStateOf<String?>(null); private set
    var downloadingModelSize by mutableStateOf<String?>(null); private set
    /** 0…1 while a speech model downloads, else null. */
    var modelDownloadProgress by mutableStateOf<Double?>(null); private set
    var currentSubtitleText by mutableStateOf(""); private set
    /** iOS `prepProgress` — build-up of the lookahead buffer, null when off. */
    var prepProgress by mutableStateOf<Double?>(null); private set

    /** Shared caption channel (the player's subtitle overlay). */
    var liveCaptionHandler: ((String) -> Unit)? = null
    /** Hands a finished sentence to translation; results come back via [applyTranslation]. */
    var translationRequestHandler: ((Long, String) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var player: StashPlayer? = null
    private var sceneId: String? = null
    private var sceneDuration: Double? = null
    private var entry: SpeechModelCatalog.Entry? = null
    private var clockJob: Job? = null
    private var feedJob: Job? = null
    private var downloadJob: Job? = null
    private var seekRestartJob: Job? = null
    private var generation = 0
    private val timeline = LiveCaptionTimeline()
    private var feedStart = 0.0
    @Volatile private var fedFrontier = 0.0
    private var lastObservedPlayhead: Double? = null
    private var sessionRunning = false

    // MARK: Public API

    /** iOS: `probeSpeechModel(for:)` — never falls back to another language. */
    fun probeSpeechModel(languageTag: String?): ModelProbe {
        val name = SubtitleTargetLanguage.displayName(SubtitleTargetLanguage.languageCode(languageTag.orEmpty()) ?: "?")
        val e = SpeechModelCatalog.entry(languageTag) ?: return ModelProbe.Unsupported(name)
        return if (SpeechModelStore.isInstalled(context, e)) ModelProbe.Ready else ModelProbe.NeedsDownload(e.displayName, e.sizeText)
    }

    /** iOS: `start(mode:aether:sceneID:…)`. The caller has probed the language. */
    fun start(mode: SceneTeleprompterMode, player: StashPlayer, sceneId: String, sceneDuration: Double?, sceneLanguage: String) {
        disable()
        val e = SpeechModelCatalog.entry(sceneLanguage) ?: run { errorMessage = "Speech recognition is not available for this language on this device."; return }
        this.mode = mode
        this.player = player
        this.sceneId = sceneId
        this.sceneDuration = sceneDuration
        this.entry = e
        errorMessage = null
        isTeleprompterModeActive = true
        attachClock(player)
        if (SpeechModelStore.isInstalled(context, e)) runSession()
        else {
            // iOS parks in `ensureSpeechModel` until the user approves the download.
            downloadingModelLanguage = e.displayName
            downloadingModelSize = e.sizeText
            needsSpeechModelDownload = true
        }
    }

    /** iOS: `approveSpeechModelDownload()` — installs, then starts captions. */
    fun approveSpeechModelDownload() {
        val e = entry ?: return
        needsSpeechModelDownload = false
        errorMessage = null
        downloadingModelLanguage = e.displayName
        downloadJob?.cancel()
        downloadJob = scope.launch {
            modelDownloadProgress = 0.0
            try {
                SpeechModelStore.download(context, e) { p -> scope.launch { if (modelDownloadProgress != null) modelDownloadProgress = p } }
                modelDownloadProgress = null
                if (isTeleprompterModeActive) runSession()
            } catch (c: CancellationException) {
                modelDownloadProgress = null
                throw c
            } catch (t: Throwable) {
                modelDownloadProgress = null
                needsSpeechModelDownload = true
                errorMessage = t.localizedMessage ?: "Speech model download failed"
            }
        }
    }

    /** iOS: `disable()`. A running model download keeps going (it is the user's explicit request). */
    fun disable() {
        generation++
        feedJob?.cancel(); feedJob = null
        seekRestartJob?.cancel(); seekRestartJob = null
        clockJob?.cancel(); clockJob = null
        sessionRunning = false
        isTeleprompterModeActive = false
        isPreparing = false
        needsSpeechModelDownload = false
        prepProgress = null
        mode = SceneTeleprompterMode.Off
        timeline.reset()
        lastObservedPlayhead = null
        if (currentSubtitleText.isNotEmpty()) { currentSubtitleText = ""; liveCaptionHandler?.invoke("") }
        player = null
    }

    fun clearError() { errorMessage = null }

    /** iOS: `applyTranslation(cueID:text:)` — patches the cue and re-renders if on screen. */
    fun applyTranslation(cueId: Long, text: String) {
        if (timeline.applyTranslation(cueId, text)) player?.let { updateDisplayed(it.currentTime) }
    }

    fun release() {
        disable()
        downloadJob?.cancel()
    }

    // MARK: Clock

    private fun attachClock(p: StashPlayer) {
        clockJob?.cancel()
        clockJob = scope.launch {
            while (isActive) {
                handlePlayheadTick(p.currentTime)
                delay(100)
            }
        }
    }

    private fun handlePlayheadTick(time: Double) {
        val previous = lastObservedPlayhead
        lastObservedPlayhead = time
        if (previous != null && abs(time - previous) > FeedScheduler.SEEK_DETECTION_SECONDS) handleSeek(time)
        updateDisplayed(time)
        if (sessionRunning) {
            val progress = FeedScheduler.prepProgress(time, timeline.cues.lastOrNull()?.end ?: feedStart, sceneDuration)
            if (prepProgress == null || abs((prepProgress ?: 0.0) - progress) >= 0.02) prepProgress = progress
        }
    }

    private fun updateDisplayed(time: Double) {
        if (!isTeleprompterModeActive) return
        val text = timeline.textAt(time)
        if (text != currentSubtitleText) {
            currentSubtitleText = text
            liveCaptionHandler?.invoke(text)
        }
    }

    /** iOS: `handleSeek(to:)` — restart the feed where the playhead landed (debounced 0.4 s). */
    private fun handleSeek(time: Double) {
        if (!isTeleprompterModeActive || !sessionRunning) return
        if (timeline.covers(time, feedStart, fedFrontier, FeedScheduler.SEEK_RESTART_LAG_SECONDS)) return
        if (currentSubtitleText.isNotEmpty()) { currentSubtitleText = ""; liveCaptionHandler?.invoke("") }
        prepProgress = 0.0
        seekRestartJob?.cancel()
        seekRestartJob = scope.launch {
            delay(400)
            if (isTeleprompterModeActive) runSession()
        }
    }

    // MARK: Session

    private fun runSession() {
        val p = player ?: return
        val id = sceneId ?: return
        val e = entry ?: return
        val gen = ++generation
        feedJob?.cancel()
        timeline.reset()
        feedStart = max(0.0, p.currentTime - FeedScheduler.PRE_ROLL_SECONDS)
        fedFrontier = feedStart
        sessionRunning = true
        isPreparing = true
        prepProgress = 0.0
        val joiner = if (SubtitleTargetLanguage.languageCode(e.code) in SpeechModelCatalog.unspacedLanguages) "" else " "
        feedJob = scope.launch {
            var recognizer: Recognizer? = null
            try {
                val model = SpeechModelStore.load(context, e)
                recognizer = withContext(Dispatchers.IO) {
                    runCatching { LibVosk.setLogLevel(LogLevel.WARNINGS) }
                    Recognizer(model, SAMPLE_RATE.toFloat()).apply { setWords(true) }
                }
                feedLoop(gen, recognizer, id, joiner)
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                if (gen == generation) {
                    android.util.Log.w("LiveTranscriber", "session failed", t)
                    errorMessage = when (t) {
                        is UnsatisfiedLinkError -> "Speech recognition is not available on this device."
                        is AudioUnavailable -> "No readable audio from the server transcode. Try again later."
                        else -> t.localizedMessage ?: "Live captions stopped."
                    }
                    sessionRunning = false
                    isPreparing = false
                }
            } finally {
                recognizer?.let { r -> withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) { runCatching { r.close() } } }
            }
        }
    }

    private class AudioUnavailable : Exception()

    private suspend fun feedLoop(gen: Int, recognizer: Recognizer, sceneId: String, joiner: String) {
        val planner = ChunkPlanner(feedStart, sceneDuration)
        val feedTimeline = FeedTimeline(feedStart)
        var analyzerSeconds = 0.0
        var mediaSinceCheck = 0.0

        suspend fun step(frontier: Double): Boolean {
            while (true) {
                if (gen != generation) throw CancellationException()
                val p = player ?: throw CancellationException()
                when (val s = FeedScheduler.next(p.currentTime, frontier, p.isPlaying)) {
                    FeedStep.Feed -> return true
                    is FeedStep.Wait -> delay(s.millis)
                    FeedStep.Restart -> { scope.launch { if (gen == generation && isTeleprompterModeActive) runSession() }; throw CancellationException() }
                }
            }
        }

        suspend fun feed(pcm: ShortArray) {
            // Small slices keep each JNI call short; a `true` marks an utterance end.
            var offset = 0
            while (offset < pcm.size) {
                val n = minOf(SLICE, pcm.size - offset)
                val slice = if (offset == 0 && n == pcm.size) pcm else pcm.copyOfRange(offset, offset + n)
                val endOfUtterance = recognizer.acceptWaveForm(slice, n)
                analyzerSeconds += n.toDouble() / SAMPLE_RATE
                if (endOfUtterance) deliver(gen, VoskResult.words(recognizer.result), feedTimeline, joiner)
                offset += n
            }
        }

        while (true) {
            step(planner.frontier)
            if (planner.isComplete) {
                deliver(gen, VoskResult.words(withContext(Dispatchers.Default) { recognizer.finalResult }), feedTimeline, joiner)
                withContext(Dispatchers.Main) { isPreparing = false }
                return
            }
            val requestStart = planner.requestStart
            val url = TranscodeAudioSource.chunkURL(sceneId, requestStart) ?: throw AudioUnavailable()
            val file = TranscodeAudioSource.tempFile(context.cacheDir)
            var chunk: TranscodeAudioSource.DecodedChunk? = null
            var bytes = 0
            try {
                bytes = TranscodeAudioSource.download(url, file, planner.budget)
                if (bytes > 0) {
                    val silence = planner.prependsSilence
                    chunk = TranscodeAudioSource.decode(
                        file, requestStart, planner.skipBefore,
                        onAnchor = { mediaStart ->
                            if (silence) feed(ShortArray((ChunkPlanner.SILENCE_SECONDS * SAMPLE_RATE).toInt()))
                            feedTimeline.anchor(analyzerSeconds, mediaStart)
                        },
                        onPcm = { pcm, mediaEnd ->
                            feed(pcm)
                            val before = fedFrontier
                            fedFrontier = mediaEnd
                            mediaSinceCheck += max(0.0, mediaEnd - before)
                            if (mediaSinceCheck >= 3.0) { mediaSinceCheck = 0.0; step(mediaEnd) }
                        },
                    )
                }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                android.util.Log.w("LiveTranscriber", "chunk failed at $requestStart", t)
                chunk = null
            } finally {
                file.delete()
            }
            val decoded = chunk
            if (decoded == null || !planner.chunkDecoded(decoded.mediaEnd, bytes, decoded.decodedSeconds)) {
                if (planner.chunkFailed()) throw AudioUnavailable()
                delay(planner.retryDelayMillis)
                continue
            }
            fedFrontier = planner.frontier
            withContext(Dispatchers.Main) { if (gen == generation) isPreparing = false }
        }
    }

    /** Final words → caption sentences on the main thread (iOS `applyFinal`). */
    private suspend fun deliver(gen: Int, words: List<TranscriptWord>, feedTimeline: FeedTimeline, joiner: String) {
        if (words.isEmpty()) return
        val global = words.map { TranscriptWord(it.text, feedTimeline.global(it.start), feedTimeline.global(it.end)) }
        withContext(Dispatchers.Main) {
            if (gen != generation) return@withContext
            val now = player?.currentTime
            for (sentence in CaptionSegmenter.segment(global)) {
                val cue = timeline.addSentence(sentence, now, joiner) ?: continue
                translationRequestHandler?.invoke(cue.id, cue.text)
            }
            now?.let { updateDisplayed(it) }
        }
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        private const val SLICE = 4_000   // 0.25 s
    }
}
