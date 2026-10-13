package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

/** Settings › Playback › "Feeds start position": where a Feeds › Scenes row starts (skips studio intros). */
enum class FeedsSceneStartPosition(val raw: String, val label: String) {
    Beginning("beginning", "Beginning"), FirstMarker("firstMarker", "First Marker"), Skip30("skip30", "Skip 30s"), Random("random", "Random");
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Beginning }
}

/** iOS: `SubtitleFontSize`. */
enum class SubtitleFontSize(val raw: String, val label: String) {
    Small("small", "Small"), Medium("medium", "Medium"), Large("large", "Large"), ExtraLarge("extraLarge", "Extra large");
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Medium }
}

/** iOS: `SubtitleFontFamily`. */
enum class SubtitleFontFamily(val raw: String, val label: String) {
    System("system", "System"), Rounded("rounded", "Rounded"), Serif("serif", "Serif"), Monospaced("monospaced", "Monospaced");
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: System }
}

/** iOS: `SubtitleTextColorChoice`. */
enum class SubtitleTextColorChoice(val raw: String, val label: String, val argb: Long) {
    White("white", "White", 0xFFFFFFFF), Yellow("yellow", "Yellow", 0xFFFFDE40), Cyan("cyan", "Cyan", 0xFF73E6FF),
    Green("green", "Green", 0xFF73F280), Black("black", "Black", 0xFF000000);
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: White }
}

/** iOS: `SubtitleBackgroundChoice` (`argb` null = no box). */
enum class SubtitleBackgroundChoice(val raw: String, val label: String, val argb: Long?) {
    Black("black", "Black", 0xA6000000), DarkGray("darkGray", "Dark grey", 0xBF404040), White("white", "White", 0xBFFFFFFF), None("none", "None", null);
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Black }
}

/**
 * iOS: `TabManager` — tab visibility/order, dashboard rows, channels, Feeds modes, default
 * sorts/filters (per server, `<key>_<serverID>`) plus the global playback/feeds settings.
 * The single store of `AppTabsConfig_<serverId>`, session sorts, `DetailViewsSortConfig_*` and
 * `CatalogCardColumns`; [CatalogPrefs] is the catalogs' facade over it.
 * All keys are the iOS UserDefaults keys. JSON configs are stored as strings (iOS: `Data`).
 *
 * Player/feeds read the global settings from here (or from [Prefs] with the same keys:
 * Double values are stored as Float, Int values as Int, Bool as Bool).
 */
/**
 * Plain mirror of [TabManager.feedsMarkerDefaultSeconds] for pure feed logic (`FeedSegment`), so
 * it never has to touch Prefs (unit tests). [TabManager] keeps it in sync.
 */
object FeedsPlaybackPrefs {
    @Volatile var markerDefaultSeconds: Double = 30.0
}

object TabManager {
    private const val TABS_KEY = "AppTabsConfig"
    private const val DETAIL_SORT_KEY = "DetailViewsSortConfig"
    private const val HOME_ROWS_KEY = "HomeRowsConfig"
    private const val CHANNEL_ITEMS_KEY = "HomeChannelItemsConfig"
    private const val CHANNEL_SOURCES_KEY = "HomeChannelSourcesConfig"
    private const val LAST_PLAYED_ON_TOP_KEY = "HomeRowsLastPlayedOnTop_v1"
    private const val REELS_MODES_KEY = "ReelsModesConfig"
    private const val CARD_COLUMNS_KEY = "CatalogCardColumns"

    val playerSkipOptions = listOf(5.0, 10.0, 15.0, 30.0)
    val playCountThresholdOptions = listOf(0.0, 1.0, 5.0, 10.0, 30.0, 60.0, 120.0)
    val holdSpeedOptions = listOf(1.5, 2.0, 2.5, 3.0, 4.0)
    val downloadBatchSizeOptions = listOf(5, 10, 25, 50, 100, 200)

    var tabs by mutableStateOf<List<TabConfig>>(emptyList()); private set
    var homeRows by mutableStateOf<List<HomeRowConfig>>(emptyList()); private set
    var homeChannelItems by mutableStateOf<List<HomeChannelItemConfig>>(emptyList()); private set
    var reelsModes by mutableStateOf<List<ReelsModeConfig>>(emptyList()); private set
    private val detailSorts = mutableStateMapOf<DetailViewContext, String>()
    private val cardColumns = mutableStateMapOf<CatalogCardColumnScope, CatalogCardColumns>()
    /** Session-only sorts (iOS `sessionSortOptions`). */
    private val sessionSorts = mutableStateMapOf<AppTab, String>()
    /** Session-only detail sorts (iOS `sessionDetailSortOptions`), keyed by context raw value. */
    private val sessionDetailSorts = mutableStateMapOf<String, String>()

    /**
     * Bumped whenever a persistent default (sort, filter, detail sort) changes or the session is
     * reset (iOS `DefaultSortChanged` / `DefaultFilterChanged`). Catalogs re-check their defaults
     * on a bump and whenever they reappear (`CatalogController.syncDefaults`).
     */
    var defaultsVersion by mutableIntStateOf(0); private set

    private fun notifyDefaults() { defaultsVersion++ }

    /** Bumped when a default filter changes (iOS `DefaultFilterChanged` notification); value = tab. */
    var defaultFilterChanged by mutableStateOf<Pair<AppTab, Long>?>(null); private set

    private var loadedFor: String? = "<never>"

    // MARK: global settings (iOS @Published + didSet → UserDefaults)
    private fun bool(key: String, def: Boolean) = mutableStateOf(if (Prefs.has(key)) Prefs.bool(key) else def)
    private fun dbl(key: String, def: Double, allowed: List<Double>? = null) =
        mutableStateOf((if (Prefs.has(key)) Prefs.float(key).toDouble() else def).let { v -> if (allowed != null && allowed.none { it == v }) def else v })

    private val _reelsFillHeight = bool("ReelsFillHeight", true)
    var reelsFillHeight: Boolean get() = _reelsFillHeight.value; set(v) { _reelsFillHeight.value = v; Prefs.setBool("ReelsFillHeight", v) }
    private val _reelsContinuousPlay = bool("ReelsContinuousPlay", false)
    var reelsContinuousPlay: Boolean get() = _reelsContinuousPlay.value; set(v) { _reelsContinuousPlay.value = v; Prefs.setBool("ReelsContinuousPlay", v) }
    private val _isPiPEnabled = bool("isPiPEnabled", true)
    var isPiPEnabled: Boolean get() = _isPiPEnabled.value; set(v) { _isPiPEnabled.value = v; Prefs.setBool("isPiPEnabled", v) }
    private val _playerSkipSeconds = dbl("playerSkipSeconds", 10.0, playerSkipOptions)
    var playerSkipSeconds: Double get() = _playerSkipSeconds.value; set(v) { _playerSkipSeconds.value = v; Prefs.setFloat("playerSkipSeconds", v.toFloat()) }
    private val _showsPlayerSkipButtons = bool("showsPlayerSkipButtons", true)
    var showsPlayerSkipButtons: Boolean get() = _showsPlayerSkipButtons.value; set(v) { _showsPlayerSkipButtons.value = v; Prefs.setBool("showsPlayerSkipButtons", v) }
    private val _playerAutoZoom = bool("playerAutoZoom", false)
    var playerAutoZoom: Boolean get() = _playerAutoZoom.value; set(v) { _playerAutoZoom.value = v; Prefs.setBool("playerAutoZoom", v) }
    /** iOS: Settings › Playback › "Playback activity" (Stash web `trackActivity`). Off: no play count,
     *  history, resume time or play duration goes to the server. */
    private val _tracksPlaybackActivity = bool("playbackTrackActivity", true)
    var tracksPlaybackActivity: Boolean get() = _tracksPlaybackActivity.value; set(v) { _tracksPlaybackActivity.value = v; Prefs.setBool("playbackTrackActivity", v) }
    /** Scenes whose activity the player menu paused ("Count this playback" off) — in memory, until the app restarts. */
    val activityPausedSceneIds: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    /** The global switch and the per-scene pause from the player menu. */
    fun tracksActivity(sceneId: String): Boolean = tracksPlaybackActivity && sceneId !in activityPausedSceneIds
    private val _playerDolbyVision = bool("player_dolby_vision_enabled", true)
    var playerDolbyVisionEnabled: Boolean get() = _playerDolbyVision.value; set(v) { _playerDolbyVision.value = v; Prefs.setBool("player_dolby_vision_enabled", v) }
    private val _playCountPlayerSeconds = dbl("play_count_player_seconds", 1.0, playCountThresholdOptions)
    var playCountPlayerSeconds: Double get() = _playCountPlayerSeconds.value; set(v) { _playCountPlayerSeconds.value = v; Prefs.setFloat("play_count_player_seconds", v.toFloat()) }
    private val _playCountFeedsSeconds = dbl("play_count_feeds_seconds", 30.0, playCountThresholdOptions)
    var playCountFeedsSeconds: Double get() = _playCountFeedsSeconds.value; set(v) { _playCountFeedsSeconds.value = v; Prefs.setFloat("play_count_feeds_seconds", v.toFloat()) }
    private val _holdSpeedPlayer = dbl("hold_speed_player", 2.0, holdSpeedOptions)
    var holdSpeedPlayer: Double get() = _holdSpeedPlayer.value; set(v) { _holdSpeedPlayer.value = v; Prefs.setFloat("hold_speed_player", v.toFloat()) }
    /** Settings › Playback › "Marker length": how long a Feeds › Markers row plays when the marker has no end time. */
    val feedsMarkerLengthOptions = listOf(15.0, 30.0, 45.0, 60.0, 90.0, 120.0)
    private val _feedsMarkerDefaultSeconds = dbl("feedsMarkerDefaultSeconds", 30.0, feedsMarkerLengthOptions)
    var feedsMarkerDefaultSeconds: Double get() = _feedsMarkerDefaultSeconds.value; set(v) { _feedsMarkerDefaultSeconds.value = v; FeedsPlaybackPrefs.markerDefaultSeconds = v; Prefs.setFloat("feedsMarkerDefaultSeconds", v.toFloat()) }
    init { FeedsPlaybackPrefs.markerDefaultSeconds = _feedsMarkerDefaultSeconds.value }
    private val _feedsSceneStartPosition = mutableStateOf(FeedsSceneStartPosition.from(Prefs.string("feedsSceneStartPosition")))
    var feedsSceneStartPosition: FeedsSceneStartPosition
        get() = _feedsSceneStartPosition.value
        set(v) { _feedsSceneStartPosition.value = v; Prefs.setString("feedsSceneStartPosition", v.raw) }
    private val _holdSpeedFeeds = dbl("hold_speed_feeds", 2.0, holdSpeedOptions)
    var holdSpeedFeeds: Double get() = _holdSpeedFeeds.value; set(v) { _holdSpeedFeeds.value = v; Prefs.setFloat("hold_speed_feeds", v.toFloat()) }
    private val _downloadBatchSize = mutableStateOf(Prefs.int("download_batch_size", 50).let { if (it in downloadBatchSizeOptions) it else 50 })
    var downloadBatchSize: Int get() = _downloadBatchSize.value; set(v) { _downloadBatchSize.value = v; Prefs.setInt("download_batch_size", v) }
    private val _sceneDownloadBatchSize = mutableStateOf(Prefs.int("scene_download_batch_size", 5).let { if (it in downloadBatchSizeOptions) it else 5 })
    var sceneDownloadBatchSize: Int get() = _sceneDownloadBatchSize.value; set(v) { _sceneDownloadBatchSize.value = v; Prefs.setInt("scene_download_batch_size", v) }
    private val _reelsShowsDeleteButton = bool("ReelsShowsDeleteButton", false)
    var reelsShowsDeleteButton: Boolean get() = _reelsShowsDeleteButton.value; set(v) { _reelsShowsDeleteButton.value = v; Prefs.setBool("ReelsShowsDeleteButton", v) }
    private val _sceneCardsShowStudioLogo = bool("SceneCardsShowStudioLogo", true)
    var sceneCardsShowStudioLogo: Boolean get() = _sceneCardsShowStudioLogo.value; set(v) { _sceneCardsShowStudioLogo.value = v; Prefs.setBool("SceneCardsShowStudioLogo", v) }
    private val _useCompactStatistics = bool("useCompactStatistics", false)
    var useCompactStatistics: Boolean get() = _useCompactStatistics.value; set(v) { _useCompactStatistics.value = v; Prefs.setBool("useCompactStatistics", v) }
    private val _showDashboardHeroBackground = bool("showDashboardHeroBackground", true)
    var showDashboardHeroBackground: Boolean get() = _showDashboardHeroBackground.value; set(v) { _showDashboardHeroBackground.value = v; Prefs.setBool("showDashboardHeroBackground", v) }
    private val _useColoredStatistics = bool("useColoredStatistics", true)
    var useColoredStatistics: Boolean get() = _useColoredStatistics.value; set(v) { _useColoredStatistics.value = v; Prefs.setBool("useColoredStatistics", v) }
    /** iOS `DashboardHeroSize` raw ("big"/"small"). */
    private val _dashboardHeroSize = mutableStateOf(Prefs.string("DashboardHeroSize") ?: "big")
    var dashboardHeroSize: String get() = _dashboardHeroSize.value; set(v) { _dashboardHeroSize.value = v; Prefs.setString("DashboardHeroSize", v) }

    // Subtitles (Settings → Playback → Subtitles)
    private val _subtitlesAutoEnabled = bool("subtitle_auto_enabled", false)
    var subtitlesAutoEnabled: Boolean get() = _subtitlesAutoEnabled.value; set(v) { _subtitlesAutoEnabled.value = v; Prefs.setBool("subtitle_auto_enabled", v) }
    /** ISO 639-1 code or "any". */
    private val _subtitlePreferredLanguage = mutableStateOf(Prefs.string("subtitle_preferred_language")?.trim()?.lowercase()?.ifEmpty { null } ?: "any")
    var subtitlePreferredLanguage: String get() = _subtitlePreferredLanguage.value; set(v) { _subtitlePreferredLanguage.value = v; Prefs.setString("subtitle_preferred_language", v) }
    private val _subtitleFontSize = mutableStateOf(SubtitleFontSize.from(Prefs.string("subtitle_font_size")))
    var subtitleFontSize: SubtitleFontSize get() = _subtitleFontSize.value; set(v) { _subtitleFontSize.value = v; Prefs.setString("subtitle_font_size", v.raw) }
    private val _subtitleFontFamily = mutableStateOf(SubtitleFontFamily.from(Prefs.string("subtitle_font_family")))
    var subtitleFontFamily: SubtitleFontFamily get() = _subtitleFontFamily.value; set(v) { _subtitleFontFamily.value = v; Prefs.setString("subtitle_font_family", v.raw) }
    private val _subtitleTextColor = mutableStateOf(SubtitleTextColorChoice.from(Prefs.string("subtitle_text_color")))
    var subtitleTextColor: SubtitleTextColorChoice get() = _subtitleTextColor.value; set(v) { _subtitleTextColor.value = v; Prefs.setString("subtitle_text_color", v.raw) }
    private val _subtitleBackgroundColor = mutableStateOf(SubtitleBackgroundChoice.from(Prefs.string("subtitle_background_color")))
    var subtitleBackgroundColor: SubtitleBackgroundChoice get() = _subtitleBackgroundColor.value; set(v) { _subtitleBackgroundColor.value = v; Prefs.setString("subtitle_background_color", v.raw) }
    private val _subtitleBoxEnabled = bool("subtitle_box_enabled", true)
    var subtitleBoxEnabled: Boolean get() = _subtitleBoxEnabled.value; set(v) { _subtitleBoxEnabled.value = v; Prefs.setBool("subtitle_box_enabled", v) }

    // Images / Pics (other @AppStorage keys shown in Settings)
    private val _imagesFeedVideoAutoplay = bool("images_feed_video_autoplay", true)
    var imagesFeedVideoAutoplay: Boolean get() = _imagesFeedVideoAutoplay.value; set(v) { _imagesFeedVideoAutoplay.value = v; Prefs.setBool("images_feed_video_autoplay", v) }
    /**
     * iOS `StashImageGroupingPrefs`: `stashline_group_mode` (off / gallery / gallerySession). First
     * read migrates the old switch `stashline_group_sets` (false → off, else gallery + session);
     * every write keeps that old key in sync (true unless off) for older readers.
     */
    private val _stashlineGroupMode = mutableStateOf(
        if (Prefs.has(ImageSetGrouping.MODE_KEY)) ImageGroupMode.from(Prefs.string(ImageSetGrouping.MODE_KEY))
        else ImageSetGrouping.migratedMode(if (Prefs.has(ImageSetGrouping.LEGACY_SETS_KEY)) Prefs.bool(ImageSetGrouping.LEGACY_SETS_KEY) else null)
            .also { Prefs.setString(ImageSetGrouping.MODE_KEY, it.raw) }
    )
    var stashlineGroupMode: ImageGroupMode
        get() = _stashlineGroupMode.value
        set(v) {
            _stashlineGroupMode.value = v
            Prefs.setString(ImageSetGrouping.MODE_KEY, v.raw)
            Prefs.setBool(ImageSetGrouping.LEGACY_SETS_KEY, v != ImageGroupMode.Off)
        }
    /** Session gap in minutes (2 / 10 / 60) for [ImageGroupMode.GallerySession]. */
    private val _stashlineGroupGapMinutes = mutableStateOf(
        ImageSetGrouping.normalizedGap(if (Prefs.has(ImageSetGrouping.GAP_KEY)) Prefs.int(ImageSetGrouping.GAP_KEY) else null)
    )
    var stashlineGroupGapMinutes: Int
        get() = _stashlineGroupGapMinutes.value
        set(v) { val g = ImageSetGrouping.normalizedGap(v); _stashlineGroupGapMinutes.value = g; Prefs.setInt(ImageSetGrouping.GAP_KEY, g) }
    /** Max images per set (10 / 20 / 30 / 50 / 100, `stashline_group_max_size`). */
    private val _stashlineGroupMaxSize = mutableStateOf(
        ImageSetGrouping.normalizedMaxSize(if (Prefs.has(ImageSetGrouping.MAX_SIZE_KEY)) Prefs.int(ImageSetGrouping.MAX_SIZE_KEY) else null)
    )
    var stashlineGroupMaxSize: Int
        get() = _stashlineGroupMaxSize.value
        set(v) { val m = ImageSetGrouping.normalizedMaxSize(v); _stashlineGroupMaxSize.value = m; Prefs.setInt(ImageSetGrouping.MAX_SIZE_KEY, m) }

    // MARK: loading

    /** Loads the per-server configs when the active server changed (or on first use). */
    fun ensureLoaded() {
        val id = ServerConfigManager.activeConfig?.id
        if (id != loadedFor) reload()
    }

    /** iOS `loadAllConfigs()` (also on `ServerConfigChanged`). */
    fun reload() {
        loadedFor = ServerConfigManager.activeConfig?.id
        loadTabs(); loadDetailSorts(); loadHomeRows(); loadChannelItems(); loadReelsModes(); loadCardColumns()
        sessionSorts.clear(); sessionDetailSorts.clear()
    }

    private fun key(base: String) = Prefs.serverKey(base)
    private val hasServer get() = ServerConfigManager.activeConfig != null

    /** iOS migration: no server-specific value yet → take the legacy global one. */
    private fun readWithLegacy(base: String, onLegacy: (String) -> String = { it }): String? {
        Prefs.string(key(base))?.let { return it }
        if (!hasServer) return null
        val legacy = Prefs.string(base) ?: return null
        val migrated = onLegacy(legacy)
        Prefs.setString(key(base), migrated)
        return migrated
    }

    private fun loadTabs() {
        val raw = readWithLegacy(TABS_KEY) { legacy ->
            // Clear filter ids so filters don't leak across servers.
            val decoded = TabConfigLogic.decodeLenient(legacy, TabConfig.serializer()) ?: return@readWithLegacy legacy
            Json.encodeToString(ListSerializer(TabConfig.serializer()), decoded.map { it.copy(defaultFilterId = null, defaultFilterName = null) })
        }
        val (list, save) = TabConfigLogic.normalizeTabs(TabConfigLogic.decodeLenient(raw, TabConfig.serializer()))
        tabs = list
        if (save) saveTabs()
    }

    private fun saveTabs() = Prefs.setString(key(TABS_KEY), Json.encodeToString(ListSerializer(TabConfig.serializer()), tabs))

    private fun loadHomeRows() {
        val raw = readWithLegacy(HOME_ROWS_KEY)
        val promoteKey = key(LAST_PLAYED_ON_TOP_KEY)
        val decoded = TabConfigLogic.decodeLenient(raw, HomeRowConfig.serializer())
        val promote = decoded != null && !Prefs.bool(promoteKey)
        val (rows, changed) = TabConfigLogic.normalizeHomeRows(decoded, promote)
        if (decoded != null) Prefs.setBool(promoteKey, true)
        homeRows = rows
        if (changed) saveHomeRows()
    }

    private fun saveHomeRows() = Prefs.setString(key(HOME_ROWS_KEY), Json.encodeToString(ListSerializer(HomeRowConfig.serializer()), homeRows))

    private fun loadChannelItems() {
        homeChannelItems = TabConfigLogic.decodeLenient(Prefs.string(key(CHANNEL_ITEMS_KEY)), HomeChannelItemConfig.serializer())
            ?.sortedBy { it.sortOrder }?.mapIndexed { i, c -> c.copy(sortOrder = i) }.orEmpty()
    }

    private fun saveChannelItems() = Prefs.setString(key(CHANNEL_ITEMS_KEY), Json.encodeToString(ListSerializer(HomeChannelItemConfig.serializer()), homeChannelItems))

    private fun loadReelsModes() {
        val (modes, changed) = TabConfigLogic.normalizeReelsModes(TabConfigLogic.decodeLenient(readWithLegacy(REELS_MODES_KEY), ReelsModeConfig.serializer()))
        reelsModes = modes
        if (changed) saveReelsModes()
    }

    private fun saveReelsModes() = Prefs.setString(key(REELS_MODES_KEY), Json.encodeToString(ListSerializer(ReelsModeConfig.serializer()), reelsModes))

    private fun loadDetailSorts() {
        detailSorts.clear()
        for (ctx in DetailViewContext.entries) {
            val k = "${DETAIL_SORT_KEY}_${ctx.raw}"
            var saved = Prefs.string(key(k))
            if (saved == null && hasServer) Prefs.string(k)?.let { saved = it; Prefs.setString(key(k), it) }
            detailSorts[ctx] = saved ?: "dateDesc"
        }
    }

    private fun loadCardColumns() {
        cardColumns.clear()
        val raw = Prefs.string(CARD_COLUMNS_KEY)?.let { runCatching { Json.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), it) }.getOrNull() }
        if (raw != null) {
            for (s in CatalogCardColumnScope.entries) CatalogCardColumns.from(raw[s.raw])?.let { cardColumns[s] = it }
            if (cardColumns[CatalogCardColumnScope.OpenedGallery] == null) cardColumns[CatalogCardColumnScope.Images]?.let { cardColumns[CatalogCardColumnScope.OpenedGallery] = it }
        }
        for (s in CatalogCardColumnScope.entries) if (cardColumns[s] == null) cardColumns[s] = CatalogCardColumns.Two
    }

    // MARK: tabs

    fun tab(id: AppTab): TabConfig? { ensureLoaded(); return tabs.firstOrNull { it.id == id } }

    fun isVisible(id: AppTab): Boolean = tab(id)?.isVisible ?: true

    /** Home catalogue sub-tabs in the user's order (incl. hidden ones). */
    val catalogSubTabs: List<TabConfig> get() {
        ensureLoaded()
        val ids = setOf(AppTab.Scenes, AppTab.Galleries, AppTab.Performers, AppTab.Studios, AppTab.Tags, AppTab.Images, AppTab.Groups, AppTab.Markers)
        return tabs.filter { it.id in ids }.sortedBy { it.sortOrder }
    }

    /** iOS `toggle(_:)` — the dashboard can't be hidden. */
    fun toggle(id: AppTab) {
        if (id == AppTab.Dashboard) return
        ensureLoaded()
        tabs = tabs.map { if (it.id == id) it.copy(isVisible = !it.isVisible) else it }
        saveTabs()
    }

    /** iOS `moveSubTab(from:to:within: .catalogue)` with indices into [catalogSubTabs]; dashboard stays first. */
    fun moveCatalogSubTab(from: Int, to: Int) {
        val ids = setOf(AppTab.Performers, AppTab.Studios, AppTab.Tags, AppTab.Scenes, AppTab.Galleries, AppTab.Images, AppTab.Dashboard, AppTab.Groups, AppTab.Markers)
        val sub = tabs.filter { it.id in ids }.sortedBy { it.sortOrder }.toMutableList()
        sub.indexOfFirst { it.id == AppTab.Dashboard }.takeIf { it >= 0 }?.let { sub.add(0, sub.removeAt(it)) }
        val moved = listOf(sub.first()) + TabConfigLogic.move(sub.drop(1), from, to)
        val order = moved.mapIndexed { i, t -> t.id to i }.toMap()
        tabs = tabs.map { t -> order[t.id]?.let { t.copy(sortOrder = it) } ?: t }
        saveTabs()
    }

    // MARK: sorts & filters

    fun getSortOption(tab: AppTab): String? = sessionSorts[tab] ?: getPersistentSortOption(tab)
    fun getPersistentSortOption(tab: AppTab): String? = tab(tab)?.defaultSortOption
    fun setSortOption(tab: AppTab, option: String) { sessionSorts[tab] = option }

    /** iOS `setPersistentSortOption(for:option:)` — posts `DefaultSortChanged`. */
    fun setPersistentSortOption(tab: AppTab, option: String) {
        ensureLoaded()
        if (tabs.none { it.id == tab }) return
        tabs = tabs.map { if (it.id == tab) it.copy(defaultSortOption = option) else it }
        sessionSorts[tab] = option
        saveTabs()
        notifyDefaults()
    }

    fun getDefaultFilterId(tab: AppTab) = tab(tab)?.defaultFilterId
    fun getDefaultFilterName(tab: AppTab) = tab(tab)?.defaultFilterName
    fun getDefaultMarkerFilterName(tab: AppTab) = tab(tab)?.defaultMarkerFilterName
    fun getDefaultMarkerFilterId(tab: AppTab) = tab(tab)?.defaultMarkerFilterId
    fun getDefaultClipFilterId(tab: AppTab) = tab(tab)?.defaultClipFilterId
    fun getDefaultPreviewFilterId(tab: AppTab) = tab(tab)?.defaultPreviewFilterId

    private fun updateTab(tab: AppTab, change: (TabConfig) -> TabConfig) {
        ensureLoaded()
        tabs = tabs.map { if (it.id == tab) change(it) else it }
        saveTabs()
        defaultFilterChanged = tab to System.nanoTime()
        notifyDefaults()
    }

    fun setDefaultFilter(tab: AppTab, id: String?, name: String?) = updateTab(tab) { it.copy(defaultFilterId = id, defaultFilterName = name) }
    fun setDefaultMarkerFilter(tab: AppTab, id: String?, name: String?) = updateTab(tab) { it.copy(defaultMarkerFilterId = id, defaultMarkerFilterName = name) }
    fun setDefaultClipFilter(tab: AppTab, id: String?, name: String?) = updateTab(tab) { it.copy(defaultClipFilterId = id, defaultClipFilterName = name) }
    fun setDefaultPreviewFilter(tab: AppTab, id: String?, name: String?) = updateTab(tab) { it.copy(defaultPreviewFilterId = id, defaultPreviewFilterName = name) }

    fun getPersistentDetailSortOption(ctx: DetailViewContext): String? { ensureLoaded(); return detailSorts[ctx] }
    fun setPersistentDetailSortOption(ctx: DetailViewContext, option: String) {
        ensureLoaded()
        detailSorts[ctx] = option
        sessionDetailSorts[ctx.raw] = option
        Prefs.setString(key("${DETAIL_SORT_KEY}_${ctx.raw}"), option)
        notifyDefaults()
    }

    /** iOS `getDetailSortOption(for:)` — session first, then the persistent detail default. */
    fun getDetailSortOption(context: String): String? =
        sessionDetailSorts[context] ?: DetailViewContext.fromRaw(context)?.let { getPersistentDetailSortOption(it) }

    /** iOS `setDetailSortOption(for:option:)` — session only. */
    fun setDetailSortOption(context: String, option: String) { sessionDetailSorts[context] = option }

    /** Server switch: session sorts belong to the old server. */
    fun resetSession() {
        sessionSorts.clear(); sessionDetailSorts.clear()
        notifyDefaults()
    }

    fun catalogCardColumns(scope: CatalogCardColumnScope): CatalogCardColumns { ensureLoaded(); return cardColumns[scope] ?: CatalogCardColumns.Two }
    fun setCatalogCardColumns(columns: CatalogCardColumns, scope: CatalogCardColumnScope) {
        cardColumns[scope] = columns
        Prefs.setString(CARD_COLUMNS_KEY, Json.encodeToString(MapSerializer(String.serializer(), Int.serializer()), cardColumns.entries.associate { it.key.raw to it.value.raw }))
    }
    fun toggleCatalogCardColumns(scope: CatalogCardColumnScope) = setCatalogCardColumns(catalogCardColumns(scope).next, scope)

    /**
     * iOS `CatalogsView.sortedVisibleTabs` — Home chip strip: dashboard + catalogs that are
     * visible, in the user's order.
     */
    val visibleCatalogTabs: List<AppTab> get() {
        ensureLoaded()
        val ids = setOf(AppTab.Dashboard, AppTab.Scenes, AppTab.Galleries, AppTab.Performers, AppTab.Studios, AppTab.Tags, AppTab.Images, AppTab.Groups, AppTab.Markers)
        return tabs.filter { it.id in ids && it.isVisible }.sortedBy { it.sortOrder }.map { it.id }
    }

    // MARK: home rows

    fun toggleHomeRow(id: String) {
        homeRows = homeRows.map { if (it.id == id) it.copy(isEnabled = !it.isEnabled) else it }
        saveHomeRows()
    }

    fun moveHomeRow(from: Int, to: Int) {
        homeRows = TabConfigLogic.move(homeRows, from, to).mapIndexed { i, r -> r.copy(sortOrder = i) }
        saveHomeRows()
    }

    fun syncHomeChannelItems(filters: List<SavedFilter>) {
        ensureLoaded()
        val legacy = Prefs.string(key(CHANNEL_SOURCES_KEY))?.let { s ->
            runCatching {
                Json.parseToJsonElement(s).arr?.mapNotNull { el ->
                    val kind = el.obj?.get("kind").stringOrNull?.let { k -> HomeChannelSourceKind.entries.firstOrNull { it.raw == k } }
                    val on = el.obj?.get("isEnabled")?.toString()?.toBooleanStrictOrNull()
                    if (kind != null && on != null) kind to on else null
                }?.toMap()
            }.getOrNull()
        }.orEmpty()
        val next = TabConfigLogic.syncChannelItems(homeChannelItems, filters.map { Triple(it.id, it.name, it.mode) }, legacy)
        if (next != homeChannelItems) { homeChannelItems = next; saveChannelItems() }
    }

    fun toggleHomeChannelItem(id: String) {
        homeChannelItems = homeChannelItems.map { if (it.id == id) it.copy(isEnabled = !it.isEnabled) else it }
        saveChannelItems()
    }

    fun moveHomeChannelItem(from: Int, to: Int) {
        homeChannelItems = TabConfigLogic.move(homeChannelItems.sortedBy { it.sortOrder }, from, to).mapIndexed { i, c -> c.copy(sortOrder = i) }
        saveChannelItems()
    }

    // MARK: Feeds modes

    val configurableReelsModes: List<ReelsModeConfig> get() { ensureLoaded(); return reelsModes.sortedBy { it.sortOrder } }
    val enabledReelsModes: List<ReelsModeType> get() = configurableReelsModes.filter { it.isEnabled }.map { it.type }

    /** iOS `toggleReelsMode` — the last enabled mode can't be switched off. */
    fun toggleReelsMode(type: ReelsModeType) {
        val enabled = reelsModes.count { it.isEnabled }
        val m = reelsModes.firstOrNull { it.type == type } ?: return
        if (m.isEnabled && enabled <= 1) return
        reelsModes = reelsModes.map { if (it.type == type) it.copy(isEnabled = !it.isEnabled) else it }
        saveReelsModes()
    }

    fun moveReelsMode(from: Int, to: Int) {
        reelsModes = TabConfigLogic.move(reelsModes.sortedBy { it.sortOrder }, from, to).mapIndexed { i, m -> m.copy(sortOrder = i) }
        saveReelsModes()
    }

    fun getReelsDefaultSort(type: ReelsModeType): String? = configurableReelsModes.firstOrNull { it.type == type }?.defaultSortOption
    fun setReelsDefaultSort(type: ReelsModeType, option: String) {
        reelsModes = reelsModes.map { if (it.type == type) it.copy(defaultSortOption = option) else it }
        saveReelsModes()
    }
}
