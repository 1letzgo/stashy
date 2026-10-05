package de.letzgo.stashy.ui.player

import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneFile
import de.letzgo.stashy.data.Studio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SceneNowPlayingTest {
    private val full = Scene(
        id = "1",
        title = "Sunset",
        date = "2024-03-07",
        studio = Studio(id = "s", name = "Acme Studio"),
        performers = listOf(Performer(id = "a", name = "Alice"), Performer(id = "b", name = " Bob "), Performer(id = "c", name = "")),
    )

    @Test fun mapsTitlePerformersStudioAndArtwork() {
        val np = SceneNowPlaying.of(full, artworkUrl = "https://stash.local/scene/1/screenshot?width=640")
        assertEquals("Sunset", np.title)
        assertEquals("Alice, Bob", np.performers)
        assertEquals("Acme Studio", np.studio)
        assertEquals("Alice, Bob · Acme Studio", np.artist)
        assertEquals("https://stash.local/scene/1/screenshot?width=640", np.artworkUrl)
        assertEquals(Triple<Int?, Int?, Int?>(2024, 3, 7), np.releaseDate)
    }

    @Test fun titleFallsBackToFileName() {
        val scene = Scene(id = "2", title = "  ", files = listOf(SceneFile(path = "/media/clips/My Clip.mp4")))
        assertEquals("My Clip", SceneNowPlaying.of(scene, artworkUrl = null).title)
    }

    @Test fun artistLineUsesWhicheverPartExists() {
        assertEquals("Acme Studio", SceneNowPlaying.of(full.copy(performers = emptyList()), null).artist)
        assertEquals("Alice, Bob", SceneNowPlaying.of(full.copy(studio = null), null).artist)
        val bare = SceneNowPlaying.of(full.copy(studio = Studio(id = "s", name = " "), performers = emptyList()), artworkUrl = " ")
        assertNull(bare.artist)
        assertNull(bare.studio)
        assertNull(bare.artworkUrl)
    }

    @Test fun releaseDateToleratesPartialAndInvalidDates() {
        assertEquals(Triple<Int?, Int?, Int?>(2020, null, null), SceneNowPlaying.of(full.copy(date = "2020"), null).releaseDate)
        assertEquals(Triple<Int?, Int?, Int?>(2020, 5, null), SceneNowPlaying.of(full.copy(date = "2020-05"), null).releaseDate)
        assertNull(SceneNowPlaying.of(full.copy(date = "garbage"), null).releaseDate)
        assertNull(SceneNowPlaying.of(full.copy(date = null), null).releaseDate)
    }

    @Test fun buildsMediaMetadata() {
        val md = SceneNowPlaying.of(full, artworkUrl = null).toMediaMetadata()
        assertEquals("Sunset", md.title)
        assertEquals("Alice, Bob · Acme Studio", md.artist)
        assertEquals("Alice, Bob", md.albumArtist)
        assertEquals("Acme Studio", md.albumTitle)
        assertEquals(2024, md.releaseYear)
        assertEquals(3, md.releaseMonth)
        assertEquals(7, md.releaseDay)
    }
}
