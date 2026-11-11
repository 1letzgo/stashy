import SwiftUI

/// Settings › Server › stashy+ → Filters: list / create / edit / rename / delete all server saved filters.
struct FiltersToolsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared

    @State private var searchText = ""
    @State private var editingFilter: StashDBViewModel.SavedFilter?
    @State private var pendingEditAfterCreate: StashDBViewModel.SavedFilter?
    @State private var isCreating = false
    @State private var createMode: StashDBViewModel.FilterMode = .scenes
    @State private var renameTarget: StashDBViewModel.SavedFilter?
    @State private var renameText = ""
    @State private var deleteTarget: StashDBViewModel.SavedFilter?

    private static let listedModes: [StashDBViewModel.FilterMode] = [
        .scenes, .sceneMarkers, .performers, .studios, .tags, .galleries, .images, .groups
    ]

    private var filteredFilters: [StashDBViewModel.SavedFilter] {
        var list = Array(viewModel.savedFilters.values)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var grouped: [(mode: StashDBViewModel.FilterMode, filters: [StashDBViewModel.SavedFilter])] {
        Self.listedModes.compactMap { mode in
            let list = filteredFilters.filter { $0.mode == mode }
            guard !list.isEmpty else { return nil }
            return (mode, list)
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty {
                StandardLoadingView(message: tr("loading_filters"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground(for: appearance.currentTheme))
            } else if grouped.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground(for: appearance.currentTheme))
            } else {
                filtersList
            }
        }
        .modifier(FiltersToolsSearchChromeModifier(
            searchText: $searchText,
            addMenuItems: { addMenuItems }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground(for: appearance.currentTheme))
        .onAppear { viewModel.fetchSavedFilters() }
        .sheet(item: $editingFilter) { filter in
            FiltersToolsEditorSheet(
                filter: filter,
                viewModel: viewModel,
                onDismiss: { editingFilter = nil }
            )
        }
        .sheet(isPresented: $isCreating, onDismiss: {
            // Present the editor only after the create sheet is fully gone — chaining both in one
            // runloop leaves the second sheet unpresented on iOS.
            if let saved = pendingEditAfterCreate {
                pendingEditAfterCreate = nil
                editingFilter = saved
            }
        }) {
            FiltersToolsEditorSheet(
                filter: nil,
                createMode: createMode,
                viewModel: viewModel,
                onSaved: { saved in
                    pendingEditAfterCreate = saved
                    isCreating = false
                },
                onDismiss: { isCreating = false }
            )
        }
        .alert(tr("action_rename_filter"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(tr("name"), text: $renameText)
            Button(tr("action_save")) {
                guard let target = renameTarget else { return }
                rename(filter: target, to: renameText)
            }
            Button(tr("action_cancel"), role: .cancel) { renameTarget = nil }
        }
        .alert(tr("confirm_delete_filter"), isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button(tr("action_delete"), role: .destructive) {
                guard let target = deleteTarget else { return }
                delete(filter: target)
            }
            Button(tr("action_cancel"), role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { tr("confirm_delete_arg_from_server", $0.name) } ?? "")
        }
    }

    /// Shared "+" menu items for the inset button.
    @ViewBuilder
    private var addMenuItems: some View {
        ForEach(Self.listedModes, id: \.self) { mode in
            Button(Self.modeTitle(mode)) {
                createMode = mode
                isCreating = true
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? tr("empty_filters") : tr("empty_matches"),
            systemImage: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
            description: Text(searchText.isEmpty
                              ? tr("hint_create_filter_or_sync_from")
                              : tr("empty_filters_match_your_search"))
        )
    }

    private var filtersList: some View {
        List {
            ForEach(grouped, id: \.mode) { section in
                // Real section header, not a first row: as a row it would own the group's
                // rounded top and leave the first filter with square corners.
                Section {
                    ForEach(section.filters) { filter in
                        Button {
                            editingFilter = filter
                        } label: {
                            filterRowLabel(filter)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = filter
                            } label: {
                                Label(tr("action_delete"), systemImage: "trash")
                            }
                            Button {
                                renameTarget = filter
                                renameText = filter.name
                            } label: {
                                Label(tr("action_rename"), systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button {
                                renameTarget = filter
                                renameText = filter.name
                            } label: {
                                Label(tr("action_rename"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = filter
                            } label: {
                                Label(tr("action_delete"), systemImage: "trash")
                            }
                        }
                        // List rows default to system colors and would ignore the app theme.
                        .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                        .listRowSeparatorTint(Color.primary.opacity(0.15))
                    }
                } header: {
                    // Same small caps header the other Tools views and Settings use.
                    // Zero row insets: insetGrouped would otherwise indent the header
                    // further than the card edge it belongs to.
                    Text(Self.modeTitle(section.mode))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .listStyle(.insetGrouped)
        // Custom header rows replace the grouped section headers; without this the list
        // keeps the room reserved for them and the first group floats far below the search.
        .listSectionSpacing(DesignTokens.Spacing.md)
        .contentMargins(.top, DesignTokens.Spacing.sm, for: .scrollContent)
        // insetGrouped insets at 20pt; the other Tools sit at 16pt.
        .contentMargins(.horizontal, DesignTokens.Tools.contentPadding, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground(for: appearance.currentTheme))
        .refreshable { viewModel.fetchSavedFilters() }
    }

    private func filterRowLabel(_ filter: StashDBViewModel.SavedFilter) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Text(criteriaSummary(filter))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DesignTokens.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    static func modeTitle(_ mode: StashDBViewModel.FilterMode) -> String {
        switch mode {
        case .scenes: return tr("scenes")
        case .sceneMarkers: return tr("markers")
        case .performers: return tr("performers")
        case .studios: return tr("studios")
        case .tags: return tr("tags")
        case .galleries: return tr("galleries")
        case .images: return tr("images")
        case .groups: return tr("groups")
        case .unknown: return tr("other")
        }
    }

    /// Human-readable criteria list ("Tags, Rating, Studio"), not raw GraphQL keys.
    private func criteriaSummary(_ filter: StashDBViewModel.SavedFilter) -> String {
        let keys = filter.criteriaObjectFilter().keys.sorted()
        if keys.isEmpty { return tr("empty_criteria") }
        let labels = keys.map { key in
            FilterFieldCatalog.field(key: key, mode: filter.mode)?.label ?? key
        }
        return labels.prefix(4).joined(separator: ", ") + (labels.count > 4 ? "…" : "")
    }

    private func rename(filter: StashDBViewModel.SavedFilter, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.renameSavedFilter(filter, to: trimmed) { result in
            renameTarget = nil
            switch result {
            case .success:
                HapticManager.success()
                viewModel.fetchSavedFilters()
            case .failure(let error):
                ToastManager.shared.show(tr("action_rename_failed_arg", error.localizedDescription), icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private func delete(filter: StashDBViewModel.SavedFilter) {
        viewModel.destroySavedSceneFilter(id: filter.id) { result in
            deleteTarget = nil
            switch result {
            case .success:
                HapticManager.success()
                viewModel.fetchSavedFilters()
            case .failure(let error):
                ToastManager.shared.show(tr("action_delete_failed_arg", error.localizedDescription), icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }
}

/// Search + "+" chrome for the Filters list, pinned as a custom top inset.
private struct FiltersToolsSearchChromeModifier<MenuItems: View>: ViewModifier {
    @Binding var searchText: String
    @ViewBuilder var addMenuItems: () -> MenuItems

    @ObservedObject private var appearance = AppearanceManager.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ToolsSearchField(prompt: tr("search_filters"), text: $searchText)
                    Menu {
                        addMenuItems()
                    } label: {
                        ToolsAddButtonLabel()
                    }
                    .accessibilityLabel(tr("new_filter"))
                }
                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                .padding(.top, DesignTokens.Tools.menuTopPadding)
                .padding(.bottom, DesignTokens.Spacing.xs + 2)
                .background(Color.appBackground(for: appearance.currentTheme))
            }
    }
}

/// Create / edit one saved filter. One chrome bar, house style — no second action bar.
private struct FiltersToolsEditorSheet: View {
    var filter: StashDBViewModel.SavedFilter?
    var createMode: StashDBViewModel.FilterMode = .scenes
    @ObservedObject var viewModel: StashDBViewModel
    var onSaved: ((StashDBViewModel.SavedFilter) -> Void)? = nil
    var onDismiss: () -> Void

    @StateObject private var document: FilterCriteriaDocument
    @State private var name: String
    @State private var showSaveAs = false
    @State private var showSaveChoice = false
    @State private var saveAsName = ""
    @State private var showDelete = false
    @State private var isSaving = false
    /// Selected `FilterSortChoice.raw`. Empty when this mode has no sort catalog.
    @State private var selectedSortRaw: String
    @ObservedObject private var appearance = AppearanceManager.shared

    init(
        filter: StashDBViewModel.SavedFilter?,
        createMode: StashDBViewModel.FilterMode = .scenes,
        viewModel: StashDBViewModel,
        onSaved: ((StashDBViewModel.SavedFilter) -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.filter = filter
        self.createMode = createMode
        self.viewModel = viewModel
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        let mode = filter?.mode ?? createMode
        _document = StateObject(wrappedValue: FilterCriteriaDocument(
            mode: mode,
            objectFilter: filter?.criteriaObjectFilter() ?? [:]
        ))
        _name = State(initialValue: filter?.name ?? "")
        let resolved = FilterSortCatalog.choice(
            forRaw: filter?.stashySortRaw,
            pair: filter?.encodedSortPair,
            mode: mode
        )
        let fallback = Self.defaultSort(for: mode)
        _selectedSortRaw = State(initialValue: resolved?.raw
            ?? FilterSortCatalog.choice(forRaw: nil, pair: fallback, mode: mode)?.raw
            ?? FilterSortCatalog.choices(for: mode).first?.raw
            ?? "")
    }

    private var sortChoices: [FilterSortChoice] { FilterSortCatalog.choices(for: mode) }
    private var selectedSortChoice: FilterSortChoice? { sortChoices.first { $0.raw == selectedSortRaw } }

    private var mode: StashDBViewModel.FilterMode { filter?.mode ?? createMode }
    private var isExisting: Bool { filter != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                    Text(tr("name"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    TextField(tr("filter_name"), text: $name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                .catalogFilterSortControlCardChrome()

                if !sortChoices.isEmpty {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                        Text(tr("action_sort"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(sortChoices) { choice in
                                Button {
                                    selectedSortRaw = choice.raw
                                } label: {
                                    if choice.raw == selectedSortRaw {
                                        Label(choice.label, systemImage: "checkmark")
                                    } else {
                                        Text(choice.label)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xxs) {
                                Text(selectedSortChoice?.label ?? tr("action_select_menu"))
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .catalogFilterSortControlCardChrome()
                }

                // Title now lives in the editor's header row, sharing it with "Add group".
                FilterCriteriaEditorView(
                    document: document,
                    levelTitle: FiltersToolsView.modeTitle(mode)
                )
            }
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .stashyModalSheetChrome(isExisting ? tr("action_edit_filter") : tr("new_filter"), onBack: onDismiss) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Button {
                        showSaveChoice = true
                    } label: {
                        Text(tr("action_save"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(trimmedName.isEmpty || document.hasInvalidInput ? .white.opacity(0.4) : .white)
                            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                    }
                    .buttonStyle(.plain)
                    // An invalid date / half-typed number would be dropped silently on save.
                    .disabled((trimmedName.isEmpty && !isExisting) || document.hasInvalidInput)
                    // Gleicher Speichern-Dialog wie in den Filter-Sheets und bei Merge Tags/Studios.
                    .alert(tr("action_save_filter"), isPresented: $showSaveChoice) {
                        if isExisting {
                            Button(tr("action_update_arg", filter?.name ?? trimmedName)) {
                                save(existingId: filter?.id, saveName: trimmedName)
                            }
                            .disabled(trimmedName.isEmpty)
                        } else {
                            Button(tr("action_save")) { save(existingId: nil, saveName: trimmedName) }
                                .disabled(trimmedName.isEmpty)
                        }
                        Button(tr("action_save_as_new")) {
                            saveAsName = trimmedName.isEmpty ? "" : trimmedName + " copy"
                            showSaveAs = true
                        }
                        if isExisting {
                            Button(tr("action_delete"), role: .destructive) { showDelete = true }
                        }
                        Button(tr("action_cancel"), role: .cancel) {}
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .alert(tr("action_save_as_new"), isPresented: $showSaveAs) {
            TextField(tr("name"), text: $saveAsName)
            Button(tr("action_save")) { save(existingId: nil, saveName: saveAsName) }
            Button(tr("action_cancel"), role: .cancel) {}
        }
        .alert(tr("confirm_delete_filter"), isPresented: $showDelete) {
            Button(tr("action_delete"), role: .destructive) {
                guard let id = filter?.id else { return }
                viewModel.destroySavedSceneFilter(id: id) { result in
                    switch result {
                    case .success:
                        HapticManager.success()
                        viewModel.fetchSavedFilters()
                        onDismiss()
                    case .failure(let error):
                        ToastManager.shared.show(tr("action_delete_failed_arg", error.localizedDescription), icon: "exclamationmark.triangle.fill", style: .error)
                    }
                }
            }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: {
            Text(filter.map { tr("confirm_delete_arg_from_server", $0.name) } ?? "")
        }
    }

    private func save(existingId: String?, saveName: String) {
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        let choice = selectedSortChoice
        let pair = choice.map { (field: $0.field, direction: $0.direction) }
            ?? filter?.encodedSortPair
            ?? Self.defaultSort(for: mode)
        viewModel.saveFullObjectFilter(
            mode: mode,
            existingId: existingId,
            name: trimmed,
            sortField: pair.field.hasPrefix("random") ? "random" : pair.field,
            sortDirection: pair.direction,
            sortRaw: choice?.raw ?? filter?.stashySortRaw,
            objectFilter: document.sanitizedObjectFilter,
            randomSeedKind: StashDBViewModel.randomSeedKind(for: mode)
        ) { result in
            isSaving = false
            switch result {
            case .success(let saved):
                HapticManager.success()
                viewModel.fetchSavedFilters()
                if let onSaved {
                    onSaved(saved)
                } else {
                    onDismiss()
                }
            case .failure(let error):
                ToastManager.shared.show(tr("action_save_failed_arg", error.localizedDescription), icon: "exclamationmark.triangle.fill", style: .error)
            }
        }
    }

    private static func defaultSort(for mode: StashDBViewModel.FilterMode) -> (field: String, direction: String) {
        switch mode {
        case .performers, .tags, .studios: return ("name", "ASC")
        case .sceneMarkers: return ("seconds", "ASC")
        default: return ("date", "DESC")
        }
    }
}
