//
//  AITagsSettingsView.swift
//  stashy
//
//  stashy+ hub "Recommendations": tag suggestions, Similar Scenes and the For You row on
//  Home share one statistics model. For You is on whenever either switch is.
//

#if !os(tvOS)

import SwiftUI

struct AITagsSettingsView: View {
    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var similar = SimilarScenesFinder.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @ObservedObject private var forYou = SceneRecommendationEngine.shared
    @ObservedObject private var forgotten = ForgottenFavoritesEngine.shared


    private var isUnlocked: Bool { stashyPlus.isUnlocked }

    var body: some View {
        List {
            if !isUnlocked {
                Section {
                    Label(tr("recommendations_require_stashy_plus"), systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                    stashyScrollingSectionFooter(tr("hint_unlock_stashy_plus_to_use"))
                }
            }

            togglesSection
            forYouSection
            forgottenSection
            modelSection
            tuningSection
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("recommendations"))
        .task { await manager.loadIfNeeded() }
    }

    // MARK: - Sections

    private var togglesSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("features"), isBeta: true)

            Toggle(isOn: enabledBinding) {
                Label(tr("tag_suggestions"), systemImage: "tag")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked)
            .stashyGroupedBlockRow(index: 0, count: 2)

            Toggle(isOn: Binding(
                get: { isUnlocked && similar.isEnabled },
                set: { newValue in
                    guard isUnlocked else { return }
                    similar.isEnabled = newValue
                }
            )) {
                Label(tr("similar_scenes"), systemImage: "square.stack.3d.up")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked)
            .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }

    private var forYouSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("for_you_on_home"), isBeta: true)
            Toggle(isOn: Binding(
                get: { isUnlocked && forYou.hasStatistics && forYou.isEnabled },
                set: { newValue in
                    guard isUnlocked else { return }
                    forYou.isEnabled = newValue
                }
            )) {
                Label(tr("for_you"), systemImage: "wand.and.stars")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked || !forYou.hasStatistics)
            .stashyGroupedBlockRow(index: 0, count: 2)

            NavigationLink(destination: LazyView { RecommendationSettingsView() }) {
                Label(tr("for_you_settings"), systemImage: "slider.horizontal.3")
            }
            .disabled(!isUnlocked)
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter(forYou.hasStatistics
                ? tr("hint_scenes_picked_from_your_plays")
                : tr("hint_needs_tag_suggestions_or_similar"))
        }
    }

    private var forgottenSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("forgotten_favorites_on_home"), isBeta: true)
            Toggle(isOn: Binding(
                get: { isUnlocked && forgotten.hasStatistics && forgotten.isEnabled },
                set: { newValue in
                    guard isUnlocked else { return }
                    forgotten.isEnabled = newValue
                }
            )) {
                Label(tr("forgotten_favorites"), systemImage: "clock.arrow.circlepath")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked || !forgotten.hasStatistics)
            .stashyGroupedBlockRow(index: 0, count: 2)

            NavigationLink(destination: LazyView { ForgottenFavoritesSettingsView() }) {
                Label(tr("forgotten_favorites_settings"), systemImage: "slider.horizontal.3")
            }
            .disabled(!isUnlocked)
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter(forgotten.hasStatistics
                ? tr("hint_top_scenes_you_have_not")
                : tr("hint_needs_tag_suggestions_or_similar"))
        }
    }

    private var modelSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("statistics"))

            HStack {
                Label(tr("status"), systemImage: "chart.bar.doc.horizontal")
                Spacer()
                Text(statusText)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .stashyGroupedBlockRow(index: 0, count: isBuilding ? 3 : 2)

            if case .building(let processed, let total) = manager.state {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: manager.buildProgress)
                        .tint(appearanceManager.tintColor)
                    Text(tr("arg_of_arg_items", processed, total))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 1, count: 3)

                Button(role: .destructive) {
                    manager.cancelWork()
                } label: {
                    Label(tr("action_stop"), systemImage: "stop.circle")
                        .foregroundColor(.red)
                }
                .stashyGroupedBlockRow(index: 2, count: 3)
            } else {
                Button {
                    manager.rebuild()
                } label: {
                    Label(buildButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(appearanceManager.tintColor)
                }
                .disabled(!manager.needsStatistics)
                .stashyGroupedBlockRow(index: 1, count: 2)
            }

            stashyScrollingSectionFooter(tr("refreshed_every_12_hours"))
        }
    }

    private var tuningSection: some View {
        Section {
            stashyScrollingSectionHeader(tr("tuning"))

            Stepper(value: $manager.maxSuggestions, in: 1...20) {
                HStack {
                    Text(tr("tags_per_item"))
                    Spacer()
                    Text("\(manager.maxSuggestions)").foregroundColor(.secondary)
                }
            }
            .disabled(!manager.isEnabled)
            .stashyGroupedBlockRow(index: 0, count: 3)

            Stepper(value: $similar.maxCount, in: 4...8) {
                HStack {
                    Text(tr("similar_scenes"))
                    Spacer()
                    Text("\(similar.maxCount)").foregroundColor(.secondary)
                }
            }
            .disabled(!similar.isEnabled)
            .stashyGroupedBlockRow(index: 1, count: 3)

            NavigationLink(destination: LazyView { IgnoredTagsView() }) {
                HStack {
                    Label(tr("ignored_tags"), systemImage: "hand.thumbsdown")
                    Spacer()
                    Text(manager.dismissedTagCount == 0 ? tr("none") : "\(manager.dismissedTagCount)")
                        .foregroundColor(.secondary)
                }
            }
            .stashyGroupedBlockRow(index: 2, count: 3)
        }
        .disabled(!isUnlocked)
    }

    // MARK: - Helpers

    private var isBuilding: Bool {
        if case .building = manager.state { return true }
        return false
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isUnlocked && manager.isEnabled },
            set: { newValue in
                guard isUnlocked else { return }
                manager.isEnabled = newValue
            }
        )
    }

    private var statusText: String {
        switch manager.state {
        case .idle:
            return tr("not_built")
        case .loading:
            return tr("loading")
        case .building:
            return tr("counting_menu")
        case .ready(let items):
            if let date = manager.lastBuiltAt {
                return tr("arg_items_arg", items, date.formatted(date: .abbreviated, time: .shortened))
            }
            return tr("arg_items", items)
        case .failed(let message):
            return message
        }
    }

    private var buildButtonTitle: String {
        manager.hasModel ? tr("rebuild_statistics") : tr("build_statistics")
    }
}

// MARK: - Ignored Tags

/// Settings › Recommendations › Ignored Tags: every tag waved away with "Ignore Tag", each
/// removable on its own (swipe or the minus button), plus Reset All behind a confirmation.
/// Names come from the statistics; a tag they never saw is asked for on the server, and one
/// deleted there shows as "Unknown Tag" with its id — still removable.
struct IgnoredTagsView: View {
    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var fetchedNames: [String: String] = [:]
    @State private var missingIds: Set<String> = []
    @State private var search = ""
    @State private var confirmsResetAll = false

    private struct Entry: Identifiable {
        let id: String
        let name: String?
    }

    private var entries: [Entry] {
        manager.ignoredTagIds
            .map { Entry(id: $0, name: manager.knownTagName($0) ?? fetchedNames[$0]) }
            .sorted {
                switch ($0.name, $1.name) {
                case let (a?, b?): return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0.id < $1.id
                }
            }
    }

    /// The search field appears once the list is long enough to need it.
    private static let searchThreshold = 8

    private func filtered(_ all: [Entry]) -> [Entry] {
        let term = search.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return all }
        return all.filter { ($0.name ?? $0.id).localizedCaseInsensitiveContains(term) || $0.id == term }
    }

    var body: some View {
        let all = entries
        let shown = filtered(all)
        List {
            if all.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.thumbsdown")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(tr("empty_no_ignored_tags"))
                            .font(.headline)
                        Text(tr("hint_ignored_tags"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .stashyGroupedSettingsRow()
                }
            } else {
                if all.count >= Self.searchThreshold {
                    Section {
                        searchField
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                Section {
                    if shown.isEmpty {
                        Text(tr("nothing_found"))
                            .foregroundColor(.secondary)
                            .stashyGroupedSettingsRow()
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                            .stashyGroupedBlockRow(index: index, count: shown.count)
                            .swipeActions {
                                Button(role: .destructive) {
                                    withAnimation { manager.undismiss(tagId: entry.id) }
                                } label: {
                                    Label(tr("action_remove"), systemImage: "trash")
                                }
                            }
                    }
                    stashyScrollingSectionFooter(tr("hint_ignored_tags"))
                }

                Section {
                    Button(role: .destructive) {
                        confirmsResetAll = true
                    } label: {
                        Label(tr("action_reset_all"), systemImage: "arrow.counterclockwise")
                            .foregroundColor(.red)
                    }
                    .stashyGroupedSettingsRow()
                }
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("ignored_tags"))
        .alert(tr("confirm_reset_ignored_tags"), isPresented: $confirmsResetAll) {
            Button(tr("action_reset_all"), role: .destructive) {
                withAnimation { manager.resetDismissals() }
            }
            Button(tr("action_cancel"), role: .cancel) {}
        }
        .task {
            await manager.loadIfNeeded()
            await resolveMissingNames()
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tag")
                .foregroundColor(appearanceManager.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? (missingIds.contains(entry.id) ? tr("unknown_tag") : entry.id))
                    .lineLimit(1)
                    .foregroundColor(entry.name == nil ? .secondary : .primary)
                if entry.name == nil && missingIds.contains(entry.id) {
                    Text(verbatim: "ID \(entry.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                withAnimation { manager.undismiss(tagId: entry.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("action_remove"))
        }
        .padding(.vertical, 2)
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

    /// Ids the statistics don't know (built before the tag existed, or never built): ask the
    /// server, a few at a time. A tag the server no longer has is marked unknown.
    private func resolveMissingNames() async {
        let unresolved = manager.ignoredTagIds.filter { manager.knownTagName($0) == nil && fetchedNames[$0] == nil }
        guard !unresolved.isEmpty else { return }
        await withTaskGroup(of: (String, String?, Bool).self) { group in
            for id in unresolved.prefix(50) {
                group.addTask {
                    do {
                        let tag = try await TagRepository().fetchTagDetails(tagId: id)
                        return (id, tag?.name, tag == nil)
                    } catch {
                        return (id, nil, false)
                    }
                }
            }
            for await (id, name, isMissing) in group {
                if let name { fetchedNames[id] = name }
                if isMissing { missingIds.insert(id) }
            }
        }
    }
}

#endif
