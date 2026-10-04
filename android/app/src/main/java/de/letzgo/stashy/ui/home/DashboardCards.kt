package de.letzgo.stashy.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.components.formatDuration
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.player.ScenePreviewOnHold
import de.letzgo.stashy.ui.stashyGlass

private val titleShadow = Shadow(Color.Black.copy(alpha = 0.8f), androidx.compose.ui.geometry.Offset(0f, 2f), 4f)

/** iOS: `HomeSceneCardView` — thumbnail, studio badge, duration, title, resume bar. */
@Composable
fun DashboardSceneCard(scene: Scene, isLarge: Boolean, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Box(modifier.size(width, height).clip(shape).background(Theme.palette.secondaryBackground)) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
            Icon(SF.film, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(24.dp))
        }
        AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        // iOS: hold 0.15 s → muted looping `paths.preview` (shared preview player pool).
        ScenePreviewOnHold(scene.previewURL)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(60.dp).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))))
        Column(Modifier.fillMaxSize().padding(start = 8.dp, end = 8.dp, top = 8.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                scene.studio?.let { DashboardStudioBadge(it, isLarge) }
                Spacer(Modifier.weight(1f))
                (scene.files?.firstOrNull()?.duration ?: scene.sceneDuration)?.let { formatDuration(it) }?.let {
                    Text(it, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White,
                        modifier = Modifier.stashyGlass(RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp))
                }
                if (Downloads.isDownloaded(scene.id)) {
                    Box(Modifier.size(18.dp).background(Color(0xFF30D158), CircleShape), contentAlignment = Alignment.Center) {
                        Icon(SF.checkmarkCircleFill, null, tint = Color.White, modifier = Modifier.size(12.dp))
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Text(
                scene.displayTitle,
                style = (if (isLarge) IosTypography.subheadline else TextStyle(fontSize = 12.sp)).copy(fontWeight = FontWeight.Bold, shadow = titleShadow),
                color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
        val resume = scene.resumeTime ?: 0.0
        val duration = scene.sceneDuration
        if (resume > 0 && duration != null) {
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(5.dp).background(Color.White.copy(alpha = 0.2f)))
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth((minOf(resume, duration) / duration).toFloat()).height(5.dp).background(Appearance.tint))
        }
    }
}

/** iOS `SceneStudioBadge(logoHeight: 14/12, font 9/8 bold uppercased)` on glass. */
@Composable
private fun DashboardStudioBadge(studio: Studio, isLarge: Boolean) {
    Box(Modifier.stashyGlass(RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 4.dp)) {
        if (TabManager.sceneCardsShowStudioLogo && studio.hasImage) {
            AsyncImage(studio.imageURL, studio.name, Modifier.height(if (isLarge) 14.dp else 12.dp).widthIn(max = if (isLarge) 130.dp else 100.dp), contentScale = ContentScale.Fit)
        } else {
            Text(studio.name.uppercase(), fontSize = if (isLarge) 9.sp else 8.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1)
        }
    }
}

/** iOS `PerformerBadgeType`. */
enum class PerformerBadge { SceneCount, OCount, Rating }

/** iOS: `HomePerformerCardView` — portrait image (top-aligned), count badge, name. */
@Composable
fun DashboardPerformerCard(performer: Performer, badge: PerformerBadge, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    Box(modifier.size(width, height).clip(RoundedCornerShape(Tokens.Radius.card)).background(Theme.palette.secondaryBackground)) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(SF.personFill, null, tint = Theme.palette.secondaryText)
        }
        AsyncImage(performer.imageURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(50.dp).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))))
        Column(Modifier.fillMaxSize().padding(6.dp)) {
            Row(Modifier.align(Alignment.End).stashyGlass(RoundedCornerShape(50)).padding(horizontal = 5.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                val icon = when (badge) { PerformerBadge.OCount -> oCounterIcon(Appearance.oCounterIcon, filled = true); PerformerBadge.Rating -> SF.starFill; PerformerBadge.SceneCount -> SF.film }
                val value = when (badge) { PerformerBadge.OCount -> performer.oCounter ?: 0; PerformerBadge.Rating -> performer.rating100 ?: 0; PerformerBadge.SceneCount -> performer.sceneCount ?: 0 }
                Icon(icon, null, tint = Color.White, modifier = Modifier.size(9.dp))
                Text("$value", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            Spacer(Modifier.weight(1f))
            Text(performer.name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TextStyle(shadow = titleShadow))
        }
    }
}

/** iOS: `HomeStudioCardView` — logo on the grey header, name + scene/gallery counts below. */
@Composable
fun DashboardStudioCard(studio: Studio, isLarge: Boolean, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val barHeight = if (isLarge) 36.dp else 32.dp
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Column(modifier.size(width, height).cardShadow(shape).clip(shape).background(p.secondaryBackground)) {
        Box(Modifier.fillMaxWidth().height(height - barHeight).background(p.studioHeader).padding(12.dp), contentAlignment = Alignment.Center) {
            if (studio.hasImage) AsyncImage(studio.imageURL, studio.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(SF.building2, null, tint = p.secondaryText, modifier = Modifier.size(30.dp))
                Text(studio.name, style = IosTypography.caption, color = p.secondaryText, maxLines = 1)
            }
        }
        Row(
            Modifier.fillMaxWidth().height(barHeight).padding(horizontal = if (isLarge) 10.dp else 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(studio.name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            val iconSize = if (isLarge) 11.dp else 9.dp
            val font = if (isLarge) 11.sp else 9.sp
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Icon(SF.film, null, tint = p.secondaryText, modifier = Modifier.size(iconSize))
                Text("${studio.sceneCount ?: 0}", fontSize = font, fontWeight = FontWeight.Medium, color = p.secondaryText)
            }
            studio.galleryCount?.takeIf { it > 0 }?.let { gc ->
                Row(Modifier.background(Color.Black.copy(alpha = 0.1f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Icon(SF.photoStack, null, tint = p.secondaryText, modifier = Modifier.size(iconSize))
                    Text("$gc", fontSize = font, fontWeight = FontWeight.Medium, color = p.secondaryText)
                }
            }
        }
    }
}
