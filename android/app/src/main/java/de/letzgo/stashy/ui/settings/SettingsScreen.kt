package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.coroutines.launch
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.catalogTopPadding
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.layout.padding
import de.letzgo.stashy.BuildConfig
import de.letzgo.stashy.ui.tools.StashyTipsSection
import de.letzgo.stashy.ui.tools.stashyPlusSettingsItems

/** iOS: `SettingsView.SettingsSection` (titles = chip labels). */
enum class SettingsSection(val title: String, val icon: ImageVector) {
    Main(tr(R.string.settings), SFS.gearshapeFill), Design(tr(R.string.design), SFS.paintbrushFill), Actions(tr(R.string.server), SFS.serverRack), StashyPlus("stashy+", SF.sparkles)
}

/** iOS: `SettingsView` — floating section chips (Settings · Design · Server · stashy+). */
@Composable
fun SettingsScreen() {
    val p = Theme.palette
    var selectedName by rememberSaveable { androidx.compose.runtime.mutableStateOf(SettingsSection.Main.name) }
    val sections = if (StashyPlus.isUnlocked) SettingsSection.entries else SettingsSection.entries.filter { it != SettingsSection.StashyPlus }
    val active = SettingsSection.valueOf(selectedName).takeIf { it in sections } ?: SettingsSection.Main
    LaunchedEffect(Unit) { de.letzgo.stashy.data.TabManager.ensureLoaded() }

    Box(Modifier.fillMaxSize().background(p.background)) {
        val top = catalogTopPadding()
        when (active) {
            SettingsSection.Main -> SettingsList(top) { mainSettings() }
            SettingsSection.Design -> SettingsList(top) { designSettings() }
            SettingsSection.Actions -> ServerTasksContent(top)
            SettingsSection.StashyPlus -> SettingsList(top) { stashyPlusSettings() }
        }
        SectionChipStrip(sections, active, { it.icon }, { it.title }) { selectedName = it.name }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.mainSettings() {
    serverListSection()
    appLanguageSection()
    if (ServerConfigManager.activeConfig != null) playbackSections()
    settingsTransferSection()
    aboutSection()
}

private fun androidx.compose.foundation.lazy.LazyListScope.designSettings() {
    settingsSection(header = tr(R.string.appearance), key = "appearance") {
        SettingsNavRow(tr(R.string.appearance), SFS.paintbrush) { Nav.push(AppearanceSettingsScreen()) }
        SettingsDivider()
        SettingsNavRow(tr(R.string.editing), SFS.pencilCircle) { Nav.push(EditModeSettingsScreen()) }
        SettingsDivider()
        SettingsNavRow(tr(R.string.scene_view), SF.rectangleGrid1x2) { Nav.push(SceneViewSettingsScreen()) }
    }
    settingsSection(header = tr(R.string.security), key = "security") {
        SettingsNavRow(tr(R.string.security), SFS.lockShield) { Nav.push(SecuritySettingsScreen()) }
    }
    if (ServerConfigManager.activeConfig != null) {
        settingsSection(header = tr(R.string.content_and_tabs), key = "content") {
            SettingsNavRow(tr(R.string.dashboard), SFS.uiwindowSplit) { Nav.push(DashboardSettingsScreen()) }
            SettingsDivider()
            SettingsNavRow(tr(R.string.feeds), SF.playRectangleOnRectangle) { Nav.push(FeedsSettingsScreen()) }
            if (StashyPlus.isUnlocked) {
                SettingsDivider()
                SettingsNavRow(tr(R.string.tools), SF.cubeBox) { Nav.push(ToolsSettingsScreen()) }
            }
        }
    } else {
        settingsSection(key = "content") {
            SettingsRow { Text(tr(R.string.hint_content_settings_require_active_server), color = Theme.palette.secondaryText, style = NativeType.bodyLarge) }
        }
    }
}

/**
 * iOS `stashyPlusSettings` + `stashyPlusPurchaseSection` — the same items as the paywall
 * (`ui/tools/StashyPlusPaywall.kt`), so both look like iOS's stashy+ section.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.stashyPlusSettings() {
    stashyPlusSettingsItems()
}

private fun androidx.compose.foundation.lazy.LazyListScope.aboutSection() {
    // iOS `tipSection` — the tip products inline (header, Small / Medium / Large, footer).
    // Sideload builds aren't installed by Play, so Play returns no tips there: the section only
    // shows when tips were loaded instead of a permanent "Tips unavailable".
    if (!BuildConfig.LICENSE_KEYS || StashyPlus.tipProducts.isNotEmpty()) item(key = "tips") {
        StashyTipsSection(Modifier.padding(bottom = 24.dp))
    }
    settingsSection(header = tr(R.string.links), key = "links") {
        LinkRow("GitHub", SFS.code, "https://github.com/1letzgo/stashy")
        SettingsDivider()
        LinkRow(tr(R.string.discord), SFS.bubbles, "https://discord.gg/DMxEFaVzUM")
        SettingsDivider()
        SettingsNavRow(tr(R.string.acknowledgements), SFS.docText) { Nav.push(AcknowledgementsScreen()) }
    }
    // Android only: sideload builds update themselves from buntes.am (Play builds update via
    // the Play Store and, like iOS, have no such row).
    if (de.letzgo.stashy.data.AppUpdate.isEnabled) settingsSection(header = tr(R.string.app), key = "app-version") { AppUpdateRow() }
}

/** Version of this build + manual check for a newer sideload APK. */
@Composable
private fun AppUpdateRow() {
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val version = "${de.letzgo.stashy.data.AppUpdate.currentVersionName(context)} (${de.letzgo.stashy.data.AppUpdate.currentVersionCode(context)})"
    SettingsNavRow(tr(R.string.check_for_updates), SFS.arrowDownCircle, trailing = version) {
        scope.launch { de.letzgo.stashy.data.AppUpdate.check(context, manual = true) }
    }
}

@Composable
private fun LinkRow(title: String, icon: ImageVector, url: String) {
    val context = LocalContext.current
    de.letzgo.stashy.ui.NativeListItem(title, supporting = url.removePrefix("https://"), icon = icon, onClick = {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    })
}

/** iOS: `AppLanguageRow` — Settings › App Language (beta); switching restarts the app at once. */
private fun androidx.compose.foundation.lazy.LazyListScope.appLanguageSection() {
    settingsSection(header = tr(R.string.app_language), isBeta = true, key = "app-language") {
        val context = androidx.compose.ui.platform.LocalContext.current
        val selection = remember { de.letzgo.stashy.AppLanguage.stored }
        val codes = listOf(de.letzgo.stashy.AppLanguage.SYSTEM) + de.letzgo.stashy.AppLanguage.options.map { it.first }
        SettingsPickerRow(tr(R.string.language), codes, selection, { de.letzgo.stashy.AppLanguage.name(it) }, SFS.globe) { code ->
            if (code != selection) de.letzgo.stashy.AppLanguage.selectAndRestart(context, code)
        }
    }
}
