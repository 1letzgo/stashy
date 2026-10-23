package de.letzgo.stashy.data

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.Base64
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** A verified stashy+ license (sideload flavor). Dates are days since 1970-01-01, UTC. */
data class License(
    val id: String,
    val name: String,
    val issuedDay: Int,
    /** null = never expires; valid through the end of this day (UTC). */
    val expiresDay: Int?,
) {
    fun isExpired(nowMillis: Long): Boolean = expiresDay != null && nowMillis >= (expiresDay + 1L) * DAY_MS

    val expiresText: String? get() = expiresDay?.let { formatDay(it) }

    companion object {
        const val DAY_MS = 86_400_000L
        fun formatDay(day: Int): String = SimpleDateFormat("d MMM yyyy", Locale.ENGLISH)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(day * DAY_MS))
    }
}

/**
 * Offline license keys for the `sideload` flavor's stashy+ unlock, issued by
 * `tools/stashy-keygen.py` (format documented there). ECDSA P-256 / SHA-256 over a small binary
 * payload; the key text is Crockford base32 of `payload || r||s`, grouped as `STASHY-XXXXX-…`.
 * Pure Kotlin + java.security, so it runs in JVM unit tests.
 */
object LicenseKey {
    /** Public half of the key pair in ~/.stashy-license (base64 DER SubjectPublicKeyInfo). */
    const val PUBLIC_KEY =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEEPR3tLXCiX2KeSAB5G+0xVe57ArTiZIno9+38p2EnIAT/WmYkM+MHkZ3GhYr+D33KcIsMgwFii7NQoWpvz0cIw=="

    private const val VERSION = 1
    private const val SIG_LEN = 64
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    sealed interface Result {
        data class Valid(val license: License) : Result
        data class Expired(val license: License) : Result
        data class Invalid(val reason: String) : Result
    }

    val embeddedPublicKey: PublicKey by lazy { publicKey(PUBLIC_KEY) }

    fun publicKey(base64Der: String): PublicKey =
        KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(base64Der.trim())))

    /**
     * Candidate base32 bodies for pasted input: any case, whitespace and dashes ignored,
     * I/L read as 1 and O as 0, optional `STASHY` prefix (the stripped variant is tried first;
     * the unstripped one only matters if the data itself happened to start with those letters).
     */
    fun candidates(input: String): List<String> {
        val s = input.uppercase(Locale.ROOT).filterNot { it.isWhitespace() }
            .replace('I', '1').replace('L', '1').replace('O', '0')
        val out = mutableListOf<String>()
        if (s.startsWith("STASHY")) out += s.removePrefix("STASHY").replace("-", "")
        out += s.replace("-", "")
        return out.filter { it.isNotEmpty() }.distinct()
    }

    fun verify(input: String, nowMillis: Long, key: PublicKey = embeddedPublicKey): Result {
        var firstError: String? = null
        for (body in candidates(input)) {
            val license = runCatching { decodeAndVerify(body, key) }.getOrElse {
                if (firstError == null) firstError = it.message ?: "Invalid license key."
                null
            } ?: continue
            return if (license.isExpired(nowMillis)) Result.Expired(license) else Result.Valid(license)
        }
        return Result.Invalid(firstError ?: "Enter a license key.")
    }

    private fun decodeAndVerify(body: String, key: PublicKey): License {
        val blob = base32Decode(body)
        if (blob.size < 5 || blob[0].toInt() != VERSION) throw IllegalArgumentException("This is not a stashy license key.")
        val issued = u16(blob, 1)
        val expires = u16(blob, 3)
        var pos = 5
        val fields = ArrayList<String>(2)
        repeat(2) {
            if (pos >= blob.size) throw IllegalArgumentException("The license key is incomplete.")
            val n = blob[pos].toInt() and 0xFF
            pos++
            if (pos + n > blob.size) throw IllegalArgumentException("The license key is incomplete.")
            fields += String(blob, pos, n, Charsets.UTF_8)
            pos += n
        }
        if (blob.size - pos != SIG_LEN) throw IllegalArgumentException("The license key is incomplete.")
        val sig = Signature.getInstance("SHA256withECDSA")
        sig.initVerify(key)
        sig.update(blob, 0, pos)
        val ok = runCatching { sig.verify(rawToDer(blob.copyOfRange(pos, blob.size))) }.getOrDefault(false)
        if (!ok) throw IllegalArgumentException("This license key is not valid.")
        return License(fields[0], fields[1], issued, expires.takeIf { it != 0 })
    }

    private fun u16(b: ByteArray, at: Int) = ((b[at].toInt() and 0xFF) shl 8) or (b[at + 1].toInt() and 0xFF)

    fun base32Decode(text: String): ByteArray {
        val out = ByteArrayOutputStream()
        var bits = 0
        var value = 0
        for (ch in text) {
            val idx = ALPHABET.indexOf(ch)
            if (idx < 0) throw IllegalArgumentException("The license key contains invalid characters.")
            value = (value shl 5) or idx
            bits += 5
            if (bits >= 8) {
                bits -= 8
                out.write((value shr bits) and 0xFF)
            }
            value = value and 0xFF // keep only bits not yet emitted (at most 7 + 5 needed)
        }
        return out.toByteArray()
    }

    /** Raw r||s (2×32 bytes) → ASN.1 DER `SEQUENCE { INTEGER r, INTEGER s }` for java.security. */
    fun rawToDer(raw: ByteArray): ByteArray {
        require(raw.size == SIG_LEN)
        fun int(part: ByteArray): ByteArray {
            val v = BigInteger(1, part).toByteArray() // minimal two's complement, leading 0 if high bit set
            return byteArrayOf(0x02, v.size.toByte()) + v
        }
        val body = int(raw.copyOfRange(0, 32)) + int(raw.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }
}
