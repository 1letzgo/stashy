package de.letzgo.stashy.ui.player.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sin

class AiSubtitlesLogicTest {
    private fun w(text: String, start: Double, end: Double) = TranscriptWord(text, start, end)

    // MARK: Vosk result parsing

    @Test fun parsesVoskWordsAndDropsUnknown() {
        val json = """{"result":[{"conf":1.0,"end":1.02,"start":0.6,"word":"hello"},{"conf":0.4,"end":1.4,"start":1.1,"word":"[unk]"},{"conf":0.9,"end":1.9,"start":1.5,"word":"world"}],"text":"hello world"}"""
        val words = VoskResult.words(json)
        assertEquals(listOf("hello", "world"), words.map { it.text })
        assertEquals(0.6, words[0].start, 1e-9)
        assertEquals(1.9, words[1].end, 1e-9)
    }

    @Test fun emptyOrTextOnlyResultHasNoWords() {
        assertTrue(VoskResult.words("""{"text":""}""").isEmpty())
        assertTrue(VoskResult.words("""{"text":"no timings"}""").isEmpty())
        assertTrue(VoskResult.words("garbage").isEmpty())
        assertTrue(VoskResult.words(null).isEmpty())
    }

    // MARK: Feed timeline

    @Test fun feedTimelineMapsChunksOntoMediaTime() {
        val t = FeedTimeline(sessionStart = 100.0)
        assertEquals(105.0, t.global(5.0), 1e-9)            // before any anchor: session start
        t.anchor(0.0, 100.0)
        t.anchor(45.3, 145.0)                               // 0.3 s seam silence before chunk 2
        assertEquals(110.0, t.global(10.0), 1e-9)
        assertEquals(146.0, t.global(46.3), 1e-9)
    }

    // MARK: Segmentation

    @Test fun segmentsAtPausesAndSentenceEnds() {
        val words = listOf(w("hello", 0.0, 0.4), w("there", 0.5, 0.9), w("how", 2.0, 2.2), w("are", 2.3, 2.4), w("you?", 2.5, 2.8), w("fine", 2.9, 3.2), w("thanks", 3.3, 3.6))
        val parts = CaptionSegmenter.segment(words).map { CaptionSegmenter.text(it) }
        assertEquals(listOf("Hello there", "How are you?", "Fine thanks"), parts)
    }

    @Test fun segmentsLongRunsByLengthAndDuration() {
        val words = (0 until 60).map { w("word$it", it * 0.3, it * 0.3 + 0.25) }
        val parts = CaptionSegmenter.segment(words)
        assertTrue(parts.size > 1)
        for (p in parts) {
            assertTrue(CaptionSegmenter.text(p).length <= CaptionSegmenter.MAX_CHARS)
            assertTrue(p.last().end - p.first().start <= CaptionSegmenter.MAX_SECONDS + 0.3)
        }
        assertEquals(60, parts.sumOf { it.size })
    }

    @Test fun oneWordTailIsFoldedIntoThePreviousCut() {
        val words = (0 until 22).map { w("abcd", it * 0.3, it * 0.3 + 0.2) }   // 22 × 5 chars → cut at 110, one word left
        val parts = CaptionSegmenter.segment(words)
        assertTrue(parts.last().size >= 2)
    }

    // MARK: Cue timeline

    @Test fun cueTimingFollowsTheIosReadingHold() {
        val tl = LiveCaptionTimeline()
        val cue = tl.addSentence(listOf(w("hi", 10.0, 10.3)), now = 0.0)!!
        assertEquals(10.0, cue.start, 1e-9)
        assertEquals(11.6, cue.end, 1e-9)                    // max(0.3+0.55, 1.6 reading hold)
        val second = tl.addSentence(listOf(w("next", 11.0, 11.4), w("line", 11.5, 11.9)), now = 0.0)!!
        assertEquals(10.95, tl.cues[0].end, 1e-9)            // previous cut 0.05 s before the next
        assertEquals("Next line", second.text)
    }

    @Test fun textAtShowsCuesOnTheirTimestampsAndBlanksBetween() {
        val tl = LiveCaptionTimeline()
        tl.addSentence(listOf(w("one", 1.0, 1.5)), now = 0.0)
        tl.addSentence(listOf(w("two", 5.0, 5.5)), now = 0.0)
        assertEquals("", tl.textAt(0.5))
        assertEquals("One", tl.textAt(1.2))
        assertEquals("", tl.textAt(3.5))
        assertEquals("Two", tl.textAt(5.1))
        // Seek backwards re-selects.
        assertEquals("One", tl.textAt(1.1))
    }

    @Test fun selectionNeverFlipsBackToAnOlderOverlappingCue() {
        val tl = LiveCaptionTimeline()
        tl.addSentence(listOf(w("first", 1.0, 1.2)), now = 3.0)   // end extended to now + hold = 4.6
        tl.addSentence(listOf(w("second", 2.0, 2.2)), now = null)  // cuts first to 1.95
        assertEquals("Second", tl.textAt(2.1))
        assertEquals("Second", tl.textAt(2.3))
    }

    @Test fun translationReplacesDisplayedText() {
        val tl = LiveCaptionTimeline()
        val cue = tl.addSentence(listOf(w("hallo", 1.0, 1.5), w("welt", 1.6, 2.0)), now = null)!!
        assertTrue(tl.applyTranslation(cue.id, "Hello world"))
        assertEquals("Hello world", tl.textAt(1.5))
        assertFalse(tl.applyTranslation(999, "x"))
    }

    @Test fun keepsOnlyTheNewestCues() {
        val tl = LiveCaptionTimeline()
        repeat(50) { i -> tl.addSentence(listOf(w("w$i", i * 2.0, i * 2.0 + 0.5)), now = null) }
        assertEquals(LiveCaptionTimeline.MAX_CUES, tl.cues.size)
        assertEquals("W49", tl.cues.last().text)
    }

    @Test fun seekCoverage() {
        val tl = LiveCaptionTimeline()
        tl.addSentence(listOf(w("a", 10.0, 10.5)), now = null)
        assertTrue(tl.covers(20.0, feedStart = 8.0, frontier = 60.0))
        assertFalse(tl.covers(70.0, feedStart = 8.0, frontier = 60.0))   // beyond fed range + 4 s
        assertFalse(tl.covers(9.0, feedStart = 8.0, frontier = 60.0))    // before the oldest kept cue
        assertTrue(LiveCaptionTimeline().covers(9.0, feedStart = 8.0, frontier = 60.0))
    }

    // MARK: Feed scheduling

    @Test fun feedSchedulerKeepsAboutAMinuteAhead() {
        assertEquals(FeedStep.Feed, FeedScheduler.next(playback = 10.0, fedFrontier = 40.0, isPlaying = true))
        assertEquals(FeedStep.Wait(120), FeedScheduler.next(10.0, 71.0, true))
        assertEquals(FeedStep.Wait(300), FeedScheduler.next(10.0, 71.0, false))
        assertEquals(FeedStep.Restart, FeedScheduler.next(100.0, 87.0, true))   // > 12 s behind
        assertEquals(0.5, FeedScheduler.prepProgress(10.0, 20.0, null), 1e-9)
        assertEquals(1.0, FeedScheduler.prepProgress(10.0, 12.0, 12.0), 1e-9)   // only 2 s left
    }

    @Test fun chunkPlannerAdaptsBudgetAndOverlap() {
        val p = ChunkPlanner(startSeconds = 30.0, mediaDuration = 600.0)
        assertEquals(ChunkPlanner.FIRST_CHUNK_BYTE_BUDGET, p.budget)
        assertEquals(30.0, p.requestStart, 1e-9)
        assertNull(p.skipBefore)
        assertTrue(p.chunkDecoded(mediaEnd = 63.0, downloadedBytes = 1_200_000, decodedSeconds = 33.0))
        // ~36 kB/s × 45 s × 1.3 ≈ 2.1 MB
        assertEquals((1_200_000 / 33.0 * 45 * 1.3).toInt(), p.budget)
        assertEquals(62.25, p.requestStart, 1e-9)
        assertEquals(63.0, p.skipBefore!!, 1e-9)
        assertTrue(p.prependsSilence)
        assertFalse(p.chunkDecoded(63.1, 1000, 0.1))         // < 0.25 s gained
        assertFalse(p.isComplete)
    }

    @Test fun chunkPlannerGivesUpAfterFourFailuresWithBackoff() {
        val p = ChunkPlanner(0.0, null)
        assertFalse(p.chunkFailed()); assertEquals(400, p.retryDelayMillis)
        assertFalse(p.chunkFailed()); assertEquals(800, p.retryDelayMillis)
        assertFalse(p.chunkFailed()); assertEquals(1600, p.retryDelayMillis)
        assertTrue(p.chunkFailed())
    }

    @Test fun chunkPlannerCompletesNearTheEnd() {
        val p = ChunkPlanner(0.0, 50.0)
        p.chunkDecoded(48.5, 1_000_000, 48.5)
        assertTrue(p.isComplete)
        val budget = ChunkPlanner(0.0, 1000.0).apply { chunkDecoded(1.0, 50_000_000, 1.0) }.budget
        assertEquals(ChunkPlanner.MAX_CHUNK_BYTE_BUDGET, budget)
    }

    // MARK: Resampling

    @Test fun resamplesStereo48kToMono16kAcrossBuffers() {
        val r = PcmResampler(48_000, 2)
        val seconds = 1.0
        val frames = (48_000 * seconds).toInt()
        val input = ShortArray(frames * 2) { i ->
            val f = i / 2
            (sin(2 * Math.PI * 440 * f / 48_000.0) * 10_000).toInt().toShort()
        }
        // Feed in uneven buffers.
        val out = ArrayList<Short>()
        var offset = 0
        for (size in listOf(2048, 4096, 1234 * 2, 30_000)) {
            val n = minOf(size, input.size - offset)
            out += r.process(input.copyOfRange(offset, offset + n)).toList()
            offset += n
        }
        if (offset < input.size) out += r.process(input.copyOfRange(offset, input.size)).toList()
        assertTrue("got ${out.size}", abs(out.size - 16_000) <= 2)
        // Output follows the 440 Hz sine at the new rate.
        for (k in 100 until 15_900 step 997) {
            val expected = sin(2 * Math.PI * 440 * k / 16_000.0) * 10_000
            assertEquals(expected, out[k].toDouble(), 400.0)
        }
    }

    @Test fun resamplerPassesThrough16kMono() {
        val r = PcmResampler(16_000, 1)
        val a = r.process(shortArrayOf(1, 2, 3, 4))
        val b = r.process(shortArrayOf(5, 6))
        // Same rate: identity with a one-sample carry-over between buffers.
        assertEquals(listOf<Short>(1, 2, 3, 4, 5), (a.toList() + b.toList()))
    }

    // MARK: Languages

    @Test fun sceneLanguageTags() {
        assertEquals("de", SubtitleTargetLanguage.normalizedSceneLanguageTag("German"))
        assertEquals("zh-CN", SubtitleTargetLanguage.normalizedSceneLanguageTag("zh"))
        assertEquals("yue-CN", SubtitleTargetLanguage.normalizedSceneLanguageTag("Cantonese"))
        assertEquals("en-gb", SubtitleTargetLanguage.normalizedSceneLanguageTag("en_GB"))
        assertNull(SubtitleTargetLanguage.normalizedSceneLanguageTag("qqq"))
        assertEquals("de", SubtitleTargetLanguage.canonicalCode("deu"))
        assertTrue(SubtitleTargetLanguage.sameLanguage("de-DE", "de"))
        assertEquals("de", SubtitleTargetLanguage.loadFrom("de-AT", deviceDefault = "en"))
        assertEquals("en", SubtitleTargetLanguage.loadFrom("xx", deviceDefault = "en"))
        assertEquals("fr", SubtitleTargetLanguage.loadFrom(null, deviceDefault = "fr"))
    }

    @Test fun teleprompterModeRawValues() {
        assertEquals(SceneTeleprompterMode.English, SceneTeleprompterMode.fromRaw("sceneLanguage"))
        assertEquals(SceneTeleprompterMode.UserLanguage, SceneTeleprompterMode.fromRaw("userLanguage"))
        assertEquals(SceneTeleprompterMode.Off, SceneTeleprompterMode.fromRaw(null))
        assertEquals("en", SceneTeleprompterMode.English.captionTargetCode("de"))
        assertEquals("de", SceneTeleprompterMode.UserLanguage.captionTargetCode("de"))
    }

    @Test fun audioTrackLanguage() {
        assertEquals("de", AudioTrackLanguage.tag("ger", null))
        assertEquals("en", AudioTrackLanguage.tag("eng", null))
        assertEquals("fr", AudioTrackLanguage.tag("und", "French · AAC · 2ch"))
        assertNull(AudioTrackLanguage.tag("und", "AAC · 2ch"))
    }

    @Test fun speechModelCatalogMatching() {
        assertEquals("vosk-model-small-en-us-0.15", SpeechModelCatalog.entry("en")?.modelName)
        assertEquals("vosk-model-small-en-gb-0.15", SpeechModelCatalog.entry("en-GB")?.modelName)
        assertEquals("vosk-model-small-en-us-0.15", SpeechModelCatalog.entry("en-AU")?.modelName)
        assertEquals("vosk-model-small-cn-0.22", SpeechModelCatalog.entry("zh-CN")?.modelName)
        assertNull(SpeechModelCatalog.entry("yue-CN"))
        assertNull(SpeechModelCatalog.entry("hu"))                // no fallback to another language
        assertEquals("de", SpeechModelCatalog.matchingPickerId("de-DE", listOf("de", "en")))
    }
}
