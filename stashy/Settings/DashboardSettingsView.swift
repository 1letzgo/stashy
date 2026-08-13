//
//  DashboardSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()

    private var catalogTabs: [TabConfig] {
        tabManager.tabs
            .filter {
                $0.id == .scenes || $0.id == .galleries || $0.id == .performers ||
                $0.id == .studios || $0.id == .tags || $0.id == .images ||
                $0.id == .groups || $0.id == .markers
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                stashyScrollingSectionHeader("Dashboard")
                dashboardCard
                    .stashySettingsCardRow()
            }

            Section {
                stashyScrollingSectionHeader("Home Tabs")
                ForEach(catalogTabs) { tab in
                    catalogTabCard(tab)
                        .stashySettingsCardRow()
                }
                .onMove { indices, newOffset in
                    var adjustedIndices = IndexSet()
                    for index in indices {
                        adjustedIndices.insert(index + 1)
                    }
                    tabManager.moveSubTab(from: adjustedIndices, to: newOffset + 1, within: .catalogue)
                }
            }

            Section {
                stashyScrollingSectionHeader("Visible Dashboard Rows")
                ForEach(Array(tabManager.homeRows.enumerated()), id: \.element.id) { index, row in
                    Toggle(isOn: Binding(
                        get: { row.isEnabled },
                        set: { _ in tabManager.toggleHomeRow(row.id) }
                    )) {
                        Text(row.title)
                    }
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedBlockRow(index: index, count: tabManager.homeRows.count)
                }
                .onMove { indices, newOffset in
                    tabManager.moveHomeRow(from: indices, to: newOffset)
                }
            }
        }
        .stashyMovableCardsList()
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .applyAppBackground()
        .stashySettingsDetailChrome("Dashboard")
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    private var dashboardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Dashboard", systemImage: "house.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(appearanceManager.tintColor)
                Spacer()
                Text("Always Visible")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.vertical, 8)

            settingRow("Default Filter") {
                CatalogDefaultFilterMenu(tab: .dashboard, viewModel: viewModel)
            }

            settingRow("Hero Background") {
                Toggle("", isOn: Binding(
                    get: { tabManager.showDashboardHeroBackground },
                    set: { tabManager.showDashboardHeroBackground = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)

            settingRow("Compact Statistics") {
                Toggle("", isOn: Binding(
                    get: { tabManager.useCompactStatistics },
                    set: { tabManager.useCompactStatistics = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)

            settingRow("Colored Statistics") {
                Toggle("", isOn: Binding(
                    get: { tabManager.useColoredStatistics },
                    set: { tabManager.useColoredStatistics = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private func catalogTabCard(_ tab: TabConfig) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tab.id.title, systemImage: tab.id.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(appearanceManager.tintColor)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { tab.isVisible },
                    set: { _ in tabManager.toggle(tab.id) }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }

            if tab.isVisible {
                Divider()
                    .padding(.vertical, 8)

                if CatalogCardColumnScope.from(appTab: tab.id) != nil {
                    settingRow("Display") {
                        CatalogCardColumnsMenu(tab: tab.id)
                    }
                    .padding(.bottom, 4)
                }

                if tab.id == .images {
                    settingRow("Autoplay") {
                        ImagesFeedAutoplayToggle()
                    }
                    .padding(.bottom, 4)
                }

                settingRow("Default Sort") {
                    CatalogDefaultSortMenu(tab: tab.id)
                }

                settingRow("Default Filter") {
                    CatalogDefaultFilterMenu(tab: tab.id, viewModel: viewModel)
                }
                .padding(.top, 4)

                if let detail = CatalogDetailSortMenu.context(for: tab.id) {
                    settingRow(detail.settingsRowTitle) {
                        CatalogDetailSortMenu(context: detail)
                    }
                    .padding(.top, 4)
                }

                if tab.id == .galleries {
                    settingRow("Opened Gallery") {
                        CatalogCardColumnsMenu(scope: .openedGallery)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func settingRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 36)
    }
}

struct CatalogDefaultSortMenu: View {
    let tab: AppTab
    @ObservedObject var tabManager = TabManager.shared

    var body: some View {
        switch tab {
        case .scenes:
            sortMenu(
                StashDBViewModel.SceneSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.SceneSortOption.dateDesc.rawValue
            )
        case .performers:
            sortMenu(
                StashDBViewModel.PerformerSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.PerformerSortOption.sceneCountDesc.rawValue
            )
        case .studios:
            sortMenu(
                StashDBViewModel.StudioSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.StudioSortOption.sceneCountDesc.rawValue
            )
        case .galleries:
            sortMenu(
                StashDBViewModel.GallerySortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.GallerySortOption.dateDesc.rawValue
            )
        case .tags:
            sortMenu(
                StashDBViewModel.TagSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.TagSortOption.sceneCountDesc.rawValue
            )
        case .images:
            sortMenu(
                StashDBViewModel.ImageSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.ImageSortOption.dateDesc.rawValue
            )
        case .groups:
            sortMenu(
                StashDBViewModel.GroupSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.GroupSortOption.nameAsc.rawValue
            )
        case .markers:
            sortMenu(
                StashDBViewModel.SceneMarkerSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.SceneMarkerSortOption.createdAtDesc.rawValue
            )
        default:
            EmptyView()
        }
    }

    private func sortMenu(_ options: [(id: String, name: String)], fallback: String) -> some View {
        let current = tabManager.getPersistentSortOption(for: tab) ?? fallback
        return Menu {
            ForEach(options, id: \.id) { option in
                Button {
                    tabManager.setPersistentSortOption(for: tab, option: option.id)
                } label: {
                    HStack {
                        Text(option.name)
                        if option.id == current { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text(options.first(where: { $0.id == current })?.name ?? current)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct CatalogCardColumnsMenu: View {
    var tab: AppTab? = nil
    var scope: CatalogCardColumnScope? = nil
    @ObservedObject var tabManager = TabManager.shared

    private var resolvedScope: CatalogCardColumnScope? {
        scope ?? tab.flatMap { CatalogCardColumnScope.from(appTab: $0) }
    }

    var body: some View {
        if let resolvedScope {
            columnsMenu(for: resolvedScope)
        }
    }

    private func columnsMenu(for scope: CatalogCardColumnScope) -> some View {
        let current = tabManager.catalogCardColumns(for: scope)
        return Menu {
            ForEach(CatalogCardColumns.allCases, id: \.self) { option in
                Button {
                    tabManager.setCatalogCardColumns(option, for: scope)
                } label: {
                    HStack {
                        Text(option.settingsLabel)
                        if option == current { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text(current.settingsLabel)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct ImagesFeedAutoplayToggle: View {
    @AppStorage("images_feed_video_autoplay") private var videoAutoplay = true
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Toggle("", isOn: $videoAutoplay)
            .labelsHidden()
            .tint(appearanceManager.tintColor)
    }
}

struct CatalogDetailSortMenu: View {
    let context: DetailViewContext
    @ObservedObject var tabManager = TabManager.shared

    static func context(for tab: AppTab) -> DetailViewContext? {
        switch tab {
        case .performers: return .performer
        case .studios: return .studio
        case .tags: return .tag
        case .galleries: return .gallery
        case .groups: return .group
        default: return nil
        }
    }

    var body: some View {
        if context == .gallery {
            sortMenu(
                StashDBViewModel.ImageSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.ImageSortOption.dateDesc.rawValue
            )
        } else {
            sortMenu(
                StashDBViewModel.SceneSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.SceneSortOption.dateDesc.rawValue
            )
        }
    }

    private func sortMenu(_ options: [(id: String, name: String)], fallback: String) -> some View {
        let current = tabManager.getPersistentDetailSortOption(for: context.rawValue) ?? fallback
        return Menu {
            ForEach(options, id: \.id) { option in
                Button {
                    tabManager.setPersistentDetailSortOption(for: context.rawValue, option: option.id)
                } label: {
                    HStack {
                        Text(option.name)
                        if option.id == current { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text(options.first(where: { $0.id == current })?.name ?? current)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
#endif
