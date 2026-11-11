package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import de.letzgo.stashy.data.SettingsTransfer
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeConfirmDialog
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * iOS: `SettingsTransferControls` — "Export Settings" (with or without API keys, Storage Access
 * Framework "Create document") and "Import Settings" (SAF "Open document"). Settings shows both,
 * the setup wizard only the import ([importOnly]); [onImported] runs after a successful import.
 * File format: `docs/settings-transfer-format.md`.
 */
class SettingsTransferState {
    var showsSecretsChoice by mutableStateOf(false)
    var resultMessage by mutableStateOf<String?>(null)
    internal var includeSecrets = false
}

@Composable
fun rememberSettingsTransfer(onImported: () -> Unit = {}): Pair<SettingsTransferState, SettingsTransferLaunchers> {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state = remember { SettingsTransferState() }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val secrets = state.includeSecrets
        scope.launch {
            state.resultMessage = runCatching {
                val text = SettingsTransfer.export(secrets)
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                        ?: error("Could not write the file.")
                }
                null
            }.getOrElse { it.message ?: tr(R.string.error_export) }
        }
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            state.resultMessage = runCatching {
                val text = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } ?: error("Could not read the file.")
                }
                val summary = SettingsTransfer.importFile(text)
                Appearance.reload()
                onImported()
                tr(R.string.hint_imported_arg_server_s_and, summary.servers, summary.settings)
            }.getOrElse { it.message ?: tr(R.string.error_import) }
        }
    }
    return state to SettingsTransferLaunchers(
        export = { secrets -> state.includeSecrets = secrets; exporter.launch(SettingsTransfer.defaultFileName()) },
        import = { importer.launch(arrayOf("application/json", "text/plain", "application/octet-stream")) },
    )
}

class SettingsTransferLaunchers(val export: (includeSecrets: Boolean) -> Unit, val import: () -> Unit)

/** The export choice and the result alert of [rememberSettingsTransfer]. */
@Composable
fun SettingsTransferDialogs(state: SettingsTransferState, launchers: SettingsTransferLaunchers) {
    val p = Theme.palette
    if (state.showsSecretsChoice) AlertDialog(
        onDismissRequest = { state.showsSecretsChoice = false },
        containerColor = p.secondaryBackground, titleContentColor = p.text, textContentColor = p.secondaryText,
        title = { Text(tr(R.string.confirm_include_api_keys), style = NativeType.headlineSmall) },
        text = {
            Column(Modifier.fillMaxWidth()) {
                Text(tr(R.string.hint_with_api_keys_file_gives), style = NativeType.bodyMedium)
                TextButton({ state.showsSecretsChoice = false; launchers.export(false) }) {
                    Text(tr(R.string.without_api_keys), color = de.letzgo.stashy.ui.textAccent(), style = NativeType.labelLarge)
                }
                TextButton({ state.showsSecretsChoice = false; launchers.export(true) }) {
                    Text(tr(R.string.with_api_keys_and_headers), color = de.letzgo.stashy.ui.textAccent(), style = NativeType.labelLarge)
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton({ state.showsSecretsChoice = false }) { Text(tr(R.string.action_cancel), color = de.letzgo.stashy.ui.textAccent(), style = NativeType.labelLarge) } },
    )
    state.resultMessage?.let { message ->
        NativeConfirmDialog(tr(R.string.settings), message, onDismiss = { state.resultMessage = null }, dismissLabel = null)
    }
}

/** Settings main page: "Backup & Transfer" section. */
fun androidx.compose.foundation.lazy.LazyListScope.settingsTransferSection() {
    settingsSection(
        header = tr(R.string.backup_and_transfer), key = "settings-transfer",
        footer = tr(R.string.hint_servers_settings_default_filters_dashboard),
    ) {
        val (state, launchers) = rememberSettingsTransfer()
        NativeListItem(tr(R.string.action_export_settings), icon = Icons.Outlined.FileUpload, onClick = { state.showsSecretsChoice = true })
        SettingsDivider()
        NativeListItem(tr(R.string.action_import_settings), icon = Icons.Outlined.FileDownload, onClick = launchers.import)
        SettingsTransferDialogs(state, launchers)
    }
}
