package de.letzgo.stashy.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthAlertGateTest {
    @Test fun showsOncePerServerUntilReset() {
        val gate = AuthAlertGate()
        assertTrue(gate.shouldShow("A"))
        assertFalse(gate.shouldShow("A"))
        assertFalse(gate.shouldShow("A"))
        gate.reset()
        assertTrue(gate.shouldShow("A"))
    }

    @Test fun anotherServerAlertsAgain() {
        val gate = AuthAlertGate()
        assertTrue(gate.shouldShow("A"))
        assertTrue(gate.shouldShow("B"))
    }
}
