package de.letzgo.stashy.ui.feeds

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.ui.composed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.components.AITagSuggestionBar
import de.letzgo.stashy.ui.components.TagChipRow
import de.letzgo.stashy.ui.components.TagChips
import de.letzgo.stashy.ui.components.showsTagRow
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.oCounterIcon
import de.letzgo.stashy.ui.stashyGlass
import kotlin.math.roundToInt

/** iOS: `StashyExpandingDock` metrics shared by the Feeds chrome. */
object FeedsDock {
    const val inactiveIconOpacity = 0.72f
    val itemSpacing = 10.dp
    val circleSize = 40.dp
    val iconSize = 18.dp
    val activeHeight = 40.dp
    /** Round overlay buttons (Play · Mute · Rating · O-Counter). */
    val stackedButtonSize = 48.dp
    val activeHorizontalPadding = 14.dp
    val iconLabelSpacing = 8.dp
    val edgePadding = 16.dp
    val hashtagForeground = Color.White.copy(alpha = 0.8f)
}

/** iOS mode icons (`ReelsMode.icon`). */
val ReelsModeType.icon: ImageVector get() = when (this) {
    ReelsModeType.Scenes -> SF.film
    ReelsModeType.Markers -> SF.bookmarkFill
    ReelsModeType.Clips -> SF.photoOnRectangleAngled
    ReelsModeType.Previews -> SF.playRectangleOnRectangleFill
    ReelsModeType.Pics -> SF.cameraFill
}

private val Capsule = RoundedCornerShape(50)

/** iOS: `StashyChromePillStyle` (glass capsule, min 40 pt). */
fun Modifier.chromePill(height: Dp = FeedsDock.activeHeight, width: Dp? = null): Modifier =
    this.height(height)
        .let { if (width != null) it.width(width) else it.widthIn(min = FeedsDock.circleSize) }
        .stashyGlass(Capsule)

/**
 * iOS: `StashySectionChromeBar` + `reelsModeDock` + `reelsFilterSortPill` — the Feeds top bar.
 * Selected mode = tinted glass capsule with label (iOS `stashyChromeFill`), the others glass circles.
 */
@Composable
fun FeedsTopBar(
    modes: List<ReelsModeType>,
    selected: ReelsModeType,
    onSelect: (ReelsModeType) -> Unit,
    onFilterSort: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Native Material tabs over the video (Android look), filter button at the end.
    de.letzgo.stashy.ui.NativeTabStrip(
        modes, selected, { it.title }, { if (it != selected) onSelect(it) }, modifier, transparent = true, icon = { it.icon },
        trailing = {
            androidx.compose.material3.IconButton(onClick = onFilterSort) {
                Icon(SF.sliderHorizontal3, "Filter and sort", tint = Color.White)
            }
        },
    )
}

@Composable
private fun ModeChip(mode: ReelsModeType, selected: Boolean, onClick: () -> Unit) {
    val shape = Capsule
    Row(
        Modifier
            .height(FeedsDock.activeHeight)
            .widthIn(min = FeedsDock.circleSize)
            .animateContentSize(spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow))
            .let { if (selected) it.stashyGlass(shape, Appearance.tint) else it.stashyGlass(shape) }
            .noIndicationClick(onClick)
            .padding(horizontal = if (selected) FeedsDock.activeHorizontalPadding else (FeedsDock.circleSize - FeedsDock.iconSize) / 2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (selected) FeedsDock.iconLabelSpacing else 0.dp),
    ) {
        Icon(mode.icon, mode.title, tint = if (selected) Color.White else Color.White.copy(alpha = FeedsDock.inactiveIconOpacity), modifier = Modifier.size(FeedsDock.iconSize))
        if (selected) Text(mode.title, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Color.White, maxLines = 1)
    }
}

/** iOS: `reelsCriterionChipsRow` — active performer / studio / tags, tap removes. */
@Composable
fun FeedsCriterionChips(
    performer: IdName?,
    studio: IdName?,
    tags: List<IdName>,
    onClearPerformer: () -> Unit,
    onClearStudio: () -> Unit,
    onRemoveTag: (IdName) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Same metrics as the tag chips: 32 dp chips in a 40 dp touch row, 8 dp apart.
    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalMinimumInteractiveComponentSize provides TagChips.rowHeight) {
        Row(
            modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                .padding(horizontal = FeedsDock.edgePadding, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(TagChips.spacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            performer?.let { CriterionChip(it.name ?: "") { onClearPerformer() } }
            studio?.let { CriterionChip(it.name ?: "") { onClearStudio() } }
            tags.forEach { t -> CriterionChip("#${t.name}") { onRemoveTag(t) } }
        }
    }
}

/** Active criterion as a Material `InputChip` (tap removes), styled like the tag chips over media. */
@Composable
private fun CriterionChip(label: String, onClick: () -> Unit) {
    androidx.compose.material3.InputChip(
        selected = false,
        onClick = onClick,
        label = { Text(label, style = androidx.compose.material3.MaterialTheme.typography.labelLarge, maxLines = 1) },
        trailingIcon = { Icon(SF.xmark, "Remove", Modifier.size(androidx.compose.material3.InputChipDefaults.IconSize)) },
        colors = androidx.compose.material3.InputChipDefaults.inputChipColors(
            containerColor = Color.Black.copy(alpha = 0.45f),
            labelColor = Color.White,
            trailingIconColor = Color.White,
        ),
        border = androidx.compose.material3.InputChipDefaults.inputChipBorder(
            enabled = true, selected = false, borderColor = Color.White.copy(alpha = 0.25f),
        ),
    )
}

/** iOS: `ChromePillIconButton` (48 pt glass circle). */
@Composable
fun ChromePillIconButton(icon: ImageVector, description: String, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        Modifier.size(FeedsDock.stackedButtonSize).stashyGlass(CircleShape)
            .let { if (enabled) it.noIndicationClick(onClick) else it },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, description, tint = if (enabled) FeedsDock.hashtagForeground else Color.White.copy(alpha = 0.35f), modifier = Modifier.size(FeedsDock.iconSize))
    }
}

/** iOS: `reelsRateChrome` — O-Counter (tap +1, long press menu) and Rating (menu). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FeedsRateChrome(item: FeedItem, onOCounter: (FeedsRepository.OMutation) -> Unit, onRating: (Int?) -> Unit) {
    val oCount = item.oCounter ?: 0
    val stars = ((item.rating100 ?: 0) / 20.0).roundToInt().coerceIn(0, 5)
    var oMenu by remember { mutableStateOf(false) }
    var ratingMenu by remember { mutableStateOf(false) }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box {
            StackedPill(
                icon = oCounterIcon(Appearance.oCounterIcon, filled = oCount > 0),
                value = "$oCount",
                active = oCount > 0,
                modifier = Modifier.combinedClickable(
                    interactionSource = remember { MutableInteractionSource() }, indication = null,
                    onClick = { onOCounter(FeedsRepository.OMutation.Increment) },
                    onLongClick = { if (oCount > 0) oMenu = true },
                ),
            )
            // iOS `oCounterRemovalMenu`.
            DropdownMenu(oMenu, onDismissRequest = { oMenu = false }) {
                DropdownMenuItem(text = { Text("Remove one") }, onClick = { oMenu = false; onOCounter(FeedsRepository.OMutation.Decrement) })
                DropdownMenuItem(text = { Text("Reset") }, onClick = { oMenu = false; onOCounter(FeedsRepository.OMutation.Reset) })
            }
        }
        Box {
            StackedPill(SF.starFill, "$stars", stars > 0, Modifier.noIndicationClick { ratingMenu = true })
            DropdownMenu(ratingMenu, onDismissRequest = { ratingMenu = false }) {
                DropdownMenuItem(
                    text = { Text("Clear Rating") },
                    trailingIcon = { if (stars == 0) Icon(SF.checkmark, null) },
                    onClick = { ratingMenu = false; onRating(0) },
                )
                HorizontalDivider()
                for (s in 1..5) DropdownMenuItem(
                    text = { Text("★".repeat(s)) },
                    trailingIcon = { if (stars == s) Icon(SF.checkmark, null) },
                    onClick = { ratingMenu = false; onRating(s * 20) },
                )
            }
        }
    }
}

@Composable
private fun StackedPill(icon: ImageVector, value: String, active: Boolean, modifier: Modifier = Modifier) {
    Column(
        Modifier.size(FeedsDock.stackedButtonSize).stashyGlass(CircleShape).then(modifier),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, tint = Color.White.copy(alpha = if (active) 1f else FeedsDock.inactiveIconOpacity), modifier = Modifier.size(FeedsDock.iconSize))
        Text(value, style = IosTypography.caption2.copy(fontWeight = FontWeight.SemiBold), color = Color.White.copy(alpha = FeedsDock.inactiveIconOpacity))
    }
}

/**
 * iOS: `reelsInfoOverlay` — avatar · performer / title on the leading side, the control stack
 * (O-Counter, Rating, Delete, Mute, Play) trailing, hashtags in their own row below.
 */
@Composable
fun FeedsInfoOverlay(
    item: FeedItem,
    mode: ReelsModeType,
    isMuted: Boolean,
    isPlaying: Boolean,
    showsDelete: Boolean,
    onPerformerFilter: (FeedPerformer) -> Unit,
    onPerformerOpen: (FeedPerformer) -> Unit,
    onTitle: () -> Unit,
    onTag: (IdName) -> Unit,
    onAddTags: () -> Unit,
    onRemoveTag: (IdName) -> Unit,
    onOCounter: (FeedsRepository.OMutation) -> Unit,
    onRating: (Int?) -> Unit,
    onDelete: () -> Unit,
    onToggleMute: () -> Unit,
    onTogglePlay: () -> Unit,
    pausesAdvance: Boolean,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = FeedsDock.edgePadding), verticalAlignment = Alignment.Bottom) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                item.performers.firstOrNull()?.let { p -> PerformerThumbnail(p) { onPerformerOpen(p) } }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    item.performers.firstOrNull()?.let { p ->
                        Text(
                            p.name, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                            overflow = TextOverflow.Ellipsis, modifier = Modifier.noIndicationClick { onPerformerFilter(p) },
                        )
                    }
                    item.title?.takeIf { it.isNotEmpty() }?.let { title ->
                        Text(
                            title, color = Color.White.copy(alpha = 0.85f), fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = if (item.titleLinkScene != null) Modifier.noIndicationClick(onTitle) else Modifier,
                        )
                    }
                }
            }
            Spacer(Modifier.width(8.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (mode != ReelsModeType.Pics) FeedsRateChrome(item, onOCounter, onRating)
                if (showsDelete && item.supportsDelete) ChromePillIconButton(SF.trash, "Delete", onClick = onDelete)
                ChromePillIconButton(if (isMuted) SF.speakerSlashFill else SF.speakerWave2Fill, if (isMuted) "Unmute" else "Mute", enabled = item.isVideo, onClick = onToggleMute)
                ChromePillIconButton(if (isPlaying) SF.pauseFill else SF.playFill, if (isPlaying) "Pause" else "Play", enabled = item.isVideo || pausesAdvance, onClick = onTogglePlay)
            }
        }
        // Hashtags on their own full-width row (iOS: top 8): the shared Material [TagChipRow] —
        // pinned "Add tag" (edit mode, opens `AddTagsSheet`), scrolling `#tag` chips (tap toggles
        // the tag filter, long press → "Remove tag" in edit mode) and the Tag Suggestion chips
        // (stashy+) inline, so the row also exists for an untagged item. The 40 dp slot is kept
        // even without a row, so the overlay does not jump between clips.
        val showsRow = showsTagRow(item.tags)
        Box(Modifier.padding(top = 8.dp - TagChips.touchInset).fillMaxWidth().height(TagChips.rowHeight)) {
            if (showsRow) {
                TagChipRow(
                    itemId = item.id,
                    tags = item.tags,
                    modifier = Modifier.padding(horizontal = FeedsDock.edgePadding),
                    onAddTag = onAddTags,
                    onTagClick = onTag,
                    onRemoveTag = onRemoveTag,
                    canRemove = { it.id != item.primaryTagId },
                ) {
                    // iOS: `AITagSuggestionBar(target: item.aiTagTarget)` inline after the tags;
                    // the row follows through the `TagsUpdated` patch of [FeedsModel].
                    AITagSuggestionBar(item.aiTagTarget) { }
                }
            }
        }
    }
}

@Composable
private fun PerformerThumbnail(p: FeedPerformer, onClick: () -> Unit) {
    val size = FeedsDock.circleSize
    Box(
        Modifier.size(size).clip(CircleShape).background(Appearance.tint.copy(alpha = 0.2f))
            .border(2.dp, Appearance.tint, CircleShape).noIndicationClick(onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(SF.personFill, null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(18.dp))
        p.thumbnailURL?.let {
            // Head-and-shoulders shots lose the face to a centred crop → top alignment.
            AsyncImage(it, p.name, contentScale = ContentScale.Crop, alignment = Alignment.TopCenter, modifier = Modifier.size(size).clip(CircleShape))
        }
    }
}

/**
 * iOS: `IsolatedScrubberBar` — the shared `AetherTimeBar` (44 pt glass capsule: elapsed · track ·
 * remaining) with 16 pt sides and 8 pt above / below. [placeholderURL] stands in for the iOS
 * scrub-preview still (Android decodes no frames here; the row's poster is shown instead).
 */
@Composable
fun FeedsScrubber(time: Double, duration: Double, placeholderURL: String?, onScrub: (Double) -> Unit, onScrubEnd: (Double) -> Unit) {
    var scrubbing by remember { mutableStateOf(false) }
    de.letzgo.stashy.ui.player.TimeBar(
        currentTime = time,
        duration = duration,
        isScrubbing = scrubbing,
        previewImage = null,
        previewPlaceholderURL = placeholderURL,
        markers = emptyList(),
        modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 8.dp),
        onScrubChanged = { s -> scrubbing = true; onScrub(s) },
        onScrubEnded = { s -> scrubbing = false; onScrubEnd(s) },
    )
}

/** `m:ss` / `h:mm:ss`. */
fun formatTime(seconds: Double): String {
    val s = seconds.coerceAtLeast(0.0).toInt()
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
}

/** Click without ripple (iOS `.buttonStyle(.plain)`). */
fun Modifier.noIndicationClick(onClick: () -> Unit): Modifier = composed {
    clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onClick)
}
