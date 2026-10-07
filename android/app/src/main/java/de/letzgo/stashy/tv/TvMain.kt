package de.letzgo.stashy.tv

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.zIndex
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.Tag
import kotlinx.coroutines.delay

/**
 * The root screen of every sidebar entry, alive for one server (iOS: the views inside the
 * per-tab `NavigationStack`s of `TVMainTabView`, which keep their state between tab switches).
 */
object TvRoots {
    private var serverId: String? = "<none>"
    private var dashboardModel: TvDashboardModel? = null
    private var searchModel: TvSearchModel? = null
    private var settingsModel: TvSettingsModel? = null
    private val catalogs = HashMap<TvRootTab, TvCatalogModel<*>>()

    fun ensure(server: String?) {
        if (server == serverId) return
        serverId = server
        dashboardModel?.dispose(); searchModel?.dispose()
        catalogs.values.forEach { it.dispose() }
        dashboardModel = null; searchModel = null; settingsModel = null
        catalogs.clear()
    }

    val dashboard: TvDashboardModel get() = dashboardModel ?: TvDashboardModel().also { dashboardModel = it }
    val search: TvSearchModel get() = searchModel ?: TvSearchModel().also { searchModel = it }
    val settings: TvSettingsModel get() = settingsModel ?: TvSettingsModel().also { settingsModel = it }

    @Suppress("UNCHECKED_CAST")
    fun <T> catalog(tab: TvRootTab, mode: FilterMode, key: (T) -> String): TvCatalogModel<T> =
        catalogs.getOrPut(tab) { TvCatalogModel(mode, null, key) } as TvCatalogModel<T>

    fun memory(tab: TvRootTab): TvFocusMemory? = when (tab) {
        TvRootTab.Home -> dashboard.focus
        TvRootTab.Search -> search.focus
        TvRootTab.Settings -> settings.focus
        else -> catalogs[tab]?.focus
    }

    /** App back from the background: new scenes can't be announced, reload the rows (tvOS). */
    fun onForeground() { dashboardModel?.load() }
}

private data class SidebarItem(val tab: TvRootTab, val icon: ImageVector, val appTab: AppTab?)

private val sidebarLibrary = listOf(
    SidebarItem(TvRootTab.Scenes, TvIcons.film, AppTab.Scenes),
    SidebarItem(TvRootTab.Performers, TvIcons.person3, AppTab.Performers),
    SidebarItem(TvRootTab.Studios, TvIcons.building, AppTab.Studios),
    SidebarItem(TvRootTab.Tags, TvIcons.tag, AppTab.Tags),
    SidebarItem(TvRootTab.Groups, TvIcons.stack, AppTab.Groups),
    SidebarItem(TvRootTab.Galleries, TvIcons.photoStack, AppTab.Galleries),
    SidebarItem(TvRootTab.Images, TvIcons.photo, AppTab.Images),
)

/** iOS: `TVApp` body — server setup, the sidebar app, and the PIN lock over everything. */
@Composable
fun TvApp() {
    val config = ServerConfigManager.activeConfig
    val serverId = config?.id
    LaunchedEffect(serverId) {
        // Pushed pages and root models belong to the old server.
        TvRoots.ensure(serverId)
        TvNav.reset()
        TabManager.ensureLoaded()
    }
    TvRoots.ensure(serverId)
    TvNav.rootMemoryProvider = { TvRoots.memory(it) }
    Box(Modifier.fillMaxSize().background(TvColors.background).onFocusChanged { TvNav.appHasFocus = it.hasFocus }) {
        TvNav.shellShown = !TvSecurity.isAppLocked && config?.hasValidConfig == true
        when {
            de.letzgo.stashy.data.BetaExpiry.expired -> de.letzgo.stashy.ui.BetaExpiredScreen()
            TvSecurity.isAppLocked -> TvPasscodeEntry()
            config?.hasValidConfig != true -> TvServerSetup()
            else -> TvMainShell()
        }
    }
    if (!TvSecurity.isAppLocked && config?.hasValidConfig == true) TvAuthAlert()
    de.letzgo.stashy.ui.AppUpdateDialog()
}

/**
 * iOS `MainTabView` "Authentication Required" alert on a 401 (`AuthEvents`, shown once per
 * server until its key changes). "Update API Key" opens the active server's form in Settings.
 */
@Composable
private fun TvAuthAlert() {
    val active = ServerConfigManager.activeConfig ?: return
    if (de.letzgo.stashy.data.AuthEvents.pendingServerId != active.id) return
    TvOptionDialog(
        "Authentication Required\nYour API key is invalid or expired. Please check your server configuration.",
        listOf(TvOption(true, "Update API Key")), null,
        onSelect = {
            de.letzgo.stashy.data.AuthEvents.consume()
            TvNav.dismissFullScreen()
            if (TvNav.selected != TvRootTab.Settings) TvNav.select(TvRootTab.Settings)
            while (TvNav.pop()) Unit
            TvNav.push(TvServerFormRoute(active))
        },
        onDismiss = { de.letzgo.stashy.data.AuthEvents.consume() },
    )
}

/**
 * iOS: `TVMainTabView` — a sidebar (Search, Home, "Library" section with the visible catalogs,
 * Settings) with one back stack per entry. The sidebar collapses to icons while the content has
 * focus and expands over the content when focus moves into it. Back on a tab root moves focus to
 * the sidebar; Back in the sidebar leaves the app.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun TvMainShell() {
    val selected = TvNav.selected
    TvNav.version
    val top = TvNav.top(selected)
    var sidebarFocused by remember { mutableStateOf(false) }
    val visibleLibrary = sidebarLibrary.filter { item -> item.appTab == null || TabManager.isVisible(item.appTab) }
    val requesters = remember { TvRootTab.entries.associateWith { FocusRequester() } }
    val inputModeManager = androidx.compose.ui.platform.LocalInputModeManager.current

    LaunchedEffect(TabManager.tabs) { TvNav.validate(TvRootTab.fixed + visibleLibrary.map { it.tab }) }
    LaunchedEffect(TvNav.sidebarFocusRequest) {
        if (TvNav.sidebarFocusRequest > 0) {
            // The items become focusable on the next frame: retry until the selected one has focus.
            val inputMode = inputModeManager
            repeat(8) {
                delay(30)
                inputMode.requestKeyboardMode()
                runCatching { requesters.getValue(TvNav.selected).requestFocus() }
                if (TvNav.sidebarFocused) return@LaunchedEffect
            }
        }
    }
    BackHandler(enabled = !sidebarFocused) {
        if (!TvNav.pop()) TvNav.focusSidebar()
    }

    val holder = rememberSaveableStateHolder()
    val fullScreen = top?.fullScreen == true
    LaunchedEffect(fullScreen) { if (fullScreen) { sidebarFocused = false; TvNav.sidebarFocused = false } }
    val collapsed = pt(120)

    Box(Modifier.fillMaxSize()) {
        val focusManager = LocalFocusManager.current
        val stateKey = top?.key ?: "root.${selected.name}.${ServerConfigManager.activeConfig?.id}"
        val screenMemory = top?.focus ?: TvNav.rootMemory(selected)
        LaunchedEffect(stateKey) {
            TvFocusLog.screen = stateKey
            delay(1200)
            TvFocusLog.log("settled", if (TvNav.sidebarFocused) "sidebar" else if (TvNav.contentHasFocus) (screenMemory.lastKey ?: "content(unnamed)") else null)
        }
        Box(
            Modifier.fillMaxSize().padding(start = if (fullScreen) pt(0) else collapsed)
                .onFocusChanged { TvNav.contentHasFocus = it.hasFocus }
                .onKeyEvent { e ->
                    // Left from the leftmost element (nothing else to the left) opens the sidebar;
                    // the sidebar is not focusable otherwise.
                    if (fullScreen || e.type != KeyEventType.KeyDown || e.nativeKeyEvent.keyCode != android.view.KeyEvent.KEYCODE_DPAD_LEFT) return@onKeyEvent false
                    if (!focusManager.moveFocus(FocusDirection.Left)) TvNav.openSidebarFromContent()
                    true
                },
        ) {
            holder.SaveableStateProvider(stateKey) {
                androidx.compose.runtime.CompositionLocalProvider(LocalTvFocusMemory provides screenMemory) {
                    if (top != null) top.Content() else RootContent(selected)
                }
            }
        }
        if (!fullScreen) {
            Sidebar(selected, visibleLibrary, sidebarFocused, TvNav.sidebarEnabled, requesters) { focused ->
                if (focused == sidebarFocused) return@Sidebar
                sidebarFocused = focused
                TvNav.sidebarFocused = focused
                if (focused) TvFocusLog.log("sidebar", TvNav.selected.title)
                // Leaving the sidebar makes it unfocusable again until the next explicit request.
                else TvNav.sidebarEnabled = false
            }
        }
    }
}

@Composable
private fun RootContent(tab: TvRootTab) {
    when (tab) {
        TvRootTab.Home -> TvDashboard(TvRoots.dashboard)
        TvRootTab.Search -> TvSearch(TvRoots.search)
        TvRootTab.Settings -> TvSettings(TvRoots.settings)
        TvRootTab.Scenes -> TvScenesGrid(TvRoots.catalog<Scene>(tab, FilterMode.Scenes) { it.id })
        TvRootTab.Performers -> TvPerformersGrid(TvRoots.catalog<Performer>(tab, FilterMode.Performers) { it.id })
        TvRootTab.Studios -> TvStudiosGrid(TvRoots.catalog<Studio>(tab, FilterMode.Studios) { it.id })
        TvRootTab.Tags -> TvTagsGrid(TvRoots.catalog<Tag>(tab, FilterMode.Tags) { it.id })
        TvRootTab.Groups -> TvGroupsGrid(TvRoots.catalog<StashGroup>(tab, FilterMode.Groups) { it.id })
        TvRootTab.Galleries -> TvGalleriesGrid(TvRoots.catalog<Gallery>(tab, FilterMode.Galleries) { it.id })
        TvRootTab.Images -> TvImagesGrid(TvRoots.catalog<StashImage>(tab, FilterMode.Images) { it.id })
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun Sidebar(
    selected: TvRootTab,
    library: List<SidebarItem>,
    expanded: Boolean,
    focusable: Boolean,
    requesters: Map<TvRootTab, FocusRequester>,
    onFocusChange: (Boolean) -> Unit,
) {
    val width = if (expanded) pt(520) else pt(120)
    Box(
        Modifier.fillMaxHeight().zIndex(2f)
            .background(
                if (expanded) Brush.horizontalGradient(listOf(Color(0xF2101620), Color(0xE6101620), Color.Transparent), endX = Float.POSITIVE_INFINITY)
                else Brush.horizontalGradient(listOf(Color(0x66000000), Color.Transparent)),
            ),
    ) {
        // Scrolls on short screens; with room to spare Settings sits at the bottom (tvOS).
        BoxWithConstraints(Modifier.width(width).fillMaxHeight().animateContentSize()) {
            val viewport = maxHeight
            Column(
                Modifier.fillMaxWidth()
                    .onFocusChanged { onFocusChange(it.hasFocus) }
                    .focusGroup()
                    .verticalScroll(rememberScrollState())
                    .heightIn(min = viewport)
                    .padding(horizontal = pt(16), vertical = pt(40)),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(pt(8))) {
                    SidebarRow(TvRootTab.Search, TvIcons.search, selected, expanded, focusable, requesters)
                    SidebarRow(TvRootTab.Home, TvIcons.home, selected, expanded, focusable, requesters)
                    if (library.isNotEmpty()) {
                        if (expanded) Text("Library", Modifier.padding(start = pt(20), top = pt(24), bottom = pt(6)), style = TvType.caption.copy(fontWeight = FontWeight.SemiBold), color = TvColors.secondary)
                        else Spacer(Modifier.height(pt(24)))
                        library.forEach { SidebarRow(it.tab, it.icon, selected, expanded, focusable, requesters) }
                    }
                }
                Box(Modifier.padding(top = pt(24))) {
                    SidebarRow(TvRootTab.Settings, TvIcons.gear, selected, expanded, focusable, requesters)
                }
            }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun SidebarRow(tab: TvRootTab, icon: ImageVector, selected: TvRootTab, expanded: Boolean, focusable: Boolean, requesters: Map<TvRootTab, FocusRequester>) {
    val isSelected = tab == selected
    val bringIntoView = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    Surface(
        onClick = { TvNav.select(tab) },
        modifier = Modifier.fillMaxWidth().bringIntoViewRequester(bringIntoView)
            // Keep the focused pill (plus its focus scale) fully on screen.
            .onFocusChanged { if (it.isFocused) scope.launch { bringIntoView.bringIntoView() } }
            .focusProperties { canFocus = focusable }.focusRequester(requesters.getValue(tab)),
        shape = ClickableSurfaceDefaults.shape(RoundedCornerShape(pt(40))),
        colors = ClickableSurfaceDefaults.colors(
            containerColor = if (isSelected && expanded) Color.White.copy(alpha = 0.15f) else Color.Transparent,
            contentColor = if (isSelected) Color.White else Color.White.copy(alpha = 0.7f),
            focusedContainerColor = Color.White, focusedContentColor = Color.Black,
        ),
        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.04f),
    ) {
        Row(Modifier.padding(horizontal = pt(22), vertical = pt(14)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(20))) {
            Icon(icon, tab.title, Modifier.size(pt(40)), tint = if (isSelected && !expanded) TvColors.tint else LocalContentColor.current)
            if (expanded) Text(tab.title, style = TvType.headline, maxLines = 1)
        }
    }
}
