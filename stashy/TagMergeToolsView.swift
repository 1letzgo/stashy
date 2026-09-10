//
//  TagMergeToolsView.swift
//  stashy
//
//  Tools → Merge Tags: mehrere Tags auf einen einzigen zusammenführen.
//

import SwiftUI

/// Führt Tags zusammen: alles, was an den Quell-Tags hängt (Szenen, Bilder,
/// Galerien, Performer und Marker — Primär- wie Zusatz-Tag), zeigt danach auf den
/// Ziel-Tag; die Quellen sind weg.
///
/// Die Umschreibung macht der Server (`tagsMerge`), nicht die App. Ein Aufruf
/// statt hunderter Einzelmutationen, und der Server bleibt dabei konsistent.
struct TagMergeToolsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var configManager = ServerConfigManager.shared

    /// Einmal laden, dann lokal filtern — wie im Tag-Editor der Szenenseite.
    /// Serverseitig pro Tastendruck zu suchen leerte die Liste bei jedem Zeichen.
    @State private var allTags: [Tag] = []
    @State private var isLoading = false
    /// Weitere Serverseiten laufen noch ein, die erste ist aber schon da.
    @State private var isLoadingMorePages = false
    /// Wächst beim Scrollen. Alle Treffer auf einmal zu rendern macht die Liste zäh.
    @State private var visibleCount = Self.pageSize
    @State private var searchText = ""
    @State private var sources: Set<String> = []
    @State private var destination: Tag?
    @State private var showingDestinationPicker = false
    @State private var showingConfirmation = false
    @State private var isMerging = false

    private let repository = TagRepository()

    /// Zeilen, die gleichzeitig gerendert werden. Alles anzuzeigen macht das Formular
    /// bei ein paar tausend Tags zäh; der Rest kommt über die Suche.
    /// Zeilen, die pro Nachladeschritt dazukommen.
    static let pageSize = 50

    /// Ausgewählte zuerst: mit nur 30 sichtbaren Zeilen entscheidet die Reihenfolge,
    /// was überhaupt erreichbar bleibt.
    private var filtered: [Tag] {
        let base = allTags.filter { $0.id != destination?.id }
        let matches = searchText.isEmpty
            ? base
            : base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return matches.sorted { lhs, rhs in
            let lhsSelected = sources.contains(lhs.id)
            let rhsSelected = sources.contains(rhs.id)
            if lhsSelected != rhsSelected { return lhsSelected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedSources: [Tag] {
        allTags.filter { sources.contains($0.id) }
    }

    private var canMerge: Bool {
        destination != nil && !sources.isEmpty && !isMerging
    }

    private var hasSelection: Bool {
        destination != nil || !sources.isEmpty || !searchText.isEmpty
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { load() }
            } else {
                tagListCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
        .safeAreaInset(edge: .top) { pinnedHeader }
        .safeAreaInset(edge: .bottom) { mergeBar }
        .onAppear {
            if allTags.isEmpty { load() }
        }
        .onChange(of: searchText) { _, _ in
            visibleCount = Self.pageSize
        }
        .sheet(isPresented: $showingDestinationPicker) {
            TagMergeDestinationSheet(tags: allTags, excludedIds: sources) { picked in
                destination = picked
                sources.remove(picked.id)
                showingDestinationPicker = false
            } onCancel: {
                showingDestinationPicker = false
            }
        }
        .alert("Merge tags?", isPresented: $showingConfirmation) {
            Button("Merge", role: .destructive) { merge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    // MARK: - Pinned header

    /// Ziel und Suche stehen fest über der Liste: beim Scrollen durch hunderte Tags
    /// muss sichtbar bleiben, worauf gemerged wird und wonach gefiltert ist.
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            sectionHeading("Merge into")

            Button {
                showingDestinationPicker = true
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let destination {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name)
                                .foregroundColor(.primary)
                            Text(usageSummary(destination))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Choose a tag")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            sectionHeading("Search Tags")
                .padding(.top, DesignTokens.Spacing.xs)

            TagMergeSearchField(text: $searchText)
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .background(Color.appBackground(for: appearance.currentTheme))
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.leading, DesignTokens.Spacing.xs)
    }

    // MARK: - Tag list

    /// Eigener Card-Container statt `Form`: nur so lässt sich der Eckradius auf den
    /// der Ziel-Card legen und das Suchfeld aus der scrollenden Liste heraushalten.
    private var tagListCard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading {
                    HStack { Spacer(); ProgressView("Loading..."); Spacer() }
                        .padding(.vertical, DesignTokens.Spacing.lg)
                } else if filtered.isEmpty {
                    Text(allTags.isEmpty ? "This server has no tags yet." : "No matches")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.md)
                } else {
                    let shown = Array(filtered.prefix(visibleCount))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, tag in
                        if index > 0 {
                            Divider()
                                .overlay(Color.primary.opacity(0.15))
                                .padding(.leading, DesignTokens.Spacing.md)
                        }
                        tagRow(tag)
                            .onAppear {
                                guard tag.id == shown.last?.id else { return }
                                if visibleCount < filtered.count {
                                    visibleCount += Self.pageSize
                                }
                            }
                    }

                    if visibleCount < filtered.count || isLoadingMorePages {
                        Divider()
                            .overlay(Color.primary.opacity(0.15))
                            .padding(.leading, DesignTokens.Spacing.md)
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            InlineSpinner()
                            Text("Loading more...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                    }
                }
            }
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
            .padding(.bottom, DesignTokens.Spacing.sm)
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .foregroundColor(.primary)
                Text(usageSummary(tag))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if sources.contains(tag.id) {
                Image(systemName: "checkmark")
                    .foregroundColor(appearance.tintColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { toggle(tag) }
    }

    // MARK: - Action bar

    @ViewBuilder
    private var mergeBar: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            if canMerge, let destination {
                Text("\(sources.count) tag\(sources.count == 1 ? "" : "s") → \(destination.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    showingConfirmation = true
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if isMerging { InlineSpinner() }
                        Text(isMerging ? "Merging..." : "Merge Tags")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .disabled(!canMerge)

                Button {
                    clearSelection()
                } label: {
                    Text("Clear")
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(Color.secondaryAppBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!hasSelection || isMerging)
                .opacity(hasSelection && !isMerging ? 1 : 0.4)
            }
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(Color.appBackground(for: appearance.currentTheme))
    }

    // MARK: - Helpers

    /// Auswahl und Suche zurücksetzen, ohne die geladene Tag-Liste wegzuwerfen.
    private func clearSelection() {
        sources.removeAll()
        destination = nil
        searchText = ""
    }

    private func toggle(_ tag: Tag) {
        if sources.contains(tag.id) {
            sources.remove(tag.id)
        } else {
            sources.insert(tag.id)
        }
    }

    private func usageSummary(_ tag: Tag) -> String {
        var parts: [String] = []
        appendCount(&parts, tag.sceneCount, "scene")
        appendCount(&parts, tag.imageCount, "image")
        appendCount(&parts, tag.galleryCount, "gallery", plural: "galleries")
        appendCount(&parts, tag.performerCount, "performer")
        appendCount(&parts, tag.sceneMarkerCount, "marker")
        return parts.isEmpty ? "Unused" : parts.joined(separator: " · ")
    }

    private func appendCount(_ parts: inout [String], _ value: Int?, _ singular: String, plural: String? = nil) {
        guard let value, value > 0 else { return }
        parts.append("\(value) \(value == 1 ? singular : (plural ?? singular + "s"))")
    }

    private var confirmationMessage: String {
        guard let destination else { return "" }
        let names = selectedSources.map(\.name).joined(separator: ", ")
        return "\(names) will be re-tagged to \(destination.name) and then deleted. This cannot be undone."
    }

    /// Erste Serverseite sofort anzeigen, der Rest läuft im Hintergrund nach.
    /// Gesucht wird lokal, deshalb müssen am Ende wirklich alle Tags da sein —
    /// eine einzelne Seite ließe den Rest auch über die Suche unerreichbar.
    private func load() {
        allTags = []
        visibleCount = Self.pageSize
        isLoading = true
        isLoadingMorePages = true
        Task {
            var page = 1
            let perPage = 500
            var total = 0

            do {
                while true {
                    let result = try await repository.fetchTags(
                        page: page,
                        perPage: perPage,
                        sortBy: .nameAsc,
                        searchQuery: "",
                        filter: nil
                    )
                    total = result.total
                    let batch = result.tags

                    await MainActor.run {
                        allTags.append(contentsOf: batch)
                        isLoading = false
                    }

                    let loaded = page * perPage
                    if batch.count < perPage || (total > 0 && loaded >= total) { break }

                    page += 1
                    // Sicherheitsventil gegen ein Backend, das immer volle Seiten liefert.
                    if page > 60 { break }
                }
            } catch {
                AppLog.error("❌ Loading tags failed: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    isLoadingMorePages = false
                    ToastManager.shared.show("Failed to load tags", icon: "exclamationmark.triangle", style: .error)
                }
                return
            }

            await MainActor.run {
                allTags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                isLoadingMorePages = false
            }
        }
    }

    private func merge() {
        guard let destination, !sources.isEmpty else { return }
        let sourceIds = Array(sources)
        let mergedCount = sourceIds.count
        isMerging = true
        HapticManager.light()

        Task {
            do {
                try await repository.mergeTags(sourceIds: sourceIds, destinationId: destination.id)
                await MainActor.run {
                    isMerging = false
                    sources.removeAll()
                    allTags.removeAll { sourceIds.contains($0.id) }
                    // Gelöschte Tags dürfen in Filter-Pickern nicht weiterleben.
                    FilterPickerOptionsStore.shared.invalidate()
                    ToastManager.shared.show(
                        "\(mergedCount) tag\(mergedCount == 1 ? "" : "s") merged into \(destination.name)",
                        icon: "arrow.triangle.merge",
                        style: .success
                    )
                    load()
                }
            } catch {
                AppLog.error("❌ Tag merge failed: \(error.localizedDescription)")
                await MainActor.run {
                    isMerging = false
                    ToastManager.shared.show(
                        "Failed to merge tags",
                        icon: "exclamationmark.triangle",
                        style: .error
                    )
                }
            }
        }
    }
}

// MARK: - Destination picker

/// Gleiche Suchform wie die Tool-Seite: Suchfeld als erste Zeile der Liste, lokal
/// gefiltert. Die Tags kommen von der Tool-Seite, damit hier nichts nachgeladen wird.
private struct TagMergeDestinationSheet: View {
    let tags: [Tag]
    let excludedIds: Set<String>
    let onPick: (Tag) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var visibleCount = TagMergeToolsView.pageSize

    private var filtered: [Tag] {
        let base = tags.filter { !excludedIds.contains($0.id) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Form {
            Section(header: Text("Search Tags")) {
                TextField("Search...", text: $searchText)

                let shown = Array(filtered.prefix(visibleCount))
                ForEach(shown) { tag in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tag.name)
                            Text(usageSummary(tag))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(tag) }
                    .onAppear {
                        guard tag.id == shown.last?.id else { return }
                        if visibleCount < filtered.count {
                            visibleCount += TagMergeToolsView.pageSize
                        }
                    }
                }

                if visibleCount < filtered.count {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        InlineSpinner()
                        Text("Loading more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashyModalSheetChrome("Merge into", onBack: onCancel)
        .onChange(of: searchText) { _, _ in
            visibleCount = TagMergeToolsView.pageSize
        }
    }

    private func usageSummary(_ tag: Tag) -> String {
        var parts: [String] = []
        appendCount(&parts, tag.sceneCount, "scene")
        appendCount(&parts, tag.imageCount, "image")
        appendCount(&parts, tag.galleryCount, "gallery", plural: "galleries")
        appendCount(&parts, tag.performerCount, "performer")
        appendCount(&parts, tag.sceneMarkerCount, "marker")
        return parts.isEmpty ? "Unused" : parts.joined(separator: " · ")
    }

    private func appendCount(_ parts: inout [String], _ value: Int?, _ singular: String, plural: String? = nil) {
        guard let value, value > 0 else { return }
        parts.append("\(value) \(value == 1 ? singular : (plural ?? singular + "s"))")
    }
}

// MARK: - Search field

/// Eine Suchleiste für beide Listen — Tool-Seite und Ziel-Auswahl.
private struct TagMergeSearchField: View {
    @Binding var text: String

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search...", text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
    }
}
