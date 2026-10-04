package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.util.UUID

/**
 * Pure (Android-free) encode/decode of the per-server `ReelsModesConfig` list, incl. the iOS
 * repair step "ensure all modes exist" (`TabManager.loadReelsModes`). Unit-tested.
 */
object ReelsModesCodec {
    private val serializer = ListSerializer(ReelsModeConfig.serializer())
    /** Every key written like Swift's encoder (defaults included); nulls omitted like `encodeIfPresent`. */
    private val codecJson = kotlinx.serialization.json.Json(from = Json) { encodeDefaults = true }

    /** iOS defaults: all five modes on, Pics sorted by `dateDesc`. */
    fun defaults(): List<ReelsModeConfig> = listOf(
        ReelsModeConfig(type = ReelsModeType.Scenes, sortOrder = 0),
        ReelsModeConfig(type = ReelsModeType.Markers, sortOrder = 1),
        ReelsModeConfig(type = ReelsModeType.Clips, sortOrder = 2),
        ReelsModeConfig(type = ReelsModeType.Previews, sortOrder = 3),
        ReelsModeConfig(type = ReelsModeType.Pics, sortOrder = 4, defaultSortOption = "dateDesc"),
    )

    fun encode(modes: List<ReelsModeConfig>): String = codecJson.encodeToString(serializer, modes)

    /**
     * Returns the sorted list and whether it had to be repaired (missing modes appended with
     * re-numbered `sortOrder`). `null` input or garbage → defaults (repaired = true).
     */
    fun decode(raw: String?): Pair<List<ReelsModeConfig>, Boolean> {
        val decoded = raw?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }
            ?: return defaults() to true
        var modes = decoded.sortedBy { it.sortOrder }
        val missing = ReelsModeType.entries.filter { t -> modes.none { it.type == t } }
        if (missing.isEmpty()) return modes to false
        modes = modes + missing.mapIndexed { i, t ->
            ReelsModeConfig(type = t, sortOrder = modes.size + i, defaultSortOption = if (t == ReelsModeType.Pics) "dateDesc" else null)
        }
        return modes.mapIndexed { i, m -> m.copy(sortOrder = i) } to true
    }

    fun enabled(modes: List<ReelsModeConfig>): List<ReelsModeType> =
        modes.filter { it.isEnabled }.sortedBy { it.sortOrder }.map { it.type }

    /** iOS: `toggleReelsMode` — the last enabled mode cannot be switched off. */
    fun toggle(modes: List<ReelsModeConfig>, type: ReelsModeType): List<ReelsModeConfig> {
        val enabledCount = modes.count { it.isEnabled }
        return modes.map {
            if (it.type != type) it
            else if (it.isEnabled && enabledCount <= 1) it
            else it.copy(isEnabled = !it.isEnabled)
        }
    }

    /** iOS: `moveReelsMode(from:to:)` with a single index. */
    fun move(modes: List<ReelsModeConfig>, from: Int, to: Int): List<ReelsModeConfig> {
        val list = modes.sortedBy { it.sortOrder }.toMutableList()
        if (from !in list.indices) return list
        val item = list.removeAt(from)
        list.add(to.coerceIn(0, list.size), item)
        return list.mapIndexed { i, m -> m.copy(sortOrder = i) }
    }

    fun withDefaultSort(modes: List<ReelsModeConfig>, type: ReelsModeType, option: String): List<ReelsModeConfig> =
        modes.map { if (it.type == type) it.copy(defaultSortOption = option) else it }
}

/**
 * iOS: the Feeds part of `TabManager` — mode list (`ReelsModesConfig_<serverID>`), the
 * playback toggles of the Filter & Sort sheet and the Feeds default filters.
 * Keys are the iOS UserDefaults keys.
 */
object FeedsConfig {
    private const val MODES_KEY = "ReelsModesConfig"
    private const val TABS_KEY = "AppTabsConfig"

    private fun serverSuffix(): String = ServerConfigManager.activeConfig?.id?.let { "_$it" } ?: ""

    // Mode list: single store in `TabManager` (shared with Settings → Feeds).
    /** iOS: `reelsModes` (sorted by `sortOrder`). */
    val modes: List<ReelsModeConfig> get() = TabManager.configurableReelsModes
    /** iOS: `enabledReelsModes`. */
    val enabledModes: List<ReelsModeType> get() = TabManager.enabledReelsModes
    fun toggleMode(type: ReelsModeType) = TabManager.toggleReelsMode(type)
    fun moveMode(from: Int, to: Int) = TabManager.moveReelsMode(from, to)
    fun defaultSort(type: ReelsModeType): String? = TabManager.getReelsDefaultSort(type)
    fun setDefaultSort(type: ReelsModeType, option: String) = TabManager.setReelsDefaultSort(type, option)

    // Playback toggles (global keys, iOS `TabManager`).
    var fillHeight by mutableStateOf(if (Prefs.has("ReelsFillHeight")) Prefs.bool("ReelsFillHeight") else true)
        private set
    var continuousPlay by mutableStateOf(Prefs.bool("ReelsContinuousPlay"))
        private set
    var showsDeleteButton by mutableStateOf(Prefs.bool("ReelsShowsDeleteButton"))
        private set

    fun updateFillHeight(v: Boolean) { fillHeight = v; Prefs.setBool("ReelsFillHeight", v) }
    fun updateContinuousPlay(v: Boolean) { continuousPlay = v; Prefs.setBool("ReelsContinuousPlay", v) }
    fun updateShowsDeleteButton(v: Boolean) { showsDeleteButton = v; Prefs.setBool("ReelsShowsDeleteButton", v) }

    /** iOS: `holdSpeedFeeds` (default 2×). Stored as Double on iOS; read leniently. */
    val holdSpeedFeeds: Float get() = readNumber("hold_speed_feeds", 2f)
    /** iOS: `playerSkipSeconds` (default 10). */
    val playerSkipSeconds: Float get() = readNumber("playerSkipSeconds", 10f)
    /** iOS: `playCountFeedsSeconds` (default 30). */
    val playCountFeedsSeconds: Float get() = readNumber("play_count_feeds_seconds", 30f)

    private fun readNumber(key: String, default: Float): Float {
        if (!Prefs.has(key)) return default
        val all = Prefs.prefs.all[key]
        return when (all) {
            is Float -> all
            is Int -> all.toFloat()
            is Long -> all.toFloat()
            is String -> all.toFloatOrNull() ?: default
            else -> default
        }
    }

    /**
     * Feeds default filters live in the `AppTabsConfig` tab list on iOS (`TabConfig` of the
     * `reels` tab: `defaultFilterId`, `defaultMarkerFilterId`, `defaultClipFilterId`,
     * `defaultPreviewFilterId`; Pics uses the `images` tab's `defaultFilterId`). Read here from
     * the same JSON (`AppTabsConfig_<serverID>`); the settings port owns writing the rest.
     */
    fun defaultFilterId(mode: ReelsModeType): String? = when (mode) {
        ReelsModeType.Scenes -> TabManager.getDefaultFilterId(AppTab.Reels)
        ReelsModeType.Markers -> TabManager.getDefaultMarkerFilterId(AppTab.Reels)
        ReelsModeType.Clips -> TabManager.getDefaultClipFilterId(AppTab.Reels)
        ReelsModeType.Previews -> TabManager.getDefaultPreviewFilterId(AppTab.Reels)
        ReelsModeType.Pics -> TabManager.getDefaultFilterId(AppTab.Images)
    }?.takeIf { it.isNotEmpty() }

    fun setDefaultFilter(mode: ReelsModeType, filterId: String?, filterName: String?) = when (mode) {
        ReelsModeType.Scenes -> TabManager.setDefaultFilter(AppTab.Reels, filterId, filterName)
        ReelsModeType.Markers -> TabManager.setDefaultMarkerFilter(AppTab.Reels, filterId, filterName)
        ReelsModeType.Clips -> TabManager.setDefaultClipFilter(AppTab.Reels, filterId, filterName)
        ReelsModeType.Previews -> TabManager.setDefaultPreviewFilter(AppTab.Reels, filterId, filterName)
        ReelsModeType.Pics -> TabManager.setDefaultFilter(AppTab.Images, filterId, filterName)
    }

    private val kotlinx.serialization.json.JsonElement?.str: String?
        get() = (this as? JsonPrimitive)?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.contentOrNull
}
