package de.letzgo.stashy.ui.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.History
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.FeedsSceneStartPosition
import de.letzgo.stashy.data.SubtitleBackgroundChoice
import de.letzgo.stashy.data.SubtitleFontFamily
import de.letzgo.stashy.data.SubtitleFontSize
import de.letzgo.stashy.data.SubtitleTextColorChoice
import de.letzgo.stashy.data.TabConfigLogic
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.SFS
import java.util.Locale

/**
 * iOS: `PlaybackSettingsSection` — Playback, Downloads, Subtitles. Only persists the values
 * (same keys as iOS); the player and Feeds read them from [TabManager].
 */
fun LazyListScope.playbackSections() {
    // The scene player (scene detail, fullscreen, PiP).
    settingsSection(header = "Player", key = "player") {
        SettingsToggleRow("Picture-in-Picture", TabManager.isPiPEnabled, SFS.pip) { TabManager.isPiPEnabled = it }
        SettingsDivider()
        SettingsPickerRow("Skip interval", TabManager.playerSkipOptions, TabManager.playerSkipSeconds, { "${it.toInt()} s" }, SFS.goforward) { TabManager.playerSkipSeconds = it }
        SettingsDivider()
        SettingsToggleRow("Skip buttons", TabManager.showsPlayerSkipButtons, SFS.goforward10) { TabManager.showsPlayerSkipButtons = it }
        SettingsDivider()
        SettingsToggleRow("Autozoom", TabManager.playerAutoZoom, SFS.arrowUpLeftDownRight) { TabManager.playerAutoZoom = it }
        SettingsDivider()
        SettingsToggleRow("Dolby Vision", TabManager.playerDolbyVisionEnabled, SFS.sparklesTv) { TabManager.playerDolbyVisionEnabled = it }
        SettingsDivider()
        SettingsPickerRow("Hold to speed up", TabManager.holdSpeedOptions, TabManager.holdSpeedPlayer, TabConfigLogic::holdSpeedLabel, SFS.forwardFill) { TabManager.holdSpeedPlayer = it }
        SettingsDivider()
        SettingsPickerRow("Count as played", TabManager.playCountThresholdOptions, TabManager.playCountPlayerSeconds, TabConfigLogic::playCountThresholdLabel, SFS.playCircle) { TabManager.playCountPlayerSeconds = it }
    }
    // Feeds playback (Scenes / Markers rows).
    settingsSection(header = "Feeds", key = "feeds-playback") {
        // Feeds › Scenes only: skip studio intros (beginning / first marker / 30 s / random in the first half).
        SettingsPickerRow("Start position", FeedsSceneStartPosition.entries, TabManager.feedsSceneStartPosition, { it.label }, SFS.goforward) { TabManager.feedsSceneStartPosition = it }
        SettingsDivider()
        // Feeds › Markers: length of a marker without an end time.
        SettingsPickerRow("Marker length", TabManager.feedsMarkerLengthOptions, TabManager.feedsMarkerDefaultSeconds, { "${it.toInt()} s" }, SFS.goforward10) { TabManager.feedsMarkerDefaultSeconds = it }
        SettingsDivider()
        SettingsPickerRow("Hold to speed up", TabManager.holdSpeedOptions, TabManager.holdSpeedFeeds, TabConfigLogic::holdSpeedLabel, SFS.forwardFrameFill) { TabManager.holdSpeedFeeds = it }
        SettingsDivider()
        SettingsPickerRow("Count as played", TabManager.playCountThresholdOptions, TabManager.playCountFeedsSeconds, TabConfigLogic::playCountThresholdLabel, SFS.rectangleStackBadgePlay) { TabManager.playCountFeedsSeconds = it }
    }
    // Stash web "Track activity": play count, history, resume point, watch time.
    settingsSection(
        header = "Activity", key = "activity",
        footer = "Play count, history, resume point and watch time on the server. The player menu can pause it for one scene.",
    ) {
        SettingsToggleRow("Playback activity", TabManager.tracksPlaybackActivity, Icons.Outlined.History) { TabManager.tracksPlaybackActivity = it }
    }
    settingsSection(header = "Downloads", key = "downloads") {
        SettingsPickerRow("Newest batch — Images", TabManager.downloadBatchSizeOptions, TabManager.downloadBatchSize, { "$it" }, SF.photoStack) { TabManager.downloadBatchSize = it }
        SettingsDivider()
        SettingsPickerRow("Newest batch — Scenes", TabManager.downloadBatchSizeOptions, TabManager.sceneDownloadBatchSize, { "$it" }, SF.film) { TabManager.sceneDownloadBatchSize = it }
    }
    settingsSection(header = "Subtitles", key = "subtitles") {
        SettingsToggleRow("Show subtitles automatically", TabManager.subtitlesAutoEnabled, SFS.captionsBubble) { TabManager.subtitlesAutoEnabled = it }
        SettingsDivider()
        val langs = subtitleLanguageOptions()
        SettingsPickerRow("Preferred language", langs.map { it.first }, TabManager.subtitlePreferredLanguage.takeIf { c -> langs.any { it.first == c } } ?: "any",
            { id -> langs.firstOrNull { it.first == id }?.second ?: id }, SFS.globe) { TabManager.subtitlePreferredLanguage = it }
        SettingsDivider()
        SettingsPickerRow("Size", SubtitleFontSize.entries, TabManager.subtitleFontSize, { it.label }, SFS.textformatSize) { TabManager.subtitleFontSize = it }
        SettingsDivider()
        SettingsPickerRow("Font", SubtitleFontFamily.entries, TabManager.subtitleFontFamily, { it.label }, SFS.textformat) { TabManager.subtitleFontFamily = it }
        SettingsDivider()
        SettingsPickerRow("Text color", SubtitleTextColorChoice.entries, TabManager.subtitleTextColor, { it.label }, SFS.paintpalette) { TabManager.subtitleTextColor = it }
        SettingsDivider()
        SettingsToggleRow("Background box", TabManager.subtitleBoxEnabled, SFS.rectangleFill) { TabManager.subtitleBoxEnabled = it }
        SettingsDivider()
        SettingsPickerRow("Background color", SubtitleBackgroundChoice.entries, TabManager.subtitleBackgroundColor, { it.label }, SFS.squareFillOnSquare, enabled = TabManager.subtitleBoxEnabled) { TabManager.subtitleBackgroundColor = it }
        SettingsDivider()
        SubtitlePreview()
    }
}

/** iOS `SubtitlePreferredLanguage.pickerOptions()` — "Any", common languages, then the rest by name. */
fun subtitleLanguageOptions(): List<Pair<String, String>> {
    val common = listOf("en", "de", "es", "fr", "it", "pt", "nl", "ru", "ja", "zh", "ko")
    fun name(code: String) = Locale(code).getDisplayLanguage(Locale.ENGLISH).ifEmpty { code }
    val rest = Locale.getISOLanguages().filter { it !in common }.map { it to name(it) }.sortedBy { it.second }
    return listOf("any" to "Any") + common.map { it to name(it) } + rest
}

/** iOS `subtitlePreview` — the cue as the player draws it, over a dark stand-in for the picture. */
@androidx.compose.runtime.Composable
private fun SubtitlePreview() {
    val size = when (TabManager.subtitleFontSize) { SubtitleFontSize.Small -> 14; SubtitleFontSize.Medium -> 18; SubtitleFontSize.Large -> 22; SubtitleFontSize.ExtraLarge -> 28 }
    val family = when (TabManager.subtitleFontFamily) { SubtitleFontFamily.Serif -> FontFamily.Serif; SubtitleFontFamily.Monospaced -> FontFamily.Monospace; else -> FontFamily.Default }
    val box = if (TabManager.subtitleBoxEnabled) TabManager.subtitleBackgroundColor.argb?.let { Color(it) } else null
    Box(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).height(96.dp).clip(RoundedCornerShape(10.dp))
            .background(Brush.linearGradient(listOf(Color(0xFF383838), Color(0xFF0F0F0F)))),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Text(
            "Sample subtitle",
            color = Color(TabManager.subtitleTextColor.argb), fontSize = size.sp, fontFamily = family, fontWeight = FontWeight.SemiBold,
            style = if (box == null) androidx.compose.ui.text.TextStyle(shadow = Shadow(Color.Black, blurRadius = 4f)) else androidx.compose.ui.text.TextStyle.Default,
            modifier = Modifier.padding(bottom = 10.dp).let { if (box != null) it.background(box, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp) else it },
        )
    }
}
