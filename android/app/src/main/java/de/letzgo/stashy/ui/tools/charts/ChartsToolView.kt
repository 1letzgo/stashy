package de.letzgo.stashy.ui.tools.charts

import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.TopListsLogic
import de.letzgo.stashy.data.tools.TopListsMetric
import de.letzgo.stashy.data.tools.TopListsPerformerMetric
import de.letzgo.stashy.data.tools.TopListsSceneMetric
import de.letzgo.stashy.data.tools.TopListsStudioMetric
import de.letzgo.stashy.data.tools.TopListsTagMetric
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.detail.StudioDetailScreen
import de.letzgo.stashy.ui.detail.TagDetailScreen
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.ToolsBottomPadding
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** iOS: `StashyExpandingDock.itemSpacing` / `activeHeight`. */
private val DockItemSpacing = 10.dp
private val DockActiveHeight = 40.dp
/** iOS: `DesignTokens.Opacity.placeholder`. */
private const val PlaceholderOpacity = 0.1f

/**
 * iOS: `TopListsToolsContainerView` — Tools › Charts: a pill row (Scenes · Performers · Studios ·
 * Tags) above the ranked list of the selected category. State lives in [ChartsState].
 */
@Composable
fun ChartsToolView() {
    val vm = ChartsState.viewModel
    val section = ChartsState.section
    Column(Modifier.fillMaxSize().background(Theme.palette.background)) {
        Spacer(Modifier.height(toolsTopPadding()))
        ChartsPillMenuRow(
            items = ChartsSection.entries.map { it to it.title },
            selected = section,
            onSelect = { ChartsState.section = it },
        )
        Box(Modifier.weight(1f).fillMaxWidth()) {
            key(section) {
                when (section) {
                    ChartsSection.Scenes -> TopScenesList(vm)
                    ChartsSection.Performers -> TopPerformersList(vm)
                    ChartsSection.Studios -> TopStudiosList(vm)
                    ChartsSection.Tags -> TopTagsList(vm)
                }
            }
        }
    }
}

/** iOS: `TopScenesToolsView`. */
@Composable
private fun TopScenesList(vm: TopListsViewModel) = TopListSection(
    vm, vm.scenes, "Loading top scenes...", "No scenes yet.", Scene::id,
    onTap = { Nav.push(SceneDetailScreen(it.id, it)) },
) { index, scene, metric ->
    LeaderboardCard(
        title = scene.title ?: "Untitled", place = index + 1, thumbWidth = 128.dp, thumbAspectRatio = 16f / 9f,
        titleMaxLines = 1,
        thumbnail = { ThumbImage(scene.thumbnailURL, SF.film) },
    ) {
        StatColumn("Views", TopListsLogic.formatCount(scene.playCount ?: 0), metric == TopListsSceneMetric.Views)
        StatColumn("O-Count", TopListsLogic.formatCount(scene.oCounter ?: 0), metric == TopListsSceneMetric.OCount)
        StatColumn("Watch", TopListsLogic.formatDuration(scene.playDuration ?: 0.0), metric == TopListsSceneMetric.WatchTime)
        StatColumn("Rating", TopListsLogic.formatRating(scene.rating100), metric == TopListsSceneMetric.Rating)
    }
}

/** iOS: `TopPerformersToolsView`. */
@Composable
private fun TopPerformersList(vm: TopListsViewModel) = TopListSection(
    vm, vm.performers, "Loading top performers...", "No performers yet.", Performer::id,
    onTap = { Nav.push(PerformerDetailScreen(it.id, it)) },
) { index, performer, metric ->
    LeaderboardCard(
        title = performer.name, place = index + 1, thumbWidth = 68.dp, thumbAspectRatio = null,
        thumbnail = { ThumbImage(performer.imageURL, SF.personFill, Alignment.TopCenter) },
    ) {
        StatColumn("O-Count", TopListsLogic.formatCount(performer.oCounter ?: 0), metric == TopListsPerformerMetric.OCount)
        StatColumn("Scenes", TopListsLogic.formatCount(performer.sceneCount ?: 0), metric == TopListsPerformerMetric.Scenes)
        StatColumn("Rating", TopListsLogic.formatRating(performer.rating100), metric == TopListsPerformerMetric.Rating)
        StatColumn("Images", TopListsLogic.formatCount(performer.imageCount ?: 0), metric == TopListsPerformerMetric.Images)
        StatColumn("Galleries", TopListsLogic.formatCount(performer.galleryCount ?: 0), metric == TopListsPerformerMetric.Galleries)
    }
}

/** iOS: `TopStudiosToolsView`. */
@Composable
private fun TopStudiosList(vm: TopListsViewModel) = TopListSection(
    vm, vm.studios, "Loading top studios...", "No studios yet.", Studio::id,
    onTap = { Nav.push(StudioDetailScreen(it.id, it)) },
) { index, studio, metric ->
    LeaderboardCard(
        title = studio.name, place = index + 1, thumbWidth = 128.dp, thumbAspectRatio = 16f / 9f,
        isStudio = true,
        thumbnail = {
            // iOS: `StudioImageView` — logo fitted with 8 pt padding on the studio header grey.
            if (studio.hasImage) {
                AsyncImage(studio.imageURL, studio.name, Modifier.fillMaxSize().padding(8.dp), contentScale = ContentScale.Fit)
            } else {
                PlaceholderIcon(SF.building2, Modifier.align(Alignment.Center))
            }
        },
    ) {
        StatColumn("Scenes", TopListsLogic.formatCount(studio.sceneCount ?: 0), metric == TopListsStudioMetric.Scenes)
        StatColumn("Galleries", TopListsLogic.formatCount(studio.galleryCount ?: 0), metric == TopListsStudioMetric.Galleries)
        StatColumn("Rating", TopListsLogic.formatRating(studio.rating100), metric == TopListsStudioMetric.Rating)
        StatColumn("Images", TopListsLogic.formatCount(studio.imageCount ?: 0), metric == TopListsStudioMetric.Images)
    }
}

/**
 * iOS: `TopTagsToolsView`. iOS opens the tag on the tab matching the metric
 * (`tagDetailTab(for:)`); [TagDetailScreen] has no initial-tab parameter yet.
 */
@Composable
private fun TopTagsList(vm: TopListsViewModel) = TopListSection(
    vm, vm.tags, "Loading top tags...", "No tags yet.", Tag::id,
    onTap = { Nav.push(TagDetailScreen(it.id, it)) },
) { index, tag, metric ->
    LeaderboardCard(
        title = tag.name, place = index + 1, thumbWidth = 128.dp, thumbAspectRatio = 16f / 9f,
        thumbnail = { ThumbImage(tag.imageURL, SF.tag) },
    ) {
        StatColumn("Scenes", TopListsLogic.formatCount(tag.sceneCount ?: 0), metric == TopListsTagMetric.Scenes)
        StatColumn("Images", TopListsLogic.formatCount(tag.imageCount ?: 0), metric == TopListsTagMetric.Images)
        StatColumn("Galleries", TopListsLogic.formatCount(tag.galleryCount ?: 0), metric == TopListsTagMetric.Galleries)
        StatColumn("Markers", TopListsLogic.formatCount(tag.sceneMarkerCount ?: 0), metric == TopListsTagMetric.Markers)
    }
}

/**
 * Shared body of the four `Top<X>ToolsView`s: placeholder states, metric chips, ranked cards and
 * the infinite-scroll footer (iOS: `TopListsCardsGrid` + `TopListsPaginationFooter`).
 */
@Composable
private fun <M : TopListsMetric, T> TopListSection(
    vm: TopListsViewModel,
    state: TopListsSectionState<M, T>,
    loadingMessage: String,
    emptyText: String,
    idOf: (T) -> String,
    onTap: (T) -> Unit,
    card: @Composable (index: Int, item: T, metric: M) -> Unit,
) {
    val p = Theme.palette
    val serverId = ServerConfigManager.activeConfig?.id
    // iOS: `.task` on appear, `onChange(of: metric)` and `onChange(of: activeConfig?.id)` (reset first).
    LaunchedEffect(serverId, state.metric) {
        vm.syncServer(serverId)
        if (serverId != null) state.reload()
    }
    when {
        serverId == null -> NoServerPlaceholder(SF.chartBar, "Connect to a Stash server to see your charts.")
        state.isLoading && !state.hasContent -> ChartsLoadingView(loadingMessage)
        state.didFail && !state.hasContent -> ChartsConnectionError { vm.scope.launch { state.reload() } }
        else -> {
            val items = state.items
            val metric = state.metric
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding, bottom = ToolsBottomPadding),
                verticalArrangement = Arrangement.spacedBy(ToolsTokens.rankedGridSpacing),
            ) {
                item(key = "metrics") {
                    MetricChipRow(state.metrics, metric) { state.metric = it }
                }
                if (items.isEmpty()) {
                    item(key = "empty") {
                        Text(
                            emptyText, style = IosTypography.subheadline, color = p.secondaryText, textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                        )
                    }
                } else {
                    itemsIndexed(items, key = { _, item -> "item-" + idOf(item) }) { index, item ->
                        Box(Modifier.noRippleClickable { onTap(item) }) { card(index, item, metric) }
                    }
                    if (state.isLoadingMore) {
                        item(key = "loading-more") {
                            Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) {
                                CircularProgressIndicator(Modifier.size(24.dp), color = p.text, strokeWidth = 2.dp)
                            }
                        }
                    } else if (state.hasMore) {
                        item(key = "more-${items.size}") {
                            // iOS: an invisible 1 pt row whose `onAppear` loads the next page. Launched in
                            // the view model scope so swapping this row for the spinner can't cancel it.
                            LaunchedEffect(items.size) { vm.scope.launch { state.loadMore() } }
                            Spacer(Modifier.fillMaxWidth().height(1.dp))
                        }
                    }
                }
            }
        }
    }
}

/** iOS: `ToolsPillMenuRow` — equally wide capsules, tinted when selected. */
@Composable
private fun <K> ChartsPillMenuRow(items: List<Pair<K, String>>, selected: K, onSelect: (K) -> Unit) {
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier.fillMaxWidth()
            .padding(start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding, top = ToolsTokens.menuTopPadding, bottom = ToolsTokens.menuBottomPadding),
        horizontalArrangement = Arrangement.spacedBy(DockItemSpacing),
    ) {
        items.forEach { (id, title) ->
            val isSelected = id == selected
            CapsuleChip(
                title, isSelected, DockActiveHeight, IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), 6.dp,
                Modifier.weight(1f),
            ) {
                if (!isSelected) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSelect(id)
                }
            }
        }
    }
}

/** iOS: `TopListsMetricChipRow` — 28 pt capsules sharing the width. */
@Composable
private fun <M : TopListsMetric> MetricChipRow(metrics: List<M>, selection: M, onSelect: (M) -> Unit) {
    val haptics = LocalHapticFeedback.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DockItemSpacing)) {
        metrics.forEach { metric ->
            val isSelected = metric == selection
            CapsuleChip(
                metric.label, isSelected, 28.dp, IosTypography.caption.copy(fontWeight = FontWeight.SemiBold), 4.dp,
                Modifier.weight(1f),
            ) {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onSelect(metric)
            }
        }
    }
}

@Composable
private fun CapsuleChip(
    title: String,
    selected: Boolean,
    height: Dp,
    style: TextStyle,
    shadowRadius: Dp,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val p = Theme.palette
    val tint = Appearance.tint
    val shape = RoundedCornerShape(50)
    Box(
        modifier
            .heightIn(min = height)
            .let { if (selected) it.shadow(shadowRadius, shape, ambientColor = tint.copy(alpha = 0.35f), spotColor = tint.copy(alpha = 0.35f)) else it }
            .clip(shape)
            .background(if (selected) tint else p.secondaryBackground, shape)
            .noRippleClickable(onClick)
            .padding(horizontal = 4.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        ShrinkingText(title, style, if (selected) Color.White else p.text.copy(alpha = 0.85f), minScale = 0.65f)
    }
}

/**
 * iOS: `TopListsLeaderboardCard` + `TopListsCardRowLayout` — thumbnail with a rank badge on the
 * leading edge, title and stat columns on the right. With [thumbAspectRatio] the thumbnail width
 * follows the content height (16:9), otherwise it is [thumbWidth] wide.
 */
@Composable
private fun LeaderboardCard(
    title: String,
    place: Int,
    thumbWidth: Dp,
    thumbAspectRatio: Float?,
    titleMaxLines: Int = 2,
    isStudio: Boolean = false,
    thumbnail: @Composable BoxScope.() -> Unit,
    stats: @Composable RowScope.() -> Unit,
) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Layout(
        modifier = Modifier
            .fillMaxWidth()
            .cardShadow(shape)
            .clip(shape)
            .background(p.secondaryBackground, shape)
            .border(0.5.dp, p.text.copy(alpha = 0.1f), shape),
        content = {
            Box(Modifier.background(if (isStudio) p.studioHeader else Color.Gray.copy(alpha = PlaceholderOpacity))) {
                thumbnail()
                Text(
                    "#$place",
                    fontSize = 9.sp, fontWeight = FontWeight.Bold, color = p.text, maxLines = 1,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(end = 4.dp, bottom = 4.dp)
                        .background(p.background.copy(alpha = 0.72f), RoundedCornerShape(50))
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }
            Column(
                Modifier.padding(top = 10.dp, bottom = 10.dp, end = 10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold), color = p.text,
                    maxLines = titleMaxLines, overflow = TextOverflow.Ellipsis, modifier = Modifier.fillMaxWidth(),
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Top, content = stats)
            }
        },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val spacing = 12.dp.roundToPx()
        val thumb = measurables[0]
        val content = measurables[1]
        val thumbW = if (thumbAspectRatio != null && thumbAspectRatio > 0f) {
            val firstPassHeight = content.maxIntrinsicHeight((width - thumbWidth.roundToPx() - spacing).coerceAtLeast(0))
            (firstPassHeight * thumbAspectRatio).roundToInt().coerceAtMost(width / 2)
        } else {
            thumbWidth.roundToPx()
        }
        val contentW = (width - thumbW - spacing).coerceAtLeast(0)
        val contentPlaceable = content.measure(Constraints(minWidth = contentW, maxWidth = contentW))
        val height = contentPlaceable.height
        val thumbPlaceable = thumb.measure(Constraints.fixed(thumbW, height))
        layout(width, height) {
            thumbPlaceable.place(0, 0)
            contentPlaceable.place(thumbW + spacing, 0)
        }
    }
}

/** Thumbnail image filling the slot (iOS `CustomAsyncImage` + `scaledToFill`). */
@Composable
private fun BoxScope.ThumbImage(url: String?, placeholder: ImageVector, alignment: Alignment = Alignment.Center) {
    PlaceholderIcon(placeholder, Modifier.align(Alignment.Center))
    if (url != null) {
        AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = alignment)
    }
}

@Composable
private fun PlaceholderIcon(icon: ImageVector, modifier: Modifier = Modifier) {
    Icon(icon, null, tint = StashyColors.appAccent.copy(alpha = 0.45f), modifier = modifier.size(26.dp))
}

/** iOS: `TopListsStatColumn` — tiny uppercase caption over a big monospaced value. */
@Composable
private fun RowScope.StatColumn(title: String, value: String, emphasized: Boolean) {
    val p = Theme.palette
    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(title.uppercase(), fontSize = 8.sp, lineHeight = 10.sp, color = p.secondaryText, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        ShrinkingText(
            value,
            IosTypography.title2.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum", textAlign = TextAlign.Center),
            if (emphasized) p.text else p.secondaryText,
            minScale = 0.55f,
        )
    }
}

/** One-line text that shrinks down to [minScale] to fit (iOS `minimumScaleFactor`). */
@Composable
private fun ShrinkingText(text: String, style: TextStyle, color: Color, minScale: Float) {
    // Shrink-to-fit never goes below the size the text has at the default (1×) font scale, so a
    // large system font is honoured at least up to the normal size.
    val floor = maxOf(minScale, 1f / LocalDensity.current.fontScale.coerceAtLeast(1f))
    var scale by remember(text) { mutableFloatStateOf(1f) }
    var ready by remember(text) { mutableStateOf(false) }
    Text(
        text,
        style = style.copy(
            fontSize = if (style.fontSize.isSpecified) style.fontSize * scale else style.fontSize,
            lineHeight = if (style.lineHeight.isSpecified) style.lineHeight * scale else style.lineHeight,
        ),
        color = color,
        maxLines = 1,
        softWrap = false,
        modifier = Modifier.drawWithContent { if (ready) drawContent() },
        onTextLayout = { result ->
            if (result.hasVisualOverflow && scale > floor) {
                scale = (scale * 0.9f).coerceAtLeast(floor)
            } else {
                ready = true
            }
        },
    )
}

/** iOS: `StandardLoadingView(message:)`. */
@Composable
private fun ChartsLoadingView(message: String) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(color = p.text)
        Text(message, style = IosTypography.subheadline, color = p.secondaryText)
    }
}

/** iOS: `ConnectionErrorView` — "Server not reachable" with a retry button. */
@Composable
private fun ChartsConnectionError(onRetry: () -> Unit) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxSize().padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(SF.server, null, tint = p.secondaryText, modifier = Modifier.size(56.dp))
        Text("Server not reachable", style = IosTypography.title3, color = p.text, textAlign = TextAlign.Center)
        TextButton(
            onClick = onRetry,
            modifier = Modifier.background(Appearance.tint, RoundedCornerShape(Tokens.Radius.button)),
        ) {
            Text("Retry Connection", style = IosTypography.headline, color = Color.White)
        }
    }
}
