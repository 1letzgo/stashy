package de.letzgo.stashy.ui.filter

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
import de.letzgo.stashy.data.ImageBackdropMode
import de.letzgo.stashy.data.ImageScalingMode
import de.letzgo.stashy.data.ImageViewing
import de.letzgo.stashy.ui.Appearance
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import de.letzgo.stashy.data.TabManager

@Composable
private fun RowScope.ChipRow(content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.weight(1f).horizontalScroll(androidx.compose.foundation.rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        content = content,
    )
}

/**
 * iOS `ImageViewingOptionsCards`: Image Scaling, Background, Fit Images and Keep Rating Visible
 * ([ImageViewing]) — the Images settings sheet, and without Fit Images Feeds › Clips.
 * Rows for a [ControlGroup].
 */
@Composable
fun ImageViewingOptionRows(showsGridFit: Boolean) {
    ControlCard {
        ControlLabel(tr(R.string.image_scaling))
        ChipRow {
            ImageScalingMode.entries.forEach { m ->
                CatalogFilterChip(tr(m.titleRes), ImageViewing.scaling == m) { ImageViewing.scaling = m }
            }
        }
    }
    de.letzgo.stashy.ui.NativeDivider()
    ControlCard {
        ControlLabel(tr(R.string.background))
        ChipRow {
            ImageBackdropMode.entries.forEach { m ->
                CatalogFilterChip(tr(m.titleRes), ImageViewing.backdrop == m) { ImageViewing.backdrop = m }
            }
        }
    }
    if (showsGridFit) {
        de.letzgo.stashy.ui.NativeDivider()
        ControlToggleRow(tr(R.string.fit_images), ImageViewing.gridFit) { ImageViewing.gridFit = it }
    }
    de.letzgo.stashy.ui.NativeDivider()
    ControlToggleRow(tr(R.string.keep_rating_visible), ImageViewing.keepRating) { ImageViewing.keepRating = it }
}

/**
 * iOS: `ImagesFeedAutoplaySettingsCard` (Images / Feeds › Pics sheet): 1/row video Autoplay
 * (`images_feed_video_autoplay`), Image Scaling / Background / Fit Images / Keep Rating Visible ([ImageViewing]) and
 * Continuous with its still duration (`images_fullscreen_continuous`,
 * `images_fullscreen_continuous_duration` — the keys `ImageViewerScreen` reads).
 */
@Composable
fun ImagesFeedAutoplaySettingsCard() {
    var continuous by remember { mutableStateOf(Prefs.bool("images_fullscreen_continuous", false)) }
    var seconds by remember { mutableIntStateOf(Prefs.int("images_fullscreen_continuous_duration", 3)) }
    ControlGroup {
        ControlToggleRow(tr(R.string.autoplay), TabManager.imagesFeedVideoAutoplay) { TabManager.imagesFeedVideoAutoplay = it }
        de.letzgo.stashy.ui.NativeDivider()
        ImageViewingOptionRows(showsGridFit = true)
        de.letzgo.stashy.ui.NativeDivider()
        ControlToggleRow(tr(R.string.continuous), continuous) { continuous = it; Prefs.setBool("images_fullscreen_continuous", it) }
        if (continuous) de.letzgo.stashy.ui.NativeDivider()
        if (continuous) ControlCard {
            ControlLabel(tr(R.string.still_duration))
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
