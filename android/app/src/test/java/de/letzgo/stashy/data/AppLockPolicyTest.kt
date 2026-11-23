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

    @Test fun pipRectangleSafeAreaIsClampedNotLaidOutInto() {
        // QA: content started at the PiP's x 440 / y 1494 px on a 1080 × 2400 lock window.
        val (left, right) = AppLockPolicy.safePadding(windowStart = 0, windowSize = 1080, safeStart = 440, safeEnd = 1080)
        val (top, bottom) = AppLockPolicy.safePadding(windowStart = 0, windowSize = 2400, safeStart = 1494, safeEnd = 2400)
        assertTrue(left + right <= 1080 / 4)
        assertTrue(top + bottom <= 2400 / 4)
    }

    @Test fun clampKeepsRealBarsAndScalesAbsurdOnes() {
        assertEquals(128 to 63, AppLockPolicy.clampPadding(128, 63, 2400))
        assertEquals(400 to 200, AppLockPolicy.clampPadding(800, 400, 2400))
        assertEquals(0 to 0, AppLockPolicy.clampPadding(0, 0, 0))
    }

    @Test fun appWindowSafeAreaOnlyWhileItCoversTheLockWindow() {
        assertTrue(AppLockPolicy.appWindowMatchesLock(appInPip = false, appWidth = 1080, appHeight = 2400, lockWidth = 1080, lockHeight = 2400))
        // In PiP, or still PiP-sized right after closing it.
        assertFalse(AppLockPolicy.appWindowMatchesLock(appInPip = true, appWidth = 1080, appHeight = 2400, lockWidth = 1080, lockHeight = 2400))
        assertFalse(AppLockPolicy.appWindowMatchesLock(appInPip = false, appWidth = 640, appHeight = 360, lockWidth = 1080, lockHeight = 2400))
        assertFalse(AppLockPolicy.appWindowMatchesLock(appInPip = false, appWidth = 1080, appHeight = 2400, lockWidth = 0, lockHeight = 0))
    }

    @Test fun splitScreenTopHalfLockWindowBelowTheStatusBarGetsNoPadding() {
        // QA: app window [0,0]–[1080,1187], lock window [0,136]–[1080,1187], status bar 136 px,
        // navigation bar 63 px at the bottom of a 2400 px display.
        // API 30+: display safe area 136 … 2337 mapped onto the lock window.
        assertEquals(0 to 0, AppLockPolicy.safePadding(windowStart = 136, windowSize = 1051, safeStart = 136, safeEnd = 2337))
        // API 26–29: app window's safe area 136 … 1187 (no bar at the divider).
        assertTrue(AppLockPolicy.appWindowMatchesLock(appInPip = false, appWidth = 1080, appHeight = 1187, lockWidth = 1080, lockHeight = 1051))
        assertEquals(0 to 0, AppLockPolicy.safePadding(windowStart = 136, windowSize = 1051, safeStart = 136, safeEnd = 1187))
        // Horizontally nothing to pad.
        assertEquals(0 to 0, AppLockPolicy.safePadding(windowStart = 0, windowSize = 1080, safeStart = 0, safeEnd = 1080))
    }

    @Test fun splitScreenBottomHalfPadsOnlyTheNavigationBar() {
        // Lock window [0,1213]–[1080,2400] over the 63 px navigation bar.
        assertEquals(0 to 63, AppLockPolicy.safePadding(windowStart = 1213, windowSize = 1187, safeStart = 136, safeEnd = 2337))
    }
}
