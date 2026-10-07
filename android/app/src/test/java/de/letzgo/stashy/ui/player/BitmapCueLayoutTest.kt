package de.letzgo.stashy.ui.player

import androidx.media3.common.text.Cue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BitmapCueLayoutTest {
    private val eps = 0.01f

    @Test fun pgsCuePlacesAtStartAnchorsInFrameFractions() {
        // PGS: position/line are the top-left corner, size / bitmapHeight the extent.
        val r = BitmapCueLayout.rect(
            1920f, 1080f, 800, 100,
            position = 0.25f, positionAnchor = Cue.ANCHOR_TYPE_START,
            line = 0.8f, lineType = Cue.LINE_TYPE_FRACTION, lineAnchor = Cue.ANCHOR_TYPE_START,
            size = 0.5f, bitmapHeight = 0.1f,
        )
        assertNotNull(r!!)
        assertEquals(480f, r.left, eps)
        assertEquals(864f, r.top, eps)
        assertEquals(960f, r.width, eps)
        assertEquals(108f, r.height, eps)
    }

    @Test fun scalesWithTheDisplayedFrame() {
        val r = BitmapCueLayout.rect(
            960f, 540f, 800, 100, 0.25f, Cue.ANCHOR_TYPE_START, 0.8f, Cue.LINE_TYPE_FRACTION, Cue.ANCHOR_TYPE_START, 0.5f, 0.1f,
        )!!
        assertEquals(240f, r.left, eps)
        assertEquals(432f, r.top, eps)
        assertEquals(480f, r.width, eps)
        assertEquals(54f, r.height, eps)
    }

    @Test fun middleAndEndAnchorsAndAspectHeight() {
        val r = BitmapCueLayout.rect(
            1000f, 500f, 400, 100, 0.5f, Cue.ANCHOR_TYPE_MIDDLE, 1f, Cue.LINE_TYPE_FRACTION, Cue.ANCHOR_TYPE_END, 0.4f, Cue.DIMEN_UNSET,
        )!!
        assertEquals(400f, r.width, eps)
        assertEquals(100f, r.height, eps) // bitmap aspect 4:1
        assertEquals(300f, r.left, eps)
        assertEquals(400f, r.top, eps)
    }

    @Test fun unsetFieldsFallBackToBottomCentre() {
        val u = Cue.DIMEN_UNSET
        val r = BitmapCueLayout.rect(1000f, 500f, 200, 50, u, Cue.TYPE_UNSET, u, Cue.TYPE_UNSET, Cue.TYPE_UNSET, u, u)!!
        assertEquals(200f, r.width, eps)
        assertEquals(400f, r.left, eps)
        assertEquals(475f - 50f, r.top, eps)
    }

    @Test fun emptyFrameOrBitmapDrawsNothing() {
        assertNull(BitmapCueLayout.rect(0f, 500f, 10, 10, 0f, 0, 0f, 0, 0, 0.5f, 0.1f))
        assertNull(BitmapCueLayout.rect(100f, 500f, 0, 10, 0f, 0, 0f, 0, 0, 0.5f, 0.1f))
    }
}
