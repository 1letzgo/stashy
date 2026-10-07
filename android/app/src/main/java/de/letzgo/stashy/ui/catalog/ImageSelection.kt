package de.letzgo.stashy.ui.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ImageDeletion
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeCardShape
import de.letzgo.stashy.ui.NativeConfirmDialog
import de.letzgo.stashy.ui.PagedList
import de.letzgo.stashy.ui.SF
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * iOS `ImagesView` multi-select state (`isSelectionMode` + `selectedImageIds`), as a pure value
 * so the rules are unit-testable. Selection only changes while [isActive].
 */
data class ImageSelection(val isActive: Boolean = false, val selectedIds: Set<String> = emptySet()) {
    val count: Int get() = selectedIds.size

    fun isSelected(id: String): Boolean = id in selectedIds

    /** "Select images": enter selection mode with nothing selected. */
    fun begin(): ImageSelection = ImageSelection(isActive = true)

    /** "Done": leave selection mode and clear the selection. */
    fun end(): ImageSelection = ImageSelection()

    /** iOS `toggleSelection(for:)`. */
    fun toggle(id: String): ImageSelection =
        if (!isActive) this else copy(selectedIds = if (id in selectedIds) selectedIds - id else selectedIds + id)

    /** iOS "Select all": every loaded (displayed) image. */
    fun selectAll(ids: Iterable<String>): ImageSelection = if (!isActive) this else copy(selectedIds = ids.toSet())

    /**
     * iOS `deleteSelectedImages` completion: all deleted → selection mode ends; otherwise it
     * stays on with only the failed ones selected so the user can retry.
     */
    fun afterDelete(failedIds: Set<String>): ImageSelection =
        if (failedIds.isEmpty()) ImageSelection() else ImageSelection(isActive = true, selectedIds = failedIds)
}

/** Result of one bulk delete (iOS toast texts). */
data class ImageDeleteOutcome(val requested: Int, val failedIds: Set<String>) {
    val deleted: Int get() = requested - failedIds.size
    val message: String
        get() = if (failedIds.isEmpty()) "$deleted image${if (deleted == 1) "" else "s"} deleted"
        else "$deleted of $requested deleted — ${failedIds.size} failed"

    companion object {
        /** iOS alert title — literally "Delete N images?". */
        fun confirmTitle(count: Int) = "Delete $count images?"
        const val CONFIRM_MESSAGE = "These images will be permanently deleted. This action cannot be undone."
    }
}

/** Deletes outlive the screen that started them (like iOS's detached completion handlers). */
private val deleteScope = MainScope()

/**
 * Observable holder of [ImageSelection] plus the delete confirmation / progress (one per image
 * list: Home › Images, an opened gallery).
 */
class ImageSelectionController {
    var state by mutableStateOf(ImageSelection()); private set
    var isConfirmingDelete by mutableStateOf(false); private set
    var isDeleting by mutableStateOf(false); private set

    val isActive: Boolean get() = state.isActive

    fun begin() { state = state.begin() }
    fun end() { state = state.end(); isConfirmingDelete = false }
    fun toggle(id: String) { state = state.toggle(id) }
    fun selectAll(images: List<StashImage>) { state = state.selectAll(images.map { it.id }) }

    fun requestDelete() { if (state.count > 0 && !isDeleting) isConfirmingDelete = true }
    fun cancelDelete() { isConfirmingDelete = false }

    /**
     * Deletes the selection: removes the images from [list] right away (optimistic), then runs
     * the deletes; failures are reported and the list is refetched so they reappear (iOS
     * `refetchImages(initial: true)`).
     */
    fun confirmDelete(list: PagedList<StashImage>) {
        isConfirmingDelete = false
        val ids = state.selectedIds
        if (ids.isEmpty() || isDeleting) return
        isDeleting = true
        list.patch { if (it.id in ids) null else it }
        deleteScope.launch {
            val failed = ImageDeletion.deleteAll(ids)
            val outcome = ImageDeleteOutcome(ids.size, failed)
            isDeleting = false
            state = state.afterDelete(failed)
            if (failed.isNotEmpty()) list.refresh()
            showToast(outcome.message)
        }
    }
}

/** The "Delete N images?" confirmation (iOS `.alert`). */
@Composable
fun ImageDeleteConfirmation(selection: ImageSelectionController, list: PagedList<StashImage>) {
    if (!selection.isConfirmingDelete) return
    NativeConfirmDialog(
        title = ImageDeleteOutcome.confirmTitle(selection.state.count),
        text = ImageDeleteOutcome.CONFIRM_MESSAGE,
        onDismiss = { selection.cancelDelete() },
        confirmLabel = "Delete",
        destructive = true,
        icon = SF.trash,
        onConfirm = { selection.confirmDelete(list) },
    )
}

/**
 * iOS selection cell: the thumbnail with a dim + `checkmark.circle.fill` (tint) when selected,
 * an empty `circle` otherwise; tapping anywhere toggles. [content] must not be clickable itself.
 */
@Composable
fun SelectableImageCell(selected: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier) {
        content()
        Box(
            Modifier.matchParentSize()
                .clip(NativeCardShape)
                .background(if (selected) Color.Black.copy(alpha = 0.4f) else Color.Transparent)
                .toggleable(value = selected, role = Role.Checkbox, onValueChange = { onToggle() }),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (selected) SF.checkmarkCircleFill else SF.circle,
                if (selected) "Selected" else "Not selected",
                tint = if (selected) Appearance.tint else Color.White.copy(alpha = 0.7f),
                modifier = Modifier.size(32.dp),
            )
        }
    }
}
