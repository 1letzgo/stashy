package de.letzgo.stashy.ui

import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.grid.LazyGridItemScope
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.runtime.Composable

/**
 * Unique keys for a lazy list / pager built from entity ids. Compose throws
 * `IllegalArgumentException: Key "" was already used` when two items share a key — which happens
 * with offline metadata (a downloaded scene's performers / studio carry `id = ""`) and with
 * overlapping server pages. The first occurrence of a non-empty id keeps the id itself (stable
 * across recompositions); empty ids fall back to their index, later duplicates get a suffix.
 */
fun uniqueLazyKeys(ids: List<String?>): List<String> {
    val seen = HashSet<String>(ids.size * 2)
    return ids.mapIndexed { index, raw ->
        val base = if (raw.isNullOrEmpty()) "#$index" else raw
        var key = base
        var n = 1
        while (!seen.add(key)) key = "$base#${n++}"
        key
    }
}

/** [uniqueLazyKeys] for a list of items. */
inline fun <T> List<T>.uniqueLazyKeys(id: (T) -> String?): List<String> = uniqueLazyKeys(map(id))

/** `items(list, key = id)` with [uniqueLazyKeys] — safe for empty / duplicate ids. */
inline fun <T> LazyListScope.uniqueItems(
    items: List<T>,
    noinline id: (T) -> String?,
    crossinline itemContent: @Composable LazyItemScope.(T) -> Unit,
) {
    val keys = items.uniqueLazyKeys(id)
    items(items.size, key = { keys[it] }) { itemContent(items[it]) }
}

/** `itemsIndexed(list, key = id)` with [uniqueLazyKeys] — safe for empty / duplicate ids. */
inline fun <T> LazyListScope.uniqueItemsIndexed(
    items: List<T>,
    noinline id: (T) -> String?,
    crossinline itemContent: @Composable LazyItemScope.(index: Int, T) -> Unit,
) {
    val keys = items.uniqueLazyKeys(id)
    items(items.size, key = { keys[it] }) { itemContent(it, items[it]) }
}

/** Grid variant of [uniqueItemsIndexed]. */
inline fun <T> LazyGridScope.uniqueItemsIndexed(
    items: List<T>,
    noinline id: (T) -> String?,
    crossinline itemContent: @Composable LazyGridItemScope.(index: Int, T) -> Unit,
) {
    val keys = items.uniqueLazyKeys(id)
    items(items.size, key = { keys[it] }) { itemContent(it, items[it]) }
}
