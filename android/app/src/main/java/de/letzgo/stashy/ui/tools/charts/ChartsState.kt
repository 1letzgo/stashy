package de.letzgo.stashy.ui.tools.charts

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Page
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.TopListPage
import de.letzgo.stashy.data.tools.TopListsLogic
import de.letzgo.stashy.data.tools.TopListsPerformerMetric
import de.letzgo.stashy.data.tools.TopListsRepository
import de.letzgo.stashy.data.tools.TopListsSceneMetric
import de.letzgo.stashy.data.tools.TopListsStudioMetric
import de.letzgo.stashy.data.tools.TopListsTagMetric
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * One ranked category of the Charts tool: one list + paging cursor per metric, the selected
 * metric and the loading flags. iOS keeps these as parallel `@Published` properties
 * (`scenesByViews`, `scenePaging`, `isLoadingScenes` …) in `TopListsViewModel`.
 */
class TopListsSectionState<M, T>(
    val metrics: List<M>,
    defaultMetric: M,
    private val idOf: (T) -> String,
    private val fetch: suspend (metric: M, page: Int) -> Page<T>,
) {
    var metric by mutableStateOf(defaultMetric)
    private val lists = mutableStateMapOf<M, List<T>>()
    private val paging = mutableStateMapOf<M, TopListPage>()
    var isLoading by mutableStateOf(false); private set
    var isLoadingMore by mutableStateOf(false); private set
    var didFail by mutableStateOf(false); private set
    private var generation = 0

    /** iOS: `has<X>Content`. */
    val hasContent: Boolean get() = lists.values.any { it.isNotEmpty() }
    /** iOS: `<x>ForSelectedMetric`. */
    val items: List<T> get() = lists[metric].orEmpty()
    /** iOS: `hasMore<X>`. */
    val hasMore: Boolean get() = paging[metric]?.hasMore ?: false

    fun list(metric: M): List<T> = lists[metric].orEmpty()

    /** Replaces one list in place (live patches); no-op when unchanged. */
    fun update(metric: M, transform: (List<T>) -> List<T>) {
        val current = lists[metric] ?: return
        val next = transform(current)
        if (next !== current) lists[metric] = next
    }

    /** iOS: `reload<X>()` — first page of every metric in parallel. */
    suspend fun reload() {
        val gen = ++generation
        isLoading = true
        didFail = false
        try {
            val results = coroutineScope {
                metrics.map { m -> async { fetchOrNull(m, 1) } }.awaitAll()
            }
            if (gen != generation) return
            metrics.forEachIndexed { i, m ->
                val r = results[i]
                if (r != null) {
                    lists[m] = r.items
                    paging[m] = TopListPage.afterFirstPage(r.items.size, r.count)
                } else {
                    lists[m] = emptyList()
                    paging[m] = TopListPage.exhausted
                }
            }
            didFail = results.all { it == null }
        } finally {
            if (gen == generation) isLoading = false
        }
    }

    /** iOS: `loadMore<X>()` — next page of the selected metric. */
    suspend fun loadMore() {
        if (isLoading || isLoadingMore) return
        val m = metric
        val page = paging[m]?.takeIf { it.hasMore } ?: return
        val gen = generation
        isLoadingMore = true
        try {
            val r = fetchOrNull(m, page.nextPage) ?: return
            if (gen != generation) return
            val merged = TopListsLogic.appendUnique(lists[m].orEmpty(), r.items, idOf)
            lists[m] = merged
            paging[m] = page.afterLoadMore(r.items.size, merged.size, r.count)
        } finally {
            isLoadingMore = false
        }
    }

    /** iOS: part of `reset()`. */
    fun reset() {
        generation++
        lists.clear()
        paging.clear()
        didFail = false
        isLoading = false
        isLoadingMore = false
    }

    private suspend fun fetchOrNull(m: M, page: Int): Page<T>? = try {
        fetch(m, page)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }
}

/**
 * iOS: `TopListsViewModel` — the four ranked categories of Tools › Charts.
 * Held process-wide by [ChartsState] so the lists stay warm while switching tools
 * (iOS: `@StateObject` on `ToolsView`).
 */
class TopListsViewModel {
    /** Scope for work that must outlive a composable (pagination). */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Server the lists were loaded from; a change resets everything (iOS: `onChange(of: activeConfig?.id)`). */
    var serverId: String? = null

    val scenes = TopListsSectionState(
        TopListsSceneMetric.entries, TopListsSceneMetric.WatchTime, Scene::id,
    ) { m, page -> TopListsRepository.scenes(m, page) }

    val performers = TopListsSectionState(
        TopListsPerformerMetric.entries, TopListsPerformerMetric.OCount, Performer::id,
    ) { m, page -> TopListsRepository.performers(m, page) }

    val studios = TopListsSectionState(
        TopListsStudioMetric.entries, TopListsStudioMetric.Scenes, Studio::id,
    ) { m, page -> TopListsRepository.studios(m, page) }

    val tags = TopListsSectionState(
        TopListsTagMetric.entries, TopListsTagMetric.Scenes, Tag::id,
    ) { m, page -> TopListsRepository.tags(m, page) }

    /** iOS: `reset()`. */
    fun reset() {
        scenes.reset(); performers.reset(); studios.reset(); tags.reset()
    }

    /** Resets when the active server differs from the one the lists came from. */
    fun syncServer(id: String?) {
        if (id != serverId) {
            reset()
            serverId = id
        }
    }

    // MARK: Live patches — iOS observes `SceneOCounterUpdated`, `SceneUpdated`, `SceneCoverUpdated`.
    // Android has no notification centre in the foundation; whoever changes a scene calls these.

    /** iOS: `patchSceneOCounter(sceneId:oCounter:)`. */
    fun patchSceneOCounter(sceneId: String, oCounter: Int) {
        val all = TopListsSceneMetric.entries.map { scenes.list(it) }
        val existing = all.firstNotNullOfOrNull { list -> list.firstOrNull { it.id == sceneId } }
        val performerIds = existing?.performers?.map { it.id }.orEmpty()
        val previous = all.firstNotNullOfOrNull { list -> list.firstOrNull { it.id == sceneId }?.oCounter }
        TopListsSceneMetric.entries.forEach { m -> scenes.update(m) { TopListsLogic.withSceneOCounter(it, sceneId, oCounter) } }
        scenes.update(TopListsSceneMetric.OCount) { TopListsLogic.sortScenesByOCounter(it) }

        val delta = oCounter - (previous ?: oCounter)
        if (delta == 0 || performerIds.isEmpty()) return
        TopListsPerformerMetric.entries.forEach { m ->
            performers.update(m) { TopListsLogic.bumpPerformersOCounter(it, performerIds, delta) }
        }
        performers.update(TopListsPerformerMetric.OCount) { TopListsLogic.sortPerformersByOCounter(it) }
    }

    /** iOS: `patchSceneMetadata(_:)`. */
    fun patchSceneMetadata(scene: Scene) {
        TopListsSceneMetric.entries.forEach { m -> scenes.update(m) { TopListsLogic.mergeScene(it, scene) } }
        scenes.update(TopListsSceneMetric.Rating) { TopListsLogic.sortScenesByRating(it) }
    }

    /** iOS: `patchSceneCover(sceneId:updatedAt:)`. */
    fun patchSceneCover(sceneId: String, updatedAt: String) {
        TopListsSceneMetric.entries.forEach { m -> scenes.update(m) { TopListsLogic.withSceneUpdatedAt(it, sceneId, updatedAt) } }
    }
}

/** iOS: `TopListsToolsContainerView.Section`. */
enum class ChartsSection(val title: String) {
    Scenes("Scenes"), Performers("Performers"), Studios("Studios"), Tags("Tags"),
}

/** Process-wide state of Tools › Charts (survives switching tools). */
object ChartsState {
    val viewModel = TopListsViewModel()
    /** iOS: `@State section` of `TopListsToolsContainerView`. */
    var section by mutableStateOf(ChartsSection.Scenes)
}
