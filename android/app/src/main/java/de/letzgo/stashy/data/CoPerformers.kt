package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.util.concurrent.ConcurrentHashMap

/** How often two performers appear together; [images] are those outside the shared galleries. */
data class CoAppearanceCounts(val scenes: Int = 0, val galleries: Int = 0, val images: Int = 0) {
    val total: Int get() = scenes + galleries + images
}

/** A performer who shares scenes, galleries or images with the opened performer. */
data class CoPerformer(val performer: Performer, val shared: CoAppearanceCounts)

/** One gallery / image reduced to what the co-appearance count needs. */
data class CoAppearanceRow(val id: String?, val performers: List<String>, val galleries: List<String> = emptyList())

/**
 * "Appears with" tab of the performer detail (iOS implements the same logic): every scene, gallery
 * and image of the performer (only the ids needed), shared counts per co-performer
 * ([CoPerformerLogic.countAll]), then those
 * performers via `findPerformers` with Stash's co-appearance criterion AND the tab's own filter &
 * sort sheet ([CoPerformerLogic.performerRequest]), intersected with the shared-scene ids and
 * ordered by [CoPerformerLogic.ordered].
 * Shared-scene counts are cached per server + performer, results additionally per filter + sort,
 * for the session; pull-to-refresh ([load] with `force`) drops both.
 */
object CoPerformersRepository {
    private const val PAGE = 1000

    private const val SCENES_QUERY =
        "query CoPerformerScenes(\$filter: FindFilterType, \$scene_filter: SceneFilterType) { " +
            "findScenes(filter: \$filter, scene_filter: \$scene_filter) { count scenes { performers { id } } } }"
    private const val GALLERIES_QUERY =
        "query CoPerformerGalleries(\$filter: FindFilterType, \$gallery_filter: GalleryFilterType) { " +
            "findGalleries(filter: \$filter, gallery_filter: \$gallery_filter) { count galleries { id performers { id } } } }"
    private const val IMAGES_QUERY =
        "query CoPerformerImages(\$filter: FindFilterType, \$image_filter: ImageFilterType) { " +
            "findImages(filter: \$filter, image_filter: \$image_filter) { count images { performers { id } galleries { id } } } }"

    private val counts = ConcurrentHashMap<String, Map<String, CoAppearanceCounts>>()
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
        val shared = counts[base] ?: coroutineScope {
            val scenes = async { fetchRows(performerId, SCENES_QUERY, "findScenes", "scenes", "scene_filter") }
            val galleries = async { fetchRows(performerId, GALLERIES_QUERY, "findGalleries", "galleries", "gallery_filter") }
            val images = async { fetchRows(performerId, IMAGES_QUERY, "findImages", "images", "image_filter") }
            CoPerformerLogic.countAll(scenes.await(), galleries.await(), images.await(), performerId)
        }.also { counts[base] = it }
        val performers = if (shared.isEmpty()) emptyList() else {
            val vars = CoPerformerLogic.performerRequest(performerId, query)
            val obj = GraphQL.named("findPerformers", vars)["findPerformers"] as? JsonObject
            GraphQL.decode(ListSerializer(Performer.serializer()), obj?.get("performers") ?: JsonArray(emptyList()))
        }
        return CoPerformerLogic.ordered(performers, shared, query.sort).also { results[resultKey] = it }
    }

    /** Every scene / gallery / image of [performerId] with its performer (and gallery) ids. */
    private suspend fun fetchRows(
        performerId: String,
        query: String,
        root: String,
        listKey: String,
        filterKey: String,
    ): List<CoAppearanceRow> {
        val filter = DetailRepository.scope("performers", performerId)
        val result = mutableListOf<CoAppearanceRow>()
        var page = 1
        while (true) {
            val vars = buildJsonObject {
                put("filter", FindFilter(page, PAGE, sort = "id", direction = "ASC").json())
                put(filterKey, filter)
            }
            val obj = GraphQL.data(query, vars)[root] as? JsonObject ?: break
            val total = (obj["count"] as? JsonPrimitive)?.contentOrNull?.toIntOrNull() ?: 0
            val rows = (obj[listKey] as? JsonArray).orEmpty()
            rows.forEach { r ->
                val o = r as? JsonObject
                result += CoAppearanceRow(
                    id = (o?.get("id") as? JsonPrimitive)?.contentOrNull,
                    performers = ids(o?.get("performers")),
                    galleries = ids(o?.get("galleries")),
                )
            }
            if (rows.isEmpty() || result.size >= total) break
            page++
        }
        return result
    }

    private fun ids(element: kotlinx.serialization.json.JsonElement?): List<String> =
        (element as? JsonArray).orEmpty().mapNotNull { ((it as? JsonObject)?.get("id") as? JsonPrimitive)?.contentOrNull }
}

/**
 * Sorts only the "Appears with" tab offers on top of the performer sorts: the shared-scene count
 * (applied on the client — the server knows nothing about it). [Default] is the tab's original order.
 */
object CoPerformerSort {
    const val FIELD = "shared_scenes"
    val Desc = SortOption("sharedScenesDesc", tr(R.string.most_shared_high_low), FIELD, "DESC")
    val Asc = SortOption("sharedScenesAsc", tr(R.string.most_shared_low_high), FIELD, "ASC")
    val Default = Desc
    val options = listOf(Desc, Asc)

    fun isShared(sort: SortOption) = sort.field == FIELD
}

/** Pure counting / request building / ordering of [CoPerformersRepository] (unit-tested). */
object CoPerformerLogic {
    /** Shared items per co-performer id; [selfId] excluded, an id counted once per item. */
    fun count(scenePerformerIds: List<List<String>>, selfId: String): Map<String, Int> {
        val counts = HashMap<String, Int>()
        scenePerformerIds.forEach { ids ->
            ids.toSet().forEach { id -> if (id != selfId) counts[id] = (counts[id] ?: 0) + 1 }
        }
        return counts
    }

    /**
     * Shared scenes, galleries and images per co-performer. An image inside a gallery both
     * already share is not counted again, so a 20-picture set reads as one gallery, not 21 items.
     */
    fun countAll(
        scenes: List<CoAppearanceRow>,
        galleries: List<CoAppearanceRow>,
        images: List<CoAppearanceRow>,
        selfId: String,
    ): Map<String, CoAppearanceCounts> {
        val sceneCounts = count(scenes.map { it.performers }, selfId)
        val galleryCounts = count(galleries.map { it.performers }, selfId)
        val galleryPerformers = galleries.mapNotNull { g -> g.id?.let { it to g.performers.toSet() } }.toMap()
        val imageCounts = HashMap<String, Int>()
        images.forEach { image ->
            image.performers.toSet().forEach { id ->
                val inSharedGallery = image.galleries.any { galleryPerformers[it]?.contains(id) == true }
                if (id != selfId && !inSharedGallery) imageCounts[id] = (imageCounts[id] ?: 0) + 1
            }
        }
        return (sceneCounts.keys + galleryCounts.keys + imageCounts.keys).associateWith {
            CoAppearanceCounts(sceneCounts[it] ?: 0, galleryCounts[it] ?: 0, imageCounts[it] ?: 0)
        }
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
    fun ordered(performers: List<Performer>, counts: Map<String, CoAppearanceCounts>, sort: SortOption): List<CoPerformer> {
        val list = performers.distinctBy { it.id }
            .mapNotNull { p -> counts[p.id]?.takeIf { it.total > 0 }?.let { CoPerformer(p, it) } }
        if (!CoPerformerSort.isShared(sort)) return list
        val byCount = if (sort.isAscending) compareBy<CoPerformer> { it.shared.total } else compareByDescending { it.shared.total }
        return list.sortedWith(
            byCount.thenBy(String.CASE_INSENSITIVE_ORDER) { it.performer.name }.thenBy { it.performer.id },
        )
    }

    /** Performers with a count, by shared count desc, then name (case-insensitive), then id. */
    fun sorted(performers: List<Performer>, counts: Map<String, CoAppearanceCounts>): List<CoPerformer> =
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
