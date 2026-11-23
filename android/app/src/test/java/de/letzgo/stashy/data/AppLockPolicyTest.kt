package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
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

    @Test fun safePaddingKeepsTheLockAboveTheGestureBar() {
        // 2400 px screen, status bar 128 px, gesture bar 63 px; lock window over the whole screen.
        assertEquals(128 to 63, AppLockPolicy.safePadding(windowStart = 0, windowSize = 2400, safeStart = 128, safeEnd = 2400 - 63))
    }

    @Test fun safePaddingFollowsAShiftedLockWindow() {
        // Lock window placed below the status bar but still 2400 px tall: no top padding, the overhang at the bottom is added.
        assertEquals(0 to 128 + 63, AppLockPolicy.safePadding(windowStart = 128, windowSize = 2400, safeStart = 128, safeEnd = 2337))
    }

    @Test fun safePaddingIsNeverNegative() {
        assertEquals(0 to 0, AppLockPolicy.safePadding(windowStart = 200, windowSize = 1000, safeStart = 100, safeEnd = 2000))
    }
}
