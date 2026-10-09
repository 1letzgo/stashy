package de.letzgo.stashy.ui.detail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import coil3.compose.SubcomposeAsyncImage
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.scaledIconSize

/**
 * The picture of a [DetailHeroCard]. [Cover] fills the 16:9 frame center-cropped (gallery cover,
 * tag image); [Logo] keeps the whole picture (studio logo, ContentScale.Fit by the caller), inset
 * on [background] and kept above the title overlay.
 */
internal class DetailHero(
    val style: Style,
    val background: Color,
    val clickLabel: String,
    val onClick: () -> Unit,
    /** Fills its box; the card clips and positions it. */
    val content: @Composable BoxScope.() -> Unit,
) {
    enum class Style { Cover, Logo }
}

/**
 * Detail header as one hero card (gallery, tag, studio). With a [hero], the picture fills a 16:9
 * frame (capped to 70% of the screen height in landscape) and the [title] + label/value grid sit
 * on it in white over a bottom gradient; tapping the picture runs [DetailHero.onClick]. Without
 * one, the same title + grid on the plain card. Below, inside the same card: [footer] (e.g. the
 * studio URL) and the [description], clamped to three lines with the expand chevron when longer.
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
    /** Next to the title (Feeds pill); gets the content colour to use (white over the picture). */
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
                val screenHeight = LocalConfiguration.current.screenHeightDp.dp
                val density = LocalDensity.current
                var overlayHeight by remember { mutableStateOf(0.dp) }
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val frame = min(maxWidth * 9f / 16f, screenHeight * 0.7f)
                    // A logo keeps at least 72pt above the overlay; a cover only grows when a large
                    // font scale needs room for the overlay.
                    val minHeight = if (hero.style == DetailHero.Style.Logo) max(frame, overlayHeight + 72.dp) else frame
                    Box(
                        Modifier.fillMaxWidth().heightIn(min = minHeight).background(hero.background)
                            .clickable(onClickLabel = hero.clickLabel, onClick = hero.onClick),
                    ) {
                        val pictureBox = when (hero.style) {
                            DetailHero.Style.Cover -> Modifier.matchParentSize()
                            DetailHero.Style.Logo -> Modifier.matchParentSize()
                                .padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = overlayHeight + 4.dp)
                        }
                        Box(pictureBox, content = hero.content)
                        Box(
                            Modifier.matchParentSize()
                                .background(Brush.verticalGradient(0.35f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.8f))),
                        )
                        HeroTitleAndItems(
                            title, visible, expanded, Color.White, Color.White.copy(alpha = 0.75f), titleAccessory, onImage = true,
                            Modifier.align(Alignment.BottomStart).padding(top = 24.dp)
                                .onSizeChanged { overlayHeight = with(density) { it.height.toDp() } },
                        )
                    }
                }
            } else {
                HeroTitleAndItems(title, visible, expanded, p.text, p.secondaryText, titleAccessory, onImage = false, Modifier)
            }
            if (description != null || footer != null || expandable) {
                Column(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = if (hero != null) 6.dp else 0.dp, bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (hero == null && (description != null || footer != null)) HorizontalDivider(color = p.separator)
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

/** Title (title2 bold, two lines; all when expanded) + optional accessory, then the detail grid. */
@Composable
private fun HeroTitleAndItems(
    title: String,
    items: List<DetailItem>,
    expanded: Boolean,
    titleColor: Color,
    labelColor: Color,
    accessory: (@Composable (Color?) -> Unit)?,
    onImage: Boolean,
    modifier: Modifier,
) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                title, Modifier.weight(1f), style = IosTypography.title2.copy(fontWeight = FontWeight.Bold), color = titleColor,
                maxLines = if (expanded) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
            )
            accessory?.invoke(if (onImage) Color.White else null)
        }
        if (items.isNotEmpty()) DetailItemsGrid(items, labelColor = labelColor, valueColor = titleColor)
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
