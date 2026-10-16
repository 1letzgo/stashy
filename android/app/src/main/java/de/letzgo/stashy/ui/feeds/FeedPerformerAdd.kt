package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Performer

/**
 * The write behind the Feeds overlay's "+" after the performer names: which entity gets the
 * performers and the full `performer_ids` list Stash expects (it replaces, so the list is the
 * row's existing performers ∪ the picked ones, without duplicates, existing order first).
 *
 * Scenes and previews update their scene, a marker updates its parent scene (markers carry no
 * performers of their own), clips are images (`imageUpdate`).
 */
data class FeedPerformerAdd(val target: Target, val id: String, val performerIds: List<String>) {
    enum class Target { Scene, Image }

    /** The mutation input: only `id` + `performer_ids`. */
    val input: Map<String, Any> get() = mapOf("id" to id, "performer_ids" to performerIds)

    companion object {
        /** Existing ∪ picked, first occurrence wins (blank ids dropped). */
        fun mergedIds(existing: List<String>, picked: List<String>): List<String> =
            (existing + picked).filter { it.isNotBlank() }.distinct()

        /**
         * Null when the row has nothing to write to (a marker without its scene) or its
         * performer list was not loaded (an image with `performers == null`): `performer_ids`
         * replaces, so writing only the picked ids would wipe the existing performers.
         */
        fun forItem(item: FeedItem, picked: List<String>): FeedPerformerAdd? {
            val existing = item.performers.map { it.id }
            val merged = mergedIds(existing, picked)
            return when (item) {
                is FeedItem.SceneItem -> FeedPerformerAdd(Target.Scene, item.scene.id, merged)
                is FeedItem.PreviewItem -> FeedPerformerAdd(Target.Scene, item.scene.id, merged)
                is FeedItem.MarkerItem -> item.marker.scene?.id?.let { FeedPerformerAdd(Target.Scene, it, merged) }
                is FeedItem.ClipItem -> if (item.image.performers == null) null else FeedPerformerAdd(Target.Image, item.image.id, merged)
            }
        }

        /** Scene performers with [added] appended (ids already present are skipped). */
        fun appending(current: List<Performer>, added: List<Performer>): List<Performer> {
            val seen = current.map { it.id }.toMutableSet()
            return current + added.filter { seen.add(it.id) }
        }

        /** Image performers with [added] appended (ids already present are skipped). */
        fun appendingNames(current: List<IdName>, added: List<Performer>): List<IdName> {
            val seen = current.map { it.id }.toMutableSet()
            return current + added.filter { seen.add(it.id) }.map { IdName(it.id, it.name) }
        }
    }
}

/** Whether the overlay offers the "+" (a marker needs its parent scene, an image its loaded performers). */
val FeedItem.canAddPerformers: Boolean get() = FeedPerformerAdd.forItem(this, emptyList()) != null
