//
//  TVMainTabView.swift
//  stashyTV
//
//  Netflix/Amazon Prime style navigation with proper focus handling
//

import SwiftUI

struct TVMainTabView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var selectedTab: MenuTab = .dashboard
    
    enum MenuTab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case search = "Search"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .performers: return "person.3.fill"
            case .studios: return "building.2.fill"
            case .tags: return "tag.fill"
            case .search: return "magnifyingglass"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(MenuTab.allCases) { tab in
                NavigationStack {
                    contentArea(for: tab)
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
                .tag(tab)
            }
        }
    }
    
    @ViewBuilder
    private func contentArea(for tab: MenuTab) -> some View {
        switch tab {
        case .dashboard:
            TVDashboardView()
        case .performers:
            TVPerformersView()
        case .studios:
            TVStudiosView()
        case .tags:
            TVTagsView()
        case .search:
            TVSearchView()
        case .settings:
            TVSettingsView()
        }
    }
}

struct TVMainTabView_Previews: PreviewProvider {
    static var previews: some View {
        TVMainTabView()
    }
}
