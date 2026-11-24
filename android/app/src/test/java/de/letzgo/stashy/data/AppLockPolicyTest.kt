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

    // Emulator: 1080 × 2400 px, density 2.625, status bar 136 px, gesture bar 63 px.
    private val min = (200 * 2.625f).toInt()
    private val displaySafe = PxRect(0, 136, 1080, 2337)

    @Test fun fullScreenPortraitPadsStatusAndGestureBar() {
        val lock = PxRect(0, 0, 1080, 2400)
        val frame = PxRect(0, 136, 1080, 2337)
        assertEquals(PxInsets(0, 136, 0, 63), AppLockPolicy.lockPadding(lock, listOf(frame, lock, displaySafe), min, min))
    }

    @Test fun splitScreenTopHalfStopsAtTheDivider() {
        // QA round 4/5: lock window reported [0,136]–[1080,1187] or display-tall; app window
        // [0,0]–[1080,1187] or [0,136]–[1080,1187]. Whatever the windows say, the keys end at 1187.
        for (lock in listOf(PxRect(0, 136, 1080, 1187), PxRect(0, 0, 1080, 2400), PxRect(0, 136, 1080, 2400))) {
            for (app in listOf(PxRect(0, 0, 1080, 1187), PxRect(0, 136, 1080, 1187))) {
                val frame = PxRect(0, 136, 1080, 1187)
                val pad = AppLockPolicy.lockPadding(lock, listOf(frame, app), min, min)
                assertEquals("lock=$lock app=$app", 1187, lock.bottom - pad.bottom)
                assertEquals("lock=$lock app=$app", 136, lock.top + pad.top)
            }
        }
    }

    @Test fun splitScreenBottomHalfPadsTheGestureBar() {
        val lock = PxRect(0, 1213, 1080, 2400)
        val frame = PxRect(0, 1213, 1080, 2337)
        assertEquals(PxInsets(0, 0, 0, 63), AppLockPolicy.lockPadding(lock, listOf(frame, PxRect(0, 1213, 1080, 2400)), min, min))
    }

    @Test fun stalePipRectangleIsIgnored() {
        // QA round 3: app window still at the PiP's [440,1494]–[1040,1832] after closing PiP.
        val lock = PxRect(0, 0, 1080, 2400)
        val frame = PxRect(0, 136, 1080, 2337)
        val pad = AppLockPolicy.lockPadding(lock, listOf(frame, PxRect(440, 1494, 1040, 1832), displaySafe), min, min)
        assertEquals(PxInsets(0, 136, 0, 63), pad)
    }

    @Test fun noOverlapLeavesTheWindowAlone() {
        val lock = PxRect(0, 0, 1080, 2400)
        assertEquals(PxInsets(0, 0, 0, 0), AppLockPolicy.lockPadding(lock, listOf(PxRect(2000, 0, 3000, 100)), min, min))
        assertEquals(PxInsets(0, 0, 0, 0), AppLockPolicy.lockPadding(lock, emptyList(), min, min))
    }

    @Test fun landscapeCutoutSideIsPadded() {
        val lock = PxRect(0, 0, 2400, 1080)
        val frame = PxRect(136, 0, 2337, 1080)
        assertEquals(PxInsets(136, 0, 63, 0), AppLockPolicy.lockPadding(lock, listOf(frame), min, min))
    }
}
