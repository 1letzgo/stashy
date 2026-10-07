package de.letzgo.stashy.ui.feeds

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.FeedCriteria
import de.letzgo.stashy.data.FeedQueryKind
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.FeedsQuery
import de.letzgo.stashy.data.FeedsRepository
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageSortOption
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SceneMarkerSortOption
import de.letzgo.stashy.data.SceneSortOption
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.await
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.Request
import androidx.compose.foundation.lazy.LazyListState
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.ListLivePresetTag
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.criteriaObjectFilter
import de.letzgo.stashy.data.encodedSortPair
import de.letzgo.stashy.data.filterMode
import de.letzgo.stashy.data.stashyMetadata
import de.letzgo.stashy.data.LocalFilterPreset
import de.letzgo.stashy.data.LocalFilterPresetStore
import de.letzgo.stashy.data.SavedFiltersRepository
import de.letzgo.stashy.data.SortOption
import de.letzgo.stashy.data.mergedObjectFilterForSave
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.data.tools.AITagUpdateEvent
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.catalog.ImageMediaKindHolder
import kotlin.random.Random

/** One mode's timeline (iOS: `viewModel.scenes` / `sceneMarkers` / `clips` / `previews` + paging flags). */
class FeedList {
    val items = mutableStateListOf<FeedItem>()
    var isLoading by mutableStateOf(false)
    var isLoadingMore by mutableStateOf(false)
    var hasMore by mutableStateOf(true)
    var error by mutableStateOf<String?>(null)
    var loadedOnce by mutableStateOf(false)
    /** Bumped on every page-1 fetch, so the pager jumps to the new first row. */
    var generation by mutableStateOf(0)
    var page = 0
    /** Criteria identity of the loaded timeline (iOS `ReelsFeedSignature`, warm feeds). */
    var signature: String? = null
    var job: Job? = null
}

/**
 * Session state of the Feeds tab (iOS: `ReelsViewBody` @State + `ReelsSessionRAM` + the Reels
 * part of `StashDBViewModel`). RAM only: survives tab switches and pushes, not an app restart —
 * like iOS. Per server: a server switch resets everything.
 */
object FeedsModel {
    private val scope = MainScope()
    private var serverId: String? = null

    var mode by mutableStateOf(ReelsModeType.Scenes)
        private set
    private val lists = ReelsModeType.entries.associateWith { FeedList() }
    fun list(m: ReelsModeType = mode): FeedList = lists.getValue(m)

    // Per-mode selections (iOS: selectedSortOption / selectedMarkerSortOption / clip & pics models).
    val sorts = mutableStateMapOf<ReelsModeType, FeedSort>()
    val filters = mutableStateMapOf<ReelsModeType, SavedFilter>()
    /** Advanced criteria per mode (iOS `FilterCriteriaDocument`) — filled by the `ui/filter` editor hook. */
    val advanced = mutableStateMapOf<ReelsModeType, JsonObject>()
    /** iOS: selectedPerformer / selectedTags / selectedStudio (shared across modes). */
    var criteria by mutableStateOf(FeedCriteria())
        private set

    // MARK: - Pics (iOS: `reelsPicsFilters` + `reelsPicsViewModel` driving the embedded `ImagesView`)

    /** iOS `DetailLinkedImagesFilterModel.liveFilterMediaKind` of the Pics sheet ("Type"). */
    val picsKind = ImageMediaKindHolder()

    /**
     * Pics runs the Images catalog's own controller (sort, saved filter / local preset, criteria
     * editor, paging) like iOS embeds `ImagesView` with `reelsPicsFilters`: session sort starts
     * at the Pics default sort (Settings › Feeds, `dateDesc`) and is not written to the Images
     * tab; the handed performer / tags / studio and the "Type" chip are layered on top.
     */
    var pics by mutableStateOf(makePics())
        private set
    /** Scroll position of the Pics list (iOS keeps `lastOpenedImageId`; RAM like the rest). */
    var picsListState = LazyListState()
        private set
    private var picsBootstrapped = false

    private fun makePics(): CatalogController<StashImage> = CatalogController(
        FilterMode.Images, scope, tabId = null,
        initialSort = SortCatalog.option(FilterMode.Images, defaultSort(ReelsModeType.Pics).raw),
        extraLive = { picsLive() },
        persistSort = {},
    )

    private fun picsLive(): JsonObject {
        val out = LinkedHashMap<String, JsonElement>()
        picsKind.kind.pathCriterion?.let { out["path"] = it }
        FeedsQuery.applyCriteria(out, criteria, FeedQueryKind.Pics)
        return JsonObject(out)
    }

    private fun resetPics() {
        pics = makePics()
        picsKind.kind = de.letzgo.stashy.ui.filter.ImageListMediaKind.All
        picsListState = LazyListState()
        picsBootstrapped = false
    }

    /**
     * First show of Pics: the Images tab's Settings default filter (iOS
     * `bootstrapReelsPicsFiltersIfNeeded`) unless criteria were handed in — then Filter = None
     * (`suppressSettingsDefaultFilter`).
     */
    fun ensurePicsLoaded() {
        if (picsBootstrapped) {
            if (!pics.list.loadedOnce && !pics.list.isLoading) pics.refresh()
            return
        }
        picsBootstrapped = true
        val controller = pics
        scope.launch {
            SavedFiltersStore.load()
            val defId = FeedsConfig.defaultFilterId(ReelsModeType.Pics)
            val def = defId?.let { SavedFiltersStore.byId[it] }
            if (def != null && criteria.isEmpty && controller.presetRow.isEmpty()) controller.selectPresetRow(ListLivePresetTag.serverRow(def.id))
            else controller.refresh()
        }
    }

    /**
     * Handed criteria changed while on Pics (iOS `applyPerformerFilter` / `applyTagsChange` /
     * `applyClear…` `.pics` branches): a handed criterion drops the filter and editor
     * (`reelsPicsApplyHandedCriteria(onTopOf: nil)`); clearing the last one restores the Settings
     * default filter (`reelsPicsRestoreDefaultFilterAfterDeepLinkIfNeeded`).
     */
    private fun picsCriteriaChanged() {
        if (!criteria.isEmpty) {
            if (pics.presetRow.isNotEmpty() || pics.selectedFilter != null || !pics.criteria.isEmpty) { pics.reset(); return }
        } else if (pics.selectedFilter == null && pics.presetRow.isEmpty()) {
            FeedsConfig.defaultFilterId(ReelsModeType.Pics)?.let { SavedFiltersStore.byId[it] }?.let {
                pics.selectPresetRow(ListLivePresetTag.serverRow(it.id)); return
            }
        }
        pics.refresh()
    }

    /** Optimistic edit of one Pics image (rating / O-counter from a post). */
    fun patchPicsImage(image: StashImage) = pics.list.patch { if (it.id == image.id) image else it }

    /** iOS: `currentVisibleSceneId` per mode (session position). */
    val currentIds = mutableStateMapOf<ReelsModeType, String>()
    /**
     * Start position per Scenes row ([FeedStartPosition]), keyed by row id and setting — computed
     * once per feed session so a Random start stays put for the row and its loop. Never written
     * to the server as a resume time.
     */
    private val startPositions = HashMap<String, Double>()

    fun startPosition(item: FeedItem): Double {
        val scene = (item as? FeedItem.SceneItem)?.scene ?: return 0.0
        val setting = de.letzgo.stashy.data.TabManager.feedsSceneStartPosition
        return startPositions.getOrPut("${item.id}|${setting.raw}") { FeedStartPosition.forScene(scene, setting) }
    }

    /** iOS: playback checkpoint `itemId|seconds`. */
    var checkpoint: Pair<String, Double>? = null

    /** iOS: `unplayableItemIds` / `mediaProbedItemIds`. */
    val unplayable = mutableStateMapOf<String, Boolean>()
    private val probed = HashSet<String>()

    private val seeds = HashMap<ReelsModeType, Int>()
    var savedFilters by mutableStateOf<List<SavedFilter>>(emptyList())
        private set
    private var savedFiltersLoaded = false
    private var initialized = false

    /** iOS: `currentItemIsPlaying` (play intent of the active row). */
    var isPlaying by mutableStateOf(true)
    /** iOS: `isMuted` — set from [FeedAudio] on first show. */
    var isMuted by mutableStateOf<Boolean?>(null)

    private fun seed(m: ReelsModeType): Int = seeds.getOrPut(m) { Random.nextInt(1, 1_000_000) }
    private fun reseed(m: ReelsModeType) { seeds[m] = Random.nextInt(1, 1_000_000) }

    fun sort(m: ReelsModeType = mode): FeedSort = sorts[m] ?: defaultSort(m)

    /** iOS: `getReelsDefaultSort(for:) ?? .random` (Pics: `.dateDesc`). */
    fun defaultSort(m: ReelsModeType): FeedSort {
        val raw = FeedsConfig.defaultSort(m)
        return when (m) {
            ReelsModeType.Scenes, ReelsModeType.Previews -> SceneSortOption.from(raw) ?: SceneSortOption.random
            ReelsModeType.Markers -> SceneMarkerSortOption.from(raw) ?: SceneMarkerSortOption.random
            ReelsModeType.Clips -> ImageSortOption.from(raw) ?: ImageSortOption.random
            ReelsModeType.Pics -> ImageSortOption.from(raw) ?: ImageSortOption.dateDesc
        }
    }

    /** All sort options of a mode, for the sheet. */
    fun sortOptions(m: ReelsModeType): List<FeedSort> = when (m) {
        ReelsModeType.Scenes, ReelsModeType.Previews -> SceneSortOption.entries
        ReelsModeType.Markers -> SceneMarkerSortOption.entries
        ReelsModeType.Clips, ReelsModeType.Pics -> ImageSortOption.entries
    }

    /** Saved-filter mode string a Feeds mode accepts (iOS: scenes/previews → SCENES …). */
    fun filterModeFor(m: ReelsModeType): String = when (m) {
        ReelsModeType.Scenes, ReelsModeType.Previews -> "SCENES"
        ReelsModeType.Markers -> "SCENE_MARKERS"
        ReelsModeType.Clips, ReelsModeType.Pics -> "IMAGES"
    }

    fun filtersFor(m: ReelsModeType): List<SavedFilter> =
        savedFilters.filter { it.mode == filterModeFor(m) }.sortedBy { it.name.lowercase() }

    private fun kind(m: ReelsModeType) = when (m) {
        ReelsModeType.Scenes -> FeedQueryKind.Scenes
        ReelsModeType.Markers -> FeedQueryKind.Markers
        ReelsModeType.Clips -> FeedQueryKind.Clips
        ReelsModeType.Previews -> FeedQueryKind.Previews
        ReelsModeType.Pics -> FeedQueryKind.Pics
    }

    /** Rows the pager shows (iOS `currentReelItems`; dead preview rows dropped). */
    fun visibleItems(m: ReelsModeType = mode): List<FeedItem> = list(m).items.filter { it.id !in unplayable }

    private fun signature(m: ReelsModeType): String = listOf(
        m.name, sort(m).raw, seed(m), filters[m]?.id, advanced[m]?.toString(),
        criteria.performer?.id, criteria.tags.joinToString(",") { it.id }, criteria.studio?.id,
    ).joinToString("|")

    // MARK: - Lifecycle

    /** iOS: `handleOnAppear` (first show) / `reelsResumePlaybackAfterReturn` (later shows). */
    fun onAppear() {
        val sid = ServerConfigManager.activeConfig?.id
        if (sid != serverId) resetForServer(sid)
        if (!savedFiltersLoaded) refreshSavedFilters()
        if (initialized) {
            isPlaying = true
            return
        }
        initialized = true
        val enabled = FeedsConfig.enabledModes
        if (mode !in enabled) mode = enabled.firstOrNull() ?: ReelsModeType.Scenes
        ensureLoaded(mode)
    }

    private fun resetForServer(sid: String?) {
        serverId = sid
        initialized = false
        savedFiltersLoaded = false
        savedFilters = emptyList()
        lists.values.forEach { it.job?.cancel(); it.items.clear(); it.loadedOnce = false; it.signature = null; it.page = 0; it.error = null }
        sorts.clear(); filters.clear(); advanced.clear(); criteriaDocs.clear(); presetRows.clear(); currentIds.clear(); unplayable.clear(); probed.clear(); seeds.clear()
        criteria = FeedCriteria()
        checkpoint = null
        startPositions.clear()
        resetPics()
        mode = FeedsConfig.enabledModes.firstOrNull() ?: ReelsModeType.Scenes
    }

    private fun refreshSavedFilters(then: (() -> Unit)? = null) {
        scope.launch {
            runCatching { FeedsRepository.savedFilters() }.onSuccess {
                savedFilters = it
                savedFiltersLoaded = true
            }
            then?.invoke()
            // iOS `handleSavedFiltersChanged`: a default filter can only be applied once the list is in.
            applyDefaultFilterIfPending()
        }
    }

    private val awaitingDefaultFilter = HashSet<ReelsModeType>()

    /** Default filter of the mode (Settings), resolved against the loaded saved filters. */
    private fun defaultFilter(m: ReelsModeType): SavedFilter? =
        FeedsConfig.defaultFilterId(m)?.let { id -> savedFilters.firstOrNull { it.id == id } }

    /**
     * Cold start of a mode: Settings default sort + default filter, then fetch. When a default
     * filter is configured but the saved filters are still loading, the fetch waits for them
     * (iOS: "Wait for onChange(of: viewModel.savedFilters)").
     */
    fun ensureLoaded(m: ReelsModeType, applyDefaultFilter: Boolean = criteria.isEmpty) {
        if (m == ReelsModeType.Pics) { ensurePicsLoaded(); return }
        val l = list(m)
        if (l.loadedOnce || l.isLoading) {
            if (l.signature == signature(m)) return
        }
        if (m !in filters && applyDefaultFilter && FeedsConfig.defaultFilterId(m) != null) {
            val def = defaultFilter(m)
            if (def == null && !savedFiltersLoaded) {
                awaitingDefaultFilter.add(m)
                l.isLoading = true
                return
            }
            def?.let { filters[m] = it }
        }
        refetch(m)
    }

    private fun applyDefaultFilterIfPending() {
        val pending = awaitingDefaultFilter.toList()
        awaitingDefaultFilter.clear()
        pending.forEach { m ->
            defaultFilter(m)?.let { filters[m] = it }
            refetch(m)
        }
    }

    // MARK: - Fetching

    /** Page-1 fetch of a mode (iOS `applySettings` → `fetchScenes` & co). */
    fun refetch(m: ReelsModeType = mode, reroll: Boolean = false, keepPosition: Boolean = false) {
        if (m == ReelsModeType.Pics) {
            if (reroll && pics.sort.isRandom) de.letzgo.stashy.data.RandomSeeds.refresh(FilterMode.Images)
            pics.refresh()
            return
        }
        if (reroll && sort(m).isRandom) reseed(m)
        val l = list(m)
        l.job?.cancel()
        if (!keepPosition) currentIds.remove(m)
        // A new Scenes timeline is a new feed session: start positions are drawn again.
        if (m == ReelsModeType.Scenes && !keepPosition) startPositions.clear()
        // A fresh fetch may well bring items whose files exist now.
        if (m == mode) { unplayable.clear(); probed.clear() }
        l.isLoading = true
        l.isLoadingMore = false
        l.error = null
        l.hasMore = true
        val sig = signature(m)
        l.signature = sig
        l.job = scope.launch {
            try {
                val items = fetchPage(m, 1)
                l.items.clear()
                l.items.addAll(items.first)
                l.page = 1
                l.hasMore = items.second
                l.generation++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                l.error = e.message ?: "Unknown error"
                l.signature = null
            } finally {
                l.loadedOnce = true
                l.isLoading = false
            }
        }
    }

    /** iOS `loadMoreScenes` & co. */
    fun loadMore(m: ReelsModeType = mode) {
        if (m == ReelsModeType.Pics) { pics.list.loadMore(); return }
        val l = list(m)
        if (l.isLoading || l.isLoadingMore || !l.hasMore || !l.loadedOnce) return
        l.isLoadingMore = true
        val next = l.page + 1
        l.job = scope.launch {
            try {
                val (items, more) = fetchPage(m, next)
                val existing = l.items.map { it.id }.toHashSet()
                val fresh = items.filter { it.id !in existing }
                l.items.addAll(fresh)
                l.page = next
                // iOS `noteFeedProgress`: a page that adds nothing new ends paging.
                l.hasMore = more && fresh.isNotEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                l.hasMore = false
            } finally {
                l.isLoadingMore = false
            }
        }
    }

    /** Returns the page's rows and whether more pages exist (iOS: `count == perPage`). */
    private suspend fun fetchPage(m: ReelsModeType, page: Int): Pair<List<FeedItem>, Boolean> {
        val per = FeedsQuery.PER_PAGE
        // iOS `fetchBaseFilter`: once the editor holds the filter's criteria, only they are sent.
        val base = if (advanced[m] != null) null else filters[m]
        val vars = FeedsQuery.variables(kind(m), page, per, sort(m), seed(m), base, advanced[m], criteria)
        return when (m) {
            ReelsModeType.Scenes -> FeedsRepository.feedScenes(vars).let { p -> p.items.map { FeedItem.SceneItem(it) } to (p.items.size == per) }
            ReelsModeType.Previews -> FeedsRepository.scenes(vars).let { p ->
                // iOS: only scenes the server actually has a preview for.
                p.items.filter { !it.paths?.preview.isNullOrEmpty() }.map { FeedItem.PreviewItem(it) } to (p.items.size == per)
            }
            ReelsModeType.Markers -> FeedsRepository.markers(vars).let { p ->
                // Markers play their scene's original file, so no generated marker stream is
                // needed; only a marker without a scene still relies on it.
                p.items.filter { it.scene != null || !it.stream.isNullOrEmpty() }.map { FeedItem.MarkerItem(it) } to (p.items.size == per)
            }
            ReelsModeType.Clips, ReelsModeType.Pics -> FeedsRepository.images(vars).let { p -> p.items.map { FeedItem.ClipItem(it) } to (p.items.size == per) }
        }
    }

    // MARK: - Mode / sort / filter (iOS sheet + dock)

    /** iOS: `handleModeChange` — session sort/filter of the new mode stay, warm feeds are reused. */
    fun selectMode(m: ReelsModeType) {
        if (m == mode) return
        mode = m
        isPlaying = true
        unplayable.clear(); probed.clear()
        ensureLoaded(m)
    }

    fun setSort(m: ReelsModeType, sort: FeedSort) {
        val reroll = sort.isRandom && sort(m).isRandom
        sorts[m] = sort
        refetch(m, reroll = reroll)
    }

    fun setFilter(m: ReelsModeType, filter: SavedFilter?) {
        presetRows.remove(m)
        if (filter == null) filters.remove(m) else filters[m] = filter
        // iOS: picking a filter reloads the editor from it; "None" empties it.
        advanced.remove(m)
        criteriaDocs.remove(m)
        refetch(m)
    }

    /**
     * iOS `reelsCriteriaDocument` / `reelsMarkerCriteriaDocument` (+ the clip model's document):
     * the editor's copy of the selected filter's criteria (`reelsLoadCriteriaDocumentIfEmpty`).
     * Once edited, [advanced] holds the whole document and the filter is no longer sent as base
     * (iOS `fetchBaseFilter`), so removing one of its criteria in the editor takes effect.
     */
    private val criteriaDocs = HashMap<ReelsModeType, de.letzgo.stashy.data.CriteriaDocument>()

    fun criteriaDocument(m: ReelsModeType): de.letzgo.stashy.data.CriteriaDocument = criteriaDocs.getOrPut(m) {
        val fm = when (m) {
            ReelsModeType.Markers -> FilterMode.SceneMarkers
            ReelsModeType.Clips, ReelsModeType.Pics -> FilterMode.Images
            else -> FilterMode.Scenes
        }
        de.letzgo.stashy.data.CriteriaDocument(fm, pinsDefaults = true).also { doc ->
            val source = advanced[m] ?: filters[m]?.let { f ->
                val merged = LinkedHashMap<String, JsonElement>(f.criteriaObjectFilter())
                f.stashyMetadataLive()?.let { live -> merged.putAll(de.letzgo.stashy.data.FilterMapper.sanitize(live, m == ReelsModeType.Markers)) }
                JsonObject(merged)
            }
            source?.let { doc.load(it) }
        }
    }

    private fun SavedFilter.stashyMetadataLive(): JsonObject? = FeedsQuery.stashyLiveFragment(this)?.takeIf { it.isNotEmpty() }

    /** Editor change → the document replaces the criteria and the filter base (refetch). */
    fun applyCriteriaDocument(m: ReelsModeType) {
        val doc = criteriaDocs[m] ?: return
        val dict = doc.sanitizedObjectFilter
        advanced[m] = dict
        refetch(m)
    }

    /** Hook for the advanced criteria editor (`ui/filter`): replaces the mode's criteria and refetches. */
    fun setAdvancedCriteria(m: ReelsModeType, criteria: JsonObject?) {
        if (criteria == null || criteria.isEmpty()) advanced.remove(m) else advanced[m] = criteria
        refetch(m)
    }

    /** iOS sheet "Reset": no filter, no criteria; sort stays. */
    fun reset(m: ReelsModeType) {
        filters.remove(m); advanced.remove(m); criteriaDocs.remove(m); presetRows.remove(m)
        refetch(m)
    }

    // MARK: - Presets (iOS `reelsSaveSceneLivePresetOverwrite` / `…As` / `reelsRenameSceneLivePreset` /
    // `reelsDeleteSceneLivePreset`, the clip model's `savePresetOverwrite` & co.)

    /**
     * Selected row of the sheet's Filter picker per mode (`""` | `server:<id>` | `local:<uuid>`,
     * iOS `ListLivePresetTag`). Only a local preset needs an entry; a server filter is derived
     * from [filters].
     */
    private val presetRows = mutableStateMapOf<ReelsModeType, String>()
    /** Bumped when a mode's on-device presets change, so the sheet re-reads them. */
    var localPresetsVersion by mutableStateOf(0)
        private set

    /** Catalog list whose filters / presets a Feeds mode shares (Scenes & Previews → scenes …). */
    fun filterMode(m: ReelsModeType): FilterMode = when (m) {
        ReelsModeType.Markers -> FilterMode.SceneMarkers
        ReelsModeType.Clips, ReelsModeType.Pics -> FilterMode.Images
        else -> FilterMode.Scenes
    }

    fun presetRow(m: ReelsModeType): String =
        presetRows[m] ?: filters[m]?.let { ListLivePresetTag.serverRow(it.id) } ?: ""

    /** On-device presets of the mode's list (same store as the catalog sheet). */
    fun localPresets(m: ReelsModeType): List<LocalFilterPreset> {
        localPresetsVersion // read so callers recompose after a change
        return LocalFilterPresetStore.load(filterMode(m))
    }

    fun presetName(m: ReelsModeType): String? {
        val row = presetRow(m)
        ListLivePresetTag.parseServerId(row)?.let { sid -> return savedFilters.firstOrNull { it.id == sid }?.name ?: filters[m]?.name }
        ListLivePresetTag.parseLocalId(row)?.let { lid -> return localPresets(m).firstOrNull { it.id == lid }?.name }
        return null
    }

    /** Sort of a raw value in the mode's enum (`sortRaw` of a preset / stashy filter). */
    private fun feedSort(m: ReelsModeType, raw: String?): FeedSort? = when (m) {
        ReelsModeType.Scenes, ReelsModeType.Previews -> SceneSortOption.from(raw)
        ReelsModeType.Markers -> SceneMarkerSortOption.from(raw)
        ReelsModeType.Clips, ReelsModeType.Pics -> ImageSortOption.from(raw)
    }

    /** iOS `reelsHandleScenePresetSelectionChange`. */
    fun selectPresetRow(m: ReelsModeType, row: String) {
        ListLivePresetTag.parseServerId(row)?.let { sid ->
            val f = savedFilters.firstOrNull { it.id == sid } ?: return
            // iOS `reelsApplyServerSceneSavedFilterForReels`: a stashy filter brings its sort.
            feedSort(m, FeedsQuery.stashySortRaw(f))?.let { sorts[m] = it }
            setFilter(m, f)
            return
        }
        val lid = ListLivePresetTag.parseLocalId(row)
        val preset = lid?.let { id -> localPresets(m).firstOrNull { it.id == id } }
        if (preset == null) { setFilter(m, null); return }
        // iOS `reelsApplyLiveScenePresetForReels`: sort, base filter, then the fragment on top.
        feedSort(m, preset.sortRaw)?.let { sorts[m] = it }
        val base = preset.baseSavedFilterId?.let { id -> savedFilters.firstOrNull { it.id == id } }
        if (base == null) filters.remove(m) else filters[m] = base
        presetRows[m] = row
        val merged = LinkedHashMap<String, JsonElement>(base?.criteriaObjectFilter() ?: JsonObject(emptyMap()))
        merged.putAll(de.letzgo.stashy.data.FilterMapper.sanitize(preset.liveFragment, m == ReelsModeType.Markers))
        criteriaDocs.remove(m)
        val doc = criteriaDocument(m)
        doc.load(JsonObject(merged))
        val dict = doc.sanitizedObjectFilter
        if (dict.isEmpty()) advanced.remove(m) else advanced[m] = dict
        refetch(m)
    }

    /** iOS `reelsActivePresetLiveFragment` — the editor document of the mode. */
    private fun liveFragment(m: ReelsModeType): JsonObject = criteriaDocument(m).sanitizedObjectFilter

    /** Sort as the catalog's [SortOption] (same raw names as iOS). */
    private fun catalogSort(m: ReelsModeType): SortOption {
        val s = sort(m)
        return SortCatalog.option(filterMode(m), s.raw) ?: SortOption(s.raw, s.displayName, s.sortField, s.direction)
    }

    /** "Update <name>" — overwrites the selected server filter or local preset. */
    fun saveOverwrite(m: ReelsModeType) {
        val row = presetRow(m)
        ListLivePresetTag.parseServerId(row)?.let { sid ->
            val existing = savedFilters.firstOrNull { it.id == sid } ?: filters[m] ?: return
            saveServer(m, existing.id, existing.name)
            return
        }
        val lid = ListLivePresetTag.parseLocalId(row) ?: return
        val old = localPresets(m).firstOrNull { it.id == lid } ?: return
        LocalFilterPresetStore.upsert(
            filterMode(m), LocalFilterPreset.create(old.name, sort(m).raw, filters[m]?.id, liveFragment(m), id = old.id),
        )
        localPresetsVersion++
    }

    /** "Save as new" — always a Stash saved filter of the mode (iOS). */
    fun saveAs(m: ReelsModeType, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        saveServer(m, null, trimmed)
    }

    private fun saveServer(m: ReelsModeType, existingId: String?, name: String) {
        val isMarker = m == ReelsModeType.Markers
        val live = liveFragment(m)
        val previousLive = existingId?.let { id -> savedFilters.firstOrNull { it.id == id } }
            ?.let { FeedsQuery.stashyLiveFragment(it) } ?: JsonObject(emptyMap())
        val base = filters[m]?.takeIf { it.id != existingId }
        val merged = mergedObjectFilterForSave(base, live, previousLive, isMarker)
        val input = SavedFiltersRepository.saveInput(
            filterMode(m), existingId, name, catalogSort(m), merged, live, base?.id,
            de.letzgo.stashy.ui.filter.FilterPickerOptionsStore.knownLabels(),
        )
        scope.launch {
            try {
                val saved = SavedFiltersRepository.save(input)
                savedFilters = savedFilters.filter { it.id != saved.id } + saved
                SavedFiltersStore.byId[saved.id] = saved
                if (existingId == null) {
                    // The new filter becomes the selection; the editor keeps its criteria, so
                    // the feed itself does not change.
                    filters[m] = saved
                    presetRows.remove(m)
                } else {
                    ReelsModeType.entries.forEach { mm -> if (filters[mm]?.id == saved.id) filters[mm] = saved }
                }
                list(m).signature = signature(m)
                SavedFiltersStore.fetch()
                message = if (existingId == null) "Saved “$name”" else "Updated “$name”"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                message = "Save failed: ${e.message}"
            }
        }
    }

    /** iOS `reelsRenameSceneLivePreset` — a server rename keeps criteria, sort and metadata. */
    fun rename(m: ReelsModeType, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        val row = presetRow(m)
        ListLivePresetTag.parseServerId(row)?.let { sid ->
            val existing = savedFilters.firstOrNull { it.id == sid } ?: return
            val fm = existing.filterMode
            val meta = existing.stashyMetadata
            val sortForRename = SortCatalog.choice(fm, meta?.sortRaw, existing.encodedSortPair) ?: catalogSort(m)
            val input = SavedFiltersRepository.saveInput(
                fm, existing.id, trimmed, sortForRename, existing.criteriaObjectFilter(),
                meta?.liveFragment, meta?.baseSavedFilterId, de.letzgo.stashy.ui.filter.FilterPickerOptionsStore.knownLabels(),
            )
            scope.launch {
                try {
                    val saved = SavedFiltersRepository.save(input)
                    savedFilters = savedFilters.map { if (it.id == saved.id) saved else it }
                    SavedFiltersStore.byId[saved.id] = saved
                    // Same criteria: swap the reference without a refetch (the signature uses the id).
                    ReelsModeType.entries.forEach { mm -> if (filters[mm]?.id == saved.id) filters[mm] = saved }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    message = "Rename failed: ${e.message}"
                }
            }
            return
        }
        val lid = ListLivePresetTag.parseLocalId(row) ?: return
        val p = localPresets(m).firstOrNull { it.id == lid } ?: return
        LocalFilterPresetStore.upsert(filterMode(m), p.renamed(trimmed))
        localPresetsVersion++
    }

    /** iOS `reelsDeleteSceneLivePreset`. */
    fun deletePreset(m: ReelsModeType) {
        val row = presetRow(m)
        ListLivePresetTag.parseServerId(row)?.let { sid ->
            scope.launch {
                try {
                    SavedFiltersRepository.destroy(sid)
                    savedFilters = savedFilters.filter { it.id != sid }
                    SavedFiltersStore.byId.remove(sid)
                    // Every mode that ran the deleted filter falls back to None.
                    ReelsModeType.entries.forEach { mm ->
                        if (filters[mm]?.id == sid) {
                            filters.remove(mm); advanced.remove(mm); criteriaDocs.remove(mm); presetRows.remove(mm)
                            if (mm != ReelsModeType.Pics) refetch(mm)
                        }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    message = "Delete failed: ${e.message}"
                }
            }
            return
        }
        val lid = ListLivePresetTag.parseLocalId(row) ?: return
        LocalFilterPresetStore.remove(filterMode(m), lid)
        localPresetsVersion++
        // iOS only clears the picker row; the editor keeps the criteria, so the feed stays.
        presetRows.remove(m)
        filters.remove(m)
        liveFragment(m).let { if (it.isEmpty()) advanced.remove(m) else advanced[m] = it }
        list(m).signature = signature(m)
    }

    /** iOS `reelsSceneDeletePresetConfirmationText`. */
    fun deleteConfirmationText(m: ReelsModeType): String {
        val row = presetRow(m)
        ListLivePresetTag.parseServerId(row)?.let { sid ->
            savedFilters.firstOrNull { it.id == sid }?.let { return "Remove “${it.name}” from Stash? Other devices will lose this saved filter." }
        }
        ListLivePresetTag.parseLocalId(row)?.let { lid ->
            localPresets(m).firstOrNull { it.id == lid }?.let { return "Remove “${it.name}” from this device? This cannot be undone." }
        }
        return "Remove this filter? This cannot be undone."
    }

    /** Tab icon reselect (iOS `reelsWillRemount` → `refetchCurrentReelsModeFromTop`). */
    fun restartFromTop() {
        checkpoint = null
        isPlaying = true
        refetch(mode, reroll = true)
    }

    // MARK: - Criterion overlay (performer / tags / studio)

    private fun updateCriteria(new: FeedCriteria) {
        criteria = new
        if (mode == ReelsModeType.Pics) picsCriteriaChanged() else refetch(mode)
    }

    /** iOS `applyPerformerFilter`. */
    fun filterByPerformer(p: IdName) = updateCriteria(criteria.copy(performer = p))
    /** iOS `onTagTap` — toggles the tag in the selection. */
    fun toggleTag(t: IdName) {
        val tags = if (criteria.tags.any { it.id == t.id }) criteria.tags.filter { it.id != t.id } else criteria.tags + t
        updateCriteria(criteria.copy(tags = tags))
    }
    fun clearPerformer() = updateCriteria(criteria.copy(performer = null))
    fun clearStudio() = updateCriteria(criteria.copy(studio = null))

    // MARK: - Deep links (iOS `applyPendingReelsNavigationFromCoordinator`)

    fun apply(link: FeedsDeepLink) {
        val sid = ServerConfigManager.activeConfig?.id
        if (sid != serverId) resetForServer(sid)
        if (!savedFiltersLoaded) refreshSavedFilters()
        initialized = true
        checkpoint = null
        isPlaying = true
        // iOS `prepareFreshFeedForDeepLink`: every list and position is rebuilt.
        lists.values.forEach { it.job?.cancel(); it.items.clear(); it.loadedOnce = false; it.signature = null }
        currentIds.clear()
        resetPics()
        val target = ReelsModeType.fromModeRaw(link.mode)
        when {
            link.clipFilter != null -> {
                mode = ReelsModeType.Clips
                criteria = FeedCriteria()
                advanced.remove(ReelsModeType.Clips); criteriaDocs.remove(ReelsModeType.Clips); presetRows.remove(ReelsModeType.Clips)
                filters[ReelsModeType.Clips] = link.clipFilter
                sorts[ReelsModeType.Clips] = ImageSortOption.from(link.clipSort) ?: defaultSort(ReelsModeType.Clips)
                refetch(ReelsModeType.Clips)
            }
            link.sceneFilter != null -> {
                mode = ReelsModeType.Scenes
                criteria = FeedCriteria()
                advanced.remove(ReelsModeType.Scenes); criteriaDocs.remove(ReelsModeType.Scenes); presetRows.remove(ReelsModeType.Scenes)
                filters[ReelsModeType.Scenes] = link.sceneFilter
                sorts[ReelsModeType.Scenes] = SceneSortOption.from(link.sceneSort) ?: defaultSort(ReelsModeType.Scenes)
                refetch(ReelsModeType.Scenes)
            }
            link.performer != null || link.tags.isNotEmpty() || link.studio != null -> {
                // iOS `reelsClearSessionFiltersForDeepLink`: only the handed criteria plus the
                // mode's Settings default filter and default sort survive.
                filters.clear(); advanced.clear(); criteriaDocs.clear(); presetRows.clear(); sorts.clear()
                mode = target ?: FeedsConfig.enabledModes.firstOrNull() ?: ReelsModeType.Scenes
                criteria = FeedCriteria(link.performer, link.tags, link.studio)
                // iOS: every Feeds view starts from its Settings default filter; the handed
                // criteria narrow it.
                ensureLoaded(mode, applyDefaultFilter = true)
            }
            target != null -> {
                mode = target
                ensureLoaded(mode)
            }
        }
    }

    // MARK: - Dead rows (iOS `probeUpcomingMedia`, `handleUnplayableItem`)

    /**
     * Only Previews depend on generated files the server may not have. Markers play their window
     * of the original scene (like Scenes), so a failing marker shows the row's error instead of
     * being skipped.
     */
    private fun dropsDeadRows(m: ReelsModeType) = m == ReelsModeType.Previews

    /** Drops a row the server has no file for and returns the id that takes its place. */
    fun dropUnplayable(id: String): String? {
        if (!dropsDeadRows(mode)) return null
        val ids = visibleItems().map { it.id }
        val successor = PreloadWindow.successor(ids, id, unplayable.keys + id)
        unplayable[id] = true
        if (currentIds[mode] == id) successor?.let { currentIds[mode] = it } ?: currentIds.remove(mode)
        refillAfterDrops()
        return successor
    }

    private fun refillAfterDrops() {
        val items = visibleItems()
        val index = currentIds[mode]?.let { id -> items.indexOfFirst { it.id == id } } ?: 0
        if (PreloadWindow.needsRefill(index, items.size)) loadMore()
    }

    /**
     * Asks the server whether the generated files ahead exist (one-byte range GET; only a
     * definite 404/410 counts as missing) and drops the dead ones before the user reaches them.
     */
    fun probeUpcomingMedia() {
        val m = mode
        if (!dropsDeadRows(m)) return
        val items = visibleItems(m)
        val window = PreloadWindow.probeWindow(items.map { it.id }, currentIds[m], probed)
        if (window.isEmpty()) return
        probed.addAll(window)
        val byId = items.associateBy { it.id }
        scope.launch {
            val missing = window.map { id ->
                async { byId[id]?.videoURL?.let { url -> if (fileIsMissing(url)) id else null } }
            }.awaitAll().filterNotNull()
            if (missing.isEmpty() || m != mode) return@launch
            missing.forEach { dropUnplayable(it) }
            probeUpcomingMedia()
        }
    }

    private suspend fun fileIsMissing(url: String): Boolean = withContext(Dispatchers.IO) {
        withTimeoutOrNull(12_000) {
            runCatching {
                val req = Request.Builder().url(url).header("Range", "bytes=0-0").build()
                Net.client.newCall(req).await().use { it.code == 404 || it.code == 410 }
            }.getOrDefault(false)
        } ?: false
    }

    // MARK: - Optimistic updates (iOS `handleRatingChange`, `handleOCounterChange`, …)

    /** Replaces every row that shows [sceneId] (scenes, previews, markers of that scene). */
    private fun patchScene(sceneId: String, transform: (de.letzgo.stashy.data.Scene) -> de.letzgo.stashy.data.Scene) {
        lists.values.forEach { l ->
            for (i in l.items.indices) {
                val item = l.items[i]
                val patched = when (item) {
                    is FeedItem.SceneItem -> if (item.scene.id == sceneId) FeedItem.SceneItem(transform(item.scene)) else null
                    is FeedItem.PreviewItem -> if (item.scene.id == sceneId) FeedItem.PreviewItem(transform(item.scene)) else null
                    is FeedItem.MarkerItem -> item.marker.scene?.takeIf { it.id == sceneId }?.let { FeedItem.MarkerItem(item.marker.copy(scene = transform(it))) }
                    is FeedItem.ClipItem -> null
                }
                if (patched != null) l.items[i] = patched
            }
        }
    }

    private fun patchImage(imageId: String, transform: (de.letzgo.stashy.data.StashImage) -> de.letzgo.stashy.data.StashImage) {
        lists.values.forEach { l ->
            for (i in l.items.indices) {
                val item = l.items[i]
                if (item is FeedItem.ClipItem && item.image.id == imageId) l.items[i] = FeedItem.ClipItem(transform(item.image))
            }
        }
    }

    /** Toast-like message for failed writes (shown by the screen). */
    var message by mutableStateOf<String?>(null)

    // MARK: - Tags (iOS `SceneTagsUpdated` / `MarkerTagsUpdated` / `ImageTagsUpdated` / `BulkTagsApplied`)

    init {
        // Tag Suggestion accepts, the "+" editor and bulk "Set on all of …" patch the rows in
        // place (iOS `patch*TagsInLists`, `patchBulkAppliedTag`) instead of refetching the feed.
        scope.launch { AITagSuggestions.events.collect { applyTagEvent(it) } }
    }

    private fun applyTagEvent(event: AITagUpdateEvent) {
        lists.values.forEach { l ->
            for (i in l.items.indices) l.items[i].applying(event)?.let { l.items[i] = it }
        }
        // Pics runs the Images catalog's list (iOS patches `allImages` too).
        pics.list.patch { img -> (FeedItem.ClipItem(img).applying(event) as? FeedItem.ClipItem)?.image ?: img }
    }

    /**
     * iOS `removeTag(_:from:)` — takes a tag off the item itself (not off the filter). A marker's
     * primary tag is a separate field in Stash and is left alone.
     */
    fun removeTag(tagId: String, from: AITagTarget) {
        if (tagId == from.primaryTagId) return
        val name = from.tags.firstOrNull { it.id == tagId }?.name.orEmpty()
        val remaining: List<Tag> = from.tags.filter { it.id != tagId }
        scope.launch {
            message = if (AITagSuggestions.write(remaining, from)) "Removed #$name" else "Could not remove tag"
        }
    }

    fun setRating(item: FeedItem, rating100: Int?) {
        val sceneId = item.sceneID
        if (sceneId != null) {
            val original = item.rating100
            patchScene(sceneId) { it.copy(rating100 = rating100) }
            scope.launch {
                if (!FeedsRepository.updateSceneRating(sceneId, rating100)) {
                    patchScene(sceneId) { it.copy(rating100 = original) }
                    message = "Failed to save rating"
                }
            }
        } else if (item is FeedItem.ClipItem) {
            val original = item.image.rating100
            patchImage(item.image.id) { it.copy(rating100 = rating100) }
            scope.launch {
                if (!FeedsRepository.updateImageRating(item.image.id, rating100)) {
                    patchImage(item.image.id) { it.copy(rating100 = original) }
                    message = "Failed to save rating"
                }
            }
        }
    }

    fun changeOCounter(item: FeedItem, mutation: FeedsRepository.OMutation) {
        val current = item.oCounter ?: 0
        val optimistic = when (mutation) {
            FeedsRepository.OMutation.Increment -> current + 1
            FeedsRepository.OMutation.Decrement -> (current - 1).coerceAtLeast(0)
            FeedsRepository.OMutation.Reset -> 0
        }
        val sceneId = item.sceneID
        if (sceneId != null) {
            patchScene(sceneId) { it.copy(oCounter = optimistic) }
            scope.launch {
                val count = FeedsRepository.mutateOCounter(sceneId, isImage = false, mutation)
                patchScene(sceneId) { it.copy(oCounter = count ?: current) }
                if (count == null) message = "Counter update failed"
            }
        } else if (item is FeedItem.ClipItem) {
            patchImage(item.image.id) { it.copy(oCounter = optimistic) }
            scope.launch {
                val count = FeedsRepository.mutateOCounter(item.image.id, isImage = true, mutation)
                patchImage(item.image.id) { it.copy(oCounter = count ?: current) }
                if (count == null) message = "Counter update failed"
            }
        }
    }

    /** iOS `handlePlayCountChange` — credited once per row after the Feeds threshold. */
    fun creditPlay(item: FeedItem) {
        when (item) {
            is FeedItem.SceneItem -> scope.launch {
                FeedsRepository.addScenePlay(item.scene.id)?.let { c -> patchScene(item.scene.id) { it.copy(playCount = c) } }
            }
            is FeedItem.MarkerItem -> scope.launch { FeedsRepository.addSceneMarkerPlay(item.marker.id) }
            else -> {}
        }
    }

    /** iOS `reelsDeleteItem`. Returns via [message]. */
    fun delete(item: FeedItem, onDone: (Boolean) -> Unit) {
        scope.launch {
            val ok = when (item) {
                is FeedItem.SceneItem -> FeedsRepository.deleteSceneWithFiles(item.scene)
                is FeedItem.PreviewItem -> FeedsRepository.deleteSceneWithFiles(item.scene)
                is FeedItem.ClipItem -> FeedsRepository.deleteImage(item.image.id)
                is FeedItem.MarkerItem -> false
            }
            val label = if (item is FeedItem.ClipItem) "image" else "scene"
            if (ok) {
                lists.values.forEach { l -> l.items.removeAll { it.sceneID != null && it.sceneID == item.sceneID && item.sceneID != null || it.id == item.id } }
                message = "${label.replaceFirstChar { it.uppercase() }} deleted"
            } else message = "Failed to delete $label"
            onDone(ok)
        }
    }
}
