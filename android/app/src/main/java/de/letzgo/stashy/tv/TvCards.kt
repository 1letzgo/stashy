package de.letzgo.stashy.tv

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.player.PreviewSurface
import de.letzgo.stashy.ui.player.rememberPreviewPlayer
import kotlinx.coroutines.delay

private val cardGradient = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.3f), Color.Black.copy(alpha = 0.8f)))

/** Hue from the name (tvOS `tagColor` / `groupColor`: saturation 0.35, brightness 0.3). */
fun nameColor(name: String): Color = Color.hsv((Math.floorMod(name.hashCode(), 360)).toFloat(), 0.35f, 0.3f)

/**
 * iOS: `TVFocusPreview` — muted preview clip that fades in once the card has held focus for 2 s.
 */
@Composable
fun BoxScope.TvFocusPreview(url: String?, focused: Boolean, radius: Dp = pt(10)) {
    if (url == null) return
    val preview = rememberPreviewPlayer()
    var previewing by remember { mutableStateOf(false) }
    LaunchedEffect(focused, url) {
        if (focused) {
            delay(2000)
            preview.start(url)
            previewing = true
        } else if (previewing) {
            previewing = false
            preview.stop(release = true)
        }
    }
    AnimatedVisibility(previewing && preview.hasFirstFrame, Modifier.matchParentSize(), enter = fadeIn(), exit = fadeOut()) {
        PreviewSurface(preview, Modifier.fillMaxSize().clip(RoundedCornerShape(radius)))
    }
}

/** iOS: `TVSceneCardView` + the `TVNavButton` around it. */
@Composable
fun TvSceneCard(
    scene: Scene,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = pt(410),
    height: Dp = pt(230),
    showsFocusPreview: Boolean = true,
) {
    var focused by remember { mutableStateOf(false) }
    TvCardButton(onClick, modifier.onFocusChanged { focused = it.isFocused }) {
        Box(Modifier.width(width).height(height).clip(RoundedCornerShape(pt(10)))) {
            TvImage(scene.thumbnailURL, Modifier.fillMaxSize(), TvIcons.filmOutline)
            if (showsFocusPreview) TvFocusPreview(scene.previewURL, focused)
            Box(Modifier.matchParentSize().alpha(if (focused) 0.3f else 1f).background(cardGradient))
            Row(Modifier.fillMaxWidth().padding(pt(12)).align(Alignment.TopStart), verticalAlignment = Alignment.Top) {
                scene.studio?.let { TvPill(it.name, Modifier.weight(1f, fill = false), uppercase = true) }
                Spacer(Modifier.weight(1f))
                val duration = scene.sceneDuration
                if (duration != null && duration > 0) TvPill(TvFormat.time(duration), mono = true)
            }
            scene.rating100?.takeIf { it > 0 }?.let { TvRatingBadge(it, Modifier.align(Alignment.BottomEnd).padding(pt(12))) }
            TvFormat.progress(scene.resumeTime, scene.sceneDuration)?.let { p ->
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(pt(4)).background(Color.White.copy(alpha = 0.3f))) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(p).background(TvColors.tint))
                }
            }
        }
    }
}

/** iOS: `TVSceneCardTitleView` — title, date and up to three performers under the card. */
@Composable
fun TvSceneCardTitle(scene: Scene, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(top = pt(10))) {
        Text(scene.displayTitle, style = TvType.body.copy(fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
        scene.date?.takeIf { it.isNotEmpty() }?.let { Text(it, style = TvType.caption, color = TvColors.secondary, maxLines = 1) }
        if (scene.performers.isNotEmpty()) {
            Text(scene.performers.take(3).joinToString(", ") { it.name }, style = TvType.caption, color = TvColors.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Card + title column as used by every scene grid / row. */
@Composable
fun TvSceneTile(scene: Scene, onClick: () -> Unit, modifier: Modifier = Modifier, width: Dp = pt(410), height: Dp = pt(230), showsFocusPreview: Boolean = true) {
    Column(Modifier.width(width)) {
        TvSceneCard(scene, onClick, modifier, width, height, showsFocusPreview)
        TvSceneCardTitle(scene)
    }
}

/** Count pill in the top-right corner shared by the entity cards. */
@Composable
private fun BoxScope.CountPill(count: Int?, icon: ImageVector? = null) {
    if (count != null && count > 0) TvPill("$count", Modifier.align(Alignment.TopEnd).padding(pt(12)), icon = icon)
}

/** iOS: `TVPerformerCardView` (260 × 390). */
@Composable
fun TvPerformerCard(performer: Performer, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TvCardButton(onClick, modifier) {
        Box(Modifier.width(pt(260)).height(pt(390)).clip(RoundedCornerShape(pt(10)))) {
            TvImage(performer.imageURL, Modifier.fillMaxSize(), TvIcons.person, iconSize = pt(40))
            Box(Modifier.matchParentSize().background(cardGradient))
            CountPill(performer.sceneCount)
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12))) {
                Text(performer.name, style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                performer.disambiguation?.takeIf { it.isNotEmpty() }?.let {
                    Text(it, style = TvType.caption, color = Color.White.copy(alpha = 0.8f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** iOS: `TVStudioCardView` (410 × 230, logo fitted with 24 pt padding). */
@Composable
fun TvStudioCard(studio: Studio, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TvCardButton(onClick, modifier) {
        Box(Modifier.width(pt(410)).height(pt(230)).clip(RoundedCornerShape(pt(10))).background(TvColors.placeholder)) {
            TvImage(studio.imageURL?.takeIf { studio.hasImage }, Modifier.fillMaxSize().padding(pt(24)), TvIcons.building, Color.Transparent, ContentScale.Fit, pt(40))
            Box(Modifier.matchParentSize().background(cardGradient))
            CountPill(studio.sceneCount)
            Row(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12)), verticalAlignment = Alignment.Bottom) {
                Text(studio.name, Modifier.weight(1f), style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                studio.rating100?.let { TvRatingBadge(it, Modifier.padding(start = pt(12))) }
            }
        }
    }
}

/** iOS: `TVTagCardView` (400 × 225). */
@Composable
fun TvTagCard(tag: Tag, onClick: () -> Unit, modifier: Modifier = Modifier, width: Dp = pt(400), height: Dp = pt(225)) {
    TvCardButton(onClick, modifier) {
        Box(Modifier.width(width).height(height).clip(RoundedCornerShape(pt(10)))) {
            TvImage(tag.imageURL?.takeIf { tag.hasImage }, Modifier.fillMaxSize(), TvIcons.tag, nameColor(tag.name), iconSize = pt(32))
            Box(Modifier.matchParentSize().background(cardGradient))
            CountPill(tag.sceneCount)
            Text(tag.name, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12)), style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS: `TVGalleryCardView` (410 × 230). */
@Composable
fun TvGalleryCard(gallery: Gallery, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TvCardButton(onClick, modifier) {
        Box(Modifier.width(pt(410)).height(pt(230)).clip(RoundedCornerShape(pt(10)))) {
            TvImage(gallery.coverURL, Modifier.fillMaxSize(), TvIcons.photoStack)
            Box(Modifier.matchParentSize().background(cardGradient))
            CountPill(gallery.imageCount, TvIcons.photo)
            Text(gallery.displayTitle, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12)), style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS: `TVGroupCardView` (260 × 390). */
@Composable
fun TvGroupCard(group: StashGroup, onClick: () -> Unit, modifier: Modifier = Modifier) {
    TvCardButton(onClick, modifier) {
        Box(Modifier.width(pt(260)).height(pt(390)).clip(RoundedCornerShape(pt(10)))) {
            TvImage(group.frontImageURL, Modifier.fillMaxSize(), TvIcons.stack, nameColor(group.name), iconSize = pt(32))
            Box(Modifier.matchParentSize().background(cardGradient))
            CountPill(group.sceneCount)
            Text(group.name, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12)), style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS: `TVImageCardView` (300 × 300) + `TVImageCardTitleView`. */
@Composable
fun TvImageTile(image: StashImage, onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = pt(300)) {
    Column(Modifier.width(size)) {
        TvCardButton(onClick, modifier) {
            Box(Modifier.size(size).clip(RoundedCornerShape(pt(10)))) {
                TvImage(image.thumbnailURL, Modifier.fillMaxSize(), TvIcons.photo, iconSize = pt(32))
                image.performerPillText?.let {
                    TvPill(it, Modifier.align(Alignment.TopEnd).padding(pt(12)).widthIn(max = size - pt(24)), uppercase = true)
                }
                image.rating100?.takeIf { it > 0 }?.let {
                    Box(Modifier.align(Alignment.BottomEnd).padding(pt(8)).clip(RoundedCornerShape(pt(8))).background(Color.Black.copy(alpha = 0.6f)).padding(horizontal = pt(10), vertical = pt(5))) {
                        TvRatingBadge(it)
                    }
                }
            }
        }
        image.tvDisplayTitle?.let { Text(it, Modifier.padding(top = pt(10)), style = TvType.caption, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

/** iOS: the "See All" card at the end of a dashboard row. */
@Composable
fun TvSeeAllCard(onClick: () -> Unit, width: Dp, height: Dp, modifier: Modifier = Modifier) {
    TvCardButton(onClick, modifier, radius = pt(12)) {
        Column(
            Modifier.width(width).height(height).clip(RoundedCornerShape(pt(12))).background(Color.White.copy(alpha = 0.05f)),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
        ) {
            Icon(TvIcons.arrowRightCircle, null, Modifier.size(pt(60)), tint = Color.White.copy(alpha = 0.8f))
            Spacer(Modifier.height(pt(20)))
            Text("See All", style = TvType.headline.copy(fontWeight = FontWeight.Bold), color = Color.White)
        }
    }
}

/** iOS: `TVChannelCardView` — up to four thumbnails side by side, kind label + play badge. */
@Composable
fun TvChannelCard(channel: TvChannel, scenes: List<Scene>, onClick: () -> Unit, modifier: Modifier = Modifier, width: Dp = pt(410), height: Dp = pt(230)) {
    var focused by remember { mutableStateOf(false) }
    TvCardButton(onClick, modifier.onFocusChanged { focused = it.isFocused }) {
        Box(Modifier.width(width).height(height).clip(RoundedCornerShape(pt(10))).background(TvColors.placeholder)) {
            if (scenes.isEmpty()) {
                Icon(channel.icon, null, Modifier.align(Alignment.Center).size(pt(36)), tint = TvColors.secondary)
            } else {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(pt(2))) {
                    scenes.take(4).forEach { TvImage(it.thumbnailURL, Modifier.weight(1f).fillMaxHeight(), channel.icon) }
                }
            }
            Box(Modifier.matchParentSize().alpha(if (focused) 0.3f else 1f).background(cardGradient))
            Row(Modifier.fillMaxWidth().padding(pt(12)).align(Alignment.TopStart)) {
                TvPill(channel.subtitle, Modifier.weight(1f, fill = false), icon = channel.icon, uppercase = true)
                Spacer(Modifier.weight(1f))
                TvPill("", icon = TvIcons.play)
            }
            Text(channel.title, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(pt(12)), style = TvType.body.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
