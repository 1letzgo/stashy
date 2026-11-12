package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.LibraryCleanupCandidate
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerTasksRepository
import de.letzgo.stashy.data.StashQueuedJob
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.tools.filters.FiltersToolView
import de.letzgo.stashy.ui.tools.merge.StudioMergeToolView
import de.letzgo.stashy.ui.tools.merge.TagMergeToolView
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.nativeAccent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS `ToolsServerView.CleanupKind`. */
private enum class CleanupKind(
    @androidx.annotation.StringRes private val titleRes: Int,
    @androidx.annotation.StringRes private val confirmRes: Int,
    @androidx.annotation.StringRes private val emptyRes: Int,
    @androidx.annotation.StringRes private val loadErrorRes: Int,
    @androidx.annotation.StringRes private val deleteErrorRes: Int,
    @androidx.annotation.StringRes private val oneRes: Int,
    @androidx.annotation.StringRes private val otherRes: Int,
    val mutation: String,
) {
    // One key per sentence and kind: an inserted noun would stay English in every translation.
    Tags(R.string.action_remove_unused_tags, R.string.confirm_remove_unused_tags, R.string.empty_unused_tags_found,
        R.string.error_load_tag_list, R.string.error_delete_unused_tags, R.string.arg_count_tag, R.string.arg_count_tags, "tagsDestroy"),
    Performers(R.string.action_remove_unused_performers, R.string.confirm_remove_unused_performers, R.string.empty_unused_performers_found,
        R.string.error_load_performer_list, R.string.error_delete_unused_performers, R.string.arg_count_performer, R.string.arg_count_performers, "performersDestroy"),
    Studios(R.string.action_remove_unused_studios, R.string.confirm_remove_unused_studios, R.string.empty_unused_studios_found,
        R.string.error_load_studio_list, R.string.error_delete_unused_studios, R.string.arg_count_studio, R.string.arg_count_studios, "studiosDestroy");

    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)
    val confirmTitle: String get() = tr(confirmRes)
    val emptyText: String get() = tr(emptyRes)
    val loadError: String get() = tr(loadErrorRes)
    val deleteError: String get() = tr(deleteErrorRes)
    /** "1 tag" / "3 performers". */
    fun counted(count: Int): String = tr(if (count == 1) oneRes else otherRes, count)
}

/** One Generate task: label, icon, `GenerateMetadataInput` flag, alert title. */
private data class GenerateTask(val label: String, val icon: ImageVector, val flag: String, val alertTitle: String = label)

private val generateTasks = listOf(
    GenerateTask(tr(R.string.scene_covers), SFS.photoFill, "covers"),
    GenerateTask(tr(R.string.video_perceptual_hashes), SFS.numberSquareFill, "phashes"),
    GenerateTask(tr(R.string.previews), SFS.playRectangleFill, "previews"),
    GenerateTask(tr(R.string.animated_image_previews), SFS.photoOnRectangle, "imagePreviews"),
    GenerateTask(tr(R.string.scene_scrubber_sprites), SFS.squareGrid3x3, "sprites"),
    GenerateTask(tr(R.string.marker_previews), SFS.mappinEllipse, "markers"),
    GenerateTask(tr(R.string.marker_animated_image_previews), SFS.mappinCircleFill, "markerImagePreviews"),
    GenerateTask(tr(R.string.marker_screenshots), SFS.cameraFill, "markerScreenshots"),
    GenerateTask(tr(R.string.transcodes), SFS.filmStack, "transcodes"),
    GenerateTask(tr(R.string.hint_generate_heatmaps_and_speeds_for), SFS.waveformEcg, "interactiveHeatmapsSpeeds", tr(R.string.action_generate_heatmaps_and_speeds)),
    GenerateTask(tr(R.string.image_clip_previews), SFS.playRectOnRectFill, "clipPreviews"),
    GenerateTask(tr(R.string.image_thumbnails), SFS.photoOnRectangle, "imageThumbnails"),
    GenerateTask(tr(R.string.image_perceptual_hashes), SFS.numberCircleFill, "imagePhashes"),
)

/**
 * iOS: `ToolsServerView(embedded: true)` — the Settings › Server section: job queue (polled
 * every 2 s), Scan & Identify, Generate, Library Cleanup and the image cache.
 */
@Composable
fun ServerTasksContent(topPadding: Dp) {
    val p = Theme.palette
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val server = ServerConfigManager.activeConfig
    var jobs by remember { mutableStateOf<List<StashQueuedJob>>(emptyList()) }
    var jobsLoaded by remember { mutableStateOf(false) }
    var stopping by remember { mutableStateOf(setOf<String>()) }
    var runningTask by remember { mutableStateOf<String?>(null) }
    var alert by remember { mutableStateOf<Pair<String, String>?>(null) }
    var cleanup by remember { mutableStateOf<Pair<CleanupKind, List<LibraryCleanupCandidate>>?>(null) }

    if (server == null) {
        Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
            Icon(SFS.serverRack, null, tint = Appearance.tint, modifier = Modifier.size(64.dp))
            Text(tr(R.string.empty_active_server), style = NativeType.titleLarge.copy(fontWeight = FontWeight.Bold), color = p.text)
            Text(tr(R.string.hint_select_server_under_main_first), style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
        }
        return
    }

    suspend fun refreshJobs() {
        val fetched = ServerTasksRepository.jobQueue() ?: return
        jobs = fetched
        jobsLoaded = true
        stopping = stopping.filter { id -> fetched.any { it.id == id } }.toSet()
    }
    LaunchedEffect(server.id) { while (true) { refreshJobs(); delay(2000) } }

    fun run(taskId: String, action: suspend () -> Pair<String, String>?) {
        runningTask = taskId
        scope.launch {
            delay(200)
            val result = action()
            runningTask = null
            result?.let { alert = it }
        }
        scope.launch { delay(1500); refreshJobs() }
    }

    @Composable
    fun TaskRow(label: String, icon: ImageVector, taskId: String, action: suspend () -> Pair<String, String>?) {
        // Material list item; the whole row and the tonal play button start the task.
        NativeListItem(label, icon = icon, onClick = { if (runningTask == null) run(taskId, action) }, trailing = {
            if (runningTask == taskId) Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { RowProgress() }
            else FilledTonalIconButton(
                { run(taskId, action) }, enabled = runningTask == null,
                colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = nativeAccent().copy(alpha = 0.16f), contentColor = p.text),
            ) { Icon(Icons.Filled.PlayArrow, tr(R.string.action_run_arg, label)) }
        })
    }

    SettingsList(topPadding) {
        settingsSection(header = tr(R.string.jobs), key = "jobs") {
            if (jobs.isEmpty()) NativeListItem(if (jobsLoaded) tr(R.string.empty_jobs_running) else tr(R.string.loading_jobs), icon = SFS.tray, iconTint = p.secondaryText, headlineColor = p.secondaryText)
            else jobs.forEachIndexed { i, job ->
                JobRow(job, job.id in stopping) {
                    stopping = stopping + job.id
                    scope.launch {
                        if (!ServerTasksRepository.stopJob(job.id)) stopping = stopping - job.id
                        refreshJobs()
                    }
                }
                if (i < jobs.lastIndex) SettingsDivider()
            }
        }
        settingsSection(header = tr(R.string.action_scan_and_identify), key = "scan") {
            TaskRow(tr(R.string.action_scan_library), SFS.arrowTriangle2Circle, "scan") { tr(R.string.action_scan_library) to ServerTasksRepository.scan().second }
            SettingsDivider()
            TaskRow(tr(R.string.action_identify), SFS.personCropSquare, "identify") { tr(R.string.action_identify) to ServerTasksRepository.identify().second }
        }
        settingsSection(header = tr(R.string.action_generate), key = "generate") {
            generateTasks.forEachIndexed { i, t ->
                TaskRow(t.label, t.icon, "gen_${t.flag}") { t.alertTitle to ServerTasksRepository.generate(t.flag).second }
                if (i < generateTasks.lastIndex) SettingsDivider()
            }
        }
        settingsSection(header = tr(R.string.library_cleanup), key = "cleanup") {
            TaskRow(tr(R.string.action_remove_unused_tags), SFS.tagSlash, "tags_unused") { findUnusedResult(CleanupKind.Tags) { cleanup = it } }
            SettingsDivider()
            TaskRow(tr(R.string.action_remove_unused_performers), SFS.personSlash, "performers_unused") { findUnusedResult(CleanupKind.Performers) { cleanup = it } }
            SettingsDivider()
            TaskRow(tr(R.string.action_remove_unused_studios), SFS.building2Circle, "studios_unused") { findUnusedResult(CleanupKind.Studios) { cleanup = it } }
        }
        // Admin-Werkzeuge (früher unter Tools), nur mit stashy+.
        if (StashyPlus.isUnlocked) {
            settingsSection(header = "stashy+", key = "stashyplus") {
                SettingsNavRow(tr(R.string.filters), SF.line3HorizontalDecreaseCircle) { Nav.push(ServerToolScreen.Filters) }
                SettingsDivider()
                SettingsNavRow(tr(R.string.action_merge_tags), SF.arrowTriangleMerge) { Nav.push(ServerToolScreen.MergeTags) }
                SettingsDivider()
                SettingsNavRow(tr(R.string.action_merge_studios), SF.building2) { Nav.push(ServerToolScreen.MergeStudios) }
            }
        }
        settingsSection(header = tr(R.string.cache), key = "cache") {
            TaskRow(tr(R.string.action_clear_image_cache), SFS.internaldrive, "cache_clear") {
                // iOS `ImageCache.shared.clearCurrentServerCache()`: the active server only.
                de.letzgo.stashy.data.ServerImageCache.clearActiveServer(context)
                tr(R.string.cache_cleared) to tr(R.string.hint_images_will_be_reloaded_from)
            }
        }
    }

    alert?.let { (t, m) -> SimpleAlert(t, m) { alert = null } }
    cleanup?.let { (kind, candidates) ->
        val preview = candidates.take(8).joinToString(", ") { it.name }
        val names = if (candidates.size > 8) tr(R.string.arg_and_arg_more, preview, candidates.size - 8) else preview
        ConfirmAlert(
            kind.confirmTitle,
            tr(R.string.hint_arg_not_used_anywhere, kind.counted(candidates.size), names),
            tr(R.string.action_delete_arg, candidates.size),
            onConfirm = {
                val ids = candidates.map { it.id }
                scope.launch {
                    alert = try {
                        val ok = ServerTasksRepository.destroy(kind.mutation, ids)
                        kind.title to if (ok) tr(R.string.arg_deleted, kind.counted(ids.size)) else tr(R.string.server_rejected_deletion)
                    } catch (e: Exception) { kind.title to kind.deleteError }
                }
            },
            onDismiss = { cleanup = null },
        )
    }
}

/** iOS: the stashy+ rows of `ToolsServerView` — Filters, Merge Tags and Merge Studios as pushed pages. */
private enum class ServerToolScreen(@androidx.annotation.StringRes private val titleRes: Int) : Screen {
    Filters(R.string.filters), MergeTags(R.string.action_merge_tags), MergeStudios(R.string.action_merge_studios);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)

    override val key get() = "settings-server-$name"

    @Composable override fun Content() = SettingsDetailScaffold(title) { top ->
        when (this) {
            Filters -> FiltersToolView(top)
            MergeTags -> TagMergeToolView(top)
            MergeStudios -> StudioMergeToolView(top)
        }
    }
}

private suspend fun findUnusedResult(kind: CleanupKind, onFound: (Pair<CleanupKind, List<LibraryCleanupCandidate>>) -> Unit): Pair<String, String>? = try {
    val unused = when (kind) {
        CleanupKind.Tags -> ServerTasksRepository.unusedTags()
        CleanupKind.Performers -> ServerTasksRepository.unusedPerformers()
        CleanupKind.Studios -> ServerTasksRepository.unusedStudios()
    }
    if (unused.isEmpty()) kind.title to kind.emptyText else { onFound(kind to unused); null }
} catch (e: Exception) {
    kind.title to kind.loadError
}

/** iOS `jobRow` — status icon, description, detail line, progress and the cancel button. */
@Composable
private fun JobRow(job: StashQueuedJob, isStopping: Boolean, onStop: () -> Unit) {
    val p = Theme.palette
    val progress = job.progress?.takeIf { job.isRunning && it >= 0 }?.coerceIn(0.0, 1.0)
    SettingsRow {
        Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
            when (job.status) {
                "RUNNING" -> CircularProgressIndicator(Modifier.size(18.dp), color = p.secondaryText, strokeWidth = 2.dp)
                "READY" -> Icon(SF.clock, null, tint = Appearance.tint)
                "FINISHED" -> Icon(SF.checkmarkCircleFill, null, tint = Color(0xFF30D158))
                "FAILED" -> Icon(SFS.exclamationTriangleFill, null, tint = Color(0xFFFF453A))
                "CANCELLED", "STOPPING" -> Icon(SFS.stopCircle, null, tint = p.secondaryText)
                else -> Icon(SFS.circle, null, tint = p.secondaryText)
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(job.description ?: tr(R.string.job_arg, job.id), style = NativeType.bodyLarge, color = p.text, maxLines = 2)
            jobDetailLine(job)?.let { Text(it, style = NativeType.bodySmall, color = p.secondaryText, maxLines = 1) }
            if (progress != null) LinearProgressIndicator({ progress.toFloat() }, Modifier.fillMaxWidth(), color = nativeAccent(), trackColor = p.separator)
        }
        if (progress != null) Text("${Math.round(progress * 100)}%", style = NativeType.bodySmall, color = p.secondaryText)
        if (job.isActive) {
            if (isStopping || job.status == "STOPPING") RowProgress()
            else IconButton(onStop) { Icon(Icons.Filled.Close, job.description?.let { tr(R.string.action_cancel_arg, it) } ?: tr(R.string.action_cancel), tint = p.secondaryText) }
        }
    }
}

/** iOS `jobDetailLine`. */
private fun jobDetailLine(job: StashQueuedJob): String? {
    job.error?.takeIf { it.isNotEmpty() }?.let { return it }
    if (job.isRunning) job.subTasks?.firstOrNull()?.takeIf { it.isNotEmpty() }?.let { return it }
    return when (job.status) {
        "READY" -> tr(R.string.queued); "STOPPING" -> tr(R.string.stopping_menu); "FINISHED" -> tr(R.string.finished); "CANCELLED" -> tr(R.string.cancelled); "FAILED" -> tr(R.string.error_generic_2)
        else -> null
    }
}
