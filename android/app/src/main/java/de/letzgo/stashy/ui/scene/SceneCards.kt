package de.letzgo.stashy.ui.scene

import de.letzgo.stashy.ui.cappedFontScale
import de.letzgo.stashy.ui.scaledIconSize
import androidx.compose.foundation.layout.sizeIn
import de.letzgo.stashy.ui.uniqueItems
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import de.letzgo.stashy.ui.detail.DirectorDetailScreen
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneGalleryStub
import de.letzgo.stashy.data.SceneGroupEntry
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.OverflowItem
import de.letzgo.stashy.ui.SF
import androidx.compose.material3.DropdownMenu
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.player.PlaybackFormat
import de.letzgo.stashy.ui.player.PlayerIcons
import java.time.LocalDate
import java.time.Period

internal fun Modifier.plainClick(onClick: () -> Unit) = clickable(interactionSource = null, indication = null, onClick = onClick)

/** iOS: `ScenePerformersCard.age(for:)` — age at the scene date. */
internal fun ageAt(birthdate: String?, sceneDate: String?): Int? {
    if (birthdate.isNullOrEmpty() || sceneDate.isNullOrEmpty()) return null
    return runCatching { Period.between(LocalDate.parse(birthdate.take(10)), LocalDate.parse(sceneDate.take(10))).years }.getOrNull()
}

/**
 * Performers & Studio — one horizontal row that always starts with the studio, then the performers
 * (round portraits with age badge and name pill), then the director. Shared by scene detail and the
 * opened gallery ([de.letzgo.stashy.ui.detail.GalleryDetailScreen]); `date` is then the gallery date.
 * Hidden when there is nothing to show, except in edit mode, where the pencil opens a menu
 * ("Edit Studio" / "Edit Performers") leading to the existing picker sheets.
 */
@Composable
fun ScenePerformersStudioCard(
    date: String?,
    studio: Studio?,
    performers: List<Performer>,
    director: String?,
    onEditStudio: () -> Unit,
    onEditPerformers: () -> Unit,
) {
    val edit = Appearance.isEditModeEnabled
    val isEmpty = studio == null && performers.isEmpty() && director == null
    if (isEmpty && !edit) return
    val tint = Appearance.tint
    val p = Theme.palette
    SceneCardContainer(Modifier.fillMaxWidth()) {
        SceneCardHeader("Performers & Studio", onEdit = null, trailing = if (edit) { { PerformersStudioEditMenu(onEditStudio, onEditPerformers) } } else null)
        if (isEmpty) {
            Box(Modifier.padding(top = 8.dp)) { SceneCardEmpty("No performers or studio assigned") }
        } else {
            LazyRow(Modifier.padding(top = 8.dp, bottom = 12.dp), contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                if (studio != null) item("studio-${studio.id}") { StudioItem(studio) }
                uniqueItems(performers.sortedBy { it.name }, { it.id }) { performer ->
                    ScenePerformerTile(performer, ageAt(performer.birthdate, date)?.toString()) { DetailLinks.performer(performer) }
                }
                items(DirectorDetailScreen.directorNames(director), key = { "director:$it" }) { director ->
                    Box(Modifier.padding(bottom = 8.dp).plainClick { DetailLinks.director(director) }, contentAlignment = Alignment.BottomCenter) {
                        Box(Modifier.size(88.dp).clip(CircleShape).background(tint).padding(4.dp).clip(CircleShape).background(p.secondaryBackground), contentAlignment = Alignment.Center) {
                            Icon(PlayerIcons.director, null, tint = p.pillAccent, modifier = Modifier.size(30.dp))
                        }
                        NamePill(director, Modifier.offset(y = 8.dp))
                    }
                }
            }
        }
    }
}

/**
 * Performer entry of [ScenePerformersStudioCard]: 88 dp round portrait with the tint ring, optional
 * [badge] top-right (the age at the scene date), name pill overlapping the bottom.
 */
@Composable
internal fun ScenePerformerTile(performer: Performer, badge: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val tint = Appearance.tint
    val p = Theme.palette
    Box(modifier.padding(bottom = 8.dp).plainClick(onClick), contentAlignment = Alignment.BottomCenter) {
        Box(Modifier.size(88.dp).clip(CircleShape).background(tint).padding(4.dp).clip(CircleShape)) {
            val url = performer.imageURL
            if (url != null) AsyncImage(url, performer.name, Modifier.fillMaxSize().background(Color.Gray.copy(alpha = 0.2f)), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
            else Icon(PlayerIcons.person, null, tint = tint.copy(alpha = 0.4f), modifier = Modifier.fillMaxSize())
        }
        badge?.let { text ->
            Box(
                // Min 22 dp circle that widens into a capsule when the font scale grows the number.
                Modifier.align(Alignment.TopEnd).sizeIn(minWidth = 22.dp, minHeight = 22.dp).clip(RoundedCornerShape(50)).background(tint)
                    .border(1.5.dp, p.secondaryBackground, RoundedCornerShape(50)).padding(horizontal = 4.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center,
            ) { Text(text, style = pillTextStyle, color = Color.White, maxLines = 1) }
        }
        NamePill(performer.name, Modifier.offset(y = 8.dp))
    }
}

/**
 * Studio entry of [ScenePerformersStudioCard]: an 88 dp rounded tile (same size and tint ring as the
 * performer portraits; a tile rather than a circle so wide logos aren't cropped) with the logo fitted
 * on the neutral studio-header background, name pill below.
 */
@Composable
private fun StudioItem(studio: Studio) {
    val p = Theme.palette
    val outer = RoundedCornerShape(Tokens.Radius.card + 4.dp)
    val inner = RoundedCornerShape(Tokens.Radius.card)
    var failed by remember(studio.id, studio.imagePath) { mutableStateOf(!studio.hasImage) }
    Box(Modifier.padding(bottom = 8.dp).plainClick { DetailLinks.studio(studio) }, contentAlignment = Alignment.BottomCenter) {
        Box(Modifier.size(88.dp).clip(outer).background(Appearance.tint).padding(4.dp).clip(inner).background(p.studioHeader).padding(8.dp), contentAlignment = Alignment.Center) {
            if (failed) Icon(SF.building2, null, tint = p.secondaryText, modifier = Modifier.size(34.dp))
            else AsyncImage(studio.imageURL, studio.name, Modifier.fillMaxSize(), contentScale = ContentScale.Fit, onError = { failed = true })
        }
        NamePill(studio.name, Modifier.offset(y = 8.dp))
    }
}

/** Edit-mode pencil of [ScenePerformersStudioCard] with its "Edit Studio" / "Edit Performers" menu. */
@Composable
private fun PerformersStudioEditMenu(onEditStudio: () -> Unit, onEditPerformers: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        EditCircleButton { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = Theme.palette.secondaryBackground) {
            OverflowItem("Edit Studio", SF.building2, { open = false }, onClick = onEditStudio)
            OverflowItem("Edit Performers", PlayerIcons.person, { open = false }, onClick = onEditPerformers)
        }
    }
}

/** iOS: `SceneGroupsCard` — 70×105 posters with name pills, in a horizontal row. */
@Composable
fun SceneGroupsCard(groups: List<SceneGroupEntry>, onEdit: () -> Unit, modifier: Modifier = Modifier) {
    val tint = Appearance.tint
    SceneCardContainer(modifier.fillMaxWidth()) {
        SceneCardHeader("Groups", onEdit)
        if (groups.isEmpty()) Box(Modifier.padding(top = 8.dp)) { SceneCardEmpty("No groups assigned") }
        else LazyRow(Modifier.padding(top = 8.dp, bottom = 12.dp), contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            uniqueItems(groups.sortedBy { it.group.name }, { it.group.id }) { entry ->
                Box(Modifier.padding(bottom = 8.dp).plainClick { DetailLinks.group(entry.group) }, contentAlignment = Alignment.BottomCenter) {
                    Box(Modifier.size(70.dp, 105.dp).clip(RoundedCornerShape(Tokens.Radius.card)).background(tint), contentAlignment = Alignment.Center) {
                        val url = Net.signed(entry.group.frontImagePath)
                        if (url != null) AsyncImage(url, entry.group.name, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        else Icon(PlayerIcons.group, null, tint = tint.copy(alpha = 0.4f), modifier = Modifier.padding(16.dp).fillMaxSize())
                    }
                    NamePill(entry.group.name, Modifier.offset(y = 8.dp))
                }
            }
        }
    }
}

/** iOS: `SceneTagsCard` — tag chips, collapsed to 68 pt with a chevron when they overflow. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SceneTagsCard(tags: List<Tag>?, expanded: Boolean, onToggleExpanded: () -> Unit, onEdit: () -> Unit, modifier: Modifier = Modifier) {
    val p = Theme.palette
    val density = LocalDensity.current
    var totalHeight by remember { mutableIntStateOf(0) }
    // Collapsed height ≈ 1½ chip rows; grows with the font scale like the chips themselves.
    val collapsed = 68.dp * cappedFontScale()
    SceneCardContainer(modifier.fillMaxWidth()) {
        SceneCardHeader("Tags", onEdit)
        if (tags.isNullOrEmpty()) Box(Modifier.padding(top = 8.dp)) { SceneCardEmpty("No tags assigned") }
        else Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 12.dp), horizontalAlignment = Alignment.End) {
            Box(Modifier.fillMaxWidth().then(if (expanded) Modifier else Modifier.heightIn(max = collapsed)).clipToBounds()) {
                FlowRow(
                    Modifier.fillMaxWidth().wrapContentHeight(unbounded = true, align = Alignment.Top).onSizeChanged { totalHeight = it.height },
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    tags.forEach { tag ->
                        Row(
                            Modifier.clip(RoundedCornerShape(50)).background(p.pillAccent.copy(alpha = 0.1f)).plainClick { DetailLinks.tag(tag) }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(PlayerIcons.tag, null, tint = p.pillAccent, modifier = Modifier.size(scaledIconSize(10.dp)))
                            Text(tag.name, style = pillTextStyle, color = p.pillAccent)
                        }
                    }
                }
            }
            if (with(density) { totalHeight.toDp() } > collapsed) ExpandChevron(expanded, Modifier.padding(top = 4.dp), onToggleExpanded)
        }
    }
}

/** iOS: `SceneGalleriesCard` — one strip per gallery: link tile with the image count, then its images. */
@Composable
fun SceneGalleriesCard(galleries: List<SceneGalleryStub>?, modifier: Modifier = Modifier, onEdit: () -> Unit) {
    SceneCardContainer(modifier.fillMaxWidth()) {
        SceneCardHeader("Galleries", onEdit)
        if (galleries.isNullOrEmpty()) Box(Modifier.padding(top = 8.dp)) { SceneCardEmpty("No galleries assigned") }
        else Column(Modifier.padding(top = 8.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            galleries.forEach { GalleryImageStrip(it) }
        }
    }
}

@Composable
private fun GalleryImageStrip(gallery: SceneGalleryStub) {
    val tint = Appearance.tint
    val thumb = 88.dp
    val shape = RoundedCornerShape(Tokens.Radius.card * 0.75f)
    var images by remember(gallery.id) { mutableStateOf<List<StashImage>>(emptyList()) }
    var loading by remember(gallery.id) { mutableStateOf(true) }
    LaunchedEffect(gallery.id) {
        images = runCatching { SceneEditing.galleryPreviewImages(gallery.id, 40) }.getOrDefault(emptyList())
        loading = false
    }
    LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        item("link") {
            Column(
                Modifier.size(thumb).clip(shape).background(tint.copy(alpha = 0.1f)).border(1.dp, tint.copy(alpha = 0.35f), shape).plainClick { DetailLinks.gallery(gallery) },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            ) {
                Icon(PlayerIcons.gallery, null, tint = tint, modifier = Modifier.size(scaledIconSize(22.dp, maxScale = 1.4f)))
                Text(gallery.imageCount?.toString() ?: "—", style = IosTypography.caption.copy(fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace), color = tint)
            }
        }
        uniqueItems(images, { it.id }) { image ->
            Box(Modifier.size(thumb).clip(shape).background(Color.Gray.copy(alpha = 0.2f)).plainClick { DetailLinks.image(images, image.id) }) {
                AsyncImage(image.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
        }
        if (loading && images.isEmpty()) item("loading") {
            Box(Modifier.size(thumb), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = tint) }
        }
    }
}

/**
 * iOS: `SceneHeatmapCard` ("Interactive") — Stash's funscript heatmap with a draggable playhead
 * (seeks throttled to 150 ms while dragging, committed on release). Device sync buttons
 * (TheHandy, Intiface, Love Spouse) are not ported.
 */
@Composable
fun SceneHeatmapCard(heatmapURL: String?, duration: Double, currentTime: Double, onSeek: (Double) -> Unit, onSeekCommit: (Double) -> Unit, onScrubStateChange: (Boolean) -> Unit) {
    val tint = Appearance.tint
    val p = Theme.palette
    val heatmapHeight = 80.dp
    var dragging by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(0f) }
    val progress = if (dragging) draft else if (duration > 0) (currentTime.coerceIn(0.0, duration) / duration).toFloat() else 0f
    SceneCardContainer(Modifier.fillMaxWidth()) {
        SceneCardHeader("Interactive", null, trailing = { Icon(PlayerIcons.waveform, null, tint = p.pillAccent, modifier = Modifier.size(18.dp)) })
        Box(
            // No fixed height: the time-label row below the heatmap sizes the box at any font scale.
            Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 8.dp)
                .pointerInput(duration) {
                    var lastSent = 0L
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val w = size.width.toFloat().coerceAtLeast(1f)
                        fun frac(x: Float) = (x / w).coerceIn(0f, 1f)
                        dragging = true; lastSent = 0L; onScrubStateChange(true)
                        draft = frac(down.position.x)
                        var x = down.position.x
                        while (true) {
                            val now = System.currentTimeMillis()
                            if (now - lastSent >= 150) { lastSent = now; onSeek(duration * frac(x)) }
                            val e = awaitPointerEvent()
                            val c = e.changes.firstOrNull { it.id == down.id } ?: break
                            if (!c.pressed) break
                            x = c.position.x; draft = frac(x); c.consume()
                        }
                        draft = frac(x)
                        dragging = false
                        onSeekCommit(duration * frac(x))
                        onScrubStateChange(false)
                    }
                },
        ) {
            Box(Modifier.fillMaxWidth().height(heatmapHeight).background(p.secondaryText.copy(alpha = 0.12f)))
            // Grid lines + time labels at 0 / 25 / 50 / 75 / 100 %.
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
                val w = maxWidth
                listOf(0f, 0.25f, 0.5f, 0.75f, 1f).forEach { pos ->
                    Box(Modifier.offset(x = w * pos).size(1.dp, heatmapHeight).background(Color.Gray.copy(alpha = 0.2f)))
                }
                if (heatmapURL != null) {
                    AsyncImage(heatmapURL, null, Modifier.fillMaxWidth().height(heatmapHeight).alpha(0.15f), contentScale = ContentScale.FillBounds)
                    AsyncImage(
                        heatmapURL, null,
                        Modifier.fillMaxWidth().height(heatmapHeight).drawWithContent {
                            clipRect(right = size.width * progress) { this@drawWithContent.drawContent() }
                        },
                        contentScale = ContentScale.FillBounds,
                    )
                } else Box(Modifier.fillMaxWidth().height(heatmapHeight).background(Color.Gray.copy(alpha = 0.1f)), contentAlignment = Alignment.Center) {
                    Text("No Heatmap", style = IosTypography.caption2, color = p.secondaryText)
                }
                // Playhead.
                Box(Modifier.offset(x = w * progress - 1.dp, y = (-2).dp).size(2.dp, heatmapHeight + 4.dp).background(tint))
                Box(Modifier.offset(x = w * progress - 5.dp, y = (-7).dp).size(10.dp).clip(CircleShape).background(tint))
            }
            // Time labels at 0 / 25 / 50 / 75 / 100 % (equal-width monospace, SpaceBetween keeps
            // the outer ones inside the card even when the font scale widens them).
            Row(Modifier.fillMaxWidth().padding(top = heatmapHeight + 10.dp, bottom = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                listOf(0f, 0.25f, 0.5f, 0.75f, 1f).forEach { pos ->
                    Text(
                        PlaybackFormat.time(duration * pos),
                        style = IosTypography.caption2.copy(fontSize = 9.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace), color = p.text.copy(alpha = 0.8f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}


/**
 * iOS: `SceneSimilarScenesCard` (stashy+) — scenes from the library that resemble the one on
 * screen ([de.letzgo.stashy.data.tools.SimilarScenes]). Hidden while the finder is inactive
 * (off or locked) and when nothing similar was found. Cards are the dashboard's small
 * `HomeSceneCardView` (222 × 125); like iOS the card has no shadow.
 */
@Composable
fun SceneSimilarScenesCard(scenes: List<de.letzgo.stashy.data.Scene>, isLoading: Boolean) {
    if (!de.letzgo.stashy.data.tools.SimilarScenes.isActive) return
    if (scenes.isEmpty() && !isLoading) return
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(Theme.palette.secondaryBackground).padding(bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SceneCardHeader("Similar Scenes", null, trailing = {
            if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), color = Theme.palette.secondaryText, strokeWidth = 2.dp)
        })
        if (scenes.isNotEmpty()) {
            LazyRow(contentPadding = PaddingValues(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                uniqueItems(scenes, { it.id }) { s ->
                    de.letzgo.stashy.ui.home.DashboardSceneCard(
                        s, isLarge = false, width = 125.dp * 16 / 9, height = 125.dp,
                        // Material card click (ripple) like every other card (README "Cards").
                        onClick = { de.letzgo.stashy.ui.Nav.push(SceneDetailScreen(s.id, s)) },
                    )
                }
            }
        }
    }
}
