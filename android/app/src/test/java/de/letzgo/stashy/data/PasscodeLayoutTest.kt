package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PasscodeLayoutTest {
    private fun fits(spec: PasscodeLayout.Spec, width: Float, height: Float) {
        if (spec.sideBySide) {
            assertTrue("keypad height", spec.keypadHeight <= height - 32f + 0.01f)
            assertTrue("keypad width", spec.keySize * PasscodeLayout.WIDTH_PER_KEY <= width / 2 - 16f + 0.01f)
        } else {
            assertTrue("column height", spec.topSpace + PasscodeLayout.HEADER + spec.keypadHeight + PasscodeLayout.PORTRAIT_GAPS <= height + 0.01f)
        }
    }

    @Test fun phonePortraitKeepsTheIosKeys() {
        val spec = PasscodeLayout.spec(379f, 780f) // 411 dp wide minus 2×16 padding
        assertFalse(spec.sideBySide)
        assertEquals(70f, spec.keySize, 0.01f)
        assertEquals(12f, spec.rowGap, 0.01f)
        assertEquals(80f, spec.topSpace, 0.01f)
        assertFalse(spec.scrolls)
    }

    @Test fun phoneLandscapePutsTheHeaderBesideAndFitsAllRows() {
        // QA: 1–6 visible, 7/8/9 cut, 0 / delete off screen. Typical landscape: ~800 × 340 dp after bars and cutout.
        for ((w, h) in listOf(800f to 340f, 760f to 300f, 860f to 380f, 700f to 260f)) {
            val spec = PasscodeLayout.spec(w, h)
            assertTrue(spec.sideBySide)
            assertFalse(spec.scrolls)
            fits(spec, w, h)
        }
    }

    @Test fun lowPortraitWindowShrinksKeysInsteadOfCutting() {
        val spec = PasscodeLayout.spec(379f, 500f) // split screen, top half
        assertFalse(spec.sideBySide)
        assertTrue(spec.keySize < 70f)
        assertEquals(24f, spec.topSpace, 0.01f)
        assertFalse(spec.scrolls)
        fits(spec, 379f, 500f)
    }

    @Test fun narrowWindowShrinksKeysByWidth() {
        val spec = PasscodeLayout.spec(200f, 700f)
        assertTrue(spec.keySize * PasscodeLayout.WIDTH_PER_KEY <= 200f + 0.01f)
    }

    @Test fun onlyATinyWindowScrolls() {
        val spec = PasscodeLayout.spec(379f, 300f)
        // 300 high, 379 wide: wider than high -> side by side, height 268 for 4 rows of ≥ 36
        assertTrue(spec.sideBySide)
        val tiny = PasscodeLayout.spec(600f, 150f)
        assertTrue(tiny.scrolls)
        assertEquals(PasscodeLayout.MIN_KEY, tiny.keySize, 0.01f)
    }
}
