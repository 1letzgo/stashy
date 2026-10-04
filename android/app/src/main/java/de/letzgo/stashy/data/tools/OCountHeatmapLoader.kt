package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.GraphQLError
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ScenePaths
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.VisualFile
import de.letzgo.stashy.data.vars
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import kotlin.math.abs

// iOS: `OCountHeatmapLoader.swift` — scene `o_history` plus image `o_counter` from Stash,
// bucketed by local day. Pure bucketing lives in `OCountHeatmapBucketing.kt`.

/** iOS: `OCountHeatmapItem.asScene` — a list-style scene for the detail screen. */
fun OCountHeatmapItem.asScene(): Scene = Scene(
    id = stashID,
    title = title,
    studio = studio?.let { Studio(id = it.id, name = it.name.orEmpty()) },
    oCounter = countOnDay,
    paths = ScenePaths(screenshot = thumbnailPath),
)

/** iOS: `OCountHeatmapItem.asImage`. */
fun OCountHeatmapItem.asImage(): StashImage = StashImage(
    id = stashID,
    title = displayTitle,
    rating100 = rating100,
    oCounter = countOnDay,
    paths = ImagePaths(thumbnail = thumbnailPath, preview = previewPath, image = imagePath),
    visualFiles = visualFiles,
    performers = performers.ifEmpty { null },
)

/** iOS: `OCountHeatmapItem.thumbnailURL`. */
val OCountHeatmapItem.thumbnailURL: String?
    get() = when (kind) {
        OCountHeatmapItem.Kind.Scene -> asScene().thumbnailURL
        OCountHeatmapItem.Kind.Image -> asImage().let { it.thumbnailURL ?: de.letzgo.stashy.data.Net.signed(it.paths?.preview) ?: it.imageURL }
    }

/**
 * iOS: `ImageOCountActionStore` — local action times for image O-counts (Stash images have no
 * `o_history`). Same key `stashy_timeline_image_o_actions_<serverID>`, 90 days lookback.
 */
object ImageOCountActionStore {
    @Serializable
    data class Entry(
        val imageId: String,
        val at: Double,
        val title: String? = null,
        val thumbnailPath: String? = null,
        val previewPath: String? = null,
        val imagePath: String? = null,
        val rating100: Int? = null,
    ) {
        fun asItem(): OCountHeatmapItem? {
            val resolved = title?.trim().orEmpty().ifEmpty { "Untitled" }
            if (resolved == "Untitled" && thumbnailPath == null && previewPath == null && imagePath == null) return null
            return OCountHeatmapItem(
                kind = OCountHeatmapItem.Kind.Image, stashID = imageId, title = resolved,
                thumbnailPath = thumbnailPath, previewPath = previewPath, imagePath = imagePath,
                rating100 = rating100, countOnDay = 1,
            )
        }

        fun withMetadata(item: OCountHeatmapItem) = copy(
            title = if (item.isPlaceholder) title else item.title,
            thumbnailPath = item.thumbnailPath ?: thumbnailPath,
            previewPath = item.previewPath ?: previewPath,
            imagePath = item.imagePath ?: imagePath,
            rating100 = item.rating100 ?: rating100,
        )
    }

    private const val LOOKBACK_SECONDS = 90.0 * 24 * 60 * 60
    private val serializer = ListSerializer(Entry.serializer())

    fun record(imageId: String, at: Instant = Instant.now(), item: OCountHeatmapItem? = null) {
        if (imageId.isEmpty()) return
        val entries = load().toMutableList()
        entries.add(
            Entry(
                imageId = imageId, at = at.toEpochMilli() / 1000.0,
                title = if (item?.isPlaceholder == false) item.title else null,
                thumbnailPath = item?.thumbnailPath, previewPath = item?.previewPath,
                imagePath = item?.imagePath, rating100 = item?.rating100,
            ),
        )
        val cutoff = nowSeconds() - LOOKBACK_SECONDS
        save(entries.filter { it.at >= cutoff })
    }

    fun updateMetadata(imageId: String, item: OCountHeatmapItem) {
        if (imageId.isEmpty() || item.isPlaceholder) return
        var changed = false
        val entries = load().map { e ->
            if (e.imageId != imageId) return@map e
            val next = e.withMetadata(item)
            if (next.title != e.title || next.thumbnailPath != e.thumbnailPath) { changed = true; next } else e
        }
        if (changed) save(entries)
    }

    fun all(): List<Entry> {
        val cutoff = nowSeconds() - LOOKBACK_SECONDS
        return load().filter { it.at >= cutoff }
    }

    private fun nowSeconds() = System.currentTimeMillis() / 1000.0
    private fun key() = "stashy_timeline_image_o_actions_${ServerConfigManager.activeConfig?.id ?: "default"}"
    private fun load(): List<Entry> =
        Prefs.string(key())?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()
    private fun save(entries: List<Entry>) = Prefs.setString(key(), Json.encodeToString(serializer, entries))
}

/**
 * iOS: `OCountHeatmapLoader` (singleton `ObservableObject`). Compose state; call [loadIfNeeded]
 * / [reload] from the UI. Other features can feed live changes through [applyLiveOIncrement],
 * [applyLiveRating] and [applyLiveSceneMetadata] (iOS: `SceneOCounterUpdated`,
 * `ImageOCounterUpdated`, `SceneRatingUpdated`, `ImageRatingUpdated`, `SceneUpdated` notifications).
 */
object OCountHeatmapLoader {
    var countsByDay by mutableStateOf<Map<String, Int>>(emptyMap())
        private set
    var itemsByDay by mutableStateOf<Map<String, List<OCountHeatmapItem>>>(emptyMap())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var didFail by mutableStateOf(false)
        private set
    /** Bumped on every change so observers of derived data recompose (iOS `objectWillChange`). */
    var revision by mutableStateOf(0)
        private set

    private var timedEvents: List<OCountTimelineEvent> = emptyList()
    private val liveEvents = mutableListOf<OCountTimelineEvent>()
    private val hydratingImageIDs = mutableSetOf<String>()
    private var loadedServerID: String? = null
    private var hasLoaded = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** iOS uses `TimeZone.current` through its Gregorian calendar. */
    val zone: ZoneId get() = ZoneId.systemDefault()

    val isReady: Boolean get() = hasLoaded

    suspend fun loadIfNeeded() {
        val serverID = ServerConfigManager.activeConfig?.id
        if (hasLoaded && loadedServerID == serverID) return
        if (loadedServerID != null && loadedServerID != serverID) reset()
        reload()
    }

    suspend fun reload() {
        val serverID = ServerConfigManager.activeConfig?.id
        isLoading = true
        didFail = false
        try {
            val buckets = fetchCountsByDay()
            countsByDay = buckets.counts.toMap()
            itemsByDay = buckets.items.mapValues { it.value.toList() }
            timedEvents = buckets.events.toList()
            pruneLiveEvents(buckets.events)
            restorePersistedImageActions()
            loadedServerID = serverID
            hasLoaded = true
            didFail = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            didFail = true
            countsByDay = emptyMap()
            itemsByDay = emptyMap()
            timedEvents = emptyList()
            loadedServerID = null
            hasLoaded = false
            restorePersistedImageActions()
        } finally {
            isLoading = false
            revision++
        }
    }

    fun latestMonthStart(): YearMonth? = OCountHeatmapBucketing.latestMonth(countsByDay)
    fun earliestMonthStart(): YearMonth? = OCountHeatmapBucketing.earliestMonth(countsByDay)

    fun count(onDayKey: String): Int = countsByDay[onDayKey] ?: 0

    fun items(onDayKey: String): List<OCountHeatmapItem> = OCountHeatmapBucketing.sortedItems(itemsByDay[onDayKey].orEmpty())

    fun monthHeatmap(month: YearMonth): OCountMonthHeatmap =
        OCountMonthHeatmap.build(countsByDay, month, countsByDay.values.maxOrNull() ?: 0)

    /** iOS: `events(in:actionsOnly:)` — fetched + live events in `[start, end)`. */
    fun events(start: Instant, end: Instant, actionsOnly: Boolean = false): List<OCountTimelineEvent> {
        restorePersistedImageActions()
        return (timedEvents + liveEvents).filter { e ->
            if (e.date < start || e.date >= end) return@filter false
            if (actionsOnly && e.item.kind == OCountHeatmapItem.Kind.Image) e.isActionTime else true
        }
    }

    fun reset() {
        countsByDay = emptyMap()
        itemsByDay = emptyMap()
        timedEvents = emptyList()
        liveEvents.clear()
        hydratingImageIDs.clear()
        hasLoaded = false
        loadedServerID = null
        didFail = false
        revision++
    }

    fun imageItem(stashID: String): OCountHeatmapItem? =
        (liveEvents.map { it.item } + itemsByDay.values.flatten())
            .firstOrNull { it.kind == OCountHeatmapItem.Kind.Image && it.stashID == stashID && !it.isPlaceholder }

    // MARK: live updates

    fun applyLiveOIncrement(kind: OCountHeatmapItem.Kind, stashID: String) {
        val now = Instant.now()
        val today = OCountHeatmapBucketing.dayKey(now, zone)
        countsByDay = countsByDay + (today to ((countsByDay[today] ?: 0) + 1))
        val list = itemsByDay[today].orEmpty().toMutableList()
        val source = list.firstOrNull { it.kind == kind && it.stashID == stashID }
            ?: itemsByDay.values.flatten().firstOrNull { it.kind == kind && it.stashID == stashID }
            ?: liveEvents.lastOrNull { it.item.kind == kind && it.item.stashID == stashID }?.item
        val idx = list.indexOfFirst { it.kind == kind && it.stashID == stashID }
        when {
            idx >= 0 -> list[idx] = list[idx].copy(countOnDay = list[idx].countOnDay + 1)
            source != null -> list.add(source.withCountOnDay(1))
            else -> list.add(OCountHeatmapItem.stub(kind, stashID))
        }
        itemsByDay = itemsByDay + (today to list)

        val item = source ?: OCountHeatmapItem.stub(kind, stashID)
        liveEvents.add(OCountTimelineEvent(item.withCountOnDay(1), now, 1, isActionTime = true))
        revision++

        if (kind == OCountHeatmapItem.Kind.Image) {
            ImageOCountActionStore.record(stashID, now, if (item.isPlaceholder) null else item)
            if (item.isPlaceholder) scope.launch { hydrateLiveImage(stashID) }
        }
    }

    fun applyLiveSceneMetadata(sceneId: String, title: String?, studio: IdName?, rating100: Int?) {
        var changed = false
        val next = itemsByDay.mapValues { (_, items) ->
            items.map {
                if (it.kind == OCountHeatmapItem.Kind.Scene && it.stashID == sceneId) {
                    changed = true
                    it.mergingListMetadata(title, studio, rating100)
                } else it
            }
        }
        if (changed) itemsByDay = next
    }

    fun applyLiveSceneMetadata(scene: Scene) =
        applyLiveSceneMetadata(scene.id, scene.title, scene.studio?.let { IdName(it.id, it.name) }, scene.rating100)

    fun applyLiveRating(kind: OCountHeatmapItem.Kind, stashID: String, rating100: Int?) {
        fun patch(item: OCountHeatmapItem) = if (item.kind == kind && item.stashID == stashID) item.withRating(rating100) else item
        timedEvents = timedEvents.map { it.copy(item = patch(it.item)) }
        for (i in liveEvents.indices) liveEvents[i] = liveEvents[i].copy(item = patch(liveEvents[i].item))
        val next = itemsByDay.mapValues { (_, items) -> items.map(::patch) }
        if (next != itemsByDay) itemsByDay = next
        revision++
    }

    suspend fun hydrateImageIfNeeded(stashID: String) = hydrateLiveImage(stashID)

    private suspend fun hydrateLiveImage(stashID: String) {
        if (!hydratingImageIDs.add(stashID)) return
        try {
            val item = fetchImageItem(stashID) ?: return
            for (i in liveEvents.indices) {
                val e = liveEvents[i]
                if (e.item.kind == OCountHeatmapItem.Kind.Image && e.item.stashID == stashID) {
                    liveEvents[i] = OCountTimelineEvent(item.withCountOnDay(e.count), e.date, e.count, true)
                }
            }
            itemsByDay = itemsByDay.mapValues { (_, items) ->
                items.map { if (it.kind == OCountHeatmapItem.Kind.Image && it.stashID == stashID) item.withCountOnDay(it.countOnDay) else it }
            }
            ImageOCountActionStore.updateMetadata(stashID, item)
            revision++
        } finally {
            hydratingImageIDs.remove(stashID)
        }
    }

    private fun pruneLiveEvents(fetched: List<OCountTimelineEvent>) {
        val now = Instant.now()
        val imageCutoff = now.minusSeconds(90L * 24 * 60 * 60)
        val sceneCutoff = now.minusSeconds(24L * 60 * 60)
        fun close(a: Instant, b: Instant) = abs(a.toEpochMilli() - b.toEpochMilli()) < 180_000
        liveEvents.removeAll { live ->
            if (live.item.kind == OCountHeatmapItem.Kind.Scene) {
                if (live.date < sceneCutoff) return@removeAll true
                return@removeAll fetched.any { it.item.kind == OCountHeatmapItem.Kind.Scene && it.item.stashID == live.item.stashID && close(it.date, live.date) }
            }
            if (!live.isActionTime) return@removeAll true
            if (live.date < imageCutoff) return@removeAll true
            fetched.any { it.isActionTime && it.item.kind == OCountHeatmapItem.Kind.Image && it.item.stashID == live.item.stashID && close(it.date, live.date) }
        }
    }

    private fun restorePersistedImageActions() {
        val hydrateIDs = mutableSetOf<String>()
        for (entry in ImageOCountActionStore.all()) {
            val date = Instant.ofEpochMilli((entry.at * 1000).toLong())
            val source = imageItem(entry.imageId) ?: entry.asItem() ?: OCountHeatmapItem.stub(OCountHeatmapItem.Kind.Image, entry.imageId)
            val event = OCountTimelineEvent(source.withCountOnDay(1), date, 1, true)
            val index = liveEvents.indexOfFirst {
                it.isActionTime && it.item.kind == OCountHeatmapItem.Kind.Image && it.item.stashID == entry.imageId &&
                    abs(it.date.toEpochMilli() / 1000.0 - entry.at) < 0.05
            }
            if (index >= 0) {
                if (liveEvents[index].item.isPlaceholder && !source.isPlaceholder) liveEvents[index] = event
            } else {
                liveEvents.add(event)
            }
            if (source.isPlaceholder) hydrateIDs.add(entry.imageId)
        }
        hydrateIDs.forEach { id -> scope.launch { hydrateLiveImage(id) } }
    }

    // MARK: fetching

    private suspend fun fetchCountsByDay(): OCountDayBuckets = coroutineScope {
        val scenes = async { fetchOptionally { fetchSceneCountsByDay() } }
        val images = async { fetchOptionally { fetchImageCountsByDay() } }
        val sceneBuckets = scenes.await()
        val imageBuckets = images.await()
        if (sceneBuckets == null && imageBuckets == null) throw GraphQLError.Query("O-Count query failed")
        val merged = sceneBuckets ?: OCountDayBuckets()
        if (imageBuckets != null) merged.merge(imageBuckets)
        merged
    }

    private suspend fun fetchOptionally(work: suspend () -> OCountDayBuckets): OCountDayBuckets? =
        try { work() } catch (e: CancellationException) { throw e } catch (e: Exception) { null }

    private fun oCounterFilterVars(page: Int, perPage: Int, filterName: String): JsonObject = vars(
        "filter" to mapOf("page" to page, "per_page" to perPage, "sort" to "o_counter", "direction" to "DESC"),
        filterName to mapOf("o_counter" to mapOf("value" to 0, "modifier" to "GREATER_THAN")),
    )

    private suspend fun fetchSceneCountsByDay(): OCountDayBuckets {
        val query = """
            query FindSceneOHistory(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
              findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) {
                count
                scenes { id title o_counter o_history created_at rating100 paths { screenshot } studio { id name } }
              }
            }
        """.trimIndent()
        var page = 1
        val perPage = 500
        val buckets = OCountDayBuckets()
        var total = Int.MAX_VALUE
        while ((page - 1).toLong() * perPage < total) {
            val data = try {
                GraphQL.data(query, oCounterFilterVars(page, perPage, "scene_filter"))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (page == 1) return fetchCountsByDayWithoutHistory()
                throw e
            }
            val result = GraphQL.decode(OCScenesPayload.serializer(), data["findScenes"] ?: JsonObject(emptyMap()))
            val scenes = result.scenes.orEmpty()
            total = result.count ?: scenes.size
            for (scene in scenes) {
                val id = scene.id ?: continue
                var addedHistory = false
                for (stamp in scene.oHistory.orEmpty()) {
                    val date = OCountHeatmapBucketing.flexibleTime(stamp) ?: continue
                    addedHistory = true
                    buckets.add(
                        OCountHeatmapItem.Kind.Scene, id, scene.title, scene.paths?.screenshot,
                        studio = scene.studio?.asIdName(), rating100 = scene.rating100,
                        dayKey = OCountHeatmapBucketing.dayKey(date, zone), amount = 1, occurredAt = date, isActionTime = true,
                    )
                }
                val created = scene.createdAt?.let { OCountHeatmapBucketing.parseTimestamp(it) }
                if (!addedHistory && (scene.oCounter ?: 0) > 0 && created != null) {
                    buckets.add(
                        OCountHeatmapItem.Kind.Scene, id, scene.title, scene.paths?.screenshot,
                        studio = scene.studio?.asIdName(), rating100 = scene.rating100,
                        dayKey = OCountHeatmapBucketing.dayKey(created, zone), amount = scene.oCounter ?: 0, occurredAt = created,
                    )
                }
            }
            if (scenes.isEmpty()) break
            page++
            if (page > 200) break
        }
        return buckets
    }

    private suspend fun fetchCountsByDayWithoutHistory(): OCountDayBuckets {
        val query = """
            query FindSceneOCounters(${'$'}filter: FindFilterType, ${'$'}scene_filter: SceneFilterType) {
              findScenes(filter: ${'$'}filter, scene_filter: ${'$'}scene_filter) {
                count
                scenes { id title o_counter created_at updated_at rating100 paths { screenshot } studio { id name } }
              }
            }
        """.trimIndent()
        var page = 1
        val perPage = 500
        val buckets = OCountDayBuckets()
        var total = Int.MAX_VALUE
        while ((page - 1).toLong() * perPage < total) {
            val data = GraphQL.data(query, oCounterFilterVars(page, perPage, "scene_filter"))
            val result = GraphQL.decode(OCScenesPayload.serializer(), data["findScenes"] ?: JsonObject(emptyMap()))
            val scenes = result.scenes.orEmpty()
            total = result.count ?: scenes.size
            for (scene in scenes) {
                val id = scene.id ?: continue
                val date = (scene.createdAt ?: scene.updatedAt)?.let { OCountHeatmapBucketing.parseTimestamp(it) } ?: continue
                buckets.add(
                    OCountHeatmapItem.Kind.Scene, id, scene.title, scene.paths?.screenshot,
                    studio = scene.studio?.asIdName(), rating100 = scene.rating100,
                    dayKey = OCountHeatmapBucketing.dayKey(date, zone), amount = scene.oCounter ?: 0, occurredAt = date,
                )
            }
            if (scenes.isEmpty()) break
            page++
            if (page > 200) break
        }
        return buckets
    }

    private const val IMAGE_FIELDS = """
        id title o_counter rating100 created_at updated_at
        paths { thumbnail preview image }
        visual_files {
          ... on BaseFile { __typename path basename }
          ... on ImageFile { __typename path height width basename }
          ... on VideoFile { __typename path height width duration basename }
        }
        performers { id name image_path }
    """

    private suspend fun fetchImageCountsByDay(): OCountDayBuckets {
        val query = """
            query FindImageOCounters(${'$'}filter: FindFilterType, ${'$'}image_filter: ImageFilterType) {
              findImages(filter: ${'$'}filter, image_filter: ${'$'}image_filter) { count images { $IMAGE_FIELDS } }
            }
        """.trimIndent()
        var page = 1
        val perPage = 500
        val buckets = OCountDayBuckets()
        var total = Int.MAX_VALUE
        while ((page - 1).toLong() * perPage < total) {
            val data = GraphQL.data(query, oCounterFilterVars(page, perPage, "image_filter"))
            val result = GraphQL.decode(OCImagesPayload.serializer(), data["findImages"] ?: JsonObject(emptyMap()))
            val images = result.images.orEmpty()
            total = result.count ?: images.size
            for (image in images) {
                val id = image.id ?: continue
                val date = (image.updatedAt ?: image.createdAt)?.let { OCountHeatmapBucketing.parseTimestamp(it) } ?: continue
                buckets.add(
                    OCountHeatmapItem.Kind.Image, id, image.title,
                    image.paths?.thumbnail ?: image.paths?.preview ?: image.paths?.image,
                    previewPath = image.paths?.preview, imagePath = image.paths?.image,
                    visualFiles = image.visualFiles?.filter { !it.path.isNullOrEmpty() },
                    performers = image.performers.orEmpty().mapNotNull { it.asIdName() },
                    rating100 = image.rating100,
                    dayKey = OCountHeatmapBucketing.dayKey(date, zone), amount = image.oCounter ?: 0, occurredAt = date,
                )
            }
            if (images.isEmpty()) break
            page++
            if (page > 200) break
        }
        return buckets
    }

    private suspend fun fetchImageItem(id: String): OCountHeatmapItem? {
        val query = """
            query FindImageOCountItem(${'$'}id: ID!) { findImage(id: ${'$'}id) { $IMAGE_FIELDS } }
        """.trimIndent()
        return try {
            val data = GraphQL.data(query, vars("id" to id))
            val element = data["findImage"] as? JsonObject ?: return null
            val image = GraphQL.decode(OCImageRow.serializer(), element)
            val imageID = image.id ?: return null
            OCountHeatmapItem(
                kind = OCountHeatmapItem.Kind.Image,
                stashID = imageID,
                title = image.title?.trim().orEmpty().ifEmpty { "Untitled" },
                thumbnailPath = image.paths?.thumbnail ?: image.paths?.preview ?: image.paths?.image,
                previewPath = image.paths?.preview,
                imagePath = image.paths?.image,
                visualFiles = image.visualFiles?.filter { !it.path.isNullOrEmpty() },
                performers = image.performers.orEmpty().mapNotNull { it.asIdName() },
                rating100 = image.rating100,
                countOnDay = maxOf(1, image.oCounter ?: 1),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }
}

// Decoding payloads (iOS: `OHistoryResponse`, `OCounterFallbackResponse`, `ImageOCounterResponse` …).

@Serializable
internal data class OCPaths(val screenshot: String? = null, val thumbnail: String? = null, val preview: String? = null, val image: String? = null)

@Serializable
internal data class OCNamed(val id: String? = null, val name: String? = null) {
    /** iOS: `asSceneStudio` / `asGalleryPerformer` — needs id and a non-blank name. */
    fun asIdName(): IdName? {
        val i = id ?: return null
        val n = name?.trim().orEmpty()
        return if (n.isEmpty()) null else IdName(i, n)
    }
}

@Serializable
internal data class OCSceneRow(
    val id: String? = null,
    val title: String? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    @SerialName("o_history") val oHistory: List<JsonElement>? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val rating100: Int? = null,
    val paths: OCPaths? = null,
    val studio: OCNamed? = null,
)

@Serializable
internal data class OCScenesPayload(val count: Int? = null, val scenes: List<OCSceneRow>? = null)

@Serializable
internal data class OCImageRow(
    val id: String? = null,
    val title: String? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    val rating100: Int? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val paths: OCPaths? = null,
    @SerialName("visual_files") val visualFiles: List<VisualFile>? = null,
    val performers: List<OCNamed>? = null,
)

@Serializable
internal data class OCImagesPayload(val count: Int? = null, val images: List<OCImageRow>? = null)
