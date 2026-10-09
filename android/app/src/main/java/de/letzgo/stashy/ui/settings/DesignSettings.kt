package de.letzgo.stashy.ui.settings

import androidx.compose.material.icons.outlined.VerticalAlignBottom
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.SceneDetailLayout
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.AppTheme
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.floatingShadow
import de.letzgo.stashy.ui.stashyGlass
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.oCounterIcon
import kotlin.math.abs

/** iOS: `AppearanceSettingsView` — theme, accent colour, glass transparency, O counter icon. */
class AppearanceSettingsScreen : Screen {
    override val key = "settings-appearance"

    @OptIn(ExperimentalLayoutApi::class)
    @Composable override fun Content() = SettingsDetailScaffold("Appearance") { top ->
        SettingsList(top) {
            settingsSection(header = "App Theme", footer = "Choose the appearance of the app.", key = "theme") {
                SettingsPickerRow("Theme", AppTheme.entries, Appearance.theme, { it.raw }, SFS.circleLeftHalf) { Appearance.updateTheme(it) }
            }
            settingsSection(
                header = "Tab Bar", key = "tabbar",
                footer = "Slides the tab bar away while you scroll down a list and brings it back when you scroll up. Feeds keeps its own behaviour.",
            ) {
                SettingsToggleRow("Auto-hide tab bar", de.letzgo.stashy.ui.TabBarAutoHide.enabled, androidx.compose.material.icons.Icons.Outlined.VerticalAlignBottom) {
                    de.letzgo.stashy.ui.TabBarAutoHide.enabled = it
                }
            }
            settingsSection(
                header = "App Accent Color", key = "accent",
                footer = "This color will be applied to the tab bar, navigation bar buttons, and other interactive elements throughout the app.",
            ) {
                // iOS ColorPicker → hue slider (Android has no system colour picker).
                Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Custom Color", style = NativeType.bodyLarge, color = Theme.palette.text, modifier = Modifier.weight(1f))
                        Box(Modifier.size(28.dp).background(Appearance.tint, CircleShape).border(1.dp, Theme.palette.text.copy(alpha = 0.3f), CircleShape))
                    }
                    val hsv = FloatArray(3).also { android.graphics.Color.colorToHSV(Appearance.tint.toArgb(), it) }
                    Box(Modifier.fillMaxWidth().height(36.dp), contentAlignment = Alignment.Center) {
                        Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(Brush.horizontalGradient((0..6).map { Color.hsv(it * 60f % 360f, 0.75f, 0.9f) })))
                        Slider(
                            hsv[0], { h -> Appearance.updateTint(Color.hsv(h, 0.75f, 0.9f)) }, valueRange = 0f..359f,
                            colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = Color.Transparent, inactiveTrackColor = Color.Transparent),
                        )
                    }
                }
                SettingsDivider()
                FlowRow(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Appearance.presets.forEach { (_, color) ->
                        Box(
                            Modifier.size(44.dp).background(color, CircleShape).border(1.dp, Theme.palette.text.copy(alpha = 0.3f), CircleShape)
                                .clickable { Appearance.updateTint(color) },
                            contentAlignment = Alignment.Center,
                        ) { if (sameColor(Appearance.tint, color)) Icon(SFS.checkmark, null, tint = Color.White) }
                    }
                }
            }
            settingsSection(header = "Glass", footer = "How much of the content shows through the glass buttons, pills and bars drawn over videos and images.", key = "glass") {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(SFS.circleLeftHalf, null, tint = Appearance.tint, modifier = Modifier.size(24.dp))
                        Text("Transparency", style = NativeType.bodyLarge, color = Theme.palette.text, modifier = Modifier.padding(start = 16.dp).weight(1f))
                        Text("${Math.round(Appearance.glassTransparency * 100)} %", style = NativeType.bodyLarge, color = Theme.palette.secondaryText)
                    }
                    Slider(
                        Appearance.glassTransparency, { Appearance.updateGlassTransparency((Math.round(it * 20) / 20f).coerceIn(0.2f, 1f)) },
                        valueRange = 0.2f..1f, steps = 15,
                        colors = SliderDefaults.colors(thumbColor = nativeAccent(), activeTrackColor = nativeAccent(), inactiveTrackColor = Theme.palette.separator, activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent),
                    )
                }
                SettingsDivider()
                GlassDemo()
            }
            settingsSection(header = "O Counter", footer = "Choose which icon to display for the O Counter throughout the app.", key = "ocounter") {
                FlowRow(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    oCounterPresets.forEach { (icon, label) ->
                        val selected = Appearance.oCounterIcon == icon
                        Column(Modifier.widthIn(min = 56.dp).clickable { Appearance.updateOCounterIcon(icon) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Box(
                                Modifier.size(48.dp)
                                    .background(if (selected) Appearance.tint.copy(alpha = 0.15f) else Color.Gray.copy(alpha = 0.2f), CircleShape)
                                    .border(if (selected) 2.dp else 1.dp, if (selected) Appearance.tint else Theme.palette.text.copy(alpha = 0.2f), CircleShape),
                                contentAlignment = Alignment.Center,
                            ) { Icon(oCounterIcon(icon, filled = true), null, tint = if (selected) Appearance.tint else Theme.palette.text.copy(alpha = 0.6f), modifier = Modifier.size(22.dp)) }
                            Text(label, fontSize = 10.sp, color = Theme.palette.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

/** iOS `oCounterIconPresets`. */
val oCounterPresets = listOf(
    "heart" to "Heart", "star" to "Star", "flame" to "Flame", "bolt" to "Bolt", "hand.thumbsup" to "Thumbs Up",
    "circle" to "Circle", "diamond" to "Diamond", "crown" to "Crown", "trophy" to "Trophy", "moon" to "Moon",
    "drop" to "Drop", "leaf" to "Leaf", "bell" to "Bell", "tag" to "Tag", "eye" to "Eye",
)

/**
 * Settings › Design › Scene View — order and visibility of the cards on the scene detail page.
 * The video player always stays on top and isn't part of the list.
 */
class SceneViewSettingsScreen : Screen {
    override val key = "settings-scene-view"

    @Composable override fun Content() = SettingsDetailScaffold("Scene View") { top ->
        SettingsList(top) {
            item(key = "cards") {
                Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
                    SectionHeaderText("Cards")
                    val cards = SceneDetailLayout.order
                    val hidden = SceneDetailLayout.hidden
                    SettingsGroup {
                        ReorderableColumn(cards, { it.id }, { from, to -> SceneDetailLayout.move(from, to) }) { card, i, handle ->
                            Column {
                                SettingsRow(verticalPadding = 6.dp) {
                                    Text(card.title, style = NativeType.bodyLarge, color = Theme.palette.text, modifier = Modifier.weight(1f))
                                    SettingsSwitch(card !in hidden) { SceneDetailLayout.setVisible(card, it) }
                                    DragHandle(handle)
                                }
                                if (i < cards.lastIndex) SettingsDivider()
                            }
                        }
                    }
                    SectionFooterText("Drag to reorder the cards below the video player; switch a card off to hide it. In landscape, Groups and Tags share a row when they sit next to each other.")
                }
            }
            settingsSection(key = "reset") {
                val isDefault = SceneDetailLayout.isDefault
                SettingsRow(onClick = { SceneDetailLayout.reset() }, enabled = !isDefault) {
                    Text("Reset to Default", style = NativeType.bodyLarge, color = if (isDefault) Theme.palette.tertiaryText else nativeAccent())
                }
            }
        }
    }
}

private fun sameColor(a: Color, b: Color) = abs(a.red - b.red) < 0.01f && abs(a.green - b.green) < 0.01f && abs(a.blue - b.blue) < 0.01f

/** iOS `glassDemo` — the chrome shapes on a busy backdrop, redrawn with the slider. */
@Composable
private fun GlassDemo() {
    Box(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).heightIn(min = 96.dp).clip(RoundedCornerShape(10.dp))
            .background(Brush.linearGradient(listOf(Color(0xFFFF9F0A), Color(0xFFFF375F), Color(0xFFBF5AF2), Color(0xFF0A84FF), Color(0xFF40C8E0), Color(0xFF30D158)))),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.matchParentSize().padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(4) { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    repeat(8) { col -> Box(Modifier.weight(1f).height(10.dp).background(Color.White.copy(alpha = if ((row + col) % 2 == 0) 0.55f else 0.1f), RoundedCornerShape(3.dp))) }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            DemoGlassCapsule(tint = Appearance.tint) {
                Icon(SFS.chevronLeft, null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text("Back", style = NativeType.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
            }
            DemoGlassCapsule { Text("Demo", style = NativeType.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = Color.White) }
            Box(Modifier.size(42.dp).floatingShadow().stashyGlass(CircleShape), contentAlignment = Alignment.Center) {
                Icon(SF.line3HorizontalDecrease, null, tint = Color.White, modifier = Modifier.size(19.dp))
            }
        }
    }
}

/**
 * Glass capsule of the demo. Regular surfaces use Material components now; the glass look (and
 * this setting) only remains on the overlays drawn over playback (Feeds chrome, player, viewer).
 */
@Composable
private fun DemoGlassCapsule(tint: Color? = null, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.heightIn(min = 42.dp).floatingShadow(RoundedCornerShape(50)).stashyGlass(RoundedCornerShape(50), tint).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** iOS: `EditModeSettingsView`. */
class EditModeSettingsScreen : Screen {
    override val key = "settings-editing"
    @Composable override fun Content() = SettingsDetailScaffold("Editing") { top ->
        SettingsList(top) {
            settingsSection(
                key = "edit",
                footer = "Show edit buttons on scene detail cards (performers, studio, groups, galleries, tags, title, description) and on performer / studio / tag / group / gallery detail.",
            ) { SettingsToggleRow("Enable Editing", Appearance.isEditModeEnabled) { Appearance.updateEditMode(it) } }
        }
    }
}

/** iOS: `ToolsSettingsView`. */
class ToolsSettingsScreen : Screen {
    override val key = "settings-tools"
    @Composable override fun Content() = SettingsDetailScaffold("Tools") { top ->
        SettingsList(top) {
            settingsSection(header = "Tab", footer = "Tools are grouped on the Tools page.", key = "tab") {
                SettingsToggleRow("Show Tools Tab", TabManager.isVisible(AppTab.Tools), SF.cubeBox) { TabManager.toggle(AppTab.Tools) }
            }
        }
    }
}

/** iOS: `AcknowledgementsView` — Android components instead of the iOS player stack. */
class AcknowledgementsScreen : Screen {
    override val key = "settings-acknowledgements"

    private data class Entry(val name: String, val license: String, val note: String?, val url: String)

    private val entries = listOf(
        Entry("AndroidX Media3 (ExoPlayer)", "Apache-2.0", null, "https://github.com/androidx/media"),
        Entry("Jetpack Compose & AndroidX", "Apache-2.0", null, "https://developer.android.com/jetpack/androidx"),
        Entry("OkHttp", "Apache-2.0", null, "https://square.github.io/okhttp/"),
        Entry("Coil", "Apache-2.0", null, "https://coil-kt.github.io/coil/"),
        Entry("kotlinx.serialization / kotlinx.coroutines", "Apache-2.0", null, "https://github.com/Kotlin/kotlinx.serialization"),
    )

    @Composable override fun Content() = SettingsDetailScaffold("Acknowledgements") { top ->
        val context = LocalContext.current
        SettingsList(top) {
            settingsSection(header = "Components", footer = "stashy uses the components above. Their licenses apply in addition to stashy's own terms.", key = "components") {
                entries.forEachIndexed { i, e ->
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(e.name, style = NativeType.titleMedium, color = Theme.palette.text)
                        Text(e.license, style = NativeType.bodyMedium, color = Theme.palette.secondaryText)
                        e.note?.let { Text(it, style = NativeType.bodySmall, color = Theme.palette.secondaryText) }
                        Text(e.url, style = NativeType.bodySmall, color = Appearance.tint, modifier = Modifier.clickable {
                            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(e.url))) }
                        })
                    }
                    if (i < entries.lastIndex) SettingsDivider()
                }
            }
        }
    }
}
