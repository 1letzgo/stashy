package de.letzgo.stashy.ui.settings

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
private enum class CleanupKind(val title: String, val noun: String, val mutation: String) {
    Tags("Remove Unused Tags", "tags", "tagsDestroy"),
    Performers("Remove Unused Performers", "performers", "performersDestroy"),
    Studios("Remove Unused Studios", "studios", "studiosDestroy"),
}

/** One Generate task: label, icon, `GenerateMetadataInput` flag, alert title. */
private data class GenerateTask(val label: String, val icon: ImageVector, val flag: String, val alertTitle: String = label)

private val generateTasks = listOf(
    GenerateTask("Scene covers", SFS.photoFill, "covers"),
    GenerateTask("Video perceptual hashes", SFS.numberSquareFill, "phashes"),
    GenerateTask("Previews", SFS.playRectangleFill, "previews"),
    GenerateTask("Animated image previews", SFS.photoOnRectangle, "imagePreviews"),
    GenerateTask("Scene scrubber sprites", SFS.squareGrid3x3, "sprites"),
    GenerateTask("Marker previews", SFS.mappinEllipse, "markers"),
    GenerateTask("Marker animated image previews", SFS.mappinCircleFill, "markerImagePreviews"),
    GenerateTask("Marker screenshots", SFS.cameraFill, "markerScreenshots"),
    GenerateTask("Transcodes", SFS.filmStack, "transcodes"),
    GenerateTask("Generate heatmaps and speeds for interactive scenes", SFS.waveformEcg, "interactiveHeatmapsSpeeds", "Generate heatmaps and speeds"),
    GenerateTask("Image clip previews", SFS.playRectOnRectFill, "clipPreviews"),
    GenerateTask("Image thumbnails", SFS.photoOnRectangle, "imageThumbnails"),
    GenerateTask("Image perceptual hashes", SFS.numberCircleFill, "imagePhashes"),
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
            Text("No active server", style = NativeType.titleLarge.copy(fontWeight = FontWeight.Bold), color = p.text)
            Text("Select a server under Main first.", style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
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
            ) { Icon(Icons.Filled.PlayArrow, "Run $label") }
        })
    }

    SettingsList(topPadding) {
        settingsSection(header = "Jobs", key = "jobs") {
            if (jobs.isEmpty()) NativeListItem(if (jobsLoaded) "No jobs running" else "Loading jobs…", icon = SFS.tray, iconTint = p.secondaryText, headlineColor = p.secondaryText)
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
        settingsSection(header = "Scan & Identify", key = "scan") {
            TaskRow("Scan Library", SFS.arrowTriangle2Circle, "scan") { "Scan Library" to ServerTasksRepository.scan().second }
            SettingsDivider()
            TaskRow("Identify", SFS.personCropSquare, "identify") { "Identify" to ServerTasksRepository.identify().second }
        }
        settingsSection(header = "Generate", key = "generate") {
            generateTasks.forEachIndexed { i, t ->
                TaskRow(t.label, t.icon, "gen_${t.flag}") { t.alertTitle to ServerTasksRepository.generate(t.flag).second }
                if (i < generateTasks.lastIndex) SettingsDivider()
            }
        }
        settingsSection(header = "Library Cleanup", key = "cleanup") {
            TaskRow("Remove Unused Tags", SFS.tagSlash, "tags_unused") { findUnusedResult(CleanupKind.Tags) { cleanup = it } }
            SettingsDivider()
            TaskRow("Remove Unused Performers", SFS.personSlash, "performers_unused") { findUnusedResult(CleanupKind.Performers) { cleanup = it } }
            SettingsDivider()
            TaskRow("Remove Unused Studios", SFS.building2Circle, "studios_unused") { findUnusedResult(CleanupKind.Studios) { cleanup = it } }
        }
        settingsSection(header = "Cache", key = "cache") {
            TaskRow("Clear Image Cache", SFS.internaldrive, "cache_clear") {
                // iOS `ImageCache.shared.clearCurrentServerCache()`: the active server only.
                de.letzgo.stashy.data.ServerImageCache.clearActiveServer(context)
                "Cache Cleared" to "Images will be reloaded from the server."
            }
        }
    }

    alert?.let { (t, m) -> SimpleAlert(t, m) { alert = null } }
    cleanup?.let { (kind, candidates) ->
        val preview = candidates.take(8).joinToString(", ") { it.name }
        val rest = if (candidates.size > 8) " and ${candidates.size - 8} more" else ""
        ConfirmAlert(
            "Remove unused ${kind.noun}?",
            "${candidates.size} ${kind.noun} are not used anywhere: $preview$rest. Deleting them cannot be undone.",
            "Delete ${candidates.size}",
            onConfirm = {
                val ids = candidates.map { it.id }
                scope.launch {
                    alert = try {
                        val ok = ServerTasksRepository.destroy(kind.mutation, ids)
                        kind.title to if (ok) "${ids.size} unused ${kind.noun} deleted." else "The server rejected the deletion."
                    } catch (e: Exception) { kind.title to "Could not delete the ${kind.noun}." }
                }
            },
            onDismiss = { cleanup = null },
        )
    }
}

private suspend fun findUnusedResult(kind: CleanupKind, onFound: (Pair<CleanupKind, List<LibraryCleanupCandidate>>) -> Unit): Pair<String, String>? = try {
    val unused = when (kind) {
        CleanupKind.Tags -> ServerTasksRepository.unusedTags()
        CleanupKind.Performers -> ServerTasksRepository.unusedPerformers()
        CleanupKind.Studios -> ServerTasksRepository.unusedStudios()
    }
    if (unused.isEmpty()) kind.title to "No unused ${kind.noun} found." else { onFound(kind to unused); null }
} catch (e: Exception) {
    kind.title to "Could not load the ${kind.noun} list."
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
            Text(job.description ?: "Job ${job.id}", style = NativeType.bodyLarge, color = p.text, maxLines = 2)
            jobDetailLine(job)?.let { Text(it, style = NativeType.bodySmall, color = p.secondaryText, maxLines = 1) }
            if (progress != null) LinearProgressIndicator({ progress.toFloat() }, Modifier.fillMaxWidth(), color = nativeAccent(), trackColor = p.separator)
        }
        if (progress != null) Text("${Math.round(progress * 100)}%", style = NativeType.bodySmall, color = p.secondaryText)
        if (job.isActive) {
            if (isStopping || job.status == "STOPPING") RowProgress()
            else IconButton(onStop) { Icon(Icons.Filled.Close, "Cancel ${job.description ?: "job"}", tint = p.secondaryText) }
        }
    }
}

/** iOS `jobDetailLine`. */
private fun jobDetailLine(job: StashQueuedJob): String? {
    job.error?.takeIf { it.isNotEmpty() }?.let { return it }
    if (job.isRunning) job.subTasks?.firstOrNull()?.takeIf { it.isNotEmpty() }?.let { return it }
    return when (job.status) {
        "READY" -> "Queued"; "STOPPING" -> "Stopping…"; "FINISHED" -> "Finished"; "CANCELLED" -> "Cancelled"; "FAILED" -> "Failed"
        else -> null
    }
}
