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
                    Label(tr("for_you_requires_stashy_plus"), systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            } else if !engine.isFeatureOn {
                Section {
                    Label(engine.hasStatistics
                          ? tr("hint_for_you_is_off_turn")
                          : tr("hint_turn_on_tag_suggestions_or"), systemImage: "info.circle")
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
        .stashySettingsDetailChrome(tr("for_you"))
        .disabled(!stashyPlus.isUnlocked)
        // Changed settings apply from the next list (pull to refresh, Refresh above, app start);
        // leaving here only builds one when none is shown yet.
        .onDisappear { engine.refreshIfNeeded() }
        // Feedback for Refresh: a prepared list swaps in instantly and would otherwise go unseen.
        .onChange(of: engine.builtAt) { old, new in
            guard old != nil, new != nil, engine.state == .ready else { return }
            ToastManager.shared.show(tr("new_suggestions_on_home"), icon: "sparkles", style: .success)
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("for_you"), isBeta: true)

            HStack {
                Label(tr("status"), systemImage: "sparkles")
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
                    Label(tr("action_refresh_suggestions"), systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(appearanceManager.tintColor)
                    Spacer()
                    if engine.isRefreshing { ProgressView() }
                }
            }
            .disabled(engine.isRefreshing)
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter(tr("hint_picked_on_this_device_from"))
        }
    }

    private var historySection: some View {
        Section {
            stashyScrollingSectionHeader(tr("watch_history"))

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("look_back"))
                Picker(tr("look_back"), selection: $engine.lookbackDays) {
                    ForEach(SceneRecommendationEngine.lookbackChoices, id: \.self) { days in
                        Text(tr("arg_count_days", days)).tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
            .stashyGroupedBlockRow(index: 0, count: 2)

            Stepper(value: $engine.count, in: SceneRecommendationEngine.countRange) {
                HStack {
                    Text(tr("suggestions"))
                    Spacer()
                    Text("\(engine.count)").foregroundColor(.secondary)
                }
            }
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter(tr("hint_scenes_played_in_this_period"))
        }
    }

    private var discoverySection: some View {
        Section {
            stashyScrollingSectionHeader(tr("what_to_suggest"))

            Picker(tr("what_to_suggest"), selection: $engine.discovery) {
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
            stashyScrollingSectionHeader(tr("influence"))

            weightRow(tr("similar_to_watched"), icon: "square.stack.3d.up.fill", value: $engine.similarWeight, index: 0)
            weightRow(tr("performers"), icon: "person.fill", value: $engine.performerWeight, index: 1)
            weightRow(tr("studios"), icon: "building.2.fill", value: $engine.studioWeight, index: 2)
            weightRow(tr("tags"), icon: "tag.fill", value: $engine.tagWeight, index: 3)
            weightRow(tr("o_counts"), icon: appearanceManager.oCounterIcon, value: $engine.oCountWeight, index: 4)
            weightRow(tr("ratings"), icon: "star.fill", value: $engine.ratingWeight, index: 5)

            stashyScrollingSectionFooter(tr("hint_how_much_each_part_steers"))
        }
    }

    private var adjustmentsSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("performers_studios_and_tags"))

            NavigationLink(destination: LazyView { RecommendationAdjustmentsView() }) {
                HStack {
                    Label(tr("adjustments"), systemImage: "slider.horizontal.3")
                    Spacer()
                    Text(adjustmentsSummary)
                        .foregroundColor(.secondary)
                }
            }
            .stashyGroupedSettingsRow()

            stashyScrollingSectionFooter(tr("hint_also_from_menu_below_card"))
        }
    }

    private var adjustmentsSummary: String {
        let list = engine.adjustments
        guard !list.isEmpty else { return tr("none") }
        let hidden = list.filter(\.isHidden).count
        return hidden > 0 ? tr("arg_arg_hidden", list.count, hidden) : "\(list.count)"
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                engine.resetSettings()
            } label: {
                Label(tr("action_reset_to_defaults"), systemImage: "arrow.uturn.backward")
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
        case ..<0.01: return tr("off")
        case ..<0.75: return tr("low")
        case ..<1.26: return tr("normal")
        case ..<1.76: return tr("high")
        default: return tr("max")
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: return tr("not_built_yet")
        case .loading: return tr("looking_menu")
        case .ready where engine.isRefreshing: return tr("looking_menu")
        case .noHistory: return tr("empty_plays_yet")
        case .failed(let message): return message
        case .ready:
            let picks = tr("arg_scenes_from_arg_watched", engine.homeItems.count, engine.seedCount)
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
                                    Label(tr("action_remove"), systemImage: "trash")
                                }
                            }
                    }
                }
            }

            Section {
                stashyScrollingSectionFooter(tr("hint_hidden_never_shows_it_above_1"))
            }

            if !engine.adjustments.isEmpty {
                Section {
                    Button(role: .destructive) {
                        confirmsRemoveAll = true
                    } label: {
                        Label(tr("action_remove_all"), systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .stashyGroupedSettingsRow()
                }
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("adjustments"))
        .sheet(item: $addKind) { kind in
            RecommendationAdjustmentPicker(kind: kind)
        }
        .alert(tr("confirm_remove_all_adjustments"), isPresented: $confirmsRemoveAll) {
            Button(tr("action_remove_all"), role: .destructive) { engine.removeAllAdjustments() }
            Button(tr("action_cancel"), role: .cancel) {}
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
                        Text(names.isEmpty ? SceneRecommendationEngine.preparingMessage : tr("nothing_found"))
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
            TextField(tr("search"), text: $search)
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
                Label(tr("tags"), systemImage: "tag.fill")
            }
        }
    }

    private func itemMenu(_ kind: RecommendationAdjustment.Kind, id: String, name: String) -> some View {
        let current = engine.adjustment(kind, id)
        return Menu {
            Button {
                apply(kind, id: id, name: name, factor: RecommendationAdjustment.more)
            } label: {
                Label(tr("more_like_this"), systemImage: "hand.thumbsup")
            }
            Button {
                apply(kind, id: id, name: name, factor: RecommendationAdjustment.less)
            } label: {
                Label(tr("less_like_this"), systemImage: "hand.thumbsdown")
            }
            Button(role: .destructive) {
                apply(kind, id: id, name: name, factor: 0)
            } label: {
                Label(tr("never_suggest"), systemImage: "eye.slash")
            }
            if current != nil {
                Button {
                    engine.removeAdjustment(kind, id: id)
                    engine.applyAdjustmentsNow()
                } label: {
                    Label(tr("back_to_normal"), systemImage: "arrow.uturn.backward")
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
        case ..<RecommendationAdjustment.hiddenBelow: message = tr("arg_wont_be_suggested", name)
        case ..<1: message = tr("less_of_arg", name)
        default: message = tr("more_of_arg", name)
        }
        ToastManager.shared.show(message, icon: factor < RecommendationAdjustment.hiddenBelow ? "eye.slash" : "sparkles", style: .success)
    }
}

#endif
