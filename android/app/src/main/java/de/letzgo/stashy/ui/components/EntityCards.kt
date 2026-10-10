package de.letzgo.stashy.ui.components

import de.letzgo.stashy.ui.scaledMaxLines
import de.letzgo.stashy.ui.scaledIconSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.PerformerBadgeType
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeMediaLabel
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.oCounterIcon
import java.time.LocalDate
import java.time.Period

/** Bottom gradient used by the poster cards (`.clear → .black 0.8`). */
private val bottomGradient = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))

/** iOS card pill (icon + count) — Android look: Material label ([NativeMediaLabel]). */
@Composable
fun CardPill(icon: ImageVector?, text: String, modifier: Modifier = Modifier) = NativeMediaLabel(text, modifier, icon)

/** Caption label (studio name / date / file extension on media cards). */
@Composable
fun CaptionPill(text: String, modifier: Modifier = Modifier, small: Boolean = false) = NativeMediaLabel(text, modifier, small = small)

@Composable
private fun PlaceholderIcon(icon: ImageVector, tint: Color = Theme.palette.secondaryText, size: Int = 34) =
    Icon(icon, null, tint = tint, modifier = Modifier.size(size.dp))

/** Age in years from a `yyyy-MM-dd` birthdate (iOS `PerformerCardView.ageText`). */
fun performerAge(birthdate: String?): Int? {
    val d = birthdate?.takeIf { it.isNotBlank() }?.let { runCatching { LocalDate.parse(it.take(10)) }.getOrNull() } ?: return null
    val y = Period.between(d, LocalDate.now()).years
    return y.takeIf { it in 1..119 }
}

/**
 * iOS: `PerformerCardView` — 9:12 portrait (top-anchored crop), age pill top-left, count pill
 * top-right (depends on the sort), bottom gradient with the name. [badge] (icon + text) replaces
 * the sort-driven count pill (performer detail "Appears with": shared scene count).
 */
@Composable
fun PerformerCard(
    performer: Performer,
    modifier: Modifier = Modifier,
    badgeType: PerformerBadgeType = PerformerBadgeType.SceneCount,
    badge: Pair<ImageVector, String>? = null,
    onClick: (() -> Unit)? = null,
) {
    val p = Theme.palette
    val (icon, text) = badge ?: when (badgeType) {
        PerformerBadgeType.SceneCount -> SF.film to "${performer.sceneCount ?: 0}"
        PerformerBadgeType.ImageCount -> SF.photo to "${performer.imageCount ?: 0}"
        PerformerBadgeType.GalleryCount -> SF.photoStack to "${performer.galleryCount ?: 0}"
        PerformerBadgeType.OCount -> oCounterIcon(Appearance.oCounterIcon) to "${performer.oCounter ?: 0}"
        PerformerBadgeType.Rating -> SF.starFill to "${performer.rating100 ?: 0}"
    }
    NativeCard(modifier.fillMaxWidth().aspectRatio(9f / 12f), onClick = onClick) { BoxWithConstraints(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            var failed by remember(performer.id, performer.imageURL) { mutableStateOf(performer.imageURL == null) }
            if (failed) PlaceholderIcon(SF.personFill)
            AsyncImage(performer.imageURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter, onError = { failed = true })
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(min(120.dp, maxHeight * 0.55f)).background(bottomGradient))
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            performerAge(performer.birthdate)?.let { CardPill(SF.calendar, "$it") }
            Spacer(Modifier.weight(1f))
            CardPill(icon, text)
        }
        Text(
            performer.name, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    } }
}

/**
 * iOS: `StudioCardView` — logo block (2.2:1, header grey, logo fitted with 14/12 insets) above a
 * name row with scene and gallery counts.
 */
@Composable
fun StudioCard(studio: Studio, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth(), onClick = onClick) { Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().aspectRatio(2.2f).background(p.studioHeader), contentAlignment = Alignment.Center) {
            StudioLogo(studio, Modifier.fillMaxSize().padding(start = 14.dp, end = 14.dp, top = 12.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(studio.name, Modifier.weight(1f), style = NativeType.titleSmall, color = p.text, maxLines = scaledMaxLines(), overflow = TextOverflow.Ellipsis)
            CountLabel(SF.film, studio.sceneCount ?: 0)
            studio.galleryCount?.takeIf { it > 0 }?.let { CountLabel(SF.photoStack, it) }
        }
    } }
}

/** iOS: `StudioImageView` — logo (PNG/JPG/SVG) fitted, else building icon + name. */
@Composable
fun StudioLogo(studio: Studio, modifier: Modifier = Modifier) {
    val p = Theme.palette
    var failed by remember(studio.id) { mutableStateOf(!studio.hasImage) }
    Box(modifier, contentAlignment = Alignment.Center) {
        if (failed) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                PlaceholderIcon(SF.building2)
                Text(studio.name, Modifier.padding(horizontal = 4.dp), style = NativeType.labelMedium, color = p.secondaryText, maxLines = 1)
            }
        } else {
            val url = studio.imageURL?.let { u -> studio.updatedAt?.let { "$u${if (u.contains("?")) "&" else "?"}t=${android.net.Uri.encode(it)}" } ?: u }
            AsyncImage(url, studio.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit, onError = { failed = true })
        }
    }
}

@Composable
private fun CountLabel(icon: ImageVector, count: Int) {
    val p = Theme.palette
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(icon, null, tint = p.secondaryText, modifier = Modifier.size(scaledIconSize(14.dp)))
        Text("$count", style = NativeType.labelMedium, color = p.secondaryText)
    }
}

/** iOS: `TagCardView.hasCustomImage` — Stash's generated default image doesn't count. */
val Tag.hasCustomImage: Boolean get() = imagePath != null && !imagePath.contains("default")

/**
 * iOS: `TagCardView` — image block (2.2:1, cover-cropped) or a tinted `#` on header grey, then the
 * name with scene / gallery counts.
 */
@Composable
fun TagCard(tag: Tag, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth(), onClick = onClick) { Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().aspectRatio(2.2f).background(p.studioHeader), contentAlignment = Alignment.Center) {
            if (tag.hasCustomImage) {
                var failed by remember(tag.id) { mutableStateOf(false) }
                if (failed) {
                    Box(Modifier.fillMaxSize().background(Appearance.tint), contentAlignment = Alignment.Center) { PlaceholderIcon(SF.number, Color.White, 32) }
                } else {
                    AsyncImage(tag.imageURL, tag.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, onError = { failed = true })
                }
            } else {
                PlaceholderIcon(SF.number, Appearance.tint, 32)
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(tag.name, Modifier.weight(1f), style = NativeType.titleSmall, color = p.text, maxLines = scaledMaxLines(), overflow = TextOverflow.Ellipsis)
            tag.sceneCount?.takeIf { it > 0 }?.let { CountLabel(SF.film, it) }
            tag.galleryCount?.takeIf { it > 0 }?.let { CountLabel(SF.photoStack, it) }
        }
    } }
}

/**
 * iOS: `GalleryCardView` — cover filling the card ([aspectRatio] 16:9 at 1/row, 1:1 at 2/row),
 * studio pill top-left, image count top-right, gradient (40 %) with the title.
 */
@Composable
fun GalleryCard(gallery: Gallery, modifier: Modifier = Modifier, aspectRatio: Float = 1f, shape: androidx.compose.ui.graphics.Shape = de.letzgo.stashy.ui.NativeCardShape, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth().aspectRatio(aspectRatio), shape = shape, onClick = onClick) { BoxWithConstraints(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            var failed by remember(gallery.id) { mutableStateOf(gallery.coverURL == null) }
            if (failed) PlaceholderIcon(SF.photoOnRectangle, size = 40)
            AsyncImage(gallery.coverURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, onError = { failed = true })
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(maxHeight * 0.4f).background(bottomGradient))
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            gallery.studio?.name?.let { CaptionPill(it, Modifier.weight(1f, fill = false)) }
            Spacer(Modifier.weight(1f))
            gallery.imageCount?.takeIf { it > 0 }?.let { NativeMediaLabel("$it", icon = SF.photoStack) }
        }
        Text(
            gallery.displayTitle, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    } }
}

/**
 * iOS: `GroupCardView` — 9:12 front cover (top-anchored), scene count pill top-right, gradient
 * (100 pt) with the name.
 */
@Composable
fun GroupCard(group: StashGroup, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth().aspectRatio(9f / 12f), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
            var failed by remember(group.id) { mutableStateOf(group.frontImageURL == null) }
            if (failed) PlaceholderIcon(SF.rectangleStack)
            AsyncImage(group.frontImageURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter, onError = { failed = true })
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(100.dp).background(bottomGradient))
        Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            group.sceneCount?.let { CardPill(SF.film, "$it") }
        }
        Text(
            group.name, Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** iOS: `StashImage.fileExtension` — upper-cased extension of the first visual file. */
val StashImage.fileExtension: String? get() {
    val f = visualFiles?.firstOrNull() ?: return null
    val name = f.basename?.takeIf { it.isNotEmpty() } ?: f.path?.substringAfterLast('/') ?: return null
    return name.substringAfterLast('.', "").takeIf { it.isNotEmpty() && it != name }?.uppercase()
}

/** Aspect ratio for the 1/row Images layout (portrait images capped like iOS feed cells). */
val StashImage.oneColumnAspectRatio: Float get() = (aspectRatio ?: 1f).coerceIn(0.75f, 16f / 9f)

/**
 * iOS: `ImageThumbnailCard` — thumbnail filling the card, play badge for videos, studio / date
 * pills on top, gradient with performer (or title) and the file extension.
 */
@Composable
fun ImageCard(image: StashImage, modifier: Modifier = Modifier, aspectRatio: Float = 1f, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth().aspectRatio(aspectRatio), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
            var failed by remember(image.id) { mutableStateOf(image.thumbnailURL == null) }
            if (failed) PlaceholderIcon(SF.photo, size = 24)
            AsyncImage(image.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, onError = { failed = true })
            if (image.isVideo) Box(Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.4f)).padding(12.dp)) {
                Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(24.dp))
            }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            image.studio?.name?.let { CaptionPill(it, Modifier.weight(1f, fill = false)) }
            Spacer(Modifier.weight(1f))
            image.date?.let { CaptionPill(it) }
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(100.dp).background(bottomGradient))
        Row(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                image.performers?.firstOrNull()?.name ?: image.title ?: "Image", Modifier.weight(1f),
                style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            image.fileExtension?.let { CaptionPill(it, small = true) }
        }
    }
}

/** iOS: `SceneMarker.thumbnailURL` — the marker screenshot. */
val SceneMarker.thumbnailURL: String? get() = screenshotURL

/**
 * iOS: `MarkerCardView` — 16:9 screenshot on header grey, marker title pill top-left, scene title
 * bottom-left over a 60 pt gradient.
 */
@Composable
fun MarkerCard(marker: SceneMarker, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth().aspectRatio(16f / 9f), onClick = onClick) {
        Box(Modifier.fillMaxSize().background(p.studioHeader), contentAlignment = Alignment.Center) {
            var failed by remember(marker.id, marker.thumbnailURL) { mutableStateOf(marker.thumbnailURL == null) }
            if (failed) PlaceholderIcon(SF.bookmarkFill, Appearance.tint)
            AsyncImage(marker.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, onError = { failed = true })
        }
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(60.dp).background(bottomGradient))
        Column(Modifier.fillMaxSize().padding(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                NativeMediaLabel(marker.title ?: "Marker", Modifier.weight(1f, fill = false), small = true)
            }
            Spacer(Modifier.weight(1f))
            Text(
                marker.scene?.title ?: "Unknown Scene", Modifier.fillMaxWidth(),
                style = NativeType.titleSmall, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
