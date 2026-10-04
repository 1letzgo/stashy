package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneFile
import de.letzgo.stashy.data.Studio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class TopListsLogicTest {

    // MARK: metrics → sort fields (iOS `*SortOption.sortField`)

    @Test fun sceneMetricsSortFields() {
        assertEquals(listOf("play_count", "o_counter", "play_duration", "rating"), TopListsSceneMetric.entries.map { it.sortField })
        assertEquals(listOf("Views", "O-Count", "Watch Time", "Rating"), TopListsSceneMetric.entries.map { it.label })
        assertTrue(TopListsSceneMetric.entries.all { it.direction == "DESC" })
    }

    @Test fun otherMetricsSortFields() {
        assertEquals(
            listOf("o_counter", "scenes_count", "rating", "images_count", "galleries_count"),
            TopListsPerformerMetric.entries.map { it.sortField },
        )
        assertEquals(listOf("scenes_count", "galleries_count", "rating", "images_count"), TopListsStudioMetric.entries.map { it.sortField })
        assertEquals(listOf("scenes_count", "images_count", "galleries_count", "scene_markers_count"), TopListsTagMetric.entries.map { it.sortField })
    }

    // MARK: paging

    @Test fun firstPageHasMoreOnlyWhenPartial() {
        assertEquals(TopListPage(2, true), TopListPage.afterFirstPage(25, 60))
        assertEquals(TopListPage(2, false), TopListPage.afterFirstPage(25, 25))
        assertEquals(TopListPage(2, false), TopListPage.afterFirstPage(0, 10))
        assertEquals(TopListPage(1, false), TopListPage.exhausted)
    }

    @Test fun loadMoreAdvancesCursor() {
        val page = TopListPage.afterFirstPage(25, 60)
        val second = page.afterLoadMore(incomingCount = 25, listCount = 50, total = 60)
        assertEquals(TopListPage(3, true), second)
        val third = second.afterLoadMore(incomingCount = 10, listCount = 60, total = 60)
        assertEquals(TopListPage(4, false), third)
        // An empty page stops paging even when the total says otherwise.
        assertFalse(second.afterLoadMore(0, 50, 60).hasMore)
    }

    @Test fun appendUniqueKeepsOrderAndDropsDuplicates() {
        val merged = TopListsLogic.appendUnique(listOf("a", "b"), listOf("b", "c", "a", "d", "c")) { it }
        assertEquals(listOf("a", "b", "c", "d"), merged)
    }

    // MARK: formatting

    @Test fun formatsCountsWithGrouping() {
        assertEquals("1,234,567", TopListsLogic.formatCount(1_234_567, Locale.US))
        assertEquals("1.234", TopListsLogic.formatCount(1234, Locale.GERMANY))
        assertEquals("0", TopListsLogic.formatCount(0, Locale.US))
    }

    @Test fun formatsWatchTime() {
        assertEquals("0m", TopListsLogic.formatDuration(0.0))
        assertEquals("1m", TopListsLogic.formatDuration(89.6))
        assertEquals("1h 56m", TopListsLogic.formatDuration(7016.12))
        assertEquals("10h 0m", TopListsLogic.formatDuration(36_000.0))
    }

    @Test fun formatsRating() {
        assertEquals("—", TopListsLogic.formatRating(null))
        assertEquals("80", TopListsLogic.formatRating(80))
    }

    // MARK: live patches

    private fun scene(id: String, o: Int? = null, rating: Int? = null, performers: List<Performer> = emptyList()) =
        Scene(id = id, oCounter = o, rating100 = rating, performers = performers)

    @Test fun oCounterPatchUpdatesAndResorts() {
        val list = listOf(scene("1", o = 5), scene("2", o = 3), scene("3", o = 1))
        val patched = TopListsLogic.withSceneOCounter(list, "3", 9)
        assertEquals(9, patched[2].oCounter)
        assertEquals(listOf("3", "1", "2"), TopListsLogic.sortScenesByOCounter(patched).map { it.id })
        // Unknown id or same value → same instance (no recomposition).
        assertSame(list, TopListsLogic.withSceneOCounter(list, "9", 1))
        assertSame(list, TopListsLogic.withSceneOCounter(list, "1", 5))
    }

    @Test fun performerBumpAddsDelta() {
        val performers = listOf(Performer("a", oCounter = 2), Performer("b"), Performer("c", oCounter = 7))
        val bumped = TopListsLogic.bumpPerformersOCounter(performers, listOf("a", "b"), 3)
        assertEquals(listOf(5, 3, 7), bumped.map { it.oCounter })
        assertEquals(listOf("c", "a", "b"), TopListsLogic.sortPerformersByOCounter(bumped).map { it.id })
        assertSame(performers, TopListsLogic.bumpPerformersOCounter(performers, listOf("a"), 0))
    }

    @Test fun ratingSortIsStableAndTreatsNullAsZero() {
        val list = listOf(scene("1"), scene("2", rating = 60), scene("3", rating = 60), scene("4", rating = 100))
        assertEquals(listOf("4", "2", "3", "1"), TopListsLogic.sortScenesByRating(list).map { it.id })
    }

    @Test fun metadataMergeKeepsCountersAndPrefersIncoming() {
        val old = Scene(
            id = "1", title = "Old", date = "2024-01-01", playCount = 4, oCounter = 2, rating100 = 40,
            updatedAt = "2026-01-01T00:00:00Z", files = listOf(SceneFile(duration = 120.0)),
            performers = listOf(Performer("p")),
        )
        val incoming = Scene(
            id = "1", title = "New", date = "", rating100 = 80, oCounter = 0, updatedAt = "2026-02-01T00:00:00Z",
            studio = Studio("s", "Studio"), files = listOf(SceneFile(duration = 0.0)),
        )
        val merged = TopListsLogic.mergeSceneListMetadata(old, incoming)
        assertEquals("New", merged.title)
        assertEquals("2024-01-01", merged.date) // empty incoming date keeps the old one
        assertEquals(80, merged.rating100)
        assertEquals(2, merged.oCounter) // counters are not taken from the edit
        assertEquals(4, merged.playCount)
        assertEquals("2026-02-01T00:00:00Z", merged.updatedAt)
        assertEquals("s", merged.studio?.id)
        assertEquals(listOf("p"), merged.performers.map { it.id }) // empty incoming performers keep the old ones
        assertEquals(120.0, merged.files?.first()?.duration)
    }

    @Test fun newerUpdatedAtPicksLatest() {
        assertEquals("b", TopListsLogic.newerUpdatedAt(null, "b"))
        assertEquals("2026-03-01", TopListsLogic.newerUpdatedAt("2026-03-01", "2026-01-01"))
        assertEquals("2026-03-01", TopListsLogic.newerUpdatedAt("2026-01-01", "2026-03-01"))
    }

    @Test fun coverPatchReplacesUpdatedAt() {
        val list = listOf(Scene(id = "1", updatedAt = "x"), Scene(id = "2", updatedAt = "y"))
        assertEquals("z", TopListsLogic.withSceneUpdatedAt(list, "2", "z")[1].updatedAt)
        assertSame(list, TopListsLogic.withSceneUpdatedAt(list, "2", "y"))
    }
}
