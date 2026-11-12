package de.letzgo.stashy.data.tools

/**
 * iOS: `MagazineTextBlock` — a piece of text on a page: a speech bubble, a caption, a sound word.
 * [left]…[bottom] lie within the image, 0…1, origin top left.
 */
data class MagazineTextBlock(
    val id: Long,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val text: String,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
}

/** iOS: the grouping and hit testing of `MagazineTextRecognizer` / `MagazinePageTranslation`. */
object MagazineTextLogic {
    /** One recognized line, in pixels. [group] is the recognizer's own paragraph. */
    data class Piece(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
        val text: String,
        val group: Int,
    ) {
        val width: Float get() = right - left
        val height: Float get() = bottom - top
        /** Height of a horizontal line, width of a vertical column. */
        val thickness: Float get() = minOf(width, height)
        val isVertical: Boolean get() = height > width * 1.3f
        /** A single character is as wide as tall and says nothing about the direction. */
        val hasDirection: Boolean get() = text.trim().length > 1
    }

    /** The image as it is fitted and centred in its container. */
    data class Fitted(val left: Float, val top: Float, val width: Float, val height: Float)

    fun fitted(containerWidth: Float, containerHeight: Float, imageWidth: Int, imageHeight: Int): Fitted? {
        if (containerWidth <= 0f || containerHeight <= 0f || imageWidth <= 0 || imageHeight <= 0) return null
        val scale = minOf(containerWidth / imageWidth, containerHeight / imageHeight)
        val width = imageWidth * scale
        val height = imageHeight * scale
        return Fitted((containerWidth - width) / 2f, (containerHeight - height) / 2f, width, height)
    }

    /**
     * The lines of one bubble come as separate pieces: those of one paragraph, and those of the
     * same direction and letter size that lie closer than about half a line, belong together.
     */
    fun blocks(pieces: List<Piece>, imageWidth: Int, imageHeight: Int, firstId: Long = 0): List<MagazineTextBlock> {
        val lines = pieces.filter { piece -> piece.text.any { it.isLetter() } && piece.thickness > 0f }
        if (lines.isEmpty() || imageWidth <= 0 || imageHeight <= 0) return emptyList()
        val parent = IntArray(lines.size) { it }
        fun root(index: Int): Int {
            var i = index
            while (parent[i] != i) i = parent[i]
            return i
        }
        for (first in lines.indices) {
            for (second in first + 1 until lines.size) {
                val a = lines[first]
                val b = lines[second]
                if (a.group == b.group) { parent[root(second)] = root(first); continue }
                if (a.hasDirection && b.hasDirection && a.isVertical != b.isVertical) continue
                val thin = minOf(a.thickness, b.thickness)
                val thick = maxOf(a.thickness, b.thickness)
                if (thick / thin >= 1.6f) continue
                val reach = thin * 0.6f
                val touches = a.left - reach < b.right && b.left < a.right + reach &&
                    a.top - reach < b.bottom && b.top < a.bottom + reach
                if (touches) parent[root(second)] = root(first)
            }
        }
        var id = firstId
        return lines.indices.groupBy { root(it) }.values.map { members ->
            val group = members.map { lines[it] }
            MagazineTextBlock(
                id = id++,
                left = group.minOf { it.left } / imageWidth,
                top = group.minOf { it.top } / imageHeight,
                right = group.maxOf { it.right } / imageWidth,
                bottom = group.maxOf { it.bottom } / imageHeight,
                text = joined(group),
            )
        }
    }

    /** Reading order: vertical columns from right to left, horizontal lines from the top. */
    fun joined(group: List<Piece>): String {
        val directed = group.filter { it.hasDirection }
        val vertical = directed.isNotEmpty() && directed.count { it.isVertical } * 2 > directed.size
        val ordered = if (vertical) group.sortedByDescending { it.right } else group.sortedBy { it.top }
        val texts = ordered.map { it.text.trim() }
        val usesSpaces = texts.none { text -> text.any { isKana(it) || isHan(it) } }
        return texts.joinToString(if (usesSpaces) " " else "")
    }

    /** The smallest block under the point; [reachX] / [reachY] widen it for a finger. */
    fun hit(blocks: List<MagazineTextBlock>, x: Float, y: Float, reachX: Float, reachY: Float): MagazineTextBlock? =
        blocks.filter { x >= it.left - reachX && x <= it.right + reachX && y >= it.top - reachY && y <= it.bottom + reachY }
            .minByOrNull { it.width * it.height }

    fun isKana(char: Char): Boolean = char.code in 0x3040..0x30FF
    fun isHan(char: Char): Boolean = char.code in 0x4E00..0x9FFF
    fun isHangul(char: Char): Boolean = char.code in 0xAC00..0xD7A3
}
