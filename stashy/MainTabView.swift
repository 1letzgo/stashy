//
//  MainTabView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI
import AVKit

struct MainTabView: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
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
        .onAppear {
            checkConfiguration()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuthError401"))) { _ in
            // Navigate to Home on 401 errors
            coordinator.selectedTab = .catalogue
            warningType = .authExpired
            showConfigWarning = true
        }
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
                        coordinator.selectedTab = .catalogue
                    }
                )
            case .invalidConfig:
                return Alert(
                    title: Text("Incomplete Setup"),
                    message: Text("Your server configuration is missing some details."),
                    dismissButton: .default(Text("Check Settings")) {
                        coordinator.selectedTab = .catalogue
                    }
                )
            case .authExpired:
                return Alert(
                    title: Text("Authentication Required"),
                    message: Text("Your API key is invalid or expired. Please check your server configuration."),
                    dismissButton: .default(Text("Update API Key")) {
                        coordinator.selectedTab = .catalogue
                    }
                )
            default:
                return Alert(title: Text("Error"))
            }
        }
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
            NavigationView {
                HomeView()
                    .applyAppBackground()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .id(coordinator.homeTabID)
            
        case .performers:
            NavigationView {
                PerformersView()
                    .applyAppBackground()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .id(coordinator.performersTabID)
            
        case .catalogue:
            NavigationView {
                CatalogsView()
                    .applyAppBackground()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .id(coordinator.catalogueTabID)
            
        case .downloads:
            NavigationView {
                DownloadsView()
                    .applyAppBackground()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .id(coordinator.downloadsTabID)
            
        case .reels:
            NavigationView {
                ReelsView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .id(coordinator.reelsTabID)
            
        case .settings:
            NavigationStack {
                ServerConfigView()
                    .applyAppBackground()
            }
            .id(coordinator.settingsTabID)
            
        default:
            EmptyView()
        }
    }
}

#Preview {
    MainTabView()
}
