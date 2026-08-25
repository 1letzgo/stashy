import SwiftUI

/// Tools → Filters: list / create / edit / rename / delete all server saved filters.
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
                StandardLoadingView(message: "Loading filters…")
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search filters", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs + 2)
                .background(Color.secondaryAppBackground(for: appearance.currentTheme))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                Menu {
                    ForEach(Self.listedModes, id: \.self) { mode in
                        Button(Self.modeTitle(mode)) {
                            createMode = mode
                            isCreating = true
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                        .background(appearance.tintColor)
                        .clipShape(Circle())
                }
                .accessibilityLabel("New filter")
            }
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
            .padding(.vertical, DesignTokens.Spacing.xs + 2)
            .background(Color.appBackground(for: appearance.currentTheme))
        }
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
        .alert("Rename filter", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                guard let target = renameTarget else { return }
                rename(filter: target, to: renameText)
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete filter?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let target = deleteTarget else { return }
                delete(filter: target)
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { "Delete “\($0.name)” from the server?" } ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "No filters" : "No matches",
            systemImage: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass",
            description: Text(searchText.isEmpty
                              ? "Create a filter or sync from your Stash server."
                              : "No filters match your search.")
        )
    }

    private var filtersList: some View {
        List {
            ForEach(grouped, id: \.mode) { section in
                Section(Self.modeTitle(section.mode)) {
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
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                renameTarget = filter
                                renameText = filter.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button {
                                renameTarget = filter
                                renameText = filter.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = filter
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // List rows default to system colors and would ignore the app theme.
                        .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                        .listRowSeparatorTint(Color.primary.opacity(0.15))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        case .scenes: return "Scenes"
        case .sceneMarkers: return "Markers"
        case .performers: return "Performers"
        case .studios: return "Studios"
        case .tags: return "Tags"
        case .galleries: return "Galleries"
        case .images: return "Images"
        case .groups: return "Groups"
        case .unknown: return "Other"
        }
    }

    /// Human-readable criteria list ("Tags, Rating, Studio"), not raw GraphQL keys.
    private func criteriaSummary(_ filter: StashDBViewModel.SavedFilter) -> String {
        let keys = filter.criteriaObjectFilter().keys.sorted()
        if keys.isEmpty { return "No criteria" }
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
                ToastManager.shared.show("Rename failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
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
                ToastManager.shared.show("Delete failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
            }
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
                    Text("Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    TextField("Filter name", text: $name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                .catalogFilterSortControlCardChrome()

                if !sortChoices.isEmpty {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                        Text("Sort")
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
                                Text(selectedSortChoice?.label ?? "Select…")
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .catalogFilterSortControlCardChrome()
                }

                Text(FiltersToolsView.modeTitle(mode))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.md + DesignTokens.Spacing.xxs)

                FilterCriteriaEditorView(document: document)
            }
            .padding(.top, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .stashyModalSheetChrome(isExisting ? "Edit filter" : "New filter", onBack: onDismiss) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Menu {
                        Button {
                            save(existingId: filter?.id, saveName: trimmedName)
                        } label: {
                            Label("Save", systemImage: "arrow.down.doc")
                        }
                        .disabled(trimmedName.isEmpty)
                        Button {
                            saveAsName = trimmedName.isEmpty ? "" : trimmedName + " copy"
                            showSaveAs = true
                        } label: {
                            Label("Save as…", systemImage: "doc.badge.plus")
                        }
                        if isExisting {
                            Divider()
                            Button(role: .destructive) { showDelete = true } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Text("Save")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(trimmedName.isEmpty ? .white.opacity(0.4) : .white)
                            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                    }
                    .disabled(trimmedName.isEmpty && !isExisting)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .alert("Save as", isPresented: $showSaveAs) {
            TextField("Name", text: $saveAsName)
            Button("Save") { save(existingId: nil, saveName: saveAsName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete filter?", isPresented: $showDelete) {
            Button("Delete", role: .destructive) {
                guard let id = filter?.id else { return }
                viewModel.destroySavedSceneFilter(id: id) { result in
                    switch result {
                    case .success:
                        HapticManager.success()
                        viewModel.fetchSavedFilters()
                        onDismiss()
                    case .failure(let error):
                        ToastManager.shared.show("Delete failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(filter.map { "Delete “\($0.name)” from the server?" } ?? "")
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
                ToastManager.shared.show("Save failed: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill", style: .error)
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
