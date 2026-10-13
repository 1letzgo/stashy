package de.letzgo.stashy.ui.tools.stats

import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.scaledMaxLines
import de.letzgo.stashy.ui.scaledIconSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.OverviewStatistics
import de.letzgo.stashy.data.tools.OverviewStatsRepository
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.launch
import java.text.DecimalFormat
import java.text.NumberFormat
import kotlin.math.roundToLong

/**
 * iOS: `ToolsStatisticsView` (MainTabView.swift) wrapping `ServerStatisticsView`
 * (Settings/ServerStatisticsView.swift) — Playback hero, Catalogs tiles and Storage card.
 */
@Composable
fun OverviewToolView() {
    val config = ServerConfigManager.activeConfig
    if (config == null) {
        NoServerPlaceholder(Icons.Filled.BarChart, "Select a server in Settings to view statistics.")
        return
    }
    ServerStatisticsContent(config.id)
}

/** iOS: `ServerStatisticsView`. */
@Composable
private fun ServerStatisticsContent(serverID: String) {
    val repo = OverviewStatsRepository
    val scope = rememberCoroutineScope()
    var hasAttemptedLoad by remember(serverID) { mutableStateOf(false) }
    var didFailLoad by remember(serverID) { mutableStateOf(false) }

    fun reload() {
        hasAttemptedLoad = true
        didFailLoad = false
        scope.launch { didFailLoad = !repo.fetch() }
    }

    LaunchedEffect(serverID) { reload() }

    val stats = repo.statistics
    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        when {
            stats != null -> Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = ToolsTokens.contentPadding)
                    .padding(top = toolsTopPadding() + ToolsTokens.menuTopPadding, bottom = bottomBarContentPadding()),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                HeroCard(stats)
                CatalogsCard(stats)
                StorageCard(stats)
            }
            !hasAttemptedLoad || (!didFailLoad && repo.errorMessage == null) ->
                InsightsLoading("Loading statistics...", Modifier.fillMaxSize())
            else -> InsightsConnectionError(onRetry = { reload() })
        }
    }
}

// MARK: - Hero

@Composable
private fun HeroCard(stats: OverviewStatistics) {
    val unplayed = maxOf(0, stats.sceneCount - stats.scenesPlayed)
    val avgWatch = if (stats.totalPlayCount > 0) stats.totalPlayDuration / stats.totalPlayCount else 0.0

    StatsCard("Playback") {
        val entries = listOf(
            Triple(Icons.Filled.Schedule, statDuration(stats.totalPlayDuration), "Watch Time"),
            Triple(oCounterIcon(Appearance.oCounterIcon, filled = true), statCount(stats.totalOCount), "O-Count"),
            Triple(SF.playFill, statCount(stats.totalPlayCount), "Play Count"),
            Triple(Icons.Filled.PieChart, playedShare(stats.scenesPlayed, stats.sceneCount), "Played Share"),
        )
        Column(
            Modifier.padding(horizontal = 16.dp).padding(top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            entries.chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(ToolsTokens.rankedGridSpacing)) {
                    row.forEach { (icon, value, label) -> HeroStat(icon, value, label, Modifier.weight(1f)) }
                }
            }
        }
        Text(
            "Library ${statDuration(stats.scenesDuration)}  ·  Ø ${statDuration(avgWatch)}/play  ·  ${statCount(unplayed)} unplayed",
            style = NativeType.bodySmall,
            color = Theme.palette.secondaryText,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 6.dp, bottom = 12.dp),
        )
    }
}

@Composable
private fun HeroStat(icon: ImageVector, value: String, label: String, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(scaledIconSize(24.dp, maxScale = 1.4f)))
        Text(
            value,
            style = NativeType.headlineSmall.monoDigits(),
            color = p.text, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
        )
        Text(label, style = NativeType.bodyMedium, color = p.secondaryText, maxLines = scaledMaxLines(), overflow = TextOverflow.Ellipsis)
    }
}

// MARK: - Catalogs

private data class CatalogStatEntry(val title: String, val value: Int, val icon: ImageVector, val tab: CatalogTab)

@Composable
private fun CatalogsCard(stats: OverviewStatistics) {
    val entries = listOf(
        CatalogStatEntry("Scenes", stats.sceneCount, SF.film, CatalogTab.Scenes),
        CatalogStatEntry("Performers", stats.performerCount, SF.person2, CatalogTab.Performers),
        CatalogStatEntry("Galleries", stats.galleryCount, SF.photoStack, CatalogTab.Galleries),
        CatalogStatEntry("Images", stats.imageCount, SF.photo, CatalogTab.Images),
        CatalogStatEntry("Markers", stats.sceneMarkerCount ?: 0, SF.bookmarkFill, CatalogTab.Markers),
        CatalogStatEntry("Studios", stats.studioCount, SF.building2, CatalogTab.Studios),
        CatalogStatEntry("Groups", stats.groupCount, SF.rectangleStackFill, CatalogTab.Groups),
        CatalogStatEntry("Tags", stats.tagCount, SF.tag, CatalogTab.Tags),
    )
    StatsCard("Catalogs") {
        entries.forEachIndexed { index, entry ->
            if (index > 0) NativeDivider()
            NativeListItem(entry.title, icon = entry.icon, onClick = { Nav.openCatalog(entry.tab) }) {
                Text(statCount(entry.value), style = NativeType.bodyMedium.monoDigits(), color = Theme.palette.secondaryText, maxLines = 1)
            }
        }
    }
}

// MARK: - Storage

@Composable
private fun StorageCard(stats: OverviewStatistics) {
    StatsCard("Storage") {
        StatRow("Scenes", formatBytes(stats.scenesSize))
        NativeDivider()
        StatRow("Images", formatBytes(stats.imagesSize))
        NativeDivider()
        StatRow("Total", formatBytes(stats.scenesSize + stats.imagesSize), emphasize = true)
    }
}

@Composable
private fun StatRow(title: String, value: String, emphasize: Boolean = false) {
    val p = Theme.palette
    NativeListItem(title) {
        Text(value, style = NativeType.bodyMedium.monoDigits(), color = if (emphasize) p.text else p.secondaryText)
    }
}

/** iOS `statsCard(title:content:)` — Material section header above a Material group, as in Settings. */
@Composable
private fun StatsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        InsightsSectionHeading(title)
        NativeGroup(content = content)
    }
}

// MARK: - Formatting (iOS helpers of ServerStatisticsView)

/** iOS `formatDuration` — `12h 5m` / `42m`. */
private fun statDuration(seconds: Double): String {
    val total = seconds.roundToLong()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    return if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
}

/** iOS `NumberFormatter.decimal` with the current locale. */
private fun statCount(value: Int): String = NumberFormat.getIntegerInstance().format(value)

private fun playedShare(played: Int, total: Int): String =
    if (total <= 0) "—" else String.format("%.0f%%", played.toDouble() / total * 100)

/** iOS `ByteCountFormatter` (file style, GB/MB/KB, decimal units). */
private fun formatBytes(bytes: Double): String {
    if (bytes <= 0) return "Zero KB"
    fun fmt(value: Double, digits: Int) = (DecimalFormat.getInstance() as DecimalFormat).apply {
        maximumFractionDigits = digits
        minimumFractionDigits = 0
    }.format(value)
    return when {
        bytes >= 1e9 -> "${fmt(bytes / 1e9, 2)} GB"
        bytes >= 1e6 -> "${fmt(bytes / 1e6, 1)} MB"
        else -> "${fmt(maxOf(1.0, bytes / 1e3), 0)} KB"
    }
}
