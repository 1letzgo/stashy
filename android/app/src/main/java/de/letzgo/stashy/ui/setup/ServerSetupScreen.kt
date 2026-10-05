package de.letzgo.stashy.ui.setup

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerAddress
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerConnection
import de.letzgo.stashy.data.ServerProtocol
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeGroupShape
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.NativeTonalButton
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.nativeAccent
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.settings.HeaderDraft
import de.letzgo.stashy.ui.settings.PlainTextField
import de.letzgo.stashy.ui.settings.PrimaryButton
import de.letzgo.stashy.ui.settings.Segmented
import de.letzgo.stashy.ui.settings.headerProblem
import kotlinx.coroutines.launch

/** iOS: `AuthMethod` (order and titles identical). */
enum class AuthMethod(val title: String) { None("None"), Login("Login"), ApiKey("API Key") }

private sealed interface TestState {
    data object NotTested : TestState
    data object Testing : TestState
    data object Success : TestState
    data class Failure(val message: String) : TestState
}

/**
 * iOS: `ServerSetupWizardView` — first-run setup in two steps: server details (name, protocol,
 * address, auth, collapsible custom headers) → connection test; Finish saves and activates.
 * Editing a saved server uses `ServerFormScreen` (Settings), so [existing] is only a prefill.
 */
@Composable
fun ServerSetupScreen(existing: ServerConfig? = null, onDone: () -> Unit) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    var step by remember { mutableIntStateOf(1) }
    var serverName by remember { mutableStateOf(existing?.name ?: "My Stash") }
    var address by remember { mutableStateOf(existing?.let { ServerAddress.display(it) } ?: "") }
    var proto by remember { mutableStateOf(existing?.serverProtocol ?: ServerProtocol.HTTPS) }
    var auth by remember { mutableStateOf(AuthMethod.None) }
    var apiKey by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var fetchingKey by remember { mutableStateOf(false) }
    var loginError by remember { mutableStateOf<String?>(null) }
    var test by remember { mutableStateOf<TestState>(TestState.NotTested) }
    var showsHeaders by remember { mutableStateOf(false) }
    val headers = remember { mutableStateListOf<HeaderDraft>() }

    fun usableHeaders() = headers.map { it.toHeader() }.filter { it.isUsable }
    fun buildConfig(): ServerConfig {
        val parsed = ServerAddress.parse(address)
        return ServerConfig(name = serverName, serverAddress = parsed.host, port = parsed.port, serverProtocol = proto, subpath = parsed.subpath)
    }
    fun runTest() = scope.launch {
        test = TestState.Testing
        val key = apiKey.takeIf { auth != AuthMethod.None && it.isNotBlank() }
        test = when (val o = ServerConnection.probe(buildConfig().baseURL, key, usableHeaders())) {
            is ServerConnection.Outcome.Stash -> TestState.Success
            is ServerConnection.Outcome.Failure -> TestState.Failure(o.message)
        }
    }
    fun cleanAddress() { ServerAddress.detectProtocol(address).let { (pr, a) -> pr?.let { proto = it }; address = a } }
    fun complete() {
        val config = buildConfig()
        ServerConfigManager.save(config, apiKey = apiKey.trim().ifEmpty { null }.takeIf { auth != AuthMethod.None }, headers = usableHeaders())
        ServerConfigManager.activate(config)
        onDone()
    }
    fun fetchKey() = scope.launch {
        fetchingKey = true; loginError = null
        try {
            apiKey = ServerConnection.fetchAPIKey(buildConfig().baseURL, username, password, usableHeaders())
            auth = AuthMethod.ApiKey; username = ""; password = ""
            step = 2
        } catch (e: Exception) { loginError = e.message }
        fetchingKey = false
    }
    val canProceed = when (step) { 1 -> address.isNotEmpty() && serverName.isNotEmpty(); else -> test == TestState.Success }

    Column(Modifier.fillMaxSize().background(p.background).navigationBarsPadding().imePadding()) {
        // Material top app bar; on step 2 its back arrow returns to the details.
        NativeTopBar("Server Setup", onBack = if (step > 1) ({ step--; test = TestState.NotTested }) else null)
        // Step progress (Material linear indicator).
        LinearProgressIndicator(
            progress = { step / 2f },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 4.dp),
            color = nativeAccent(), trackColor = p.separator,
        )
        AnimatedContent(step, Modifier.weight(1f), transitionSpec = {
            if (targetState > initialState) slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
            else slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
        }, label = "wizard") { s ->
            if (s == 1) Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.fillMaxWidth().padding(top = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(SFS.serverRack, null, tint = Appearance.tint, modifier = Modifier.size(50.dp))
                    Text("Server Details", style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                    Text("Enter your Stash server information", style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                }
                Spacer(Modifier.height(8.dp))
                PlainTextField(serverName, { serverName = it }, "My Stash", label = "Server Name")
                Labeled("Protocol") { Segmented(ServerProtocol.entries, proto, { it.name }) { proto = it } }
                NativeTextField(
                    address, { v ->
                        val (detected, rest) = ServerAddress.detectProtocol(v)
                        if (detected != null) { proto = detected; address = if (rest.isNotEmpty()) rest else v } else address = v
                    }, "Server Address",
                    placeholder = "192.168.1.100:9999 or stash.example.com/stash", keyboard = KeyboardType.Uri,
                    supportingText = "Enter address (e.g. timeout.com:9999 or example.com/stash)",
                )
                // Authentication card
                Column(Modifier.fillMaxWidth().background(p.secondaryBackground, NativeGroupShape).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Labeled("Authentication") { Segmented(AuthMethod.entries, auth, { it.title }) { auth = it } }
                    when (auth) {
                        AuthMethod.Login -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            PlainTextField(username, { username = it }, "Username")
                            PlainTextField(password, { password = it }, "Password", secret = true)
                            PrimaryButton("Fetch API Key", enabled = username.isNotEmpty() && password.isNotEmpty() && !fetchingKey, busy = fetchingKey) { fetchKey() }
                            loginError?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF453A)) }
                        }
                        AuthMethod.ApiKey -> PlainTextField(apiKey, { apiKey = it }, "Enter API Key", secret = true, label = "API Key")
                        AuthMethod.None -> {}
                    }
                }
                // Custom headers card (collapsed by default)
                Column(Modifier.fillMaxWidth().background(p.secondaryBackground, NativeGroupShape).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(Modifier.fillMaxWidth().clickable { showsHeaders = !showsHeaders }, verticalAlignment = Alignment.CenterVertically) {
                        Text("Custom Headers", style = NativeType.titleSmall, color = p.text)
                        val n = usableHeaders().size
                        if (n > 0) Text("  $n", style = NativeType.labelSmall.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText)
                        Spacer(Modifier.weight(1f))
                        Icon(if (showsHeaders) SFS.chevronUp else SFS.chevronDown, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
                    }
                    if (showsHeaders) {
                        headers.forEachIndexed { i, h ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    PlainTextField(h.name, { headers[i] = h.copy(name = it) }, "Header name", monospaced = true)
                                    PlainTextField(h.value, { headers[i] = h.copy(value = it) }, "Value", secret = true)
                                    headerProblem(h)?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF9F0A)) }
                                }
                                IconButton({ headers.removeAt(i) }) { Icon(SFS.minusCircleFill, "Remove header", tint = StashyColors.systemRed) }
                            }
                        }
                        NativeTonalButton("Add Header", leading = SFS.plusCircleFill) { headers.add(HeaderDraft()) }
                        Text("Sent with every request to this server, e.g. for SSO or a reverse proxy that needs its own token.", style = NativeType.labelSmall, color = p.secondaryText)
                    }
                }
                Spacer(Modifier.height(32.dp))
            } else {
                LaunchedEffect(Unit) { if (test == TestState.NotTested) runTest() }
                Column(Modifier.fillMaxSize().padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
                    when (val t = test) {
                        TestState.NotTested, TestState.Testing -> {
                            if (t == TestState.Testing) CircularProgressIndicator(Modifier.size(48.dp), color = Appearance.tint)
                            else Icon(SFS.antenna, null, tint = Appearance.tint, modifier = Modifier.size(60.dp))
                            Text(if (t == TestState.Testing) "Connecting..." else "Test Connection", style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text("We're checking if your server is reachable", style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                        }
                        TestState.Success -> {
                            Icon(SF.checkmarkCircleFill, null, tint = Color(0xFF30D158), modifier = Modifier.size(80.dp))
                            Text("Connection successful!", style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text("Your Stash server was found", style = NativeType.bodyLarge, color = p.secondaryText)
                        }
                        is TestState.Failure -> {
                            Icon(SFS.xmarkCircleFill, null, tint = Color(0xFFFF453A), modifier = Modifier.size(80.dp))
                            Text("Connection failed", style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text(t.message, style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                            NativeTonalButton("Test again", leading = SF.arrowClockwise) { runTest() }
                        }
                    }
                }
            }
        }
        // Navigation buttons
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (step > 1) NativeTonalButton("Back", Modifier.weight(1f), leading = SFS.chevronLeft) { step--; test = TestState.NotTested }
            PrimaryButton(
                if (step == 2) "Finish" else "Next", Modifier.weight(1f), enabled = canProceed,
                trailing = if (step == 2) SFS.checkmark else SFS.chevronRight,
            ) { if (step < 2) { cleanAddress(); step++ } else complete() }
        }
    }
}

@Composable
private fun Labeled(label: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = NativeType.bodySmall, color = Theme.palette.secondaryText)
        content()
    }
}


