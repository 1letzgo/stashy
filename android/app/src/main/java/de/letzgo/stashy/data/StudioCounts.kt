package de.letzgo.stashy.data

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray

@Serializable
data class StudioCounts(
    val id: String,
    @SerialName("o_count") val oCount: Int = 0,
    @SerialName("o_count_all") val oCountAll: Int = 0,
    @SerialName("scene_count_all") val sceneCountAll: Int = 0,
    @SerialName("performer_count_all") val performerCountAll: Int = 0,
    @SerialName("gallery_count_all") val galleryCountAll: Int = 0,
)

/** What a studio card shows. [oCount] stays null until the server has answered. */
data class StudioDisplayCounts(val scenes: Int?, val galleries: Int?, val performers: Int?, val oCount: Int?)

/**
 * iOS: `StudioCountsStore`. Loads the counts of all visible studios in one query instead of one
 * per card; a query of its own because older servers reject `o_counter(depth:)`.
 */
object StudioCountsStore {
    private const val INCLUDE_KEY = "studio_counts_include_sub_studios"
    private const val BATCH_SIZE = 100
    private const val QUERY = "query FindStudioCounts(\$ids: [ID!], \$filter: FindFilterType) { findStudios(ids: \$ids, filter: \$filter) { studios { id o_count: o_counter(depth: 0) o_count_all: o_counter(depth: -1) scene_count_all: scene_count(depth: -1) performer_count_all: performer_count(depth: -1) gallery_count_all: gallery_count(depth: -1) } } }"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val counts = mutableStateMapOf<String, StudioCounts>()
    private val pending = mutableSetOf<String>()
    private var flushJob: Job? = null

    private var includeState by mutableStateOf<Boolean?>(null)
    var includeSubStudios: Boolean
        get() = includeState ?: Prefs.bool(INCLUDE_KEY).also { includeState = it }
        set(value) { includeState = value; Prefs.setBool(INCLUDE_KEY, value) }

    fun clear() {
        counts.clear()
        pending.clear()
    }

    /** [refresh]: ask again even when known (a detail page opening). */
    fun request(id: String, refresh: Boolean = false) {
        if (!ServerCapabilities.supports032 || (!refresh && id in counts)) return
        pending += id
        if (flushJob != null) return
        flushJob = scope.launch {
            delay(100)
            while (pending.isNotEmpty()) {
                val ids = pending.take(BATCH_SIZE)
                pending -= ids.toSet()
                runCatching {
                    val data = GraphQL.data(QUERY, vars("ids" to ids, "filter" to mapOf("per_page" to ids.size)))
                    val studios = data["findStudios"].obj?.get("studios") ?: JsonArray(emptyList())
                    GraphQL.decode(ListSerializer(StudioCounts.serializer()), studios).forEach { counts[it.id] = it }
                }
            }
            flushJob = null
        }
    }

    fun known(id: String): StudioCounts? = counts[id]

    fun display(studio: Studio): StudioDisplayCounts {
        val known = counts[studio.id]
        if (!includeSubStudios || known == null) return StudioDisplayCounts(studio.sceneCount, studio.galleryCount, studio.performerCount, known?.oCount)
        return StudioDisplayCounts(known.sceneCountAll, known.galleryCountAll, known.performerCountAll, known.oCountAll)
    }
}

/** The badge's count for a studio card; `*_all` sorts use the sub-studio totals once known. */
fun Studio.badgeCount(badge: CatalogCardBadge, counts: StudioDisplayCounts): BadgeCount {
    val value: Int? = when (badge) {
        CatalogCardBadge.Scenes -> counts.scenes
        CatalogCardBadge.Images -> imageCount
        CatalogCardBadge.Galleries -> counts.galleries
        CatalogCardBadge.Performers -> counts.performers
        CatalogCardBadge.PerformersAll -> StudioCountsStore.known(id)?.performerCountAll ?: counts.performers
        CatalogCardBadge.OCount -> counts.oCount
        CatalogCardBadge.OCountAll -> StudioCountsStore.known(id)?.oCountAll ?: counts.oCount
        CatalogCardBadge.Rating -> rating100
        CatalogCardBadge.Markers -> null
    }
    return if (value != null) badge to value else CatalogCardBadge.Scenes to (counts.scenes ?: 0)
}

@Composable
fun rememberStudioCounts(studio: Studio, refresh: Boolean = false): StudioDisplayCounts {
    LaunchedEffect(studio.id, ServerCapabilities.supports032) { StudioCountsStore.request(studio.id, refresh) }
    return StudioCountsStore.display(studio)
}
