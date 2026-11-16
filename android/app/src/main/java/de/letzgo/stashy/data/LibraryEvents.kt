package de.letzgo.stashy.data

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Live updates for performers, studios and galleries and the "library counts changed" signal,
 * next to [SceneEvents] and [PerformerEvents]. Posted by the mutation helpers in
 * [DetailRepository] and friends; the dashboard (`DashboardStore`) collects [LibraryEvents.events]
 * once and patches its rows in place (iOS: the `*Updated` / `*Deleted` notifications).
 */
sealed class LibraryEvent {
    /** The performer after an edit, favorite or rating change; applied as a patch on the row's copy. */
    data class PerformerPatched(val id: String, val patch: (Performer) -> Performer) : LibraryEvent()
    data class StudioPatched(val id: String, val patch: (Studio) -> Studio) : LibraryEvent()
    /** A studio got or lost its parent: studio lists reload (iOS `StudioParentChanged`). */
    data class StudioParentChanged(val id: String) : LibraryEvent()
    /** A tag got or lost parents: the Tags list and open tag pages' sub-tag sections reload (iOS `TagParentsChanged`). */
    data class TagParentsChanged(val id: String) : LibraryEvent()
    /** A group got or lost containing groups: the Groups list and open group pages reload (iOS `GroupHierarchyChanged`). */
    data class GroupHierarchyChanged(val id: String) : LibraryEvent()
    data class GalleryPatched(val id: String, val patch: (Gallery) -> Gallery) : LibraryEvent()
    /** A gallery's scenes were edited (iOS `GallerySceneLinksChanged`): the gallery page and the pages of [sceneIds] (added or removed) reload. */
    data class GallerySceneLinksChanged(val galleryId: String, val sceneIds: Set<String>) : LibraryEvent()
    data class PerformerDeleted(val id: String) : LibraryEvent()
    data class StudioDeleted(val id: String) : LibraryEvent()
    data class GalleryDeleted(val id: String) : LibraryEvent()
    /** A scene marker was deleted (iOS `SceneMarkerDeleted`): marker lists, the scene page's strip and time bar and Feeds drop it. */
    data class SceneMarkerDeleted(val id: String, val sceneId: String?, val seconds: Double) : LibraryEvent()
    /** Something was created or deleted, or an O count changed: the statistics are stale. */
    data object StatsChanged : LibraryEvent()
}

object LibraryEvents {
    private val flow = MutableSharedFlow<LibraryEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<LibraryEvent> get() = flow
    fun post(event: LibraryEvent) { flow.tryEmit(event) }
}
