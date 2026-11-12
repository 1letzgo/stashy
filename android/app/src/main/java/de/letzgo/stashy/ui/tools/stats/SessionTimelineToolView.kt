package de.letzgo.stashy.ui.tools.stats

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.bottomBarContentPadding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ScenePaths
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.SessionTimelineGrouping
import de.letzgo.stashy.data.tools.SessionTimelineLoader
import de.letzgo.stashy.data.tools.TimelineKind
import de.letzgo.stashy.data.tools.TimelineKindFilter
import de.letzgo.stashy.data.tools.TimelineSceneSnapshot
import de.letzgo.stashy.data.tools.TimelineSession
import de.letzgo.stashy.data.tools.TimelineVisit
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayCircle
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.ToolsBreadcrumbChrome
import de.letzgo.stashy.ui.tools.ToolsMenuItem
import de.letzgo.stashy.ui.tools.ToolsMenuSectionHeader
import de.letzgo.stashy.ui.tools.ToolsRowMenu
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToLong

/** iOS: `SessionTimelineToolsView` (SessionTimelineToolsView.swift) — Tools → Timeline. */
@Composable
fun SessionTimelineToolView() {
    val loader = SessionTimelineLoader
    val scope = rememberCoroutineScope()
    val serverID = ServerConfigManager.activeConfig?.id
    var enabledKinds by remember { mutableStateOf(TimelineKindFilter.saved()) }

    LaunchedEffect(serverID) {
        if (serverID == null) return@LaunchedEffect
        if (loader.loadedServerID != null && loader.loadedServerID != serverID) loader.reset()
        loader.reload()
    }

    var refreshing by remember { mutableStateOf(false) }
    val top = toolsTopPadding()
    Box(Modifier.fillMaxSize().background(Theme.palette.background)) {
        if (serverID == null) {
            InsightsConnectionError(onRetry = { loader.reload() })
        } else {
            InsightsRefreshBox(
                isRefreshing = refreshing,
                onRefresh = { scope.launch { refreshing = true; loader.reload().join(); refreshing = false } },
                indicatorTop = top,
            ) {
                TimelineList(enabledKinds, top)
            }
        }
        // iOS: `toolsBreadcrumbChrome { kindMenu }` — which activity shows, in the Tools row.
        ToolsBreadcrumbChrome {
            TimelineKindMenu(enabledKinds) { kinds ->
                enabledKinds = kinds
                TimelineKindFilter.save(kinds)
            }
        }
    }
}

/**
 * iOS: `kindMenu` — Watch / O-Count / Markers as checkable items (it was a pill row above the
 * list). Several can be on; the last one stays. The menu stays open while toggling. Label: a
 * filter icon with a tint dot while not every kind shows.
 */
@Composable
private fun TimelineKindMenu(enabled: Set<TimelineKind>, onChange: (Set<TimelineKind>) -> Unit) {
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    ToolsRowMenu(
        icon = SF.line3HorizontalDecrease,
        accessibilityLabel = tr(R.string.action_show_activity),
        isActive = enabled.size < TimelineKind.entries.size,
    ) { _ ->
        ToolsMenuSectionHeader(tr(R.string.action_show))
        TimelineKind.entries.forEach { kind ->
            val on = kind in enabled
            ToolsMenuItem(kind.label, kindIcon(kind), checked = on) {
                if (on) {
                    if (enabled.size > 1) {
                        haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                        onChange(enabled - kind)
                    }
                } else {
                    haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                    onChange(enabled + kind)
                }
            }
        }
    }
}

/** iOS: `icon(for:)`. */
private fun kindIcon(kind: TimelineKind): androidx.compose.ui.graphics.vector.ImageVector = when (kind) {
    TimelineKind.Watch -> Icons.Outlined.PlayCircle
    TimelineKind.OCount -> de.letzgo.stashy.ui.oCounterIcon(Appearance.oCounterIcon)
    TimelineKind.Marker -> SF.bookmark
}

private data class TimelineDayGroup(val day: LocalDate, val sessions: List<TimelineSession>)

@Composable
private fun TimelineList(enabledKinds: Set<TimelineKind>, top: androidx.compose.ui.unit.Dp) {
    val loader = SessionTimelineLoader
    val p = Theme.palette
    val zone = ZoneId.systemDefault()
    val visibleDays = SessionTimelineGrouping.days(loader.sessions.mapNotNull { it.filtered(enabledKinds) }) {
        it.atZone(zone).toLocalDate()
    }.map { TimelineDayGroup(it.first, it.second) }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding,
            top = top + ToolsTokens.menuTopPadding, bottom = bottomBarContentPadding(),
        ),
    ) {
        when {
            loader.isLoading && loader.sessions.isEmpty() -> item(key = "loading") {
                InsightsLoading(tr(R.string.loading_timeline), Modifier.fillMaxWidth().padding(top = 40.dp))
            }
            loader.didFail && loader.sessions.isEmpty() -> item(key = "failed") {
                CenteredNote(tr(R.string.error_load_play_history_from_this))
            }
            visibleDays.isEmpty() -> item(key = "empty") {
                CenteredNote(
                    if (loader.sessions.isEmpty()) tr(R.string.hint_no_plays_o_counts_or)
                    else tr(R.string.empty_matching_activity_for_selected_filters),
                )
            }
            else -> visibleDays.forEachIndexed { index, day ->
                item(key = "day-${day.day}") {
                    Box(Modifier.padding(top = if (index == 0) 0.dp else 28.dp)) { TimelineDayBlock(day) }
                }
            }
        }
        if (loader.isLoadingMore) {
            item(key = "more-spinner") {
                Box(Modifier.fillMaxWidth().padding(top = 28.dp).padding(vertical = 16.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(22.dp), color = p.secondaryText, strokeWidth = 2.dp)
                }
            }
        } else if (loader.hasMore && !loader.isLoading && loader.sessions.isNotEmpty()) {
            item(key = "more-trigger") {
                LaunchedEffect(loader.sessions.size) { loader.loadMore() }
                Spacer(Modifier.height(1.dp))
            }
        }
    }
}

@Composable
private fun CenteredNote(text: String) {
    Text(
        text, style = IosTypography.subheadline, color = Theme.palette.secondaryText, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
    )
}

private val dayFormatter: DateTimeFormatter get() = DateTimeFormatter.ofPattern("EEEE, d MMM", Locale.getDefault())
private val timeFormatter: DateTimeFormatter get() = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault())

/** iOS: `TimelineDayBlock`. */
@Composable
private fun TimelineDayBlock(day: TimelineDayGroup) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(dayFormatter.format(day.day), style = IosTypography.title3.copy(fontWeight = FontWeight.SemiBold), color = Theme.palette.text)
        day.sessions.forEach { TimelineSessionBlock(it) }
    }
}

// iOS: `TimelineSessionBlock` static helpers.
private fun clockTime(date: Instant): String = timeFormatter.format(date.atZone(ZoneId.systemDefault()))
private fun clockRange(start: Instant, end: Instant) = "${clockTime(start)} – ${clockTime(end)}"
private fun clock(seconds: Double): String {
    val total = maxOf(0L, seconds.roundToLong())
    val h = total / 3600; val m = (total % 3600) / 60; val s = total % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s) else String.format(Locale.US, "%d:%02d", m, s)
}
private fun watchedLabel(seconds: Double): String {
    val minutes = maxOf(1L, (seconds / 60.0).roundToLong())
    return if (minutes < 60) tr(R.string.arg_m_watched, minutes) else tr(R.string.arg_h_m_watched, minutes / 60, minutes % 60)
}
private fun watchedLine(visit: TimelineVisit): String? {
    if (!visit.isPlayback) return null
    val watched = watchedLabel(visit.watchedSeconds)
    val start = visit.sceneStartSeconds?.takeIf { it >= 5 } ?: return watched
    return tr(R.string.arg_started_at_arg, clock(start)) + "  ·  " + watched
}

/** iOS: `TimelineSessionBlock`. */
@Composable
private fun TimelineSessionBlock(session: TimelineSession) {
    val p = Theme.palette
    val tint = Appearance.tint
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                clockRange(session.startedAt, session.endedAt),
                style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold).monoDigits(),
                color = p.secondaryText,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                if (session.sessionSeconds >= 1) Stat(clock(session.sessionSeconds), "session")
                if (session.watchedSeconds >= 15) Stat(clock(session.watchedSeconds), "watched")
                if (session.sceneCount > 0) Stat("${session.sceneCount}", if (session.sceneCount == 1) "scene" else "scenes")
                if (session.oCount > 0) IconStat(oCounterIcon(Appearance.oCounterIcon, filled = true), session.oCount, tint)
                if (session.markerCount > 0) IconStat(SF.bookmarkFill, session.markerCount, tint)
            }
        }
        TimelineSpine(session.visits)
    }
}

@Composable
private fun Stat(value: String, label: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
        Text(value, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold).monoDigits(), color = Theme.palette.text)
        Text(label, style = IosTypography.caption, color = Theme.palette.secondaryText)
    }
}

@Composable
private fun IconStat(icon: androidx.compose.ui.graphics.vector.ImageVector, count: Int, tint: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(13.dp))
        Text("$count", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold).monoDigits(), color = tint)
    }
}

/** iOS: `TimelineSpine` — the visits on a 2 pt tinted line (compact layout). */
@Composable
private fun TimelineSpine(visits: List<TimelineVisit>) {
    val lineColor = Appearance.tint.copy(alpha = 0.9f)
    Column(
        Modifier.fillMaxWidth().drawBehind {
            drawRect(lineColor, topLeft = Offset(9.dp.toPx(), 0f), size = Size(2.dp.toPx(), size.height))
        },
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        visits.forEach { TimelineVisitRow(it) }
    }
}

/** iOS: `TimelineActionSurface` — secondary background, tinted for O-count/marker actions. */
@Composable
private fun actionSurface(isOCountAction: Boolean): Color {
    val base = Theme.palette.secondaryBackground
    return if (isOCountAction) Appearance.tint.copy(alpha = 0.14f).compositeOver(base) else base
}

/** iOS: `TimelineVisitRow` — time capsule + card; opens the scene. */
@Composable
private fun TimelineVisitRow(visit: TimelineVisit) {
    val p = Theme.palette
    val tint = Appearance.tint
    val isOCountAction = !visit.isPlayback
    Row(
        Modifier.fillMaxWidth().clickable { Nav.push(SceneDetailScreen(visit.scene.id, visit.scene.asScene())) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val capsule = RoundedCornerShape(50)
        Text(
            clockTime(visit.startedAt),
            style = IosTypography.caption2.copy(fontWeight = FontWeight.SemiBold).monoDigits(),
            color = if (isOCountAction) tint else p.secondaryText,
            modifier = Modifier
                .clip(capsule)
                .background(actionSurface(isOCountAction), capsule)
                .border(0.5.dp, if (isOCountAction) tint.copy(alpha = 0.28f) else p.text.copy(alpha = 0.1f), capsule)
                .padding(horizontal = 8.dp, vertical = 4.dp),
        )
        TimelineVisitCard(visit, Modifier.weight(1f))
    }
}

/** iOS: `TimelineVisitCard` (compact thumb width 128, 16:9). */
@Composable
private fun TimelineVisitCard(visit: TimelineVisit, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val tint = Appearance.tint
    val isOCountAction = !visit.isPlayback
    val thumbWidth = 128.dp
    val cardHeight = thumbWidth * 9f / 16f
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(
        // Min height (not fixed): the text column sizes the card at large font scales; the
        // thumbnail matches whatever height that gives.
        modifier
            .heightIn(min = cardHeight)
            .cardShadow(shape)
            .clip(shape)
            .background(actionSurface(isOCountAction), shape)
            .border(0.5.dp, if (isOCountAction) tint.copy(alpha = 0.28f) else p.text.copy(alpha = 0.1f), shape),
    ) {
        Box(Modifier.matchParentSize()) {
            ThumbPlaceholder(Modifier.width(thumbWidth).fillMaxHeight()) {
                Icon(SF.film, null, tint = p.secondaryText, modifier = Modifier.size(20.dp))
                visit.scene.thumbnailURL()?.let { AsyncImage(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            }
        }
        Column(
            Modifier.fillMaxWidth().heightIn(min = cardHeight).padding(start = thumbWidth).padding(horizontal = 12.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                visit.scene.displayTitle, style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold),
                color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                watchedLine(visit)?.let {
                    Text(it, style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                val subtitle = visit.markerTitle?.takeIf { it.isNotEmpty() } ?: visit.scene.studioName
                subtitle?.let {
                    Text(it, style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Row(Modifier.align(Alignment.BottomEnd), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            when {
                visit.isMarkerAction -> BadgeIcon(SF.bookmarkFill, tint, tr(R.string.marker_created))
                visit.isPlayback -> {
                    if (visit.oCount > 0) OCountBadge(visit.oCount)
                    BadgeIcon(SF.playFill, p.secondaryText)
                }
                visit.oCount > 0 -> OCountBadge(visit.oCount)
            }
        }
    }
}

@Composable
private fun BadgeIcon(icon: androidx.compose.ui.graphics.vector.ImageVector, color: Color, description: String? = null) {
    Icon(icon, description, tint = color, modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp).size(13.dp))
}

@Composable
private fun OCountBadge(count: Int) {
    val tint = Appearance.tint
    Row(
        Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(oCounterIcon(Appearance.oCounterIcon, filled = true), null, tint = tint, modifier = Modifier.size(13.dp))
        if (count > 1) Text("×$count", style = IosTypography.caption2.copy(fontWeight = FontWeight.SemiBold).monoDigits(), color = tint)
    }
}

/** iOS: `TimelineSceneSnapshot.asScene` — list-style scene for the detail screen preview. */
private fun TimelineSceneSnapshot.asScene(): Scene = Scene(
    id = id,
    title = title,
    duration = duration,
    resumeTime = resumeTime,
    rating100 = rating100,
    studio = studio?.let { Studio(id = it.id, name = it.name.orEmpty()) },
    performers = performers.map { Performer(id = it.id, name = it.name.orEmpty()) },
    tags = tags.takeIf { it.isNotEmpty() }?.map { Tag(id = it.id, name = it.name.orEmpty()) },
    paths = ScenePaths(screenshot = thumbnailPath),
)

/** iOS: `TimelineSceneSnapshot.thumbnailURL` (= `asScene.thumbnailURL`). */
private fun TimelineSceneSnapshot.thumbnailURL(): String? = asScene().thumbnailURL ?: Net.signed(thumbnailPath)
