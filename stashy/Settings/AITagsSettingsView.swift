//
//  AITagsSettingsView.swift
//  stashy
//
//  stashy+ hub for Suggestions: one kill switch and one statistics model behind both tag
//  suggestions and Similar Scenes.
//

#if !os(tvOS)

import SwiftUI

struct AITagsSettingsView: View {
    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var similar = SimilarScenesFinder.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared


    private var isUnlocked: Bool { stashyPlus.isUnlocked }

    var body: some View {
        List {
            if !isUnlocked {
                Section {
                    Label("Suggestions require stashy+", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                    stashyScrollingSectionFooter("Unlock stashy+ to use this feature.")
                }
            }

            togglesSection
            modelSection
            tuningSection
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Suggestions")
        .task { await manager.loadIfNeeded() }
    }

    // MARK: - Sections

    private var togglesSection: some View {
        Section {
            stashyScrollingSectionHeader("Suggestions", isBeta: true)

            Toggle(isOn: enabledBinding) {
                Label("Tag suggestions", systemImage: "tag")
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
                Label("Similar scenes", systemImage: "square.stack.3d.up")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked)
            .stashyGroupedBlockRow(index: 1, count: 2)
        }
    }

    private var modelSection: some View {
        Section {
            stashyScrollingSectionHeader("Statistics")

            HStack {
                Label("Status", systemImage: "chart.bar.doc.horizontal")
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
                    Text("\(processed) of \(total) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 1, count: 3)

                Button(role: .destructive) {
                    manager.cancelWork()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
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

            stashyScrollingSectionFooter("Built automatically when Tag suggestions or Similar scenes is on, refreshed at app start once older than 12 hours, and removed from the device when both are off.")
        }
    }

    private var tuningSection: some View {
        Section {
            stashyScrollingSectionHeader("Tuning")

            Stepper(value: $manager.maxSuggestions, in: 1...20) {
                HStack {
                    Text("Tags per item")
                    Spacer()
                    Text("\(manager.maxSuggestions)").foregroundColor(.secondary)
                }
            }
            .disabled(!manager.isEnabled)
            .stashyGroupedBlockRow(index: 0, count: 3)

            Stepper(value: $similar.maxCount, in: 4...8) {
                HStack {
                    Text("Similar scenes")
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
                    Label("Ignored tags", systemImage: "hand.thumbsdown")
                        .foregroundColor(appearanceManager.tintColor)
                    Spacer()
                    Text(manager.dismissedTagCount == 0 ? "None" : "\(manager.dismissedTagCount) · reset")
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
            return "Not built"
        case .loading:
            return "Loading…"
        case .building:
            return "Counting…"
        case .ready(let items):
            if let date = manager.lastBuiltAt {
                return "\(items) items · \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "\(items) items"
        case .failed(let message):
            return message
        }
    }

    private var buildButtonTitle: String {
        manager.hasModel ? "Rebuild statistics" : "Build statistics"
    }
}

#endif
