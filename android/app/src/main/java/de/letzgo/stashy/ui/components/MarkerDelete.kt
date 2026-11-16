package de.letzgo.stashy.ui.components

import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import de.letzgo.stashy.R
import de.letzgo.stashy.data.DeleteActions
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.showToast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Outlives the dialog (and the card or row that opened it), so the delete always finishes. */
private val markerDeleteScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/**
 * iOS: `MarkerDeleteMenuButton` in a marker's `.contextMenu` — opened by a long press. Never
 * opens while Settings › Design › Editing hides Delete ([DeleteActions]).
 */
@Composable
fun MarkerDeleteMenu(expanded: Boolean, onDismiss: () -> Unit, onDelete: () -> Unit) {
    // A long press while hidden still sets the caller's flag: reset it, so the menu does not
    // pop up later when the switch goes back on.
    if (expanded && !DeleteActions.isShown) androidx.compose.runtime.LaunchedEffect(Unit) { onDismiss() }
    DropdownMenu(expanded = expanded && DeleteActions.isShown, onDismissRequest = onDismiss, containerColor = Theme.palette.secondaryBackground) {
        DropdownMenuItem(
            text = { Text(tr(R.string.action_delete_marker), color = StashyColors.systemRed) },
            leadingIcon = { Icon(SF.trash, null, tint = StashyColors.systemRed) },
            onClick = { onDismiss(); onDelete() },
        )
    }
}

/**
 * iOS: `markerDeleteAlert` — the confirmation for deleting [marker] (null = closed). Deletes
 * through [SceneEditing.deleteMarker], whose `SceneMarkerDeleted` event lets every marker list,
 * the scene page and Feeds drop the marker.
 */
@Composable
fun MarkerDeleteConfirm(marker: SceneMarker?, sceneId: String? = null, onDismiss: () -> Unit) {
    marker ?: return
    StashyAlert(
        title = tr(R.string.confirm_delete_marker),
        message = tr(R.string.hint_marker_is_removed_scene_stays),
        onDismiss = onDismiss,
        confirmLabel = tr(R.string.action_delete),
        destructive = true,
        dismissLabel = tr(R.string.action_cancel),
        onConfirm = {
            onDismiss()
            markerDeleteScope.launch {
                val ok = runCatching { SceneEditing.deleteMarker(marker, sceneId) }.isSuccess
                showToast(tr(if (ok) R.string.marker_deleted else R.string.error_delete_marker))
            }
        },
    )
}
