package de.letzgo.stashy.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.tv.material3.Text
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.DashboardRepository
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.HomeRowType
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.applying
import de.letzgo.stashy.data.filterDict
import de.letzgo.stashy.data.CatalogRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/** One dashboard row (iOS: the five `@State` scene arrays + loading flags of `TVDashboardView`). */
class TvDashboardRow(val title: String, val type: HomeRowType, val seeAllSort: String, val large: Boolean = false) {
    val scenes: SnapshotStateList<Scene> = mutableStateListOf()
    var isLoading by mutableStateOf(true)
}

/** iOS: `TVDashboardView` data — five scene rows, the stashy+ channels and their previews. */
class TvDashboardModel {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val focus = TvFocusMemory()
    val rows = listOf(
        TvDashboardRow("Continue Watching", HomeRowType.LastPlayed, "lastPlayedAtDesc", large = true),
        TvDashboardRow("New Releases", HomeRowType.Newest3Min, "dateDesc"),
        TvDashboardRow("Recently Added", HomeRowType.LastAdded3Min, "createdAtDesc"),
        TvDashboardRow("Top Rated", HomeRowType.TopRating3Min, "ratingDesc"),
        TvDashboardRow("Random Picks", HomeRowType.Random, "random"),
    )
    private val continueWatching get() = rows[0]
    private val topRated get() = rows[3]
    val channelPreviews = mutableStateMapOf<String, List<Scene>>()
    private var loadingPreviews = false
    /** Progress saved while the dashboard was covered: refresh "Continue Watching" on return. */
    var needsContinueRefresh by mutableStateOf(false)
    private var started = false

    init {
        scope.launch {
            SceneEvents.events.collect { event ->
                rows.forEach { row -> row.scenes.applying(event)?.let { row.scenes.clear(); row.scenes.addAll(it) } }
                when (event) {
                    is SceneEvent.ResumeTimeUpdated, is SceneEvent.PlayAdded -> needsContinueRefresh = true
                    is SceneEvent.Updated -> loadRow(topRated)
                    else -> {}
                }
            }
        }
    }

    val hasValidConfig: Boolean get() = ServerConfigManager.activeConfig?.hasValidConfig == true

    val isAnyLoading: Boolean get() = rows.any { it.isLoading }
    val isEmpty: Boolean get() = rows.all { it.scenes.isEmpty() }

    /** iOS: `channels` — Recently Released, Recently Added, then the saved scene filters by name. */
    val channels: List<TvChannel> get() {
        if (!StashyPlus.isUnlocked) return emptyList()
        SavedFiltersStore.version
        val filters = SavedFiltersStore.forMode(de.letzgo.stashy.data.FilterMode.Scenes).map { TvChannel.savedFilter(it) }
        return listOf(TvChannel.recentlyReleased, TvChannel.recentlyAdded) + filters
    }

    fun start() {
        if (started) return
        started = true
        load()
    }

    fun load() {
        if (!hasValidConfig) return
        scope.launch {
            // The default dashboard filter needs the saved filters first.
            if (TabManager.getDefaultFilterId(AppTab.Dashboard) != null) {
                SavedFiltersStore.load()
                while (SavedFiltersStore.isLoading) kotlinx.coroutines.delay(50)
            }
            rows.forEach { loadRow(it) }
            if (StashyPlus.isUnlocked) {
                SavedFiltersStore.load()
                loadChannelPreviews()
            }
        }
    }

    fun refreshContinueWatching() {
        needsContinueRefresh = false
        loadRow(continueWatching)
    }

    private fun dashboardSceneFilter(): JsonObject? {
        val id = TabManager.getDefaultFilterId(AppTab.Dashboard) ?: return null
        val raw = SavedFiltersStore.byId[id]?.filterDict ?: return null
        return JsonObject(FilterMapper.sanitize(raw).filterKeys { it != "sort" && it != "direction" })
    }

    private fun loadRow(row: TvDashboardRow) {
        if (!hasValidConfig) return
        row.isLoading = true
        scope.launch {
            val scenes = runCatching { DashboardRepository.scenes(row.type, 15, dashboardSceneFilter()) }.getOrNull()
            if (scenes != null) { row.scenes.clear(); row.scenes.addAll(scenes) }
            row.isLoading = false
        }
    }

    /** Four preview scenes per channel, one channel after another (retry once when empty). */
    fun loadChannelPreviews() {
        if (loadingPreviews) return
        val pending = channels.filter { channelPreviews[it.id] == null }
        if (pending.isEmpty()) return
        loadingPreviews = true
        scope.launch {
            for (channel in pending) {
                var scenes = runCatching { CatalogRepository.find<Scene>(channel.query(), 1, 4).items }.getOrDefault(emptyList())
                if (scenes.isEmpty()) scenes = runCatching { CatalogRepository.find<Scene>(channel.query(), 1, 4).items }.getOrDefault(emptyList())
                channelPreviews[channel.id] = scenes
            }
            loadingPreviews = false
            // Saved filters may have arrived meanwhile.
            if (channels.any { channelPreviews[it.id] == null }) loadChannelPreviews()
        }
    }

    fun dispose() = scope.cancel()
}

/** iOS: `TVDashboardView` — Netflix-style rows. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun TvDashboard(model: TvDashboardModel) {
    LaunchedEffect(Unit) { model.start() }
    LaunchedEffect(model.needsContinueRefresh) { if (model.needsContinueRefresh) model.refreshContinueWatching() }
    LaunchedEffect(StashyPlus.isUnlocked) { if (StashyPlus.isUnlocked) model.loadChannelPreviews() }
    LaunchedEffect(SavedFiltersStore.version) { if (StashyPlus.isUnlocked) model.loadChannelPreviews() }
    val firstFocus = remember { FocusRequester() }
    val firstRow = model.rows.firstOrNull { it.scenes.isNotEmpty() }
    Box(Modifier.fillMaxSize().background(TvColors.background)) {
        if (!model.hasValidConfig) {
            TvConnectionError(subtitle = "Add a server in Settings.") { model.load() }
            return@Box
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(top = pt(16), bottom = pt(140)),
            verticalArrangement = Arrangement.spacedBy(pt(50)),
        ) {
            if (model.isAnyLoading && model.isEmpty) item(key = "loading") { TvLoading() }
            val continueRow = model.rows[0]
            if (continueRow.scenes.isNotEmpty()) item(key = "continue") { SceneRow(model, continueRow, firstFocus.takeIf { firstRow === continueRow }) }
            val channels = model.channels
            if (channels.isNotEmpty()) item(key = "channels") {
                Column {
                    RowTitle("Channels")
                    LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(50), vertical = pt(20))) {
                        items(channels, key = { it.id }) { channel ->
                            Column(Modifier.width(pt(400))) {
                                TvChannelCard(channel, model.channelPreviews[channel.id].orEmpty(), { TvNav.push(TvChannelPlayerRoute(channel)) },
                                    Modifier.tvFocusMemory(model.focus, channel.id), width = pt(410), height = pt(230))
                                Text(channel.subtitle, Modifier.padding(top = pt(10)), style = TvType.caption, color = TvColors.secondary, maxLines = 1)
                            }
                        }
                    }
                }
            }
            model.rows.drop(1).forEach { row ->
                if (row.scenes.isNotEmpty()) item(key = row.type.name) { SceneRow(model, row, firstFocus.takeIf { firstRow === row }) }
            }
            if (!model.isAnyLoading && model.isEmpty) item(key = "empty") {
                TvEmpty(TvIcons.stackFilm, "No scenes to show yet", buttonLabel = "Reload") { model.load() }
            }
        }
    }
    // Opening focus on the first card of the first row (tvOS starts in the content).
    TvInitialFocus(model.focus, firstFocus, enabled = firstRow != null, name = "dashboard.firstCard")
}

@Composable
private fun RowTitle(title: String) {
    Text(title, Modifier.padding(horizontal = pt(50)), style = TvType.headline.copy(fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = 0.6f))
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun SceneRow(model: TvDashboardModel, row: TvDashboardRow, entry: FocusRequester? = null) {
    val cardWidth: Dp = if (row.large) pt(560) else pt(400)
    val cardHeight: Dp = if (row.large) pt(315) else pt(225)
    Column(Modifier.fillMaxWidth()) {
        RowTitle(row.title)
        LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(50), vertical = pt(20))) {
            itemsIndexed(row.scenes, key = { _, s -> "${row.type}.${s.id}" }) { index, scene ->
                val first = if (index == 0 && entry != null) Modifier.focusRequester(entry) else Modifier
                TvSceneTile(scene, { TvNav.push(TvSceneDetailRoute(scene.id, scene)) }, first.tvFocusMemory(model.focus, "${row.type}.${scene.id}"), cardWidth + pt(10), cardHeight + pt(5))
            }
            item(key = "${row.type}.seeAll") {
                TvSeeAllCard({ TvNav.push(TvScenesRoute(row.seeAllSort)) }, cardWidth, cardHeight, Modifier.tvFocusMemory(model.focus, "${row.type}.seeAll"))
            }
        }
    }
}
