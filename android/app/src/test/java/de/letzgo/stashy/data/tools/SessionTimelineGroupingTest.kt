package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.IdName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class SessionTimelineGroupingTest {
    private val base = Instant.parse("2026-10-03T20:00:00Z")
    private fun at(minutes: Long) = base.plusSeconds(minutes * 60)
    private val windowStart = base.minusSeconds(3600)
    private val windowEnd = base.plusSeconds(24 * 3600)

    private fun scene(id: String, duration: Double? = null, resume: Double? = null) =
        TimelineSceneSnapshot(id = id, title = "Scene $id", duration = duration, resumeTime = resume, studio = IdName("s", "Studio"))

    private fun row(
        id: String,
        plays: List<Instant> = emptyList(),
        os: List<Instant> = emptyList(),
        playDuration: Double? = null,
        playCount: Int? = null,
        duration: Double? = null,
        resume: Double? = null,
        lastPlayed: Instant? = null,
    ) = TimelineSceneRowData(scene(id, duration, resume), plays, lastPlayed, os, playDuration, playCount)

    private fun visit(id: String, start: Instant, watched: Double = 0.0, playback: Boolean = true) =
        TimelineVisit(id, scene(id), start, watched, null, emptyList(), playback)

    @Test fun groupsByThirtyMinuteGapNewestFirst() {
        val visits = listOf(visit("a", at(0)), visit("b", at(20)), visit("c", at(51)), visit("d", at(80)))
        val sessions = SessionTimelineGrouping.groupedSessions(visits)
        // 80 → 51 (29 min) stays together; 51 → 20 (31 min) splits; 20 → 0 together.
        assertEquals(2, sessions.size)
        assertEquals(listOf("d", "c"), sessions[0].visits.map { it.id })
        assertEquals(listOf("b", "a"), sessions[1].visits.map { it.id })
        assertEquals(at(51), sessions[0].startedAt)
        assertEquals(at(0), sessions[1].startedAt)
    }

    @Test fun sessionEndIncludesWatchedTimeOfNewestVisit() {
        val sessions = SessionTimelineGrouping.groupedSessions(listOf(visit("a", at(0), watched = 60.0), visit("b", at(10), watched = 300.0)))
        assertEquals(1, sessions.size)
        assertEquals(at(15), sessions[0].endedAt)
        assertEquals(15 * 60.0, sessions[0].sessionSeconds, 0.001)
        assertEquals(360.0, sessions[0].watchedSeconds, 0.001)
    }

    @Test fun emptyInputGivesNoSessions() {
        assertTrue(SessionTimelineGrouping.groupedSessions(emptyList()).isEmpty())
    }

    @Test fun oCountsAttachToThePlayBeforeThem() {
        val sessions = SessionTimelineGrouping.makeSessions(
            rows = listOf(row("1", plays = listOf(at(0), at(10)), os = listOf(at(5), at(12), at(60)), playDuration = 600.0, playCount = 2)),
            oStamps = emptyList(), fetchedMarkers = emptyList(), start = windowStart, end = windowEnd,
        )
        val visits = sessions.flatMap { it.visits }
        val plays = visits.filter { it.isPlayback }.sortedBy { it.startedAt }
        assertEquals(2, plays.size)
        assertEquals(listOf(at(5)), plays[0].oCountTimes)     // until the next play
        assertEquals(listOf(at(12)), plays[1].oCountTimes)    // within 30 min of the last play
        val loose = visits.filter { !it.isPlayback }
        assertEquals(1, loose.size)                            // 60 min is a separate O action
        assertEquals(TimelineKind.OCount, loose[0].timelineKind)
        assertEquals(at(60), loose[0].startedAt)
        // 60 → 10 is a 50 min gap → two sessions.
        assertEquals(2, sessions.size)
    }

    @Test fun watchedSecondsUseGapToNextVisitOrPlayShare() {
        val sessions = SessionTimelineGrouping.makeSessions(
            rows = listOf(
                row("1", plays = listOf(at(0)), playDuration = 0.0, playCount = 1, duration = 3600.0),
                row("2", plays = listOf(at(10)), playDuration = 900.0, playCount = 3, duration = 200.0),
            ),
            oStamps = emptyList(), fetchedMarkers = emptyList(), start = windowStart, end = windowEnd,
        )
        val byId = sessions.flatMap { it.visits }.associateBy { it.scene.id }
        assertEquals(600.0, byId.getValue("1").watchedSeconds, 0.001) // gap to next visit
        assertEquals(200.0, byId.getValue("2").watchedSeconds, 0.001) // 900/3 capped by duration 200
    }

    @Test fun resumeEstimateOnNewestPlay() {
        val sessions = SessionTimelineGrouping.makeSessions(
            rows = listOf(row("1", plays = listOf(at(0)), playDuration = 120.0, playCount = 1, resume = 500.0)),
            oStamps = emptyList(), fetchedMarkers = emptyList(), start = windowStart, end = windowEnd,
        )
        val v = sessions.single().visits.single()
        assertEquals(120.0, v.watchedSeconds, 0.001)
        assertEquals(380.0, v.sceneStartSeconds!!, 0.001)
    }

    @Test fun playsOutsideWindowAreIgnoredAndLastPlayedIsFallback() {
        val sessions = SessionTimelineGrouping.makeSessions(
            rows = listOf(
                row("1", plays = listOf(windowStart.minusSeconds(10))),
                row("2", lastPlayed = at(30)),
            ),
            oStamps = emptyList(), fetchedMarkers = emptyList(), start = windowStart, end = windowEnd,
        )
        val visits = sessions.flatMap { it.visits }
        assertEquals(listOf("2"), visits.map { it.scene.id })
        assertTrue(visits.single().isPlayback)
    }

    @Test fun oStampsAndMarkersAreMergedWithoutDuplicates() {
        val stampScene = scene("9")
        val sessions = SessionTimelineGrouping.makeSessions(
            rows = listOf(row("1", plays = listOf(at(0)), os = listOf(at(5)))),
            oStamps = listOf(
                TimelineOStamp(scene("1"), at(5)),       // duplicate of the row's o_history
                TimelineOStamp(stampScene, at(20)),
            ),
            fetchedMarkers = listOf(
                TimelineFetchedMarker("m1", "1", at(8), "Intro", null, "shot", null),
                TimelineFetchedMarker("m1", "1", at(8), "Intro", null, "shot", null),
                TimelineFetchedMarker("m2", "77", at(9), null, "  ", null, IdName("s2", "Other")),
            ),
            start = windowStart, end = windowEnd,
        )
        val visits = sessions.flatMap { it.visits }
        assertEquals(1, visits.count { it.scene.id == "9" })
        assertEquals(1, visits.flatMap { it.oCountTimes }.count { it == at(5) })
        val markers = visits.filter { it.isMarkerAction }
        assertEquals(listOf("marker-m1", "marker-m2").toSet(), markers.map { it.id }.toSet())
        val m1 = markers.first { it.id == "marker-m1" }
        assertEquals("shot", m1.scene.thumbnailPath)
        assertEquals("Scene 1", m1.scene.title)
        assertEquals(TimelineKind.Marker, m1.timelineKind)
        val m2 = markers.first { it.id == "marker-m2" }
        assertEquals("Untitled", m2.scene.title)
        assertEquals("Other", m2.scene.studioName)
    }

    @Test fun filteringKeepsOnlySelectedKindsAndRecomputesBounds() {
        val visits = listOf(
            visit("p", at(30), watched = 120.0, playback = true),
            TimelineVisit("o", scene("o"), at(10), 0.0, null, listOf(at(10)), false),
        )
        val session = SessionTimelineGrouping.groupedSessions(visits).single()
        val onlyO = session.filtered(setOf(TimelineKind.OCount))!!
        assertEquals(listOf("o"), onlyO.visits.map { it.id })
        assertEquals(at(10), onlyO.startedAt)
        assertEquals(at(10), onlyO.endedAt)
        assertNull(session.filtered(setOf(TimelineKind.Marker)))
        assertEquals(1, session.oCount)
    }

    @Test fun mergeWindowSkipsKnownVisits() {
        val first = SessionTimelineGrouping.groupedSessions(listOf(visit("a", at(100))))
        val built = SessionTimelineGrouping.groupedSessions(listOf(visit("a", at(100)), visit("b", at(90))))
        val merged = SessionTimelineGrouping.mergeWindow(first, built)
        assertEquals(1, merged.size)
        assertEquals(listOf("a", "b"), merged.single().visits.map { it.id })
    }

    @Test fun daysGroupByLocalStartDayInOrder() {
        val zone = ZoneId.of("Europe/Berlin")
        val sessions = SessionTimelineGrouping.groupedSessions(
            listOf(
                visit("late", Instant.parse("2026-10-03T22:30:00Z")),  // 00:30 on Oct 4 in Berlin
                visit("evening", Instant.parse("2026-10-03T19:00:00Z")),
                visit("morning", Instant.parse("2026-10-03T08:00:00Z")),
            ),
        )
        val days = SessionTimelineGrouping.days(sessions) { it.atZone(zone).toLocalDate() }
        assertEquals(listOf(LocalDate.of(2026, 10, 4), LocalDate.of(2026, 10, 3)), days.map { it.first })
        assertEquals(2, days[1].second.size)
    }
}
