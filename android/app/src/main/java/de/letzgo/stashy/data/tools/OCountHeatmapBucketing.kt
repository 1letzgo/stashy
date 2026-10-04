package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.VisualFile
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.ln

// Pure O-Count heatmap logic (no Android APIs) so plain JUnit can test it.
// iOS: the static helpers of `OCountHeatmapLoader`, `OCountDayBuckets`, `OCountTimestamp`,
// `OCountMonthHeatmap` and `FlexibleJSONTime` in `OCountHeatmapLoader.swift`.

/** iOS: `OCountHeatmapItem` — one scene or image counted on a day. */
data class OCountHeatmapItem(
    val kind: Kind,
    val stashID: String,
    val title: String,
    val thumbnailPath: String? = null,
    val previewPath: String? = null,
    val imagePath: String? = null,
    val visualFiles: List<VisualFile>? = null,
    val performers: List<IdName> = emptyList(),
    val studio: IdName? = null,
    val rating100: Int? = null,
    val countOnDay: Int = 1,
) {
    enum class Kind { Scene, Image }

    val id: String get() = "${if (kind == Kind.Scene) "scene" else "image"}-$stashID"

    val displayTitle: String get() {
        if (title != "Untitled") return title
        val names = performers.mapNotNull { it.name }.filter { it.isNotEmpty() }
        return if (names.isEmpty()) title else names.joinToString(", ")
    }

    val performerNamesLine: String get() = performers.mapNotNull { it.name }.filter { it.isNotEmpty() }.joinToString(", ")

    val isVideo: Boolean get() = visualFiles?.firstOrNull()?.typename == "VideoFile"

    val kindTitle: String get() = when (kind) {
        Kind.Scene -> "Scene"
        Kind.Image -> if (isVideo) "Video" else "Image"
    }

    val rowSubtitle: String get() = when (kind) {
        Kind.Scene -> studio?.name?.trim().orEmpty().ifEmpty { kindTitle }
        Kind.Image -> kindTitle
    }

    val isPlaceholder: Boolean get() = title == "Untitled" && thumbnailPath == null && previewPath == null && imagePath == null

    fun withRating(rating: Int?) = copy(rating100 = rating)
    fun withCountOnDay(count: Int) = copy(countOnDay = count)

    /** iOS: `mergingListMetadata(from:)`. */
    fun mergingListMetadata(sceneTitle: String?, sceneStudio: IdName?, sceneRating: Int?) = copy(
        title = sceneTitle ?: title,
        studio = sceneStudio ?: studio,
        rating100 = sceneRating ?: rating100,
    )

    companion object {
        fun stub(kind: Kind, stashID: String) = OCountHeatmapItem(kind = kind, stashID = stashID, title = "Untitled", countOnDay = 1)
    }
}

/** iOS: `OCountTimelineEvent`. [isActionTime] = the O action time, not a file created/updated date. */
data class OCountTimelineEvent(
    val item: OCountHeatmapItem,
    val date: Instant,
    val count: Int,
    val isActionTime: Boolean = false,
)

/** iOS: `OCountDayBuckets` — counts, items and events per local day key. */
class OCountDayBuckets {
    val counts = linkedMapOf<String, Int>()
    val items = linkedMapOf<String, MutableList<OCountHeatmapItem>>()
    val events = mutableListOf<OCountTimelineEvent>()

    fun add(
        kind: OCountHeatmapItem.Kind,
        stashID: String,
        title: String?,
        thumbnailPath: String?,
        previewPath: String? = null,
        imagePath: String? = null,
        visualFiles: List<VisualFile>? = null,
        performers: List<IdName> = emptyList(),
        studio: IdName? = null,
        rating100: Int? = null,
        dayKey: String,
        amount: Int,
        occurredAt: Instant? = null,
        isActionTime: Boolean = false,
    ) {
        if (amount <= 0 || stashID.isEmpty()) return
        counts[dayKey] = (counts[dayKey] ?: 0) + amount
        val list = items.getOrPut(dayKey) { mutableListOf() }
        val resolvedTitle = title?.trim().orEmpty().ifEmpty { "Untitled" }
        val item = OCountHeatmapItem(kind, stashID, resolvedTitle, thumbnailPath, previewPath, imagePath, visualFiles, performers, studio, rating100, amount)
        val idx = list.indexOfFirst { it.kind == kind && it.stashID == stashID }
        if (idx >= 0) list[idx] = list[idx].copy(countOnDay = list[idx].countOnDay + amount) else list.add(item)
        if (occurredAt != null) events.add(OCountTimelineEvent(item, occurredAt, amount, isActionTime))
    }

    fun merge(other: OCountDayBuckets) {
        for ((dayKey, list) in other.items) {
            for (item in list) {
                add(
                    item.kind, item.stashID, item.title, item.thumbnailPath, item.previewPath, item.imagePath,
                    item.visualFiles, item.performers, item.studio, item.rating100, dayKey, item.countOnDay,
                )
            }
        }
        events.addAll(other.events)
    }
}

/** iOS: `OCountMonthHeatmap` — the Monday-first month grid of one calendar month. */
data class OCountMonthHeatmap(
    val year: Int,
    val month: Int,
    val monthTitle: String,
    val rowCount: Int,
    val columnCount: Int,
    val daysWithOCount: Int,
    val totalInMonth: Int,
    val cells: List<Cell>,
) {
    data class Cell(
        val id: String,
        val column: Int,
        val row: Int,
        val day: Int,
        val isInDisplayedMonth: Boolean,
        val count: Int,
        val colorLevel: Int,
        val accessibilityLabel: String,
    )

    fun cell(column: Int, row: Int): Cell? = cells.firstOrNull { it.column == column && it.row == row }

    companion object {
        private val monthFormatter = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.US)
        private val prettyFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)

        /**
         * iOS: `OCountMonthHeatmap.build(countsByDay:monthContaining:calendar:locale:globalMax:)`
         * with a Gregorian calendar whose first weekday is Monday.
         */
        fun build(countsByDay: Map<String, Int>, month: YearMonth, globalMax: Int): OCountMonthHeatmap {
            val monthStart = month.atDay(1)
            val dayCount = month.lengthOfMonth()
            val leading = OCountHeatmapBucketing.leadingSlots(monthStart)
            val rowCount = (leading + dayCount + 6) / 7
            val slotCount = rowCount * 7

            data class Staged(val col: Int, val row: Int, val key: String, val date: LocalDate, val count: Int, val inMonth: Boolean)
            val staged = (0 until slotCount).map { slot ->
                val offset = slot - leading
                val date = monthStart.plusDays(offset.toLong())
                val inMonth = offset in 0 until dayCount
                val key = OCountHeatmapBucketing.dayKey(date)
                Staged(slot % 7, slot / 7, key, date, if (inMonth) countsByDay[key] ?: 0 else 0, inMonth)
            }

            val maxValue = maxOf(globalMax, staged.maxOfOrNull { it.count } ?: 0)
            var daysWithOCount = 0
            var totalInMonth = 0
            val cells = staged.map { s ->
                if (s.inMonth) {
                    if (s.count > 0) daysWithOCount++
                    totalInMonth += s.count
                }
                val pretty = prettyFormatter.format(s.date)
                val a11y = when {
                    !s.inMonth -> "$pretty, outside month"
                    s.count > 0 -> "$pretty, ${s.count} O-Count"
                    else -> "$pretty, no O-Count"
                }
                Cell(s.key, s.col, s.row, s.date.dayOfMonth, s.inMonth, s.count,
                    OCountHeatmapBucketing.colorLevel(if (s.inMonth) s.count else 0, maxValue), a11y)
            }
            return OCountMonthHeatmap(
                month.year, month.monthValue, monthFormatter.format(monthStart),
                rowCount, 7, daysWithOCount, totalInMonth, cells,
            )
        }
    }
}

object OCountHeatmapBucketing {
    /** iOS: `OCountHeatmapLoader.dayKey(_:calendar:)` — `yyyy-MM-dd` of the local day in [zone]. */
    fun dayKey(instant: Instant, zone: ZoneId): String = dayKey(instant.atZone(zone).toLocalDate())

    fun dayKey(date: LocalDate): String = String.format(Locale.US, "%04d-%02d-%02d", date.year, date.monthValue, date.dayOfMonth)

    /** iOS: `parseDayKey(_:calendar:)`. */
    fun parseDayKey(key: String): LocalDate? {
        val parts = key.split("-").mapNotNull { it.toIntOrNull() }
        if (parts.size != 3) return null
        return runCatching { LocalDate.of(parts[0], parts[1], parts[2]) }.getOrNull()
    }

    /** Empty slots before day 1 in a Monday-first week (iOS `firstWeekday = 2`). */
    fun leadingSlots(monthStart: LocalDate): Int = (monthStart.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7

    /** iOS: `OCountMonthHeatmap.colorLevel` — 0 … 4 on a log scale against the global max. */
    fun colorLevel(count: Int, maxValue: Int): Int {
        if (count <= 0 || maxValue <= 0) return 0
        if (maxValue <= 1) return 4
        val ratio = ln(count.toDouble() + 1) / ln(maxValue.toDouble() + 1)
        return ceil(ratio * 4.0).toInt().coerceIn(1, 4)
    }

    /** Months between two month starts (iOS `dateComponents([.month], from:to:)`). */
    fun monthsBetween(from: YearMonth, to: YearMonth): Int = (to.year - from.year) * 12 + (to.monthValue - from.monthValue)

    fun earliestMonth(countsByDay: Map<String, Int>): YearMonth? =
        countsByDay.filterValues { it > 0 }.keys.mapNotNull { parseDayKey(it) }.minOrNull()?.let { YearMonth.from(it) }

    fun latestMonth(countsByDay: Map<String, Int>): YearMonth? =
        countsByDay.filterValues { it > 0 }.keys.mapNotNull { parseDayKey(it) }.maxOrNull()?.let { YearMonth.from(it) }

    /** iOS: `items(onDayKey:)` order — scenes first, then higher count, then title. */
    fun sortedItems(items: List<OCountHeatmapItem>): List<OCountHeatmapItem> = items.sortedWith(
        compareBy<OCountHeatmapItem> { if (it.kind == OCountHeatmapItem.Kind.Scene) 0 else 1 }
            .thenByDescending { it.countOnDay }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title },
    )

    /** iOS: `FlexibleJSONTime.date` — ISO string or unix seconds/milliseconds. */
    fun flexibleTime(element: JsonElement?): Instant? {
        val p = element as? JsonPrimitive ?: return null
        if (p.isString) return parseTimestamp(p.contentOrNull ?: return null)
        val value = p.doubleOrNull ?: return null
        val seconds = if (value > 1_000_000_000_000) value / 1000 else value
        return Instant.ofEpochMilli((seconds * 1000).toLong())
    }

    private val fraction = Regex("""\.(\d+)""")
    private val compactOffset = Regex("""([+-]\d{2})(\d{2})$""")

    /**
     * iOS: `OCountHeatmapLoader.parseTimestamp` — unix numbers, ISO 8601 with or without
     * fractional seconds and offsets (`Z`, `+02:00`, `+0200`), `yyyy-MM-dd HH:mm:ss` (UTC)
     * and finally the `yyyy-MM-dd` prefix (UTC midnight).
     */
    fun parseTimestamp(raw: String): Instant? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null

        trimmed.toDoubleOrNull()?.let { value ->
            if (value > 1_000_000_000) {
                val seconds = if (value > 1_000_000_000_000) value / 1000 else value
                return Instant.ofEpochMilli((seconds * 1000).toLong())
            }
        }

        // Fractional seconds collapsed to milliseconds like iOS `collapseFractionalSeconds`.
        val collapsed = fraction.find(trimmed)?.let { m ->
            val digits = m.groupValues[1].take(3).padEnd(3, '0')
            trimmed.replaceRange(m.range, ".$digits")
        }
        for (candidate in listOfNotNull(collapsed, trimmed)) {
            val normalized = candidate.replace(compactOffset, "$1:$2")
            runCatching { return OffsetDateTime.parse(normalized, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant() }
            runCatching {
                return LocalDateTime.parse(candidate, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.US)).toInstant(ZoneOffset.UTC)
            }
        }
        if (trimmed.length >= 10) {
            parseDayKeyStrict(trimmed.take(10))?.let { return it.atStartOfDay(ZoneOffset.UTC).toInstant() }
        }
        return null
    }

    private fun parseDayKeyStrict(prefix: String): LocalDate? =
        runCatching { LocalDate.parse(prefix, DateTimeFormatter.ISO_LOCAL_DATE) }.getOrNull()
}
