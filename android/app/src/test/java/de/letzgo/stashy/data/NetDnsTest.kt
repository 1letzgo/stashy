package de.letzgo.stashy.data

import okhttp3.Dns
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.UnknownHostException

class NetDnsTest {
    private fun ip(literal: String): InetAddress = InetAddress.getByName(literal) // literals never hit DNS
    private val v6a = ip("2001:db8::1")
    private val v6b = ip("2001:db8::2")
    private val v4a = ip("203.0.113.1")
    private val v4b = ip("203.0.113.2")

    @Test fun interleavesStartingWithResolversFirstFamily() {
        assertEquals(listOf(v6a, v4a, v6b, v4b), AddressOrder.order(listOf(v6a, v6b, v4a, v4b), ipv6Broken = false))
        assertEquals(listOf(v4a, v6a, v4b, v6b), AddressOrder.order(listOf(v4a, v4b, v6a, v6b), ipv6Broken = false))
    }

    @Test fun unevenFamiliesKeepTheRemainderAtTheEnd() {
        assertEquals(listOf(v6a, v4a, v6b), AddressOrder.order(listOf(v6a, v6b, v4a), ipv6Broken = false))
    }

    @Test fun singleFamilyAndDuplicatesUnchanged() {
        assertEquals(listOf(v4a, v4b), AddressOrder.order(listOf(v4a, v4b, v4a), ipv6Broken = false))
        assertEquals(listOf(v6a, v6b), AddressOrder.order(listOf(v6a, v6b), ipv6Broken = true))
        assertEquals(emptyList<InetAddress>(), AddressOrder.order(emptyList(), ipv6Broken = true))
    }

    @Test fun brokenIPv6DropsIPv6WhenIPv4Exists() {
        assertEquals(listOf(v4a, v4b), AddressOrder.order(listOf(v6a, v4a, v6b, v4b), ipv6Broken = true))
    }

    private class FakeDns(var answer: List<InetAddress>) : Dns {
        override fun lookup(hostname: String) = answer
    }

    @Test fun ipv6FailureSkipsIPv6ForThatHostUntilPenaltyExpires() {
        var clock = 0L
        val dns = StashDns(FakeDns(listOf(v6a, v4a)), ipv6PenaltyMs = 1_000, now = { clock })
        assertEquals(listOf(v6a, v4a), dns.lookup("stash.example.com"))

        dns.noteConnectFailed("Stash.Example.com", v6a)
        assertEquals(listOf(v4a), dns.lookup("stash.example.com"))
        assertEquals(listOf(v6a, v4a), dns.lookup("other.example.com"))

        clock = 1_000
        assertFalse(dns.ipv6RecentlyFailed("stash.example.com"))
        assertEquals(listOf(v6a, v4a), dns.lookup("stash.example.com"))
    }

    @Test fun ipv4FailureOrIPv6SuccessOrNetworkChangeRestoresIPv6() {
        val dns = StashDns(FakeDns(listOf(v6a, v4a)), now = { 0L })
        dns.noteConnectFailed("h", v6a); dns.noteConnectFailed("h", v4a)
        assertFalse(dns.ipv6RecentlyFailed("h"))

        dns.noteConnectFailed("h", v6a); assertTrue(dns.ipv6RecentlyFailed("h"))
        dns.noteConnected("h", v6a); assertFalse(dns.ipv6RecentlyFailed("h"))

        dns.noteConnectFailed("h", v6a); dns.forgetFailures()
        assertFalse(dns.ipv6RecentlyFailed("h"))

        dns.noteConnectFailed("h", v6a); dns.noteConnected("h", v4a)
        assertTrue("an IPv4 success says nothing about IPv6", dns.ipv6RecentlyFailed("h"))
    }

    @Test(expected = UnknownHostException::class)
    fun resolverErrorsPropagate() {
        StashDns(object : Dns { override fun lookup(hostname: String) = throw UnknownHostException(hostname) }).lookup("nope")
    }
}
