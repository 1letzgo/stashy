package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.ServerAddress
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerConnection
import de.letzgo.stashy.data.ServerHTTPHeader
import de.letzgo.stashy.data.ServerProtocol
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS: `AuthMethod` (raw values = labels). */
enum class TvAuthMethod(@androidx.annotation.StringRes private val labelRes: Int) { None(R.string.none), Login(R.string.login), ApiKey(R.string.api_key);

    /** Read on use: a constant must not freeze its text at class load. */
    val label: String get() = tr(labelRes)
}

/** Editable state of the server form (iOS: the `@State`s of `TVServerSetupView` / `TVServerFormView`). */
class TvServerFormState(server: ServerConfig?) {
    val id: String? = server?.id
    var name by mutableStateOf(server?.name ?: tr(R.string.my_stash))
    var address by mutableStateOf(server?.let { ServerAddress.display(it) } ?: "")
    var localAddress by mutableStateOf(server?.localURL ?: "")
    var port by mutableStateOf("")
    var protocol by mutableStateOf(server?.serverProtocol ?: ServerProtocol.HTTPS)
    var apiKey by mutableStateOf(server?.apiKey ?: "")
    var authMethod by mutableStateOf(if (server?.apiKey.isNullOrEmpty()) TvAuthMethod.None else TvAuthMethod.ApiKey)
    var username by mutableStateOf("")
    var password by mutableStateOf("")
    val headers = mutableStateListOf<ServerHTTPHeader>().apply { server?.customHeaders?.let { addAll(it) } }
    var isFetchingKey by mutableStateOf(false)
    var loginError by mutableStateOf<String?>(null)

    /** iOS: typing/pasting `https://…` picks the protocol and strips the scheme. */
    fun updateAddress(value: String) {
        val (detected, stripped) = ServerAddress.detectProtocol(value)
        if (detected != null) { protocol = detected; address = stripped } else address = value
    }

    fun config(): ServerConfig {
        val parsed = ServerAddress.parse(address)
        return ServerConfig(
            id = id ?: java.util.UUID.randomUUID().toString().uppercase(),
            name = name.ifBlank { tr(R.string.my_stash) },
            serverAddress = parsed.host,
            port = port.trim().ifEmpty { parsed.port },
            serverProtocol = protocol,
            subpath = parsed.subpath,
            localURL = ServerAddress.normalizeLocal(localAddress),
        )
    }

    val usableHeaders: List<ServerHTTPHeader> get() = headers.filter { it.isUsable }
    val effectiveKey: String? get() = if (authMethod == TvAuthMethod.None) null else apiKey.trim().ifEmpty { null }

    /** iOS: `LoginAuthHelper.fetchAPIKey` — stays in the Login flow. */
    suspend fun fetchKey(): Boolean {
        isFetchingKey = true
        loginError = null
        return try {
            apiKey = ServerConnection.fetchAPIKey(config().baseURL, username, password, usableHeaders)
            true
        } catch (e: Exception) {
            loginError = e.message ?: tr(R.string.error_login)
            false
        } finally {
            isFetchingKey = false
        }
    }
}

/** The fields shared by first-run setup and the Settings server form. */
@Composable
fun TvServerFields(state: TvServerFormState, firstFocus: FocusRequester? = null, showLocalAddress: Boolean = false) {
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(pt(24))) {
        TvTextField(tr(R.string.server_name), state.name, { state.name = it }, if (firstFocus != null) Modifier.focusRequester(firstFocus) else Modifier)
        TvTextField(tr(R.string.hint_server_address_e_g_192), state.address, { state.updateAddress(it) }, keyboardType = KeyboardType.Uri)
        Row(horizontalArrangement = Arrangement.spacedBy(pt(24)), verticalAlignment = Alignment.CenterVertically) {
            TvTextField(tr(R.string.port_optional), state.port, { v -> state.port = v.filter { it.isDigit() } }, Modifier.width(pt(300)), keyboardType = KeyboardType.Number)
            TvSegmented(listOf(TvOption(ServerProtocol.HTTP, "HTTP"), TvOption(ServerProtocol.HTTPS, "HTTPS")), state.protocol, { state.protocol = it })
        }
        if (showLocalAddress) {
            TvTextField(tr(R.string.local_address_e_g_192), state.localAddress, { state.localAddress = it }, keyboardType = KeyboardType.Uri)
            Text(tr(R.string.hint_optional_used_instead_of_address), style = TvType.caption, color = TvColors.secondary)
        }
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(20))).background(Color.White.copy(alpha = 0.05f)).padding(pt(32)),
            verticalArrangement = Arrangement.spacedBy(pt(24)),
        ) {
            Text(tr(R.string.authentication), style = TvType.headline, color = TvColors.secondary)
            TvSegmented(TvAuthMethod.entries.map { TvOption(it, it.label) }, state.authMethod, { state.authMethod = it })
            when (state.authMethod) {
                TvAuthMethod.Login -> {
                    TvTextField(tr(R.string.username), state.username, { state.username = it })
                    TvTextField(tr(R.string.password), state.password, { state.password = it }, secure = true)
                    TvButton(
                        { scope.launch { state.fetchKey() } },
                        enabled = state.username.isNotEmpty() && state.password.isNotEmpty() && !state.isFetchingKey,
                    ) {
                        if (state.isFetchingKey) TvSpinner(pt(30))
                        Text(if (state.isFetchingKey) tr(R.string.logging_in_menu) else if (state.apiKey.isNotEmpty()) (tr(R.string.action_fetch_api_key) + " ✓") else tr(R.string.action_fetch_api_key), style = TvType.headline)
                    }
                    state.loginError?.let { Text(it, style = TvType.callout, color = TvColors.red) }
                }
                TvAuthMethod.ApiKey -> TvTextField(tr(R.string.api_key), state.apiKey, { state.apiKey = it }, secure = true)
                TvAuthMethod.None -> {}
            }
        }
        TvCustomHeadersCard(state)
    }
}

/** iOS: `TVCustomHeadersCard` — name/value pairs sent with every request (SSO, reverse proxy). */
@Composable
fun TvCustomHeadersCard(state: TvServerFormState) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(20))).background(Color.White.copy(alpha = 0.05f)).padding(pt(32)),
        verticalArrangement = Arrangement.spacedBy(pt(20)),
    ) {
        Text(tr(R.string.custom_headers), style = TvType.headline, color = TvColors.secondary)
        state.headers.forEachIndexed { index, header ->
            Column(verticalArrangement = Arrangement.spacedBy(pt(12))) {
                TvTextField(tr(R.string.header_name), header.name, { state.headers[index] = header.copy(name = it) })
                Row(horizontalArrangement = Arrangement.spacedBy(pt(16)), verticalAlignment = Alignment.CenterVertically) {
                    TvTextField(tr(R.string.value), header.value, { state.headers[index] = header.copy(value = it) }, Modifier.weight(1f), secure = true)
                    TvButton({ state.headers.removeAt(index) }) { Icon(TvIcons.minusCircle, tr(R.string.action_remove_header), Modifier.size(pt(36))) }
                }
            }
        }
        TvButton({ state.headers.add(ServerHTTPHeader(name = "", value = "")) }) {
            Icon(TvIcons.plusCircle, null, Modifier.size(pt(32)))
            Text(tr(R.string.action_add_header), style = TvType.headline)
        }
        Text(tr(R.string.hint_sent_with_every_request_to), style = TvType.caption, color = TvColors.secondary)
    }
}

/** iOS: `TVServerSetupView` — first run: test the connection, then save and activate. */
@Composable
fun TvServerSetup() {
    val state = remember { TvServerFormState(null) }
    val scope = rememberCoroutineScope()
    var isTesting by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val first = remember { FocusRequester() }

    fun connect() {
        scope.launch {
            if (state.authMethod == TvAuthMethod.Login && state.apiKey.isEmpty() && state.username.isNotEmpty() && state.password.isNotEmpty()) {
                if (!state.fetchKey()) return@launch
            }
            val config = state.config()
            isTesting = true
            error = null
            when (val outcome = ServerConnection.probe(config.baseURL, state.effectiveKey, state.usableHeaders)) {
                is ServerConnection.Outcome.Stash -> {
                    ServerConfigManager.save(config, state.effectiveKey, state.usableHeaders)
                    ServerConfigManager.activate(config)
                }
                is ServerConnection.Outcome.Failure -> error = outcome.message.ifEmpty { tr(R.string.error_reach_arg_check_address_port, config.baseURL) }
            }
            isTesting = false
        }
    }

    Box(Modifier.fillMaxSize().background(TvColors.background)) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = pt(60), vertical = pt(40)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(pt(48)),
        ) {
            item {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(16))) {
                    Icon(TvIcons.server, null, Modifier.size(pt(80)), tint = TvColors.secondary)
                    Text(tr(R.string.action_connect_to_stash), style = TvType.largeTitle, color = Color.White)
                    Text(tr(R.string.hint_enter_your_stash_server_details), style = TvType.title3, color = TvColors.secondary, textAlign = TextAlign.Center)
                }
            }
            item { Box(Modifier.width(pt(800))) { TvServerFields(state, first) } }
            error?.let { item { Text(it, Modifier.width(pt(800)), style = TvType.callout, color = TvColors.red, textAlign = TextAlign.Center) } }
            item {
                TvButton({ if (!isTesting) connect() }, enabled = state.address.isNotEmpty(), contentPadding = PaddingValues(horizontal = pt(60), vertical = pt(16))) {
                    if (isTesting) TvSpinner(pt(30))
                    Text(if (isTesting) tr(R.string.loading_connecting) else tr(R.string.action_connect), style = TvType.title3.copy(fontWeight = FontWeight.SemiBold))
                }
            }
        }
    }
    TvRequestFocus(first, "setup.name", delayMs = 100)
}

/** iOS: `TVServerFormView` — Add / Edit server from Settings (saved without a test). */
class TvServerFormRoute(private val server: ServerConfig?) : TvRoute {
    override val key = "serverForm.${server?.id ?: "new"}.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()
    private val state = TvServerFormState(server)

    @Composable
    override fun Content() {
        val scope = rememberCoroutineScope()
        val first = remember { FocusRequester() }
        BackHandler { TvNav.pop() }

        fun save() {
            scope.launch {
                if (state.authMethod == TvAuthMethod.Login && state.apiKey.isEmpty() && state.username.isNotEmpty() && state.password.isNotEmpty()) {
                    if (!state.fetchKey()) return@launch
                }
                val config = state.config()
                ServerConfigManager.save(config, state.effectiveKey, state.headers.toList())
                if (server == null) ServerConfigManager.activate(config)
                else if (ServerConfigManager.activeConfig?.id == config.id) ServerConfigManager.activate(config)
                TvNav.pop()
            }
        }

        LazyColumn(
            Modifier.fillMaxSize().background(TvColors.background),
            contentPadding = PaddingValues(horizontal = pt(60), vertical = pt(40)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(pt(40)),
        ) {
            item { Text(if (server == null) tr(R.string.action_add_server) else tr(R.string.action_edit_server), style = TvType.largeTitle, color = Color.White) }
            item { Box(Modifier.width(pt(800))) { TvServerFields(state, first, showLocalAddress = true) } }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(pt(40))) {
                    TvButton({ TvNav.pop() }) { Text(tr(R.string.action_cancel), style = TvType.title3) }
                    TvButton({ save() }, enabled = state.address.isNotEmpty()) { Text(tr(R.string.action_save), style = TvType.title3.copy(fontWeight = FontWeight.SemiBold)) }
                }
            }
        }
        TvInitialFocus(focus, first, name = "serverForm.name")
    }
}
