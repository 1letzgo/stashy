package de.letzgo.stashy.ui.feeds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.stashyGlass

/**
 * iOS: Feeds → Pics, which embeds `ImagesView(forceOneColumnFeed: true, feedsEmbedded: true)`.
 * Approximation until the Images catalog port lands: a one-column image feed with the Pics
 * sort / filter / criteria of [FeedsModel] (video images show their thumbnail with a play
 * badge; grouping into sets and the fullscreen viewer belong to the Images port).
 */
@Composable
fun PicsFeed(model: FeedsModel, topPadding: Dp, bottomPadding: Dp) {
    val list = model.list(ReelsModeType.Pics)
    LaunchedEffect(Unit) { model.ensureLoaded(ReelsModeType.Pics) }
    val items = list.items
    val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + topPadding
    when {
        items.isEmpty() && (list.isLoading || !list.loadedOnce) -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = Color.White) }
        items.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(SF.cameraFill, if (list.error != null) "Server not reachable" else "No images found") }
        else -> LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = Tokens.Grid.contentPadding, end = Tokens.Grid.contentPadding, top = top + Tokens.Spacing.xs, bottom = bottomPadding + 16.dp),
            verticalArrangement = Arrangement.spacedBy(Tokens.Grid.spacing),
        ) {
            itemsIndexed(items, key = { _, it -> it.id }) { index, item ->
                LaunchedEffect(index) { if (PreloadWindow.shouldLoadMore(index, items.size)) model.loadMore(ReelsModeType.Pics) }
                val image = (item as? FeedItem.ClipItem)?.image ?: return@itemsIndexed
                val isVideo = image.isVideo
                Box(
                    Modifier.fillMaxWidth().aspectRatio((image.aspectRatio ?: 1f).coerceIn(0.4f, 2.5f))
                        .clip(RoundedCornerShape(Tokens.Radius.card)).background(Color.White.copy(alpha = 0.06f)),
                ) {
                    AsyncImage(
                        model = if (isVideo || item.isAnimated) image.thumbnailURL else (image.imageURL ?: image.thumbnailURL),
                        contentDescription = item.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
                    )
                    if (isVideo) Box(Modifier.align(Alignment.Center).size(56.dp).stashyGlass(CircleShape), Alignment.Center) {
                        Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(26.dp))
                    }
                }
            }
        }
    }
}
