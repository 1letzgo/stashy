package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class LicenseKeyTest {
    private val now = 20_384L * License.DAY_MS // 2025-10-23

    // MARK: - Throwaway key pair + an encoder mirroring tools/stashy-keygen.py

    private fun keyPair(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    private fun derToRaw(der: ByteArray): ByteArray {
        var pos = 2
        fun int(): ByteArray {
            require(der[pos].toInt() == 0x02)
            val len = der[pos + 1].toInt()
            val v = der.copyOfRange(pos + 2, pos + 2 + len)
            pos += 2 + len
            val bytes = BigInteger(1, v).toByteArray().let { if (it.size > 32) it.copyOfRange(it.size - 32, it.size) else it }
            return ByteArray(32 - bytes.size) + bytes
        }
        return int() + int()
    }

    private fun base32(data: ByteArray): String {
        val alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        val sb = StringBuilder()
        var bits = 0
        var value = 0
        for (b in data) {
            value = (value shl 8) or (b.toInt() and 0xFF)
            bits += 8
            while (bits >= 5) { bits -= 5; sb.append(alphabet[(value shr bits) and 31]) }
            value = value and 0xFF
        }
        if (bits > 0) sb.append(alphabet[(value shl (5 - bits)) and 31])
        return sb.toString()
    }

    private fun issue(pair: KeyPair, name: String, issued: Int = 20_384, expires: Int = 0, id: String = "ABCD1234"): String {
        val out = ByteArrayOutputStream()
        out.write(1)
        out.write(issued shr 8); out.write(issued and 0xFF)
        out.write(expires shr 8); out.write(expires and 0xFF)
        id.toByteArray().let { out.write(it.size); out.write(it) }
        name.toByteArray().let { out.write(it.size); out.write(it) }
        val payload = out.toByteArray()
        val sig = Signature.getInstance("SHA256withECDSA").apply { initSign(pair.private); update(payload) }.sign()
        return "STASHY-" + base32(payload + derToRaw(sig)).chunked(5).joinToString("-")
    }

    private fun resource(name: String) = javaClass.classLoader!!.getResource("license/$name")!!.readText().trim()

    // MARK: - Tests

    @Test fun validKeyVerifies() {
        val pair = keyPair()
        val r = LicenseKey.verify(issue(pair, "Jane Doe"), now, pair.public)
        assertTrue(r is LicenseKey.Result.Valid)
        val l = (r as LicenseKey.Result.Valid).license
        assertEquals("Jane Doe", l.name)
        assertEquals("ABCD1234", l.id)
        assertNull(l.expiresDay)
    }

    @Test fun tamperedKeyIsRejected() {
        val pair = keyPair()
        val key = issue(pair, "Jane Doe")
        // Change one data character inside the payload (the holder name).
        val i = 31
        val swapped = key.substring(0, i) + (if (key[i] == 'Z') 'Y' else 'Z') + key.substring(i + 1)
        assertTrue(LicenseKey.verify(swapped, now, pair.public) is LicenseKey.Result.Invalid)
        // Truncated / extended keys.
        assertTrue(LicenseKey.verify(key.dropLast(3), now, pair.public) is LicenseKey.Result.Invalid)
        assertTrue(LicenseKey.verify(key + "-00000", now, pair.public) is LicenseKey.Result.Invalid)
        assertTrue(LicenseKey.verify("", now, pair.public) is LicenseKey.Result.Invalid)
        assertTrue(LicenseKey.verify("hello world", now, pair.public) is LicenseKey.Result.Invalid)
    }

    @Test fun wrongPublicKeyIsRejected() {
        val key = issue(keyPair(), "Jane Doe")
        assertTrue(LicenseKey.verify(key, now, keyPair().public) is LicenseKey.Result.Invalid)
    }

    @Test fun expiryIsInclusiveOfTheLastDay() {
        val pair = keyPair()
        val key = issue(pair, "Temp", expires = 20_384) // expires "today"
        assertTrue(LicenseKey.verify(key, now + License.DAY_MS - 1, pair.public) is LicenseKey.Result.Valid)
        val r = LicenseKey.verify(key, now + License.DAY_MS, pair.public)
        assertTrue(r is LicenseKey.Result.Expired)
        assertEquals("Temp", (r as LicenseKey.Result.Expired).license.name)
    }

    @Test fun pastedInputIsNormalised() {
        val pair = keyPair()
        val key = issue(pair, "Ünïcødé Name")
        val variants = listOf(
            key,
            key.lowercase(),
            key.removePrefix("STASHY-"),
            key.replace("-", ""),
            "  " + key.chunked(17).joinToString("\n ") + "\n",
            key.replace("-", " "),
            // Crockford look-alikes: 1 typed as I/L, 0 typed as O.
            key.replace('1', 'l').replace('0', 'O'),
        )
        for (v in variants) assertTrue(v, LicenseKey.verify(v, now, pair.public) is LicenseKey.Result.Valid)
        assertEquals("Ünïcødé Name", (LicenseKey.verify(key.lowercase(), now, pair.public) as LicenseKey.Result.Valid).license.name)
    }

    @Test fun rawSignatureConvertsToDer() {
        val raw = ByteArray(64) { if (it == 0 || it == 32) 0x80.toByte() else 1 }
        val der = LicenseKey.rawToDer(raw)
        assertEquals(0x30, der[0].toInt())
        assertEquals(der.size - 2, der[1].toInt())
        assertEquals(33, der[3].toInt()) // high bit set → leading zero byte
    }

    /** Keys produced by `tools/stashy-keygen.py` with a throwaway TEST key pair (not the app's key). */
    @Test fun pythonIssuedTestKeysVerify() {
        val pub = LicenseKey.publicKey(resource("test-public-key.txt"))
        val valid = LicenseKey.verify(resource("test-valid.txt"), now, pub)
        assertTrue(valid is LicenseKey.Result.Valid)
        assertEquals("Test", (valid as LicenseKey.Result.Valid).license.name)
        assertEquals("TEST0001", valid.license.id)

        val expiring = LicenseKey.verify(resource("test-valid-expiring.txt"), now, pub)
        assertTrue(expiring is LicenseKey.Result.Valid)
        assertEquals("Jane Doe <jane@example.com>", (expiring as LicenseKey.Result.Valid).license.name)
        assertEquals("31 Dec 2099", expiring.license.expiresText)

        val expired = LicenseKey.verify(resource("test-expired.txt"), now, pub)
        assertTrue(expired is LicenseKey.Result.Expired)
        assertEquals("30 Jun 2025", (expired as LicenseKey.Result.Expired).license.expiresText)
    }

    /** The test keys must not unlock the shipped app (signed by a different key pair). */
    @Test fun testKeysAreRejectedByTheEmbeddedPublicKey() {
        assertTrue(LicenseKey.verify(resource("test-valid.txt"), now) is LicenseKey.Result.Invalid)
    }
}
