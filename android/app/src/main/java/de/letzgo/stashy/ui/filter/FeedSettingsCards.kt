package de.letzgo.stashy.ui.filter

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.TabManager

/**
 * iOS: `ImagesFeedAutoplaySettingsCard` (Images / Feeds › Pics sheet): 1/row video Autoplay
 * (`images_feed_video_autoplay`), fullscreen Immersive (`images_fullscreen_immersive`) and
 * Continuous with its still duration (`images_fullscreen_continuous`,
 * `images_fullscreen_continuous_duration` — the keys `ImageViewerScreen` reads).
 */
@Composable
fun ImagesFeedAutoplaySettingsCard() {
    var immersive by remember { mutableStateOf(Prefs.bool("images_fullscreen_immersive", true)) }
    var continuous by remember { mutableStateOf(Prefs.bool("images_fullscreen_continuous", false)) }
    var seconds by remember { mutableIntStateOf(Prefs.int("images_fullscreen_continuous_duration", 3)) }
    ControlGroup {
        ControlToggleRow("Autoplay", TabManager.imagesFeedVideoAutoplay) { TabManager.imagesFeedVideoAutoplay = it }
        de.letzgo.stashy.ui.NativeDivider()
        ControlToggleRow("Immersive", immersive) { immersive = it; Prefs.setBool("images_fullscreen_immersive", it) }
        de.letzgo.stashy.ui.NativeDivider()
        ControlToggleRow("Continuous", continuous) { continuous = it; Prefs.setBool("images_fullscreen_continuous", it) }
        if (continuous) de.letzgo.stashy.ui.NativeDivider()
        if (continuous) ControlCard {
            ControlLabel("Still Duration")
            Row(
                Modifier.weight(1f).horizontalScroll(androidx.compose.foundation.rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
            ) {
                listOf(2, 3, 5, 8, 10).forEach { s ->
                    CatalogFilterChip("${s}s", seconds == s) { seconds = s; Prefs.setInt("images_fullscreen_continuous_duration", s) }
                }
            }
        }
    }
}
