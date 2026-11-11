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
    /// Channels are stashy+ — row toggle and the Channels section only show while unlocked.
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @ObservedObject private var forYou = SceneRecommendationEngine.shared
    @ObservedObject private var forgotten = ForgottenFavoritesEngine.shared
    /// Same key as the switch in Settings › stashy+, so either one updates the other.
    @AppStorage(MagazineMode.enabledKey) private var isMagazineEnabled = false
    @StateObject private var viewModel = StashDBViewModel()
    @State private var showAddRowSheet = false
    @State private var rowToRemove: HomeRowConfig?

    private var catalogTabs: [TabConfig] {
        tabManager.tabs
            .filter {
                $0.id == .scenes || $0.id == .galleries || $0.id == .performers ||
                $0.id == .studios || $0.id == .tags || $0.id == .images ||
                $0.id == .groups || $0.id == .markers ||
                ($0.id == .magazine && stashyPlus.isUnlocked)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                stashyScrollingSectionHeader(tr("dashboard"))
                dashboardCard
                    .stashySettingsCardRow()
            }

            Section {
                stashyScrollingSectionHeader(tr("home_tabs"))
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
                stashyScrollingSectionHeader(tr("visible_dashboard_rows"))
                ForEach(Array(visibleHomeRows.enumerated()), id: \.element.id) { index, row in
                    homeRowToggle(row)
                        .stashyGroupedBlockRow(index: index, count: visibleHomeRows.count + 1)
                }
                .onMove { indices, newOffset in
                    moveVisibleHomeRows(from: indices, to: newOffset)
                }
                // Tap gesture instead of a Button: a Button in a themed list row in edit mode
                // did not reliably register the tap.
                Label(tr("action_add_row"), systemImage: "plus.circle.fill")
                    .foregroundColor(appearanceManager.tintColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { showAddRowSheet = true }
                    .accessibilityAddTraits(.isButton)
                    .moveDisabled(true)
                .stashyGroupedBlockRow(index: visibleHomeRows.count, count: visibleHomeRows.count + 1)
            }

            if stashyPlus.isUnlocked {
                Section {
                    stashyScrollingSectionHeader(tr("channels"))
                    if channelSettingItems.isEmpty {
                        Text(viewModel.isLoadingSavedFilters ? tr("loading_filters") : tr("empty_saved_scene_or_image_filters"))
                            .foregroundColor(.secondary)
                            .stashyGroupedBlockRow(index: 0, count: 1)
                            .moveDisabled(true)
                    } else {
                        ForEach(Array(channelSettingItems.enumerated()), id: \.element.id) { index, item in
                            Toggle(isOn: Binding(
                                get: { item.isEnabled },
                                set: { _ in tabManager.toggleHomeChannelItem(item.id) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channelTitle(for: item))
                                    Text(item.destination.title)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tint(appearanceManager.tintColor)
                            .stashyGroupedBlockRow(index: index, count: channelSettingItems.count)
                        }
                        .onMove { indices, newOffset in
                            tabManager.moveHomeChannelItem(from: indices, to: newOffset)
                        }
                    }
                }
            }
        }
        .stashyMovableCardsList()
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("dashboard"))
        .onAppear {
            viewModel.fetchSavedFilters { _ in
                tabManager.syncHomeChannelItems(with: Array(viewModel.savedFilters.values))
            }
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            tabManager.syncHomeChannelItems(with: Array(newValue.values))
        }
        .sheet(isPresented: $showAddRowSheet) {
            DashboardAddCustomRowSheet(viewModel: viewModel)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appBackground)
        }
        .alert(tr("action_remove_row"), isPresented: Binding(
            get: { rowToRemove != nil },
            set: { if !$0 { rowToRemove = nil } }
        )) {
            Button(tr("action_remove"), role: .destructive) {
                if let row = rowToRemove { tabManager.removeCustomHomeRows(ids: [row.id]) }
                rowToRemove = nil
            }
            Button(tr("action_cancel"), role: .cancel) { rowToRemove = nil }
        } message: {
            Text(tr("hint_removes_arg_from_dashboard_saved", rowToRemove?.displayTitle ?? ""))
        }
    }

    /// Switch for one dashboard row; a custom row also names its filter and has a remove button.
    @ViewBuilder
    private func homeRowToggle(_ row: HomeRowConfig) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { row.isEnabled },
                set: { _ in tabManager.toggleHomeRow(row.id) }
            )) {
                if row.type == .customFilter {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayTitle)
                        Text(customRowSubtitle(row))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(row.displayTitle)
                }
            }
            .tint(appearanceManager.tintColor)

            if row.type == .customFilter {
                // Tap gesture instead of a Button: a Button inside a themed list row in edit
                // mode did not reliably register the tap.
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture { rowToRemove = row }
                    .accessibilityLabel(tr("action_remove_row"))
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func customRowSubtitle(_ row: HomeRowConfig) -> String {
        let kind: String
        switch row.filterMode {
        case .performers: kind = tr("performers")
        case .studios: kind = tr("studios")
        case .galleries: kind = tr("galleries")
        default: kind = tr("scenes")
        }
        if let id = row.filterId, let name = viewModel.savedFilters[id]?.name {
            return "\(kind) · \(name)"
        }
        if row.filterId == nil,
           let sort = StashDBViewModel.customRowSortOption(mode: row.filterMode, raw: row.sortRaw) {
            return "\(kind) · \(sort.name)"
        }
        return kind
    }

    /// Dashboard rows offered in Settings; the Channels row (stashy+) is hidden while locked.
    private var visibleHomeRows: [HomeRowConfig] {
        tabManager.homeRows.filter { row in
            if row.type.requiresStashyPlus && !stashyPlus.isUnlocked { return false }
            // For You comes with Settings › stashy+ › Recommendations.
            if row.type == .recommendations && !forYou.isFeatureOn { return false }
            if row.type == .forgottenFavorites && !forgotten.isFeatureOn { return false }
            return true
        }
    }

    /// Maps a move in `visibleHomeRows` onto `tabManager.homeRows` (hidden rows keep their place).
    private func moveVisibleHomeRows(from source: IndexSet, to destination: Int) {
        let visible = visibleHomeRows
        let all = tabManager.homeRows
        guard visible.count != all.count else {
            tabManager.moveHomeRow(from: source, to: destination)
            return
        }
        let fullSource = IndexSet(source.compactMap { i in
            visible.indices.contains(i) ? all.firstIndex(where: { $0.id == visible[i].id }) : nil
        })
        let fullDestination: Int
        if destination < visible.count {
            fullDestination = all.firstIndex(where: { $0.id == visible[destination].id }) ?? all.count
        } else if let last = visible.last, let lastIndex = all.firstIndex(where: { $0.id == last.id }) {
            fullDestination = lastIndex + 1
        } else {
            fullDestination = all.count
        }
        tabManager.moveHomeRow(from: fullSource, to: fullDestination)
    }

    private var channelSettingItems: [HomeChannelItemConfig] {
        tabManager.homeChannelItems.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func channelTitle(for item: HomeChannelItemConfig) -> String {
        viewModel.savedFilters[item.filterId]?.name ?? tr("filter")
    }

    private var dashboardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tr("dashboard"), systemImage: "house.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(appearanceManager.tintColor)
                Spacer()
                Text(tr("always_visible"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.vertical, 8)

            settingRow(tr("default_filter")) {
                CatalogDefaultFilterMenu(tab: .dashboard, viewModel: viewModel)
            }

            settingRow(tr("hero_background")) {
                Toggle("", isOn: Binding(
                    get: { tabManager.showDashboardHeroBackground },
                    set: { tabManager.showDashboardHeroBackground = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)

            settingRow(tr("hero_autoplay")) {
                Toggle("", isOn: Binding(
                    get: { tabManager.dashboardHeroAutoplay },
                    set: { tabManager.dashboardHeroAutoplay = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)

            settingRow(tr("compact_statistics")) {
                Toggle("", isOn: Binding(
                    get: { tabManager.useCompactStatistics },
                    set: { tabManager.useCompactStatistics = $0 }
                ))
                .labelsHidden()
                .tint(appearanceManager.tintColor)
            }
            .padding(.top, 4)

            settingRow(tr("colored_statistics")) {
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
                if tab.id == .magazine {
                    Toggle("", isOn: $isMagazineEnabled)
                        .labelsHidden()
                        .tint(appearanceManager.tintColor)
                } else {
                    Toggle("", isOn: Binding(
                        get: { tab.isVisible },
                        set: { _ in tabManager.toggle(tab.id) }
                    ))
                    .labelsHidden()
                    .tint(appearanceManager.tintColor)
                }
            }

            if tab.id == .magazine {
                if isMagazineEnabled {
                    Divider()
                        .padding(.vertical, 8)
                    settingRow(tr("default_filter")) {
                        MagazineDefaultFilterMenu(viewModel: viewModel)
                    }
                }
            } else if tab.isVisible {
                Divider()
                    .padding(.vertical, 8)

                if CatalogCardColumnScope.from(appTab: tab.id) != nil {
                    settingRow(tr("display")) {
                        CatalogCardColumnsMenu(tab: tab.id)
                    }
                    .padding(.bottom, 4)
                }

                if tab.id == .images {
                    settingRow(tr("autoplay")) {
                        ImagesFeedAutoplayToggle()
                    }
                    .padding(.bottom, 4)
                }

                if tab.id == .scenes {
                    settingRow(tr("studio_logos")) {
                        Toggle("", isOn: Binding(
                            get: { tabManager.sceneCardsShowStudioLogo },
                            set: { tabManager.sceneCardsShowStudioLogo = $0 }
                        ))
                        .labelsHidden()
                        .tint(appearanceManager.tintColor)
                    }
                    .padding(.bottom, 4)
                }

                if tab.id == .studios, StashServerCapabilities.supports032 {
                    settingRow(tr("counts_incl_sub_studios")) {
                        StudioCountsSubStudiosToggle()
                    }
                    .padding(.bottom, 4)
                }

                settingRow(tr("default_sort")) {
                    CatalogDefaultSortMenu(tab: tab.id)
                }

                settingRow(tr("default_filter")) {
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
                    settingRow(tr("opened_gallery")) {
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

/// Add Row sheet: Filter or Sort, the kind, then a saved filter of that kind or one of the
/// kind's sort options, and an optional title.
private struct DashboardAddCustomRowSheet: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss
    private enum Source: Hashable { case filter, sort }
    @State private var source: Source = .filter
    @State private var mode: StashDBViewModel.FilterMode = .scenes
    @State private var selectedId: String?
    @State private var selectedSortRaw: String?
    @State private var title = ""
    /// The name last put into `title` automatically; a title the user changed is left alone.
    @State private var autoTitle = ""

    private static var modes: [(mode: StashDBViewModel.FilterMode, title: String)] {
[
        (.scenes, tr("scenes")), (.performers, tr("performers")), (.studios, tr("studios")), (.galleries, tr("galleries"))
    ]
    }

    private var filters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == mode }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedFilter: StashDBViewModel.SavedFilter? {
        selectedId.flatMap { viewModel.savedFilters[$0] }
    }

    /// The sort options the kind's own list offers.
    private var sortOptions: [(raw: String, name: String)] {
        typealias VM = StashDBViewModel
        switch mode {
        case .performers: return VM.PerformerSortOption.allCases.map { ($0.rawValue, $0.displayName) }
        case .studios: return VM.StudioSortOption.availableCases.map { ($0.rawValue, $0.displayName) }
        case .galleries: return VM.GallerySortOption.availableCases.map { ($0.rawValue, $0.displayName) }
        default: return VM.SceneSortOption.generalCases.map { ($0.rawValue, $0.displayName) }
        }
    }

    private var canAdd: Bool {
        source == .filter ? selectedFilter != nil : selectedSortRaw != nil
    }

    private func checkRow(_ name: String, selected: Bool, index: Int, count: Int, action: @escaping () -> Void) -> some View {
        // Plain row with a tap gesture: a Button in a themed row did not
        // reliably register the tap.
        HStack {
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .foregroundColor(appearanceManager.tintColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .stashyGroupedBlockRow(index: index, count: count)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stashyScrollingSectionHeader(tr("build_from"))
                    Picker(tr("build_from"), selection: $source) {
                        Text(tr("filter")).tag(Source.filter)
                        Text(tr("action_sort")).tag(Source.sort)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .stashyGroupedBlockRow(index: 0, count: 1)
                }

                Section {
                    stashyScrollingSectionHeader(tr("kind"))
                    Picker(tr("kind"), selection: $mode) {
                        ForEach(Self.modes, id: \.mode) { Text($0.title).tag($0.mode) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .stashyGroupedBlockRow(index: 0, count: 1)
                }

                if source == .filter {
                    Section {
                        stashyScrollingSectionHeader(tr("saved_filter"))
                        let list = filters
                        if list.isEmpty {
                            Text(viewModel.isLoadingSavedFilters
                                 ? tr("loading_filters")
                                 : tr("hint_no_saved_filters_of_this"))
                                .foregroundColor(.secondary)
                                .stashyGroupedBlockRow(index: 0, count: 1)
                        } else {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, filter in
                                checkRow(filter.name, selected: selectedId == filter.id,
                                         index: index, count: list.count) { select(filter) }
                            }
                        }
                    }
                } else {
                    Section {
                        stashyScrollingSectionHeader(tr("action_sort"))
                        let list = sortOptions
                        ForEach(Array(list.enumerated()), id: \.element.raw) { index, option in
                            checkRow(option.name, selected: selectedSortRaw == option.raw,
                                     index: index, count: list.count) { select(sort: option) }
                        }
                    }
                }

                Section {
                    stashyScrollingSectionHeader(tr("title"))
                    TextField(tr("title"), text: $title)
                        .stashyGroupedBlockRow(index: 0, count: 1)
                }

                Section {
                    Button(action: add) {
                        Text(tr("action_add"))
                            .font(.headline)
                            .foregroundColor(Color.onAppTint)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(appearanceManager.tintColor,
                                        in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .stashySettingsList()
            .applyAppBackground()
            .stashyModalSheetChrome(tr("action_add_row"), onBack: { dismiss() })
        }
        .onChange(of: mode) { _, _ in clearSelection() }
        .onChange(of: source) { _, _ in clearSelection() }
    }

    private func clearSelection() {
        selectedId = nil
        selectedSortRaw = nil
        if title == autoTitle { title = "" }
        autoTitle = ""
    }

    private func select(_ filter: StashDBViewModel.SavedFilter) {
        selectedId = filter.id
        setAutoTitle(defaultTitle(for: filter.name))
    }

    private func select(sort option: (raw: String, name: String)) {
        selectedSortRaw = option.raw
        setAutoTitle(defaultTitle(for: option.name))
    }

    private func setAutoTitle(_ name: String) {
        if title.isEmpty || title == autoTitle { title = name }
        autoTitle = name
    }

    /// "Scenes - <filter or sort>", like the shipped rows ("Scenes - Last Played").
    private func defaultTitle(for name: String) -> String {
        let kind = Self.modes.first { $0.mode == mode }?.title ?? ""
        return kind.isEmpty ? name : "\(kind) - \(name)"
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .filter {
            guard let filter = selectedFilter else { return }
            TabManager.shared.addCustomHomeRow(title: trimmed.isEmpty ? defaultTitle(for: filter.name) : trimmed,
                                               mode: mode, filterId: filter.id)
        } else {
            guard let option = sortOptions.first(where: { $0.raw == selectedSortRaw }) else { return }
            TabManager.shared.addCustomHomeRow(title: trimmed.isEmpty ? defaultTitle(for: option.name) : trimmed,
                                               mode: mode, filterId: nil, sortRaw: option.raw)
        }
        dismiss()
    }
}

struct CatalogDefaultSortMenu: View {
    let tab: AppTab
    @ObservedObject var tabManager = TabManager.shared

    var body: some View {
        switch tab {
        case .scenes:
            sortMenu(
                StashDBViewModel.SceneSortOption.generalCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.SceneSortOption.dateDesc.rawValue
            )
        case .performers:
            sortMenu(
                StashDBViewModel.PerformerSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.PerformerSortOption.sceneCountDesc.rawValue
            )
        case .studios:
            sortMenu(
                StashDBViewModel.StudioSortOption.availableCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.StudioSortOption.sceneCountDesc.rawValue
            )
        case .galleries:
            sortMenu(
                StashDBViewModel.GallerySortOption.availableCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.GallerySortOption.dateDesc.rawValue
            )
        case .tags:
            sortMenu(
                StashDBViewModel.TagSortOption.allCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.TagSortOption.sceneCountDesc.rawValue
            )
        case .images:
            sortMenu(
                StashDBViewModel.ImageSortOption.availableCases.map { ($0.rawValue, $0.displayName) },
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

private struct StudioCountsSubStudiosToggle: View {
    @AppStorage(StudioCountsStore.includeSubStudiosKey) private var includeSubStudios = false
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        Toggle("", isOn: $includeSubStudios)
            .labelsHidden()
            .tint(appearanceManager.tintColor)
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
                StashDBViewModel.ImageSortOption.availableCases.map { ($0.rawValue, $0.displayName) },
                fallback: StashDBViewModel.ImageSortOption.dateDesc.rawValue
            )
        } else {
            // Groups also sort by scene number (picked on the group page), so offer those too.
            let cases = context == .group
                ? StashDBViewModel.SceneSortOption.availableCases.filter { $0 != .forYou }
                : StashDBViewModel.SceneSortOption.generalCases
            sortMenu(
                cases.map { ($0.rawValue, $0.displayName) },
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
