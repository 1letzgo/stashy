package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.NativeTonalButton
import de.letzgo.stashy.ui.nativeAccent
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.outlined.Settings
import de.letzgo.stashy.ui.setup.AuthMethod
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

/** Connection state of the active server (iOS `viewModel.isServerConnected` / `serverStatus`). */
object ActiveServerStatus {
    var isConnected by mutableStateOf<Boolean?>(null); private set
    var statusText by mutableStateOf(tr(R.string.not_connected)); private set
    private var testedFor: String? = null

    /** iOS `testConnection(force:)`. */
    suspend fun test(force: Boolean = false) {
        val config = ServerConfigManager.activeConfig ?: run { isConnected = null; statusText = tr(R.string.not_connected); return }
        if (!force && testedFor == config.id && isConnected != null) return
        testedFor = config.id
        when (val o = ServerConnection.probe(config.baseURL, config.apiKey, config.customHeaders)) {
            is ServerConnection.Outcome.Stash -> { isConnected = true; statusText = tr(R.string.connected_v_arg, o.version.removePrefix("v")) }
            is ServerConnection.Outcome.Failure -> { isConnected = false; statusText = o.message }
        }
    }

    fun reset() { isConnected = null; testedFor = null; statusText = tr(R.string.not_connected) }
}

/** URL lines of a server: the external address, as "Remote: …" plus "Local: …" when it has a local one; the active server's address in use is bold. */
@Composable
private fun serverUrlText(server: ServerConfig, active: Boolean): androidx.compose.ui.text.AnnotatedString {
    val local = server.localURL?.takeIf { it.isNotBlank() }
        ?: return androidx.compose.ui.text.AnnotatedString(server.externalBaseURL)
    val usesLocal by de.letzgo.stashy.data.ServerEndpointSelector.activeUsesLocal.collectAsState()
    val bold = androidx.compose.ui.text.SpanStyle(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
    return androidx.compose.ui.text.buildAnnotatedString {
        val remote = tr(R.string.remote_2) + server.externalBaseURL
        if (active && !usesLocal) { pushStyle(bold); append(remote); pop() } else append(remote)
        append("\n")
        val localLine = tr(R.string.local_arg, local)
        if (active && usesLocal) { pushStyle(bold); append(localLine); pop() } else append(localLine)
    }
}

/** iOS `ServerListRow.onConnect` / `ServerDetailView.connectServer`: activate and reset all stacks. */
fun connectServer(server: ServerConfig) {
    ServerConfigManager.activate(server)
    ActiveServerStatus.reset()
    MainTab.entries.forEach { Nav.popToRoot(it) }
}

/** iOS: `ServerListSection` — saved servers with status dot, plus "Add New Server". */
fun androidx.compose.foundation.lazy.LazyListScope.serverListSection() {
    settingsSection(header = tr(R.string.servers), key = "servers") {
        LaunchedEffect(ServerConfigManager.activeConfig?.id) { ActiveServerStatus.test() }
        ServerConfigManager.savedServers.forEach { server ->
            ServerListRow(server)
            SettingsDivider()
        }
        NativeListItem(tr(R.string.action_add_new_server), icon = SF.plus, headlineColor = nativeAccent(), onClick = { Nav.push(ServerFormScreen(null)) })
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun ServerListRow(server: ServerConfig) {
    val p = Theme.palette
    val active = ServerConfigManager.activeConfig?.id == server.id
    val dot = when {
        !active -> Color.Gray.copy(alpha = 0.3f)
        ActiveServerStatus.isConnected == true -> Color(0xFF30D158)
        else -> Color(0xFFFFD60A)
    }
    var confirmDelete by remember { mutableStateOf(false) }
    // iOS `.onDelete` on the server list: swipe left deletes. The row snaps back and the same
    // "Delete Server" confirmation as the detail screen decides (also for the active server).
    val swipe = androidx.compose.material3.rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == androidx.compose.material3.SwipeToDismissBoxValue.EndToStart) confirmDelete = true
        false
    })
    androidx.compose.material3.SwipeToDismissBox(
        state = swipe,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(Modifier.fillMaxSize().background(StashyColors.systemRed).padding(end = 20.dp), contentAlignment = Alignment.CenterEnd) {
                Icon(SF.trash, tr(R.string.action_delete_server), tint = Color.White)
            }
        },
    ) {
        // Material list item like the Wi-Fi list: tap connects, the gear opens the server details.
        Box(Modifier.background(p.secondaryBackground)) {
            NativeListItem(
                server.name, supportingStyled = serverUrlText(server, active),
                onClick = { if (!active) connectServer(server) },
                leading = { Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { Box(Modifier.size(10.dp).background(dot, CircleShape)) } },
                trailing = {
                    IconButton({ Nav.push(ServerDetailScreen(server.id)) }) {
                        Icon(androidx.compose.material.icons.Icons.Outlined.Settings, tr(R.string.server_details), tint = p.secondaryText)
                    }
                },
            )
        }
    }
    if (confirmDelete) ConfirmAlert(
        tr(R.string.action_delete_server),
        tr(R.string.hint_are_you_sure_you_want_to),
        tr(R.string.action_delete),
        onConfirm = { if (active) { ServerConfigManager.delete(server); ActiveServerStatus.reset(); MainTab.entries.forEach { Nav.popToRoot(it) } } else ServerConfigManager.delete(server) },
        onDismiss = { confirmDelete = false },
    )
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
                settingsSection(header = tr(R.string.server_information), key = "info") {
                    ValueRow(tr(R.string.name), server.name); SettingsDivider()
                    NativeListItem("URL", supportingStyled = serverUrlText(server, active)); SettingsDivider()
                    ValueRow(tr(R.string.protocol), server.serverProtocol.name)
                    if (active) {
                        SettingsDivider()
                        NativeListItem(tr(R.string.status), trailing = {
                            Text(ActiveServerStatus.statusText, style = NativeType.bodyMedium, color = if (ActiveServerStatus.isConnected == true) Color(0xFF30D158) else Color(0xFFFF453A), maxLines = 2)
                        })
                    }
                }
                if (!active) settingsSection(key = "connect") {
                    val connect = {
                        connecting = true
                        connectServer(server)
                        scope.launch { ActiveServerStatus.test(force = true); connecting = false }
                        Unit
                    }
                    NativeListItem(tr(R.string.action_connect_to_server), icon = SFS.power, onClick = { if (!connecting) connect() }, trailing = {
                        if (connecting) RowProgress() else NativeTonalButton(tr(R.string.action_connect)) { connect() }
                    })
                }
                settingsSection(header = tr(R.string.server_configuration), key = "config") {
                    NativeListItem(tr(R.string.action_edit_configuration), icon = SF.pencil, onClick = { Nav.push(ServerFormScreen(server.id)) })
                    SettingsDivider()
                    NativeListItem(tr(R.string.action_delete_server), icon = SF.trash, iconTint = StashyColors.systemRed, headlineColor = StashyColors.systemRed, onClick = { confirmDelete = true })
                }
            }
        }
        if (confirmDelete) ConfirmAlert(
            tr(R.string.action_delete_server), tr(R.string.hint_are_you_sure_you_want_to), tr(R.string.action_delete),
            onConfirm = { ServerConfigManager.delete(server); Nav.pop() }, onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
private fun ValueRow(title: String, value: String) = NativeListItem(title, supporting = value)

/**
 * Text field of the server forms — Material outlined field ([NativeTextField]). [placeholder]
 * becomes the floating label unless a separate [label] is given.
 */
@Composable
fun PlainTextField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    secret: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    monospaced: Boolean = false,
    label: String? = null,
) = NativeTextField(
    value, onChange, label ?: placeholder, modifier,
    placeholder = if (label != null) placeholder else null,
    secret = secret, keyboard = keyboard, monospaced = monospaced,
)

/** iOS segmented `Picker` — Material 3 single-choice segmented buttons. */
@Composable
fun <T> Segmented(options: List<T>, selected: T, label: (T) -> String, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    val p = Theme.palette
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, o ->
            SegmentedButton(
                selected = o == selected, onClick = { onSelect(o) }, shape = SegmentedButtonDefaults.itemShape(i, options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = nativeAccent().copy(alpha = 0.22f), activeContentColor = p.text,
                    inactiveContainerColor = Color.Transparent, inactiveContentColor = p.text,
                    activeBorderColor = p.secondaryText.copy(alpha = 0.5f), inactiveBorderColor = p.secondaryText.copy(alpha = 0.5f),
                ),
            ) { Text(label(o), style = NativeType.labelLarge, maxLines = 1) }
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
    if (name.isEmpty()) return tr(R.string.enter_header_name)
    if (name.lowercase() in ServerHTTPHeader.reservedNames) return tr(R.string.hint_arg_is_managed_by_app, name)
    if (h.value.trim().isEmpty()) return tr(R.string.enter_value)
    if (!h.toHeader().isUsable) return tr(R.string.hint_header_names_may_only_contain)
    return null
}

/** iOS: `ServerCustomHeadersEditor` rows (inside a settings group). */
@Composable
fun HeadersEditorRows(headers: SnapshotStateList<HeaderDraft>) {
    headers.forEachIndexed { index, h ->
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PlainTextField(h.name, { headers[index] = h.copy(name = it) }, tr(R.string.header_name), Modifier.weight(1f), monospaced = true)
                IconButton({ headers.removeAt(index) }) { Icon(SFS.minusCircleFill, tr(R.string.action_remove_header), tint = StashyColors.systemRed) }
            }
            PlainTextField(h.value, { headers[index] = h.copy(value = it) }, tr(R.string.value), secret = true)
            headerProblem(h)?.let { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF9F0A)) }
        }
        SettingsDivider()
    }
    NativeListItem(tr(R.string.action_add_header), icon = SFS.plusCircleFill, headlineColor = nativeAccent(), onClick = { headers.add(HeaderDraft()) })
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
        var name by remember { mutableStateOf(existing?.name ?: tr(R.string.my_stash)) }
        var address by remember { mutableStateOf(existing?.let { ServerAddress.display(it) } ?: "") }
        var proto by remember { mutableStateOf(existing?.serverProtocol ?: ServerProtocol.HTTPS) }
        var localAddress by remember { mutableStateOf(existing?.localURL ?: "") }
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
                localURL = ServerAddress.normalizeLocal(localAddress),
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

        SettingsDetailScaffold(if (existing == null) tr(R.string.action_add_server) else tr(R.string.action_edit_server), trailing = {
            ChromeTextButton(tr(R.string.action_save), enabled = valid) { save() }
        }) { top ->
            SettingsList(top) {
                settingsSection(header = tr(R.string.server_details), key = "details") {
                    SettingsRow { PlainTextField(name, { name = it }, tr(R.string.server_name)) }
                    SettingsDivider()
                    SettingsRow { Segmented(ServerProtocol.entries, proto, { it.name }) { proto = it; resetTest() } }
                    SettingsDivider()
                    SettingsRow {
                        PlainTextField(address, ::onAddress, tr(R.string.n192_168_1_100_9999), keyboard = KeyboardType.Uri, label = tr(R.string.server_address))
                    }
                }
                settingsSection(
                    header = tr(R.string.local_address), key = "local",
                    footer = tr(R.string.hint_optional_used_instead_of_address),
                ) {
                    SettingsRow { PlainTextField(localAddress, { localAddress = it }, "192.168.1.100:9999", keyboard = KeyboardType.Uri, label = tr(R.string.local_address)) }
                }
                val authFooter = when (auth) {
                    AuthMethod.None -> tr(R.string.empty_authentication_will_be_used)
                    AuthMethod.Login -> tr(R.string.hint_login_with_your_stash_credentials)
                    AuthMethod.ApiKey -> tr(R.string.hint_enter_your_stash_api_key)
                }
                settingsSection(header = tr(R.string.authentication), footer = authFooter, key = "auth") {
                    SettingsRow { Segmented(listOf(AuthMethod.None, AuthMethod.Login, AuthMethod.ApiKey), auth, { it.title }) { auth = it } }
                    when (auth) {
                        AuthMethod.Login -> {
                            SettingsDivider(); SettingsRow { PlainTextField(username, { username = it }, tr(R.string.username)) }
                            SettingsDivider(); SettingsRow { PlainTextField(password, { password = it }, tr(R.string.password), secret = true) }
                            SettingsDivider()
                            Box(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                                PrimaryButton(tr(R.string.action_fetch_api_key), enabled = username.isNotEmpty() && password.isNotEmpty() && !fetchingKey, busy = fetchingKey) { fetchKey() }
                            }
                            loginError?.let { SettingsDivider(); SettingsRow { Text(it, style = NativeType.bodySmall, color = Color(0xFFFF453A)) } }
                        }
                        AuthMethod.ApiKey -> {
                            SettingsDivider()
                            SettingsRow { NativeTextField(apiKey, { apiKey = it }, tr(R.string.api_key), Modifier.weight(1f), secret = true, leadingIcon = SFS.key) }
                        }
                        AuthMethod.None -> {}
                    }
                }
                settingsSection(
                    header = tr(R.string.custom_headers), key = "headers",
                    footer = tr(R.string.hint_sent_with_every_request_to_this),
                ) { HeadersEditorRows(headers) }
                settingsSection(header = tr(R.string.connection), footer = if (valid) "URL: $baseURL" else null, key = "connection") {
                    SettingsRow(onClick = { test() }, enabled = valid && !testing) {
                        if (testing) RowProgress()
                        else Icon(
                            when (testResult) { true -> SF.checkmarkCircleFill; false -> SFS.xmarkCircleFill; null -> SFS.network },
                            null, tint = when (testResult) { true -> Color(0xFF30D158); false -> Color(0xFFFF453A); null -> Theme.palette.secondaryText },
                            modifier = Modifier.size(22.dp),
                        )
                        Text(if (testing) tr(R.string.loading_testing) else tr(R.string.action_test_connection), style = NativeType.bodyLarge, color = Theme.palette.text, modifier = Modifier.weight(1f))
                        if (testResult == true) Text(testMessage, style = NativeType.bodySmall, color = Color(0xFF30D158))
                    }
                    if (testResult == false && testMessage.isNotEmpty()) {
                        SettingsDivider()
                        SettingsRow {
                            Icon(SFS.exclamationTriangleFill, null, tint = Color(0xFFFF9F0A), modifier = Modifier.size(18.dp))
                            Text(testMessage, style = NativeType.bodySmall, color = Theme.palette.secondaryText, modifier = Modifier.weight(1f))
                        }
                    }
                }
                if (existing != null) settingsSection(key = "delete") {
                    NativeListItem(tr(R.string.action_delete_server), icon = SF.trash, iconTint = StashyColors.systemRed, headlineColor = StashyColors.systemRed, onClick = { confirmDelete = true })
                }
            }
        }
        if (confirmDelete && existing != null) ConfirmAlert(
            tr(R.string.action_delete_server), tr(R.string.hint_are_you_sure_you_want_to), tr(R.string.action_delete),
            onConfirm = { ServerConfigManager.delete(existing); Nav.pop(); Nav.top?.let { if (it is ServerDetailScreen) Nav.pop() } },
            onDismiss = { confirmDelete = false },
        )
    }
}
