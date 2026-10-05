package de.letzgo.stashy.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeCard
import de.letzgo.stashy.ui.NativeMediaLabel
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.stashyGlass

// Cards used inside the detail grids. Private ports until the catalog's shared cards in
// `ui/components/` land — then swap them (same iOS sources).

/** iOS `Performer.thumbnailURL` — `image_path`, else `<base>/performer/<id>/image`. */
internal fun performerThumbnailURL(id: String, imagePath: String?): String? =
    Net.signed(imagePath?.takeIf { it.startsWith("http") } ?: ServerConfigManager.activeConfig?.let { "${it.baseURL}/performer/$id/image" })

/** iOS `StashGroup.thumbnailURL` — front image at width 320 with `t=updated_at`. */
internal fun groupThumbnailURL(g: StashGroup): String? {
    val path = g.frontImagePath ?: return null
    var url = path + (if (path.contains("?")) "&" else "?") + "width=320"
    g.updatedAt?.let { url += "&t=" + android.net.Uri.encode(it) }
    return Net.signed(url)
}

private val cardShape = RoundedCornerShape(Tokens.Radius.card)

@Composable
private fun CardBox(modifier: Modifier, aspect: Float, onClick: (() -> Unit)?, content: @Composable BoxScope.() -> Unit) {
    NativeCard(modifier.fillMaxWidth().aspectRatio(aspect), onClick = onClick, content = content)
}

@Composable
private fun CardImage(url: String?, placeholder: ImageVector, alignment: Alignment = Alignment.Center) {
    Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)))
    if (url == null) {
        Box(Modifier.fillMaxSize(), Alignment.Center) { Icon(placeholder, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(36.dp)) }
        return
    }
    SubcomposeAsyncImage(
        url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = alignment,
        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), color = Theme.palette.secondaryText, strokeWidth = 2.dp) } },
        error = { Box(Modifier.fillMaxSize(), Alignment.Center) { Icon(placeholder, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(36.dp)) } },
    )
}

@Composable
private fun BoxScope.BottomGradient(height: Float = 0.45f) {
    Box(
        Modifier.align(Alignment.BottomCenter).fillMaxWidth().fillMaxHeight(height)
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f)))),
    )
}

/** iOS `cardPill` — Android look: Material label. */
@Composable
private fun CardPill(icon: ImageVector, text: String) = NativeMediaLabel(text, icon = icon)

/** iOS: `PerformerCardView` (9:12, top-anchored portrait, age + scene-count pills, name). */
@Composable
internal fun DetailPerformerCard(performer: Performer, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    CardBox(modifier, 9f / 12f, onClick) {
        CardImage(performerThumbnailURL(performer.id, performer.imagePath), SF.personFill, Alignment.TopCenter)
        BottomGradient(0.55f)
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            DetailFormatting.age(performer.birthdate)?.let { CardPill(SF.calendar, it) }
            Spacer(Modifier.weight(1f))
            CardPill(SF.film, "${performer.sceneCount ?: 0}")
        }
        Text(
            performer.name, Modifier.align(Alignment.BottomStart).padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** iOS: `StudioImageView` — logo fit (PNG/JPG/SVG via Coil), placeholder with the name. */
@Composable
internal fun StudioLogo(studio: Studio, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val placeholder: @Composable () -> Unit = {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(SF.building2, null, tint = p.secondaryText, modifier = Modifier.size(32.dp))
            Text(studio.name, style = IosTypography.caption, color = p.secondaryText, maxLines = 1, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
    if (!studio.hasImage) { Box(modifier) { placeholder() }; return }
    SubcomposeAsyncImage(
        studio.imageURL, studio.name, modifier, contentScale = ContentScale.Fit,
        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), color = p.secondaryText, strokeWidth = 2.dp) } },
        error = { placeholder() },
    )
}

@Composable
private fun CountLabel(icon: ImageVector, count: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(icon, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(11.dp))
        Text("$count", style = NativeType.labelMedium, color = Theme.palette.secondaryText)
    }
}

/** Logo block (2.2:1, studio header grey) + name/count row (iOS `StudioCardView` / `TagCardView`). */
@Composable
private fun LogoCard(modifier: Modifier, onClick: (() -> Unit)?, name: String, scenes: Int?, galleries: Int?, alwaysShowScenes: Boolean, logo: @Composable BoxScope.() -> Unit) {
    val p = Theme.palette
    NativeCard(modifier.fillMaxWidth(), onClick = onClick) { Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().aspectRatio(2.2f).background(p.studioHeader).clip(RoundedCornerShape(0.dp)), content = logo)
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, Modifier.weight(1f), style = NativeType.titleSmall, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (alwaysShowScenes || (scenes ?: 0) > 0) CountLabel(SF.film, scenes ?: 0)
                if ((galleries ?: 0) > 0) CountLabel(SF.photoStack, galleries ?: 0)
            }
        }
    } }
}

/** iOS: `StudioCardView`. */
@Composable
internal fun DetailStudioCard(studio: Studio, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    LogoCard(modifier, onClick, studio.name, studio.sceneCount, studio.galleryCount, true) {
        StudioLogo(studio, Modifier.fillMaxSize().padding(start = 14.dp, end = 14.dp, top = 12.dp))
    }
}

/** iOS: `TagImageView` — image, else tint fill with `#`. */
@Composable
internal fun TagImage(tag: Tag, modifier: Modifier = Modifier) {
    val fallback: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize().background(Appearance.tint), Alignment.Center) {
            Icon(SF.number, null, tint = Color.White, modifier = Modifier.size(32.dp))
        }
    }
    if (!tag.hasImage) { Box(modifier) { fallback() }; return }
    SubcomposeAsyncImage(
        tag.imageURL, tag.name, modifier, contentScale = ContentScale.Crop,
        loading = { Box(Modifier.fillMaxSize().background(Appearance.tint), Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp) } },
        error = { fallback() },
    )
}

/** iOS: `TagCardView`. */
@Composable
internal fun DetailTagCard(tag: Tag, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    LogoCard(modifier, onClick, tag.name, tag.sceneCount, tag.galleryCount, false) {
        if (tag.hasImage) TagImage(tag, Modifier.fillMaxSize())
        else Icon(SF.number, null, tint = Appearance.tint, modifier = Modifier.align(Alignment.Center).size(32.dp))
    }
}

/** iOS: `GalleryCardView` (1:1, studio badge, image count, title). */
@Composable
internal fun DetailGalleryCard(gallery: Gallery, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    CardBox(modifier, 1f, onClick) {
        CardImage(gallery.coverURL, SF.photoOnRectangle)
        BottomGradient(0.4f)
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            gallery.studio?.name?.let { NativeMediaLabel(it) }
            Spacer(Modifier.weight(1f))
            gallery.imageCount?.takeIf { it > 0 }?.let { NativeMediaLabel("$it", icon = SF.photoStack) }
        }
        Text(
            gallery.displayTitle, Modifier.align(Alignment.BottomStart).padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** iOS: `GroupCardView` (9:12 front cover, scene count badge, name). */
@Composable
internal fun DetailGroupCard(group: StashGroup, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    CardBox(modifier, 9f / 12f, onClick) {
        CardImage(groupThumbnailURL(group), SF.rectangleStack, Alignment.TopCenter)
        BottomGradient(0.45f)
        Row(Modifier.fillMaxWidth().padding(8.dp)) {
            Spacer(Modifier.weight(1f))
            group.sceneCount?.let { CardPill(SF.film, "$it") }
        }
        Text(
            group.name, Modifier.align(Alignment.BottomStart).padding(12.dp),
            style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** iOS: `ImageThumbnailCard` — thumbnail, play badge for clips, studio/date, name + extension. */
@Composable
internal fun DetailImageCard(image: StashImage, modifier: Modifier = Modifier, aspect: Float = 1f, onClick: (() -> Unit)? = null) {
    CardBox(modifier, aspect, onClick) {
        CardImage(image.thumbnailURL, SF.photo)
        if (image.isVideo) {
            Box(Modifier.align(Alignment.Center).size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.4f)), Alignment.Center) {
                Icon(SF.playFill, null, tint = Color.White, modifier = Modifier.size(24.dp))
            }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.Top) {
            image.studio?.name?.let { NativeMediaLabel(it) }
            Spacer(Modifier.weight(1f))
            image.date?.let { NativeMediaLabel(it) }
        }
        BottomGradient(0.4f)
        Row(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                image.performers?.firstOrNull()?.name ?: image.title ?: "Image", Modifier.weight(1f),
                style = NativeType.titleMedium, color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            DetailFormatting.fileExtension(image)?.let { NativeMediaLabel(it) }
        }
    }
}
