package de.letzgo.stashy.ui.setup

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerConnection
import de.letzgo.stashy.data.ServerProtocol
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import kotlinx.coroutines.launch

/** iOS: `AuthMethod`. */
enum class AuthMethod(val title: String) { ApiKey("API Key"), Login("Login"), None("None") }

/**
 * iOS: `ServerSetupWizardView` / `ServerFormViewNew` — address, protocol, port, subpath, auth;
 * a connection test must reach Stash before the server is saved.
 * [existing] edits a saved server (used from Settings → Servers).
 */
@Composable
fun ServerSetupScreen(existing: ServerConfig? = null, onDone: () -> Unit) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(existing?.name ?: "My Stash") }
    var address by remember { mutableStateOf(existing?.serverAddress ?: "") }
    var port by remember { mutableStateOf(existing?.port ?: "9999") }
    var proto by remember { mutableStateOf(existing?.serverProtocol ?: ServerProtocol.HTTP) }
    var subpath by remember { mutableStateOf(existing?.subpath ?: "") }
    var auth by remember { mutableStateOf(if (existing?.apiKey != null || existing == null) AuthMethod.ApiKey else AuthMethod.None) }
    var apiKey by remember { mutableStateOf(existing?.apiKey ?: "") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<Boolean, String>?>(null) }

    fun draft() = ServerConfig(
        id = existing?.id ?: java.util.UUID.randomUUID().toString().uppercase(),
        name = name.ifBlank { "My Stash" },
        serverAddress = address.trim().removePrefix("http://").removePrefix("https://").trimEnd('/'),
        port = port.trim().ifEmpty { null },
        serverProtocol = proto,
        subpath = subpath.trim().ifEmpty { null },
    )

    fun connect() = scope.launch {
        busy = true; status = null
        val config = draft()
        try {
            val key = when (auth) {
                AuthMethod.ApiKey -> apiKey.trim().ifEmpty { null }
                AuthMethod.Login -> ServerConnection.fetchAPIKey(config.baseURL, username, password)
                AuthMethod.None -> null
            }
            when (val outcome = ServerConnection.probe(config.baseURL, key)) {
                is ServerConnection.Outcome.Stash -> {
                    status = true to "Connected — Stash ${outcome.version}"
                    ServerConfigManager.save(config, apiKey = key)
                    ServerConfigManager.activate(config)
                    onDone()
                }
                is ServerConnection.Outcome.Failure -> status = false to outcome.message
            }
        } catch (e: Exception) {
            status = false to (e.message ?: "Unknown error")
        } finally { busy = false }
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = p.text, unfocusedTextColor = p.text,
        focusedContainerColor = p.secondaryBackground, unfocusedContainerColor = p.secondaryBackground,
        focusedBorderColor = Appearance.tint, unfocusedBorderColor = Color.Transparent,
        focusedLabelColor = p.secondaryText, unfocusedLabelColor = p.secondaryText, cursorColor = p.text,
    )
    @Composable fun field(label: String, value: String, keyboard: KeyboardType = KeyboardType.Uri, secret: Boolean = false, onChange: (String) -> Unit) =
        OutlinedTextField(
            value, onChange, Modifier.fillMaxWidth(), label = { Text(label) }, singleLine = true,
            shape = RoundedCornerShape(10.dp), colors = fieldColors,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, autoCorrectEnabled = false),
            visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        )

    Column(
        Modifier.fillMaxSize().background(p.background).statusBarsPadding().imePadding()
            .verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Spacer(Modifier.height(24.dp))
        Icon(SF.server, null, tint = p.text, modifier = Modifier.size(56.dp).align(Alignment.CenterHorizontally))
        Text(if (existing == null) "Connect to Stash" else "Edit Server", style = IosTypography.largeTitle, color = p.text, modifier = Modifier.align(Alignment.CenterHorizontally))
        Text("Enter the address of your Stash server.", style = IosTypography.subheadline, color = p.secondaryText, modifier = Modifier.align(Alignment.CenterHorizontally))
        field("Name", name, KeyboardType.Text) { name = it }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            ServerProtocol.entries.forEachIndexed { i, pr ->
                SegmentedButton(proto == pr, { proto = pr; if (port.isBlank() || port == "443" || port == "80") port = pr.defaultPort }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(pr.name) }
            }
        }
        field("Server Address (IP or Domain)", address) { address = it }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) { field("Port", port, KeyboardType.Number) { port = it } }
            Column(Modifier.weight(1f)) { field("Subpath (optional)", subpath) { subpath = it } }
        }
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            AuthMethod.entries.forEachIndexed { i, m ->
                SegmentedButton(auth == m, { auth = m }, SegmentedButtonDefaults.itemShape(i, AuthMethod.entries.size)) { Text(m.title) }
            }
        }
        when (auth) {
            AuthMethod.ApiKey -> field("API Key", apiKey, KeyboardType.Password, secret = true) { apiKey = it }
            AuthMethod.Login -> {
                field("Username", username, KeyboardType.Text) { username = it }
                field("Password", password, KeyboardType.Password, secret = true) { password = it }
            }
            AuthMethod.None -> {}
        }
        status?.let { (ok, msg) -> Text(msg, color = if (ok) Color(0xFF30D158) else Color(0xFFFF453A), style = IosTypography.footnote) }
        Button(
            { connect() }, Modifier.fillMaxWidth().height(50.dp), enabled = address.isNotBlank() && !busy,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Appearance.tint, contentColor = Color.White),
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
            else Text("Connect", style = IosTypography.headline)
        }
    }
}
