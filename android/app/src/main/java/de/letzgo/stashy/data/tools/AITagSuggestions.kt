package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.arr
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import de.letzgo.stashy.data.vars
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import kotlin.coroutines.coroutineContext

// iOS: `AITagSuggestionManager.swift` — Tag Suggestion (stashy+): tags proposed from the
// library's own statistics. The whole library is counted once into a local model (performer,
// gallery, studio and library-wide tag counts plus tag co-occurrence); suggestions are plain
// lookups in it — no network round trip while browsing, nothing leaves the device.

// MARK: - Model

/** iOS: `AITagSuggestion`. */
data class AITagSuggestion(val tag: Tag, val confidence: Double, val source: Source) {
    /** iOS: `AITagSuggestion.Source` (raw values identical). */
    enum class Source(val raw: String) {
        /** how often this performer carries the tag */
        Performer("performer"),
        /** how often this gallery carries the tag */
        Gallery("gallery"),
        /** how often this studio carries the tag */
        Studio("studio"),
        /** co-occurrence with the tags the item already has */
        Related("related"),
    }

    val id: String get() = tag.id
}

/**
 * iOS: `AITagTarget` — what a suggestion is made for. Scenes, markers and pictures all reach
 * the same statistics; only the write path differs.
 */
data class AITagTarget(
    val kind: Kind,
    val entityId: String,
    /** Everything the item carries, primary tag included. */
    val tags: List<Tag>,
    /** A marker's primary tag is set separately in Stash and must stay out of `tag_ids`. */
    val primaryTagId: String? = null,
    val performerIds: List<String> = emptyList(),
    val studioId: String? = null,
    val galleryIds: List<String> = emptyList(),
) {
    enum class Kind(val raw: String) { Image("image"), Scene("scene"), Marker("marker") }

    val id: String get() = "${kind.raw}-$entityId"

    companion object {
        fun image(image: StashImage) = AITagTarget(
            kind = Kind.Image,
            entityId = image.id,
            tags = image.tags.orEmpty().map { Tag(id = it.id, name = it.name ?: "") },
            performerIds = image.performers.orEmpty().map { it.id },
            studioId = image.studio?.id,
            galleryIds = image.galleries.orEmpty().map { it.id },
        )

        fun scene(scene: Scene) = AITagTarget(
            kind = Kind.Scene,
            entityId = scene.id,
            tags = scene.tags.orEmpty(),
            performerIds = scene.performers.map { it.id },
            studioId = scene.studio?.id,
            galleryIds = scene.galleries.orEmpty().map { it.id },
        )

        /** Markers are tagged as themselves; their scene supplies the performers. */
        fun marker(marker: SceneMarker): AITagTarget {
            val tags = marker.tags.orEmpty().map { Tag(id = it.id, name = it.name ?: "") }.toMutableList()
            val primary = marker.primaryTag
            if (primary != null && tags.none { it.id == primary.id }) tags.add(0, Tag(id = primary.id, name = primary.name ?: ""))
            return AITagTarget(
                kind = Kind.Marker,
                entityId = marker.id,
                tags = tags,
                primaryTagId = primary?.id,
                performerIds = marker.scene?.performers.orEmpty().map { it.id },
            )
        }
    }
}

/**
 * iOS: `AITagStatsModel` — everything counted from the library, persisted per server as
 * `AITagStats/<key>.json`. Same JSON keys as iOS; `builtAt` is seconds since 2001-01-01 like
 * Swift's default `JSONEncoder` date strategy.
 */
@Serializable
data class AITagStatsModel(
    val version: Int,
    val builtAt: Double,
    val itemCount: Int,
    val tags: List<Tag>,
    /** performer id → tag id → number of that performer's items carrying the tag */
    val performerCounts: Map<String, Map<String, Int>>,
    val performerTotals: Map<String, Int>,
    val galleryCounts: Map<String, Map<String, Int>>,
    val galleryTotals: Map<String, Int>,
    val studioCounts: Map<String, Map<String, Int>>,
    val studioTotals: Map<String, Int>,
    /** tag id → co-occurring tag id → number of items carrying both */
    val pairCounts: Map<String, Map<String, Int>>,
    val tagTotals: Map<String, Int>,
) {
    val builtAtMillis: Long get() = ((builtAt + AITagStatsMath.REFERENCE_DATE_OFFSET) * 1000).toLong()
}

/** One counted item (scene or image): ids only. */
data class AITagStatsItem(
    val tagIds: List<String>,
    val performerIds: List<String> = emptyList(),
    val galleryIds: List<String> = emptyList(),
    val studioId: String? = null,
)

/** iOS: `BulkScope` / `BulkPlan` of the manager. */
enum class AITagBulkScope { Gallery, Performer }

data class AITagBulkPlan(val scope: AITagBulkScope, val tag: Tag, val imageIds: List<String>, val sceneIds: List<String>) {
    val id: String get() = "$scope-${tag.id}"
    val total: Int get() = imageIds.size + sceneIds.size
}

/** iOS: `AITagSuggestionManager.ModelState`. */
sealed class AITagModelState {
    object Idle : AITagModelState()
    object Loading : AITagModelState()
    data class Building(val processed: Int, val total: Int) : AITagModelState()
    data class Ready(val items: Int) : AITagModelState()
    data class Failed(val message: String) : AITagModelState()
}

/**
 * iOS: the `NotificationCenter` posts of the manager (`SceneTagsUpdated`, `ImageTagsUpdated`,
 * `MarkerTagsUpdated`, `BulkTagsApplied`) so open lists can patch themselves.
 */
sealed class AITagUpdateEvent {
    data class TagsUpdated(val kind: AITagTarget.Kind, val entityId: String, val tags: List<Tag>) : AITagUpdateEvent()
    data class BulkTagsApplied(val tag: Tag, val imageIds: List<String>, val sceneIds: List<String>) : AITagUpdateEvent()
}

// MARK: - Pure statistics (unit-tested)

/** Counts items into the statistics model (iOS: `absorb` inside `performBuild`). */
class AITagStatsBuilder {
    val performerCounts = HashMap<String, HashMap<String, Int>>()
    val performerTotals = HashMap<String, Int>()
    val galleryCounts = HashMap<String, HashMap<String, Int>>()
    val galleryTotals = HashMap<String, Int>()
    val studioCounts = HashMap<String, HashMap<String, Int>>()
    val studioTotals = HashMap<String, Int>()
    val pairCounts = HashMap<String, HashMap<String, Int>>()
    val tagTotals = HashMap<String, Int>()

    /** Items without tags are not counted. Returns whether the item was counted. */
    fun absorb(item: AITagStatsItem): Boolean {
        val tagIds = item.tagIds
        if (tagIds.isEmpty()) return false
        for (t in tagIds) tagTotals.bump(t)
        for (t in tagIds) for (other in tagIds) if (other != t) pairCounts.getOrPut(t) { HashMap() }.bump(other)
        for (p in item.performerIds) {
            performerTotals.bump(p)
            val scope = performerCounts.getOrPut(p) { HashMap() }
            tagIds.forEach { scope.bump(it) }
        }
        for (g in item.galleryIds) {
            galleryTotals.bump(g)
            val scope = galleryCounts.getOrPut(g) { HashMap() }
            tagIds.forEach { scope.bump(it) }
        }
        item.studioId?.let { s ->
            studioTotals.bump(s)
            val scope = studioCounts.getOrPut(s) { HashMap() }
            tagIds.forEach { scope.bump(it) }
        }
        return true
    }

    /** Trims the co-occurrence matrix and freezes everything into a model. */
    fun build(tags: List<Tag>, itemCount: Int, builtAt: Double, partnersPerTag: Int = AITagStatsMath.PARTNERS_PER_TAG) = AITagStatsModel(
        version = AITagStatsMath.MODEL_VERSION,
        builtAt = builtAt,
        itemCount = itemCount,
        tags = tags,
        performerCounts = performerCounts.mapValues { it.value.toMap() },
        performerTotals = performerTotals.toMap(),
        galleryCounts = galleryCounts.mapValues { it.value.toMap() },
        galleryTotals = galleryTotals.toMap(),
        studioCounts = studioCounts.mapValues { it.value.toMap() },
        studioTotals = studioTotals.toMap(),
        pairCounts = AITagStatsMath.trimPairs(pairCounts, partnersPerTag),
        tagTotals = tagTotals.toMap(),
    )

    private fun HashMap<String, Int>.bump(key: String, by: Int = 1) { this[key] = (this[key] ?: 0) + by }
}

/** Scoring, local updates and storage helpers of the manager as pure functions. */
object AITagStatsMath {
    const val MODEL_VERSION = 2
    /** One "Ignore Tag" is the answer, not a vote. */
    const val DISMISS_STRIKES = 1
    /** Laplace-style damping: one of one item is not a certainty. */
    const val SMOOTHING = 1.0
    /** Co-occurrence is only kept for the strongest partners of a tag. */
    const val PARTNERS_PER_TAG = 40
    /** Fewer, larger pages: the build is dominated by round trips. */
    const val PAGE_SIZE = 500
    /** Statistics older than this are rebuilt on app start (12 h). */
    const val STALE_AFTER_MS = 12L * 60 * 60 * 1000
    /** Seconds between 1970-01-01 and Swift's reference date 2001-01-01. */
    const val REFERENCE_DATE_OFFSET = 978_307_200.0

    const val PERFORMER_WEIGHT = 1.0
    const val GALLERY_WEIGHT = 0.95
    const val STUDIO_WEIGHT = 0.8
    const val RELATED_WEIGHT = 1.0

    fun nowReferenceSeconds(nowMillis: Long = System.currentTimeMillis()): Double = nowMillis / 1000.0 - REFERENCE_DATE_OFFSET

    /** Only partners seen together at least twice, strongest first, at most [limit] per tag. */
    fun trimPairs(pairs: Map<String, Map<String, Int>>, limit: Int = PARTNERS_PER_TAG): Map<String, Map<String, Int>> {
        val out = LinkedHashMap<String, Map<String, Int>>()
        for ((tagId, partners) in pairs) {
            val kept = partners.entries
                .filter { it.value >= 2 }
                .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                .take(limit)
            if (kept.isNotEmpty()) out[tagId] = kept.associate { it.key to it.value }
        }
        return out
    }

    /** Two signals for the same tag: the stronger carries, agreement adds a modest bonus. */
    fun combine(lhs: Double, rhs: Double): Double = minOf(1.0, maxOf(lhs, rhs) + 0.15 * minOf(lhs, rhs))

    /**
     * iOS: `suggestions(for:)` — ranked suggestions for one item, excluding tags it already has and
     * dismissed ones. Top [maxSuggestions] by confidence (no threshold).
     */
    fun suggest(
        model: AITagStatsModel,
        target: AITagTarget,
        dismissals: Map<String, Int> = emptyMap(),
        maxSuggestions: Int = 8,
        tagsById: Map<String, Tag> = model.tags.associateBy { it.id },
    ): List<AITagSuggestion> {
        val existing = target.tags.map { it.id }.toSet()
        val scores = LinkedHashMap<String, Pair<Double, AITagSuggestion.Source>>()

        fun offer(tagId: String, score: Double, source: AITagSuggestion.Source) {
            if (tagId in existing) return
            if ((dismissals[tagId] ?: 0) >= DISMISS_STRIKES) return
            val current = scores[tagId]
            scores[tagId] = if (current == null) score to source
            else combine(current.first, score) to (if (score > current.first) source else current.second)
        }

        fun absorb(counts: Map<String, Int>?, total: Int?, weight: Double, source: AITagSuggestion.Source) {
            if (counts == null || total == null || total <= 0) return
            val denominator = total + SMOOTHING
            for ((tagId, count) in counts) offer(tagId, weight * count / denominator, source)
        }

        // 1. What this item's performers are usually tagged with.
        for (p in target.performerIds) absorb(model.performerCounts[p], model.performerTotals[p], PERFORMER_WEIGHT, AITagSuggestion.Source.Performer)
        // 2. The gallery — usually one shoot.
        for (g in target.galleryIds) absorb(model.galleryCounts[g], model.galleryTotals[g], GALLERY_WEIGHT, AITagSuggestion.Source.Gallery)
        // 3. The studio — real, but less specific.
        target.studioId?.let { s -> absorb(model.studioCounts[s], model.studioTotals[s], STUDIO_WEIGHT, AITagSuggestion.Source.Studio) }
        // 4. Tags that travel with the ones this item already has.
        for (tag in target.tags) absorb(model.pairCounts[tag.id], model.tagTotals[tag.id], RELATED_WEIGHT, AITagSuggestion.Source.Related)

        return scores.mapNotNull { (tagId, value) ->
            val tag = tagsById[tagId] ?: return@mapNotNull null
            AITagSuggestion(tag, minOf(1.0, value.first), value.second)
        }
            .sortedWith(compareByDescending<AITagSuggestion> { it.confidence }.thenBy { it.tag.id })
            .take(maxOf(1, maxSuggestions))
    }

    /** iOS: `relatedTagWeights(for:)` — how strongly other tags co-occur with [tagIds], 0…1. */
    fun relatedTagWeights(model: AITagStatsModel?, tagIds: List<String>): Map<String, Double> {
        if (model == null) return emptyMap()
        val weights = HashMap<String, Double>()
        for (tagId in tagIds) {
            val partners = model.pairCounts[tagId] ?: continue
            val total = (model.tagTotals[tagId] ?: 0).toDouble()
            if (total <= 0) continue
            for ((partner, count) in partners) {
                if (partner in tagIds) continue
                val share = minOf(1.0, count / total)
                weights[partner] = maxOf(weights[partner] ?: 0.0, share)
            }
        }
        return weights
    }

    /** iOS: `performerTagCounts(for:)` — strongest count among the item's performers. */
    fun performerTagCounts(model: AITagStatsModel?, target: AITagTarget): Map<String, Int> {
        if (model == null) return emptyMap()
        val counts = HashMap<String, Int>()
        for (p in target.performerIds) {
            val pc = model.performerCounts[p] ?: continue
            for ((tagId, count) in pc) counts[tagId] = maxOf(counts[tagId] ?: 0, count)
        }
        return counts
    }

    /**
     * iOS: `applyLocalUpdate(target:newTags:)` — folds one tag change into the model. Returns
     * null when nothing changed.
     */
    fun applyLocalUpdate(model: AITagStatsModel, target: AITagTarget, newTags: List<Tag>): AITagStatsModel? {
        val oldIds = target.tags.map { it.id }.toSet()
        val newIds = newTags.map { it.id }.toSet()
        val added = newIds - oldIds
        val removed = oldIds - newIds
        if (added.isEmpty() && removed.isEmpty()) return null

        // Markers are no items in the build, they only affect the vocabulary.
        val countsAsItem = target.kind != AITagTarget.Kind.Marker
        val wasCounted = countsAsItem && oldIds.isNotEmpty()
        val isCounted = countsAsItem && newIds.isNotEmpty()
        val itemDelta = (if (isCounted) 1 else 0) - (if (wasCounted) 1 else 0)

        fun bump(counts: Map<String, Map<String, Int>>, totals: Map<String, Int>, ids: List<String>): Pair<Map<String, Map<String, Int>>, Map<String, Int>> {
            val c = counts.toMutableMap()
            val t = totals.toMutableMap()
            for (id in ids) {
                if (itemDelta != 0) t[id] = maxOf(0, (t[id] ?: 0) + itemDelta)
                val scope = (c[id] ?: emptyMap()).toMutableMap()
                for (tagId in added) scope[tagId] = (scope[tagId] ?: 0) + 1
                for (tagId in removed) scope[tagId] = maxOf(0, (scope[tagId] ?: 0) - 1)
                c[id] = scope.filterValues { it > 0 }
            }
            return c to t
        }

        var m = model
        if (countsAsItem) {
            val (pc, pt) = bump(m.performerCounts, m.performerTotals, target.performerIds)
            val (gc, gt) = bump(m.galleryCounts, m.galleryTotals, target.galleryIds)
            var sc = m.studioCounts
            var st = m.studioTotals
            target.studioId?.let { s -> bump(sc, st, listOf(s)).let { sc = it.first; st = it.second } }

            val totals = m.tagTotals.toMutableMap()
            for (tagId in added) totals[tagId] = (totals[tagId] ?: 0) + 1
            for (tagId in removed) totals[tagId] = maxOf(0, (totals[tagId] ?: 0) - 1)

            // Co-occurrence: an added tag pairs with everything the item now has, a removed
            // one loses its pairs with whatever stayed.
            val pairs = m.pairCounts.mapValues { it.value.toMutableMap() }.toMutableMap()
            fun pair(lhs: String, rhs: String, delta: Int) {
                val partners = pairs[lhs] ?: mutableMapOf()
                val v = maxOf(0, (partners[rhs] ?: 0) + delta)
                if (v == 0) partners.remove(rhs) else partners[rhs] = v
                if (partners.isEmpty()) pairs.remove(lhs) else pairs[lhs] = partners
            }
            for (tagId in added) for (other in newIds) if (other != tagId) { pair(tagId, other, 1); pair(other, tagId, 1) }
            for (tagId in removed) for (other in newIds) if (other != tagId) { pair(tagId, other, -1); pair(other, tagId, -1) }

            m = m.copy(
                performerCounts = pc, performerTotals = pt,
                galleryCounts = gc, galleryTotals = gt,
                studioCounts = sc, studioTotals = st,
                itemCount = maxOf(0, m.itemCount + itemDelta),
                tagTotals = totals,
                pairCounts = pairs.mapValues { it.value.toMap() },
            )
        }

        // A tag created from the picker is not in the captured vocabulary yet.
        val known = m.tags.map { it.id }.toMutableSet()
        val extra = newTags.filter { known.add(it.id) }
        if (extra.isNotEmpty()) m = m.copy(tags = m.tags + extra)
        return m
    }

    /** iOS: `applyBulkToModel` — every item of that scope now carries the tag. */
    fun applyBulk(model: AITagStatsModel, plan: AITagBulkPlan, target: AITagTarget): AITagStatsModel {
        val tagId = plan.tag.id
        var m = model
        when (plan.scope) {
            AITagBulkScope.Gallery -> {
                val gc = m.galleryCounts.toMutableMap()
                for (g in target.galleryIds) {
                    val total = m.galleryTotals[g] ?: continue
                    gc[g] = (gc[g] ?: emptyMap()) + (tagId to total)
                }
                m = m.copy(galleryCounts = gc)
            }
            AITagBulkScope.Performer -> {
                val pc = m.performerCounts.toMutableMap()
                for (p in target.performerIds) {
                    val total = m.performerTotals[p] ?: continue
                    pc[p] = (pc[p] ?: emptyMap()) + (tagId to total)
                }
                m = m.copy(performerCounts = pc)
            }
        }
        m = m.copy(tagTotals = m.tagTotals + (tagId to maxOf(m.tagTotals[tagId] ?: 0, plan.total)))
        if (m.tags.none { it.id == tagId }) m = m.copy(tags = m.tags + plan.tag)
        return m
    }

    /**
     * iOS: `modelURL()` key — host and port rather than the config id, so re-adding a server
     * keeps its model: `"<host>:<port>"` split at non-alphanumerics, joined with `_`.
     */
    fun storageKey(host: String, port: String): String? {
        val h = host.trim().lowercase()
        if (h.isEmpty()) return null
        return "$h:$port".split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString("_")
    }

    private val json = kotlinx.serialization.json.Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        explicitNulls = false
        isLenient = true
        encodeDefaults = true
    }

    fun encode(model: AITagStatsModel): String = json.encodeToString(AITagStatsModel.serializer(), model)
    fun decode(text: String): AITagStatsModel? = runCatching { json.decodeFromString(AITagStatsModel.serializer(), text) }.getOrNull()

    private val dismissalsSerializer = MapSerializer(String.serializer(), Int.serializer())
    fun encodeDismissals(map: Map<String, Int>): String = json.encodeToString(dismissalsSerializer, map)
    fun decodeDismissals(text: String?): Map<String, Int> =
        text?.let { runCatching { json.decodeFromString(dismissalsSerializer, it) }.getOrNull() }.orEmpty()
}

// MARK: - Manager

/**
 * iOS: `AITagSuggestionManager.shared`. Settings keys identical (`ai_tags_enabled`,
 * `ai_tags_max_suggestions`, `ai_tags_dismissed` — the latter as a JSON string). Call [start] once
 * at app launch (server switches and the 12-hour refresh then follow by themselves) and
 * [ensureStatistics] when the app returns to the foreground.
 */
object AITagSuggestions {
    private const val KEY_ENABLED = "ai_tags_enabled"
    private const val KEY_MAX = "ai_tags_max_suggestions"
    private const val KEY_DISMISSED = "ai_tags_dismissed"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // MARK: Settings (kill switch — default OFF)

    private var enabledState by mutableStateOf(Prefs.bool(KEY_ENABLED))
    /** Master kill switch. */
    var isEnabled: Boolean
        get() = enabledState
        set(value) {
            enabledState = value
            Prefs.setBool(KEY_ENABLED, value)
            statisticsConsumerChanged()
        }

    private var maxState by mutableStateOf(Prefs.int(KEY_MAX, 8))
    /** How many suggestions the chip row shows at most (1…20 in Settings). */
    var maxSuggestions: Int
        get() = maxState
        set(value) { maxState = value; Prefs.setInt(KEY_MAX, value) }

    // MARK: Published state

    var state by mutableStateOf<AITagModelState>(AITagModelState.Idle); private set
    /** Epoch millis of the last build. */
    var lastBuiltAt by mutableStateOf<Long?>(null); private set
    var itemCount by mutableStateOf(0); private set
    private var dismissals by mutableStateOf(AITagStatsMath.decodeDismissals(Prefs.string(KEY_DISMISSED)))

    private val _events = MutableSharedFlow<AITagUpdateEvent>(extraBufferCapacity = 32)
    /** Tag writes and bulk applies, so open lists can patch themselves without a refetch. */
    val events: SharedFlow<AITagUpdateEvent> = _events.asSharedFlow()

    /** Available and allowed to run right now. */
    val isActive: Boolean get() = isEnabled && StashyPlus.isUnlocked

    /** Someone consumes the statistics: tag suggestions or Similar Scenes. */
    val needsStatistics: Boolean get() = StashyPlus.isUnlocked && (isEnabled || SimilarScenes.isEnabled)

    val hasModel: Boolean get() = state is AITagModelState.Ready

    val buildProgress: Double get() = (state as? AITagModelState.Building)
        ?.takeIf { it.total > 0 }?.let { minOf(1.0, it.processed.toDouble() / it.total) } ?: 0.0

    // MARK: Private state

    private var model: AITagStatsModel? = null
    private var tagsById: Map<String, Tag> = emptyMap()
    private var buildJob: Job? = null
    private var persistJob: Job? = null
    private var didLoadFromDisk = false
    private var loadedKey: String? = null
    private var started = false
    private var suggestionCache = HashMap<String, List<AITagSuggestion>>()

    // MARK: - Lifecycle

    /** Observes server switches and keeps the statistics fresh (iOS notification observers). */
    fun start() {
        if (started) return
        started = true
        scope.launch {
            var first = true
            snapshotFlow { ServerConfigManager.activeConfig?.id }.distinctUntilChanged().collect {
                if (!first) handleServerChange()
                first = false
                ensureStatistics()
            }
        }
    }

    /** Each server keeps its own model; switching loads that server's model. */
    private fun handleServerChange() {
        cancelWork()
        model = null
        tagsById = emptyMap()
        suggestionCache.clear()
        didLoadFromDisk = false
        loadedKey = null
        lastBuiltAt = null
        itemCount = 0
        state = AITagModelState.Idle
        SimilarScenes.invalidate()
    }

    fun cancelWork() {
        persistJob?.cancel(); persistJob = null
        buildJob?.cancel(); buildJob = null
        if (state is AITagModelState.Building) state = restingState()
    }

    private fun restingState(): AITagModelState = model?.let { AITagModelState.Ready(it.itemCount) } ?: AITagModelState.Idle

    /** Reads the cached statistics — gated on stashy+ only (Similar Scenes reads them too). */
    suspend fun loadIfNeeded() {
        val key = modelKey()
        if (didLoadFromDisk && key != loadedKey) handleServerChange()
        if (didLoadFromDisk || !StashyPlus.isUnlocked) return
        val file = modelFile() ?: return
        didLoadFromDisk = true
        loadedKey = key
        state = AITagModelState.Loading
        val loaded = withContext(Dispatchers.IO) {
            runCatching { if (file.exists()) AITagStatsMath.decode(file.readText()) else null }.getOrNull()
        }
        if (loaded == null || loaded.version != AITagStatsMath.MODEL_VERSION) {
            if (loaded != null) withContext(Dispatchers.IO) { file.delete() }
            if (state is AITagModelState.Loading) state = AITagModelState.Idle
            return
        }
        apply(loaded)
    }

    private fun apply(loaded: AITagStatsModel) {
        model = loaded
        tagsById = loaded.tags.associateBy { it.id }
        lastBuiltAt = loaded.builtAtMillis
        itemCount = loaded.itemCount
        suggestionCache.clear()
        state = AITagModelState.Ready(loaded.itemCount)
    }

    // MARK: - Building

    /** Switching a consumer on builds missing/stale statistics; the last one off deletes them. */
    fun statisticsConsumerChanged() {
        if (needsStatistics) scope.launch { ensureStatistics() } else deleteModel()
    }

    /** Builds when a consumer is on and there is no model yet or it is older than 12 hours. */
    suspend fun ensureStatistics() {
        if (!needsStatistics) return
        loadIfNeeded()
        if (state is AITagModelState.Building) return
        val built = lastBuiltAt
        if (built != null && hasModel && System.currentTimeMillis() - built < AITagStatsMath.STALE_AFTER_MS) return
        rebuild()
    }

    fun rebuild() {
        if (!needsStatistics || buildJob?.isActive == true) return
        buildJob = scope.launch { performBuild() }
    }

    fun deleteModel() {
        cancelWork()
        model = null
        tagsById = emptyMap()
        suggestionCache.clear()
        lastBuiltAt = null
        itemCount = 0
        state = AITagModelState.Idle
        modelFile()?.let { f -> scope.launch(Dispatchers.IO) { f.delete() } }
    }

    private suspend fun performBuild() {
        state = AITagModelState.Building(0, 0)
        val tags = try {
            fetchAllTags()
        } catch (e: CancellationException) {
            state = restingState(); throw e
        } catch (e: Exception) {
            state = AITagModelState.Failed("Could not read the tag list")
            return
        }
        val builder = AITagStatsBuilder()
        var processed = 0
        var expected = 0
        try {
            // Scenes first: in most libraries they carry the richer vocabulary.
            for (source in listOf("scenes", "images")) {
                var page = 1
                while (true) {
                    coroutineContext.ensureActive()
                    val batch = try {
                        fetchStatsPage(source, page)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        break
                    }
                    if (page == 1) expected += batch.second
                    if (batch.first.isEmpty()) break
                    batch.first.forEach { builder.absorb(it) }
                    processed += batch.first.size
                    state = AITagModelState.Building(processed, maxOf(expected, processed))
                    if (batch.first.size < AITagStatsMath.PAGE_SIZE) break
                    page += 1
                }
            }
        } catch (e: CancellationException) {
            state = restingState(); throw e
        }
        if (processed <= 0) {
            state = AITagModelState.Failed("No tagged scenes or images found")
            return
        }
        val built = builder.build(tags, processed, AITagStatsMath.nowReferenceSeconds())
        loadedKey = modelKey()
        didLoadFromDisk = true
        apply(built)
        persist(built)
    }

    private fun persist(built: AITagStatsModel) {
        val file = modelFile() ?: return
        scope.launch(Dispatchers.IO) {
            runCatching {
                file.parentFile?.mkdirs()
                val tmp = File(file.parentFile, file.name + ".tmp")
                tmp.writeText(AITagStatsMath.encode(built))
                if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
            }
        }
    }

    /** A short idle window collapses a tagging spree into one save. */
    private fun schedulePersist() {
        persistJob?.cancel()
        persistJob = scope.launch {
            delay(10_000)
            model?.let { persist(it) }
        }
    }

    // MARK: - Suggestions

    /** Cached suggestions for a target; tags it meanwhile carries are dropped. */
    fun cachedSuggestions(target: AITagTarget): List<AITagSuggestion>? {
        val cached = suggestionCache[target.id] ?: return null
        val existing = target.tags.map { it.id }.toSet()
        return cached.filter { it.tag.id !in existing }
    }

    /** Ranked suggestions for one item. Pure lookups in the local model. */
    suspend fun suggestions(target: AITagTarget, forceRefresh: Boolean = false): List<AITagSuggestion> {
        if (!isActive) return emptyList()
        if (!forceRefresh) cachedSuggestions(target)?.let { return it }
        loadIfNeeded()
        val m = model ?: return emptyList()
        val result = AITagStatsMath.suggest(m, target, dismissals, maxSuggestions, tagsById)
        suggestionCache[target.id] = result
        return result
    }

    /** The server's tag list as captured by the last build. */
    val vocabulary: List<Tag> get() = model?.tags.orEmpty()

    /** iOS: `relatedTagWeights(for:)` — empty while no statistics are built. */
    fun relatedTagWeights(tagIds: List<String>): Map<String, Double> = AITagStatsMath.relatedTagWeights(model, tagIds)

    fun performerTagCounts(target: AITagTarget): Map<String, Int> = AITagStatsMath.performerTagCounts(model, target)

    // MARK: - Dismissing

    /** Records a rejected tag; accepting it anywhere clears the record. */
    fun dismiss(suggestion: AITagSuggestion, target: AITagTarget) {
        dismissals = dismissals + (suggestion.tag.id to ((dismissals[suggestion.tag.id] ?: 0) + 1))
        Prefs.setString(KEY_DISMISSED, AITagStatsMath.encodeDismissals(dismissals))
        suggestionCache[target.id]?.let { cached -> suggestionCache[target.id] = cached.filter { it.tag.id != suggestion.tag.id } }
    }

    val dismissedTagCount: Int get() = dismissals.count { it.value >= AITagStatsMath.DISMISS_STRIKES }

    fun resetDismissals() {
        dismissals = emptyMap()
        Prefs.remove(KEY_DISMISSED)
        suggestionCache.clear()
    }

    // MARK: - Accepting

    suspend fun accept(suggestion: AITagSuggestion, target: AITagTarget): List<Tag>? = accept(listOf(suggestion), target)

    /** Adds tags in one mutation. Returns the item's new tag list, or null on failure. */
    suspend fun accept(accepted: List<AITagSuggestion>, target: AITagTarget): List<Tag>? {
        val existingIds = target.tags.map { it.id }.toSet()
        val additions = accepted.map { it.tag }.filter { it.id !in existingIds }
        if (additions.isEmpty()) return target.tags
        val newTags = target.tags + additions
        if (!write(newTags, target)) return null
        val acceptedIds = additions.map { it.id }.toSet()
        dismissals = dismissals.filterKeys { it !in acceptedIds }
        Prefs.setString(KEY_DISMISSED, AITagStatsMath.encodeDismissals(dismissals))
        suggestionCache[target.id]?.let { cached -> suggestionCache[target.id] = cached.filter { it.tag.id !in acceptedIds } }
        return newTags
    }

    private val SCENE_UPDATE_TAGS = """
        mutation SceneUpdate(${'$'}input: SceneUpdateInput!) {
            sceneUpdate(input: ${'$'}input) { id tags { id name } }
        }
    """
    private val IMAGE_UPDATE_TAGS = """
        mutation ImageUpdate(${'$'}input: ImageUpdateInput!) {
            imageUpdate(input: ${'$'}input) { id tags { id name } }
        }
    """
    private val MARKER_UPDATE_TAGS = """
        mutation SceneMarkerUpdate(${'$'}input: SceneMarkerUpdateInput!) {
            sceneMarkerUpdate(input: ${'$'}input) { id tags { id name } primary_tag { id name } }
        }
    """

    /**
     * Writes a tag list to the entity the target stands for, folds the change into the local
     * statistics and broadcasts it via [events].
     */
    suspend fun write(tags: List<Tag>, target: AITagTarget): Boolean {
        val mutation = when (target.kind) {
            AITagTarget.Kind.Image -> IMAGE_UPDATE_TAGS
            AITagTarget.Kind.Scene -> SCENE_UPDATE_TAGS
            AITagTarget.Kind.Marker -> MARKER_UPDATE_TAGS
        }
        // The primary tag lives in its own field; repeating it in tag_ids would duplicate it.
        val tagIds = tags.map { it.id }.let { ids -> if (target.kind == AITagTarget.Kind.Marker) ids.filter { it != target.primaryTagId } else ids }
        try {
            GraphQL.data(mutation, vars("input" to mapOf("id" to target.entityId, "tag_ids" to tagIds)))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return false
        }
        model?.let { m ->
            AITagStatsMath.applyLocalUpdate(m, target, tags)?.let { updated ->
                model = updated
                tagsById = updated.tags.associateBy { it.id }
                itemCount = updated.itemCount
                suggestionCache.clear()
                schedulePersist()
            }
        }
        _events.tryEmit(AITagUpdateEvent.TagsUpdated(target.kind, target.entityId, tags))
        return true
    }

    // MARK: - Bulk actions

    private val IDS_IMAGES = """
        query BulkImageIds(${'$'}filter: FindFilterType, ${'$'}image_filter: ImageFilterType) {
            findImages(filter: ${'$'}filter, image_filter: ${'$'}image_filter) { count images { id } }
        }
    """
    private val IDS_SCENES = """
        query BulkSceneIds(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
            findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) { count scenes { id } }
        }
    """
    private val BULK_IMAGE_ADD_TAGS = """
        mutation BulkImageUpdate(${'$'}input: BulkImageUpdateInput!) {
            bulkImageUpdate(input: ${'$'}input) { id }
        }
    """
    private val BULK_SCENE_ADD_TAGS = """
        mutation BulkSceneUpdate(${'$'}input: BulkSceneUpdateInput!) {
            bulkSceneUpdate(input: ${'$'}input) { id }
        }
    """

    /** Collects everything a bulk action would touch, so the user is asked with a real number. */
    suspend fun planBulkApply(tag: Tag, bulkScope: AITagBulkScope, target: AITagTarget): AITagBulkPlan? {
        val ids = if (bulkScope == AITagBulkScope.Gallery) target.galleryIds else target.performerIds
        if (ids.isEmpty()) return null
        val key = if (bulkScope == AITagBulkScope.Gallery) "galleries" else "performers"
        val filter = mapOf("per_page" to -1, "sort" to "id", "direction" to "ASC")
        val itemFilter = mapOf(key to mapOf("value" to ids, "modifier" to "INCLUDES"))
        val (images, scenes) = coroutineScope {
            val images = async { fetchIds(IDS_IMAGES, vars("filter" to filter, "image_filter" to itemFilter), "findImages", "images") }
            // A gallery holds images; scenes only match the performer scope.
            val scenes = async {
                if (bulkScope == AITagBulkScope.Performer) fetchIds(IDS_SCENES, vars("filter" to filter, "scene_filter" to itemFilter), "findScenes", "scenes")
                else emptyList()
            }
            images.await() to scenes.await()
        }
        val plan = AITagBulkPlan(bulkScope, tag, images, scenes)
        return if (plan.total > 0) plan else null
    }

    /** Adds the tag to everything the plan covers (mode ADD keeps existing tags). */
    suspend fun applyBulk(plan: AITagBulkPlan, target: AITagTarget): Boolean {
        var ok = true
        if (plan.imageIds.isNotEmpty()) ok = bulkAdd(plan.tag.id, plan.imageIds, BULK_IMAGE_ADD_TAGS) && ok
        if (plan.sceneIds.isNotEmpty()) ok = bulkAdd(plan.tag.id, plan.sceneIds, BULK_SCENE_ADD_TAGS) && ok
        if (!ok) return false
        model?.let { m ->
            val updated = AITagStatsMath.applyBulk(m, plan, target)
            model = updated
            tagsById = updated.tags.associateBy { it.id }
            suggestionCache.clear()
            schedulePersist()
        }
        _events.tryEmit(AITagUpdateEvent.BulkTagsApplied(plan.tag, plan.imageIds, plan.sceneIds))
        return true
    }

    private suspend fun bulkAdd(tagId: String, ids: List<String>, mutation: String): Boolean {
        // Chunked so a large gallery does not go out as one enormous request.
        for (chunk in ids.chunked(200)) {
            try {
                GraphQL.data(mutation, vars("input" to mapOf("ids" to chunk, "tag_ids" to mapOf("ids" to listOf(tagId), "mode" to "ADD"))))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                return false
            }
        }
        return true
    }

    private suspend fun fetchIds(query: String, variables: kotlinx.serialization.json.JsonObject, field: String, list: String): List<String> = try {
        GraphQL.data(query, variables)[field].obj?.get(list).arr?.mapNotNull { it.obj?.get("id").stringOrNull }.orEmpty()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        emptyList()
    }

    // MARK: - GraphQL

    private val STATS_SCENES = """
        query StatsScenes(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
            findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) {
                count
                scenes { id tags { id name } performers { id } studio { id } galleries { id } }
            }
        }
    """
    private val STATS_IMAGES = """
        query StatsImages(${'$'}filter: FindFilterType, ${'$'}image_filter: ImageFilterType) {
            findImages(filter: ${'$'}filter, image_filter: ${'$'}image_filter) {
                count
                images { id tags { id name } performers { id } studio { id } galleries { id } }
            }
        }
    """

    @Serializable private data class StatsRef(val id: String)
    @Serializable private data class StatsItem(
        val id: String,
        val tags: List<StatsRef>? = null,
        val performers: List<StatsRef>? = null,
        val studio: StatsRef? = null,
        val galleries: List<StatsRef>? = null,
    )

    private suspend fun fetchAllTags(): List<Tag> {
        val data = GraphQL.named("findTags", vars("filter" to mapOf("per_page" to -1, "sort" to "name", "direction" to "ASC")))
        val list = data["findTags"].obj?.get("tags") ?: return emptyList()
        return GraphQL.decode(ListSerializer(Tag.serializer()), list)
    }

    /** One page of the census: (items, total count). */
    private suspend fun fetchStatsPage(source: String, page: Int): Pair<List<AITagStatsItem>, Int> {
        val filter = mapOf("page" to page, "per_page" to AITagStatsMath.PAGE_SIZE, "sort" to "id", "direction" to "ASC")
        val scopeFilter = mapOf("tag_count" to mapOf("value" to 0, "modifier" to "GREATER_THAN"))
        val (query, field, list, filterVar) = if (source == "scenes") listOf(STATS_SCENES, "findScenes", "scenes", "scene_filter")
        else listOf(STATS_IMAGES, "findImages", "images", "image_filter")
        val obj = GraphQL.data(query, vars("filter" to filter, filterVar to scopeFilter))[field].obj
        val count = obj?.get("count").stringOrNull?.toIntOrNull() ?: 0
        val items = obj?.get(list)?.let { GraphQL.decode(ListSerializer(StatsItem.serializer()), it) }.orEmpty()
        return items.map { item ->
            AITagStatsItem(
                tagIds = item.tags.orEmpty().map { it.id },
                performerIds = item.performers.orEmpty().map { it.id },
                galleryIds = item.galleries.orEmpty().map { it.id },
                studioId = item.studio?.id,
            )
        } to count
    }

    // MARK: - Storage

    private fun modelKey(): String? {
        val config = ServerConfigManager.activeConfig ?: return null
        return AITagStatsMath.storageKey(config.serverAddress, config.port ?: config.serverProtocol.defaultPort)
    }

    /** `filesDir/AITagStats/<host_port>.json` (iOS: Application Support/AITagStats/<key>.json). */
    private fun modelFile(): File? {
        val key = modelKey() ?: return null
        return File(File(Prefs.appContext.filesDir, "AITagStats"), "$key.json")
    }
}
