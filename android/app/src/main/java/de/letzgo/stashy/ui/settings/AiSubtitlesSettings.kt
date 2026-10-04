package de.letzgo.stashy.ui.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.player.ai.CaptionTranslator
import de.letzgo.stashy.ui.player.ai.SpeechModelStore
import de.letzgo.stashy.ui.player.ai.SubtitleTargetLanguage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: `StashyPlusAISubtitlesSettings` — "My subtitle language" (`stashy_subtitle_target_language`).
 * On iOS the speech and translation packs are managed by the system; on Android they are the
 * app's own files, so a second row frees that space again.
 */
@Composable
fun AiSubtitlesSettingsRows() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var language by remember { mutableStateOf(SubtitleTargetLanguage.load()) }
    val options = remember { SubtitleTargetLanguage.pickerOptions() }
    SettingsPickerRow("My subtitle language", options.map { it.first }, language, { id -> options.firstOrNull { it.first == id }?.second ?: id }, Icons.Filled.ClosedCaption) {
        language = it
        SubtitleTargetLanguage.persist(it)
    }
    SettingsDivider()
    var bytes by remember { mutableLongStateOf(0L) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { bytes = withContext(Dispatchers.IO) { SpeechModelStore.installedBytes(context) } }
    SettingsNavRow(
        "Delete downloaded language packs", Icons.Outlined.Delete,
        trailing = if (bytes > 0) "${bytes / 1_000_000} MB" else null,
    ) { confirm = true }
    if (confirm) AlertDialog(
        onDismissRequest = { confirm = false },
        title = { Text("Delete language packs?") },
        text = { Text("Removes the downloaded speech models and translation packs. AI subtitles download them again when needed.") },
        confirmButton = {
            TextButton({
                confirm = false
                scope.launch {
                    withContext(Dispatchers.IO) { SpeechModelStore.deleteAll(context) }
                    CaptionTranslator.deleteAllModels()
                    bytes = 0
                }
            }) { Text("Delete", color = StashyColors.systemRed) }
        },
        dismissButton = { TextButton({ confirm = false }) { Text("Cancel") } },
    )
}
