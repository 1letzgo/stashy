package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.data.ImageGroupMode
import de.letzgo.stashy.data.ImageSetGrouping
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.CatalogCardColumnScope
import de.letzgo.stashy.data.CatalogCardColumns
import de.letzgo.stashy.data.DetailViewContext
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.TabConfigLogic
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.ReelsModeConfig
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.HomeRowType
import de.letzgo.stashy.data.TabConfig
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme

/** iOS `AppTab.icon` for the catalogue tabs. */
fun AppTab.settingsIcon(): ImageVector = when (this) {
    AppTab.Dashboard -> SF.houseFill
    AppTab.Studios -> SF.building2
    AppTab.Performers -> SF.personFill
    AppTab.Scenes -> SF.film
    AppTab.Galleries -> SF.photoStack
    AppTab.Images -> SF.photo
    AppTab.Tags -> SF.tag
    AppTab.Groups -> SF.rectangleStackFill
    AppTab.Markers -> SF.bookmarkFill
    AppTab.Reels -> SF.playRectangleOnRectangle
    AppTab.Tools -> SF.cubeBox
    else -> SF.squareGrid2x2Fill
}

/** (raw, label) of the iOS sort enum of [mode] in `allCases` order — what the default-sort menus offer. */
private fun sortNames(mode: FilterMode): List<Pair<String, String>> = SortCatalog.choices(mode).map { it.raw to it.label }

/** iOS `CatalogDefaultSortMenu` fallback: the tab's default from `loadConfig()`. */
private fun defaultSortFallback(tab: AppTab, mode: FilterMode): String =
    TabConfigLogic.defaultTabs().firstOrNull { it.id == tab }?.defaultSortOption ?: SortCatalog.defaultRaw(mode)

/** iOS `ReelsModeType.icon`. */
private fun ReelsModeType.icon(): ImageVector = when (this) {
    ReelsModeType.Scenes -> SF.film
    ReelsModeType.Markers -> SF.bookmarkFill
    ReelsModeType.Clips -> SFS.photoOnRectangleAngled
    ReelsModeType.Previews -> SFS.playRectOnRectFill
    ReelsModeType.Pics -> SFS.cameraFill
}

/** Card header (iOS `Label(…).font(.subheadline.weight(.semibold)).foregroundColor(tint)`) — Material titleMedium. */
@Composable
private fun CardHeader(title: String, icon: ImageVector, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(16.dp))
        Text(title, style = NativeType.titleMedium, color = Theme.palette.text, modifier = Modifier.weight(1f))
        trailing()
    }
}

@Composable
private fun CardDivider() = HorizontalDivider(Modifier.padding(vertical = 8.dp), thickness = 1.dp, color = Theme.palette.separator.copy(alpha = 0.5f))

/** iOS: `CatalogDefaultFilterMenu` — None + the saved filters of the tab's mode. */
@Composable
fun DefaultFilterMenu(tab: AppTab, kind: FilterKind = FilterKind.Standard) {
    val mode = when (kind) {
        FilterKind.Marker -> "SCENE_MARKERS"
        FilterKind.Clip -> "IMAGES"
        FilterKind.Preview -> "SCENES"
        FilterKind.Standard -> (if (tab == AppTab.Reels || tab == AppTab.Dashboard) FilterMode.Scenes.raw else tab.filterMode?.raw) ?: return
    }
    val filters = SavedFiltersStore.ofMode(mode)
    val current = when (kind) {
        FilterKind.Marker -> TabManager.getDefaultMarkerFilterId(tab)
        FilterKind.Clip -> TabManager.getDefaultClipFilterId(tab)
        FilterKind.Preview -> TabManager.getDefaultPreviewFilterId(tab)
        FilterKind.Standard -> if (tab == AppTab.Markers) TabManager.getDefaultMarkerFilterId(tab) else TabManager.getDefaultFilterId(tab)
    }
    if (filters.isEmpty() && !SavedFiltersStore.isLoading) {
        Text("No filters found", style = NativeType.bodyMedium, color = Theme.palette.secondaryText)
        return
    }
    MenuValue(listOf("" to "None") + filters.map { it.id to it.name }, current ?: "") { id ->
        val f = filters.firstOrNull { it.id == id }
        val (fid, name) = f?.id to f?.name
        when {
            kind == FilterKind.Marker || (kind == FilterKind.Standard && tab == AppTab.Markers) -> TabManager.setDefaultMarkerFilter(tab, fid, name)
            kind == FilterKind.Clip -> TabManager.setDefaultClipFilter(tab, fid, name)
            kind == FilterKind.Preview -> TabManager.setDefaultPreviewFilter(tab, fid, name)
            else -> TabManager.setDefaultFilter(tab, fid, name)
        }
    }
}

/** Which default-filter slot of a `TabConfig` a menu edits. */
enum class FilterKind { Standard, Marker, Clip, Preview }

/** iOS: `DashboardSettingsView` — dashboard card, Home tabs (order/visibility/defaults), rows, channels. */
class DashboardSettingsScreen : Screen {
    override val key = "settings-dashboard"

    @Composable override fun Content() {
        LaunchedEffect(Unit) { SavedFiltersStore.load(force = true); TabManager.syncHomeChannelItems(SavedFiltersStore.byId.values.toList()) }
        SettingsDetailScaffold("Dashboard") { top ->
            SettingsList(top) {
                item(key = "dash") {
                    Column(Modifier.padding(bottom = 24.dp)) {
                        SectionHeaderText("Dashboard")
                        SettingsCard {
                            CardHeader("Dashboard", SF.houseFill) { Text("Always Visible", style = NativeType.bodySmall, color = Theme.palette.secondaryText) }
                            CardDivider()
                            CardSettingRow("Default Filter") { DefaultFilterMenu(AppTab.Dashboard) }
                            CardSettingRow("Hero Background") { SettingsSwitch(TabManager.showDashboardHeroBackground) { TabManager.showDashboardHeroBackground = it } }
                            CardSettingRow("Compact Statistics") { SettingsSwitch(TabManager.useCompactStatistics) { TabManager.useCompactStatistics = it } }
                            CardSettingRow("Colored Statistics") { SettingsSwitch(TabManager.useColoredStatistics) { TabManager.useColoredStatistics = it } }
                        }
                    }
                }
                item(key = "tabs") {
                    Column(Modifier.padding(bottom = 24.dp)) {
                        SectionHeaderText("Home Tabs")
                        ReorderableColumn(TabManager.catalogSubTabs, { it.id }, { from, to -> TabManager.moveCatalogSubTab(from, to) }) { tab, _, handle ->
                            CatalogTabCard(tab, handle)
                        }
                    }
                }
                item(key = "rows") {
                    Column(Modifier.padding(bottom = 24.dp)) {
                        SectionHeaderText("Visible Dashboard Rows")
                        // Channels are stashy+: the row is hidden while locked; moves map back onto the full list.
                        val allRows = TabManager.homeRows
                        val rows = if (StashyPlus.isUnlocked) allRows else allRows.filter { it.type != HomeRowType.Channels }
                        SettingsGroup {
                            ReorderableColumn(rows, { it.id }, { from, to ->
                                val fullFrom = allRows.indexOfFirst { it.id == rows[from].id }
                                val fullTo = allRows.indexOfFirst { it.id == rows[to].id }
                                if (fullFrom >= 0 && fullTo >= 0) TabManager.moveHomeRow(fullFrom, fullTo)
                            }) { row, i, handle ->
                                Column {
                                    SettingsRow(verticalPadding = 6.dp) {
                                        Text(row.title, style = NativeType.bodyLarge, color = Theme.palette.text, modifier = Modifier.weight(1f))
                                        SettingsSwitch(row.isEnabled) { TabManager.toggleHomeRow(row.id) }
                                        DragHandle(handle)
                                    }
                                    if (i < rows.lastIndex) SettingsDivider()
                                }
                            }
                        }
                    }
                }
                if (StashyPlus.isUnlocked) item(key = "channels") {
                    Column(Modifier.padding(bottom = 24.dp)) {
                        SectionHeaderText("Channels")
                        val items = TabManager.homeChannelItems.sortedBy { it.sortOrder }
                        SettingsGroup {
                            if (items.isEmpty()) SettingsRow {
                                Text(if (SavedFiltersStore.isLoading) "Loading filters…" else "No saved scene or image filters", style = NativeType.bodyLarge, color = Theme.palette.secondaryText)
                            } else ReorderableColumn(items, { it.id }, { from, to -> TabManager.moveHomeChannelItem(from, to) }) { item, i, handle ->
                                Column {
                                    SettingsRow(verticalPadding = 6.dp) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            Text(SavedFiltersStore.byId[item.filterId]?.name ?: "Filter", style = NativeType.bodyLarge, color = Theme.palette.text)
                                            Text(item.destination.title, style = NativeType.bodyMedium, color = Theme.palette.secondaryText)
                                        }
                                        SettingsSwitch(item.isEnabled) { TabManager.toggleHomeChannelItem(item.id) }
                                        DragHandle(handle)
                                    }
                                    if (i < items.lastIndex) SettingsDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** iOS `catalogTabCard(_:)`. */
@Composable
private fun CatalogTabCard(tab: TabConfig, handle: Modifier) {
    SettingsCard {
        CardHeader(tab.id.title, tab.id.settingsIcon()) {
            SettingsSwitch(tab.isVisible) { TabManager.toggle(tab.id) }
            Spacer(Modifier.width(8.dp))
            DragHandle(handle)
        }
        if (!tab.isVisible) return@SettingsCard
        CardDivider()
        CatalogCardColumnScope.from(tab.id)?.let { scope -> CardSettingRow("Display") { ColumnsMenu(scope) } }
        if (tab.id == AppTab.Images) CardSettingRow("Autoplay") { SettingsSwitch(TabManager.imagesFeedVideoAutoplay) { TabManager.imagesFeedVideoAutoplay = it } }
        if (tab.id == AppTab.Scenes) CardSettingRow("Studio Logos") { SettingsSwitch(TabManager.sceneCardsShowStudioLogo) { TabManager.sceneCardsShowStudioLogo = it } }
        tab.id.filterMode?.let { m -> sortNames(m) to defaultSortFallback(tab.id, m) }?.let { (options, fallback) ->
            CardSettingRow("Default Sort") {
                MenuValue(options, TabManager.getPersistentSortOption(tab.id) ?: fallback) { TabManager.setPersistentSortOption(tab.id, it) }
            }
        }
        CardSettingRow("Default Filter") { DefaultFilterMenu(tab.id) }
        DetailViewContext.forTab(tab.id)?.let { ctx ->
            CardSettingRow(ctx.settingsRowTitle) {
                val options = if (ctx == DetailViewContext.Gallery) sortNames(FilterMode.Images) else sortNames(FilterMode.Scenes)
                MenuValue(options, TabManager.getPersistentDetailSortOption(ctx) ?: "dateDesc") { TabManager.setPersistentDetailSortOption(ctx, it) }
            }
        }
        if (tab.id == AppTab.Galleries) CardSettingRow("Opened Gallery") { ColumnsMenu(CatalogCardColumnScope.OpenedGallery) }
    }
}

/** iOS `CatalogCardColumnsMenu`. */
@Composable
private fun ColumnsMenu(scope: CatalogCardColumnScope) {
    MenuValue(CatalogCardColumns.entries.map { it.name to it.settingsLabel }, TabManager.catalogCardColumns(scope).name) {
        TabManager.setCatalogCardColumns(CatalogCardColumns.valueOf(it), scope)
    }
}

/** iOS: `ReelsModeSettingsView` — Feeds tab toggle and the per-mode cards. */
class FeedsSettingsScreen : Screen {
    override val key = "settings-feeds"

    @Composable override fun Content() {
        LaunchedEffect(Unit) { SavedFiltersStore.load(force = true) }
        SettingsDetailScaffold("Feeds") { top ->
            SettingsList(top) {
                settingsSection(header = "Tab", key = "tab") {
                    SettingsToggleRow("Show Feeds Tab", TabManager.isVisible(AppTab.Reels), SF.playRectangleOnRectangle) { TabManager.toggle(AppTab.Reels) }
                }
                // App UI, not a per-feed filter option — moved here from the Feeds filter sheet
                // (same `ReelsShowsDeleteButton` key, existing choices carry over).
                settingsSection(header = "Controls", key = "controls") {
                    SettingsToggleRow("Show Delete Button", FeedsConfig.showsDeleteButton, SF.trash) { FeedsConfig.updateShowsDeleteButton(it) }
                }
                item(key = "modes") {
                    Column(Modifier.padding(bottom = 24.dp)) {
                        SectionHeaderText("Modes")
                        ReorderableColumn(TabManager.configurableReelsModes, { it.id }, { from, to -> TabManager.moveReelsMode(from, to) }) { mode, _, handle ->
                            FeedsModeCard(mode, handle)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FeedsModeCard(mode: ReelsModeConfig, handle: Modifier) {
    SettingsCard {
        CardHeader(mode.type.defaultTitle, mode.type.icon()) {
            SettingsSwitch(mode.isEnabled) { TabManager.toggleReelsMode(mode.type) }
            Spacer(Modifier.width(8.dp))
            DragHandle(handle)
        }
        if (!mode.isEnabled) return@SettingsCard
        CardDivider()
        val (options, fallback) = when (mode.type) {
            ReelsModeType.Scenes, ReelsModeType.Previews -> sortNames(FilterMode.Scenes) to "random"
            ReelsModeType.Markers -> sortNames(FilterMode.SceneMarkers) to "random"
            ReelsModeType.Clips -> sortNames(FilterMode.Images) to "random"
            ReelsModeType.Pics -> sortNames(FilterMode.Images) to "dateDesc"
        }
        CardSettingRow("Default Sort") {
            val current = TabManager.getReelsDefaultSort(mode.type)?.takeIf { c -> options.any { it.first == c } } ?: fallback
            MenuValue(options, current) { TabManager.setReelsDefaultSort(mode.type, it) }
        }
        CardSettingRow("Default Filter") {
            when (mode.type) {
                ReelsModeType.Scenes -> DefaultFilterMenu(AppTab.Reels)
                ReelsModeType.Markers -> DefaultFilterMenu(AppTab.Reels, FilterKind.Marker)
                ReelsModeType.Clips -> DefaultFilterMenu(AppTab.Reels, FilterKind.Clip)
                ReelsModeType.Previews -> DefaultFilterMenu(AppTab.Reels, FilterKind.Preview)
                ReelsModeType.Pics -> DefaultFilterMenu(AppTab.Images)
            }
        }
        if (mode.type == ReelsModeType.Pics) {
            CardSettingRow("Group into sets") {
                MenuValue(ImageGroupMode.entries.map { it.raw to it.displayName }, TabManager.stashlineGroupMode.raw) {
                    TabManager.stashlineGroupMode = ImageGroupMode.from(it)
                }
            }
            if (TabManager.stashlineGroupMode == ImageGroupMode.GallerySession) CardSettingRow("Session gap") {
                MenuValue(ImageSetGrouping.gapOptions.map { it.toString() to "$it min" }, TabManager.stashlineGroupGapMinutes.toString()) {
                    TabManager.stashlineGroupGapMinutes = it.toInt()
                }
            }
            if (TabManager.stashlineGroupMode != ImageGroupMode.Off) CardSettingRow("Max set size") {
                MenuValue(ImageSetGrouping.maxSizeOptions.map { it.toString() to "$it images" }, TabManager.stashlineGroupMaxSize.toString()) {
                    TabManager.stashlineGroupMaxSize = it.toInt()
                }
            }
        }
    }
}
