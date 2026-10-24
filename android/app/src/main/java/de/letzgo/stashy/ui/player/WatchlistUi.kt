package de.letzgo.stashy.ui.player

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.WatchlistStore
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme

/** Row being dragged by its handle, and how far (px) it moved since its last swap. */
class WatchlistDragState {
    var draggingId by mutableStateOf<String?>(null)
    var offset by mutableFloatStateOf(0f)
}

/**
 * iOS: the watchlist `ForEach` of `NowPlayingContent` / `WatchlistToolsView` — a plain list on the
 * background with thin separators. Swipe left removes a row; drag handles show only in the
 * Sort mode ([sorting]); a long-press menu offers Play next (not for the playing scene),
 * Move up, Move down and Remove from watchlist.
 */
fun LazyListScope.watchlistRows(
    scenes: List<Scene>,
    currentId: String?,
    drag: WatchlistDragState,
    margin: Dp,
    sorting: Boolean,
    onOpen: (Scene) -> Unit,
) {
    itemsIndexed(scenes, key = { _, s -> "w-${s.id}" }) { index, scene ->
        Column {
            SwipeToRemove(scene.id) {
                WatchlistSceneRow(scene, index, scenes.size, isCurrent = scene.id == currentId, currentId, drag, margin, sorting, onOpen)
            }
            if (index < scenes.lastIndex) HorizontalDivider(Modifier.padding(start = margin), color = Theme.palette.text.copy(alpha = 0.08f))
        }
    }
}

/** iOS `.swipeActions(edge: .trailing, allowsFullSwipe: true)` — swipe left removes the entry. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToRemove(sceneId: String, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) { WatchlistStore.remove(sceneId); true } else false
    })
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(StashyColors.systemRed).padding(end = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(Icons.Filled.Delete, "Remove from watchlist", tint = Color.White)
            }
        },
    ) { content() }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun WatchlistSceneRow(
    scene: Scene,
    index: Int,
    count: Int,
    isCurrent: Boolean,
    currentId: String?,
    drag: WatchlistDragState,
    margin: Dp,
    sorting: Boolean,
    onOpen: (Scene) -> Unit,
) {
    val p = Theme.palette
    var menu by remember { mutableStateOf(false) }
    var rowHeight by remember { mutableIntStateOf(1) }
    val dragging = drag.draggingId == scene.id
    val performers = scene.performers.take(2).joinToString(", ") { it.name }
    Box(
        Modifier.fillMaxWidth().zIndex(if (dragging) 1f else 0f)
            .graphicsLayer { translationY = if (dragging) drag.offset else 0f }
            .onSizeChanged { rowHeight = maxOf(1, it.height) },
    ) {
        Row(
            Modifier.fillMaxWidth().background(p.background)
                .combinedClickable(onClick = { onOpen(scene) }, onLongClick = { menu = true })
                .padding(start = margin, end = (margin - 8.dp).coerceAtLeast(0.dp), top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(width = 80.dp, height = 45.dp).clip(RoundedCornerShape(6.dp)).background(Color.Black.copy(alpha = 0.3f)), contentAlignment = Alignment.Center) {
                AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                if (isCurrent) Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).padding(6.dp)) {
                    Icon(SF.speakerWave2Fill, "Now playing", tint = Color.White, modifier = Modifier.size(14.dp))
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(scene.displayTitle, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = if (isCurrent) Appearance.tint else p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (performers.isNotEmpty()) Text(performers, fontSize = 12.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            // Drag handle (Sort mode): swaps with a neighbour each time the row passes half its height.
            if (sorting) Box(
                Modifier.size(40.dp).pointerInput(scene.id) {
                    detectDragGestures(
                        onDragStart = { drag.draggingId = scene.id; drag.offset = 0f },
                        onDragEnd = { drag.draggingId = null; drag.offset = 0f },
                        onDragCancel = { drag.draggingId = null; drag.offset = 0f },
                    ) { change, amount ->
                        change.consume()
                        drag.offset += amount.y
                        val list = WatchlistStore.all
                        val i = list.indexOfFirst { it.id == scene.id }
                        val h = rowHeight.toFloat()
                        if (drag.offset > h / 2 && i in 0 until list.lastIndex) {
                            WatchlistStore.move(i, i + 1); drag.offset -= h
                        } else if (drag.offset < -h / 2 && i > 0) {
                            WatchlistStore.move(i, i - 1); drag.offset += h
                        }
                    }
                },
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.DragHandle, "Reorder", tint = p.secondaryText) }
        }
        DropdownMenu(menu, { menu = false }, containerColor = p.secondaryBackground) {
            if (currentId != null && !isCurrent) DropdownMenuItem(
                text = { Text("Play next", color = p.text) },
                leadingIcon = { Icon(WatchlistIcons.list, null, tint = p.text) },
                onClick = { menu = false; WatchlistStore.moveAfter(scene.id, currentId) },
            )
            if (index > 0) DropdownMenuItem(
                text = { Text("Move up", color = p.text) },
                leadingIcon = { Icon(Icons.Filled.ArrowUpward, null, tint = p.text) },
                onClick = { menu = false; WatchlistStore.shift(scene.id, -1) },
            )
            if (index < count - 1) DropdownMenuItem(
                text = { Text("Move down", color = p.text) },
                leadingIcon = { Icon(Icons.Filled.ArrowDownward, null, tint = p.text) },
                onClick = { menu = false; WatchlistStore.shift(scene.id, 1) },
            )
            DropdownMenuItem(
                text = { Text("Remove from watchlist", color = StashyColors.systemRed) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = StashyColors.systemRed) },
                onClick = { menu = false; WatchlistStore.remove(scene.id) },
            )
        }
    }
}
