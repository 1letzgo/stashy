package de.letzgo.stashy.tv

import android.view.KeyEvent as AndroidKeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.StashImage
import kotlinx.coroutines.delay

/**
 * iOS: `TVImageDetailView` — full-screen still image, Left/Right browse the list the grid
 * shows (its sort, filter and every loaded page), asking the grid for the next page three
 * images before the end. Back closes.
 */
class TvImageViewerRoute(
    private val imageId: String,
    private val title: String,
    private val images: () -> List<StashImage>,
    private val loadMore: () -> Unit,
    private val hasMore: () -> Boolean,
) : TvRoute {
    override val key = "image.$imageId.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()
    private var currentId by mutableStateOf(imageId)

    @Composable
    override fun Content() {
        val list = images()
        // Anchor on the image on screen first, then on the one that was opened.
        val index = list.indexOfFirst { it.id == currentId }.takeIf { it >= 0 }
            ?: list.indexOfFirst { it.id == imageId }.takeIf { it >= 0 } ?: 0
        val requester = remember { FocusRequester() }
        BackHandler { TvNav.pop() }
        Box(
            Modifier.fillMaxSize().background(Color.Black).focusRequester(requester).onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.nativeKeyEvent.keyCode) {
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT -> { if (index > 0) currentId = list[index - 1].id; true }
                    AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
                        if (index < list.size - 1) {
                            currentId = list[index + 1].id
                            if (index + 1 >= list.size - 3 && hasMore()) loadMore()
                        }
                        true
                    }
                    AndroidKeyEvent.KEYCODE_DPAD_UP, AndroidKeyEvent.KEYCODE_DPAD_DOWN -> true
                    else -> false
                }
            }.focusable(),
        ) {
            val image = list.getOrNull(index)
            if (image == null) {
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
                    Icon(TvIcons.photo, null, Modifier.size(pt(64)), tint = TvColors.secondary)
                    Text("No images", style = TvType.title2, color = TvColors.secondary)
                    if (title.isNotEmpty()) Text(title, style = TvType.title3, color = TvColors.tertiary, maxLines = 2)
                }
            } else {
                var loading by remember(image.id) { mutableStateOf(true) }
                AsyncImage(
                    image.imageURL ?: image.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit,
                    onSuccess = { loading = false }, onError = { loading = false },
                )
                if (loading) Box(Modifier.align(Alignment.Center)) { TvSpinner(pt(64)) }
                Text(
                    image.title ?: title, Modifier.align(Alignment.TopStart).padding(horizontal = pt(60), vertical = pt(40)),
                    style = TvType.title3, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                if (list.size > 1) {
                    Text("${index + 1} / ${list.size}", Modifier.align(Alignment.BottomCenter).padding(bottom = pt(40)), style = TvType.title3, color = TvColors.secondary)
                }
            }
        }
        LaunchedEffect(Unit) { delay(50); runCatching { requester.requestFocus() } }
    }
}
