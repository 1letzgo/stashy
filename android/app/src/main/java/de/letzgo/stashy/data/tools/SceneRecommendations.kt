package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEvent
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
 * iOS `RecommendationAdjustment`: one performer, studio or tag turned up, down or off for For You
 * (Settings › For You › Adjustments, or the ··· menu below a For You card). Per server, same JSON.
 */
@kotlinx.serialization.Serializable
data class RecommendationAdjustment(val kind: Kind, val itemId: String, val name: String, val factor: Double) {
    @kotlinx.serialization.Serializable
    enum class Kind(val title: String) {
        @kotlinx.serialization.SerialName("performer") Performer("Performers"),
        @kotlinx.serialization.SerialName("studio") Studio("Studios"),
        @kotlinx.serialization.SerialName("tag") Tag("Tags"),
    }

    val id: String get() = "${kind.name.lowercase()}:$itemId"
    val isHidden: Boolean get() = factor < HIDDEN_BELOW

    companion object {
        val RANGE = 0.0..3.0
        const val HIDDEN_BELOW = 0.05
        const val LESS = 0.5
        const val MORE = 2.0
        fun label(factor: Double): String = if (factor < HIDDEN_BELOW) "Hidden" else String.format(java.util.Locale.US, "%.1f×", factor)
    }
}

/** iOS `SceneRecommendationEngine.Adjust`: the adjustments as lookups for one build. */
internal class RecommendationAdjust(list: List<RecommendationAdjustment>) {
    private val performers = HashMap<String, Double>()
    private val studios = HashMap<String, Double>()
    private val tags = HashMap<String, Double>()

    init {
        list.forEach {
            when (it.kind) {
                RecommendationAdjustment.Kind.Performer -> performers[it.itemId] = it.factor
                RecommendationAdjustment.Kind.Studio -> studios[it.itemId] = it.factor
                RecommendationAdjustment.Kind.Tag -> tags[it.itemId] = it.factor
            }
        }
    }

    val isEmpty get() = performers.isEmpty() && studios.isEmpty() && tags.isEmpty()
    fun hidesPerformer(id: String) = (performers[id] ?: 1.0) < RecommendationAdjustment.HIDDEN_BELOW
    fun hidesStudio(id: String) = (studios[id] ?: 1.0) < RecommendationAdjustment.HIDDEN_BELOW
    fun hidesTag(id: String) = (tags[id] ?: 1.0) < RecommendationAdjustment.HIDDEN_BELOW

    fun hides(performerIds: List<String>, studioId: String?, tagIds: List<String>): Boolean {
        if (isEmpty) return false
        return performerIds.any(::hidesPerformer) || (studioId != null && hidesStudio(studioId)) || tagIds.any(::hidesTag)
    }

    fun hides(scene: Scene) = hides(scene.performers.map { it.id }, scene.studio?.id, scene.tags.orEmpty().map { it.id })

    /** Every adjusted item on the scene multiplies its score. */
    fun multiplier(performerIds: List<String>, studioId: String?, tagIds: List<String>): Double {
        if (isEmpty) return 1.0
        var value = 1.0
        performerIds.forEach { value *= performers[it] ?: 1.0 }
        studioId?.let { value *= studios[it] ?: 1.0 }
        tagIds.forEach { value *= tags[it] ?: 1.0 }
        return value.coerceIn(0.05, 8.0)
    }

    /** Turned up: in the profile even without plays (3× counts like the favourite performer). */
    fun boost(profilePerformers: HashMap<String, Double>, profileStudios: HashMap<String, Double>, profileTags: HashMap<String, Double>) {
        performers.forEach { (id, f) -> if (f > 1) profilePerformers[id] = max(profilePerformers[id] ?: 0.0, min(1.0, (f - 1) / 2)) }
        studios.forEach { (id, f) -> if (f > 1) profileStudios[id] = max(profileStudios[id] ?: 0.0, min(1.0, (f - 1) / 2)) }
        tags.forEach { (id, f) -> if (f > 1) profileTags[id] = max(profileTags[id] ?: 0.0, 0.25 * min(1.0, (f - 1) / 2)) }
    }
}

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
    private const val KEY_ENABLED = "recommendations_enabled"
    /** Device-local, one entry per server: the last lists shown, newest first. */
    private const val LAST_PICKS_PREFIX = "recommendations_last_picks_"

    val lookbackChoices = listOf(7, 14, 30, 60, 90)
    val countRange = 5..10
    /** The For You sort of the Scenes list shows this many; Home shows the first [count]. */
    const val LIST_LIMIT = 25
    val weightRange = 0f..2f

    private const val HISTORY_PAGE_SIZE = 100
    private const val HISTORY_MAX_PAGES = 4
    private const val CANDIDATES_PER_QUERY = 150
    private const val MIN_RARITY = 0.15
    private const val REMEMBERED_LISTS = 3

    /** New for every build: candidate order and jitter change with it, so each list differs. */
    private var sessionSeed = (0 until 100_000_000).random()

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

    // MARK: Adjustments

    private const val ADJUSTMENTS_PREFIX = "recommendations_adjustments_"
    private val adjustmentsKey: String? get() = ServerConfigManager.activeConfig?.id?.let { "$ADJUSTMENTS_PREFIX$it" }
    private val adjustmentsSerializer = ListSerializer(RecommendationAdjustment.serializer())

    /** The user's per-item adjustments for the active server. */
    var adjustments by mutableStateOf(loadAdjustments()); private set

    private fun loadAdjustments(): List<RecommendationAdjustment> {
        val raw = adjustmentsKey?.let(Prefs::string) ?: return emptyList()
        return runCatching { de.letzgo.stashy.data.Json.decodeFromString(adjustmentsSerializer, raw) }.getOrDefault(emptyList())
    }

    private fun saveAdjustments(list: List<RecommendationAdjustment>) {
        adjustments = list
        stale = true
        prepared = null
        val key = adjustmentsKey ?: return
        Prefs.setString(key, if (list.isEmpty()) null else de.letzgo.stashy.data.Json.encodeToString(adjustmentsSerializer, list))
    }

    fun adjustment(kind: RecommendationAdjustment.Kind, itemId: String) = adjustments.firstOrNull { it.kind == kind && it.itemId == itemId }

    /** Adds or changes one; a new one goes to the top. */
    fun setAdjustment(kind: RecommendationAdjustment.Kind, itemId: String, name: String, factor: Double) {
        val value = factor.coerceIn(RecommendationAdjustment.RANGE)
        val existing = adjustments.indexOfFirst { it.kind == kind && it.itemId == itemId }
        val entry = RecommendationAdjustment(kind, itemId, name, value)
        if (existing >= 0) {
            if (adjustments[existing] == entry) return
            saveAdjustments(adjustments.toMutableList().also { it[existing] = entry })
        } else {
            saveAdjustments(listOf(entry) + adjustments)
        }
    }

    fun removeAdjustment(kind: RecommendationAdjustment.Kind, itemId: String) {
        if (adjustments.none { it.kind == kind && it.itemId == itemId }) return
        saveAdjustments(adjustments.filterNot { it.kind == kind && it.itemId == itemId })
    }

    fun removeAllAdjustments() { if (adjustments.isNotEmpty()) saveAdjustments(emptyList()) }

    /** From a card's menu: a hidden item takes its cards off the row at once, then a new list is built. */
    fun applyAdjustmentsNow() {
        val adjust = RecommendationAdjust(adjustments)
        val kept = recommendations.filterNot { adjust.hides(it.scene) }
        if (kept.size != recommendations.size) recommendations = kept
        rebuild()
    }

    // MARK: Output

    var recommendations by mutableStateOf<List<SceneRecommendation>>(emptyList()); private set
    var state by mutableStateOf(RecommendationState.Idle); private set
    var failure by mutableStateOf<String?>(null); private set
    var builtAt by mutableStateOf<Long?>(null); private set
    var seedCount by mutableStateOf(0); private set
    /** A visible rebuild is running (Settings shows it; the row keeps its cards meanwhile). */
    var isRefreshing by mutableStateOf(false); private set

    /** The user's own switch for the row (Settings › Recommendations). On by default. */
    var isEnabled by mutableStateOf(Prefs.bool(KEY_ENABLED, true)); private set
    fun updateEnabled(v: Boolean) { isEnabled = v; Prefs.setBool(KEY_ENABLED, v); if (!v) reset() }
    /** Tag Suggestions or Similar Scenes is on: the statistics the row draws on are there. */
    val hasStatistics: Boolean get() = AITagSuggestions.isEnabled || SimilarScenes.isEnabled
    /** iOS `isFeatureOn`: the user's switch is on and so is Tag Suggestions or Similar Scenes. */
    val isFeatureOn: Boolean get() = isEnabled && hasStatistics
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

    /**
     * A scene changed elsewhere (progress, play, O count, rating, metadata, cover, delete): the
     * cards already shown take it in place — no rebuild, no reshuffle; a deleted scene leaves.
     */
    fun applySceneEvent(event: SceneEvent) {
        // The prepared next list drops a deleted scene too (in memory; the file is rewritten with the next list).
        if (event is SceneEvent.Deleted) prepared = prepared?.let { p -> p.copy(items = p.items.filter { it.id != event.sceneId }) }
        if (recommendations.none { it.id == event.sceneId }) return
        recommendations = recommendations.mapNotNull { item ->
            if (item.id != event.sceneId) item else event.applyTo(item.scene)?.let { item.copy(scene = it) }
        }
    }

    fun reset() {
        job?.cancel(); job = null
        prepareJob?.cancel(); prepareJob = null
        prepared = null; preparedLoadedFor = null
        isRefreshing = false
        generation++
        recommendations = emptyList(); builtAt = null; seedCount = 0
        state = RecommendationState.Idle; failure = null
        totalSceneCount = null
        // A new server has its own ids, so its own adjustments.
        adjustments = loadAdjustments()
    }

    /** Builds when nothing is there, the list is older than three hours, a setting or the server changed. */
    fun refreshIfNeeded() {
        if (!isAvailable) return
        val server = ServerConfigManager.activeConfig?.id
        if (server != builtForServer) { reset(); builtForServer = server }
        if (job != null) return
        // Within a session the list stays: a new one comes at app start, on pull to refresh or Refresh.
        if (state == RecommendationState.Ready || state == RecommendationState.NoHistory) return
        rebuild()
    }

    /**
     * A new list now: the prepared one when it fits the current settings (instant), else a
     * visible build. Either way the next list is prepared right after.
     */
    /** What Home shows: the first [count] of the list. */
    val homeItems: List<SceneRecommendation> get() = recommendations.take(count)

    /** The For You sort of the Scenes list: the current list (up to [LIST_LIMIT]), built first when there is none. */
    suspend fun scenesForList(): List<Scene> {
        if (recommendations.isEmpty()) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { rebuild() }
            job?.join()
        }
        return recommendations.map { it.scene }
    }

    /** iOS `rebuildAndWait`: a new list, returning once it is shown (pull to refresh). */
    suspend fun rebuildAndWait() {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) { rebuild() }
        job?.join()
    }

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
        saveRecentPicks(list.items.take(count).map { it.id }, loadRecentPicks())
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
                if (picks.isNotEmpty()) saveRecentPicks(picks.take(count).map { it.id }, loadRecentPicks())
            }.onFailure {
                if (recommendations.isEmpty()) { failure = it.message ?: "Could not build your list"; state = RecommendationState.Failed }
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
    ).joinToString("|") + "|" + adjustments.map { "${it.id}=${it.factor}" }.sorted().joinToString(",")

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

    /** iOS `RecItem`: what scoring needs of one scene — from the local index or a server scene. */
    private class RecItem(
        val id: String,
        val title: String?,
        val performers: List<Pair<String, String>>,
        val studio: Pair<String, String>?,
        val tagIds: List<String>,
        val playCount: Int,
        val oCounter: Int,
        val rating: Int?,
        val lastPlayedAt: Instant?,
        val playDuration: Double?,
        val duration: Double?,
    ) {
        val isUnwatched get() = playCount == 0 && lastPlayedAt == null

        companion object {
            fun of(e: de.letzgo.stashy.data.tools.LocalSceneIndex.Entry, index: de.letzgo.stashy.data.tools.LocalSceneIndex) = RecItem(
                e.id, e.title,
                e.p.map { it to (index.performerNames[it] ?: "this performer") },
                e.s?.let { it to (index.studioNames[it] ?: "this studio") },
                e.t, e.pc, e.oc, e.r, e.lp?.let(Instant::ofEpochMilli), e.pd, e.d,
            )
        }
    }

    /** Tag names and how many scenes carry each tag, for labels and the rarity weighting. */
    private class Vocabulary {
        val tagNames = HashMap<String, String>()
        val tagScenes = HashMap<String, Int>()
        var totalScenes = 0

        fun rarity(tagId: String): Double {
            val df = max(1, tagScenes[tagId] ?: 1)
            if (totalScenes <= 1 || df >= totalScenes) return MIN_RARITY
            val idf = ln(totalScenes.toDouble() / df) / ln(totalScenes.toDouble())
            return min(1.0, max(MIN_RARITY, idf))
        }
    }

    private class Seed(val item: RecItem, val weight: Double)

    private class Scored(val item: RecItem, val reason: RecommendationReason, val score: Double)

    private class Anchor(val item: RecItem, val weight: Double, val performerIds: Set<String>, val tagMass: Map<String, Double>, val totalMass: Double)

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
        sessionSeed = (0 until 100_000_000).random()
        // Everything comes from the Suggestions statistics on this device: the scene index for
        // the candidates and their cards, the tag pairs for the related-tag bonus.
        AITagSuggestions.loadIfNeeded()
        val index = AITagSuggestions.sceneIndex()?.takeIf { it.scenes.isNotEmpty() }
            ?: return Result.failure(IllegalStateException(PREPARING_MESSAGE))
        return buildLocal(index)
    }

    /** Shown until the first statistics build on this device is done. */
    const val PREPARING_MESSAGE = "Getting your library ready on this device…"

    /** A finished statistics build: the next list reads the new index; a row still waiting gets its list now. */
    fun onSceneIndexChanged() {
        stale = true
        prepared = null
        if (recommendations.isEmpty()) rebuild()
    }

    /** iOS `buildLocal`: the whole library from the device's scene index — no server request. */
    private fun buildLocal(index: de.letzgo.stashy.data.tools.LocalSceneIndex): Result<Pair<List<SceneRecommendation>, Int>> {
        val now = Instant.now()
        val windowStart = now.minusSeconds(lookbackDays * 86_400L)
        val entries = index.scenes.filter { it.scene != null }
        val items = entries.map { RecItem.of(it, index) }
        val vocabulary = Vocabulary()
        vocabulary.tagNames.putAll(index.tagNames)
        vocabulary.totalScenes = items.size
        items.forEach { item -> item.tagIds.forEach { vocabulary.tagScenes.merge(it, 1, Int::plus) } }

        var seeds = items.mapNotNull { item ->
            val last = item.lastPlayedAt?.takeIf { it >= windowStart } ?: return@mapNotNull null
            seed(item, listOf(last), null, windowStart, now)
        }
        if (seeds.isEmpty()) seeds = favoriteSeeds(items)
        if (seeds.isEmpty()) return Result.success(emptyList<SceneRecommendation>() to 0)
        val recentlyPlayed = items.filter { (it.lastPlayedAt ?: Instant.EPOCH) >= windowStart }.map { it.id }.toSet()

        val picks = rank(items, seeds, recentlyPlayed, vocabulary, RecommendationAdjust(adjustments), now)
        val scenes = entries.associate { it.id to it.scene!! }
        val recommendations = picks.mapNotNull { pick ->
            scenes[pick.item.id]?.let { SceneRecommendation(it, pick.reason, pick.item.isUnwatched, pick.score) }
        }
        return Result.success(recommendations to seeds.size)
    }

    private fun makeProfile(seeds: List<Seed>, vocabulary: Vocabulary, adjust: RecommendationAdjust): Profile {
        val profile = Profile()
        for (seed in seeds) {
            // A hidden item learns nothing from the history; the rest of its scene still counts.
            seed.item.performers.forEach { if (!adjust.hidesPerformer(it.first)) profile.performers.merge(it.first, seed.weight, Double::plus) }
            seed.item.studio?.let { if (!adjust.hidesStudio(it.first)) profile.studios.merge(it.first, seed.weight, Double::plus) }
            seed.item.tagIds.forEach { tagId ->
                if (adjust.hidesTag(tagId)) return@forEach
                val r = vocabulary.rarity(tagId)
                profile.tags.merge(tagId, seed.weight * r * r, Double::plus)
            }
        }
        profile.normalize(seeds.sumOf { it.weight })
        adjust.boost(profile.performers, profile.studios, profile.tags)
        return profile
    }

    private fun RecommendationAdjust.hides(item: RecItem) = hides(item.performers.map { it.first }, item.studio?.first, item.tagIds)
    private fun RecommendationAdjust.multiplier(item: RecItem) = multiplier(item.performers.map { it.first }, item.studio?.first, item.tagIds)

    /** Scores every candidate, steps back what the last lists showed and picks a diverse list. */
    private fun rank(candidates: List<RecItem>, seeds: List<Seed>, recentlyPlayed: Set<String>, vocabulary: Vocabulary,
                     adjust: RecommendationAdjust, now: Instant): List<Scored> {
        val profile = makeProfile(seeds, vocabulary, adjust)
        if (profile.isEmpty) return emptyList()
        val topTags = profile.top(profile.tags, 10)
        val seenAnchor = HashSet<String>()
        val anchors = seeds.sortedByDescending { it.weight }.filter { !adjust.hides(it.item) && seenAnchor.add(it.item.id) }
            .take(if (similarWeight > 0) 6 else 0)
            .map { s ->
                val mass = s.item.tagIds.associateWith { vocabulary.rarity(it) }
                Anchor(s.item, s.weight, s.item.performers.map { it.first }.toSet(), mass, mass.values.sum())
            }
        val maxSeedWeight = anchors.firstOrNull()?.weight ?: 1.0
        val related = if (tagWeight > 0) AITagSuggestions.relatedTagWeights(topTags) else emptyMap()
        val scored = candidates.mapNotNull { c ->
            if (c.id in recentlyPlayed || adjust.hides(c)) return@mapNotNull null
            val scored = score(c, profile, related, anchors, maxSeedWeight, vocabulary, now) ?: return@mapNotNull null
            val factor = adjust.multiplier(c)
            if (factor == 1.0) scored else Scored(scored.item, scored.reason, scored.score * factor)
        }
        // What the recent lists showed steps back, so the next one is a new list.
        val recentLists = loadRecentPicks()
        val rotated = scored.map { item ->
            val i = recentLists.indexOfFirst { item.item.id in it }
            if (i < 0) item else Scored(item.item, item.reason, item.score * if (i == 0) 0.3 else 0.55)
        }
        return diversify(rotated)
    }

    /** Weight of one watched scene for the profile. Without play stamps (local index) the play count stands in. */
    private fun seed(item: RecItem, allPlays: List<Instant>, oStamps: List<Instant>?, windowStart: Instant, now: Instant): Seed? {
        var plays = allPlays.filter { it >= windowStart }
        if (plays.isEmpty()) item.lastPlayedAt?.takeIf { it >= windowStart }?.let { plays = listOf(it) }
        val os = oStamps.orEmpty().filter { it >= windowStart }
        val lastEvent = (plays + os).maxOrNull() ?: return null

        // Recency: half-life of a third of the window.
        val halfLife = max(2.0, lookbackDays / 3.0) * 86_400
        val age = max(0.0, (now.epochSecond - lastEvent.epochSecond).toDouble())
        val recency = 0.5.pow(age / halfLife)

        var engagement = 1.0
        val replays = if (oStamps == null && plays.size <= 1) min(item.playCount - 1, 3) else plays.size - 1
        engagement += 0.4 * min(max(replays, 0), 5)
        val oCount = if (oStamps != null) os.size else if (item.oCounter > 0) 1 else 0
        engagement += 1.5 * oCountWeight * min(oCount, 4)
        val duration = item.duration
        val watched = item.playDuration
        if (duration != null && duration > 0 && watched != null && watched > 0) {
            val perPlay = watched / maxOf(item.playCount, plays.size, 1)
            engagement += 0.5 * min(1.0, perPlay / duration)
        }
        item.rating?.let { rating ->
            if (rating >= 80) engagement += 0.6 * ratingWeight
            else if (rating <= 40) engagement *= max(0.1, 1 - 0.7 * ratingWeight)
        }
        return Seed(item, recency * engagement)
    }

    /** Cold start: scenes with O-Counts or high ratings, weighted lower than real plays. */
    private fun favoriteSeeds(items: List<RecItem>): List<Seed> = items
        .filter { it.oCounter > 0 || (it.rating ?: 0) >= 80 }
        .map { item ->
            var w = 0.5 + 0.3 * oCountWeight * min(item.oCounter, 4)
            if ((item.rating ?: 0) >= 80) w += 0.4 * ratingWeight
            Seed(item, w)
        }
        .sortedByDescending { it.weight }
        .take(120)

    private fun score(
        candidate: RecItem,
        profile: Profile,
        related: Map<String, Double>,
        anchors: List<Anchor>,
        maxSeedWeight: Double,
        vocabulary: Vocabulary,
        now: Instant,
    ): Scored? {
        val isUnwatched = candidate.isUnwatched
        if (discovery == RecommendationDiscovery.Fresh && !isUnwatched) return null

        val performerHits = candidate.performers.mapNotNull { p -> profile.performers[p.first]?.let { p to it } }.sortedByDescending { it.second }
        var performerScore = performerHits.mapIndexed { i, h -> if (i == 0) h.second else h.second * 0.3 }.sum()
        performerScore *= 3.0 * performerWeight

        val studioScore = candidate.studio?.let { s -> profile.studios[s.first]?.let { it * 1.5 * studioWeight } } ?: 0.0

        val tagHits = candidate.tagIds.mapNotNull { t -> profile.tags[t]?.let { t to it } }.sortedByDescending { it.second }
        val tagScore = min(tagHits.sumOf { it.second }, 1.2) * 2.0 * tagWeight

        var relatedScore = 0.0
        var bestRelated: Pair<String, Double>? = null
        if (related.isNotEmpty()) {
            for (tagId in candidate.tagIds) {
                if (profile.tags.containsKey(tagId)) continue
                val w = (related[tagId] ?: continue) * vocabulary.rarity(tagId)
                relatedScore += w
                if (w > (bestRelated?.second ?: 0.0)) bestRelated = tagId to w
            }
            relatedScore = min(relatedScore, 1.0) * 0.6 * tagWeight
        }

        // Closeness to a single watched scene, scaled by how much that scene counted.
        var similarScore = 0.0
        var similarAnchor: RecItem? = null
        if (similarWeight > 0 && anchors.isNotEmpty()) {
            val candidatePerformers = candidate.performers.map { it.first }
            for (anchor in anchors) {
                if (anchor.item.id == candidate.id) continue
                val shared = candidatePerformers.count { it in anchor.performerIds }
                val performerPart = if (anchor.performerIds.isEmpty()) 0.0 else min(shared, 2) / 2.0
                val sharedMass = candidate.tagIds.sumOf { anchor.tagMass[it] ?: 0.0 }
                val tagPart = if (anchor.totalMass > 0) sharedMass / anchor.totalMass else 0.0
                val studioPart = if (anchor.item.studio?.first != null && anchor.item.studio.first == candidate.studio?.first) 1.0 else 0.0
                val value = (0.5 * performerPart + 0.35 * tagPart + 0.15 * studioPart) * (anchor.weight / max(maxSeedWeight, 0.0001))
                if (value > similarScore) { similarScore = value; similarAnchor = anchor.item }
            }
            similarScore *= 3.0 * similarWeight
        }

        var score = performerScore + studioScore + tagScore + relatedScore + similarScore
        if (score <= 0) return null

        candidate.rating?.let { score *= 1 + ratingWeight * (it - 60) / 200.0 }

        val oCounter = candidate.oCounter
        val daysSincePlay = candidate.lastPlayedAt?.let { (now.epochSecond - it.epochSecond) / 86_400.0 } ?: Double.POSITIVE_INFINITY
        var isRediscover = false
        when (discovery) {
            RecommendationDiscovery.Fresh -> score *= 1.2
            // Never played and not played in the window weigh the same.
            RecommendationDiscovery.Balanced -> if (!isUnwatched) isRediscover = oCounter > 0 && daysSincePlay > 60
            RecommendationDiscovery.Favorites -> if (isUnwatched) score *= 0.85 else {
                score *= 1 + 0.25 * oCountWeight * min(oCounter, 4)
                if ((candidate.rating ?: 0) >= 80) score *= 1 + 0.2 * ratingWeight
                isRediscover = daysSincePlay > 60
            }
        }

        // Per-build jitter: close scores resolve differently in every list.
        score *= 1 + 0.35 * jitter(candidate.id)

        fun tagName(id: String) = vocabulary.tagNames[id] ?: "this tag"
        val factors = listOf(
            performerScore to performerHits.firstOrNull()?.let { RecommendationReason.Performer(it.first.second) },
            studioScore to candidate.studio?.let { RecommendationReason.Studio(it.second) },
            tagScore to tagHits.firstOrNull()?.let { RecommendationReason.Tag(tagName(it.first)) },
            relatedScore to bestRelated?.let { RecommendationReason.RelatedTag(tagName(it.first)) },
            similarScore to similarAnchor?.let { RecommendationReason.SimilarTo(it.title ?: "a scene you watched") },
        )
        val strongest = factors.filter { it.second != null && it.first > 0 }.maxByOrNull { it.first }?.second
        val reason = when {
            isRediscover -> if (discovery == RecommendationDiscovery.Favorites && oCounter > 0) RecommendationReason.Favorite else RecommendationReason.Rediscover
            strongest != null -> strongest
            else -> return null
        }
        return Scored(candidate, reason, score)
    }

    /** Greedy pick; repeating a performer, studio or reason costs ground. */
    private fun diversify(scored: List<Scored>): List<Scored> {
        // Only the best few hundred can make the list; the greedy pass is quadratic.
        val pool = scored.sortedByDescending { it.score }.take(600).toMutableList()
        val picks = mutableListOf<Scored>()
        val performerUses = HashMap<String, Int>()
        val studioUses = HashMap<String, Int>()
        val reasonUses = HashMap<String, Int>()
        // Balanced keeps never-played and played-before scenes level: the pool holds far more
        // unplayed scenes, so equal scores alone would fill the list with NEW ones.
        var newPicks = 0
        var seenPicks = 0
        val balances = discovery == RecommendationDiscovery.Balanced && pool.any { !it.item.isUnwatched }
        fun adjusted(entry: Scored): Double {
            val pp = entry.item.performers.maxOfOrNull { performerUses[it.first] ?: 0 } ?: 0
            val sp = entry.item.studio?.let { studioUses[it.first] ?: 0 } ?: 0
            val rp = reasonUses[entry.reason.label] ?: 0
            val lead = if (!balances) 0 else if (entry.item.isUnwatched) newPicks - seenPicks else seenPicks - newPicks
            return entry.score * 0.5.pow(maxOf(lead, 0)) * 0.6.pow(pp) * 0.75.pow(sp) * 0.7.pow(rp)
        }
        while (picks.size < maxOf(count, LIST_LIMIT) && pool.isNotEmpty()) {
            var best = 0
            var bestScore = Double.NEGATIVE_INFINITY
            pool.forEachIndexed { i, entry ->
                val v = adjusted(entry)
                if (v > bestScore || (v == bestScore && entry.item.id < pool[best].item.id)) { bestScore = v; best = i }
            }
            val pick = pool.removeAt(best)
            picks += pick
            pick.item.performers.forEach { performerUses.merge(it.first, 1, Int::plus) }
            pick.item.studio?.let { studioUses.merge(it.first, 1, Int::plus) }
            reasonUses.merge(pick.reason.label, 1, Int::plus)
            if (pick.item.isUnwatched) newPicks++ else seenPicks++
        }
        return picks
    }

    // MARK: Helpers

    /** 0…1, stable for a scene within one build. */
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
}
