package de.letzgo.stashy.ui.settings

import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Theme

/**
 * iOS `List` in edit mode with `.onMove` — rows reorder by dragging the ≡ handle. Rows are
 * plain (non-lazy) children, which fits settings sections of a few dozen rows.
 * [onMove] gets (from, to) indices; the caller persists the new order.
 */
@Composable
fun <T> ReorderableColumn(
    items: List<T>,
    key: (T) -> Any,
    onMove: (Int, Int) -> Unit,
    modifier: Modifier = Modifier,
    row: @Composable (item: T, index: Int, handle: Modifier) -> Unit,
) {
    val heights = remember { mutableStateMapOf<Any, Int>() }
    var draggingKey by remember { mutableStateOf<Any?>(null) }
    var offset by remember { mutableFloatStateOf(0f) }
    val currentItems by rememberUpdatedState(items)
    val currentOnMove by rememberUpdatedState(onMove)

    Column(modifier) {
        items.forEachIndexed { index, item ->
            val k = key(item)
            key(k) {
                val dragging = draggingKey == k
                val handle = Modifier.pointerInput(k) {
                    detectVerticalDragGestures(
                        onDragStart = { draggingKey = k; offset = 0f },
                        onDragEnd = { draggingKey = null; offset = 0f },
                        onDragCancel = { draggingKey = null; offset = 0f },
                    ) { change, dy ->
                        change.consume()
                        offset += dy
                        val list = currentItems
                        val i = list.indexOfFirst { key(it) == k }
                        if (i < 0) return@detectVerticalDragGestures
                        if (offset > 0 && i < list.lastIndex) {
                            val next = heights[key(list[i + 1])] ?: return@detectVerticalDragGestures
                            if (offset > next / 2f) { currentOnMove(i, i + 1); offset -= next }
                        } else if (offset < 0 && i > 0) {
                            val prev = heights[key(list[i - 1])] ?: return@detectVerticalDragGestures
                            if (-offset > prev / 2f) { currentOnMove(i, i - 1); offset += prev }
                        }
                    }
                }
                Box(
                    Modifier.onSizeChanged { heights[k] = it.height }
                        .zIndex(if (dragging) 1f else 0f)
                        .graphicsLayer { translationY = if (dragging) offset else 0f }
                        .let { if (dragging) it.shadow(8.dp) else it },
                ) { row(item, index, handle) }
            }
        }
    }
}

/** The ≡ drag handle shown at the trailing edge of movable rows. */
@Composable
fun DragHandle(modifier: Modifier) {
    Icon(SFS.dragHandle, "Reorder", tint = Theme.palette.tertiaryText, modifier = modifier.size(24.dp))
}

