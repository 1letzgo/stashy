package de.letzgo.stashy.ui.tools.downloads

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.scaledIconSize
import androidx.compose.foundation.layout.heightIn
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.ActiveDownload
import de.letzgo.stashy.data.DownloadedGallery
import de.letzgo.stashy.data.DownloadedScene
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.DownloadSavedFilter
import de.letzgo.stashy.data.tools.DownloadSavedFilters
import de.letzgo.stashy.data.tools.DownloadSyncJob
import de.letzgo.stashy.data.tools.DownloadSyncJobRunner
import de.letzgo.stashy.data.tools.DownloadSyncJobStore
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeGroup
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeSectionHeader
import de.letzgo.stashy.ui.NativeSwitchItem
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.components.formatDuration
import de.letzgo.stashy.ui.scene.SceneDetailScreen
import de.letzgo.stashy.ui.stashyGlass
import de.letzgo.stashy.ui.tools.GroupedCard
import de.letzgo.stashy.ui.tools.RowDivider
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.showToast
import de.letzgo.stashy.ui.tools.toolsTopPadding
import java.io.File
import java.util.Locale

/** iOS: `StashyExpandingDock.circleSize` / `iconSize`. */
internal val DownloadsCircleSize = 40.dp
internal val DownloadsIconSize = 18.dp

/**
 * iOS: `DownloadsView` (DownloadsView.swift) as embedded in Tools › Downloads — search field with
 * the round "+" for a new sync job, the sync-job pills, then Active Downloads, Queued, Scenes,
 * Galleries & Images and Tags. Works offline (no "no server" placeholder, like iOS).
 */
@Composable
fun DownloadsToolView(topPadding: androidx.compose.ui.unit.Dp = toolsTopPadding()) {
    val p = Theme.palette
    var search by rememberSaveable { mutableStateOf("") }
    var showingJobSheet by remember { mutableStateOf(false) }
    var showingRunAll by remember { mutableStateOf(false) }
    var jobToDelete by remember { mutableStateOf<DownloadSyncJob?>(null) }
    var savedFilters by remember { mutableStateOf<Map<String, DownloadSavedFilter>>(emptyMap()) }
    var sceneToDelete by remember { mutableStateOf<DownloadedScene?>(null) }
    var galleryToDelete by remember { mutableStateOf<DownloadedGallery?>(null) }

    val serverId = ServerConfigManager.activeConfig?.id
    LaunchedEffect(serverId) {
        DownloadSyncJobStore.load()
        Downloads.backfillMissingImageTitles()
        savedFilters = if (serverId != null) DownloadSavedFilters.fetch() else emptyMap()
    }
    DownloadsNotificationPermission()

    val downloads = Downloads.downloads
    val galleries = Downloads.galleryDownloads
    val active = Downloads.activeDownloads
    val queuedIds = Downloads.queuedSceneIds
    val jobs = DownloadSyncJobStore.jobs
    val query = search.trim()

    Column(Modifier.fillMaxSize()) {
        Spacer(Modifier.height(topPadding))
        // Search field plus the round "+" for a new sync job.
        Row(
            Modifier.fillMaxWidth()
                .padding(horizontal = ToolsTokens.contentPadding)
                .padding(top = ToolsTokens.menuTopPadding, bottom = Tokens.Spacing.xs + 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
        ) {
            NativeSearchField(search, { search = it }, tr(R.string.search_downloads), Modifier.weight(1f))
            Box(
                Modifier.size(48.dp).clip(CircleShape).background(Appearance.tint).clickable { showingJobSheet = true },
                contentAlignment = Alignment.Center,
            ) { Icon(SF.plus, tr(R.string.new_sync_job), tint = Color.White, modifier = Modifier.size(24.dp)) }
        }

        if (jobs.isNotEmpty()) SyncJobRow(
            jobs = jobs,
            onRunAll = { showingRunAll = true },
            onRun = { DownloadSyncJobRunner.run(it, savedFilters) },
            onLongPress = { jobToDelete = it },
        )

        if (downloads.isEmpty() && galleries.isEmpty() && active.isEmpty()) {
            Column(
                Modifier.fillMaxSize().padding(bottom = bottomBarContentPadding()),
                verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(SF.squareAndArrowDown, null, tint = Appearance.tint, modifier = Modifier.size(64.dp))
                Text(tr(R.string.empty_downloads_yet), style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = p.text)
                Text(
                    tr(R.string.hint_downloaded_scenes_will_appear_here),
                    style = IosTypography.body, color = p.secondaryText, textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = ToolsTokens.contentPadding),
                )
            }
        } else {
            val running = active.values.filter { it.id !in queuedIds }.sortedBy { it.title }
            val queued = active.values.filter { it.id in queuedIds }.sortedBy { it.title }
            val scenes = if (query.isEmpty()) downloads else downloads.filter { d ->
                d.title.orEmpty().contains(query, true) || d.studioName.orEmpty().contains(query, true) ||
                    d.performerNames.any { it.contains(query, true) }
            }
            val filteredGalleries = if (query.isEmpty()) galleries else galleries.filter { it.displayTitle.contains(query, true) }
            val galleryEntries = filteredGalleries.filter { it.resolvedKind != DownloadedGallery.Kind.Tag }
            val tagEntries = filteredGalleries.filter { it.resolvedKind == DownloadedGallery.Kind.Tag }
            val columns = downloadsGridColumns(ideal = 360.dp, minimum = 1, maximum = 6)

            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(top = ToolsTokens.menuTopPadding, bottom = bottomBarContentPadding()),
            ) {
                if (running.isNotEmpty()) {
                    sectionHeading(tr(R.string.active_downloads))
                    item(key = "active-group") {
                        NativeGroup(Modifier.padding(horizontal = ToolsTokens.contentPadding)) {
                            running.forEachIndexed { index, d ->
                                if (index > 0) NativeDivider()
                                ActiveDownloadRow(d)
                            }
                        }
                    }
                    item { Spacer(Modifier.height(20.dp)) }
                }
                if (queued.isNotEmpty()) {
                    sectionHeading(tr(R.string.queued))
                    item(key = "queued-group") {
                        NativeGroup(Modifier.padding(horizontal = ToolsTokens.contentPadding)) {
                            queued.forEachIndexed { index, d ->
                                if (index > 0) NativeDivider()
                                QueuedDownloadRow(d)
                            }
                        }
                    }
                    item { Spacer(Modifier.height(20.dp)) }
                }
                if (scenes.isNotEmpty()) {
                    sectionHeading(tr(R.string.scenes))
                    gridRows(scenes.chunked(columns), columns, keyPrefix = "scene", keyOf = { it.id }) { scene ->
                        DownloadedSceneCard(
                            scene,
                            onOpen = { Nav.push(SceneDetailScreen(scene.id, scene.toScene())) },
                            onDelete = { sceneToDelete = scene },
                        )
                    }
                    item { Spacer(Modifier.height(8.dp)) }
                }
                if (galleryEntries.isNotEmpty()) {
                    downloadSection(tr(R.string.galleries_and_images), galleryEntries, columns) { galleryToDelete = it }
                }
                if (tagEntries.isNotEmpty()) {
                    downloadSection(tr(R.string.tags), tagEntries, columns) { galleryToDelete = it }
                }
            }
        }
    }

    if (showingJobSheet) {
        DownloadSyncJobSheet(savedFilters, onDismiss = { showingJobSheet = false }) { DownloadSyncJobStore.add(it) }
    }
    if (showingRunAll) {
        StashyAlert(
            title = tr(R.string.confirm_run_all_jobs),
            message = tr(R.string.hint_each_job_downloads_its_configured),
            onDismiss = { showingRunAll = false },
            confirmLabel = tr(R.string.action_run_all),
            dismissLabel = tr(R.string.action_cancel),
            onConfirm = { showingRunAll = false; DownloadSyncJobRunner.runAll(DownloadSyncJobStore.jobs, savedFilters) },
        )
    }
    jobToDelete?.let { job ->
        StashyAlert(
            title = tr(R.string.confirm_delete_job),
            message = "${job.filterName} stays on the server; only the job goes away.",
            onDismiss = { jobToDelete = null },
            confirmLabel = tr(R.string.action_delete), destructive = true, dismissLabel = tr(R.string.action_cancel),
            onConfirm = { DownloadSyncJobStore.remove(job); jobToDelete = null },
        )
    }
    sceneToDelete?.let { scene ->
        StashyAlert(
            title = tr(R.string.confirm_delete_this_download),
            message = tr(R.string.hint_video_file_is_removed_from),
            onDismiss = { sceneToDelete = null },
            confirmLabel = tr(R.string.action_delete_download), destructive = true, dismissLabel = tr(R.string.action_cancel),
            onConfirm = { Downloads.deleteDownload(scene.id); sceneToDelete = null },
        )
    }
    galleryToDelete?.let { entry ->
        StashyAlert(
            title = tr(R.string.confirm_delete_this_download),
            message = tr(R.string.hint_downloaded_images_are_removed_from),
            onDismiss = { galleryToDelete = null },
            confirmLabel = tr(R.string.action_delete), destructive = true, dismissLabel = tr(R.string.action_cancel),
            onConfirm = { Downloads.deleteGalleryDownload(entry.id); galleryToDelete = null },
        )
    }
}

/** iOS: `DesignTokens.Grid.adaptiveColumns(width:ideal:minimum:maximum:)` over the content width. */
@Composable
internal fun downloadsGridColumns(ideal: Dp, minimum: Int, maximum: Int, spacing: Dp = 12.dp): Int {
    val width = LocalConfiguration.current.screenWidthDp.dp - ToolsTokens.contentPadding * 2
    val count = ((width + spacing) / (ideal + spacing)).toInt()
    return count.coerceIn(minimum, maximum)
}

/** Material section header (Settings style) above a downloads section. */
private fun LazyListScope.sectionHeading(title: String) {
    item(key = "heading-$title") {
        NativeSectionHeader(title, Modifier.padding(horizontal = ToolsTokens.contentPadding))
    }
}

private fun <T> LazyListScope.gridRows(
    rows: List<List<T>>,
    columns: Int,
    keyPrefix: String,
    keyOf: (T) -> String,
    cell: @Composable (T) -> Unit,
) {
    items(rows.size, key = { "$keyPrefix-$it-${rows[it].joinToString { e -> keyOf(e) }}" }) { index ->
        Row(
            Modifier.fillMaxWidth().padding(horizontal = ToolsTokens.contentPadding).padding(bottom = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val row = rows[index]
            row.forEach { Box(Modifier.weight(1f)) { cell(it) } }
            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

/** iOS: `downloadSection(_:entries:)` — galleries / images / tags as row cards. */
private fun LazyListScope.downloadSection(
    title: String,
    entries: List<DownloadedGallery>,
    columns: Int,
    onDelete: (DownloadedGallery) -> Unit,
) {
    sectionHeading(title)
    gridRows(entries.chunked(columns), columns, keyPrefix = "gallery-$title", keyOf = { it.id }) { entry ->
        DownloadedGalleryCard(
            entry,
            onOpen = { Nav.push(DownloadedGalleryScreen(entry.id)) },
            onSync = { if (entry.resolvedKind == DownloadedGallery.Kind.Tag) Downloads.syncTagImages(entry.id) else Downloads.syncGallery(entry.id) },
            onDelete = { onDelete(entry) },
        )
    }
    item { Spacer(Modifier.height(8.dp)) }
}

// MARK: - Sync jobs

/** iOS: `syncJobRow` — heading, run-all button and one pill per job (long press deletes). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SyncJobRow(
    jobs: List<DownloadSyncJob>,
    onRunAll: () -> Unit,
    onRun: (DownloadSyncJob) -> Unit,
    onLongPress: (DownloadSyncJob) -> Unit,
) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxWidth().padding(top = Tokens.Spacing.sm, bottom = Tokens.Spacing.md),
    ) {
        NativeSectionHeader(tr(R.string.action_sync_jobs), Modifier.padding(horizontal = ToolsTokens.contentPadding))
        Row(
            Modifier.padding(horizontal = ToolsTokens.contentPadding),
            horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(width = 40.dp, height = 44.dp).clip(RoundedCornerShape(50))
                    .background(p.secondaryBackground).clickable(enabled = jobs.isNotEmpty(), onClick = onRunAll),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.PlaylistPlay, tr(R.string.action_run_all_sync_jobs),
                    tint = if (jobs.isEmpty()) p.secondaryText else Appearance.tint, modifier = Modifier.size(20.dp),
                )
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
                jobs.forEach { job ->
                    Column(
                        Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(50)).background(p.secondaryBackground)
                            .combinedClickable(onClick = { onRun(job) }, onLongClick = { onLongPress(job) })
                            .padding(horizontal = Tokens.Spacing.sm, vertical = 4.dp),
                        verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(if (job.kind == DownloadSyncJob.Kind.Scenes) SF.film else SF.photo, null, tint = p.text, modifier = Modifier.size(scaledIconSize(11.dp)))
                            Text(job.filterName, style = IosTypography.footnote.copy(fontWeight = FontWeight.Medium), color = p.text, maxLines = 1)
                        }
                        Text(job.amountLabel, style = IosTypography.caption2, color = p.text, maxLines = 1, modifier = Modifier.alpha(0.75f))
                    }
                }
            }
        }
    }
}

/** iOS: `DownloadSyncJobSheet` — pick a scene/image saved filter and how many newest items per run. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DownloadSyncJobSheet(
    savedFilters: Map<String, DownloadSavedFilter>,
    onDismiss: () -> Unit,
    onSave: (DownloadSyncJob) -> Unit,
) {
    val p = Theme.palette
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var selectedId by remember { mutableStateOf<String?>(null) }
    var amount by remember { mutableStateOf(5) }
    var everything by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf("") }
    val usable = savedFilters.values
        .filter { it.isScenes || it.isImages }
        .filter { search.isEmpty() || it.name.contains(search, true) }
        .sortedBy { it.name.lowercase(Locale.ROOT) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = p.background) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            de.letzgo.stashy.ui.NativeSheetTopBar(tr(R.string.new_sync_job), onClose = onDismiss)
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = ToolsTokens.contentPadding, vertical = 8.dp),
            ) {
                item { NativeSearchField(search, { search = it }, tr(R.string.search_filters)) }
                item { Spacer(Modifier.height(20.dp)) }
                item { NativeSectionHeader(tr(R.string.filter)) }
                item {
                    GroupedCard {
                        if (usable.isEmpty()) {
                            NativeListItem(tr(R.string.hint_no_scene_or_image_filters), headlineColor = p.secondaryText)
                        }
                        usable.forEachIndexed { index, filter ->
                            if (index > 0) RowDivider()
                            NativeListItem(
                                filter.name,
                                icon = if (filter.isScenes) SF.film else SF.photo,
                                iconTint = p.secondaryText,
                                onClick = { selectedId = filter.id },
                                trailing = if (selectedId == filter.id) ({ Icon(Icons.Filled.Check, null, tint = nativeAccent(), modifier = Modifier.size(24.dp)) }) else null,
                            )
                        }
                    }
                }
                item { Spacer(Modifier.height(20.dp)) }
                item { NativeSectionHeader(tr(R.string.amount_per_run)) }
                item {
                    GroupedCard {
                        NativeSwitchItem(tr(R.string.all_matching_items), everything, onCheckedChange = { everything = it })
                        if (!everything) {
                            NativeDivider()
                            NativeListItem(tr(R.string.newest_arg, amount)) {
                                StepperControl(
                                    onDecrement = { amount = (amount - (if (amount < 20) 1 else 10)).coerceAtLeast(1) },
                                    onIncrement = { amount = (amount + (if (amount < 20) 1 else 10)).coerceAtMost(500) },
                                    canDecrement = amount > 1, canIncrement = amount < 500,
                                )
                            }
                        }
                    }
                }
            }
            val enabled = selectedId != null
            Box(
                Modifier.fillMaxWidth().background(p.background)
                    .padding(horizontal = ToolsTokens.contentPadding).padding(top = 6.dp, bottom = 12.dp).navigationBarsPadding(),
            ) {
                de.letzgo.stashy.ui.NativeButton(tr(R.string.action_save_job), Modifier.fillMaxWidth(), enabled = enabled) {
                    val id = selectedId ?: return@NativeButton
                    val filter = savedFilters[id] ?: return@NativeButton
                    onSave(
                        DownloadSyncJob(
                            filterId = id, filterName = filter.name,
                            kind = if (filter.isImages) DownloadSyncJob.Kind.Images else DownloadSyncJob.Kind.Scenes,
                            amount = if (everything) 0 else amount,
                        ),
                    )
                    onDismiss()
                }
            }
        }
    }
}

/** iOS `Stepper` look: − | + in one rounded capsule. */
@Composable
private fun StepperControl(onDecrement: () -> Unit, onIncrement: () -> Unit, canDecrement: Boolean, canIncrement: Boolean) {
    val p = Theme.palette
    Row(
        Modifier.clip(RoundedCornerShape(8.dp)).background(p.separator.copy(alpha = 0.35f)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(width = 46.dp, height = 32.dp).clickable(enabled = canDecrement, onClick = onDecrement), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Remove, tr(R.string.decrease), tint = if (canDecrement) p.text else p.tertiaryText, modifier = Modifier.size(18.dp))
        }
        Box(Modifier.width(0.5.dp).height(18.dp).background(p.separator))
        Box(Modifier.size(width = 46.dp, height = 32.dp).clickable(enabled = canIncrement, onClick = onIncrement), contentAlignment = Alignment.Center) {
            Icon(SF.plus, tr(R.string.increase), tint = if (canIncrement) p.text else p.tertiaryText, modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: - Active / queued rows

/** iOS: `activeDownloadRow` — title, cancel, progress bar, caption (row of a Material group). */
@Composable
private fun ActiveDownloadRow(download: ActiveDownload, modifier: Modifier = Modifier) {
    val p = Theme.palette
    Column(
        modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(
                download.title, style = NativeType.bodyLarge, color = p.text,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
            )
            CancelDownloadButton(download.id)
        }
        val fraction = download.progress.coerceIn(0.0, 1.0).toFloat()
        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier.fillMaxWidth(),
            color = Appearance.tint,
            trackColor = p.separator,
        )
        Text(DownloadsFormat.progressCaption(download), style = NativeType.bodyMedium, color = p.secondaryText)
    }
}

/** iOS: `queuedDownloadRow` — waiting for one of the two transfer slots. */
@Composable
private fun QueuedDownloadRow(download: ActiveDownload, modifier: Modifier = Modifier) {
    NativeListItem(
        download.title, modifier, supporting = tr(R.string.queued), supportingMaxLines = 1,
        icon = SF.clock, iconTint = Theme.palette.secondaryText,
        trailing = { CancelDownloadButton(download.id) },
    )
}

@Composable
private fun CancelDownloadButton(id: String) {
    Icon(
        Icons.Filled.Cancel, tr(R.string.action_cancel_download), tint = Theme.palette.secondaryText,
        modifier = Modifier.size(24.dp).clip(CircleShape).clickable { Downloads.cancelActiveDownload(id) },
    )
}

/** Byte and progress formatting like iOS `ByteCountFormatter` (`.file`, decimal units). */
object DownloadsFormat {
    fun bytes(count: Long): String {
        if (count <= 0) return tr(R.string.zero_kb)
        if (count < 1000) return "$count bytes"
        val kb = count / 1000.0
        if (kb < 1000) return String.format(Locale.US, "%.0f KB", kb)
        val mb = kb / 1000.0
        if (mb < 1000) return String.format(Locale.US, "%.1f MB", mb)
        val gb = mb / 1000.0
        return String.format(Locale.US, "%.2f GB", gb)
    }

    /** "42% · 12.3 MB of 280 MB · 4.1 MB/s", or "7 of 50 images" for an image download. */
    fun progressCaption(download: ActiveDownload): String {
        val parts = mutableListOf("${(download.progress.coerceIn(0.0, 1.0) * 100).toInt()}%")
        when {
            download.totalUnits > 0 -> parts += "${download.completedUnits} of ${download.totalUnits} images"
            download.totalSize > 0 -> parts += "${bytes(download.downloadedSize)} of ${bytes(download.totalSize)}"
            download.downloadedSize > 0 -> parts += bytes(download.downloadedSize)
        }
        if (download.speed > 0) parts += "${bytes(download.speed.toLong())}/s"
        return parts.joinToString(" · ")
    }
}

// MARK: - Cards

/**
 * Card wrapper with the row actions: swipe to the left deletes (iOS `stashySwipeActions`),
 * long press opens the full action menu.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun DownloadActionsCard(
    onOpen: () -> Unit,
    onDelete: () -> Unit,
    menu: List<Triple<String, ImageVector, () -> Unit>>,
    content: @Composable () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) onDelete()
        false
    })
    Box {
        SwipeToDismissBox(
            state = state,
            enableDismissFromStartToEnd = false,
            backgroundContent = {
                Box(
                    Modifier.fillMaxSize().clip(RoundedCornerShape(Tokens.Radius.card)).background(Appearance.tint).padding(end = 20.dp),
                    contentAlignment = Alignment.CenterEnd,
                ) { Icon(SF.trash, tr(R.string.action_delete), tint = Color.White) }
            },
        ) {
            Box(Modifier.combinedClickable(onClick = onOpen, onLongClick = { showMenu = true })) { content() }
        }
        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
            menu.forEach { (label, icon, action) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    leadingIcon = { Icon(icon, null) },
                    onClick = { showMenu = false; action() },
                )
            }
            DropdownMenuItem(
                text = { Text(tr(R.string.action_delete), color = StashyColors.systemRed) },
                leadingIcon = { Icon(SF.trash, null, tint = StashyColors.systemRed) },
                onClick = { showMenu = false; onDelete() },
            )
        }
    }
}

/** iOS: `DownloadedSceneCard` — 130×100 thumbnail with check, resume bar and duration, chips on the right. */
@Composable
private fun DownloadedSceneCard(downloaded: DownloadedScene, onOpen: () -> Unit, onDelete: () -> Unit) {
    val p = Theme.palette
    val context = LocalContext.current
    val tint = Appearance.tint
    val shape = RoundedCornerShape(Tokens.Radius.card)
    DownloadActionsCard(
        onOpen = onOpen,
        onDelete = onDelete,
        menu = listOf(
            Triple<String, ImageVector, () -> Unit>(tr(R.string.action_share), Icons.Outlined.Share, {
                val file = Downloads.localVideoFile(downloaded.id)
                if (file != null) shareDownloadedFile(context, file, "video/*") else showToast(tr(R.string.file_missing))
            }),
        ),
    ) {
        Row(
            // Min height: title + chips grow with the font scale (the 130×100 thumbnail stays top-aligned).
            Modifier.fillMaxWidth().heightIn(min = 100.dp).cardShadow(shape).clip(shape).background(p.secondaryBackground),
        ) {
            Box(Modifier.size(width = 130.dp, height = 100.dp)) {
                val thumb = Downloads.localThumbnailFile(downloaded)
                Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
                    Icon(SF.film, null, tint = p.secondaryText)
                }
                AsyncImage("file://${thumb.absolutePath}", null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                Box(
                    Modifier.align(Alignment.BottomStart).padding(4.dp).size(18.dp).clip(CircleShape).background(StashyColors.systemGreen),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(12.dp)) }
                val resume = downloaded.resumeTime ?: 0.0
                val duration = downloaded.duration ?: 0.0
                if (resume > 0 && duration > 0) {
                    Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(3.dp).background(Color.White.copy(alpha = 0.25f)))
                    Box(
                        Modifier.align(Alignment.BottomStart).fillMaxWidth((resume / duration).coerceAtMost(1.0).toFloat())
                            .height(3.dp).background(tint),
                    )
                }
                formatDuration(downloaded.duration)?.let { text ->
                    Text(
                        text, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp)
                            .stashyGlass(RoundedCornerShape(50)).padding(horizontal = 4.dp, vertical = 2.dp),
                    )
                }
            }
            Column(
                Modifier.weight(1f).heightIn(min = 100.dp).padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    downloaded.title ?: tr(R.string.unknown_title), style = IosTypography.subheadline.copy(fontWeight = FontWeight.Bold),
                    color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 4.dp),
                )
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    downloaded.studioName?.let { MetaChip(Icons.Filled.Business, it) }
                    downloaded.performerNames.take(3).forEach { MetaChip(Icons.Filled.Person, it) }
                    if (downloaded.performerNames.size > 3) {
                        Text("+${downloaded.performerNames.size - 3}", style = IosTypography.caption2, color = p.secondaryText, modifier = Modifier.padding(start = 2.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun MetaChip(icon: ImageVector, text: String) {
    val tint = Appearance.tint
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(tint.copy(alpha = 0.1f)).padding(horizontal = 6.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(9.dp))
        Text(text, style = IosTypography.caption2.copy(fontWeight = FontWeight.Medium), color = tint, maxLines = 1)
    }
}

/** iOS: `DownloadedGalleryCard` — 96×72 cover, title, "N of M images · Studio", stop while syncing. */
@Composable
private fun DownloadedGalleryCard(entry: DownloadedGallery, onOpen: () -> Unit, onSync: () -> Unit, onDelete: () -> Unit) {
    val p = Theme.palette
    val isSyncing = Downloads.activeDownloads[entry.id] != null
    val shape = RoundedCornerShape(Tokens.Radius.card)
    DownloadActionsCard(
        onOpen = onOpen,
        onDelete = onDelete,
        menu = if (entry.isSingleImage) emptyList() else listOf(Triple(tr(R.string.action_sync), Icons.Filled.Sync, onSync)),
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 72.dp).clip(shape).background(p.secondaryBackground),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(width = 96.dp, height = 72.dp).background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                Icon(galleryKindIcon(entry.resolvedKind), null, tint = p.secondaryText)
                Downloads.localCoverFile(entry)?.let { cover ->
                    AsyncImage("file://${cover.absolutePath}", null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                }
            }
            Column(
                Modifier.weight(1f).padding(horizontal = Tokens.Spacing.sm, vertical = Tokens.Spacing.sm),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    entry.displayTitle, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold),
                    color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis,
                )
                Text(gallerySubtitle(entry), style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (isSyncing) {
                Icon(
                    Icons.Outlined.StopCircle, tr(R.string.action_cancel_download), tint = StashyColors.systemRed,
                    modifier = Modifier.padding(end = Tokens.Spacing.sm).size(24.dp).clip(CircleShape)
                        .clickable { Downloads.cancelGalleryDownload(entry.id) },
                )
            }
        }
    }
}

internal fun galleryKindIcon(kind: DownloadedGallery.Kind): ImageVector = when (kind) {
    DownloadedGallery.Kind.Image -> SF.photo
    DownloadedGallery.Kind.Tag -> SF.tag
    DownloadedGallery.Kind.Gallery -> SF.photoStack
}

private fun gallerySubtitle(entry: DownloadedGallery): String {
    val parts = mutableListOf<String>()
    val total = entry.serverImageCount
    when {
        entry.isSingleImage -> parts += tr(R.string.single_image)
        total != null && total > entry.images.size -> parts += "${entry.images.size} of $total images"
        else -> parts += "${entry.images.size} image(s)"
    }
    entry.studioName?.takeIf { it.isNotEmpty() }?.let { parts += it }
    return parts.joinToString(" · ")
}

// MARK: - Share / permission

/**
 * Share sheet for a downloaded file (iOS: `UIActivityViewController`). Needs the FileProvider
 * `${applicationId}.downloads` (DownloadsFileProvider) with `res/xml/download_paths.xml` in the manifest.
 */
internal fun shareDownloadedFile(context: Context, file: File, mimeType: String) {
    val uri = runCatching { FileProvider.getUriForFile(context, "${context.packageName}.downloads", file) }.getOrNull()
        ?: run { showToast(tr(R.string.sharing_is_not_available)); return }
    val send = Intent(Intent.ACTION_SEND)
        .setType(mimeType)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    runCatching {
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }.onFailure { showToast(tr(R.string.sharing_is_not_available)) }
}

/** Android 13+: asks once for the notification permission when a download is running (progress notification). */
@Composable
private fun DownloadsNotificationPermission() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    val hasActive = Downloads.activeDownloads.isNotEmpty()
    LaunchedEffect(hasActive) {
        if (!hasActive) return@LaunchedEffect
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (granted || Prefs.bool(NOTIFICATION_ASKED_KEY)) return@LaunchedEffect
        Prefs.setBool(NOTIFICATION_ASKED_KEY, true)
        runCatching { launcher.launch(Manifest.permission.POST_NOTIFICATIONS) }
    }
}

/** Android-only flag: the notification permission was requested once. */
private const val NOTIFICATION_ASKED_KEY = "downloads_notification_permission_asked"

/**
 * iOS: `CatalogsView.downloadsPage` — the Downloads screen as a page pushed onto the Home dashboard
 * (system back / back arrow return to it). Same screen the Tools tab used to show.
 */
class DownloadsScreen : de.letzgo.stashy.ui.Screen {
    override val key = "home-downloads"

    @Composable override fun Content() = de.letzgo.stashy.ui.settings.SettingsDetailScaffold(tr(R.string.downloads)) { top ->
        DownloadsToolView(topPadding = top)
    }
}
