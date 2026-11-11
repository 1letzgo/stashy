package de.letzgo.stashy.ui.setup

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.outlined.FileDownload
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
enum class AuthMethod(val title: String) { None(tr(R.string.none)), Login("Login"), ApiKey(tr(R.string.api_key)) }

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
    var serverName by remember { mutableStateOf(existing?.name ?: tr(R.string.my_stash)) }
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
        NativeTopBar(tr(R.string.server_setup), onBack = if (step > 1) ({ step--; test = TestState.NotTested }) else null)
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
                    Text(tr(R.string.server_details), style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                    Text(tr(R.string.enter_your_stash_server_information), style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                }
                Spacer(Modifier.height(8.dp))
                // App language (beta): preset to the device language on a fresh install; a change restarts the app.
                Labeled(tr(R.string.app_language)) {
                    val context = androidx.compose.ui.platform.LocalContext.current
                    val selection = remember { de.letzgo.stashy.AppLanguage.stored }
                    val codes = listOf(de.letzgo.stashy.AppLanguage.SYSTEM) + de.letzgo.stashy.AppLanguage.options.map { it.first }
                    de.letzgo.stashy.ui.settings.SettingsPickerRow(tr(R.string.language), codes, selection, { de.letzgo.stashy.AppLanguage.name(it) }, de.letzgo.stashy.ui.SFS.globe) { code ->
                        if (code != selection) de.letzgo.stashy.AppLanguage.selectAndRestart(context, code)
                    }
                }
                PlainTextField(serverName, { serverName = it }, tr(R.string.my_stash), label = tr(R.string.server_name))
                Labeled(tr(R.string.protocol)) { Segmented(ServerProtocol.entries, proto, { it.name }) { proto = it } }
                NativeTextField(
                    address, { v ->
                        val (detected, rest) = ServerAddress.detectProtocol(v)
                        if (detected != null) { proto = detected; address = if (rest.isNotEmpty()) rest else v } else address = v
                    }, tr(R.string.server_address),
                    placeholder = tr(R.string.n192_168_1_100_9999_or), keyboard = KeyboardType.Uri,
                    supportingText = tr(R.string.hint_enter_address_e_g_timeout),
                )
                // Authentication card
                Column(Modifier.fillMaxWidth().background(p.secondaryBackground, NativeGroupShape).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Labeled(tr(R.string.authentication)) { Segmented(AuthMethod.entries, auth, { it.title }) { auth = it } }
                    when (auth) {
                        AuthMethod.Login -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            PlainTextField(username, { username = it }, tr(R.string.username))
                            PlainTextField(password, { password = it }, tr(R.string.password), secret = true)
                            PrimaryButton(tr(R.string.action_fetch_api_key), enabled = username.isNotEmpty() && password.isNotEmpty() && !fetchingKey, busy = fetchingKey) { fetchKey() }
                            loginError?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF453A)) }
                        }
                        AuthMethod.ApiKey -> PlainTextField(apiKey, { apiKey = it }, tr(R.string.enter_api_key), secret = true, label = tr(R.string.api_key))
                        AuthMethod.None -> {}
                    }
                }
                // Custom headers card (collapsed by default)
                Column(Modifier.fillMaxWidth().background(p.secondaryBackground, NativeGroupShape).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(Modifier.fillMaxWidth().clickable { showsHeaders = !showsHeaders }, verticalAlignment = Alignment.CenterVertically) {
                        Text(tr(R.string.custom_headers), style = NativeType.titleSmall, color = p.text)
                        val n = usableHeaders().size
                        if (n > 0) Text("  $n", style = NativeType.labelSmall.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText)
                        Spacer(Modifier.weight(1f))
                        Icon(if (showsHeaders) SFS.chevronUp else SFS.chevronDown, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
                    }
                    if (showsHeaders) {
                        headers.forEachIndexed { i, h ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    PlainTextField(h.name, { headers[i] = h.copy(name = it) }, tr(R.string.header_name), monospaced = true)
                                    PlainTextField(h.value, { headers[i] = h.copy(value = it) }, tr(R.string.value), secret = true)
                                    headerProblem(h)?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF9F0A)) }
                                }
                                IconButton({ headers.removeAt(i) }) { Icon(SFS.minusCircleFill, tr(R.string.action_remove_header), tint = StashyColors.systemRed) }
                            }
                        }
                        NativeTonalButton(tr(R.string.action_add_header), leading = SFS.plusCircleFill) { headers.add(HeaderDraft()) }
                        Text(tr(R.string.hint_sent_with_every_request_to), style = NativeType.labelSmall, color = p.secondaryText)
                    }
                }
                // First setup only: bring servers and settings over from another device. With an
                // active server after the import, the shell leaves setup by itself.
                if (existing == null) {
                    val (transfer, launchers) = de.letzgo.stashy.ui.settings.rememberSettingsTransfer {
                        if (de.letzgo.stashy.data.ServerConfigManager.activeConfig != null) onDone()
                    }
                    NativeTonalButton(tr(R.string.action_import_settings), Modifier.fillMaxWidth(), leading = androidx.compose.material.icons.Icons.Outlined.FileDownload, onClick = launchers.import)
                    Text(tr(R.string.hint_servers_and_settings_exported_from), style = NativeType.labelSmall, color = p.secondaryText)
                    de.letzgo.stashy.ui.settings.SettingsTransferDialogs(transfer, launchers)
                }
                Spacer(Modifier.height(32.dp))
            } else {
                LaunchedEffect(Unit) { if (test == TestState.NotTested) runTest() }
                Column(Modifier.fillMaxSize().padding(horizontal = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically)) {
                    when (val t = test) {
                        TestState.NotTested, TestState.Testing -> {
                            if (t == TestState.Testing) CircularProgressIndicator(Modifier.size(48.dp), color = Appearance.tint)
                            else Icon(SFS.antenna, null, tint = Appearance.tint, modifier = Modifier.size(60.dp))
                            Text(if (t == TestState.Testing) "Connecting..." else tr(R.string.action_test_connection), style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text(tr(R.string.hint_were_checking_if_your_server), style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                        }
                        TestState.Success -> {
                            Icon(SF.checkmarkCircleFill, null, tint = Color(0xFF30D158), modifier = Modifier.size(80.dp))
                            Text(tr(R.string.connection_successful), style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text(tr(R.string.your_stash_server_was_found), style = NativeType.bodyLarge, color = p.secondaryText)
                        }
                        is TestState.Failure -> {
                            Icon(SFS.xmarkCircleFill, null, tint = Color(0xFFFF453A), modifier = Modifier.size(80.dp))
                            Text(tr(R.string.error_connection), style = NativeType.headlineSmall.copy(fontWeight = FontWeight.Bold), color = p.text)
                            Text(t.message, style = NativeType.bodyLarge, color = p.secondaryText, textAlign = TextAlign.Center)
                            NativeTonalButton(tr(R.string.action_test_again), leading = SF.arrowClockwise) { runTest() }
                        }
                    }
                }
            }
        }
        // Navigation buttons
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (step > 1) NativeTonalButton(tr(R.string.back), Modifier.weight(1f), leading = SFS.chevronLeft) { step--; test = TestState.NotTested }
            PrimaryButton(
                if (step == 2) tr(R.string.finish) else tr(R.string.next), Modifier.weight(1f), enabled = canProceed,
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


