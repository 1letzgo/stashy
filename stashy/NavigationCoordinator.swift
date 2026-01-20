//
//  NavigationCoordinator.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

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
    
    // IDs to force reset of navigation stacks
    @Published var homeTabID = UUID()
    @Published var performersTabID = UUID()
    @Published var studiosTabID = UUID()
    @Published var catalogueTabID = UUID()
    @Published var downloadsTabID = UUID()
    @Published var reelsTabID = UUID()
    @Published var settingsTabID = UUID()
    
    // Sub-tab control for Combined Tabs
    @Published var catalogueSubTab: String = ""
    
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
    }
    
    func openPerformer(_ performer: Performer) {
        // Reset the Performers tab stack
        performersTabID = UUID()
        
        // Set the performer to open
        performerToOpen = performer
        
        // Switch to Performers tab
        selectedTab = .performers
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
    
    func navigateToReels(performer: ScenePerformer? = nil, tags: [Tag] = []) {
        self.reelsPerformer = performer
        self.reelsTags = tags
        
        self.reelsTabID = UUID() // Force reset stack if needed
        self.selectedTab = .reels
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
    
    func makeUIView(context: Context) -> PlayerView {
        return PlayerView(player: player, gravity: videoGravity)
    }
    
    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player != player {
            uiView.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}

class PlayerView: UIView {
    var player: AVPlayer? {
        get { return playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        self.player = player
        self.playerLayer.videoGravity = gravity
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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


