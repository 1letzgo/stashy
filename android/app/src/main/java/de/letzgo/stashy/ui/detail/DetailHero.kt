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
import androidx.compose.ui.BiasAlignment
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.graphics.compositeOver
import coil3.compose.AsyncImage
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme

/**
 * The picture of a [DetailHeroCard]. [backdropUrl] is blurred behind the band (dashboard
 * `HeroBackdrop` technique); without one the band is a muted tinted solid. [content] fills the
 * sharp circle avatar (the picture, or [HeroPlaceholder] when there is none).
 * [Cover] center-crops in the circle (gallery cover, tag image); [Logo] keeps the whole picture
 * (studio logo, ContentScale.Fit by the caller), inset on [background], never cropped.
 * [onClick] (fullscreen) is null when there is no picture to open.
 */
internal class DetailHero(
    val style: Style,
    val backdropUrl: String?,
    val background: Color,
    val clickLabel: String,
    val onClick: (() -> Unit)?,
    /** Where the blurred backdrop is cropped (performer portraits: top-biased, toward the face). */
    val backdropAlignment: Alignment = Alignment.Center,
    /** Fills the circle; the card clips and positions it. */
    val content: @Composable BoxScope.() -> Unit,
) {
    enum class Style { Cover, Logo }
}

/**
 * Detail header as a profile-style hero card (gallery, tag, studio, performer). Top: a band (min 130dp,
 * grows with the grid) with the picture blurred as backdrop, or a muted tinted solid without a
 * picture, holding the label/value grid in white to the end side of the circle. The circle avatar
 * straddles the band's lower edge exactly half/half, start-aligned. Below the edge, on the plain
 * card background: the [title] + [titleAccessory] (Feeds pill) next to the circle's lower half,
 * then [footer] (e.g. the studio URL) and the [description], clamped to three lines. When
 * anything can expand, an expand pill (same chip as Feeds) ends the title row.
 * Tapping the band or circle runs [DetailHero.onClick].
 * [collapsedItemCount] limits the grid until expanded.
 */
@Composable
internal fun DetailHeroCard(
    title: String,
    items: List<DetailItem>,
    description: String?,
    expanded: Boolean,
    onToggle: () -> Unit,
    hero: DetailHero,
    collapsedItemCount: Int = Int.MAX_VALUE,
    /** Next to the title (Feeds pill); gets the content colour to use (null = default). */
    titleAccessory: (@Composable (Color?) -> Unit)? = null,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    /** Secondary line under the title (performer disambiguation). */
    subtitle: String? = null,
    /** The [footer] shows more when expanded (performer URLs beyond the first). */
    footerHasMore: Boolean = false,
) {
    val p = Theme.palette
    var descriptionOverflow by remember(description) { mutableStateOf(false) }
    val expandable = footerHasMore || items.size > collapsedItemCount || (description != null && (expanded || descriptionOverflow))
    val visible = if (expanded) items else items.take(collapsedItemCount)
    HeaderCardFrame {
        Column(Modifier.fillMaxWidth()) {
            HeroHeaderLayout(hero, title, subtitle, visible, expanded, titleAccessory, if (expandable) onToggle else null)
            if (description != null || footer != null) {
                Column(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    HorizontalDivider(color = p.separator)
                    if (footer != null) Column(Modifier.padding(vertical = 4.dp)) { footer() }
                    if (description != null) {
                        Text(
                            description, style = IosTypography.caption, color = p.secondaryText,
                            maxLines = if (expanded) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis,
                            onTextLayout = { if (!expanded) descriptionOverflow = it.hasVisualOverflow },
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                }
            } else {
                Spacer(Modifier.height(10.dp))
            }
        }
    }
}

/** Top-biased crop for portraits / posters (performer image, group cover): keeps the face in view. */
internal val HeroPortraitBias = BiasAlignment(0f, -0.6f)

private val HeroAvatar = 84.dp
private val HeroAvatarGap = 3.dp
private val HeroInset = 12.dp

/**
 * Band + title row + the circle on their shared edge. A custom layout so the circle's vertical
 * center lands exactly on the band's measured bottom, whatever height the grid gives the band.
 */
@Composable
private fun HeroHeaderLayout(
    hero: DetailHero,
    title: String,
    subtitle: String?,
    items: List<DetailItem>,
    expanded: Boolean,
    accessory: (@Composable (Color?) -> Unit)?,
    /** Non-null when something can expand: the chevron pill at the row end. */
    onToggle: (() -> Unit)?,
) {
    val p = Theme.palette
    val outer = HeroAvatar + HeroAvatarGap * 2
    // Text column start: past the circle, so neither grid nor title ever meets it.
    val textStart = HeroInset + outer + 10.dp
    val tap = hero.onClick?.let { Modifier.clickable(onClickLabel = hero.clickLabel, onClick = it) } ?: Modifier
    // A one-line title (+ pill) is centred on the circle's lower half (band edge → circle bottom);
    // a wrapping title starts a little below the edge and lets the row grow.
    var singleLine by remember(title) { mutableStateOf(true) }
    Layout(
        content = {
            HeroBand(hero, items, textStart, tap)
            Row(
                Modifier.fillMaxWidth().heightIn(min = outer / 2 + 6.dp)
                    .padding(start = textStart, end = HeroInset, top = if (singleLine) 0.dp else 6.dp, bottom = if (singleLine) 6.dp else 0.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        title, style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = p.text,
                        maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
                        onTextLayout = { singleLine = it.lineCount <= 1 },
                    )
                    if (!subtitle.isNullOrEmpty()) {
                        Text(subtitle, style = IosTypography.caption, color = p.secondaryText, maxLines = if (expanded) Int.MAX_VALUE else 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                accessory?.invoke(null)
                onToggle?.let { ExpandPill(expanded, it) }
            }
            // Card-coloured gap ring, then the Feeds performer-thumbnail ring (tinted fill, 2dp tint border).
            Box(
                Modifier.size(outer).clip(CircleShape).background(p.secondaryBackground).then(tap).padding(HeroAvatarGap),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier.size(HeroAvatar).clip(CircleShape)
                        .background(if (hero.style == DetailHero.Style.Logo && hero.backdropUrl != null) hero.background else Appearance.tint.copy(alpha = 0.2f))
                        .border(2.dp, Appearance.tint, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    val inner = when (hero.style) {
                        DetailHero.Style.Cover -> Modifier.matchParentSize().clip(CircleShape)
                        // Inscribed square-ish inset so a wide logo is never cut by the circle.
                        DetailHero.Style.Logo -> Modifier.matchParentSize().padding(HeroAvatar * 0.15f)
                    }
                    Box(inner, content = hero.content)
                }
            }
        },
    ) { measurables, constraints ->
        val loose = constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity)
        val band = measurables[0].measure(loose)
        val titleRow = measurables[1].measure(loose)
        val avatar = measurables[2].measure(Constraints())
        val width = constraints.maxWidth
        layout(width, band.height + titleRow.height) {
            band.place(0, 0)
            titleRow.place(0, band.height)
            avatar.place(HeroInset.roundToPx(), band.height - avatar.height / 2)
        }
    }
}

/**
 * Band: with a picture it is scaled 1.3 and blurred 18dp (soft but still recognisable) (API 31+; older APIs show it dimmed
 * unblurred, as the dashboard does) under a dark scrim; without one a muted tint on a dark base,
 * so the white grid reads in both themes. The grid sits to the end side of the circle.
 */
@Composable
private fun HeroBand(hero: DetailHero, items: List<DetailItem>, textStart: Dp, tap: Modifier) {
    val base = if (hero.backdropUrl != null) hero.background else Appearance.tint.copy(alpha = 0.45f).compositeOver(Color(0xFF26262A))
    Box(Modifier.fillMaxWidth().heightIn(min = 130.dp).background(base).clipToBounds().then(tap)) {
        hero.backdropUrl?.let { u ->
            val canBlur = Build.VERSION.SDK_INT >= 31
            AsyncImage(
                u, null, contentScale = ContentScale.Crop, alignment = hero.backdropAlignment,
                modifier = Modifier.matchParentSize()
                    .graphicsLayer { scaleX = 1.3f; scaleY = 1.3f; alpha = if (canBlur) 1f else 0.45f }.blur(18.dp),
            )
        }
        if (hero.backdropUrl != null) {
            Box(
                Modifier.matchParentSize()
                    // Less blur leaves more detail behind the white grid: a slightly darker scrim,
                    // plus a horizontal one deepening toward the grid side.
                    .background(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.22f), 1f to Color.Black.copy(alpha = 0.6f)))
                    .background(Brush.horizontalGradient(0f to Color.Transparent, 0.35f to Color.Black.copy(alpha = 0.12f), 1f to Color.Black.copy(alpha = 0.22f))),
            )
        }
        if (items.isNotEmpty()) {
            Box(Modifier.align(Alignment.CenterStart).fillMaxWidth().padding(start = textStart, end = HeroInset, top = 14.dp, bottom = 14.dp)) {
                DetailItemsGrid(items, labelColor = Color.White.copy(alpha = 0.72f), valueColor = Color.White)
            }
        }
    }
}

/** Circle content without a picture: the type icon, tinted. */
@Composable
internal fun HeroPlaceholder(icon: ImageVector) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Icon(icon, null, tint = Appearance.tint.copy(alpha = 0.8f), modifier = Modifier.size(34.dp))
    }
}

/** Remote picture for a [DetailHero]: spinner while loading, [placeholderIcon] when it fails. */
@Composable
internal fun HeroPicture(
    url: String?,
    contentDescription: String?,
    contentScale: ContentScale,
    placeholderIcon: ImageVector,
    alignment: Alignment = Alignment.Center,
) {
    SubcomposeAsyncImage(
        url, contentDescription, Modifier.fillMaxSize(), contentScale = contentScale, alignment = alignment,
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
