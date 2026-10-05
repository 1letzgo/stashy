package de.letzgo.stashy.ui.tools

import de.letzgo.stashy.ui.scaledMaxLines
import androidx.compose.foundation.background
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
import de.letzgo.stashy.ui.tools.filters.FiltersToolView
import de.letzgo.stashy.ui.tools.match.MatchToolView
import de.letzgo.stashy.ui.tools.merge.StudioMergeToolView
import de.letzgo.stashy.ui.tools.merge.TagMergeToolView
import de.letzgo.stashy.ui.tools.rateme.RateMeToolView
import de.letzgo.stashy.ui.tools.stats.OCountHeatmapToolView
import de.letzgo.stashy.ui.tools.stats.OverviewToolView
import de.letzgo.stashy.ui.tools.stats.SessionTimelineToolView

/** iOS: `ToolsView.ToolsTab` — raw values are the titles (`coordinator.toolsSubTab`). */
enum class ToolsTab(val title: String, val icon: ImageVector) {
    Downloads("Downloads", SF.squareAndArrowDown),
    Overview("Overview", SF.chartBarFill),
    OCount("O-Count", SF.calendar),
    Timeline("Timeline", SF.calendarDayTimelineLeft),
    TopLists("Charts", SF.listNumber),
    Filters("Filters", SF.line3HorizontalDecreaseCircle),
    MergeTags("Merge Tags", SF.arrowTriangleMerge),
    MergeStudios("Merge Studios", SF.building2),
    HotOrNot("Match", SF.flameFill),
    RateMe("RateMe", SF.starFill);

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.title == raw }

        /** iOS: `ToolsView.toolGroups` — fixed grouping and order. */
        val groups: List<Pair<String, List<ToolsTab>>> = listOf(
            "Library" to listOf(Downloads, Filters, MergeTags, MergeStudios),
            "Insights" to listOf(Overview, TopLists, OCount, Timeline),
            "Discover" to listOf(HotOrNot, RateMe),
        )
        val sorted: List<ToolsTab> = groups.flatMap { it.second }
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

/** iOS: `ToolsView` — landing grid or the selected tool, with the tool strip on top. */
@Composable
private fun ToolsView() {
    LaunchedEffect(Unit) {
        ToolsConfig.repairMissingToolsIfNeeded()
        normalizeToolsSubTab()
    }
    LaunchedEffect(StashyPlus.isUnlocked) { normalizeToolsSubTab() }
    val selected = ToolsTab.from(ToolsNav.subTab)?.takeIf { it in ToolsTab.sorted }
    val p = Theme.palette
    Box(Modifier.fillMaxSize().background(p.background)) {
        when (selected) {
            null -> ToolsLandingView { ToolsNav.subTab = it.title }
            ToolsTab.Downloads -> DownloadsToolView()
            ToolsTab.Overview -> OverviewToolView()
            ToolsTab.OCount -> OCountHeatmapToolView()
            ToolsTab.Timeline -> SessionTimelineToolView()
            ToolsTab.TopLists -> ChartsToolView()
            ToolsTab.Filters -> FiltersToolView()
            ToolsTab.MergeTags -> TagMergeToolView()
            ToolsTab.MergeStudios -> StudioMergeToolView()
            ToolsTab.HotOrNot -> MatchToolView()
            ToolsTab.RateMe -> RateMeToolView()
        }
        ToolsStrip(selected)
    }
}

/** iOS: `normalizeToolsSubTab()` — legacy names map to their tools, unknown → landing grid. */
private fun normalizeToolsSubTab() {
    val raw = ToolsNav.subTab
    ToolsNav.subTab = when {
        raw == "Hot or Not" || raw == "Server" -> ToolsTab.sorted.first().title
        raw == "Statistics" -> ToolsTab.Overview.title
        raw == "Top 10" || raw == "Top" -> ToolsTab.TopLists.title
        ToolsTab.from(raw) == null -> ""
        else -> raw
    }
}

/**
 * iOS: `toolsDropdown` (`StashyTopNavNameDropdownRow` with the pinned "Tools" entry): the pinned
 * grid chip stays left, the tools scroll beside it; selected = labelled glass capsule.
 */
@Composable
private fun ToolsStrip(selected: ToolsTab?) {
    // First tab = the landing grid ("Tools"), then every enabled tool (native Material tabs).
    val items: List<ToolsTab?> = listOf<ToolsTab?>(null) + ToolsTab.sorted
    de.letzgo.stashy.ui.NativeTabStrip(items, selected, { it?.title ?: "Tools" }, { ToolsNav.subTab = it?.title ?: "" }, icon = { it?.icon ?: de.letzgo.stashy.ui.SF.squareGrid2x2 }, pinFirst = true)
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
                .padding(top = toolsTopPadding() + ToolsTokens.menuTopPadding, bottom = ToolsBottomPadding),
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
