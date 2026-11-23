package de.letzgo.stashy.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLockPolicyTest {
    @Test fun locksWhenLeavingWithPasscodeAndAutoLock() {
        assertTrue(AppLockPolicy.locksOnBackground(passcodeSet = true, autoLockOnBackground = true, pipActive = false, changingConfigurations = false))
    }

    @Test fun autoLockOffNeverLocksOnBackground() {
        assertFalse(AppLockPolicy.locksOnBackground(passcodeSet = true, autoLockOnBackground = false, pipActive = false, changingConfigurations = false))
    }

    @Test fun noPasscodeNeverLocks() {
        assertFalse(AppLockPolicy.locksOnBackground(passcodeSet = false, autoLockOnBackground = true, pipActive = false, changingConfigurations = false))
    }

    @Test fun pictureInPictureKeepsItUnlocked() {
        assertFalse(AppLockPolicy.locksOnBackground(passcodeSet = true, autoLockOnBackground = true, pipActive = true, changingConfigurations = false))
    }

    @Test fun rotationIsNoLeaving() {
        assertFalse(AppLockPolicy.locksOnBackground(passcodeSet = true, autoLockOnBackground = true, pipActive = false, changingConfigurations = true))
    }

    @Test fun lockWindowIsThereAtOnceWhenLocking() {
        // Lock just went up, nothing drawn yet: the window must be added in this composition.
        assertTrue(AppLockPolicy.showsLockWindow(visibleNow = false, locked = true))
        assertTrue(AppLockPolicy.showsLockWindow(visibleNow = true, locked = true))
    }

    @Test fun lockWindowStaysForItsFadeOutThenGoes() {
        assertTrue(AppLockPolicy.showsLockWindow(visibleNow = true, locked = false))
        assertFalse(AppLockPolicy.showsLockWindow(visibleNow = false, locked = false))
    }

    @Test fun windowsAreSecureOnlyWhileTheAppLocksOnLeaving() {
        assertTrue(AppLockPolicy.securesWindows(passcodeSet = true, autoLockOnBackground = true))
        assertFalse(AppLockPolicy.securesWindows(passcodeSet = true, autoLockOnBackground = false))
        assertFalse(AppLockPolicy.securesWindows(passcodeSet = false, autoLockOnBackground = true))
        assertFalse(AppLockPolicy.securesWindows(passcodeSet = false, autoLockOnBackground = false))
    }
}
