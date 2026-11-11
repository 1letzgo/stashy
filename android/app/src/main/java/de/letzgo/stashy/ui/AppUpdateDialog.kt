package de.letzgo.stashy.ui

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.AppUpdate
import kotlinx.coroutines.launch

/** Dialog for [AppUpdate] (sideload builds). Shown above everything by [AppShell]. */
@Composable
fun AppUpdateDialog() {
    if (!AppUpdate.showsDialog) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val p = Theme.palette
    val state = AppUpdate.state

    fun action(label: String, onClick: () -> Unit) = @Composable {
        TextButton(onClick) { Text(label, color = de.letzgo.stashy.ui.textAccent(), fontWeight = FontWeight.SemiBold) }
    }

    val (title, body, confirm, dismiss) = when (state) {
        AppUpdate.State.Checking -> Quad(tr(R.string.checking_for_updates_menu), null, null, action(tr(R.string.action_cancel)) { AppUpdate.dismiss() })
        is AppUpdate.State.Available -> Quad(
            tr(R.string.action_update_available),
            "stashy " + listOfNotNull(state.versionName, state.versionCode?.let { "($it)" }).joinToString(" ").ifEmpty { "" } +
                " is available" + (state.bytes?.let { " (%.1f MB)".format(it / 1_048_576f) } ?: "") + ".",
            action(tr(R.string.action_download)) { scope.launch { AppUpdate.download(context) } },
            action(tr(R.string.later)) { AppUpdate.dismiss() },
        )
        is AppUpdate.State.Downloading -> Quad(tr(R.string.downloading_update_menu), null, null, null)
        is AppUpdate.State.ReadyToInstall -> Quad(
            tr(R.string.install_update),
            "stashy ${state.versionName ?: ""} (${state.versionCode}) is ready." +
                if (AppUpdate.needsInstallPermission(context)) tr(R.string.hint_allow_stashy_to_install_apps) else "",
            action(tr(R.string.install)) { AppUpdate.install(context) },
            action(tr(R.string.later)) { AppUpdate.dismiss() },
        )
        AppUpdate.State.UpToDate -> Quad(tr(R.string.youre_up_to_date), tr(R.string.hint_stashy_arg_is_latest_version, AppUpdate.currentVersionName(context)), action(tr(R.string.ok)) { AppUpdate.dismiss() }, null)
        is AppUpdate.State.Failed -> Quad(tr(R.string.error_update), state.message, action(tr(R.string.ok)) { AppUpdate.dismiss() }, null)
        AppUpdate.State.Idle -> return
    }

    AlertDialog(
        onDismissRequest = { if (state !is AppUpdate.State.Downloading) AppUpdate.dismiss() },
        containerColor = p.secondaryBackground,
        shape = RoundedCornerShape(14.dp),
        title = { Text(title, style = IosTypography.headline, color = p.text) },
        text = {
            Column {
                body?.let { Text(it, style = IosTypography.subheadline, color = p.secondaryText) }
                if (state is AppUpdate.State.Downloading || state is AppUpdate.State.Checking) {
                    val progress = (state as? AppUpdate.State.Downloading)?.progress
                    val mod = Modifier.fillMaxWidth().padding(top = 12.dp)
                    if (progress != null) LinearProgressIndicator(progress = { progress }, modifier = mod, color = Appearance.tint)
                    else LinearProgressIndicator(modifier = mod, color = Appearance.tint)
                }
            }
        },
        confirmButton = { confirm?.invoke() },
        dismissButton = { dismiss?.invoke() },
    )
}

private data class Quad(
    val title: String,
    val body: String?,
    val confirm: (@Composable () -> Unit)?,
    val dismiss: (@Composable () -> Unit)?,
)
