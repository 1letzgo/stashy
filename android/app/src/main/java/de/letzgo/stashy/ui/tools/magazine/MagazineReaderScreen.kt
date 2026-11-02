package de.letzgo.stashy.ui.tools.magazine

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.CircleShape
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import coil3.compose.SubcomposeAsyncImage
import coil3.imageLoader
import coil3.request.Disposable
import coil3.request.ImageRequest
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.tools.MagazineLogic
import de.letzgo.stashy.data.tools.MagazineReadingStore
import de.letzgo.stashy.data.tools.MagazineRepository
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.detail.ZoomableBox
import kotlinx.coroutines.CancellationException

/**
 * iOS: `MagazineReaderView` — a gallery as two-page spreads (side by side in landscape, stacked in
 * portrait), a tap opens one page fullscreen. Android has no system page curl: the outgoing page
 * swings away around its left edge and uncovers the next one, which already lies underneath.
 */
class MagazineReaderScreen(private val gallery: Gallery) : Screen {
    override val key = "magazine-${gallery.id}"
    override val hidesTabBar = true

    private var pages by mutableStateOf<List<StashImage>>(emptyList())
    private var isLoading by mutableStateOf(true)
    private var error by mutableStateOf<String?>(null)
    private var spreadIndex by mutableIntStateOf(0)
    private var fullscreenPage by mutableIntStateOf(0)
    private var showsFullscreen by mutableStateOf(false)
    /** Stays false until the saved position is applied, so it cannot be overwritten with page 1. */
    private var didRestorePosition = false
    private var loadAttempt by mutableIntStateOf(0)
    private var finishedAttempt = -1

    private suspend fun load() {
        isLoading = true
        error = null
        try {
            pages = MagazineRepository.pages(gallery.id)
            MagazineReadingStore.sync(listOf(gallery.id))
            MagazineReadingStore.entries[gallery.id]?.page?.let { page ->
                if (pages.isNotEmpty()) spreadIndex = (page.coerceIn(1, pages.size) - 1) / 2
            }
            didRestorePosition = true
            // Opening counts as reading, even without turning a page.
            notePosition()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Could not load pages"
        }
        isLoading = false
    }

    private fun notePosition() {
        if (!didRestorePosition || pages.isEmpty()) return
        val page = if (showsFullscreen) fullscreenPage else spreadIndex * 2
        MagazineReadingStore.note(page + 1, gallery.id)
    }

    private fun openFullscreen(page: Int) {
        fullscreenPage = page
        showsFullscreen = true
    }

    private fun closeFullscreen() {
        spreadIndex = fullscreenPage / 2
        showsFullscreen = false
        notePosition()
    }

    @Composable
    override fun Content() {
        LaunchedEffect(loadAttempt) {
            if (finishedAttempt != loadAttempt) {
                finishedAttempt = loadAttempt
                load()
            }
        }
        BackHandler(enabled = showsFullscreen) { closeFullscreen() }
        KeepScreenOn()
        PushPositionWhenLeaving()
        Prefetch()

        Box(Modifier.fillMaxSize().background(Color.Black)) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                TopBar()
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { Body() }
            }
            if (showsFullscreen) Fullscreen()
        }
    }

    @Composable
    private fun KeepScreenOn() {
        val view = LocalView.current
        DisposableEffect(view) {
            view.keepScreenOn = true
            onDispose { view.keepScreenOn = false }
        }
    }

    @Composable
    private fun PushPositionWhenLeaving() {
        val owner = LocalLifecycleOwner.current
        DisposableEffect(owner) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_STOP) MagazineReadingStore.pushInBackground(gallery.id)
            }
            owner.lifecycle.addObserver(observer)
            onDispose {
                owner.lifecycle.removeObserver(observer)
                MagazineReadingStore.pushInBackground(gallery.id)
            }
        }
    }

    /** Next and previous pages, loaded ahead into Coil's cache. */
    @Composable
    private fun Prefetch() {
        val context = LocalContext.current
        val first = if (showsFullscreen) fullscreenPage else spreadIndex * 2
        val count = if (showsFullscreen) 1 else 2
        DisposableEffect(pages, first, count) {
            val requests: List<Disposable> = listOf(first - 2, first - 1, first + count, first + count + 1)
                .mapNotNull { pages.getOrNull(it)?.imageURL }
                .map { url -> context.imageLoader.enqueue(ImageRequest.Builder(context).data(url).build()) }
            onDispose { requests.forEach { it.dispose() } }
        }
    }

    /** Stays visible while reading: a tap on a page is taken by the fullscreen view. */
    @Composable
    private fun TopBar() {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CircleIcon(SF.xmark, "Close") { Nav.pop() }
            Text(
                gallery.displayTitle, Modifier.weight(1f), color = Color.White, fontSize = 14.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            if (pages.isNotEmpty()) {
                val first = spreadIndex * 2 + 1
                val last = minOf(first + 1, pages.size)
                Text(
                    if (first == last) "Page $first / ${pages.size}" else "Page $first–$last / ${pages.size}",
                    Modifier.padding(horizontal = 12.dp), color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp,
                )
            }
            if (spreadIndex > 0) {
                CircleIcon(SF.counterclockwise, "Reset position") {
                    spreadIndex = 0
                    MagazineReadingStore.resetPosition(gallery.id)
                }
            }
        }
    }

    @Composable
    private fun Body() {
        val message = error
        when {
            isLoading -> CircularProgressIndicator(color = Color.White)
            message != null -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(message, color = Color.White, modifier = Modifier.padding(16.dp))
                TextButton(onClick = { loadAttempt++ }) { Text("Try again") }
            }
            pages.isEmpty() -> Text("No pages", color = Color.White)
            else -> Spreads()
        }
    }

    @Composable
    private fun Spreads() {
        val pagerState = rememberPagerState(initialPage = spreadIndex) { MagazineLogic.spreadCount(pages.size) }
        LaunchedEffect(pagerState) {
            snapshotFlow { pagerState.settledPage }.collect { page ->
                if (page != spreadIndex) { spreadIndex = page; notePosition() }
            }
        }
        // Reset button and closing the fullscreen view jump without an animation.
        LaunchedEffect(spreadIndex) {
            if (pagerState.settledPage != spreadIndex) pagerState.scrollToPage(spreadIndex)
        }
        HorizontalPager(pagerState, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { index ->
            TurningPage(pagerState, index) { Spread(it) }
        }
    }

    @Composable
    private fun Spread(index: Int) {
        val first = index * 2
        val second = pages.getOrNull(first + 1)
        BoxWithConstraints(Modifier.fillMaxSize()) {
            if (maxWidth > maxHeight) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    SpreadPage(first, if (second != null) Alignment.CenterEnd else Alignment.Center, Modifier.weight(1f))
                    if (second != null) SpreadPage(first + 1, Alignment.CenterStart, Modifier.weight(1f))
                }
            } else {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SpreadPage(first, if (second != null) Alignment.BottomCenter else Alignment.Center, Modifier.weight(1f))
                    if (second != null) SpreadPage(first + 1, Alignment.TopCenter, Modifier.weight(1f))
                }
            }
        }
    }

    /** [alignment] lets two pages meet in the middle, like the fold of a magazine. */
    @Composable
    private fun SpreadPage(page: Int, alignment: Alignment, modifier: Modifier) {
        PageImage(
            pages[page], alignment,
            modifier.fillMaxSize().clickable(onClick = { openFullscreen(page) }),
        )
    }

    @Composable
    private fun Fullscreen() {
        var zoomed by remember { mutableStateOf(false) }
        var showsChrome by remember { mutableStateOf(true) }
        val pagerState = rememberPagerState(initialPage = fullscreenPage) { pages.size }
        LaunchedEffect(pagerState) {
            snapshotFlow { pagerState.settledPage }.collect { page ->
                if (page != fullscreenPage) { fullscreenPage = page; notePosition() }
                zoomed = false
            }
        }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(
                pagerState, Modifier.fillMaxSize(),
                beyondViewportPageCount = 1, userScrollEnabled = !zoomed,
            ) { index ->
                TurningPage(pagerState, index) { shown ->
                    ZoomableBox(onTap = { showsChrome = !showsChrome }, onZoomChange = { zoomed = it }) {
                        PageImage(pages[shown], Alignment.Center, Modifier.fillMaxSize())
                    }
                }
            }
            if (showsChrome) {
                Row(
                    Modifier.fillMaxWidth().safeDrawingPadding().padding(PaddingValues(horizontal = 4.dp)),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircleIcon(SF.xmark, "Close", background = true) { closeFullscreen() }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "${fullscreenPage + 1} / ${pages.size}",
                        Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 12.dp, vertical = 8.dp),
                        color = Color.White, fontSize = 12.sp,
                    )
                }
            }
        }
    }

    @Composable
    private fun PageImage(image: StashImage, alignment: Alignment, modifier: Modifier) {
        SubcomposeAsyncImage(
            model = image.imageURL,
            contentDescription = null,
            modifier = modifier,
            contentScale = ContentScale.Fit,
            alignment = alignment,
            loading = {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White) }
            },
            error = {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(SF.exclamationTriangle, null, tint = Color.White.copy(alpha = 0.6f))
                }
            },
        )
    }

    @Composable
    private fun CircleIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, background: Boolean = false, onClick: () -> Unit) {
        Box(
            Modifier.size(48.dp).clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(40.dp).clip(CircleShape).background(if (background) Color.Black.copy(alpha = 0.45f) else Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, label, tint = Color.White)
            }
        }
    }
}

/**
 * The pager lays pages side by side; this stacks them. A turning page stays pinned in place and
 * swings away around its left edge, with the following page drawn underneath it. That following
 * page's own pager slot stays hidden until the turn has finished.
 */
@Composable
private fun TurningPage(state: PagerState, page: Int, content: @Composable (Int) -> Unit) {
    // 0 at rest, towards 1 while the page leaves; negative for a page that is still to come.
    fun turn() = -state.getOffsetDistanceInPages(page)
    val isTurning by remember(state, page) { derivedStateOf { turn() > 0f } }
    Box(
        Modifier.fillMaxSize().graphicsLayer {
            val amount = turn()
            if (amount > 0f) translationX = amount * size.width
            alpha = if (amount < 0f) 0f else 1f
        },
    ) {
        if (isTurning && page + 1 < state.pageCount) content(page + 1)
        Box(
            Modifier.fillMaxSize()
                .graphicsLayer {
                    val amount = turn()
                    if (amount > 0f) {
                        transformOrigin = TransformOrigin(0f, 0.5f)
                        rotationY = 100f * amount
                        cameraDistance = 16f * density
                        alpha = if (amount >= 0.9f) 0f else 1f
                    }
                }
                .background(Color.Black),
        ) { content(page) }
    }
}
