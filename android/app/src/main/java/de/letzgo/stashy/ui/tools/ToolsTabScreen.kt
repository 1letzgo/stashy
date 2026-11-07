package de.letzgo.stashy.ui.tools

import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.scaledMaxLines
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.noRippleClickable
import de.letzgo.stashy.ui.tools.charts.ChartsToolView
import de.letzgo.stashy.ui.tools.downloads.DownloadsToolView
import de.letzgo.stashy.ui.tools.match.MatchToolView
import de.letzgo.stashy.ui.tools.rateme.RateMeToolView
import de.letzgo.stashy.ui.tools.stats.OCountHeatmapToolView
import de.letzgo.stashy.ui.tools.stats.OverviewToolView
import de.letzgo.stashy.ui.tools.stats.SessionTimelineToolView

/** iOS: `ToolsView.ToolsTab` — raw values are the titles (`coordinator.toolsSubTab`). */
enum class ToolsTab(val title: String, val icon: ImageVector) {
    Downloads("Downloads", SF.squareAndArrowDown),
    Watchlist("Watchlist", de.letzgo.stashy.ui.player.WatchlistIcons.listed),
    Overview("Overview", SF.chartBarFill),
    OCount("O-Count", SF.calendar),
    Timeline("Timeline", SF.calendarDayTimelineLeft),
    TopLists("Charts", SF.listNumber),
    HotOrNot("Match", SF.flameFill),
    RateMe("RateMe", SF.starFill);

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.title == raw }

        /**
         * iOS: `ToolsView.visibleToolGroups` — fixed grouping and order; Settings › stashy+ ›
         * Miniplayer & Watchlist off: no Watchlist tool either.
         */
        val groups: List<Pair<String, List<ToolsTab>>> get() = listOf(
            "Library" to if (de.letzgo.stashy.data.TabManager.isMiniPlayerEnabled) listOf(Downloads, Watchlist) else listOf(Downloads),
            "Insights" to listOf(Overview, TopLists, OCount, Timeline),
            "Discover" to listOf(HotOrNot, RateMe),
        )
        val sorted: List<ToolsTab> get() = groups.flatMap { it.second }
    }
}

/**
 * iOS: `NavigationCoordinator.toolsSubTab` — empty means the landing grid. In memory only, like
 * iOS. Other screens can deep-link into a tool with [openTool].
 */
object ToolsNav {
    var subTab by mutableStateOf("")

    /** Switches to the Tools tab and opens [tool] (no-op target while stashy+ is locked). */
    fun openTool(tool: ToolsTab) {
        subTab = tool.title
        de.letzgo.stashy.ui.Nav.tab = de.letzgo.stashy.ui.MainTab.Tools
        de.letzgo.stashy.ui.Nav.popToRoot(de.letzgo.stashy.ui.MainTab.Tools)
    }
}

/** iOS: `ToolsView`, or the stashy+ paywall tab (`SettingsView(stashyPlusOnly: true)`) while locked. */
@Composable
fun ToolsTabScreen() {
    if (!StashyPlus.isUnlocked) {
        StashyPlusPaywallContent()
        return
    }
    ToolsView()
}

/**
 * iOS: `ToolsView` — like Home, the tool grid is the root and a tool is a page pushed onto it
 * (system back returns to the grid, see `AppShell`). The grid's row reads Tools › every tool as
 * an icon; a tool's row reads Tools › tool menu (› the tool's own control, see
 * [toolsWithOwnControls]). Picking another tool from the menu swaps it in place.
 */
@Composable
private fun ToolsView() {
    LaunchedEffect(Unit) {
        ToolsConfig.repairMissingToolsIfNeeded()
        normalizeToolsSubTab()
    }
    LaunchedEffect(StashyPlus.isUnlocked, de.letzgo.stashy.data.TabManager.isMiniPlayerEnabled) { normalizeToolsSubTab() }
    val selected = ToolsTab.from(ToolsNav.subTab)?.takeIf { it in ToolsTab.sorted }
    val p = Theme.palette
    AnimatedContent(
        targetState = selected,
        // Push / pop between the grid and a tool; switching tools from the menu is instant.
        contentKey = { it == null },
        transitionSpec = {
            when {
                initialState == null && targetState != null ->
                    slideInHorizontally { it } togetherWith slideOutHorizontally { -it / 3 }
                initialState != null && targetState == null ->
                    slideInHorizontally { -it / 3 } togetherWith slideOutHorizontally { it }
                else -> EnterTransition.None togetherWith ExitTransition.None
            }
        },
        label = "toolsPush",
    ) { tool ->
        Box(Modifier.fillMaxSize().background(p.background)) {
            if (tool == null) {
                ToolsLandingView { ToolsNav.subTab = it.title }
                ToolsStrip()
            } else {
                ToolPage(tool)
            }
        }
    }
}

/**
 * iOS: `ToolsView.toolsWithOwnControls` — tools that put their own control (metric / theme /
 * filter menu) at the right of the Tools row and draw the row themselves ([ToolsBreadcrumbChrome]).
 */
private val toolsWithOwnControls = setOf(ToolsTab.TopLists, ToolsTab.RateMe, ToolsTab.Timeline)

/** iOS: `toolPage` + `ToolPageChrome` — the tool with its Tools row. */
@Composable
private fun ToolPage(tool: ToolsTab) {
    val context = ToolsBreadcrumbContext(ToolsTab.sorted, tool) { ToolsNav.subTab = it?.title ?: "" }
    val drawsOwnRow = tool in toolsWithOwnControls
    CompositionLocalProvider(LocalToolsBreadcrumb provides context.takeIf { drawsOwnRow }) {
        when (tool) {
            ToolsTab.Downloads -> DownloadsToolView()
            ToolsTab.Watchlist -> de.letzgo.stashy.ui.tools.watchlist.WatchlistToolView()
            ToolsTab.Overview -> OverviewToolView()
            ToolsTab.OCount -> OCountHeatmapToolView()
            ToolsTab.Timeline -> SessionTimelineToolView()
            ToolsTab.TopLists -> ChartsToolView()
            ToolsTab.HotOrNot -> MatchToolView()
            ToolsTab.RateMe -> RateMeToolView()
        }
    }
    if (!drawsOwnRow) ToolsBreadcrumbStrip(context)
}

/** iOS: `normalizeToolsSubTab()` — legacy names map to their tools, unknown → landing grid. */
private fun normalizeToolsSubTab() {
    val raw = ToolsNav.subTab
    ToolsNav.subTab = when {
        raw == "Hot or Not" || raw == "Server" -> ToolsTab.sorted.first().title
        raw == "Statistics" -> ToolsTab.Overview.title
        raw == "Top 10" || raw == "Top" -> ToolsTab.TopLists.title
        ToolsTab.from(raw)?.takeIf { it in ToolsTab.sorted } == null -> ""
        else -> raw
    }
}

/**
 * iOS: `ToolsBreadcrumbRow(current: nil)` on the grid — Tools (grid icon, highlighted) pinned at
 * the left, every tool as an icon beside it; tapping one opens that tool. Same native strip as
 * the Home dashboard row.
 */
@Composable
private fun ToolsStrip() {
    val items: List<ToolsTab?> = listOf<ToolsTab?>(null) + ToolsTab.sorted
    de.letzgo.stashy.ui.NativeTabStrip(items, null, { it?.title ?: "Tools" }, { tool -> tool?.let { ToolsNav.subTab = it.title } }, icon = { it?.icon ?: de.letzgo.stashy.ui.SF.squareGrid2x2 }, pinFirst = true)
}

/**
 * iOS: `ToolsLandingView` — every tool as an icon tile in fixed groups; two columns (three when
 * wide), tiles built like `TagCardView` (grey 2.2:1 header with the tinted glyph, bold name).
 */
@Composable
private fun ToolsLandingView(onSelect: (ToolsTab) -> Unit) {
    val p = Theme.palette
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = if (maxWidth >= 600.dp) 3 else 2
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                .padding(horizontal = ToolsTokens.contentPadding)
                .padding(top = toolsTopPadding() + ToolsTokens.menuTopPadding, bottom = bottomBarContentPadding()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            ToolsTab.groups.forEach { (title, tools) ->
                Column {
                    // Material section header, as in Settings.
                    de.letzgo.stashy.ui.NativeSectionHeader(title)
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        tools.chunked(columns).forEach { row ->
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                row.forEach { tool -> ToolTile(tool, Modifier.weight(1f)) { onSelect(tool) } }
                                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ToolTile(tool: ToolsTab, modifier: Modifier, onClick: () -> Unit) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Column(
        modifier.cardShadow(shape).clip(shape).background(p.secondaryBackground).noRippleClickable(onClick),
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(2.2f).background(p.studioHeader), contentAlignment = Alignment.Center) {
            Icon(tool.icon, null, tint = Appearance.tint, modifier = Modifier.size(34.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp)) {
            Text(
                tool.title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold), color = p.text,
                maxLines = scaledMaxLines(), overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
