package de.letzgo.stashy.data

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Live performer updates (iOS: `PerformerImageUpdated` with `performerId` + `newImagePath`,
 * consumed by `patchPerformerImageInLists`, `PerformerDetailView` and `UniversalSearchView`).
 * Lists holding performers (catalog, dashboard rows, search, performer detail header, scene
 * performer rows) collect [PerformerEvents.events] and patch their items via [applyTo].
 */
sealed class PerformerEvent {
    abstract val performerId: String

    /**
     * The performer's image changed. [imagePath] is the new `image_path` when the mutation
     * returned it; [stamp] is the cache-buster the change registered in [ImageBusters].
     */
    data class ImageUpdated(override val performerId: String, val imagePath: String?, val stamp: String) : PerformerEvent()

    /** The performer after this event; other performers come back unchanged (same instance). */
    fun applyTo(performer: Performer): Performer {
        if (performer.id != performerId) return performer
        return when (this) {
            is ImageUpdated -> {
                val path = imagePath?.takeIf { it.isNotBlank() } ?: performer.imagePath
                // URLs built from the id alone (Feeds overlay) pick up [stamp] via ImageBusters.
                if (path == performer.imagePath) performer else performer.copy(imagePath = path)
            }
        }
    }

    /** A scene with this event applied to its performer rows (null when it has none of them). */
    fun applyTo(scene: Scene): Scene? {
        if (scene.performers.none { it.id == performerId }) return null
        val patched = scene.performers.map { applyTo(it) }
        return if (patched == scene.performers) null else scene.copy(performers = patched)
    }
}

object PerformerEvents {
    private val flow = MutableSharedFlow<PerformerEvent>(extraBufferCapacity = 32)
    val events: SharedFlow<PerformerEvent> get() = flow
    fun post(event: PerformerEvent) { flow.tryEmit(event) }
}

/** Applies [event] to a performer list; returns null when nothing changed. */
fun List<Performer>.applying(event: PerformerEvent): List<Performer>? {
    val idx = indexOfFirst { it.id == event.performerId }
    if (idx < 0) return null
    val next = event.applyTo(this[idx])
    if (next == this[idx]) return null
    return toMutableList().apply { set(idx, next) }
}

/** Applies [event] to the performer rows of every scene in a list; null when nothing changed. */
fun List<Scene>.applyingPerformerEvent(event: PerformerEvent): List<Scene>? {
    var changed = false
    val out = map { s -> event.applyTo(s)?.also { changed = true } ?: s }
    return if (changed) out else null
}
