//
//  CatalogsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI

struct CatalogsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    enum CatalogsTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case scenes = "Scenes"
        case images = "Images"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .scenes: return "film"
            case .images: return "photo"
            case .galleries: return "photo.stack"
            case .performers: return "person.3"
            case .studios: return "building.2"
            case .tags: return "tag"
            }
        }
    }
    
    private var sortedVisibleTabs: [CatalogsTab] {
        tabManager.tabs
            .filter { ($0.id == .dashboard || $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { (config: TabConfig) -> CatalogsTab? in
                switch config.id {
                case .dashboard: return .dashboard
                case .scenes: return .scenes
                case .galleries: return .galleries
                case .performers: return .performers
                case .studios: return .studios
                case .tags: return .tags
                default: return nil
                }
            }
            .flatMap { (tab: CatalogsTab) -> [CatalogsTab] in
                if tab == .galleries {
                    return [.galleries, .images]
                }
                return [tab]
            }
    }
    
    private var selectedTabBinding: Binding<CatalogsTab> {
        Binding(
            get: { effectiveTab ?? .studios },
            set: { coordinator.catalogueSubTab = $0.rawValue }
        )
    }
    
    private var showTabSwitcher: Bool {
        sortedVisibleTabs.count > 1
    }
    
    private var effectiveTab: CatalogsTab? {
        let visible = sortedVisibleTabs
        
        // If current sub-tab is in visible list, use it
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), visible.contains(current) {
            return current
        }
        
        // Otherwise fallback to the first visible one (respecting sortOrder)
        return visible.first
    }
    
    private var effectiveTabRaw: String {
        coordinator.catalogueSubTab
    }
    
    var body: some View {
        Group {
            if let tab = effectiveTab {
                switch tab {
                case .dashboard:
                    HomeView()
                case .scenes:
                    ScenesView()
                case .images:
                    ImagesView()
                case .galleries:
                    GalleriesView()
                case .performers:
                    PerformersView()
                case .studios:
                    StudiosView(hideTitle: false)
                case .tags:
                    TagsView(hideTitle: false)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Please enable Dashboard, Performers, Studios or Tags in Settings")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .toolbar {
            if showTabSwitcher {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Dashboard", selection: selectedTabBinding) {
                            ForEach(sortedVisibleTabs, id: \.self) { tab in
                                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: effectiveTab?.icon ?? "square.grid.2x2")
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
