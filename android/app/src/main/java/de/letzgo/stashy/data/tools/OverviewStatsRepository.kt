package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** iOS: `Statistics` (StashDBViewModel.swift) — the `stats { … }` payload plus the marker count. */
@Serializable
data class OverviewStatistics(
    @SerialName("scene_count") val sceneCount: Int = 0,
    @SerialName("scenes_size") val scenesSize: Double = 0.0,
    @SerialName("scenes_duration") val scenesDuration: Double = 0.0,
    @SerialName("image_count") val imageCount: Int = 0,
    @SerialName("images_size") val imagesSize: Double = 0.0,
    @SerialName("gallery_count") val galleryCount: Int = 0,
    @SerialName("performer_count") val performerCount: Int = 0,
    @SerialName("studio_count") val studioCount: Int = 0,
    @SerialName("group_count") val groupCount: Int = 0,
    @SerialName("movie_count") val movieCount: Int = 0,
    @SerialName("tag_count") val tagCount: Int = 0,
    @SerialName("total_o_count") val totalOCount: Int = 0,
    @SerialName("total_play_duration") val totalPlayDuration: Double = 0.0,
    @SerialName("total_play_count") val totalPlayCount: Int = 0,
    @SerialName("scenes_played") val scenesPlayed: Int = 0,
    /** Not part of `stats`; filled from `findSceneMarkers { count }` (cached per server). */
    val sceneMarkerCount: Int? = null,
)

/**
 * iOS: `StashDBViewModel.fetchStatistics` + `fetchMarkerCountStandalone` — holds the last
 * statistics so the Overview shows them instantly when reopened. Same throttle (3 s) and the
 * same per-server marker-count cache key (`cachedMarkerCount_<serverID>`).
 */
object OverviewStatsRepository {
    private const val STATS_QUERY =
        "{ stats { scene_count scenes_size scenes_duration image_count images_size gallery_count performer_count studio_count group_count tag_count total_o_count total_play_duration total_play_count scenes_played movie_count } }"
    private const val MARKER_COUNT_QUERY = "{ findSceneMarkers(filter: { per_page: 1 }) { count } }"

    var statistics by mutableStateOf<OverviewStatistics?>(null)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var isFetching by mutableStateOf(false)
        private set

    private var lastFetchAt = 0L
    private var loadedServerID: String? = null

    private val cachedMarkerCountKey: String
        get() = "cachedMarkerCount_${ServerConfigManager.activeConfig?.id ?: "default"}"

    /** Returns `true` on success (iOS completion `success`). */
    suspend fun fetch(): Boolean {
        val serverID = ServerConfigManager.activeConfig?.id
        if (serverID != loadedServerID) {
            statistics = null
            lastFetchAt = 0L
        }
        if (isFetching) return false
        if (statistics != null && System.currentTimeMillis() - lastFetchAt < 3_000) return true

        isFetching = true
        errorMessage = null
        return try {
            val data = GraphQL.data(STATS_QUERY)
            val stats = Json.decodeFromJsonElement(OverviewStatistics.serializer(), data["stats"] ?: throw IllegalStateException("No stats"))
            val cached = Prefs.int(cachedMarkerCountKey)
            statistics = if (cached > 0) stats.copy(sceneMarkerCount = cached) else stats
            loadedServerID = serverID
            errorMessage = null
            lastFetchAt = System.currentTimeMillis()
            isFetching = false
            fetchMarkerCount()
            true
        } catch (e: kotlinx.coroutines.CancellationException) {
            isFetching = false
            throw e
        } catch (e: Exception) {
            lastFetchAt = System.currentTimeMillis()
            isFetching = false
            errorMessage = "Statistics could not be loaded"
            false
        }
    }

    private suspend fun fetchMarkerCount() {
        val count = runCatching {
            GraphQL.data(MARKER_COUNT_QUERY)["findSceneMarkers"].obj?.get("count").stringOrNull?.toIntOrNull()
        }.getOrNull() ?: return
        Prefs.setInt(cachedMarkerCountKey, count)
        statistics = statistics?.copy(sceneMarkerCount = count)
    }
}
