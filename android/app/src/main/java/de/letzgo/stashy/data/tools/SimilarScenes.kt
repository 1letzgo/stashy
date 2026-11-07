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

    private var cacheServer: String? = null
    /** Keyed by [signature], not by scene id (the detail first renders the list version). */
    private val cache = HashMap<String, List<Scene>>()

    fun signature(scene: Scene): String = SimilarScenesScoring.signature(scene)

    fun invalidate() {
        cache.clear()
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
        // Everything from the device's scene index, cards included — no server request.
        // Right after an update the index is still being built: wait for it instead of showing nothing.
        val index = AITagSuggestions.waitForSceneIndex()?.takeIf { it.scenes.isNotEmpty() } ?: return emptyList()
        val ids = rankLocal(index, performerIds.toSet(), tagIds.toSet(), studioId, scene.id, maxOf(limit, maxCount))
        val scenes = index.scenes.mapNotNull { e -> e.scene?.let { e.id to it } }.toMap()
        val ranked = ids.mapNotNull { scenes[it] }
        cache[key] = ranked
        return ranked.take(limit)
    }

    /** iOS name. */
    suspend fun similarScenes(scene: Scene): List<Scene> = find(scene)

    /** Scenes per tag in the index, counted once per index build. */
    private var indexTagCounts: Pair<Long, Map<String, Int>>? = null

    /** iOS `rankLocal`: the same weighting as [SimilarScenesScoring.rank] over every scene of the index; best ids first. */
    private fun rankLocal(index: LocalSceneIndex, performerIds: Set<String>, tagIds: Set<String>, studioId: String?, excluding: String, limit: Int): List<String> {
        val counts = indexTagCounts?.takeIf { it.first == index.builtAt }?.second ?: HashMap<String, Int>().also { built ->
            index.scenes.forEach { e -> e.t.forEach { built.merge(it, 1, Int::plus) } }
            indexTagCounts = index.builtAt to built
        }
        val total = index.scenes.size
        val rarityById = tagIds.associateWith { SimilarScenesScoring.rarity(counts[it], total) }
        val related = AITagSuggestions.relatedTagWeights(tagIds.toList())
        return index.scenes.asSequence()
            .filter { it.id != excluding && it.scene != null }
            .mapNotNull { e ->
                var score = e.p.count { it in performerIds } * SimilarScenesScoring.PERFORMER_WEIGHT
                var bonus = 0.0
                for (t in e.t) {
                    val r = rarityById[t]
                    if (r != null) score += SimilarScenesScoring.TAG_WEIGHT * r else related[t]?.let { bonus += it }
                }
                if (studioId != null && e.s == studioId) score += SimilarScenesScoring.STUDIO_WEIGHT
                score += minOf(bonus, SimilarScenesScoring.RELATED_BONUS_CAP) * SimilarScenesScoring.RELATED_TAG_WEIGHT
                if (score > 0) e.id to score else null
            }
            .sortedWith(compareByDescending<Pair<String, Double>> { it.second }.thenBy { it.first })
            .take(limit)
            .map { it.first }
            .toList()
    }
}
