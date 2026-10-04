package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import de.letzgo.stashy.data.vars
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.builtins.ListSerializer
import kotlin.math.ln

/**
 * iOS: ranking part of `SimilarScenesFinder` as pure functions: weighted overlap of performers,
 * rarity-weighted tags, studio, plus a capped bonus for related (co-occurring) tags.
 */
object SimilarScenesScoring {
    // Weights: who is in it matters most, then what it is about, then who made it.
    const val PERFORMER_WEIGHT = 3.0
    const val TAG_WEIGHT = 1.5
    const val STUDIO_WEIGHT = 1.0
    const val RELATED_TAG_WEIGHT = 0.5
    /** Floor for the rarity factor: a tag on almost every scene still says a little. */
    const val MIN_RARITY = 0.15
    /** Cap of the related-tag bonus, so a heavily tagged scene cannot out-rank a shared performer. */
    const val RELATED_BONUS_CAP = 2.0

    /** iOS: `signature(for:)` — identity of the inputs (same scene with more metadata = new lookup). */
    fun signature(scene: Scene): String {
        val performers = scene.performers.map { it.id }.sorted().joinToString(",")
        val tags = scene.tags.orEmpty().map { it.id }.sorted().joinToString(",")
        return "${scene.id}|p:$performers|t:$tags|s:${scene.studio?.id ?: ""}"
    }

    /** Rarity of a tag, 0.15…1 — classic IDF `log(N / df) / log(N)`, df = `Tag.scene_count`. */
    fun rarity(sceneCount: Int?, totalScenes: Int): Double {
        val df = maxOf(1, sceneCount ?: 1)
        if (totalScenes <= 1 || df >= totalScenes) return MIN_RARITY
        val idf = ln(totalScenes.toDouble() / df) / ln(totalScenes.toDouble())
        return minOf(1.0, maxOf(MIN_RARITY, idf))
    }

    /** Score of one candidate (0 = nothing in common). */
    fun score(
        candidate: Scene,
        performerIds: Set<String>,
        tagIds: Set<String>,
        rarityById: Map<String, Double>,
        studioId: String?,
        related: Map<String, Double>,
    ): Double {
        val candidatePerformers = candidate.performers.map { it.id }.toSet()
        val candidateTags = candidate.tags.orEmpty().map { it.id }.toSet()
        var score = (candidatePerformers intersect performerIds).size * PERFORMER_WEIGHT
        score += (candidateTags intersect tagIds).sumOf { TAG_WEIGHT * (rarityById[it] ?: MIN_RARITY) }
        if (studioId != null && candidate.studio?.id == studioId) score += STUDIO_WEIGHT
        if (related.isNotEmpty()) {
            val bonus = (candidateTags - tagIds).mapNotNull { related[it] }.sum()
            score += minOf(bonus, RELATED_BONUS_CAP) * RELATED_TAG_WEIGHT
        }
        return score
    }

    /**
     * iOS: `rank(candidates:…)` — drops the source scene and scenes without overlap, sorts by
     * score (ties by id ascending) and keeps [maxCount].
     */
    fun rank(
        candidates: List<Scene>,
        performerIds: Set<String>,
        sourceTags: List<Tag>,
        studioId: String?,
        totalScenes: Int,
        excludingSceneId: String,
        related: Map<String, Double> = emptyMap(),
        maxCount: Int = 8,
    ): List<Scene> {
        val tagIds = sourceTags.map { it.id }.toSet()
        val rarityById = sourceTags.associate { it.id to rarity(it.sceneCount, totalScenes) }
        return candidates
            .asSequence()
            .filter { it.id != excludingSceneId }
            .map { it to score(it, performerIds, tagIds, rarityById, studioId, related) }
            .filter { it.second > 0 }
            .sortedWith { a, b -> if (a.second == b.second) a.first.id.compareTo(b.first.id) else b.second.compareTo(a.second) }
            .take(maxCount)
            .map { it.first }
            .toList()
    }
}

/**
 * iOS: `SimilarScenesFinder.shared` (stashy+) — scenes resembling the one on screen, found in the
 * user's own library: one `findScenesSimilar` query per criterion (performers, tags, studio),
 * merged locally and ranked by [SimilarScenesScoring]. Keys `similar_scenes_enabled`,
 * `similar_scenes_max` like iOS.
 */
object SimilarScenes {
    const val ENABLED_KEY = "similar_scenes_enabled"
    const val MAX_COUNT_KEY = "similar_scenes_max"

    /** Upper bound on what the server sends back before local ranking. */
    private const val CANDIDATE_LIMIT = 200

    private var enabledState by mutableStateOf(Prefs.bool(ENABLED_KEY))
    /** Own kill switch — independent of tag suggestions; shares their statistics. */
    var isEnabled: Boolean
        get() = enabledState
        set(value) {
            enabledState = value
            Prefs.setBool(ENABLED_KEY, value)
            AITagSuggestions.statisticsConsumerChanged()
        }

    private var maxState by mutableStateOf(Prefs.int(MAX_COUNT_KEY, 0).let { if (it in 4..8) it else 8 })
    /** How many to show (4…8). */
    var maxCount: Int
        get() = maxState
        set(value) { maxState = value; Prefs.setInt(MAX_COUNT_KEY, value) }

    val isActive: Boolean get() = isEnabled && StashyPlus.isUnlocked

    /** Library scene count for the rarity factor, fetched once per session (per server). */
    private var totalSceneCount: Int? = null
    private var cacheServer: String? = null
    /** Keyed by [signature], not by scene id (the detail first renders the list version). */
    private val cache = HashMap<String, List<Scene>>()

    fun signature(scene: Scene): String = SimilarScenesScoring.signature(scene)

    fun invalidate() {
        cache.clear()
        totalSceneCount = null
    }

    /**
     * iOS: `similarScenes(for:)`. Returns at most [limit] scenes (default: the user's
     * `maxCount`); empty while the feature is off or stashy+ is locked.
     */
    suspend fun find(scene: Scene, limit: Int = maxCount): List<Scene> {
        val server = ServerConfigManager.activeConfig?.id
        if (server != cacheServer) { invalidate(); cacheServer = server }
        val key = signature(scene)
        cache[key]?.let { return it.take(limit) }
        if (!isActive) return emptyList()

        val performerIds = scene.performers.map { it.id }
        val tagIds = scene.tags.orEmpty().map { it.id }
        val studioId = scene.studio?.id
        if (performerIds.isEmpty() && tagIds.isEmpty() && studioId == null) return emptyList()

        // The ranking bonus reads the shared statistics; load them even when suggestions are off.
        AITagSuggestions.loadIfNeeded()

        val candidates = fetchCandidates(performerIds, tagIds, studioId)
        if (candidates.isEmpty()) {
            cache[key] = emptyList()
            return emptyList()
        }
        val ranked = SimilarScenesScoring.rank(
            candidates = candidates,
            performerIds = performerIds.toSet(),
            sourceTags = scene.tags.orEmpty(),
            studioId = studioId,
            totalScenes = loadTotalSceneCount(),
            excludingSceneId = scene.id,
            related = AITagSuggestions.relatedTagWeights(tagIds.distinct()),
            maxCount = maxOf(limit, maxCount),
        )
        cache[key] = ranked
        return ranked.take(limit)
    }

    /** iOS name. */
    suspend fun similarScenes(scene: Scene): List<Scene> = find(scene)

    private suspend fun loadTotalSceneCount(): Int {
        totalSceneCount?.let { return it }
        val count = try {
            GraphQL.data("{ stats { scene_count } }")["stats"].obj?.get("scene_count").stringOrNull?.toIntOrNull() ?: 0
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            0
        }
        totalSceneCount = count
        return count
    }

    /** One query per criterion, run concurrently and merged; one failing still leaves the others. */
    private suspend fun fetchCandidates(performerIds: List<String>, tagIds: List<String>, studioId: String?): List<Scene> {
        val clauses = buildList<Map<String, Any>> {
            if (performerIds.isNotEmpty()) add(mapOf("performers" to mapOf("value" to performerIds, "modifier" to "INCLUDES", "depth" to 0)))
            if (tagIds.isNotEmpty()) add(mapOf("tags" to mapOf("value" to tagIds, "modifier" to "INCLUDES", "depth" to 0)))
            if (studioId != null) add(mapOf("studios" to mapOf("value" to listOf(studioId), "modifier" to "INCLUDES", "depth" to 0)))
        }
        if (clauses.isEmpty()) return emptyList()
        val results = coroutineScope { clauses.map { async { runCandidateQuery(it) } }.awaitAll() }
        val seen = HashSet<String>()
        return results.flatten().filter { seen.add(it.id) }
    }

    private suspend fun runCandidateQuery(filter: Map<String, Any>): List<Scene> = try {
        val data = GraphQL.named("findScenesSimilar", vars("filter" to mapOf("page" to 1, "per_page" to CANDIDATE_LIMIT), "scene_filter" to filter))
        data["findScenes"].obj?.get("scenes")?.let { GraphQL.decode(ListSerializer(Scene.serializer()), it) }.orEmpty()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        emptyList()
    }
}
