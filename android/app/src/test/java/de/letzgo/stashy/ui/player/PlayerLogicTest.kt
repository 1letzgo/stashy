package de.letzgo.stashy.ui.player

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WebVttTest {
    @Test fun parsesCuesWithHeaderIdsTagsAndSettings() {
        val vtt = "﻿WEBVTT\nKind: captions\n\nNOTE a comment\nstill note\n\n1\n00:00:01.000 --> 00:00:03.500 align:start\n<i>Hello</i> &amp; welcome\nsecond line\n\n00:05.000 --> 00:06,250\nShort form\n"
        val cues = WebVtt.parseCues(vtt)
        assertEquals(2, cues.size)
        assertEquals(1.0, cues[0].start, 1e-9)
        assertEquals(3.5, cues[0].end, 1e-9)
        assertEquals("Hello & welcome\nsecond line", cues[0].text)
        assertEquals(5.0, cues[1].start, 1e-9)
        assertEquals(6.25, cues[1].end, 1e-9)
    }

    @Test fun cueTextAtTime() {
        val cues = WebVtt.parseCues("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nA\n\n00:00:03.000 --> 00:00:04.000\nB\n")
        assertEquals("A", WebVtt.cueText(cues, 1.5))
        assertNull(WebVtt.cueText(cues, 2.5))
        assertEquals("B", WebVtt.cueText(cues, 3.0))
        assertNull(WebVtt.cueText(cues, 4.0))
    }

    @Test fun crlfAndSortedOutput() {
        val cues = WebVtt.parseCues("WEBVTT\r\n\r\n00:00:09.000 --> 00:00:10.000\r\nLate\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nEarly\r\n")
        assertEquals(listOf("Early", "Late"), cues.map { it.text })
    }

    @Test fun parsesStashSpriteVtt() {
        val vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:10.000\nabc_sprite.jpg#xywh=0,0,160,90\n\n00:00:10.000 --> 00:00:20.000\nabc_sprite.jpg#xywh=160,0,160,90\n\n00:00:20.000 --> 00:00:30.000\nabc_sprite.jpg#xywh=0,90,0,90\n"
        val tiles = WebVtt.parseSpriteTiles(vtt)
        assertEquals(2, tiles.size) // zero-width tile dropped
        assertEquals(SpriteTile(10.0, 20.0, 160, 0, 160, 90), tiles[1])
        assertEquals(160, WebVtt.tileAt(tiles, 15.0)?.x)
        assertEquals(0, WebVtt.tileAt(tiles, -3.0)?.x)
        assertEquals(160, WebVtt.tileAt(tiles, 999.0)?.x)
    }

    @Test fun timestamps() {
        assertEquals(3723.5, WebVtt.parseTimestamp("01:02:03.500")!!, 1e-9)
        assertEquals(63.25, WebVtt.parseTimestamp("01:03,250")!!, 1e-9)
        assertNull(WebVtt.parseTimestamp("garbage"))
    }
}

class PlaybackFormatTest {
    @Test fun timeLikeIos() {
        assertEquals("0:00", PlaybackFormat.time(0.0))
        assertEquals("0:59", PlaybackFormat.time(59.9))
        assertEquals("10:00", PlaybackFormat.time(600.0))
        assertEquals("1:02:03", PlaybackFormat.time(3723.0))
        assertEquals("0:00", PlaybackFormat.time(Double.NaN))
        assertEquals("0:00", PlaybackFormat.time(-5.0))
    }

    @Test fun widestLabel() {
        assertEquals("0:00", PlaybackFormat.widestLabel(599.0))
        assertEquals("00:00", PlaybackFormat.widestLabel(600.0))
        assertEquals("0:00:00", PlaybackFormat.widestLabel(3600.0))
        assertEquals("00:00:00", PlaybackFormat.widestLabel(36000.0))
    }

    @Test fun speedLabels() {
        assertEquals("1×", PlaybackFormat.speedLabel(1f))
        assertEquals("0.75×", PlaybackFormat.speedLabel(0.75f))
        assertEquals("1.5×", PlaybackFormat.speedLabel(1.5f))
        assertEquals("2×", PlaybackFormat.speedLabel(2f))
    }

    @Test fun markerTimeAndParse() {
        assertEquals("0:01:05", PlaybackFormat.markerTime(65.0))
        assertEquals("1:00:05", PlaybackFormat.markerTime(3605.0))
        assertEquals(95.0, PlaybackFormat.parseTime("01:35")!!, 1e-9)
        assertEquals(42.5, PlaybackFormat.parseTime("42.5")!!, 1e-9)
        assertEquals(3723.0, PlaybackFormat.parseTime("1:02:03")!!, 1e-9)
        assertNull(PlaybackFormat.parseTime(""))
        assertNull(PlaybackFormat.parseTime("0:00"))
    }

    @Test fun resolutionLabels() {
        assertEquals("4K", PlaybackFormat.resolutionLabel(2160))
        assertEquals("1080p", PlaybackFormat.resolutionLabel(1080))
        assertEquals("720p", PlaybackFormat.resolutionLabel(818))
        assertEquals("480p", PlaybackFormat.resolutionLabel(480))
        assertNull(PlaybackFormat.resolutionLabel(0))
    }

    @Test fun markerLabelWindow() {
        val markers = listOf(TimeBarMarker(10.0, "A"), TimeBarMarker(200.0, "B"))
        assertNull(markerAt(markers, 5.0))
        assertEquals("A", markerAt(markers, 70.0)?.title)
        assertNull(markerAt(markers, 71.0))
        assertEquals("B", markerAt(markers, 230.0)?.title)
    }
}

class PlaybackActivityTrackerTest {
    private fun tracker(saves: MutableList<Pair<Double?, Double>>) =
        PlaybackActivityTracker(CoroutineScope(Dispatchers.Unconfined)).apply { onSave = { r, d -> saves += r to d } }

    @Test fun countsContinuousPlaybackAndSavesEvery10s() {
        val saves = mutableListOf<Pair<Double?, Double>>()
        val t = tracker(saves)
        t.setPosition(0.0, 100.0)
        for (s in 1..10) { t.setPosition(s.toDouble(), 100.0); t.tick() }
        assertEquals(1, saves.size)
        assertEquals(10.0, saves[0].second, 1e-9)
        assertEquals(10.0, saves[0].first!!, 1e-9)
    }

    @Test fun seeksDoNotCount() {
        val saves = mutableListOf<Pair<Double?, Double>>()
        val t = tracker(saves)
        t.setPosition(0.0, 100.0)
        t.setPosition(1.0, 100.0); t.tick()
        t.setPosition(50.0, 100.0); t.tick() // jump > 4 s: realigned, not counted
        t.setPosition(51.0, 100.0); t.tick()
        t.flush()
        assertEquals(2.0, saves.single().second, 1e-9)
    }

    @Test fun resumeClearedAtEnd() {
        val saves = mutableListOf<Pair<Double?, Double>>()
        val t = tracker(saves)
        t.setPosition(97.0, 100.0)
        t.setPosition(99.0, 100.0); t.tick()
        t.flush()
        assertEquals(0.0, saves.single().first!!, 1e-9)
    }

    @Test fun noSaveWithoutWatchTime() {
        val saves = mutableListOf<Pair<Double?, Double>>()
        tracker(saves).flush()
        assertTrue(saves.isEmpty())
    }

    @Test fun markerStreamsSkipResume() {
        val saves = mutableListOf<Pair<Double?, Double>>()
        val t = tracker(saves).apply { updatesResumeTime = false }
        t.setPosition(0.0, 100.0); t.setPosition(2.0, 100.0); t.tick(); t.flush()
        assertNull(saves.single().first)
    }
}
