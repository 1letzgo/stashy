package de.letzgo.stashy.data

import okhttp3.Call
import okhttp3.Dns
import okhttp3.EventListener
import okhttp3.Protocol
import java.io.IOException
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.ConcurrentHashMap

/**
 * Address ordering for connects (RFC 8305 §4, what iOS URLSession does internally).
 *
 * OkHttp 4 tried the resolved addresses strictly in order: a domain with AAAA records on a
 * network whose IPv6 path is broken sat on each IPv6 address until the connect timeout before
 * reaching IPv4 — the "spinner for a minute after launch, then everything loads" pattern.
 * OkHttp 5's fast fallback ([Net]) races the families itself; this ordering is the sequential
 * fallback, and `ipv6Broken` drops IPv6 for a host whose IPv6 path just failed so new
 * connections don't even start the doomed attempt.
 */
object AddressOrder {
    /**
     * Interleaves IPv6 and IPv4 (v6, v4, v6, v4, …), keeping the resolver's order inside each
     * family and starting with the family the resolver put first. With [ipv6Broken], only the
     * IPv4 addresses are returned (all addresses when there is no IPv4 at all).
     */
    fun order(addresses: List<InetAddress>, ipv6Broken: Boolean): List<InetAddress> {
        val distinct = addresses.distinct()
        val (v6, v4) = distinct.partition { it is Inet6Address }
        if (v6.isEmpty() || v4.isEmpty()) return distinct
        if (ipv6Broken) return v4
        val (first, second) = if (distinct.first() is Inet6Address) v6 to v4 else v4 to v6
        val out = ArrayList<InetAddress>(distinct.size)
        for (i in 0 until maxOf(first.size, second.size)) {
            first.getOrNull(i)?.let(out::add)
            second.getOrNull(i)?.let(out::add)
        }
        return out
    }
}

/**
 * System DNS plus per-host memory of a broken IPv6 path: once an IPv6 connect to a host fails,
 * that host resolves to its IPv4 addresses only for [ipv6PenaltyMs]. Cleared on a network change
 * ([forgetFailures]), on an IPv6 success, and when IPv4 fails too (then IPv6 may be the only
 * working path). Logs resolution time through [log] (DEBUG builds only).
 */
class StashDns(
    private val system: Dns = Dns.SYSTEM,
    private val ipv6PenaltyMs: Long = 10 * 60_000L,
    private val now: () -> Long = System::currentTimeMillis,
    private val log: ((String) -> Unit)? = null,
) : Dns {
    private val ipv6FailedAt = ConcurrentHashMap<String, Long>()

    override fun lookup(hostname: String): List<InetAddress> {
        val start = System.nanoTime()
        val resolved = try {
            system.lookup(hostname)
        } catch (e: IOException) {
            log?.invoke("dns $hostname failed after ${elapsedMs(start)} ms: ${e.javaClass.simpleName}")
            throw e
        }
        val ipv6Broken = ipv6RecentlyFailed(hostname)
        val ordered = AddressOrder.order(resolved, ipv6Broken)
        log?.invoke(
            "dns $hostname ${elapsedMs(start)} ms → ${ordered.joinToString { it.hostAddress ?: "?" }}" +
                if (ordered.size < resolved.distinct().size) " (IPv6 skipped: failed recently)" else "",
        )
        return ordered
    }

    fun ipv6RecentlyFailed(host: String): Boolean {
        val key = host.lowercase()
        val failedAt = ipv6FailedAt[key] ?: return false
        if (now() - failedAt < ipv6PenaltyMs) return true
        ipv6FailedAt.remove(key, failedAt)
        return false
    }

    fun noteConnectFailed(host: String, address: InetAddress?) {
        when (address) {
            null -> Unit
            is Inet6Address -> ipv6FailedAt[host.lowercase()] = now()
            // IPv4 is failing too: IPv6 may be the only working path, so stop skipping it.
            else -> ipv6FailedAt.remove(host.lowercase())
        }
    }

    fun noteConnected(host: String, address: InetAddress?) {
        if (address is Inet6Address) ipv6FailedAt.remove(host.lowercase())
    }

    fun forgetFailures() = ipv6FailedAt.clear()

    private fun elapsedMs(startNanos: Long) = (System.nanoTime() - startNanos) / 1_000_000
}

/**
 * Feeds connect results back into [StashDns] and, in DEBUG builds, logs connect time per host
 * and address (fast fallback runs several attempts per call, hence the per-address map).
 * One instance per call.
 */
class NetEventListener(private val dns: StashDns, private val log: ((String) -> Unit)?) : EventListener() {
    private val connectStarts = ConcurrentHashMap<InetSocketAddress, Long>()
    @Volatile private var callStart = System.nanoTime()

    override fun callStart(call: Call) { callStart = System.nanoTime() }

    override fun connectStart(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy) {
        connectStarts[inetSocketAddress] = System.nanoTime()
    }

    override fun connectEnd(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy, protocol: Protocol?) {
        val started = connectStarts.remove(inetSocketAddress)
        dns.noteConnected(call.request().url.host, inetSocketAddress.address)
        log?.invoke("connect ${call.request().url.host} ${inetSocketAddress.address?.hostAddress} ok in ${since(started)} ms ($protocol)")
    }

    override fun connectFailed(call: Call, inetSocketAddress: InetSocketAddress, proxy: Proxy, protocol: Protocol?, ioe: IOException) {
        val started = connectStarts.remove(inetSocketAddress)
        // A cancelled call says nothing about the path. (An IPv6 attempt that lost the fast-fallback
        // race to IPv4 does count: IPv4 is the better path then, and an IPv4 failure undoes it.)
        if (!call.isCanceled()) dns.noteConnectFailed(call.request().url.host, inetSocketAddress.address)
        log?.invoke("connect ${call.request().url.host} ${inetSocketAddress.address?.hostAddress} FAILED after ${since(started)} ms: ${ioe.javaClass.simpleName}")
    }

    override fun callFailed(call: Call, ioe: IOException) {
        log?.invoke("call ${call.request().url.host}${call.request().url.encodedPath} failed after ${since(callStart)} ms: ${ioe.javaClass.simpleName}")
    }

    private fun since(startNanos: Long?) = startNanos?.let { (System.nanoTime() - it) / 1_000_000 } ?: -1
}
