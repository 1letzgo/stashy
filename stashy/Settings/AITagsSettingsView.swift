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

            Button {
                manager.resetDismissals()
            } label: {
                HStack {
                    Label(tr("ignored_tags"), systemImage: "hand.thumbsdown")
                        .foregroundColor(appearanceManager.tintColor)
                    Spacer()
                    Text(manager.dismissedTagCount == 0 ? tr("none") : tr("arg_reset_suffix", manager.dismissedTagCount))
                        .foregroundColor(.secondary)
                }
            }
            .disabled(manager.dismissedTagCount == 0)
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

#endif
