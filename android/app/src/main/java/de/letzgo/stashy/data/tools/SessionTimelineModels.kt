package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.IdName
import java.time.Instant

// Pure Session Timeline models and grouping (no Android APIs, unit-tested).
// iOS: `TimelineSceneSnapshot`, `TimelineKind`, `TimelineVisit`, `TimelineSession` and the
// static `makeSessions` / `groupedSessions` … helpers of `SessionTimelineLoader.swift`.

/** iOS: `TimelineSceneSnapshot`. */
data class TimelineSceneSnapshot(
    val id: String,
    val title: String,
    val thumbnailPath: String? = null,
    val duration: Double? = null,
    val resumeTime: Double? = null,
    val studio: IdName? = null,
    val tags: List<IdName> = emptyList(),
    val performers: List<IdName> = emptyList(),
    val rating100: Int? = null,
) {
    fun withThumbnail(path: String?): TimelineSceneSnapshot {
        val trimmed = path?.trim().orEmpty()
        return if (trimmed.isEmpty()) this else copy(thumbnailPath = trimmed)
    }

    val displayTitle: String get() {
        if (title != "Untitled" && title.isNotEmpty()) return title
        val names = performers.mapNotNull { it.name }.filter { it.isNotEmpty() }
        return if (names.isEmpty()) title else names.joinToString(", ")
    }

    val studioName: String? get() = studio?.name?.trim()?.takeIf { it.isNotEmpty() }
}

/** iOS: `TimelineKind` (raw values identical). */
enum class TimelineKind(val raw: String, val label: String) {
    Watch("watch", "Watch"), OCount("oCount", "O-Count"), Marker("marker", "Markers");

    companion object {
        fun from(raw: String): TimelineKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS: `TimelineVisit` — one play, O action or marker creation. */
data class TimelineVisit(
    val id: String,
    val scene: TimelineSceneSnapshot,
    val startedAt: Instant,
    val watchedSeconds: Double,
    val sceneStartSeconds: Double?,
    val oCountTimes: List<Instant>,
    val isPlayback: Boolean,
    val isMarkerAction: Boolean = false,
    val markerTitle: String? = null,
) {
    val oCount: Int get() = oCountTimes.size

    val timelineKind: TimelineKind get() = when {
        isMarkerAction -> TimelineKind.Marker
        isPlayback -> TimelineKind.Watch
        else -> TimelineKind.OCount
    }

    fun withWatchedSeconds(seconds: Double) = copy(watchedSeconds = seconds)
}

/** iOS: `TimelineSession` — visits newest first; a gap > 30 min starts a new session. */
data class TimelineSession(
    val id: String,
    val startedAt: Instant,
    val endedAt: Instant,
    val visits: List<TimelineVisit>,
) {
    val sceneCount: Int get() = visits.size
    val oCount: Int get() = visits.sumOf { it.oCount }
    val markerCount: Int get() = visits.count { it.isMarkerAction }
    val watchedSeconds: Double get() = visits.sumOf { it.watchedSeconds }
    val sessionSeconds: Double get() = maxOf(0.0, (endedAt.toEpochMilli() - startedAt.toEpochMilli()) / 1000.0)

    fun filtered(kinds: Set<TimelineKind>): TimelineSession? {
        val kept = visits.filter { it.timelineKind in kinds }
        if (kept.isEmpty()) return null
        val start = kept.last().startedAt
        val end = kept.first().let { it.startedAt.plusSeconds(it.watchedSeconds) }
        return TimelineSession(id, start, maxOf(end, start), kept)
    }
}

/** Raw `findScenes` row of the timeline query, already decoded to instants. */
data class TimelineSceneRowData(
    val snapshot: TimelineSceneSnapshot,
    val playHistory: List<Instant>,
    val lastPlayedAt: Instant?,
    val oHistory: List<Instant>,
    val playDuration: Double?,
    val playCount: Int?,
)

/** iOS: `TimelineOStamp`. */
data class TimelineOStamp(val scene: TimelineSceneSnapshot, val date: Instant)

/** iOS: `TimelineFetchedMarker`. */
data class TimelineFetchedMarker(
    val id: String,
    val sceneId: String,
    val date: Instant,
    val title: String?,
    val sceneTitle: String?,
    val thumbnailPath: String?,
    val studio: IdName?,
)

internal fun Instant.plusSeconds(seconds: Double): Instant = plusMillis((seconds * 1000).toLong())

/** Stable id component (iOS uses `timeIntervalSince1970`; only uniqueness matters). */
internal fun Instant.swiftInterval(): String = toEpochMilli().toString()

object SessionTimelineGrouping {
    const val WINDOW_SECONDS: Long = 24 * 60 * 60
    const val MAX_LOOKBACK_SECONDS: Long = 90 * 24 * 60 * 60
    const val SESSION_GAP_SECONDS: Double = 30.0 * 60

    private fun gapSeconds(newer: Instant, older: Instant) = (newer.toEpochMilli() - older.toEpochMilli()) / 1000.0

    /** iOS: `makeSessions(from:oStamps:fetchedMarkers:in:)` — range is `[start, end)`. */
    fun makeSessions(
        rows: List<TimelineSceneRowData>,
        oStamps: List<TimelineOStamp>,
        fetchedMarkers: List<TimelineFetchedMarker>,
        start: Instant,
        end: Instant,
    ): List<TimelineSession> {
        fun inRange(d: Instant) = d >= start && d < end
        val visits = mutableListOf<TimelineVisit>()
        val snapshots = linkedMapOf<String, TimelineSceneSnapshot>()
        val playDurationByScene = mutableMapOf<String, Double>()
        val playCountByScene = mutableMapOf<String, Int>()
        val durationByScene = mutableMapOf<String, Double>()

        for (row in rows) {
            val snapshot = row.snapshot
            snapshots[snapshot.id] = snapshot
            val allPlays = playTimes(row)
            playDurationByScene[snapshot.id] = row.playDuration ?: 0.0
            playCountByScene[snapshot.id] = maxOf(row.playCount ?: 0, allPlays.size, 1)
            snapshot.duration?.takeIf { it > 0 }?.let { durationByScene[snapshot.id] = it }

            val plays = allPlays.filter(::inRange).sorted()
            val os = row.oHistory.filter(::inRange).sorted()

            if (plays.isEmpty()) {
                os.forEach { visits.add(oVisit(snapshot, it)) }
                continue
            }

            plays.forEachIndexed { index, playStart ->
                val nextPlay = plays.getOrNull(index + 1)
                val attachUntil = nextPlay ?: playStart.plusSeconds(30 * 60L)
                val windowEnd = minOf(attachUntil, playStart.plusSeconds(30 * 60L + 120))
                val attached = os.filter { it >= playStart && it <= windowEnd }
                visits.add(
                    TimelineVisit(
                        id = "${snapshot.id}-${playStart.swiftInterval()}", scene = snapshot, startedAt = playStart,
                        watchedSeconds = 0.0, sceneStartSeconds = null, oCountTimes = attached, isPlayback = true,
                    ),
                )
            }

            val attached = visits.filter { it.scene.id == snapshot.id }.flatMap { it.oCountTimes }.toSet()
            os.filter { it !in attached }.forEach { visits.add(oVisit(snapshot, it)) }
        }

        mergeOStamps(oStamps, visits, snapshots)
        mergeFetchedMarkers(fetchedMarkers, visits, snapshots)
        applyWatchedDurations(visits, playDurationByScene, playCountByScene, durationByScene)
        applyResumeStartEstimates(visits)
        return groupedSessions(visits)
    }

    private fun oVisit(scene: TimelineSceneSnapshot, stamp: Instant) = TimelineVisit(
        id = "${scene.id}-o-${stamp.swiftInterval()}", scene = scene, startedAt = stamp,
        watchedSeconds = 0.0, sceneStartSeconds = null, oCountTimes = listOf(stamp), isPlayback = false,
    )

    internal fun mergeOStamps(stamps: List<TimelineOStamp>, visits: MutableList<TimelineVisit>, snapshots: MutableMap<String, TimelineSceneSnapshot>) {
        val seen = visits.flatMap { v -> v.oCountTimes.map { "${v.scene.id}-${it.epochSecond}" } }.toMutableSet()
        for (stamp in stamps) {
            val key = "${stamp.scene.id}-${stamp.date.epochSecond}"
            if (!seen.add(key)) continue
            val snapshot = snapshots[stamp.scene.id] ?: stamp.scene
            snapshots[stamp.scene.id] = snapshot
            visits.add(oVisit(snapshot, stamp.date))
        }
    }

    internal fun mergeFetchedMarkers(markers: List<TimelineFetchedMarker>, visits: MutableList<TimelineVisit>, snapshots: Map<String, TimelineSceneSnapshot>) {
        val seen = visits.filter { it.isMarkerAction }.map { it.id }.toMutableSet()
        for (marker in markers) {
            val visitId = "marker-${marker.id}"
            if (!seen.add(visitId)) continue
            val scene = snapshots[marker.sceneId]?.withThumbnail(marker.thumbnailPath)
                ?: visits.map { it.scene }.firstOrNull { it.id == marker.sceneId }?.withThumbnail(marker.thumbnailPath)
                ?: TimelineSceneSnapshot(
                    id = marker.sceneId,
                    title = marker.sceneTitle?.trim().orEmpty().ifEmpty { "Untitled" },
                    thumbnailPath = marker.thumbnailPath,
                    studio = marker.studio,
                )
            visits.add(
                TimelineVisit(
                    id = visitId, scene = scene, startedAt = marker.date, watchedSeconds = 0.0, sceneStartSeconds = null,
                    oCountTimes = emptyList(), isPlayback = false, isMarkerAction = true, markerTitle = marker.title,
                ),
            )
        }
    }

    /** iOS: `applyWatchedDurations` — gap to the next visit, else play_duration / play_count. */
    internal fun applyWatchedDurations(
        visits: MutableList<TimelineVisit>,
        playDurationByScene: Map<String, Double>,
        playCountByScene: Map<String, Int>,
        durationByScene: Map<String, Double>,
    ) {
        val ordered = visits.indices.sortedBy { visits[it].startedAt }
        ordered.forEachIndexed { position, index ->
            val visit = visits[index]
            if (!visit.isPlayback) return@forEachIndexed
            val sceneId = visit.scene.id
            val cap = durationByScene[sceneId]
            if (position + 1 < ordered.size) {
                val gap = gapSeconds(visits[ordered[position + 1]].startedAt, visit.startedAt)
                if (gap >= 15 && gap <= SESSION_GAP_SECONDS) {
                    visits[index] = visit.withWatchedSeconds(minOf(gap, cap ?: gap))
                    return@forEachIndexed
                }
            }
            val total = playDurationByScene[sceneId] ?: 0.0
            val count = maxOf(1, playCountByScene[sceneId] ?: 1)
            val share = total / count
            if (share < 15) return@forEachIndexed
            visits[index] = visit.withWatchedSeconds(minOf(share, cap ?: share))
        }
    }

    /** iOS: `applyResumeStartEstimates` — `resume_time − watched` on the newest play per scene. */
    internal fun applyResumeStartEstimates(visits: MutableList<TimelineVisit>) {
        val latestIndexByScene = linkedMapOf<String, Int>()
        for (index in visits.indices) {
            if (!visits[index].isPlayback) continue
            val sceneId = visits[index].scene.id
            val existing = latestIndexByScene[sceneId]
            if (existing == null || visits[index].startedAt > visits[existing].startedAt) latestIndexByScene[sceneId] = index
        }
        for (index in latestIndexByScene.values) {
            val visit = visits[index]
            val resume = visit.scene.resumeTime ?: continue
            if (resume <= 5 || visit.watchedSeconds < 15) continue
            val estimated = maxOf(0.0, resume - visit.watchedSeconds)
            if (estimated < 5) continue
            visits[index] = visit.copy(sceneStartSeconds = estimated)
        }
    }

    /** iOS: `groupedSessions(from:)` — newest first, split where the gap exceeds 30 minutes. */
    fun groupedSessions(visits: List<TimelineVisit>): List<TimelineSession> {
        val ordered = visits.sortedByDescending { it.startedAt }
        if (ordered.isEmpty()) return emptyList()
        val sessions = mutableListOf<TimelineSession>()
        var bucket = mutableListOf<TimelineVisit>()
        for (visit in ordered) {
            val last = bucket.lastOrNull()
            if (last != null && gapSeconds(last.startedAt, visit.startedAt) > SESSION_GAP_SECONDS) {
                sessions.add(session(bucket))
                bucket = mutableListOf(visit)
            } else {
                bucket.add(visit)
            }
        }
        if (bucket.isNotEmpty()) sessions.add(session(bucket))
        return sessions
    }

    private fun session(newestFirst: List<TimelineVisit>): TimelineSession {
        val start = newestFirst.last().startedAt
        val end = newestFirst.first().let { it.startedAt.plusSeconds(it.watchedSeconds) }
        return TimelineSession("${start.swiftInterval()}-${newestFirst.size}", start, maxOf(end, start), newestFirst.toList())
    }

    /** iOS: `mergeWindow` — adds visits of a newly loaded window and regroups. */
    fun mergeWindow(existing: List<TimelineSession>, built: List<TimelineSession>): List<TimelineSession> {
        val visits = existing.flatMap { it.visits }.toMutableList()
        val ids = visits.map { it.id }.toSet()
        built.flatMap { it.visits }.filter { it.id !in ids }.forEach { visits.add(it) }
        return groupedSessions(visits)
    }

    private fun playTimes(row: TimelineSceneRowData): List<Instant> =
        row.playHistory.ifEmpty { listOfNotNull(row.lastPlayedAt) }

    /** iOS: `SessionTimelineToolsView.days(from:)` — sessions grouped by local start day, in order. */
    fun <D> days(sessions: List<TimelineSession>, dayOf: (Instant) -> D): List<Pair<D, List<TimelineSession>>> {
        val grouped = mutableListOf<Pair<D, MutableList<TimelineSession>>>()
        for (session in sessions) {
            val day = dayOf(session.startedAt)
            val existing = grouped.firstOrNull { it.first == day }
            if (existing != null) existing.second.add(session) else grouped.add(day to mutableListOf(session))
        }
        return grouped.map { it.first to it.second.toList() }
    }
}
