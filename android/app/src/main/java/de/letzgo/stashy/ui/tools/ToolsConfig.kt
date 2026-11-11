package de.letzgo.stashy.ui.tools

import de.letzgo.stashy.R
import de.letzgo.stashy.UiText
import de.letzgo.stashy.tr
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.StashyPlus
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** iOS: `ToolsItem` (raw values identical — persisted in `ToolsConfig_<serverID>`). */
@Serializable
enum class ToolsItem(private val titleText: UiText) {
    @SerialName("server") Server(UiText(R.string.server)),
    @SerialName("downloads") Downloads(UiText(R.string.downloads)),
    @SerialName("statistics") Statistics(UiText(R.string.overview)),
    @SerialName("oCount") OCount(UiText(R.string.o_count)),
    @SerialName("timeline") Timeline(UiText(R.string.timeline)),
    @SerialName("topLists") TopLists(UiText(R.string.charts)),
    @SerialName("filters") Filters(UiText(R.string.filters)),
    @SerialName("hotOrNot") HotOrNot(UiText(R.string.match)),
    @SerialName("rateMe") RateMe(UiText("RateMe"));
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = titleText.text

    /** Name used in stashy+ settings / paywall lists. */
    val plusFeatureTitle: String get() = if (this == HotOrNot) tr(R.string.performer_match) else title
}

/** iOS: `ToolsItemConfig`. */
@Serializable
data class ToolsItemConfig(val id: ToolsItem, val isEnabled: Boolean, val sortOrder: Int)

/**
 * iOS: the Tools part of `TabManager` (`loadTools`, `saveTools`, `enabledTools`,
 * `repairMissingToolsIfNeeded`, `isStashyPlusTool`, `toggleTool`, `moveTools`). Same per-server
 * prefs key and JSON shape. The Tools grid itself uses fixed groups (`ToolsView.toolGroups`);
 * this config still drives which tools count as enabled for other screens.
 */
object ToolsConfig {
    private const val TOOLS_KEY = "ToolsConfig"
    private val serializer = ListSerializer(ToolsItemConfig.serializer())

    var tools by mutableStateOf<List<ToolsItemConfig>>(emptyList())
        private set
    private var loadedFor: String? = null

    private val currentKey: String get() = Prefs.serverKey(TOOLS_KEY)

    /** Loads (once per server) — cheap to call from composables. */
    fun ensureLoaded() {
        if (loadedFor != currentKey) load()
    }

    fun load() {
        val key = currentKey
        loadedFor = key
        var raw = Prefs.string(key)
        if (raw == null && key != TOOLS_KEY) {
            raw = Prefs.string(TOOLS_KEY)
            raw?.let { Prefs.setString(key, it) }
        }
        val decoded = raw?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }
        if (decoded != null) {
            val result = decoded.sortedBy { it.sortOrder }.toMutableList()
            var changed = false
            fun ensure(item: ToolsItem, after: ToolsItem?, enabled: Boolean) {
                if (result.any { it.id == item }) return
                val config = ToolsItemConfig(item, enabled, 0)
                val idx = after?.let { a -> result.indexOfFirst { it.id == a } } ?: -1
                if (idx >= 0) result.add(idx + 1, config) else result.add(config)
                changed = true
            }
            ensure(ToolsItem.Statistics, ToolsItem.Downloads, true)
            val statsEnabled = result.firstOrNull { it.id == ToolsItem.Statistics }?.isEnabled ?: true
            ensure(ToolsItem.OCount, ToolsItem.Statistics, statsEnabled)
            ensure(ToolsItem.Timeline, ToolsItem.OCount, statsEnabled)
            ensure(ToolsItem.TopLists, ToolsItem.Timeline, statsEnabled)
            ensure(ToolsItem.Filters, ToolsItem.TopLists, true)
            ToolsItem.entries.forEach { ensure(it, null, true) }
            tools = enforceFixed(result.mapIndexed { i, c -> c.copy(sortOrder = i) })
            if (changed) save()
        } else {
            tools = enforceFixed(listOf(
                ToolsItem.Downloads, ToolsItem.Server, ToolsItem.Statistics, ToolsItem.OCount, ToolsItem.Timeline,
                ToolsItem.TopLists, ToolsItem.Filters, ToolsItem.HotOrNot, ToolsItem.RateMe,
            ).mapIndexed { i, item -> ToolsItemConfig(item, true, i) })
            save()
        }
    }

    fun save() {
        tools = enforceFixed(tools)
        Prefs.setString(currentKey, Json.encodeToString(serializer, tools))
    }

    /** iOS: `enabledTools` — sorted, without Server, stashy+ tools only while unlocked. */
    val enabledTools: List<ToolsItem> get() {
        ensureLoaded()
        return tools.sortedBy { it.sortOrder }.mapNotNull { c ->
            if (c.id == ToolsItem.Server) return@mapNotNull null
            if (isStashyPlusTool(c.id) && !StashyPlus.isUnlocked) return@mapNotNull null
            c.id
        }
    }

    /** iOS: `repairMissingToolsIfNeeded()`. */
    fun repairMissingToolsIfNeeded() {
        ensureLoaded()
        val before = tools.map { it.id }
        val fixed = enforceFixed(tools)
        if (fixed.map { it.id } == before) return
        tools = fixed
        save()
    }

    /** iOS: `isStashyPlusTool(_:)`. */
    fun isStashyPlusTool(item: ToolsItem): Boolean = item != ToolsItem.Server

    fun toggleTool(item: ToolsItem) {
        if (item == ToolsItem.Server) return
        tools = tools.map { if (it.id == item) it.copy(isEnabled = !it.isEnabled) else it }
        save()
    }

    fun moveTools(from: Int, to: Int) {
        val reordered = tools.sortedBy { it.sortOrder }.toMutableList()
        if (from !in reordered.indices) return
        val item = reordered.removeAt(from)
        reordered.add(to.coerceIn(0, reordered.size), item)
        tools = reordered.mapIndexed { i, c -> c.copy(sortOrder = i) }
        save()
    }

    /** iOS: `enforceFixedTools()` — Downloads and O-Count must always exist. */
    private fun enforceFixed(list: List<ToolsItemConfig>): List<ToolsItemConfig> {
        val result = list.toMutableList()
        if (result.none { it.id == ToolsItem.Downloads }) {
            result.add(ToolsItemConfig(ToolsItem.Downloads, true, (result.maxOfOrNull { it.sortOrder } ?: 0) + 1))
        }
        if (result.none { it.id == ToolsItem.OCount }) {
            val statsEnabled = result.firstOrNull { it.id == ToolsItem.Statistics }?.isEnabled ?: true
            val config = ToolsItemConfig(ToolsItem.OCount, statsEnabled, 0)
            val idx = result.indexOfFirst { it.id == ToolsItem.Statistics }
            if (idx >= 0) result.add(idx + 1, config) else result.add(config)
            return result.mapIndexed { i, c -> c.copy(sortOrder = i) }
        }
        return result
    }
}
