package de.letzgo.stashy.ui.tools.downloads

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme

/** iOS SF `arrow.down.doc` — the download glyph of the detail chrome. */
val DownloadGlyph: ImageVector get() = Icons.Outlined.FileDownload

/** One button of a download options alert. */
data class DownloadOption(val label: String, val destructive: Boolean = false, val action: () -> Unit)

/** iOS `.alert` with stacked buttons + Cancel, used by all download option prompts. */
@Composable
fun DownloadOptionsAlert(title: String, message: String?, options: List<DownloadOption>, onDismiss: () -> Unit) {
    val p = Theme.palette
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = p.secondaryBackground,
        titleContentColor = p.text,
        textContentColor = p.secondaryText,
        title = { Text(title, style = IosTypography.headline) },
        text = message?.let { { Text(it, style = IosTypography.subheadline) } },
        confirmButton = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(0.dp)) {
                options.forEach { option ->
                    TextButton(onClick = { onDismiss(); option.action() }) {
                        Text(
                            option.label,
                            color = if (option.destructive) StashyColors.systemRed else Appearance.tint,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
                TextButton(onClick = onDismiss) { Text("Cancel", color = Appearance.tint) }
            }
        },
    )
}

/**
 * iOS: `sceneBulkDownloadDialog(isPresented:scope:scopeName:)` (SceneBulkDownloadControl.swift) —
 * "Newest N scenes" / "All scenes" for a performer, studio, tag, group or saved filter.
 * Show it while a flag is set; [onDismiss] clears the flag.
 */
@Composable
fun SceneBulkDownloadDialog(scope: Downloads.SceneDownloadScope, scopeName: String, onDismiss: () -> Unit) {
    val batch = Downloads.sceneNewestBatchSize
    DownloadOptionsAlert(
        title = "Download scenes",
        message = "Scenes already downloaded are skipped.",
        options = listOf(
            DownloadOption("Newest $batch scenes") { Downloads.downloadScenes(scope, batch, scopeName) },
            DownloadOption("All scenes") { Downloads.downloadScenes(scope, null, scopeName) },
        ),
        onDismiss = onDismiss,
    )
}

/** iOS: `SceneBulkDownloadChrome.slot` — Material icon button that opens [SceneBulkDownloadDialog]. */
@Composable
fun SceneBulkDownloadButton(onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = DownloadsCircleSize) {
    IconButton(onClick, modifier.size(size)) { Icon(DownloadGlyph, "Download scenes") }
}

/**
 * iOS: `SceneDetailView.sceneDownloadNavButton` — green check when downloaded, progress ring
 * while downloading (indeterminate until the size is known), else the "Save scene" button.
 * Android: a Material app bar action of the scene's `NativeTopBar` (48 dp touch target).
 */
@Composable
fun SceneDownloadNavButton(scene: Scene, modifier: Modifier = Modifier) {
    val downloaded = Downloads.downloads.any { it.id == scene.id }
    val active = Downloads.activeDownloads[scene.id]
    when {
        downloaded -> Box(modifier.size(48.dp), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.CheckCircle, "Downloaded", tint = StashyColors.systemGreen)
        }
        active != null -> Box(modifier.size(48.dp), contentAlignment = Alignment.Center) {
            if (active.totalSize > 0) {
                CircularProgressIndicator(
                    progress = { active.progress.coerceIn(0.0, 1.0).toFloat() },
                    modifier = Modifier.size(22.dp), color = Appearance.tint,
                    trackColor = Appearance.tint.copy(alpha = 0.2f), strokeWidth = 2.5.dp,
                )
            } else {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp), color = Appearance.tint,
                    trackColor = Appearance.tint.copy(alpha = 0.2f), strokeWidth = 2.5.dp,
                )
            }
        }
        else -> de.letzgo.stashy.ui.TopBarAction(DownloadGlyph, "Save scene", modifier) { Downloads.downloadScene(scene) }
    }
}

/**
 * iOS: `GalleryDownloadOptionsAlert` (ImagesView.swift) — download newest N / all images, or for a
 * downloaded gallery sync newest / sync newest N / remove.
 */
@Composable
fun GalleryDownloadOptionsDialog(gallery: Gallery, onDismiss: () -> Unit) {
    val stored = Downloads.galleryDownloads.firstOrNull { it.id == gallery.id }
    val batch = Downloads.galleryNewestBatchSize
    val message = when {
        stored != null && stored.serverImageCount != null -> "${stored.images.size} of ${stored.serverImageCount} downloaded"
        gallery.imageCount != null -> "${gallery.imageCount} images in this gallery"
        else -> null
    }
    val options = if (stored != null) listOf(
        DownloadOption("Sync newest") { Downloads.syncGallery(gallery.id) },
        DownloadOption("Sync newest $batch") { Downloads.syncGallery(gallery.id, batch) },
        DownloadOption("Remove download", destructive = true) { Downloads.deleteGalleryDownload(gallery.id) },
    ) else listOf(
        DownloadOption("Newest $batch images") { Downloads.downloadGallery(gallery, batch) },
        DownloadOption("All images") { Downloads.downloadGallery(gallery, null) },
    )
    DownloadOptionsAlert("Gallery", message, options, onDismiss)
}

/** iOS: the "Tag images" alert of `TagDetailView`. Entry id is `tag-<tagId>`. */
@Composable
fun TagImagesDownloadDialog(tagId: String, tagName: String, onDismiss: () -> Unit) {
    val entryId = "tag-$tagId"
    val stored = Downloads.galleryDownloads.any { it.id == entryId }
    val batch = Downloads.galleryNewestBatchSize
    val options = if (stored) listOf(
        DownloadOption("Sync newest") { Downloads.syncTagImages(entryId) },
        DownloadOption("Sync newest $batch") { Downloads.syncTagImages(entryId, batch) },
        DownloadOption("Remove download", destructive = true) { Downloads.deleteGalleryDownload(entryId) },
    ) else listOf(
        DownloadOption("Newest $batch images") { Downloads.downloadTagImages(tagId, tagName, batch) },
        DownloadOption("All images") { Downloads.downloadTagImages(tagId, tagName, null) },
    )
    DownloadOptionsAlert("Tag images", null, options, onDismiss)
}

/**
 * iOS: `galleryDownloadSlot` / the tag equivalent — stop while downloading (tap cancels),
 * check when stored, else the download glyph. [onShowOptions] opens the options dialog.
 */
@Composable
fun ImageSetDownloadButton(entryId: String, onShowOptions: () -> Unit, modifier: Modifier = Modifier, size: Dp = DownloadsCircleSize) {
    val downloading = Downloads.activeDownloads[entryId] != null
    val stored = Downloads.galleryDownloads.any { it.id == entryId }
    when {
        downloading -> IconButton({ Downloads.cancelGalleryDownload(entryId) }, modifier.size(size)) {
            Icon(Icons.Outlined.StopCircle, "Cancel download", tint = StashyColors.systemRed)
        }
        stored -> IconButton(onShowOptions, modifier.size(size)) { Icon(Icons.Filled.CheckCircle, "Downloaded", tint = Appearance.tint) }
        else -> IconButton(onShowOptions, modifier.size(size)) { Icon(DownloadGlyph, "Download") }
    }
}
