//
//  MergeTools.swift
//  stashy
//
//  Settings › Server › stashy+ → Merge Tags / Merge Studios: mehrere Einträge auf einen zusammenführen,
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
    /// Stabile Merkmale für Vorlagen: nach einem Merge legt ein Scraper den Eintrag
    /// unter neuer ID wieder an — wiedererkennbar ist er dann nur hierüber.
    var mergeStashIds: [MergePresetStashId] { get }
    var mergeAliases: [String] { get }
}

extension Tag: MergeableItem {
    var mergeStashIds: [MergePresetStashId] { MergePresetStashId.from(stashIds) }
    var mergeAliases: [String] { aliases ?? [] }

    var mergeUsageSummary: String {
        var parts: [String] = []
        MergeUsage.append(&parts, sceneCount, one: "arg_count_scene", other: "arg_count_scenes")
        MergeUsage.append(&parts, imageCount, one: "arg_count_image", other: "arg_count_images")
        MergeUsage.append(&parts, galleryCount, one: "arg_count_gallery", other: "arg_count_galleries")
        MergeUsage.append(&parts, performerCount, one: "arg_count_performer", other: "arg_count_performers")
        MergeUsage.append(&parts, sceneMarkerCount, one: "arg_count_marker", other: "arg_count_markers")
        return parts.isEmpty ? tr("unused") : parts.joined(separator: " · ")
    }
}

extension Studio: MergeableItem {
    var mergeStashIds: [MergePresetStashId] { MergePresetStashId.from(stashIds) }
    var mergeAliases: [String] { aliases ?? [] }

    var mergeUsageSummary: String {
        var parts: [String] = []
        MergeUsage.append(&parts, sceneCount, one: "arg_count_scene", other: "arg_count_scenes")
        MergeUsage.append(&parts, imageCount, one: "arg_count_image", other: "arg_count_images")
        MergeUsage.append(&parts, galleryCount, one: "arg_count_gallery", other: "arg_count_galleries")
        MergeUsage.append(&parts, performerCount, one: "arg_count_performer", other: "arg_count_performers")
        return parts.isEmpty ? tr("unused") : parts.joined(separator: " · ")
    }
}

enum MergeUsage {
    /// `one` / `other` are localization keys (one value placeholder each).
    static func append(_ parts: inout [String], _ value: Int?, one: String, other: String) {
        guard let value, value > 0 else { return }
        parts.append(tr(value == 1 ? one : other, value))
    }
}

// MARK: - Presets (local)

/// Ein `stash_id` eines Eintrags (StashDB o. Ä.) — endpoint + ID zusammen sind die
/// einzige Kennung, die einen Neuanlage-durch-Scraper überlebt.
struct MergePresetStashId: Codable, Equatable {
    var endpoint: String
    var stashId: String

    /// Aus dem GraphQL-Modell; Einträge ohne endpoint oder ID sind wertlos.
    static func from(_ ids: [StashID]?) -> [MergePresetStashId] {
        (ids ?? []).compactMap { id in
            guard let endpoint = id.endpoint, !endpoint.isEmpty,
                  let stashId = id.stashId, !stashId.isEmpty else { return nil }
            return MergePresetStashId(endpoint: endpoint, stashId: stashId)
        }
    }
}

/// Ein Eintrag in einer Vorlage. Die Stash-ID allein reicht nicht: nach dem Merge ist
/// die Quelle gelöscht, und der Scraper legt sie beim nächsten Mal unter neuer ID an.
/// Deshalb stehen Name und `stash_ids` mit in der Vorlage.
struct MergePresetEntry: Codable, Equatable {
    var id: String
    var name: String
    var stashIds: [MergePresetStashId]

    init(id: String, name: String = "", stashIds: [MergePresetStashId] = []) {
        self.id = id
        self.name = name
        self.stashIds = stashIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        stashIds = try container.decodeIfPresent([MergePresetStashId].self, forKey: .stashIds) ?? []
    }

    /// Für Anzeige und Toasts: Name, solange einer bekannt ist.
    var displayName: String { name.isEmpty ? id : name }
}

/// Gespeicherte Merge-Vorlage: Ziel + Quellen. Liegt nur auf dem Gerät, pro Server.
struct MergePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var destination: MergePresetEntry
    var sources: [MergePresetEntry]

    init(id: UUID = UUID(), name: String, destination: MergePresetEntry, sources: [MergePresetEntry]) {
        self.id = id
        self.name = name
        self.destination = destination
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, destination, sources
        // Altes Format (nur Stash-IDs).
        case destinationId, destinationName, sourceIds
    }

    /// Vorlagen aus älteren Versionen kennen nur IDs. Sie werden gelesen, als hätten
    /// die Einträge keine Identitätsmerkmale — beim nächsten Speichern sind sie dabei.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let destination = try container.decodeIfPresent(MergePresetEntry.self, forKey: .destination) {
            self.destination = destination
            sources = try container.decodeIfPresent([MergePresetEntry].self, forKey: .sources) ?? []
        } else {
            let legacyId = try container.decodeIfPresent(String.self, forKey: .destinationId) ?? ""
            let legacyName = try container.decodeIfPresent(String.self, forKey: .destinationName) ?? ""
            destination = MergePresetEntry(id: legacyId, name: legacyName)
            sources = (try container.decodeIfPresent([String].self, forKey: .sourceIds) ?? [])
                .map { MergePresetEntry(id: $0) }
        }
    }

    /// Geschrieben wird immer das neue Format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(destination, forKey: .destination)
        try container.encode(sources, forKey: .sources)
    }
}

// MARK: - Resolving preset entries

/// Nachschlagewerk über die geladene Liste: ID → Eintrag, stash_id → Eintrag,
/// Name/Alias (klein geschrieben) → Eintrag. Einmal pro Ladevorgang gebaut.
struct MergeItemIndex<Item: MergeableItem> {
    private var byId: [String: Item] = [:]
    private var byStashId: [String: Item] = [:]
    private var byName: [String: Item] = [:]
    private var byAlias: [String: Item] = [:]

    init(items: [Item] = []) {
        for item in items {
            byId[item.id] = item
            for stashId in item.mergeStashIds {
                let key = Self.key(stashId)
                if byStashId[key] == nil { byStashId[key] = item }
            }
            let name = item.name.lowercased()
            if !name.isEmpty, byName[name] == nil { byName[name] = item }
            for alias in item.mergeAliases {
                let key = alias.lowercased()
                if !key.isEmpty, byAlias[key] == nil { byAlias[key] = item }
            }
        }
    }

    private static func key(_ stashId: MergePresetStashId) -> String {
        "\(stashId.endpoint)\u{1}\(stashId.stashId)"
    }

    /// Reihenfolge: exakte ID, dann stash_id, dann Name, dann Alias. Der erste Treffer gilt.
    func resolve(_ entry: MergePresetEntry) -> Item? {
        if !entry.id.isEmpty, let hit = byId[entry.id] { return hit }
        for stashId in entry.stashIds {
            if let hit = byStashId[Self.key(stashId)] { return hit }
        }
        let name = entry.name.lowercased()
        guard !name.isEmpty else { return nil }
        if let hit = byName[name] { return hit }
        return byAlias[name]
    }
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
    func update(_ id: UUID, destination: MergePresetEntry, sources: [MergePresetEntry]) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].destination = destination
        presets[index].sources = sources
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
    let loadAll: () async throws -> [Item]
    let merge: (_ sourceIds: [String], _ destinationId: String) async throws -> Void
    /// Nach erfolgreichem Merge (Caches invalidieren etc.).
    let didMerge: () -> Void
}

/// Texte je Art. Jeder Satz hat seinen eigenen Key: ein eingesetztes "tag"/"studio" bliebe
/// in jeder Übersetzung englisch und passt in vielen Sprachen grammatisch nicht.
extension MergeToolsConfig {
    private var isTags: Bool { kind == "tags" }
    var title: String { tr(isTags ? "tags" : "studios") }
    var searchSectionTitle: String { tr(isTags ? "search_tags" : "search_studios") }
    var searchPrompt: String { tr(isTags ? "placeholder_search_tags" : "placeholder_search_studios") }
    var confirmTitle: String { tr(isTags ? "confirm_merge_tags" : "confirm_merge_studios") }
    var emptyServerText: String { tr(isTags ? "hint_this_server_has_no_tags" : "hint_this_server_has_no_studios") }
    var mergeAction: String { tr(isTags ? "action_merge_tags" : "action_merge_studios") }
    var loadError: String { tr(isTags ? "error_load_tags" : "error_load_studios") }
    /// "1 tag" / "3 studios".
    func counted(_ count: Int) -> String {
        if isTags { return tr(count == 1 ? "arg_count_tag" : "arg_count_tags", count) }
        return tr(count == 1 ? "arg_count_studio" : "arg_count_studios", count)
    }
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
    /// Wird mit `allItems` gesetzt; Vorlagen schlagen darüber ihre Einträge nach.
    @State private var itemIndex = MergeItemIndex<Item>()
    @State private var isLoading = false
    /// Wächst beim Scrollen. Alle Treffer auf einmal zu rendern macht die Liste zäh.
    @State private var visibleCount = MergeToolsLayout.pageSize
    @State private var searchText = ""
    @State private var sources: Set<String> = []
    @State private var destination: Item?
    @State private var showingDestinationPicker = false
    @State private var showingConfirmation = false
    @State private var showingRunAllConfirmation = false
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
            : base.filter { sources.contains($0.id) || $0.name.localizedCaseInsensitiveContains(searchText) }
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
    private var missingPresetSources: [MergePresetEntry] {
        guard let activePreset else { return [] }
        return activePreset.sources.filter { itemIndex.resolve($0) == nil }
    }

    private var hasSelection: Bool {
        destination != nil || !sources.isEmpty || !searchText.isEmpty
    }

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
            MergeDestinationSheet(items: allItems, excludedIds: sources, sectionTitle: config.searchSectionTitle) { picked in
                destination = picked
                sources.remove(picked.id)
                showingDestinationPicker = false
            } onCancel: {
                showingDestinationPicker = false
            }
        }
        .alert(config.confirmTitle, isPresented: $showingConfirmation) {
            Button(tr("action_merge"), role: .destructive) { merge() }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(tr("confirm_run_all_templates"), isPresented: $showingRunAllConfirmation) {
            Button(tr("action_merge_all"), role: .destructive) { runAllPresets() }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: {
            Text(runAllConfirmationMessage)
        }
        .alert(tr("action_save_template"), isPresented: $showingSavePrompt) {
            TextField(tr("name"), text: $presetName)
            Button(tr("action_save")) { savePreset() }
            Button(tr("action_cancel"), role: .cancel) {}
        }
        .alert(
            tr("confirm_delete_template"),
            isPresented: Binding(get: { presetToDelete != nil }, set: { if !$0 { presetToDelete = nil } }),
            presenting: presetToDelete
        ) { preset in
            Button(tr("action_delete"), role: .destructive) {
                presets.delete(preset)
                if activePreset?.id == preset.id { activePreset = nil }
            }
            Button(tr("action_cancel"), role: .cancel) {}
        } message: { preset in
            Text(tr("hint_arg_will_be_removed_from", preset.name))
        }
        .alert(tr("action_save_template"), isPresented: $showingSaveChoice) {
            if let activePreset {
                Button(tr("action_update_arg", activePreset.name)) { updateActivePreset() }
            }
            Button(tr("action_save_as_new")) {
                presetName = destination?.name ?? ""
                showingSavePrompt = true
            }
            Button(tr("action_cancel"), role: .cancel) {}
        }
    }

    // MARK: Pinned header

    /// Ziel, Vorlagen und Suche stehen fest über der Liste: beim Scrollen muss
    /// sichtbar bleiben, worauf gemerged wird und wonach gefiltert ist.
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            // The destination picker is the first field and carries its own label — no
            // heading above it.
            Button {
                showingDestinationPicker = true
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let destination {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("action_merge_into"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(destination.name)
                                .foregroundColor(.primary)
                            Text(destination.mergeUsageSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(tr("action_merge_into_menu"))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                // Same insets as ToolsSearchField, and a text line as tall as its TextField
                // (22 pt), so the empty field matches the search field of Tools › Filters.
                .frame(minHeight: 22)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !presets.presets.isEmpty {
                presetRow
                    .padding(.top, DesignTokens.Spacing.xs)
            }

            // Category heading over the list, Settings style, 8 pt above the card.
            StashySectionHeading(title: config.title)
                .padding(.top, DesignTokens.Spacing.md)
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        .padding(.top, DesignTokens.Tools.menuTopPadding)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .background(Color.appBackground(for: appearance.currentTheme))
    }

    /// Gespeicherte Vorlagen als Pills: Tippen lädt Ziel + Quellen, langes Drücken löscht.
    /// Davor, fest und nicht mitscrollend: der Knopf, der alle Vorlagen nacheinander
    /// ausführt (mit Rückfrage).
    private var presetRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            runAllButton
            ScrollView(.horizontal, showsIndicators: false) {
                presetPills
            }
        }
    }

    /// Nur Symbol, kein Text: die Pills daneben tragen die Namen, der Knopf soll nicht
    /// wie eine weitere Vorlage aussehen.
    private var runAllButton: some View {
        let runnable = runnablePresets.count
        return Button {
            showingRunAllConfirmation = true
        } label: {
            Image(systemName: "play.square.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(runnable > 0 ? appearance.tintColor : .secondary)
                // Gleiche Höhe wie eine zweizeilige Pill (Name + Quellenzahl).
                .frame(width: 40, height: MergeToolsLayout.presetPillHeight)
                .background(Color.secondaryAppBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(runnable == 0 || isMerging)
        .accessibilityLabel(tr("action_run_all_templates"))
    }

    private var presetPills: some View {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(presets.presets) { preset in
                    let isActive = isPresetActive(preset)
                    let missing = unresolvedSources(of: preset).count
                    Button {
                        apply(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                Text(preset.name)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                            }
                            // Immer die Quellenzahl; solange die Liste lädt, ist noch nichts
                            // aufgelöst, also kein "fehlt"-Hinweis. Nach einem Merge legt ein
                            // Scraper die Quelle neu an — bis dahin fehlt sie hier, bleibt
                            // aber in der Vorlage.
                            Text(presetSubtitle(preset, missing: missing))
                                .font(.caption2)
                                .lineLimit(1)
                                .opacity(0.75)
                        }
                        .foregroundColor(isActive ? Color.onAppTint : .primary)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .frame(height: MergeToolsLayout.presetPillHeight)
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

    // MARK: List

    /// Eigener Card-Container statt `Form`: nur so lässt sich der Eckradius auf den
    /// der Ziel-Card legen und das Suchfeld aus der scrollenden Liste heraushalten.
    private var listCard: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // The search is the card's first row, above the rows it filters.
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(config.searchPrompt, text: $searchText)
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
                        .accessibilityLabel(tr("action_clear_search"))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                Divider()
                    .overlay(Color.primary.opacity(0.15))
                if isLoading && allItems.isEmpty {
                    HStack { Spacer(); ProgressView(tr("loading")); Spacer() }
                        .padding(.vertical, DesignTokens.Spacing.lg)
                } else if filtered.isEmpty {
                    Text(allItems.isEmpty ? config.emptyServerText : tr("empty_matches"))
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
                            Text(tr("loading_more"))
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
            .cardShadow()
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
                Text("\(config.counted(sources.count)) → \(destination.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    showingConfirmation = true
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if isMerging { InlineSpinner() }
                        Text(isMerging ? tr("loading_merging") : config.mergeAction)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFilledButtonStyle())
                .disabled(!canMerge)

                secondaryButton(tr("action_save"), enabled: canSavePreset) {
                    if let activePreset, presets.presets.contains(where: { $0.id == activePreset.id }) {
                        showingSaveChoice = true
                    } else {
                        presetName = destination?.name ?? ""
                        showingSavePrompt = true
                    }
                }

                secondaryButton(tr("action_clear"), enabled: hasSelection && !isMerging) {
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

    /// Aufgelöste Quellen einer Vorlage (ohne das Ziel selbst) und die Einträge,
    /// die es auf dem Server gerade nicht gibt.
    private func resolveSources(of preset: MergePreset) -> (resolved: [Item], unresolved: [MergePresetEntry]) {
        let destinationId = itemIndex.resolve(preset.destination)?.id
        var resolved: [Item] = []
        var unresolved: [MergePresetEntry] = []
        var seen: Set<String> = []
        for entry in preset.sources {
            guard let item = itemIndex.resolve(entry) else {
                unresolved.append(entry)
                continue
            }
            // Was auf das Ziel zeigt, ist bereits zusammengeführt.
            guard item.id != destinationId, seen.insert(item.id).inserted else { continue }
            resolved.append(item)
        }
        return (resolved, unresolved)
    }

    private func unresolvedSources(of preset: MergePreset) -> [MergePresetEntry] {
        resolveSources(of: preset).unresolved
    }

    private func presetSubtitle(_ preset: MergePreset, missing: Int) -> String {
        let total = preset.sources.count
        // Vor dem Laden ist nichts aufgelöst — dann nur die Gesamtzahl. Danach immer
        // "K of N", auch wenn alle da sind, damit die Pill ihre Form nicht wechselt.
        let counted = tr(total == 1 ? "arg_count_source" : "arg_count_sources", total)
        if allItems.isEmpty { return counted }
        return tr("hint_arg_of_arg_on_server", total - missing, counted)
    }

    /// Vorlagen, für die es gerade etwas zu tun gibt: Ziel vorhanden und mindestens
    /// eine Quelle auf dem Server.
    private var runnablePresets: [(preset: MergePreset, destination: Item, sources: [Item])] {
        presets.presets.compactMap { preset in
            guard let destination = itemIndex.resolve(preset.destination) else { return nil }
            let resolved = resolveSources(of: preset).resolved
            guard !resolved.isEmpty else { return nil }
            return (preset, destination, resolved)
        }
    }

    private var runAllConfirmationMessage: String {
        let runnable = runnablePresets
        let sourceCount = runnable.reduce(0) { $0 + $1.sources.count }
        let skipped = presets.presets.count - runnable.count
        var text = tr("hint_arg_of_arg_templates_have", runnable.count, presets.presets.count)
            + tr("hint_arg_will_be_merged", config.counted(sourceCount))
        if skipped > 0 {
            text += tr(skipped == 1 ? "hint_one_template_nothing_to_do" : "hint_arg_templates_nothing_to_do", skipped)
        }
        return text + tr("this_cannot_be_undone")
    }

    /// Führt alle Vorlagen nacheinander aus. Nach jeder wird der Index aktualisiert,
    /// damit eine spätere Vorlage keine schon zusammengeführte Quelle mehr sieht.
    private func runAllPresets() {
        let jobs = runnablePresets
        guard !jobs.isEmpty, !isMerging else { return }
        isMerging = true
        HapticManager.light()
        sources.removeAll()
        destination = nil
        activePreset = nil

        Task {
            var mergedTotal = 0
            var failed: [String] = []
            for job in jobs {
                // Der Index wandert mit den vorherigen Merges; deshalb pro Vorlage neu auflösen.
                let resolvedNow = await MainActor.run { resolveSources(of: job.preset).resolved }
                guard !resolvedNow.isEmpty else { continue }
                let sourceIds = resolvedNow.map(\.id)
                do {
                    try await config.merge(sourceIds, job.destination.id)
                    mergedTotal += sourceIds.count
                    await MainActor.run {
                        allItems.removeAll { sourceIds.contains($0.id) }
                        itemIndex = MergeItemIndex(items: allItems)
                    }
                } catch {
                    AppLog.error("❌ \(config.kind) merge (template \(job.preset.name)) failed: \(error.localizedDescription)")
                    failed.append(job.preset.name)
                }
            }
            let merged = mergedTotal
            await MainActor.run {
                isMerging = false
                if merged > 0 { config.didMerge() }
                if failed.isEmpty {
                    ToastManager.shared.show(
                        tr("arg_merged_from_arg_templates", config.counted(merged), jobs.count),
                        icon: "arrow.triangle.merge",
                        style: .success
                    )
                } else {
                    ToastManager.shared.show(
                        tr("arg_merged_failed_arg", merged, failed.prefix(3).joined(separator: ", ") + (failed.count > 3 ? " " + tr("arg_plus_more", failed.count - 3) : "")),
                        icon: "exclamationmark.triangle",
                        style: .error
                    )
                }
                load()
            }
        }
    }

    private func entry(for item: Item) -> MergePresetEntry {
        MergePresetEntry(id: item.id, name: item.name, stashIds: item.mergeStashIds)
    }

    private func isPresetActive(_ preset: MergePreset) -> Bool {
        guard let destination, let resolvedDestination = itemIndex.resolve(preset.destination),
              destination.id == resolvedDestination.id else { return false }
        return sources == Set(resolveSources(of: preset).resolved.map(\.id))
    }

    /// Ziel und Quellen aus der Vorlage übernehmen — nur, was es auf dem Server noch gibt.
    private func apply(_ preset: MergePreset) {
        HapticManager.selection()
        let resolution = resolveSources(of: preset)
        let resolvedDestination = itemIndex.resolve(preset.destination)
        destination = resolvedDestination
        sources = Set(resolution.resolved.map(\.id))
        searchText = ""
        activePreset = preset

        var missingNames = resolution.unresolved.map(\.displayName)
        if resolvedDestination == nil { missingNames.insert(preset.destination.displayName, at: 0) }
        if !missingNames.isEmpty {
            let shown = missingNames.prefix(3).joined(separator: ", ")
            let rest = missingNames.count - min(3, missingNames.count)
            ToastManager.shared.show(
                tr("hint_not_on_this_server_kept", rest > 0 ? shown + " " + tr("arg_plus_more", rest) : shown),
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
            destination: entry(for: destination),
            sources: selectedSources.map(entry(for:)) + missingPresetSources
        )
        presets.save(preset)
        activePreset = preset
        HapticManager.light()
        ToastManager.shared.show(tr("template_saved"), icon: "bookmark.fill", style: .success)
    }

    private func updateActivePreset() {
        guard let activePreset, !sources.isEmpty else { return }
        // Fehlt das Ziel auf dem Server, bleibt das gespeicherte stehen.
        let destinationEntry = destination.map(entry(for:)) ?? activePreset.destination
        presets.update(
            activePreset.id,
            destination: destinationEntry,
            sources: selectedSources.map(entry(for:)) + missingPresetSources
        )
        self.activePreset = presets.presets.first { $0.id == activePreset.id }
        HapticManager.light()
        ToastManager.shared.show(tr("template_updated"), icon: "bookmark.fill", style: .success)
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
        return tr("hint_arg_will_be_merged_into", names, destination.name)
    }

    private func load() {
        visibleCount = MergeToolsLayout.pageSize
        isLoading = true
        Task {
            do {
                let items = try await config.loadAll()
                await MainActor.run {
                    allItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    itemIndex = MergeItemIndex(items: allItems)
                    isLoading = false
                }
            } catch {
                AppLog.error("❌ Loading \(config.kind) failed: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    ToastManager.shared.show(config.loadError, icon: "exclamationmark.triangle", style: .error)
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
                    itemIndex = MergeItemIndex(items: allItems)
                    config.didMerge()
                    ToastManager.shared.show(
                        tr("arg_merged_into_arg", config.counted(mergedCount), destination.name),
                        icon: "arrow.triangle.merge",
                        style: .success
                    )
                    load()
                }
            } catch {
                AppLog.error("❌ \(config.kind) merge failed: \(error.localizedDescription)")
                await MainActor.run {
                    isMerging = false
                    ToastManager.shared.show(tr("action_merge_failed_arg", error.localizedDescription), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

enum MergeToolsLayout {
    /// Zeilen, die pro Nachladeschritt dazukommen.
    static let pageSize = 50
    /// Vorlagen-Pills und der Alle-ausführen-Knopf davor: eine feste Höhe für beide.
    static let presetPillHeight: CGFloat = 44
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
                TextField(tr("placeholder_search"), text: $searchText)

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
                        Text(tr("loading_more"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .stashyModalSheetChrome(tr("action_merge_into"), onBack: onCancel)
        .onChange(of: searchText) { _, _ in
            visibleCount = MergeToolsLayout.pageSize
        }
    }
}

// MARK: - Search field

/// Eine Suchleiste für beide Listen — Tool-Seite und Ziel-Auswahl. Dasselbe Feld wie in
/// Tools › Filters.
private struct MergeSearchField: View {
    @Binding var text: String

    var body: some View {
        ToolsSearchField(prompt: tr("placeholder_search"), text: $text)
    }
}

// MARK: - Studios

/// Settings › Server › stashy+ → Merge Studios. Stash kennt kein `studiosMerge`; `StudioRepository.mergeStudios`
/// hängt Szenen, Galerien, Bilder, Gruppen und Kind-Studios per Bulk-Update um und
/// löscht die Quellen danach.
struct StudioMergeToolsView: View {
    private static let repository = StudioRepository()

    var body: some View {
        MergeToolsView(config: MergeToolsConfig<Studio>(
            kind: "studios",
            loadAll: { try await Self.repository.fetchEveryStudioForMerge() },
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
