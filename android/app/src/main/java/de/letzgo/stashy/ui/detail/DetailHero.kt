package de.letzgo.stashy.ui.detail

import android.os.Build
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.scaledIconSize

/**
 * The picture of a [DetailHeroCard]. [backdropUrl] is blurred behind the band (dashboard
 * `HeroBackdrop` technique); [content] fills the sharp circle avatar in front of the title.
 * [Cover] center-crops in the circle (gallery cover, tag image); [Logo] keeps the whole picture
 * (studio logo, ContentScale.Fit by the caller), inset on [background], never cropped.
 */
internal class DetailHero(
    val style: Style,
    val backdropUrl: String?,
    val background: Color,
    val clickLabel: String,
    val onClick: () -> Unit,
    /** Fills the circle; the card clips and positions it. */
    val content: @Composable BoxScope.() -> Unit,
) {
    enum class Style { Cover, Logo }
}

/**
 * Detail header as one hero card (gallery, tag, studio). With a [hero], a compact band (160dp,
 * grows with large font scales) shows the picture blurred as a backdrop with a sharp circle
 * avatar (Feeds ring style) and the [title] + [titleAccessory] in white next to it; tapping the
 * band runs [DetailHero.onClick]. Below it, on the plain card background with the normal text
 * colours: the label/value grid, [footer] (e.g. the studio URL) and the [description], clamped to
 * three lines with the expand chevron when longer. Without a hero, title + grid on the plain card.
 * [collapsedItemCount] limits the grid until expanded.
 */
@Composable
internal fun DetailHeroCard(
    title: String,
    items: List<DetailItem>,
    description: String?,
    expanded: Boolean,
    onToggle: () -> Unit,
    hero: DetailHero?,
    collapsedItemCount: Int = Int.MAX_VALUE,
    /** Next to the title (Feeds pill); gets the content colour to use (white on the band). */
    titleAccessory: (@Composable (Color?) -> Unit)? = null,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val p = Theme.palette
    var descriptionOverflow by remember(description) { mutableStateOf(false) }
    val expandable = items.size > collapsedItemCount || (description != null && (expanded || descriptionOverflow))
    val visible = if (expanded) items else items.take(collapsedItemCount)
    HeaderCardFrame {
        Column(Modifier.fillMaxWidth()) {
            if (hero != null) {
                HeroBand(hero, title, expanded, titleAccessory)
                if (visible.isNotEmpty()) {
                    Box(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = if (description != null || footer != null || expandable) 0.dp else 10.dp)) {
                        DetailItemsGrid(visible, labelColor = p.secondaryText, valueColor = p.text)
                    }
                }
            } else {
                PlainTitleAndItems(title, visible, expanded, titleAccessory)
            }
            if (description != null || footer != null || expandable) {
                Column(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = if (hero != null) 8.dp else 0.dp, bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if ((hero == null || visible.isNotEmpty()) && (description != null || footer != null)) HorizontalDivider(color = p.separator)
                    if (footer != null) Column(Modifier.padding(vertical = 4.dp)) { footer() }
                    if (description != null) {
                        Text(
                            description, style = IosTypography.caption, color = p.secondaryText,
                            maxLines = if (expanded) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis,
                            onTextLayout = { if (!expanded) descriptionOverflow = it.hasVisualOverflow },
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                    if (expandable) Spacer(Modifier.height(scaledIconSize(18.dp)))
                }
            }
        }
        if (expandable) HeaderExpandButton(expanded, onToggle)
    }
}

/**
 * Blurred backdrop band: the picture scaled 1.3 and blurred 40dp (API 31+; older APIs show it
 * dimmed unblurred, as the dashboard does) under a dark scrim, then the circle avatar + title.
 */
@Composable
private fun HeroBand(hero: DetailHero, title: String, expanded: Boolean, accessory: (@Composable (Color?) -> Unit)?) {
    val avatar = 72.dp
    Box(
        Modifier.fillMaxWidth().heightIn(min = 160.dp).background(hero.background).clipToBounds()
            .clickable(onClickLabel = hero.clickLabel, onClick = hero.onClick),
    ) {
        hero.backdropUrl?.let { u ->
            val canBlur = Build.VERSION.SDK_INT >= 31
            AsyncImage(
                u, null, contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize()
                    .graphicsLayer { scaleX = 1.3f; scaleY = 1.3f; alpha = if (canBlur) 1f else 0.45f }.blur(40.dp),
            )
        }
        Box(
            Modifier.matchParentSize()
                .background(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.15f), 1f to Color.Black.copy(alpha = 0.55f))),
        )
        Row(
            Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 16.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Feeds performer-thumbnail ring: tinted fill, 2dp tint border.
            Box(
                Modifier.size(avatar).clip(CircleShape)
                    .background(if (hero.style == DetailHero.Style.Logo) hero.background else Appearance.tint.copy(alpha = 0.2f))
                    .border(2.dp, Appearance.tint, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                val inner = when (hero.style) {
                    DetailHero.Style.Cover -> Modifier.matchParentSize().clip(CircleShape)
                    // Inscribed square-ish inset so a wide logo is never cut by the circle.
                    DetailHero.Style.Logo -> Modifier.matchParentSize().padding(avatar * 0.15f)
                }
                Box(inner, content = hero.content)
            }
            Text(
                title, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = Color.White,
                maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
            )
            accessory?.invoke(Color.White)
        }
    }
}

/** No picture: title (title2 bold, two lines; all when expanded) + accessory, then the grid. */
@Composable
private fun PlainTitleAndItems(
    title: String,
    items: List<DetailItem>,
    expanded: Boolean,
    accessory: (@Composable (Color?) -> Unit)?,
) {
    val p = Theme.palette
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                title, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text,
                maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
            )
            accessory?.invoke(null)
        }
        if (items.isNotEmpty()) DetailItemsGrid(items, labelColor = p.secondaryText, valueColor = p.text)
    }
}

/** Remote picture for a [DetailHero]: spinner while loading, [placeholderIcon] when it fails. */
@Composable
internal fun HeroPicture(url: String?, contentDescription: String?, contentScale: ContentScale, placeholderIcon: ImageVector) {
    SubcomposeAsyncImage(
        url, contentDescription, Modifier.fillMaxSize(), contentScale = contentScale, alignment = Alignment.Center,
        loading = { Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), color = Color.White.copy(alpha = 0.7f), strokeWidth = 2.dp) } },
        error = {
            Box(Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.1f)), Alignment.Center) {
                Icon(placeholderIcon, null, tint = StashyColors.appAccent.copy(alpha = 0.5f), modifier = Modifier.size(34.dp))
            }
        },
    )
}

/**
 * Fullscreen view of a header picture that is not a Stash image (tag image, studio logo): the
 * whole picture fit on [background], pinch / double-tap zoom, tap toggles the back bar.
 */
internal class HeroPictureViewerScreen(
    val url: String,
    val title: String,
    val background: Color = Color.Black,
    /** Logos get breathing room around them. */
    val inset: Boolean = false,
) : Screen {
    override val key = "hero-picture-$url"
    override val hidesTabBar = true

    @Composable
    override fun Content() {
        var showUI by remember { mutableStateOf(true) }
        var scale by remember { mutableFloatStateOf(1f) }
        var offset by remember { mutableStateOf(Offset.Zero) }
        Box(
            Modifier.fillMaxSize().background(background)
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(1f, 6f)
                        offset = if (scale == 1f) Offset.Zero else offset + pan
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { showUI = !showUI },
                        onDoubleTap = {
                            if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f
                        },
                    )
                },
        ) {
            Box(
                Modifier.fillMaxSize().padding(if (inset) 32.dp else 0.dp)
                    .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y },
            ) {
                HeroPicture(url, title, ContentScale.Fit, de.letzgo.stashy.ui.SF.photo)
            }
            AnimatedVisibility(showUI, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.TopStart)) {
                NativeTopBar(title, transparent = true)
            }
        }
    }
}
