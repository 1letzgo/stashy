package de.letzgo.stashy.ui.player.ai

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.max
import kotlin.math.min

/**
 * Pure caption logic of the AI subtitles (iOS: the cue / timing parts of
 * `SceneLiveTranscriptionController` and `SceneTranscodeAudioPrefetcher`). No Android types, so
 * everything here is unit-tested on the JVM.
 */

/** One recognised word on the media timeline (iOS `SceneTranscriptWord`, whitespace dropped). */
data class TranscriptWord(val text: String, val start: Double, val end: Double)

/** Parses a Vosk result (`{"result":[{"word","start","end","conf"}…],"text":…}`). */
object VoskResult {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /** Words with times in recognizer seconds; empty for silence / a result without word times. */
    fun words(raw: String?): List<TranscriptWord> {
        if (raw.isNullOrBlank()) return emptyList()
        val root = runCatching { json.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return emptyList()
        val list = root["result"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val word = o["word"]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            // Kaldi marks unknown words like this; never show them.
            if (word == "[unk]" || word == "<unk>") return@mapNotNull null
            val start = o["start"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
            val end = o["end"]?.jsonPrimitive?.doubleOrNull ?: start
            TranscriptWord(word, start, max(start, end))
        }
    }
}

/**
 * iOS: `feedTimeline` + `globalTime(forAnalyzerSeconds:)`. The recognizer sees one continuous
 * stream while the chunked feed jumps in media time; every chunk anchors where its audio
 * continues on the media timeline.
 */
class FeedTimeline(private val sessionStart: Double) {
    private data class Segment(val analyzerStart: Double, val globalStart: Double)
    private val segments = ArrayList<Segment>()

    fun anchor(analyzerSeconds: Double, globalStart: Double) {
        segments += Segment(analyzerSeconds, globalStart)
        if (segments.size > 60) segments.subList(0, segments.size - 60).clear()
    }

    fun global(analyzerSeconds: Double): Double {
        val seg = segments.lastOrNull { analyzerSeconds >= it.analyzerStart } ?: segments.firstOrNull()
            ?: return sessionStart + analyzerSeconds
        return seg.globalStart + (analyzerSeconds - seg.analyzerStart)
    }
}

/**
 * Splits a final recognition result into caption sentences. SpeechAnalyzer hands iOS one phrase
 * per final with punctuation; Vosk finals are unpunctuated utterances that can run long, so they
 * are cut at pauses ([GAP_SECONDS], iOS `sentenceGapFlushSeconds`), at
 * [MAX_CHARS] (iOS `maxPendingSentenceCharacters`) and at [MAX_SECONDS]
 * (iOS `maxPendingSentenceSeconds`).
 */
object CaptionSegmenter {
    const val GAP_SECONDS = 0.85
    const val MAX_CHARS = 110
    const val MAX_SECONDS = 7.0
    /** Words that bunch up behind a cut this short would leave a one-word orphan cue. */
    private const val MIN_TAIL_WORDS = 2

    fun segment(words: List<TranscriptWord>): List<List<TranscriptWord>> {
        val out = ArrayList<List<TranscriptWord>>()
        var current = ArrayList<TranscriptWord>()
        var chars = 0
        for (w in words) {
            if (current.isNotEmpty()) {
                val gap = w.start - current.last().end
                val span = w.end - current.first().start
                val tooLong = chars + 1 + w.text.length > MAX_CHARS || span > MAX_SECONDS
                if (gap >= GAP_SECONDS || tooLong) {
                    out += current; current = ArrayList(); chars = 0
                }
            }
            current += w
            chars += (if (chars > 0) 1 else 0) + w.text.length
            if (endsSentence(w.text)) { out += current; current = ArrayList(); chars = 0 }
        }
        if (current.isNotEmpty()) {
            // Fold a one-word tail into the previous cut when that one still has room.
            val prev = out.lastOrNull()
            if (prev != null && current.size < MIN_TAIL_WORDS && current.first().start - prev.last().end < GAP_SECONDS &&
                text(prev + current).length <= MAX_CHARS && !endsSentence(prev.last().text)
            ) out[out.lastIndex] = prev + current else out += current
        }
        return out
    }

    /** Words joined for display; Vosk is lower-case, so the line starts capitalised. */
    fun text(words: List<TranscriptWord>, joiner: String = " "): String =
        words.joinToString(joiner) { it.text }.trim().replaceFirstChar { it.uppercaseChar() }

    /** iOS: `endsSentence`. */
    fun endsSentence(text: String): Boolean {
        var t = text.trim()
        while (t.isNotEmpty() && t.last() in "'\"»」)]}") t = t.dropLast(1)
        return t.isNotEmpty() && t.last() in ".!?…。！？"
    }
}

/** iOS: `SubtitleCue` of the live channel (with its async translation). */
data class LiveCue(val id: Long, val start: Double, val end: Double, val text: String, val translated: String? = null) {
    val displayText: String get() = translated ?: text
}

/**
 * iOS: `subtitleCues` + `flushPendingSentence` + `captionText(at:)` of
 * `SceneLiveTranscriptionController` for the lookahead feed: cues are timed like SRT, shown
 * exactly on their own timestamps, and selection only moves forward while the playhead does.
 */
class LiveCaptionTimeline {
    companion object {
        const val MAX_CUES = 40
        const val MAX_CAPTION_CHARS = 160
    }

    private val list = ArrayList<LiveCue>()
    val cues: List<LiveCue> get() = list
    private var nextId = 1L
    private var shownStart = Double.NEGATIVE_INFINITY
    private var shownEnd = Double.NEGATIVE_INFINITY
    private var shownTime = Double.NEGATIVE_INFINITY

    fun reset() {
        list.clear()
        shownStart = Double.NEGATIVE_INFINITY; shownEnd = Double.NEGATIVE_INFINITY; shownTime = Double.NEGATIVE_INFINITY
    }

    /**
     * iOS: `flushPendingSentence(force: true)` — anchored at the first word, held for reading time,
     * the previous cue is cut where this one starts. [now] is the playhead (null when unknown).
     */
    fun addSentence(words: List<TranscriptWord>, now: Double?, joiner: String = " "): LiveCue? {
        if (words.isEmpty()) return null
        val text = clip(CaptionSegmenter.text(words, joiner))
        if (text.isEmpty()) return null
        val start = words.first().start
        val readingHold = max(1.6, text.length * 0.05)
        var end = max(words.last().end + 0.55, start + readingHold)
        if (now != null) end = max(end, now + readingHold)
        list.lastOrNull()?.let { prev ->
            if (prev.end > start) list[list.lastIndex] = prev.copy(end = max(prev.start + 0.35, start - 0.05))
        }
        val cue = LiveCue(nextId++, start, end, text)
        list += cue
        if (list.size > MAX_CUES) list.subList(0, list.size - MAX_CUES).clear()
        return cue
    }

    fun applyTranslation(id: Long, text: String): Boolean {
        val i = list.indexOfFirst { it.id == id }
        val trimmed = clip(text)
        if (i < 0 || trimmed.isEmpty()) return false
        list[i] = list[i].copy(translated = trimmed)
        return true
    }

    /** iOS: `captionText(at:)` (lookahead branch) — "" between cues. */
    fun textAt(time: Double): String {
        if (time + 0.5 < shownTime) { shownStart = Double.NEGATIVE_INFINITY; shownEnd = Double.NEGATIVE_INFINITY }
        shownTime = time
        val floor = if (time < shownEnd) shownStart else Double.NEGATIVE_INFINITY
        var best: LiveCue? = null
        for (cue in list) {
            if (time >= cue.start && time < cue.end && cue.start >= floor && cue.start > (best?.start ?: Double.NEGATIVE_INFINITY)) best = cue
        }
        best ?: return ""
        shownStart = best.start; shownEnd = best.end
        return best.displayText
    }

    /**
     * iOS: the coverage test of `handleSeek(to:)` — the fed range plus the oldest kept cue still
     * cover [time], so the running feed can stay.
     */
    fun covers(time: Double, feedStart: Double, frontier: Double, restartLag: Double = 4.0): Boolean {
        val inside = time >= feedStart - 1 && time <= frontier + restartLag
        val reachesBack = list.firstOrNull()?.let { it.start <= time } ?: true
        return inside && reachesBack
    }

    private fun clip(text: String): String {
        val plain = text.replace('\n', ' ').trim()
        return if (plain.length <= MAX_CAPTION_CHARS) plain else plain.take(MAX_CAPTION_CHARS).trim()
    }
}

/** iOS: `SceneLiveTranscriptionController.nextFeedStep` — throttles the feed against the playhead. */
sealed class FeedStep {
    data object Feed : FeedStep()
    data class Wait(val millis: Long) : FeedStep()
    data object Restart : FeedStep()
}

object FeedScheduler {
    const val PRE_ROLL_SECONDS = 2.0
    /** ~1 minute ahead is plenty; more only costs server transcode and slows seek recovery. */
    const val LEAD_BUFFER_SECONDS = 58.0
    /** Safety net when the playhead outruns the feed without a detectable jump. */
    const val BEHIND_RESTART_SECONDS = 12.0
    /** A playhead jump larger than this is a seek. */
    const val SEEK_DETECTION_SECONDS = 1.5
    const val SEEK_RESTART_LAG_SECONDS = 4.0
    /** Recognised lead at which the lookahead buffer counts as built. */
    const val READY_LOOKAHEAD_SECONDS = 20.0

    fun next(playback: Double, fedFrontier: Double, isPlaying: Boolean): FeedStep {
        val pos = max(0.0, playback)
        if (pos - fedFrontier > BEHIND_RESTART_SECONDS) return FeedStep.Restart
        val lead = fedFrontier - pos
        if (lead > PRE_ROLL_SECONDS + LEAD_BUFFER_SECONDS) return FeedStep.Wait(if (isPlaying) 120 else 300)
        return FeedStep.Feed
    }

    /** iOS: `updatePrepProgress` — 0…1 build-up of the lookahead buffer. */
    fun prepProgress(playback: Double, frontier: Double, duration: Double?): Double {
        val lead = max(0.0, frontier - playback)
        val remaining = duration?.let { max(0.0, it - playback) } ?: Double.MAX_VALUE
        val target = min(READY_LOOKAHEAD_SECONDS, max(1.0, remaining))
        return min(1.0, lead / target)
    }
}

/**
 * iOS: the chunk loop state of `SceneTranscodeAudioPrefetcher.run` — `stream.mp4?start=` is a
 * non-seekable fragmented MP4, so each chunk is a byte budget sized from the measured bitrate to
 * ~45 s of media, requested 0.75 s early (overlap dropped on decode) with a short silence fed at
 * the seam.
 */
class ChunkPlanner(startSeconds: Double, mediaDuration: Double?) {
    companion object {
        const val FIRST_CHUNK_BYTE_BUDGET = 1_200_000
        const val MIN_CHUNK_BYTE_BUDGET = 1_500_000
        const val MAX_CHUNK_BYTE_BUDGET = 24_000_000
        const val TARGET_CHUNK_SECONDS = 45.0
        const val END_OF_MEDIA_SLACK = 2.0
        const val MAX_CONSECUTIVE_FAILURES = 4
        const val OVERLAP_SECONDS = 0.75
        const val SILENCE_SECONDS = 0.3
        /** 240p keeps the extra server transcode cheap; only the audio track is used. */
        const val RESOLUTION = "LOW"
    }

    private val duration = mediaDuration?.takeIf { it > 0 }
    var frontier = max(0.0, startSeconds); private set
    var budget = FIRST_CHUNK_BYTE_BUDGET; private set
    var isFirstChunk = true; private set
    var failures = 0; private set
    private var bytesPerSecond: Double? = null

    val isComplete: Boolean get() = duration != null && frontier >= duration - END_OF_MEDIA_SLACK
    val requestStart: Double get() = if (isFirstChunk) frontier else max(0.0, frontier - OVERLAP_SECONDS)
    /** Decoded audio ending before this is the requested overlap. */
    val skipBefore: Double? get() = if (isFirstChunk) null else frontier
    val prependsSilence: Boolean get() = !isFirstChunk

    /** Returns false (counted as a failure) when the chunk added less than 0.25 s. */
    fun chunkDecoded(mediaEnd: Double, downloadedBytes: Int, decodedSeconds: Double): Boolean {
        if (mediaEnd - frontier < 0.25) return false
        failures = 0
        frontier = mediaEnd
        isFirstChunk = false
        val measured = downloadedBytes / max(0.25, decodedSeconds)
        val rate = bytesPerSecond?.let { it * 0.5 + measured * 0.5 } ?: measured
        bytesPerSecond = rate
        budget = min(MAX_CHUNK_BYTE_BUDGET, max(MIN_CHUNK_BYTE_BUDGET, (rate * TARGET_CHUNK_SECONDS * 1.3).toInt()))
        return true
    }

    /** Counts a failure; true when the session should give up. */
    fun chunkFailed(): Boolean { failures += 1; return failures >= MAX_CONSECUTIVE_FAILURES }

    /** iOS: `retryDelay(after:)` — 0.4 s doubling, capped at 4 s. */
    val retryDelayMillis: Long get() = (min(4.0, Math.pow(2.0, (failures - 1).toDouble()) * 0.4) * 1000).toLong()
}

/**
 * Interleaved 16-bit PCM of any rate / channel count → 16 kHz mono for the recognizer (iOS:
 * `SceneTranscriptionAudioConverter`). Linear interpolation, stateful across buffers so chunk
 * boundaries don't click.
 */
class PcmResampler(private val sourceRate: Int, private val channels: Int, private val targetRate: Int = 16_000) {
    private val step = sourceRate.toDouble() / targetRate
    private var position = 0.0       // next output position, in source frames relative to `previous`
    private var previous = 0f
    private var hasPrevious = false

    fun process(input: ShortArray, length: Int = input.size): ShortArray {
        val frames = length / max(1, channels)
        if (frames == 0) return ShortArray(0)
        val mono = FloatArray(frames + 1)
        // Index 0 is the last frame of the previous buffer; source frame k is mono[k + 1].
        mono[0] = if (hasPrevious) previous else 0f
        for (f in 0 until frames) {
            var sum = 0f
            for (c in 0 until channels) sum += input[f * channels + c]
            mono[f + 1] = sum / channels
        }
        if (!hasPrevious) { mono[0] = mono[1]; position = 1.0 }
        val out = ShortArray(((frames - position) / step).toInt().coerceAtLeast(0) + 2)
        var n = 0
        // Interpolates mono[i] … mono[i + 1]; stops before the last frame, which carries over.
        while (position < frames && n < out.size) {
            val i = position.toInt()
            val frac = (position - i).toFloat()
            val a = mono[i]
            val b = mono[i + 1]
            out[n++] = (a + (b - a) * frac).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            position += step
        }
        previous = mono[frames]
        hasPrevious = true
        position -= frames
        return if (n == out.size) out else out.copyOf(n)
    }

    /** [seconds] of 16 kHz silence (iOS `makeSilence`). */
    fun silence(seconds: Double): ShortArray = ShortArray((seconds * targetRate).toInt().coerceAtLeast(1))
}
