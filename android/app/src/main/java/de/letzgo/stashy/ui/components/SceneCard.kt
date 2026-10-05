package de.letzgo.stashy.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.ui.player.ScenePreviewOnHold
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeMediaLabel
import de.letzgo.stashy.ui.NativeMediaLabelBox
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.SF

/**
 * iOS: `SceneCardView` — thumbnail filling the card, studio badge top-left, date top-right,
 * gradient with title, duration and performer count at the bottom, resume bar.
 * Android look: Material `ElevatedCard` ([NativeCard], ripple on [onClick]) with Material labels.
 * Holding the card for 0.15 s plays `paths.preview` muted and looping on top of the
 * thumbnail (iOS `AetherPreviewPlayer`, shared pool of 2 — see `ui/player/PreviewPlayer.kt`);
 * releasing stops it. The press is observed without consuming, so the card's tap still works.
 */
@Composable
fun SceneCard(
    scene: Scene,
    modifier: Modifier = Modifier,
    aspectRatio: Float = 16f / 9f,
    showDate: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    NativeCard(modifier.fillMaxWidth().aspectRatio(aspectRatio), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)))
        AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        ScenePreviewOnHold(scene.previewURL)

        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            scene.studio?.let { StudioBadge(it) }
            Box(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (showDate) scene.date?.let { NativeMediaLabel(it) }
                if (Downloads.isDownloaded(scene.id)) DownloadedMark()
            }
        }

        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(100.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)))),
        )
        Row(
            Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                scene.displayTitle, Modifier.weight(1f),
                style = NativeType.titleMedium,
                color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            formatDuration(scene.sceneDuration)?.let { NativeMediaLabel(it, icon = SF.clock) }
            if (scene.performers.isNotEmpty()) NativeMediaLabel("${scene.performers.size}", icon = SF.person2)
        }

        val resume = scene.resumeTime ?: 0.0
        val duration = scene.sceneDuration
        if (resume > 0 && duration != null) {
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.25f)))
            Box(
                Modifier.align(Alignment.BottomStart).fillMaxWidth((resume / duration).toFloat().coerceIn(0f, 1f)).height(4.dp)
                    .background(Appearance.tint),
            )
        }
    }
}

/** "Downloaded" mark on scene cards: green check in a small Material circle. */
@Composable
fun DownloadedMark(size: Int = 20) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(StashyColors.systemGreen), contentAlignment = Alignment.Center) {
        Icon(SF.checkmarkCircleFill, "Downloaded", tint = Color.White, modifier = Modifier.size((size * 0.7f).dp))
    }
}

/** iOS: `SceneStudioBadge` — studio logo on a dark scrim label when present, else the name. */
@Composable
fun StudioBadge(studio: Studio, modifier: Modifier = Modifier, small: Boolean = false, showLogo: Boolean = true) {
    if (showLogo && studio.hasImage) {
        NativeMediaLabelBox(modifier, small = small, scrim = true) {
            AsyncImage(
                studio.imageURL, studio.name, Modifier.height(if (small) 14.dp else 20.dp).widthIn(max = if (small) 110.dp else 120.dp),
                contentScale = ContentScale.Fit, alignment = Alignment.CenterStart,
            )
        }
    } else {
        NativeMediaLabel(studio.name, modifier, small = small)
    }
}
