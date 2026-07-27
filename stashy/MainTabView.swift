//
//  MainTabView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import AVKit
import AVFoundation

struct MainTabView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var securityManager = SecurityManager.shared
    /// Feeds (`ReelsView`): bleibt über Tab-Wechsel erhalten; Szenen-/Marker-Scroll-Position in `ReelsSessionRAM`.
    @StateObject private var reelsFeedViewModel = StashDBViewModel()
    @State private var hasValidConfig = false
    @State private var showConfigWarning = false
    @State private var showOnboarding = false
    @State private var warningType: ConfigWarningType = .none

    enum ConfigWarningType {
        case none
        case noServer
        case invalidConfig
        case authExpired
    }

    var body: some View {
        ZStack {
            TabView(selection: Binding(
                get: { coordinator.selectedTab },
                set: { newValue in
                    if newValue == coordinator.selectedTab && newValue == .catalogue {
                        let now = Date()
                        if let lastTap = coordinator.lastHomeTapTime, now.timeIntervalSince(lastTap) < 0.5 {
                            // Double tap detected -> Go to Dashboard
                            coordinator.catalogueSubTab = CatalogsView.CatalogsTab.dashboard.rawValue
                            coordinator.lastHomeTapTime = nil
                        } else {
                            // Single tap -> Just record time and let system pop/scroll
                            coordinator.lastHomeTapTime = now
                        }
                    } else {
                        coordinator.selectedTab = newValue
                        coordinator.lastHomeTapTime = nil
                    }
                }
            )) {
                // Dynamic Configurable Tabs using new Tab API
                ForEach(tabManager.visibleTabs) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        view(for: tab)
                            .tint(appearanceManager.tintColor)
                    }
                }
                
                // iOS 18+ Search tab with dedicated role
                Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    UniversalSearchView()
                        .applyAppBackground()
                }
            }
            .id(coordinator.serverSwitchID)
            .tint(appearanceManager.tintColor)
            .withToasts()
            .onAppear {
                ServerConfigManager.shared.scrubPlaintextAPIKeysFromDisk()
                checkConfiguration()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuthError401"))) { _ in
                // Navigate to Home on 401 errors
                coordinator.selectedTab = .catalogue
                warningType = .authExpired
                showConfigWarning = true
            }
            .onChange(of: coordinator.selectedTab) { oldTab, newTab in
                // Fallback wenn `ReelsView` beim Tab-Wechsel keinen eigenen Teardown auslöst.
                guard oldTab == .reels, newTab != .reels else { return }
                ReelsPlayerRegistry.pauseAll()
                NotificationCenter.default.post(name: Notification.Name("ReelsPauseAllPlayers"), object: nil)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }

            if securityManager.isAppLocked {
                PasscodeEntryView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0), value: securityManager.isAppLocked)
        .sheet(isPresented: $showOnboarding) {
            ServerSetupWizardView { newConfig in
                ServerConfigManager.shared.addOrUpdateServer(newConfig)
                ServerConfigManager.shared.saveConfig(newConfig)
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .alert(isPresented: $showConfigWarning) {
            switch warningType {
            case .noServer:
                return Alert(
                    title: Text("Welcome to stashy"),
                    message: Text("Please configure your Stash server to get started."),
                    dismissButton: .default(Text("Go to Settings")) {
                        coordinator.selectedTab = .settings
                    }
                )
            case .invalidConfig:
                return Alert(
                    title: Text("Incomplete Setup"),
                    message: Text("Your server configuration is missing some details."),
                    dismissButton: .default(Text("Check Settings")) {
                        coordinator.selectedTab = .settings
                    }
                )
            case .authExpired:
                return Alert(
                    title: Text("Authentication Required"),
                    message: Text("Your API key is invalid or expired. Please check your server configuration."),
                    dismissButton: .default(Text("Update API Key")) {
                        coordinator.selectedTab = .settings
                    }
                )
            default:
                return Alert(title: Text("Error"))
            }
        }
        .preferredColorScheme(appearanceManager.preferredTheme.colorScheme)
    }

    private func checkConfiguration() {
        if let config = ServerConfigManager.shared.loadConfig() {
            hasValidConfig = config.hasValidConfig
            if !hasValidConfig {
                warningType = .invalidConfig
                showConfigWarning = true
            }
        } else if ServerConfigManager.shared.savedServers.isEmpty {
            print("❌ NO SERVER CONFIGURATION FOUND - SHOWING WIZARD")
            hasValidConfig = false
            showOnboarding = true
        } else {
            hasValidConfig = false
            coordinator.selectedTab = .settings
        }
    }
}

extension MainTabView {
    @ViewBuilder
    func view(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            NavigationStack {
                HomeView()
                    .applyAppBackground()
            }
            .id(coordinator.homeTabID)

        case .performers:
            NavigationStack {
                PerformersView()
                    .applyAppBackground()
            }
            .id(coordinator.performersTabID)

        case .catalogue:
            NavigationStack {
                CatalogsView()
                    .applyAppBackground()
            }
            .id(coordinator.catalogueTabID)

        case .downloads:
            NavigationStack {
                DownloadsView()
                    .applyAppBackground()
            }
            .id(coordinator.downloadsTabID)
            
        case .tools:
            NavigationStack {
                ToolsView()
                    .applyAppBackground()
            }
            .id(coordinator.toolsTabID)
            
        case .reels:
            NavigationStack {
                ReelsView(viewModel: reelsFeedViewModel)
            }
            .id(coordinator.reelsTabID)

        case .settings:
            NavigationStack {
                SettingsView()
                    .applyAppBackground()
            }
            .id(coordinator.settingsTabID)
            
        default:
            EmptyView()
        }
    }
}

// MARK: - Tools (Container Tab)

struct ToolsView: View {
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    
    enum ToolsTab: String, CaseIterable {
        case server = "Server"
        case downloads = "Downloads"
        case statistics = "Statistics"
        case hotOrNot = "Match"
        
        var icon: String {
            switch self {
            case .server: return "server.rack"
            case .downloads: return "square.and.arrow.down"
            case .statistics: return "chart.bar.fill"
            case .hotOrNot: return "flame.fill"
            }
        }
    }
    
    private var sortedTabs: [ToolsTab] {
        // Use persisted order from Settings → Tools
        tabManager.enabledTools.compactMap { item in
            switch item {
            case .server: return .server
            case .downloads: return .downloads
            case .statistics: return .statistics
            case .hotOrNot: return .hotOrNot
            }
        }
    }
    
    private var effectiveTab: ToolsTab {
        if let current = ToolsTab(rawValue: coordinator.toolsSubTab), sortedTabs.contains(current) {
            return current
        }
        return sortedTabs.first ?? .downloads
    }
    
    private var selectedTabBinding: Binding<ToolsTab> {
        Binding(
            get: { effectiveTab },
            set: { coordinator.toolsSubTab = $0.rawValue }
        )
    }
    
    var body: some View {
        Group {
            switch effectiveTab {
            case .server:
                ToolsServerView()
            case .downloads:
                DownloadsView()
            case .statistics:
                ToolsStatisticsView()
            case .hotOrNot:
                HotOrNotToolsView()
            }
        }
        .onAppear {
            if coordinator.toolsSubTab == "Hot or Not" {
                coordinator.toolsSubTab = ToolsTab.hotOrNot.rawValue
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                toolsCategoryRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                
                Divider().overlay(Color.white.opacity(0.15))
            }
            .background(.bar)
            .colorScheme(.dark)
        }
    }
    
    private var toolsCategoryRow: some View {
        HStack(spacing: 8) {
            Text(effectiveTab.rawValue)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 8) {
                ForEach(sortedTabs, id: \.self) { tab in
                    toolTabButton(tab: tab, isActive: tab == effectiveTab)
                        .frame(width: 44)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func toolTabButton(tab: ToolsTab, isActive: Bool) -> some View {
        Button(action: { selectedTabBinding.wrappedValue = tab }) {
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? .white : .primary)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? appearanceManager.tintColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }
}

private struct ToolsServerView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var runningTask: String? = nil
    
    private var activeServer: ServerConfig? { configManager.activeConfig }
    
    var body: some View {
        Group {
            if activeServer != nil {
                Form {
                    Section("Scan & Identify") {
                        taskRow(label: "Scan Library", icon: "arrow.triangle.2.circlepath", taskId: "scan") {
                            viewModel.triggerLibraryScan { _, message in
                                showResult(title: "Scan Library", message: message)
                            }
                        }
                        taskRow(label: "Identify", icon: "person.crop.square.filled.and.at.rectangle", taskId: "identify") {
                            viewModel.triggerIdentify { _, message in
                                showResult(title: "Identify", message: message)
                            }
                        }
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                    
                    Section("Generate") {
                        taskRow(label: "Scene covers", icon: "photo.fill", taskId: "gen_covers") {
                            viewModel.triggerGenerate(covers: true) { _, message in
                                showResult(title: "Scene covers", message: message)
                            }
                        }
                        taskRow(label: "Previews", icon: "play.rectangle.fill", taskId: "gen_previews") {
                            viewModel.triggerGenerate(previews: true) { _, message in
                                showResult(title: "Previews", message: message)
                            }
                        }
                        taskRow(label: "Animated image previews", icon: "photo.on.rectangle.angled", taskId: "gen_imagePreviews") {
                            viewModel.triggerGenerate(imagePreviews: true) { _, message in
                                showResult(title: "Animated image previews", message: message)
                            }
                        }
                        taskRow(label: "Scene scrubber sprites", icon: "square.grid.3x3.fill", taskId: "gen_sprites") {
                            viewModel.triggerGenerate(sprites: true) { _, message in
                                showResult(title: "Scene scrubber sprites", message: message)
                            }
                        }
                        taskRow(label: "Marker previews", icon: "mappin.and.ellipse", taskId: "gen_markers") {
                            viewModel.triggerGenerate(markers: true) { _, message in
                                showResult(title: "Marker previews", message: message)
                            }
                        }
                        taskRow(label: "Marker animated image previews", icon: "mappin.and.ellipse.circle.fill", taskId: "gen_markerImagePreviews") {
                            viewModel.triggerGenerate(markerImagePreviews: true) { _, message in
                                showResult(title: "Marker animated image previews", message: message)
                            }
                        }
                        taskRow(label: "Marker screenshots", icon: "camera.fill", taskId: "gen_markerScreenshots") {
                            viewModel.triggerGenerate(markerScreenshots: true) { _, message in
                                showResult(title: "Marker screenshots", message: message)
                            }
                        }
                        taskRow(label: "Transcodes", icon: "film.stack", taskId: "gen_transcodes") {
                            viewModel.triggerGenerate(transcodes: true) { _, message in
                                showResult(title: "Transcodes", message: message)
                            }
                        }
                        taskRow(label: "Video perceptual hashes", icon: "number.square.fill", taskId: "gen_phashes") {
                            viewModel.triggerGenerate(phashes: true) { _, message in
                                showResult(title: "Video perceptual hashes", message: message)
                            }
                        }
                        taskRow(label: "Generate heatmaps and speeds for interactive scenes", icon: "waveform.path.ecg", taskId: "gen_heatmaps") {
                            viewModel.triggerGenerate(interactiveHeatmapsSpeeds: true) { _, message in
                                showResult(title: "Generate heatmaps and speeds", message: message)
                            }
                        }
                        taskRow(label: "Image clip previews", icon: "play.rectangle.on.rectangle.fill", taskId: "gen_clipPreviews") {
                            viewModel.triggerGenerate(clipPreviews: true) { _, message in
                                showResult(title: "Image clip previews", message: message)
                            }
                        }
                        taskRow(label: "Image thumbnails", icon: "photo.on.rectangle", taskId: "gen_imageThumbnails") {
                            viewModel.triggerGenerate(imageThumbnails: true) { _, message in
                                showResult(title: "Image thumbnails", message: message)
                            }
                        }
                        taskRow(label: "Image perceptual hashes", icon: "number.circle.fill", taskId: "gen_imagePhashes") {
                            viewModel.triggerGenerate(imagePhashes: true) { _, message in
                                showResult(title: "Image perceptual hashes", message: message)
                            }
                        }
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                    
                    Section("Cache") {
                        taskRow(label: "Clear Image Cache", icon: "internaldrive", taskId: "cache_clear") {
                            ImageCache.shared.clearCurrentServerCache()
                            showResult(title: "Cache Cleared", message: "Images will be reloaded from the server.")
                        }
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }
                .navigationTitle("Server")
                .scrollContentBackground(.hidden)
                .alert(alertTitle, isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(alertMessage)
                }
                .onAppear {
                    viewModel.testConnection()
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "server.rack")
                        .font(.system(size: 64))
                        .foregroundColor(appearanceManager.tintColor)
                    Text("No active server")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Select a server in Settings to use server tools.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func taskRow(label: String, icon: String, taskId: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 24, alignment: .center)
            }
            .foregroundColor(.primary)
            Spacer()
            if runningTask == taskId {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                Button(action: {
                    runningTask = taskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        action()
                    }
                }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(runningTask != nil)
            }
        }
    }
    
    private func showResult(title: String, message: String) {
        DispatchQueue.main.async {
            runningTask = nil
            alertTitle = title
            alertMessage = message
            showAlert = true
        }
    }
}

private struct ToolsStatisticsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        Group {
            if configManager.activeConfig != nil {
                ServerStatisticsView(viewModel: viewModel)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 64))
                        .foregroundColor(appearanceManager.tintColor)
                    Text("No active server")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Select a server in Settings to view statistics.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    MainTabView()
}
#endif
