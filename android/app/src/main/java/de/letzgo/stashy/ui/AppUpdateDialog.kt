package de.letzgo.stashy.ui

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
        TextButton(onClick) { Text(label, color = Appearance.tint, fontWeight = FontWeight.SemiBold) }
    }

    val (title, body, confirm, dismiss) = when (state) {
        AppUpdate.State.Checking -> Quad("Checking for Updates…", null, null, action("Cancel") { AppUpdate.dismiss() })
        is AppUpdate.State.Available -> Quad(
            "Update Available",
            "stashy " + listOfNotNull(state.versionName, state.versionCode?.let { "($it)" }).joinToString(" ").ifEmpty { "" } +
                " is available" + (state.bytes?.let { " (%.1f MB)".format(it / 1_048_576f) } ?: "") + ".",
            action("Download") { scope.launch { AppUpdate.download(context) } },
            action("Later") { AppUpdate.dismiss() },
        )
        is AppUpdate.State.Downloading -> Quad("Downloading Update…", null, null, null)
        is AppUpdate.State.ReadyToInstall -> Quad(
            "Install Update",
            "stashy ${state.versionName ?: ""} (${state.versionCode}) is ready." +
                if (AppUpdate.needsInstallPermission(context)) "\n\nAllow stashy to install apps once, then tap Install again." else "",
            action("Install") { AppUpdate.install(context) },
            action("Later") { AppUpdate.dismiss() },
        )
        AppUpdate.State.UpToDate -> Quad("You're Up to Date", "stashy ${AppUpdate.currentVersionName(context)} is the latest version.", action("OK") { AppUpdate.dismiss() }, null)
        is AppUpdate.State.Failed -> Quad("Update Failed", state.message, action("OK") { AppUpdate.dismiss() }, null)
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
