package de.letzgo.stashy.data

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Live updates from the scene detail to lists (iOS: the `NotificationCenter` posts
 * `SceneResumeTimeUpdated`, `ScenePlayAdded`, `SceneDeleted`, `SceneUpdated`, `SceneCoverUpdated`,
 * `SceneOCounterUpdated` consumed by `sceneLiveUpdates(using:)`). Catalog scene lists
 * (`CatalogController`) and the dashboard rows (`DashboardStore`) collect [SceneEvents.events]
 * and patch their items in place via [SceneEvent.applyTo].
 */
sealed class SceneEvent {
    abstract val sceneId: String
    data class ResumeTimeUpdated(override val sceneId: String, val resumeTime: Double) : SceneEvent()
    data class PlayAdded(override val sceneId: String) : SceneEvent()
    data class Deleted(override val sceneId: String) : SceneEvent()
    /** Title, details, studio, performers, tags, groups, galleries or rating changed. */
    data class Updated(val scene: Scene) : SceneEvent() { override val sceneId: String get() = scene.id }
    data class CoverUpdated(override val sceneId: String, val updatedAt: String) : SceneEvent()
    data class OCounterUpdated(override val sceneId: String, val oCounter: Int) : SceneEvent()

    /**
     * The list item after this event (iOS `updateSceneResumeTime`, `incrementScenePlayCount`,
     * `removeScene`, `mergeSceneListMetadata`, `patchSceneCoverInLists`,
     * `patchSceneOCounterInLists`); null removes it. Other scenes come back unchanged.
     */
    fun applyTo(scene: Scene): Scene? {
        if (scene.id != sceneId) return scene
        return when (this) {
            is ResumeTimeUpdated -> scene.copy(resumeTime = resumeTime)
            is PlayAdded -> scene.copy(playCount = maxOf(0, (scene.playCount ?: 0) + 1))
            is Deleted -> null
            is Updated -> scene.mergingListMetadata(this.scene)
            is CoverUpdated -> if (scene.updatedAt == updatedAt) scene else scene.copy(updatedAt = updatedAt)
            is OCounterUpdated -> scene.copy(oCounter = oCounter)
        }
    }
}

object SceneEvents {
    private val flow = MutableSharedFlow<SceneEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<SceneEvent> get() = flow
    fun post(event: SceneEvent) { flow.tryEmit(event) }
}

/** Applies [event] to a scene list; returns null when nothing changed. */
fun List<Scene>.applying(event: SceneEvent): List<Scene>? {
    val idx = indexOfFirst { it.id == event.sceneId }
    if (idx < 0) return null
    val next = event.applyTo(this[idx])
    if (next == this[idx]) return null
    return toMutableList().apply { if (next == null) removeAt(idx) else set(idx, next) }
}

/**
 * iOS: `Scene.mergingListMetadata(from:)` — takes the edited metadata of [other] (detail page)
 * but keeps the list's own resume time, play count, O-count, paths and markers.
 */
fun Scene.mergingListMetadata(other: Scene): Scene {
    val mergedFiles = when {
        other.files?.any { (it.duration ?: 0.0) > 0 } == true -> other.files
        files?.any { (it.duration ?: 0.0) > 0 } == true -> files
        else -> other.files ?: files
    }
    return copy(
        title = other.title ?: title,
        details = other.details ?: details,
        director = other.director ?: director,
        date = other.date?.takeIf { it.isNotEmpty() } ?: date,
        duration = other.duration ?: duration ?: mergedFiles?.mapNotNull { it.duration }?.maxOrNull(),
        studio = other.studio ?: studio,
        performers = other.performers.ifEmpty { performers },
        files = mergedFiles,
        tags = other.tags ?: tags,
        galleries = other.galleries ?: galleries,
        groups = other.groups ?: groups,
        organized = other.organized ?: organized,
        rating100 = other.rating100 ?: rating100,
        updatedAt = SceneStamps.newerUpdatedAt(other.updatedAt, updatedAt),
        stashIds = other.stashIds ?: stashIds,
    )
}

/** iOS: `Scene.newerUpdatedAt` and its stamp parsing. */
object SceneStamps {
    /** The later of two stamps (ISO 8601 or a local millisecond bust). */
    fun newerUpdatedAt(a: String?, b: String?): String? {
        if (a == null) return b
        if (b == null) return a
        val da = parseUpdatedAt(a); val db = parseUpdatedAt(b)
        if (da != null && db != null) return if (da >= db) a else b
        return if (a > b) a else b
    }

    /** Epoch millis of a 12–14 digit millisecond stamp or an ISO 8601 date, else null. */
    fun parseUpdatedAt(raw: String): Long? {
        if (raw.length in 12..14) raw.toLongOrNull()?.let { return it }
        return runCatching { java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli() }.getOrNull()
    }
}
