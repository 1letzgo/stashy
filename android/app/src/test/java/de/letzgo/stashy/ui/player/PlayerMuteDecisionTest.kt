package de.letzgo.stashy.ui.player

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerMuteDecisionTest {
    @Test fun speakerWithSettingOnAlwaysStartsMuted() {
        assertTrue(PlayerMute.decide(headphonesConnected = false, muteWithoutHeadphones = true, storedMuted = null))
        assertTrue(PlayerMute.decide(headphonesConnected = false, muteWithoutHeadphones = true, storedMuted = false))
    }

    @Test fun speakerWithSettingOffStartsWithSound() {
        assertFalse(PlayerMute.decide(headphonesConnected = false, muteWithoutHeadphones = false, storedMuted = null))
        assertFalse(PlayerMute.decide(headphonesConnected = false, muteWithoutHeadphones = false, storedMuted = false))
    }

    @Test fun manualMuteIsStillHonoured() {
        assertTrue(PlayerMute.decide(headphonesConnected = false, muteWithoutHeadphones = false, storedMuted = true))
        assertTrue(PlayerMute.decide(headphonesConnected = true, muteWithoutHeadphones = true, storedMuted = true))
    }

    @Test fun headphonesUseStoredChoiceDefaultingToSound() {
        assertFalse(PlayerMute.decide(headphonesConnected = true, muteWithoutHeadphones = true, storedMuted = null))
        assertFalse(PlayerMute.decide(headphonesConnected = true, muteWithoutHeadphones = false, storedMuted = false))
    }
}
