package de.letzgo.stashy.ui.scene

import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.GlassCapsule
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.cardShadow
import de.letzgo.stashy.ui.player.PlayerIcons
import de.letzgo.stashy.ui.player.PlayerMenuItem
import de.letzgo.stashy.ui.player.PlayerWindow
import de.letzgo.stashy.ui.player.ScenePlayerSurface
import de.letzgo.stashy.ui.player.VideoSurface
import de.letzgo.stashy.ui.stashyGlass
import kotlinx.coroutines.delay

/**
 * iOS: `SceneDetailView`. [preview] is the list item, shown while the full scene loads;
 * [autoPlay] starts (resuming) playback on open, like iOS `SceneDetailView(scene:autoPlay:)`.
 * The page model lives with the screen object, so a pushed page or another tab can come back
 * to it and resume playback where it left off.
 */
class SceneDetailScreen(val sceneId: String, val preview: Scene? = null, autoPlay: Boolean = false) : Screen {
    override val key = "scene-$sceneId"
    private val model = SceneDetailModel(preview ?: Scene(id = sceneId), autoPlay)
    override val hidesTabBar: Boolean get() = model.isFullscreen || PlayerWindow.isInPictureInPicture

    @Composable override fun Content() = SceneDetailContent(model)
}

private enum class EditSheet { Title, Performers, Studio, Groups, Tags, Galleries }

@Composable
private fun SceneDetailContent(model: SceneDetailModel) {
    val p = Theme.palette
    val scene = model.scene
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var sheet by remember { mutableStateOf<EditSheet?>(null) }
    PlayerWindow.ObservePictureInPicture()

    DisposableEffect(model) {
        model.onAppear()
        val observer = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_STOP) model.onStop() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); model.onDisappear() }
    }
    // iOS: `Timer.publish(every: 10)` → periodic activity sync.
    LaunchedEffect(model) { while (true) { delay(10_000); model.periodicSync() } }
    // PiP window closed (not expanded back): stop like iOS ending PiP.
    LaunchedEffect(PlayerWindow.isInPictureInPicture) {
        if (!PlayerWindow.isInPictureInPicture) {
            delay(400)
            if (!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) model.player?.pause()
        }
    }
    // Plugging headphones in turns the sound on, unplugging mutes again (iOS route change).
    RouteMuteFollower(model)

    // Fullscreen: immersive, landscape for landscape videos.
    LaunchedEffect(model.isFullscreen) {
        if (model.isFullscreen) {
            PlayerWindow.setImmersive(true)
            val size = model.player?.videoSize ?: scene.files?.firstOrNull()?.let { (it.width ?: 0) to (it.height ?: 0) }
            if (size != null && size.first > size.second) PlayerWindow.lockLandscape(true)
        } else {
            PlayerWindow.setImmersive(false)
            PlayerWindow.releaseOrientation()
        }
    }
    BackHandler(enabled = model.isFullscreen) { model.isFullscreen = false }

    val extraMenuItems: () -> List<PlayerMenuItem> = {
        buildList {
            add(PlayerMenuItem.Separator("extras.section.scene", "Scene"))
            add(PlayerMenuItem.Action("extras.sceneCover", "Use frame as scene cover", PlayerIcons.photo, isDisabled = model.isCapturing) { model.showReplaceCoverConfirm = true })
            add(PlayerMenuItem.Action("extras.tagImage", "Use frame as tag image", PlayerIcons.tag, isDisabled = model.isCapturing) { model.captureTagImage() })
            de.letzgo.stashy.ui.player.PlaybackFormat.resolutionLabel(model.scene.files?.firstOrNull()?.height)?.let {
                add(PlayerMenuItem.Separator("extras.section.info"))
                add(PlayerMenuItem.Info("extras.resolution", it, PlayerIcons.video))
            }
        }
    }

    // Picture in Picture: only the picture.
    val player = model.player
    if (PlayerWindow.isInPictureInPicture && player != null) {
        Box(Modifier.fillMaxSize().background(Color.Black)) { VideoSurface(player, Modifier.fillMaxSize()) }
        return
    }

    Box(Modifier.fillMaxSize().background(p.background)) {
        val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
        val pinned = model.isPlaybackStarted && player != null && !landscape
        Column(Modifier.fillMaxSize()) {
            SceneDetailNavBar(model)
            val playerCard: @Composable () -> Unit = {
                Column(Modifier.fillMaxWidth().cardShadow().clip(RoundedCornerShape(Tokens.Radius.card)).background(p.secondaryBackground)) {
                    SceneVideoPlayerCard(model, extraMenuItems)
                }
            }
            if (pinned) Box(Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp)) { playerCard() }
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, end = 16.dp, top = if (pinned) 12.dp else 16.dp, bottom = 16.dp + TabBarClearance),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (!pinned) playerCard()
                SceneCardContainer(Modifier.fillMaxWidth()) { SceneMetadataCard(model) { sheet = EditSheet.Title } }
                if (scene.interactive == true && scene.hasFunscript) {
                    SceneHeatmapCard(
                        scene.heatmapURL, scene.sceneDuration ?: 0.0, model.currentPlaybackTime,
                        onSeek = model::seekTo, onSeekCommit = model::commitScrub, onScrubStateChange = model::updateScrubbing,
                    )
                }
                SceneSimilarScenesCard()
                ScenePerformersCard(scene.date, scene.performers, scene.normalizedDirector) { sheet = EditSheet.Performers }
                if (landscape) {
                    // iOS landscape: two-column grid (Studio | Groups, Tags, Galleries full width, Delete).
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SceneStudioCard(scene.studio, { sheet = EditSheet.Studio }, Modifier.weight(1f))
                        SceneGroupsCard(scene.groups.orEmpty(), { sheet = EditSheet.Groups }, Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SceneTagsCard(scene.tags, model.isTagsExpanded, { model.isTagsExpanded = !model.isTagsExpanded }, { sheet = EditSheet.Tags }, Modifier.weight(1f))
                        Spacer(Modifier.weight(1f))
                    }
                    SceneGalleriesCard(scene.galleries) { sheet = EditSheet.Galleries }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        DeleteSceneButton(Modifier.weight(1f)) { model.showDeleteConfirmation = true }
                        Spacer(Modifier.weight(1f))
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SceneStudioCard(scene.studio, { sheet = EditSheet.Studio }, Modifier.weight(1f))
                        SceneGroupsCard(scene.groups.orEmpty(), { sheet = EditSheet.Groups }, Modifier.weight(1f))
                    }
                    SceneTagsCard(scene.tags, model.isTagsExpanded, { model.isTagsExpanded = !model.isTagsExpanded }, { sheet = EditSheet.Tags })
                    SceneGalleriesCard(scene.galleries) { sheet = EditSheet.Galleries }
                    DeleteSceneButton(Modifier.fillMaxWidth().padding(top = 10.dp)) { model.showDeleteConfirmation = true }
                }
            }
        }

        // iOS: `fullScreenCover` — the same player, full bleed.
        if (model.isFullscreen && player != null) {
            Box(Modifier.fillMaxSize().background(Color.Black)) {
                ScenePlayerSurface(
                    player = player,
                    posterURL = scene.thumbnailURL,
                    isMuted = model.isMuted,
                    onMutedChange = model::updateMuted,
                    onSeek = model::seekTo,
                    modifier = Modifier.fillMaxSize(),
                    onToggleFullscreen = { model.isFullscreen = false },
                    isFullscreen = true,
                    markers = scene.timeBarMarkers,
                    onAddMarker = model::beginAddMarker,
                    extraMenuItems = extraMenuItems,
                    scrubSprites = model.scrubSprites,
                    onRotate = { PlayerWindow.toggleOrientation() },
                    onPictureInPicture = { PlayerWindow.enterPictureInPicture(player.videoSize) },
                )
            }
        }

        SceneToastHost(Modifier.align(Alignment.TopCenter))
    }

    // Sheets and alerts (iOS `SceneDetailAlertModifier`, `ScenePlayerExtrasSheetsModifier`).
    when (sheet) {
        EditSheet.Title -> EditSceneTitleSheet(scene, { sheet = null }) { t, d -> model.applyEdit(model.scene.copy(title = t, details = d)) }
        EditSheet.Performers -> EditPerformersSheet(scene, { sheet = null }) { model.applyEdit(model.scene.copy(performers = it)) }
        EditSheet.Studio -> EditStudioSheet(scene, { sheet = null }) { model.applyEdit(model.scene.copy(studio = it)) }
        EditSheet.Groups -> EditGroupsSheet(scene, { sheet = null }) { model.applyEdit(model.scene.copy(groups = it)) }
        EditSheet.Tags -> EditTagsSheet(scene, { sheet = null }) { model.applyEdit(model.scene.copy(tags = it)) }
        EditSheet.Galleries -> EditGalleriesSheet(scene, { sheet = null }) { model.applyEdit(model.scene.copy(galleries = it)) }
        null -> {}
    }
    if (model.showAddMarker) AddMarkerSheet(scene, model.capturedMarkerTime, { model.showAddMarker = false }) { model.refreshDetails() }
    model.tagImageDataURL?.let { url -> SetTagImageFromFrameSheet(url, scene.tags.orEmpty()) { model.tagImageDataURL = null } }
    if (model.showReplaceCoverConfirm) AlertDialog(
        onDismissRequest = { model.showReplaceCoverConfirm = false },
        title = { Text("Replace Scene Cover?") },
        text = { Text("The current video frame will replace this scene’s cover image. This cannot be undone from the app.") },
        confirmButton = { TextButton({ model.showReplaceCoverConfirm = false; model.captureAndSetSceneCover() }) { Text("Replace", color = StashyColors.systemRed) } },
        dismissButton = { TextButton({ model.showReplaceCoverConfirm = false }) { Text("Cancel") } },
    )
    if (model.showDeleteConfirmation) AlertDialog(
        onDismissRequest = { model.showDeleteConfirmation = false },
        title = { Text("Really delete scene and files?") },
        text = { Text("The scene '${scene.displayTitle}' and all associated files will be permanently deleted. This action cannot be undone.") },
        confirmButton = { TextButton({ model.showDeleteConfirmation = false; model.deleteSceneWithFiles { Nav.pop() } }) { Text("Delete", color = StashyColors.systemRed) } },
        dismissButton = { TextButton({ model.showDeleteConfirmation = false }) { Text("Cancel") } },
    )
}

/** iOS: `sceneDetailNavBar` — Back pill (accent) · Identify (no StashID yet) · download state. */
@Composable
private fun SceneDetailNavBar(model: SceneDetailModel) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        GlassCapsule(tint = Appearance.tint, height = 40.dp, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp), onClick = { Nav.pop() }) {
            Icon(PlayerIcons.back, "Back", tint = Color.White, modifier = Modifier.size(18.dp))
            Text("Back", color = Color.White, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold))
        }
        Spacer(Modifier.weight(1f))
        if (!model.scene.hasStashID) {
            Box(Modifier.size(40.dp).stashyGlass(CircleShape).clickable(enabled = !model.isIdentifying) { model.identify() }, contentAlignment = Alignment.Center) {
                if (model.isIdentifying) CircularProgressIndicator(Modifier.size(22.dp), color = Appearance.tint, strokeWidth = 2.5.dp)
                else Icon(PlayerIcons.identify, "Identify scene", tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(18.dp))
            }
        }
        if (Downloads.isDownloaded(model.scene.id)) {
            Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                Icon(PlayerIcons.checkCircle, "Downloaded", tint = StashyColors.systemGreen, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/** iOS: "Delete Scene" card button — destructive red, never the accent. */
@Composable
private fun DeleteSceneButton(modifier: Modifier, onClick: () -> Unit) {
    Row(
        modifier.clip(RoundedCornerShape(Tokens.Radius.card)).background(StashyColors.systemRed.copy(alpha = 0.15f)).clickable(onClick = onClick).padding(16.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(PlayerIcons.trash, null, tint = StashyColors.systemRed, modifier = Modifier.size(18.dp))
        Spacer(Modifier.size(6.dp))
        Text("Delete Scene", color = StashyColors.systemRed, style = IosTypography.body)
    }
}

/** iOS: the `AVAudioSession.routeChangeNotification` handler — mute follows the headphones. */
@Composable
private fun RouteMuteFollower(model: SceneDetailModel) {
    val context = androidx.compose.ui.platform.LocalContext.current
    DisposableEffect(model) {
        val am = context.getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
        val callback = object : android.media.AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out android.media.AudioDeviceInfo>?) = sync()
            override fun onAudioDevicesRemoved(removed: Array<out android.media.AudioDeviceInfo>?) = sync()
            fun sync() {
                if (model.player == null) return
                val muted = de.letzgo.stashy.ui.player.PlayerMute.initialValue(context)
                if (muted != model.isMuted) model.updateMuted(muted)
            }
        }
        am.registerAudioDeviceCallback(callback, android.os.Handler(android.os.Looper.getMainLooper()))
        onDispose { am.unregisterAudioDeviceCallback(callback) }
    }
}

