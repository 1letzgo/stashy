package de.letzgo.stashy.ui.detail

import androidx.compose.runtime.Composable
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.feeds.FeedPerformerAdd
import de.letzgo.stashy.ui.scene.PerformersPickerSheet
import de.letzgo.stashy.ui.scene.PickerEntry

/**
 * The "+" after the performer names on a picture (fullscreen viewer, Pics / image feed header):
 * `imageUpdate(id, performer_ids)` with the image's existing performers ∪ the picked ones
 * (no duplicates, existing order first) — the same write the Feeds clip rows use
 * ([FeedPerformerAdd]). An image whose performer list was not loaded (`performers == null`) is
 * refused: `performer_ids` replaces, so writing only the picked ids would wipe the others.
 */
object ImagePerformerAdd {
    /** Whether the "+" shows: Edit Mode on and the image's performers loaded. */
    fun canAdd(image: StashImage, editMode: Boolean = Appearance.isEditModeEnabled): Boolean =
        editMode && image.performers != null

    /** Picked performers the image does not have yet (first occurrence wins). */
    fun newPerformers(image: StashImage, picked: List<Performer>): List<Performer> {
        val existing = image.performers.orEmpty().map { it.id }.toSet()
        return picked.filter { it.id.isNotBlank() && it.id !in existing }.distinctBy { it.id }
    }

    /** The write, or null when the image's performers were not loaded. */
    fun plan(image: StashImage, picked: List<Performer>): FeedPerformerAdd? {
        val existing = image.performers ?: return null
        return FeedPerformerAdd(FeedPerformerAdd.Target.Image, image.id, FeedPerformerAdd.mergedIds(existing.map { it.id }, picked.map { it.id }))
    }

    /** The image with [added] appended locally (ids already present are skipped). */
    fun applied(image: StashImage, added: List<Performer>): StashImage =
        image.copy(performers = FeedPerformerAdd.appendingNames(image.performers.orEmpty(), added))

    fun toastText(added: List<Performer>): String =
        if (added.size == 1) "Added ${added[0].name}" else "Added ${added.size} performers"

    /**
     * Writes existing ∪ [picked] and returns the updated image (the server's performer list when
     * it sends one, else the local append). Throws when refused or on failure — the caller keeps
     * its state and the picker shows the error.
     */
    suspend fun add(
        image: StashImage,
        picked: List<Performer>,
        write: suspend (id: String, performerIds: List<String>) -> List<IdName> = { id, ids -> FeedsRepository.updateImagePerformers(id, ids) },
    ): StashImage {
        val plan = checkNotNull(plan(image, picked)) { "Image performers not loaded" }
        val added = newPerformers(image, picked)
        if (added.isEmpty()) return image
        val server = write(plan.id, plan.performerIds)
        val local = applied(image, added)
        // Trust the server only when it lists at least what we wrote.
        return if (server.map { it.id }.containsAll(plan.performerIds)) image.copy(performers = server) else local
    }

    /** Picker rows for the image's own performers (ticked, locked, with their pictures). */
    fun currentEntries(image: StashImage): List<PickerEntry> =
        image.performers.orEmpty().map { PickerEntry(it.id, it.name ?: "", null, performerThumbnailURL(it.id, null)) }
}

/**
 * The scene detail's performer picker ([PerformersPickerSheet]) in add-only mode for [image]:
 * on success [onUpdated] gets the patched image and a toast confirms; on failure the sheet stays
 * open with the error and nothing changes.
 */
@Composable
fun AddImagePerformersSheet(image: StashImage, onDismiss: () -> Unit, onUpdated: (StashImage) -> Unit) =
    PerformersPickerSheet(
        itemKey = "image-${image.id}",
        current = ImagePerformerAdd.currentEntries(image),
        addOnly = true,
        save = { _, picked ->
            val added = ImagePerformerAdd.newPerformers(image, picked)
            val updated = ImagePerformerAdd.add(image, picked)
            onUpdated(updated)
            if (added.isNotEmpty()) detailToast(ImagePerformerAdd.toastText(added))
        },
        onDismiss = onDismiss,
    )
