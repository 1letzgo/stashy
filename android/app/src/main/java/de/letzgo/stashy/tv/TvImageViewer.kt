package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.StashImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import de.letzgo.stashy.data.DetailRepository
import de.letzgo.stashy.data.ImageViewing
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.ui.detail.detailToast
import de.letzgo.stashy.ui.detail.starsFromRating

/**
 * iOS: `TVImageDetailView` — full-screen still image, Left/Right browse the list the grid
 * shows (its sort, filter and every loaded page), asking the grid for the next page three
 * images before the end. Back closes. An empty list offers Retry (next page, while the grid has
 * more) and Close; an image that fails to load shows an error icon (Select retries it).
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
    /** Image whose load failed (error icon), and a counter that restarts the load on Select. */
    private var failedId by mutableStateOf<String?>(null)
    private var attempt by mutableStateOf(0)
    /** Rating / O count changes of this session, over the grid's own (immutable) list. */
    private val overrides = androidx.compose.runtime.mutableStateMapOf<String, StashImage>()
    private var menuOpen by mutableStateOf(false)

    private suspend fun changeO(image: StashImage) {
        val base = overrides[image.id] ?: image
        val original = base.oCounter ?: 0
        overrides[image.id] = base.copy(oCounter = original + 1)
        val result = DetailRepository.imageOCounter(image.id, OCounterMutation.Increment)
        overrides[image.id] = (overrides[image.id] ?: base).copy(oCounter = result ?: original)
        if (result == null) detailToast(tr(R.string.error_update_o_count))
    }

    private suspend fun rate(image: StashImage, stars: Int) {
        val base = overrides[image.id] ?: image
        val original = base.rating100
        overrides[image.id] = base.copy(rating100 = (stars * 20).takeIf { it > 0 })
        if (!DetailRepository.setImageRating(image.id, (stars * 20).takeIf { it > 0 })) {
            overrides[image.id] = (overrides[image.id] ?: base).copy(rating100 = original)
            detailToast(tr(R.string.error_save_rating))
        }
    }

    @Composable
    override fun Content() {
        val list = images()
        // Anchor on the image on screen first, then on the one that was opened.
        val index = list.indexOfFirst { it.id == currentId }.takeIf { it >= 0 }
            ?: list.indexOfFirst { it.id == imageId }.takeIf { it >= 0 } ?: 0
        val requester = remember { FocusRequester() }
        val emptyFocus = remember { FocusRequester() }
        val scope = androidx.compose.runtime.rememberCoroutineScope()
        val spacePortrait = androidx.compose.ui.platform.LocalConfiguration.current.let { it.screenHeightDp > it.screenWidthDp }
        BackHandler { TvNav.pop() }
        Box(
            Modifier.fillMaxSize().background(ImageViewing.backdropColor(list.getOrNull(index)?.let { it.thumbnailURL ?: it.imageURL })).focusRequester(requester).onKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (event.nativeKeyEvent.keyCode) {
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_NUMPAD_ENTER -> {
                        if (failedId != null && failedId == list.getOrNull(index)?.id) { failedId = null; attempt++; true } else if (list.getOrNull(index) != null) { menuOpen = true; true } else false
                    }
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT -> { if (index > 0) currentId = list[index - 1].id; true }
                    AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
                        if (index < list.size - 1) {
                            currentId = list[index + 1].id
                            if (index + 1 >= list.size - 3 && hasMore()) loadMore()
                        }
                        true
                    }
                    // Empty list: Up / Down move between Retry and Close.
                    AndroidKeyEvent.KEYCODE_DPAD_UP, AndroidKeyEvent.KEYCODE_DPAD_DOWN -> list.isNotEmpty()
                    else -> false
                }
            }.focusable(),
        ) {
            val base = list.getOrNull(index)
            val image = base?.let { overrides[it.id] ?: it }
            if (image == null) {
                // iOS: "No images" with Retry / Close — without them the remote had nothing to focus.
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
                    Icon(TvIcons.photo, null, Modifier.size(pt(64)), tint = TvColors.secondary)
                    Text(tr(R.string.empty_images), style = TvType.title2, color = TvColors.secondary)
                    if (title.isNotEmpty()) Text(title, Modifier.padding(horizontal = pt(80)), style = TvType.title3, color = TvColors.tertiary, maxLines = 2, textAlign = TextAlign.Center)
                    val canRetry = hasMore()
                    if (canRetry) TvButton({ loadMore() }, Modifier.focusRequester(emptyFocus)) { Text(tr(R.string.action_retry), style = TvType.title3) }
                    TvButton({ TvNav.pop() }, if (canRetry) Modifier else Modifier.focusRequester(emptyFocus)) { Text(tr(R.string.action_close), style = TvType.title3) }
                }
                TvRequestFocus(emptyFocus, "imageViewer.empty")
            } else {
                val url = image.imageURL ?: image.thumbnailURL
                var loading by remember(image.id, attempt) { mutableStateOf(url != null) }
                val failed = failedId == image.id || url == null
                val portraitImage = image.visualFiles?.firstOrNull()?.let { (it.height ?: 0) > (it.width ?: 0) } ?: false
                val fill = ImageViewing.scaling.fills(portraitImage, spacePortrait)
                if (url != null && !failed) {
                    androidx.compose.runtime.key(image.id, attempt) {
                        AsyncImage(
                            url, null, Modifier.fillMaxSize(), contentScale = if (fill) ContentScale.Crop else ContentScale.Fit,
                            onSuccess = { loading = false }, onError = { loading = false; failedId = image.id },
                        )
                    }
                }
                if (failed) {
                    // iOS `TVImageDetailView`: the photo glyph instead of a blank screen.
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(16))) {
                        Icon(TvIcons.warning, null, Modifier.size(pt(64)), tint = TvColors.secondary)
                        Text(tr(R.string.error_load_this_image), style = TvType.title3, color = TvColors.secondary)
                        if (url != null) Text(tr(R.string.press_select_to_retry), style = TvType.callout, color = TvColors.tertiary)
                    }
                } else if (loading) Box(Modifier.align(Alignment.Center)) { TvSpinner(pt(64)) }
                Text(
                    image.title ?: title, Modifier.align(Alignment.TopStart).padding(horizontal = pt(60), vertical = pt(40)),
                    style = TvType.title3, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                // Info line: stars and O count (Select opens the rating / O menu).
                val stars = starsFromRating(image.rating100)
                Row(
                    Modifier.align(Alignment.BottomStart).padding(horizontal = pt(60), vertical = pt(40)).clip(RoundedCornerShape(pt(10))).background(Color.Black.copy(alpha = 0.5f)).padding(horizontal = pt(16), vertical = pt(8)),
                    horizontalArrangement = Arrangement.spacedBy(pt(20)), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(pt(6)), verticalAlignment = Alignment.CenterVertically) {
                        Icon(TvIcons.star, null, Modifier.size(pt(24)), tint = if (stars > 0) TvColors.star else TvColors.secondary)
                        Text("$stars", style = TvType.title3, color = Color.White)
                    }
                    Text("${tr(R.string.o_count)} ${image.oCounter ?: 0}", style = TvType.title3, color = Color.White)
                }
                if (menuOpen) {
                    TvOptionDialog(
                        tr(R.string.rating),
                        (0..5).map { TvOption(it, if (it == 0) tr(R.string.empty_rating) else "★".repeat(it)) },
                        stars, { s -> scope.launch { rate(image, s) } }, onDismiss = { menuOpen = false },
                        extra = listOf(tr(R.string.action_add_o) to { scope.launch { changeO(image) }; Unit }),
                    )
                }
                if (list.size > 1) {
                    Text("${index + 1} / ${list.size}", Modifier.align(Alignment.BottomCenter).padding(bottom = pt(40)), style = TvType.title3, color = TvColors.secondary)
                }
            }
        }
        if (list.isNotEmpty()) TvRequestFocus(requester, "imageViewer")
    }
}
