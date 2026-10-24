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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.sp
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
 * Detail header as a profile-style hero card (gallery, tag, studio, performer, group), 1:1 with
 * iOS `DetailHeroCard`. Top: a compact band ([HeroBandHeight]: a little padding above the
 * circle's upper half) with the picture blurred as backdrop (or a tint wash without one). The
 * 76dp circle avatar straddles the band's lower edge half/half, start-aligned at the content
 * padding. Below the edge: the [title] (22sp bold, one line centred on the circle's lower half;
 * wraps to two when it does not fit) with the compact [titleAccessory] (Feeds pill) and, when
 * anything can expand, the chevron pill; then the label/value grid in the normal text colours
 * (iOS column rule: `min(max(n, 2), 4)`), [footer] (e.g. the studio URL) and the [description]
 * under a divider, clamped to two lines.
 * Tapping the band or circle runs [DetailHero.onClick].
 * [collapsedItemCount] limits the grid until expanded (iOS default 4).
 */
@Composable
internal fun DetailHeroCard(
    title: String,
    items: List<DetailItem>,
    description: String?,
    expanded: Boolean,
    onToggle: () -> Unit,
    hero: DetailHero,
    collapsedItemCount: Int = 4,
    /** Next to the title (Feeds pill); gets the content colour to use (null = default). */
    titleAccessory: (@Composable (Color?) -> Unit)? = null,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    /** Secondary line under the title (only passed when expanded; iOS has none collapsed). */
    subtitle: String? = null,
    /** Something beyond grid and description appears when expanded (performer / group links). */
    footerHasMore: Boolean = false,
    /**
     * A second circle overlapping [hero]'s to its right (shared scenes of two performers). Each
     * circle runs its own [DetailHero.onClick]; the band is then not tappable.
     */
    secondHero: DetailHero? = null,
) {
    val p = Theme.palette
    val desc = description?.trim().orEmpty()
    // iOS `hasExpandableContent`: any description, or more cells than the collapsed limit.
    val expandable = footerHasMore || items.size > collapsedItemCount || desc.isNotEmpty()
    val visible = if (expanded) items else items.take(collapsedItemCount)
    HeaderCardFrame {
        Column(Modifier.fillMaxWidth()) {
            HeroHeaderLayout(hero, title, subtitle, expanded, titleAccessory, if (expandable) onToggle else null, secondHero)
            if (visible.isNotEmpty()) {
                Box(
                    Modifier.fillMaxWidth().padding(
                        start = HeroInset, end = HeroInset,
                        bottom = if (footer == null && desc.isEmpty()) 12.dp else 8.dp,
                    ),
                ) {
                    DetailItemsGrid(visible, columns = heroGridColumns(visible.size))
                }
            }
            if (footer != null) {
                Column(
                    Modifier.fillMaxWidth().padding(start = HeroInset, end = HeroInset + 28.dp, bottom = if (desc.isEmpty()) 10.dp else 6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) { footer() }
            }
            if (desc.isNotEmpty()) {
                Column(
                    Modifier.fillMaxWidth().padding(start = HeroInset, end = HeroInset, bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    HorizontalDivider(color = p.separator)
                    Text(
                        desc, style = IosTypography.caption, color = p.secondaryText,
                        maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** Top-biased crop for portraits / posters (performer image, group cover): keeps the face in view. */
internal val HeroPortraitBias = BiasAlignment(0f, -0.6f)

private val HeroAvatar = 76.dp
private val HeroInset = 16.dp
private val HeroTitleGap = 12.dp
/** Offset of the second circle: overlaps the first by a quarter of its width. */
private val HeroSecondAvatarShift = HeroAvatar * 0.75f
/** Band = top padding + the circle's upper half (the circle straddles the band edge). */
private val HeroBandHeight = 14.dp + HeroAvatar / 2

/**
 * Band + title row + the circle on their shared edge. A custom layout so the circle's vertical
 * center lands exactly on the band's bottom edge.
 */
@Composable
private fun HeroHeaderLayout(
    hero: DetailHero,
    title: String,
    subtitle: String?,
    expanded: Boolean,
    accessory: (@Composable (Color?) -> Unit)?,
    /** Non-null when something can expand: the chevron pill at the row end. */
    onToggle: (() -> Unit)?,
    second: DetailHero? = null,
) {
    val p = Theme.palette
    val secondShift = if (second != null) HeroSecondAvatarShift else 0.dp
    val textStart = HeroInset + HeroAvatar + secondShift + HeroTitleGap
    fun tapOf(h: DetailHero) = h.onClick?.let { Modifier.clickable(onClickLabel = h.clickLabel, onClick = it) } ?: Modifier
    val tap = tapOf(hero)
    // iOS `ViewThatFits`: a one-line title (+ pills) is centred on the circle's lower half
    // (band edge → circle bottom); a longer one wraps to two lines, starting a little below the edge.
    var singleLine by remember(title) { mutableStateOf(true) }
    val oneLine = singleLine && subtitle.isNullOrEmpty()
    Layout(
        content = {
            HeroBand(hero, if (second == null) tap else Modifier)
            Row(
                Modifier.fillMaxWidth()
                    .padding(start = textStart, end = HeroInset, top = if (oneLine) 0.dp else 6.dp, bottom = 10.dp)
                    .heightIn(min = HeroAvatar / 2),
                verticalAlignment = if (oneLine) Alignment.CenterVertically else Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(
                        title, fontSize = 22.sp, lineHeight = 26.sp, fontWeight = FontWeight.Bold, color = p.text,
                        maxLines = if (expanded) 4 else 2, overflow = TextOverflow.Ellipsis,
                        onTextLayout = { singleLine = it.lineCount <= 1 },
                    )
                    if (!subtitle.isNullOrEmpty()) {
                        Text(subtitle, style = IosTypography.caption, color = p.secondaryText)
                    }
                }
                if (accessory != null || onToggle != null) {
                    Row(
                        Modifier.padding(top = if (oneLine) 0.dp else 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        accessory?.invoke(null)
                        onToggle?.let { ExpandPill(expanded, it) }
                    }
                }
            }
            HeroAvatarCircle(hero, tap)
            if (second != null) HeroAvatarCircle(second, tapOf(second))
        },
    ) { measurables, constraints ->
        val loose = constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity)
        val band = measurables[0].measure(loose)
        val titleRow = measurables[1].measure(loose)
        val avatar = measurables[2].measure(Constraints())
        val secondAvatar = measurables.getOrNull(3)?.measure(Constraints())
        val width = constraints.maxWidth
        val below = maxOf(titleRow.height, avatar.height / 2 + 10.dp.roundToPx())
        layout(width, band.height + below) {
            band.place(0, 0)
            titleRow.place(0, band.height)
            avatar.place(HeroInset.roundToPx(), band.height - avatar.height / 2)
            secondAvatar?.place((HeroInset + secondShift).roundToPx(), band.height - secondAvatar.height / 2)
        }
    }
}

/**
 * iOS `avatarCircle`: opaque circle (a dark wash under a cover picture, the studio logo backdrop
 * under a logo, a tint wash under the placeholder), 2dp tint ring, soft shadow.
 */
@Composable
private fun HeroAvatarCircle(hero: DetailHero, tap: Modifier) {
    val p = Theme.palette
    val hasPicture = hero.backdropUrl != null
    val fill = when {
        !hasPicture -> Appearance.tint.copy(alpha = 0.15f).compositeOver(p.secondaryBackground)
        hero.style == DetailHero.Style.Logo -> hero.background
        else -> Color.Black.copy(alpha = 0.3f).compositeOver(p.secondaryBackground)
    }
    Box(
        Modifier.size(HeroAvatar).shadow(6.dp, CircleShape).clip(CircleShape).background(fill)
            .border(2.dp, Appearance.tint, CircleShape).then(tap),
        contentAlignment = Alignment.Center,
    ) {
        val inner = when (hero.style) {
            DetailHero.Style.Cover -> Modifier.matchParentSize().clip(CircleShape)
            // iOS pads the logo 14pt inside the circle so a wide logo is never cut.
            DetailHero.Style.Logo -> Modifier.matchParentSize().padding(14.dp)
        }
        Box(inner, content = hero.content)
    }
}

/**
 * iOS `bandBackground`: the picture scaled 1.3 and blurred 18dp over black (API 31+; older APIs
 * show it dimmed unblurred), under a 0.3 → 0.5 black gradient; without a picture a tint wash.
 * Only as tall as the circle's upper half plus a little padding.
 */
@Composable
private fun HeroBand(hero: DetailHero, tap: Modifier) {
    val hasPicture = hero.backdropUrl != null
    val base = if (hasPicture) Color.Black else Appearance.tint.copy(alpha = 0.15f)
    Box(Modifier.fillMaxWidth().height(HeroBandHeight).background(base).clipToBounds().then(tap)) {
        hero.backdropUrl?.let { u ->
            val canBlur = Build.VERSION.SDK_INT >= 31
            val logo = hero.style == DetailHero.Style.Logo
            Box(
                Modifier.matchParentSize()
                    .graphicsLayer { scaleX = 1.3f; scaleY = 1.3f; alpha = if (canBlur) 1f else 0.45f }.blur(18.dp)
                    .background(if (logo) hero.background else Color.Transparent),
            ) {
                AsyncImage(
                    u, null,
                    contentScale = if (logo) ContentScale.Fit else ContentScale.Crop,
                    alignment = hero.backdropAlignment,
                    modifier = Modifier.matchParentSize(),
                )
                if (logo) Box(Modifier.matchParentSize().background(Appearance.tint.copy(alpha = 0.18f)))
            }
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(0f to Color.Black.copy(alpha = 0.3f), 1f to Color.Black.copy(alpha = 0.5f))))
        }
    }
}

/** Circle content without a picture: the type icon in the pill accent (iOS 28pt semibold). */
@Composable
internal fun HeroPlaceholder(icon: ImageVector) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Icon(icon, null, tint = Theme.palette.pillAccent, modifier = Modifier.size(28.dp))
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
