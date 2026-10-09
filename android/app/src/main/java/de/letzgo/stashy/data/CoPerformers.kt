package de.letzgo.stashy.data

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
 * performers via `findPerformers(ids:)`, sorted by shared count desc, then name.
 * Results are cached per server + performer for the session; pull-to-refresh forces a reload.
 */
object CoPerformersRepository {
    private const val SCENE_PAGE = 1000
    private const val PERFORMER_CHUNK = 200

    private const val SCENES_QUERY =
        "query CoPerformerScenes(\$filter: FindFilterType, \$scene_filter: SceneFilterType) { " +
            "findScenes(filter: \$filter, scene_filter: \$scene_filter) { count scenes { performers { id } } } }"

    private val cache = ConcurrentHashMap<String, List<CoPerformer>>()

    private fun key(performerId: String) = "${ServerConfigManager.activeConfig?.id.orEmpty()}|$performerId"

    fun cached(performerId: String): List<CoPerformer>? = cache[key(performerId)]

    suspend fun load(performerId: String, force: Boolean = false): List<CoPerformer> {
        val k = key(performerId)
        if (!force) cache[k]?.let { return it }
        val counts = CoPerformerLogic.count(fetchScenePerformerIds(performerId), performerId)
        val performers = fetchPerformers(counts.keys.toList())
        return CoPerformerLogic.sorted(performers, counts).also { cache[k] = it }
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

    private suspend fun fetchPerformers(ids: List<String>): List<Performer> =
        ids.chunked(PERFORMER_CHUNK).flatMap { chunk ->
            findPage(
                "findPerformers", "findPerformers", "performers", Performer.serializer(),
                FindFilter(1, -1), extra = mapOf("ids" to chunk),
            ).items
        }
}

/** Pure counting / ordering of [CoPerformersRepository] (unit-tested). */
object CoPerformerLogic {
    /** Shared scenes per co-performer id; [selfId] excluded, an id counted once per scene. */
    fun count(scenePerformerIds: List<List<String>>, selfId: String): Map<String, Int> {
        val counts = HashMap<String, Int>()
        scenePerformerIds.forEach { ids ->
            ids.toSet().forEach { id -> if (id != selfId) counts[id] = (counts[id] ?: 0) + 1 }
        }
        return counts
    }

    /** Performers with a count, by shared count desc, then name (case-insensitive), then id. */
    fun sorted(performers: List<Performer>, counts: Map<String, Int>): List<CoPerformer> =
        performers.distinctBy { it.id }
            .mapNotNull { p -> counts[p.id]?.takeIf { it > 0 }?.let { CoPerformer(p, it) } }
            .sortedWith(
                compareByDescending<CoPerformer> { it.sharedScenes }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.performer.name }
                    .thenBy { it.performer.id },
            )

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
