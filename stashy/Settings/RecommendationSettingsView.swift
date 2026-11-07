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

            stashyScrollingSectionFooter("Suggests scenes on Home from what you played, the O-Counts you gave and your ratings. Each card says why it was picked. Everything is worked out on this device from your own server. Move or hide the row in Settings › Home.")
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

            stashyScrollingSectionFooter("Recent plays count more than older ones. Scenes you played in this period are never suggested again. With nothing played in it, your top O-Count and best-rated scenes stand in.")
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

            stashyScrollingSectionFooter("How much each part of your history steers the picks. Similar to watched finds unplayed scenes close to single scenes you watched a lot. Off leaves a part out. With Tag Suggestions statistics built, tags that often go with your favorite tags count as well.")
        }
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

#endif
