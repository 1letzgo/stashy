package de.letzgo.stashy.tv

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.CatalogRepository
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.resolvedSort
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** iOS: `TVChannel.Scope` — entity-scoped channels, keyed by the scene-filter field. */
enum class TvChannelScope(val raw: String, val label: String) {
    Performer("performers", "Performer"), Studio("studios", "Studio"), Tag("tags", "Tag"), Group("groups", "Group");

    /** Everything but `performers` is a `HierarchicalMultiCriterionInput` (needs `depth`). */
    val isHierarchical: Boolean get() = this != Performer
}

/**
 * iOS: `TVChannel` — continuous playback of a built-in sort, a saved scene filter, or every
 * scene of one performer, studio, tag or group (stashy+).
 */
data class TvChannel(
    val kind: Kind,
    val title: String,
    val savedFilter: SavedFilter? = null,
    val scope: TvChannelScope? = null,
    val entityId: String? = null,
) {
    enum class Kind { RecentlyReleased, RecentlyAdded, SavedFilter, Scoped }

    val id: String get() = when (kind) {
        Kind.RecentlyReleased -> "channel.recentlyReleased"
        Kind.RecentlyAdded -> "channel.recentlyAdded"
        Kind.SavedFilter -> "channel.filter.${savedFilter?.id ?: title}"
        Kind.Scoped -> "channel.${scope?.raw}.$entityId"
    }

    val sortRaw: String get() = when (kind) {
        Kind.RecentlyAdded -> "createdAtDesc"
        Kind.SavedFilter -> savedFilter?.resolvedSort(FilterMode.Scenes)?.raw ?: "dateDesc"
        else -> "dateDesc"
    }

    val subtitle: String get() = when (kind) {
        Kind.SavedFilter -> "Saved filter"
        Kind.Scoped -> scope?.label ?: "Channel"
        else -> "Channel"
    }

    /** Ad-hoc scene filter of an entity channel (it has no counterpart on the server). */
    fun scopeFilter(): JsonObject? {
        if (kind != Kind.Scoped) return null
        val s = scope ?: return null
        val id = entityId ?: return null
        val criterion = buildJsonObject {
            put("modifier", JsonPrimitive("INCLUDES"))
            put("value", JsonArray(listOf(JsonPrimitive(id))))
            if (s.isHierarchical) put("depth", JsonPrimitive(0))
        }
        return buildJsonObject { put(s.raw, criterion) }
    }

    fun query(): CatalogQuery = CatalogQuery(
        mode = FilterMode.Scenes,
        sort = SortCatalog.option(FilterMode.Scenes, sortRaw) ?: SortCatalog.option(FilterMode.Scenes, "dateDesc")!!,
        base = if (kind == Kind.SavedFilter) savedFilter else null,
        scope = scopeFilter(),
    )

    companion object {
        val recentlyReleased = TvChannel(Kind.RecentlyReleased, "Recently Released")
        val recentlyAdded = TvChannel(Kind.RecentlyAdded, "Recently Added")
        fun savedFilter(filter: SavedFilter) = TvChannel(Kind.SavedFilter, filter.name, savedFilter = filter)
        fun performer(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Performer, entityId = id)
        fun studio(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Studio, entityId = id)
        fun tag(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Tag, entityId = id)
        fun group(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Group, entityId = id)
    }
}

val TvChannel.icon: ImageVector get() = when (kind) {
    TvChannel.Kind.RecentlyReleased -> TvIcons.sparklesTv
    TvChannel.Kind.RecentlyAdded -> TvIcons.plusFolder
    TvChannel.Kind.SavedFilter -> TvIcons.filterFill
    TvChannel.Kind.Scoped -> when (scope) {
        TvChannelScope.Performer -> TvIcons.person
        TvChannelScope.Studio -> TvIcons.building
        TvChannelScope.Tag -> TvIcons.tag
        else -> TvIcons.stack
    }
}

/**
 * iOS: `TVChannelSession` — pages through the channel (20 per page), plays the scenes one after
 * another on one player, wraps around at the end, skips scenes without a stream.
 */
class TvChannelSession(val channel: TvChannel) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val player = TvPlaybackModel()

    val scenes = mutableStateListOf<Scene>()
    var currentIndex by mutableIntStateOf(0); private set
    var isLoading by mutableStateOf(true); private set
    var errorMessage by mutableStateOf<String?>(null); private set

    private var totalCount = 0
    private var currentPage = 0
    private var isLoadingMore = false
    private var skipFailures = 0
    private val pageSize = 20
    private val maxSkipFailures = 5

    val currentScene: Scene? get() = scenes.getOrNull(currentIndex)
    val canGoPrevious: Boolean get() = currentIndex > 0
    val canGoNext: Boolean get() = scenes.isNotEmpty()

    val indexLabel: String get() {
        val total = maxOf(totalCount, scenes.size)
        return if (total > 0) "${currentIndex + 1} / $total" else ""
    }

    init { player.onPlaybackEnded = { playNext() } }

    fun start() {
        isLoading = true
        errorMessage = null
        scope.launch {
            val page = runCatching { CatalogRepository.find<Scene>(channel.query(), 1, pageSize) }.getOrNull()
            scenes.clear()
            page?.let { scenes.addAll(it.items); totalCount = it.count }
            currentPage = 1
            isLoading = false
            if (scenes.isEmpty()) errorMessage = "No scenes in this channel" else play(0)
        }
    }

    /** Back on the player: pause, keep the engine until the page is gone. */
    fun stop() { player.onPlaybackEnded = null; player.suspend() }

    fun teardown() {
        player.onPlaybackEnded = null
        player.clear()
        scope.cancel()
    }

    fun playPrevious() { if (canGoPrevious) play(currentIndex - 1) }

    fun playNext() {
        when {
            currentIndex + 1 < scenes.size -> play(currentIndex + 1)
            scenes.size < totalCount -> loadMore { playNext() }
            scenes.isNotEmpty() -> play(0)
        }
    }

    /** Jump straight to a scene picked from Up Next. */
    fun play(sceneAt: Int, fromUpNext: Boolean) { if (sceneAt != currentIndex || !fromUpNext) play(sceneAt) }

    fun loadMoreForBrowsing() = loadMore(null)

    private fun play(index: Int) {
        val scene = scenes.getOrNull(index) ?: return
        currentIndex = index
        prefetchIfNeeded()
        if (scene.streamURL == null) { handleMissingStream(); return }
        skipFailures = 0
        val subtitle = scene.studio?.name
        if (player.hasPlayer) player.playNext(scene, subtitle) else player.setup(scene, 0.0, subtitle)
    }

    private fun handleMissingStream() {
        skipFailures++
        if (skipFailures >= maxSkipFailures) { errorMessage = "Unable to play scenes in this channel"; return }
        playNext()
    }

    private fun prefetchIfNeeded() {
        if (!isLoadingMore && scenes.size < totalCount && currentIndex >= scenes.size - 5) loadMore(null)
    }

    private fun loadMore(completion: (() -> Unit)?) {
        if (isLoadingMore || scenes.size >= totalCount) { completion?.invoke(); return }
        isLoadingMore = true
        val next = currentPage + 1
        scope.launch {
            val page = runCatching { CatalogRepository.find<Scene>(channel.query(), next, pageSize) }.getOrNull()
            isLoadingMore = false
            if (page != null) {
                totalCount = page.count
                currentPage = next
                val existing = scenes.map { it.id }.toSet()
                val fresh = page.items.filter { it.id !in existing }
                scenes.addAll(fresh)
                // A page without new scenes ends the channel (no endless paging).
                if (fresh.isEmpty()) totalCount = scenes.size
                completion?.invoke()
            } else if (completion != null && scenes.isNotEmpty()) {
                // Network hiccup: wrap around instead of retrying in a loop.
                play(0)
            }
        }
    }
}
