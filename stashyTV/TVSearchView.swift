//
//  TVSearchView.swift
//  stashyTV
//
//  Search for tvOS — Netflix style
//

import SwiftUI

@MainActor
struct TVSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared

    @State private var searchQuery: String = ""
    @State private var hasSearched: Bool = false
    @State private var didAutoFocusSearchField: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var isSearchBusy: Bool {
        viewModel.isLoadingScenes || viewModel.isLoadingPerformers ||
        viewModel.isLoadingStudios || viewModel.isLoadingTags ||
        viewModel.isLoadingGroups
    }

    private var hasAnyResults: Bool {
        !viewModel.scenes.isEmpty || !viewModel.performers.isEmpty ||
        !viewModel.studios.isEmpty || !viewModel.tags.isEmpty ||
        !viewModel.groups.isEmpty
    }

    var body: some View {
        Group {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") {
                    viewModel.testConnection()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 44) {
                        searchBar

                        if isSearchBusy && !hasAnyResults {
                            loadingBlock
                        } else if hasSearched && !hasAnyResults {
                            emptyResultsBlock
                        } else if hasSearched {
                            if !viewModel.scenes.isEmpty { scenesResultSection.focusSection() }
                            if !viewModel.performers.isEmpty { performersResultSection.focusSection() }
                            if !viewModel.studios.isEmpty { studiosResultSection.focusSection() }
                            if !viewModel.tags.isEmpty { tagsResultSection.focusSection() }
                            if !viewModel.groups.isEmpty { groupsResultSection.focusSection() }
                        } else {
                            placeholderBlock
                        }
                    }
                    .padding(.vertical, 48)
                    .padding(.horizontal, 40)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
            }
        }
        .background(Color.appBackground)
        .task {
            // Only autofocus on first visit of this tab instance — not when
            // returning from a pushed detail (avoids stealing focus from results).
            guard !didAutoFocusSearchField else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            isSearchFieldFocused = true
            didAutoFocusSearchField = true
        }
        .onChange(of: searchQuery) { _, newValue in
            scheduleDebouncedSearch(newValue)
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
    }

    // MARK: - Search bar (eigenes Feld: Fokus bleibt erreichbar, kein „Festfrieren“ hinter .searchable)

    private var searchBar: some View {
        HStack(alignment: .center, spacing: 28) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Scenes, Performers …", text: $searchQuery)
                .font(.title3)
                .foregroundStyle(.primary)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .onSubmit { commitSearchImmediately() }

            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchDebounceTask?.cancel()
                    searchQuery = ""
                    hasSearched = false
                    viewModel.clearSearchResults()
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear input")
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var loadingBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Searching …")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    private var emptyResultsBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("No results for \"\(searchQuery)\"")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Refine Search") {
                    isSearchFieldFocused = true
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    private var placeholderBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("Search your Stash library")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Type at least two characters. Remote or dictation supported.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Debounce & ausführen

    private func scheduleDebouncedSearch(_ raw: String) {
        searchDebounceTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            viewModel.clearSearchResults()
            hasSearched = false
            return
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            runSearch(trimmed: trimmed)
        }
    }

    private func commitSearchImmediately() {
        searchDebounceTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            viewModel.clearSearchResults()
            hasSearched = false
            return
        }
        runSearch(trimmed: trimmed)
    }

    private func runSearch(trimmed: String) {
        hasSearched = true
        viewModel.fetchScenes(sortBy: .dateDesc, searchQuery: trimmed)
        viewModel.fetchPerformers(sortBy: .nameAsc, searchQuery: trimmed)
        viewModel.fetchStudios(sortBy: .nameAsc, searchQuery: trimmed)
        viewModel.fetchTags(sortBy: .nameAsc, searchQuery: trimmed)
        viewModel.fetchGroups(sortBy: .nameAsc, searchQuery: trimmed)
    }

    // MARK: - Scenes Results

    private var scenesResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Scenes")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.scenes.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }

                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: 400)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Studios / Tags / Groups / Galleries Results

    private var studiosResultSection: some View {
        resultSection(title: "Studios", systemImage: "building.2.fill", count: viewModel.studios.count) {
            ForEach(viewModel.studios) { studio in
                TVNavButton(value: TVStudioLink(id: studio.id, name: studio.name)) {
                    TVStudioCardView(studio: studio)
                }
            }
        }
    }

    private var tagsResultSection: some View {
        resultSection(title: "Tags", systemImage: "tag.fill", count: viewModel.tags.count) {
            ForEach(viewModel.tags) { tag in
                TVNavButton(value: TVTagLink(id: tag.id, name: tag.name)) {
                    TVTagCardView(tag: tag)
                }
            }
        }
    }

    private var groupsResultSection: some View {
        resultSection(title: "Groups", systemImage: "rectangle.stack.fill", count: viewModel.groups.count) {
            ForEach(viewModel.groups) { group in
                TVNavButton(value: TVGroupLink(id: group.id, name: group.name)) {
                    TVGroupCardView(group: group)
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(title: String, systemImage: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text(title)
                    .font(.title2).fontWeight(.bold).foregroundColor(.white)
                Text("\(count)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    content()
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Performers Results

    private var performersResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Performers")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.performers.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.performers) { performer in
                        TVNavButton(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            TVPerformerCardView(performer: performer)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
