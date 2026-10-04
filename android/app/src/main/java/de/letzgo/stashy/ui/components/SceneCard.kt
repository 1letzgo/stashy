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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.GlassBadge
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow

/**
 * iOS: `SceneCardView` — thumbnail filling the card, studio badge top-left, date top-right,
 * gradient with title, duration and performer count at the bottom, resume bar.
 * (Long-press preview is added by the player feature.)
 */
@Composable
fun SceneCard(scene: Scene, modifier: Modifier = Modifier, aspectRatio: Float = 16f / 9f, showDate: Boolean = true) {
    val p = Theme.palette
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(
        modifier
            .cardShadow(shape)
            .clip(shape)
            .background(p.secondaryBackground)
            .fillMaxWidth()
            .aspectRatio(aspectRatio),
    ) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)))
        AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)

        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            scene.studio?.let { StudioBadge(it) }
            Box(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (showDate) scene.date?.let { GlassBadge(it) }
                if (Downloads.isDownloaded(scene.id)) {
                    Box(Modifier.size(20.dp).clip(CircleShape).background(Color(0xFF30D158)), contentAlignment = Alignment.Center) {
                        Icon(SF.checkmarkCircleFill, null, tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }

        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(100.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))),
        )
        Row(
            Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                scene.displayTitle, Modifier.weight(1f),
                style = IosTypography.headline.copy(fontWeight = FontWeight.Medium),
                color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            formatDuration(scene.sceneDuration)?.let { GlassBadge(it, icon = SF.clock) }
            if (scene.performers.isNotEmpty()) GlassBadge("${scene.performers.size}", icon = SF.person2)
        }

        val resume = scene.resumeTime ?: 0.0
        val duration = scene.sceneDuration
        if (resume > 0 && duration != null) {
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp).background(Color.White.copy(alpha = 0.2f)))
            Box(
                Modifier.align(Alignment.BottomStart).fillMaxWidth((resume / duration).toFloat().coerceIn(0f, 1f)).height(5.dp)
                    .background(Appearance.tint),
            )
        }
    }
}

/** iOS: `SceneStudioBadge` — studio logo on glass when present, else the name. */
@Composable
fun StudioBadge(studio: Studio, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(50)
    Box(
        modifier.clip(shape).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 8.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (studio.hasImage) {
            AsyncImage(studio.imageURL, studio.name, Modifier.height(22.dp).widthIn(max = 120.dp), contentScale = ContentScale.Fit, alignment = Alignment.CenterStart)
        } else {
            Text(studio.name, style = IosTypography.caption.copy(fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1)
        }
    }
}
