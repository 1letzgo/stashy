package de.letzgo.stashy.data

import de.letzgo.stashy.data.tools.MagazineTextLogic
import de.letzgo.stashy.data.tools.MagazineTextLogic.Piece
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class MagazineTextLogicTest {
    @Test
    fun verticalColumnsOfOneBubbleJoinFromRightToLeft() {
        // Two columns 14 px apart, each 49 px wide, recognized as separate paragraphs.
        val pieces = listOf(
            Piece(764f, 250f, 813f, 480f, "散歩に行こう", group = 0),
            Piece(827f, 230f, 876f, 560f, "今日はいい天気ですね", group = 1),
            Piece(244f, 360f, 293f, 650f, "どこへ行くのですか", group = 2),
        )
        val blocks = MagazineTextLogic.blocks(pieces, 1200, 1700)
        assertEquals(2, blocks.size)
        assertEquals("今日はいい天気ですね散歩に行こう", blocks.first { it.left > 0.5f }.text)
    }

    @Test
    fun horizontalLinesJoinFromTheTopWithSpaces() {
        val pieces = listOf(
            Piece(100f, 140f, 400f, 170f, "are you going?", group = 0),
            Piece(100f, 100f, 400f, 130f, "Where", group = 0),
            Piece(100f, 600f, 400f, 630f, "Far away", group = 1),
        )
        val blocks = MagazineTextLogic.blocks(pieces, 1000, 1000)
        assertEquals(listOf("Where are you going?", "Far away"), blocks.sortedBy { it.top }.map { it.text })
    }

    @Test
    fun aSoundWordInBigLettersStaysApart() {
        val pieces = listOf(
            Piece(100f, 100f, 300f, 130f, "Hello", group = 0),
            Piece(100f, 135f, 500f, 235f, "BOOM", group = 1),
        )
        assertEquals(2, MagazineTextLogic.blocks(pieces, 1000, 1000).size)
    }

    @Test
    fun punctuationAloneIsNoBlock() {
        assertEquals(0, MagazineTextLogic.blocks(listOf(Piece(0f, 0f, 20f, 20f, "!?", 0)), 100, 100).size)
    }

    @Test
    fun tapIsMappedThroughTheFittedImage() {
        // A 1200 × 1700 page in a 400 × 800 box: 400 × 566.7, 116.7 from the top.
        val fit = MagazineTextLogic.fitted(400f, 800f, 1200, 1700)!!
        assertEquals(0f, fit.left, 0.01f)
        assertEquals(116.67f, fit.top, 0.01f)
        val blocks = MagazineTextLogic.blocks(listOf(Piece(600f, 850f, 900f, 950f, "Hello there", 0)), 1200, 1700)
        val inside = MagazineTextLogic.hit(blocks, (250f - fit.left) / fit.width, (420f - fit.top) / fit.height, 0f, 0f)
        assertNotNull(inside)
        assertNull(MagazineTextLogic.hit(blocks, 0.1f, 0.1f, 0.02f, 0.02f))
    }
}
