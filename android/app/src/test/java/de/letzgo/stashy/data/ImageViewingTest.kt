package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImageViewingTest {
    @Test fun storedValueWins() {
        assertEquals(ImageScalingMode.Fill, ImageScalingMode.resolve("fill", true))
        assertEquals(ImageScalingMode.Fit, ImageScalingMode.resolve("fit", true))
        assertEquals(ImageScalingMode.Auto, ImageScalingMode.resolve("auto", false))
    }

    @Test fun legacyImmersiveFlagWhenNothingStored() {
        assertEquals(ImageScalingMode.Auto, ImageScalingMode.resolve(null, true))
        assertEquals(ImageScalingMode.Fit, ImageScalingMode.resolve(null, false))
        assertEquals(ImageScalingMode.Auto, ImageScalingMode.resolve("bogus", true))
    }

    @Test fun fillsRules() {
        assertFalse(ImageScalingMode.Fit.fills(true, true))
        assertTrue(ImageScalingMode.Fill.fills(true, false))
        assertTrue(ImageScalingMode.Auto.fills(true, true))
        assertTrue(ImageScalingMode.Auto.fills(false, false))
        assertFalse(ImageScalingMode.Auto.fills(true, false))
        assertFalse(ImageScalingMode.Auto.fills(false, true))
    }

    @Test fun backdropMode() {
        assertEquals(ImageBackdropMode.Black, ImageBackdropMode.resolve(null))
        assertEquals(ImageBackdropMode.Match, ImageBackdropMode.resolve("match"))
        assertEquals(ImageBackdropMode.Black, ImageBackdropMode.resolve("custom"))
    }
}
