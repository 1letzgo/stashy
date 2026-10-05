package de.letzgo.stashy.feeds

import de.letzgo.stashy.data.FeedsSceneStartPosition
import de.letzgo.stashy.data.FeedsSceneStartPosition.FirstMarker
import de.letzgo.stashy.data.FeedsSceneStartPosition.Random as RandomStart
import de.letzgo.stashy.data.FeedsSceneStartPosition.Skip30
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneFile
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.ui.feeds.FeedStartPosition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class FeedStartPositionTest {
    private fun start(
        setting: FeedsSceneStartPosition,
        duration: Double? = 600.0,
        width: Int? = 1920,
        height: Int? = 1080,
        markers: List<Double> = emptyList(),
        random: Random = Random(1),
    ) = FeedStartPosition.compute(setting, duration, width, height, markers, random)

    @Test fun settingRawValuesAndDefault() {
        assertEquals(listOf("firstMarker", "skip30", "random"), FeedsSceneStartPosition.entries.map { it.raw })
        assertEquals(listOf("First Marker", "Skip 30s", "Random"), FeedsSceneStartPosition.entries.map { it.label })
        assertEquals(FirstMarker, FeedsSceneStartPosition.from(null))
        assertEquals(FirstMarker, FeedsSceneStartPosition.from("bogus"))
        assertEquals(RandomStart, FeedsSceneStartPosition.from("random"))
    }

    @Test fun firstMarkerUsesEarliestMarker() {
        assertEquals(95.0, start(FirstMarker, markers = listOf(300.0, 95.0, 180.0)), 1e-9)
    }

    @Test fun firstMarkerAtZeroStartsAtZero() {
        assertEquals(0.0, start(FirstMarker, markers = listOf(0.0, 60.0)), 1e-9)
    }

    @Test fun firstMarkerWithoutMarkersSkips30() {
        assertEquals(30.0, start(FirstMarker), 1e-9)
        assertEquals(30.0, start(FirstMarker, markers = listOf(-1.0)), 1e-9)
    }

    @Test fun skip30() {
        assertEquals(30.0, start(Skip30, markers = listOf(95.0)), 1e-9)
    }

    @Test fun randomStaysInFirstHalf() {
        val rng = Random(42)
        repeat(1_000) {
            val s = start(RandomStart, duration = 600.0, random = rng)
            assertTrue("start $s", s >= 0.0 && s < 300.0)
        }
    }

    @Test fun randomIsDeterministicForSeed() {
        val expected = Random(7).nextDouble() * 600.0 * 0.5
        assertEquals(expected, start(RandomStart, duration = 600.0, random = Random(7)), 1e-9)
    }

    @Test fun verticalAndSquareStartAtZero() {
        assertEquals(0.0, start(Skip30, width = 1080, height = 1920), 1e-9)
        assertEquals(0.0, start(FirstMarker, width = 1080, height = 1080, markers = listOf(90.0)), 1e-9)
        assertEquals(0.0, start(RandomStart, width = 720, height = 1280), 1e-9)
    }

    @Test fun unknownSizeIsNotTreatedAsVertical() {
        assertEquals(30.0, start(Skip30, width = null, height = null), 1e-9)
        assertEquals(30.0, start(Skip30, width = 0, height = 0), 1e-9)
    }

    @Test fun shortOrUnknownDurationStartsAtZero() {
        assertEquals(0.0, start(Skip30, duration = 119.9), 1e-9)
        assertEquals(0.0, start(FirstMarker, duration = 90.0, markers = listOf(20.0)), 1e-9)
        assertEquals(0.0, start(Skip30, duration = null), 1e-9)
        assertEquals(0.0, start(Skip30, duration = 0.0), 1e-9)
        // Exactly two minutes is long enough.
        assertEquals(30.0, start(Skip30, duration = 120.0), 1e-9)
    }

    @Test fun startTooCloseToEndFallsBackToZero() {
        assertEquals(0.0, start(FirstMarker, duration = 200.0, markers = listOf(195.0)), 1e-9)
        assertEquals(0.0, start(FirstMarker, duration = 200.0, markers = listOf(250.0)), 1e-9)
        assertEquals(194.9, start(FirstMarker, duration = 200.0, markers = listOf(194.9)), 1e-9)
    }

    @Test fun forSceneReadsFileAndMarkers() {
        val scene = Scene(
            id = "s1",
            files = listOf(SceneFile(width = 1920, height = 1080, duration = 900.0)),
            sceneMarkers = listOf(SceneMarker(id = "a", seconds = 400.0), SceneMarker(id = "b", seconds = 125.0)),
        )
        assertEquals(125.0, FeedStartPosition.forScene(scene, FirstMarker), 1e-9)
        assertEquals(30.0, FeedStartPosition.forScene(scene.copy(sceneMarkers = null), FirstMarker), 1e-9)
        val vertical = scene.copy(files = listOf(SceneFile(width = 1080, height = 1920, duration = 900.0)))
        assertEquals(0.0, FeedStartPosition.forScene(vertical, FirstMarker), 1e-9)
    }
}
