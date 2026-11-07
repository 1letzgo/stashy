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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** iOS: `SceneRecommendation.Reason` — why a scene is in For You. */
@kotlinx.serialization.Serializable
sealed class RecommendationReason {
    @kotlinx.serialization.Serializable data class Performer(val name: String) : RecommendationReason()
    @kotlinx.serialization.Serializable data class Studio(val name: String) : RecommendationReason()
    @kotlinx.serialization.Serializable data class Tag(val name: String) : RecommendationReason()
    @kotlinx.serialization.Serializable data class RelatedTag(val name: String) : RecommendationReason()
    @kotlinx.serialization.Serializable data class SimilarTo(val title: String) : RecommendationReason()
    @kotlinx.serialization.Serializable data object Rediscover : RecommendationReason()
    @kotlinx.serialization.Serializable data object Favorite : RecommendationReason()

    val label: String get() = when (this) {
        is Performer -> "More with $name"
        is Studio -> "More from $name"
        is Tag -> "You like $name"
        is RelatedTag -> "Goes with your tags: $name"
        is SimilarTo -> "Like “$title”"
        Rediscover -> "Rediscover"
        Favorite -> "One of your favorites"
    }
}

/** iOS: `SceneRecommendation`. */
@kotlinx.serialization.Serializable
data class SceneRecommendation(val scene: Scene, val reason: RecommendationReason, val isUnwatched: Boolean, val score: Double) {
    val id: String get() = scene.id
}

/** iOS: `RecommendationDiscovery` (raw values identical). */
enum class RecommendationDiscovery(val raw: String, val title: String, val detail: String) {
    Fresh("fresh", "New only", "Only scenes you have never played."),
    Balanced("balanced", "Balanced", "Unplayed scenes and scenes you have not played in this period, weighed the same."),
    Favorites("favorites", "Favorites", "Scenes with O-Counts or high ratings you have not played in a while.");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Balanced }
}

/** iOS: `SceneRecommendationEngine.State`. */
enum class RecommendationState { Idle, Loading, Ready, NoHistory, Failed }

/**
 * iOS: `SceneRecommendationEngine` (stashy+) — the For You row on Home.
 *
 * 1. Profile from the scenes played in the look-back window (recency, replays, O stamps,
 *    completion, rating); tags weighted by rarity (IDF).
 * 2. Candidates: top performers / studios / tags, plus unplayed scenes close to the scenes
 *    engaged with most; random order seeded per app start.
 * 3. Score with the user's weights; 4. diversify; the strongest factor is the reason.
 * The last three lists step back, so every launch shows a new list. Keys identical to iOS.
 */
object SceneRecommendations {
    private const val KEY_LOOKBACK = "recommendations_lookback_days"
    private const val KEY_COUNT = "recommendations_count"
    private const val KEY_PERFORMER = "recommendations_weight_performer"
    private const val KEY_STUDIO = "recommendations_weight_studio"
    private const val KEY_TAG = "recommendations_weight_tag"
    private const val KEY_OCOUNT = "recommendations_weight_ocount"
    private const val KEY_RATING = "recommendations_weight_rating"
    private const val KEY_SIMILAR = "recommendations_weight_similar"
    private const val KEY_DISCOVERY = "recommendations_discovery"
    /** Device-local, one entry per server: the last lists shown, newest first. */
    private const val LAST_PICKS_PREFIX = "recommendations_last_picks_"

    val lookbackChoices = listOf(7, 14, 30, 60, 90)
    val countRange = 5..10
    val weightRange = 0f..2f

    private const val FRESH_FOR_MS = 3 * 60 * 60 * 1000L
    private const val HISTORY_PAGE_SIZE = 100
    private const val HISTORY_MAX_PAGES = 4
    private const val CANDIDATES_PER_QUERY = 150
    private const val MIN_RARITY = 0.15
    private const val REMEMBERED_LISTS = 3

    /** New on every app start: candidate order and jitter change with it. */
    private val sessionSeed = (0 until 100_000_000).random()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // MARK: Settings

    private fun weight(key: String) = Prefs.float(key, 1f).takeIf { it in weightRange } ?: 1f

    private var stale = false

    var lookbackDays by mutableStateOf(Prefs.int(KEY_LOOKBACK, 30).takeIf { it in lookbackChoices } ?: 30); private set
    var count by mutableStateOf(Prefs.int(KEY_COUNT, 8).takeIf { it in countRange } ?: 8); private set
    var performerWeight by mutableStateOf(weight(KEY_PERFORMER)); private set
    var studioWeight by mutableStateOf(weight(KEY_STUDIO)); private set
    var tagWeight by mutableStateOf(weight(KEY_TAG)); private set
    var oCountWeight by mutableStateOf(weight(KEY_OCOUNT)); private set
    var ratingWeight by mutableStateOf(weight(KEY_RATING)); private set
    var similarWeight by mutableStateOf(weight(KEY_SIMILAR)); private set
    var discovery by mutableStateOf(RecommendationDiscovery.fromRaw(Prefs.string(KEY_DISCOVERY))); private set

    fun updateLookback(v: Int) { lookbackDays = v; Prefs.setInt(KEY_LOOKBACK, v); stale = true }
    fun updateCount(v: Int) { count = v.coerceIn(countRange); Prefs.setInt(KEY_COUNT, count); stale = true }
    fun updatePerformer(v: Float) { performerWeight = v; Prefs.setFloat(KEY_PERFORMER, v); stale = true }
    fun updateStudio(v: Float) { studioWeight = v; Prefs.setFloat(KEY_STUDIO, v); stale = true }
    fun updateTag(v: Float) { tagWeight = v; Prefs.setFloat(KEY_TAG, v); stale = true }
    fun updateOCount(v: Float) { oCountWeight = v; Prefs.setFloat(KEY_OCOUNT, v); stale = true }
    fun updateRating(v: Float) { ratingWeight = v; Prefs.setFloat(KEY_RATING, v); stale = true }
    fun updateSimilar(v: Float) { similarWeight = v; Prefs.setFloat(KEY_SIMILAR, v); stale = true }
    fun updateDiscovery(v: RecommendationDiscovery) { discovery = v; Prefs.setString(KEY_DISCOVERY, v.raw); stale = true }

    val hasCustomSettings: Boolean get() = lookbackDays != 30 || count != 8 || performerWeight != 1f || studioWeight != 1f ||
        tagWeight != 1f || oCountWeight != 1f || ratingWeight != 1f || similarWeight != 1f || discovery != RecommendationDiscovery.Balanced

    fun resetSettings() {
        updateLookback(30); updateCount(8); updatePerformer(1f); updateStudio(1f); updateTag(1f)
        updateOCount(1f); updateRating(1f); updateSimilar(1f); updateDiscovery(RecommendationDiscovery.Balanced)
    }

    // MARK: Output

    var recommendations by mutableStateOf<List<SceneRecommendation>>(emptyList()); private set
    var state by mutableStateOf(RecommendationState.Idle); private set
    var failure by mutableStateOf<String?>(null); private set
    var builtAt by mutableStateOf<Long?>(null); private set
    var seedCount by mutableStateOf(0); private set
    /** A visible rebuild is running (Settings shows it; the row keeps its cards meanwhile). */
    var isRefreshing by mutableStateOf(false); private set

    /** iOS `isFeatureOn`: part of Recommendations — on while Tag Suggestions or Similar Scenes is. */
    val isFeatureOn: Boolean get() = AITagSuggestions.isEnabled || SimilarScenes.isEnabled
    val isAvailable: Boolean get() = StashyPlus.isUnlocked && isFeatureOn

    private var job: Job? = null
    /** Builds the list for the next app start (or refresh) in the background. */
    private var prepareJob: Job? = null
    /** The next list, ready to show; mirrored to disk per server so a cold start shows it at once. */
    private var prepared: PreparedList? = null
    private var preparedLoadedFor: String? = null
    private var generation = 0
    private var builtForServer: String? = null
    private var totalSceneCount: Int? = null

    fun reset() {
        job?.cancel(); job = null
        prepareJob?.cancel(); prepareJob = null
        prepared = null; preparedLoadedFor = null
        isRefreshing = false
        generation++
        recommendations = emptyList(); builtAt = null; seedCount = 0
        state = RecommendationState.Idle; failure = null
        totalSceneCount = null
    }

    /** Builds when nothing is there, the list is older than three hours, a setting or the server changed. */
    fun refreshIfNeeded() {
        if (!isAvailable) return
        val server = ServerConfigManager.activeConfig?.id
        if (server != builtForServer) { reset(); builtForServer = server }
        if (job != null) return
        val at = builtAt
        if (!stale && at != null && System.currentTimeMillis() - at < FRESH_FOR_MS &&
            (state == RecommendationState.Ready || state == RecommendationState.NoHistory)) return
        rebuild()
    }

    /**
     * A new list now: the prepared one when it fits the current settings (instant), else a
     * visible build. Either way the next list is prepared right after.
     */
    fun rebuild() {
        if (!isAvailable || ServerConfigManager.activeConfig == null) return
        loadPreparedIfNeeded()
        val next = prepared
        if (!stale && next != null && next.settings == settingsSignature() && next.items.isNotEmpty() &&
            System.currentTimeMillis() - next.builtAt < PREPARED_MAX_AGE_MS) {
            show(next)
            return
        }
        buildVisible()
    }

    private fun show(list: PreparedList) {
        generation++
        job?.cancel(); job = null
        isRefreshing = false
        prepared = null
        savePrepared(null)
        recommendations = list.items
        seedCount = list.seedCount
        state = RecommendationState.Ready
        builtAt = System.currentTimeMillis()
        // Shown now: it steps back in the next picks.
        saveRecentPicks(list.items.map { it.id }, loadRecentPicks())
        prepareNext()
    }

    private fun buildVisible() {
        job?.cancel()
        prepareJob?.cancel(); prepareJob = null
        val gen = ++generation
        stale = false
        isRefreshing = true
        if (recommendations.isEmpty()) state = RecommendationState.Loading
        job = scope.launch {
            val outcome = try { build() } catch (e: CancellationException) { throw e } catch (e: Exception) { Result.failure(e) }
            if (gen != generation) return@launch
            outcome.onSuccess { (picks, seeds) ->
                recommendations = picks
                seedCount = seeds
                state = if (picks.isEmpty() && seeds == 0) RecommendationState.NoHistory else RecommendationState.Ready
                if (picks.isNotEmpty()) saveRecentPicks(picks.map { it.id }, loadRecentPicks())
            }.onFailure {
                if (recommendations.isEmpty()) { failure = "Could not read your watch history"; state = RecommendationState.Failed }
            }
            builtAt = System.currentTimeMillis()
            isRefreshing = false
            job = null
            prepareNext()
        }
    }

    /** Builds the following list in the background and keeps it (memory + disk). */
    private fun prepareNext() {
        if (!isAvailable) return
        prepareJob?.cancel()
        val gen = generation
        val signature = settingsSignature()
        prepareJob = scope.launch {
            val outcome = try { build() } catch (e: CancellationException) { throw e } catch (e: Exception) { Result.failure(e) }
            if (gen != generation || signature != settingsSignature()) return@launch
            outcome.onSuccess { (picks, seeds) ->
                if (picks.isNotEmpty()) {
                    val list = PreparedList(signature, System.currentTimeMillis(), seeds, picks)
                    prepared = list
                    savePrepared(list)
                }
            }
            prepareJob = null
        }
    }

    // MARK: Prepared list

    @kotlinx.serialization.Serializable
    data class PreparedList(val settings: String, val builtAt: Long, val seedCount: Int, val items: List<SceneRecommendation>)

    /** A prepared list older than this is not shown: scenes may have been played meanwhile. */
    private const val PREPARED_MAX_AGE_MS = 36 * 60 * 60 * 1000L

    /** Everything a list depends on besides the library itself. */
    private fun settingsSignature(): String = listOf(
        lookbackDays, count, discovery.raw, performerWeight, studioWeight, tagWeight, oCountWeight, ratingWeight, similarWeight,
    ).joinToString("|")

    private fun preparedFile(): java.io.File? = ServerConfigManager.activeConfig?.id?.let {
        java.io.File(java.io.File(Prefs.appContext.filesDir, "ForYou"), "$it.json")
    }

    private fun loadPreparedIfNeeded() {
        val server = ServerConfigManager.activeConfig?.id
        if (preparedLoadedFor == server) return
        preparedLoadedFor = server
        prepared = runCatching {
            preparedFile()?.takeIf { it.exists() }?.readText()?.let { de.letzgo.stashy.data.Json.decodeFromString(PreparedList.serializer(), it) }
        }.getOrNull()
    }

    private fun savePrepared(list: PreparedList?) {
        val file = preparedFile() ?: return
        scope.launch(Dispatchers.IO) {
            runCatching {
                if (list == null) { file.delete(); return@runCatching }
                file.parentFile?.mkdirs()
                file.writeText(de.letzgo.stashy.data.Json.encodeToString(PreparedList.serializer(), list))
            }
        }
    }

    // MARK: Build

    private class Seed(val scene: Scene, val weight: Double)

    private class HistoryRow(val scene: Scene, val plays: List<Instant>, val oStamps: List<Instant>, val hasOHistory: Boolean)

    private class Profile {
        var performers = HashMap<String, Double>()
        var studios = HashMap<String, Double>()
        var tags = HashMap<String, Double>()
        val isEmpty get() = performers.isEmpty() && studios.isEmpty() && tags.isEmpty()

        /** Performers / studios: strongest = 1. Tags: share of watch weight × rarity, not scaled up. */
        fun normalize(totalWeight: Double) {
            fun scaled(map: HashMap<String, Double>): HashMap<String, Double> {
                val top = map.values.maxOrNull() ?: return map
                return if (top > 0) HashMap(map.mapValues { it.value / top }) else map
            }
            performers = scaled(performers)
            studios = scaled(studios)
            if (totalWeight > 0) tags = HashMap(tags.mapValues { it.value / totalWeight })
        }

        fun top(map: Map<String, Double>, n: Int): List<String> =
            map.entries.sortedWith(compareByDescending<Map.Entry<String, Double>> { it.value }.thenBy { it.key }).take(n).map { it.key }
    }

    private suspend fun build(): Result<Pair<List<SceneRecommendation>, Int>> {
        val now = Instant.now()
        val windowStart = now.minusSeconds(lookbackDays * 86_400L)

        AITagSuggestions.loadIfNeeded()

        val history = fetchHistory(windowStart)
        var seeds = history.mapNotNull { seed(it, windowStart, now) }
        if (seeds.isEmpty()) seeds = fetchFavoriteSeeds()
        if (seeds.isEmpty()) return Result.success(emptyList<SceneRecommendation>() to 0)

        val totalScenes = loadTotalSceneCount()
        val profile = Profile()
        for (seed in seeds) {
            seed.scene.performers.forEach { profile.performers.merge(it.id, seed.weight, Double::plus) }
            seed.scene.studio?.let { profile.studios.merge(it.id, seed.weight, Double::plus) }
            seed.scene.tags.orEmpty().forEach { tag ->
                val r = rarity(tag, totalScenes)
                profile.tags.merge(tag.id, seed.weight * r * r, Double::plus)
            }
        }
        profile.normalize(seeds.sumOf { it.weight })
        if (profile.isEmpty) return Result.success(emptyList<SceneRecommendation>() to seeds.size)

        // Scenes played in the window are what the user just saw — never suggest them again.
        val recentlyPlayed = history.map { it.scene.id }.toSet()
        val topPerformers = profile.top(profile.performers, 8)
        val topStudios = profile.top(profile.studios, 4)
        val topTags = profile.top(profile.tags, 10)

        val seenAnchor = HashSet<String>()
        val anchors = seeds.sortedByDescending { it.weight }.filter { seenAnchor.add(it.scene.id) }.take(if (similarWeight > 0) 6 else 0)
        val maxSeedWeight = anchors.firstOrNull()?.weight ?: 1.0

        val (profilePool, anchorPool) = coroutineScope {
            val a = async {
                fetchCandidates(
                    if (performerWeight > 0) topPerformers else emptyList(),
                    if (studioWeight > 0) topStudios else emptyList(),
                    if (tagWeight > 0) topTags else emptyList(),
                    includeFavorites = discovery == RecommendationDiscovery.Favorites,
                )
            }
            val b = async { fetchUnwatchedSimilar(anchors.map { it.scene }, totalScenes) }
            a.await() to b.await()
        }
        val ids = HashSet<String>()
        val candidates = (profilePool + anchorPool).filter { ids.add(it.id) }

        val related = if (tagWeight > 0) AITagSuggestions.relatedTagWeights(topTags) else emptyMap()
        val scored = candidates.mapNotNull { c ->
            if (c.id in recentlyPlayed) null else score(c, profile, related, anchors, maxSeedWeight, totalScenes, now)
        }

        // What the recent lists showed steps back, so the next one is a new list.
        val recentLists = loadRecentPicks()
        val rotated = scored.map { item ->
            val index = recentLists.indexOfFirst { item.id in it }
            if (index < 0) item else item.copy(score = item.score * if (index == 0) 0.3 else 0.55)
        }
        val picks = diversify(rotated)
        return Result.success(picks to seeds.size)
    }

    /** Weight of one watched scene for the profile. */
    private fun seed(row: HistoryRow, windowStart: Instant, now: Instant): Seed? {
        val scene = row.scene
        var plays = row.plays.filter { it >= windowStart }
        if (plays.isEmpty()) {
            scene.lastPlayedAt?.let(OCountHeatmapBucketing::parseTimestamp)?.takeIf { it >= windowStart }?.let { plays = listOf(it) }
        }
        val os = row.oStamps.filter { it >= windowStart }
        val lastEvent = (plays + os).maxOrNull() ?: return null

        // Recency: half-life of a third of the window.
        val halfLife = max(2.0, lookbackDays / 3.0) * 86_400
        val age = max(0.0, (now.epochSecond - lastEvent.epochSecond).toDouble())
        val recency = 0.5.pow(age / halfLife)

        var engagement = 1.0
        engagement += 0.4 * min(max(plays.size - 1, 0), 5)
        val oCount = if (row.hasOHistory) os.size else if ((scene.oCounter ?: 0) > 0) 1 else 0
        engagement += 1.5 * oCountWeight * min(oCount, 4)
        val duration = scene.sceneDuration
        val watched = scene.playDuration
        if (duration != null && duration > 0 && watched != null && watched > 0) {
            val perPlay = watched / max(scene.playCount ?: plays.size, 1)
            engagement += 0.5 * min(1.0, perPlay / duration)
        }
        scene.rating100?.let { rating ->
            if (rating >= 80) engagement += 0.6 * ratingWeight
            else if (rating <= 40) engagement *= max(0.1, 1 - 0.7 * ratingWeight)
        }
        return Seed(scene, recency * engagement)
    }

    private fun score(
        candidate: Scene,
        profile: Profile,
        related: Map<String, Double>,
        anchors: List<Seed>,
        maxSeedWeight: Double,
        totalScenes: Int,
        now: Instant,
    ): SceneRecommendation? {
        val isUnwatched = (candidate.playCount ?: 0) == 0 && candidate.lastPlayedAt == null
        if (discovery == RecommendationDiscovery.Fresh && !isUnwatched) return null

        val performerHits = candidate.performers.mapNotNull { p -> profile.performers[p.id]?.let { p to it } }.sortedByDescending { it.second }
        var performerScore = performerHits.mapIndexed { i, h -> if (i == 0) h.second else h.second * 0.3 }.sum()
        performerScore *= 3.0 * performerWeight

        val studioScore = candidate.studio?.let { s -> profile.studios[s.id]?.let { it * 1.5 * studioWeight } } ?: 0.0

        val tags = candidate.tags.orEmpty()
        val tagHits = tags.mapNotNull { t -> profile.tags[t.id]?.let { t to it } }.sortedByDescending { it.second }
        val tagScore = min(tagHits.sumOf { it.second }, 1.2) * 2.0 * tagWeight

        var relatedScore = 0.0
        var bestRelated: Pair<Tag, Double>? = null
        if (related.isNotEmpty()) {
            for (tag in tags) {
                if (profile.tags.containsKey(tag.id)) continue
                val w = (related[tag.id] ?: continue) * rarity(tag, totalScenes)
                relatedScore += w
                if (w > (bestRelated?.second ?: 0.0)) bestRelated = tag to w
            }
            relatedScore = min(relatedScore, 1.0) * 0.6 * tagWeight
        }

        // Closeness to a single watched scene; every candidate here is unplayed in the window.
        var similarScore = 0.0
        var similarAnchor: Scene? = null
        if (similarWeight > 0) {
            for (anchor in anchors) {
                val value = similarity(candidate, anchor.scene, totalScenes) * (anchor.weight / max(maxSeedWeight, 0.0001))
                if (value > similarScore) { similarScore = value; similarAnchor = anchor.scene }
            }
            similarScore *= 3.0 * similarWeight
        }

        var score = performerScore + studioScore + tagScore + relatedScore + similarScore
        if (score <= 0) return null

        candidate.rating100?.let { score *= 1 + ratingWeight * (it - 60) / 200.0 }

        val oCounter = candidate.oCounter ?: 0
        val lastPlayed = candidate.lastPlayedAt?.let(OCountHeatmapBucketing::parseTimestamp)
        val daysSincePlay = lastPlayed?.let { (now.epochSecond - it.epochSecond) / 86_400.0 } ?: Double.POSITIVE_INFINITY
        var isRediscover = false
        when (discovery) {
            RecommendationDiscovery.Fresh -> score *= 1.2
            // Never played and not played in the window weigh the same.
            RecommendationDiscovery.Balanced -> if (!isUnwatched) isRediscover = oCounter > 0 && daysSincePlay > 60
            RecommendationDiscovery.Favorites -> if (isUnwatched) score *= 0.85 else {
                score *= 1 + 0.25 * oCountWeight * min(oCounter, 4)
                if ((candidate.rating100 ?: 0) >= 80) score *= 1 + 0.2 * ratingWeight
                isRediscover = daysSincePlay > 60
            }
        }

        // Launch-seeded jitter: close scores resolve differently on each app start.
        score *= 1 + 0.35 * jitter(candidate.id)

        val factors = listOf(
            performerScore to performerHits.firstOrNull()?.let { RecommendationReason.Performer(it.first.name) },
            studioScore to candidate.studio?.let { RecommendationReason.Studio(it.name) },
            tagScore to tagHits.firstOrNull()?.let { RecommendationReason.Tag(it.first.name) },
            relatedScore to bestRelated?.let { RecommendationReason.RelatedTag(it.first.name) },
            similarScore to similarAnchor?.let { RecommendationReason.SimilarTo(it.displayTitle) },
        )
        val strongest = factors.filter { it.second != null && it.first > 0 }.maxByOrNull { it.first }?.second
        val reason = when {
            isRediscover -> if (discovery == RecommendationDiscovery.Favorites && oCounter > 0) RecommendationReason.Favorite else RecommendationReason.Rediscover
            strongest != null -> strongest
            else -> return null
        }
        return SceneRecommendation(candidate, reason, isUnwatched, score)
    }

    /** Greedy pick; repeating a performer, studio or reason costs ground. */
    private fun diversify(scored: List<SceneRecommendation>): List<SceneRecommendation> {
        val pool = scored.toMutableList()
        val picks = mutableListOf<SceneRecommendation>()
        val performerUses = HashMap<String, Int>()
        val studioUses = HashMap<String, Int>()
        val reasonUses = HashMap<String, Int>()
        fun adjusted(item: SceneRecommendation): Double {
            val pp = item.scene.performers.maxOfOrNull { performerUses[it.id] ?: 0 } ?: 0
            val sp = item.scene.studio?.let { studioUses[it.id] ?: 0 } ?: 0
            val rp = reasonUses[item.reason.label] ?: 0
            return item.score * 0.6.pow(pp) * 0.75.pow(sp) * 0.7.pow(rp)
        }
        while (picks.size < count && pool.isNotEmpty()) {
            var best = 0
            var bestScore = Double.NEGATIVE_INFINITY
            pool.forEachIndexed { i, item ->
                val v = adjusted(item)
                if (v > bestScore || (v == bestScore && item.id < pool[best].id)) { bestScore = v; best = i }
            }
            val pick = pool.removeAt(best)
            picks += pick
            pick.scene.performers.forEach { performerUses.merge(it.id, 1, Int::plus) }
            pick.scene.studio?.let { studioUses.merge(it.id, 1, Int::plus) }
            reasonUses.merge(pick.reason.label, 1, Int::plus)
        }
        return picks
    }

    // MARK: Helpers

    /** 0…1: shared performers (50 %), shared rare tags (35 %), same studio (15 %). */
    private fun similarity(candidate: Scene, anchor: Scene, totalScenes: Int): Double {
        val anchorPerformers = anchor.performers.map { it.id }.toSet()
        val shared = candidate.performers.count { it.id in anchorPerformers }
        val performerPart = if (anchorPerformers.isEmpty()) 0.0 else min(shared, 2) / 2.0
        val anchorTags = anchor.tags.orEmpty()
        val candidateTags = candidate.tags.orEmpty().map { it.id }.toSet()
        val mass = anchorTags.sumOf { rarity(it, totalScenes) }
        val sharedMass = anchorTags.filter { it.id in candidateTags }.sumOf { rarity(it, totalScenes) }
        val tagPart = if (mass > 0) sharedMass / mass else 0.0
        val studioPart = if (anchor.studio?.id != null && anchor.studio.id == candidate.studio?.id) 1.0 else 0.0
        return 0.5 * performerPart + 0.35 * tagPart + 0.15 * studioPart
    }

    private fun rarity(tag: Tag, totalScenes: Int): Double {
        val df = max(1, tag.sceneCount ?: 1)
        if (totalScenes <= 1 || df >= totalScenes) return MIN_RARITY
        val idf = ln(totalScenes.toDouble() / df) / ln(totalScenes.toDouble())
        return min(1.0, max(MIN_RARITY, idf))
    }

    /** 0…1, stable for a scene within one app run. */
    private fun jitter(id: String): Double {
        var hash = -0x340d631b7bdddcdbL xor sessionSeed.toLong()
        for (b in id.toByteArray()) { hash = hash xor (b.toLong() and 0xff); hash *= 0x100000001b3L }
        return java.lang.Long.remainderUnsigned(hash, 10_000L) / 10_000.0
    }

    private val lastPicksKey: String? get() = ServerConfigManager.activeConfig?.id?.let { "$LAST_PICKS_PREFIX$it" }

    private fun loadRecentPicks(): List<Set<String>> {
        val raw = lastPicksKey?.let(Prefs::string) ?: return emptyList()
        return runCatching {
            (de.letzgo.stashy.data.Json.parseToJsonElement(raw) as JsonArray).map { list ->
                (list as JsonArray).mapNotNull { it.stringOrNull }.toSet()
            }
        }.getOrDefault(emptyList())
    }

    private fun saveRecentPicks(ids: List<String>, previous: List<Set<String>>) {
        val key = lastPicksKey ?: return
        if (ids.isEmpty()) return
        val lists = listOf(ids) + previous.take(REMEMBERED_LISTS - 1).map { it.toList() }
        Prefs.setString(key, de.letzgo.stashy.data.Json.encodeToString(ListSerializer(ListSerializer(String.serializer())), lists))
    }

    private suspend fun loadTotalSceneCount(): Int {
        totalSceneCount?.let { return it }
        val count = try {
            GraphQL.data("{ stats { scene_count } }")["stats"].obj?.get("scene_count").stringOrNull?.toIntOrNull() ?: 0
        } catch (e: CancellationException) { throw e } catch (e: Exception) { 0 }
        if (count > 0) totalSceneCount = count
        return count
    }

    // MARK: Queries

    private fun decodeHistory(element: JsonObject): HistoryRow? {
        val scene = runCatching { GraphQL.decode(Scene.serializer(), element) }.getOrNull() ?: return null
        val plays = (element["play_history"] as? JsonArray)?.mapNotNull { OCountHeatmapBucketing.flexibleTime(it) }.orEmpty()
        val oArray = element["o_history"] as? JsonArray
        val os = oArray?.mapNotNull { OCountHeatmapBucketing.flexibleTime(it) }.orEmpty()
        return HistoryRow(scene, plays, os, oArray != null)
    }

    private suspend fun fetchHistory(start: Instant): List<HistoryRow> {
        val filter = mapOf("last_played_at" to mapOf("modifier" to "GREATER_THAN", "value" to DateTimeFormatter.ISO_INSTANT.format(start.truncatedTo(java.time.temporal.ChronoUnit.SECONDS))))
        return try {
            pagedHistory("findScenesRecommendHistory", filter)
        } catch (e: CancellationException) { throw e } catch (e: Exception) {
            // Older servers without play_history / o_history.
            pagedHistory("findScenesRecommendCandidates", filter)
        }
    }

    private suspend fun pagedHistory(query: String, sceneFilter: Map<String, Any>): List<HistoryRow> {
        val rows = mutableListOf<HistoryRow>()
        for (page in 1..HISTORY_MAX_PAGES) {
            val data = GraphQL.named(query, vars(
                "filter" to mapOf("page" to page, "per_page" to HISTORY_PAGE_SIZE, "sort" to "last_played_at", "direction" to "DESC"),
                "scene_filter" to sceneFilter,
            ))
            val block = data["findScenes"].obj ?: break
            val scenes = (block["scenes"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::decodeHistory) }
            rows += scenes
            val total = block["count"].stringOrNull?.toIntOrNull() ?: 0
            if (scenes.size < HISTORY_PAGE_SIZE || rows.size >= total) break
        }
        return rows
    }

    /** Cold start: scenes with O-Counts or high ratings, weighted lower than real plays. */
    private suspend fun fetchFavoriteSeeds(): List<Seed> = coroutineScope {
        val byO = async { runCandidateQuery(mapOf("o_counter" to mapOf("value" to 0, "modifier" to "GREATER_THAN")), "o_counter", 60) }
        val byRating = async { runCandidateQuery(mapOf("rating100" to mapOf("value" to 79, "modifier" to "GREATER_THAN")), "rating", 60) }
        val seen = HashSet<String>()
        (byO.await() + byRating.await()).filter { seen.add(it.id) }.map { scene ->
            var w = 0.5 + 0.3 * oCountWeight * min(scene.oCounter ?: 0, 4)
            if ((scene.rating100 ?: 0) >= 80) w += 0.4 * ratingWeight
            Seed(scene, w)
        }
    }

    private suspend fun fetchCandidates(performerIds: List<String>, studioIds: List<String>, tagIds: List<String>, includeFavorites: Boolean): List<Scene> {
        val sort = "random_$sessionSeed"
        val clauses = buildList<Map<String, Any>> {
            // Performers are not hierarchical: Stash rejects `depth` there.
            if (performerIds.isNotEmpty()) add(mapOf("performers" to mapOf("value" to performerIds, "modifier" to "INCLUDES")))
            if (studioIds.isNotEmpty()) add(mapOf("studios" to mapOf("value" to studioIds, "modifier" to "INCLUDES", "depth" to 0)))
            if (tagIds.isNotEmpty()) add(mapOf("tags" to mapOf("value" to tagIds, "modifier" to "INCLUDES", "depth" to 0)))
            if (includeFavorites) add(mapOf("o_counter" to mapOf("value" to 0, "modifier" to "GREATER_THAN")))
        }
        if (clauses.isEmpty()) return emptyList()
        val results = coroutineScope { clauses.map { async { runCandidateQuery(it, sort, CANDIDATES_PER_QUERY) } }.awaitAll() }
        val seen = HashSet<String>()
        return results.flatten().filter { seen.add(it.id) }
    }

    /** Unplayed scenes per anchor: its performers, and its three rarest tags together. */
    private suspend fun fetchUnwatchedSimilar(anchors: List<Scene>, totalScenes: Int): List<Scene> {
        if (anchors.isEmpty()) return emptyList()
        // New only asks the server for unplayed scenes; the other modes take any and drop the
        // ones played in the window afterwards.
        val onlyUnplayed = discovery == RecommendationDiscovery.Fresh
        fun scoped(filter: Map<String, Any>): Map<String, Any> =
            if (onlyUnplayed) filter + ("play_count" to mapOf("value" to 0, "modifier" to "EQUALS")) else filter
        val filters = buildList<Map<String, Any>> {
            for (anchor in anchors) {
                val performerIds = anchor.performers.map { it.id }
                if (performerIds.isNotEmpty()) add(scoped(mapOf("performers" to mapOf("value" to performerIds, "modifier" to "INCLUDES"))))
                val rare = anchor.tags.orEmpty().sortedByDescending { rarity(it, totalScenes) }.take(3).map { it.id }
                if (rare.size >= 2) add(scoped(mapOf("tags" to mapOf("value" to rare, "modifier" to "INCLUDES_ALL", "depth" to 0))))
            }
        }
        val sort = "random_$sessionSeed"
        val results = coroutineScope { filters.map { async { runCandidateQuery(it, sort, 40) } }.awaitAll() }
        val seen = HashSet<String>()
        return results.flatten().filter { seen.add(it.id) }
    }

    private suspend fun runCandidateQuery(filter: Map<String, Any>, sort: String, perPage: Int): List<Scene> = try {
        val data = GraphQL.named("findScenesRecommendCandidates", vars(
            "filter" to mapOf("page" to 1, "per_page" to perPage, "sort" to sort, "direction" to "DESC"),
            "scene_filter" to filter,
        ))
        data["findScenes"].obj?.get("scenes")?.let { GraphQL.decode(ListSerializer(Scene.serializer()), it) }.orEmpty()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        emptyList()
    }
}
