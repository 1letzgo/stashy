package de.letzgo.stashy.data

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Live updates from the scene detail to lists (iOS: the `NotificationCenter` posts
 * `SceneResumeTimeUpdated`, `ScenePlayAdded`, `SceneDeleted`, `SceneUpdated`, `SceneCoverUpdated`,
 * `SceneOCounterUpdated` consumed by `sceneLiveUpdates(using:)`). Catalog / dashboard lists can
 * collect [SceneEvents.events] and patch their items in place.
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
}

object SceneEvents {
    private val flow = MutableSharedFlow<SceneEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<SceneEvent> get() = flow
    fun post(event: SceneEvent) { flow.tryEmit(event) }
}
