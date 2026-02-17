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
    @State private var isSidebarFocused = false
    
    enum MenuTab: String, CaseIterable, Identifiable {
        case dashboard = "Home"
        case scenes = "Scenes"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case search = "Search"
        case settings = "Settings"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .scenes: return "film"
            case .performers: return "person.3.fill"
            case .studios: return "building.2.fill"
            case .tags: return "tag.fill"
            case .search: return "magnifyingglass"
            case .settings: return "gear"
            }
        }
    }
    
    @FocusState private var focusedTab: MenuTab?
    
    private let sidebarWidth: CGFloat = 110
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                headerSection
                
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                menuItemsSection
                
                Spacer()
            }
            .frame(width: sidebarWidth)
            .background(Color.black.opacity(0.95))
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
            
            // MARK: - Content
            contentArea
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
    
    // MARK: - Content Area
    
    @ViewBuilder
    private var contentArea: some View {
        NavigationStack {
            switch selectedTab {
            case .dashboard:
                TVDashboardView()
            case .scenes:
                TVScenesView()
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
    
    // MARK: - Header
    
    private var headerSection: some View {
        ZStack {
            Circle()
                .fill(appearanceManager.tintColor.opacity(0.2))
                .frame(width: 44, height: 44)
            
            Image(systemName: "play.tv.fill")
                .font(.title3)
                .foregroundColor(appearanceManager.tintColor)
        }
        .frame(height: 80)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }
    
    // MARK: - Menu Items
    
    private var menuItemsSection: some View {
        VStack(spacing: 12) {
            ForEach(MenuTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tab == focusedTab ? Color.white.opacity(0.15) : (selectedTab == tab ? appearanceManager.tintColor.opacity(0.15) : Color.clear))
                            .frame(width: 80, height: 56)
                        
                        Image(systemName: tab.icon)
                            .font(.system(size: 24, weight: (selectedTab == tab || tab == focusedTab) ? .semibold : .medium))
                            .foregroundColor(tab == focusedTab ? .white : (selectedTab == tab ? appearanceManager.tintColor : .white.opacity(0.4)))
                            .scaleEffect(tab == focusedTab ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focusedTab)
                    }
                }
                .buttonStyle(.plain)
                .focused($focusedTab, equals: tab)
            }
        }
        .padding(.horizontal, 12)
    }
}

struct TVMainTabView_Previews: PreviewProvider {
    static var previews: some View {
        TVMainTabView()
    }
}
