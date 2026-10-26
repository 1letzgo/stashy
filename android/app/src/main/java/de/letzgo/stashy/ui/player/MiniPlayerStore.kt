package de.letzgo.stashy.ui.player

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.automirrored.filled.PlaylistAddCheck
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.PlaylistRemove
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.data.WatchlistStore
import de.letzgo.stashy.data.MiniPlayerLastSession
import de.letzgo.stashy.ui.scene.originalVideoURL
import de.letzgo.stashy.ui.scene.transcodeFallbackURLs
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.floatingShadow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Pure rules of the mini player hand-off (iOS: the guards in `SceneDetailView.finishDisappearTeardown`,
 * `takeEngineFromMiniPlayer` and `MiniPlayerBarContent`'s drag), kept apart for the unit tests.
 */
object MiniPlayerRules {
    /** What a scene page does with the mini player when it starts playback or appears. */
    enum class StartDecision {
        /** The bar plays this scene: take its player back (no reload, no seek, no cover). */
        TakeBack,
        /** The bar plays another scene: close it (saves its position) before this one starts. */
        CloseOther,
        Nothing,
    }

    /** A page being left hands its player over instead of releasing it. */
    fun handsOff(enabled: Boolean, playbackStarted: Boolean, isPlaying: Boolean, isDeleting: Boolean, inPictureInPicture: Boolean): Boolean =
        enabled && playbackStarted && isPlaying && !isDeleting && !inPictureInPicture

    /** [pageHasPlayer]: the page already runs its own player — nothing to take or close. */
    fun onPageStart(miniSceneId: String?, pageSceneId: String, pageHasPlayer: Boolean): StartDecision = when {
        pageHasPlayer || miniSceneId == null -> StartDecision.Nothing
        miniSceneId == pageSceneId -> StartDecision.TakeBack
        else -> StartDecision.CloseOther
    }

    /** iOS: swipe down more than 40 pt or sideways more than 120 pt closes the bar (values in dp). */
    fun closesOnDrag(dx: Float, dy: Float): Boolean = dy > 40f || abs(dx) > 120f

    fun progress(currentTime: Double, duration: Double): Float =
        if (duration > 0 && currentTime.isFinite()) (currentTime / duration).coerceIn(0.0, 1.0).toFloat() else 0f

    /** Where a scene switched to in the bar starts: its resume point, unless it was watched to ≥ 95 %. */
    fun resumeStart(resumeTime: Double?, duration: Double?): Double? {
        val time = resumeTime?.takeIf { it > 0 } ?: return null
        if (duration != null && duration > 0 && time >= duration * 0.95) return null
        return time
    }

    /** "Now Playing" holds the scene last started only — never a growing history. */
    const val PLAYING_QUEUE_LIMIT = 1

    /**
     * iOS `notePlaying` — [scene] started playing: at the top of "Now Playing" (deduped, newest
     * first, at most [limit]), on the watchlist or not.
     */
    fun notedPlaying(queue: List<Scene>, scene: Scene, limit: Int = PLAYING_QUEUE_LIMIT): List<Scene> =
        if (queue.firstOrNull()?.id == scene.id) queue
        else (listOf(scene) + queue.filter { it.id != scene.id }).take(limit)

    /**
     * iOS `nextScene(after:)` — the next watchlist entry when [sceneId] is on the watchlist;
     * after a scene started with Play, the watchlist from the top (it is the "up next" list).
     */
    fun nextScene(watchlist: List<Scene>, sceneId: String): Scene? =
        if (watchlist.any { it.id == sceneId }) de.letzgo.stashy.data.WatchlistLogic.next(watchlist, sceneId)
        else watchlist.firstOrNull { it.id != sceneId }

    /** First two performers, else the studio, else nothing. */
    fun subtitle(performerNames: List<String>, studioName: String?): String {
        val names = performerNames.map { it.trim() }.filter { it.isNotEmpty() }.take(2).joinToString(", ")
        return names.ifEmpty { studioName?.trim().orEmpty() }
    }
}

/**
 * iOS: `MiniPlayerStore` — keeps a scene playing after its detail page is left. The page hands
 * its running [StashPlayer] over instead of releasing it; [MiniPlayerBar] above the tab bar draws
 * it, and reopening the scene (from the bar, or by returning to the page) takes the same player
 * back, so the video never reloads. Resume time and play duration keep syncing meanwhile.
 */
object MiniPlayerStore {
    data class Session(
        val scene: Scene,
        val player: StashPlayer,
        /** This viewing was already counted as a play; whoever takes it next must not count it again. */
        val playRegistered: Boolean,
        /** Seconds actually watched in this viewing ([PlayCountCredit]), handed on with the player. */
        val watchedSeconds: Double = 0.0,
        /** Server the scene belongs to — a switch closes the session. */
        val serverId: String?,
    )

    var session by mutableStateOf<Session?>(null)
        private set

    /** The bar's tap: [AppShell] presents the mini player's own full view ([NowPlayingSheet]). */
    var showsNowPlaying by mutableStateOf(false)

    /**
     * Scene of the Now Playing view. While it is open the scene page's player module owns the
     * player, so [session] is empty; this keys the view (set by expand, a watchlist tap, next).
     */
    var nowPlayingScene by mutableStateOf<Scene?>(null)

    /**
     * "Now Playing": the scene last started, on the watchlist or not — one entry (memory only,
     * cleared on a server switch); the + on its row adds it to the watchlist.
     */
    var playingQueue by mutableStateOf<List<Scene>>(emptyList())
        private set
    /** Server [playingQueue] belongs to. */
    private var playingQueueServerId: String? = null
    /** Scenes deleted (in the app or found missing on the server) since the last server switch. */
    private val deletedSceneIds = mutableSetOf<String>()

    // MARK: Queue

    /** A scene started playing: on top of "Now Playing". */
    fun notePlaying(scene: Scene) {
        playingQueue = MiniPlayerRules.notedPlaying(playingQueue, scene)
    }

    /** The scene now on screen: the full view's while it is open, else the bar's. */
    val currentSceneId: String? get() = if (showsNowPlaying) nowPlayingScene?.id else session?.scene?.id

    /** What follows [sceneId]: see [MiniPlayerRules.nextScene]. */
    fun nextScene(after: String): Scene? = MiniPlayerRules.nextScene(WatchlistStore.all, after)

    fun previousScene(before: String): Scene? = WatchlistStore.previous(before)

    /** The + on a "Now Playing" row: onto the watchlist (at its end). */
    fun addToWatchlist(scene: Scene) = WatchlistStore.add(scene)

    /** Swipe on a "Now Playing" row. The scene on screen stays: closing it is the bar's ✕. */
    fun removeFromPlaying(sceneId: String) {
        if (sceneId == currentSceneId) return
        playingQueue = playingQueue.filter { it.id != sceneId }
    }

    /** Taken off the watchlist: the scene on screen keeps playing (it stays in "Now Playing"). */
    fun watchlistRemoved(scene: Scene) {
        if (scene.id == currentSceneId && playingQueue.none { it.id == scene.id }) notePlaying(scene)
    }

    /** Fresh copies from the server (titles, covers, resume times). */
    fun refreshPlaying(fresh: Map<String, Scene>) {
        if (playingQueue.none { fresh[it.id] != null }) return
        playingQueue = playingQueue.map { fresh[it.id] ?: it }
    }

    /** iOS `sceneDeleted` — deleted in the app, or found missing on the server: gone from every surface. */
    fun sceneDeleted(sceneId: String) {
        deletedSceneIds += sceneId
        if (session?.scene?.id == sceneId) close(dismissNowPlaying = false)
        if (nowPlayingScene?.id == sceneId) { showsNowPlaying = false; nowPlayingScene = null }
        if (playingQueue.any { it.id == sceneId }) playingQueue = playingQueue.filter { it.id != sceneId }
        if (WatchlistStore.contains(sceneId)) WatchlistStore.remove(sceneId)
    }

    /** Now Playing: switch to [scene] (row tap, previous / next, end of a scene); the view rebuilds its player module for it. */
    fun showInNowPlaying(scene: Scene) {
        notePlaying(scene)
        nowPlayingScene = scene
    }

    /**
     * iOS `openNowPlaying`: Play on a scene page while the mini player is on — the scene plays in
     * the full view (and is listed under "Playing"). [startAt] null resumes where it was left.
     */
    fun openNowPlaying(scene: Scene, startAt: Double?) {
        notePlaying(scene)
        // The bar already runs it: the full view takes that player as is, so jump it here.
        if (startAt != null) session?.takeIf { it.scene.id == scene.id }?.player?.seek(startAt)
        nowPlayingScene = if (startAt != null) scene.copy(resumeTime = startAt) else scene
        showsNowPlaying = true
    }

    /** Now Playing reached the end of [currentId]: on to what comes next, if anything. */
    fun advanceNowPlaying(currentId: String) {
        if (!showsNowPlaying) return
        nextScene(nowPlayingScene?.id ?: currentId)?.let { showInNowPlaying(it) }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    init {
        // A scene deleted in the app leaves every mini player surface (iOS "SceneDeleted").
        scope.launch {
            SceneEvents.events.collect { event -> if (event is SceneEvent.Deleted) sceneDeleted(event.sceneId) }
        }
    }
    private val tracker = PlaybackActivityTracker(scope)
    /** "Count as played" by watched seconds, like the scene page (iOS `PlayCountWatchClock`). */
    private val playCredit = PlayCountCredit(0.0)
    /** Position of the last "last session" save (see [MiniPlayerLastSession]). */
    private var lastSavedPosition: Double? = null

    /** stashy+: Settings › stashy+ › "Mini player when leaving a scene", only while stashy+ is unlocked. */
    val isEnabled: Boolean get() = TabManager.isMiniPlayerEnabled && de.letzgo.stashy.data.StashyPlus.isUnlocked

    /** Takes over [player] from a scene page that is going away. Any other mini session ends. */
    fun adopt(scene: Scene, player: StashPlayer, watchedSeconds: Double, playRegistered: Boolean, serverId: String?) {
        // Now Playing switched to another scene: the page it replaced hands over late, after the
        // new module may already run its own player. Taking it would leave a second video playing.
        // A deleted scene (its Now Playing module closing) is not taken either.
        val shown = nowPlayingScene
        if ((showsNowPlaying && shown != null && shown.id != scene.id) || scene.id in deletedSceneIds) {
            player.onTime = null
            player.onPlayingChanged = null
            player.onReachedEnd = null
            player.pause()
            player.release()
            return
        }
        session?.let { if (it.player !== player) close() }
        player.onTime = { seconds, duration -> handleTime(seconds, duration) }
        player.onPlayingChanged = { playing -> if (playing) tracker.start() else tracker.stop() }
        // The watchlist plays on in the bar: the next entry starts when one ends.
        player.onReachedEnd = { playNext() }
        // Captions and transcode toasts belong to the page; the bar only plays.
        player.onTranscodeFallback = null
        player.onFirstFrame = null

        tracker.reset()
        configureTracker(scene.id)
        tracker.setPosition(player.currentTime, if (player.duration > 0) player.duration else scene.sceneDuration ?: 0.0)
        if (player.isPlaying) tracker.start()
        playCredit.restore(watchedSeconds, playRegistered)
        session = Session(scene, player, playRegistered, watchedSeconds, serverId)
        notePlaying(scene)
        saveLastSession(scene, player.currentTime)
    }

    private fun saveLastSession(scene: Scene, position: Double) {
        val serverId = session?.serverId ?: return
        lastSavedPosition = position
        MiniPlayerLastSession.save(serverId, scene, position)
    }

    /** A scene page stopped [sceneId] without handing it over: forget it if it is the saved one. */
    fun forgetLastSession(sceneId: String, serverId: String?) {
        if (MiniPlayerLastSession.forgetsFor(MiniPlayerLastSession.load(serverId)?.scene?.id, sceneId)) MiniPlayerLastSession.forget(serverId)
    }

    /**
     * iOS `restoreLastSessionIfNeeded` — on launch (and after a server switch) the last session of
     * [serverId] comes back paused at its position. Only with the mini player on and stashy+.
     */
    fun restoreLastSessionIfNeeded(serverId: String?) {
        if (session != null || !isEnabled) return
        val saved = MiniPlayerLastSession.load(serverId) ?: return
        val scene = saved.scene
        val url = scene.originalVideoURL ?: return
        val context = de.letzgo.stashy.data.Prefs.appContext
        val p = StashPlayer(context, StashPlayer.Role.Main)
        p.isMuted = PlayerMute.initialValue(context)
        p.fallbackSources = scene.transcodeFallbackURLs
        p.fallbackDeclaredDuration = scene.sceneDuration
        p.nowPlaying = SceneNowPlaying.of(scene)
        p.enableMediaSession()
        // Restoring is not a new viewing: no play is counted for it.
        adopt(scene, p, watchedSeconds = 0.0, playRegistered = true, serverId = serverId)
        p.load(url, saved.position.takeIf { it > 0 }, autoplay = false)
        lastSavedPosition = saved.position
    }

    /** iOS `play(_:)` — switches the bar to [scene] on the same player (watchlist tap, next entry). */
    fun play(scene: Scene) {
        val current = session ?: return
        val p = current.player
        if (current.scene.id == scene.id) { p.play(); return }
        val url = scene.originalVideoURL ?: return
        // Save the one being left before the tracker moves on.
        tracker.setPosition(p.currentTime, if (p.duration > 0) p.duration else current.scene.sceneDuration ?: 0.0)
        tracker.stop()
        tracker.reset()
        configureTracker(scene.id)
        p.fallbackSources = scene.transcodeFallbackURLs
        p.fallbackDeclaredDuration = scene.sceneDuration
        p.nowPlaying = SceneNowPlaying.of(scene)
        playCredit.reset()
        session = current.copy(scene = scene, playRegistered = false)
        notePlaying(scene)
        saveLastSession(scene, MiniPlayerRules.resumeStart(scene.resumeTime, scene.sceneDuration) ?: 0.0)
        p.load(url, MiniPlayerRules.resumeStart(scene.resumeTime, scene.sceneDuration), autoplay = true)
    }

    val hasNext: Boolean get() = session?.let { nextScene(it.scene.id) } != null

    /** The bar's video ended (or Next): on to what comes next. */
    fun playNext() {
        val current = session ?: return
        nextScene(current.scene.id)?.let { play(it) }
    }

    fun seekBy(delta: Double) {
        val p = session?.player ?: return
        val target = (p.currentTime + delta).coerceIn(0.0, maxOf(p.duration - 1, 0.0))
        p.seek(target)
        tracker.noteSeek(target)
    }

    fun seekTo(seconds: Double) {
        val p = session?.player ?: return
        p.seek(seconds)
        tracker.noteSeek(seconds)
    }

    fun expand() { session?.let { nowPlayingScene = it.scene; showsNowPlaying = true } }

    /** Resume tracking plus the play count, which the page would otherwise have counted. */
    private fun handleTime(seconds: Double, duration: Double) {
        val current = session ?: return
        if (seconds < 0) return
        tracker.setPosition(seconds, if (duration > 0) duration else current.scene.sceneDuration ?: 0.0)
        if (current.player.isPlaying && MiniPlayerLastSession.isDueForSave(lastSavedPosition, seconds)) saveLastSession(current.scene, seconds)
        playCredit.thresholdSeconds = maxOf(0.0, PlayerSettings.playCountPlayerSeconds)
        if (playCredit.onTime(seconds, current.player.isPlaying, android.os.SystemClock.elapsedRealtime() / 1000.0)) {
            session = current.copy(playRegistered = true)
            val id = current.scene.id
            if (!TabManager.tracksActivity(id)) return
            scope.launch {
                runCatching { SceneEditing.addPlay(id) }
                SceneEvents.post(SceneEvent.PlayAdded(id))
            }
        }
    }

    /** Hands the player back to a page showing [sceneId], or null when the bar plays something else. */
    fun take(sceneId: String): Session? {
        val current = session?.takeIf { it.scene.id == sceneId } ?: return null
        tracker.setPosition(current.player.currentTime, if (current.player.duration > 0) current.player.duration else current.scene.sceneDuration ?: 0.0)
        tracker.stop()
        current.player.onTime = null
        current.player.onPlayingChanged = null
        current.player.onReachedEnd = null
        session = null
        return current.copy(playRegistered = playCredit.isCredited, watchedSeconds = playCredit.watchedSeconds)
    }

    /** Ends the mini session if it plays a different scene than the one about to start. */
    fun yield(sceneId: String) {
        // Keeps Now Playing open: it is switching its own scene here.
        if (session?.let { it.scene.id != sceneId } == true) close(dismissNowPlaying = false)
    }

    fun showsScene(sceneId: String): Boolean = session?.scene?.id == sceneId

    fun togglePlayPause() { session?.player?.togglePlayPause() }

    /** iOS `stashyPauseBackgroundPlayers` (Feeds took over the screen). */
    fun pause() { session?.player?.pause() }

    /**
     * iOS `ServerConfigChanged` (and the shell's first appearance): a session of another server is
     * closed but stays saved for that server; then [serverId]'s saved session is restored.
     */
    fun onServerChanged(serverId: String?) {
        if (session?.let { it.serverId != serverId } == true) close(forget = false)
        // "Playing" is per launch and server; the shell re-running this for the same server keeps it.
        if (playingQueueServerId != serverId) {
            playingQueueServerId = serverId
            playingQueue = emptyList()
            deletedSceneIds.clear()
        }
        restoreLastSessionIfNeeded(serverId)
    }

    /** Saves the position and releases the player; [forget] drops the saved last session (✕ / swipe). */
    fun close(forget: Boolean = true, dismissNowPlaying: Boolean = true) {
        val current = session ?: return
        val p = current.player
        tracker.setPosition(p.currentTime, if (p.duration > 0) p.duration else current.scene.sceneDuration ?: 0.0)
        tracker.stop()
        p.onTime = null
        p.onPlayingChanged = null
        p.onReachedEnd = null
        p.pause()
        p.release()
        if (forget) MiniPlayerLastSession.forget(current.serverId)
        else MiniPlayerLastSession.save(current.serverId, current.scene, p.currentTime)
        lastSavedPosition = null
        session = null
        if (dismissNowPlaying) showsNowPlaying = false
    }

    /** Same save path as the scene page (`SceneDetailModel.configureTracker`). */
    private fun configureTracker(sceneId: String) {
        tracker.updatesResumeTime = true
        tracker.onSave = { resume, played ->
            scope.launch {
                val ok = runCatching { SceneEditing.saveActivity(sceneId, resume, played) }.isSuccess
                if (ok && resume != null) SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, resume))
            }
        }
    }
}

/**
 * iOS: `MiniPlayerBar` — live picture, title, performers / studio, play/pause, close and a tint
 * progress line, plus the watchlist button. Tap opens the Now Playing view; a swipe down or
 * sideways closes it.
 */
@Composable
fun MiniPlayerBar(visible: Boolean, modifier: Modifier = Modifier) {
    val session = MiniPlayerStore.session
    AnimatedVisibility(
        visible && session != null, modifier,
        enter = fadeIn() + slideInVertically { it / 2 },
        exit = fadeOut() + slideOutVertically { it / 2 },
    ) {
        // Keeps drawing the last session while the exit animation runs.
        val shown = remember { mutableStateOf(session) }
        if (session != null) shown.value = session
        shown.value?.let { MiniPlayerBarContent(it) }
    }
}

@Composable
private fun MiniPlayerBarContent(session: MiniPlayerStore.Session) {
    val p = Theme.palette
    val player = session.player
    val scene = session.scene
    val density = LocalDensity.current
    var dragX by remember { mutableFloatStateOf(0f) }
    var dragY by remember { mutableFloatStateOf(0f) }
    val subtitle = MiniPlayerRules.subtitle(scene.performers.map { it.name }, scene.studio?.name)
    val playing = player.isPlaying || player.playWhenReady

    Box(
        Modifier.fillMaxWidth().height(56.dp)
            .graphicsLayer {
                translationY = maxOf(dragY, 0f)
                val dy = with(density) { maxOf(dragY, 0f).toDp().value }
                alpha = 1f - (dy / 80f).coerceIn(0f, 0.6f)
            }
            .floatingShadow(RoundedCornerShape(16.dp))
            .clip(RoundedCornerShape(16.dp))
            .background(de.letzgo.stashy.ui.chromeBarColor(p.secondaryBackground))
            .pointerInput(session.scene.id) {
                detectDragGestures(
                    onDragStart = { dragX = 0f; dragY = 0f },
                    onDragCancel = { dragX = 0f; dragY = 0f },
                    onDragEnd = {
                        val dx = with(density) { dragX.toDp().value }
                        val dy = with(density) { dragY.toDp().value }
                        dragX = 0f; dragY = 0f
                        if (MiniPlayerRules.closesOnDrag(dx, dy)) MiniPlayerStore.close()
                    },
                ) { change, amount -> change.consume(); dragX += amount.x; dragY += amount.y }
            }
            .clickable { MiniPlayerStore.expand() }
            .semantics { contentDescription = "Mini player: ${scene.displayTitle}. Opens the player" },
    ) {
        Row(
            Modifier.fillMaxWidth().fillMaxHeight().padding(start = 8.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val thumbModifier = Modifier.size(width = 64.dp, height = 36.dp).clip(RoundedCornerShape(6.dp))
            // The full view draws the picture now; a player shows in one place only.
            // Cover while Now Playing draws the picture, and until a restored (paused) player has a frame.
            if (MiniPlayerStore.showsNowPlaying || !player.hasPresentedFrame) {
                coil3.compose.AsyncImage(scene.thumbnailURL, null, thumbModifier.background(androidx.compose.ui.graphics.Color.Black), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
            } else VideoSurface(player, thumbModifier, fill = true)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(scene.displayTitle, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitle.isNotEmpty()) Text(subtitle, fontSize = 12.sp, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            WatchlistButton()
            IconButton(onClick = { MiniPlayerStore.togglePlayPause() }, modifier = Modifier.size(40.dp)) {
                Icon(if (playing) SF.pauseFill else SF.playFill, if (playing) "Pause" else "Play", tint = p.text)
            }
            IconButton(onClick = { MiniPlayerStore.close() }, modifier = Modifier.size(36.dp)) {
                Icon(SF.xmark, "Close mini player", tint = p.text, modifier = Modifier.size(20.dp))
            }
        }
        MiniPlayerProgressLine(player, Modifier.align(Alignment.BottomStart).padding(horizontal = 12.dp).fillMaxWidth().height(2.dp))
    }
}

/**
 * iOS `MiniPlayerProgressLine` — samples the playhead once a second instead of reading the
 * player's time state, so the bar does not recompose on every time tick.
 */
@Composable
private fun MiniPlayerProgressLine(player: StashPlayer, modifier: Modifier) {
    val progress by androidx.compose.runtime.produceState(MiniPlayerRules.progress(player.currentTime, player.duration), player) {
        while (true) {
            value = MiniPlayerRules.progress(player.currentTime, player.duration)
            kotlinx.coroutines.delay(1_000)
        }
    }
    Box(modifier) {
        Box(Modifier.fillMaxWidth(progress).height(2.dp).clip(RoundedCornerShape(1.dp)).background(Appearance.tint))
    }
}

/** The bar's list button: opens Now Playing, badge = watchlist size. */
@Composable
private fun WatchlistButton() {
    val count = WatchlistStore.all.size
    Box {
        IconButton(onClick = { MiniPlayerStore.expand() }, modifier = Modifier.size(36.dp)) {
            Icon(WatchlistIcons.list, "Watchlist", tint = Theme.palette.text, modifier = Modifier.size(22.dp))
        }
        if (count > 0) Text(
            "$count",
            Modifier.align(Alignment.TopEnd).padding(top = 2.dp, end = 2.dp)
                .clip(RoundedCornerShape(50)).background(Appearance.tint).padding(horizontal = 4.dp),
            fontSize = 9.sp, fontWeight = FontWeight.Bold, color = androidx.compose.ui.graphics.Color.White,
        )
    }
}

/** iOS `list.bullet`, `text.badge.plus` / `text.badge.checkmark`. */
object WatchlistIcons {
    val list = Icons.AutoMirrored.Filled.PlaylistPlay
    val add = Icons.AutoMirrored.Filled.PlaylistAdd
    val listed = Icons.AutoMirrored.Filled.PlaylistAddCheck
    val removed = Icons.Filled.PlaylistRemove
}
