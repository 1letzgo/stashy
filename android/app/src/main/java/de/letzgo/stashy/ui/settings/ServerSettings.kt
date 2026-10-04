package de.letzgo.stashy.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import de.letzgo.stashy.ui.Chevron
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerAddress
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerConnection
import de.letzgo.stashy.data.ServerHTTPHeader
import de.letzgo.stashy.data.ServerProtocol
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Secrets
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.setup.AuthMethod
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

/** Connection state of the active server (iOS `viewModel.isServerConnected` / `serverStatus`). */
object ActiveServerStatus {
    var isConnected by mutableStateOf<Boolean?>(null); private set
    var statusText by mutableStateOf("Not connected"); private set
    private var testedFor: String? = null

    /** iOS `testConnection(force:)`. */
    suspend fun test(force: Boolean = false) {
        val config = ServerConfigManager.activeConfig ?: run { isConnected = null; statusText = "Not connected"; return }
        if (!force && testedFor == config.id && isConnected != null) return
        testedFor = config.id
        when (val o = ServerConnection.probe(config.baseURL, config.apiKey, config.customHeaders)) {
            is ServerConnection.Outcome.Stash -> { isConnected = true; statusText = "Connected (v${o.version.removePrefix("v")})" }
            is ServerConnection.Outcome.Failure -> { isConnected = false; statusText = o.message }
        }
    }

    fun reset() { isConnected = null; testedFor = null; statusText = "Not connected" }
}

/** iOS `ServerListRow.onConnect` / `ServerDetailView.connectServer`: activate and reset all stacks. */
fun connectServer(server: ServerConfig) {
    ServerConfigManager.activate(server)
    ActiveServerStatus.reset()
    MainTab.entries.forEach { Nav.popToRoot(it) }
}

/** iOS: `ServerListSection` — saved servers with status dot, plus "Add New Server". */
fun androidx.compose.foundation.lazy.LazyListScope.serverListSection() {
    settingsSection(header = "Servers", key = "servers") {
        LaunchedEffect(ServerConfigManager.activeConfig?.id) { ActiveServerStatus.test() }
        ServerConfigManager.savedServers.forEach { server ->
            ServerListRow(server)
            SettingsDivider()
        }
        SettingsRow(onClick = { Nav.push(ServerFormScreen(null)) }) { SettingsLabel("Add New Server", SF.plus, color = Appearance.tint) }
    }
}

@Composable
private fun ServerListRow(server: ServerConfig) {
    val p = Theme.palette
    val active = ServerConfigManager.activeConfig?.id == server.id
    val dot = when {
        !active -> Color.Gray.copy(alpha = 0.3f)
        ActiveServerStatus.isConnected == true -> Color(0xFF30D158)
        else -> Color(0xFFFFD60A)
    }
    Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).clickable { if (!active) connectServer(server) }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(9.dp).background(dot, CircleShape))
            Spacer(Modifier.width(12.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(server.name, style = IosTypography.headline, color = p.text)
                Text(server.baseURL, style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Box(Modifier.clickable { Nav.push(ServerDetailScreen(server.id)) }.padding(horizontal = 16.dp, vertical = 18.dp)) {
            Icon(androidx.compose.material.icons.Icons.Chevron, null, tint = p.tertiaryText, modifier = Modifier.size(20.dp))
        }
    }
}

/** iOS: `ServerDetailView`. */
class ServerDetailScreen(private val serverId: String) : Screen {
    override val key = "server-detail-$serverId"

    @Composable override fun Content() {
        val server = ServerConfigManager.savedServers.firstOrNull { it.id == serverId }
        if (server == null) { LaunchedEffect(Unit) { Nav.pop() }; return }
        val active = ServerConfigManager.activeConfig?.id == server.id
        val scope = rememberCoroutineScope()
        var connecting by remember { mutableStateOf(false) }
        var confirmDelete by remember { mutableStateOf(false) }
        LaunchedEffect(active) { if (active) ActiveServerStatus.test() }

        SettingsDetailScaffold(server.name, trailing = {
            if (active && ActiveServerStatus.isConnected == true) Box(Modifier.size(10.dp).background(Color(0xFF30D158), CircleShape))
        }) { top ->
            SettingsList(top) {
                settingsSection(header = "Server Information", key = "info") {
                    ValueRow("Name", server.name); SettingsDivider()
                    ValueRow("URL", server.baseURL); SettingsDivider()
                    ValueRow("Protocol", server.serverProtocol.name)
                    if (active) {
                        SettingsDivider()
                        SettingsRow {
                            Text("Status", style = IosTypography.body, color = Theme.palette.text, modifier = Modifier.weight(1f))
                            Text(ActiveServerStatus.statusText, style = IosTypography.body, color = if (ActiveServerStatus.isConnected == true) Color(0xFF30D158) else Color(0xFFFF453A), maxLines = 2)
                        }
                    }
                }
                if (!active) settingsSection(key = "connect") {
                    SettingsRow {
                        SettingsLabel("Connect to Server", SFS.power, iconTint = Theme.palette.text)
                        if (connecting) RowProgress()
                        else Icon(SFS.playCircleFill, null, tint = Appearance.tint, modifier = Modifier.size(28.dp).clickable {
                            connecting = true
                            connectServer(server)
                            scope.launch { ActiveServerStatus.test(force = true); connecting = false }
                        })
                    }
                }
                settingsSection(header = "Server Configuration", key = "config") {
                    SettingsRow(onClick = { Nav.push(ServerFormScreen(server.id)) }) { SettingsLabel("Edit Configuration", SF.pencil, iconTint = Theme.palette.text) }
                    SettingsDivider()
                    SettingsRow(onClick = { confirmDelete = true }) { SettingsLabel("Delete Server", SF.trash, color = Appearance.tint) }
                }
            }
        }
        if (confirmDelete) ConfirmAlert(
            "Delete Server", "Are you sure you want to delete this server configuration? This action cannot be undone.", "Delete",
            onConfirm = { ServerConfigManager.delete(server); Nav.pop() }, onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
private fun ValueRow(title: String, value: String) = SettingsRow {
    Text(title, style = IosTypography.body, color = Theme.palette.text)
    Text(value, style = IosTypography.body, color = Theme.palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.End)
}

/** iOS-like plain text field for grouped rows (placeholder in tertiary text). */
@Composable
fun PlainTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    secret: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    monospaced: Boolean = false,
) {
    val p = Theme.palette
    BasicTextField(
        value, onChange, modifier.fillMaxWidth(), singleLine = true,
        textStyle = IosTypography.body.copy(color = p.text, fontFamily = if (monospaced) FontFamily.Monospace else null),
        cursorBrush = SolidColor(Appearance.tint),
        keyboardOptions = KeyboardOptions(keyboardType = if (secret) KeyboardType.Password else keyboard, autoCorrectEnabled = false),
        visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) Text(placeholder, style = IosTypography.body, color = p.tertiaryText, maxLines = 1)
                inner()
            }
        },
    )
}

/** iOS segmented `Picker`. */
@Composable
fun <T> Segmented(options: List<T>, selected: T, label: (T) -> String, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    val p = Theme.palette
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, o ->
            SegmentedButton(
                selected = o == selected, onClick = { onSelect(o) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                icon = {},
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = p.separator.copy(alpha = 0.6f), activeContentColor = p.text,
                    inactiveContainerColor = Color.Transparent, inactiveContentColor = p.text,
                    activeBorderColor = p.separator, inactiveBorderColor = p.separator,
                ),
            ) { Text(label(o), style = IosTypography.footnote.copy(fontWeight = FontWeight.SemiBold), maxLines = 1) }
        }
    }
}

/** Header rows being edited (iOS `ServerHTTPHeader` list binding). */
data class HeaderDraft(val id: String = java.util.UUID.randomUUID().toString().uppercase(), val name: String = "", val value: String = "") {
    fun toHeader() = ServerHTTPHeader(id, name.trim(), value.trim())
}

fun loadHeaderDrafts(serverId: String?): List<HeaderDraft> =
    serverId?.let { Secrets.get("headers_$it") }?.let {
        runCatching { Json.decodeFromString(ListSerializer(ServerHTTPHeader.serializer()), it) }.getOrNull()
    }.orEmpty().map { HeaderDraft(it.id, it.name, it.value) }

/** iOS `ServerCustomHeadersEditor.problem(for:)`. */
fun headerProblem(h: HeaderDraft): String? {
    val name = h.name.trim()
    if (name.isEmpty() && h.value.trim().isEmpty()) return null
    if (name.isEmpty()) return "Enter a header name."
    if (name.lowercase() in ServerHTTPHeader.reservedNames) return "$name is managed by the app and can't be set."
    if (h.value.trim().isEmpty()) return "Enter a value."
    if (!h.toHeader().isUsable) return "Header names may only contain letters, digits and - _ . ! # $ % & ' * + ^ ` | ~"
    return null
}

/** iOS: `ServerCustomHeadersEditor` rows (inside a settings group). */
@Composable
fun HeadersEditorRows(headers: SnapshotStateList<HeaderDraft>) {
    headers.forEachIndexed { index, h ->
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PlainTextField(h.name, { headers[index] = h.copy(name = it) }, "Header name", Modifier.weight(1f), monospaced = true)
                Icon(SFS.minusCircleFill, "Remove header", tint = Color(0xFFFF453A), modifier = Modifier.size(22.dp).clickable { headers.removeAt(index) })
            }
            PlainTextField(h.value, { headers[index] = h.copy(value = it) }, "Value", secret = true)
            headerProblem(h)?.let { Text(it, style = IosTypography.caption, color = Color(0xFFFF9F0A)) }
        }
        SettingsDivider()
    }
    SettingsRow(onClick = { headers.add(HeaderDraft()) }) { SettingsLabel("Add Header", SFS.plusCircleFill, color = Appearance.tint) }
}

/**
 * iOS: `ServerFormViewNew` — add or edit a server with live connection test, login → API key,
 * and custom headers. [serverId] null = add.
 */
class ServerFormScreen(private val serverId: String?) : Screen {
    override val key = "server-form-${serverId ?: "new"}"

    @Composable override fun Content() {
        val existing = remember { serverId?.let { id -> ServerConfigManager.savedServers.firstOrNull { it.id == id } } }
        val scope = rememberCoroutineScope()
        var name by remember { mutableStateOf(existing?.name ?: "My Stash") }
        var address by remember { mutableStateOf(existing?.let { ServerAddress.display(it) } ?: "") }
        var proto by remember { mutableStateOf(existing?.serverProtocol ?: ServerProtocol.HTTPS) }
        var apiKey by remember { mutableStateOf(existing?.apiKey ?: "") }
        var auth by remember { mutableStateOf(if (existing?.apiKey != null) AuthMethod.ApiKey else AuthMethod.None) }
        var username by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var fetchingKey by remember { mutableStateOf(false) }
        var loginError by remember { mutableStateOf<String?>(null) }
        var testing by remember { mutableStateOf(false) }
        var testResult by remember { mutableStateOf<Boolean?>(null) }
        var testMessage by remember { mutableStateOf("") }
        var confirmDelete by remember { mutableStateOf(false) }
        val headers = remember { mutableStateListOf<HeaderDraft>().apply { addAll(loadHeaderDrafts(existing?.id)) } }
        val valid = name.isNotEmpty() && address.isNotEmpty()
        val baseURL = ServerAddress.baseURL(address, proto)

        fun resetTest() { testResult = null; testMessage = "" }
        fun onAddress(v: String) {
            resetTest()
            val (detected, rest) = ServerAddress.detectProtocol(v)
            if (detected != null) { proto = detected; address = if (rest.isNotEmpty()) rest else v } else address = v
        }
        fun usableHeaders() = headers.map { it.toHeader() }.filter { it.isUsable }
        fun test() = scope.launch {
            ServerAddress.detectProtocol(address).let { (pr, a) -> pr?.let { proto = it }; address = a }
            testing = true; resetTest()
            val key = apiKey.takeIf { auth != AuthMethod.None && it.isNotBlank() }
            when (val o = ServerConnection.probe(ServerAddress.baseURL(address, proto), key, usableHeaders())) {
                is ServerConnection.Outcome.Stash -> { testResult = true; testMessage = o.version }
                is ServerConnection.Outcome.Failure -> { testResult = false; testMessage = o.message }
            }
            testing = false
        }
        fun save() {
            ServerAddress.detectProtocol(address).let { (pr, a) -> pr?.let { proto = it }; address = a }
            val parsed = ServerAddress.parse(address)
            val config = ServerConfig(
                id = existing?.id ?: java.util.UUID.randomUUID().toString().uppercase(),
                name = name, serverAddress = parsed.host, port = parsed.port, serverProtocol = proto, subpath = parsed.subpath,
            )
            val key = if (auth != AuthMethod.None) apiKey.trim().ifEmpty { null } else null
            ServerConfigManager.save(config, apiKey = key, headers = usableHeaders())
            if (ServerConfigManager.activeConfig == null) ServerConfigManager.activate(config)
            if (ServerConfigManager.activeConfig?.id == config.id) ActiveServerStatus.reset()
            Nav.pop()
        }
        fun fetchKey() = scope.launch {
            fetchingKey = true; loginError = null
            try {
                apiKey = ServerConnection.fetchAPIKey(baseURL, username, password, usableHeaders())
                auth = AuthMethod.ApiKey; username = ""; password = ""
                fetchingKey = false
                test()
            } catch (e: Exception) { loginError = e.message; fetchingKey = false }
        }

        SettingsDetailScaffold(if (existing == null) "Add Server" else "Edit Server", trailing = {
            ChromeTextButton("Save", enabled = valid) { save() }
        }) { top ->
            SettingsList(top) {
                settingsSection(header = "Server Details", key = "details") {
                    SettingsRow { PlainTextField(name, { name = it }, "Server Name") }
                    SettingsDivider()
                    SettingsRow { Segmented(ServerProtocol.entries, proto, { it.name }) { proto = it; resetTest() } }
                    SettingsDivider()
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Server Address", style = IosTypography.caption, color = Theme.palette.secondaryText)
                        PlainTextField(address, ::onAddress, "192.168.1.100:9999 or stash.example.com", keyboard = KeyboardType.Uri)
                    }
                }
                val authFooter = when (auth) {
                    AuthMethod.None -> "No authentication will be used."
                    AuthMethod.Login -> "Login with your Stash credentials to retrieve the API key."
                    AuthMethod.ApiKey -> "Enter your Stash API key directly."
                }
                settingsSection(header = "Authentication", footer = authFooter, key = "auth") {
                    SettingsRow { Segmented(listOf(AuthMethod.None, AuthMethod.Login, AuthMethod.ApiKey), auth, { it.title }) { auth = it } }
                    when (auth) {
                        AuthMethod.Login -> {
                            SettingsDivider(); SettingsRow { PlainTextField(username, { username = it }, "Username") }
                            SettingsDivider(); SettingsRow { PlainTextField(password, { password = it }, "Password", secret = true) }
                            SettingsDivider()
                            Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                                PrimaryButton("Fetch API Key", enabled = username.isNotEmpty() && password.isNotEmpty() && !fetchingKey, busy = fetchingKey) { fetchKey() }
                            }
                            loginError?.let { SettingsDivider(); SettingsRow { Text(it, style = IosTypography.caption, color = Color(0xFFFF453A)) } }
                        }
                        AuthMethod.ApiKey -> {
                            SettingsDivider()
                            SettingsRow {
                                Icon(SFS.key, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(18.dp))
                                PlainTextField(apiKey, { apiKey = it }, "API Key", Modifier.weight(1f), secret = true)
                            }
                        }
                        AuthMethod.None -> {}
                    }
                }
                settingsSection(
                    header = "Custom Headers", key = "headers",
                    footer = "Sent with every request to this server, e.g. for SSO or a reverse proxy that needs its own token. Stored encrypted on this device.",
                ) { HeadersEditorRows(headers) }
                settingsSection(header = "Connection", footer = if (valid) "URL: $baseURL" else null, key = "connection") {
                    SettingsRow(onClick = { test() }, enabled = valid && !testing) {
                        if (testing) RowProgress()
                        else Icon(
                            when (testResult) { true -> SF.checkmarkCircleFill; false -> SFS.xmarkCircleFill; null -> SFS.network },
                            null, tint = when (testResult) { true -> Color(0xFF30D158); false -> Color(0xFFFF453A); null -> Theme.palette.secondaryText },
                            modifier = Modifier.size(22.dp),
                        )
                        Text(if (testing) "Testing..." else "Test Connection", style = IosTypography.body, color = Theme.palette.text, modifier = Modifier.weight(1f))
                        if (testResult == true) Text(testMessage, style = IosTypography.caption, color = Color(0xFF30D158))
                    }
                    if (testResult == false && testMessage.isNotEmpty()) {
                        SettingsDivider()
                        SettingsRow {
                            Icon(SFS.exclamationTriangleFill, null, tint = Color(0xFFFF9F0A), modifier = Modifier.size(18.dp))
                            Text(testMessage, style = IosTypography.caption, color = Theme.palette.secondaryText, modifier = Modifier.weight(1f))
                        }
                    }
                }
                if (existing != null) settingsSection(key = "delete") {
                    SettingsRow(onClick = { confirmDelete = true }) {
                        Spacer(Modifier.weight(1f))
                        Icon(SF.trash, null, tint = Appearance.tint, modifier = Modifier.size(20.dp))
                        Text("Delete Server", style = IosTypography.body, color = Appearance.tint)
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        if (confirmDelete && existing != null) ConfirmAlert(
            "Delete Server", "Are you sure you want to delete this server configuration? This action cannot be undone.", "Delete",
            onConfirm = { ServerConfigManager.delete(existing); Nav.pop(); Nav.top?.let { if (it is ServerDetailScreen) Nav.pop() } },
            onDismiss = { confirmDelete = false },
        )
    }
}
