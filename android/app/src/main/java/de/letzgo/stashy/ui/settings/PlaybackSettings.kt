package de.letzgo.stashy.ui.settings

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.VolumeOff
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
    settingsSection(header = tr(R.string.player), key = "player") {
        SettingsToggleRow(tr(R.string.picture_in_picture), TabManager.isPiPEnabled, SFS.pip) { TabManager.isPiPEnabled = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.action_skip_interval), TabManager.playerSkipOptions, TabManager.playerSkipSeconds, { TabManager.playerSkipLabel(it) }, SFS.goforward) { TabManager.playerSkipSeconds = it }
        SettingsDivider()
        SettingsToggleRow(tr(R.string.action_skip_buttons), TabManager.showsPlayerSkipButtons, SFS.goforward10) { TabManager.showsPlayerSkipButtons = it }
        SettingsDivider()
        SettingsToggleRow(tr(R.string.autozoom), TabManager.playerAutoZoom, SFS.arrowUpLeftDownRight) { TabManager.playerAutoZoom = it }
        SettingsDivider()
        // Scene player, Feeds and image-viewer videos (card previews stay muted regardless).
        SettingsToggleRow(tr(R.string.action_start_mute), TabManager.playbackStartMuted, Icons.Outlined.VolumeOff) {
            TabManager.playbackStartMuted = it
            de.letzgo.stashy.ui.player.PlayerMute.forgetSessionChoice()
        }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.hold_to_speed_up), TabManager.holdSpeedOptions, TabManager.holdSpeedPlayer, TabConfigLogic::holdSpeedLabel, SFS.forwardFill) { TabManager.holdSpeedPlayer = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.count_as_played), TabManager.playCountThresholdOptions, TabManager.playCountPlayerSeconds, TabConfigLogic::playCountThresholdLabel, SFS.playCircle) { TabManager.playCountPlayerSeconds = it }
    }
    // Feeds playback (Scenes / Markers rows).
    settingsSection(
        header = tr(R.string.feeds), key = "feeds-playback",
        footer = tr(R.string.hint_double_tap_jumps_to_markers),
    ) {
        // Feeds › Scenes only: skip studio intros (beginning / first marker / 30 s / random in the first half).
        SettingsPickerRow(tr(R.string.action_start_position), FeedsSceneStartPosition.entries, TabManager.feedsSceneStartPosition, { it.label }, SFS.goforward) { TabManager.feedsSceneStartPosition = it }
        SettingsDivider()
        // Feeds › Markers: length of a marker without an end time.
        SettingsPickerRow(tr(R.string.marker_length), TabManager.feedsMarkerLengthOptions, TabManager.feedsMarkerDefaultSeconds, { "${it.toInt()} s" }, SFS.goforward10) { TabManager.feedsMarkerDefaultSeconds = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.hold_to_speed_up), TabManager.holdSpeedOptions, TabManager.holdSpeedFeeds, TabConfigLogic::holdSpeedLabel, SFS.forwardFrameFill) { TabManager.holdSpeedFeeds = it }
        SettingsDivider()
        val verticals = de.letzgo.stashy.data.ReelsModeType.Verticals in TabManager.enabledReelsModes
        SettingsPickerRow(if (verticals) tr(R.string.count_as_played_scenes) else tr(R.string.count_as_played), TabManager.playCountThresholdOptions, TabManager.playCountFeedsSeconds, TabConfigLogic::playCountThresholdLabel, SFS.rectangleStackBadgePlay) { TabManager.playCountFeedsSeconds = it }
        if (verticals) {
            SettingsDivider()
            SettingsPickerRow(tr(R.string.count_as_played_verticals), TabManager.playCountThresholdOptions, TabManager.playCountVerticalsSeconds, TabConfigLogic::playCountThresholdLabel, SFS.rectangleStackBadgePlay) { TabManager.playCountVerticalsSeconds = it }
        }
        SettingsDivider()
        // Feeds › Scenes: a marker at the current position, beside the rating.
        SettingsToggleRow(tr(R.string.action_add_marker_button), de.letzgo.stashy.data.FeedsConfig.showsAddMarkerButton, de.letzgo.stashy.ui.player.PlayerIcons.addMarker) { de.letzgo.stashy.data.FeedsConfig.updateShowsAddMarkerButton(it) }
        SettingsDivider()
        SettingsToggleRow(tr(R.string.double_tap_jumps_to_markers), de.letzgo.stashy.data.FeedsConfig.doubleTapJumpsToMarkers, de.letzgo.stashy.ui.player.PlayerIcons.bookmark) { de.letzgo.stashy.data.FeedsConfig.updateDoubleTapJumpsToMarkers(it) }
    }
    // Stash web "Track activity": play count, history, resume point, watch time.
    settingsSection(
        header = tr(R.string.activity), key = "activity",
        footer = tr(R.string.hint_play_count_history_resume_point),
    ) {
        SettingsToggleRow(tr(R.string.playback_activity), TabManager.tracksPlaybackActivity, Icons.Outlined.History) { TabManager.tracksPlaybackActivity = it }
    }
    settingsSection(header = tr(R.string.downloads), key = "downloads") {
        SettingsPickerRow(tr(R.string.newest_batch_images), TabManager.downloadBatchSizeOptions, TabManager.downloadBatchSize, { "$it" }, SF.photoStack) { TabManager.downloadBatchSize = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.newest_batch_scenes), TabManager.downloadBatchSizeOptions, TabManager.sceneDownloadBatchSize, { "$it" }, SF.film) { TabManager.sceneDownloadBatchSize = it }
    }
    settingsSection(header = tr(R.string.subtitles), key = "subtitles") {
        SettingsToggleRow(tr(R.string.action_show_subtitles_automatically), TabManager.subtitlesAutoEnabled, SFS.captionsBubble) { TabManager.subtitlesAutoEnabled = it }
        SettingsDivider()
        val langs = subtitleLanguageOptions()
        SettingsPickerRow(tr(R.string.preferred_language), langs.map { it.first }, TabManager.subtitlePreferredLanguage.takeIf { c -> langs.any { it.first == c } } ?: "any",
            { id -> langs.firstOrNull { it.first == id }?.second ?: id }, SFS.globe) { TabManager.subtitlePreferredLanguage = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.size), SubtitleFontSize.entries, TabManager.subtitleFontSize, { it.label }, SFS.textformatSize) { TabManager.subtitleFontSize = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.font), SubtitleFontFamily.entries, TabManager.subtitleFontFamily, { it.label }, SFS.textformat) { TabManager.subtitleFontFamily = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.text_color), SubtitleTextColorChoice.entries, TabManager.subtitleTextColor, { it.label }, SFS.paintpalette) { TabManager.subtitleTextColor = it }
        SettingsDivider()
        SettingsToggleRow(tr(R.string.background_box), TabManager.subtitleBoxEnabled, SFS.rectangleFill) { TabManager.subtitleBoxEnabled = it }
        SettingsDivider()
        SettingsPickerRow(tr(R.string.background_color), SubtitleBackgroundChoice.entries, TabManager.subtitleBackgroundColor, { it.label }, SFS.squareFillOnSquare, enabled = TabManager.subtitleBoxEnabled) { TabManager.subtitleBackgroundColor = it }
        SettingsDivider()
        SubtitlePreview()
    }
}

/** iOS `SubtitlePreferredLanguage.pickerOptions()` — "Any", common languages, then the rest by name. */
fun subtitleLanguageOptions(): List<Pair<String, String>> {
    val common = listOf("en", "de", "es", "fr", "it", "pt", "nl", "ru", "ja", "zh", "ko")
    fun name(code: String) = Locale(code).getDisplayLanguage(Locale.ENGLISH).ifEmpty { code }
    val rest = Locale.getISOLanguages().filter { it !in common }.map { it to name(it) }.sortedBy { it.second }
    return listOf("any" to tr(R.string.any)) + common.map { it to name(it) } + rest
}

/** iOS `subtitlePreview` — the cue as the player draws it, over a dark stand-in for the picture. */
@androidx.compose.runtime.Composable
private fun SubtitlePreview() {
    val size = when (TabManager.subtitleFontSize) { SubtitleFontSize.Small -> 14; SubtitleFontSize.Medium -> 18; SubtitleFontSize.Large -> 22; SubtitleFontSize.ExtraLarge -> 28 }
    val family = when (TabManager.subtitleFontFamily) { SubtitleFontFamily.Serif -> FontFamily.Serif; SubtitleFontFamily.Monospaced -> FontFamily.Monospace; else -> FontFamily.Default }
    val box = if (TabManager.subtitleBoxEnabled) TabManager.subtitleBackgroundColor.argb?.let { Color(it) } else null
    Box(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).heightIn(min = 96.dp).clip(RoundedCornerShape(10.dp))
            .background(Brush.linearGradient(listOf(Color(0xFF383838), Color(0xFF0F0F0F)))),
        contentAlignment = Alignment.BottomCenter,
    ) {
        // Same capped font scale as the player draws its subtitles with (CappedFontScale on the surface).
        de.letzgo.stashy.ui.CappedFontScale { Text(
            tr(R.string.sample_subtitle),
            color = Color(TabManager.subtitleTextColor.argb), fontSize = size.sp, fontFamily = family, fontWeight = FontWeight.SemiBold,
            style = if (box == null) androidx.compose.ui.text.TextStyle(shadow = Shadow(Color.Black, blurRadius = 4f)) else androidx.compose.ui.text.TextStyle.Default,
            modifier = Modifier.padding(top = 10.dp, bottom = 10.dp).let { if (box != null) it.background(box, RoundedCornerShape(4.dp)).padding(horizontal = 6.dp, vertical = 2.dp) else it },
        ) }
    }
}
