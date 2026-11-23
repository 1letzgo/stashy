package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeepLinkTest {
    private fun ok(raw: String): DeepLink = (DeepLink.parse(raw) as DeepLink.Result.Ok).link
    private fun error(raw: String?): DeepLink.Error = (DeepLink.parse(raw) as DeepLink.Result.Failed).error

    @Test fun sceneWithoutTime() {
        val link = ok("stashy://scene/1234")
        assertEquals(DeepLink.Target.Scene("1234"), link.target)
        assertNull(link.time)
        assertNull(link.server)
    }

    @Test fun sceneWithWholeAndDecimalTime() {
        assertEquals(754.0, ok("stashy://scene/1234?t=754").time!!, 0.0)
        assertEquals(754.5, ok("stashy://scene/1234?t=754.5").time!!, 0.0)
        assertEquals(0.0, ok("stashy://scene/1234?t=0").time!!, 0.0)
    }

    @Test fun invalidTimeCountsAsAbsent() {
        listOf("-3", "abc", "", "1e3", "NaN", "Infinity", "12s", "1.2.3", " ").forEach { t ->
            val link = ok("stashy://scene/1234?t=$t")
            assertEquals(DeepLink.Target.Scene("1234"), link.target)
            assertNull("t=$t", link.time)
        }
    }

    @Test fun marker() {
        val plain = ok("stashy://marker/567")
        assertEquals(DeepLink.Target.Marker("567"), plain.target)
        assertNull(plain.time)
        assertEquals(12.25, ok("stashy://marker/567?t=12.25").time!!, 0.0)
    }

    @Test fun serverParameter() {
        assertEquals("My Stash", ok("stashy://scene/1?server=My%20Stash").server)
        assertEquals("https://stash.example.com:9999/", ok("stashy://scene/1?t=5&server=https://stash.example.com:9999/").server)
        assertEquals("https://stash.example.com", ok("stashy://scene/1?server=https%3A%2F%2Fstash.example.com&t=5").server)
        assertNull(ok("stashy://scene/1?server=").server)
        assertNull(ok("stashy://scene/1?server=%20").server)
    }

    @Test fun caseAndSlashVariants() {
        assertEquals(DeepLink.Target.Scene("9"), ok("STASHY://Scene/9").target)
        assertEquals(DeepLink.Target.Scene("5"), ok("stashy:///scene/5").target)
        assertEquals(DeepLink.Target.Scene("5"), ok("stashy://scene/5/").target)
        assertEquals(DeepLink.Target.Scene("5"), ok("stashy:scene/5").target)
        assertEquals(3.0, ok("stashy://scene/5?T=3").time!!, 0.0)
    }

    @Test fun badIds() {
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene/"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene/abc"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene/12a"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene/-12"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://scene/1/2"))
        assertEquals(DeepLink.Error.InvalidId, error("stashy://marker/x?t=4"))
    }

    @Test fun garbage() {
        assertEquals(DeepLink.Error.UnknownPath, error("stashy://foo/1"))
        assertEquals(DeepLink.Error.UnknownPath, error("stashy://"))
        assertEquals(DeepLink.Error.UnknownPath, error("stashy://performer/3"))
        assertEquals(DeepLink.Error.WrongScheme, error("https://scene/1"))
        assertEquals(DeepLink.Error.WrongScheme, error("stash://scene/1"))
        assertEquals(DeepLink.Error.WrongScheme, error("not a url"))
        assertEquals(DeepLink.Error.WrongScheme, error(""))
        assertEquals(DeepLink.Error.WrongScheme, error(null))
    }

    @Test fun clampsToDuration() {
        assertEquals(599.0, DeepLink.clamp(5000.0, 600.0), 0.0)
        assertEquals(30.0, DeepLink.clamp(30.0, 600.0), 0.0)
        assertEquals(30.0, DeepLink.clamp(30.0, null), 0.0)
        assertEquals(0.0, DeepLink.clamp(5.0, 0.5), 0.0)
    }

    @Test fun matchesServerByName() {
        assertTrue(DeepLink.serverMatches("my stash", "My Stash", emptyList()))
        assertTrue(DeepLink.serverMatches("  My Stash ", "My Stash", emptyList()))
        assertFalse(DeepLink.serverMatches("Other", "My Stash", emptyList()))
        assertFalse(DeepLink.serverMatches("", "My Stash", emptyList()))
    }

    @Test fun matchesServerByAddress() {
        val addresses = listOf("https://stash.example.com", "http://192.168.1.10:9999")
        assertTrue(DeepLink.serverMatches("https://stash.example.com", "x", addresses))
        assertTrue(DeepLink.serverMatches("HTTPS://Stash.Example.com/", "x", addresses))
        assertTrue(DeepLink.serverMatches("https://stash.example.com:443", "x", addresses))
        // The local address counts too, and a value without a scheme matches either scheme.
        assertTrue(DeepLink.serverMatches("http://192.168.1.10:9999/", "x", addresses))
        assertTrue(DeepLink.serverMatches("192.168.1.10:9999", "x", addresses))
        assertTrue(DeepLink.serverMatches("stash.example.com", "x", addresses))
        assertFalse(DeepLink.serverMatches("http://stash.example.com", "x", addresses))
        assertFalse(DeepLink.serverMatches("https://other.example.com", "x", addresses))
        assertFalse(DeepLink.serverMatches("http://192.168.1.10:8888", "x", addresses))
    }

    @Test fun matchesServerWithSubpath() {
        val addresses = listOf("https://host.example.com/stash")
        assertTrue(DeepLink.serverMatches("https://host.example.com/stash/", "x", addresses))
        assertFalse(DeepLink.serverMatches("https://host.example.com", "x", addresses))
    }

    // Consecutive links: previous link / page in front × new link (the player state does not
    // change the route; the page applies the start whether it is not started, playing or paused).

    @Test fun nothingInFrontOpensAPage() {
        assertEquals(DeepLink.Route.Open(autoPlay = true, startAt = 60.0), DeepLink.route("1", 60.0, null))
        assertEquals(DeepLink.Route.Open(autoPlay = false, startAt = null), DeepLink.route("1", null, null))
    }

    @Test fun sameSceneInFrontStaysAndSeeksOnlyWithATime() {
        // scene/1?t=… or scene/1 (or marker on 1) before, now scene/1?t=60.5 or marker/1(?t=30)
        assertEquals(DeepLink.Route.InPlace(60.5), DeepLink.route("1", 60.5, "1"))
        assertEquals(DeepLink.Route.InPlace(30.0), DeepLink.route("1", 30.0, "1"))
        assertEquals(DeepLink.Route.InPlace(319.0), DeepLink.route("1", 319.0, "1"))
        // scene/1 without t while scene 1 is on top: nothing changes.
        assertEquals(DeepLink.Route.InPlace(null), DeepLink.route("1", null, "1"))
    }

    @Test fun otherSceneInFrontOpensOneFreshPage() {
        // scene/2 on top, now scene/1(?t) or marker on 1
        assertEquals(DeepLink.Route.Open(autoPlay = true, startAt = 319.0), DeepLink.route("1", 319.0, "2"))
        assertEquals(DeepLink.Route.Open(autoPlay = false, startAt = null), DeepLink.route("1", null, "2"))
        // scene/1 on top, now scene/2
        assertEquals(DeepLink.Route.Open(autoPlay = false, startAt = null), DeepLink.route("2", null, "1"))
        assertEquals(DeepLink.Route.Open(autoPlay = true, startAt = 0.0), DeepLink.route("2", 0.0, "1"))
    }

    @Test fun startTimeIsUsedOnce() {
        val start = OnceStart(42.5)
        assertEquals(42.5, start.take()!!, 0.0)
        assertNull(start.take())
        assertNull(OnceStart(null).take())
    }
}
