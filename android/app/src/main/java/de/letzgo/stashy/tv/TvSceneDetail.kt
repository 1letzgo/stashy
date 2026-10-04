package de.letzgo.stashy.tv

import android.view.KeyEvent as AndroidKeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.ScenesRepository
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import kotlinx.coroutines.launch

/**
 * iOS: `TVSceneDetailView` — full-screen artwork with the title block, metadata line, the
 * Play/Resume · Restart | O-count · Rating buttons, then the Markers, Tags, Performers and
 * Studio rows. Play opens [TvScenePlayerRoute]; coming back refreshes silently.
 */
class TvSceneDetailRoute(private val sceneId: String, initial: Scene? = null) : TvDetailRoute() {
    override val key = "scene.$sceneId.${System.nanoTime()}"
    private var scene by mutableStateOf<Scene?>(null)
    private var isLoading by mutableStateOf(true)
    private var errorMessage by mutableStateOf<String?>(null)
    private val playback = TvPlaybackModel()

    init { load() }

    private fun load() {
        if (ServerConfigManager.activeConfig?.hasValidConfig != true) { isLoading = false; return }
        val initialLoad = scene == null
        if (initialLoad) isLoading = true
        scope.launch {
            val result = runCatching { ScenesRepository.scene(sceneId) }
            result.getOrNull()?.let { scene = it }
            errorMessage = result.exceptionOrNull()?.message
            isLoading = false
        }
    }

    /** Player dismissed: refresh resume time and play count without replacing the page. */
    override fun onReturn() = load()

    override fun onRemoved() {
        playback.clear()
        super.onRemoved()
    }

    private fun startPlayback(at: Double? = null) {
        val s = scene ?: return
        if (s.streamURL == null) return
        playback.setup(s, at ?: s.resumeTime ?: 0.0)
        TvNav.push(TvScenePlayerRoute(playback) { scene })
    }

    private fun addO() {
        val s = scene ?: return
        scope.launch {
            val count = runCatching { SceneEditing.mutateOCounter(s.id, OCounterMutation.Increment) }.getOrNull() ?: return@launch
            scene = scene?.copy(oCounter = count)
            SceneEvents.post(SceneEvent.OCounterUpdated(s.id, count))
        }
    }

    private fun rate(stars: Int) {
        val s = scene ?: return
        val value = if (stars == 0) null else stars * 20
        scope.launch {
            if (runCatching { SceneEditing.updateRating(s.id, value) }.isSuccess) {
                val rated = (scene ?: s).copy(rating100 = value)
                scene = rated
                SceneEvents.post(SceneEvent.Updated(rated))
            }
        }
    }

    @Composable
    override fun Content() {
        val playFocus = remember { FocusRequester() }
        val anchor = remember { FocusRequester() }
        Box(
            Modifier.fillMaxSize().background(TvColors.background).onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.nativeKeyEvent.repeatCount == 0 &&
                    (e.nativeKeyEvent.keyCode == AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || e.nativeKeyEvent.keyCode == AndroidKeyEvent.KEYCODE_MEDIA_PLAY)
                ) { startPlayback(); true } else false
            },
        ) {
            val s = scene
            when {
                ServerConfigManager.activeConfig?.hasValidConfig != true ->
                    TvConnectionError(subtitle = "Add a server in Settings.", focus = anchor) { load() }
                isLoading && s == null -> Box(Modifier.fillMaxSize().focusRequester(anchor).focusable(), contentAlignment = Alignment.Center) { TvSpinner(pt(72)) }
                s != null -> {
                    HeroBackground(s)
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(start = pt(60), end = pt(60), top = pt(120), bottom = pt(100)),
                        verticalArrangement = Arrangement.spacedBy(pt(50)),
                    ) {
                        item(key = "hero") { HeroContent(s, playFocus) }
                        s.sceneMarkers?.takeIf { it.isNotEmpty() }?.let { markers -> item(key = "markers") { MarkersRow(markers) } }
                        s.tags?.takeIf { it.isNotEmpty() }?.let { tags -> item(key = "tags") { TagsRow(tags) } }
                        if (s.performers.isNotEmpty()) item(key = "performers") { PerformersRow(s.performers) }
                        s.studio?.let { studio -> item(key = "studio") { StudioRow(studio) } }
                    }
                }
                errorMessage != null -> TvConnectionError(subtitle = errorMessage, focus = anchor) { load() }
                else -> Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(pt(24))) {
                    Icon(TvIcons.warning, null, Modifier.size(pt(64)), tint = TvColors.secondary)
                    Text("Failed to load scene details", style = TvType.title2.copy(fontWeight = FontWeight.Normal), color = TvColors.secondary)
                    TvButton({ load() }, Modifier.focusRequester(anchor)) { Text("Retry", style = TvType.title3) }
                }
            }
        }
        TvInitialFocus(focus, if (scene != null) playFocus else anchor, enabled = !isLoading || scene != null, name = if (scene != null) "scene.play" else "scene.loading")
    }

    @Composable
    private fun HeroBackground(s: Scene) {
        Box(Modifier.fillMaxSize()) {
            AsyncImage(s.thumbnailURL, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.1f)))
            Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(listOf(TvColors.background.copy(alpha = 0.9f), TvColors.background.copy(alpha = 0.5f), Color.Transparent, Color.Transparent))))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 0.75f to TvColors.background.copy(alpha = 0.4f), 1f to TvColors.background.copy(alpha = 0.9f))))
        }
    }

    @Composable
    private fun HeroContent(s: Scene, playFocus: FocusRequester) {
        var ratingOpen by remember { mutableStateOf(false) }
        val hasStream = s.streamURL != null
        val hasProgress = (s.resumeTime ?: 0.0) > 0
        Column(verticalArrangement = Arrangement.spacedBy(pt(16))) {
            s.studio?.let { Text(it.name.uppercase(), style = TvType.caption.copy(fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp), color = Color.White.copy(alpha = 0.8f)) }
            Text(
                s.displayTitle, Modifier.fillMaxWidth(),
                style = TvType.largeTitle.copy(fontSize = 40.sp, shadow = Shadow(Color.Black.copy(alpha = 0.6f), blurRadius = 20f)),
                color = Color.White, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            s.details?.takeIf { it.isNotEmpty() }?.let {
                Text(it, Modifier.widthIn(max = pt(1000)), style = TvType.title3, color = Color.White.copy(alpha = 0.6f), maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
            Row(Modifier.padding(top = pt(8)), horizontalArrangement = Arrangement.spacedBy(pt(24)), verticalAlignment = Alignment.CenterVertically) {
                val meta = TvType.headline
                val tint = Color.White.copy(alpha = 0.9f)
                s.sceneDuration?.takeIf { it > 0 }?.let { MetaItem(TvIcons.clock, TvFormat.time(it)) }
                TvFormat.resolution(s.files?.firstOrNull()?.height)?.let { MetaItem(TvIcons.tv, it) }
                s.rating100?.takeIf { it > 0 }?.let { r ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(8))) {
                        Icon(TvIcons.star, null, Modifier.size(pt(30)), tint = TvColors.star)
                        Text(TvFormat.ratingValue(r), style = meta, color = tint)
                    }
                }
                s.oCounter?.takeIf { it > 0 }?.let { MetaItem(TvIcons.heartCircle, "$it") }
                TvFormat.progress(s.resumeTime, s.sceneDuration)?.let { p ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(12))) {
                        Icon(TvIcons.play, null, Modifier.size(pt(22)), tint = tint)
                        Text("${(p * 100).toInt()}%", style = meta, color = tint)
                        Box(Modifier.width(pt(200)).height(pt(4)).clip(CircleShape).background(Color.White.copy(alpha = 0.3f))) {
                            Box(Modifier.fillMaxHeight().fillMaxWidth(p).background(TvColors.tint))
                        }
                    }
                }
            }
            Row(Modifier.padding(top = pt(16)), horizontalArrangement = Arrangement.spacedBy(pt(20)), verticalAlignment = Alignment.CenterVertically) {
                HeroButton(
                    if (hasStream) TvIcons.play else TvIcons.noStream,
                    if (hasStream) (if (hasProgress) "Resume" else "Play") else "No Stream",
                    Modifier.focusRequester(playFocus).tvFocusMemory(focus, "play"), enabled = hasStream,
                ) { startPlayback() }
                if (hasProgress) HeroButton(TvIcons.restart, "Restart", Modifier.tvFocusMemory(focus, "restart")) { startPlayback(0.0) }
                Box(Modifier.padding(horizontal = pt(8)).width(pt(3)).height(pt(72)).background(Color.White.copy(alpha = 0.28f)))
                HeroButton(TvIcons.heartCircle, "${s.oCounter ?: 0}", Modifier.tvFocusMemory(focus, "o")) { addO() }
                HeroButton(TvIcons.star, TvFormat.ratingLabel(s.rating100), Modifier.tvFocusMemory(focus, "rating")) { ratingOpen = true }
            }
        }
        if (ratingOpen) {
            TvOptionDialog(
                "Rating", (5 downTo 0).map { TvOption(it, if (it == 0) "No Rating" else "★".repeat(it)) }, TvFormat.stars(s.rating100),
                { rate(it) }, { ratingOpen = false },
            )
        }
    }

    @Composable
    private fun MetaItem(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(6))) {
            Icon(icon, null, Modifier.size(pt(30)), tint = Color.White.copy(alpha = 0.9f))
            Text(text, style = TvType.headline, color = Color.White.copy(alpha = 0.9f))
        }
    }

    @Composable
    private fun HeroButton(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
        TvButton(onClick, modifier.width(pt(250)).height(pt(72)), enabled = enabled, contentPadding = PaddingValues(horizontal = pt(16))) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(pt(12), Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, null, Modifier.size(pt(32)))
                Text(title, style = TvType.headline, maxLines = 1)
            }
        }
    }

    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    private fun MarkersRow(markers: List<SceneMarker>) {
        Column(verticalArrangement = Arrangement.spacedBy(pt(16))) {
            TvSectionHeading(TvIcons.bookmark, "Markers", markers.size)
            LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(24)), contentPadding = PaddingValues(horizontal = pt(20), vertical = pt(30))) {
                items(markers.sortedBy { it.seconds }, key = { it.id }) { marker ->
                    var focused by remember { mutableStateOf(false) }
                    Column(Modifier.width(pt(260))) {
                        TvCardButton({ startPlayback(marker.seconds) }, Modifier.onFocusChanged { focused = it.isFocused }.tvFocusMemory(focus, "m.${marker.id}")) {
                            Box(Modifier.width(pt(260)).height(pt(146)).clip(RoundedCornerShape(pt(10)))) {
                                TvImage(markerThumbnail(marker), Modifier.fillMaxSize(), TvIcons.bookmarkOutline)
                                TvFocusPreview(Net.signed(marker.preview), focused)
                                Text(
                                    TvFormat.time(marker.seconds),
                                    Modifier.align(Alignment.BottomEnd).padding(pt(8)).clip(RoundedCornerShape(pt(5))).background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = pt(7), vertical = pt(3)),
                                    style = TvType.caption2, color = Color.White,
                                )
                            }
                        }
                        Text(marker.title?.takeIf { it.isNotBlank() } ?: "Untitled Marker", Modifier.padding(top = pt(8)), style = TvType.callout.copy(fontWeight = FontWeight.Medium), color = Color.White.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }

    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    private fun TagsRow(tags: List<Tag>) {
        Column(verticalArrangement = Arrangement.spacedBy(pt(16))) {
            TvSectionHeading(TvIcons.tag, "Tags", tags.size)
            LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(20), vertical = pt(40))) {
                items(tags, key = { it.id }) { tag ->
                    TvButton({ TvNav.push(TvTagDetailRoute(tag.id, tag.name)) }, Modifier.tvFocusMemory(focus, "t.${tag.id}"), contentPadding = PaddingValues(horizontal = pt(24), vertical = pt(12))) {
                        Text(tag.name, style = TvType.headline, maxLines = 1)
                    }
                }
            }
        }
    }

    @OptIn(ExperimentalComposeUiApi::class)
    @Composable
    private fun PerformersRow(performers: List<Performer>) {
        Column(verticalArrangement = Arrangement.spacedBy(pt(16))) {
            TvSectionHeading(TvIcons.person2, "Performers", performers.size)
            LazyRow(Modifier.focusRestorer(), horizontalArrangement = Arrangement.spacedBy(pt(30)), contentPadding = PaddingValues(horizontal = pt(20), vertical = pt(30))) {
                items(performers, key = { it.id }) { p ->
                    TvCardButton({ TvNav.push(TvPerformerDetailRoute(p.id, p.name)) }, Modifier.tvFocusMemory(focus, "p.${p.id}")) {
                        Column(Modifier.width(pt(180))) {
                            TvImage(p.imageURL, Modifier.width(pt(180)).height(pt(270)).clip(RoundedCornerShape(pt(10))), TvIcons.person, iconSize = pt(32))
                            Text(p.name, Modifier.padding(top = pt(16)), style = TvType.headline, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun StudioRow(studio: Studio) {
        Column(verticalArrangement = Arrangement.spacedBy(pt(16))) {
            TvSectionHeading(TvIcons.building, "Studio")
            Box(Modifier.padding(horizontal = pt(20), vertical = pt(20))) {
                TvCardButton({ TvNav.push(TvStudioDetailRoute(studio.id, studio.name)) }, Modifier.tvFocusMemory(focus, "studio")) {
                    Column(Modifier.width(pt(320))) {
                        val logo = studio.imageURL?.takeIf { studio.hasImage }
                            ?: ServerConfigManager.activeConfig?.let { Net.signed("${it.baseURL}/studio/${studio.id}/image") }
                        TvImage(logo, Modifier.width(pt(320)).height(pt(180)).clip(RoundedCornerShape(pt(10))).background(TvColors.placeholder).padding(pt(25)), TvIcons.building, Color.Transparent, ContentScale.Fit, pt(40))
                        Text(studio.name, Modifier.padding(top = pt(16)), style = TvType.headline, color = Color.White, maxLines = 1)
                    }
                }
            }
        }
    }
}
