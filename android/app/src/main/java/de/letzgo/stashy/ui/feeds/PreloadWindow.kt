package de.letzgo.stashy.ui.feeds

/**
 * Pure paging/preload rules of the feed (unit-tested).
 *
 * iOS keeps one engine per *visible* row and builds it lazily; Android holds a small pool of
 * players, so the active row plus its neighbours can be prepared in advance (next first — the
 * user mostly swipes forward).
 */
object PreloadWindow {
    /** iOS `reelItemRow.onAppear`: load the next page once a row this close to the end shows. */
    const val PREFETCH_DISTANCE = 5

    /** iOS `minimumRowsBeforeRefill`: rows that must remain ahead after dropping dead rows. */
    const val MINIMUM_ROWS_BEFORE_REFILL = 5

    /** iOS `mediaProbeLookahead`. */
    const val MEDIA_PROBE_LOOKAHEAD = 4

    /**
     * Indices whose media should be prepared, in priority order: current, next, previous, then
     * further ahead, capped at [poolSize]. [skip] excludes rows that have nothing to play
     * (animated clips, rows without a source).
     */
    fun indices(current: Int, count: Int, poolSize: Int, skip: (Int) -> Boolean = { false }): List<Int> {
        if (count <= 0 || poolSize <= 0 || current !in 0 until count) return emptyList()
        val order = buildList {
            add(current)
            add(current + 1)
            add(current - 1)
            for (i in 2..poolSize) add(current + i)
        }
        return order.filter { it in 0 until count && !skip(it) }.distinct().take(poolSize)
    }

    /** iOS: `itemCount >= prefetchDistance && index >= itemCount - prefetchDistance`. */
    fun shouldLoadMore(index: Int, count: Int, distance: Int = PREFETCH_DISTANCE): Boolean =
        count >= distance && index >= count - distance

    /** iOS `refillFeedAfterDrops`: fewer than [MINIMUM_ROWS_BEFORE_REFILL] rows left ahead. */
    fun needsRefill(index: Int, count: Int): Boolean = count - index.coerceAtLeast(0) < MINIMUM_ROWS_BEFORE_REFILL

    /**
     * iOS `probeUpcomingMedia`: the rolling window of rows (from the current one) to ask the
     * server about, minus rows already asked.
     */
    fun probeWindow(ids: List<String>, currentId: String?, alreadyProbed: Set<String>): List<String> {
        if (ids.isEmpty()) return emptyList()
        val start = currentId?.let { ids.indexOf(it) }?.takeIf { it >= 0 } ?: 0
        return ids.subList(start, minOf(start + MEDIA_PROBE_LOOKAHEAD, ids.size)).filter { it !in alreadyProbed }
    }

    /** Successor after a row is dropped: next surviving row, else the first (iOS `handleUnplayableItem`). */
    fun successor(ids: List<String>, droppedId: String, dropped: Set<String>): String? {
        val index = ids.indexOf(droppedId)
        if (index < 0) return ids.firstOrNull { it !in dropped }
        return ids.drop(index + 1).firstOrNull { it !in dropped } ?: ids.firstOrNull { it !in dropped && it != droppedId }
    }
}
