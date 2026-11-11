package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.UiText
import de.letzgo.stashy.tr
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
enum class TvSettingsEntry(private val titleText: UiText, @androidx.annotation.StringRes private val summaryRes: Int) {
    Servers(UiText(R.string.servers), R.string.hint_add_stash_servers_switch_between),
    Appearance(UiText(R.string.appearance), R.string.hint_pick_accent_color_used_for),
    Security(UiText(R.string.security), R.string.hint_require_pin_before_app_opens),
    StashyPlus(UiText("stashy+"), R.string.hint_premium_features_including_channels_continuous),
    DefaultSort(UiText(R.string.default_sorting), R.string.hint_sort_order_each_section_opens),
    DefaultFilters(UiText(R.string.default_filters), R.string.hint_saved_server_filter_to_apply),
    VisibleTabs(UiText(R.string.visible_tabs), R.string.hint_hide_sections_you_do_not),
    Subtitles(UiText(R.string.subtitles), R.string.hint_turn_subtitles_on_automatically_choose),
    PlayCount(UiText(R.string.count_as_played), R.string.hint_how_long_scene_has_to),
    Maintenance(UiText(R.string.maintenance), R.string.hint_clear_cached_artwork_for_active),
    About(UiText(R.string.about), R.string.version_build_number_and_updates);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = titleText.text
    /** Read on use: a constant must not freeze its text at class load. */
    val summary: String get() = tr(summaryRes)

    val icon: ImageVector get() = when (this) {
        Servers -> TvIcons.server
        Appearance -> TvIcons.brush
        Security -> TvIcons.lock
        StashyPlus -> TvIcons.sparklesTv
        DefaultSort -> TvIcons.sort
        DefaultFilters -> TvIcons.filter
        VisibleTabs -> TvIcons.gridGroup
        Subtitles -> TvIcons.captions
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
            item { TvSectionHeader(tr(R.string.general)) }
            item { EntryRow(model, TvSettingsEntry.Servers) }
            item { EntryRow(model, TvSettingsEntry.Appearance) }
            item { EntryRow(model, TvSettingsEntry.Security) }
            item { EntryRow(model, TvSettingsEntry.StashyPlus) }
            item { TvSectionHeader(tr(R.string.content)) }
            item { EntryRow(model, TvSettingsEntry.DefaultSort) }
            item { EntryRow(model, TvSettingsEntry.DefaultFilters) }
            item { EntryRow(model, TvSettingsEntry.VisibleTabs) }
            item { TvSectionHeader(tr(R.string.playback)) }
            item { EntryRow(model, TvSettingsEntry.Subtitles) }
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
    if (firstFocus != null) TvInitialFocus(LocalTvFocusMemory.current ?: remember { TvFocusMemory() }, firstFocus, name = "settings.$title")
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
    TvSettingsPage(tr(R.string.servers), tr(R.string.hint_add_stash_servers_and_switch), firstFocus = first) {
        item { TvSectionHeader(tr(R.string.active_server)) }
        item {
            if (active != null) {
                TvListRow(
                    active.name, { TvNav.push(TvServerDetailRoute()) }, Modifier.focusRequester(first).tvFocusMemory(memory, "active"),
                    subtitle = active.baseURL, leading = TvIcons.server, leadingTint = TvColors.tint, trailingIcon = TvIcons.checkCircle, trailingTint = TvColors.green,
                    onLongClick = { TvNav.push(TvServerFormRoute(active)) },
                )
            } else {
                TvListRow(tr(R.string.empty_server_configured), {}, Modifier.focusRequester(first), leading = TvIcons.warning, leadingTint = TvColors.yellow)
            }
        }
        if (others.isNotEmpty()) {
            item { TvSectionHeader(tr(R.string.switch_server)) }
            items(others, key = { it.id }) { server ->
                TvListRow(server.name, { ServerConfigManager.activate(server) }, Modifier.tvFocusMemory(memory, server.id), subtitle = server.baseURL, onLongClick = { actionsFor = server })
            }
        }
        item { Spacer(Modifier.height(pt(28))) }
        item { TvListRow(tr(R.string.action_add_server), { TvNav.push(TvServerFormRoute(null)) }, Modifier.tvFocusMemory(memory, "add"), leading = TvIcons.plus, leadingTint = TvColors.tint) }
    }
    actionsFor?.let { server ->
        TvOptionDialog(server.name, listOf(TvOption("edit", tr(R.string.action_edit)), TvOption("delete", tr(R.string.action_delete))), null, { action ->
            if (action == "edit") TvNav.push(TvServerFormRoute(server)) else deleting = server
        }, { actionsFor = null })
    }
    deleting?.let { server ->
        TvConfirmDialog(tr(R.string.confirm_delete_arg, server.name), tr(R.string.action_delete), { ServerConfigManager.delete(server) }) { deleting = null }
    }
}

/** iOS: `TVServerDetailView` — status, version, re-test and the connection details. */
class TvServerDetailRoute : TvRoute {
    override val key = "serverDetail.${System.nanoTime()}"
    override val focus = TvFocusMemory()
    private var connected by mutableStateOf<Boolean?>(null)
    private var status by mutableStateOf(tr(R.string.checking_menu))
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
                    is ServerConnection.Outcome.Stash -> { connected = true; status = tr(R.string.stash_arg, r.version) }
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
                item { Text(tr(R.string.empty_server_configured), style = TvType.title3, color = TvColors.secondary) }
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
                        Text(if (ok) tr(R.string.connected) else tr(R.string.not_connected), style = TvType.title3.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                        Text(status, style = TvType.callout, color = Color.White.copy(alpha = 0.6f))
                    }
                    if (testing) TvSpinner(pt(40))
                }
            }
            item {
                // Never disabled: it is the only focusable element (Back must have a target).
                TvButton({ test() }, Modifier.focusRequester(button)) {
                    if (testing) TvSpinner(pt(30)) else Icon(TvIcons.retry, null, Modifier.size(pt(30)))
                    Text(tr(R.string.action_test_connection), style = TvType.headline)
                }
            }
            item {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(14))).background(Color.White.copy(alpha = 0.05f)).padding(pt(20)),
                    verticalArrangement = Arrangement.spacedBy(pt(16)),
                ) {
                    DetailLine(tr(R.string.protocol), config.serverProtocol.name)
                    DetailLine(tr(R.string.address), config.serverAddress)
                    config.port?.takeIf { it.isNotEmpty() }?.let { DetailLine(tr(R.string.port), it) }
                    DetailLine(tr(R.string.api_key), if (!config.apiKey.isNullOrEmpty()) "•••• configured" else tr(R.string.not_set))
                }
            }
        }
        TvRequestFocus(button, "server.test")
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
    TvSettingsPage(tr(R.string.appearance), tr(R.string.hint_pick_accent_color_used_for), firstFocus = first) {
        item {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(pt(14))).background(Color.White.copy(alpha = 0.06f)).padding(pt(28)), verticalArrangement = Arrangement.spacedBy(pt(16))) {
                Text(tr(R.string.accent_color), style = TvType.headline, color = Color.White)
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
    TvSettingsPage(tr(R.string.security), tr(R.string.hint_app_asks_for_your_pin), firstFocus = first) {
        item {
            TvToggleRow(tr(R.string.action_enable_pin_lock), TvSecurity.isPinLockEnabled && TvSecurity.isPinSet, { enabled ->
                if (enabled) {
                    if (!TvSecurity.isPinSet) TvNav.push(TvPasscodeSetupRoute()) else TvSecurity.setLockEnabled(true)
                } else TvSecurity.setLockEnabled(false)
            }, Modifier.focusRequester(first))
        }
        if (TvSecurity.isPinSet) {
            item { TvListRow(tr(R.string.action_change_pin), { TvNav.push(TvPasscodeSetupRoute()) }) }
            item { TvListRow(tr(R.string.action_remove_pin), { TvSecurity.removePin() }, destructive = true) }
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
    var licenseInput by remember { mutableStateOf("") }
    var licenseError by remember { mutableStateOf(StashyPlus.expiredLicense?.let { tr(R.string.hint_your_license_key_expired_on, it.expiresText) }) }
    TvSettingsPage("stashy+", null, firstFocus = first) {
        val license = StashyPlus.license
        item {
            TvListRow(
                source.statusTitle, {}, Modifier.focusRequester(first),
                subtitle = license?.let { l -> tr(R.string.licensed_to_arg, l.name) + (l.expiresText?.let { " · valid until $it" } ?: "") } ?: source.statusDetail,
                leading = if (StashyPlus.isUnlocked) TvIcons.checkSeal else TvIcons.lock, leadingTint = if (StashyPlus.isUnlocked) TvColors.green else TvColors.tint,
            )
        }
        item { TvListRow(tr(R.string.channels), {}, leading = TvIcons.sparklesTv, leadingTint = TvColors.tint) }
        if (StashyPlus.usesLicenseKeys) {
            // Sideload flavor: offline license key instead of Google Play.
            item { TvSectionHeader(tr(R.string.license)) }
            if (license != null) {
                item { TvListRow(tr(R.string.action_remove_license), { StashyPlus.removeLicense() }, destructive = true) }
                item { TvSectionFooter(tr(R.string.hint_license_arg_key_is_stored, license.id)) }
            } else {
                item { TvTextField(tr(R.string.license_key_stashy), licenseInput, { licenseInput = it; licenseError = null }, onSubmit = { licenseError = StashyPlus.activateLicense(licenseInput) }) }
                item { TvListRow(tr(R.string.activate), { licenseError = StashyPlus.activateLicense(licenseInput) }, enabled = licenseInput.isNotBlank()) }
                item { TvSectionFooter(licenseError ?: tr(R.string.hint_this_version_of_stashy_unlocks)) }
            }
        } else {
            item { TvSectionFooter(tr(R.string.hint_stashy_plus_unlocks_premium_features_across)) }
        }
        if (StashyPlus.shouldOfferPurchases) {
            item { TvSectionHeader(tr(R.string.action_unlock)) }
            if (StashyPlus.isLoadingProducts && StashyPlus.products.isEmpty()) {
                item { TvLoading() }
            } else {
                items(StashyPlus.products, key = { it.productId }) { product ->
                    val purchasing = StashyPlus.purchasingProductID == product.productId
                    TvListRow(
                        StashyPlusProduct.displayNames[product.productId] ?: product.name,
                        { (context as? Activity ?: TvActivity.current)?.let { StashyPlus.purchase(it, product) } },
                        subtitle = if (product.productId in StashyPlusProduct.subscriptionIDs) tr(R.string.auto_renews_cancel_anytime) else tr(R.string.one_time_purchase),
                        value = if (purchasing) "…" else StashyPlus.price(product),
                        enabled = !busy,
                    )
                }
                StashyPlus.lastProductError?.let { item { TvSectionFooter(it) } }
            }
            item {
                TvSectionFooter(
                    if (source == StashyPlusSource.Subscription) tr(R.string.hint_your_subscription_is_active_buying)
                    else tr(R.string.hint_payment_is_charged_to_your_google),
                )
            }
            item { Spacer(Modifier.height(pt(28))) }
            item { TvListRow(tr(R.string.action_restore_purchases), { StashyPlus.restore() }, value = if (StashyPlus.isRestoringPurchases) "…" else null, enabled = !busy) }
        }
        StashyPlus.message?.let { item { TvSectionFooter(it) } }
    }
}

// MARK: - Default sorting / filters / tabs

private val contentTabs = listOf(AppTab.Scenes to tr(R.string.scenes), AppTab.Performers to tr(R.string.performers), AppTab.Studios to tr(R.string.studios), AppTab.Tags to tr(R.string.tags), AppTab.Groups to tr(R.string.groups))

@Composable
private fun DefaultSortPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage(tr(R.string.default_sorting), tr(R.string.hint_sort_order_each_section_opens), firstFocus = first) {
        contentTabs.forEachIndexed { i, (tab, label) ->
            item {
                val mode = tab.filterMode!!
                val current = TabManager.getPersistentSortOption(tab)?.takeIf { raw -> SortCatalog.option(mode, raw) != null } ?: TvSortLabels.defaultRaw(mode)
                TvPickerRow(label, SortCatalog.choices(mode).map { TvOption(it.raw, it.label) }, current, { TabManager.setPersistentSortOption(tab, it) },
                    if (i == 0) Modifier.focusRequester(first) else Modifier)
            }
        }
        if (de.letzgo.stashy.data.ServerCapabilities.supports032) item {
            TvToggleRow(tr(R.string.studio_counts_include_sub_studios), de.letzgo.stashy.data.StudioCountsStore.includeSubStudios, { de.letzgo.stashy.data.StudioCountsStore.includeSubStudios = it })
        }
    }
}

@Composable
private fun DefaultFiltersPage() {
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { SavedFiltersStore.load(force = true) }
    val none = "\u0000none"
    TvSettingsPage(tr(R.string.default_filters), tr(R.string.hint_saved_filter_from_your_stash), firstFocus = first) {
        contentTabs.forEachIndexed { i, (tab, label) ->
            item {
                SavedFiltersStore.version
                val filters = SavedFiltersStore.forMode(tab.filterMode ?: FilterMode.Unknown)
                TvPickerRow(
                    label, listOf(TvOption(none, tr(R.string.none))) + filters.map { TvOption(it.id, it.name) }, TabManager.getDefaultFilterId(tab) ?: none,
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
        Triple(AppTab.Scenes, tr(R.string.scenes), TvIcons.film), Triple(AppTab.Performers, tr(R.string.performers), TvIcons.person3), Triple(AppTab.Studios, tr(R.string.studios), TvIcons.building),
        Triple(AppTab.Tags, tr(R.string.tags), TvIcons.tag), Triple(AppTab.Groups, tr(R.string.groups), TvIcons.stack), Triple(AppTab.Galleries, tr(R.string.galleries), TvIcons.photoStack),
        Triple(AppTab.Images, tr(R.string.images), TvIcons.photo),
    )
    TvSettingsPage(tr(R.string.visible_tabs), tr(R.string.hint_sections_you_turn_off_disappear), firstFocus = first) {
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
    val languageLabel = languages.firstOrNull { it.first == TabManager.subtitlePreferredLanguage }?.second ?: tr(R.string.any)
    TvSettingsPage(
        tr(R.string.subtitles),
        tr(R.string.hint_subtitles_start_on_preferred_language_as),
        detail = { SubtitlePreview() }, firstFocus = first,
    ) {
        item { TvSectionHeader(tr(R.string.defaults)) }
        item { TvToggleRow(tr(R.string.action_show_subtitles_automatically), TabManager.subtitlesAutoEnabled, { TabManager.subtitlesAutoEnabled = it }, Modifier.focusRequester(first)) }
        item { TvListRow(tr(R.string.preferred_language), { TvNav.push(TvLanguagePickerRoute()) }, value = languageLabel) }
        item { TvSectionHeader(tr(R.string.appearance)) }
        item { TvPickerRow(tr(R.string.size), SubtitleFontSize.entries.map { TvOption(it, it.label) }, TabManager.subtitleFontSize, { TabManager.subtitleFontSize = it }) }
        item { TvPickerRow(tr(R.string.font), SubtitleFontFamily.entries.map { TvOption(it, it.label) }, TabManager.subtitleFontFamily, { TabManager.subtitleFontFamily = it }) }
        item { TvPickerRow(tr(R.string.text_color), SubtitleTextColorChoice.entries.map { TvOption(it, it.label) }, TabManager.subtitleTextColor, { TabManager.subtitleTextColor = it }) }
        item { TvToggleRow(tr(R.string.background_box), TabManager.subtitleBoxEnabled, { TabManager.subtitleBoxEnabled = it }) }
        item {
            TvPickerRow(tr(R.string.background_color), SubtitleBackgroundChoice.entries.map { TvOption(it, it.label) }, TabManager.subtitleBackgroundColor,
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
            tr(R.string.sample_subtitle),
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
        TvSettingsPage(tr(R.string.preferred_language), tr(R.string.hint_language_scenes_subtitles_start_with), firstFocus = selectedFocus) {
            item { TvSectionHeader(tr(R.string.common)) }
            items(options.filter { it.first in common }, key = { "c.${it.first}" }) { option -> LanguageRow(option, selectedFocus) }
            item { TvSectionHeader(tr(R.string.all_languages)) }
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
    TvSettingsPage(tr(R.string.count_as_played), tr(R.string.hint_how_long_scene_has_to), firstFocus = first) {
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
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var cleared by remember { mutableStateOf(false) }
    TvSettingsPage(tr(R.string.maintenance), tr(R.string.hint_removes_cached_artwork_for_active), firstFocus = first) {
        item {
            // Never disabled: it is the page's only button. iOS `clearCurrentServerCache()`.
            TvListRow(tr(R.string.action_clear_image_cache), {
                if (ServerConfigManager.activeConfig == null) return@TvListRow
                scope.launch { cleared = de.letzgo.stashy.data.ServerImageCache.clearActiveServer(context) }
            }, Modifier.focusRequester(first), value = if (cleared) tr(R.string.cleared) else null)
        }
    }
}

@Composable
private fun AboutPage() {
    val first = remember { FocusRequester() }
    TvSettingsPage(tr(R.string.about), tr(R.string.hint_version_and_build_number_of), firstFocus = first) {
        item { TvListRow(tr(R.string.app), {}, Modifier.focusRequester(first), value = "stashy for Android TV") }
        item { TvListRow(tr(R.string.version), {}, value = BuildConfig.VERSION_NAME) }
        item { TvListRow(tr(R.string.build), {}, value = "${BuildConfig.VERSION_CODE}") }
        if (de.letzgo.stashy.data.AppUpdate.isEnabled) item {
            val context = LocalContext.current
            val scope = androidx.compose.runtime.rememberCoroutineScope()
            TvListRow(tr(R.string.check_for_updates), { scope.launch { de.letzgo.stashy.data.AppUpdate.check(context, manual = true) } })
        }
    }
}
