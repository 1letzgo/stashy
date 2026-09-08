#if !os(tvOS)
//
//  ReelsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVFoundation
import Combine
import AetherEngine

private extension Notification.Name {
    static let reelsPauseAllPlayers = Notification.Name("ReelsPauseAllPlayers")
    /// Hard teardown (pause + release item) — used when leaving video modes for Pics.
    static let reelsTeardownAllPlayers = Notification.Name("ReelsTeardownAllPlayers")
    /// Tab-bar (re)select: persist session then remount Feeds via `reelsTabID`.
    static let reelsWillRemount = Notification.Name("ReelsWillRemount")
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

/// Everything Feeds can pause / resume centrally. The playback engine is the only
/// implementation.
protocol ReelsPausable: AnyObject {
    func reelsPause()
    func reelsPlay()
    var reelsIsPlaying: Bool { get }
}

enum ReelsPlayerRegistry {
    private static let players = NSHashTable<AnyObject>.weakObjects()
    private static let lock = NSLock()
    /// When true, Feeds left the visible tab — block deferred `play()` / stream-upgrade races.
    private static var _isSuspended = false

    static var isPlaybackSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSuspended
    }

    /// Snapshot of the live registrations (the table is weak, entries can vanish).
    private static func registered() -> [ReelsPausable] {
        lock.lock()
        let all = players.allObjects
        lock.unlock()
        return all.compactMap { $0 as? ReelsPausable }
    }

    static func register(_ player: ReelsPausable) {
        lock.lock()
        players.add(player as AnyObject)
        lock.unlock()
    }

    static func unregister(_ player: ReelsPausable) {
        lock.lock()
        players.remove(player as AnyObject)
        lock.unlock()
    }

    static func pauseAll() {
        for player in registered() {
            player.reelsPause()
        }
    }

    /// Hard stop for tab leave: pause every registered player and reject further `playIfAllowed` until resume.
    static func suspendPlayback() {
        lock.lock()
        _isSuspended = true
        lock.unlock()
        for player in registered() {
            player.reelsPause()
        }
    }

    static func resumePlayback() {
        lock.lock()
        _isSuspended = false
        lock.unlock()
    }

    /// True while any registered player is actually running — used to tell "the feed never
    /// started" apart from "the user paused it".
    static var hasPlayingPlayer: Bool {
        registered().contains { $0.reelsIsPlaying }
    }

    /// Safe play entry point for Reel rows — no-op while Feeds is backgrounded/suspended.
    static func playIfAllowed(_ engine: AetherSceneEngine?) {
        guard let engine else { return }
        lock.lock()
        let suspended = _isSuspended
        lock.unlock()
        guard !suspended else { return }
        engine.reelsPlay()
    }
}

/// The engine wrapper is `@MainActor`; the registry is not. These hops keep the
/// conformance honest instead of asserting isolation the registry cannot promise.
extension AetherSceneEngine: ReelsPausable {
    nonisolated func reelsPause() {
        AetherReelsBridge.onMain(self) { $0.pause() }
    }

    nonisolated func reelsPlay() {
        AetherReelsBridge.onMain(self) { $0.play() }
    }

    nonisolated var reelsIsPlaying: Bool {
        AetherReelsBridge.readOnMain(self, fallback: false) { $0.isPlaying }
    }
}

/// Route of the active Feeds row, published for the chrome only. Changes once per row / route,
/// never on a per-frame path.
@MainActor
final class ReelsAetherRouteState: ObservableObject {
    static let shared = ReelsAetherRouteState()
    /// True while the active row plays through the engine's software route — no analysis item,
    /// so AI Motion has nothing to analyse.
    @Published var activeRowUsesSoftwareRoute = false
}

enum AetherReelsBridge {
    static func onMain(_ engine: AetherSceneEngine, _ body: @escaping @MainActor (AetherSceneEngine) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(engine) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { body(engine) }
            }
        }
    }

    static func readOnMain<T: Sendable>(_ engine: AetherSceneEngine,
                                        fallback: T,
                                        _ body: @MainActor (AetherSceneEngine) -> T) -> T {
        guard Thread.isMainThread else { return fallback }
        return MainActor.assumeIsolated { body(engine) }
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
                || key.hasPrefix("reels_session_mode_")
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
    /// Captured at remount time from ``NavigationCoordinator/reelsDeepLink``.
    private let deepLink: ReelsDeepLink
    @EnvironmentObject var coordinator: NavigationCoordinator

    init(viewModel: StashDBViewModel, deepLink: ReelsDeepLink = .empty) {
        self.viewModel = viewModel
        self.deepLink = deepLink
    }

    @State private var didConsumeDeepLink = false
    /// Deep-link already applied `applySettings` for the new mode; `onChange(reelsMode)` must
    /// not restore the previous Clips session (live chips / default o-counter filter).
    @State private var skipNextReelsModeSessionRestore = false
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedMarkerFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var selectedStudio: SceneStudio?
    // Same source as every other embed: headphone gate first, stored choice second.
    @State private var isMuted = ScenePlayerMute.initialValue()
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    /// Item behind the optional overlay delete button (scene / preview with files, or clip image).
    @State private var reelsItemToDelete: ReelItemData?
    @State private var reelsMode: ReelsMode = Self.sessionRestoredReelsMode()
    @State private var selectedMarkerSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .markers) ?? "") ?? .random
    @StateObject private var reelsClipImageFilters = DetailLinkedImagesFilterModel(
        scope: .reelsClips,
        initialSort: StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .clips) ?? "") ?? .random
    )
    /// Same catalog scope as Images 1/row — shared with embedded `ImagesView`.
    @StateObject private var reelsPicsFilters = DetailLinkedImagesFilterModel(
        scope: .catalogRoot,
        initialSort: StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .pics) ?? "") ?? .dateDesc
    )
    @StateObject private var reelsPicsViewModel = StashDBViewModel()
    @State private var tagEditorTarget: AITagTarget?
    /// Play state to hand back when the tag editor closes.
    @State private var wasPlayingBeforeTagEditor = false
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
    @StateObject private var reelsCriteriaDocument = FilterCriteriaDocument(mode: .scenes, pinsDefaults: true)
    @StateObject private var reelsMarkerCriteriaDocument = FilterCriteriaDocument(mode: .sceneMarkers, pinsDefaults: true)
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
    /// Bewusst `@State`, **nicht** `@StateObject`: Der Scrubber tickt mit 10 Hz und soll
    /// `ReelsViewBody` nicht neu rendern. Observiert wird nur in ``IsolatedScrubberBar``.
    @State private var scrubberState = ScrubberState()
    @State private var isInitialized = false
    /// Reentrancy guard: SwiftUI can fire `onAppear` multiple times during tab
    /// remounts before `isInitialized` flips — each pass would re-bootstrap and
    /// reset arrays/players mid-mount (black first cell).
    @State private var isBootstrapping = false
    @State private var playTrigger = 0  // Incremented when first item should autoplay
    /// Coalesces `activateFeed` delayed play kicks so mode switches don't stack timers.
    @State private var feedActivationGeneration = 0
    /// `reelsListView` is in the hierarchy (not the loading overlay).
    @State private var reelsListMounted = false
    /// Data is ready (or will be) — play only after the list has appeared and settled.
    @State private var pendingFeedActivation = false
    @State private var pendingRestoreId: String? = nil
    @State private var shouldScrollToTopAfterCriterionChange: Bool = false

    // MARK: - Session-persisted sort/filter (per server + mode)
    private static func reelsSessionServerID() -> String {
        ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
    }

    private static func reelsSessionModeKey() -> String {
        "reels_session_mode_\(reelsSessionServerID())"
    }

    /// Last Feeds sub-mode for this app launch (survives tab remounts).
    private static func sessionRestoredReelsMode() -> ReelsMode {
        let enabled = TabManager.shared.enabledReelsModes
        if let raw = ReelsSessionRAM.string(forKey: reelsSessionModeKey()),
           let mode = ReelsMode(rawValue: raw),
           enabled.contains(mode.toModeType) {
            return mode
        }
        return ReelsMode(from: enabled.first ?? .scenes)
    }

    private func persistSessionReelsMode(_ mode: ReelsMode? = nil) {
        ReelsSessionRAM.setString((mode ?? reelsMode).rawValue, forKey: Self.reelsSessionModeKey())
    }

    private func reelsSessionSortKey(for mode: ReelsMode) -> String {
        "reels_session_sort_\(Self.reelsSessionServerID())_\(mode.rawValue)"
    }

    private func reelsSessionFilterKey(for mode: ReelsMode) -> String {
        "reels_session_filter_\(Self.reelsSessionServerID())_\(mode.rawValue)"
    }

    private static func reelsSessionPerformerKey() -> String {
        "reels_session_performer_\(reelsSessionServerID())"
    }

    private static func reelsSessionTagsKey() -> String {
        "reels_session_tags_\(reelsSessionServerID())"
    }

    private static func reelsSessionStudioKey() -> String {
        "reels_session_studio_\(reelsSessionServerID())"
    }

    private var hasActiveCriterionOverlay: Bool {
        selectedPerformer != nil || !selectedTags.isEmpty || selectedStudio != nil
    }

    private func persistSessionCriteria() {
        if let performer = selectedPerformer,
           let data = try? JSONEncoder().encode(performer),
           let json = String(data: data, encoding: .utf8) {
            ReelsSessionRAM.setString(json, forKey: Self.reelsSessionPerformerKey())
        } else {
            ReelsSessionRAM.setString(nil, forKey: Self.reelsSessionPerformerKey())
        }
        if selectedTags.isEmpty {
            ReelsSessionRAM.setString(nil, forKey: Self.reelsSessionTagsKey())
        } else if let data = try? JSONEncoder().encode(selectedTags),
                  let json = String(data: data, encoding: .utf8) {
            ReelsSessionRAM.setString(json, forKey: Self.reelsSessionTagsKey())
        }
        if let studio = selectedStudio,
           let data = try? JSONEncoder().encode(studio),
           let json = String(data: data, encoding: .utf8) {
            ReelsSessionRAM.setString(json, forKey: Self.reelsSessionStudioKey())
        } else {
            ReelsSessionRAM.setString(nil, forKey: Self.reelsSessionStudioKey())
        }
    }

    /// Restores performer/tag/studio chips across tab remounts (warm VM keeps lists; criteria live in RAM).
    private func restoreSessionCriteria() {
        if let json = ReelsSessionRAM.string(forKey: Self.reelsSessionPerformerKey()),
           let data = json.data(using: .utf8),
           let performer = try? JSONDecoder().decode(ScenePerformer.self, from: data) {
            selectedPerformer = performer
        } else {
            selectedPerformer = nil
        }
        if let json = ReelsSessionRAM.string(forKey: Self.reelsSessionTagsKey()),
           let data = json.data(using: .utf8),
           let tags = try? JSONDecoder().decode([Tag].self, from: data) {
            selectedTags = tags
        } else {
            selectedTags = []
        }
        if let json = ReelsSessionRAM.string(forKey: Self.reelsSessionStudioKey()),
           let data = json.data(using: .utf8),
           let studio = try? JSONDecoder().decode(SceneStudio.self, from: data) {
            selectedStudio = studio
        } else {
            selectedStudio = nil
        }
    }

    private func sessionSortRaw(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionSortKey(for: mode))
    }

    private func sessionFilterId(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionFilterKey(for: mode))
    }

    private func saveSessionState(for mode: ReelsMode) {
        persistSessionReelsMode(mode)

        // Sort
        let sortRaw: String? = {
            switch mode {
            case .scenes: return selectedSortOption.rawValue
            case .markers: return selectedMarkerSortOption.rawValue
            case .clips: return reelsClipImageFilters.selectedSortOption.rawValue
            case .previews: return selectedSortOption.rawValue
            case .pics: return reelsPicsFilters.selectedSortOption.rawValue
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
            case .pics: return reelsPicsFilters.selectedFilter?.id
            }
        }()
        if let id = filterId, !id.isEmpty {
            ReelsSessionRAM.setString(id, forKey: reelsSessionFilterKey(for: mode))
        } else {
            ReelsSessionRAM.setString(nil, forKey: reelsSessionFilterKey(for: mode))
        }

        persistSessionCriteria()
    }

    /// Re-fetch the active sub-mode with performer/tag overlay and without injecting Settings defaults.
    private func syncFeedToCriterionOverlay(rerollRandom: Bool = false) {
        guard hasActiveCriterionOverlay else { return }
        switch reelsMode {
        case .scenes:
            applySettings(
                sortBy: selectedSortOption,
                sceneFilter: selectedFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                rerollRandom: rerollRandom
            )
        case .markers:
            applySettings(
                markerSortBy: selectedMarkerSortOption,
                markerFilter: selectedMarkerFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                rerollRandom: rerollRandom
            )
        case .clips:
            applySettings(
                clipSortBy: reelsClipImageFilters.selectedSortOption,
                clipFilter: reelsClipImageFilters.selectedFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                rerollRandom: rerollRandom
            )
        case .previews:
            applySettings(
                previewSortBy: selectedSortOption,
                previewFilter: selectedPreviewFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                rerollRandom: rerollRandom
            )
        case .pics:
            applyReelsPicsNavigation(performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
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

    /// Performer / Studio / Tag → Feeds: the feed must show exactly the handed criteria.
    /// Quick chips and advanced criteria left over from the session would silently narrow it —
    /// the chips were only reset *after* `applySettings` had already fetched, and the criteria
    /// document was never reset at all. Mirrors `applyReelsPicsNavigation`, which already
    /// enters with Filter = None.
    private func reelsClearSessionFiltersForDeepLink() {
        reelsSceneLiveChips.clearChipsOnly()
        reelsMarkerLiveChips.clearChipsOnly()
        reelsPreviewLiveChips.clearChipsOnly()
        reelsCriteriaDocument.clear()
        reelsMarkerCriteriaDocument.clear()
        reelsClipImageFilters.selectedFilter = nil
        reelsClipImageFilters.catalogPresetRowSelection = ""
        reelsClipImageFilters.clearLiveChipsOnly()
        reelsClipImageFilters.criteriaDocument.clear()
        reelsPicsFilters.selectedFilter = nil
        reelsPicsFilters.catalogPresetRowSelection = ""
        reelsPicsFilters.clearLiveChipsOnly()
        reelsPicsFilters.criteriaDocument.clear()
        // Every mode, not just the one we land on: switching modes later restores
        // `sessionFilterId(for:)`, which would otherwise hand the old filter back.
        for mode in [ReelsMode.scenes, .markers, .clips, .previews, .pics] {
            ReelsSessionRAM.setString(nil, forKey: reelsSessionFilterKey(for: mode))
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
        case .pics: break
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
        case .pics: break
        }
    }

    /// What a preset stores for the active mode: the criteria document of that mode.
    private func reelsActivePresetLiveFragment() -> [String: Any] {
        switch reelsMode {
        case .markers: return reelsMarkerCriteriaDocument.sanitizedObjectFilter
        default: return reelsCriteriaDocument.sanitizedObjectFilter
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
            studio: selectedStudio,
            mode: .images
        )
        vm.abandonInactiveReelsFeeds(keeping: .clips)
        if let signature = reelsFeedSignature(for: .clips) {
            vm.rememberReelsFeedSignature(signature)
        }
        vm.fetchClips(
            sortBy: reelsClipImageFilters.selectedSortOption,
            filter: merged,
            isInitialLoad: true,
            liveFilter: reelsClipImageFilters.imageLiveFragmentForFetch()
        )
        vm.clearReelsCriterionFrozenSnapshots()
        currentVisibleSceneId = nil
        saveSessionState(for: .clips)
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
            applySettings(sortBy: new, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
        case .previews:
            applySettings(previewSortBy: new, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
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
        applySettings(markerSortBy: new, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
    }

    private func reelsApplySceneLiveFromSheet() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, sceneLiveRefresh: true)
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
            // "None" must also empty the editor — otherwise the criteria of the filter just
            // deselected keep filtering the feed from the document.
            reelsLoadPresetCriteria([:], base: nil)
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
        // Preset-Kriterien in das Dokument des aktiven Modus — das ist die einzige Filterfläche.
        reelsLoadPresetCriteria(preset.liveFragment, base: reelsLiveChipTargetFilter)
        reelsApplySceneLiveFromSheet()
    }

    /// Spiegelt den gewählten Filter in das Kriterien-Dokument des aktiven Modus: erst die
    /// Kriterien des Server-Filters, darüber das stashy-Fragment des Presets.
    ///
    /// Ohne diese Spiegelung stünde die Sheet leer da, obwohl der Feed gefiltert ist — die
    /// Studios/Tags eines Filters tauchten in ihren Karten nicht auf.
    private func reelsLoadPresetCriteria(_ fragment: [String: Any], base: StashDBViewModel.SavedFilter?) {
        var merged: [String: Any] = base?.criteriaObjectFilter() ?? [:]
        for (key, value) in fragment { merged[key] = value }
        if reelsMode == .markers {
            reelsMarkerCriteriaDocument.load(merged)
        } else {
            reelsCriteriaDocument.load(merged)
        }
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
        reelsLoadPresetCriteria(f.stashyScenePresetMetadata?.liveFragment ?? [:], base: reelsLiveChipTargetFilter)
        reelsApplySceneLiveFromSheet()
    }

    private func reelsSaveSceneLivePresetOverwrite() {
        let sel = reelsActiveSheetPresetIdForRead
        let liveDict = reelsActivePresetLiveFragment()
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
            liveFragment: reelsActivePresetLiveFragment()
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
                liveFragment: reelsActivePresetLiveFragment()
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
        case .pics: return .images
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
        case .pics: return nil
        }
    }

    private func savedPosition(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsPositionKey(for: mode))
    }

    private func savePosition(_ id: String, for mode: ReelsMode) {
        ReelsSessionRAM.setString(id, forKey: reelsPositionKey(for: mode))
    }

    private func clearSavedPosition(for mode: ReelsMode) {
        ReelsSessionRAM.setString(nil, forKey: reelsPositionKey(for: mode))
    }

    /// Tab-bar reselect: rebuild Feeds from the first item (not mid-timeline restore).
    private static func reelsRestartFromTopKey() -> String {
        "reels_restart_from_top_\(reelsSessionServerID())"
    }

    private var shouldRestartFeedFromTop: Bool {
        ReelsSessionRAM.string(forKey: Self.reelsRestartFromTopKey()) != nil
    }

    private func markRestartFeedFromTop() {
        ReelsSessionRAM.setString("1", forKey: Self.reelsRestartFromTopKey())
    }

    private func clearRestartFeedFromTopFlag() {
        ReelsSessionRAM.setString(nil, forKey: Self.reelsRestartFromTopKey())
    }

    private func saveCurrentPositionIfPossible(for mode: ReelsMode) {
        // Tab-bar remount asks for a fresh start — don't re-persist the old index.
        guard !shouldRestartFeedFromTop else { return }
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
        guard !shouldRestartFeedFromTop else {
            ReelsSessionRAM.setString(nil, forKey: reelsPlaybackCheckpointKey(for: mode))
            return
        }
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
        // The fallback can hand us the *previous* mode's id (switching markers → clips
        // leaves "marker-…" in `currentVisibleSceneId`). Chasing it pages the new feed
        // forever for something that can never appear in it.
        if let expected = expectedPrefix(for: reelsMode), !targetId.hasPrefix(expected + "-") {
            pendingRestoreId = nil
            return
        }
        // If it's already present, bind selection — clearing `pendingRestoreId` alone
        // left `currentVisibleSceneId` nil after tab remounts (blank Clips feed).
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            currentVisibleSceneId = targetId
            return
        }
        // Restores driven by a *saved* position: all feed types run on seeded random
        // standard filters (`random_<seed>`), so pages stay stable within a session
        // and the target remains findable — a generous chase is safe and correct.
        pendingRestoreId = targetId
        restorePageBudget = Self.maxRestorePages
        continuePagedRestoreIfNeeded()
    }

    /// Pages loaded while chasing a restore target. Prevents an unreachable target
    /// (e.g. saved position without preview/stream after filter change) from paging
    /// through the whole library. Generous: deep saved positions need many pages.
    static let maxRestorePages = 24
    @State private var restorePageBudget: Int = 0

    private func continuePagedRestoreIfNeeded() {
        guard let targetId = pendingRestoreId else { return }

        // Stop when found.
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            return
        }

        // Stop when the chase budget is exhausted — give up on the target so it
        // cannot re-trigger paging on every future items change.
        guard restorePageBudget > 0 else {
            pendingRestoreId = nil
            return
        }

        // Load more until we either find it or run out of pages.
        switch reelsMode {
        case .scenes:
            guard viewModel.hasMoreScenes, !viewModel.isLoadingMoreScenes else { return }
            restorePageBudget -= 1
            viewModel.loadMoreScenes()
        case .markers:
            guard viewModel.hasMoreMarkers, !viewModel.isLoadingMarkers else { return }
            restorePageBudget -= 1
            viewModel.loadMoreMarkers()
        case .clips:
            guard viewModel.hasMoreClips, !viewModel.isLoadingClips else { return }
            restorePageBudget -= 1
            viewModel.loadMoreClips()
        case .previews:
            guard viewModel.hasMorePreviews, !viewModel.isLoadingMorePreviews else { return }
            restorePageBudget -= 1
            viewModel.loadMorePreviews()
        case .pics: break
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

    /// True while paging may rewrite `scrollPosition` before the snap finishes (defer next row player setup).
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
        case pics = "Pics"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .markers: return "bookmark.fill"
            case .clips: return "photo.on.rectangle.angled"
            case .previews: return "play.rectangle.on.rectangle.fill"
            case .pics: return "camera.fill"
            }
        }
        
        var toModeType: ReelsModeType {
            switch self {
            case .scenes: return .scenes
            case .markers: return .markers
            case .clips: return .clips
            case .previews: return .previews
            case .pics: return .pics
            }
        }
        
        init(from type: ReelsModeType) {
            switch type {
            case .scenes: self = .scenes
            case .markers: self = .markers
            case .clips: self = .clips
            case .previews: self = .previews
            case .pics: self = .pics
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
        
        var isClip: Bool {
            if case .clip = self { return true }
            return false
        }

        /// What AI Tags and the manual "+" act on. Markers are tagged as themselves —
        /// they carry their own tags in Stash — while previews are just scenes.
        var aiTagTarget: AITagTarget {
            switch self {
            case .scene(let s), .preview(let s): return .scene(s)
            case .marker(let m): return .marker(m)
            case .clip(let c): return .image(c)
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
            switch self {
            case .scene(let s):
                // The engine plays the original file — no transcode / quality pick.
                return s.aetherVideoURL

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
                // using the engine's decoded source size when available.
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

        /// Rows a scrub still can be decoded for: real video with a stream.
        /// Clips are images and animations have no timeline.
        var supportsScrubPreview: Bool {
            // Animated clips (GIF/WebP) have no video track to decode; video clips do.
            guard !isAnimated else { return false }
            return videoURL != nil
        }

    }

    private var currentReelItems: [ReelItemData] {
        switch reelsMode {
        case .scenes: return viewModel.scenes.map { ReelItemData.scene($0) }
        case .markers: return viewModel.sceneMarkers.filter { $0.stream != nil && !$0.stream!.isEmpty }.map { ReelItemData.marker($0) }
        case .clips: return viewModel.clips.map { ReelItemData.clip($0) }
        case .previews: return viewModel.previews.map { ReelItemData.preview($0) }
        case .pics: return []
        }
    }

    

    private func applyPerformerFilter(_ performer: ScenePerformer) {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: performer, tags: selectedTags, studio: selectedStudio)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: performer, tags: selectedTags, studio: selectedStudio)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: performer, tags: selectedTags, studio: selectedStudio)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: performer, tags: selectedTags, studio: selectedStudio)
        case .pics:
            selectedPerformer = performer
            selectedTags = []
            reelsPicsFilters.liveFilterTagIds = []
            reelsPicsViewModel.imagePerformerIdFilter = performer.id
            reelsPicsFilters.suppressSettingsDefaultFilter = true
            reelsPicsFilters.selectedFilter = nil
            reelsPicsFilters.catalogPresetRowSelection = ""
            reelsPicsViewModel.currentImageFilter = nil
            persistSessionCriteria()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        }
    }

    /// Takes a tag off the item itself (not off the filter). A marker's primary tag is
    /// a separate field in Stash and is left alone.
    private func removeTag(_ tag: Tag, from target: AITagTarget) {
        guard tag.id != target.primaryTagId else { return }
        let remaining = target.tags.filter { $0.id != tag.id }
        Task {
            let success = await AITagSuggestionManager.shared.write(tags: remaining, to: target)
            if success {
                HapticManager.success()
                ToastManager.shared.show("Removed #\(tag.name)")
            } else {
                HapticManager.error()
                ToastManager.shared.show("Could not remove tag", icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private func applyTagsChange(_ newTags: [Tag]) {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: newTags, studio: selectedStudio)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: newTags, studio: selectedStudio)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: newTags, studio: selectedStudio)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: newTags, studio: selectedStudio)
        case .pics:
            selectedTags = newTags
            reelsPicsFilters.liveFilterTagIds = newTags.map(\.id)
            if newTags.isEmpty && selectedPerformer == nil && selectedStudio == nil {
                reelsPicsRestoreDefaultFilterAfterDeepLinkIfNeeded()
            } else {
                reelsPicsFilters.suppressSettingsDefaultFilter = true
                reelsPicsFilters.selectedFilter = nil
                reelsPicsFilters.catalogPresetRowSelection = ""
                reelsPicsViewModel.currentImageFilter = nil
            }
            persistSessionCriteria()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        }
    }

    private func applyClearPerformerOnly() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: nil, tags: selectedTags, studio: selectedStudio)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: nil, tags: selectedTags, studio: selectedStudio)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: nil, tags: selectedTags, studio: selectedStudio)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: nil, tags: selectedTags, studio: selectedStudio)
        case .pics:
            selectedPerformer = nil
            reelsPicsViewModel.imagePerformerIdFilter = nil
            if selectedTags.isEmpty && selectedStudio == nil {
                reelsPicsRestoreDefaultFilterAfterDeepLinkIfNeeded()
            }
            persistSessionCriteria()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        }
    }

    private func applyClearStudioOnly() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: nil)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: nil)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: nil)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, studio: nil)
        case .pics:
            selectedStudio = nil
            reelsPicsFilters.liveFilterStudioIds = []
            if selectedTags.isEmpty && selectedPerformer == nil {
                reelsPicsRestoreDefaultFilterAfterDeepLinkIfNeeded()
            }
            persistSessionCriteria()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        }
    }

    private func reelsFeedKind(for mode: ReelsMode) -> StashDBViewModel.ReelsFeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .markers: return .markers
        case .clips: return .clips
        case .previews: return .previews
        case .pics: return nil
        }
    }

    /// Fragment mirrored from the selected saved filter, with the criteria editor on top.
    private func reelsSceneLive(_ base: [String: Any]?) -> [String: Any]? {
        reelsCriteriaDocument.layered(over: base ?? [:])
    }

    /// Marker counterpart of ``reelsSceneLive(_:)``.
    private func reelsMarkerLive(_ base: [String: Any]?) -> [String: Any]? {
        reelsMarkerCriteriaDocument.layered(over: base ?? [:])
    }

    /// Criteria identity for the given mode — used to skip a page-1 refetch when the VM list is still valid.
    private func reelsFeedSignature(for mode: ReelsMode) -> StashDBViewModel.ReelsFeedSignature? {
        guard let kind = reelsFeedKind(for: mode) else { return nil }
        switch mode {
        case .scenes:
            return viewModel.makeReelsFeedSignature(
                kind: kind,
                sortField: selectedSortOption.sortField,
                direction: selectedSortOption.direction,
                filterId: selectedFilter?.id,
                liveFilter: reelsSceneLive(reelsSceneLiveChips.effectiveLiveFilter(for: selectedFilter)),
                performerId: selectedPerformer?.id,
                tagIds: selectedTags.map(\.id),
                studioId: selectedStudio?.id
            )
        case .markers:
            return viewModel.makeReelsFeedSignature(
                kind: kind,
                sortField: selectedMarkerSortOption.sortField,
                direction: selectedMarkerSortOption.direction,
                filterId: selectedMarkerFilter?.id,
                liveFilter: reelsMarkerLive(reelsMarkerLiveChips.effectiveLiveFilter(for: selectedMarkerFilter)),
                performerId: selectedPerformer?.id,
                tagIds: selectedTags.map(\.id),
                studioId: selectedStudio?.id
            )
        case .clips:
            return viewModel.makeReelsFeedSignature(
                kind: kind,
                sortField: reelsClipImageFilters.selectedSortOption.sortField,
                direction: reelsClipImageFilters.selectedSortOption.direction,
                filterId: reelsClipImageFilters.selectedFilter?.id,
                liveFilter: reelsClipImageFilters.imageLiveFragmentForFetch(),
                performerId: selectedPerformer?.id,
                tagIds: selectedTags.map(\.id),
                studioId: selectedStudio?.id
            )
        case .previews:
            return viewModel.makeReelsFeedSignature(
                kind: kind,
                sortField: selectedSortOption.sortField,
                direction: selectedSortOption.direction,
                filterId: selectedPreviewFilter?.id,
                liveFilter: reelsSceneLive(reelsPreviewLiveChips.effectiveLiveFilter(for: selectedPreviewFilter)),
                performerId: selectedPerformer?.id,
                tagIds: selectedTags.map(\.id),
                studioId: selectedStudio?.id
            )
        case .pics:
            return nil
        }
    }

    private func isWarmFeed(for mode: ReelsMode) -> Bool {
        guard let kind = reelsFeedKind(for: mode),
              let signature = reelsFeedSignature(for: mode) else { return false }
        return viewModel.hasWarmReelsFeed(kind, signature: signature)
    }

    /// Queue play until GraphQL page-1 is in and `reelsListView` is actually on screen.
    /// Calling this while the loading overlay is up wastes `playTrigger` (no rows exist yet).
    private func activateFeed() {
        requestFeedActivation()
    }

    private func requestFeedActivation() {
        guard reelsMode != .pics else { return }
        guard coordinator.selectedTab == .reels else { return }
        pendingFeedActivation = true
        guard !isFeedLoading, !isListEmpty else { return }
        autoSelectFirstItem(bumpPlay: false)
        guard reelsListMounted else { return }
        activateFeedAfterListSettles()
    }

    /// First paint of a mode remounts the list; paging emits `.animating` after this frame.
    /// Kick on the next runloop, then again after layout/paging has had time to go idle.
    private func activateFeedAfterListSettles() {
        guard reelsMode != .pics else { return }
        guard !isFeedLoading, !isListEmpty else { return }
        feedActivationGeneration += 1
        let generation = feedActivationGeneration
        let kick = {
            guard generation == self.feedActivationGeneration else { return }
            guard self.coordinator.selectedTab == .reels, self.reelsMode != .pics else { return }
            guard !self.isFeedLoading, !self.isListEmpty else { return }
            // Die drei gestaffelten Kicks sind Retries, falls der erste vor dem Layout läuft —
            // nicht drei Aktivierungen. Sie müssen feuern, solange der Feed *nicht* angelaufen
            // ist (sonst bleibt der Tab schwarz); sobald etwas spielt, würden sie nur noch eine
            // frisch getippte User-Pause überschreiben.
            // "Something is already playing" is only a reason to stand down when that
            // something belongs to the mode we are activating. Coming from another feed
            // (pics → previews → clips) a player of the *previous* mode can still report
            // .playing, and taking the shortcut there left the new feed's first item
            // black and unselected.
            let visibleBelongsToMode: Bool = {
                guard let id = self.currentVisibleSceneId,
                      let prefix = self.expectedPrefix(for: self.reelsMode) else { return false }
                return id.hasPrefix(prefix + "-")
            }()
            guard !(ReelsPlayerRegistry.hasPlayingPlayer && visibleBelongsToMode) else {
                self.pendingFeedActivation = false
                return
            }
            self.isUserScrollingReels = false
            self.currentItemIsPlaying = true
            self.reelsWasPlayingBeforeScrollGesture = true
            ReelsPlayerRegistry.resumePlayback()
            self.autoSelectFirstItem(bumpPlay: false)
            self.playTrigger += 1
            self.pendingFeedActivation = false
        }
        DispatchQueue.main.async(execute: kick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: kick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: kick)
    }

    /// After clearing a Feeds deep-link, allow Settings default filter again.
    private func reelsPicsRestoreDefaultFilterAfterDeepLinkIfNeeded() {
        guard reelsPicsFilters.suppressSettingsDefaultFilter else { return }
        reelsPicsFilters.suppressSettingsDefaultFilter = false
        if reelsPicsFilters.selectedFilter == nil,
           let defId = TabManager.shared.getDefaultFilterId(for: .images) {
            let filter = viewModel.savedFilters[defId] ?? reelsPicsViewModel.savedFilters[defId]
            reelsPicsFilters.selectedFilter = filter
            if let filter {
                reelsPicsFilters.catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
            }
        }
        saveSessionState(for: .pics)
    }

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, previewSortBy: StashDBViewModel.SceneSortOption? = nil, sceneFilter: StashDBViewModel.SavedFilter? = nil, markerFilter: StashDBViewModel.SavedFilter? = nil, clipFilter: StashDBViewModel.SavedFilter? = nil, previewFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], studio: SceneStudio? = nil, mode: ReelsMode? = nil, clearClipFilter: Bool = false, clearSceneFilter: Bool = false, clearMarkerFilter: Bool = false, clearPreviewFilter: Bool = false, rerollRandom: Bool = false, sceneLiveRefresh: Bool = false, clipImageLiveRefresh: Bool = false, stripLiveChips: Bool = false) {
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

        let hadCriterionOverlay = selectedPerformer != nil || !selectedTags.isEmpty || selectedStudio != nil
        let willCriterionOverlay = performer != nil || !tags.isEmpty || studio != nil

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
            case .pics: break
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
            case .pics: break
            }
            // Entering a criterion overlay (performer/tags/studio) should start at the top of the
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
        selectedStudio = studio

        // Overlay performer/tags/studio only when the user actually set a criterion overlay.
        // An empty merge used to rewrite `object_filter` via a blank `c` array and drop
        // `ui_options` — Channel fetches then lost tags that Feeds still applied via chips.
        let hasCriterionOverlay = performer != nil || !tags.isEmpty || studio != nil
        let mergedSceneFilter = hasCriterionOverlay
            ? viewModel.mergeFilterWithCriteria(filter: resolvedSceneFilterEarly, performer: performer, tags: tags, studio: studio, mode: .scenes)
            : resolvedSceneFilterEarly
        let mergedMarkerFilter = hasCriterionOverlay
            ? viewModel.mergeFilterWithCriteria(filter: resolvedMarkerFilterEarly, performer: performer, tags: tags, studio: studio, mode: .sceneMarkers)
            : resolvedMarkerFilterEarly
        let mergedClipFilter = hasCriterionOverlay
            ? viewModel.mergeFilterWithCriteria(filter: resolvedClipFilter, performer: performer, tags: tags, studio: studio, mode: .images)
            : resolvedClipFilter
        let mergedPreviewFilter = hasCriterionOverlay
            ? viewModel.mergeFilterWithCriteria(filter: resolvedPreviewFilter, performer: performer, tags: tags, studio: studio, mode: .scenes)
            : resolvedPreviewFilter
        let sceneLiveForScenes = stripLiveChips ? nil : reelsSceneLive(reelsSceneLiveChips.effectiveLiveFilter(for: resolvedSceneFilterEarly))
        let sceneLiveForMarkers = stripLiveChips ? nil : reelsMarkerLive(reelsMarkerLiveChips.effectiveLiveFilter(for: resolvedMarkerFilterEarly))
        let sceneLiveForPreviews = stripLiveChips ? nil : reelsSceneLive(reelsPreviewLiveChips.effectiveLiveFilter(for: resolvedPreviewFilter))

        if usedFrozenRestore {
            saveSessionState(for: currentMode)
            activateFeed()
            return
        }

        if !rerollRandom,
           let kind = reelsFeedKind(for: currentMode),
           let signature = reelsFeedSignature(for: currentMode),
           viewModel.hasWarmReelsFeed(kind, signature: signature) {
            viewModel.setActiveReelsFeed(kind)
            saveSessionState(for: currentMode)
            activateFeed()
            return
        }

        if let kind = reelsFeedKind(for: currentMode) {
            viewModel.abandonInactiveReelsFeeds(keeping: kind)
            if let signature = reelsFeedSignature(for: currentMode) {
                viewModel.rememberReelsFeedSignature(signature)
            }
        }

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
                liveFilter: stripLiveChips ? [:] : reelsClipImageFilters.imageLiveFragmentForFetch()
            )
        case .previews:
            viewModel.fetchPreviews(sortBy: selectedSortOption, isInitialLoad: true, filter: mergedPreviewFilter, liveFilter: sceneLiveForPreviews)
        case .pics: break
        }

        saveSessionState(for: currentMode)
    }
    
    private func autoSelectFirstItem(bumpPlay: Bool = true) {
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
                if bumpPlay { playTrigger += 1 }
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
                if bumpPlay { playTrigger += 1 }
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
            case .pics: break
            }
            if let id = newId {
                // Show first item while paging walks toward pendingRestoreId in
                // the background. Don't clear pendingRestoreId here — the snap
                // will fire once the target is loaded.
                currentVisibleSceneId = id
                if bumpPlay { playTrigger += 1 }
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
        case .markers:
            // Markers without streams are filtered out of the feed — an all-streamless
            // marker list must count as empty, otherwise the UI renders zero rows
            // without spinner/error (blank screen).
            return viewModel.sceneMarkers.allSatisfy { $0.stream == nil || $0.stream!.isEmpty }
        case .clips: return viewModel.clips.isEmpty
        case .previews: return viewModel.previews.isEmpty
        case .pics: return false
        }
    }

    /// Mode-specific loading — `viewModel.isLoading` is not set by `fetchScenes` and hid the spinner.
    private var isFeedLoading: Bool {
        switch reelsMode {
        case .scenes: return viewModel.isLoadingScenes
        case .markers: return viewModel.isLoadingMarkers
        case .clips: return viewModel.isLoadingClips
        case .previews: return viewModel.isLoadingPreviews || viewModel.isLoading
        case .pics: return false
        }
    }

    /// Same gate as Pics (`isLoadingImages && allImages.isEmpty`): spinner only while a fetch is in flight.
    private var showsBlockingFeedLoad: Bool {
        isFeedLoading && isListEmpty
    }

    private var showsFeedConnectionError: Bool {
        isListEmpty && !isFeedLoading && viewModel.errorMessage != nil
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
        case .pics:
            return nil
        }
    }

    /// Kein Server / Verbindungsfehler / Laden: untere Capsule- & Scrubber-Leiste ausblenden (wie Pics).
    private var reelsBottomChromeSuppressed: Bool {
        if reelsMode == .pics { return true }
        if isListEmpty { return true }
        return configManager.activeConfig == nil
    }

    /// Voller Rand-zu-Rand-Modus nur für den eigentlichen Reels-Player. Bei leerer Liste + Laden/Fehler
    /// bleibt die System-Safe-Area aktiv, damit zentrierte States (`ConnectionErrorView`, Loading)
    /// mit der oberen `safeAreaInset`-Nav-Leiste fluchten und nicht „nach oben rutschen“.
    private var reelsPremiumContentSafeAreaRegions: SafeAreaRegions {
        if reelsMode == .pics { return [] }
        if isListEmpty { return [] }
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // iOS pauses playback on backgrounding but never tells SwiftUI, so
                // `currentItemIsPlaying` would stay `true` over a paused player. Pausing here
                // keeps the play button and the player in the same state.
                guard coordinator.selectedTab == .reels, reelsMode != .pics else { return }
                reelsPausePlaybackForLocalTeardown()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Same path the tab switch uses — re-arms the audio session, restores the
                // checkpoint and re-asserts play intent. Without it Feeds came back paused
                // while the button still read "playing", so the first tap only flipped the
                // flag and a second one was needed to actually resume.
                guard coordinator.selectedTab == .reels else { return }
                guard isInitialized else { return }
                reelsResumePlaybackAfterReturn()
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
                // Still on Feeds (push/pop or tab remount): pause only — never `suspendPlayback()`.
                // Remount destroys this view *after* the new instance's `onAppear`; suspending here
                // would leave `playIfAllowed` as a permanent no-op for Clips.
                if coordinator.selectedTab == .reels {
                    reelsPausePlaybackForLocalTeardown()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reelsWillRemount)) { _ in
                // Tab-bar icon: restart feed from the top (mode/filter stay; position does not).
                markRestartFeedFromTop()
                persistSessionReelsMode()
                saveSessionState(for: reelsMode)
                clearSavedPosition(for: reelsMode)
                ReelsSessionRAM.setString(nil, forKey: reelsPlaybackCheckpointKey(for: reelsMode))
                currentItemIsPlaying = false
                ReelsPlayerRegistry.pauseAll()
                NotificationCenter.default.post(name: .reelsTeardownAllPlayers, object: nil)
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
            criteriaDocument: reelsMode == .markers ? reelsMarkerCriteriaDocument : reelsCriteriaDocument,
            sortOption: selectedSortOption,
            onSortChange: { changeReelsSceneSortFromSheet($0) },
            onApply: { reelsApplySceneLiveFromSheet() },
            onReset: {
                reelsSetActiveSheetPresetSelection("")
                reelsClearActiveLiveChipsOnly()
                reelsCriteriaDocument.clear()
                reelsMarkerCriteriaDocument.clear()
                switch reelsMode {
                case .scenes:
                    applySettings(sortBy: selectedSortOption, sceneFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearSceneFilter: true, sceneLiveRefresh: true)
                case .markers:
                    applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearMarkerFilter: true, sceneLiveRefresh: true)
                case .previews:
                    applySettings(previewSortBy: selectedSortOption, previewFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearPreviewFilter: true, sceneLiveRefresh: true)
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
        .environmentObject(viewModel)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .presentationBackgroundInteraction(.disabled)
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
            .alert(reelsDeleteConfirmationTitle, isPresented: $showDeleteConfirmation, presenting: reelsItemToDelete) { item in
                Button("Delete", role: .destructive) { reelsDeleteItem(item) }
                Button("Cancel", role: .cancel) { reelsItemToDelete = nil }
            } message: { item in
                Text(reelsDeleteConfirmationMessage(for: item))
            }
    }

    // MARK: - Overlay delete button

    private var reelsDeleteConfirmationTitle: String {
        if case .clip = reelsItemToDelete { return "Delete image?" }
        return "Delete scene?"
    }

    private func reelsDeleteConfirmationMessage(for item: ReelItemData) -> String {
        switch item {
        case .clip:
            return "The image is removed from the server. This cannot be undone."
        case .scene, .preview:
            return "The scene and its files are removed from the server. This cannot be undone."
        case .marker:
            return ""
        }
    }

    /// Markers point at a scene shared with other markers; deleting from the marker feed is not offered.
    private func reelsItemSupportsDelete(_ item: ReelItemData) -> Bool {
        switch item {
        case .scene, .preview, .clip: return true
        case .marker: return false
        }
    }

    /// Same flow as the fullscreen image viewer: resolve the successor now, move the
    /// `scrollPosition` binding before the request, prune the array on success.
    private func reelsDeleteItem(_ item: ReelItemData) {
        reelsItemToDelete = nil
        HapticManager.light()

        let items = currentReelItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        let successorId: String? = {
            if currentIndex + 1 < items.count { return items[currentIndex + 1].id }
            if currentIndex > 0 { return items[currentIndex - 1].id }
            return nil
        }()

        // Move before deleting: the binding must never point at an id that has left the array.
        if let successorId {
            isUserScrollingReels = false
            currentVisibleSceneId = successorId
        }

        let finish: (Bool, String, @escaping () -> Void) -> Void = { success, label, prune in
            DispatchQueue.main.async {
                guard success else {
                    self.currentVisibleSceneId = item.id
                    ToastManager.shared.show("Failed to delete \(label)", icon: "exclamationmark.triangle", style: .error)
                    return
                }
                ToastManager.shared.show("\(label.capitalized) deleted", icon: "trash", style: .success)
                prune()
                if successorId == nil {
                    self.currentVisibleSceneId = nil
                }
            }
        }

        switch item {
        case .scene(let scene), .preview(let scene):
            viewModel.deleteSceneWithFiles(scene: scene) { success in
                finish(success, "scene") {
                    self.viewModel.scenes.removeAll { $0.id == scene.id }
                    self.viewModel.previews.removeAll { $0.id == scene.id }
                }
            }
        case .clip(let clip):
            viewModel.deleteImage(imageId: clip.id) { success in
                finish(success, "image") {
                    self.viewModel.clips.removeAll { $0.id == clip.id }
                }
            }
        case .marker:
            break
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
            .onChange(of: reelsPicsFilters.selectedSortOption) { _, _ in
                guard reelsMode == .pics else { return }
                saveSessionState(for: .pics)
            }
            .onChange(of: reelsPicsFilters.selectedFilter?.id) { _, newId in
                guard reelsMode == .pics else { return }
                // User picked a saved filter — allow Settings defaults again later.
                if newId != nil {
                    reelsPicsFilters.suppressSettingsDefaultFilter = false
                }
                saveSessionState(for: .pics)
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
            .onChange(of: firstSceneId) { _, new in
                guard reelsMode == .scenes, new != nil else { return }
                continuePagedRestoreIfNeeded()
                activateFeed()
            }
            .onChange(of: firstMarkerId) { _, new in
                guard reelsMode == .markers, new != nil else { return }
                continuePagedRestoreIfNeeded()
                activateFeed()
            }
            .onChange(of: firstClipId) { _, new in
                guard reelsMode == .clips, new != nil else { return }
                continuePagedRestoreIfNeeded()
                activateFeed()
            }
            .onChange(of: firstPreviewId) { _, new in
                guard reelsMode == .previews, new != nil else { return }
                continuePagedRestoreIfNeeded()
                activateFeed()
            }
            .onChange(of: isFeedLoading) { wasLoading, nowLoading in
                if wasLoading && !nowLoading {
                    continuePagedRestoreIfNeeded()
                    activateFeed()
                }
            }
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
            .sheet(item: $tagEditorTarget) { target in
                // Lists patch themselves through the *TagsUpdated broadcasts.
                AddTagsSheet(target: target, viewModel: viewModel) { _ in }
            }
            .onChange(of: tagEditorTarget?.id) { _, newValue in
                // Nobody wants a clip looping with sound behind the tag picker.
                if newValue != nil {
                    wasPlayingBeforeTagEditor = currentItemIsPlaying
                    currentItemIsPlaying = false
                    ReelsPlayerRegistry.pauseAll()
                    NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
                } else if wasPlayingBeforeTagEditor {
                    wasPlayingBeforeTagEditor = false
                    currentItemIsPlaying = true
                    ReelsPlayerRegistry.resumePlayback()
                    playTrigger += 1
                }
            }
    }

    private var reelsClipFilterSortSheet: some View {
        ImagesCatalogFilterSortSheet(
            serverFilters: reelsClipImageFilters.sortedServerImageFilters(viewModel: viewModel),
            localPresets: reelsClipImageFilters.localCatalogPresets,
            selectedPresetRowId: $reelsClipImageFilters.catalogPresetRowSelection,
            criteriaDocument: reelsClipImageFilters.criteriaDocument,
            filterMenuTitleFallback: reelsClipImageFilters.selectedFilter?.name,
            showMediaTypeFilter: reelsClipImageFilters.showImageMediaTypeFilter,
            sortOption: reelsClipImageFilters.selectedSortOption,
            onSortChange: { new in
                reelsClipImageFilters.changeSortOption(to: new, viewModel: viewModel)
                refetchReelsClipsFromModel(viewModel)
            },
            liveMediaKind: $reelsClipImageFilters.liveFilterMediaKind,
            onApply: {
                refetchReelsClipsFromModel(viewModel)
            },
            onReset: {
                reelsClipImageFilters.catalogPresetRowSelection = ""
                reelsClipImageFilters.selectedFilter = nil
                reelsClipImageFilters.clearLiveChipsOnly()
                reelsClearActiveLiveChipsOnly()
                reelsClipImageFilters.criteriaDocument.clear()
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
        .presentationBackgroundInteraction(.disabled)
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
        ZStack {
            StashyThemeFill(role: .app)
                .ignoresSafeArea()

            if reelsMode == .pics {
                if isInitialized {
                    ImagesView(
                        catalogBrowserViewModel: reelsPicsViewModel,
                        forceOneColumnFeed: true,
                        feedsEmbedded: true,
                        sharedImageListFilters: reelsPicsFilters
                    )
                } else {
                    StandardLoadingView(message: "Loading feeds...")
                }
            } else if showsBlockingFeedLoad {
                loadingStateView
            } else if showsFeedConnectionError {
                errorStateView
            } else if isListEmpty {
                emptyStateView
            } else {
                reelsListView()
                    .ignoresSafeArea(reelsPremiumContentSafeAreaRegions)
            }
        }
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
        guard let tabId = notification.userInfo?["tab"] as? String else { return }
        if tabId == AppTab.images.rawValue, reelsMode == .pics {
            let defaultId = TabManager.shared.getDefaultFilterId(for: .images)
            reelsPicsFilters.selectedFilter = defaultId.flatMap { viewModel.savedFilters[$0] }
            saveSessionState(for: .pics)
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
            return
        }
        if tabId == AppTab.reels.rawValue {
            switch reelsMode {
            case .scenes:
                let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(sortBy: selectedSortOption, sceneFilter: newFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
            case .markers:
                let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: newFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
            case .clips:
                let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                reelsClipImageFilters.selectedFilter = newFilter
                applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: newFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
            case .previews:
                let defaultId = TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                selectedPreviewFilter = newFilter
                applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, previewFilter: newFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
            case .pics:
                break
            }
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
        }
    }

    private func handleSavedFiltersChanged(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        // Deep-link already chose filter / overlay / fetch. A late saved-filters
        // arrival must not inject Settings defaults and reset that timeline.
        if didConsumeDeepLink {
            reelsSyncFilterSheetPresetRow()
            return
        }

        let isCurrentlyEmpty: Bool = {
            switch reelsMode {
            case .scenes: return viewModel.scenes.isEmpty
            case .markers: return viewModel.sceneMarkers.isEmpty
            case .clips: return viewModel.clips.isEmpty
            case .previews: return viewModel.previews.isEmpty
            case .pics: return false
            }
        }()

        let noSavedSceneStyleFilter: Bool = {
            switch reelsMode {
            case .clips: return reelsClipImageFilters.selectedFilter == nil
            case .scenes: return selectedFilter == nil
            case .markers: return selectedMarkerFilter == nil
            case .previews: return selectedPreviewFilter == nil
            case .pics: return reelsPicsFilters.selectedFilter == nil
            }
        }()
        let noLiveChipCriteria: Bool = {
            switch reelsMode {
            case .clips:
                return !reelsClipImageFilters.catalogFilterSortFABActive
            case .scenes:
                return !reelsSceneLiveChips.isLiveFilterActive && reelsCriteriaDocument.isEmpty
            case .markers:
                return !reelsMarkerLiveChips.isLiveFilterActive && reelsMarkerCriteriaDocument.isEmpty
            case .previews:
                return !reelsPreviewLiveChips.isLiveFilterActive && reelsCriteriaDocument.isEmpty
            case .pics:
                return !reelsPicsFilters.catalogFilterSortFABActive
            }
        }()
        let noCriteriaSet = noSavedSceneStyleFilter && noLiveChipCriteria && selectedPerformer == nil && selectedTags.isEmpty && selectedStudio == nil

        if noCriteriaSet && !newValue.isEmpty {
            let defaultId: String? = {
                switch reelsMode {
                case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                case .pics: return TabManager.shared.getDefaultFilterId(for: .images)
                }
            }()

            // Only kick an automatic fetch when the timeline is still empty (cold start). If the user is
            // already browsing with "no saved filter", a later `fetchSavedFilters` (e.g. opening the sheet)
            // must not inject the default filter and reset the feed.
            if isCurrentlyEmpty {
                if let defId = defaultId, let filter = newValue[defId] {
                    switch reelsMode {
                    case .scenes:
                        applySettings(sortBy: selectedSortOption, sceneFilter: filter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .markers:
                        applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: filter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .clips:
                        reelsClipImageFilters.selectedFilter = filter
                        applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .previews:
                        selectedPreviewFilter = filter
                        applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, previewFilter: filter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .pics:
                        reelsPicsFilters.selectedFilter = filter
                        saveSessionState(for: .pics)
                        reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
                    }
                } else {
                    let currentModeType = reelsMode.toModeType
                    let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)

                    switch reelsMode {
                    case .scenes:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(sortBy: savedSort, sceneFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearSceneFilter: true)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(markerSortBy: savedSort, markerFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearMarkerFilter: true)
                    case .clips:
                        let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(clipSortBy: savedSort, clipFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearClipFilter: true)
                    case .previews:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        applySettings(previewSortBy: savedSort, previewFilter: nil, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, clearPreviewFilter: true)
                    case .pics:
                        if let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") {
                            reelsPicsFilters.selectedSortOption = savedSort
                        }
                        reelsPicsFilters.selectedFilter = nil
                        saveSessionState(for: .pics)
                    }
                }
                reelsSyncFilterSheetPresetAndLiveChips(savedFilters: newValue)
            } else {
                reelsSyncFilterSheetPresetRow()
            }
        }
    }

    /// Pause players while staying on Feeds (nav push or `reelsTabID` remount). Does **not** suspend
    /// the registry — that would race a remounted instance's autoplay.
    private func reelsPausePlaybackForLocalTeardown() {
        saveCurrentPositionIfPossible(for: reelsMode)
        savePlaybackCheckpoint(for: reelsMode)
        currentItemIsPlaying = false
        ReelsPlayerRegistry.pauseAll()
        NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
        HandyManager.shared.stop()
        ButtplugManager.shared.stopAllDevices()
        LoveSpouseManager.shared.stop()
    }

    /// Pausiert alle registrierten Reels-Engines, beendet Zubehör-Sync und gibt die Audio-Session frei.
    /// Wichtig beim **Haupttab-Wechsel weg von Feeds**: SwiftUI-`TabView` ruft hier oft kein `onDisappear` auf.
    private func reelsStopPlaybackAndAccessories() {
        reelsPausePlaybackForLocalTeardown()
        ReelsPlayerRegistry.suspendPlayback()
        UIApplication.shared.isIdleTimerDisabled = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLog.debug("🎬 Reels: Audio deactivation error: \(error)")
        }
    }

    /// Scenes / Markers / Clips / Previews take the playback session. Pics must not —
    /// muted 1-row autoplay mixes with other audio instead of ducking it.
    private func applyReelsAudioSession(for mode: ReelsMode) {
        if mode == .pics {
            applyAmbientMixingAudioSession()
        } else {
            applyPlaybackAudioSession()
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
        applyReelsAudioSession(for: reelsMode)

        // Pics uses ImagesView muted autoplay and must not resume reel players / steal audio.
        if reelsMode == .pics { return }

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

    /// Clears warm lists / restore targets so a deep-link always rebuilds the timeline.
    private func prepareFreshFeedForDeepLink() {
        markRestartFeedFromTop()
        pendingRestoreId = nil
        currentVisibleSceneId = nil
        shouldScrollToTopAfterCriterionChange = true
        viewModel.clearReelsCriterionFrozenSnapshots()
        viewModel.forgetAllReelsFeedSignatures()
        viewModel.scenes = []
        viewModel.sceneMarkers = []
        viewModel.clips = []
        viewModel.previews = []
        reelsPicsViewModel.allImages = []
        for mode in [ReelsMode.scenes, .markers, .clips, .previews, .pics] {
            clearSavedPosition(for: mode)
        }
    }

    /// Applies a Feeds deep link. Prefer the remount-captured snapshot; if this instance was
    /// created earlier in the session (TabView kept it alive), fall back to the live coordinator.
    @discardableResult
    private func applyPendingReelsNavigationFromCoordinator() -> Bool {
        let link = !deepLink.isEmpty ? deepLink : coordinator.reelsDeepLink
        guard !didConsumeDeepLink, !link.isEmpty else { return false }
        didConsumeDeepLink = true
        // Drop coordinator copy so icon remounts / later appears cannot re-apply stale criteria.
        coordinator.clearReelsDeepLink()
        coordinator.suppressNextFeedsIconRemount = false
        prepareFreshFeedForDeepLink()

        let initialPerformer = link.performer
        let initialTags = link.tags
        let initialStudio = link.studio
        let targetModeStr = link.mode
        let picsPerformer = link.picsPerformer

        let intendedMode: ReelsMode? = {
            if let modeStr = targetModeStr {
                if modeStr == "Pics" { return .pics }
                return ReelsMode(rawValue: modeStr)
            }
            if link.clipFilter != nil { return .clips }
            if link.sceneFilter != nil { return .scenes }
            return nil
        }()
        if let intendedMode, reelsMode != intendedMode {
            skipNextReelsModeSessionRestore = true
        }

        if let modeStr = targetModeStr {
            if modeStr == "Pics" {
                reelsMode = .pics
            } else if let mode = ReelsMode(rawValue: modeStr) {
                reelsMode = mode
            }
        }

        // Legacy: Performer detail → Pics (Images 1/row)
        if let performer = picsPerformer {
            applyReelsPicsNavigation(performer: performer.toScenePerformer(), tags: [])
            return true
        }

        // After applying target mode: if we land on Pics (first enabled mode or explicit),
        // apply performer/tags there — do not drop them (old path skipped refetch / cleared tags).
        if reelsMode == .pics, initialPerformer != nil || !initialTags.isEmpty || initialStudio != nil {
            applyReelsPicsNavigation(performer: initialPerformer, tags: initialTags, studio: initialStudio)
            return true
        }

        // Dashboard image channel: Clips mode scoped to a saved image filter.
        if let clipFilter = link.clipFilter {
            reelsMode = .clips
            let sort = StashDBViewModel.ImageSortOption(rawValue: link.clipSort ?? "")
                ?? StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .clips) ?? "")
                ?? .random
            reelsClipImageFilters.clearLiveChipsOnly()
            reelsClipImageFilters.selectedFilter = clipFilter
            reelsClipImageFilters.syncLiveChipsFromSelectedFilter(viewModel: viewModel)
            applySettings(clipSortBy: sort, clipFilter: clipFilter, mode: .clips)
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
            isInitialized = true
            return true
        }

        // Dashboard channel: Scenes mode scoped to the channel's saved filter. Map that
        // filter's own live chips (tags etc.) — do not keep leftover chips from another session.
        if let channelFilter = link.sceneFilter {
            reelsMode = .scenes
            let sort = StashDBViewModel.SceneSortOption(rawValue: link.sceneSort ?? "")
                ?? StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .scenes) ?? "")
                ?? .random
            selectedSortOption = sort
            reelsClearActiveLiveChipsOnly()
            selectedFilter = channelFilter
            if let meta = channelFilter.stashyScenePresetMetadata, !meta.liveFragment.isEmpty {
                reelsMapLiveFragmentToActiveChips(meta.liveFragment)
            } else if let raw = channelFilter.filterDict {
                reelsMapLiveFragmentToActiveChips(raw)
            }
            applySettings(sortBy: sort, sceneFilter: channelFilter, mode: .scenes)
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
            isInitialized = true
            return true
        }

        if initialPerformer != nil || !initialTags.isEmpty || initialStudio != nil {
            // Before picking the mode: drop everything the session was still carrying, so only
            // the handed performer / tags / studio plus the mode's default sort survive.
            reelsClearSessionFiltersForDeepLink()
            let targetMode: ReelsMode = {
                if let modeStr = targetModeStr {
                    if modeStr == "Pics" { return .pics }
                    if let mode = ReelsMode(rawValue: modeStr) { return mode }
                }
                return firstEnabledReelsMode
            }()
            if reelsMode != targetMode {
                skipNextReelsModeSessionRestore = true
            }
            reelsMode = targetMode

            // Every Feeds view starts from its Settings default filter; the handed performer /
            // tag / studio narrows it. Only the *session's* filter is dropped (cleared above).
            switch targetMode {
            case .scenes:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .scenes)
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                let f = TabManager.shared.getDefaultFilterId(for: .reels).flatMap { viewModel.savedFilters[$0] }
                selectedFilter = f
                applySettings(sortBy: savedSort, sceneFilter: f, performer: initialPerformer, tags: initialTags, studio: initialStudio, mode: .scenes, clearSceneFilter: f == nil)
            case .markers:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .markers)
                let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                let f = TabManager.shared.getDefaultMarkerFilterId(for: .reels).flatMap { viewModel.savedFilters[$0] }
                selectedMarkerFilter = f
                applySettings(markerSortBy: savedSort, markerFilter: f, performer: initialPerformer, tags: initialTags, studio: initialStudio, mode: .markers, clearMarkerFilter: f == nil)
            case .previews:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .previews)
                let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                let f = TabManager.shared.getDefaultPreviewFilterId(for: .reels).flatMap { viewModel.savedFilters[$0] }
                selectedPreviewFilter = f
                applySettings(previewSortBy: savedSort, previewFilter: f, performer: initialPerformer, tags: initialTags, studio: initialStudio, mode: .previews, clearPreviewFilter: f == nil)
            case .clips:
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .clips)
                let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                let f = TabManager.shared.getDefaultClipFilterId(for: .reels).flatMap { viewModel.savedFilters[$0] }
                reelsClipImageFilters.selectedFilter = f
                applySettings(clipSortBy: savedSort, clipFilter: f, performer: initialPerformer, tags: initialTags, studio: initialStudio, mode: .clips, clearClipFilter: f == nil)
            case .pics:
                applyReelsPicsNavigation(performer: initialPerformer, tags: initialTags, studio: initialStudio)
                return true
            }
            reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
            isInitialized = true
            return true
        }

        if targetModeStr != nil {
            if reelsMode == .pics {
                // Mode-only handoff: normal Pics bootstrap (with default filter). Criterion
                // deep-links are handled above via `applyReelsPicsNavigation`.
                if selectedPerformer != nil || !selectedTags.isEmpty || selectedStudio != nil {
                    applyReelsPicsNavigation(performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                } else {
                    bootstrapReelsPicsFiltersIfNeeded()
                    reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
                    isInitialized = true
                }
            } else {
                isInitialized = true
            }
            return true
        }

        return false
    }

    /// Apply performer/tag/studio criteria to Feeds → Pics and fetch immediately.
    /// Deep-links drop the session's filter and start from the Settings default, like every
    /// other Feeds view; the handed criteria narrow it.
    private func applyReelsPicsNavigation(performer: ScenePerformer?, tags: [Tag], studio: SceneStudio? = nil) {
        reelsMode = .pics
        selectedPerformer = performer
        selectedTags = tags
        selectedStudio = studio

        if let raw = sessionSortRaw(for: .pics),
           let opt = StashDBViewModel.ImageSortOption(rawValue: raw) {
            reelsPicsFilters.selectedSortOption = opt
        } else if let def = TabManager.shared.getReelsDefaultSort(for: .pics),
                  let opt = StashDBViewModel.ImageSortOption(rawValue: def) {
            reelsPicsFilters.selectedSortOption = opt
        }

        // Drop the session's filter, then start from the Settings default like every other
        // Feeds view — the handed criteria narrow it rather than replace it.
        reelsPicsFilters.suppressSettingsDefaultFilter = false
        reelsPicsFilters.catalogPresetRowSelection = ""
        reelsPicsFilters.clearLiveChipsOnly()
        reelsPicsFilters.selectedFilter = TabManager.shared.getDefaultFilterId(for: .images)
            .flatMap { viewModel.savedFilters[$0] ?? reelsPicsViewModel.savedFilters[$0] }
        reelsPicsViewModel.currentImageFilter = nil
        reelsPicsViewModel.imagePerformerIdFilter = performer?.id
        reelsPicsFilters.liveFilterTagIds = tags.map(\.id)
        reelsPicsFilters.liveFilterStudioIds = studio.map { [$0.id] } ?? []
        saveSessionState(for: .pics)

        reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
        isInitialized = true
    }

    /// Session / Settings defaults for embedded Images 1/row (Pics).
    private func bootstrapReelsPicsFiltersIfNeeded() {
        // The Settings default applies to a criterion hand-off too — it is the baseline every
        // Feeds view starts from; the performer / tag / studio only narrows it further.
        reelsPicsFilters.suppressSettingsDefaultFilter = false
        if let fid = sessionFilterId(for: .pics) {
            reelsPicsFilters.selectedFilter = viewModel.savedFilters[fid] ?? reelsPicsViewModel.savedFilters[fid]
        } else if let defId = TabManager.shared.getDefaultFilterId(for: .images) {
            reelsPicsFilters.selectedFilter = viewModel.savedFilters[defId] ?? reelsPicsViewModel.savedFilters[defId]
        }
        if let raw = sessionSortRaw(for: .pics),
           let opt = StashDBViewModel.ImageSortOption(rawValue: raw) {
            reelsPicsFilters.selectedSortOption = opt
        } else if let def = TabManager.shared.getReelsDefaultSort(for: .pics),
                  let opt = StashDBViewModel.ImageSortOption(rawValue: def) {
            reelsPicsFilters.selectedSortOption = opt
        }
        reelsPicsViewModel.imagePerformerIdFilter = selectedPerformer?.id
        reelsPicsFilters.liveFilterTagIds = selectedTags.map(\.id)
        reelsPicsFilters.liveFilterStudioIds = selectedStudio.map { [$0.id] } ?? []
        saveSessionState(for: .pics)
    }

    private func handleOnAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
        ReelsPlayerRegistry.resumePlayback()
        reelsClipImageFilters.externalRefetchClips = { vm in
            refetchReelsClipsFromModel(vm)
        }

        ReelsSessionRAM.clearLegacyUserDefaultsIfNeeded()
        
        applyReelsAudioSession(for: reelsMode)
        if let kind = reelsFeedKind(for: reelsMode) {
            viewModel.setActiveReelsFeed(kind)
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
            // Deep-link path runs its own fetch cycle — release the bootstrap guard
            // so the follow-up onAppear can complete normal initialization.
            isBootstrapping = false
            return
        }

        restoreSessionCriteria()
        let restoredCriterionOverlay = hasActiveCriterionOverlay

        // After the first full setup, re-onAppear must NOT re-run session restore /
        // autoSelectFirstItem (that reset scroll). Just resume autoplay + seek.
        if isInitialized {
            reelsResumePlaybackAfterReturn()
            return
        }

        // A bootstrap pass is already running (multi-onAppear remount) — let it finish
        // instead of issuing a duplicate initial fetch that resets the feed mid-mount.
        guard !isBootstrapping else { return }
        isBootstrapping = true

        let restartFromTop = shouldRestartFeedFromTop

        if !restartFromTop {
            restoreSessionRandomSeedIfAvailable()
        }

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
        case .pics:
            bootstrapReelsPicsFiltersIfNeeded()
        }

        // Tab-bar icon → start of feed. Normal appear → restore last scroll position.
        if restartFromTop {
            pendingRestoreId = nil
            currentVisibleSceneId = nil
            clearSavedPosition(for: reelsMode)
            ReelsSessionRAM.setString(nil, forKey: reelsPlaybackCheckpointKey(for: reelsMode))
            if let kind = seedKind(for: reelsMode) {
                viewModel.refreshRandomSeed(for: kind)
                persistSessionRandomSeed(for: reelsMode)
            }
        } else {
            // IMPORTANT: Restore sort/filter BEFORE scroll position (Clips Created sorting).
            restorePositionIfAvailable(for: reelsMode, forceIfPrefixMismatch: false)
            beginPagedRestoreIfNeeded()
            autoSelectFirstItem()
        }
        
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
                case .pics: return false
                }
            }()

            if isCurrentlyEmpty && !restartFromTop && !restoredCriterionOverlay {
                // Priority 2: Try to apply default filter
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                    case .pics: return TabManager.shared.getDefaultFilterId(for: .images)
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
                        if initialSceneFilter == nil, let defId = defaultId, !restoredCriterionOverlay {
                            initialSceneFilter = viewModel.savedFilters[defId]
                        }
                    case .markers:
                        if initialMarkerFilter == nil, let defId = defaultId, !restoredCriterionOverlay {
                            initialMarkerFilter = viewModel.savedFilters[defId]
                        }
                    default:
                        if initialSceneFilter == nil, let defId = defaultId, !restoredCriterionOverlay {
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
                        applySettings(sortBy: savedSort, sceneFilter: initialSceneFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedMarkerSortOption = savedSort
                        applySettings(markerSortBy: savedSort, markerFilter: initialMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .clips:
                        // Fetched via `ensureReelsClipsLoaded()` below (also covers warm remounts).
                        break
                    case .previews:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedSortOption = savedSort
                        var prevFilter = selectedPreviewFilter
                        if prevFilter == nil, let defId = defaultId, !restoredCriterionOverlay {
                            prevFilter = viewModel.savedFilters[defId]
                        }
                        selectedPreviewFilter = prevFilter
                        applySettings(previewSortBy: savedSort, previewFilter: prevFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
                    case .pics:
                        bootstrapReelsPicsFiltersIfNeeded()
                    }
                    reelsSyncFilterSheetPresetAndLiveChips(savedFilters: viewModel.savedFilters)
                }
            } else if reelsMode == .pics, !restartFromTop {
                bootstrapReelsPicsFiltersIfNeeded()
                // Remount recreates the Pics VM — refetch when the warm scene VM has no pics list.
                if reelsPicsViewModel.allImages.isEmpty {
                    reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
                }
            }

        if restartFromTop {
            refetchCurrentReelsModeFromTop()
        } else if restoredCriterionOverlay {
            syncFeedToCriterionOverlay()
        } else if reelsMode == .clips, !isWarmFeed(for: .clips) {
            ensureReelsClipsLoaded(rerollRandom: false)
        }

        persistSessionReelsMode()
        isInitialized = true
        clearRestartFeedFromTopFlag()
        if reelsMode != .pics, !isListEmpty {
            activateFeed()
        }
    }

    /// Tab-bar reselect: page-1 refetch for the active mode, first item selected when data arrives.
    private func refetchCurrentReelsModeFromTop() {
        shouldScrollToTopAfterCriterionChange = true
        pendingRestoreId = nil
        currentVisibleSceneId = nil
        switch reelsMode {
        case .scenes:
            applySettings(
                sortBy: selectedSortOption,
                sceneFilter: selectedFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                mode: .scenes,
                rerollRandom: true
            )
        case .markers:
            applySettings(
                markerSortBy: selectedMarkerSortOption,
                markerFilter: selectedMarkerFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                mode: .markers,
                rerollRandom: true
            )
        case .clips:
            ensureReelsClipsLoaded(rerollRandom: true)
        case .previews:
            applySettings(
                previewSortBy: selectedSortOption,
                previewFilter: selectedPreviewFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                studio: selectedStudio,
                mode: .previews,
                rerollRandom: true
            )
        case .pics:
            bootstrapReelsPicsFiltersIfNeeded()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
        }
    }

    /// Cold / remount Clips: apply session-or-default sort/filter and fetch.
    private func ensureReelsClipsLoaded(rerollRandom: Bool = false) {
        let sortRaw = sessionSortRaw(for: .clips) ?? TabManager.shared.getReelsDefaultSort(for: .clips) ?? ""
        let sort = StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? reelsClipImageFilters.selectedSortOption
        reelsClipImageFilters.selectedSortOption = sort
        let fid = sessionFilterId(for: .clips) ?? TabManager.shared.getDefaultClipFilterId(for: .reels)
        reelsClipImageFilters.selectedFilter = fid.flatMap { viewModel.savedFilters[$0] }
        if !rerollRandom, isWarmFeed(for: .clips) {
            activateFeed()
            return
        }
        applySettings(
            clipSortBy: sort,
            clipFilter: reelsClipImageFilters.selectedFilter,
            performer: selectedPerformer,
            tags: selectedTags,
            studio: selectedStudio,
            mode: .clips,
            rerollRandom: rerollRandom
        )
    }

    private func handleModeChange(from oldValue: ReelsMode, to newValue: ReelsMode) {
        // When switching sub-tabs always pause immediately. Autoplay for the new *video*
        // mode is restored below; Pics embeds ImagesView and must not keep clip audio.
        persistSessionReelsMode(newValue)
        currentItemIsPlaying = false
        ReelsPlayerRegistry.pauseAll()
        NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
        isMediaZoomed = false
        isUserScrollingReels = false
        feedActivationGeneration += 1

        if let kind = reelsFeedKind(for: newValue) {
            viewModel.abandonInactiveReelsFeeds(keeping: kind)
        } else {
            viewModel.setActiveReelsFeed(nil)
        }

        if skipNextReelsModeSessionRestore {
            skipNextReelsModeSessionRestore = false
            applyReelsAudioSession(for: newValue)
            if newValue == .pics {
                NotificationCenter.default.post(name: .reelsTeardownAllPlayers, object: nil)
                currentVisibleSceneId = nil
            } else if !isListEmpty {
                activateFeed()
            }
            return
        }

        // Persist old mode position before clearing the active id (Pics teardown).
        saveCurrentPositionIfPossible(for: oldValue)

        applyReelsAudioSession(for: newValue)

        if newValue == .pics {
            // Active row's `onDisappear` skips `cleanupPlayer` while still "active", so force
            // teardown and clear identity — otherwise Clips keep playing under Pics.
            NotificationCenter.default.post(name: .reelsTeardownAllPlayers, object: nil)
            currentVisibleSceneId = nil
        }

        restorePositionIfAvailable(for: newValue, forceIfPrefixMismatch: true)

        // An id from the old feed must not survive into the new one: `.scrollPosition(id:)`
        // stalls on a target that is not in the list, which is the black first item that
        // only recovers once the user scrolls. `autoSelectFirstItem` picks the new feed's
        // first item as soon as its data is in.
        if let expected = expectedPrefix(for: newValue),
           let current = currentVisibleSceneId,
           !current.hasPrefix(expected + "-") {
            currentVisibleSceneId = nil
        }

        beginPagedRestoreIfNeeded()

        // Restore session sort/filter (prefer session over defaults)
        switch newValue {
        case .scenes:
            let sortRaw = sessionSortRaw(for: .scenes) ?? TabManager.shared.getReelsDefaultSort(for: .scenes) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
            let fid = sessionFilterId(for: .scenes) ?? defaultId
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedFilter = f
        case .markers:
            let sortRaw = sessionSortRaw(for: .markers) ?? TabManager.shared.getReelsDefaultSort(for: .markers) ?? ""
            selectedMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: sortRaw) ?? selectedMarkerSortOption
            let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels)
            let fid = sessionFilterId(for: .markers) ?? defaultId
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedMarkerFilter = f
        case .clips:
            let sortRaw = sessionSortRaw(for: .clips) ?? TabManager.shared.getReelsDefaultSort(for: .clips) ?? ""
            reelsClipImageFilters.selectedSortOption = StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? reelsClipImageFilters.selectedSortOption
            let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels)
            let fid = sessionFilterId(for: .clips) ?? defaultId
            reelsClipImageFilters.selectedFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        case .previews:
            let sortRaw = sessionSortRaw(for: .previews) ?? TabManager.shared.getReelsDefaultSort(for: .previews) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let defaultId = TabManager.shared.getDefaultPreviewFilterId(for: .reels)
            let fid = sessionFilterId(for: .previews) ?? defaultId
            selectedPreviewFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        case .pics:
            bootstrapReelsPicsFiltersIfNeeded()
        }

        reelsSyncFilterSheetPresetAndLiveChips(for: newValue, savedFilters: viewModel.savedFilters)

        if newValue == .pics {
            bootstrapReelsPicsFiltersIfNeeded()
            reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
            return
        }

        if isWarmFeed(for: newValue) {
            pendingFeedActivation = true
            activateFeed()
            return
        }

        pendingFeedActivation = true

        switch newValue {
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, mode: newValue)
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, mode: newValue)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, mode: newValue)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio, mode: newValue)
        case .pics:
            break
        }
    }

    @ViewBuilder
    private var loadingStateView: some View {
        StandardLoadingView(message: "Loading feeds...")
    }

    @ViewBuilder
    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: emptyStateIcon,
            title: emptyStateTitle,
            buttonText: "Reload",
            onRetry: retryCurrentFeedFetch
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateIcon: String {
        switch reelsMode {
        case .scenes: return "film"
        case .markers: return "bookmark.fill"
        case .clips: return "photo.on.rectangle.angled"
        case .previews: return "play.rectangle"
        case .pics: return "camera.fill"
        }
    }

    private var emptyStateTitle: String {
        switch reelsMode {
        case .scenes: return "No scenes found"
        case .markers: return "No markers found"
        case .clips: return "No clips found"
        case .previews: return "No previews found"
        case .pics: return "No images found"
        }
    }

    private func retryCurrentFeedFetch() {
        switch reelsMode {
        case .scenes:
            applySettings(sortBy: selectedSortOption, sceneFilter: selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, markerFilter: selectedMarkerFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
        case .clips:
            applySettings(clipSortBy: reelsClipImageFilters.selectedSortOption, clipFilter: reelsClipImageFilters.selectedFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, studio: selectedStudio)
        case .pics: break
        }
    }

    @ViewBuilder
    private var errorStateView: some View {
        ConnectionErrorView(onRetry: retryCurrentFeedFetch)
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
                case .pics: break
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
                    if pendingFeedActivation {
                        requestFeedActivation()
                    }
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
                reelsListMounted = true
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

                if pendingFeedActivation || currentVisibleSceneId == nil {
                    requestFeedActivation()
                }
            }
            .onDisappear {
                reelsListMounted = false
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
                // The snap's scroll animation emits drift-suppressed phases that can
                // strand the scroll flag; reset it alongside the play intent.
                self.isUserScrollingReels = false
                self.currentItemIsPlaying = true
            }
        }
    }


    /// Match expanding-dock menu chrome.
    private var reelsTopChromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    /// Section chrome: mode pills · StashSync/Settings trailing.
    /// Criterion chips + O/Rating sit outside the bar (over the feed).
    @ViewBuilder
    private func reelsNavBar(currentItem: ReelItemData?) -> some View {
        // O-Counter / Rating live in the info overlay next to mute/play; this row only carries chips.
        let showsRateChrome = false
        let hasActiveCriterionChips = selectedPerformer != nil || !selectedTags.isEmpty || selectedStudio != nil
        let showsCriterionRow = hasActiveCriterionChips
        let prefersBottom = StashyChromePlacement.prefersBottom

        VStack(spacing: 0) {
            if prefersBottom, showsCriterionRow {
                reelsCriterionAndRateRow(
                    currentItem: currentItem,
                    hasActiveCriterionChips: hasActiveCriterionChips,
                    showsRateChrome: showsRateChrome
                )
            }

            StashySectionChromeBar {
                HStack(spacing: 8) {
                    reelsModeDock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        #if !os(tvOS)
                        ReelsAIMotionPill(pillHeight: reelsTopChromePillHeight,
                                          isPicsMode: reelsMode == .pics)
                        #endif
                        reelsFilterSortPill
                    }
                    .fixedSize()
                }
                .frame(minHeight: reelsTopChromePillHeight)
                .padding(.horizontal, StashyExpandingDock.edgePadding)
                .padding(.vertical, 6)
            }

            if !prefersBottom, showsCriterionRow {
                reelsCriterionAndRateRow(
                    currentItem: currentItem,
                    hasActiveCriterionChips: hasActiveCriterionChips,
                    showsRateChrome: showsRateChrome
                )
            }
        }
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }

    @ViewBuilder
    private func reelsCriterionAndRateRow(
        currentItem: ReelItemData?,
        hasActiveCriterionChips: Bool,
        showsRateChrome: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if hasActiveCriterionChips {
                reelsCriterionChipsRow
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if showsRateChrome {
                reelsRateChrome(currentItem: currentItem)
            }
        }
        .frame(minHeight: reelsTopChromePillHeight)
        .padding(.horizontal, StashyExpandingDock.edgePadding)
        .padding(.vertical, 6)
        .colorScheme(.dark)
    }

    @ViewBuilder
    private var reelsModeDock: some View {
        let enabledModes = tabManager.enabledReelsModes.map { ReelsMode(from: $0) }
        StashyExpandingDockBrowseStrip(
            items: enabledModes.map {
                StashyNavMenuItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
            },
            selectionID: reelsMode.rawValue,
            accessibilityLabel: "Feed",
            accessibilityHint: "Chooses which feed mode to show"
        ) { id in
            guard let mode = ReelsMode(rawValue: id), mode != reelsMode else { return }
            reelsMode = mode
        }
    }

    @ViewBuilder
    private var reelsCriterionChipsRow: some View {
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

                if let studio = selectedStudio {
                    Button(action: { applyClearStudioOnly() }) {
                        HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(studio.name)
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
    }

    /// "Name - Title" on one line, plain text. Name applies the performer filter.
    @ViewBuilder
    private func reelsNameTitleLine(item: ReelItemData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let performer = item.performers.first {
                Button(action: { applyPerformerFilter(performer) }) {
                    Text(performer.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel("Filter by \(performer.name)")
                Text("-")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            reelsTitleText(item: item)
        }
    }

    @ViewBuilder
    private func reelsTitleText(item: ReelItemData) -> some View {
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

    @ViewBuilder
    private func reelsRateChrome(currentItem: ReelItemData?) -> some View {
        let oCounter = currentItem?.oCounter ?? 0
        let rating100 = currentItem?.rating100 ?? 0
        let stars = max(0, min(5, Int(round(Double(rating100) / 20.0))))

        VStack(alignment: .trailing, spacing: 8) {
            Button {
                if let item = currentItem {
                    handleOCounterChange(item: item, newCount: oCounter + 1)
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: oCounter > 0 ? AppearanceManager.shared.oCounterIconFilled : AppearanceManager.shared.oCounterIcon)
                        .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        .foregroundColor(.white.opacity(oCounter > 0 ? 1.0 : StashyExpandingDock.inactiveIconOpacity))
                    Text("\(oCounter)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                }
                .opacity(currentItem == nil ? 0.35 : 1.0)
                .modifier(StashyChromePillStyle(height: StashyExpandingDock.stackedButtonSize, width: StashyExpandingDock.stackedButtonSize, hashtagColors: true))
            }
            .buttonStyle(.plain)
            .disabled(currentItem == nil)
            .accessibilityLabel("O-Counter")

            Group {
                if let item = currentItem {
                    Menu {
                        Button {
                            handleRatingChange(item: item, newRating: 0)
                        } label: {
                            HStack {
                                Text("Clear Rating")
                                if stars == 0 { Image(systemName: "checkmark") }
                            }
                        }
                        Divider()
                        ForEach(1...5, id: \.self) { s in
                            Button {
                                handleRatingChange(item: item, newRating: s * 20)
                            } label: {
                                HStack {
                                    Text(String(repeating: "★", count: s))
                                    if stars == s { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                .foregroundColor(.white.opacity(stars > 0 ? 1.0 : StashyExpandingDock.inactiveIconOpacity))
                            Text("\(stars)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        }
                        .modifier(StashyChromePillStyle(height: StashyExpandingDock.stackedButtonSize, width: StashyExpandingDock.stackedButtonSize, hashtagColors: true))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("0")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .modifier(StashyChromePillStyle(height: StashyExpandingDock.stackedButtonSize, width: StashyExpandingDock.stackedButtonSize, hashtagColors: true))
                }
            }
            .accessibilityLabel("Rating")
        }
        .fixedSize()
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
                // Own row above the performer line — the circles used to sit inside it and
                // squeezed the title/tag column on narrow screens.
                // Avatar · (name - title / tags) on the leading side, the control stack trailing.
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        if let performer = item.performers.first {
                            NavigationLink(
                                destination: PerformerDetailView(
                                    performer: performer.toPerformer(),
                                    // Clips (and Pics) are image feeds — open the Images tab, not Galleries/Scenes.
                                    initialTab: (reelsMode == .clips || reelsMode == .pics) ? .images : nil
                                )
                            ) {
                                performerThumbnail(performer)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(performer.name)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            reelsNameTitleLine(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let tags = item.tags
                            // Tag Suggestion (stashy+, off by default) shares this row, so
                            // it also has to exist for an untagged clip.
                            let showsTagRow = !tags.isEmpty
                                || appearanceManager.isEditModeEnabled
                                || AITagSuggestionManager.shared.isActive
                            Group {
                                if showsTagRow {
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
                                                .contextMenu {
                                                    let target = item.aiTagTarget
                                                    if appearanceManager.isEditModeEnabled,
                                                       tag.id != target.primaryTagId {
                                                        Button(role: .destructive) {
                                                            removeTag(tag, from: target)
                                                        } label: {
                                                            Label("Remove tag", systemImage: "trash")
                                                        }
                                                    }
                                                }
                                            }

                                            if appearanceManager.isEditModeEnabled {
                                                Button {
                                                    tagEditorTarget = item.aiTagTarget
                                                } label: {
                                                    // A bare symbol is shorter than a line
                                                    // of text, which made this pill smaller
                                                    // than the tag chips beside it.
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .frame(height: tagChipGlyphHeight)
                                                        .foregroundColor(.white.opacity(0.8))
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 3)
                                                        .background(Color.black.opacity(0.3))
                                                        .clipShape(Capsule())
                                                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Add tags")
                                            }

                                            // Tag Suggestion (stashy+, off by default).
                                            AITagSuggestionBar(target: item.aiTagTarget) { _ in }
                                        }
                                    }
                                    // Fresh identity per item: without it SwiftUI reuses the
                                    // row and the next clip inherits however far the previous
                                    // one was scrolled sideways.
                                    .id(item.id)
                                } else {
                                    Color.clear.opacity(0)
                                }
                            }
                            .frame(height: 22)
                        }
                    }
                    Spacer(minLength: 8)

                    // O-Counter · Rating · Mute · Play stacked on the trailing edge.
                    VStack(alignment: .trailing, spacing: 8) {
                        if reelsMode != .pics {
                            reelsRateChrome(currentItem: item)
                        }

                        if tabManager.reelsShowsDeleteButton, reelsItemSupportsDelete(item) {
                            ChromePillIconButton(systemImage: "trash", accessibilityLabel: "Delete") {
                                reelsItemToDelete = item
                                showDeleteConfirmation = true
                            }
                        }

                        ChromePillIconButton(
                            systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            enabled: isVideo,
                            accessibilityLabel: isMuted ? "Ton an" : "Stumm"
                        ) {
                            if isVideo {
                                isMuted.toggle()
                                ScenePlayerMute.persist(isMuted)
                            }
                        }

                        ChromePillIconButton(
                            systemImage: currentItemIsPlaying ? "pause.fill" : "play.fill",
                            enabled: isVideo,
                            accessibilityLabel: currentItemIsPlaying ? "Pause" : "Play"
                        ) {
                            if isVideo { currentItemIsPlaying.toggle() }
                        }
                    }
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
    private func performerThumbnail(_ performer: ScenePerformer, size: CGFloat = StashyExpandingDock.circleSize) -> some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable()
                                .scaledToFill()
                                // Head-and-shoulders shots lose the face to a centred crop.
                                .frame(width: size, height: size, alignment: .top)
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

    @ViewBuilder
    private var reelsFilterSortFAB: some View {
        reelsFilterSortPill
    }

    private var reelsQuickFilterMenuActive: Bool {
        switch reelsMode {
        case .pics:
            return reelsPicsFilters.selectedFilter != nil || !reelsPicsFilters.catalogPresetRowSelection.isEmpty
        case .clips:
            return reelsClipImageFilters.selectedFilter != nil || !reelsClipImageFilters.catalogPresetRowSelection.isEmpty
        default:
            return false
        }
    }

    @ViewBuilder
    private var reelsQuickFilterPill: some View {
        let filtersModel: DetailLinkedImagesFilterModel = {
            switch reelsMode {
            case .pics: return reelsPicsFilters
            default: return reelsClipImageFilters
            }
        }()
        let filterSourceVM: StashDBViewModel = {
            if reelsMode == .pics {
                return reelsPicsViewModel.savedFilters.isEmpty ? viewModel : reelsPicsViewModel
            }
            return viewModel
        }()
        let serverFilters = filtersModel.sortedServerImageFilters(viewModel: filterSourceVM)
        let selection = filtersModel.catalogPresetRowSelection
        Menu {
            Button {
                applyReelsQuickFilterSelection("")
            } label: {
                HStack {
                    Text("No Filter")
                    if selection.isEmpty && filtersModel.selectedFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !serverFilters.isEmpty {
                Section("Saved Filters") {
                    ForEach(serverFilters) { filter in
                        Button {
                            applyReelsQuickFilterSelection(ListLivePresetTag.serverRow(filter.id))
                        } label: {
                            HStack {
                                Text(filter.name)
                                if selection == ListLivePresetTag.serverRow(filter.id)
                                    || (selection.isEmpty && filtersModel.selectedFilter?.id == filter.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            if !filtersModel.localCatalogPresets.isEmpty {
                Section("Presets") {
                    ForEach(filtersModel.localCatalogPresets) { preset in
                        Button {
                            applyReelsQuickFilterSelection(ListLivePresetTag.localRow(preset.id))
                        } label: {
                            HStack {
                                Text(preset.name)
                                if selection == ListLivePresetTag.localRow(preset.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(
                    reelsQuickFilterMenuActive
                        ? appearanceManager.tintColor
                        : .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                )
                .frame(width: StashyExpandingDock.iconSize, height: StashyExpandingDock.iconSize)
                .modifier(StashyChromePillStyle(height: reelsTopChromePillHeight, iconOnly: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter")
        .accessibilityHint("Chooses a saved filter or preset")
    }

    private func applyReelsQuickFilterSelection(_ rowId: String) {
        switch reelsMode {
        case .pics:
            reelsPicsFilters.refreshLocalPresets()
            // Prefer Pics VM; fall back to Reels VM for saved-filter lookup if Pics hasn't loaded yet.
            let filterSource = reelsPicsViewModel.savedFilters.isEmpty ? viewModel : reelsPicsViewModel
            reelsPicsFilters.catalogPresetRowSelection = rowId
            reelsPicsFilters.handlePresetSelection(rowId, viewModel: filterSource)
            // Ensure fetch hits the embedded Images list VM.
            if filterSource !== reelsPicsViewModel {
                reelsPicsFilters.refetchImages(viewModel: reelsPicsViewModel, initial: true)
            }
            saveSessionState(for: .pics)
        case .clips:
            reelsClipImageFilters.refreshLocalPresets()
            reelsClipImageFilters.catalogPresetRowSelection = rowId
            reelsClipImageFilters.handlePresetSelection(rowId, viewModel: viewModel)
            refetchReelsClipsFromModel(viewModel)
        default:
            break
        }
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
            case .pics:
                reelsPicsFilters.refreshLocalPresets()
                reelsPicsFilters.prepareCatalogFilterSortSheetUI(viewModel: reelsPicsViewModel)
                reelsPicsFilters.showFilterSortSheet = true
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
}

#if !os(tvOS)
/// Isolated from ``ReelsViewBody`` so AI Motion intensity ticks cannot rebuild Feeds
/// (and restack the video layer over the filter-sheet menu).
private struct ReelsAIMotionPill: View {
    let pillHeight: CGFloat
    let isPicsMode: Bool
    @ObservedObject private var aetherRoute = ReelsAetherRouteState.shared
    @ObservedObject private var stashSyncManager = StashSyncManager.shared
    @ObservedObject private var handyManager = HandyManager.shared
    @ObservedObject private var buttplugManager = ButtplugManager.shared
    @ObservedObject private var loveSpouseManager = LoveSpouseManager.shared
    @ObservedObject private var plusManager = StashyPlusManager.shared
    @AppStorage("video_sync_enabled") private var isVideoSyncEnabled = false

    /// AI Motion works on the engine's item-backed routes; only the software route
    /// (nothing to analyse) hides the control.
    private var isBlockedByEngineRoute: Bool {
        aetherRoute.activeRowUsesSoftwareRoute
    }

    private var showsButton: Bool {
        plusManager.isUnlocked && isVideoSyncEnabled && !isPicsMode && !isBlockedByEngineRoute
    }

    private var isActive: Bool {
        stashSyncManager.isSyncing
            || handyManager.isStashSyncMode
            || buttplugManager.isStashSyncMode
            || loveSpouseManager.isStashSyncMode
    }

    var body: some View {
        if showsButton {
            Button {
                HapticManager.selection()
                stashSyncManager.setSyncing(!isActive)
            } label: {
                Image(systemName: isActive ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                    .foregroundColor(.white.opacity(isActive ? 1.0 : StashyExpandingDock.inactiveIconOpacity))
                    .frame(width: StashyExpandingDock.iconSize, height: StashyExpandingDock.iconSize)
                    .modifier(StashyChromePillStyle(height: pillHeight, iconOnly: true))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AIMotionCopy.name)
            .accessibilityValue(isActive ? "On" : "Off")
            .accessibilityHint("Toggles device sync for the current feed")
        }
    }
}
#endif

extension ReelsViewBody {
    @ViewBuilder
    private var modeMenu: some View {
        reelsModeDock
    }

}

// MARK: - Reel thumbnail-first video (hide AV layer until first frame is ready)

/// Steuert die Thumbnail→Video-Überblendung: `true`, sobald die Engine ihr **erstes Frame**
/// gemeldet hat (`onFirstFrame`). Vorher bleibt der schwarze Hintergrund stehen.
private final class ReelItemVideoSurfaceReadiness: ObservableObject {
    @Published private(set) var showsDecodedVideo: Bool = false

    /// Neue Session auf dieser Zeile: bis zum ersten Frame gilt wieder „kein Bild“.
    func reset() {
        showsDecodedVideo = false
    }

    /// Die Engine hat ein dekodiertes Frame gemeldet → Überblendung freigeben.
    func markFrameReady() {
        showsDecodedVideo = true
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

    /// Playback engine for this row — one per row, created lazily by `setupPlayer`.
    @State private var aetherEngine: AetherSceneEngine?
    /// Scrub preview stills for this row. Only the active row ever asks it for a frame,
    /// so only the active row can open a decode context.
    @StateObject private var scrubThumbs = ReelsScrubThumbnailProvider()
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
    /// Bumped on each `setupPlayer` / `cleanupPlayer` so an in-flight engine load
    /// cannot claim this row after the user has scrolled away.
    @State private var playerSetupGeneration: Int = 0
    /// The watchdog rebuilds a failed engine exactly once per row; after that the error stands.
    @State private var didRebuildAfterEngineError = false
    /// Set once the row has given up on playback — surfaced instead of a silent black cell.
    @State private var engineErrorMessage: String?
    @State private var showTagsOverlay = false
    @State private var playbackWatchdogTask: Task<Void, Never>?
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
    /// Skipped Reels must not hit `sceneAddPlay` / `sceneSaveActivity` (those set last_played).
    @State private var didCreditReelsWatch = false
    @State private var reelsWatchedSeconds: Double = 0
    @State private var heldReelsPlayDuration: Double = 0

    private static let reelsMinWatchSecondsBeforePlayCredit: Double = 30

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
            playbackErrorOverlay
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
                // fast scroll every flashed cell would otherwise open a decode session —
                // that saturates the device and the Stash server.
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
                            if aetherEngine == nil { setupPlayer() }
                            aetherPlayIfAllowed()
                        }
                    }
                }
                armPlaybackWatchdog()
            }
            .onDisappear {
                // LazyVStack can call `onDisappear` briefly while the row is still the centered reel; tearing down
                // the active engine there causes a second flash when paging settles.
                disarmPlaybackWatchdog()
                guard !isActive else { return }
                shutdownScrubPreview()
                cleanupPlayer()
                cancelAnimationAdvanceTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reelsPauseAllPlayers)) { _ in
                // Robust pause: when paging/scrolling starts, pause immediately even if
                // `currentVisibleSceneId` (and thus `isActive`) hasn't updated yet.
                aetherPause()
                syncPlaybackActivityPosition()
                playbackActivityTracker.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reelsTeardownAllPlayers)) { _ in
                cleanupPlayer()
                cancelAnimationAdvanceTimer()
            }
            .onChange(of: isMuted) { _, newValue in
                aetherSetMuted(newValue)
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    guard !isUserScrolling else { return }
                    if aetherEngine == nil {
                        setupPlayer()
                    } else {
                        refreshAetherCallbacks()
                    }
                    if isPlaying && !isRotating {
                        aetherPlayIfAllowed()
                    }
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                    // Deferred play: ensure player starts even if isPlaying binding
                    // hasn't propagated yet (e.g. after filter change resets state).
                    DispatchQueue.main.async {
                        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
                        if self.isActive && self.isPlaying && !self.isRotating && !self.isUserScrolling {
                            self.aetherPlayIfAllowed()
                        }
                    }
                    armPlaybackWatchdog()
                } else {
                    disarmPlaybackWatchdog()
                    if isUserScrolling {
                        aetherPause()
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
                    // `pause()` here (can flash the current video layer on touch / drag start).
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
                if aetherEngine == nil {
                    setupPlayer()
                } else {
                    refreshAetherCallbacks()
                }
                if isPlaying && !isRotating {
                    aetherPlayIfAllowed()
                }
                onInteraction()
                DispatchQueue.main.async {
                    guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
                    if self.isActive && self.isPlaying && !self.isRotating && !self.isUserScrolling {
                        self.aetherPlayIfAllowed()
                    }
                }
            }
            .onChange(of: tabManager.reelsContinuousPlay) { _, enabled in
                aetherSetLoops(continuousPlay: enabled)
                if item.isAnimated {
                    if enabled && isActive {
                        startAnimationAdvanceTimer()
                    } else {
                        cancelAnimationAdvanceTimer()
                    }
                }
            }
            .onChange(of: playTrigger) { _, _ in
                // Fired after `activateFeedAfterListSettles`. Must not require
                // `!isUserScrolling` — that flag is often still true from the
                // first paging layout when this fires.
                guard isActive else { return }
                if aetherEngine == nil { setupPlayer(forcePlay: true) }
                if !isRotating {
                    aetherPlayIfAllowed()
                }
                DispatchQueue.main.async {
                    guard self.isActive, !self.isRotating else { return }
                    self.aetherPlayIfAllowed()
                }
                armPlaybackWatchdog()
            }
            .onChange(of: isRotating) { _, newValue in
                if !newValue && isPlaybackActive && isPlaying {
                    aetherPlayIfAllowed()
                } else if newValue {
                    aetherPause()
                }
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
                        aetherPlayIfAllowed()
                        startPlaybackActivityTrackingIfNeeded()
                    }
                } else {
                    aetherPause()
                    syncPlaybackActivityPosition()
                    playbackActivityTracker.stop()
                }
            }
            .onReceive(scrubberState.$seekTarget) { target in
                guard let t = target else { return }
                // Scrubber lives outside the pager; allow seek whenever this row is the active item
                // (do not require `!isUserScrolling` — that flag can briefly be true during chrome drags).
                guard isActive, aetherEngine != nil else { return }
                requestScrubPreviewIfDragging(at: t)
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
                    aetherPause()
                } else {
                    endScrubPreview()
                    if isPlaying, !isUserScrolling {
                        aetherPlayIfAllowed()
                        onInteraction()
                    }
                }
            }
    }

    // MARK: - Scrub preview

    /// Decoding a still is worth it only while the finger is actually on the bar and this row
    /// owns playback. `seekTarget` is also set by checkpoint restore, hence the `seeking` gate.
    private func requestScrubPreviewIfDragging(at seconds: Double) {
        guard isActive, scrubberState.seeking, item.supportsScrubPreview else { return }
        // The bar lives outside the pager and reads the still off `ScrubberState`, so the
        // decode result is pushed there directly instead of through a view-level binding.
        let state = scrubberState
        scrubThumbs.onImage = { image in state.previewImage = image }
        scrubThumbs.request(at: seconds, aether: aetherEngine, url: item.videoURL)
    }

    private func endScrubPreview() {
        scrubThumbs.end()
        scrubberState.previewImage = nil
    }

    private func shutdownScrubPreview() {
        scrubThumbs.shutdown()
        if isActive { scrubberState.previewImage = nil }
    }


    @ViewBuilder
    private func applyStashSyncModifiers<V: View>(_ content: V) -> some View {
        content
            .modifier(makeStashSyncModifier())
    }

    private func makeStashSyncModifier() -> StashSyncManagerModifier {
        StashSyncManagerModifier(isActive: isActive, isPlaying: isPlaying, aetherEngine: aetherEngine)
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
                                    // Fill crops off the bottom, not both edges (matches Pics).
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shouldFill ? .top : .center)
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
                        // bis die Engine ihr **erstes echtes Frame** dekodiert hat.
                        // Spart pro Karte einen `CustomAsyncImage`-Request + Render-Pass und vermeidet das Aufblitzen
                        // eines Standbilds vor dem Video.
                        //
                        // WICHTIG: Die Video-Surface bleibt IMMER sichtbar (kein Opacity-Gating).
                        // Eine noch nicht dekodierte Surface ist schwarz auf schwarzem Grund — visuell identisch.
                        if let aether = aetherEngine {
                            AetherVideoSurface(
                                engine: aether,
                                videoGravity: shouldFill ? .resizeAspectFill : .resizeAspect,
                                bottomContentInset: shouldFill ? bottomInset : 0,
                                topAlignAspectFill: shouldFill
                            )
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
        guard !item.isAnimated, let aether = aetherEngine else { return }

        if isPressed {
            HapticManager.selection()
            aether.rate = 2.0
            withAnimation {
                isFastForwarding = true
            }
        } else {
            aether.rate = 1.0
            withAnimation {
                isFastForwarding = false
            }
        }
        onInteraction()
    }

    /// The engine gave up on this row — say so instead of leaving a black cell.
    @ViewBuilder
    private var playbackErrorOverlay: some View {
        if let message = engineErrorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
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
                if !isRotating { aetherPlayIfAllowed() }
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
    
    
    /// Self-healing for the known "first reel stays black on initial load" stall:
    /// if the active row should be playing but the engine is missing or not actually
    /// playing, rebuild it. Covers lost play triggers, audio-session hiccups and
    /// load races that deterministic review could not pin down.
    private func armPlaybackWatchdog() {
        guard !item.isAnimated else { return }
        playbackWatchdogTask?.cancel()
        playbackWatchdogTask = Task {
            if await cancellableSleep(nanoseconds: 2_500_000_000) { return }
            // NOTE: deliberately not gated on `isUserScrolling` — that flag can strand
            // `true` after initial programmatic scrolling, and this row is active
            // (never an off-screen flasher), so recovery is always safe here.
            // Also NOT gated on `isPlaying`: a missing player renders the row black, and
            // that has to be repaired whether or not the user wants playback running.
            guard self.isActive,
                  !ReelsPlayerRegistry.isPlaybackSuspended else { return }

            if self.aetherEngine == nil {
                AppLog.error("🎬 Reel watchdog: active row has no engine — recovering (scrolling=\(self.isUserScrolling) playing=\(self.isPlaying))")
                // Build the engine either way so a frame appears; only start it when the
                // user actually wants playback.
                self.setupPlayer(forcePlay: self.isPlaying)
                if self.isPlaying {
                    self.aetherPlayIfAllowed()
                }
                return
            }

            // A dead engine never recovers on its own — rebuild it once. If the rebuilt
            // engine fails again, the error stands and the row reports it.
            if let message = self.aetherErrorMessage {
                guard !self.didRebuildAfterEngineError else {
                    AppLog.error("🎬 Reel watchdog: playback engine failed again (\(message))")
                    self.engineErrorMessage = message
                    return
                }
                AppLog.error("🎬 Reel watchdog: playback engine failed (\(message)) — rebuilding once")
                self.didRebuildAfterEngineError = true
                self.cleanupPlayer()
                self.setupPlayer(forcePlay: true)
                return
            }

            // From here on the row has an engine — the remaining checks are about *playback*,
            // so they must respect a pause the user tapped in the last 2.5s.
            guard self.isPlaying else { return }

            guard !self.isPlaybackMoving else {
                // Playing but no decoded frame surfaced yet — force the readiness fallback.
                if !self.videoSurfaceReadiness.showsDecodedVideo {
                    AppLog.error("🎬 Reel watchdog: playing without decoded surface — forcing visibility")
                    self.videoSurfaceReadiness.markFrameReady()
                }
                return
            }
            self.aetherPlayIfAllowed()

            if await cancellableSleep(nanoseconds: 1_200_000_000) { return }
            guard self.isActive, self.isPlaying else { return }
            if !self.isPlaybackMoving {
                AppLog.error("🎬 Reel watchdog: playback stalled after kick — rebuilding")
                self.cleanupPlayer()
                self.setupPlayer()
                self.aetherPlayIfAllowed()
            }
        }
    }

    private func disarmPlaybackWatchdog() {
        playbackWatchdogTask?.cancel()
        playbackWatchdogTask = nil
    }

    /// Builds (or refreshes) this row's playback engine. One engine per row, created lazily.
    func setupPlayer(forcePlay: Bool = false) {
        // Animations are images — nothing to play.
        guard !item.isAnimated else { return }
        // Off-tab: do not create engines (loading would re-activate the audio session).
        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }

        // `onAppear` + scroll settle can both call `setupPlayer` in the same transition;
        // an existing engine only needs its callbacks re-bound (no reload, no flash).
        if let aether = aetherEngine {
            refreshAetherCallbacks()
            if !isRotating && (forcePlay || (isPlaying && isPlaybackActive)) {
                ReelsPlayerRegistry.playIfAllowed(aether)
            }
            return
        }

        playerSetupGeneration &+= 1

        guard let url = item.videoURL else {
            AppLog.error("🎬 Reel: no playable source for this row")
            engineErrorMessage = "No playable source"
            return
        }

        guard let aether = try? AetherSceneEngine() else {
            AppLog.error("🎬 Reel: playback engine could not be created")
            engineErrorMessage = "Playback engine unavailable"
            return
        }

        engineErrorMessage = nil
        aether.isMuted = isMuted
        aether.loopsAtEnd = !TabManager.shared.reelsContinuousPlay
        aether.setVideoGravity(shouldFill ? .resizeAspectFill : .resizeAspect)
        bindAetherCallbacks(on: aether)

        videoSurfaceReadiness.reset()
        aetherEngine = aether
        ReelsPlayerRegistry.register(aether)

        let autoplay = !isRotating && isActive && (forcePlay || isPlaying)
        Task { await aether.load(url: url, startAt: nil, autoplay: autoplay) }

        // Initial duration guess from model.
        if let d = item.duration, d > 0 {
            if isActive { scrubberState.duration = d }
        }

        if isPlaying && isPlaybackActive && !isRotating {
            startPlaybackActivityTrackingIfNeeded()
        }
    }

    func incrementPlayCount() {
        switch item {
        case .scene, .marker:
            onPlayCountChanged((item.playCount ?? 0) + 1)
        case .preview, .clip:
            break
        }
    }

    /// Count real playback only. Skipping away before 30s must not call `sceneAddPlay`.
    private func noteReelsWatchProgress(delta: Double = 0.1) {
        switch item {
        case .scene, .marker: break
        case .preview, .clip: return
        }
        guard isPlaying, isPlaybackActive, !isRotating else { return }
        guard !ReelsPlayerRegistry.isPlaybackSuspended else { return }
        reelsWatchedSeconds += delta
        guard !didCreditReelsWatch, reelsWatchedSeconds >= Self.reelsMinWatchSecondsBeforePlayCredit else { return }
        didCreditReelsWatch = true
        incrementPlayCount()
        playbackActivityTracker.flush()
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
            // Don't write last_played / resume until this reel has been watched 30s.
            guard self.didCreditReelsWatch else {
                self.heldReelsPlayDuration += max(0, playDuration)
                return
            }
            let durationToSave = playDuration + self.heldReelsPlayDuration
            self.heldReelsPlayDuration = 0
            vm.updateSceneResumeTime(
                sceneId: sceneId,
                resumeTime: resumeTime,
                playDuration: durationToSave
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

    private func syncPlaybackActivityPosition() {
        guard tracksPlaybackActivity else { return }
        let current = aetherCurrentTime ?? scrubberState.time
        let duration = aetherDuration ?? scrubberState.duration
        playbackActivityTracker.setPosition(currentTime: current, duration: duration)
    }

    /// Tears the row's engine down and resets everything derived from it.
    func cleanupPlayer() {
        shutdownScrubPreview()
        playerSetupGeneration &+= 1
        syncPlaybackActivityPosition()
        playbackActivityTracker.stop()
        didCreditReelsWatch = false
        reelsWatchedSeconds = 0
        heldReelsPlayDuration = 0
        cleanupAetherEngine()
        videoSurfaceReadiness.reset()
        playbackPresentationSize = nil
    }

    func seek(to time: Double) {
        guard let aether = aetherEngine else { return }
        Task {
            await aether.seek(to: time)
            if self.isPlaying && self.isPlaybackActive && !self.isRotating {
                ReelsPlayerRegistry.playIfAllowed(aether)
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

// MARK: - Playback engine (Feeds)

/// Every engine touch point of ``ReelItemView`` lives here.
extension ReelItemView {

    var aetherErrorMessage: String? {
        aetherEngine?.errorMessage
    }

    /// "Playback really moves" — the watchdog's stall check.
    var isPlaybackMoving: Bool {
        aetherEngine?.isPlaying ?? false
    }

    var aetherCurrentTime: Double? {
        aetherEngine?.currentTime
    }

    var aetherDuration: Double? {
        guard let d = aetherEngine?.duration, d > 0, !d.isNaN else { return nil }
        return d
    }

    func aetherPause() {
        aetherEngine?.pause()
    }

    func aetherPlayIfAllowed() {
        ReelsPlayerRegistry.playIfAllowed(aetherEngine)
    }

    func aetherSetMuted(_ muted: Bool) {
        aetherEngine?.isMuted = muted
    }

    func aetherSetLoops(continuousPlay: Bool) {
        aetherEngine?.loopsAtEnd = !continuousPlay
    }

    /// Re-binds the engine callbacks so they capture the current view struct.
    func refreshAetherCallbacks() {
        guard let aether = aetherEngine else { return }
        bindAetherCallbacks(on: aether)
    }

    func cleanupAetherEngine() {
        shutdownScrubPreview()
        guard let aether = aetherEngine else { return }
        if isActive { ReelsAetherRouteState.shared.activeRowUsesSoftwareRoute = false }
        AetherMotionAnalysis.teardown(engine: aether)
        ReelsPlayerRegistry.unregister(aether)
        aether.stop()
        aetherEngine = nil
    }

    /// The engine's time / end-of-item / first-frame callbacks, bound to the current view struct.
    private func bindAetherCallbacks(on aether: AetherSceneEngine) {
        aether.loopsAtEnd = !TabManager.shared.reelsContinuousPlay

        // A (re)load swaps the analysis item in place; re-attach AI Motion and publish the route
        // so the chrome pill can hide itself on the software route.
        aether.onAnalysisItemChanged = { [weak aether] item in
            guard let aether else { return }
            if self.isActive {
                ReelsAetherRouteState.shared.activeRowUsesSoftwareRoute = (item == nil)
            }
            guard item != nil else { return }
            AetherMotionAnalysis.ensure(engine: aether)
        }

        aether.onFirstFrame = {
            self.videoSurfaceReadiness.markFrameReady()
        }

        aether.onReachedEnd = {
            // Tab leave can race with end-of-item; never restart audio off-Feeds.
            guard !ReelsPlayerRegistry.isPlaybackSuspended, self.isPlaying, self.isPlaybackActive else { return }
            self.onVideoEnded()
        }

        aether.onTime = { time, duration in
            if self.isActive && !self.scrubberState.seeking {
                self.scrubberState.time = time
            }

            if self.isActive, duration > 0, !duration.isNaN {
                self.scrubberState.duration = duration
            }

            self.syncPlaybackPresentationSize(aether)
            self.syncPlaybackActivityPosition()
            self.noteReelsWatchProgress()
            if self.isPlaying && self.isPlaybackActive && !self.isRotating {
                self.startPlaybackActivityTrackingIfNeeded()
            }
        }
    }

    /// `presentationSize` equivalent: the decoded source size once a frame exists.
    private func syncPlaybackPresentationSize(_ aether: AetherSceneEngine) {
        guard aether.hasFirstFrame, let size = aether.sourceSize else { return }
        guard size.width > 1, size.height > 1 else { return }
        if playbackPresentationSize != size {
            playbackPresentationSize = size
        }
    }
}

struct StashSyncManagerModifier: ViewModifier {
    let isActive: Bool
    let isPlaying: Bool
    /// This row's playback engine. Analysis rides the engine's own item.
    var aetherEngine: AetherSceneEngine?

    // Ohne diese `@ObservedObject`s werden die `onChange(of:)` unten nur ausgewertet,
    // wenn die View aus einem anderen Grund neu rendert — Sync-Mode-Toggles kamen
    // dadurch verzögert oder gar nicht an.
    @ObservedObject private var stashSyncManager = StashSyncManager.shared
    @ObservedObject private var handyManager = HandyManager.shared
    @ObservedObject private var buttplugManager = ButtplugManager.shared
    @ObservedObject private var loveSpouseManager = LoveSpouseManager.shared

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
            .onChange(of: stashSyncManager.isActive) { _, active in
                if active { initialSync() }
            }
            .onChange(of: aetherEngine?.analysisPlayerItem) { _, _ in
                if StashSyncManager.shared.isActive {
                    ensureVideoAnalysis()
                }
            }
            .onChange(of: handyManager.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis()
                    // `isActive = true` alone never starts the pulse oscillator, and the device
                    // managers only ever see `currentIntensityPublisher` — go through `start()`.
                    if !StashSyncManager.shared.isActive { StashSyncManager.shared.start() }
                    if isPlaying { HandyManager.shared.play(at: aetherEngine?.currentTime ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: buttplugManager.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis()
                    // `isActive = true` alone never starts the pulse oscillator, and the device
                    // managers only ever see `currentIntensityPublisher` — go through `start()`.
                    if !StashSyncManager.shared.isActive { StashSyncManager.shared.start() }
                    if isPlaying { ButtplugManager.shared.play(at: aetherEngine?.currentTime ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: loveSpouseManager.isStashSyncMode) { _, isStash in
                if isStash && isActive {
                    ensureVideoAnalysis()
                    // `isActive = true` alone never starts the pulse oscillator, and the device
                    // managers only ever see `currentIntensityPublisher` — go through `start()`.
                    if !StashSyncManager.shared.isActive { StashSyncManager.shared.start() }
                    if isPlaying { LoveSpouseManager.shared.play(at: aetherEngine?.currentTime ?? 0) }
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
        let currentTime = aetherEngine?.currentTime ?? 0
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
        ensureVideoAnalysis()
        // Sync-Signale auf den aktuellen Play/Pause-Stand bringen — ersetzt den
        // früheren zweiten `onChange(of: isActive)`-Block.
        applyStashSyncPlaybackState(isActiveOverride: nil, isPlayingOverride: nil)
    }
    // MARK: - Helper Methods
    
    

    
    private func ensureVideoAnalysis() {
        // The native routes expose an analysis item, the software route does not —
        // `AetherMotionAnalysis` handles both.
        guard let aether = aetherEngine else { return }
        AetherMotionAnalysis.ensure(engine: aether)
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
    private let deepLink: ReelsDeepLink

    init(viewModel: StashDBViewModel? = nil, deepLink: ReelsDeepLink = .empty) {
        self.externalViewModel = viewModel
        self.deepLink = deepLink
    }

    var body: some View {
        ReelsViewBody(viewModel: externalViewModel ?? ownedViewModel, deepLink: deepLink)
    }
}

// MARK: - Scrubber Isolation
class ScrubberState: ObservableObject {
    @Published var time: Double = 0.0
    @Published var duration: Double = 1.0
    @Published var seeking: Bool = false
    @Published var seekTarget: Double? = nil
    /// Scrub preview still for the active row. The bar renders it; the active `ReelItemView`
    /// is the only writer (it owns the decode). Deliberately parked here rather than passed
    /// down: the bar lives outside the pager, so this object is the only channel between them.
    @Published var previewImage: UIImage? = nil
}

/// Scrub preview stills for the Feeds scrubber.
///
/// Same policy as `AetherSceneSurface`: one decode in flight, the newest finger position
/// parked and requested as soon as the current one lands, results applied in order, and a
/// nil result keeps whatever was last shown (nil is transient, not "no frame here").
///
/// Source: the row's engine when it has one (its still comes from bytes the playing session
/// already produced, so no second connection); otherwise a standalone `FrameExtractor` over
/// the same signed URL, built lazily on the first request and reused until the URL changes.
@MainActor
final class ReelsScrubThumbnailProvider: ObservableObject {
    @Published var image: UIImage?

    /// Where a landed still is delivered (the Feeds bar reads it off `ScrubberState`).
    var onImage: ((UIImage?) -> Void)?

    private static let thumbnailWidth = 240

    private var task: Task<Void, Never>?
    private var pendingSeconds: Double?
    private var extractor: FrameExtractor?
    private var extractorURL: URL?
    /// Bumped by `end()` / `shutdown()` so a decode that lands after the drag ended
    /// cannot repaint the overlay or chain the parked position.
    private var epoch = 0

    func request(at seconds: Double, aether: AetherSceneEngine?, url: URL?) {
        guard aether != nil || url != nil else { return }
        if task != nil {
            pendingSeconds = seconds
            return
        }
        pendingSeconds = nil
        let target = max(0, seconds)
        let startedEpoch = epoch
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result: UIImage?
            if let aether {
                result = await aether.scrubThumbnail(at: target, maxWidth: CGFloat(Self.thumbnailWidth))
            } else if let extractor = self.makeExtractor(for: url) {
                result = await extractor.thumbnail(at: target, maxWidth: Self.thumbnailWidth)
                    .map { UIImage(cgImage: $0) }
            } else {
                result = nil
            }
            self.task = nil
            guard self.epoch == startedEpoch else { return }
            if let result {
                self.image = result
                self.onImage?(result)
            }
            if let next = self.pendingSeconds {
                self.pendingSeconds = nil
                self.request(at: next, aether: aether, url: url)
            }
        }
    }

    /// Drag ended: drop the overlay, keep the extractor warm for the next drag on this row.
    func end() {
        epoch &+= 1
        pendingSeconds = nil
        task = nil
        image = nil
        onImage?(nil)
    }

    /// Row torn down: release the decode context too. The sink is dropped first so a row
    /// that is no longer the active one cannot blank the bar's still on its way out.
    func shutdown() {
        onImage = nil
        end()
        if let extractor {
            Task { await extractor.shutdown() }
        }
        extractor = nil
        extractorURL = nil
    }

    /// Same auth as playback: the signed URL plus the `ApiKey` header, so a server that
    /// honours only one of the two still returns frames. Local files get neither.
    private func makeExtractor(for url: URL?) -> FrameExtractor? {
        guard let url else { return nil }
        let signed = signedURL(url) ?? url
        if let existing = extractor, extractorURL == signed { return existing }
        if let extractor { Task { await extractor.shutdown() } }

        var headers: [String: String] = [:]
        if !url.isFileURL, url.absoluteString.hasPrefix("http"),
           let key = ServerConfigManager.shared.activeConfig?.secureApiKey, !key.isEmpty {
            headers["ApiKey"] = key
        }
        let created = FrameExtractor(url: signed, httpHeaders: headers)
        extractor = created
        extractorURL = signed
        return created
    }
}

struct IsolatedScrubberBar: View {
    @ObservedObject var state: ScrubberState
    var isUIVisible: Bool

    var body: some View {
        scrubber
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    if state.seeking, state.duration > 0 {
                        scrubPreviewOverlay(barWidth: max(geo.size.width, 1))
                    }
                }
                .allowsHitTesting(false)
                .opacity(isUIVisible ? 1 : 0)
            }
    }

    /// Floating still above the scrub position, clamped to the bar so it never leaves the screen.
    /// Matches the scene-detail overlay: 120 pt, 16:9, radius 6, white hairline, time label.
    @ViewBuilder
    private func scrubPreviewOverlay(barWidth: CGFloat) -> some View {
        let previewWidth: CGFloat = 120
        let previewHeight: CGFloat = previewWidth * 9 / 16
        let half = previewWidth / 2
        let progress = CGFloat(min(1, max(0, state.time / max(state.duration, 0.001))))
        let rawCenter = barWidth * progress
        let center = barWidth > previewWidth
            ? min(max(half, rawCenter), barWidth - half)
            : barWidth / 2

        VStack(spacing: 3) {
            // No frame yet (first decode, or a source without stills): only the time label,
            // never an empty black box.
            if let image = state.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewWidth, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)
            }

            Text(Self.formatTime(state.time))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: previewWidth)
        .offset(x: center - half, y: -(previewHeight + 28))
        .allowsHitTesting(false)
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var scrubber: some View {
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
