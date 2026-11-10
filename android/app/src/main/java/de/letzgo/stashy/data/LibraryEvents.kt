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
    data class GalleryPatched(val id: String, val patch: (Gallery) -> Gallery) : LibraryEvent()
    data class PerformerDeleted(val id: String) : LibraryEvent()
    data class StudioDeleted(val id: String) : LibraryEvent()
    data class GalleryDeleted(val id: String) : LibraryEvent()
    /** Something was created or deleted, or an O count changed: the statistics are stale. */
    data object StatsChanged : LibraryEvent()
}

object LibraryEvents {
    private val flow = MutableSharedFlow<LibraryEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<LibraryEvent> get() = flow
    fun post(event: LibraryEvent) { flow.tryEmit(event) }
}
