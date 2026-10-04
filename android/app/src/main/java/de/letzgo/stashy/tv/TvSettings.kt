package de.letzgo.stashy.tv

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import de.letzgo.stashy.BuildConfig
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.ServerConfig
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.ServerConnection
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.StashyPlusProduct
import de.letzgo.stashy.data.StashyPlusSource
import de.letzgo.stashy.data.SubtitleBackgroundChoice
import de.letzgo.stashy.data.SubtitleFontFamily
import de.letzgo.stashy.data.SubtitleFontSize
import de.letzgo.stashy.data.SubtitleTextColorChoice
import de.letzgo.stashy.data.TabConfigLogic
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.settings.subtitleLanguageOptions
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS: `TVSettingsEntry` — one entry of the Settings overview (title, icon, right-column text). */
enum class TvSettingsEntry(val title: String, val summary: String) {
    Servers("Servers", "Add Stash servers, switch between them, and edit or remove saved ones."),
    Appearance("Appearance", "Pick the accent color used for focus highlights and icons throughout the app."),
    Security("Security", "Require a PIN before the app opens."),
    StashyPlus("stashy+", "Premium features, including Channels — continuous playback of a performer, studio, tag or saved filter."),
    DefaultSort("Default Sorting", "The sort order each section opens with."),
    DefaultFilters("Default Filters", "A saved server filter to apply automatically when a section opens."),
    VisibleTabs("Visible Tabs", "Hide sections you do not use. They disappear from the sidebar."),
    Subtitles("Subtitles", "Turn subtitles on automatically, choose the language a scene should start with, and set how the cues look."),
    DolbyVision("Dolby Vision", "Turn off if a Dolby Vision scene shows green or purple colors. It then plays as HDR10, which your TV still shows in HDR."),
    PlayCount("Count As Played", "How long a scene has to play before it counts as played and its position is saved."),
    Maintenance("Maintenance", "Clear the cached artwork for the active server. Images are re-downloaded as they are shown again."),
    About("About", "Version and build number.");

    val icon: ImageVector get() = when (this) {
        Servers -> TvIcons.server
        Appearance -> TvIcons.brush
        Security -> TvIcons.lock
        StashyPlus -> TvIcons.sparklesTv
        DefaultSort -> TvIcons.sort
        DefaultFilters -> TvIcons.filter
        VisibleTabs -> TvIcons.gridGroup
        Subtitles -> TvIcons.captions
        DolbyVision -> TvIcons.tv
        PlayCount -> TvIcons.playCircle
        Maintenance -> TvIcons.drive
        About -> TvIcons.info
    }
}

/** Root state of the Settings tab. */
class TvSettingsModel {
    val focus = TvFocusMemory()
    var detailEntry by mutableStateOf(TvSettingsEntry.Servers)
}

/**
 * iOS: `TVSettingsView` — the tvOS two-column form: a narrow list on the left (720 pt), the
 * icon, title and explanation of the focused entry on the right.
 */
@Composable
fun TvSettings(model: TvSettingsModel) {
    Row(Modifier.fillMaxSize().background(TvColors.background).padding(end = pt(80)), horizontalArrangement = Arrangement.spacedBy(pt(80))) {
        LazyColumn(Modifier.width(pt(720)).fillMaxHeight(), contentPadding = PaddingValues(start = pt(40), top = pt(40), bottom = pt(160)), verticalArrangement = Arrangement.spacedBy(pt(12))) {
            item { TvSectionHeader("General") }
            item { EntryRow(model, TvSettingsEntry.Servers) }
            item { EntryRow(model, TvSettingsEntry.Appearance) }
            item { EntryRow(model, TvSettingsEntry.Security) }
            item { EntryRow(model, TvSettingsEntry.StashyPlus) }
            item { TvSectionHeader("Content") }
            item { EntryRow(model, TvSettingsEntry.DefaultSort) }
            item { EntryRow(model, TvSettingsEntry.DefaultFilters) }
            item { EntryRow(model, TvSettingsEntry.VisibleTabs) }
            item { TvSectionHeader("Playback") }
            item { EntryRow(model, TvSettingsEntry.Subtitles) }
            item {
                TvToggleRow("Dolby Vision", TabManager.playerDolbyVisionEnabled, { TabManager.playerDolbyVisionEnabled = it },
                    Modifier.tvFocusMemory(model.focus, TvSettingsEntry.DolbyVision.name), onFocus = { model.detailEntry = TvSettingsEntry.DolbyVision })
            }
            item { EntryRow(model, TvSettingsEntry.PlayCount, TabConfigLogic.playCountThresholdLabel(TabManager.playCountPlayerSeconds)) }
            item { Spacer(Modifier.height(pt(28))) }
            item { EntryRow(model, TvSettingsEntry.Maintenance) }
            item { EntryRow(model, TvSettingsEntry.About) }
        }
        val entry = model.detailEntry
        Column(Modifier.widthIn(max = pt(620)).padding(top = pt(100)), verticalArrangement = Arrangement.spacedBy(pt(28))) {
            Icon(entry.icon, null, Modifier.size(pt(72)), tint = TvColors.tint)
            Text(entry.title, style = TvType.title.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
            Text(entry.summary, style = TvType.title3, color = TvColors.secondary)
        }
    }
}

@Composable
private fun EntryRow(model: TvSettingsModel, entry: TvSettingsEntry, value: String? = null) {
    TvListRow(entry.title, { TvNav.push(TvSettingsPageRoute(entry)) }, Modifier.tvFocusMemory(model.focus, entry.name), value = value, onFocus = { model.detailEntry = entry })
}

/**
 * iOS: `TVSettingsPageChrome` — every Settings sub-page: large title over the list (900 pt),
 * the explanation (and an optional preview) in the right column.
 */
@Composable
fun TvSettingsPage(title: String, description: String?, detail: (@Composable () -> Unit)? = null, firstFocus: FocusRequester? = null, list: LazyListScope.() -> Unit) {
    Row(Modifier.fillMaxSize().background(TvColors.background).padding(start = pt(60), end = pt(80), top = pt(60)), horizontalArrangement = Arrangement.spacedBy(pt(80))) {
        Column(Modifier.width(pt(900)).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(pt(16))) {
            Text(title, style = TvType.largeTitle, color = Color.White)
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = pt(160), top = pt(8)), verticalArrangement = Arrangement.spacedBy(pt(12)), content = list)
        }
        if (description != null || detail != null) {
            Column(Modifier.widthIn(max = pt(620)).padding(top = pt(96)), verticalArrangement = Arrangement.spacedBy(pt(32))) {
                if (description != null) Text(description, style = TvType.title3, color = TvColors.secondary)
                detail?.invoke()
            }
        }
    }
    if (firstFocus != null) TvInitialFocus(LocalTvFocusMemory.current ?: remember { TvFocusMemory() }, firstFocus)
}

/** A pushed Settings sub-page (iOS: `navigationDestination(for: TVSettingsEntry.self)`). */
class TvSettingsPageRoute(private val entry: TvSettingsEntry) : TvRoute {
    override val key = "settings.${entry.name}.${System.nanoTime()}"
    override val focus = TvFocusMemory()

    @Composable
    override fun Content() {
        when (entry) {
            TvSettingsEntry.Servers -> ServersPage(focus)
            TvSettingsEntry.Appearance -> AppearancePage()
            TvSettingsEntry.Security -> SecurityPage()
            TvSettingsEntry.StashyPlus -> StashyPlusPage()
            TvSettingsEntry.DefaultSort -> DefaultSortPage()
            TvSettingsEntry.DefaultFilters -> DefaultFiltersPage()
            TvSettingsEntry.VisibleTabs -> VisibleTabsPage()
            TvSettingsEntry.Subtitles -> SubtitlesPage()
            TvSettingsEntry.PlayCount -> PlayCountPage()
            TvSettingsEntry.Maintenance -> MaintenancePage()
            TvSettingsEntry.About -> AboutPage()
            TvSettingsEntry.DolbyVision -> {}
        }
    }
}

// MARK: - Servers

@Composable
private fun ServersPage(memory: TvFocusMemory) {
    val first = remember { FocusRequester() }
    val active = ServerConfigManager.activeConfig
    val others = ServerConfigManager.savedServers.filter { it.id != active?.id }
    var actionsFor by remember { mutableStateOf<ServerConfig?>(null) }
    var deleting by remember { mutableStateOf<ServerConfig?>(null) }
    TvSettingsPage("Servers", "Add Stash servers and switch between them. Hold Select on a server to edit it or remove a saved one.", firstFocus = first) {
        item { TvSectionHeader("Active Server") }
        item {
            if (active != null) {
                TvListRow(
                    active.name, { TvNav.push(TvServerDetailRoute()) }, Modifier.focusRequester(first).tvFocusMemory(memory, "active"),
                    subtitle = active.baseURL, leading = TvIcons.server, leadingTint = TvColors.tint, trailingIcon = TvIcons.checkCircle, trailingTint = TvColors.green,
                    onLongClick = { TvNav.push(TvServerFormRoute(active)) },
                )
            } else {
                TvListRow("No server configured", {}, Modifier.focusRequester(first), leading = TvIcons.warning, leadingTint = TvColors.yellow)
            }
        }
        if (others.isNotEmpty()) {
            item { TvSectionHeader("Switch Server") }
            items(others, key = { it.id }) { server ->
                TvListRow(server.name, { ServerConfigManager.activate(server) }, Modifier.tvFocusMemory(memory, server.id), subtitle = server.baseURL, onLongClick = { actionsFor = server })
            }
        }
        item { Spacer(Modifier.height(pt(28))) }
        item { TvListRow("Add Server", { TvNav.push(TvServerFormRoute(null)) }, Modifier.tvFocusMemory(memory, "add"), leading = TvIcons.plus, leadingTint = TvColors.tint) }
    }
    actionsFor?.let { server ->
        TvOptionDialog(server.name, listOf(TvOption("edit", "Edit"), TvOption("delete", "Delete")), null, { action ->
            if (action == "edit") TvNav.push(TvServerFormRoute(server)) else deleting = server
        }, { actionsFor = null })
    }
    deleting?.let { server ->
        TvConfirmDialog("Delete \"${server.name}\"?", "Delete", { ServerConfigManager.delete(server) }) { deleting = null }
    }
}

/** iOS: `TVServerDetailView` — status, version, re-test and the connection details. */
class TvServerDetailRoute : TvRoute {
    override val key = "serverDetail.${System.nanoTime()}"
    override val focus = TvFocusMemory()
    private var connected by mutableStateOf<Boolean?>(null)
    private var status by mutableStateOf("Checking…")
    private var testing by mutableStateOf(false)

    @Composable
    override fun Content() {
        val scope = rememberCoroutineScope()
        val button = remember { FocusRequester() }
        val config = ServerConfigManager.activeConfig
        fun test() {
            val c = config ?: return
            if (testing) return
            testing = true
            scope.launch {
                when (val r = ServerConnection.probe(c.baseURL, c.apiKey, c.customHeaders)) {
                    is ServerConnection.Outcome.Stash -> { connected = true; status = "Stash ${r.version}" }
                    is ServerConnection.Outcome.Failure -> { connected = false; status = r.message }
                }
                testing = false
            }
        }
        LaunchedEffect(Unit) { test() }
        LazyColumn(
            Modifier.fillMaxSize().background(TvColors.background),
            contentPadding = PaddingValues(start = pt(60), end = pt(60), top = pt(40), bottom = pt(120)),
            verticalArrangement = Arrangement.spacedBy(pt(32)),
        ) {
            if (config == null) {
                item { Text("No server configured.", style = TvType.title3, color = TvColors.secondary) }
                return@LazyColumn
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(24))) {
                    Icon(TvIcons.server, null, Modifier.size(pt(100)), tint = TvColors.tint)
                    Column(verticalArrangement = Arrangement.spacedBy(pt(8))) {
                        Text(config.name, style = TvType.largeTitle, color = Color.White)
                        Text(config.baseURL, style = TvType.title3, color = Color.White.copy(alpha = 0.6f))
                    }
                }
            }
            item {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(14))).background(Color.White.copy(alpha = 0.05f)).padding(pt(20)),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(20)),
                ) {
                    val ok = connected == true
                    Icon(if (ok) TvIcons.checkCircle else TvIcons.warning, null, Modifier.size(pt(48)), tint = if (ok) TvColors.green else TvColors.yellow)
                    Column(Modifier.weight(1f)) {
                        Text(if (ok) "Connected" else "Not connected", style = TvType.title3.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                        Text(status, style = TvType.callout, color = Color.White.copy(alpha = 0.6f))
                    }
                    if (testing) TvSpinner(pt(40))
                }
            }
            item {
                // Never disabled: it is the only focusable element (Back must have a target).
                TvButton({ test() }, Modifier.focusRequester(button)) {
                    if (testing) TvSpinner(pt(30)) else Icon(TvIcons.retry, null, Modifier.size(pt(30)))
                    Text("Test Connection", style = TvType.headline)
                }
            }
            item {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(14))).background(Color.White.copy(alpha = 0.05f)).padding(pt(20)),
                    verticalArrangement = Arrangement.spacedBy(pt(16)),
                ) {
                    DetailLine("Protocol", config.serverProtocol.name)
                    DetailLine("Address", config.serverAddress)
                    config.port?.takeIf { it.isNotEmpty() }?.let { DetailLine("Port", it) }
                    DetailLine("API Key", if (!config.apiKey.isNullOrEmpty()) "•••• configured" else "Not set")
                }
            }
        }
        LaunchedEffect(Unit) { delay(80); runCatching { button.requestFocus() } }
    }

    @Composable
    private fun DetailLine(label: String, value: String) {
        Row {
            Text(label, style = TvType.title3, color = Color.White.copy(alpha = 0.6f))
            Spacer(Modifier.weight(1f))
            Text(value, style = TvType.title3, color = Color.White)
        }
    }
}

// MARK: - Appearance

@Composable
private fun AppearancePage() {
    val first = remember { FocusRequester() }
    TvSettingsPage("Appearance", "Pick the accent color used for focus highlights and icons throughout the app.", firstFocus = first) {
        item {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(14))).background(Color.White.copy(alpha = 0.06f)).padding(pt(28)), verticalArrangement = Arrangement.spacedBy(pt(16))) {
                Text("Accent Color", style = TvType.headline, color = Color.White)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(20)), contentPadding = PaddingValues(vertical = pt(8))) {
                    items(Appearance.presets.size) { i ->
                        val (name, color) = Appearance.presets[i]
                        ColorPreset(name, color, colorsEqual(color, Appearance.tint), if (i == 0) Modifier.focusRequester(first) else Modifier) { Appearance.updateTint(color) }
                    }
                }
            }
        }
    }
}

private fun colorsEqual(a: Color, b: Color, tolerance: Float = 0.01f) =
    kotlin.math.abs(a.red - b.red) <= tolerance && kotlin.math.abs(a.green - b.green) <= tolerance &&
        kotlin.math.abs(a.blue - b.blue) <= tolerance && kotlin.math.abs(a.alpha - b.alpha) <= tolerance

/** iOS: `TVColorPresetButton` — circle that grows and glows on focus, white ring when selected. */
@Composable
private fun ColorPreset(name: String, color: Color, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        modifier = modifier.onFocusChanged { focused = it.isFocused },
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(pt(16))),
        colors = ClickableSurfaceDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.Transparent, contentColor = Color.White, focusedContentColor = Color.White),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1f),
    ) {
        Column(Modifier.padding(pt(16)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(12))) {
            Box(
                Modifier.size(pt(60)).scale(if (focused) 1.2f else 1f).clip(CircleShape).background(color)
                    .border(2.dp, if (selected) Color.White else if (focused) Color.White.copy(alpha = 0.5f) else Color.Transparent, CircleShape),
            )
            Text(name, style = TvType.caption, color = if (focused) Color.White else TvColors.secondary)
        }
    }
}

// MARK: - Security

@Composable
private fun SecurityPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage("Security", "The app asks for your PIN each time it opens and whenever it returns from the background.", firstFocus = first) {
        item {
            TvToggleRow("Enable PIN Lock", TvSecurity.isPinLockEnabled && TvSecurity.isPinSet, { enabled ->
                if (enabled) {
                    if (!TvSecurity.isPinSet) TvNav.push(TvPasscodeSetupRoute()) else TvSecurity.setLockEnabled(true)
                } else TvSecurity.setLockEnabled(false)
            }, Modifier.focusRequester(first))
        }
        if (TvSecurity.isPinSet) {
            item { TvListRow("Change PIN", { TvNav.push(TvPasscodeSetupRoute()) }) }
            item { TvListRow("Remove PIN", { TvSecurity.removePin() }, destructive = true) }
        }
    }
}

/** Full-screen PIN setup (iOS: `fullScreenCover` with `TVPasscodeSetupView`). */
class TvPasscodeSetupRoute : TvRoute {
    override val key = "pinSetup.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()

    @Composable
    override fun Content() = TvPasscodeSetup { TvNav.pop() }
}

// MARK: - stashy+

/**
 * iOS: `TVStashyPlusSettingsView` — status, the plans (Google Play Billing, bought through
 * [StashyPlus.purchase] with the TV activity) and Restore Purchases.
 */
@Composable
private fun StashyPlusPage() {
    val first = remember { FocusRequester() }
    val context = LocalContext.current
    LaunchedEffect(Unit) { if (StashyPlus.products.isEmpty()) StashyPlus.fetchProducts() }
    val source = StashyPlus.source
    val busy = StashyPlus.purchasingProductID != null || StashyPlus.isRestoringPurchases
    TvSettingsPage("stashy+", null, firstFocus = first) {
        item {
            TvListRow(
                source.statusTitle, {}, Modifier.focusRequester(first), subtitle = source.statusDetail,
                leading = if (StashyPlus.isUnlocked) TvIcons.checkSeal else TvIcons.lock, leadingTint = if (StashyPlus.isUnlocked) TvColors.green else TvColors.tint,
            )
        }
        item { TvListRow("Channels", {}, leading = TvIcons.sparklesTv, leadingTint = TvColors.tint) }
        item { TvSectionFooter("stashy+ unlocks premium features across stashy for phone, tablet and Android TV with one purchase.") }
        if (StashyPlus.shouldOfferPurchases) {
            item { TvSectionHeader("Unlock") }
            if (StashyPlus.isLoadingProducts && StashyPlus.products.isEmpty()) {
                item { TvLoading() }
            } else {
                items(StashyPlus.products, key = { it.productId }) { product ->
                    val purchasing = StashyPlus.purchasingProductID == product.productId
                    TvListRow(
                        StashyPlusProduct.displayNames[product.productId] ?: product.name,
                        { (context as? Activity ?: TvActivity.current)?.let { StashyPlus.purchase(it, product) } },
                        subtitle = if (product.productId in StashyPlusProduct.subscriptionIDs) "Auto-renews · cancel anytime" else "One-time purchase",
                        value = if (purchasing) "…" else StashyPlus.price(product),
                        enabled = !busy,
                    )
                }
                StashyPlus.lastProductError?.let { item { TvSectionFooter(it) } }
            }
            item {
                TvSectionFooter(
                    if (source == StashyPlusSource.Subscription) "Your subscription is active. Buying Lifetime keeps stashy+ forever, even after cancelling."
                    else "Payment is charged to your Google Play account. Subscriptions renew automatically unless cancelled. Manage or cancel anytime in the Play Store.",
                )
            }
            item { Spacer(Modifier.height(pt(28))) }
            item { TvListRow("Restore Purchases", { StashyPlus.restore() }, value = if (StashyPlus.isRestoringPurchases) "…" else null, enabled = !busy) }
        }
        StashyPlus.message?.let { item { TvSectionFooter(it) } }
    }
}

// MARK: - Default sorting / filters / tabs

private val contentTabs = listOf(AppTab.Scenes to "Scenes", AppTab.Performers to "Performers", AppTab.Studios to "Studios", AppTab.Tags to "Tags", AppTab.Groups to "Groups")

@Composable
private fun DefaultSortPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage("Default Sorting", "The sort order each section opens with.", firstFocus = first) {
        contentTabs.forEachIndexed { i, (tab, label) ->
            item {
                val mode = tab.filterMode!!
                val current = TabManager.getPersistentSortOption(tab)?.takeIf { raw -> SortCatalog.option(mode, raw) != null } ?: TvSortLabels.defaultRaw(mode)
                TvPickerRow(label, SortCatalog.choices(mode).map { TvOption(it.raw, it.label) }, current, { TabManager.setPersistentSortOption(tab, it) },
                    if (i == 0) Modifier.focusRequester(first) else Modifier)
            }
        }
    }
}

@Composable
private fun DefaultFiltersPage() {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { SavedFiltersStore.load(force = true) }
    val none = "\u0000none"
    TvSettingsPage("Default Filters", "A saved filter from your Stash server, applied automatically when a section opens.", firstFocus = first) {
        contentTabs.forEachIndexed { i, (tab, label) ->
            item {
                SavedFiltersStore.version
                val filters = SavedFiltersStore.forMode(tab.filterMode ?: FilterMode.Unknown)
                TvPickerRow(
                    label, listOf(TvOption(none, "None")) + filters.map { TvOption(it.id, it.name) }, TabManager.getDefaultFilterId(tab) ?: none,
                    { id -> if (id == none) TabManager.setDefaultFilter(tab, null, null) else TabManager.setDefaultFilter(tab, id, filters.firstOrNull { it.id == id }?.name) },
                    if (i == 0) Modifier.focusRequester(first) else Modifier,
                )
            }
        }
    }
}

@Composable
private fun VisibleTabsPage() {
    val first = remember { FocusRequester() }
    val rows = listOf(
        Triple(AppTab.Scenes, "Scenes", TvIcons.film), Triple(AppTab.Performers, "Performers", TvIcons.person3), Triple(AppTab.Studios, "Studios", TvIcons.building),
        Triple(AppTab.Tags, "Tags", TvIcons.tag), Triple(AppTab.Groups, "Groups", TvIcons.stack), Triple(AppTab.Galleries, "Galleries", TvIcons.photoStack),
        Triple(AppTab.Images, "Images", TvIcons.photo),
    )
    TvSettingsPage("Visible Tabs", "Sections you turn off disappear from the sidebar. Home, Search and Settings always stay.", firstFocus = first) {
        rows.forEachIndexed { i, (tab, label, icon) ->
            item { TvToggleRow(label, TabManager.isVisible(tab), { TabManager.toggle(tab) }, if (i == 0) Modifier.focusRequester(first) else Modifier, leading = icon) }
        }
    }
}

// MARK: - Subtitles

@Composable
private fun SubtitlesPage() {
    val first = remember { FocusRequester() }
    val languages = remember { subtitleLanguageOptions() }
    val languageLabel = languages.firstOrNull { it.first == TabManager.subtitlePreferredLanguage }?.second ?: "Any"
    TvSettingsPage(
        "Subtitles",
        "Subtitles start on the preferred language as soon as a scene's tracks are known. The look applies to every player on this TV.",
        detail = { SubtitlePreview() }, firstFocus = first,
    ) {
        item { TvSectionHeader("Defaults") }
        item { TvToggleRow("Show subtitles automatically", TabManager.subtitlesAutoEnabled, { TabManager.subtitlesAutoEnabled = it }, Modifier.focusRequester(first)) }
        item { TvListRow("Preferred language", { TvNav.push(TvLanguagePickerRoute()) }, value = languageLabel) }
        item { TvSectionHeader("Appearance") }
        item { TvPickerRow("Size", SubtitleFontSize.entries.map { TvOption(it, it.label) }, TabManager.subtitleFontSize, { TabManager.subtitleFontSize = it }) }
        item { TvPickerRow("Font", SubtitleFontFamily.entries.map { TvOption(it, it.label) }, TabManager.subtitleFontFamily, { TabManager.subtitleFontFamily = it }) }
        item { TvPickerRow("Text color", SubtitleTextColorChoice.entries.map { TvOption(it, it.label) }, TabManager.subtitleTextColor, { TabManager.subtitleTextColor = it }) }
        item { TvToggleRow("Background box", TabManager.subtitleBoxEnabled, { TabManager.subtitleBoxEnabled = it }) }
        item {
            TvPickerRow("Background color", SubtitleBackgroundChoice.entries.map { TvOption(it, it.label) }, TabManager.subtitleBackgroundColor,
                { TabManager.subtitleBackgroundColor = it }, enabled = TabManager.subtitleBoxEnabled)
        }
    }
}

/** The cue as the player draws it (iOS `preview` of `TVSubtitleSettingsView`). */
@Composable
private fun SubtitlePreview() {
    val size = when (TabManager.subtitleFontSize) { SubtitleFontSize.Small -> 14; SubtitleFontSize.Medium -> 18; SubtitleFontSize.Large -> 22; SubtitleFontSize.ExtraLarge -> 28 }
    val family = when (TabManager.subtitleFontFamily) { SubtitleFontFamily.Serif -> FontFamily.Serif; SubtitleFontFamily.Monospaced -> FontFamily.Monospace; else -> FontFamily.Default }
    val box = if (TabManager.subtitleBoxEnabled) TabManager.subtitleBackgroundColor.argb?.let { Color(it) } else null
    Box(
        Modifier.width(pt(620)).height(pt(300)).clip(RoundedCornerShape(pt(16))).background(Brush.linearGradient(listOf(Color(0xFF383838), Color(0xFF0F0F0F)))),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Text(
            "Sample subtitle",
            Modifier.padding(bottom = pt(24)).then(if (box != null) Modifier.clip(RoundedCornerShape(pt(8))).background(box).padding(horizontal = pt(16), vertical = pt(6)) else Modifier),
            style = androidx.compose.ui.text.TextStyle(
                fontSize = (size * 0.85f).sp, fontFamily = family, fontWeight = FontWeight.SemiBold,
                shadow = if (box == null) Shadow(Color.Black, blurRadius = 4f) else null,
            ),
            color = Color(TabManager.subtitleTextColor.argb), textAlign = TextAlign.Center,
        )
    }
}

/** iOS: `TVSubtitleLanguagePickerView` — "Common" then "All Languages"; picking returns. */
class TvLanguagePickerRoute : TvRoute {
    override val key = "language.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()

    @Composable
    override fun Content() {
        val options = remember { subtitleLanguageOptions() }
        val common = setOf("any", "en", "de", "es", "fr", "it", "pt", "nl", "ru", "ja", "zh", "ko")
        val selectedFocus = remember { FocusRequester() }
        BackHandler { TvNav.pop() }
        TvSettingsPage("Preferred Language", "The language a scene's subtitles start with. \"Any\" takes the first ordinary track in the file.", firstFocus = selectedFocus) {
            item { TvSectionHeader("Common") }
            items(options.filter { it.first in common }, key = { "c.${it.first}" }) { option -> LanguageRow(option, selectedFocus) }
            item { TvSectionHeader("All Languages") }
            items(options.filter { it.first !in common }, key = { "a.${it.first}" }) { option -> LanguageRow(option, selectedFocus) }
        }
    }

    @Composable
    private fun LanguageRow(option: Pair<String, String>, selectedFocus: FocusRequester) {
        val selected = TabManager.subtitlePreferredLanguage == option.first
        TvListRow(
            option.second, { TabManager.subtitlePreferredLanguage = option.first; TvNav.pop() },
            if (selected) Modifier.focusRequester(selectedFocus) else Modifier,
            trailingIcon = if (selected) TvIcons.check else null, trailingTint = TvColors.tint,
        )
    }
}

// MARK: - Count As Played / Maintenance / About

@Composable
private fun PlayCountPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage("Count As Played", "How long a scene has to play before it counts as played and its position is saved.", firstFocus = first) {
        items(TabManager.playCountThresholdOptions) { seconds ->
            val selected = TabManager.playCountPlayerSeconds == seconds
            TvListRow(
                TabConfigLogic.playCountThresholdLabel(seconds), { TabManager.playCountPlayerSeconds = seconds },
                if (selected) Modifier.focusRequester(first) else Modifier, trailingIcon = if (selected) TvIcons.check else null,
            )
        }
    }
}

@Composable
private fun MaintenancePage() {
    val first = remember { FocusRequester() }
    val context = LocalContext.current
    var cleared by remember { mutableStateOf(false) }
    TvSettingsPage("Maintenance", "Removes the cached artwork for the active server. Images are downloaded again as they appear.", firstFocus = first) {
        item {
            // Never disabled: it is the page's only button.
            TvListRow("Clear Image Cache", {
                if (ServerConfigManager.activeConfig == null) return@TvListRow
                coil3.SingletonImageLoader.get(context).let { it.memoryCache?.clear(); it.diskCache?.clear() }
                cleared = true
            }, Modifier.focusRequester(first), value = if (cleared) "Cleared" else null)
        }
    }
}

@Composable
private fun AboutPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage("About", "Version and build number of this app.", firstFocus = first) {
        item { TvListRow("App", {}, Modifier.focusRequester(first), value = "stashy for Android TV") }
        item { TvListRow("Version", {}, value = BuildConfig.VERSION_NAME) }
        item { TvListRow("Build", {}, value = "${BuildConfig.VERSION_CODE}") }
    }
}
