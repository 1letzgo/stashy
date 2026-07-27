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
    @Published var reelsTargetMode: String? = nil
    @Published var reelsNavigationToken = UUID()

    // StashLine Navigation
    @Published var stashlinePath = NavigationPath()
    @Published var picsPerformerFilter: GalleryPerformer?

    
    // IDs to force reset of navigation stacks
    @Published var homeTabID = UUID()
    @Published var performersTabID = UUID()
    @Published var studiosTabID = UUID()
    @Published var catalogueTabID = UUID()
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
    
    func navigateToScenes(sort: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter? = nil, search: String = "", noDefaultFilter: Bool = false) {
        self.activeSortOption = sort?.rawValue
        self.activeFilter = filter
        self.activeSearchText = search
        self.noDefaultFilter = noDefaultFilter
        
        self.catalogueTabID = UUID() // Force reset stack
        self.catalogueSubTab = "Scenes"
        self.selectedTab = .catalogue
    }
    
    func navigateToPerformers(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Performers"
        self.selectedTab = .catalogue
    }
    
    func navigateToStudios(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Studios"
        self.selectedTab = .catalogue
    }
    
    func navigateToTags(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Tags"
        self.selectedTab = .catalogue
    }
    
    func navigateToGalleries(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Galleries"
        self.selectedTab = .catalogue
    }
    
    func navigateToImages(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Images"
        self.selectedTab = .catalogue
    }
    
    func navigateToGroups(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Groups"
        self.selectedTab = .catalogue
    }

    func navigateToMarkers(search: String = "") {
        self.activeSearchText = search
        self.catalogueTabID = UUID()
        self.catalogueSubTab = "Markers"
        self.selectedTab = .catalogue
    }
    
    func navigateToReels(performer: ScenePerformer? = nil, tags: [Tag] = [], mode: String? = nil) {
        self.reelsPerformer = performer
        self.reelsTags = tags
        self.reelsTargetMode = mode
        self.reelsNavigationToken = UUID()
        self.reelsTabID = UUID() // Force reset stack if needed
        self.selectedTab = .reels
    }

    func navigateToStashLine(performer: GalleryPerformer) {
        self.picsPerformerFilter = performer
        self.reelsTargetMode = "Pics"
        self.reelsTabID = UUID()
        self.selectedTab = .reels
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
        reelsPerformer = nil
        reelsTags = []
        reelsTargetMode = nil
        picsPerformerFilter = nil
        
        // Force navigation to Home (Dashboard) sub-tab
        self.catalogueSubTab = "Dashboard"
        self.selectedTab = .catalogue
    }
}

// MARK: - SHARED UI COMPONENTS (Extracted for decluttering)

// MARK: - Connection Error
struct ConnectionErrorView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    var title: String = "Server not reachable"
    let onRetry: () -> Void
    var isDark: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 64) )
                .foregroundColor(appearanceManager.tintColor)
            
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isDark ? .white : .primary)
            
            Button(action: onRetry) {
                Text("Retry Connection")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(appearanceManager.tintColor)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
        onLayerReady?(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player != player {
            uiView.player = player
        }
        uiView.intendedGravity = videoGravity
        uiView.intelligentZoomFactor = intelligentZoomFactor
        uiView.contentPixelSize = contentSize
        // Always assign — clearing to nil must hard-reset framing.
        uiView.focusNormalized = focusNormalized
        uiView.applyFramingNow()
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

    private func applyFraming() {
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard bounds.width > 1, bounds.height > 1 else {
            avLayer.frame = bounds
            return
        }

        guard let focus = focusNormalized else {
            // Zoom off: sublayer fills view, standard gravity.
            avLayer.videoGravity = intendedGravity
            avLayer.frame = bounds
            return
        }

        let videoSize: CGSize = {
            if let s = contentPixelSize, s.width > 1, s.height > 1 { return s }
            if let s = player?.currentItem?.presentationSize, s.width > 1, s.height > 1 { return s }
            return .zero
        }()
        guard videoSize.width > 1, videoSize.height > 1 else {
            avLayer.videoGravity = intendedGravity
            avLayer.frame = bounds
            return
        }

        // Stretch pixels 1:1 into framed rect; we size the rect ourselves.
        avLayer.videoGravity = .resize
        let fillScale = max(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let scale = fillScale * max(intelligentZoomFactor, 1.0)
        let scaledW = videoSize.width * scale
        let scaledH = videoSize.height * scale

        let focusX = min(max(focus.x, 0), 1)
        // Vision y is bottom-left; layer y is top-left.
        let focusYFromTop = 1 - min(max(focus.y, 0), 1)

        var originX = bounds.midX - focusX * scaledW
        var originY = bounds.midY - focusYFromTop * scaledH
        // Keep view covered (no letterboxing).
        originX = min(max(originX, bounds.width - scaledW), 0)
        originY = min(max(originY, bounds.height - scaledH), 0)
        avLayer.frame = CGRect(x: originX, y: originY, width: scaledW, height: scaledH)
    }
}

// MARK: - Shared Empty State
struct SharedEmptyStateView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    var icon: String
    var title: String
    var buttonText: String
    let onRetry: () -> Void
    var isDark: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(appearanceManager.tintColor)

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isDark ? .white : .primary)

            Button(action: onRetry) {
                Text(buttonText)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(appearanceManager.tintColor)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

// MARK: - Custom Async Image


#endif
