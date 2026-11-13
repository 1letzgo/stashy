package de.letzgo.stashy.ui.filter

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import de.letzgo.stashy.R
import de.letzgo.stashy.data.StudioCountsStore
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.NativeDivider

/** Set by a studio's page: its filter sheets then offer "Include sub-studio content" (iOS `showsSubStudioContentOption`). */
val LocalShowsSubStudioContentOption = compositionLocalOf { false }

/**
 * iOS: `SubStudioOptionsCard` — the sub-studio switches of the Studios settings sheet
 * ([showsHide]) and of a studio's page. App settings ([StudioCountsStore]), not filter criteria:
 * no active dot, never saved into a filter; the lists watch them and refetch.
 */
@Composable
fun SubStudioOptionsCard(showsHide: Boolean) {
    ControlGroup {
        if (showsHide) {
            ControlToggleRow(tr(R.string.hide_sub_studios), StudioCountsStore.hideSubStudios) { StudioCountsStore.hideSubStudios = it }
            NativeDivider()
        }
        ControlToggleRow(tr(R.string.include_sub_studio_content), StudioCountsStore.includeSubStudios) { StudioCountsStore.includeSubStudios = it }
    }
}
