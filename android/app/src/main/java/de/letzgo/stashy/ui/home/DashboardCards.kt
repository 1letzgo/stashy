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
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeCardShape
import de.letzgo.stashy.ui.NativeHeroShape
import de.letzgo.stashy.ui.NativeMediaLabel
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.components.DownloadedMark
import de.letzgo.stashy.ui.components.StudioBadge
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.components.formatDuration
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.player.ScenePreviewOnHold

private val titleShadow = Shadow(Color.Black.copy(alpha = 0.8f), androidx.compose.ui.geometry.Offset(0f, 2f), 4f)

/** Card shape of the dashboard rows: Material carousel radius for the hero row. */
internal fun dashboardCardShape(isLarge: Boolean) = if (isLarge) NativeHeroShape else NativeCardShape

/**
 * iOS: `HomeSceneCardView` — thumbnail, studio badge, duration, title, resume bar.
 * Android look: Material `ElevatedCard` (28 dp hero / 12 dp row items), Material labels, ripple on
 * [onClick]; holding 0.15 s still plays the muted preview.
 */
@Composable
fun DashboardSceneCard(scene: Scene, isLarge: Boolean, width: Dp, height: Dp, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    NativeCard(modifier.size(width, height), shape = dashboardCardShape(isLarge), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
            Icon(SF.film, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(24.dp))
        }
        AsyncImage(scene.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        // iOS: hold 0.15 s → muted looping `paths.preview` (shared preview player pool).
        ScenePreviewOnHold(scene.previewURL)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(if (isLarge) 80.dp else 60.dp).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)))))
        val inset = if (isLarge) 12.dp else 8.dp
        Column(Modifier.fillMaxSize().padding(start = inset, end = inset, top = inset, bottom = if (isLarge) 14.dp else 10.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                scene.studio?.let { StudioBadge(it, Modifier.weight(1f, fill = false), small = !isLarge, showLogo = TabManager.sceneCardsShowStudioLogo) }
                Spacer(Modifier.weight(1f))
                (scene.files?.firstOrNull()?.duration ?: scene.sceneDuration)?.let { formatDuration(it) }?.let {
                    NativeMediaLabel(it, small = !isLarge)
                }
                if (Downloads.isDownloaded(scene.id)) DownloadedMark(18)
            }
            Spacer(Modifier.weight(1f))
            Text(
                scene.displayTitle,
                style = (if (isLarge) NativeType.titleMedium else NativeType.labelLarge).copy(shadow = titleShadow),
                color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
        val resume = scene.resumeTime ?: 0.0
        val duration = scene.sceneDuration
        if (resume > 0 && duration != null) {
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.25f)))
            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth((minOf(resume, duration) / duration).toFloat()).height(4.dp).background(Appearance.tint))
        }
    }
}

/** iOS `PerformerBadgeType`. */
enum class PerformerBadge { SceneCount, OCount, Rating }

/** iOS: `HomePerformerCardView` — portrait image (top-aligned), count badge, name. */
@Composable
fun DashboardPerformerCard(performer: Performer, badge: PerformerBadge, width: Dp, height: Dp, modifier: Modifier = Modifier, isLarge: Boolean = false, onClick: (() -> Unit)? = null) {
    NativeCard(modifier.size(width, height), shape = dashboardCardShape(isLarge), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            Icon(SF.personFill, null, tint = Theme.palette.secondaryText)
        }
        AsyncImage(performer.imageURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(50.dp).background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)))))
        Column(Modifier.fillMaxSize().padding(6.dp)) {
            val icon = when (badge) { PerformerBadge.OCount -> oCounterIcon(Appearance.oCounterIcon, filled = true); PerformerBadge.Rating -> SF.starFill; PerformerBadge.SceneCount -> SF.film }
            val value = when (badge) { PerformerBadge.OCount -> performer.oCounter ?: 0; PerformerBadge.Rating -> performer.rating100 ?: 0; PerformerBadge.SceneCount -> performer.sceneCount ?: 0 }
            NativeMediaLabel("$value", Modifier.align(Alignment.End), icon = icon, small = true)
            Spacer(Modifier.weight(1f))
            Text(performer.name, style = NativeType.labelLarge.copy(shadow = titleShadow), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 2.dp))
        }
    }
}

/** iOS: `HomeStudioCardView` — logo on the grey header, name + scene/gallery counts below. */
@Composable
fun DashboardStudioCard(studio: Studio, isLarge: Boolean, width: Dp, height: Dp, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    val barHeight = if (isLarge) 40.dp else 34.dp
    NativeCard(modifier.size(width, height), shape = dashboardCardShape(isLarge), onClick = onClick) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxWidth().height(height - barHeight).background(p.studioHeader).padding(12.dp), contentAlignment = Alignment.Center) {
                if (studio.hasImage) AsyncImage(studio.imageURL, studio.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(SF.building2, null, tint = p.secondaryText, modifier = Modifier.size(30.dp))
                    Text(studio.name, style = NativeType.labelMedium, color = p.secondaryText, maxLines = 1)
                }
            }
            Row(
                Modifier.fillMaxWidth().height(barHeight).padding(horizontal = if (isLarge) 12.dp else 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(studio.name, style = if (isLarge) NativeType.titleSmall else NativeType.labelLarge, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                val iconSize = if (isLarge) 14.dp else 12.dp
                val style = if (isLarge) NativeType.labelMedium else NativeType.labelSmall
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    Icon(SF.film, null, tint = p.secondaryText, modifier = Modifier.size(iconSize))
                    Text("${studio.sceneCount ?: 0}", style = style, color = p.secondaryText)
                }
                studio.galleryCount?.takeIf { it > 0 }?.let { gc ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Icon(SF.photoStack, null, tint = p.secondaryText, modifier = Modifier.size(iconSize))
                        Text("$gc", style = style, color = p.secondaryText)
                    }
                }
            }
        }
    }
}
