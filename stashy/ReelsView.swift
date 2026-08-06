#if !os(tvOS)
//
//  ReelsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

private extension Notification.Name {
    static let reelsPauseAllPlayers = Notification.Name("ReelsPauseAllPlayers")
}

/// Reads the on-screen tab bar overlap without changing SwiftUI safe-area / paging layout.
@MainActor
enum ReelsTabBarLayout {
    /// Avoid walking the VC hierarchy on every SwiftUI body pass (Feeds fill mode).
    private static var cachedOverlap: CGFloat?
    private static var cacheTimestamp: CFAbsoluteTime = 0
    private static let cacheTTL: CFAbsoluteTime = 0.5

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.keyWindow
            ?? scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first
    }

    static func invalidateCache() {
        cachedOverlap = nil
        cacheTimestamp = 0
    }

    static func topInset() -> CGFloat {
        keyWindow()?.safeAreaInsets.top ?? 0
    }

    static func overlapFromBottom() -> CGFloat {
        let now = CFAbsoluteTimeGetCurrent()
        if let cachedOverlap, now - cacheTimestamp < cacheTTL {
            return cachedOverlap
        }

        guard let window = keyWindow() else { return 0 }

        func tabBar(from vc: UIViewController?) -> UITabBar? {
            guard let vc else { return nil }
            if let tab = vc as? UITabBarController { return tab.tabBar }
            for child in vc.children {
                if let bar = tabBar(from: child) { return bar }
            }
            return tabBar(from: vc.presentedViewController)
        }

        let value: CGFloat
        if let bar = tabBar(from: window.rootViewController),
           !bar.isHidden,
           bar.alpha > 0.01,
           bar.bounds.height > 1 {
            let frameInWindow = bar.convert(bar.bounds, to: window)
            value = max(0, window.bounds.maxY - frameInWindow.minY)
        } else {
            // Fallback before UITabBar is attached: standard bar + home indicator.
            value = 49 + window.safeAreaInsets.bottom
        }

        cachedOverlap = value
        cacheTimestamp = now
        return value
    }
}

/// Bottom chrome heights for immersive video fill (scrubber + tab bar; no capsule bar).
@MainActor
enum ReelsImmersiveChromeLayout {
    /// Video bottom inset so fill ends flush with the scrubber bottom (above tab bar).
    static func videoBottomInset() -> CGFloat {
        ReelsTabBarLayout.overlapFromBottom()
    }
}

enum ReelsPlayerRegistry {
    private static let players = NSHashTable<AVPlayer>.weakObjects()
    private static let lock = NSLock()
    /// When true, Feeds left the visible tab — block deferred `play()` / stream-upgrade races.
    private static var _isSuspended = false

    static var isPlaybackSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSuspended
    }

    static func register(_ player: AVPlayer) {
        lock.lock()
        players.add(player)
        lock.unlock()
    }

    static func unregister(_ player: AVPlayer) {
        lock.lock()
        players.remove(player)
        lock.unlock()
    }

    static func pauseAll() {
        lock.lock()
        let all = players.allObjects
        lock.unlock()
        for player in all {
            player.pause()
            player.rate = 0
        }
    }

    /// Hard stop for tab leave: pause every registered player and reject further `playIfAllowed` until resume.
    static func suspendPlayback() {
        lock.lock()
        _isSuspended = true
        let all = players.allObjects
        lock.unlock()
        for player in all {
            player.pause()
            player.rate = 0
        }
    }

    static func resumePlayback() {
        lock.lock()
        _isSuspended = false
        lock.unlock()
    }

    /// Safe play entry point for Reel rows — no-op while Feeds is backgrounded/suspended.
    static func playIfAllowed(_ player: AVPlayer?) {
        guard let player else { return }
        lock.lock()
        let suspended = _isSuspended
        lock.unlock()
        guard !suspended else { return }
        player.play()
    }
}

/// Reels „Session“ state: **RAM only** — survives tab switches / navigation within one app launch, **not** an app restart.
/// One-time cleanup removes legacy `UserDefaults` keys from older builds so nothing persists across relaunch.
///
enum ReelsSessionRAM {
    private static let lock = NSLock()
    private static var strings: [String: String] = [:]
    private static var ints: [String: Int] = [:]
    private static var didClearLegacyUserDefaults = false

    static func clearLegacyUserDefaultsIfNeeded() {
        lock.lock()
        let shouldClear = !didClearLegacyUserDefaults
        if shouldClear { didClearLegacyUserDefaults = true }
        lock.unlock()
        guard shouldClear else { return }
        let ud = UserDefaults.standard
        let keys = Array(ud.dictionaryRepresentation().keys)
        for key in keys {
            if key.hasPrefix("reels_last_visible_")
                || key.hasPrefix("reels_session_sort_")
                || key.hasPrefix("reels_session_filter_")
                || key.hasPrefix("reels_session_random_seed_")
                || key.hasPrefix("reels_playback_checkpoint_") {
                ud.removeObject(forKey: key)
            }
        }
    }

    static func string(forKey key: String) -> String? {
        lock.lock()
        let v = strings[key]
        lock.unlock()
        return v
    }

    static func setString(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value, !value.isEmpty { strings[key] = value }
        else { strings.removeValue(forKey: key) }
    }

    static func int(forKey key: String) -> Int {
        lock.lock()
        let v = ints[key] ?? 0
        lock.unlock()
        return v
    }

    static func setInt(_ value: Int, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if value > 0 { ints[key] = value }
        else { ints.removeValue(forKey: key) }
    }

}

struct ReelsViewBody: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedMarkerFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var isMuted = !isHeadphonesConnected() // Shared mute state for Reels
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    @State private var sceneToDelete: Scene?
    @State private var reelsMode: ReelsMode = ReelsMode(from: TabManager.shared.enabledReelsModes.first ?? .scenes)
    @State private var selectedMarkerSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .markers) ?? "") ?? .random
    @StateObject private var reelsClipImageFilters = DetailLinkedImagesFilterModel(
        scope: .reelsClips,
        initialSort: StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .clips) ?? "") ?? .random
    )
    @State private var selectedPreviewFilter: StashDBViewModel.SavedFilter?
    @State private var showReelsSceneFilterSheet = false
    /// While the scene-style filter sheet hydrates UI (migration / saved-filter list), ignore preset `onChange` so we do not refetch the Reels timeline.
    @State private var reelsSceneFilterSheetHydrating = false
    /// Same idea for the clips image filter sheet (`catalogPresetRowSelection` updates).
    @State private var reelsClipFilterSheetHydrating = false
    @State private var reelsSceneLiveSheetPresetSelection = ""
    @State private var reelsMarkerLiveSheetPresetSelection = ""
    @State private var reelsPreviewLiveSheetPresetSelection = ""
    @State private var reelsSceneLiveChips = SceneLiveChipRowState()
    @State private var reelsMarkerLiveChips = SceneLiveChipRowState()
    @State private var reelsPreviewLiveChips = SceneLiveChipRowState()
    @State private var reelsStudioPickerOptions: [Studio] = []
    @State private var reelsStudioPickerLoading = false
    @State private var reelsTagPickerOptions: [Tag] = []
    @State private var reelsTagPickerLoading = false
    @State private var reelsGroupPickerOptions: [StashGroup] = []
    @State private var reelsGroupPickerLoading = false
    @State private var reelsSceneLivePresets: [SceneLiveFilterPreset] = SceneLiveFilterPresetStore.loadPresets()
    @State private var reelsScenePresetNameInput = ""
    @State private var showReelsSceneSaveAsAlert = false
    @State private var showReelsSceneRenameAlert = false
    @State private var showReelsSceneDeleteAlert = false
    @State private var isMenuOpen = false
    @State private var isMediaZoomed = false
    @State private var isRotating = false
    @State private var isUIVisible = true
    @State private var isUserScrollingReels = false
    /// Snapshot of autoplay when a scroll gesture leaves `.idle` (restore after settle, don't force-play if user had paused).
    @State private var reelsWasPlayingBeforeScrollGesture = true
    @State private var currentItemIsPlaying = true
    @State private var currentItemShowRatingOverlay = false
    @State private var showStashSyncSheet = false
    @State private var scrubberState = ScrubberState()
    @State private var isInitialized = false
    @State private var playTrigger = 0  // Incremented when first item should autoplay
    @State private var pendingRestoreId: String? = nil
    @State private var shouldScrollToTopAfterCriterionChange: Bool = false

    // MARK: - Session-persisted sort/filter (per server + mode)
    private func reelsSessionSortKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_sort_\(serverID)_\(mode.rawValue)"
    }

    private func reelsSessionFilterKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_filter_\(serverID)_\(mode.rawValue)"
    }

    private func sessionSortRaw(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionSortKey(for: mode))
    }

    private func sessionFilterId(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionFilterKey(for: mode))
    }

    private func saveSessionState(for mode: ReelsMode) {
        // Sort
        let sortRaw: String? = {
            switch mode {
            case .scenes: return selectedSortOption.rawValue
            case .markers: return selectedMarkerSortOption.rawValue
            case .clips: return reelsClipImageFilters.selectedSortOption.rawValue
            case .previews: return selectedSortOption.rawValue
            }
        }()
        if let raw = sortRaw {
            ReelsSessionRAM.setString(raw, forKey: reelsSessionSortKey(for: mode))
        }

        // Filter
        let filterId: String? = {
            switch mode {
            case .scenes:
                return selectedFilter?.id
            case .markers:
                return selectedMarkerFilter?.id
            case .clips:
                return reelsClipImageFilters.selectedFilter?.id
            case .previews:
                return selectedPreviewFilter?.id
            }
        }()
        if let id = filterId, !id.isEmpty {
            ReelsSessionRAM.setString(id, forKey: reelsSessionFilterKey(for: mode))
        } else {
            ReelsSessionRAM.setString(nil, forKey: reelsSessionFilterKey(for: mode))
        }
    }

    /// Saved filter used to decide whether live scene chips may merge into the GraphQL query.
    private var reelsLiveChipTargetFilter: StashDBViewModel.SavedFilter? {
        switch reelsMode {
        case .scenes: return selectedFilter
        case .markers: return selectedMarkerFilter
        case .previews: return selectedPreviewFilter
        default: return nil
        }
    }

    private var reelsActiveSceneStyleSheetPresetSelection: Binding<String> {
        Binding(
            get: {
                switch reelsMode {
                case .scenes: return reelsSceneLiveSheetPresetSelection
                case .markers: return reelsMarkerLiveSheetPresetSelection
                case .previews: return reelsPreviewLiveSheetPresetSelection
                default: return reelsSceneLiveSheetPresetSelection
                }
            },
            set: { new in
                switch reelsMode {
                case .scenes: reelsSceneLiveSheetPresetSelection = new
                case .markers: reelsMarkerLiveSheetPresetSelection = new
                case .previews: reelsPreviewLiveSheetPresetSelection = new
                default: reelsSceneLiveSheetPresetSelection = new
                }
            }
        )
    }

    private var reelsActiveSheetPresetIdForRead: String {
        switch reelsMode {
        case .scenes: return reelsSceneLiveSheetPresetSelection
        case .markers: return reelsMarkerLiveSheetPresetSelection
        case .previews: return reelsPreviewLiveSheetPresetSelection
        default: return reelsSceneLiveSheetPresetSelection
        }
    }

    private func reelsSetActiveSheetPresetSelection(_ new: String) {
        switch reelsMode {
        case .scenes: reelsSceneLiveSheetPresetSelection = new
        case .markers: reelsMarkerLiveSheetPresetSelection = new
        case .previews: reelsPreviewLiveSheetPresetSelection = new
        default: reelsSceneLiveSheetPresetSelection = new
        }
    }

    private func reelsClearActiveLiveChipsOnly() {
        switch reelsMode {
        case .scenes: reelsSceneLiveChips.clearChipsOnly()
        case .markers: reelsMarkerLiveChips.clearChipsOnly()
        case .previews: reelsPreviewLiveChips.clearChipsOnly()
        default: reelsSceneLiveChips.clearChipsOnly()
        }
    }

    private func reelsLoadStudioPickerOptions() {
        guard !reelsStudioPickerLoading else { return }
        reelsStudioPickerLoading = true
        viewModel.fetchStudiosForLiveFilterPicker(mode: .scenesHasScenes) { list in
            reelsStudioPickerOptions = list
            reelsStudioPickerLoading = false
        }
    }

    private func reelsLoadTagPickerOptions() {
        guard !reelsTagPickerLoading else { return }
        reelsTagPickerLoading = true
        viewModel.fetchTagsForSceneLiveFilterPicker { list in
            reelsTagPickerOptions = list
            reelsTagPickerLoading = false
        }
    }

    private func reelsLoadGroupPickerOptions() {
        guard !reelsGroupPickerLoading else { return }
        reelsGroupPickerLoading = true
        viewModel.fetchGroupsForSceneLiveFilterPicker { list in
            reelsGroupPickerOptions = list
            reelsGroupPickerLoading = false
        }
    }

    /// When the saved filter is not chip-safe, still restore studio / tag / group from the fragment or flat dict.
    private func reelsApplyAuxIdsFromLiveFragment(_ frag: [String: Any]) {
        let f = FilterMapper.sanitize(frag, isMarker: false)
        switch reelsMode {
        case .scenes:
            var c = reelsSceneLiveChips
            c.studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["studios"])
            c.tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["tags"])
            c.groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["groups"])
            reelsSceneLiveChips = c
        case .markers:
            var c = reelsMarkerLiveChips
            c.studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["studios"])
            c.tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["tags"])
            c.groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["groups"])
            reelsMarkerLiveChips = c
        case .previews:
            var c = reelsPreviewLiveChips
            c.studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["studios"])
            c.tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["tags"])
            c.groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: f["groups"])
            reelsPreviewLiveChips = c
        default:
            break
        }
    }

    /// Keeps only the sheet preset row aligned with the active saved filter.
    /// This is safe on sheet open / saved-filter refresh because it does not overwrite live chips.
    private func reelsSyncFilterSheetPresetRow(for mode: ReelsMode? = nil) {
        let mode = mode ?? reelsMode
        switch mode {
        case .scenes:
            if let f = selectedFilter {
                reelsSceneLiveSheetPresetSelection = SceneLivePresetTag.serverRow(f.id)
            } else {
                reelsSceneLiveSheetPresetSelection = ""
            }
        case .markers:
            if let f = selectedMarkerFilter {
                reelsMarkerLiveSheetPresetSelection = SceneLivePresetTag.serverRow(f.id)
            } else {
                reelsMarkerLiveSheetPresetSelection = ""
            }
        case .previews:
            if let f = selectedPreviewFilter {
                reelsPreviewLiveSheetPresetSelection = SceneLivePresetTag.serverRow(f.id)
            } else {
                reelsPreviewLiveSheetPresetSelection = ""
            }
        case .clips:
            reelsSyncClipCatalogPresetPickerSelection()
        }
    }

    private func reelsSyncClipCatalogPresetPickerSelection() {
        reelsClipImageFilters.applyResolvedCatalogPresetPickerRowIfNeeded(viewModel: viewModel)
    }

    /// Keeps filter-sort sheet preset rows and live chips aligned with `@State` selections (e.g. after defaults or session restore).
    /// - Parameter mode: Pass the target sub-mode when syncing from `handleModeChange` so state matches `newValue` even if `reelsMode` lags one tick.
    private func reelsSyncFilterSheetPresetAndLiveChips(for mode: ReelsMode? = nil, savedFilters: [String: StashDBViewModel.SavedFilter]) {
        let mode = mode ?? reelsMode
        reelsSyncFilterSheetPresetRow(for: mode)
        switch mode {
        case .scenes:
            var sceneChips = reelsSceneLiveChips
            sceneChips.syncLiveChipsToMatchSelectedFilter(selectedFilter, savedFilters: savedFilters)
            reelsSceneLiveChips = sceneChips
        case .markers:
            var markerChips = reelsMarkerLiveChips
            markerChips.syncLiveChipsToMatchSelectedFilter(selectedMarkerFilter, savedFilters: savedFilters)
            reelsMarkerLiveChips = markerChips
        case .previews:
            var previewChips = reelsPreviewLiveChips
            previewChips.syncLiveChipsToMatchSelectedFilter(selectedPreviewFilter, savedFilters: savedFilters)
            reelsPreviewLiveChips = previewChips
        case .clips:
            break
        }
    }

    private func reelsActiveLiveChipsActiveLiveFilterDict() -> [String: Any] {
        switch reelsMode {
        case .scenes: return reelsSceneLiveChips.activeLiveFilterDict()
        case .markers: return reelsMarkerLiveChips.activeLiveFilterDict()
        case .previews: return reelsPreviewLiveChips.activeLiveFilterDict()
        default: return reelsSceneLiveChips.activeLiveFilterDict()
        }
    }

    private func reelsMapLiveFragmentToActiveChips(_ frag: [String: Any]) {
        switch reelsMode {
        case .scenes: reelsSceneLiveChips.mapLiveFragmentToChips(frag)
        case .markers: reelsMarkerLiveChips.mapLiveFragmentToChips(frag)
        case .previews: reelsPreviewLiveChips.mapLiveFragmentToChips(frag)
        default: reelsSceneLiveChips.mapLiveFragmentToChips(frag)
        }
    }

    private func reelChipBinding<Value>(_ keyPath: WritableKeyPath<SceneLiveChipRowState, Value>) -> Binding<Value> {
        Binding(
            get: {
                switch reelsMode {
                case .scenes: return reelsSceneLiveChips[keyPath: keyPath]
                case .markers: return reelsMarkerLiveChips[keyPath: keyPath]
                case .previews: return reelsPreviewLiveChips[keyPath: keyPath]
                default: return reelsSceneLiveChips[keyPath: keyPath]
                }
            },
            set: { newValue in
                switch reelsMode {
                case .scenes: reelsSceneLiveChips[keyPath: keyPath] = newValue
                case .markers: reelsMarkerLiveChips[keyPath: keyPath] = newValue
                case .previews: reelsPreviewLiveChips[keyPath: keyPath] = newValue
                default: reelsSceneLiveChips[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var sortedServerSceneFiltersForReels: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .scenes }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reels filter sheet: Szenen- und Vorschau-Modus nutzen Szenenfilter; Marker-Modus `SCENE_MARKERS`.
    private var reelsSceneStyleSheetServerFilters: [StashDBViewModel.SavedFilter] {
        switch reelsMode {
        case .markers:
            return viewModel.savedFilters.values
                .filter { $0.mode == .sceneMarkers }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .scenes, .previews:
            return sortedServerSceneFiltersForReels
        default:
            return sortedServerSceneFiltersForReels
        }
    }

    private func refetchReelsClipsFromModel(_ vm: StashDBViewModel) {
        let merged = vm.mergeFilterWithCriteria(
            filter: reelsClipImageFilters.selectedFilter,
            performer: selectedPerformer,
            tags: selectedTags,
            mode: .images
        )
        vm.fetchClips(
            sortBy: reelsClipImageFilters.selectedSortOption,
            filter: merged,
            isInitialLoad: true,
            liveFilter: reelsClipImageFilters.imageLiveFragmentForFetch()
        )
        vm.clearReelsCriterionFrozenSnapshots()
        currentVisibleSceneId = nil
        saveSessionState(for: .clips)
        playTrigger += 1
    }

    private func reelsRefreshSceneLivePresets() {
        reelsSceneLivePresets = SceneLiveFilterPresetStore.loadPresets()
    }

    private func changeReelsSceneSortFromSheet(_ new: StashDBViewModel.SceneSortOption) {
        if new == .random && selectedSortOption == .random {
            if reelsMode == .previews {
                viewModel.refreshRandomSeed(for: .previews)
                persistSessionRandomSeed(for: .previews)
            } else {
                viewModel.refreshRandomSeed(for: .scenes)
                persistSessionRandomSeed(for: .scenes)
            }
        }
        selectedSortOption = new
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: new, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
        case .previews:
            applySettings(previewSortBy: new, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
        default:
            break
        }
    }

    private func changeReelsMarkerSortFromSheet(_ new: StashDBViewModel.SceneMarkerSortOption) {
        if new == .random && selectedMarkerSortOption == .random {
            viewModel.refreshRandomSeed(for: .markers)
            persistSessionRandomSeed(for: .markers)
        }
        selectedMarkerSortOption = new
        applySettings(markerSortBy: new, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
    }

    private func reelsApplySceneLiveFromSheet() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, sceneLiveRefresh: true)
        default:
            break
        }
    }

    private var reelsSceneDeletePresetConfirmationText: String {
        let sel = reelsActiveSheetPresetIdForRead
        if let sid = SceneLivePresetTag.parseServerId(sel),
           let f = viewModel.savedFilters[sid] {
            return "„\(f.name)“ in Stash entfernen? Andere Clients verlieren diesen gespeicherten Filter."
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
           let uuid = UUID(uuidString: ls),
           let p = reelsSceneLivePresets.first(where: { $0.id == uuid }) {
            return "„\(p.name)“ von diesem Gerät entfernen? Das kann nicht rückgängig gemacht werden."
        }
        return "Diesen Filter entfernen? Das kann nicht rückgängig gemacht werden."
    }

    private func reelsSetPrimarySceneishSavedFilter(_ f: StashDBViewModel.SavedFilter?) {
        switch reelsMode {
        case .previews:
            selectedPreviewFilter = f
        case .markers:
            selectedMarkerFilter = f
        default:
            selectedFilter = f
        }
    }

    private func reelsHandleScenePresetSelectionChange(_ newId: String) {
        if newId.isEmpty {
            reelsSetPrimarySceneishSavedFilter(nil)
            reelsClearActiveLiveChipsOnly()
            reelsApplySceneLiveFromSheet()
            return
        }
        if let sid = SceneLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            reelsApplyServerSceneSavedFilterForReels(f)
            return
        }
        if let ls = SceneLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = reelsSceneLivePresets.first(where: { $0.id == uuid }) {
            reelsApplyLiveScenePresetForReels(preset)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = reelsSceneLivePresets.first(where: { $0.id == uuid }) {
            reelsSetActiveSheetPresetSelection(SceneLivePresetTag.localRow(uuid))
            reelsApplyLiveScenePresetForReels(preset)
        }
    }

    private func reelsApplyLiveScenePresetForReels(_ preset: SceneLiveFilterPreset) {
        let sort = StashDBViewModel.SceneSortOption(rawValue: preset.sortRaw) ?? selectedSortOption
        if sort != selectedSortOption {
            selectedSortOption = sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            reelsSetPrimarySceneishSavedFilter(f)
        } else {
            reelsSetPrimarySceneishSavedFilter(nil)
        }
        if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(reelsLiveChipTargetFilter) {
            reelsMapLiveFragmentToActiveChips(preset.liveFragment)
        } else {
            reelsClearActiveLiveChipsOnly()
            reelsApplyAuxIdsFromLiveFragment(preset.liveFragment)
        }
        reelsApplySceneLiveFromSheet()
    }

    private func reelsApplyServerSceneSavedFilterForReels(_ f: StashDBViewModel.SavedFilter) {
        if let meta = f.stashyScenePresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                reelsSetPrimarySceneishSavedFilter(base)
            } else {
                reelsSetPrimarySceneishSavedFilter(nil)
            }
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(reelsLiveChipTargetFilter) {
                reelsMapLiveFragmentToActiveChips(meta.liveFragment)
            } else {
                reelsClearActiveLiveChipsOnly()
                reelsApplyAuxIdsFromLiveFragment(meta.liveFragment)
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.SceneSortOption(rawValue: sr) {
                selectedSortOption = parsed
            }
        } else {
            reelsSetPrimarySceneishSavedFilter(f)
            let sanitizeAsMarker = (f.mode == .sceneMarkers)
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(f), let raw = f.filterDict {
                reelsMapLiveFragmentToActiveChips(raw)
            } else {
                reelsClearActiveLiveChipsOnly()
                let flat: [String: Any]? = {
                    if let raw = f.filterDict { return FilterMapper.sanitize(raw, isMarker: sanitizeAsMarker) }
                    if let obj = f.object_filter, let objDict = obj.value as? [String: Any] {
                        return FilterMapper.sanitize(objDict, isMarker: sanitizeAsMarker)
                    }
                    return nil
                }()
                if let flat { reelsApplyAuxIdsFromLiveFragment(flat) }
            }
        }
        reelsApplySceneLiveFromSheet()
    }

    private func reelsSaveSceneLivePresetOverwrite() {
        let sel = reelsActiveSheetPresetIdForRead
        let liveDict = reelsActiveLiveChipsActiveLiveFilterDict()
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            let currentName = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveSceneSavedFilter(
                existingId: sid,
                name: currentName,
                sort: selectedSortOption,
                baseFilter: reelsLiveChipTargetFilter,
                liveFragment: liveDict
            ) { _ in }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = reelsSceneLivePresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = reelsSceneLivePresets[index]
        let updated = SceneLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: reelsLiveChipTargetFilter?.id,
            liveFragment: liveDict
        )
        SceneLiveFilterPresetStore.upsert(updated)
        reelsRefreshSceneLivePresets()
    }

    private func reelsSaveSceneLivePresetAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveSceneSavedFilter(
            existingId: nil,
            name: trimmed,
            sort: selectedSortOption,
            baseFilter: reelsLiveChipTargetFilter,
            liveFragment: reelsActiveLiveChipsActiveLiveFilterDict()
        ) { result in
            if case .success(let saved) = result {
                reelsSetActiveSheetPresetSelection(SceneLivePresetTag.serverRow(saved.id))
                showReelsSceneSaveAsAlert = false
            }
        }
    }

    private func reelsRenameSceneLivePreset(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = reelsActiveSheetPresetIdForRead
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.saveSceneSavedFilter(
                existingId: sid,
                name: trimmed,
                sort: selectedSortOption,
                baseFilter: reelsLiveChipTargetFilter,
                liveFragment: reelsActiveLiveChipsActiveLiveFilterDict()
            ) { result in
                if case .success = result {
                    showReelsSceneRenameAlert = false
                }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = reelsSceneLivePresets.first(where: { $0.id == uuid }) else { return }
        let renamed = preset.renamed(trimmed)
        SceneLiveFilterPresetStore.upsert(renamed)
        reelsRefreshSceneLivePresets()
        showReelsSceneRenameAlert = false
    }

    private func reelsDeleteSceneLivePreset() {
        let sel = reelsActiveSheetPresetIdForRead
        if let sid = SceneLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { result in
                if case .success = result {
                    if reelsMode == .previews, selectedPreviewFilter?.id == sid {
                        selectedPreviewFilter = nil
                    } else if reelsMode == .markers, selectedMarkerFilter?.id == sid {
                        selectedMarkerFilter = nil
                    } else if selectedFilter?.id == sid {
                        selectedFilter = nil
                    }
                    reelsSetActiveSheetPresetSelection("")
                    showReelsSceneDeleteAlert = false
                    reelsApplySceneLiveFromSheet()
                }
            }
            return
        }
        guard let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        SceneLiveFilterPresetStore.remove(id: uuid)
        reelsRefreshSceneLivePresets()
        reelsSetActiveSheetPresetSelection("")
        showReelsSceneDeleteAlert = false
    }

    /// Maps a ReelsMode to the VM's per-kind random-seed bucket.
    private func seedKind(for mode: ReelsMode) -> StashDBViewModel.RandomSeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .markers: return .markers
        case .clips: return .images   // clips are served via findImages
        case .previews: return .previews
        }
    }

    private func reelsSessionRandomSeedKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_random_seed_\(serverID)_\(mode.rawValue)"
    }

    /// Restore per-mode session seeds so Scenes / Previews / Markers / Clips keep
    /// independent but stable "random" orders across navigation.
    private func restoreSessionRandomSeedIfAvailable() {
        for mode in [ReelsMode.scenes, .markers, .clips, .previews] {
            guard let kind = seedKind(for: mode) else { continue }
            let seed = ReelsSessionRAM.int(forKey: reelsSessionRandomSeedKey(for: mode))
            if seed > 0 {
                viewModel.setRandomSeed(seed, for: kind)
            }
        }
    }

    private func persistSessionRandomSeed(for mode: ReelsMode) {
        guard let kind = seedKind(for: mode) else { return }
        ReelsSessionRAM.setInt(viewModel.getRandomSeed(for: kind), forKey: reelsSessionRandomSeedKey(for: mode))
    }

    private func reelsPositionKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_last_visible_\(serverID)_\(mode.rawValue)"
    }

    private func expectedPrefix(for mode: ReelsMode) -> String? {
        switch mode {
        case .scenes: return "scene"
        case .markers: return "marker"
        case .clips: return "clip"
        case .previews: return "preview"
        }
    }

    private func savedPosition(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsPositionKey(for: mode))
    }

    private func savePosition(_ id: String, for mode: ReelsMode) {
        ReelsSessionRAM.setString(id, forKey: reelsPositionKey(for: mode))
    }

    private func saveCurrentPositionIfPossible(for mode: ReelsMode) {
        guard let prefix = expectedPrefix(for: mode) else { return }
        guard let id = currentVisibleSceneId, id.hasPrefix("\(prefix)-") else { return }
        savePosition(id, for: mode)
    }

    private func reelsPlaybackCheckpointKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_playback_checkpoint_\(serverID)_\(mode.rawValue)"
    }

    /// Persists `itemId|seconds` so resume can seek only when the same item is still active.
    private func savePlaybackCheckpoint(for mode: ReelsMode) {
        guard let id = currentVisibleSceneId else {
            ReelsSessionRAM.setString(nil, forKey: reelsPlaybackCheckpointKey(for: mode))
            return
        }
        let time = scrubberState.time
        guard time.isFinite, time > 0.25 else {
            ReelsSessionRAM.setString(nil, forKey: reelsPlaybackCheckpointKey(for: mode))
            return
        }
        ReelsSessionRAM.setString("\(id)|\(time)", forKey: reelsPlaybackCheckpointKey(for: mode))
    }

    /// Applies a matching checkpoint to the scrubber (seek happens via `seekTarget` on the active row).
    private func applySavedPlaybackCheckpointIfMatching() {
        guard let raw = ReelsSessionRAM.string(forKey: reelsPlaybackCheckpointKey(for: reelsMode)),
              let sep = raw.lastIndex(of: "|") else { return }
        let id = String(raw[..<sep])
        let time = Double(raw[raw.index(after: sep)...]) ?? 0
        guard id == currentVisibleSceneId, time.isFinite, time > 0.25 else { return }
        scrubberState.time = time
        scrubberState.seekTarget = time
    }

    private func restorePositionIfAvailable(for mode: ReelsMode, forceIfPrefixMismatch: Bool) {
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        let expected = expectedPrefix(for: mode)

        if forceIfPrefixMismatch {
            if let expected, currentPrefix == expected { return }
        } else {
            guard currentVisibleSceneId == nil else { return }
        }

        // Keep restore target OUTSIDE of `currentVisibleSceneId`. Setting an ID
        // into `.scrollPosition(id:)` that isn't in the list yet causes SwiftUI
        // to visually stall (black view) until it appears.
        if let saved = savedPosition(for: mode), !saved.isEmpty {
            pendingRestoreId = saved
        }
    }

    private func beginPagedRestoreIfNeeded() {
        guard let targetId = pendingRestoreId ?? currentVisibleSceneId else {
            pendingRestoreId = nil
            return
        }
        // If it's already present, we're done.
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            return
        }
        pendingRestoreId = targetId
        continuePagedRestoreIfNeeded()
    }

    private func continuePagedRestoreIfNeeded() {
        guard let targetId = pendingRestoreId else { return }

        // Stop when found.
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            return
        }

        // Load more until we either find it or run out of pages.
        switch reelsMode {
        case .scenes:
            guard viewModel.hasMoreScenes, !viewModel.isLoadingMoreScenes else { return }
            viewModel.loadMoreScenes()
        case .markers:
            guard viewModel.hasMoreMarkers, !viewModel.isLoadingMarkers else { return }
            viewModel.loadMoreMarkers()
        case .clips:
            guard viewModel.hasMoreClips, !viewModel.isLoadingClips else { return }
            viewModel.loadMoreClips()
        case .previews:
            guard viewModel.hasMorePreviews, !viewModel.isLoadingMorePreviews else { return }
            viewModel.loadMorePreviews()
        }
    }

    // Extracted binding to help the Swift compiler with type-checking
    // Native scroll binding
    private var scrollPositionBinding: Binding<String?> {
        Binding<String?>(
            get: { currentVisibleSceneId },
            set: { newValue in
                currentVisibleSceneId = newValue
            }
        )
    }

    /// True while paging may rewrite `scrollPosition` before the snap finishes (defer next row `AVPlayer` setup).
    /// Excludes `.tracking` so a touch without drag does not pause the current clip or clear `isPlaybackActive`.
    private func reelsScrollDelaysPagingIdentityDrift(_ phase: ScrollPhase) -> Bool {
        switch phase {
        case .idle, .tracking:
            return false
        case .interacting, .decelerating, .animating:
            return true
        @unknown default:
            return true
        }
    }

    enum ReelsMode: String, CaseIterable {
        case scenes = "Scenes"
        case markers = "Markers"
        case clips = "Clips"
        case previews = "Previews"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .markers: return "bookmark.fill"
            case .clips: return "photo.on.rectangle.angled"
            case .previews: return "play.rectangle.on.rectangle.fill"
            }
        }
        
        var toModeType: ReelsModeType {
            switch self {
            case .scenes: return .scenes
            case .markers: return .markers
            case .clips: return .clips
            case .previews: return .previews
            }
        }
        
        init(from type: ReelsModeType) {
            switch type {
            case .scenes: self = .scenes
            case .markers: self = .markers
            case .clips: self = .clips
            case .previews: self = .previews
            case .pics: self = .scenes // Codable migration: legacy Pics → Scenes
            }
        }
    }

    enum ReelItemData: Identifiable {
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

        var title: String? {
            func nonEmpty(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return t
            }
            func fileNameFromPath(_ path: String?) -> String? {
                guard let p = nonEmpty(path) else { return nil }
                let clean = p.components(separatedBy: "?").first ?? p
                return URL(fileURLWithPath: clean).lastPathComponent
            }

            switch self {
            case .scene(let s):
                if let t = nonEmpty(s.title) { return t }
                // Fallback: use filename if title is missing
                if let name = fileNameFromPath(s.files?.first?.path) { return name }
                if let name = fileNameFromPath(s.paths?.stream) { return name }
                return nil
            case .marker(let m):
                if let t = nonEmpty(m.scene?.title) { return t }
                if let name = fileNameFromPath(m.scene?.files?.first?.path) { return name }
                if let name = fileNameFromPath(m.scene?.paths?.stream) { return name }
                return nil
            case .clip(let c):
                if let t = nonEmpty(c.title) { return t }
                // Fallback: show filename when no title is present
                if let name = fileNameFromPath(c.visual_files?.first?.path) { return name }
                if let name = fileNameFromPath(c.paths?.image) { return name }
                return nil
            case .preview(let s):
                if let t = nonEmpty(s.title) { return t }
                if let name = fileNameFromPath(s.files?.first?.path) { return name }
                if let name = fileNameFromPath(s.paths?.stream) { return name }
                return nil
            }
        }
        
        var performers: [ScenePerformer] {
            switch self {
            case .scene(let s): return s.performers
            case .marker(let m): return m.scene?.performers ?? []
            case .clip(let c): return c.performers?.map { ScenePerformer(id: $0.id, name: $0.name, birthdate: nil, sceneCount: nil, galleryCount: nil, oCounter: nil, updatedAt: nil) } ?? []
            case .preview(let s): return s.performers
            }
        }
        
        var tags: [Tag] {
            switch self {
            case .scene(let s): return s.tags ?? []
            case .marker(let m):
                var allTags = m.tags ?? []
                if let primary = m.primaryTag {
                    allTags.insert(primary, at: 0)
                }
                return allTags
            case .clip(let c): return c.tags ?? []
            case .preview(let s): return s.tags ?? []
            }
        }
        
        var videoURL: URL? {
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            switch self {
            case .scene(let s):
                // 0. Check local first
                if let local = s.videoURL, !local.absoluteString.hasPrefix("http") {
                    return local
                }
                return s.bestStream(for: quality) ?? s.videoURL
                
            case .marker(let m):
                let potentialURL: URL?
                if let streamPath = m.stream, let url = URL(string: streamPath) {
                    potentialURL = url
                } else if let config = ServerConfigManager.shared.loadConfig() {
                    potentialURL = URL(string: "\(config.baseURL)/scenemarker/\(m.id)/stream")
                } else {
                    potentialURL = nil
                }
                
                guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty, let url = potentialURL else { return potentialURL }
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = comps?.queryItems ?? []
                if !items.contains(where: { $0.name == "apikey" }) {
                    items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
                    comps?.queryItems = items
                }
                return comps?.url ?? url
                
            case .clip(let c):
                // For clips (images that are videos or animations), the imagePath IS the video path
                return c.imageURL
            case .preview(let s):
                return s.previewURL
            }
        }
        
        var startTime: Double {
            switch self {
            case .scene: return 0
            case .marker: return 0
            case .clip: return 0
            case .preview: return 0
            }
        }

        var duration: Double? {
            switch self {
            case .scene(let s): return s.duration
            case .marker(let m): 
                if let end = m.endSeconds { return end - m.seconds }
                return nil
            case .clip(let c): return c.visual_files?.first?.duration
            case .preview(let s): return s.duration
            }
        }
        
        var isPortrait: Bool {
            switch self {
            case .scene(let s): return s.isPortrait
            case .marker(let m):
                if let width = m.scene?.files?.first?.width, let height = m.scene?.files?.first?.height {
                    return height > width
                }
                return false
            case .clip(let c):
                // Metadata width/height can ignore container rotation; prefer caller
                // using AVPlayer `presentationSize` when available.
                if let file = c.visual_files?.first {
                    return (file.height ?? 0) > (file.width ?? 0)
                }
                return false
            case .preview(let s): return s.isPortrait
            }
        }

        var rating100: Int? {
            switch self {
            case .scene(let s): return s.rating100
            case .marker(let m): return m.scene?.rating100
            case .clip(let c): return c.rating100
            case .preview(let s): return s.rating100
            }
        }
        
        var oCounter: Int? {
            switch self {
            case .scene(let s): return s.oCounter
            case .marker(let m): return m.scene?.oCounter
            case .clip(let c): return c.o_counter
            case .preview(let s): return s.oCounter
            }
        }
        
        var playCount: Int? {
            switch self {
            case .scene(let s): return s.playCount
            case .marker(let m): return m.playCount
            case .clip: return nil  // Images don't track play count
            case .preview(let s): return s.playCount
            }
        }
        
        var dateString: String? {
            switch self {
            case .scene(let s): return s.date
            case .marker(let m): return m.scene?.date
            case .clip(let c): return c.date
            case .preview(let s): return s.date
            }
        }
        
        var sceneID: String? {
            switch self {
            case .scene(let s): return s.id
            case .marker(let m): return m.scene?.id
            case .clip: return nil  // Clips are images, not scenes
            case .preview(let s): return s.id
            }
        }
        
        var isAnimated: Bool {
            switch self {
            case .clip(let c):
                let ext = c.fileExtension?.uppercased()
                return ext == "GIF" || ext == "WEBP"
            case .scene: return false
            case .marker: return false
            case .preview: return false
            }
        }

        var underlyingScene: Scene? {
            switch self {
            case .scene(let s): return s
            case .marker(let m): return m.scene?.toScene()
            case .clip: return nil
            case .preview(let s): return s
            }
        }

    }

    private var currentReelItems: [ReelItemData] {
        switch reelsMode {
        case .scenes: return viewModel.scenes.map { ReelItemData.scene($0) }
        case .markers: return viewModel.sceneMarkers.filter { $0.stream != nil && !$0.stream!.isEmpty }.map { ReelItemData.marker($0) }
        case .clips: return viewModel.clips.map { ReelItemData.clip($0) }
        case .previews: return viewModel.previews.map { ReelItemData.preview($0) }
        }
    }

    

    private func applyPerformerFilter(_ performer: ScenePerformer) {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: performer, tags: selectedTags)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: performer, tags: selectedTags)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: performer, tags: selectedTags)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: performer, tags: selectedTags)
        }
    }

    private func applyTagsChange(_ newTags: [Tag]) {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: newTags)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: newTags)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: newTags)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: newTags)
        }
    }

    private func applyClearPerformerOnly() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: nil, tags: selectedTags)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: nil, tags: selectedTags)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: nil, tags: selectedTags)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: nil, tags: selectedTags)
        }
    }

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, previewSortBy: StashDBViewModel.SceneSortOption? = nil, sceneFilter: StashDBViewModel.SavedFilter? = nil, markerFilter: StashDBViewModel.SavedFilter? = nil, clipFilter: StashDBViewModel.SavedFilter? = nil, previewFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil, clearClipFilter: Bool = false, clearSceneFilter: Bool = false, clearMarkerFilter: Bool = false, clearPreviewFilter: Bool = false, rerollRandom: Bool = false, sceneLiveRefresh: Bool = false, clipImageLiveRefresh: Bool = false) {
        let priorMode = reelsMode
        let currentMode = mode ?? reelsMode
        if let providedMode = mode {
            reelsMode = providedMode
        }
        if let m = mode, m != priorMode {
            viewModel.clearReelsCriterionFrozenSnapshots()
        }

        let resolvedClipFilter: StashDBViewModel.SavedFilter?
        if clearClipFilter {
            resolvedClipFilter = nil
        } else if clipFilter != nil {
            resolvedClipFilter = clipFilter
        } else {
            resolvedClipFilter = reelsClipImageFilters.selectedFilter
        }

        let resolvedSceneFilterEarly: StashDBViewModel.SavedFilter?
        if clearSceneFilter {
            resolvedSceneFilterEarly = nil
        } else if sceneFilter != nil {
            resolvedSceneFilterEarly = sceneFilter
        } else {
            resolvedSceneFilterEarly = selectedFilter
        }

        let resolvedMarkerFilterEarly: StashDBViewModel.SavedFilter?
        if clearMarkerFilter {
            resolvedMarkerFilterEarly = nil
        } else if markerFilter != nil {
            resolvedMarkerFilterEarly = markerFilter
        } else {
            resolvedMarkerFilterEarly = selectedMarkerFilter
        }

        let resolvedPreviewFilterEarly: StashDBViewModel.SavedFilter?
        if clearPreviewFilter {
            resolvedPreviewFilterEarly = nil
        } else if previewFilter != nil {
            resolvedPreviewFilterEarly = previewFilter
        } else {
            resolvedPreviewFilterEarly = selectedPreviewFilter
        }

        // User explicitly changed sort or saved filter → new timeline; drop frozen main feed.
        let sortMutated =
            (sortBy != nil && sortBy != selectedSortOption) ||
            (markerSortBy != nil && markerSortBy != selectedMarkerSortOption) ||
            (clipSortBy != nil && clipSortBy != reelsClipImageFilters.selectedSortOption) ||
            (previewSortBy != nil && previewSortBy != selectedSortOption)
        let sceneSavedFilterMutated = resolvedSceneFilterEarly?.id != selectedFilter?.id
        let markerSavedFilterMutated = resolvedMarkerFilterEarly?.id != selectedMarkerFilter?.id
        let clipSavedFilterMutated = resolvedClipFilter?.id != reelsClipImageFilters.selectedFilter?.id
        let previewSavedFilterMutated = resolvedPreviewFilterEarly?.id != selectedPreviewFilter?.id
        let timelineMutated = sortMutated || sceneSavedFilterMutated || markerSavedFilterMutated || clipSavedFilterMutated || previewSavedFilterMutated || sceneLiveRefresh || clipImageLiveRefresh
        if timelineMutated {
            viewModel.clearReelsCriterionFrozenSnapshots()
        }

        let hadCriterionOverlay = selectedPerformer != nil || !selectedTags.isEmpty
        let willCriterionOverlay = performer != nil || !tags.isEmpty

        var usedFrozenRestore = false
        if hadCriterionOverlay && !willCriterionOverlay && !timelineMutated {
            pendingRestoreId = nil
            switch currentMode {
            case .clips:
                if let vid = viewModel.restoreReelsFrozenClipsIfAvailable() {
                    usedFrozenRestore = true
                    currentVisibleSceneId = vid
                }
            case .scenes:
                if let vid = viewModel.restoreReelsFrozenScenesIfAvailable() {
                    usedFrozenRestore = true
                    currentVisibleSceneId = vid
                }
            case .markers:
                if let vid = viewModel.restoreReelsFrozenMarkersIfAvailable() {
                    usedFrozenRestore = true
                    currentVisibleSceneId = vid
                }
            case .previews:
                if let vid = viewModel.restoreReelsFrozenPreviewsIfAvailable() {
                    usedFrozenRestore = true
                    currentVisibleSceneId = vid
                }
            }
        }

        if !hadCriterionOverlay && willCriterionOverlay && !timelineMutated {
            switch currentMode {
            case .clips:
                viewModel.takeReelsFrozenClipsSnapshot(visibleItemId: currentVisibleSceneId)
            case .scenes:
                viewModel.takeReelsFrozenScenesSnapshot(visibleItemId: currentVisibleSceneId)
            case .markers:
                viewModel.takeReelsFrozenMarkersSnapshot(visibleItemId: currentVisibleSceneId)
            case .previews:
                viewModel.takeReelsFrozenPreviewsSnapshot(visibleItemId: currentVisibleSceneId)
            }
            // Entering a criterion overlay (performer/tags) should start at the top of the
            // newly filtered timeline. Keep the old position only in the frozen snapshot.
            pendingRestoreId = nil
            currentVisibleSceneId = nil
            shouldScrollToTopAfterCriterionChange = true
        }

        // Update local state and handle random re-roll (only when explicitly requested)
        if let sortBy = sortBy {
            if rerollRandom && sortBy == .random && selectedSortOption == .random && reelsMode == .scenes {
                viewModel.refreshRandomSeed(for: .scenes)
                persistSessionRandomSeed(for: .scenes)
            }
            selectedSortOption = sortBy
            if !usedFrozenRestore { currentVisibleSceneId = nil }
        }

        if let markerSortBy = markerSortBy {
            if rerollRandom && markerSortBy == .random && selectedMarkerSortOption == .random && reelsMode == .markers {
                viewModel.refreshRandomSeed(for: .markers)
                persistSessionRandomSeed(for: .markers)
            }
            selectedMarkerSortOption = markerSortBy
            if !usedFrozenRestore { currentVisibleSceneId = nil }
        }

        if let clipSortBy = clipSortBy {
            if rerollRandom && clipSortBy == .random && reelsClipImageFilters.selectedSortOption == .random && reelsMode == .clips {
                viewModel.refreshRandomSeed(for: .images)
                persistSessionRandomSeed(for: .clips)
            }
            reelsClipImageFilters.selectedSortOption = clipSortBy
            if !usedFrozenRestore { currentVisibleSceneId = nil }
        }

        if let previewSortBy = previewSortBy {
            if rerollRandom && previewSortBy == .random && selectedSortOption == .random && reelsMode == .previews {
                viewModel.refreshRandomSeed(for: .previews)
                persistSessionRandomSeed(for: .previews)
            }
            selectedSortOption = previewSortBy
            if !usedFrozenRestore { currentVisibleSceneId = nil }
        }

        reelsClipImageFilters.selectedFilter = resolvedClipFilter

        let resolvedPreviewFilter: StashDBViewModel.SavedFilter?
        if clearPreviewFilter {
            resolvedPreviewFilter = nil
        } else if previewFilter != nil {
            resolvedPreviewFilter = previewFilter
        } else {
            resolvedPreviewFilter = selectedPreviewFilter
        }
        selectedPreviewFilter = resolvedPreviewFilter

        selectedFilter = resolvedSceneFilterEarly
        selectedMarkerFilter = resolvedMarkerFilterEarly
        selectedPerformer = performer
        selectedTags = tags

        // Merge performer and tags into filter if needed
        // IMPORTANT: Use resolved filters (not stale @State) so merges match the fetch below.
        let mergedSceneFilter = viewModel.mergeFilterWithCriteria(filter: resolvedSceneFilterEarly, performer: performer, tags: tags, mode: .scenes)
        let mergedMarkerFilter = viewModel.mergeFilterWithCriteria(filter: resolvedMarkerFilterEarly, performer: performer, tags: tags, mode: .sceneMarkers)
        let mergedClipFilter = viewModel.mergeFilterWithCriteria(filter: resolvedClipFilter, performer: performer, tags: tags, mode: .images)
        let mergedPreviewFilter = viewModel.mergeFilterWithCriteria(filter: resolvedPreviewFilter, performer: performer, tags: tags, mode: .scenes)
        let sceneLiveForScenes = reelsSceneLiveChips.effectiveLiveFilter(for: resolvedSceneFilterEarly)
        let sceneLiveForMarkers = reelsMarkerLiveChips.effectiveLiveFilter(for: resolvedMarkerFilterEarly)
        let sceneLiveForPreviews = reelsPreviewLiveChips.effectiveLiveFilter(for: resolvedPreviewFilter)

        if !usedFrozenRestore {
            switch currentMode {
            case .scenes:
                viewModel.fetchScenes(sortBy: selectedSortOption, filter: mergedSceneFilter, liveFilter: sceneLiveForScenes)
            case .markers:
                viewModel.fetchSceneMarkers(sortBy: selectedMarkerSortOption, filter: mergedMarkerFilter, liveFilter: sceneLiveForMarkers)
            case .clips:
                viewModel.fetchClips(
                    sortBy: reelsClipImageFilters.selectedSortOption,
                    filter: mergedClipFilter,
                    isInitialLoad: true,
                    liveFilter: reelsClipImageFilters.imageLiveFragmentForFetch()
                )
            case .previews:
                viewModel.fetchPreviews(sortBy: selectedSortOption, isInitialLoad: true, filter: mergedPreviewFilter, liveFilter: sceneLiveForPreviews)
            }
        }

        saveSessionState(for: currentMode)
        if usedFrozenRestore {
            playTrigger += 1
        }
    }
    
    private func autoSelectFirstItem() {
        guard !currentReelItems.isEmpty else { return }
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        guard let expectedPrefix = expectedPrefix(for: reelsMode) else { return }

        let currentIdExists: Bool = {
            guard let id = currentVisibleSceneId else { return false }
            return currentReelItems.contains(where: { $0.id == id })
        }()

        if !currentIdExists || currentPrefix != expectedPrefix {
            // If the restore target is already loaded in the current page, use it.
            // Otherwise show first item immediately — snapToPendingRestoreIfLoaded
            // will scroll later when the target arrives via pagination.
            if let target = pendingRestoreId,
               currentReelItems.contains(where: { $0.id == target }) {
                currentVisibleSceneId = target
                pendingRestoreId = nil
                playTrigger += 1
                return
            }
            // Only fall back to session-RAM savedPosition if NO pending restore
            // target exists. Otherwise a stale session-save (e.g. from browsing
            // a performer's clips) could accidentally match an item in the new
            // page 1 and clear pendingRestoreId — breaking paged restore.
            if pendingRestoreId == nil,
               let saved = savedPosition(for: reelsMode),
               currentReelItems.contains(where: { $0.id == saved }) {
                currentVisibleSceneId = saved
                playTrigger += 1
                return
            }

            var newId: String?
            switch reelsMode {
            case .scenes:
                if let firstId = viewModel.scenes.first?.id { newId = "scene-\(firstId)" }
            case .markers:
                if let firstId = viewModel.sceneMarkers.first?.id { newId = "marker-\(firstId)" }
            case .clips:
                if let firstId = viewModel.clips.first?.id { newId = "clip-\(firstId)" }
            case .previews:
                if let firstId = viewModel.previews.first?.id { newId = "preview-\(firstId)" }
            }
            if let id = newId {
                // Show first item while paging walks toward pendingRestoreId in
                // the background. Don't clear pendingRestoreId here — the snap
                // will fire once the target is loaded.
                currentVisibleSceneId = id
                playTrigger += 1
            }
        }
    }



    private func handleRatingChange(item: ReelItemData, newRating: Int?) {
        // Preview items live in viewModel.previews, not viewModel.scenes
        if case .preview(let scene) = item {
            let sceneId = scene.id
            let originalRating = viewModel.previews.first(where: { $0.id == sceneId })?.rating100
            if let index = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                viewModel.previews[index] = viewModel.previews[index].withRating(newRating)
            }
            viewModel.updateSceneRating(sceneId: sceneId, rating100: newRating) { success in
                if !success {
                    DispatchQueue.main.async {
                        if let revertIndex = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.previews[revertIndex] = viewModel.previews[revertIndex].withRating(originalRating)
                        }
                        ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
            return
        }

        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }

        if let sceneId = targetSceneId {
            let originalSceneRating = viewModel.scenes.first(where: { $0.id == sceneId })?.rating100
            let originalMarkerRatings: [(id: String, rating: Int?)] = viewModel.sceneMarkers.compactMap { marker in
                guard marker.scene?.id == sceneId else { return nil }
                return (marker.id, marker.scene?.rating100)
            }

            if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)
            }
            for marker in viewModel.sceneMarkers where marker.scene?.id == sceneId {
                if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == marker.id }),
                   let markerScene = viewModel.sceneMarkers[idx].scene {
                    viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx].withScene(markerScene.withRating(newRating))
                }
            }

            viewModel.updateSceneRating(sceneId: sceneId, rating100: newRating) { success in
                if !success {
                    DispatchQueue.main.async {
                        if let revertIndex = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.scenes[revertIndex] = viewModel.scenes[revertIndex].withRating(originalSceneRating)
                        }
                        for entry in originalMarkerRatings {
                            if let revertIndex = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                               let markerScene = viewModel.sceneMarkers[revertIndex].scene {
                                viewModel.sceneMarkers[revertIndex] = viewModel.sceneMarkers[revertIndex]
                                    .withScene(markerScene.withRating(entry.rating))
                            }
                        }
                        ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        } else if case .clip(let image) = item {
            let imageId = image.id
            let originalRating = viewModel.clips.first(where: { $0.id == imageId })?.rating100
            if let clipIndex = viewModel.clips.firstIndex(where: { $0.id == imageId }) {
                viewModel.clips[clipIndex] = viewModel.clips[clipIndex].withRating(newRating)
            }
            viewModel.updateImageRating(imageId: imageId, rating100: newRating) { success in
                if !success {
                    DispatchQueue.main.async {
                        if let revertIndex = viewModel.clips.firstIndex(where: { $0.id == imageId }) {
                            viewModel.clips[revertIndex] = viewModel.clips[revertIndex].withRating(originalRating)
                        }
                        ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        }
    }

    private func handleOCounterChange(item: ReelItemData, newCount: Int) {
        // Preview items live in viewModel.previews, not viewModel.scenes
        if case .preview(let scene) = item {
            let sceneId = scene.id
            let originalCount = viewModel.previews.first(where: { $0.id == sceneId })?.oCounter ?? 0
            if let index = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                viewModel.previews[index] = viewModel.previews[index].withOCounter(newCount)
            }
            viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                DispatchQueue.main.async {
                    if let count = returnedCount {
                        if let idx = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.previews[idx] = viewModel.previews[idx].withOCounter(count)
                        }
                    } else {
                        if let idx = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.previews[idx] = viewModel.previews[idx].withOCounter(originalCount)
                        }
                        ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
            return
        }

        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }

        if let sceneId = targetSceneId {
            let originalSceneCount = viewModel.scenes.first(where: { $0.id == sceneId })?.oCounter ?? 0
            let originalMarkerCounts: [(id: String, count: Int)] = viewModel.sceneMarkers.compactMap { marker in
                guard marker.scene?.id == sceneId else { return nil }
                return (marker.id, marker.scene?.oCounter ?? 0)
            }

            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                viewModel.scenes[index] = viewModel.scenes[index].withOCounter(newCount)
            }
            for entry in originalMarkerCounts {
                if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                   let markerScene = viewModel.sceneMarkers[idx].scene {
                    viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx].withScene(markerScene.withOCounter(newCount))
                }
            }

            // One mutation for scene + all related markers
            viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                DispatchQueue.main.async {
                    if let count = returnedCount {
                        if let idx = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.scenes[idx] = viewModel.scenes[idx].withOCounter(count)
                        }
                        for entry in originalMarkerCounts {
                            if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                               let markerScene = viewModel.sceneMarkers[idx].scene {
                                viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx]
                                    .withScene(markerScene.withOCounter(count))
                            }
                        }
                    } else {
                        if let idx = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.scenes[idx] = viewModel.scenes[idx].withOCounter(originalSceneCount)
                        }
                        for entry in originalMarkerCounts {
                            if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                               let markerScene = viewModel.sceneMarkers[idx].scene {
                                viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx]
                                    .withScene(markerScene.withOCounter(entry.count))
                            }
                        }
                        ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        } else if case .clip(let image) = item {
            let imageId = image.id
            let originalCount = viewModel.clips.first(where: { $0.id == imageId })?.o_counter ?? 0
            if let index = viewModel.clips.firstIndex(where: { $0.id == imageId }) {
                viewModel.clips[index] = viewModel.clips[index].withOCounter(newCount)
            }
            viewModel.incrementImageOCounter(imageId: imageId) { returnedCount in
                DispatchQueue.main.async {
                    if let count = returnedCount {
                        if let idx = viewModel.clips.firstIndex(where: { $0.id == imageId }) {
                            viewModel.clips[idx] = viewModel.clips[idx].withOCounter(count)
                        }
                    } else {
                        if let revertIndex = viewModel.clips.firstIndex(where: { $0.id == imageId }) {
                            viewModel.clips[revertIndex] = viewModel.clips[revertIndex].withOCounter(originalCount)
                        }
                        ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        }
    }

    private func handlePlayCountChange(item: ReelItemData, newCount: Int) {
        // As requested: bypass view counter for Previews
        if case .preview = item { return }
        
        if case .scene(let scene) = item {
            let sceneId = scene.id
            let originalSceneCount = viewModel.scenes.first(where: { $0.id == sceneId })?.playCount ?? 0
            let originalMarkerCounts: [(id: String, count: Int)] = viewModel.sceneMarkers.compactMap { marker in
                guard marker.scene?.id == sceneId else { return nil }
                return (marker.id, marker.scene?.playCount ?? 0)
            }

            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(newCount)
            }
            for entry in originalMarkerCounts {
                if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                   let markerScene = viewModel.sceneMarkers[idx].scene {
                    viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx].withScene(markerScene.withPlayCount(newCount))
                }
            }

            viewModel.addScenePlay(sceneId: sceneId) { returnedCount in
                DispatchQueue.main.async {
                    if let count = returnedCount {
                        if let idx = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.scenes[idx] = viewModel.scenes[idx].withPlayCount(count)
                        }
                        for entry in originalMarkerCounts {
                            if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                               let markerScene = viewModel.sceneMarkers[idx].scene {
                                viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx]
                                    .withScene(markerScene.withPlayCount(count))
                            }
                        }
                    } else {
                        if let idx = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                            viewModel.scenes[idx] = viewModel.scenes[idx].withPlayCount(originalSceneCount)
                        }
                        for entry in originalMarkerCounts {
                            if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == entry.id }),
                               let markerScene = viewModel.sceneMarkers[idx].scene {
                                viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx]
                                    .withScene(markerScene.withPlayCount(entry.count))
                            }
                        }
                        ToastManager.shared.show("View count update failed", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        } else if case .marker(let marker) = item {
            let markerId = marker.id
            let originalCount = viewModel.sceneMarkers.first(where: { $0.id == markerId })?.playCount ?? 0
            if let index = viewModel.sceneMarkers.firstIndex(where: { $0.id == markerId }) {
                viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withPlayCount(newCount)
            }
            viewModel.addSceneMarkerPlay(markerId: markerId) { returnedCount in
                DispatchQueue.main.async {
                    if let count = returnedCount {
                        if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == markerId }) {
                            viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx].withPlayCount(count)
                        }
                    } else {
                        if let idx = viewModel.sceneMarkers.firstIndex(where: { $0.id == markerId }) {
                            viewModel.sceneMarkers[idx] = viewModel.sceneMarkers[idx].withPlayCount(originalCount)
                        }
                        ToastManager.shared.show("Marker view count update failed", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        }
    }

    private var isListEmpty: Bool {
        switch reelsMode {
        case .scenes: return viewModel.scenes.isEmpty
        case .markers: return viewModel.sceneMarkers.isEmpty
        case .clips: return viewModel.clips.isEmpty
        case .previews: return viewModel.previews.isEmpty
        }
    }

    /// Mode-specific loading — `viewModel.isLoading` is not set by `fetchScenes` and hid the spinner.
    private var isFeedLoading: Bool {
        switch reelsMode {
        case .scenes: return viewModel.isLoadingScenes
        case .markers: return viewModel.isLoadingMarkers
        case .clips: return viewModel.isLoadingClips
        case .previews: return viewModel.isLoadingPreviews || viewModel.isLoading
        }
    }

    /// Lookup without remapping the entire feed list (chrome reads this every body pass).
    private var currentVisibleReelItem: ReelItemData? {
        guard let id = currentVisibleSceneId else { return nil }
        switch reelsMode {
        case .scenes:
            let raw = id.hasPrefix("scene-") ? String(id.dropFirst("scene-".count)) : id
            return viewModel.scenes.first(where: { $0.id == raw }).map { .scene($0) }
        case .markers:
            let raw = id.hasPrefix("marker-") ? String(id.dropFirst("marker-".count)) : id
            return viewModel.sceneMarkers.first(where: { $0.id == raw }).map { .marker($0) }
        case .clips:
            let raw = id.hasPrefix("clip-") ? String(id.dropFirst("clip-".count)) : id
            return viewModel.clips.first(where: { $0.id == raw }).map { .clip($0) }
        case .previews:
            let raw = id.hasPrefix("preview-") ? String(id.dropFirst("preview-".count)) : id
            return viewModel.previews.first(where: { $0.id == raw }).map { .preview($0) }
        }
    }

    /// Kein Server / Verbindungsfehler: untere Capsule- & Scrubber-Leiste ausblenden (wie „offline“).
    private var reelsBottomChromeSuppressed: Bool {
        configManager.activeConfig == nil || (isListEmpty && viewModel.errorMessage != nil)
    }

    /// Voller Rand-zu-Rand-Modus nur für den eigentlichen Reels-Player. Bei leerer Liste + Laden/Fehler
    /// bleibt die System-Safe-Area aktiv, damit zentrierte States (`ConnectionErrorView`, Loading)
    /// mit der oberen `safeAreaInset`-Nav-Leiste fluchten und nicht „nach oben rutschen“.
    private var reelsPremiumContentSafeAreaRegions: SafeAreaRegions {
        let awaitingFeed = isListEmpty && (isFeedLoading || viewModel.errorMessage != nil)
        if awaitingFeed { return [] }
        return .all
    }

    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        premiumContentBase
            .onAppear {
                handleOnAppear()
            }
            .onChange(of: coordinator.selectedTab) { oldTab, newTab in
                if newTab == .reels {
                    // Prefer pending performer/tag navigation over plain resume.
                    if applyPendingReelsNavigationFromCoordinator() {
                        return
                    }
                    if !isInitialized {
                        handleOnAppear()
                    } else {
                        reelsResumePlaybackAfterReturn()
                    }
                } else if oldTab == .reels {
                    reelsStopPlaybackAndAccessories()
                }
            }
            .onChange(of: coordinator.reelsNavigationToken) { _, _ in
                // Ignore token updates while Feeds is not visible — otherwise an
                // off-tab / soon-remounted instance clears `reelsPerformer` too early.
                guard coordinator.selectedTab == .reels else { return }
                applyPendingReelsNavigationFromCoordinator()
            }
            .sceneLiveUpdates(using: viewModel)
            .onChange(of: isMenuOpen) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    // Clear both flags — leaving rating overlay true would re-lock menus.
                    self.isMenuOpen = false
                    self.currentItemShowRatingOverlay = false
                }
            }
            .onDisappear {
                // Tab switches often skip `onDisappear`; still needed for push/pop within Feeds.
                if coordinator.selectedTab == .reels {
                    reelsStopPlaybackAndAccessories()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                handleDefaultFilterChanged(notification)
            }
            .onChange(of: viewModel.savedFilters) { _, newValue in
                handleSavedFiltersChanged(newValue)
                if reelsMode == .clips {
                    reelsSyncClipCatalogPresetPickerSelection()
                }
            }
    }

    @ViewBuilder
    private var reelsSceneStyleFilterSheet: some View {
        SceneLiveFilterSheet(
            serverSceneFilters: reelsSceneStyleSheetServerFilters,
            localPresets: reelsSceneLivePresets,
            selectedPresetId: reelsActiveSceneStyleSheetPresetSelection,
            liveChipRowsVisible: SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(reelsLiveChipTargetFilter),
            sortOption: selectedSortOption,
            onSortChange: { changeReelsSceneSortFromSheet($0) },
            minRating: reelChipBinding(\.minRating),
            organized: reelChipBinding(\.organized),
            interactive: reelChipBinding(\.interactive),
            orientation: reelChipBinding(\.orientation),
            performerCount: reelChipBinding(\.performerCount),
            resolution: reelChipBinding(\.resolution),
            performerFavorite: reelChipBinding(\.performerFavorite),
            oCounterTag: reelChipBinding(\.oCounterTag),
            studioSelectionIds: reelChipBinding(\.studioIds),
            studioPickerOptions: reelsStudioPickerOptions,
            studioPickerLoading: reelsStudioPickerLoading,
            onStudioPickerSectionAppear: { reelsLoadStudioPickerOptions() },
            tagSelectionIds: reelChipBinding(\.tagIds),
            tagPickerOptions: reelsTagPickerOptions,
            tagPickerLoading: reelsTagPickerLoading,
            onTagPickerSectionAppear: { reelsLoadTagPickerOptions() },
            groupSelectionIds: reelChipBinding(\.groupIds),
            groupPickerOptions: reelsGroupPickerOptions,
            groupPickerLoading: reelsGroupPickerLoading,
            onGroupPickerSectionAppear: { reelsLoadGroupPickerOptions() },
            onApply: { reelsApplySceneLiveFromSheet() },
            onReset: {
                reelsSetActiveSheetPresetSelection("")
                reelsClearActiveLiveChipsOnly()
                switch reelsMode {
                case .scenes:
                    applySettings(sortBy: selectedSortOption, sceneFilter: nil, performer: selectedPerformer, tags: selectedTags, clearSceneFilter: true, sceneLiveRefresh: true)
                case .markers:
                    applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: nil, performer: selectedPerformer, tags: selectedTags, clearMarkerFilter: true, sceneLiveRefresh: true)
                case .previews:
                    applySettings(previewSortBy: selectedSortOption, previewFilter: nil, performer: selectedPerformer, tags: selectedTags, clearPreviewFilter: true, sceneLiveRefresh: true)
                default:
                    break
                }
            },
            onRequestSave: { reelsSaveSceneLivePresetOverwrite() },
            onRequestSaveAs: {
                reelsScenePresetNameInput = ""
                showReelsSceneSaveAsAlert = true
            },
            onRequestRename: {
                let sel = reelsActiveSheetPresetIdForRead
                if let sid = SceneLivePresetTag.parseServerId(sel),
                   let n = viewModel.savedFilters[sid]?.name {
                    reelsScenePresetNameInput = n
                } else if let ls = SceneLivePresetTag.parseLocalUUIDString(sel),
                          let uuid = UUID(uuidString: ls),
                          let p = reelsSceneLivePresets.first(where: { $0.id == uuid }) {
                    reelsScenePresetNameInput = p.name
                }
                showReelsSceneRenameAlert = true
            },
            onRequestDelete: { showReelsSceneDeleteAlert = true },
            showsFeedsPlaybackSettings: true,
            showsSortControls: reelsMode != .markers,
            useMarkerSort: reelsMode == .markers,
            markerSortOption: $selectedMarkerSortOption,
            onMarkerSortChange: { changeReelsMarkerSortFromSheet($0) }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            reelsSceneFilterSheetHydrating = true
            SceneLivePresetTag.migrateLegacySelection(&reelsSceneLiveSheetPresetSelection)
            SceneLivePresetTag.migrateLegacySelection(&reelsMarkerLiveSheetPresetSelection)
            SceneLivePresetTag.migrateLegacySelection(&reelsPreviewLiveSheetPresetSelection)
            reelsRefreshSceneLivePresets()
            reelsSyncFilterSheetPresetRow()
            viewModel.fetchSavedFilters { _ in
                reelsSyncFilterSheetPresetRow()
            }
            Task { @MainActor in
                reelsSceneFilterSheetHydrating = false
            }
        }
        .onChange(of: reelsSceneLiveSheetPresetSelection) { _, newId in
            guard showReelsSceneFilterSheet, !reelsSceneFilterSheetHydrating, reelsMode == .scenes else { return }
            reelsHandleScenePresetSelectionChange(newId)
        }
        .onChange(of: reelsMarkerLiveSheetPresetSelection) { _, newId in
            guard showReelsSceneFilterSheet, !reelsSceneFilterSheetHydrating, reelsMode == .markers else { return }
            reelsHandleScenePresetSelectionChange(newId)
        }
        .onChange(of: reelsPreviewLiveSheetPresetSelection) { _, newId in
            guard showReelsSceneFilterSheet, !reelsSceneFilterSheetHydrating, reelsMode == .previews else { return }
            reelsHandleScenePresetSelectionChange(newId)
        }
    }

    private var premiumContentBase: some View {
        let withClipAlerts = applyPremiumClipAlerts(premiumContentWithSheets)
        let withSceneAlerts = applyPremiumSceneAlerts(withClipAlerts)
        let withModeLifecycle = applyPremiumModeLifecycle(withSceneAlerts)
        return applyPremiumListLifecycle(withModeLifecycle)
    }

    private func applyPremiumClipAlerts<V: View>(_ content: V) -> some View {
        content
            .alert("Speichern unter", isPresented: $reelsClipImageFilters.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $reelsClipImageFilters.catalogPresetNameInput)
                Button("Speichern") {
                    reelsClipImageFilters.savePresetAs(name: reelsClipImageFilters.catalogPresetNameInput, viewModel: viewModel)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Sortierung, Filter und Live-Kriterien als neuen Stash-Bildfilter speichern.")
            }
            .alert("Umbenennen", isPresented: $reelsClipImageFilters.showRenameCatalogPresetAlert) {
                TextField("Name", text: $reelsClipImageFilters.renameCatalogPresetInput)
                Button("Speichern") {
                    reelsClipImageFilters.renamePreset(to: reelsClipImageFilters.renameCatalogPresetInput, viewModel: viewModel)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Preset oder gespeicherten Filter umbenennen.")
            }
            .alert("Filter löschen?", isPresented: $reelsClipImageFilters.showDeleteCatalogPresetAlert) {
                Button("Löschen", role: .destructive) {
                    reelsClipImageFilters.deletePreset(viewModel: viewModel)
                    refetchReelsClipsFromModel(viewModel)
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(reelsClipImageFilters.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private func applyPremiumSceneAlerts<V: View>(_ content: V) -> some View {
        content
            .alert("Speichern unter", isPresented: $showReelsSceneSaveAsAlert) {
                TextField("Name", text: $reelsScenePresetNameInput)
                Button("Speichern") { reelsSaveSceneLivePresetAs(name: reelsScenePresetNameInput) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Neuen Szenen-Filter auf dem Stash-Server anlegen.")
            }
            .alert("Umbenennen", isPresented: $showReelsSceneRenameAlert) {
                TextField("Name", text: $reelsScenePresetNameInput)
                Button("Speichern") { reelsRenameSceneLivePreset(to: reelsScenePresetNameInput) }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Preset oder gespeicherten Filter umbenennen.")
            }
            .alert("Filter löschen?", isPresented: $showReelsSceneDeleteAlert) {
                Button("Löschen", role: .destructive) { reelsDeleteSceneLivePreset() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(reelsSceneDeletePresetConfirmationText)
            }
    }

    private func applyPremiumModeLifecycle<V: View>(_ content: V) -> some View {
        content
            .onChange(of: reelsClipImageFilters.catalogPresetRowSelection) { _, newId in
                guard reelsClipImageFilters.showFilterSortSheet, !reelsClipFilterSheetHydrating else { return }
                reelsClipImageFilters.handlePresetSelection(newId, viewModel: viewModel)
            }
            .onChange(of: reelsMode) { oldValue, newValue in
                handleModeChange(from: oldValue, to: newValue)
            }
            .onChange(of: currentVisibleSceneId) { _, _ in
                handleCurrentVisibleSceneIdChanged()
            }
    }

    private func applyPremiumListLifecycle<V: View>(_ content: V) -> some View {
        let firstSceneId = viewModel.scenes.first?.id
        let firstMarkerId = viewModel.sceneMarkers.first?.id
        let firstClipId = viewModel.clips.first?.id
        let firstPreviewId = viewModel.previews.first?.id
        let sceneCount = viewModel.scenes.count
        let markerCount = viewModel.sceneMarkers.count
        let clipCount = viewModel.clips.count
        let previewCount = viewModel.previews.count
        return content
            .onChange(of: firstSceneId) { _, _ in autoSelectFirstItem(); continuePagedRestoreIfNeeded() }
            .onChange(of: firstMarkerId) { _, _ in autoSelectFirstItem(); continuePagedRestoreIfNeeded() }
            .onChange(of: firstClipId) { _, _ in autoSelectFirstItem(); continuePagedRestoreIfNeeded() }
            .onChange(of: firstPreviewId) { _, _ in autoSelectFirstItem(); continuePagedRestoreIfNeeded() }
            .onChange(of: sceneCount) { _, _ in continuePagedRestoreIfNeeded() }
            .onChange(of: markerCount) { _, _ in continuePagedRestoreIfNeeded() }
            .onChange(of: clipCount) { _, _ in continuePagedRestoreIfNeeded() }
            .onChange(of: previewCount) { _, _ in continuePagedRestoreIfNeeded() }
    }

    private func handleCurrentVisibleSceneIdChanged() {
        isMenuOpen = false
        // New page: drop zoom lock so Feeds paging is not stuck disabled.
        isMediaZoomed = false
        if reelsMode == .clips {
            reelsSyncClipCatalogPresetPickerSelection()
        }
        // Avoid turning playback on mid-gesture: `scrollPosition` can update before paging settles,
        // which would briefly attach/play the next row's player (flash). Resume is handled in `onScrollPhaseChange(.idle)`.
        if !isUserScrollingReels {
            currentItemIsPlaying = true
        }
        currentItemShowRatingOverlay = false
        scrubberState.time = 0.0
        scrubberState.duration = 1.0
        scrubberState.seeking = false
        scrubberState.seekTarget = nil
        // Don't overwrite the saved session position while we are still paging
        // towards a restore target (page 2+). Otherwise we would persist item 1.
        if pendingRestoreId == nil {
            saveCurrentPositionIfPossible(for: reelsMode)
        }
    }

    private var premiumContentWithSheets: some View {
        premiumContentLayout
            // `.automatic` (statt `.visible`), damit gepushte Children ihre eigene
            // Tab-Bar-Sichtbarkeit (z. B. `FullScreenImageView`) durchsetzen können.
            .toolbar(isUIVisible ? .automatic : .hidden, for: .tabBar)
            .sheet(isPresented: $showStashSyncSheet) {
                #if !os(tvOS)
                StashSyncSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showReelsSceneFilterSheet) {
                reelsSceneStyleFilterSheet
            }
            .sheet(isPresented: $reelsClipImageFilters.showFilterSortSheet) {
                reelsClipFilterSortSheet
            }
    }

    private var reelsClipFilterSortSheet: some View {
        ImagesCatalogFilterSortSheet(
            serverFilters: reelsClipImageFilters.sortedServerImageFilters(viewModel: viewModel),
            localPresets: reelsClipImageFilters.localCatalogPresets,
            selectedPresetRowId: $reelsClipImageFilters.catalogPresetRowSelection,
            filterMenuTitleFallback: reelsClipImageFilters.selectedFilter?.name,
            liveChipRowsVisible: reelsClipImageFilters.imageLiveChipRowsVisible,
            showMediaTypeFilter: reelsClipImageFilters.showImageMediaTypeFilter,
            sortOption: reelsClipImageFilters.selectedSortOption,
            onSortChange: { new in
                reelsClipImageFilters.changeSortOption(to: new, viewModel: viewModel)
                refetchReelsClipsFromModel(viewModel)
            },
            liveMinRating: $reelsClipImageFilters.liveFilterMinRating,
            livePerformerFavorite: $reelsClipImageFilters.liveFilterPerformerFavorite,
            liveOrganized: $reelsClipImageFilters.liveFilterOrganized,
            liveOCounterTag: $reelsClipImageFilters.liveFilterOCounterTag,
            liveStudioIds: $reelsClipImageFilters.liveFilterStudioIds,
            liveTagIds: $reelsClipImageFilters.liveFilterTagIds,
            liveMediaKind: $reelsClipImageFilters.liveFilterMediaKind,
            studioPickerOptions: reelsClipImageFilters.studioPickerOptions,
            studioPickerLoading: reelsClipImageFilters.studioPickerLoading,
            onStudioPickerSectionAppear: { reelsClipImageFilters.loadStudioPickerOptions(viewModel: viewModel) },
            tagPickerOptions: reelsClipImageFilters.tagPickerOptions,
            tagPickerLoading: reelsClipImageFilters.tagPickerLoading,
            onTagPickerSectionAppear: { reelsClipImageFilters.loadTagPickerOptions(viewModel: viewModel) },
            onApply: {
                refetchReelsClipsFromModel(viewModel)
            },
            onReset: {
                reelsClipImageFilters.catalogPresetRowSelection = ""
                reelsClipImageFilters.selectedFilter = nil
                reelsClipImageFilters.clearLiveChipsOnly()
                refetchReelsClipsFromModel(viewModel)
            },
            onRequestSave: { reelsClipImageFilters.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                reelsClipImageFilters.catalogPresetNameInput = ""
                reelsClipImageFilters.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(reelsClipImageFilters.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    reelsClipImageFilters.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(reelsClipImageFilters.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = reelsClipImageFilters.localCatalogPresets.first(where: { $0.id == uuid }) {
                    reelsClipImageFilters.renameCatalogPresetInput = p.name
                }
                reelsClipImageFilters.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { reelsClipImageFilters.showDeleteCatalogPresetAlert = true },
            showsFeedsPlaybackSettings: true
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            reelsClipFilterSheetHydrating = true
            var sel = reelsClipImageFilters.catalogPresetRowSelection
            ListLivePresetTag.migrateLegacySelection(&sel)
            reelsClipImageFilters.catalogPresetRowSelection = sel
            reelsClipImageFilters.refreshLocalPresets()
            reelsSyncClipCatalogPresetPickerSelection()
            Task { @MainActor in
                reelsClipFilterSheetHydrating = false
            }
        }
    }

    @ViewBuilder
    private var premiumContentLayout: some View {
        let reelsFeedConnectionError = isListEmpty && viewModel.errorMessage != nil
        ZStack {
            Group {
                if reelsFeedConnectionError {
                    Color.appBackground.ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            let isLoading = isFeedLoading && isListEmpty

            if isLoading {
                loadingStateView
            } else if isListEmpty && viewModel.errorMessage != nil {
                errorStateView
            } else {
                reelsListView()
            }
        }
        .ignoresSafeArea(reelsPremiumContentSafeAreaRegions)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !StashyChromePlacement.prefersBottom {
                reelsNavBar(currentItem: currentVisibleReelItem)
                    .allowsHitTesting(isUIVisible)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let currentItem = currentVisibleReelItem
            VStack(spacing: 0) {
                if StashyChromePlacement.prefersBottom {
                    reelsNavBar(currentItem: currentItem)
                        .allowsHitTesting(isUIVisible)
                }
                if !reelsBottomChromeSuppressed {
                    reelsInfoOverlay(currentItem: currentItem)
                    reelsScrubberBar(currentItem: currentItem)
                }
            }
            // Scrubber / info overlay must stay interactive whenever the chrome is visible.
            .allowsHitTesting(isUIVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            ReelsTabBarLayout.invalidateCache()
        }
    }

    private func handleDefaultFilterChanged(_ notification: Notification) {
        if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.reels.rawValue {
            switch reelsMode {
            case .scenes:
                let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(sortBy: selectedSortOption, sceneFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .markers:
                let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .clips:
                let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                reelsClipImageFilters.selectedFilter = newFilter
                applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .previews:
                let defaultId = TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                selectedPreviewFilter = newFilter
                applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, previewFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            }
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
        }
    }

    private func handleSavedFiltersChanged(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        let isCurrentlyEmpty: Bool = {
            switch reelsMode {
            case .scenes: return viewModel.scenes.isEmpty
            case .markers: return viewModel.sceneMarkers.isEmpty
            case .clips: return viewModel.clips.isEmpty
            case .previews: return viewModel.previews.isEmpty
            }
        }()

        let noSavedSceneStyleFilter: Bool = {
            switch reelsMode {
            case .clips: return reelsClipImageFilters.selectedFilter == nil
            case .scenes: return selectedFilter == nil
            case .markers: return selectedMarkerFilter == nil
            case .previews: return selectedPreviewFilter == nil
            }
        }()
        let noLiveChipCriteria: Bool = {
            switch reelsMode {
            case .clips:
                return !reelsClipImageFilters.catalogFilterSortFABActive
            case .scenes:
                return !reelsSceneLiveChips.isLiveFilterActive
            case .markers:
                return !reelsMarkerLiveChips.isLiveFilterActive
            case .previews:
                return !reelsPreviewLiveChips.isLiveFilterActive
            }
        }()
        let noCriteriaSet = noSavedSceneStyleFilter && noLiveChipCriteria && selectedPerformer == nil && selectedTags.isEmpty

        if noCriteriaSet && !newValue.isEmpty {
            let defaultId: String? = {
                switch reelsMode {
                case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                }
            }()

            // Only kick an automatic fetch when the timeline is still empty (cold start). If the user is
            // already browsing with "no saved filter", a later `fetchSavedFilters` (e.g. opening the sheet)
            // must not inject the default filter and reset the feed.
            if isCurrentlyEmpty {
                if let defId = defaultId, let filter = newValue[defId] {
                    switch reelsMode {
                    case .scenes:
                        applySettings(sortBy: selectedSortOption, sceneFilter: filter, performer: selectedPerformer, tags: selectedTags)
                    case .markers:
                        applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: filter, performer: selectedPerformer, tags: selectedTags)
                    case .clips:
                        reelsClipImageFilters.selectedFilter = filter
                        applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: filter, performer: selectedPerformer, tags: selectedTags)
                    case .previews:
                        selectedPreviewFilter = filter
                        applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, previewFilter: filter, performer: selectedPerformer, tags: selectedTags)
                    }
                } else {
                    let currentModeType = reelsMode.toModeType
                    let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)

                    switch reelsMode {
                    case .scenes:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(sortBy: savedSort, sceneFilter: nil, performer: selectedPerformer, tags: selectedTags, clearSceneFilter: true)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(markerSortBy: savedSort, markerFilter: nil, performer: selectedPerformer, tags: selectedTags, clearMarkerFilter: true)
                    case .clips:
                        let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(clipSortBy: savedSort, clipFilter: nil, performer: selectedPerformer, tags: selectedTags, clearClipFilter: true)
                    case .previews:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(previewSortBy: savedSort, previewFilter: nil, performer: selectedPerformer, tags: selectedTags, clearPreviewFilter: true)
                    }
                }
                reelsSyncFilterSheetPresetAndLiveChips(savedFilters: newValue)
            } else {
                reelsSyncFilterSheetPresetRow()
            }
        }
    }

    /// Pausiert alle registrierten Reels-`AVPlayer`, beendet Zubehör-Sync und gibt die Audio-Session frei.
    /// Wichtig beim **Haupttab-Wechsel weg von Feeds**: SwiftUI-`TabView` ruft hier oft kein `onDisappear` auf.
    private func reelsStopPlaybackAndAccessories() {
        saveCurrentPositionIfPossible(for: reelsMode)
        savePlaybackCheckpoint(for: reelsMode)
        currentItemIsPlaying = false
        ReelsPlayerRegistry.suspendPlayback()
        NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
        UIApplication.shared.isIdleTimerDisabled = false
        HandyManager.shared.stop()
        ButtplugManager.shared.stopAllDevices()
        LoveSpouseManager.shared.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("🎬 Reels: Audio deactivation error: \(error)")
        }
    }

    /// Resume scroll item + mid-clip time and continue autoplay after returning to Feeds.
    private func reelsResumePlaybackAfterReturn() {
        guard coordinator.selectedTab == .reels else { return }

        ReelsPlayerRegistry.resumePlayback()

        // Tab leave mid-gesture / overlays can leave these stuck and block Feeds interaction.
        isUserScrollingReels = false
        isRotating = false
        isMenuOpen = false
        isMediaZoomed = false
        currentItemShowRatingOverlay = false

        UIApplication.shared.isIdleTimerDisabled = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🎬 Reels: Audio resume error: \(error)")
        }

        // Ensure the last visible item is still selected (TabView usually keeps @State).
        if currentVisibleSceneId == nil {
            restorePositionIfAvailable(for: reelsMode, forceIfPrefixMismatch: false)
            beginPagedRestoreIfNeeded()
            autoSelectFirstItem()
        }

        // Play first so the layer can decode a frame; seek follows on the next tick.
        currentItemIsPlaying = true
        playTrigger += 1

        DispatchQueue.main.async {
            guard self.coordinator.selectedTab == .reels else { return }
            self.isUserScrollingReels = false
            self.currentItemIsPlaying = true
            self.applySavedPlaybackCheckpointIfMatching()
            self.playTrigger += 1
        }
    }

    private var firstEnabledReelsMode: ReelsMode {
        ReelsMode(from: tabManager.enabledReelsModes.first ?? .scenes)
    }

    /// Consumes ``NavigationCoordinator`` reels navigation (performer/tag/mode) even when
    /// ``isInitialized`` is already true — e.g. Feeds button from Tag/Performer detail.
    @discardableResult
    private func applyPendingReelsNavigationFromCoordinator() -> Bool {
        let initialPerformer = coordinator.reelsPerformer
        let initialTags = coordinator.reelsTags
        let targetModeStr = coordinator.reelsTargetMode

        guard targetModeStr != nil
            || initialPerformer != nil
            || !initialTags.isEmpty else {
            return false
        }

        if let modeStr = targetModeStr {
            coordinator.reelsTargetMode = nil
            if modeStr == "Pics" {
                reelsMode = firstEnabledReelsMode
            } else if let mode = ReelsMode(rawValue: modeStr) {
                reelsMode = mode
            }
        }

        if initialPerformer != nil || !initialTags.isEmpty {
            coordinator.reelsPerformer = nil
            coordinator.reelsTags = []

            let targetMode = firstEnabledReelsMode
            reelsMode = targetMode

            switch targetMode {
            case .scenes:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .scenes)
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                var baseFilter = selectedFilter
                if baseFilter == nil, let defId = TabManager.shared.getDefaultFilterId(for: .reels) {
                    baseFilter = viewModel.savedFilters[defId]
                }
                applySettings(sortBy: savedSort, sceneFilter: baseFilter, performer: initialPerformer, tags: initialTags, mode: .scenes)
            case .markers:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .markers)
                let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                var baseFilter = selectedMarkerFilter
                if baseFilter == nil, let defId = TabManager.shared.getDefaultMarkerFilterId(for: .reels) {
                    baseFilter = viewModel.savedFilters[defId]
                }
                applySettings(markerSortBy: savedSort, markerFilter: baseFilter, performer: initialPerformer, tags: initialTags, mode: .markers)
            case .previews:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .previews)
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                var baseFilter = selectedPreviewFilter
                if baseFilter == nil, let defId = TabManager.shared.getDefaultPreviewFilterId(for: .reels) {
                    baseFilter = viewModel.savedFilters[defId]
                }
                applySettings(previewSortBy: savedSort, previewFilter: baseFilter, performer: initialPerformer, tags: initialTags, mode: .previews)
            case .clips:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .clips)
                let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                var clipF = reelsClipImageFilters.selectedFilter
                if clipF == nil, let defId = TabManager.shared.getDefaultClipFilterId(for: .reels) {
                    clipF = viewModel.savedFilters[defId]
                }
                reelsClipImageFilters.selectedFilter = clipF
                applySettings(clipSortBy: savedSort, clipFilter: clipF, performer: initialPerformer, tags: initialTags, mode: .clips)
            }
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
            isInitialized = true
            return true
        }

        return false
    }

    private func handleOnAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
        ReelsPlayerRegistry.resumePlayback()
        reelsClipImageFilters.externalRefetchClips = { vm in
            refetchReelsClipsFromModel(vm)
        }

        ReelsSessionRAM.clearLegacyUserDefaultsIfNeeded()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🎬 Reels: Audio setup error: \(error)")
        }

        // 0. Guard against rotation-triggered onAppear
        if isRotating {
            isRotating = false
            return
        }

        if viewModel.savedFilters.isEmpty {
            viewModel.fetchSavedFilters()
        }

        if applyPendingReelsNavigationFromCoordinator() {
            return
        }

        // After the first full setup, re-onAppear must NOT re-run session restore /
        // autoSelectFirstItem (that reset scroll). Just resume autoplay + seek.
        if isInitialized {
            reelsResumePlaybackAfterReturn()
            return
        }

        restoreSessionRandomSeedIfAvailable()

        // Restore session sort/filter for the current mode (prevents resetting to defaults on tab return)
        switch reelsMode {
        case .scenes:
            if let raw = sessionSortRaw(for: .scenes), let opt = StashDBViewModel.SceneSortOption(rawValue: raw) {
                selectedSortOption = opt
            }
            if let fid = sessionFilterId(for: .scenes) {
                selectedFilter = viewModel.savedFilters[fid]
            }
        case .markers:
            if let raw = sessionSortRaw(for: .markers), let opt = StashDBViewModel.SceneMarkerSortOption(rawValue: raw) {
                selectedMarkerSortOption = opt
            }
            if let fid = sessionFilterId(for: .markers) {
                selectedMarkerFilter = viewModel.savedFilters[fid]
            }
        case .clips:
            if let raw = sessionSortRaw(for: .clips), let opt = StashDBViewModel.ImageSortOption(rawValue: raw) {
                reelsClipImageFilters.selectedSortOption = opt
            }
            if let fid = sessionFilterId(for: .clips) {
                reelsClipImageFilters.selectedFilter = viewModel.savedFilters[fid]
            }
        case .previews:
            if let raw = sessionSortRaw(for: .previews), let opt = StashDBViewModel.SceneSortOption(rawValue: raw) {
                selectedSortOption = opt
            }
            if let fid = sessionFilterId(for: .previews) {
                selectedPreviewFilter = viewModel.savedFilters[fid]
            }
        }

        // IMPORTANT: Restore the session sort/filter BEFORE restoring scroll position.
        // Otherwise we may auto-select (and persist) the first item from the wrong sort,
        // which breaks position restore (notably for Clips when using Created sorting).
        restorePositionIfAvailable(for: reelsMode, forceIfPrefixMismatch: false)
        beginPagedRestoreIfNeeded()
        autoSelectFirstItem()
        
        // 1. Initialize reelsMode ONLY if current mode is disabled in settings
        let enabledTypes = tabManager.enabledReelsModes
        var currentEffectiveMode = reelsMode
        if !enabledTypes.contains(reelsMode.toModeType) {
            if let first = enabledTypes.first {
                currentEffectiveMode = ReelsMode(from: first)
                reelsMode = currentEffectiveMode
            }
        }

        let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                case .previews: return viewModel.previews.isEmpty
                }
            }()

            if isCurrentlyEmpty {
                // Priority 2: Try to apply default filter
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                    }
                }()
                    
                let hasFiltersArrived = !viewModel.savedFilters.isEmpty
                
                if defaultId != nil, !hasFiltersArrived {
                    // Wait for onChange(of: viewModel.savedFilters) to trigger applySettings.
                } else {
                    // Filters are ready OR no default filter is configured
                    var initialSceneFilter = selectedFilter
                    var initialMarkerFilter = selectedMarkerFilter
                    switch reelsMode {
                    case .scenes:
                        if initialSceneFilter == nil, let defId = defaultId {
                            initialSceneFilter = viewModel.savedFilters[defId]
                        }
                    case .markers:
                        if initialMarkerFilter == nil, let defId = defaultId {
                            initialMarkerFilter = viewModel.savedFilters[defId]
                        }
                    default:
                        if initialSceneFilter == nil, let defId = defaultId {
                            initialSceneFilter = viewModel.savedFilters[defId]
                        }
                    }
                    
                    // Load saved sort for current mode
                    let currentModeType = reelsMode.toModeType
                    let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)
                    
                    // Apply based on mode
                    switch reelsMode {
                    case .scenes:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedSortOption = savedSort
                        applySettings(sortBy: savedSort, sceneFilter: initialSceneFilter, performer: selectedPerformer, tags: selectedTags)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedMarkerSortOption = savedSort
                        applySettings(markerSortBy: savedSort, markerFilter: initialMarkerFilter, performer: selectedPerformer, tags: selectedTags)
                    case .clips:
                        let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                        reelsClipImageFilters.selectedSortOption = savedSort
                        var clipFilter = reelsClipImageFilters.selectedFilter
                        if clipFilter == nil, let defId = defaultId {
                            clipFilter = viewModel.savedFilters[defId]
                        }
                        reelsClipImageFilters.selectedFilter = clipFilter
                        applySettings(clipSortBy: savedSort, clipFilter: clipFilter)
                    case .previews:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedSortOption = savedSort
                        var prevFilter = selectedPreviewFilter
                        if prevFilter == nil, let defId = defaultId {
                            prevFilter = viewModel.savedFilters[defId]
                        }
                        selectedPreviewFilter = prevFilter
                        applySettings(previewSortBy: savedSort, previewFilter: prevFilter)
                    }
                    reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
                }
            }
        isInitialized = true
    }

    private func handleModeChange(from oldValue: ReelsMode, to newValue: ReelsMode) {
        // When switching sub-tabs (Scenes/Markers/Clips/Previews) always pause the
        // currently playing item immediately. Autoplay for the new mode is handled by
        // autoSelectFirstItem -> currentVisibleSceneId change (which resets isPlaying).
        currentItemIsPlaying = false
        // Zoom locks outer paging via `.scrollDisabled(isMediaZoomed)` — clear on mode switch
        // so Clips/etc. are swipeable again after a pinch on Scenes.
        isMediaZoomed = false
        isUserScrollingReels = false
        // Some mode switches may not trigger a scrollPosition/currentVisibleSceneId change
        // (e.g. when the list is already populated). Ensure we resume playback intent
        // shortly after the mode switch so the active item can start playing again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.currentItemIsPlaying = true
        }

        // Persist old mode position, then restore the last known position for the new mode.
        saveCurrentPositionIfPossible(for: oldValue)
        restorePositionIfAvailable(for: newValue, forceIfPrefixMismatch: true)
        beginPagedRestoreIfNeeded()

        // Restore session sort/filter (prefer session over defaults)
        switch newValue {
        case .scenes:
            let sortRaw = sessionSortRaw(for: .scenes) ?? TabManager.shared.getReelsDefaultSort(for: .scenes) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let fid = sessionFilterId(for: .scenes) ?? TabManager.shared.getDefaultFilterId(for: .reels)
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedFilter = f
        case .markers:
            let sortRaw = sessionSortRaw(for: .markers) ?? TabManager.shared.getReelsDefaultSort(for: .markers) ?? ""
            selectedMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: sortRaw) ?? selectedMarkerSortOption
            let fid = sessionFilterId(for: .markers) ?? TabManager.shared.getDefaultMarkerFilterId(for: .reels)
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedMarkerFilter = f
        case .clips:
            let sortRaw = sessionSortRaw(for: .clips) ?? TabManager.shared.getReelsDefaultSort(for: .clips) ?? ""
            reelsClipImageFilters.selectedSortOption = StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? reelsClipImageFilters.selectedSortOption
            let fid = sessionFilterId(for: .clips) ?? TabManager.shared.getDefaultClipFilterId(for: .reels)
            reelsClipImageFilters.selectedFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        case .previews:
            let sortRaw = sessionSortRaw(for: .previews) ?? TabManager.shared.getReelsDefaultSort(for: .previews) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let fid = sessionFilterId(for: .previews) ?? TabManager.shared.getDefaultPreviewFilterId(for: .reels)
            selectedPreviewFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        }

        reelsSyncFilterSheetPresetAndLiveChips(for: newValue, savedFilters: viewModel.savedFilters)

        switch newValue {
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        }
    }

    @ViewBuilder
    private var loadingStateView: some View {
        StandardLoadingView(message: "Loading feeds...")
    }

    @ViewBuilder
    private var errorStateView: some View {
        ConnectionErrorView(onRetry: {
            switch reelsMode {
            case .scenes:
                applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags)
            case .markers:
                applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags)
            case .clips:
                applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: selectedTags)
            case .previews:
                applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags)
            }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func advanceToNextItem(from item: ReelItemData) {
        let items = currentReelItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < items.count else { return }
        currentVisibleSceneId = items[nextIndex].id
    }

    @ViewBuilder
    private func reelItemRow(index: Int, item: ReelItemData, itemCount: Int) -> some View {
        ReelItemView(
            item: item,
            currentVisibleSceneId: $currentVisibleSceneId,
            isMuted: $isMuted,
            isUIVisible: $isUIVisible,
            isPlaying: $currentItemIsPlaying,
            isUserScrolling: $isUserScrollingReels,
            showRatingOverlay: $currentItemShowRatingOverlay,
            scrubberState: scrubberState,
            onPerformerTap: { performer in
                applyPerformerFilter(performer)
            },
            onTagTap: { tag in
                // Add tag to existing selection (or toggle off if already selected)
                var newTags = selectedTags
                if newTags.contains(where: { $0.id == tag.id }) {
                    newTags.removeAll { $0.id == tag.id }
                } else {
                    newTags.append(tag)
                }
                applyTagsChange(newTags)
            },
            onRatingChanged: { rating in
                self.handleRatingChange(item: item, newRating: rating)
            },
            onOCounterChanged: { newCount in
                self.handleOCounterChange(item: item, newCount: newCount)
            },
            onPlayCountChanged: { newCount in
                self.handlePlayCountChange(item: item, newCount: newCount)
            },
            onVideoEnded: {
                self.advanceToNextItem(from: item)
            },
            viewModel: viewModel,
            playTrigger: playTrigger,
            isMenuOpen: $isMenuOpen,
            isZoomed: $isMediaZoomed,
            isRotating: $isRotating,
            onInteraction: { }
        )
        .scrollDisabled(isMediaZoomed)
        .containerRelativeFrame([.horizontal, .vertical])
        .background(Color.black)
        .id(item.id)
        .onAppear {
            // Früher nachladen als nur beim vorletzten Eintrag — weniger Warten am Listenende.
            let prefetchDistance = 5
            if itemCount >= prefetchDistance, index >= itemCount - prefetchDistance {
                switch reelsMode {
                case .scenes: viewModel.loadMoreScenes()
                case .markers: viewModel.loadMoreMarkers()
                case .clips: viewModel.loadMoreClips()
                case .previews: viewModel.loadMorePreviews()
                }
            }
        }
    }

    @ViewBuilder
    private func reelsListView() -> some View {
        let items = currentReelItems

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        reelItemRow(index: index, item: item, itemCount: items.count)
                    }
                }
                .scrollTargetLayout()
            }
            .focusable(false)
            .focusEffectDisabled()
            .scrollTargetBehavior(.paging)
            .scrollDisabled(isMenuOpen)
            .scrollPosition(id: scrollPositionBinding)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .onScrollPhaseChange { oldPhase, newPhase in
                let wasDriftSuppressed = reelsScrollDelaysPagingIdentityDrift(oldPhase)
                let driftSuppressed = reelsScrollDelaysPagingIdentityDrift(newPhase)
                if !wasDriftSuppressed && driftSuppressed {
                    reelsWasPlayingBeforeScrollGesture = currentItemIsPlaying
                }
                if driftSuppressed {
                    isUserScrollingReels = true
                    currentItemIsPlaying = false
                    ReelsPlayerRegistry.pauseAll()
                    NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
                } else {
                    // Restore play intent before clearing the scroll flag so `ReelItemView` never sees
                    // `!isUserScrolling && !isPlaying` for a frame (play button / thumbnail flash).
                    if reelsWasPlayingBeforeScrollGesture {
                        currentItemIsPlaying = true
                    }
                    isUserScrollingReels = false
                }
            }
            .onChange(of: items.count) { _, _ in
                continuePagedRestoreIfNeeded()
                snapToPendingRestoreIfLoaded(using: proxy)

                if shouldScrollToTopAfterCriterionChange, let first = items.first?.id {
                    shouldScrollToTopAfterCriterionChange = false
                    pendingRestoreId = nil
                    currentVisibleSceneId = first
                    DispatchQueue.main.async {
                        withAnimation(nil) {
                            proxy.scrollTo(first, anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                // When returning from the loading overlay, items.count may already
                // be at N (first page) but no onChange fires. Ensure paged restore
                // resumes and attempt a snap if the target is already loaded.
                continuePagedRestoreIfNeeded()
                snapToPendingRestoreIfLoaded(using: proxy)

                if shouldScrollToTopAfterCriterionChange, let first = items.first?.id {
                    shouldScrollToTopAfterCriterionChange = false
                    pendingRestoreId = nil
                    currentVisibleSceneId = first
                    DispatchQueue.main.async {
                        withAnimation(nil) {
                            proxy.scrollTo(first, anchor: .top)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) { isRotating = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation { isRotating = false }
                }
            }
        }
    }

    /// Scrolls to pending restore target once it's present in the list. No overlay,
    /// no blocking — UI already shows first item. Just a single scroll-snap.
    private func snapToPendingRestoreIfLoaded(using proxy: ScrollViewProxy) {
        guard let target = pendingRestoreId else { return }
        guard currentReelItems.contains(where: { $0.id == target }) else { return }

        pendingRestoreId = nil
        ReelsPlayerRegistry.pauseAll()
        currentVisibleSceneId = target

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(nil) {
                proxy.scrollTo(target, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.currentItemIsPlaying = true
            }
        }
    }


    /// Match expanding-dock menu chrome.
    private var reelsTopChromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    /// Top chrome: filter + mode · active filters/hashtags · O + rating
    @ViewBuilder
    private func reelsNavBar(currentItem: ReelItemData?) -> some View {
        let oCounter = currentItem?.oCounter ?? 0
        let rating100 = currentItem?.rating100 ?? 0
        let stars = max(0, min(5, Int(round(Double(rating100) / 20.0))))

        HStack(spacing: 8) {
            HStack(spacing: 6) {
                reelsModePill
                reelsFilterSortPill
            }
            .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let performer = selectedPerformer {
                        Button(action: { applyClearPerformerOnly() }) {
                            HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text(performer.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(selectedTags) { tag in
                        Button(action: {
                            var newTags = selectedTags
                            newTags.removeAll { $0.id == tag.id }
                            applyTagsChange(newTags)
                        }) {
                            HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("#\(tag.name)")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: reelsTopChromePillHeight)

            HStack(spacing: 6) {
                Button {
                    if let item = currentItem {
                        handleOCounterChange(item: item, newCount: oCounter + 1)
                    }
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: oCounter > 0 ? AppearanceManager.shared.oCounterIconFilled : AppearanceManager.shared.oCounterIcon)
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(oCounter > 0 ? appearanceManager.tintColor : .white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        Text("\(oCounter)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    }
                    .opacity(currentItem == nil ? 0.35 : 1.0)
                    .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
                }
                .buttonStyle(.plain)
                .disabled(currentItem == nil)
                .accessibilityLabel("O-Counter")

                Group {
                    if let item = currentItem {
                        Menu {
                            Button(action: { handleRatingChange(item: item, newRating: 0) }) {
                                HStack {
                                    Text("Clear Rating")
                                    if stars == 0 { Image(systemName: "checkmark") }
                                }
                            }
                            Divider()
                            ForEach(1...5, id: \.self) { s in
                                Button(action: { handleRatingChange(item: item, newRating: s * 20) }) {
                                    HStack {
                                        Text(String(repeating: "★", count: s))
                                        if stars == s { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                    .foregroundColor(.white.opacity(stars > 0 ? 1.0 : StashyExpandingDock.inactiveIconOpacity))
                                Text("\(stars)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            }
                            .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                            Image(systemName: "star.fill")
                                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            Text("0")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white.opacity(0.35))
                        .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
                    }
                }
                .accessibilityLabel("Rating")
            }
            .fixedSize()
        }
        .frame(height: reelsTopChromePillHeight)
        .padding(.horizontal, StashyExpandingDock.edgePadding)
        .padding(.vertical, 6)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }

    // MARK: - Scrubber bar
    @ViewBuilder
    private func reelsScrubberBar(currentItem: ReelItemData?) -> some View {
        if let item = currentItem {
            if item.isAnimated {
                // GIFs don't have a scrubber; don't reserve scrubber space (it pushed the overlay too high).
                EmptyView()
            } else {
                IsolatedScrubberBar(state: scrubberState, isUIVisible: isUIVisible)
            }
        }
    }

    /// Info overlay above the scrubber (performer/title + item hashtags + mute/play circles).
    @ViewBuilder
    private func reelsInfoOverlay(currentItem: ReelItemData?) -> some View {
        let isVideo = currentItem.map { $0.videoURL != nil && !$0.isAnimated } ?? false
        VStack(alignment: .leading, spacing: 0) {
            if let item = currentItem {
                HStack(alignment: .center, spacing: 10) {
                    if let performer = item.performers.first {
                        NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
                            performerThumbnail(performer)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let performer = item.performers.first {
                                Button(action: { applyPerformerFilter(performer) }) {
                                    Text(performer.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .layoutPriority(1)
                                Text("-")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            if let title = item.title, !title.isEmpty {
                                if let scene = item.underlyingScene {
                                    NavigationLink(destination: SceneDetailView(scene: scene)) {
                                        Text(title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        let tags = item.tags
                        Group {
                            if !tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tags) { tag in
                                            Button(action: {
                                                var newTags = selectedTags
                                                if newTags.contains(where: { $0.id == tag.id }) {
                                                    newTags.removeAll { $0.id == tag.id }
                                                } else {
                                                    newTags.append(tag)
                                                }
                                                applyTagsChange(newTags)
                                            }) {
                                                Text("#\(tag.name)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.8))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(Color.black.opacity(0.3))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            } else {
                                Color.clear.opacity(0)
                            }
                        }
                        .frame(height: 20)
                    }

                    // Circular mute / play spanning title + hashtag rows
                    HStack(spacing: 8) {
                        ChromeCircleButton(
                            systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            enabled: isVideo,
                            accessibilityLabel: isMuted ? "Ton an" : "Stumm"
                        ) {
                            if isVideo { isMuted.toggle() }
                        }

                        ChromeCircleButton(
                            systemImage: currentItemIsPlaying ? "pause.fill" : "play.fill",
                            enabled: isVideo,
                            accessibilityLabel: currentItemIsPlaying ? "Pause" : "Play"
                        ) {
                            if isVideo { currentItemIsPlaying.toggle() }
                        }
                    }
                    .fixedSize()
                }
                .padding(.horizontal, StashyExpandingDock.edgePadding)
            }
        }
        .padding(.bottom, 2)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
        .allowsHitTesting(!isMenuOpen)
    }

    @ViewBuilder
    private func performerThumbnail(_ performer: ScenePerformer) -> some View {
        let size: CGFloat = StashyExpandingDock.circleSize
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
    }

    @ToolbarContentBuilder
    private var reelsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                if let firstTab = TabManager.shared.visibleTabs.first {
                    coordinator.selectedTab = firstTab
                }
            }) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.01)) // Ensure hit area is detected
                    .contentShape(Rectangle())
            }
        }
            
            if !(isListEmpty && viewModel.errorMessage != nil) {
                ToolbarItem(placement: .principal) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let performer = selectedPerformer {
                                Button(action: {
                                    applyClearPerformerOnly()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(performer.name)
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(Edge.Set.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                            
                            ForEach(selectedTags) { tag in
                                Button(action: {
                                    var newTags = selectedTags
                                    newTags.removeAll { $0.id == tag.id }
                                    applyTagsChange(newTags)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("#\(tag.name)")
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(Edge.Set.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    modeMenu
                    reelsFilterSortFAB
                }
            }
        }

    @ViewBuilder
    private var reelsFilterSortFAB: some View {
        reelsFilterSortPill
    }

    @ViewBuilder
    private var reelsFilterSortPill: some View {
        Button {
            switch reelsMode {
            case .scenes, .markers, .previews:
                reelsRefreshSceneLivePresets()
                SceneLivePresetTag.migrateLegacySelection(&reelsSceneLiveSheetPresetSelection)
                SceneLivePresetTag.migrateLegacySelection(&reelsMarkerLiveSheetPresetSelection)
                SceneLivePresetTag.migrateLegacySelection(&reelsPreviewLiveSheetPresetSelection)
                reelsSyncFilterSheetPresetRow()
                showReelsSceneFilterSheet = true
            case .clips:
                reelsClipImageFilters.refreshLocalPresets()
                reelsSyncClipCatalogPresetPickerSelection()
                reelsClipImageFilters.showFilterSortSheet = true
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(width: StashyExpandingDock.iconSize, height: StashyExpandingDock.iconSize)
                .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight, iconOnly: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter und Sortierung")
    }

    @ViewBuilder
    private var modeMenu: some View {
        reelsModePill
    }

    @ViewBuilder
    private var reelsModePill: some View {
        let enabledModes = tabManager.enabledReelsModes.map { ReelsMode(from: $0) }
        Menu {
            ForEach(enabledModes, id: \.self) { mode in
                Button {
                    guard mode != reelsMode else { return }
                    #if !os(tvOS)
                    HapticManager.selection()
                    #endif
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        reelsMode = mode
                    }
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: reelsMode.icon)
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .frame(width: StashyExpandingDock.iconSize, height: StashyExpandingDock.iconSize)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
            .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed")
        .accessibilityValue(reelsMode.rawValue)
    }

}

// MARK: - Reel thumbnail-first video (hide AV layer until first frame is ready)

/// Steuert die Thumbnail→Video-Überblendung: wird `true`, wenn der `AVPlayerLayer` das **erste Frame**
/// tatsächlich gerendert hat (`isReadyForDisplay`). Vorher: `AVPlayerItem.status == .readyToPlay` —
/// das bedeutet nur „Buffer reicht zum Starten“ und kann zu kurzem Schwarz vor dem ersten Frame führen.
///
/// Failure-Pfad (`item.status == .failed`) bleibt erhalten und blendet den Player wieder aus.
private final class ReelItemVideoSurfaceReadiness: ObservableObject {
    @Published private(set) var showsDecodedVideo: Bool = false
    private var layerReadyObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private weak var boundLayer: AVPlayerLayer?

    /// Auf Player-Wechsel reagieren (Item-Wechsel ⇒ Reset der Anzeige + neue Failure-Beobachtung).
    ///
    /// Wichtig beim Zurückkehren von Navigation (Profil etc.): `onAppear` ruft `observe` erneut auf.
    /// Der Layer ist oft bereits `isReadyForDisplay == true` — KVO feuert dann nicht nochmal.
    /// Früher wurde `showsDecodedVideo` blind auf `false` gesetzt → dauerhaft schwarzes Bild.
    func observe(player: AVPlayer?) {
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        guard let player else {
            showsDecodedVideo = false
            return
        }

        // Nur verstecken, wenn wirklich kein Frame bereitsteht.
        if boundLayer?.isReadyForDisplay != true {
            showsDecodedVideo = false
        }

        // Kein `.initial` — sonst wipen wir beim Re-Observe ein bereits sichtbares Frame weg.
        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.showsDecodedVideo = false
                self?.bindItemFailure(player.currentItem)
            }
        }
        bindItemFailure(player.currentItem)
        resyncFromBoundLayer()
    }

    /// Vom `FullScreenVideoPlayer` per `onLayerReady` aufgerufen — wir hängen uns dauerhaft an
    /// `AVPlayerLayer.isReadyForDisplay`. Sobald `true`, ist das erste Frame sichtbar → Thumbnail ausblenden.
    func bind(layer: AVPlayerLayer) {
        if boundLayer !== layer || layerReadyObservation == nil {
            layerReadyObservation?.invalidate()
            layerReadyObservation = nil
            boundLayer = layer
            layerReadyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] avLayer, _ in
                DispatchQueue.main.async {
                    if avLayer.isReadyForDisplay {
                        self?.showsDecodedVideo = true
                    }
                }
            }
        }
        // Immer aktuellen Stand übernehmen (gleiche Layer-Instanz nach Pop/Update).
        resyncFromBoundLayer()
    }

    /// Nach Pause/Navigation/Seek: sichtbaren Stand vom gebundenen Layer wiederherstellen.
    func resyncFromBoundLayer() {
        if let layer = boundLayer, layer.isReadyForDisplay {
            showsDecodedVideo = true
        }
    }

    /// `opacity: 0` kann verhindern, dass `isReadyForDisplay` wieder `true` wird.
    /// Nach Play kurz nachziehen — besser kurzer Flash als dauerhaft schwarz.
    func notePlaybackStarted() {
        resyncFromBoundLayer()
        guard !showsDecodedVideo else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.resyncFromBoundLayer()
            if !self.showsDecodedVideo, self.boundLayer != nil {
                self.showsDecodedVideo = true
            }
        }
    }

    private func bindItemFailure(_ item: AVPlayerItem?) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        guard let item else { return }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] avItem, _ in
            if avItem.status == .failed {
                DispatchQueue.main.async { self?.showsDecodedVideo = false }
            }
        }
    }

    deinit {
        layerReadyObservation?.invalidate()
        itemStatusObservation?.invalidate()
        currentItemObservation?.invalidate()
    }
}

struct ReelItemView: View {
    let item: ReelsViewBody.ReelItemData
    @Binding var currentVisibleSceneId: String?
    
    var isActive: Bool {
        item.id == currentVisibleSceneId
    }

    /// `scrollPosition` can mark the next row active before paging finishes; defer player work until scrolling settles.
    private var isPlaybackActive: Bool {
        isActive && !isUserScrolling
    }

    @State private var player: AVPlayer?
    @State private var looper: Any?
    @State private var animationAdvanceTimer: Timer?
    @ObservedObject var tabManager = TabManager.shared
    
    // Playback State
    @Binding var isMuted: Bool
    @Binding var isUIVisible: Bool
    @Binding var isPlaying: Bool
    @Binding var isUserScrolling: Bool
    @Binding var showRatingOverlay: Bool
    let scrubberState: ScrubberState
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    var onOCounterChanged: (Int) -> Void
    var onPlayCountChanged: (Int) -> Void
    var onVideoEnded: () -> Void = {}
    @ObservedObject var viewModel: StashDBViewModel
    var playTrigger: Int
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var timeObserver: Any?
    /// Bumped on each `setupPlayer` / `cleanupPlayer` so in-flight `fetchSceneStreams`
    /// completions cannot attach a new `AVPlayerItem` after the user has scrolled away.
    @State private var playerSetupGeneration: Int = 0
    @State private var showTagsOverlay = false
    @Binding var isMenuOpen: Bool
    @Binding var isZoomed: Bool
    @Binding var isRotating: Bool
    @State private var showStashSyncSheet = false
    @State private var isFastForwarding = false
    var onInteraction: () -> Void
    @StateObject private var videoSurfaceReadiness = ReelItemVideoSurfaceReadiness()
    /// Live decoded size (accounts for clip rotation / preferredTransform).
    @State private var playbackPresentationSize: CGSize? = nil
    @State private var playbackActivityTracker = ScenePlaybackActivityTracker()

    /// Scenes + markers contribute watch time to the parent scene; previews/clips do not.
    private var tracksPlaybackActivity: Bool {
        switch item {
        case .scene, .marker: return true
        case .preview, .clip: return false
        }
    }

    private var shouldFill: Bool {
        // Only fill if the setting is enabled
        guard tabManager.reelsFillHeight else { return false }

        let isPortraitDevice = UIScreen.main.bounds.height > UIScreen.main.bounds.width
        if isPortraitDevice {
            return !effectiveContentIsLandscape
        } else {
            return effectiveContentIsLandscape
        }
    }

    /// Immersive fill stops at the scrubber bottom (above capsules + tab bar). When chrome is hidden, full height.
    /// Applied only to the video layer / web image — not to page layout (keeps paging intact).
    private var immersiveBottomInset: CGFloat {
        guard shouldFill, isUIVisible else { return 0 }
        return ReelsImmersiveChromeLayout.videoBottomInset()
    }

    /// True when playing pixels are wider than tall (rotation-aware for clips).
    private var effectiveContentIsLandscape: Bool {
        if let size = playbackPresentationSize, size.width > 1, size.height > 1 {
            return size.width > size.height
        }
        return !item.isPortrait
    }

    var body: some View {
        applyModifiers(mainContent)
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            mediaLayer
            fastForwardOverlay
            playButtonOverlay
            bottomBarOverlay
        }
    }
}

extension ReelItemView {
    func applyModifiers<V: View>(_ content: V) -> some View {
        let v1 = applyBasicModifiers(content)
        let v2 = applyPlaybackLifecycleModifiers(v1)
        let v4 = applyOverlayModifiers(v2)
        return applyStashSyncModifiers(v4)
    }

    @ViewBuilder
    private func applyBasicModifiers<V: View>(_ content: V) -> some View {
        content
            .buttonStyle(.plain)
            .background(Color.black)
            .focusable(false)
            .focusEffectDisabled()
    }

    @ViewBuilder
    private func applyPlaybackLifecycleModifiers<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                // Critical: do **not** call `setupPlayer()` for off-screen rows. During
                // fast scroll every flashed cell would otherwise spawn HLS + a
                // `fetchSceneStreams` round-trip — that saturates Stash/ffmpeg.
                if isActive && !isUserScrolling {
                    setupPlayer()
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                } else {
                    // Deferred autoplay: after a filter change, onAppear can run before
                    // `currentVisibleSceneId` is set. Retry shortly if this row became active.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
                        if isActive && isPlaying && !isRotating && !isUserScrolling {
                            if player == nil { setupPlayer() }
                            ReelsPlayerRegistry.playIfAllowed(player)
                        }
                    }
                }
                videoSurfaceReadiness.observe(player: player)
            }
            .onDisappear {
                // LazyVStack can call `onDisappear` briefly while the row is still the centered reel; tearing down
                // the active `AVPlayer` there causes a second flash when paging settles.
                guard !isActive else { return }
                cleanupPlayer()
                cancelAnimationAdvanceTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reelsPauseAllPlayers)) { _ in
                // Robust pause: when paging/scrolling starts, pause immediately even if
                // `currentVisibleSceneId` (and thus `isActive`) hasn't updated yet.
                player?.pause()
                player?.rate = 0
                syncPlaybackActivityPosition()
                playbackActivityTracker.stop()
            }
            .onChange(of: isMuted) { _, newValue in
                player?.isMuted = newValue
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    guard !isUserScrolling else { return }
                    if player == nil { setupPlayer() } else { refreshTimeObserver() }
                    if isPlaying && !isRotating { ReelsPlayerRegistry.playIfAllowed(player) }
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                    // Deferred play: ensure player starts even if isPlaying binding
                    // hasn't propagated yet (e.g. after filter change resets state).
                    DispatchQueue.main.async {
                        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
                        if self.isActive && self.isPlaying && !self.isRotating && !self.isUserScrolling {
                            ReelsPlayerRegistry.playIfAllowed(self.player)
                        }
                    }
                } else {
                    if isUserScrolling {
                        player?.pause()
                        player?.rate = 0
                        cancelAnimationAdvanceTimer()
                    } else {
                        cleanupPlayer()
                        cancelAnimationAdvanceTimer()
                    }
                }
            }
            .onChange(of: isUserScrolling) { _, scrolling in
                if scrolling {
                    // Pause is handled by `ReelsPauseAllPlayers` from `onScrollPhaseChange`; avoid a second
                    // `pause()` here (can flash the current `AVPlayerLayer` on touch / drag start).
                    if item.isAnimated { cancelAnimationAdvanceTimer() }
                    return
                }
                if !isActive {
                    cleanupPlayer()
                    cancelAnimationAdvanceTimer()
                    return
                }
                if item.isAnimated {
                    if tabManager.reelsContinuousPlay {
                        startAnimationAdvanceTimer()
                    }
                    onInteraction()
                    return
                }
                if player == nil { setupPlayer() } else { refreshTimeObserver() }
                if isPlaying && !isRotating { ReelsPlayerRegistry.playIfAllowed(player) }
                onInteraction()
                DispatchQueue.main.async {
                    guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
                    if self.isActive && self.isPlaying && !self.isRotating && !self.isUserScrolling {
                        ReelsPlayerRegistry.playIfAllowed(self.player)
                    }
                }
            }
            .onChange(of: tabManager.reelsContinuousPlay) { _, enabled in
                if item.isAnimated {
                    if enabled && isActive {
                        startAnimationAdvanceTimer()
                    } else {
                        cancelAnimationAdvanceTimer()
                    }
                }
            }
            .onChange(of: playTrigger) { _, _ in
                // Fired by autoSelectFirstItem after setting currentVisibleSceneId.
                // At this point isActive should be true for the correct item.
                guard isActive && !isUserScrolling else { return }
                if player == nil { setupPlayer() }
                if isPlaying && !isRotating {
                    ReelsPlayerRegistry.playIfAllowed(player)
                    videoSurfaceReadiness.notePlaybackStarted()
                } else {
                    videoSurfaceReadiness.resyncFromBoundLayer()
                }
                // After nav pop the layer can keep the last frame; force a display refresh.
                DispatchQueue.main.async {
                    if self.isActive && self.isPlaying && !self.isRotating && !self.isUserScrolling {
                        ReelsPlayerRegistry.playIfAllowed(self.player)
                        self.videoSurfaceReadiness.notePlaybackStarted()
                    } else {
                        self.videoSurfaceReadiness.resyncFromBoundLayer()
                    }
                }
            }
            .onChange(of: isRotating) { _, newValue in
                if !newValue && isPlaybackActive && isPlaying {
                    ReelsPlayerRegistry.playIfAllowed(player)
                } else if newValue {
                    player?.pause()
                }
            }
            .onChange(of: player) { _, newPlayer in
                videoSurfaceReadiness.observe(player: newPlayer)
            }
    }

    @ViewBuilder
    private func applyOverlayModifiers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: showRatingOverlay) { _, newValue in
                isMenuOpen = newValue || showTagsOverlay
            }
            .onChange(of: showTagsOverlay) { _, newValue in
                isMenuOpen = newValue || showRatingOverlay
            }
            .onChange(of: isPlaying) { _, playing in
                guard isPlaybackActive else { return }
                if playing {
                    if !isRotating {
                        ReelsPlayerRegistry.playIfAllowed(player)
                        videoSurfaceReadiness.notePlaybackStarted()
                        startPlaybackActivityTrackingIfNeeded()
                    }
                } else {
                    player?.pause()
                    syncPlaybackActivityPosition()
                    playbackActivityTracker.stop()
                }
            }
            .onReceive(scrubberState.$seekTarget) { target in
                guard let t = target else { return }
                // Scrubber lives outside the pager; allow seek whenever this row is the active item
                // (do not require `!isUserScrolling` — that flag can briefly be true during chrome drags).
                guard isActive, player != nil else { return }
                seek(to: t)
                DispatchQueue.main.async {
                    if scrubberState.seekTarget != nil {
                        scrubberState.seekTarget = nil
                    }
                }
            }
            .onReceive(scrubberState.$seeking) { seeking in
                guard isActive else { return }
                if seeking {
                    player?.pause()
                } else if isPlaying, !isUserScrolling {
                    ReelsPlayerRegistry.playIfAllowed(player)
                    onInteraction()
                }
            }
    }


    @ViewBuilder
    private func applyStashSyncModifiers<V: View>(_ content: V) -> some View {
        content
            .modifier(StashSyncManagerModifier(isActive: isActive, isPlaying: isPlaying, player: player))
    }

    

    @ViewBuilder
    private var mediaLayer: some View {
        let bottomInset = immersiveBottomInset
        ZoomableScrollView(isZoomed: $isZoomed, onTap: handleMediaTap, onLongPress: handleLongPress) {
            ZStack {
                Color.black
                Group {
                    if item.isAnimated {
                        CustomAsyncImage(url: item.videoURL) { loader in
                            if let data = loader.imageData, isAnimatedData(data) {
                                AnimatedWebView(data: data, fillMode: shouldFill, bottomInset: bottomInset)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                                    // Visual-only inset; outer frame stays full-bleed for paging.
                                    .padding(.bottom, bottomInset)
                                    .clipped()
                            } else if loader.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.white)
                            }
                        }
                    } else {
                        // Bewusst kein Thumbnail mehr vor dem Video — schwarzer Hintergrund bleibt sichtbar,
                        // bis der Player das **erste echte Frame** dekodiert hat (`AVPlayerLayer.isReadyForDisplay`).
                        // Spart pro Karte einen `CustomAsyncImage`-Request + Render-Pass und vermeidet das Aufblitzen
                        // eines Standbilds vor dem Video.
                        if let player = player {
                            FullScreenVideoPlayer(
                                player: player,
                                videoGravity: shouldFill ? .resizeAspectFill : .resizeAspect,
                                bottomContentInset: bottomInset,
                                onLayerReady: { layer in
                                    videoSurfaceReadiness.bind(layer: layer)
                                }
                            )
                                .opacity(videoSurfaceReadiness.showsDecodedVideo ? 1 : 0)
                                .animation(.easeInOut(duration: 0.18), value: videoSurfaceReadiness.showsDecodedVideo)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Top only — do not expand under the bottom scrubber/capsule inset (steals scrubber drags).
        .ignoresSafeArea(edges: .top)
        .focusable(false)
        .focusEffectDisabled()
    }

    private func handleMediaTap(at location: CGPoint) {
        let screenHeight = UIScreen.main.bounds.height
        // Ignore taps in the top chrome and bottom info/scrubber area
        if location.y > 0 && location.y < 120 { return }
        if location.y > 0 && location.y > screenHeight - 160 { return }
        
        guard !isMenuOpen else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isUIVisible.toggle()
        }
        onInteraction()
    }

    private func handleLongPress(_ isPressed: Bool) {
        guard !item.isAnimated, let player = player else { return }
        
        if isPressed {
            #if !os(tvOS)
            HapticManager.selection()
            #endif
            player.rate = 2.0
            withAnimation {
                isFastForwarding = true
            }
        } else {
            player.rate = 1.0
            withAnimation {
                isFastForwarding = false
            }
        }
        onInteraction()
    }

    @ViewBuilder
    private var fastForwardOverlay: some View {
        if isFastForwarding {
            VStack {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    .padding(.top, 130)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var playButtonOverlay: some View {
        if !item.isAnimated && !isPlaying && isUIVisible && !isUserScrolling {
            CenterPlayButton {
                isPlaying = true
                if !isRotating { ReelsPlayerRegistry.playIfAllowed(player) }
                onInteraction()
            }
        }
    }

    @ViewBuilder
    private var bottomBarOverlay: some View {
        if isUIVisible {
            bottomOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            // Rating overlay (expands upward)
            if showRatingOverlay {
                    let rating = item.rating100 ?? 0
                    HStack {
                        StarRatingView(
                            rating100: rating,
                            isInteractive: true,
                            size: 28,
                            spacing: 10,
                            isVertical: false
                        ) { newRating in
                            onRatingChanged(newRating)
                            onInteraction()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showRatingOverlay = false
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(Edge.Set.horizontal, 16)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .padding(Edge.Set.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                

                // 3. Full-width progress bar moved to reelsFloatingBar
            }
        .sheet(isPresented: $showStashSyncSheet) {
            #if !os(tvOS)
            StashSyncSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
    }
    

    @ViewBuilder
    private func performerLabel(for item: ReelsViewBody.ReelItemData) -> some View {

        if let performer = item.performers.first {
            Button(action: { onPerformerTap(performer) }) {
                Text(performer.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func titleLabel(for item: ReelsViewBody.ReelItemData) -> some View {
        if let title = item.title, !title.isEmpty {
            Group {
                if let scene = item.underlyingScene {
                    NavigationLink(destination: SceneDetailView(scene: scene)) {
                        titleText(title, item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    titleText(title, item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func titleText(_ title: String, item: ReelsViewBody.ReelItemData) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            
            // Download Indicator
            let sceneId: String? = {
                if case .scene(let s) = item { return s.id }
                if case .marker(let m) = item { return m.scene?.id }
                if case .preview(let s) = item { return s.id }
                return nil
            }()
            
            if let sId = sceneId, DownloadManager.shared.isDownloaded(id: sId) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.green)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
        }
    }
    
    
    func setupPlayer() {
        // Animations don't need AVPlayer
        guard !item.isAnimated else { return }
        // Off-tab: do not create/upgrade players (createPlayer would re-activate AVAudioSession).
        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }

        // `onAppear` + scroll settle can both call `setupPlayer` in the same transition; avoid a second
        // `initPlayer`/generation bump (visible flash + duplicate stream work).
        if player != nil {
            refreshTimeObserver()
            updateBestStream(generation: playerSetupGeneration)
            if isPlaying && isPlaybackActive && !isRotating {
                ReelsPlayerRegistry.playIfAllowed(player)
            }
            return
        }

        playerSetupGeneration &+= 1
        let generation = playerSetupGeneration
        
        guard item.sceneID != nil else {
            if let url = item.videoURL { initPlayer(with: url, generation: generation) }
            return
        }
        
        // 1. Start with the immediate URL (legacy or cached) for instant playback
        if let url = item.videoURL {
            initPlayer(with: url, generation: generation)
        }
        
        // 2. Fetch best stream (MP4/HLS) only for the **active** reel — never for
        //    rows that only flashed past (those no longer call `setupPlayer`).
        updateBestStream(generation: generation)
    }
    
    private func updateBestStream(generation: Int) {
        guard let sid = item.sceneID else { return }
        
        // Optimization: If we are already using a local file, don't bother fetching streams
        // Local files are already the "best" possible quality/performance.
        if let currentURL = item.videoURL, !currentURL.absoluteString.hasPrefix("http") {
            return
        }
        
        // Background fetch for the "best" stream (MP4/HLS)
        viewModel.fetchSceneStreams(sceneId: sid) { streams in
            guard generation == self.playerSetupGeneration else { return }
            guard !streams.isEmpty else { return }
            
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            
            // Re-evaluate the best URL now that we have the full stream list
            let bestURL: URL?
            switch item {
            case .scene(let s):
                bestURL = s.withStreams(streams).bestStream(for: quality)
            case .marker(let m):
                bestURL = m.scene?.withStreams(streams).bestStream(for: quality)
            case .clip:
                bestURL = nil  // Clips don't use scene streams
            case .preview(let s):
                bestURL = s.previewURL
            }
            
            if let targetURL = bestURL {
                // Only switch if the target is significantly different from current (e.g. not just apikey diff)
                let currentURL = (player?.currentItem?.asset as? AVURLAsset)?.url
                if currentURL?.path != targetURL.path {
                    // Priority: Upgrade to MP4 if current is legacy, or better HLS if current is HLS
                    self.initPlayer(with: targetURL, generation: generation)
                }
            }
        }
    }
    
    private func initPlayer(with streamURL: URL, generation: Int) {
        guard generation == playerSetupGeneration else { return }
        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let authenticatedURL = signedURL(streamURL) ?? streamURL
        let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)
        
        let startTime = item.startTime
        
        if let existingPlayer = self.player {
            // Smooth Upgrade: Preserve state for active items
            let wasPlaying = existingPlayer.timeControlStatus == .playing
            let currentTime = existingPlayer.currentTime()
            
            // Reuse existing player for smoothness and to prevent VideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            
            existingPlayer.replaceCurrentItem(with: newItem)
            
            // Resume playback if this is the active item and the user intends to play.
            // Use isPlaying (binding = user intent) in addition to wasPlaying (AVPlayer state)
            // because the player may still be buffering (.waitingToPlayAtSpecifiedRate)
            // when the stream upgrade arrives.
            if isPlaybackActive && (wasPlaying || isPlaying) {
                existingPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                ReelsPlayerRegistry.playIfAllowed(existingPlayer)
            }
        } else {
            // First time player creation
            self.player = createPlayer(for: streamURL) // createPlayer handles AVAudioSession
        }
        
        guard let player = self.player else { return }
        ReelsPlayerRegistry.register(player)
        
        player.isMuted = isMuted
        if isPlaying && isPlaybackActive && !isRotating {
            ReelsPlayerRegistry.playIfAllowed(player)
        } else {
            player.pause()
            player.rate = 0
        }
        
        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        
        // Initial duration guess from model
        if let d = item.duration, d > 0 {
            if isActive { scrubberState.duration = d }
        }
        
        // Loop or Auto-Advance (Scenes and Clips)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            // Tab leave can race with end-of-item; never restart audio off-Feeds.
            guard !ReelsPlayerRegistry.isPlaybackSuspended, self.isPlaying, self.isPlaybackActive else { return }
            if TabManager.shared.reelsContinuousPlay {
                self.onVideoEnded()
                return
            }
            if case .scene = self.item {
                if startTime > 0 {
                    player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                } else {
                    player.seek(to: .zero)
                }
                ReelsPlayerRegistry.playIfAllowed(player)
                incrementPlayCount()
            } else if case .clip = self.item {
                player.seek(to: .zero)
                ReelsPlayerRegistry.playIfAllowed(player)
            } else if case .marker = self.item {
                let start = self.item.startTime
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                ReelsPlayerRegistry.playIfAllowed(player)
            } else if case .preview = self.item {
                player.seek(to: .zero)
                ReelsPlayerRegistry.playIfAllowed(player)
            }
        }
        
        // Time Observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if self.isActive && !self.scrubberState.seeking {
                self.scrubberState.time = time.seconds
            }
            
            // Media duration update
            if self.isActive, let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.scrubberState.duration = d
            }

            // Rotation-aware size (especially clips): preferredTransform → presentationSize
            self.syncPlaybackPresentationSize(from: player)
            self.syncPlaybackActivityPosition(from: player)
            if self.isPlaying && self.isPlaybackActive && !self.isRotating {
                self.startPlaybackActivityTrackingIfNeeded()
            }
        }
        
        // Increment play count (initial)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            incrementPlayCount()
        }

        if isPlaying && isPlaybackActive && !isRotating {
            startPlaybackActivityTrackingIfNeeded()
        }
    }
    
    func incrementPlayCount() {
        if let currentCount = item.playCount {
            onPlayCountChanged(currentCount + 1)
        }
    }

    private func configurePlaybackActivityTracker() {
        guard tracksPlaybackActivity, let sceneId = item.sceneID else { return }
        let vm = viewModel
        playbackActivityTracker.updatesResumeTime = {
            if case .scene = item { return true }
            return false
        }()
        playbackActivityTracker.onSave = { resumeTime, playDuration in
            guard playDuration > 0 || resumeTime != nil else { return }
            vm.updateSceneResumeTime(
                sceneId: sceneId,
                resumeTime: resumeTime,
                playDuration: playDuration
            ) { success in
                guard success, let resumeTime else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
    }

    private func startPlaybackActivityTrackingIfNeeded() {
        guard tracksPlaybackActivity, item.sceneID != nil else { return }
        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
        configurePlaybackActivityTracker()
        syncPlaybackActivityPosition()
        playbackActivityTracker.start()
    }

    private func syncPlaybackActivityPosition(from player: AVPlayer? = nil) {
        guard tracksPlaybackActivity else { return }
        let p = player ?? self.player
        let current = p?.currentTime().seconds ?? scrubberState.time
        let duration = p?.currentItem?.duration.seconds ?? scrubberState.duration
        playbackActivityTracker.setPosition(currentTime: current, duration: duration)
    }
    
    func cleanupPlayer() {
        playerSetupGeneration &+= 1
        syncPlaybackActivityPosition()
        playbackActivityTracker.stop()
        player?.pause()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Remove end of time observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        // Aggressively release resources
        if let p = player {
            ReelsPlayerRegistry.unregister(p)
            p.replaceCurrentItem(with: nil)
        }
        player = nil
        playbackPresentationSize = nil
    }

    /// Re-creates the periodic time observer so it captures the current `self`
    /// (with the correct `currentTime` / `duration` bindings). Called when the
    /// item becomes the active (visible) one after already having a player.
    func refreshTimeObserver() {
        if let old = timeObserver {
            player?.removeTimeObserver(old)
            timeObserver = nil
        }
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if self.isActive && !self.scrubberState.seeking {
                self.scrubberState.time = time.seconds
            }
            if self.isActive, let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.scrubberState.duration = d
            }
            self.syncPlaybackPresentationSize(from: player)
            self.syncPlaybackActivityPosition(from: player)
            if self.isPlaying && self.isPlaybackActive && !self.isRotating {
                self.startPlaybackActivityTrackingIfNeeded()
            }
        }
    }

    private func syncPlaybackPresentationSize(from player: AVPlayer) {
        let size = player.currentItem?.presentationSize ?? .zero
        guard size.width > 1, size.height > 1 else { return }
        if playbackPresentationSize != size {
            playbackPresentationSize = size
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        guard let player else { return }
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] _ in
            DispatchQueue.main.async {
                self.videoSurfaceReadiness.resyncFromBoundLayer()
                if self.isPlaying && self.isPlaybackActive && !self.isRotating {
                    ReelsPlayerRegistry.playIfAllowed(player)
                }
            }
        }
    }

    private func startAnimationAdvanceTimer() {
        // Only advance if continuous play is enabled
        guard tabManager.reelsContinuousPlay else { return }
        cancelAnimationAdvanceTimer()
        let duration = item.duration ?? 5.0
        animationAdvanceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            onVideoEnded()
        }
    }

    private func cancelAnimationAdvanceTimer() {
        animationAdvanceTimer?.invalidate()
        animationAdvanceTimer = nil
    }
}

struct StashSyncManagerModifier: ViewModifier {
    let isActive: Bool
    let isPlaying: Bool
    let player: AVPlayer?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                initialSync()
            }
            // Ein einziger `onChange(of: isActive)` — vorher waren das zwei separate Blöcke
            // (initialSync + Play/Pause-Resume), die quasi dasselbe taten und schwer zu lesen waren.
            .onChange(of: isActive) { _, active in
                if active { initialSync() }
            }
            .onChange(of: StashSyncManager.shared.isActive) { _, active in
                if active { initialSync() }
            }
            .onChange(of: player?.currentItem) { _, newItem in
                if StashSyncManager.shared.isActive {
                    ensureVideoAnalysis(for: newItem)
                }
            }
            .onChange(of: HandyManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { HandyManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: ButtplugManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { ButtplugManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: LoveSpouseManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { LoveSpouseManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: isPlaying) { _, playing in
                applyStashSyncPlaybackState(isActiveOverride: nil, isPlayingOverride: playing)
            }
    }

    /// Sync-Signale (Handy / Buttplug / LoveSpouse) ans aktuelle Play/Pause-Verhalten ankoppeln.
    /// Wird zentral genutzt von `initialSync` und vom `isPlaying`-onChange, damit Logik nur an einer Stelle lebt.
    private func applyStashSyncPlaybackState(isActiveOverride: Bool?, isPlayingOverride: Bool?) {
        let effActive = isActiveOverride ?? isActive
        let effPlaying = isPlayingOverride ?? isPlaying
        guard StashSyncManager.shared.isActive && effActive else { return }
        let currentTime = player?.currentTime().seconds ?? 0
        if effPlaying {
            if HandyManager.shared.isStashSyncMode { HandyManager.shared.play(at: currentTime) }
            if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.play(at: currentTime) }
            if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.play(at: currentTime) }
        } else {
            if HandyManager.shared.isStashSyncMode { HandyManager.shared.pause() }
            if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.pause() }
            if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.pause() }
        }
    }

    private func initialSync() {
        guard isActive && StashSyncManager.shared.isActive else { return }
        ensureVideoAnalysis(for: player?.currentItem)
        // Sync-Signale auf den aktuellen Play/Pause-Stand bringen — ersetzt den
        // früheren zweiten `onChange(of: isActive)`-Block.
        applyStashSyncPlaybackState(isActiveOverride: nil, isPlayingOverride: nil)
    }
    // MARK: - Helper Methods
    
    

    
    private func ensureVideoAnalysis(for item: AVPlayerItem?) {
        guard let item = item else { return }
        if HandyManager.shared.isStashSyncMode || ButtplugManager.shared.isStashSyncMode || LoveSpouseManager.shared.isStashSyncMode {
            StashVideoSyncManager.shared.setup(for: item)
            StashVideoSyncManager.shared.isActive = true
        }
    }
    
    private func checkAndStopStashSync() {
        if !HandyManager.shared.isStashSyncMode && 
           !ButtplugManager.shared.isStashSyncMode && 
           !LoveSpouseManager.shared.isStashSyncMode {
            StashSyncManager.shared.isActive = false
                        checkAndStopVideoAnalysis()
        }
    }
    
    private func checkAndStopVideoAnalysis() {
        if !ButtplugManager.shared.isStashSyncMode && !LoveSpouseManager.shared.isStashSyncMode {
            StashVideoSyncManager.shared.stop()
        }
    }
}

/// Feeds-Tab: optionales externes ViewModel (z. B. von ``MainTabView``), damit Listen beim Tab-Wechsel warm bleiben; Session-Position weiter in ``ReelsSessionRAM``.
struct ReelsView: View {
    @StateObject private var ownedViewModel = StashDBViewModel()
    private let externalViewModel: StashDBViewModel?

    init(viewModel: StashDBViewModel? = nil) {
        self.externalViewModel = viewModel
    }

    var body: some View {
        ReelsViewBody(viewModel: externalViewModel ?? ownedViewModel)
    }
}

// MARK: - Scrubber Isolation
class ScrubberState: ObservableObject {
    @Published var time: Double = 0.0
    @Published var duration: Double = 1.0
    @Published var seeking: Bool = false
    @Published var seekTarget: Double? = nil
}

struct IsolatedScrubberBar: View {
    @ObservedObject var state: ScrubberState
    var isUIVisible: Bool
    
    var body: some View {
        CustomVideoScrubber(
            value: Binding(
                get: { state.time },
                set: { val in
                    state.time = val
                    state.seekTarget = val
                }
            ),
            total: max(state.duration, 0.001),
            onEditingChanged: { editing in
                state.seeking = editing
            }
        )
        // Keep a bit more space below the scrubber so it sits ~5px higher.
        .padding(.bottom, 11)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .allowsHitTesting(isUIVisible)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }
}
#endif
