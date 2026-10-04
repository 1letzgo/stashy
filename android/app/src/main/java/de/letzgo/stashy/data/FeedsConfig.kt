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

/** iOS: `ReelsModeType` (raw values identical: scenes, markers, clips, previews, pics). */
@Serializable
enum class ReelsModeType {
    scenes, markers, clips, previews, pics;

    /** iOS: `defaultTitle`. */
    val title: String get() = when (this) {
        scenes -> "Scenes"; markers -> "Markers"; clips -> "Clips"; previews -> "Previews"; pics -> "Pics"
    }

    /** iOS: `ReelsMode.rawValue` ("Scenes", "Markers" …) — the deep-link / session spelling. */
    val modeRaw: String get() = title

    companion object {
        fun fromModeRaw(raw: String?): ReelsModeType? = entries.firstOrNull { it.title == raw || it.name == raw }
    }
}

/** iOS: `ReelsModeConfig` — same JSON keys (`id` is an upper-case UUID string like Swift's encoder). */
@Serializable
data class ReelsModeConfig(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val type: ReelsModeType,
    val isEnabled: Boolean = true,
    val sortOrder: Int = 0,
    val defaultSortOption: String? = null,
)

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
        ReelsModeConfig(type = ReelsModeType.scenes, sortOrder = 0),
        ReelsModeConfig(type = ReelsModeType.markers, sortOrder = 1),
        ReelsModeConfig(type = ReelsModeType.clips, sortOrder = 2),
        ReelsModeConfig(type = ReelsModeType.previews, sortOrder = 3),
        ReelsModeConfig(type = ReelsModeType.pics, sortOrder = 4, defaultSortOption = "dateDesc"),
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
            ReelsModeConfig(type = t, sortOrder = modes.size + i, defaultSortOption = if (t == ReelsModeType.pics) "dateDesc" else null)
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

    private var loadedFor: String? = null
    private var _modes by mutableStateOf<List<ReelsModeConfig>>(emptyList())

    private fun serverSuffix(): String = ServerConfigManager.activeConfig?.id?.let { "_$it" } ?: ""

    /** Reloads when the active server changed (iOS: `handleServerChange`). */
    private fun ensureLoaded() {
        val suffix = serverSuffix()
        if (loadedFor == suffix) return
        loadedFor = suffix
        var raw = Prefs.string("$MODES_KEY$suffix")
        if (raw == null && suffix.isNotEmpty()) {
            raw = Prefs.string(MODES_KEY)
            raw?.let { Prefs.setString("$MODES_KEY$suffix", it) }
        }
        val (modes, repaired) = ReelsModesCodec.decode(raw)
        _modes = modes
        if (repaired) save()
    }

    /** iOS: `reelsModes` (sorted by `sortOrder`). */
    val modes: List<ReelsModeConfig> get() { ensureLoaded(); return _modes }

    /** iOS: `enabledReelsModes`. */
    val enabledModes: List<ReelsModeType> get() = ReelsModesCodec.enabled(modes)

    private fun save() = Prefs.setString("$MODES_KEY${serverSuffix()}", ReelsModesCodec.encode(_modes))

    fun toggleMode(type: ReelsModeType) { ensureLoaded(); _modes = ReelsModesCodec.toggle(_modes, type); save() }
    fun moveMode(from: Int, to: Int) { ensureLoaded(); _modes = ReelsModesCodec.move(_modes, from, to); save() }
    fun defaultSort(type: ReelsModeType): String? = modes.firstOrNull { it.type == type }?.defaultSortOption
    fun setDefaultSort(type: ReelsModeType, option: String) { ensureLoaded(); _modes = ReelsModesCodec.withDefaultSort(_modes, type, option); save() }

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
    fun defaultFilterId(mode: ReelsModeType): String? {
        val (tab, field) = defaultFilterSlot(mode)
        return tabConfigs().firstOrNull { it["id"].str == tab }?.get(field).str?.takeIf { it.isNotEmpty() }
    }

    /** Patches only the one field of the one tab entry (adds the entry when missing). */
    fun setDefaultFilter(mode: ReelsModeType, filterId: String?, filterName: String?) {
        val (tab, field) = defaultFilterSlot(mode)
        val nameField = field.replace("Id", "Name")
        val list = tabConfigs().toMutableList()
        val index = list.indexOfFirst { it["id"].str == tab }
        val base = if (index >= 0) list[index] else JsonObject(mapOf("id" to JsonPrimitive(tab), "isVisible" to JsonPrimitive(true), "sortOrder" to JsonPrimitive(list.size)))
        val patched = JsonObject(base + mapOf(field to (filterId?.let { JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull), nameField to (filterName?.let { JsonPrimitive(it) } ?: kotlinx.serialization.json.JsonNull)))
        if (index >= 0) list[index] = patched else list.add(patched)
        Prefs.setString("$TABS_KEY${serverSuffix()}", JsonArray(list).toString())
    }

    private fun defaultFilterSlot(mode: ReelsModeType): Pair<String, String> = when (mode) {
        ReelsModeType.scenes -> "reels" to "defaultFilterId"
        ReelsModeType.markers -> "reels" to "defaultMarkerFilterId"
        ReelsModeType.clips -> "reels" to "defaultClipFilterId"
        ReelsModeType.previews -> "reels" to "defaultPreviewFilterId"
        ReelsModeType.pics -> "images" to "defaultFilterId"
    }

    private fun tabConfigs(): List<JsonObject> {
        val raw = Prefs.string("$TABS_KEY${serverSuffix()}") ?: Prefs.string(TABS_KEY) ?: return emptyList()
        return runCatching { Json.parseToJsonElement(raw) as? JsonArray }.getOrNull()?.mapNotNull { it as? JsonObject }.orEmpty()
    }

    private val kotlinx.serialization.json.JsonElement?.str: String?
        get() = (this as? JsonPrimitive)?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.contentOrNull
}
