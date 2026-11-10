package de.letzgo.stashy.data

/**
 * Turns a file-name-like scene title ("barbellinaa s pov sex tape.mp4") into a readable one
 * ("Barbellinaa's POV Sex Tape"). Pure and idempotent. Twin of Swift `SceneTitleNormalizer`
 * (SharedUtilities.swift), same rules; used by the "Normalize" button in the scene edit sheet.
 */
object SceneTitleNormalizer {
    private const val EXT = "mp4|m4v|mkv|mov|avi|wmv|webm|flv|ts|mpg|mpeg|jpg|jpeg|png|gif|webp"
    private val extRegex = Regex("\\.($EXT)$", RegexOption.IGNORE_CASE)
    private val noiseTokens = setOf("480p", "720p", "1080p", "2160p", "4k", "uhd", "hd", "hevc", "h264", "h265", "x264", "x265", "webrip")
    private val acronyms = setOf("pov", "bbc", "milf", "dp", "joi", "asmr", "vr", "hd")
    private val smallWords = setOf("a", "an", "the", "and", "or", "of", "in", "on", "with", "to", "for", "at", "by", "her", "his")
    private val negatable = setOf("don", "can", "won", "isn", "doesn", "didn", "wasn", "aren", "couldn", "wouldn", "shouldn")

    private val webDl = Regex("(?i)\\bweb[-_. ]?dl\\b")
    private val bracketRes = Regex("(?i)[\\[(]\\s*(480p|720p|1080p|2160p|4k|uhd|hd)\\s*[\\])]")
    private val dotBetween = Regex("(?<=\\p{L})\\.(?=[\\p{L}\\p{N}])|(?<=\\p{N})\\.(?=\\p{L})")
    private val dashBetween = Regex("(?<=[\\p{L}\\p{N}])[-+](?=[\\p{L}\\p{N}])")
    private val whitespaceRuns = Regex("\\s+")
    private val inlineRuns = Regex("[ \\t\\r]+")

    fun normalized(input: String): String {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return trimmed

        var text = trimmed.replace(extRegex, "").trim()
        val hadSpaces = text.any { it.isWhitespace() }
        val separatorCount = text.count { it == '_' || it == '-' || it == '+' || it == '.' }
        text = text.replace('_', ' ')
        text = text.replace(webDl, " ").replace(bracketRes, " ")
        text = text.replace(dotBetween, " ")
        if (!hadSpaces && separatorCount >= 2) text = text.replace(dashBetween, " ")

        val tokens = text.trim().split(whitespaceRuns).filter { it.isNotEmpty() && it.lowercase() !in noiseTokens }

        // Lost apostrophes: "barbellinaa s" -> "barbellinaa's", "don t" -> "don't".
        val merged = ArrayList<String>()
        for (token in tokens) {
            val last = merged.lastOrNull()
            if (last != null && last.last().isLetter()) {
                if (token == "s") { merged[merged.size - 1] = "$last's"; continue }
                if (token == "t" && last.lowercase() in negatable) { merged[merged.size - 1] = "$last't"; continue }
            }
            merged.add(token)
        }

        val result = merged.mapIndexed { index, token -> titleCased(token, index == 0) }.joinToString(" ")
        return result.ifEmpty { trimmed }
    }

    private fun titleCased(token: String, isFirst: Boolean): String {
        // Mixed / upper case words (POV, iPhone, Nice) stay as they are.
        if (token.any { it.isUpperCase() }) return token
        val core = token.trim { !it.isLetter() }.lowercase()
        if (core in acronyms) return token.uppercase()
        if (!isFirst && core in smallWords) return token
        val start = token.indexOfFirst { it.isLetter() || it.isDigit() }
        if (start < 0 || !token[start].isLetter()) return token
        return token.substring(0, start) + token[start].uppercaseChar() + token.substring(start + 1)
    }

    /** Lighter rule for the description: trim, drop a file extension when the whole text is one
     *  file-name-like line, collapse whitespace runs inside lines. Line breaks and casing stay. */
    fun normalizedDescription(input: String): String {
        var text = input.trim()
        if (text.isEmpty()) return text
        if (!text.contains('\n') && extRegex.containsMatchIn(text)) {
            val stripped = text.replace(extRegex, "").trim()
            if (stripped.isNotEmpty()) text = stripped
        }
        return text.split('\n').joinToString("\n") { it.replace(inlineRuns, " ").trim { c -> c == ' ' || c == '\t' } }
    }
}
