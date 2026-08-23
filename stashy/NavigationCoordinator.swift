//
//  NavigationCoordinator.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS) && !os(watchOS)
import SwiftUI
import Combine
import AVKit
import AVFoundation

// MARK: - Navigation Coordinator
// AppTab, TabConfig, DetailViewConfig and TabManager are defined in TabManager.swift

class NavigationCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .studios
    var performerToOpen: Performer?
    @Published var studioToOpen: Studio?
    
    // Reels Selection
    @Published var reelsPerformer: ScenePerformer?
    @Published var reelsTags: [Tag] = []
    @Published var reelsStudio: SceneStudio?
    @Published var reelsTargetMode: String? = nil
    @Published var reelsNavigationToken = UUID()
    /// Snapshot captured by the remounted Feeds instance (avoids race where a dying
    /// ReelsView clears performer/tags before the new instance can read them).
    @Published private(set) var reelsDeepLink = ReelsDeepLink.empty
    /// TabView echoes a programmatic `selectedTab = .reels` as an icon re-tap. That would
    /// remount Feeds with an empty deep link and drop the channel / performer handoff.
    var suppressNextFeedsIconRemount = false

    // StashLine Navigation
    @Published var stashlinePath = NavigationPath()
    @Published var picsPerformerFilter: GalleryPerformer?

    
    // IDs to force reset of navigation stacks
    @Published var homeTabID = UUID()
    @Published var performersTabID = UUID()
    @Published var studiosTabID = UUID()
    @Published var catalogueTabID = UUID()
    /// Pops catalogue details without remounting the stack (avoids a top-left zoom).
    @Published var cataloguePopToken = UUID()
    @Published var downloadsTabID = UUID()
    @Published var toolsTabID = UUID()
    @Published var reelsTabID = UUID()
    @Published var stashlineTabID = UUID()
    @Published var settingsTabID = UUID()
    @Published var serverSwitchID = UUID()
    
    // Sub-tab control for Combined Tabs
    @Published var catalogueSubTab: String = ""
    @Published var toolsSubTab: String = ""
    
    // Remote state injection for deep links
    @Published var activeSortOption: String?
    @Published var activeFilter: StashDBViewModel.SavedFilter?
    @Published var activeSearchText: String = ""
    @Published var noDefaultFilter: Bool = false  // Prevent default filter application
    
    // Tap timing for "Double Tap" detection
    var lastHomeTapTime: Date?
    
    // Initializer to set start tab based on config
    init() {
        // Force load TabManager
        _ = TabManager.shared
        
        // Default to the first visible tab
        if let firstTab = TabManager.shared.visibleTabs.first {
            selectedTab = firstTab
        }
        
        // Listen for server changes to reset all stacks
        NotificationCenter.default.addObserver(self, selector: #selector(handleServerChange), name: NSNotification.Name("ServerConfigChanged"), object: nil)
    }
    
    @objc private func handleServerChange() {
        resetAllStacks()
    }
    
    func openPerformer(_ performer: Performer) {
        // Reset the Catalogue tab stack (performers live as a catalogue sub-tab)
        catalogueTabID = UUID()
        
        // Set the performer to open
        performerToOpen = performer
        
        // Switch internal sub-tab to Performers
        catalogueSubTab = "Performers"
        
        // Switch to Catalogue tab
        selectedTab = .catalogue
    }
    
    func openStudio(_ studio: Studio) {
        // Reset the Catalogue tab stack (where studios now lives)
        catalogueTabID = UUID()
        
        // Set the studio to open
        studioToOpen = studio
        
        // Switch internal sub-tab to Studios
        catalogueSubTab = "Studios"
        
        // Switch to Catalogue tab
        selectedTab = .catalogue
    }

    // MARK: - Deep Links

    /// Search → Show All / stats deep links: switch catalog instantly.
    /// Do not remount `catalogueTabID` here — a new `NavigationStack` identity zooms
    /// in from the top-left (especially when leaving the Search tab).
    private func switchToCatalogue(_ subTab: String) {
        UIView.setAnimationsEnabled(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cataloguePopToken = UUID()
            catalogueSubTab = subTab
            selectedTab = .catalogue
        }
        DispatchQueue.main.async {
            UIView.setAnimationsEnabled(true)
        }
    }
    
    func navigateToScenes(sort: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter? = nil, search: String = "", noDefaultFilter: Bool = false) {
        self.activeSortOption = sort?.rawValue
        self.activeFilter = filter
        self.activeSearchText = search
        self.noDefaultFilter = noDefaultFilter
        switchToCatalogue("Scenes")
    }
    
    func navigateToPerformers(sort: StashDBViewModel.PerformerSortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Performers")
    }
    
    func navigateToStudios(sort: StashDBViewModel.StudioSortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Studios")
    }
    
    func navigateToTags(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Tags")
    }
    
    func navigateToGalleries(sort: StashDBViewModel.GallerySortOption? = nil, search: String = "") {
        self.activeSortOption = sort?.rawValue
        self.activeSearchText = search
        switchToCatalogue("Galleries")
    }
    
    func navigateToImages(search: String = "") {
        self.activeSearchText = search
        self.noDefaultFilter = !search.isEmpty
        switchToCatalogue("Images")
    }
    
    func navigateToGroups(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Groups")
    }

    func navigateToMarkers(search: String = "") {
        self.activeSearchText = search
        switchToCatalogue("Markers")
    }
    
    func navigateToReels(performer: ScenePerformer? = nil, tags: [Tag] = [], studio: SceneStudio? = nil, mode: String? = nil) {
        let link = ReelsDeepLink(performer: performer, tags: tags, studio: studio, mode: mode, picsPerformer: nil)
        self.reelsDeepLink = link
        self.reelsPerformer = performer
        self.reelsTags = tags
        self.reelsStudio = studio
        self.reelsTargetMode = mode
        self.picsPerformerFilter = nil
        // Tear down players, then remount so performer/tag/studio handoff cannot reuse a stale session.
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    /// Dashboard channel → Feeds in Scenes mode, scoped to a saved scene filter.
    func navigateToReelsChannel(filter: StashDBViewModel.SavedFilter, sort: StashDBViewModel.SceneSortOption) {
        let link = ReelsDeepLink(
            performer: nil,
            tags: [],
            mode: "Scenes",
            picsPerformer: nil,
            sceneFilter: filter,
            sceneSort: sort.rawValue
        )
        self.reelsDeepLink = link
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Scenes"
        self.picsPerformerFilter = nil
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    /// Dashboard image channel → Feeds in Clips mode, scoped to a saved image filter.
    func navigateToReelsClipsChannel(filter: StashDBViewModel.SavedFilter, sort: StashDBViewModel.ImageSortOption) {
        let link = ReelsDeepLink(
            performer: nil,
            tags: [],
            mode: "Clips",
            picsPerformer: nil,
            clipFilter: filter,
            clipSort: sort.rawValue
        )
        self.reelsDeepLink = link
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Clips"
        self.picsPerformerFilter = nil
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    func navigateToStashLine(performer: GalleryPerformer) {
        let link = ReelsDeepLink(performer: nil, tags: [], mode: "Pics", picsPerformer: performer)
        self.reelsDeepLink = link
        self.picsPerformerFilter = performer
        self.reelsPerformer = nil
        self.reelsTags = []
        self.reelsTargetMode = "Pics"
        NotificationCenter.default.post(name: Notification.Name("ReelsWillRemount"), object: nil)
        self.reelsTabID = UUID()
        self.suppressNextFeedsIconRemount = true
        self.selectedTab = .reels
        self.reelsNavigationToken = UUID()
    }

    func clearReelsDeepLink() {
        reelsDeepLink = .empty
        reelsPerformer = nil
        reelsTags = []
        reelsStudio = nil
        reelsTargetMode = nil
        picsPerformerFilter = nil
    }
    
    func resetAllStacks() {
        homeTabID = UUID()
        performersTabID = UUID()
        studiosTabID = UUID()
        catalogueTabID = UUID()
        downloadsTabID = UUID()
        toolsTabID = UUID()
        reelsTabID = UUID()
        stashlineTabID = UUID()
        stashlinePath = NavigationPath()
        settingsTabID = UUID()
        serverSwitchID = UUID()

        activeSortOption = nil
        activeFilter = nil
        activeSearchText = ""
        noDefaultFilter = false
        performerToOpen = nil
        studioToOpen = nil
        clearReelsDeepLink()
        
        // Force navigation to Home (Dashboard) sub-tab
        self.catalogueSubTab = "Dashboard"
        self.selectedTab = .catalogue
    }
}

/// Atomic Feeds deep-link payload (Performer / Tags / Mode) for a single remount.
struct ReelsDeepLink: Equatable {
    var performer: ScenePerformer?
    var tags: [Tag]
    var studio: SceneStudio? = nil
    var mode: String?
    var picsPerformer: GalleryPerformer?
    /// Channel deep link: saved scene filter to apply instead of the Feeds default filter.
    var sceneFilter: StashDBViewModel.SavedFilter? = nil
    /// `SceneSortOption.rawValue` for a channel deep link.
    var sceneSort: String? = nil
    /// Channel deep link: saved image filter applied in Feeds → Clips.
    var clipFilter: StashDBViewModel.SavedFilter? = nil
    /// `ImageSortOption.rawValue` for a Clips channel deep link.
    var clipSort: String? = nil

    static let empty = ReelsDeepLink(performer: nil, tags: [], studio: nil, mode: nil, picsPerformer: nil)

    var isEmpty: Bool {
        performer == nil && tags.isEmpty && studio == nil && mode == nil && picsPerformer == nil
            && sceneFilter == nil && sceneSort == nil
            && clipFilter == nil && clipSort == nil
    }
}

// MARK: - SHARED UI COMPONENTS (Extracted for decluttering)

// MARK: - Connection Error
struct ConnectionErrorView: View {
    var title: String = "Server not reachable"
    let onRetry: () -> Void
    var isDark: Bool = false

    var body: some View {
        StatusPlaceholderView(
            icon: "server.rack",
            title: title,
            buttonText: "Retry Connection",
            isDark: isDark,
            fillsScreen: true,
            onAction: onRetry
        )
    }
}

// MARK: - Video Player Components
struct FullScreenVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    /// Normalized focus in Vision-ish coords (x: 0…1 left→right, y: 0…1 bottom→top).
    /// `nil` = no intelligent zoom (standard gravity, full bounds).
    var focusNormalized: CGPoint? = nil
    /// Extra zoom factor on top of aspect-fill while focus is active (1.0 = fill only).
    var intelligentZoomFactor: CGFloat = 1.15
    /// Pixel size of the video content (required for intelligent framing).
    var contentSize: CGSize? = nil
    /// Shrinks only the `AVPlayerLayer` from the top (e.g. below the status-bar safe area).
    var topContentInset: CGFloat = 0
    /// Shrinks only the `AVPlayerLayer` from the bottom (e.g. stop above the tab bar).
    /// Does **not** change the UIView bounds — Feeds paging / hit-testing stay full-bleed.
    var bottomContentInset: CGFloat = 0
    /// When `videoGravity == .resizeAspect`, pin letterboxed content to the top of the draw rect
    /// instead of centering (portrait Feeds with immersive off).
    var topAlignAspectFit: Bool = false
    /// Optionaler Hook: erhält den frisch erzeugten `AVPlayerLayer` (für KVO auf `isReadyForDisplay`).
    /// Wird bspw. von `ReelItemVideoSurfaceReadiness` verwendet, um die Thumbnail-Überblendung
    /// erst beim **echten ersten Frame** zu starten — nicht schon bei `AVPlayerItem.status == .readyToPlay`.
    var onLayerReady: ((AVPlayerLayer) -> Void)? = nil

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView(player: player, gravity: videoGravity)
        view.intendedGravity = videoGravity
        view.focusNormalized = focusNormalized
        view.intelligentZoomFactor = intelligentZoomFactor
        view.contentPixelSize = contentSize
        view.topContentInset = topContentInset
        view.bottomContentInset = bottomContentInset
        view.topAlignAspectFit = topAlignAspectFit
        // Deferred: the callback mutates ObservableObject state (`videoSurfaceReadiness`).
        // Calling it synchronously from makeUIView triggers "Modifying state during view
        // update", which invalidates the surrounding SwiftUI transaction.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            onLayerReady?(view.playerLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        let playerChanged = uiView.player !== player
        if playerChanged {
            uiView.player = player
        }

        let gravityChanged = uiView.intendedGravity != videoGravity
        let zoomChanged = uiView.intelligentZoomFactor != intelligentZoomFactor
        let sizeChanged = uiView.contentPixelSize != contentSize
        let focusChanged = uiView.focusNormalized != focusNormalized
        let topInsetChanged = uiView.topContentInset != topContentInset
        let bottomInsetChanged = uiView.bottomContentInset != bottomContentInset
        let topAlignChanged = uiView.topAlignAspectFit != topAlignAspectFit

        uiView.intendedGravity = videoGravity
        uiView.intelligentZoomFactor = intelligentZoomFactor
        uiView.contentPixelSize = contentSize
        // Always assign — clearing to nil must hard-reset framing.
        uiView.focusNormalized = focusNormalized
        uiView.topContentInset = topContentInset
        uiView.bottomContentInset = bottomContentInset
        uiView.topAlignAspectFit = topAlignAspectFit

        // Avoid synchronous layout on every SwiftUI body pass (Feeds chrome / VM publishes).
        if playerChanged || gravityChanged || zoomChanged || sizeChanged
            || focusChanged || topInsetChanged || bottomInsetChanged || topAlignChanged {
            uiView.applyFramingNow()
        }
        // Only re-bind when the player instance changes (avoids SwiftUI update storms).
        if playerChanged {
            // Deferred for the same reason as in `makeUIView`.
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                onLayerReady?(uiView.playerLayer)
            }
        }
    }
}

/// Hosts `AVPlayerLayer` as a **sublayer** (not `layerClass`) so intelligent crop can
/// freely resize/offset the video, and toggle-off can restore `frame == bounds`.
class PlayerView: UIView {
    private let avLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { avLayer.player }
        set {
            avLayer.player = newValue
            observePresentationSize()
        }
    }

    var playerLayer: AVPlayerLayer { avLayer }

    /// Desired gravity when intelligent framing is off.
    var intendedGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            if focusNormalized == nil {
                avLayer.videoGravity = intendedGravity
            }
        }
    }

    var focusNormalized: CGPoint? {
        didSet {
            if oldValue != focusNormalized {
                setNeedsLayout()
            }
        }
    }

    var intelligentZoomFactor: CGFloat = 1.15
    var contentPixelSize: CGSize?
    var topAlignAspectFit: Bool = false {
        didSet {
            if oldValue != topAlignAspectFit {
                setNeedsLayout()
            }
        }
    }

    /// Top gap left black (safe area). Applied only to `avLayer.frame`, not the view bounds.
    var topContentInset: CGFloat = 0 {
        didSet {
            if oldValue != topContentInset {
                setNeedsLayout()
            }
        }
    }

    /// Bottom gap left black (tab bar). Applied only to `avLayer.frame`, not the view bounds.
    var bottomContentInset: CGFloat = 0 {
        didSet {
            if oldValue != bottomContentInset {
                setNeedsLayout()
            }
        }
    }

    private var sizeObservation: NSKeyValueObservation?

    init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        self.intendedGravity = gravity
        clipsToBounds = true
        isUserInteractionEnabled = false
        backgroundColor = .black
        avLayer.videoGravity = gravity
        layer.addSublayer(avLayer)
        self.player = player
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFocused: Bool { false }

    func applyFramingNow() {
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func observePresentationSize() {
        sizeObservation?.invalidate()
        sizeObservation = nil
        guard let item = player?.currentItem else { return }
        sizeObservation = item.observe(\.presentationSize, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.setNeedsLayout()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyFraming()
    }

    private func contentBounds(for bounds: CGRect) -> CGRect {
        let top = max(0, topContentInset)
        let bottom = max(0, bottomContentInset)
        let height = max(1, bounds.height - top - bottom)
        return CGRect(x: bounds.minX, y: bounds.minY + top, width: bounds.width, height: height)
    }

    private func resolvedVideoSize() -> CGSize {
        if let s = contentPixelSize, s.width > 1, s.height > 1 { return s }
        if let s = player?.currentItem?.presentationSize, s.width > 1, s.height > 1 { return s }
        return .zero
    }

    private func applyFraming() {
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard bounds.width > 1, bounds.height > 1 else {
            avLayer.frame = bounds
            return
        }

        let drawBounds = contentBounds(for: bounds)

        guard let focus = focusNormalized else {
            // Letterbox pinned under the top inset (portrait Feeds, immersive off).
            if topAlignAspectFit, intendedGravity == .resizeAspect {
                let videoSize = resolvedVideoSize()
                if videoSize.width > 1, videoSize.height > 1 {
                    let scale = min(drawBounds.width / videoSize.width, drawBounds.height / videoSize.height)
                    let w = videoSize.width * scale
                    let h = videoSize.height * scale
                    let x = drawBounds.minX + (drawBounds.width - w) / 2
                    avLayer.videoGravity = .resize
                    avLayer.frame = CGRect(x: x, y: drawBounds.minY, width: w, height: h)
                    return
                }
            }
            // Zoom off: sublayer fills the area between top/bottom insets.
            avLayer.videoGravity = intendedGravity
            avLayer.frame = drawBounds
            return
        }

        let videoSize = resolvedVideoSize()
        guard videoSize.width > 1, videoSize.height > 1 else {
            avLayer.videoGravity = intendedGravity
            avLayer.frame = drawBounds
            return
        }

        // Stretch pixels 1:1 into framed rect; we size the rect ourselves.
        avLayer.videoGravity = .resize
        let fillScale = max(drawBounds.width / videoSize.width, drawBounds.height / videoSize.height)
        let scale = fillScale * max(intelligentZoomFactor, 1.0)
        let scaledW = videoSize.width * scale
        let scaledH = videoSize.height * scale

        let focusX = min(max(focus.x, 0), 1)
        // Vision y is bottom-left; layer y is top-left.
        let focusYFromTop = 1 - min(max(focus.y, 0), 1)

        var originX = drawBounds.midX - focusX * scaledW
        var originY = drawBounds.midY - focusYFromTop * scaledH
        // Keep draw area covered (no letterboxing). drawBounds origin is (0,0).
        originX = min(max(originX, drawBounds.width - scaledW), 0)
        originY = min(max(originY, drawBounds.height - scaledH), 0)
        avLayer.frame = CGRect(x: originX, y: originY, width: scaledW, height: scaledH)
    }
}

// MARK: - Shared Empty State
struct SharedEmptyStateView: View {
    var icon: String
    var title: String
    var buttonText: String
    let onRetry: () -> Void
    var isDark: Bool = false

    var body: some View {
        StatusPlaceholderView(
            icon: icon,
            title: title,
            buttonText: buttonText,
            isDark: isDark,
            fillsScreen: true,
            onAction: onRetry
        )
    }
}

// MARK: - Custom Async Image


#endif
