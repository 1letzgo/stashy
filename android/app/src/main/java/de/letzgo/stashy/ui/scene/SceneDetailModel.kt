package de.letzgo.stashy.ui.scene

import android.graphics.Bitmap
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Downloads
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.OCounterMutation
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SceneStamps
import de.letzgo.stashy.data.ScenesRepository
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.VideoCaption
import de.letzgo.stashy.ui.player.PlaybackActivityTracker
import de.letzgo.stashy.ui.player.PlayerIcons
import de.letzgo.stashy.ui.player.PlayerMute
import de.letzgo.stashy.ui.player.PlayerSettings
import de.letzgo.stashy.ui.player.PlayerWindow
import de.letzgo.stashy.ui.player.SceneScrubSprites
import de.letzgo.stashy.ui.player.StashPlayer
import de.letzgo.stashy.ui.player.TimeBarMarker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.util.Locale

// MARK: - Scene helpers (iOS `Scene+AetherPlayback.swift`)

/** iOS: `Scene.aetherVideoURL` — local download first, else the original stream (never a transcode). */
val Scene.originalVideoURL: String? get() = streamURL

/** iOS: `Scene.transcodeFallbackURLs` — `stream.m3u8`, then `stream.mp4`; empty for local downloads. */
val Scene.transcodeFallbackURLs: List<String> get() {
    if (Downloads.localVideo(id) != null) return emptyList()
    val base = ServerConfigManager.activeConfig?.baseURL ?: return emptyList()
    return listOfNotNull(Net.signed("$base/scene/$id/stream.m3u8"), Net.signed("$base/scene/$id/stream.mp4"))
}

/** iOS: `Scene.timeBarMarkers` — start + title, falling back to the primary tag's name. */
val Scene.timeBarMarkers: List<TimeBarMarker> get() = sceneMarkers.orEmpty().map { m ->
    TimeBarMarker(m.seconds, m.title?.trim()?.takeIf { it.isNotEmpty() } ?: m.primaryTag?.name)
}

/** iOS: `Scene.normalizedDirector`. */
val Scene.normalizedDirector: String? get() = director?.trim()?.takeIf { it.isNotEmpty() }

val Scene.hasStashID: Boolean get() = !stashIds.isNullOrEmpty()

/** iOS: `StashCaptionURL.url(for:scene:)` — `paths.caption` (or `/scene/<id>/caption`) with `lang` + `type`. */
fun captionURL(caption: VideoCaption, scene: Scene): String? {
    val raw = scene.paths?.caption?.trim()?.takeIf { it.isNotEmpty() }
    val config = ServerConfigManager.activeConfig
    val base = when {
        raw == null -> config?.let { "${it.baseURL}/scene/${scene.id}/caption" }
        raw.startsWith("http://") || raw.startsWith("https://") -> raw
        config != null -> "${config.baseURL}/${raw.removePrefix("/")}"
        else -> raw
    } ?: return null
    val uri = android.net.Uri.parse(base)
    val builder = uri.buildUpon().clearQuery()
    uri.queryParameterNames.filter { it.lowercase() !in setOf("lang", "type", "apikey") }.forEach { n ->
        uri.getQueryParameters(n).forEach { builder.appendQueryParameter(n, it) }
    }
    builder.appendQueryParameter("lang", caption.languageCode.orEmpty())
    builder.appendQueryParameter("type", caption.captionType.orEmpty())
    return Net.signed(builder.build().toString())
}

/** iOS: `videoFrameDataURL(from:)` — JPEG 0.88 as `data:image/jpeg;base64,…`. */
fun Bitmap.toDataURL(): String {
    val out = ByteArrayOutputStream()
    compress(Bitmap.CompressFormat.JPEG, 88, out)
    return "data:image/jpeg;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
}

/**
 * State and playback logic of one scene detail page (iOS: the `@State` + private functions of
 * `SceneDetailView`). Lives as long as the pushed [SceneDetailScreen], so leaving the page for a
 * pushed screen or another tab and coming back resumes where it was (iOS `resumeOnReturn`).
 */
class SceneDetailModel(initial: Scene, private val autoPlay: Boolean) {
    /** Outlives the composition: activity saves on leaving must still go out. */
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var scene by mutableStateOf(initial)
    var player by mutableStateOf<StashPlayer?>(null); private set
    var isPlaybackStarted by mutableStateOf(false); private set
    var isFullscreen by mutableStateOf(false)
    var isMuted by mutableStateOf(true)
    var currentPlaybackTime by mutableDoubleStateOf(0.0); private set
    var isScrubbing = false
    var scrubSprites by mutableStateOf<SceneScrubSprites?>(null); private set
    var isPreviewing by mutableStateOf(false)
    var isHeaderExpanded by mutableStateOf(false)
    var isTagsExpanded by mutableStateOf(false)

    // Sheets / alerts
    var showDeleteConfirmation by mutableStateOf(false)
    var showAddMarker by mutableStateOf(false)
    var capturedMarkerTime by mutableDoubleStateOf(0.0)
    var showReplaceCoverConfirm by mutableStateOf(false)
    var tagImageDataURL by mutableStateOf<String?>(null)
    var isCapturing by mutableStateOf(false); private set

    var isDeleting by mutableStateOf(false); private set
    var isIdentifying by mutableStateOf(false); private set

    private var hasAddedPlay = false
    private var didAnnounceTranscodeFallback = false
    private var resumeOnReturn: Pair<Boolean, Double>? = null
    private var hasAppeared = false
    private val tracker = PlaybackActivityTracker(scope)
    /** AI Subtitles + caption translation of the player's "…" menu (iOS `ScenePlayerExtrasController`). */
    val aiSubtitles by lazy { SceneAiSubtitles(this) }

    // MARK: Lifecycle

    /** iOS: `handleOnAppear`. */
    fun onAppear() {
        isFullscreen = false
        refreshScrubSprites()
        val s = scene
        if (!hasAppeared || s.performers.isEmpty() || s.tags.isNullOrEmpty() || s.groups == null || s.sceneMarkers == null || s.captions == null) {
            refreshDetails()
        }
        hasAppeared = true
        resumeOnReturn?.let { (wasPlaying, position) ->
            resumeOnReturn = null
            if (position > 1) scene = scene.copy(resumeTime = position)
            if (wasPlaying) scope.launch { delay(300); if (!isPlaybackStarted) startPlayback(true) }
            return
        }
        if (autoPlay) scope.launch { delay(300); if (!isPlaybackStarted) startPlayback(true) }
    }

    /** iOS: `handleOnDisappear` + `finishDisappearTeardown`. */
    fun onDisappear() {
        isPreviewing = false
        val p = player
        if (isDeleting) { p?.pause(); return }
        persistPlaybackActivity(stopTracking = true)
        SceneEvents.post(SceneEvent.Updated(scene))
        if (p != null && isPlaybackStarted) resumeOnReturn = p.playWhenReady to p.currentTime
        p?.pause()
        p?.release()
        player = null
        isPlaybackStarted = false
        if (isFullscreen) { isFullscreen = false; PlayerWindow.setImmersive(false); PlayerWindow.releaseOrientation() }
    }

    /** App went to the background: write the activity now (process may die later). */
    fun onStop() = persistPlaybackActivity(stopTracking = false)

    /** iOS: `refreshSceneDetails` — keeps a local resume time and the newer `updated_at`. */
    fun refreshDetails() {
        scope.launch {
            val updated = runCatching { ScenesRepository.scene(scene.id) }.getOrNull() ?: return@launch
            val preserved = scene.resumeTime
            var next = updated
            if (preserved != null && preserved > 0) next = next.copy(resumeTime = preserved)
            next = next.copy(updatedAt = newerUpdatedAt(next.updatedAt, scene.updatedAt))
            scene = next
            refreshScrubSprites()
        }
    }

    private fun refreshScrubSprites() {
        scrubSprites = SceneScrubSprites.create(scene.paths?.vtt, scene.paths?.sprite)
    }

    // MARK: Playback

    /** iOS: `startPlayback(resume:)`. */
    fun startPlayback(resume: Boolean) {
        val url = scene.originalVideoURL ?: return
        val resumeTarget = scene.resumeTime?.takeIf { resume && it > 0 }
        val existing = player
        if (existing == null) {
            val p = StashPlayer(Prefs.appContext, StashPlayer.Role.Main)
            // Re-read here: the route only now reports connected headphones (iOS `initialValueForPlayback`).
            isMuted = PlayerMute.initialValue(Prefs.appContext)
            p.isMuted = isMuted
            p.onTime = { seconds, duration ->
                if (seconds >= 0) {
                    currentPlaybackTime = seconds
                    tracker.setPosition(seconds, if (duration > 0) duration else scene.sceneDuration ?: 0.0)
                    if (p.isPlaying) { configureTracker(); tracker.start() }
                }
                if (!hasAddedPlay && seconds >= playCountThreshold) registerPlay()
            }
            p.onPlayingChanged = { playing -> handlePlayingChange(p, playing) }
            p.fallbackSources = scene.transcodeFallbackURLs
            p.fallbackDeclaredDuration = scene.sceneDuration
            p.onTranscodeFallback = {
                if (!didAnnounceTranscodeFallback) {
                    didAnnounceTranscodeFallback = true
                    SceneToast.show("Original could not be played — using the server transcode", PlayerIcons.reset, SceneToast.Style.Error)
                }
            }
            p.mediaTitle = scene.displayTitle
            p.mediaArtworkURL = scene.thumbnailURL
            p.enableMediaSession()
            player = p
            p.load(url, resumeTarget, autoplay = true)
            registerCaptions(p)
        } else if (resumeTarget != null) {
            existing.seek(resumeTarget)
        }
        isPlaybackStarted = true
        player?.play()
        configureTracker()
        tracker.start()
        if (!hasAddedPlay && playCountThreshold <= 0) registerPlay()
    }

    /** Settings › Playback › "Count as played — Player". */
    private val playCountThreshold: Double get() = maxOf(0.0, PlayerSettings.playCountPlayerSeconds)

    /** iOS: `registerAetherCaptions` — server captions as selectable external tracks. */
    private fun registerCaptions(p: StashPlayer) {
        scene.captions.orEmpty().forEach { caption ->
            val url = captionURL(caption, scene) ?: return@forEach
            val code = caption.languageCode?.takeIf { it.isNotEmpty() && it != "00" }
            val name = code?.let { Locale(it).getDisplayLanguage(Locale.ENGLISH).takeIf { n -> n.isNotEmpty() && n != it } ?: it.uppercase() } ?: "Captions"
            p.addExternalSubtitleTrack(url, name, code)
        }
    }

    private fun handlePlayingChange(p: StashPlayer, playing: Boolean) {
        if (isScrubbing) return
        tracker.setPosition(p.currentTime, if (p.duration > 0) p.duration else scene.sceneDuration ?: 0.0)
        configureTracker()
        if (playing) tracker.start() else tracker.stop()
    }

    /** iOS: `seekTo` — starts playback first when needed. */
    fun seekTo(seconds: Double) {
        if (!isPlaybackStarted) startPlayback(false)
        val p = player ?: return
        p.seek(seconds)
        tracker.noteSeek(seconds)
        if (!isScrubbing) p.play()
    }

    /** iOS: `commitScrub(to:)` — heatmap drag end. */
    fun commitScrub(seconds: Double) {
        val p = player ?: return
        p.seek(seconds)
        tracker.noteSeek(seconds)
        p.play()
    }

    fun updateScrubbing(active: Boolean) {
        isScrubbing = active
        if (active) tracker.stop()
    }

    fun updateMuted(muted: Boolean) {
        isMuted = muted
        player?.isMuted = muted
    }

    /** iOS: `handlePeriodicSync` (every 10 s). */
    fun periodicSync() {
        if (isDeleting) return
        val p = player ?: return
        if (!p.isPlaying) return
        tracker.setPosition(p.currentTime, if (p.duration > 0) p.duration else scene.sceneDuration ?: 0.0)
        configureTracker()
        tracker.start()
        if (!hasAddedPlay && p.currentTime >= playCountThreshold) registerPlay()
    }

    private fun persistPlaybackActivity(stopTracking: Boolean) {
        player?.let { p ->
            val t = p.currentTime
            if (t.isFinite() && t >= 0) tracker.setPosition(t, if (p.duration > 0) p.duration else scene.sceneDuration ?: 0.0)
        }
        configureTracker()
        if (stopTracking) tracker.stop() else tracker.flush()
    }

    private fun configureTracker() {
        val sceneId = scene.id
        tracker.updatesResumeTime = true
        tracker.onSave = { resume, played ->
            scope.launch {
                val ok = runCatching { SceneEditing.saveActivity(sceneId, resume, played) }.isSuccess
                if (ok && resume != null) {
                    if (scene.id == sceneId) scene = scene.copy(resumeTime = resume)
                    SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, resume))
                }
            }
        }
    }

    /** iOS: `registerScenePlay` — `sceneAddPlay` once per page. */
    private fun registerPlay() {
        hasAddedPlay = true
        val id = scene.id
        scope.launch {
            val count = runCatching { SceneEditing.addPlay(id) }.getOrNull()
            if (count != null && scene.id == id) scene = scene.copy(playCount = count)
            SceneEvents.post(SceneEvent.PlayAdded(id))
        }
    }

    fun beginAddMarker() {
        capturedMarkerTime = player?.currentTime ?: 0.0
        showAddMarker = true
    }

    // MARK: Edits

    /** iOS: `applyLocalSceneEdit` — local state + list notification. */
    fun applyEdit(updated: Scene) {
        scene = updated
        SceneEvents.post(SceneEvent.Updated(updated))
    }

    fun incrementO() {
        val id = scene.id
        scope.launch {
            val count = runCatching { SceneEditing.mutateOCounter(id, OCounterMutation.Increment) }.getOrNull() ?: return@launch
            scene = scene.copy(oCounter = count)
            SceneEvents.post(SceneEvent.OCounterUpdated(id, count))
        }
    }

    /** iOS: `removeOCounter` — optimistic, rolled back with a toast on failure. */
    fun removeO(mutation: OCounterMutation) {
        val original = scene.oCounter ?: 0
        scene = scene.copy(oCounter = if (mutation == OCounterMutation.Reset) 0 else maxOf(0, original - 1))
        val id = scene.id
        scope.launch {
            val count = runCatching { SceneEditing.mutateOCounter(id, mutation) }.getOrNull()
            if (count != null) {
                scene = scene.copy(oCounter = count)
                SceneEvents.post(SceneEvent.OCounterUpdated(id, count))
            } else {
                scene = scene.copy(oCounter = original)
                SceneToast.show("Counter update failed", PlayerIcons.close, SceneToast.Style.Error)
            }
        }
    }

    fun setRating(rating100: Int?) {
        val original = scene
        val rated = scene.copy(rating100 = rating100)
        scene = rated
        scope.launch {
            if (runCatching { SceneEditing.updateRating(rated.id, rating100) }.isSuccess) SceneEvents.post(SceneEvent.Updated(rated))
            else { scene = original; SceneToast.show("Failed to update rating", PlayerIcons.close, SceneToast.Style.Error) }
        }
    }

    // MARK: Frame tools ("…" menu, iOS `ScenePlayerExtrasController`)

    fun captureTagImage() {
        if (isCapturing) return
        val bitmap = player?.captureFrame()
        if (bitmap == null) { SceneToast.show("Could not capture video frame", PlayerIcons.close, SceneToast.Style.Error); return }
        isCapturing = true
        scope.launch {
            tagImageDataURL = withContext(Dispatchers.Default) { bitmap.toDataURL() }
            isCapturing = false
        }
    }

    fun captureAndSetSceneCover() {
        if (isCapturing) return
        val bitmap = player?.captureFrame()
        if (bitmap == null) { SceneToast.show("Could not capture video frame", PlayerIcons.close, SceneToast.Style.Error); return }
        isCapturing = true
        val current = scene
        scope.launch {
            val dataURL = withContext(Dispatchers.Default) { bitmap.toDataURL() }
            val ok = runCatching { SceneEditing.setCoverImage(current.id, dataURL) }.isSuccess
            isCapturing = false
            if (ok) {
                val bust = System.currentTimeMillis().toString()
                scene = scene.copy(updatedAt = bust)
                SceneEvents.post(SceneEvent.CoverUpdated(current.id, bust))
                SceneToast.show("Scene cover updated", PlayerIcons.photo, SceneToast.Style.Success)
            } else SceneToast.show("Failed to update scene cover", PlayerIcons.close, SceneToast.Style.Error)
        }
    }

    // MARK: Identify / delete

    /** iOS: `startSceneIdentify` + `refreshSceneDetailsAfterIdentify`. */
    fun identify() {
        if (isIdentifying) return
        isIdentifying = true
        scope.launch {
            val started = runCatching { SceneEditing.identify(listOf(scene.id)) }
            val (message, jobId) = started.getOrElse {
                isIdentifying = false
                SceneToast.show(it.message?.removePrefix("GraphQL error: ") ?: "Identify failed", PlayerIcons.close, SceneToast.Style.Error)
                return@launch
            }
            if (jobId == null) {
                isIdentifying = false
                SceneToast.show(message, PlayerIcons.checkCircle, SceneToast.Style.Success)
                return@launch
            }
            val (ok, jobMessage) = SceneEditing.waitForJob(jobId)
            val updated = runCatching { ScenesRepository.scene(scene.id) }.getOrNull()
            if (updated != null) {
                var next: Scene = updated
                scene.resumeTime?.takeIf { it > 0 }?.let { next = next.copy(resumeTime = it) }
                if (ok) {
                    // Identify usually replaces the cover: bust like "Set as cover".
                    val bust = System.currentTimeMillis().toString()
                    next = next.copy(updatedAt = bust)
                    SceneEvents.post(SceneEvent.CoverUpdated(next.id, bust))
                }
                scene = next
                SceneEvents.post(SceneEvent.Updated(next))
            }
            isIdentifying = false
            when {
                !ok -> SceneToast.show(jobMessage, PlayerIcons.close, SceneToast.Style.Error)
                scene.hasStashID -> SceneToast.show("Scene identified", PlayerIcons.checkCircle, SceneToast.Style.Success)
                else -> SceneToast.show("Identify finished — no match", null, SceneToast.Style.Info)
            }
        }
    }

    /** iOS: `deleteSceneWithFiles` — pops the page on success. */
    fun deleteSceneWithFiles(onDeleted: () -> Unit) {
        isDeleting = true
        player?.pause()
        val s = scene
        scope.launch {
            if (runCatching { SceneEditing.deleteSceneWithFiles(s) }.isSuccess) {
                SceneEvents.post(SceneEvent.Deleted(s.id))
                SceneToast.show("Scene deleted", PlayerIcons.trash, SceneToast.Style.Success)
                player?.release(); player = null
                onDeleted()
            } else {
                isDeleting = false
                SceneToast.show("Failed to delete scene", PlayerIcons.close, SceneToast.Style.Error)
            }
        }
    }

    companion object {
        /** iOS: `Scene.newerUpdatedAt` — see [SceneStamps]. */
        fun newerUpdatedAt(a: String?, b: String?): String? = SceneStamps.newerUpdatedAt(a, b)
        fun parseUpdatedAt(raw: String): Long? = SceneStamps.parseUpdatedAt(raw)
    }
}
