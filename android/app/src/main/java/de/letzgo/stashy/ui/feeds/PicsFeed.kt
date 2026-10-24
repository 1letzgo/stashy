package de.letzgo.stashy.ui.feeds

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.catalog.ImageFeedList
import de.letzgo.stashy.ui.catalog.StandardLoading
import de.letzgo.stashy.ui.catalog.StatusPlaceholder
import de.letzgo.stashy.ui.filter.CatalogFilterSortSheet
import de.letzgo.stashy.ui.filter.ImageMediaTypeCard
import de.letzgo.stashy.ui.filter.ImagesFeedAutoplaySettingsCard

/**
 * iOS: Feeds → Pics, which embeds `ImagesView(forceOneColumnFeed: true, feedsEmbedded: true)`
 * with its own `DetailLinkedImagesFilterModel` (`reelsPicsFilters`).
 *
 * Same pieces as the Images catalog: [FeedsModel.pics] is a `CatalogController` (sort, saved
 * filter / local preset, criteria editor, paging) with the handed performer / tags / studio and
 * the "Type" chip on top; the list is the shared 1/row grouped feed ([ImageFeedList]: sets,
 * muted autoplay of the centred clip, rating / O-counter, tap → `ImageViewerScreen`); the
 * Filter & Sort pill opens the Images sheet (`ImagesCatalogFilterSortSheet` with Type and the
 * `ImagesFeedAutoplaySettingsCard`). The list scrolls under the Feeds chrome on the app
 * background, pull to refresh like iOS `.refreshable`.
 *
 * Differences to iOS: the 1/2-column toggle and multi-select of `ImagesView` are not offered
 * here (iOS hides them in Feeds too). Tag editing on posts ("+", long-press remove, AI
 * suggestions) comes from the shared feed list; an avatar opens the gallery in the 1/row feed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PicsFeed(model: FeedsModel, topPadding: Dp, bottomPadding: Dp) {
    val c = model.pics
    val list = c.list
    LaunchedEffect(c) { model.ensurePicsLoaded() }
    // A new result (filter, sort, criteria) starts at the top; returning from the viewer does not.
    val firstId = list.items.firstOrNull()?.id
    val initialFirst = remember(c) { firstId }
    LaunchedEffect(firstId) {
        if (firstId != initialFirst && model.picsListState.firstVisibleItemIndex > 0) model.picsListState.scrollToItem(0)
    }

    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        val hasServer = ServerConfigManager.activeConfig != null
        val inset = Modifier.fillMaxSize()
        when {
            !hasServer -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { c.refresh() }, inset)
            list.items.isEmpty() && (list.isLoading || !list.loadedOnce) -> StandardLoading("Loading images...")
            list.items.isEmpty() && list.error != null -> StatusPlaceholder(SF.server, list.error ?: "Server not reachable", "Retry Connection", { c.refresh() }, inset)
            list.items.isEmpty() -> StatusPlaceholder(SF.cameraFill, "No images found", "Reload", { c.refresh() }, inset)
            else -> PullToRefreshBox(isRefreshing = false, onRefresh = { c.refresh() }, modifier = Modifier.fillMaxSize()) {
                ImageFeedList(
                    images = list.items,
                    sortRaw = c.sort.raw,
                    isLoading = list.isLoading,
                    onLoadMore = { list.loadMore() },
                    contentPadding = PaddingValues(
                        start = Tokens.Grid.contentPadding, end = Tokens.Grid.contentPadding,
                        top = topPadding + Tokens.Spacing.md, bottom = bottomPadding + Tokens.Spacing.md,
                    ),
                    onImageUpdated = { model.patchPicsImage(it) },
                    state = model.picsListState,
                )
            }
        }
    }

    CatalogFilterSortSheet(c) {
        ImageMediaTypeCard(model.picsKind.kind) { model.picsKind.kind = it; c.applyLive() }
        ImagesFeedAutoplaySettingsCard()
    }
}
