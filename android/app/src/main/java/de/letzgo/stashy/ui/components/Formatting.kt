package de.letzgo.stashy.ui.components

/** iOS duration format: `36:12`, `1:02:03`. */
fun formatDuration(seconds: Double?): String? {
    val s = seconds?.toLong()?.takeIf { it > 0 } ?: return null
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
}

/** Compact counts like iOS stats (1.2K). */
fun formatCount(n: Int): String = when {
    n >= 1_000_000 -> "%.1fM".format(n / 1_000_000f)
    n >= 10_000 -> "%.1fK".format(n / 1_000f)
    else -> n.toString()
}
