//
//  DefaultFilterView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct CatalogDefaultFilterMenu: View {
    let tab: AppTab
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared

    var body: some View {
        if tab == .markers {
            markerMenu
        } else if let mode = filterMode {
            standardMenu(mode: mode)
        }
    }

    private var filterMode: StashDBViewModel.FilterMode? {
        switch tab {
        case .scenes, .reels, .dashboard: return .scenes
        case .performers: return .performers
        case .studios: return .studios
        case .galleries: return .galleries
        case .images: return .images
        case .tags: return .tags
        case .groups: return .groups
        default: return nil
        }
    }

    private var markerMenu: some View {
        let filters = viewModel.savedFilters.values
            .filter { $0.mode == .sceneMarkers }
            .sorted { $0.name < $1.name }
        let current = tabManager.getDefaultMarkerFilterId(for: .markers) ?? ""
        return filterMenu(
            filters: filters,
            currentId: current,
            setNone: { tabManager.setDefaultMarkerFilter(for: .markers, filterId: nil, filterName: nil) },
            setFilter: { tabManager.setDefaultMarkerFilter(for: .markers, filterId: $0.id, filterName: $0.name) }
        )
    }

    private func standardMenu(mode: StashDBViewModel.FilterMode) -> some View {
        let filters = viewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name < $1.name }
        let current = tabManager.getDefaultFilterId(for: tab) ?? ""
        return filterMenu(
            filters: filters,
            currentId: current,
            setNone: { tabManager.setDefaultFilter(for: tab, filterId: nil, filterName: nil) },
            setFilter: { tabManager.setDefaultFilter(for: tab, filterId: $0.id, filterName: $0.name) }
        )
    }

    @ViewBuilder
    private func filterMenu(
        filters: [StashDBViewModel.SavedFilter],
        currentId: String,
        setNone: @escaping () -> Void,
        setFilter: @escaping (StashDBViewModel.SavedFilter) -> Void
    ) -> some View {
        if filters.isEmpty && !viewModel.isLoadingSavedFilters {
            Text("No filters found")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else {
            Menu {
                Button(action: setNone) {
                    HStack { Text("None"); if currentId.isEmpty { Image(systemName: "checkmark") } }
                }
                if !filters.isEmpty { Divider() }
                ForEach(filters) { filter in
                    Button { setFilter(filter) } label: {
                        HStack { Text(filter.name); if filter.id == currentId { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                Text(filters.first(where: { $0.id == currentId })?.name ?? "None")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
#endif
