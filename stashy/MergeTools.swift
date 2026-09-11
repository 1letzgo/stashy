//
//  MergeTools.swift
//  stashy
//
//  Tools → Merge Tags / Merge Studios: mehrere Einträge auf einen zusammenführen,
//  mit lokal gespeicherten Vorlagen (Ziel + Quellen) pro Server.
//

#if !os(tvOS)
import SwiftUI

// MARK: - Mergeable items

/// Was die Merge-Seite von einem Eintrag braucht: Name für Liste und Vorlagen,
/// Nutzungszeile unter dem Namen.
protocol MergeableItem: Identifiable where ID == String {
    var name: String { get }
    var mergeUsageSummary: String { get }
}

extension Tag: MergeableItem {
    var mergeUsageSummary: String {
        var parts: [String] = []
        MergeUsage.append(&parts, sceneCount, "scene")
        MergeUsage.append(&parts, imageCount, "image")
        MergeUsage.append(&parts, galleryCount, "gallery", plural: "galleries")
        MergeUsage.append(&parts, performerCount, "performer")
        MergeUsage.append(&parts, sceneMarkerCount, "marker")
        return parts.isEmpty ? "Unused" : parts.joined(separator: " · ")
    }
}

extension Studio: MergeableItem {
    var mergeUsageSummary: String {
        var parts: [String] = []
        MergeUsage.append(&parts, sceneCount, "scene")
        MergeUsage.append(&parts, imageCount, "image")
        MergeUsage.append(&parts, galleryCount, "gallery", plural: "galleries")
        MergeUsage.append(&parts, performerCount, "performer")
        return parts.isEmpty ? "Unused" : parts.joined(separator: " · ")
    }
}

enum MergeUsage {
    static func append(_ parts: inout [String], _ value: Int?, _ singular: String, plural: String? = nil) {
        guard let value, value > 0 else { return }
        parts.append("\(value) \(value == 1 ? singular : (plural ?? singular + "s"))")
    }
}

// MARK: - Presets (local)

/// Gespeicherte Merge-Vorlage: Ziel + Quellen. Liegt nur auf dem Gerät, pro Server.
struct MergePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var destinationId: String
    var destinationName: String
    var sourceIds: [String]
}

/// UserDefaults-Ablage unter `MergePresets_<kind>_<serverID>` — Tags und Studios
/// getrennt, und ein anderer Server sieht die Vorlagen nicht.
final class MergePresetStore: ObservableObject {
    let kind: String
    @Published private(set) var presets: [MergePreset] = []

    init(kind: String) {
        self.kind = kind
        load()
    }

    private var key: String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString
            ?? ServerConfigManager.shared.loadConfig()?.id.uuidString
            ?? "default"
        return "MergePresets_\(kind)_\(serverID)"
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MergePreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded
    }

    func save(_ preset: MergePreset) {
        // Gleicher Name überschreibt — sonst sammeln sich Duplikate.
        presets.removeAll { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }
        presets.append(preset)
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    /// Ziel/Quellen einer bestehenden Vorlage ersetzen, Name und ID bleiben.
    func update(_ id: UUID, destinationId: String, destinationName: String, sourceIds: [String]) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].destinationId = destinationId
        presets[index].destinationName = destinationName
        presets[index].sourceIds = sourceIds
        persist()
    }

    func delete(_ preset: MergePreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Configuration

/// Alles, was Tags und Studios unterscheidet: Texte, Laden, Zusammenführen.
struct MergeToolsConfig<Item: MergeableItem> {
    /// Nur für den Preset-Schlüssel (`tags`, `studios`).
    let kind: String
    /// Singular/Plural für Buttons und Meldungen ("tag"/"tags").
    let noun: String
    let nounPlural: String
    let loadAll: () async throws -> [Item]
    let merge: (_ sourceIds: [String], _ destinationId: String) async throws -> Void
    /// Nach erfolgreichem Merge (Caches invalidieren etc.).
    let didMerge: () -> Void
}

// MARK: - Merge view

/// Führt Einträge zusammen: alles, was an den Quellen hängt, zeigt danach auf das
/// Ziel; die Quellen sind weg. Einmal laden, dann lokal filtern — serverseitig pro
/// Tastendruck zu suchen leerte die Liste bei jedem Zeichen.
struct MergeToolsView<Item: MergeableItem>: View {
    let config: MergeToolsConfig<Item>

    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var presets: MergePresetStore

    @State private var allItems: [Item] = []
    @State private var isLoading = false
    /// Wächst beim Scrollen. Alle Treffer auf einmal zu rendern macht die Liste zäh.
    @State private var visibleCount = MergeToolsLayout.pageSize
    @State private var searchText = ""
    @State private var sources: Set<String> = []
    @State private var destination: Item?
    @State private var showingDestinationPicker = false
    @State private var showingConfirmation = false
    @State private var showingSavePrompt = false
    @State private var showingSaveChoice = false
    @State private var presetName = ""
    @State private var presetToDelete: MergePreset?
    /// Zuletzt geladene Vorlage — "Save" bietet dann Aktualisieren statt nur Neuanlage.
    @State private var activePreset: MergePreset?
    @State private var isMerging = false

    init(config: MergeToolsConfig<Item>) {
        self.config = config
        _presets = StateObject(wrappedValue: MergePresetStore(kind: config.kind))
    }

    /// Ausgewählte zuerst: mit wenigen sichtbaren Zeilen entscheidet die Reihenfolge,
    /// was überhaupt erreichbar bleibt.
    private var filtered: [Item] {
        let base = allItems.filter { $0.id != destination?.id }
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

    private var selectedSources: [Item] {
        allItems.filter { sources.contains($0.id) }
    }

    private var canMerge: Bool {
        destination != nil && !sources.isEmpty && !isMerging
    }

    /// Beim Aktualisieren einer Vorlage reicht das gespeicherte Ziel, falls es auf
    /// dem Server gerade fehlt.
    private var canSavePreset: Bool {
        (destination != nil || activePreset != nil) && !sources.isEmpty && !isMerging
    }

    /// Einträge der geladenen Vorlage, die es auf dem Server nicht (mehr) gibt.
    /// Sie bleiben in der Vorlage — auch beim Überspeichern — statt still zu verschwinden.
    private var missingPresetSourceIds: [String] {
        guard let activePreset else { return [] }
        let known = Set(allItems.map(\.id))
        return activePreset.sourceIds.filter { !known.contains($0) }
    }

    private var hasSelection: Bool {
        destination != nil || !sources.isEmpty || !searchText.isEmpty
    }

    private var nounTitle: String { config.nounPlural.capitalized }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { load() }
            } else {
                listCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
        .safeAreaInset(edge: .top) { pinnedHeader }
        .safeAreaInset(edge: .bottom) { mergeBar }
        .onAppear {
            if allItems.isEmpty { load() }
        }
        .onChange(of: searchText) { _, _ in
            visibleCount = MergeToolsLayout.pageSize
        }
        .sheet(isPresented: $showingDestinationPicker) {
            MergeDestinationSheet(items: allItems, excludedIds: sources, sectionTitle: "Search \(nounTitle)") { picked in
                destination = picked
                sources.remove(picked.id)
                showingDestinationPicker = false
            } onCancel: {
                showingDestinationPicker = false
            }
        }
        .alert("Merge \(config.nounPlural)?", isPresented: $showingConfirmation) {
            Button("Merge", role: .destructive) { merge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert("Save template", isPresented: $showingSavePrompt) {
            TextField("Name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete template?",
            isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }),
            presenting: presetToDelete
        ) { preset in
            Button("Delete", role: .destructive) {
                presets.delete(preset)
                if activePreset?.id == preset.id { activePreset = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { preset in
            Text("\"\(preset.name)\" will be removed from this device.")
        }
        .alert("Save template", isPresented: $showingSaveChoice) {
            if let activePreset {
                Button("Update \"\(activePreset.name)\"") { updateActivePreset() }
            }
            Button("Save as new") {
                presetName = destination?.name ?? ""
                showingSavePrompt = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Pinned header

    /// Ziel, Vorlagen und Suche stehen fest über der Liste: beim Scrollen muss
    /// sichtbar bleiben, worauf gemerged wird und wonach gefiltert ist.
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
                            Text(destination.mergeUsageSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Choose a \(config.noun)")
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

            if !presets.presets.isEmpty {
                presetRow
            }

            sectionHeading("Search \(nounTitle)")
                .padding(.top, DesignTokens.Spacing.xs)

            MergeSearchField(text: $searchText)
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.top, DesignTokens.Tools.menuTopPadding)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .background(Color.appBackground(for: appearance.currentTheme))
    }

    /// Gespeicherte Vorlagen als Pills: Tippen lädt Ziel + Quellen, langes Drücken löscht.
    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(presets.presets) { preset in
                    let isActive = isPresetActive(preset)
                    Button {
                        apply(preset)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                            Text(preset.name)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(isActive ? .white : .primary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(isActive ? appearance.tintColor : Color.secondaryAppBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Langes Drücken → Löschen (mit Rückfrage). Ein Kontextmenü auf der
                    // Pill in der horizontalen Liste war nicht zuverlässig zu treffen.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            HapticManager.light()
                            presetToDelete = preset
                        }
                    )
                }
            }
        }
    }

    /// Gleicher Small-Caps-Header wie in den anderen Tools (`stashyScrollingSectionHeader`),
    /// bündig mit der Kartenkante — kein zusätzlicher Einzug.
    private func sectionHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: List

    /// Eigener Card-Container statt `Form`: nur so lässt sich der Eckradius auf den
    /// der Ziel-Card legen und das Suchfeld aus der scrollenden Liste heraushalten.
    private var listCard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && allItems.isEmpty {
                    HStack { Spacer(); ProgressView("Loading..."); Spacer() }
                        .padding(.vertical, DesignTokens.Spacing.lg)
                } else if filtered.isEmpty {
                    Text(allItems.isEmpty ? "This server has no \(config.nounPlural) yet." : "No matches")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.md)
                } else {
                    let shown = Array(filtered.prefix(visibleCount))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .overlay(Color.primary.opacity(0.15))
                                .padding(.leading, DesignTokens.Spacing.md)
                        }
                        row(item)
                            .onAppear {
                                guard item.id == shown.last?.id else { return }
                                if visibleCount < filtered.count {
                                    visibleCount += MergeToolsLayout.pageSize
                                }
                            }
                    }

                    if visibleCount < filtered.count || isLoading {
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

    private func row(_ item: Item) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundColor(.primary)
                Text(item.mergeUsageSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if sources.contains(item.id) {
                Image(systemName: "checkmark")
                    .foregroundColor(appearance.tintColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { toggle(item) }
    }

    // MARK: Action bar

    @ViewBuilder
    private var mergeBar: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            if canMerge, let destination {
                Text("\(sources.count) \(sources.count == 1 ? config.noun : config.nounPlural) → \(destination.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    showingConfirmation = true
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if isMerging { InlineSpinner() }
                        Text(isMerging ? "Merging..." : "Merge \(nounTitle)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .disabled(!canMerge)

                secondaryButton("Save", enabled: canSavePreset) {
                    if let activePreset, presets.presets.contains(where: { $0.id == activePreset.id }) {
                        showingSaveChoice = true
                    } else {
                        presetName = destination?.name ?? ""
                        showingSavePrompt = true
                    }
                }

                secondaryButton("Clear", enabled: hasSelection && !isMerging) {
                    clearSelection()
                }
            }
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(Color.appBackground(for: appearance.currentTheme))
    }

    private func secondaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: Presets

    private func isPresetActive(_ preset: MergePreset) -> Bool {
        destination?.id == preset.destinationId && sources == Set(preset.sourceIds)
    }

    /// Ziel und Quellen aus der Vorlage übernehmen — nur, was es auf dem Server noch gibt.
    private func apply(_ preset: MergePreset) {
        HapticManager.selection()
        let byId = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        destination = byId[preset.destinationId]
        sources = Set(preset.sourceIds.filter { byId[$0] != nil && $0 != preset.destinationId })
        searchText = ""
        activePreset = preset
        let missing = preset.sourceIds.count - sources.count + (destination == nil ? 1 : 0)
        if missing > 0 {
            ToastManager.shared.show(
                "\(missing) \(missing == 1 ? config.noun : config.nounPlural) from this template not on this server (kept in template)",
                icon: "info.circle",
                style: .info
            )
        }
    }

    private func savePreset() {
        guard let destination, !sources.isEmpty else { return }
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = MergePreset(
            name: name,
            destinationId: destination.id,
            destinationName: destination.name,
            sourceIds: Array(sources) + missingPresetSourceIds
        )
        presets.save(preset)
        activePreset = preset
        HapticManager.light()
        ToastManager.shared.show("Template saved", icon: "bookmark.fill", style: .success)
    }

    private func updateActivePreset() {
        guard let activePreset, !sources.isEmpty else { return }
        // Fehlt das Ziel auf dem Server, bleibt das gespeicherte stehen.
        let destinationId = destination?.id ?? activePreset.destinationId
        let destinationName = destination?.name ?? activePreset.destinationName
        presets.update(
            activePreset.id,
            destinationId: destinationId,
            destinationName: destinationName,
            sourceIds: Array(sources) + missingPresetSourceIds
        )
        self.activePreset = presets.presets.first { $0.id == activePreset.id }
        HapticManager.light()
        ToastManager.shared.show("Template updated", icon: "bookmark.fill", style: .success)
    }

    // MARK: Helpers

    /// Auswahl und Suche zurücksetzen, ohne die geladene Liste wegzuwerfen.
    private func clearSelection() {
        sources.removeAll()
        destination = nil
        searchText = ""
        activePreset = nil
    }

    private func toggle(_ item: Item) {
        if sources.contains(item.id) {
            sources.remove(item.id)
        } else {
            sources.insert(item.id)
        }
    }

    private var confirmationMessage: String {
        guard let destination else { return "" }
        let names = selectedSources.map(\.name).joined(separator: ", ")
        return "\(names) will be merged into \(destination.name) and then deleted. This cannot be undone."
    }

    private func load() {
        visibleCount = MergeToolsLayout.pageSize
        isLoading = true
        Task {
            do {
                let items = try await config.loadAll()
                await MainActor.run {
                    allItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    isLoading = false
                }
            } catch {
                AppLog.error("❌ Loading \(config.nounPlural) failed: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    ToastManager.shared.show("Failed to load \(config.nounPlural)", icon: "exclamationmark.triangle", style: .error)
                }
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
                try await config.merge(sourceIds, destination.id)
                await MainActor.run {
                    isMerging = false
                    sources.removeAll()
                    allItems.removeAll { sourceIds.contains($0.id) }
                    config.didMerge()
                    ToastManager.shared.show(
                        "\(mergedCount) \(mergedCount == 1 ? config.noun : config.nounPlural) merged into \(destination.name)",
                        icon: "arrow.triangle.merge",
                        style: .success
                    )
                    load()
                }
            } catch {
                AppLog.error("❌ \(config.kind) merge failed: \(error.localizedDescription)")
                await MainActor.run {
                    isMerging = false
                    ToastManager.shared.show("Merge failed: \(error.localizedDescription)", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

enum MergeToolsLayout {
    /// Zeilen, die pro Nachladeschritt dazukommen.
    static let pageSize = 50
}

// MARK: - Destination picker

/// Gleiche Suchform wie die Tool-Seite: Suchfeld als erste Zeile der Liste, lokal
/// gefiltert. Die Einträge kommen von der Tool-Seite, damit hier nichts nachgeladen wird.
private struct MergeDestinationSheet<Item: MergeableItem>: View {
    let items: [Item]
    let excludedIds: Set<String>
    let sectionTitle: String
    let onPick: (Item) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var visibleCount = MergeToolsLayout.pageSize

    private var filtered: [Item] {
        let base = items.filter { !excludedIds.contains($0.id) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Form {
            Section(header: Text(sectionTitle)) {
                TextField("Search...", text: $searchText)

                let shown = Array(filtered.prefix(visibleCount))
                ForEach(shown) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.mergeUsageSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(item) }
                    .onAppear {
                        guard item.id == shown.last?.id else { return }
                        if visibleCount < filtered.count {
                            visibleCount += MergeToolsLayout.pageSize
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
            visibleCount = MergeToolsLayout.pageSize
        }
    }
}

// MARK: - Search field

/// Eine Suchleiste für beide Listen — Tool-Seite und Ziel-Auswahl.
private struct MergeSearchField: View {
    @Binding var text: String

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

// MARK: - Studios

/// Tools → Merge Studios. Stash kennt kein `studiosMerge`; `StudioRepository.mergeStudios`
/// hängt Szenen, Galerien, Bilder, Gruppen und Kind-Studios per Bulk-Update um und
/// löscht die Quellen danach.
struct StudioMergeToolsView: View {
    private static let repository = StudioRepository()

    var body: some View {
        MergeToolsView(config: MergeToolsConfig<Studio>(
            kind: "studios",
            noun: "studio",
            nounPlural: "studios",
            loadAll: { try await Self.repository.fetchEveryStudio() },
            merge: { sources, destination in
                try await Self.repository.mergeStudios(sourceIds: sources, destinationId: destination)
            },
            didMerge: {
                // Gelöschte Studios dürfen in Filter-Pickern und Logo-Caches nicht weiterleben.
                FilterPickerOptionsStore.shared.invalidate()
                Task { await StudioLogoStore.shared.forgetMissing() }
            }
        ))
    }
}
#endif
