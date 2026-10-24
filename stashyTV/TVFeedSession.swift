//
//  TVFeedSession.swift
//  stashyTV
//
//  Data + playback for tvOS Feeds, the lean-back counterpart of the iOS Feeds tab
//  (`ReelsView`). The pages come from the same `StashDBViewModel` feed fetches iOS uses
//  (`fetchScenes(forFeeds:)`, `fetchSceneMarkers`, `fetchPreviews`, `fetchClips` and their
//  `loadMore*`), with the same per-mode defaults from `TabManager` (Settings › Feeds:
//  default sort + default saved filter per mode). Playback runs on a single
//  `AetherSceneEngine` that is handed from item to item, so only the current item is ever
//  decoding — the Apple TV has neither the memory nor the decoders for a pager of engines.
//

#if canImport(AetherEngine)

import SwiftUI
import Combine
import UIKit
import AetherEngine

// MARK: - Item

/// One page of the feed. A lean subset of iOS's `ReelsViewBody.ReelItemData`.
enum TVFeedItem: Identifiable {
    case scene(Scene)
    case marker(SceneMarker)
    case clip(StashImage)
    case preview(Scene)

    var id: String {
        switch self {
        case .scene(let s): return "scene-\(s.id)"
        case .marker(let m): return "marker-\(m.id)"
        case .clip(let c): return "clip-\(c.id)"
        case .preview(let s): return "preview-\(s.id)"
        }
    }

    var title: String {
        switch self {
        case .scene(let s), .preview(let s):
            return s.displayTitle ?? "Untitled Scene"
        case .marker(let m):
            if let t = m.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            if let name = m.primaryTag?.name, !name.isEmpty { return name }
            return m.scene?.toScene().displayTitle ?? "Marker"
        case .clip(let c):
            return c.displayFilename
        }
    }

    /// Second line: the scene a marker belongs to, otherwise the date.
    var subtitle: String? {
        switch self {
        case .marker(let m):
            let sceneTitle = m.scene?.toScene().displayTitle
            return sceneTitle == title ? m.scene?.date : sceneTitle
        case .scene(let s), .preview(let s):
            return s.date
        case .clip(let c):
            return c.date
        }
    }

    var performers: [(id: String, name: String)] {
        switch self {
        case .scene(let s), .preview(let s): return s.performers.map { ($0.id, $0.name) }
        case .marker(let m): return (m.scene?.performers ?? []).map { ($0.id, $0.name) }
        case .clip(let c): return (c.performers ?? []).map { ($0.id, $0.name) }
        }
    }

    var studio: (id: String, name: String)? {
        switch self {
        case .scene(let s), .preview(let s): return s.studio.map { ($0.id, $0.name) }
        case .marker: return nil
        case .clip(let c): return c.studio.map { ($0.id, $0.name) }
        }
    }

    var tagNames: [String] {
        switch self {
        case .scene(let s), .preview(let s): return (s.tags ?? []).map(\.name)
        case .marker(let m):
            var names = (m.tags ?? []).map(\.name)
            if let primary = m.primaryTag?.name { names.removeAll { $0 == primary }; names.insert(primary, at: 0) }
            return names
        case .clip(let c): return (c.tags ?? []).map(\.name)
        }
    }

    /// Same sources as iOS: scenes and markers play the original file (markers their stretch
    /// of it), previews Stash's generated preview clip, clips the image file itself.
    var videoURL: URL? {
        switch self {
        case .scene(let s): return s.aetherVideoURL
        case .marker(let m): return m.scene?.toScene().aetherVideoURL
        case .clip(let c): return c.imageURL
        case .preview(let s): return s.previewURL
        }
    }

    var posterURL: URL? {
        switch self {
        case .scene(let s), .preview(let s): return s.thumbnailURL
        case .marker(let m): return m.thumbnailURL
        case .clip(let c): return c.thumbnailURL
        }
    }

    /// The scene the overlay's "Scene Details" / "Play" act on.
    var underlyingScene: Scene? {
        switch self {
        case .scene(let s), .preview(let s): return s
        case .marker(let m): return m.scene?.toScene()
        case .clip: return nil
        }
    }

    var segment: ReelPlaybackSegment? {
        if case .marker(let m) = self { return ReelPlaybackSegment.marker(m) }
        return nil
    }

    /// Where the item starts and loops back to: the marker, or the scene's Feeds start
    /// position (Settings › Playback › "Feeds start position").
    @MainActor
    var startTime: Double {
        if let segment { return segment.start }
        if case .scene(let s) = self { return ReelsSceneStartPositions.start(for: s) }
        return 0
    }

    /// Full scenes and markers have server transcodes to fall back to; previews and clips
    /// are their own file.
    var fallbackSources: [URL] {
        switch self {
        case .scene(let s): return s.transcodeFallbackURLs
        case .marker(let m): return m.scene?.toScene().transcodeFallbackURLs ?? []
        case .clip, .preview: return []
        }
    }

    var declaredDuration: Double? {
        switch self {
        case .scene(let s): return s.sceneDuration
        case .marker(let m): return m.scene?.toScene().sceneDuration
        case .clip, .preview: return nil
        }
    }

    /// Scenes and markers credit a play to their scene after "Count as played — Feeds".
    var playCreditSceneId: String? {
        switch self {
        case .scene(let s): return s.id
        case .marker(let m): return m.scene?.id
        case .clip, .preview: return nil
        }
    }
}

// MARK: - Modes

extension ReelsModeType {
    /// Modes tvOS Feeds can play. Pics is an image slideshow, not a video feed.
    static let tvFeedModes: [ReelsModeType] = [.scenes, .markers, .clips, .previews]

    /// The iOS mode order and on/off switches (Settings › Feeds › Modes), limited to what
    /// tvOS plays. Never empty.
    @MainActor
    static var tvEnabledFeedModes: [ReelsModeType] {
        let enabled = TabManager.shared.enabledReelsModes.filter { tvFeedModes.contains($0) }
        return enabled.isEmpty ? [.scenes] : enabled
    }

    var feedKind: StashDBViewModel.ReelsFeedKind? {
        switch self {
        case .scenes: return .scenes
        case .markers: return .markers
        case .clips: return .clips
        case .previews: return .previews
        case .pics: return nil
        }
    }

    /// Saved-filter mode a Feeds default filter of this mode belongs to.
    var savedFilterMode: StashDBViewModel.FilterMode {
        switch self {
        case .scenes, .previews: return .scenes
        case .markers: return .sceneMarkers
        case .clips, .pics: return .images
        }
    }

    /// Feeds default filter id — the same `TabManager` slots iOS reads.
    @MainActor
    var defaultFilterId: String? {
        let tm = TabManager.shared
        switch self {
        case .scenes: return tm.getDefaultFilterId(for: .reels)
        case .markers: return tm.getDefaultMarkerFilterId(for: .reels)
        case .clips: return tm.getDefaultClipFilterId(for: .reels)
        case .previews: return tm.getDefaultPreviewFilterId(for: .reels)
        case .pics: return tm.getDefaultFilterId(for: .images)
        }
    }

    @MainActor
    func setDefaultFilter(id: String?, name: String?) {
        let tm = TabManager.shared
        switch self {
        case .scenes: tm.setDefaultFilter(for: .reels, filterId: id, filterName: name)
        case .markers: tm.setDefaultMarkerFilter(for: .reels, filterId: id, filterName: name)
        case .clips: tm.setDefaultClipFilter(for: .reels, filterId: id, filterName: name)
        case .previews: tm.setDefaultPreviewFilter(for: .reels, filterId: id, filterName: name)
        case .pics: tm.setDefaultFilter(for: .images, filterId: id, filterName: name)
        }
    }

    /// Feeds default sort raw value, falling back to Random like iOS.
    @MainActor
    var defaultSortRaw: String {
        TabManager.shared.getReelsDefaultSort(for: self) ?? "random"
    }

    /// Sort choices of this mode as (raw value, label).
    var sortChoices: [(raw: String, label: String)] {
        switch self {
        case .scenes, .previews:
            return StashDBViewModel.SceneSortOption.allCases.map { ($0.rawValue, $0.displayName) }
        case .markers:
            return StashDBViewModel.SceneMarkerSortOption.allCases.map { ($0.rawValue, $0.displayName) }
        case .clips, .pics:
            return StashDBViewModel.ImageSortOption.allCases.map { ($0.rawValue, $0.displayName) }
        }
    }
}

// MARK: - Session

/// Navigation targets the overlay hands back to the Feeds tab (the feed itself is a cover,
/// the tab's stack pushes them once it is gone).
enum TVFeedDestination: Hashable {
    case scene(id: String)
    case performer(id: String, name: String)
    case studio(id: String, name: String)
}

@MainActor
final class TVFeedSession: ObservableObject {

    let catalog = StashDBViewModel()

    @Published private(set) var mode: ReelsModeType
    @Published private(set) var items: [TVFeedItem] = []
    @Published private(set) var index = 0
    /// The one engine of the feed. nil while the feed is off screen.
    @Published private(set) var engine: AetherSceneEngine?
    /// A new item is loading over the previous picture: the overlay shows its poster.
    @Published private(set) var isSwitching = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isMuted: Bool

    /// Last item per mode, so switching modes back and forth (and reopening the feed) lands
    /// where the user left off — the iOS session position.
    private var positions: [ReelsModeType: String] = [:]
    /// The sort + filter each mode's list was fetched with. A match skips the page-1 refetch.
    private var loadedKeys: [ReelsModeType: String] = [:]
    private var isActive = false
    private var savedFiltersRequested = false
    private var cancellables = Set<AnyCancellable>()
    private var engineCancellables = Set<AnyCancellable>()

    // Per-item playback state
    private var watchClock = PlayCountWatchClock()
    private var creditedItemId: String?
    private var segmentEndHandled = false
    private var loadGeneration = 0
    /// Items without a playable source, skipped from here on.
    private var unplayableIds: Set<String> = []

    private static let mutedKey = "tvFeedsMuted"
    private static let seekStep: Double = 10

    var currentItem: TVFeedItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var canGoPrevious: Bool { index > 0 }
    var canGoNext: Bool { index + 1 < items.count }

    var positionLabel: String {
        guard !items.isEmpty else { return "" }
        let total = totalCount
        return total > items.count ? "\(index + 1) / \(total)" : "\(index + 1) / \(items.count)"
    }

    private var totalCount: Int {
        switch mode {
        case .scenes: return catalog.totalScenes
        case .previews: return catalog.totalPreviews
        default: return items.count
        }
    }

    init() {
        mode = ReelsModeType.tvEnabledFeedModes.first ?? .scenes
        // tvOS plays through the TV — the private-listening case iOS gates behind headphones.
        // So the stored choice applies directly and the feed starts with sound by default.
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)

        // The catalog publishes page loads; rebuild the visible list after each change.
        catalog.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshFromCatalog() }
            .store(in: &cancellables)

        let center = NotificationCenter.default
        center.publisher(for: NSNotification.Name("ServerConfigChanged"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resetForServerChange() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.engine?.pause() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// The feed cover appeared: fetch (if needed) and play.
    func activate(mode requested: ReelsModeType? = nil) {
        isActive = true
        if let requested, requested != mode {
            rememberPosition()
            mode = requested
            restoreFromCatalog()
        }
        fetchIfNeeded()
        playCurrent()
    }

    /// The cover is gone: release the engine. The list and position stay for the next visit.
    func deactivate() {
        rememberPosition()
        isActive = false
        releaseEngine()
    }

    /// The normal player takes over (overlay › Play): free the decoder until it returns.
    func suspendForFullPlayer() {
        releaseEngine()
    }

    func resumeAfterFullPlayer() {
        guard isActive else { return }
        playCurrent()
    }

    private func releaseEngine() {
        loadGeneration &+= 1
        engineCancellables.removeAll()
        if let engine {
            engine.onTime = nil
            engine.onReachedEnd = nil
            engine.stop()
        }
        engine = nil
        isSwitching = false
    }

    private func resetForServerChange() {
        releaseEngine()
        positions = [:]
        loadedKeys = [:]
        unplayableIds = []
        savedFiltersRequested = false
        items = []
        index = 0
        errorMessage = nil
        catalog.forgetAllReelsFeedSignatures()
        if isActive { fetchIfNeeded(force: true) }
    }

    // MARK: Modes

    func switchMode(to newMode: ReelsModeType) {
        guard newMode != mode else { return }
        rememberPosition()
        mode = newMode
        restoreFromCatalog()
        fetchIfNeeded()
        if currentItem != nil {
            playCurrent()
        } else {
            releaseEngine()
        }
    }

    private func rememberPosition() {
        if let id = currentItem?.id { positions[mode] = id }
    }

    /// Re-reads the (possibly still warm) list of the current mode and its last position.
    private func restoreFromCatalog() {
        items = buildItems()
        if let saved = positions[mode], let i = items.firstIndex(where: { $0.id == saved }) {
            index = i
        } else {
            index = 0
        }
        updateLoadingState()
    }

    // MARK: Data

    /// Page 1 for the current mode with its Feeds defaults, unless the list already holds it.
    func fetchIfNeeded(force: Bool = false) {
        let mode = self.mode
        let filterId = mode.defaultFilterId

        // The default filter is a saved filter: wait for the server's list once.
        if filterId != nil, catalog.savedFilters.isEmpty, !savedFiltersRequested {
            savedFiltersRequested = true
            isLoading = true
            catalog.fetchSavedFilters { [weak self] _ in
                Task { @MainActor in self?.fetchIfNeeded(force: force) }
            }
            return
        }
        let filter = filterId.flatMap { catalog.savedFilters[$0] }
        let sortRaw = mode.defaultSortRaw
        let key = "\(sortRaw)|\(filter?.id ?? "-")"
        if !force, loadedKeys[mode] == key, !buildItems().isEmpty || isFetching(mode) {
            refreshFromCatalog()
            return
        }
        loadedKeys[mode] = key
        positions[mode] = nil
        unplayableIds = []
        errorMessage = nil

        guard let kind = mode.feedKind else { return }
        catalog.abandonInactiveReelsFeeds(keeping: kind)
        catalog.setActiveReelsFeed(kind)
        if mode == .scenes { ReelsSceneStartPositions.reset() }

        switch mode {
        case .scenes:
            let sort = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? .random
            catalog.fetchScenes(sortBy: sort, filter: filter, forFeeds: true)
        case .markers:
            let sort = StashDBViewModel.SceneMarkerSortOption(rawValue: sortRaw) ?? .random
            catalog.fetchSceneMarkers(sortBy: sort, filter: filter)
        case .clips:
            let sort = StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? .random
            catalog.fetchClips(sortBy: sort, filter: filter, isInitialLoad: true)
        case .previews:
            let sort = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? .random
            catalog.fetchPreviews(sortBy: sort, isInitialLoad: true, filter: filter)
        case .pics:
            break
        }
        updateLoadingState()
    }

    /// Re-rolls the timeline: a fresh random order (or page 1 again) from the top.
    func reload() {
        if let kind = seedKind(for: mode) { catalog.refreshRandomSeed(for: kind) }
        fetchIfNeeded(force: true)
    }

    private func seedKind(for mode: ReelsModeType) -> StashDBViewModel.RandomSeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .markers: return .markers
        case .clips: return .images
        case .previews: return .previews
        case .pics: return nil
        }
    }

    private func isFetching(_ mode: ReelsModeType) -> Bool {
        switch mode {
        case .scenes: return catalog.isLoadingScenes
        case .markers: return catalog.isLoadingMarkers
        case .clips: return catalog.isLoadingClips
        case .previews: return catalog.isLoadingPreviews
        case .pics: return false
        }
    }

    /// Same row rules as iOS `currentReelItems`: markers need their scene, previews a preview
    /// file. Clips drop GIF/WebP animations, which have no video track to play.
    private func buildItems() -> [TVFeedItem] {
        let built: [TVFeedItem]
        switch mode {
        case .scenes:
            built = catalog.scenes.map { .scene($0) }
        case .markers:
            built = catalog.sceneMarkers.filter { $0.scene != nil }.map { .marker($0) }
        case .clips:
            built = catalog.clips.filter { c in
                let ext = c.fileExtension?.uppercased()
                return ext != "GIF" && ext != "WEBP"
            }.map { .clip($0) }
        case .previews:
            built = catalog.previews.filter { $0.previewURL != nil }.map { .preview($0) }
        case .pics:
            built = []
        }
        return built.filter { !unplayableIds.contains($0.id) }
    }

    private func refreshFromCatalog() {
        let fresh = buildItems()
        let oldIds = items.map(\.id)
        let newIds = fresh.map(\.id)
        updateLoadingState()
        guard oldIds != newIds else { return }

        let currentId = currentItem?.id
        items = fresh
        if let currentId, let i = fresh.firstIndex(where: { $0.id == currentId }) {
            // A page was appended (or a row dropped) — the current item plays on.
            index = i
            return
        }
        // A new timeline: start at its first item, or the remembered one when it is in there.
        if let saved = positions[mode], let i = fresh.firstIndex(where: { $0.id == saved }) {
            index = i
        } else {
            index = 0
        }
        if isActive {
            if currentItem != nil { playCurrent() } else { releaseEngine() }
        }
    }

    private func updateLoadingState() {
        let fetching = isFetching(mode)
        isLoading = items.isEmpty && (fetching || (catalog.isLoadingSavedFilters && mode.defaultFilterId != nil))
        if items.isEmpty, !fetching, loadedKeys[mode] != nil {
            errorMessage = catalog.errorMessage ?? "Nothing to play in \(mode.defaultTitle)."
        } else if !items.isEmpty {
            errorMessage = nil
        }
    }

    private func loadMoreIfNeeded() {
        guard index >= items.count - 4 else { return }
        switch mode {
        case .scenes: catalog.loadMoreScenes()
        case .markers: catalog.loadMoreMarkers()
        case .clips: catalog.loadMoreClips()
        case .previews: catalog.loadMorePreviews()
        case .pics: break
        }
    }

    // MARK: Navigation

    func next() {
        guard canGoNext else {
            loadMoreIfNeeded()
            return
        }
        index += 1
        playCurrent()
    }

    func previous() {
        guard canGoPrevious else { return }
        index -= 1
        playCurrent()
    }

    // MARK: Transport

    func togglePlayPause() {
        engine?.togglePlayPause()
    }

    /// ◀ / ▶: ±10 s, like the macOS arrow keys. Markers stay inside their segment.
    func seek(by delta: Double) {
        guard let engine, let item = currentItem else { return }
        var lower: Double = 0
        var upper = engine.duration.isFinite && engine.duration > 0 ? engine.duration - 0.5 : .greatestFiniteMagnitude
        if let segment = item.segment?.clamped(toFileDuration: engine.duration) {
            lower = segment.start
            upper = segment.end - 0.5
        }
        let target = min(max(lower, engine.currentTime + delta), max(lower, upper))
        segmentEndHandled = false
        watchClock.breakInterval()
        Task { await engine.seek(to: target) }
    }

    func toggleMute() {
        isMuted.toggle()
        UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
        engine?.isMuted = isMuted
    }

    static var seekStepSeconds: Double { seekStep }

    // MARK: Playback

    private func ensureEngine() -> AetherSceneEngine? {
        if let engine { return engine }
        guard let created = try? AetherSceneEngine() else {
            errorMessage = "Playback engine unavailable"
            return nil
        }
        created.audioSessionPolicy = .playback
        created.onTime = { [weak self] time, duration in
            self?.handleTime(time, duration: duration)
        }
        created.onReachedEnd = { [weak self] in
            self?.handleReachedEnd()
        }
        // An item that cannot be played even after the transcode ladder is dropped and the
        // feed moves on — like iOS `handleUnplayableItem`, so a lean-back feed never stalls.
        created.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard message != nil, let self else { return }
                let generation = self.loadGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    guard let self, generation == self.loadGeneration,
                          let engine = self.engine, engine.errorMessage != nil, !engine.hasFirstFrame,
                          let item = self.currentItem else { return }
                    self.skipUnplayable(item)
                }
            }
            .store(in: &engineCancellables)
        engine = created
        return created
    }

    private func playCurrent() {
        guard isActive else { return }
        loadMoreIfNeeded()
        guard let item = currentItem else { return }
        rememberPosition()

        guard let url = item.videoURL else {
            skipUnplayable(item)
            return
        }
        guard let engine = ensureEngine() else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        watchClock.reset()
        creditedItemId = nil
        segmentEndHandled = false
        isSwitching = true

        let start = item.startTime
        engine.isMuted = isMuted
        engine.fallbackSources = item.fallbackSources
        engine.fallbackDeclaredDuration = item.declaredDuration
        // Rows with a start position (markers, scenes with a Feeds start) loop back to it
        // themselves; the engine's own loop would restart at 0.
        engine.loopsAtEnd = item.segment == nil && start <= 0 && !TabManager.shared.reelsContinuousPlay
        // Keep the outgoing picture (and the route) until the new item replaces it.
        if engine.hasPresentedFrame { engine.prepareForItemReplacement() }

        Task { @MainActor [weak self] in
            await engine.load(url: url, startAt: start > 0.05 ? start : nil, autoplay: true) { options in
                // Paging through a feed must not renegotiate the HDMI display mode per item.
                options.suppressDisplayCriteria = true
            }
            guard let self, generation == self.loadGeneration else { return }
            self.isSwitching = false
        }
    }

    private func skipUnplayable(_ item: TVFeedItem) {
        AppLog.debug("📺 TV Feeds: no playable source for \(item.id) — skipping")
        unplayableIds.insert(item.id)
        let removedIndex = index
        items = buildItems()
        index = min(removedIndex, max(0, items.count - 1))
        if currentItem != nil { playCurrent() }
    }

    private func handleTime(_ time: Double, duration: Double) {
        guard let engine, let item = currentItem, !isSwitching else { return }

        // Count as played — Feeds: real watching time only, like iOS.
        if let sceneId = item.playCreditSceneId, creditedItemId != item.id {
            watchClock.sample(playhead: time, isPlaying: engine.isPlaying)
            if watchClock.watchedSeconds >= max(0, TabManager.shared.playCountFeedsSeconds) {
                creditedItemId = item.id
                if TabManager.tracksActivity(for: sceneId) {
                    catalog.addScenePlay(sceneId: sceneId)
                }
            }
        }

        // Marker rows end at their segment end: continuous play moves on, otherwise loop.
        if let segment = item.segment?.clamped(toFileDuration: duration),
           !segmentEndHandled, time >= segment.end - 0.15 {
            segmentEndHandled = true
            if TabManager.shared.reelsContinuousPlay, canGoNext {
                next()
            } else {
                loopToStart()
            }
        }
    }

    private func handleReachedEnd() {
        if TabManager.shared.reelsContinuousPlay, canGoNext {
            next()
        } else {
            loopToStart()
        }
    }

    private func loopToStart() {
        guard let engine, let item = currentItem else { return }
        let start = item.startTime
        Task { @MainActor [weak self] in
            await engine.seek(to: start)
            engine.play()
            self?.segmentEndHandled = false
        }
    }
}

#endif
