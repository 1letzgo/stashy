package de.letzgo.stashy.ui.detail

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.StopCircle
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.ui.tools.downloads.DownloadGlyph

// Download controls of the detail list bars. They are `ChromeSlot`s (not the free-standing
// `SceneBulkDownloadButton` / `ImageSetDownloadButton`) because iOS puts them into the same
// `CatalogSlotBar` as columns and filter & sort: columns · contextual · secondary · filter.
// The stashy+ gate sits in `Downloads` (`requireDownloadEntitlement`), after the options alert,
// exactly like iOS.

/** iOS: `SceneBulkDownloadChrome.slot` — opens `SceneBulkDownloadDialog`. */
internal fun sceneBulkDownloadSlot(onClick: () -> Unit) = ChromeSlot(DownloadGlyph, "Download scenes", onClick = onClick)

/**
 * iOS: `galleryDownloadSlot` (ImagesView) / `tagImagesDownloadSlot` (TagDetailView) — stop while
 * downloading (tap cancels), check when stored (tap = sync / remove options), else the download
 * glyph. Read inside composition so the slot follows `Downloads` state.
 */
internal fun imageSetDownloadSlot(entryId: String, idleLabel: String, onShowOptions: () -> Unit): ChromeSlot = when {
    Downloads.activeDownloads[entryId] != null ->
        ChromeSlot(Icons.Outlined.StopCircle, "Cancel download", isActive = true) { Downloads.cancelGalleryDownload(entryId) }
    Downloads.isGalleryDownloaded(entryId) ->
        ChromeSlot(Icons.Filled.CheckCircle, "Downloaded", isActive = true, onClick = onShowOptions)
    else -> ChromeSlot(DownloadGlyph, idleLabel, onClick = onShowOptions)
}
