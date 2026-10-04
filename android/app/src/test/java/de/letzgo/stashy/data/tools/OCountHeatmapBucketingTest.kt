package de.letzgo.stashy.data.tools

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

class OCountHeatmapBucketingTest {
    private val berlin = ZoneId.of("Europe/Berlin")
    private val la = ZoneId.of("America/Los_Angeles")
    private val utc = ZoneId.of("UTC")

    // MARK: day keys and time zones

    @Test fun dayKeyUsesLocalDayOfZone() {
        val instant = Instant.parse("2026-10-03T23:30:00Z")
        assertEquals("2026-10-04", OCountHeatmapBucketing.dayKey(instant, berlin))
        assertEquals("2026-10-03", OCountHeatmapBucketing.dayKey(instant, utc))
        assertEquals("2026-10-03", OCountHeatmapBucketing.dayKey(instant, la))
    }

    @Test fun dayKeyIsZeroPadded() {
        assertEquals("0999-01-05", OCountHeatmapBucketing.dayKey(LocalDate.of(999, 1, 5)))
    }

    @Test fun parseDayKeyRoundTripsAndRejectsGarbage() {
        assertEquals(LocalDate.of(2026, 2, 28), OCountHeatmapBucketing.parseDayKey("2026-02-28"))
        assertNull(OCountHeatmapBucketing.parseDayKey("2026-02"))
        assertNull(OCountHeatmapBucketing.parseDayKey("2026-02-30"))
        assertNull(OCountHeatmapBucketing.parseDayKey("abc"))
    }

    // MARK: timestamps

    @Test fun parsesStashTimestampVariants() {
        val expected = Instant.parse("2026-08-14T10:02:05Z")
        assertEquals(expected, OCountHeatmapBucketing.parseTimestamp("2026-08-14T03:02:05-07:00"))
        assertEquals(expected, OCountHeatmapBucketing.parseTimestamp("2026-08-14T10:02:05Z"))
        assertEquals(expected, OCountHeatmapBucketing.parseTimestamp(" 2026-08-14T12:02:05+0200 "))
        assertEquals(expected, OCountHeatmapBucketing.parseTimestamp("2026-08-14 10:02:05"))
        assertEquals(
            Instant.parse("2026-08-14T10:02:05.123Z"),
            OCountHeatmapBucketing.parseTimestamp("2026-08-14T10:02:05.123456789Z"),
        )
        assertEquals(Instant.parse("2026-08-14T00:00:00Z"), OCountHeatmapBucketing.parseTimestamp("2026-08-14"))
        assertNull(OCountHeatmapBucketing.parseTimestamp(""))
        assertNull(OCountHeatmapBucketing.parseTimestamp("not a date"))
    }

    @Test fun parsesUnixSecondsAndMilliseconds() {
        assertEquals(Instant.ofEpochSecond(1_789_978_575), OCountHeatmapBucketing.parseTimestamp("1789978575"))
        assertEquals(Instant.ofEpochSecond(1_789_978_575), OCountHeatmapBucketing.parseTimestamp("1789978575000"))
        assertEquals(Instant.ofEpochSecond(1_789_978_575), OCountHeatmapBucketing.flexibleTime(JsonPrimitive(1_789_978_575)))
        assertEquals(Instant.ofEpochSecond(1_789_978_575), OCountHeatmapBucketing.flexibleTime(JsonPrimitive(1_789_978_575_000L)))
        assertEquals(Instant.parse("2026-09-21T14:39:39Z"), OCountHeatmapBucketing.flexibleTime(JsonPrimitive("2026-09-21T14:39:39Z")))
    }

    // MARK: buckets

    @Test fun bucketsSumPerDayAndMergeItems() {
        val b = OCountDayBuckets()
        val t1 = Instant.parse("2026-10-01T20:00:00Z")
        val t2 = Instant.parse("2026-10-01T21:00:00Z")
        b.add(OCountHeatmapItem.Kind.Scene, "1", "  ", null, dayKey = "2026-10-01", amount = 1, occurredAt = t1, isActionTime = true)
        b.add(OCountHeatmapItem.Kind.Scene, "1", "A", null, dayKey = "2026-10-01", amount = 1, occurredAt = t2, isActionTime = true)
        b.add(OCountHeatmapItem.Kind.Scene, "2", "B", null, dayKey = "2026-10-01", amount = 3)
        b.add(OCountHeatmapItem.Kind.Scene, "3", "C", null, dayKey = "2026-10-01", amount = 0) // ignored
        b.add(OCountHeatmapItem.Kind.Scene, "", "D", null, dayKey = "2026-10-01", amount = 2) // ignored

        assertEquals(5, b.counts["2026-10-01"])
        val items = b.items["2026-10-01"]!!
        assertEquals(2, items.size)
        assertEquals("Untitled", items[0].title) // first title wins, blank → Untitled
        assertEquals(2, items[0].countOnDay)
        assertEquals(2, b.events.size)
        assertTrue(b.events.all { it.isActionTime })

        val images = OCountDayBuckets()
        images.add(OCountHeatmapItem.Kind.Image, "1", "Img", "thumb", dayKey = "2026-10-01", amount = 2, occurredAt = t1)
        images.add(OCountHeatmapItem.Kind.Image, "9", "Img2", null, dayKey = "2026-10-02", amount = 1, occurredAt = t2)
        b.merge(images)
        assertEquals(7, b.counts["2026-10-01"])
        assertEquals(1, b.counts["2026-10-02"])
        assertEquals(3, b.items["2026-10-01"]!!.size) // image 1 is not the same item as scene 1
        assertEquals(4, b.events.size)
    }

    @Test fun sortedItemsPutsScenesFirstThenCountThenTitle() {
        val sorted = OCountHeatmapBucketing.sortedItems(
            listOf(
                OCountHeatmapItem(OCountHeatmapItem.Kind.Image, "i", "zzz", countOnDay = 9),
                OCountHeatmapItem(OCountHeatmapItem.Kind.Scene, "b", "beta", countOnDay = 1),
                OCountHeatmapItem(OCountHeatmapItem.Kind.Scene, "a", "Alpha", countOnDay = 1),
                OCountHeatmapItem(OCountHeatmapItem.Kind.Scene, "c", "gamma", countOnDay = 4),
            ),
        )
        assertEquals(listOf("c", "a", "b", "i"), sorted.map { it.stashID })
    }

    // MARK: intensity levels

    @Test fun colorLevelsAreLogScaled() {
        assertEquals(0, OCountHeatmapBucketing.colorLevel(0, 10))
        assertEquals(0, OCountHeatmapBucketing.colorLevel(3, 0))
        assertEquals(4, OCountHeatmapBucketing.colorLevel(1, 1))
        // ceil(4 * ln(c+1)/ln(11))
        assertEquals(2, OCountHeatmapBucketing.colorLevel(1, 10))
        assertEquals(3, OCountHeatmapBucketing.colorLevel(3, 10))
        assertEquals(4, OCountHeatmapBucketing.colorLevel(7, 10))
        assertEquals(4, OCountHeatmapBucketing.colorLevel(10, 10))
        assertEquals(1, OCountHeatmapBucketing.colorLevel(1, 1000))
    }

    // MARK: month grid (Monday-first weeks)

    @Test fun monthGridStartsOnMonday() {
        // October 2026 starts on a Thursday → 3 leading slots, 31 days → 5 week rows.
        val counts = mapOf("2026-10-01" to 2, "2026-10-31" to 1, "2026-09-30" to 5, "2026-11-01" to 4)
        val h = OCountMonthHeatmap.build(counts, YearMonth.of(2026, 10), globalMax = 5)
        assertEquals("October 2026", h.monthTitle)
        assertEquals(5, h.rowCount)
        assertEquals(35, h.cells.size)
        assertEquals(3, h.totalInMonth) // days outside the month don't count
        assertEquals(2, h.daysWithOCount)

        val first = h.cell(3, 0)!!
        assertEquals("2026-10-01", first.id)
        assertEquals(1, first.day)
        assertTrue(first.isInDisplayedMonth)
        assertEquals(2, first.count)

        val leading = h.cell(2, 0)!!
        assertEquals("2026-09-30", leading.id)
        assertEquals(false, leading.isInDisplayedMonth)
        assertEquals(0, leading.count)
        assertEquals(0, leading.colorLevel)
        assertEquals("Sep 30, 2026, outside month", leading.accessibilityLabel)

        val last = h.cell(5, 4)!!
        assertEquals("2026-10-31", last.id)
        assertEquals("Oct 31, 2026, 1 O-Count", last.accessibilityLabel)
        assertEquals("2026-11-01", h.cell(6, 4)!!.id)
    }

    @Test fun monthGridRowCounts() {
        // February 2027 starts on a Monday and has 28 days → exactly 4 rows.
        assertEquals(4, OCountMonthHeatmap.build(emptyMap(), YearMonth.of(2027, 2), 0).rowCount)
        // March 2026 starts on a Sunday → 6 leading slots + 31 days → 6 rows.
        val march = OCountMonthHeatmap.build(emptyMap(), YearMonth.of(2026, 3), 0)
        assertEquals(6, march.rowCount)
        assertEquals("2026-03-01", march.cell(6, 0)!!.id)
        assertEquals(6, OCountHeatmapBucketing.leadingSlots(LocalDate.of(2026, 3, 1)))
        assertEquals(0, OCountHeatmapBucketing.leadingSlots(LocalDate.of(2027, 2, 1)))
    }

    @Test fun earliestAndLatestMonthIgnoreZeroDays() {
        val counts = mapOf("2025-12-31" to 0, "2026-01-15" to 1, "2026-08-02" to 3, "2026-09-01" to 0)
        assertEquals(YearMonth.of(2026, 1), OCountHeatmapBucketing.earliestMonth(counts))
        assertEquals(YearMonth.of(2026, 8), OCountHeatmapBucketing.latestMonth(counts))
        assertEquals(9, OCountHeatmapBucketing.monthsBetween(YearMonth.of(2026, 1), YearMonth.of(2026, 10)))
        assertEquals(13, OCountHeatmapBucketing.monthsBetween(YearMonth.of(2025, 9), YearMonth.of(2026, 10)))
    }

    @Test fun bucketingAcrossZonesMovesEventsBetweenDays() {
        val stamp = Instant.parse("2026-10-31T23:30:00Z")
        val inBerlin = OCountDayBuckets().apply {
            add(OCountHeatmapItem.Kind.Scene, "1", "x", null, dayKey = OCountHeatmapBucketing.dayKey(stamp, berlin), amount = 1)
        }
        val inLA = OCountDayBuckets().apply {
            add(OCountHeatmapItem.Kind.Scene, "1", "x", null, dayKey = OCountHeatmapBucketing.dayKey(stamp, la), amount = 1)
        }
        assertEquals(setOf("2026-11-01"), inBerlin.counts.keys)
        assertEquals(setOf("2026-10-31"), inLA.counts.keys)
        assertEquals(0, OCountMonthHeatmap.build(inBerlin.counts, YearMonth.of(2026, 10), 1).totalInMonth)
        assertEquals(1, OCountMonthHeatmap.build(inLA.counts, YearMonth.of(2026, 10), 1).totalInMonth)
    }
}
