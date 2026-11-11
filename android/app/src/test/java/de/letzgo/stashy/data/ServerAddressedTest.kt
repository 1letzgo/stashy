package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ServerAddressedTest {
    private fun config(local: String?, address: String = "stash.example.com", port: String? = null, proto: ServerProtocol = ServerProtocol.HTTPS, sub: String? = null) =
        ServerConfig(id = "T", serverAddress = address, port = port, serverProtocol = proto, subpath = sub, localURL = local)

    @Test fun externalToLocalKeepsPathAndQuery() {
        val c = config("http://192.168.1.10:9999")
        assertEquals("http://192.168.1.10:9999/scene/5/screenshot?width=640&t=1", c.addressed("https://stash.example.com/scene/5/screenshot?width=640&t=1", toLocal = true))
    }

    @Test fun localToExternalIsCanonical() {
        val c = config("http://192.168.1.10:9999")
        assertEquals("https://stash.example.com/performer/2/image", c.canonicalAddressed("http://192.168.1.10:9999/performer/2/image"))
    }

    @Test fun subpathOnExternalSideOnly() {
        val c = config("http://192.168.1.10:9999", sub = "/stash")
        assertEquals("http://192.168.1.10:9999/scene/1/stream", c.addressed("https://stash.example.com/stash/scene/1/stream", true))
        assertEquals("https://stash.example.com/stash/scene/1/stream", c.addressed("http://192.168.1.10:9999/scene/1/stream", false))
    }

    @Test fun subpathOnLocalSideOnly() {
        val c = config("http://nas.local/stash")
        assertEquals("http://nas.local/stash/scene/1/stream?x=1", c.addressed("https://stash.example.com/scene/1/stream?x=1", true))
        assertEquals("https://stash.example.com/scene/1/stream?x=1", c.addressed("http://nas.local/stash/scene/1/stream?x=1", false))
    }

    @Test fun subpathOnBothSides() {
        val c = config("http://nas.local:9999/s", sub = "/stash")
        assertEquals("http://nas.local:9999/s/graphql", c.addressed("https://stash.example.com/stash/graphql", true))
        assertEquals("https://stash.example.com/stash/graphql", c.addressed("http://nas.local:9999/s/graphql", false))
    }

    @Test fun portMismatchIsLeftAlone() {
        val c = config("http://192.168.1.10:9999", address = "stash.example.com", port = "8443")
        assertEquals("https://stash.example.com:9000/a", c.addressed("https://stash.example.com:9000/a", true))
        assertEquals("http://192.168.1.10:9999/a", c.addressed("https://stash.example.com:8443/a", true))
    }

    @Test fun defaultPortCountsAsNoPort() {
        val c = config("http://192.168.1.10:9999")
        assertEquals("http://192.168.1.10:9999/a", c.addressed("https://stash.example.com:443/a", true))
    }

    @Test fun unrelatedHostAndMissingLocalUntouched() {
        val c = config("http://192.168.1.10:9999")
        assertEquals("https://cdn.example.org/x.png", c.addressed("https://cdn.example.org/x.png", true))
        assertEquals("https://stash.example.com/x", config(null).addressed("https://stash.example.com/x", true))
    }

    @Test fun urlOutsideSubpathIsLeftAlone() {
        val c = config("http://192.168.1.10:9999", sub = "/stash")
        assertEquals("https://stash.example.com/other/x", c.addressed("https://stash.example.com/other/x", true))
    }

    @Test fun activeAddressedFollowsSelector() {
        val c = config("http://192.168.1.10:9999")
        try {
            ServerEndpointSelector.set("T")
            assertEquals("http://192.168.1.10:9999/a", c.activeAddressed("https://stash.example.com/a"))
            assertEquals("http://192.168.1.10:9999", c.baseURL)
            ServerEndpointSelector.set(null)
            assertEquals("https://stash.example.com/a", c.activeAddressed("http://192.168.1.10:9999/a"))
            assertEquals("https://stash.example.com", c.baseURL)
        } finally { ServerEndpointSelector.set(null) }
    }

    @Test fun normalizeLocalInput() {
        assertEquals("http://192.168.1.100:9999", ServerAddress.normalizeLocal(" 192.168.1.100:9999/ "))
        assertEquals("https://nas.local/stash", ServerAddress.normalizeLocal("HTTPS://nas.local/stash/"))
        assertEquals(null, ServerAddress.normalizeLocal("   "))
    }
}
