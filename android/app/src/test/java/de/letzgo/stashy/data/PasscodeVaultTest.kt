package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PasscodeVaultTest {
    private class MemoryStore : SecurityStore {
        val secrets = mutableMapOf<String, String>()
        val values = mutableMapOf<String, Any>()
        override fun secret(key: String) = secrets[key]
        override fun setSecret(key: String, value: String?) { if (value == null) secrets.remove(key) else secrets[key] = value }
        override fun int(key: String) = values[key] as? Int ?: 0
        override fun setInt(key: String, value: Int) { values[key] = value }
        override fun double(key: String) = values[key] as? Double ?: 0.0
        override fun setDouble(key: String, value: Double) { values[key] = value }
        override fun has(key: String) = key in values
        override fun remove(key: String) { values.remove(key) }
    }

    private lateinit var store: MemoryStore
    private var now = 1_000_000.0
    private lateinit var vault: PasscodeVault

    @Before fun setUp() {
        store = MemoryStore()
        now = 1_000_000.0
        vault = PasscodeVault(store) { now }
    }

    @Test fun sha256MatchesKnownVector() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", PasscodeVault.sha256Hex("abc"))
    }

    @Test fun storesSaltedHashInIosFormat() {
        assertTrue(vault.setPasscode("1234", salt = "SALT"))
        assertEquals("v1:SALT:${PasscodeVault.sha256Hex("1234:SALT")}", store.secrets[PasscodeVault.PASSCODE_KEY])
        assertTrue(vault.hasPasscode)
    }

    @Test fun rejectsInvalidPins() {
        assertFalse(vault.setPasscode("123"))
        assertFalse(vault.setPasscode("12a4"))
        assertFalse(vault.setPasscode("12345"))
        assertFalse(vault.hasPasscode)
    }

    @Test fun verifiesCorrectAndWrongPin() {
        vault.setPasscode("4711")
        assertFalse(vault.verify("0000"))
        assertEquals(1, vault.failedAttempts)
        assertTrue(vault.verify("4711"))
        assertEquals(0, vault.failedAttempts)
    }

    @Test fun locksOutAfterFiveFailuresWithProgressiveDelays() {
        vault.setPasscode("4711")
        repeat(4) { assertFalse(vault.verify("0000")) }
        assertEquals(0, vault.lockoutRemainingSeconds())
        assertFalse(vault.verify("0000"))
        assertEquals(30, vault.lockoutRemainingSeconds())
        // Even the right PIN is refused while locked out.
        assertFalse(vault.verify("4711"))
        now += 31
        assertEquals(0, vault.lockoutRemainingSeconds())
        repeat(5) { vault.verify("0000") }
        assertEquals(60, vault.lockoutRemainingSeconds())
    }

    @Test fun lockoutCapsAtFifteenMinutes() {
        vault.setPasscode("4711")
        for (tier in 1..7) {
            repeat(5) { vault.verify("0000") }
            val expected = PasscodeVault.lockoutDelays[minOf(tier, 5) - 1].toInt()
            assertEquals(expected, vault.lockoutRemainingSeconds())
            now += expected + 1
        }
    }

    @Test fun removingClearsEverything() {
        vault.setPasscode("4711")
        vault.verify("0000")
        vault.removePasscode()
        assertFalse(vault.hasPasscode)
        assertNull(vault.record())
        assertEquals(0, vault.failedAttempts)
    }

    @Test fun ignoresMalformedRecords() {
        store.secrets[PasscodeVault.PASSCODE_KEY] = "garbage"
        assertNull(vault.record())
        store.secrets[PasscodeVault.PASSCODE_KEY] = "v1::abc"
        assertNull(vault.record())
    }
}
