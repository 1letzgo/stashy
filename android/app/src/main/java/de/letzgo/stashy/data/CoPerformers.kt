package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import java.util.concurrent.ConcurrentHashMap

/** A performer who shares [sharedScenes] scenes with the opened performer. */
data class CoPerformer(val performer: Performer, val sharedScenes: Int)

/**
 * "Appears with" tab of the performer detail (iOS implements the same logic): every scene of the
 * performer (only `performers { id }`), shared-scene count per co-performer, then those
 * performers via `findPerformers` with Stash's co-appearance criterion AND the tab's own filter &
 * sort sheet ([CoPerformerLogic.performerRequest]), intersected with the shared-scene ids and
 * ordered by [CoPerformerLogic.ordered].
 * Shared-scene counts are cached per server + performer, results additionally per filter + sort,
 * for the session; pull-to-refresh ([load] with `force`) drops both.
 */
object CoPerformersRepository {
    private const val SCENE_PAGE = 1000

    private const val SCENES_QUERY =
        "query CoPerformerScenes(\$filter: FindFilterType, \$scene_filter: SceneFilterType) { " +
            "findScenes(filter: \$filter, scene_filter: \$scene_filter) { count scenes { performers { id } } } }"

    private val counts = ConcurrentHashMap<String, Map<String, Int>>()
    private val results = ConcurrentHashMap<String, List<CoPerformer>>()

    private fun key(performerId: String) = "${ServerConfigManager.activeConfig?.id.orEmpty()}|$performerId"

    suspend fun load(performerId: String, query: CatalogQuery, force: Boolean = false): List<CoPerformer> {
        val base = key(performerId)
        if (force) {
            counts.remove(base)
            results.keys.removeAll { it.startsWith("$base|") }
        }
        val resultKey = CoPerformerLogic.cacheKey(base, query)
        results[resultKey]?.let { return it }
        val shared = counts[base]
            ?: CoPerformerLogic.count(fetchScenePerformerIds(performerId), performerId).also { counts[base] = it }
        val performers = if (shared.isEmpty()) emptyList() else {
            val vars = CoPerformerLogic.performerRequest(performerId, query)
            val obj = GraphQL.named("findPerformers", vars)["findPerformers"] as? JsonObject
            GraphQL.decode(ListSerializer(Performer.serializer()), obj?.get("performers") ?: JsonArray(emptyList()))
        }
        return CoPerformerLogic.ordered(performers, shared, query.sort).also { results[resultKey] = it }
    }

    /** Performer ids of every scene of [performerId], one list per scene. */
    private suspend fun fetchScenePerformerIds(performerId: String): List<List<String>> {
        val sceneFilter = DetailRepository.scope("performers", performerId)
        val result = mutableListOf<List<String>>()
        var page = 1
        while (true) {
            val vars = buildJsonObject {
                put("filter", FindFilter(page, SCENE_PAGE, sort = "id", direction = "ASC").json())
                put("scene_filter", sceneFilter)
            }
            val obj = GraphQL.data(SCENES_QUERY, vars)["findScenes"] as? JsonObject ?: break
            val total = (obj["count"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: 0
            val scenes = (obj["scenes"] as? JsonArray).orEmpty()
            scenes.forEach { s ->
                val ids = ((s as? JsonObject)?.get("performers") as? JsonArray).orEmpty()
                    .mapNotNull { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull }
                result += ids
            }
            if (scenes.isEmpty() || result.size >= total) break
            page++
        }
        return result
    }
}

/**
 * Sorts only the "Appears with" tab offers on top of the performer sorts: the shared-scene count
 * (applied on the client — the server knows nothing about it). [Default] is the tab's original order.
 */
object CoPerformerSort {
    const val FIELD = "shared_scenes"
    val Desc = SortOption("sharedScenesDesc", "Shared scenes (High-Low)", FIELD, "DESC")
    val Asc = SortOption("sharedScenesAsc", "Shared scenes (Low-High)", FIELD, "ASC")
    val Default = Desc
    val options = listOf(Desc, Asc)

    fun isShared(sort: SortOption) = sort.field == FIELD
}

/** Pure counting / request building / ordering of [CoPerformersRepository] (unit-tested). */
object CoPerformerLogic {
    /** Shared scenes per co-performer id; [selfId] excluded, an id counted once per scene. */
    fun count(scenePerformerIds: List<List<String>>, selfId: String): Map<String, Int> {
        val counts = HashMap<String, Int>()
        scenePerformerIds.forEach { ids ->
            ids.toSet().forEach { id -> if (id != selfId) counts[id] = (counts[id] ?: 0) + 1 }
        }
        return counts
    }

    /**
     * `findPerformers` variables. Stash ignores `performer_filter`, sort and paging when `ids` is
     * passed, so no ids: `performer_filter` = the tab's criteria AND Stash's co-appearance
     * criterion `performers: { value: [performerId], modifier: INCLUDES }` (layered last, it
     * always wins), all results (`per_page: -1`). "Shared scenes" sorts on the client (request
     * by name); any other sort is the server's. The caller intersects the result with the
     * locally counted shared-scene ids (Stash's co-appearance also counts images / galleries).
     */
    fun performerRequest(performerId: String, query: CatalogQuery): JsonObject {
        val scoped = query.copy(scope = DetailRepository.scope("performers", performerId))
        val find = if (CoPerformerSort.isShared(query.sort)) FindFilter(1, -1, sort = "name", direction = "ASC", q = query.search)
            else CatalogRepository.findFilter(query, 1, -1)
        return buildJsonObject {
            put("filter", find.json())
            scoped.entityFilter()?.let { put("performer_filter", it) }
        }
    }

    /** Result cache key: performer scope + sort + search + the effective `performer_filter`. */
    fun cacheKey(base: String, query: CatalogQuery): String =
        "$base|${query.sort.raw}|${query.search}|${query.entityFilter() ?: ""}"

    /**
     * Performers with a shared-scene count (intersection with [counts]). "Shared scenes" orders by count (direction of [sort]), then
     * name (case-insensitive), then id; any other sort keeps the server's order.
     */
    fun ordered(performers: List<Performer>, counts: Map<String, Int>, sort: SortOption): List<CoPerformer> {
        val list = performers.distinctBy { it.id }
            .mapNotNull { p -> counts[p.id]?.takeIf { it > 0 }?.let { CoPerformer(p, it) } }
        if (!CoPerformerSort.isShared(sort)) return list
        val byCount = if (sort.isAscending) compareBy<CoPerformer> { it.sharedScenes } else compareByDescending { it.sharedScenes }
        return list.sortedWith(
            byCount.thenBy(String.CASE_INSENSITIVE_ORDER) { it.performer.name }.thenBy { it.performer.id },
        )
    }

    /** Performers with a count, by shared count desc, then name (case-insensitive), then id. */
    fun sorted(performers: List<Performer>, counts: Map<String, Int>): List<CoPerformer> =
        ordered(performers, counts, CoPerformerSort.Desc)

    /**
     * Scene scope of the scenes [performerId] and [otherId] share:
     * `performers: { value: [a, b], modifier: INCLUDES_ALL }` (Stash `MultiCriterionInput`).
     */
    fun sharedScenesScope(performerId: String, otherId: String): JsonObject = buildJsonObject {
        put("performers", buildJsonObject {
            put("value", JsonArray(listOf(JsonPrimitive(performerId), JsonPrimitive(otherId))))
            put("modifier", JsonPrimitive("INCLUDES_ALL"))
        })
    }
}
