package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import de.letzgo.stashy.data.FeedQueryKind
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.FeedsQuery
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.ImageSortOption
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneEvent
import de.letzgo.stashy.data.SceneEvents
import de.letzgo.stashy.data.SceneMarkerSortOption
import de.letzgo.stashy.data.SceneSortOption
import de.letzgo.stashy.data.TabManager
import de.letzgo.stashy.ui.feeds.FeedItem
import de.letzgo.stashy.ui.feeds.FeedStartPosition
import de.letzgo.stashy.ui.player.PlayCountCredit
import de.letzgo.stashy.ui.player.PlaybackActivityTracker
import de.letzgo.stashy.ui.player.StashPlayer
import de.letzgo.stashy.ui.scene.transcodeFallbackURLs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlin.random.Random

// MARK: - Item helpers (iOS `TVFeedItem`)

/** iOS `TVFeedItem.title`: scene title (else "Untitled scene"), marker title / primary tag / its scene, clip file name. */
val FeedItem.tvTitle: String get() = when (this) {
    is FeedItem.SceneItem -> scene.title?.takeIf { it.isNotBlank() } ?: title ?: tr(R.string.untitled_scene)
    is FeedItem.PreviewItem -> scene.title?.takeIf { it.isNotBlank() } ?: title ?: tr(R.string.untitled_scene)
    is FeedItem.MarkerItem -> marker.title?.trim()?.takeIf { it.isNotEmpty() } ?: marker.primaryTag?.name?.takeIf { it.isNotEmpty() }
        ?: marker.scene?.displayTitle ?: tr(R.string.marker)
    is FeedItem.ClipItem -> image.tvDisplayTitle ?: title ?: ""
}

/** iOS `TVFeedItem.subtitle`: a marker's scene (its date when the titles match), otherwise the date. */
val FeedItem.tvSubtitle: String? get() = when (this) {
    is FeedItem.MarkerItem -> marker.scene?.displayTitle.let { if (it == tvTitle) marker.scene?.date else it }
    is FeedItem.SceneItem -> scene.date
    is FeedItem.PreviewItem -> scene.date
    is FeedItem.ClipItem -> image.date
}

/** iOS `TVFeedItem.studio` (markers carry none). */
val FeedItem.tvStudio: Pair<String, String>? get() = when (this) {
    is FeedItem.SceneItem -> scene.studio?.let { it.id to it.name }
    is FeedItem.PreviewItem -> scene.studio?.let { it.id to it.name }
    is FeedItem.MarkerItem -> null
    is FeedItem.ClipItem -> image.studio?.let { s -> s.name?.let { s.id to it } }
}

/** iOS `TVFeedItem.underlyingScene`: what "Play" and "Scene Details" act on. */
val FeedItem.tvScene: de.letzgo.stashy.data.Scene? get() = when (this) {
    is FeedItem.SceneItem -> scene
    is FeedItem.PreviewItem -> scene
    is FeedItem.MarkerItem -> marker.scene
    is FeedItem.ClipItem -> null
}

/** iOS `playCreditSceneId`: scenes and markers credit a play to their scene, previews and clips none. */
private val FeedItem.creditSceneId: String? get() = when (this) {
    is FeedItem.SceneItem -> scene.id
    is FeedItem.MarkerItem -> marker.scene?.id
    else -> null
}

/** iOS `fallbackSources`: full scenes and markers fall back to the server transcodes; previews and clips are their own file. */
private val FeedItem.fallbacks: List<String> get() = when (this) {
    is FeedItem.SceneItem -> scene.transcodeFallbackURLs
    is FeedItem.MarkerItem -> marker.scene?.transcodeFallbackURLs.orEmpty()
    else -> emptyList()
}

private val FeedItem.declaredDuration: Double? get() = when (this) {
    is FeedItem.SceneItem -> scene.sceneDuration
    is FeedItem.MarkerItem -> marker.scene?.sceneDuration
    else -> null
}

/**
 * iOS `TVFeedChannelStart` — a channel opens Feeds as a starting point: Scenes with the channel's
 * saved filter ([filter]) or entity criterion ([scope]) and sort. Switching modes in the overlay
 * goes back to the Feeds defaults.
 */
data class TvFeedChannelStart(val id: String, val title: String, val filter: SavedFilter?, val scope: JsonObject?, val sortRaw: String)

/** iOS `TVFeedDestination` — where the overlay navigates (the feed closes first). */
sealed class TvFeedDestination {
    data class Scene(val id: String) : TvFeedDestination()
    data class Performer(val id: String, val name: String) : TvFeedDestination()
    data class Studio(val id: String, val name: String) : TvFeedDestination()
}

/**
 * iOS: `TVFeedSession` — data + playback of Android TV Feeds. Pages come from the phone's Feeds
 * queries ([FeedsQuery] / [FeedsRepository]) with the per-mode Settings › Feeds defaults (sort,
 * saved filter). Playback runs on **one** [StashPlayer] that is handed from item to item, so only
 * the current item ever decodes: Fire TV sticks have 1–2 GB and often a single hardware decoder.
 * Nothing is preloaded; the player is released when the pager closes or the full player takes over.
 */
class TvFeedSession {
    companion object {
        private const val MUTED_KEY = "tvFeedsMuted"
        private val live = java.util.Collections.newSetFromMap(java.util.WeakHashMap<TvFeedSession, Boolean>())

        /** App left via Home: no feed keeps playing in the background (TvActivity.onStop). */
        fun pauseAll() = live.toList().forEach { it.player?.pause() }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** One mode's timeline (iOS: the catalog's `scenes` / `sceneMarkers` / `clips` / `previews`). */
    private class ModeList {
        val items = ArrayList<FeedItem>()
        var page = 0
        var hasMore = true
        var total = 0
        var key: String? = null
        /** Bumped per fetch; a cancelled fetch's `finally` must not touch its successor's state. */
        var token = 0
        var job: Job? = null
        var isFetching = false
        var error: String? = null
    }

    private val lists = TvFeedLogic.tvFeedModes.associateWith { ModeList() }

    var mode by mutableStateOf(TvFeedLogic.enabledModes(TabManager.enabledReelsModes).first()); private set
    /** Rows of the current mode (unplayable ones dropped). */
    val items = mutableStateListOf<FeedItem>()
    var index by mutableIntStateOf(0); private set
    /** The one player of the feed; null while the pager is closed or the full player runs. */
    var player by mutableStateOf<StashPlayer?>(null); private set
    /** A new item is loading over the previous picture: the pager shows its poster. */
    var isSwitching by mutableStateOf(false); private set
    var isLoading by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    var isMuted by mutableStateOf(Prefs.bool(MUTED_KEY)); private set
    /** Set while the feed was started from a channel (Scenes only). */
    var channel by mutableStateOf<TvFeedChannelStart?>(null); private set
    /** Short-lived message (failed rating / O count write). */
    var message by mutableStateOf<String?>(null)

    /** Last item per mode, so mode switches and reopening land where the user left off. */
    private val positions = HashMap<ReelsModeType, String>()
    private val seeds = HashMap<ReelsModeType, Int>()
    /** Feeds start position per scene row, drawn once per timeline (a Random start stays put for its loop). */
    private val startPositions = HashMap<String, Double>()
    private val unplayable = HashSet<String>()
    private var isActive = false

    // Per-item playback state
    private val tracker = PlaybackActivityTracker(scope)
    private val credit = PlayCountCredit(0.0)
    private var creditedItemId: String? = null
    private var heldPlayDuration = 0.0
    private var segmentEndHandled = false
    private var generation = 0

    init { live.add(this) }

    val currentItem: FeedItem? get() = items.getOrNull(index)
    val canGoPrevious: Boolean get() = index > 0
    val canGoNext: Boolean get() = index + 1 < items.size

    val positionLabel: String get() {
        val total = when (mode) { ReelsModeType.Scenes, ReelsModeType.Previews -> lists.getValue(mode).total; else -> 0 }
        return TvFeedLogic.positionLabel(index, items.size, total)
    }

    // MARK: Lifecycle

    /** iOS `activate(channel:)` — a channel's pager opened: Scenes with its filter and sort, from the top. */
    fun activate(start: TvFeedChannelStart) {
        isActive = true
        rememberPosition()
        channel = start
        mode = ReelsModeType.Scenes
        positions.remove(ReelsModeType.Scenes)
        restore()
        fetchIfNeeded()
        playCurrent()
    }

    /** iOS `activate(mode:)` — the Feeds pager opened on [requested]. */
    fun activate(requested: ReelsModeType) {
        // Opened from Feeds itself: its own defaults, not a channel left from before.
        if (channel != null) { channel = null; lists.getValue(ReelsModeType.Scenes).key = null }
        isActive = true
        if (requested != mode) {
            rememberPosition()
            mode = requested
        }
        restore()
        fetchIfNeeded()
        playCurrent()
    }

    /** The pager closed: release the player. List and position stay for the next visit. */
    fun deactivate() {
        rememberPosition()
        isActive = false
        releasePlayer()
    }

    /** iOS `suspendForFullPlayer` — the scene player takes over: free the decoder until it returns. */
    fun suspendForFullPlayer() = releasePlayer()

    fun resumeAfterFullPlayer() { if (isActive) playCurrent() }

    /**
     * Server switch / session gone for good. The scope stays alive: the last resume / watch-time
     * save launched by [deactivate] must still reach the server.
     */
    fun dispose() {
        deactivate()
        lists.values.forEach { it.job?.cancel() }
        live.remove(this)
    }

    private fun releasePlayer() {
        tracker.reset()
        generation++
        errorWatch?.cancel(); errorWatch = null
        player?.let { p ->
            p.onTime = null; p.onReachedEnd = null; p.onFirstFrame = null; p.onPlayingChanged = null
            p.release()
        }
        player = null
        isSwitching = false
    }

    // MARK: Modes

    /** iOS `switchMode(to:)` — a channel is only the starting point: other modes use the Feeds defaults. */
    fun switchMode(to: ReelsModeType) {
        if (to == mode) return
        rememberPosition()
        if (channel != null) { channel = null; lists.getValue(ReelsModeType.Scenes).key = null }
        mode = to
        restore()
        fetchIfNeeded()
        if (currentItem != null) playCurrent() else releasePlayer()
    }

    private fun rememberPosition() { currentItem?.id?.let { positions[mode] = it } }

    /** Re-reads the (possibly still warm) list of the current mode and its last position. */
    private fun restore() {
        items.clear()
        items.addAll(buildItems())
        index = positions[mode]?.let { id -> items.indexOfFirst { it.id == id }.takeIf { it >= 0 } } ?: 0
        updateLoadingState()
    }

    // MARK: Data

    private fun list(m: ReelsModeType = mode) = lists.getValue(m)

    private fun sortFor(m: ReelsModeType, raw: String?): FeedSort = when (m) {
        ReelsModeType.Markers -> SceneMarkerSortOption.from(raw) ?: SceneMarkerSortOption.random
        ReelsModeType.Clips -> ImageSortOption.from(raw) ?: ImageSortOption.random
        else -> SceneSortOption.from(raw) ?: SceneSortOption.random
    }

    private fun kind(m: ReelsModeType) = when (m) {
        ReelsModeType.Markers -> FeedQueryKind.Markers
        ReelsModeType.Clips -> FeedQueryKind.Clips
        ReelsModeType.Previews -> FeedQueryKind.Previews
        else -> FeedQueryKind.Scenes
    }

    private fun seed(m: ReelsModeType) = seeds.getOrPut(m) { Random.nextInt(1, 1_000_000) }

    /** iOS `fetchIfNeeded` — page 1 of the current mode with its defaults, unless the list holds it. */
    fun fetchIfNeeded(force: Boolean = false) {
        val m = mode
        val ch = if (m == ReelsModeType.Scenes) channel else null
        val filterId = if (ch == null) FeedsConfig.defaultFilterId(m) else null
        val sortRaw = ch?.sortRaw ?: FeedsConfig.defaultSort(m) ?: "random"
        val key = TvFeedLogic.loadKey(ch?.id, ch?.sortRaw, sortRaw, filterId)
        val l = list(m)
        if (!force && l.key == key && (l.items.isNotEmpty() || l.isFetching)) { refresh(); return }
        l.job?.cancel()
        l.key = key
        val token = ++l.token
        l.items.clear(); l.page = 0; l.hasMore = true; l.total = 0; l.error = null
        l.isFetching = true
        positions.remove(m)
        unplayable.clear()
        if (m == ReelsModeType.Scenes) startPositions.clear()
        errorMessage = null
        refresh()
        l.job = scope.launch {
            try {
                // The default filter is a saved filter: wait for the server's list once.
                val filter = when {
                    ch != null -> ch.filter
                    filterId != null -> { SavedFiltersStore.load(); while (SavedFiltersStore.isLoading) delay(50); SavedFiltersStore.byId[filterId] }
                    else -> null
                }
                val page = fetchPage(m, 1, sortFor(m, sortRaw), filter, ch?.scope)
                l.items.addAll(page.first); l.page = 1; l.hasMore = page.second; l.total = page.third
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                l.error = e.message ?: tr(R.string.unknown_error)
            } finally {
                if (l.token == token) l.isFetching = false
            }
            if (m == mode) refresh()
        }
    }

    /** iOS `reload` — "Reshuffle": a fresh random order (or page 1 again) from the top. */
    fun reload() {
        seeds[mode] = Random.nextInt(1, 1_000_000)
        fetchIfNeeded(force = true)
    }

    private fun loadMoreIfNeeded() {
        val m = mode
        val l = list(m)
        if (!TvFeedLogic.needsMore(index, items.size) || l.isFetching || !l.hasMore || l.page == 0) return
        val ch = if (m == ReelsModeType.Scenes) channel else null
        val filterId = if (ch == null) FeedsConfig.defaultFilterId(m) else null
        val sort = sortFor(m, ch?.sortRaw ?: FeedsConfig.defaultSort(m))
        val token = ++l.token
        val next = l.page + 1
        l.isFetching = true
        l.job = scope.launch {
            try {
                val filter = ch?.filter ?: filterId?.let { SavedFiltersStore.byId[it] }
                val (fresh, more, total) = fetchPage(m, next, sort, filter, ch?.scope)
                if (l.token != token) return@launch
                val existing = l.items.map { it.id }.toHashSet()
                val added = fresh.filter { it.id !in existing }
                l.items.addAll(added); l.page = next; l.total = total
                // A page that adds nothing new ends paging (iOS `noteFeedProgress`).
                l.hasMore = more && added.isNotEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                l.hasMore = false
            } finally {
                if (l.token == token) l.isFetching = false
            }
            if (m == mode) refresh()
        }
    }

    /** One page: rows, whether more exist, the server's total. Row rules as iOS `buildItems`. */
    private suspend fun fetchPage(m: ReelsModeType, page: Int, sort: FeedSort, filter: SavedFilter?, scopeFilter: JsonObject?): Triple<List<FeedItem>, Boolean, Int> {
        val per = FeedsQuery.PER_PAGE
        val vars = FeedsQuery.variables(kind(m), page, per, sort, seed(m), filter, scopeFilter)
        return when (m) {
            ReelsModeType.Markers -> FeedsRepository.markers(vars).let { p ->
                Triple(p.items.filter { it.scene != null }.map { FeedItem.MarkerItem(it) }, p.items.size == per, p.count)
            }
            ReelsModeType.Clips -> FeedsRepository.images(vars).let { p ->
                // GIF / WebP animations have no video track to play.
                Triple(p.items.map { FeedItem.ClipItem(it) }.filter { !it.isAnimated }, p.items.size == per, p.count)
            }
            ReelsModeType.Previews -> FeedsRepository.scenes(vars).let { p ->
                Triple(p.items.filter { !it.paths?.preview.isNullOrEmpty() }.map { FeedItem.PreviewItem(it) }, p.items.size == per, p.count)
            }
            else -> FeedsRepository.feedScenes(vars).let { p -> Triple(p.items.map { FeedItem.SceneItem(it) }, p.items.size == per, p.count) }
        }
    }

    private fun buildItems(): List<FeedItem> = list().items.filter { it.id !in unplayable }

    /** iOS `refreshFromCatalog` — rebuilds the visible rows after a page load. */
    private fun refresh() {
        val fresh = buildItems()
        val same = fresh.map { it.id } == items.map { it.id }
        updateLoadingState(fresh.isEmpty())
        if (same) return
        val currentId = currentItem?.id
        items.clear(); items.addAll(fresh)
        currentId?.let { id -> fresh.indexOfFirst { it.id == id }.takeIf { it >= 0 } }?.let {
            // A page was appended: the current item plays on.
            index = it
            return
        }
        // A new timeline: its first item, or the remembered one when it is in there.
        index = positions[mode]?.let { id -> fresh.indexOfFirst { it.id == id }.takeIf { it >= 0 } } ?: 0
        if (isActive) {
            when {
                currentItem != null -> playCurrent()
                // A new page 1 is on its way (Reshuffle): keep the player for it, just stop.
                list().isFetching -> player?.stop()
                else -> releasePlayer()
            }
        }
    }

    private fun updateLoadingState(empty: Boolean = items.isEmpty()) {
        val l = list()
        isLoading = empty && l.isFetching
        errorMessage = when {
            !empty -> null
            !l.isFetching && l.key != null -> l.error ?: tr(R.string.nothing_to_play_in_arg, mode.defaultTitle)
            else -> null
        }
    }

    // MARK: Navigation

    fun next() {
        if (!canGoNext) { loadMoreIfNeeded(); return }
        index++
        playCurrent()
    }

    fun previous() {
        if (!canGoPrevious) return
        index--
        playCurrent()
    }

    // MARK: Transport

    fun togglePlayPause() { player?.togglePlayPause() }
    fun play() { player?.play() }
    fun pause() { player?.pause() }

    /** iOS `seekRange`: a marker's segment, else the whole file. */
    val seekRange: ClosedFloatingPointRange<Double>? get() {
        val p = player ?: return null
        val item = currentItem ?: return null
        val seg = item.segment
        return TvFeedLogic.seekRange(seg?.start, seg?.end, p.duration)
    }

    fun seekBy(delta: Double) { player?.let { seekTo(it.currentTime + delta) } }

    fun seekTo(time: Double) {
        val p = player ?: return
        val range = seekRange ?: return
        val target = TvFeedLogic.clamp(time, range)
        segmentEndHandled = false
        credit.noteSeek()
        tracker.noteSeek(target)
        p.seek(target)
    }

    fun toggleMute() {
        isMuted = !isMuted
        Prefs.setBool(MUTED_KEY, isMuted)
        player?.isMuted = isMuted
    }

    // MARK: O count and rating

    /** One more O for the item's scene (also a marker's or a preview's) or the clip's image. */
    fun addO(item: FeedItem) {
        val sceneId = item.sceneID
        val imageId = (item as? FeedItem.ClipItem)?.image?.id
        scope.launch {
            val count = when {
                sceneId != null -> FeedsRepository.mutateOCounter(sceneId, isImage = false, FeedsRepository.OMutation.Increment)
                imageId != null -> FeedsRepository.mutateOCounter(imageId, isImage = true, FeedsRepository.OMutation.Increment)
                else -> return@launch
            }
            if (count == null) { message = tr(R.string.error_counter_update); return@launch }
            patch(sceneId, imageId) { it.withOCounter(count) }
        }
    }

    /** [stars] 0…5, 0 clears the rating. */
    fun setRating(stars: Int, item: FeedItem) {
        val value = TvFeedLogic.rating100(stars)
        val sceneId = item.sceneID
        val imageId = (item as? FeedItem.ClipItem)?.image?.id
        scope.launch {
            val ok = when {
                sceneId != null -> FeedsRepository.updateSceneRating(sceneId, value)
                imageId != null -> FeedsRepository.updateImageRating(imageId, value)
                else -> return@launch
            }
            if (!ok) { message = tr(R.string.error_save_rating); return@launch }
            patch(sceneId, imageId) { it.withRating(value) }
        }
    }

    /** Replaces every row of every mode that shows that scene or image (the visible rows included). */
    private fun patch(sceneId: String?, imageId: String?, transform: (FeedItem) -> FeedItem) {
        fun hits(it: FeedItem) = (sceneId != null && it.sceneID == sceneId) || (imageId != null && (it as? FeedItem.ClipItem)?.image?.id == imageId)
        lists.values.forEach { l -> for (i in l.items.indices) if (hits(l.items[i])) l.items[i] = transform(l.items[i]) }
        for (i in items.indices) if (hits(items[i])) items[i] = transform(items[i])
    }

    private fun FeedItem.withOCounter(count: Int): FeedItem = when (this) {
        is FeedItem.SceneItem -> FeedItem.SceneItem(scene.copy(oCounter = count))
        is FeedItem.PreviewItem -> FeedItem.PreviewItem(scene.copy(oCounter = count))
        is FeedItem.MarkerItem -> FeedItem.MarkerItem(marker.copy(scene = marker.scene?.copy(oCounter = count)))
        is FeedItem.ClipItem -> FeedItem.ClipItem(image.copy(oCounter = count))
    }

    private fun FeedItem.withRating(rating100: Int?): FeedItem = when (this) {
        is FeedItem.SceneItem -> FeedItem.SceneItem(scene.copy(rating100 = rating100))
        is FeedItem.PreviewItem -> FeedItem.PreviewItem(scene.copy(rating100 = rating100))
        is FeedItem.MarkerItem -> FeedItem.MarkerItem(marker.copy(scene = marker.scene?.copy(rating100 = rating100)))
        is FeedItem.ClipItem -> FeedItem.ClipItem(image.copy(rating100 = rating100))
    }

    // MARK: Playback

    /** Where a row starts and loops back to: the marker, or the scene's Feeds start position. */
    fun startTime(item: FeedItem): Double {
        item.segment?.let { return it.start }
        val scene = (item as? FeedItem.SceneItem)?.scene ?: return 0.0
        val setting = TabManager.feedsSceneStartPosition
        return startPositions.getOrPut("${setting.raw}|${scene.id}") { FeedStartPosition.forScene(scene, setting) }
    }

    private fun ensurePlayer(): StashPlayer? = player ?: try {
        StashPlayer(Prefs.appContext, StashPlayer.Role.Main).also { p ->
            p.onTime = { t, d -> onTime(p, t, d) }
            p.onReachedEnd = { onReachedEnd() }
            p.onFirstFrame = { isSwitching = false }
            p.onPlayingChanged = { playing -> if (!playing) tracker.stop() }
            player = p
            watchErrors(p)
        }
    } catch (e: Exception) {
        android.util.Log.e("TvFeeds", "player init failed", e)
        errorMessage = tr(R.string.hint_video_player_could_not_be, e.localizedMessage ?: e.javaClass.simpleName)
        null
    }

    /**
     * iOS `handleUnplayableItem`: an item the player cannot show even after the transcode ladder
     * is dropped after a short grace and the feed moves on, so a lean-back feed never stalls.
     */
    private var errorWatch: Job? = null

    private fun watchErrors(p: StashPlayer) {
        errorWatch?.cancel()
        errorWatch = scope.launch {
            snapshotFlow { p.errorMessage != null && !p.hasPresentedFrame }.collectLatest { failed ->
                if (!failed) return@collectLatest
                // Show the player's reason over the poster during the grace (iOS: the load returned).
                isSwitching = false
                val gen = generation
                delay(TvFeedLogic.UNPLAYABLE_GRACE_MS)
                if (gen == generation && player === p && p.errorMessage != null && !p.hasPresentedFrame) currentItem?.let { skipUnplayable(it) }
            }
        }
    }

    private fun playCurrent() {
        if (!isActive) return
        loadMoreIfNeeded()
        val item = currentItem ?: return
        rememberPosition()
        val url = item.videoURL ?: run { skipUnplayable(item); return }
        val p = ensurePlayer() ?: return

        generation++
        // Saves the outgoing item with its own rules, then tracks this one.
        configureTracking(item)
        credit.reset()
        credit.thresholdSeconds = maxOf(0.0, TabManager.playCountFeedsSeconds)
        creditedItemId = null
        segmentEndHandled = false
        isSwitching = true

        val start = startTime(item)
        p.isMuted = isMuted
        p.fallbackSources = item.fallbacks
        p.fallbackDeclaredDuration = item.declaredDuration
        p.loops = TvFeedLogic.playerLoops(item.segment != null, start, TabManager.reelsContinuousPlay)
        p.load(url, start.takeIf { it > 0.05 }, autoplay = true)
    }

    private fun configureTracking(item: FeedItem) {
        tracker.reset()
        heldPlayDuration = 0.0
        val sceneId = item.creditSceneId ?: run { tracker.onSave = null; return }
        val itemId = item.id
        // Markers only add watch time; the scene's resume point is not theirs to move.
        tracker.updatesResumeTime = item is FeedItem.SceneItem
        tracker.onSave = { resume, played ->
            if (played > 0 || resume != null) {
                if (creditedItemId != itemId) {
                    // Nothing is written before the item counts as played; the time is held.
                    heldPlayDuration += maxOf(0.0, played)
                } else {
                    val total = played + heldPlayDuration
                    heldPlayDuration = 0.0
                    scope.launch {
                        val ok = runCatching { SceneEditing.saveActivity(sceneId, resume, total) }.isSuccess
                        if (ok && resume != null) SceneEvents.post(SceneEvent.ResumeTimeUpdated(sceneId, resume))
                    }
                }
            }
        }
    }

    private fun skipUnplayable(item: FeedItem) {
        android.util.Log.d("TvFeeds", "no playable source for ${item.id} — skipping")
        unplayable.add(item.id)
        val removed = index
        items.clear(); items.addAll(buildItems())
        index = TvFeedLogic.indexAfterRemoval(removed, items.size)
        if (currentItem != null) playCurrent() else { releasePlayer(); updateLoadingState() }
    }

    private fun onTime(p: StashPlayer, time: Double, duration: Double) {
        // The outgoing item's clock is not this item's playhead.
        if (isSwitching || !p.hasFirstFrame || time < 0) return
        val item = currentItem ?: return

        // Count as played — Feeds: real watching time only.
        val sceneId = item.creditSceneId
        if (sceneId != null && creditedItemId != item.id &&
            credit.onTime(time, p.isPlaying, SystemClock.elapsedRealtime() / 1000.0)
        ) {
            creditedItemId = item.id
            scope.launch { FeedsRepository.addScenePlay(sceneId) }
            // Counts as played now: the held time goes out at once.
            tracker.flush()
        }
        if (sceneId != null) {
            tracker.setPosition(time, if (duration > 0) duration else item.declaredDuration ?: 0.0)
            if (p.isPlaying) tracker.start()
        }

        // Marker rows end at their segment end: continuous play moves on, otherwise loop.
        val seg = item.segment
        if (seg != null && !segmentEndHandled && TvFeedLogic.reachedSegmentEnd(time, seg.end)) {
            segmentEndHandled = true
            atEnd()
        }
    }

    private fun onReachedEnd() { if (!isSwitching) atEnd() }

    private fun atEnd() = when (TvFeedLogic.endAction(TabManager.reelsContinuousPlay, canGoNext)) {
        TvFeedLogic.EndAction.Next -> next()
        TvFeedLogic.EndAction.Loop -> loopToStart()
    }

    private fun loopToStart() {
        val p = player ?: return
        val item = currentItem ?: return
        val start = startTime(item)
        credit.noteSeek()
        tracker.noteSeek(start)
        p.seek(start)
        p.play()
        segmentEndHandled = false
    }
}
