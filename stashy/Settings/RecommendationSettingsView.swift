//
//  RecommendationSettingsView.swift
//  stashy
//
//  stashy+ — tuning for the For You row on Home (`SceneRecommendationEngine`).
//

#if !os(tvOS)

import SwiftUI

struct RecommendationSettingsView: View {
    @ObservedObject private var engine = SceneRecommendationEngine.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    var body: some View {
        List {
            if !stashyPlus.isUnlocked {
                Section {
                    Label("For You requires stashy+", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            } else if !engine.isFeatureOn {
                Section {
                    Label(engine.hasStatistics
                          ? "For You is off. Turn it on in Recommendations to show it on Home."
                          : "Turn on Tag suggestions or Similar scenes to show For You on Home.", systemImage: "info.circle")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            }

            statusSection
            historySection
            discoverySection
            influenceSection
            adjustmentsSection
            resetSection
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("For You")
        .disabled(!stashyPlus.isUnlocked)
        // Changed settings apply from the next list (pull to refresh, Refresh above, app start);
        // leaving here only builds one when none is shown yet.
        .onDisappear { engine.refreshIfNeeded() }
        // Feedback for Refresh: a prepared list swaps in instantly and would otherwise go unseen.
        .onChange(of: engine.builtAt) { old, new in
            guard old != nil, new != nil, engine.state == .ready else { return }
            ToastManager.shared.show("New suggestions on Home", icon: "sparkles", style: .success)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            stashyScrollingSectionHeader("For You", isBeta: true)

            HStack {
                Label("Status", systemImage: "sparkles")
                Spacer()
                Text(statusText)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .stashyGroupedBlockRow(index: 0, count: 2)

            Button {
                engine.rebuild()
            } label: {
                HStack {
                    Label("Refresh suggestions", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(appearanceManager.tintColor)
                    Spacer()
                    if engine.isRefreshing { ProgressView() }
                }
            }
            .disabled(engine.isRefreshing)
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter("Picked on this device from your plays, O-Counts and ratings.")
        }
    }

    private var historySection: some View {
        Section {
            stashyScrollingSectionHeader("Watch history")

            VStack(alignment: .leading, spacing: 8) {
                Text("Look back")
                Picker("Look back", selection: $engine.lookbackDays) {
                    ForEach(SceneRecommendationEngine.lookbackChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
            .stashyGroupedBlockRow(index: 0, count: 2)

            Stepper(value: $engine.count, in: SceneRecommendationEngine.countRange) {
                HStack {
                    Text("Suggestions")
                    Spacer()
                    Text("\(engine.count)").foregroundColor(.secondary)
                }
            }
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter("Scenes played in this period are not suggested.")
        }
    }

    private var discoverySection: some View {
        Section {
            stashyScrollingSectionHeader("What to suggest")

            Picker("What to suggest", selection: $engine.discovery) {
                ForEach(RecommendationDiscovery.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, 4)
            .stashyGroupedSettingsRow()

            stashyScrollingSectionFooter(engine.discovery.detail)
        }
    }

    private var influenceSection: some View {
        Section {
            stashyScrollingSectionHeader("Influence")

            weightRow("Similar to watched", icon: "square.stack.3d.up.fill", value: $engine.similarWeight, index: 0)
            weightRow("Performers", icon: "person.fill", value: $engine.performerWeight, index: 1)
            weightRow("Studios", icon: "building.2.fill", value: $engine.studioWeight, index: 2)
            weightRow("Tags", icon: "tag.fill", value: $engine.tagWeight, index: 3)
            weightRow("O-Counts", icon: appearanceManager.oCounterIcon, value: $engine.oCountWeight, index: 4)
            weightRow("Ratings", icon: "star.fill", value: $engine.ratingWeight, index: 5)

            stashyScrollingSectionFooter("How much each part steers the picks.")
        }
    }

    private var adjustmentsSection: some View {
        Section {
            stashyScrollingSectionHeader("Performers, studios and tags")

            NavigationLink(destination: LazyView { RecommendationAdjustmentsView() }) {
                HStack {
                    Label("Adjustments", systemImage: "slider.horizontal.3")
                    Spacer()
                    Text(adjustmentsSummary)
                        .foregroundColor(.secondary)
                }
            }
            .stashyGroupedSettingsRow()

            stashyScrollingSectionFooter("Also from the ··· menu below a card.")
        }
    }

    private var adjustmentsSummary: String {
        let list = engine.adjustments
        guard !list.isEmpty else { return "None" }
        let hidden = list.filter(\.isHidden).count
        return hidden > 0 ? "\(list.count) · \(hidden) hidden" : "\(list.count)"
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                engine.resetSettings()
            } label: {
                Label("Reset to defaults", systemImage: "arrow.uturn.backward")
                    .foregroundColor(engine.hasCustomSettings ? .red : .secondary)
            }
            .disabled(!engine.hasCustomSettings)
            .stashyGroupedSettingsRow()
        }
    }

    // MARK: - Rows

    private func weightRow(_ title: String, icon: String, value: Binding<Double>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(Self.weightLabel(value.wrappedValue))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: SceneRecommendationEngine.weightRange, step: 0.25)
                .tint(appearanceManager.tintColor)
                .accessibilityLabel(title)
                .accessibilityValue(Self.weightLabel(value.wrappedValue))
        }
        .padding(.vertical, 4)
        .stashyGroupedBlockRow(index: index, count: 6)
    }

    private static func weightLabel(_ value: Double) -> String {
        switch value {
        case ..<0.01: return "Off"
        case ..<0.75: return "Low"
        case ..<1.26: return "Normal"
        case ..<1.76: return "High"
        default: return "Max"
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: return "Not built yet"
        case .loading: return "Looking…"
        case .ready where engine.isRefreshing: return "Looking…"
        case .noHistory: return "No plays yet"
        case .failed(let message): return message
        case .ready:
            let picks = "\(engine.homeItems.count) scenes from \(engine.seedCount) watched"
            if let date = engine.builtAt {
                return "\(picks) · \(date.formatted(date: .omitted, time: .shortened))"
            }
            return picks
        }
    }
}

// MARK: - Adjustments

/// Settings › For You › Adjustments: per kind an inline add row (search, tap to add, like the
/// filter pickers) and one slider per entry, from Hidden to 3×.
struct RecommendationAdjustmentsView: View {
    @ObservedObject private var engine = SceneRecommendationEngine.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var addKind: RecommendationAdjustment.Kind?
    @State private var confirmsRemoveAll = false

    var body: some View {
        List {
            ForEach(RecommendationAdjustment.Kind.allCases) { kind in
                let entries = engine.adjustments.filter { $0.kind == kind }
                Section {
                    stashyScrollingSectionHeader(kind.title)
                    Button {
                        addKind = kind
                    } label: {
                        Label(kind.addTitle, systemImage: "plus.circle.fill")
                            .foregroundColor(appearanceManager.tintColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .stashyGroupedBlockRow(index: 0, count: entries.count + 1)
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                            .stashyGroupedBlockRow(index: index + 1, count: entries.count + 1)
                            .swipeActions {
                                Button(role: .destructive) {
                                    engine.removeAdjustment(entry.kind, id: entry.itemId)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Section {
                stashyScrollingSectionFooter("Hidden never shows it. Above 1× also brings new scenes. Swipe to remove.")
            }

            if !engine.adjustments.isEmpty {
                Section {
                    Button(role: .destructive) {
                        confirmsRemoveAll = true
                    } label: {
                        Label("Remove all", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .stashyGroupedSettingsRow()
                }
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Adjustments")
        .sheet(item: $addKind) { kind in
            RecommendationAdjustmentPicker(kind: kind)
        }
        .alert("Remove all adjustments?", isPresented: $confirmsRemoveAll) {
            Button("Remove all", role: .destructive) { engine.removeAllAdjustments() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Entry

    private func row(_ entry: RecommendationAdjustment) -> some View {
        let binding = Binding<Double>(
            get: { engine.adjustment(entry.kind, entry.itemId)?.factor ?? entry.factor },
            set: { engine.setAdjustment(entry.kind, id: entry.itemId, name: entry.name, factor: ($0 * 10).rounded() / 10) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.name, systemImage: entry.isHidden ? "eye.slash" : entry.kind.icon)
                    .lineLimit(1)
                Spacer()
                Text(RecommendationAdjustment.label(binding.wrappedValue))
                    .foregroundColor(entry.isHidden ? .red : .secondary)
                    .monospacedDigit()
            }
            Slider(value: binding, in: RecommendationAdjustment.range, step: 0.1)
                .tint(appearanceManager.tintColor)
                .accessibilityLabel(entry.name)
                .accessibilityValue(RecommendationAdjustment.label(binding.wrappedValue))
        }
        .padding(.vertical, 4)
    }
}

/// Add sheet: every performer, studio or tag of the device's scene index, searchable.
/// Tapping one adds it at 1× and closes the sheet.
private struct RecommendationAdjustmentPicker: View {
    let kind: RecommendationAdjustment.Kind
    @ObservedObject private var engine = SceneRecommendationEngine.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var names: [(id: String, name: String)] = []
    @State private var isLoading = true

    private var results: [(id: String, name: String)] {
        let term = search.trimmingCharacters(in: .whitespaces)
        let taken = Set(engine.adjustments.filter { $0.kind == kind }.map(\.itemId))
        return names
            .filter { !taken.contains($0.id) && (term.isEmpty || $0.name.localizedCaseInsensitiveContains(term)) }
            .prefix(200)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .stashyGroupedSettingsRow()
                    } else if results.isEmpty {
                        Text(names.isEmpty ? SceneRecommendationEngine.preparingMessage : "Nothing found")
                            .foregroundColor(.secondary)
                            .stashyGroupedSettingsRow()
                    } else {
                        let hits = results
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, item in
                            // Plain row with a tap gesture: a Button in a themed row did not
                            // reliably register the tap (as in the sync job sheet).
                            Label(item.name, systemImage: kind.icon)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    engine.setAdjustment(kind, id: item.id, name: item.name, factor: 1)
                                    dismiss()
                                }
                                .stashyGroupedBlockRow(index: index, count: hits.count)
                        }
                    }
                }
            }
            .stashySettingsList()
            .applyAppBackground()
            .stashyModalSheetChrome(kind.addTitle, onBack: { dismiss() })
        }
        .task { await load() }
    }

    /// Same capsule as the filter pickers' search.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondaryAppBackground(for: appearanceManager.currentTheme))
        .clipShape(Capsule(style: .continuous))
    }

    private func load() async {
        guard let index = await AITagSuggestionManager.shared.sceneIndex() else {
            isLoading = false
            return
        }
        var map: [String: String]
        switch kind {
        case .performer: map = index.performerNames
        case .studio: map = index.studioNames
        case .tag:
            map = index.tagNames ?? [:]
            for tag in AITagSuggestionManager.shared.knownTags where map[tag.id] == nil { map[tag.id] = tag.name }
        }
        names = map.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false
    }
}

/// The ··· menu below a For You card: turn its performers, studio or tags up, down or off.
struct RecommendationAdjustMenu: View {
    let scene: Scene
    @ObservedObject private var engine = SceneRecommendationEngine.shared

    var body: some View {
        ForEach(scene.performers.prefix(4)) { performer in
            itemMenu(.performer, id: performer.id, name: performer.name)
        }
        if let studio = scene.studio {
            itemMenu(.studio, id: studio.id, name: studio.name)
        }
        if let tags = scene.tags, !tags.isEmpty {
            Menu {
                ForEach(tags.prefix(15)) { tag in
                    itemMenu(.tag, id: tag.id, name: tag.name)
                }
            } label: {
                Label("Tags", systemImage: "tag.fill")
            }
        }
    }

    private func itemMenu(_ kind: RecommendationAdjustment.Kind, id: String, name: String) -> some View {
        let current = engine.adjustment(kind, id)
        return Menu {
            Button {
                apply(kind, id: id, name: name, factor: RecommendationAdjustment.more)
            } label: {
                Label("More like this", systemImage: "hand.thumbsup")
            }
            Button {
                apply(kind, id: id, name: name, factor: RecommendationAdjustment.less)
            } label: {
                Label("Less like this", systemImage: "hand.thumbsdown")
            }
            Button(role: .destructive) {
                apply(kind, id: id, name: name, factor: 0)
            } label: {
                Label("Never suggest", systemImage: "eye.slash")
            }
            if current != nil {
                Button {
                    engine.removeAdjustment(kind, id: id)
                    engine.applyAdjustmentsNow()
                } label: {
                    Label("Back to normal", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Label(current.map { "\(name) · \(RecommendationAdjustment.label($0.factor))" } ?? name,
                  systemImage: current?.isHidden == true ? "eye.slash" : kind.icon)
        }
    }

    private func apply(_ kind: RecommendationAdjustment.Kind, id: String, name: String, factor: Double) {
        engine.setAdjustment(kind, id: id, name: name, factor: factor)
        engine.applyAdjustmentsNow()
        let message: String
        switch factor {
        case ..<RecommendationAdjustment.hiddenBelow: message = "\(name) won't be suggested"
        case ..<1: message = "Less of \(name)"
        default: message = "More of \(name)"
        }
        ToastManager.shared.show(message, icon: factor < RecommendationAdjustment.hiddenBelow ? "eye.slash" : "sparkles", style: .success)
    }
}

#endif
