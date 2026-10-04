package de.letzgo.stashy.ui.tools.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.GraphQLQueries
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.tools.OCountHeatmapBucketing
import de.letzgo.stashy.data.tools.OCountHeatmapItem
import de.letzgo.stashy.data.tools.OCountHeatmapLoader
import de.letzgo.stashy.data.tools.OCountMonthHeatmap
import de.letzgo.stashy.data.tools.asImage
import de.letzgo.stashy.data.tools.asScene
import de.letzgo.stashy.data.tools.thumbnailURL
import de.letzgo.stashy.data.vars
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tools.ToolsBottomPadding
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.launch
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** iOS: `OCountHeatmapToolsView` (Settings/OCountHeatmapCard.swift). */
@Composable
fun OCountHeatmapToolView() {
    val scope = rememberCoroutineScope()
    val config = ServerConfigManager.activeConfig
    if (config == null) {
        InsightsConnectionError(onRetry = { scope.launch { OCountHeatmapLoader.reload() } })
        return
    }
    var refreshing by remember { mutableStateOf(false) }
    val top = toolsTopPadding() + ToolsTokens.menuTopPadding
    InsightsRefreshBox(
        isRefreshing = refreshing,
        onRefresh = { scope.launch { refreshing = true; OCountHeatmapLoader.reload(); refreshing = false } },
        indicatorTop = top,
        modifier = Modifier.background(Theme.palette.background),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = ToolsTokens.contentPadding)
                .padding(top = top, bottom = ToolsBottomPadding),
        ) {
            OCountHeatmapCard()
        }
    }
}

/** iOS: `OCountHeatmapMetrics`. */
private object HeatmapMetrics {
    val cardPaddingH = 12.dp
    val cardPaddingV = 12.dp
    val weekdayHeaderHeight = 16.dp
    val legendHeight = 14.dp
    val legendTopPadding = 8.dp
    val minColumnGap = 4.dp
    val rowGap = 4.dp
    const val dayCellScale = 0.84f
    val bodySpacing = 8.dp
}

/** iOS: `OCountMonthHeatmapLayout`. */
private data class HeatmapLayout(val blockSize: Dp, val columnGap: Dp, val gridWidth: Dp) {
    companion object {
        fun make(containerWidth: Dp, columns: Int = 7): HeatmapLayout {
            val contentWidth = max(0f, containerWidth.value - 2 * HeatmapMetrics.cardPaddingH.value)
            val n = columns.toFloat()
            val minGap = HeatmapMetrics.minColumnGap.value
            val rawBlock = max(24f, (contentWidth - (n - 1) * minGap) / n)
            val block = floor(rawBlock * HeatmapMetrics.dayCellScale)
            val gap = if (n > 1) max(minGap, (contentWidth - n * block) / (n - 1)) else 0f
            return HeatmapLayout(block.dp, gap.dp, (n * block + max(0f, n - 1) * gap).dp)
        }

        /** iOS: `estimatedCalendarCardHeight(containerWidth:rowCount:)`. */
        fun estimatedHeight(containerWidth: Dp, rowCount: Int): Dp {
            val l = make(containerWidth)
            val gridH = l.blockSize * rowCount + HeatmapMetrics.rowGap * max(0, rowCount - 1)
            return HeatmapMetrics.cardPaddingV + HeatmapMetrics.weekdayHeaderHeight + HeatmapMetrics.bodySpacing + gridH +
                HeatmapMetrics.bodySpacing + HeatmapMetrics.legendTopPadding + HeatmapMetrics.legendHeight
        }
    }
}

/** Monday-first two-letter weekday labels (iOS `shortWeekdaySymbols.prefix(2)`, en_US). */
private val weekdayLabels = listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")

/**
 * iOS: `OCountHeatmapCard` — month calendar of scene + image O-Count, a summary card and the
 * items of the selected day. Public so the dashboard can embed it.
 */
@Composable
fun OCountHeatmapCard(modifier: Modifier = Modifier) {
    val loader = OCountHeatmapLoader
    val serverID = ServerConfigManager.activeConfig?.id
    var monthsBack by rememberSaveable(serverID) { mutableIntStateOf(0) }
    var selectedDayKey by rememberSaveable(serverID) { mutableStateOf<String?>(null) }
    var didAutoJump by rememberSaveable(serverID) { mutableStateOf(false) }

    val currentMonth = YearMonth.now(loader.zone)
    val visibleMonth = currentMonth.minusMonths(monthsBack.toLong())
    val maxMonthsBack = loader.earliestMonthStart()?.let { max(0, OCountHeatmapBucketing.monthsBetween(it, currentMonth)) } ?: 0
    val canGoBack = monthsBack < maxMonthsBack
    val canGoForward = monthsBack > 0
    @Suppress("UNUSED_VARIABLE") val revision = loader.revision
    val heatmap = loader.monthHeatmap(visibleMonth)

    fun syncSelectedDay(h: OCountMonthHeatmap) {
        val key = selectedDayKey ?: return
        if (h.cells.none { it.id == key && it.isInDisplayedMonth }) selectedDayKey = null
    }

    fun autoJumpToLatestMonthIfNeeded() {
        if (didAutoJump) return
        didAutoJump = true
        if (loader.monthHeatmap(currentMonth).totalInMonth != 0) return
        val latest = loader.latestMonthStart() ?: return
        monthsBack = max(0, OCountHeatmapBucketing.monthsBetween(latest, currentMonth))
    }

    LaunchedEffect(serverID) {
        loader.loadIfNeeded()
        autoJumpToLatestMonthIfNeeded()
    }
    LaunchedEffect(monthsBack) { syncSelectedDay(loader.monthHeatmap(currentMonth.minusMonths(monthsBack.toLong()))) }
    LaunchedEffect(loader.countsByDay) {
        if (loader.isReady) autoJumpToLatestMonthIfNeeded()
        val maxBack = loader.earliestMonthStart()?.let { max(0, OCountHeatmapBucketing.monthsBetween(it, currentMonth)) } ?: 0
        if (monthsBack > maxBack) monthsBack = maxBack
        syncSelectedDay(loader.monthHeatmap(currentMonth.minusMonths(monthsBack.toLong())))
    }

    // 16 pt between the cards — same spacing as Tools → Overview.
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.md)) {
        CalendarCard(
            heatmap = heatmap,
            isLoadingEmpty = loader.isLoading && loader.countsByDay.isEmpty(),
            canGoBack = canGoBack,
            canGoForward = canGoForward,
            selectedDayKey = selectedDayKey,
            onBack = { monthsBack += 1 },
            onForward = { monthsBack -= 1 },
            onJumpToCurrent = { monthsBack = 0; selectedDayKey = null },
            onSelectDay = { key -> selectedDayKey = if (selectedDayKey == key) null else key },
        )
        SummaryCard(heatmap, selectedDayKey)
        selectedDayKey?.let { DayItemsList(loader.items(it)) }
    }
}

@Composable
private fun CalendarCard(
    heatmap: OCountMonthHeatmap,
    isLoadingEmpty: Boolean,
    canGoBack: Boolean,
    canGoForward: Boolean,
    selectedDayKey: String?,
    onBack: () -> Unit,
    onForward: () -> Unit,
    onJumpToCurrent: () -> Unit,
    onSelectDay: (String) -> Unit,
) {
    Column(
        Modifier.fillMaxWidth().insightsCard().padding(bottom = 4.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        MonthTitleRow(heatmap.monthTitle, canGoBack, canGoForward, showsJumpToCurrent = canGoForward, onBack, onForward, onJumpToCurrent)
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val width = maxWidth
            if (isLoadingEmpty) {
                InsightsLoading("Loading O-Count...", Modifier.fillMaxWidth().height(HeatmapLayout.estimatedHeight(320.dp, 6)))
            } else {
                CalendarContent(heatmap, HeatmapLayout.make(width), selectedDayKey, onSelectDay)
            }
        }
    }
}

/** iOS: `OCountMonthTitleView`. */
@Composable
private fun MonthTitleRow(
    title: String,
    canGoBack: Boolean,
    canGoForward: Boolean,
    showsJumpToCurrent: Boolean,
    onBack: () -> Unit,
    onForward: () -> Unit,
    onJumpToCurrent: () -> Unit,
) {
    val p = Theme.palette
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ChevronButton(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous month", canGoBack, onBack)
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Text(
                title,
                style = IosTypography.title3.copy(fontWeight = FontWeight.SemiBold),
                color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = if (showsJumpToCurrent) Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onJumpToCurrent,
                ) else Modifier,
            )
        }
        ChevronButton(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next month", canGoForward, onForward)
    }
}

@Composable
private fun ChevronButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    val p = Theme.palette
    Box(
        Modifier.size(28.dp).clip(CircleShape).clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, label, tint = if (enabled) p.text else p.secondaryText.copy(alpha = 0.35f), modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun CalendarContent(heatmap: OCountMonthHeatmap, layout: HeatmapLayout, selectedDayKey: String?, onSelectDay: (String) -> Unit) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxWidth().padding(horizontal = HeatmapMetrics.cardPaddingH).padding(bottom = HeatmapMetrics.cardPaddingV),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(HeatmapMetrics.bodySpacing),
    ) {
        Row(Modifier.width(layout.gridWidth), horizontalArrangement = Arrangement.spacedBy(layout.columnGap)) {
            for (col in 0 until 7) {
                Box(Modifier.width(layout.blockSize).height(HeatmapMetrics.weekdayHeaderHeight), contentAlignment = Alignment.Center) {
                    Text(weekdayLabels[col], style = IosTypography.caption2.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText, maxLines = 1)
                }
            }
        }
        Column(Modifier.width(layout.gridWidth), verticalArrangement = Arrangement.spacedBy(HeatmapMetrics.rowGap)) {
            for (row in 0 until heatmap.rowCount) {
                Row(horizontalArrangement = Arrangement.spacedBy(layout.columnGap)) {
                    for (col in 0 until 7) {
                        val cell = heatmap.cell(col, row)
                        DayCell(cell, layout.blockSize, isSelected = cell != null && cell.id == selectedDayKey, onSelectDay)
                    }
                }
            }
        }
        Legend(layout.blockSize)
    }
}

/** iOS: `fillColor(level:)`. */
@Composable
private fun heatFill(level: Int): Color {
    val p = Theme.palette
    val accent = Appearance.tint
    val dark = p.isDark
    return when (level) {
        1 -> accent.copy(alpha = if (dark) 0.38f else 0.32f)
        2 -> accent.copy(alpha = if (dark) 0.56f else 0.50f)
        3 -> accent.copy(alpha = if (dark) 0.78f else 0.72f)
        4 -> accent
        else -> p.text.copy(alpha = if (dark) 0.08f else 0.06f)
    }
}

/** iOS: `outlineColor(level:)`. */
@Composable
private fun heatOutline(level: Int): Color =
    if (level == 0) Theme.palette.text.copy(alpha = 0.12f) else Appearance.tint.copy(alpha = if (Theme.palette.isDark) 0.35f else 0.5f)

/** iOS: `contrastingOnAccent` — black or white by the tint's luminance. */
private fun contrastingOn(accent: Color): Color {
    val luminance = 0.2126f * accent.red + 0.7152f * accent.green + 0.0722f * accent.blue
    return if (luminance > 0.62f) Color.Black else Color.White
}

@Composable
private fun DayCell(cell: OCountMonthHeatmap.Cell?, blockSize: Dp, isSelected: Boolean, onSelect: (String) -> Unit) {
    val p = Theme.palette
    val accent = Appearance.tint
    val inMonth = cell?.isInDisplayedMonth ?: false
    val level = if (inMonth) cell?.colorLevel ?: 0 else 0
    val day = cell?.day ?: 0
    val dayFont = max(8f, blockSize.value * 0.38f)
    val numberColor = when {
        !inMonth -> p.secondaryText.copy(alpha = 0.5f)
        (cell?.colorLevel ?: 0) >= 3 -> contrastingOn(accent)
        isSelected -> p.text
        else -> p.secondaryText
    }
    Box(
        Modifier
            .size(blockSize)
            .alpha(if (inMonth) 1f else 0.35f)
            .clip(CircleShape)
            .background(heatFill(level), CircleShape)
            .border(0.5.dp, heatOutline(level), CircleShape)
            .let { if (isSelected) it.border(2.dp, accent, CircleShape) else it }
            .let { m -> if (inMonth && cell != null) m.clickable { onSelect(cell.id) } else m }
            .semantics { contentDescription = cell?.accessibilityLabel ?: "No data" },
        contentAlignment = Alignment.Center,
    ) {
        if (day > 0) {
            Text(
                "$day",
                fontSize = dayFont.sp,
                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                fontFamily = FontFamily.SansSerif,
                style = IosTypography.caption2.monoDigits().copy(lineHeight = dayFont.sp),
                color = numberColor,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun Legend(blockSize: Dp) {
    val p = Theme.palette
    val dot = min(9f, max(5f, blockSize.value * 0.45f)).dp
    Row(
        Modifier.fillMaxWidth().padding(top = HeatmapMetrics.legendTopPadding),
        horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Less", style = IosTypography.caption2, color = p.secondaryText)
        for (level in 0 until 5) {
            Box(Modifier.size(dot).background(heatFill(level), CircleShape).border(0.5.dp, heatOutline(level), CircleShape))
        }
        Text("More", style = IosTypography.caption2, color = p.secondaryText)
    }
}

private val selectedDayFormatter = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)

@Composable
private fun SummaryCard(heatmap: OCountMonthHeatmap, selectedDayKey: String?) {
    val p = Theme.palette
    fun countLabel(count: Int) = if (count > 0) "$count" else "No O-Count"
    val selectedCell = selectedDayKey?.let { key -> heatmap.cells.firstOrNull { it.id == key && it.isInDisplayedMonth } }
    val (title, value) = if (selectedCell != null) {
        val date = OCountHeatmapBucketing.parseDayKey(selectedCell.id)
        (date?.let { selectedDayFormatter.format(it) } ?: selectedCell.id) to countLabel(selectedCell.count)
    } else {
        "O-Count" to countLabel(heatmap.totalInMonth)
    }
    Column(
        Modifier.fillMaxWidth().insightsCard().padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title.uppercase(), style = IosTypography.caption.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText, maxLines = 2)
        Text(value, style = IosTypography.title2.copy(fontWeight = FontWeight.Bold).monoDigits(), color = p.text, maxLines = 1)
    }
}

@Composable
private fun DayItemsList(items: List<OCountHeatmapItem>) {
    if (items.isEmpty()) return
    val scenes = items.filter { it.kind == OCountHeatmapItem.Kind.Scene }
    val images = items.filter { it.kind == OCountHeatmapItem.Kind.Image }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (scenes.isNotEmpty()) DayItemsSection("Scenes", scenes)
        if (images.isNotEmpty()) DayItemsSection("Images", images)
    }
}

@Composable
private fun DayItemsSection(title: String, items: List<OCountHeatmapItem>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        InsightsSectionHeading(title)
        items.forEach { item -> DayItemRow(item) { openOCountItem(item) } }
    }
}

/** iOS: `OCountMediaDestination` — scene detail or the (hydrated) image viewer. */
internal fun openOCountItem(item: OCountHeatmapItem) {
    when (item.kind) {
        OCountHeatmapItem.Kind.Scene -> Nav.push(SceneDetailScreen(item.stashID, item.asScene()))
        OCountHeatmapItem.Kind.Image -> Nav.push(OCountImageDestinationScreen(item))
    }
}

/** iOS: `OCountDayItemRow`. */
@Composable
private fun DayItemRow(item: OCountHeatmapItem, onClick: () -> Unit) {
    val p = Theme.palette
    val thumbHeight = 56.dp
    val thumbWidth = if (item.kind == OCountHeatmapItem.Kind.Scene) thumbHeight * 16f / 9f else thumbHeight
    val radius = Tokens.Radius.card
    Row(
        Modifier.fillMaxWidth().insightsCard().clickable(onClick = onClick).padding(end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ThumbPlaceholder(
            Modifier.width(thumbWidth).height(thumbHeight)
                .clip(RoundedCornerShape(topStart = radius, bottomStart = radius)),
        ) {
            Icon(
                when {
                    item.kind == OCountHeatmapItem.Kind.Scene -> SF.film
                    item.isVideo -> Icons.Outlined.Videocam
                    else -> SF.photo
                },
                null, tint = StashyColors.appAccent.copy(alpha = 0.45f), modifier = Modifier.size(22.dp),
            )
            item.thumbnailURL?.let { AsyncImage(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                item.displayTitle, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold),
                color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            val subtitle = if (item.kind == OCountHeatmapItem.Kind.Image && item.performers.isNotEmpty()) {
                if (item.title == "Untitled") item.kindTitle else item.performerNamesLine
            } else item.rowSubtitle
            Text(subtitle, style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text("${item.countOnDay}", style = IosTypography.title3.copy(fontWeight = FontWeight.Bold).monoDigits(), color = p.text)
    }
}

/**
 * iOS: `OCountImageDestination` — loads the full image (`findImage` with `ImageFields`) before
 * opening the full-screen viewer; falls back to the list stub on errors.
 */
class OCountImageDestinationScreen(private val item: OCountHeatmapItem) : Screen {
    override val key = "ocount-image-${item.stashID}"
    override val hidesTabBar = true

    @Composable
    override fun Content() {
        val stub = remember { item.asImage() }
        var images by remember { mutableStateOf<List<StashImage>?>(if (isPlayable(stub)) listOf(stub) else null) }
        LaunchedEffect(item.stashID) {
            val query = "query FindImageById(\$id: ID!) {\n  findImage(id: \$id) {\n    ...ImageFields\n  }\n}\n" +
                GraphQLQueries.load("fragment_ImageFields")
            val full = runCatching {
                GraphQL.data(query, vars("id" to item.stashID))["findImage"]
                    ?.takeIf { it is kotlinx.serialization.json.JsonObject }
                    ?.let { GraphQL.decode(StashImage.serializer(), it) }
            }.getOrNull()
            images = listOf(full ?: stub)
        }
        val ready = images
        if (ready != null) {
            val viewer = remember(ready) { ImageViewerScreen(ready, 0) }
            viewer.Content()
        } else {
            Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                InsightsLoading("Loading...")
            }
        }
    }

    private fun isPlayable(image: StashImage) = image.visualFiles != null || image.paths?.image != null || image.isVideo
}
