import SwiftUI

/// Tools → Filters: list / create / edit / rename / delete all server saved filters.
struct FiltersToolsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared

    @State private var searchText = ""
    @State private var editingFilter: StashDBViewModel.SavedFilter?
    @State private var isCreating = false
    @State private var createMode: StashDBViewModel.FilterMode = .scenes
    @State private var renameTarget: StashDBViewModel.SavedFilter?
    @State private var renameText = ""
    @State private var deleteTarget: StashDBViewModel.SavedFilter?

    private var filteredFilters: [StashDBViewModel.SavedFilter] {
        var list = Array(viewModel.savedFilters.values)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var grouped: [(mode: StashDBViewModel.FilterMode, filters: [StashDBViewModel.SavedFilter])] {
        let modes: [StashDBViewModel.FilterMode] = [
            .scenes, .sceneMarkers, .performers, .studios, .tags, .galleries, .images, .groups
        ]
        return modes.compactMap { mode in
            let list = filteredFilters.filter { $0.mode == mode }
            guard !list.isEmpty else { return nil }
            return (mode, list)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search filters", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Menu {
                    ForEach(createModes, id: \.self) { mode in
                        Button(modeTitle(mode)) {
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
            .padding(.vertical, 10)

            if viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty {
                StandardLoadingView(message: "Loading filters…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if grouped.isEmpty {
                ContentUnavailableView(
                    "No filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(searchText.isEmpty ? "Create a filter or sync from your Stash server." : "No filters match your search.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(grouped, id: \.mode) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(modeTitle(section.mode))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(section.filters.enumerated()), id: \.element.id) { index, filter in
                                        filterRow(filter)
                                        if index < section.filters.count - 1 {
                                            Divider().padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(Color.secondaryAppBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Tools.contentPadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .onAppear { viewModel.fetchSavedFilters() }
        .sheet(item: $editingFilter) { filter in
            FiltersToolsEditorSheet(
                filter: filter,
                onSaved: { saved in editingFilter = saved },
                onDismiss: { editingFilter = nil }
            )
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $isCreating) {
            FiltersToolsEditorSheet(
                filter: nil,
                createMode: createMode,
                onSaved: { saved in
                    isCreating = false
                    editingFilter = saved
                },
                onDismiss: { isCreating = false }
            )
            .environmentObject(viewModel)
        }
        .alert("Rename", isPresented: Binding(
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
                viewModel.destroySavedSceneFilter(id: target.id) { _ in
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { "Delete “\($0.name)” from the server?" } ?? "")
        }
    }

    private func filterRow(_ filter: StashDBViewModel.SavedFilter) -> some View {
        Button {
            editingFilter = filter
        } label: {
            HStack(spacing: 12) {
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
                Spacer(minLength: 8)
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createModes: [StashDBViewModel.FilterMode] {
        [.scenes, .sceneMarkers, .performers, .studios, .tags, .galleries, .images, .groups]
    }

    private func modeTitle(_ mode: StashDBViewModel.FilterMode) -> String {
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

    private func criteriaSummary(_ filter: StashDBViewModel.SavedFilter) -> String {
        let keys = filter.criteriaObjectFilter().keys.sorted()
        if keys.isEmpty { return "No criteria" }
        return keys.prefix(4).joined(separator: ", ") + (keys.count > 4 ? "…" : "")
    }

    private func rename(filter: StashDBViewModel.SavedFilter, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pair = filter.encodedSortPair ?? ("date", "DESC")
        viewModel.saveFullObjectFilter(
            mode: filter.mode,
            existingId: filter.id,
            name: trimmed,
            sortField: pair.field.hasPrefix("random") ? "random" : pair.field,
            sortDirection: pair.direction,
            sortRaw: filter.stashySortRaw,
            objectFilter: filter.criteriaObjectFilter(),
            randomSeedKind: randomSeedKind(for: filter.mode)
        ) { _ in
            renameTarget = nil
        }
    }

    private func randomSeedKind(for mode: StashDBViewModel.FilterMode) -> StashDBViewModel.RandomSeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .performers: return .performers
        case .studios: return .studios
        case .tags: return .tags
        case .galleries: return .galleries
        case .images: return .images
        case .groups: return .groups
        case .sceneMarkers: return .markers
        case .unknown: return nil
        }
    }
}

private struct FiltersToolsEditorSheet: View {
    var filter: StashDBViewModel.SavedFilter?
    var createMode: StashDBViewModel.FilterMode = .scenes
    var onSaved: (StashDBViewModel.SavedFilter) -> Void
    var onDismiss: () -> Void

    @EnvironmentObject private var viewModel: StashDBViewModel
    @StateObject private var document: FilterCriteriaDocument
    @State private var name: String
    @State private var showSaveAs = false
    @State private var saveAsName = ""
    @State private var showDelete = false
    @State private var isSaving = false

    init(
        filter: StashDBViewModel.SavedFilter?,
        createMode: StashDBViewModel.FilterMode = .scenes,
        onSaved: @escaping (StashDBViewModel.SavedFilter) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.filter = filter
        self.createMode = createMode
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        let mode = filter?.mode ?? createMode
        _document = StateObject(wrappedValue: FilterCriteriaDocument(
            mode: mode,
            objectFilter: filter?.criteriaObjectFilter() ?? [:]
        ))
        _name = State(initialValue: filter?.name ?? "New filter")
    }

    private var mode: StashDBViewModel.FilterMode { filter?.mode ?? createMode }
    private var hasSelectedPreset: Bool { filter != nil }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Name")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                        TextField("Filter name", text: $name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                    }
                    .catalogFilterSortControlCardChrome()

                    FilterCriteriaEditorView(document: document, onChange: {})
                }
                .padding(.top, 8)
            }
            .background(Color.appBackground)
            .catalogSettingsSheetChrome(
                hasSelectedPreset: hasSelectedPreset || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onReset: {
                    if let filter {
                        document.load(filter.criteriaObjectFilter())
                        name = filter.name
                    } else {
                        document.clear()
                        name = "New filter"
                    }
                },
                onRequestSave: { save(existingId: filter?.id, saveName: name) },
                onRequestSaveAs: {
                    saveAsName = name
                    showSaveAs = true
                },
                onRequestRename: {
                    // Rename = overwrite with current name field when editing existing.
                    guard filter != nil else { return }
                    save(existingId: filter?.id, saveName: name)
                },
                onRequestDelete: {
                    guard filter != nil else { return }
                    showDelete = true
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button("Close") { onDismiss() }
                        .foregroundColor(.secondary)
                    Spacer()
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save(existingId: filter?.id, saveName: name) }
                            .font(.body.weight(.semibold))
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
            .alert("Save As", isPresented: $showSaveAs) {
                TextField("Name", text: $saveAsName)
                Button("Save") { save(existingId: nil, saveName: saveAsName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete filter?", isPresented: $showDelete) {
                Button("Delete", role: .destructive) {
                    guard let id = filter?.id else { return }
                    viewModel.destroySavedSceneFilter(id: id) { _ in onDismiss() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationViewStyle(.stack)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(UIColor.systemGroupedBackground))
    }

    private func save(existingId: String?, saveName: String) {
        let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        let pair = filter?.encodedSortPair ?? defaultSort(for: mode)
        viewModel.saveFullObjectFilter(
            mode: mode,
            existingId: existingId,
            name: trimmed,
            sortField: pair.field.hasPrefix("random") ? "random" : pair.field,
            sortDirection: pair.direction,
            sortRaw: filter?.stashySortRaw,
            objectFilter: document.sanitizedObjectFilter,
            randomSeedKind: {
                switch mode {
                case .scenes: return .scenes
                case .performers: return .performers
                case .studios: return .studios
                case .tags: return .tags
                case .galleries: return .galleries
                case .images: return .images
                case .groups: return .groups
                case .sceneMarkers: return .markers
                case .unknown: return nil
                }
            }()
        ) { result in
            isSaving = false
            if case .success(let saved) = result {
                onSaved(saved)
            }
        }
    }

    private func defaultSort(for mode: StashDBViewModel.FilterMode) -> (field: String, direction: String) {
        switch mode {
        case .performers, .tags, .studios: return ("name", "ASC")
        case .sceneMarkers: return ("seconds", "ASC")
        default: return ("date", "DESC")
        }
    }
}
