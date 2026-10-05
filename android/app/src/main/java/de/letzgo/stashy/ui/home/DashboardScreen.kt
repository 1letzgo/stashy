package de.letzgo.stashy.ui.home

import de.letzgo.stashy.ui.cappedFontScale
import de.letzgo.stashy.ui.scaledIconSize
import androidx.compose.ui.text.style.TextOverflow
import android.os.Build
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.resolvedSort
import de.letzgo.stashy.data.HomeChannelSourceKind
import de.letzgo.stashy.data.HomeRowConfig
import de.letzgo.stashy.data.HomeRowType
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashStatistics
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.NativeButton
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeCardShape
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.nativeAccent
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.TextButton
import androidx.compose.ui.graphics.compositeOver
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.catalog.catalogTopPadding
import de.letzgo.stashy.ui.components.GalleryCard
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.noRippleClickable
import java.text.NumberFormat

/** iOS `homeSquareCardSide` — Channels and Statistics tiles. */
internal val HomeSquareCardSide = 125.dp

/** iOS `homeHeroCardWidth`: 80 % of the width on a portrait phone, else 280 pt. */
@Composable
internal fun homeHeroCardWidth(): Dp {
    val c = LocalConfiguration.current
    val portraitPhone = c.screenHeightDp > c.screenWidthDp && c.smallestScreenWidthDp < 600
    return if (portraitPhone) (c.screenWidthDp * 0.8f).dp else 280.dp
}

/** iOS `homeCardWidth(for:isLarge:)`. */
@Composable
internal fun homeCardWidth(type: HomeRowType, isLarge: Boolean): Dp = when {
    isLarge -> homeHeroCardWidth()
    type.isPerformerRow -> 125.dp * 2 / 3
    type.isGalleryRow -> 125.dp
    type == HomeRowType.Channels -> HomeSquareCardSide
    else -> 125.dp * 16 / 9
}

/** iOS `homeCardHeight(for:isLarge:)` (as the cards actually render). */
@Composable
internal fun homeCardHeight(type: HomeRowType, isLarge: Boolean): Dp {
    val w = homeCardWidth(type, isLarge)
    return when {
        type.isGalleryRow -> 125.dp
        type == HomeRowType.Channels -> w
        type.isPerformerRow -> if (isLarge) w * 9 / 16 else w * 3 / 2
        isLarge -> w * 9 / 16
        else -> 125.dp
    }
}

/** Catalog sub-tab for a stats tile / row header. */
internal fun AppTab.catalogTab(): CatalogTab? = when (this) {
    AppTab.Scenes -> CatalogTab.Scenes; AppTab.Images -> CatalogTab.Images; AppTab.Galleries -> CatalogTab.Galleries
    AppTab.Performers -> CatalogTab.Performers; AppTab.Studios -> CatalogTab.Studios; AppTab.Tags -> CatalogTab.Tags
    AppTab.Groups -> CatalogTab.Groups; AppTab.Markers -> CatalogTab.Markers
    else -> null
}

/**
 * iOS: `HomeView` — the dashboard rows configured in Settings › Dashboard (`HomeRowsConfig`),
 * scrolling under the floating chip strip and the tab bar; pull to refresh.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen() {
    val server = ServerConfigManager.activeConfig
    LaunchedEffect(server?.id) {
        DashboardStore.syncServer()
        TabManager.ensureLoaded()
        if (server != null) {
            if (DashboardStore.statistics == null) DashboardStore.loadStatistics(force = true) else DashboardStore.loadStatistics()
            SavedFiltersStore.load()
        }
    }
    // iOS "DefaultFilterChanged" for the dashboard → reload the scene rows.
    // Runs again whenever the dashboard reappears (Settings is another tab), so the store
    // remembers which change it already handled.
    LaunchedEffect(TabManager.defaultFilterChanged) { DashboardStore.onDefaultFilterChanged(TabManager.defaultFilterChanged) }
    when {
        server == null -> ConnectionErrorView { Nav.select(MainTab.Settings) }
        DashboardStore.statistics == null && DashboardStore.errorMessage != null -> ConnectionErrorView { DashboardStore.loadStatistics(force = true) }
        else -> DashboardContent()
    }
}

/** iOS `ConnectionErrorView` ("Server not reachable" + Retry Connection). */
@Composable
private fun ConnectionErrorView(onRetry: () -> Unit) {
    val p = Theme.palette
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
        Icon(SFS.serverRack, null, tint = p.secondaryText, modifier = Modifier.size(56.dp))
        Text("Server not reachable", style = NativeType.titleLarge, color = p.text, textAlign = TextAlign.Center)
        NativeButton("Retry Connection", onClick = onRetry)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DashboardContent() {
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(DashboardStore.isLoadingStatistics) { if (!DashboardStore.isLoadingStatistics) refreshing = false }
    val activeRows = TabManager.homeRows.filter { it.isEnabled && (it.type != HomeRowType.Channels || StashyPlus.isUnlocked) }
    val firstRowId = activeRows.firstOrNull()?.id
    val firstSceneRowId = activeRows.firstOrNull { it.type != HomeRowType.Statistics && it.type != HomeRowType.Channels }?.id

    PullToRefreshBox(refreshing, onRefresh = { refreshing = true; DashboardStore.refreshAll() }, Modifier.fillMaxSize()) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = catalogTopPadding() - 16.dp, bottom = TabBarClearance + 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            items(activeRows, key = { it.id }) { row ->
                val isFirst = row.id == firstRowId
                when (row.type) {
                    HomeRowType.Statistics -> StatisticsRow(isFirst)
                    HomeRowType.Channels -> ChannelsRow(row, isFirst)
                    else -> HomeRow(row, isLarge = row.id == firstSceneRowId, isFirst = isFirst)
                }
            }
        }
    }
}

/**
 * iOS: `HomeRowView` — header opening the catalog, horizontal row of cards.
 * Android look: Material section header (titleLarge + "See all" text button) and a horizontally
 * scrolling row with 16 dp margins and 8 dp gaps; the hero row (first scene row) snaps and uses
 * the large 28 dp carousel item shape. (The `material3.carousel` composables of material3 1.3.1
 * expose neither the current item — needed for the hero backdrop — nor item keys, so the row
 * stays a `LazyRow` styled like the Material uncontained carousel.)
 */
@Composable
private fun HomeRow(config: HomeRowConfig, isLarge: Boolean, isFirst: Boolean) {
    val p = Theme.palette
    val state = DashboardStore.row(config.type)
    LaunchedEffect(config.type, ServerConfigManager.activeConfig?.id, SavedFiltersStore.loadedOnce) { DashboardStore.loadRowIfNeeded(config) }
    val listState = rememberLazyListState()
    val focusedIndex by remember { derivedStateOf { listState.firstVisibleItemIndex + if (listState.firstVisibleItemScrollOffset > 200) 1 else 0 } }
    val w = homeCardWidth(config.type, isLarge)
    val h = homeCardHeight(config.type, isLarge)
    val showsHero = isLarge && isFirst && TabManager.showDashboardHeroBackground

    Box {
        if (showsHero) {
            val focused = state.scenes.getOrNull(focusedIndex) ?: state.scenes.firstOrNull()
            HeroBackdrop(focused?.thumbnailURL ?: state.performers.getOrNull(focusedIndex)?.imageURL, Modifier.matchParentSize())
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            DashboardSectionHeader(
                config.title, Modifier.padding(top = if (isFirst) 12.dp else 0.dp),
                onHero = showsHero, onSeeAll = { openCatalogCategory(config.type) },
            )
            when {
                state.isEmpty && state.isLoading -> LazyRow(contentPadding = PaddingValues(horizontal = RowMargin), horizontalArrangement = Arrangement.spacedBy(RowGap)) {
                    items(5) {
                        Box(Modifier.size(w, h).background(p.secondaryBackground, dashboardCardShape(isLarge)), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(20.dp), color = p.secondaryText, strokeWidth = 2.dp)
                        }
                    }
                }
                state.isEmpty -> Text("No content found", style = NativeType.bodyMedium, color = p.secondaryText, modifier = Modifier.padding(horizontal = RowMargin))
                else -> LazyRow(
                    state = listState, flingBehavior = rememberSnapFlingBehavior(listState),
                    contentPadding = PaddingValues(horizontal = RowMargin), horizontalArrangement = Arrangement.spacedBy(RowGap),
                ) {
                    when {
                        config.type.isPerformerRow -> {
                            val list = if (config.type == HomeRowType.PerformersHighestOCount) state.performers.sortedByDescending { it.oCounter ?: 0 }.take(10) else state.performers
                            val badge = when (config.type) {
                                HomeRowType.PerformersHighestOCount -> PerformerBadge.OCount
                                HomeRowType.PerformersHighestRating -> PerformerBadge.Rating
                                else -> PerformerBadge.SceneCount
                            }
                            items(list, key = { it.id }) { DashboardPerformerCard(it, badge, w, h, isLarge = isLarge, onClick = { DetailLinks.performer(it) }) }
                        }
                        config.type.isStudioRow -> items(state.studios, key = { it.id }) { DashboardStudioCard(it, isLarge, w, h, onClick = { DetailLinks.studio(it) }) }
                        config.type.isGalleryRow -> items(state.galleries, key = { it.id }) { (if (isLarge) w else 125.dp).let { gw -> GalleryCard(it, Modifier.size(gw, 125.dp), aspectRatio = gw / 125.dp, shape = dashboardCardShape(isLarge), onClick = { DetailLinks.gallery(it) }) } }
                        else -> items(state.scenes, key = { it.id }) { DashboardSceneCard(it, isLarge, w, h, onClick = { DetailLinks.scene(it) }) }
                    }
                }
            }
        }
    }
}

/** Outer margin and gap of the dashboard rows (Material carousel spacing). */
private val RowMargin = 16.dp
private val RowGap = 8.dp

/**
 * Material section header of a dashboard row: titleLarge, trailing "See all" text button when the
 * row links to a catalog (iOS: tappable "Title ›"). [onHero] = white over the hero backdrop.
 */
@Composable
private fun DashboardSectionHeader(title: String, modifier: Modifier = Modifier, onHero: Boolean = false, onSeeAll: (() -> Unit)? = null) {
    val p = Theme.palette
    Row(
        modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = RowMargin, end = if (onSeeAll != null) 4.dp else RowMargin),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title, Modifier.weight(1f), style = NativeType.titleLarge, color = if (onHero) Color.White else p.text,
            maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        if (onSeeAll != null) TextButton(onClick = onSeeAll) {
            Text("See all", style = NativeType.labelLarge, color = if (onHero) Color.White else nativeAccent())
        }
    }
}

/** iOS `openCatalogCategory()` — switch the Home sub-tab with the row's sort. */
private fun openCatalogCategory(type: HomeRowType) {
    when (type) {
        HomeRowType.NewPerformers -> Nav.openCatalog(CatalogTab.Performers, sort = "createdAtDesc")
        HomeRowType.PerformersHighestSceneCount -> Nav.openCatalog(CatalogTab.Performers, sort = "sceneCountDesc")
        HomeRowType.PerformersHighestOCount -> Nav.openCatalog(CatalogTab.Performers, sort = "oCountDesc")
        HomeRowType.PerformersHighestRating -> Nav.openCatalog(CatalogTab.Performers, sort = "ratingDesc")
        HomeRowType.NewStudios -> Nav.openCatalog(CatalogTab.Studios, sort = "createdAtDesc")
        HomeRowType.StudiosHighestSceneCount -> Nav.openCatalog(CatalogTab.Studios, sort = "sceneCountDesc")
        HomeRowType.NewGalleries -> Nav.openCatalog(CatalogTab.Galleries, sort = "createdAtDesc")
        HomeRowType.RecentlyUpdatedGalleries -> Nav.openCatalog(CatalogTab.Galleries, sort = "updatedAtDesc")
        HomeRowType.GalleriesHighestImageCount -> Nav.openCatalog(CatalogTab.Galleries, sort = "imageCountDesc")
        else -> Nav.openCatalog(CatalogTab.Scenes, sort = when (type) {
            HomeRowType.LastPlayed -> "lastPlayedAtDesc"
            HomeRowType.LastAdded3Min -> "createdAtDesc"
            HomeRowType.Newest3Min -> "dateDesc"
            HomeRowType.MostViewed3Min -> "playCountDesc"
            HomeRowType.TopCounter3Min -> "oCounterDesc"
            HomeRowType.TopRating3Min -> "ratingDesc"
            HomeRowType.Random -> "random"
            else -> null
        })
    }
}

/**
 * iOS `HomeDashboardHeroBackdrop` — the focused hero thumbnail, scaled 1.3 and blurred, behind
 * the first row and extended up under the status bar (500 pt) and 12 pt below the row.
 */
@Composable
private fun HeroBackdrop(url: String?, modifier: Modifier) {
    Box(
        modifier.layout { m, c ->
            val extraTop = 500.dp.roundToPx()
            val extraBottom = 12.dp.roundToPx()
            val placeable = m.measure(Constraints.fixed(c.maxWidth, c.maxHeight + extraTop + extraBottom))
            layout(c.maxWidth, c.maxHeight) { placeable.place(0, -extraTop) }
        }.clipToBounds(),
    ) {
        Crossfade(url, animationSpec = tween(500), label = "hero") { u ->
            if (u != null) {
                val canBlur = Build.VERSION.SDK_INT >= 31
                AsyncImage(
                    u, null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.3f; scaleY = 1.3f; alpha = if (canBlur) 1f else 0.45f }.blur(40.dp),
                )
            }
        }
    }
}

// MARK: - Statistics (iOS `HomeStatisticsRowView`)

private data class StatItem(val tab: AppTab, val title: String, val value: Int, val icon: ImageVector, val color: Color)

private fun statItems(stats: StashStatistics): List<StatItem> {
    val colored = TabManager.useColoredStatistics
    fun c(color: Color) = if (colored) color else Appearance.tint
    val order = setOf(AppTab.Scenes, AppTab.Galleries, AppTab.Images, AppTab.Performers, AppTab.Studios, AppTab.Tags, AppTab.Groups, AppTab.Markers)
    return TabManager.tabs.filter { it.id in order && it.isVisible }.sortedBy { it.sortOrder }.mapNotNull { t ->
        when (t.id) {
            AppTab.Scenes -> StatItem(t.id, "Scenes", stats.sceneCount, SF.film, c(StashyColors.systemBlue))
            AppTab.Galleries -> StatItem(t.id, "Galleries", stats.galleryCount, SF.photoStack, c(StashyColors.systemGreen))
            AppTab.Images -> StatItem(t.id, "Images", stats.imageCount, SF.photo, c(StashyColors.systemTeal))
            AppTab.Performers -> StatItem(t.id, "Performers", stats.performerCount, SF.person2, c(StashyColors.systemPurple))
            AppTab.Studios -> StatItem(t.id, "Studios", stats.studioCount, SF.building2, c(StashyColors.systemOrange))
            AppTab.Tags -> StatItem(t.id, "Tags", stats.tagCount, SF.tag, c(StashyColors.systemPink))
            AppTab.Groups -> StatItem(t.id, "Groups", stats.groupCount, SF.rectangleStackFill, c(Color(0.1f, 0.7f, 0.9f)))
            AppTab.Markers -> StatItem(t.id, "Markers", stats.sceneMarkerCount ?: 0, SF.bookmarkFill, c(StashyColors.systemRed))
            else -> null
        }
    }
}

private fun formatStat(n: Int): String = NumberFormat.getIntegerInstance().format(n)

@Composable
private fun StatisticsRow(isFirst: Boolean) {
    val p = Theme.palette
    val stats = DashboardStore.statistics
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        DashboardSectionHeader("Statistics", Modifier.padding(top = if (isFirst) 12.dp else 0.dp))
        when {
            stats != null -> {
                val items = statItems(stats)
                if (TabManager.useCompactStatistics) {
                    Column(Modifier.padding(horizontal = RowMargin), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items.chunked(2).forEach { pair ->
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                pair.forEach { CompactStatRow(it, Modifier.weight(1f)) }
                                if (pair.size == 1) Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                } else LazyRow(contentPadding = PaddingValues(horizontal = RowMargin), horizontalArrangement = Arrangement.spacedBy(RowGap)) {
                    items(items, key = { it.tab }) { StatCard(it) }
                }
            }
            DashboardStore.isLoadingStatistics || DashboardStore.errorMessage == null -> LazyRow(contentPadding = PaddingValues(horizontal = RowMargin), horizontalArrangement = Arrangement.spacedBy(RowGap)) {
                items(6) { Box(Modifier.size(HomeSquareCardSide * cappedFontScale(1.6f)).background(p.secondaryBackground, NativeCardShape)) }
            }
            else -> Row(Modifier.padding(horizontal = RowMargin), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(SF.exclamationTriangle, null, tint = p.secondaryText, modifier = Modifier.size(16.dp))
                Text("Stats unavailable", style = NativeType.bodyMedium, color = p.secondaryText)
            }
        }
    }
}

/** Tonal container of a statistics tile: the stat colour, subtle, over the card surface. */
@Composable
private fun statContainer(color: Color): Color = color.copy(alpha = if (Theme.palette.isDark) 0.22f else 0.14f).compositeOver(Theme.palette.secondaryBackground)

/**
 * iOS `StatCard` — 125 pt square with icon / value / title. Android look: Material filled card in a
 * tonal version of the stat colour (icon in the full colour), ripple, opens the catalog.
 */
@Composable
private fun StatCard(item: StatItem) {
    val p = Theme.palette
    // Square grows with the font scale (capped 1.6×) so value + title keep fitting on one line each.
    NativeCard(
        Modifier.size(HomeSquareCardSide * cappedFontScale(1.6f)), container = statContainer(item.color), elevation = 0.dp,
        onClick = { item.tab.catalogTab()?.let { Nav.openCatalog(it) } },
    ) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Icon(item.icon, null, tint = item.color, modifier = Modifier.size(scaledIconSize(28.dp, maxScale = 1.4f)))
            Column {
                Text(formatStat(item.value), style = NativeType.titleLarge, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(item.title, style = NativeType.labelMedium, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** iOS `compactStatRow` — row in a 2-column grid (48 dp Material touch height, tonal fill). */
@Composable
private fun CompactStatRow(item: StatItem, modifier: Modifier) {
    val p = Theme.palette
    // Min 48 dp (not fixed): the row grows with the font scale instead of clipping its text.
    NativeCard(
        modifier, container = statContainer(item.color), elevation = 0.dp,
        onClick = { item.tab.catalogTab()?.let { Nav.openCatalog(it) } },
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(item.icon, null, tint = item.color, modifier = Modifier.size(scaledIconSize(20.dp, maxScale = 1.4f)))
            Text(item.title, style = NativeType.labelLarge, color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(formatStat(item.value), style = NativeType.titleSmall, color = p.text, maxLines = 1)
        }
    }
}

// MARK: - Channels (iOS `HomeChannelsRowView`, stashy+)

@Composable
private fun ChannelsRow(config: HomeRowConfig, isFirst: Boolean) {
    val p = Theme.palette
    LaunchedEffect(Unit) { SavedFiltersStore.load() }
    LaunchedEffect(SavedFiltersStore.version) { TabManager.syncHomeChannelItems(SavedFiltersStore.byId.values.toList()) }
    val channels = TabManager.homeChannelItems.filter { it.isEnabled }.sortedBy { it.sortOrder }.mapNotNull { item ->
        val filter = SavedFiltersStore.byId[item.filterId] ?: return@mapNotNull null
        when (item.destination) {
            HomeChannelSourceKind.Scenes -> FeedsChannelRequest(filter, HomeChannelDestination.Scenes, filter.resolvedSort(FilterMode.Scenes)?.raw ?: "dateDesc")
            HomeChannelSourceKind.Clips -> FeedsChannelRequest(filter, HomeChannelDestination.Clips, filter.resolvedSort(FilterMode.Images)?.raw ?: "dateDesc")
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        DashboardSectionHeader(config.title, Modifier.padding(top = if (isFirst) 12.dp else 0.dp))
        if (channels.isEmpty()) {
            val msg = when {
                SavedFiltersStore.isLoading -> "Loading channels…"
                TabManager.homeChannelItems.isEmpty() -> "No saved scene or image filters"
                else -> "No channels enabled"
            }
            Text(msg, style = NativeType.bodyMedium, color = p.secondaryText, modifier = Modifier.padding(horizontal = RowMargin))
        } else LazyRow(contentPadding = PaddingValues(horizontal = RowMargin), horizontalArrangement = Arrangement.spacedBy(RowGap)) {
            items(channels, key = { "${it.destination}.${it.filter.id}" }) { ch ->
                ChannelCard(ch) { FeedsChannelLink.open(ch) }
            }
        }
    }
}

/** iOS `HomeChannelCardView` — category logo on the card surface, badge, title (Material card). */
@Composable
private fun ChannelCard(channel: FeedsChannelRequest, onClick: () -> Unit) {
    val p = Theme.palette
    val side = HomeSquareCardSide
    val icon = if (channel.destination == HomeChannelDestination.Scenes) SF.film else SFS.playRectOnRectFill
    NativeCard(Modifier.size(side), onClick = onClick) {
        Icon(icon, null, tint = nativeAccent(), modifier = Modifier.align(Alignment.Center).padding(bottom = side * 0.12f).size(side * 0.34f))
        Row(
            Modifier.align(Alignment.TopEnd).padding(8.dp).background(p.background, de.letzgo.stashy.ui.NativeLabelShape).padding(horizontal = 6.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(icon, null, tint = nativeAccent(), modifier = Modifier.size(12.dp))
            Text(channel.destination.label, style = NativeType.labelSmall, color = p.secondaryText)
        }
        Text(
            channel.filter.name, style = NativeType.labelLarge, color = p.text, maxLines = 2,
            modifier = Modifier.align(Alignment.BottomStart).padding(10.dp),
        )
    }
}
