package de.letzgo.stashy.ui.player

/** iOS: `SubtitleCue`. */
data class SubtitleCue(val start: Double, val end: Double, val text: String)

/** One scrubber-sprite tile: the moment it covers and its rectangle on the sheet. */
data class SpriteTile(val start: Double, val end: Double, val x: Int, val y: Int, val width: Int, val height: Int)

/**
 * WebVTT parsing shared by captions and scrubber sprites (iOS: `WebVTTParser` in
 * `SubtitleController.swift` and `SceneScrubSprites.parse(vtt:)`). Pure — unit tested.
 */
object WebVtt {
    /** iOS: `WebVTTParser.parse` — header/NOTE/STYLE/REGION blocks skipped, tags stripped, sorted by start. */
    fun parseCues(raw: String): List<SubtitleCue> {
        val lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n").toMutableList()
        if (lines.isNotEmpty() && lines[0].startsWith("﻿")) lines[0] = lines[0].drop(1)
        val cues = mutableListOf<SubtitleCue>()
        var i = 0
        while (i < lines.size) {
            val line = lines[i].trim()
            i++
            if (line.isEmpty()) continue
            if (line.startsWith("WEBVTT") || line.startsWith("NOTE") || line.startsWith("STYLE") || line.startsWith("REGION")) {
                while (i < lines.size && lines[i].trim().isNotEmpty()) i++
                continue
            }
            var timing = line
            if (!timing.contains("-->") && i < lines.size) {
                val maybe = lines[i].trim()
                if (maybe.contains("-->")) { timing = maybe; i++ } else continue
            }
            val range = parseTiming(timing) ?: continue
            val text = mutableListOf<String>()
            while (i < lines.size) {
                val t = lines[i]; i++
                if (t.trim().isEmpty()) break
                text += stripTags(t)
            }
            val joined = text.joinToString("\n").trim()
            if (joined.isEmpty()) continue
            cues += SubtitleCue(range.first, range.second, joined)
        }
        return cues.sortedBy { it.start }
    }

    /** Text of the cue covering [seconds] (last started cue whose end lies ahead), or null. */
    fun cueText(cues: List<SubtitleCue>, seconds: Double): String? =
        cues.lastOrNull { it.start <= seconds && seconds < it.end }?.text

    /**
     * iOS: `SceneScrubSprites.parse(vtt:)` — Stash writes one cue per tile
     * (`00:00:00.000 --> 00:00:10.000` / `…_sprite.jpg#xywh=0,0,160,90`).
     */
    fun parseSpriteTiles(raw: String): List<SpriteTile> {
        val tiles = mutableListOf<SpriteTile>()
        var pending: Pair<Double, Double>? = null
        for (rawLine in raw.lines()) {
            val line = rawLine.trim()
            if (line.contains("-->")) {
                val parts = line.split("-->")
                pending = if (parts.size == 2) {
                    val s = spriteTimestamp(parts[0]); val e = spriteTimestamp(parts[1])
                    if (s != null && e != null) s to e else null
                } else null
                continue
            }
            val range = pending ?: continue
            val hash = line.indexOf("#xywh=").takeIf { it >= 0 } ?: continue
            val numbers = line.substring(hash + 6).split(",").mapNotNull { it.trim().toDoubleOrNull() }
            pending = null
            if (numbers.size != 4 || numbers[2] <= 0 || numbers[3] <= 0) continue
            tiles += SpriteTile(range.first, range.second, numbers[0].toInt(), numbers[1].toInt(), numbers[2].toInt(), numbers[3].toInt())
        }
        return tiles.sortedBy { it.start }
    }

    /** iOS: `SceneScrubSprites.thumbnail(at:)` tile lookup — last tile started at or before `seconds`, else the first. */
    fun tileAt(tiles: List<SpriteTile>, seconds: Double): SpriteTile? {
        val target = maxOf(0.0, seconds)
        return tiles.lastOrNull { it.start <= target } ?: tiles.firstOrNull()
    }

    private fun parseTiming(line: String): Pair<Double, Double>? {
        val parts = line.split("-->")
        if (parts.size < 2) return null
        val start = parseTimestamp(parts[0].trim()) ?: return null
        val end = parseTimestamp(parts[1].trim().split(" ").firstOrNull { it.isNotEmpty() } ?: "") ?: return null
        return start to end
    }

    /** iOS: `WebVTTParser.parseTimestamp` — `hh:mm:ss.mmm` or `mm:ss.mmm`, comma accepted. */
    fun parseTimestamp(value: String): Double? {
        val pieces = value.replace(",", ".").split(":")
        return when (pieces.size) {
            3 -> {
                val h = pieces[0].toDoubleOrNull() ?: return null
                val m = pieces[1].toDoubleOrNull() ?: return null
                val s = pieces[2].toDoubleOrNull() ?: return null
                h * 3600 + m * 60 + s
            }
            2 -> {
                val m = pieces[0].toDoubleOrNull() ?: return null
                val s = pieces[1].toDoubleOrNull() ?: return null
                m * 60 + s
            }
            else -> null
        }
    }

    private fun spriteTimestamp(raw: String): Double? {
        val stamp = raw.trim().split(Regex("\\s+")).firstOrNull().orEmpty()
        val parts = stamp.split(":")
        if (parts.isEmpty() || parts.size > 3) return null
        var total = 0.0
        for (p in parts) total = total * 60 + (p.replace(",", ".").toDoubleOrNull() ?: return null)
        return total
    }

    /** iOS: `WebVTTParser.stripTags` — drops `<…>` and decodes the four common entities. */
    fun stripTags(input: String): String {
        val sb = StringBuilder()
        var inside = false
        for (ch in input) {
            when {
                ch == '<' -> inside = true
                ch == '>' -> inside = false
                !inside -> sb.append(ch)
            }
        }
        return sb.toString().replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
    }
}
