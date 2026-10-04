package de.letzgo.stashy.ui.settings

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
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.catalogTopPadding
import androidx.compose.ui.graphics.vector.ImageVector

/** iOS: `SettingsView.SettingsSection` (titles = chip labels). */
enum class SettingsSection(val title: String, val icon: ImageVector) {
    Main("Settings", SFS.gearshapeFill), Design("Design", SFS.paintbrushFill), Actions("Server", SFS.serverRack), StashyPlus("stashy+", SF.sparkles)
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
        val top = catalogTopPadding() - 20.dp
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
    if (ServerConfigManager.activeConfig != null) playbackSections()
    aboutSection()
}

private fun androidx.compose.foundation.lazy.LazyListScope.designSettings() {
    settingsSection(header = "Appearance", key = "appearance") {
        SettingsNavRow("Appearance", SFS.paintbrush) { Nav.push(AppearanceSettingsScreen()) }
        SettingsDivider()
        SettingsNavRow("Editing", SFS.pencilCircle) { Nav.push(EditModeSettingsScreen()) }
    }
    settingsSection(header = "Security", key = "security") {
        SettingsNavRow("Security", SFS.lockShield) { Nav.push(SecuritySettingsScreen()) }
    }
    if (ServerConfigManager.activeConfig != null) {
        settingsSection(header = "Content & Tabs", key = "content") {
            SettingsNavRow("Dashboard", SFS.uiwindowSplit) { Nav.push(DashboardSettingsScreen()) }
            SettingsDivider()
            SettingsNavRow("Feeds", SF.playRectangleOnRectangle) { Nav.push(FeedsSettingsScreen()) }
            if (StashyPlus.isUnlocked) {
                SettingsDivider()
                SettingsNavRow("Tools", SF.cubeBox) { Nav.push(ToolsSettingsScreen()) }
            }
        }
    } else {
        settingsSection(key = "content") {
            SettingsRow { Text("Content settings require an active server.", color = Theme.palette.secondaryText, style = IosTypography.body) }
        }
    }
}

/**
 * iOS `stashyPlusSettings` (unlocked state). The purchase / restore UI is the billing feature's
 * paywall (`openStashyPlusPaywall()`); AI features, custom icons and AI Motion are not on Android.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.stashyPlusSettings() {
    settingsSection(header = "stashy+", key = "plus-status") {
        SettingsRow {
            Icon(SFS.checkmarkSealFill, null, tint = Color(0xFF30D158), modifier = Modifier.size(22.dp))
            Column(Modifier.weight(1f)) {
                Text(StashyPlus.source.statusTitle, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Theme.palette.text)
                Text(StashyPlus.source.statusDetail, style = IosTypography.caption, color = Theme.palette.secondaryText)
            }
        }
        SettingsDivider()
        SettingsNavRow("Manage stashy+", SF.sparkles) { de.letzgo.stashy.ui.tools.openStashyPlusPaywall() }
    }
    // iOS `StashyPlusAISubtitlesSettings` (+ Android: the downloaded speech / translation packs).
    settingsSection(header = "AI Subtitles and translation", key = "plus-ai-subtitles") {
        AiSubtitlesSettingsRows()
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.aboutSection() {
    // iOS tipSection — the tip purchase buttons live in the billing feature's UI.
    settingsSection(header = "Tips", footer = "Support stashy. Tips do not unlock stashy+.", key = "tips") {
        SettingsNavRow("Leave a Tip", SFS.heart) { de.letzgo.stashy.ui.tools.openStashyPlusPaywall() }
    }
    settingsSection(header = "Links", key = "links") {
        LinkRow("GitHub", SFS.code, "https://github.com/1letzgo/stashy")
        SettingsDivider()
        LinkRow("Discord", SFS.bubbles, "https://discord.gg/DMxEFaVzUM")
        SettingsDivider()
        SettingsNavRow("Acknowledgements", SFS.docText) { Nav.push(AcknowledgementsScreen()) }
    }
    settingsSection(header = "App", key = "app-version") { AppVersionRow() }
}

/** Version of this build; sideload builds can check buntes.am for a newer APK (Android only). */
@Composable
private fun AppVersionRow() {
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val version = "${de.letzgo.stashy.data.AppUpdate.currentVersionName(context)} (${de.letzgo.stashy.data.AppUpdate.currentVersionCode(context)})"
    if (de.letzgo.stashy.data.AppUpdate.isEnabled) {
        SettingsNavRow("Check for Updates", SFS.docText, trailing = version) {
            scope.launch { de.letzgo.stashy.data.AppUpdate.check(context, manual = true) }
        }
    } else {
        SettingsNavRow("Version", SFS.docText, trailing = version) {}
    }
}

@Composable
private fun LinkRow(title: String, icon: ImageVector, url: String) {
    val context = LocalContext.current
    SettingsRow(onClick = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } }) {
        SettingsLabel(title, icon, color = Appearance.tint)
    }
}
