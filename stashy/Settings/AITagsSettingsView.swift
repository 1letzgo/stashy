//
//  AITagsSettingsView.swift
//  stashy
//
//  stashy+ hub for AI Tags: kill switch, tuning, the on-device index, and a
//  review queue for untagged images.
//

#if !os(tvOS)

import SwiftUI

struct AITagsSettingsView: View {
    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    @State private var showingDeleteConfirmation = false

    private var isUnlocked: Bool { stashyPlus.isUnlocked }

    var body: some View {
        List {
            if !isUnlocked {
                Section {
                    Label("AI Tags requires stashy+", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                    stashyScrollingSectionFooter("Unlock stashy+ to use this feature.")
                }
            }

            enableSection
            tuningSection
            autoAcceptSection
            signalsSection
            if manager.useVision {
                indexSection
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("AI Tags")
        .task { await manager.loadIndexIfNeeded() }
        .alert("Delete index?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { manager.deleteIndex() }
        } message: {
            Text("The index for this server is removed from the device. Suggestions stay off until you build it again.")
        }
    }

    // MARK: - Sections

    private var enableSection: some View {
        Section {
            stashyScrollingSectionHeader("AI Tags", isBeta: true)
            Toggle(isOn: enabledBinding) {
                Label("Tag suggestions", systemImage: "sparkles")
            }
            .tint(appearanceManager.tintColor)
            .disabled(!isUnlocked)
            .stashyGroupedSettingsRow()

            stashyScrollingSectionFooter("Suggestions come from your own library: how often this item's performers are tagged with each tag. They appear automatically in Feeds (Clips) and in the fullscreen image viewer; tap a suggested tag to add it. Tags an item already has are never suggested.")
        }
    }

    private var tuningSection: some View {
        Section {
            stashyScrollingSectionHeader("Tuning")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Minimum confidence")
                    Spacer()
                    Text("\(Int((manager.minConfidence * 100).rounded()))%")
                        .foregroundColor(.secondary)
                }
                Slider(value: $manager.minConfidence, in: 0.05...0.8, step: 0.05)
                    .tint(appearanceManager.tintColor)
            }
            .padding(.vertical, 4)
            .stashyGroupedBlockRow(index: 0, count: 3)

            Stepper(value: $manager.maxSuggestions, in: 1...20) {
                HStack {
                    Text("Suggestions per item")
                    Spacer()
                    Text("\(manager.maxSuggestions)").foregroundColor(.secondary)
                }
            }
            .stashyGroupedBlockRow(index: 1, count: 3)

            Stepper(value: $manager.framesPerClip, in: 1...10) {
                HStack {
                    Text("Frames per clip")
                    Spacer()
                    Text("\(manager.framesPerClip)").foregroundColor(.secondary)
                }
            }
            .stashyGroupedBlockRow(index: 2, count: 3)

            stashyScrollingSectionFooter("The confidence floor only filters image analysis — statistically backed tags are ranked, not cut off, so a performer's whole habitual tag list can show up. Frames per clip only applies with image analysis on: clips are sampled across their whole duration, stills always use a single frame.")
        }
        .disabled(!isUnlocked || !manager.isEnabled)
    }

    private var autoAcceptSection: some View {
        Section {
            stashyScrollingSectionHeader("Auto-accept")

            Toggle(isOn: $manager.autoAccept) {
                Label("Add confident tags automatically", systemImage: "checkmark.seal")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Auto-accept above")
                    Spacer()
                    Text("\(Int((manager.autoAcceptThreshold * 100).rounded()))%")
                        .foregroundColor(.secondary)
                }
                Slider(value: $manager.autoAcceptThreshold, in: 0.5...0.95, step: 0.05)
                    .tint(appearanceManager.tintColor)
            }
            .padding(.vertical, 4)
            .disabled(!manager.autoAccept)
            .stashyGroupedBlockRow(index: 1, count: 2)

            stashyScrollingSectionFooter("Suggestions at or above this confidence are written to the server without asking. Everything below stays a tap-to-add chip. Start high — a wrong tag has to be removed by hand.")
        }
        .disabled(!isUnlocked || !manager.isEnabled)
    }

    private var signalsSection: some View {
        Section {
            stashyScrollingSectionHeader("Signals")

            Toggle(isOn: $manager.usePerformerStats) {
                Label("Performer tag statistics", systemImage: "person.text.rectangle")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 0, count: 3)

            Toggle(isOn: $manager.useStudioStats) {
                Label("Studio tag statistics", systemImage: "building.2")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 1, count: 3)

            Toggle(isOn: $manager.useVision) {
                Label("Image analysis (Vision)", systemImage: "eye")
            }
            .tint(appearanceManager.tintColor)
            .stashyGroupedBlockRow(index: 2, count: 3)

            stashyScrollingSectionFooter("Statistics rank tags by how often this item's performers or studio already carry them, counted across their images and scenes — instant, no index, but the same answer for everything a performer is in. Vision analyses the picture on device (nothing leaves your phone) and is what can tell one clip from the next, at the cost of an index and a slower analysis. Both can run together; where they agree the suggestion scores higher.")
        }
        .disabled(!isUnlocked || !manager.isEnabled)
    }

    private var indexSection: some View {
        Section {
            stashyScrollingSectionHeader("On-device index")

            HStack {
                Label("Status", systemImage: "internaldrive")
                Spacer()
                Text(statusText)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .stashyGroupedBlockRow(index: 0, count: 4)

            if case .building(let processed, let total) = manager.indexState {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: manager.indexProgress)
                        .tint(appearanceManager.tintColor)
                    Text("\(processed) / \(total) images")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 1, count: 4)
            } else {
                Stepper(value: $manager.indexLimit, in: 250...5000, step: 250) {
                    HStack {
                        Text("Index size limit")
                        Spacer()
                        Text("\(manager.indexLimit)").foregroundColor(.secondary)
                    }
                }
                .disabled(!isUnlocked || !manager.isEnabled || !manager.useVision)
                .stashyGroupedBlockRow(index: 1, count: 4)
            }

            Button {
                if case .building = manager.indexState {
                    manager.cancelWork()
                } else {
                    manager.rebuildIndex()
                }
            } label: {
                Label(buildButtonTitle, systemImage: buildButtonIcon)
                    .foregroundColor(appearanceManager.tintColor)
            }
            .disabled(!isUnlocked || !manager.isEnabled || !manager.useVision)
            .stashyGroupedBlockRow(index: 2, count: 4)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete index", systemImage: "trash")
                    .foregroundColor(.red)
            }
            .disabled(manager.indexedCount == 0)
            .stashyGroupedBlockRow(index: 3, count: 4)

            stashyScrollingSectionFooter("The index learns your tag vocabulary from a random sample of images that already carry tags. Rebuild it after tagging a batch of new material. Each server keeps its own index on this device — switching servers loads that server's index instead of deleting anything.")
        }
    }

    // MARK: - Helpers

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isUnlocked && manager.isEnabled },
            set: { newValue in
                guard isUnlocked else { return }
                manager.isEnabled = newValue
                if newValue {
                    Task { await manager.loadIndexIfNeeded() }
                }
            }
        )
    }

    private var statusText: String {
        switch manager.indexState {
        case .idle:
            return manager.indexedCount > 0 ? "\(manager.indexedCount) images" : "Not built"
        case .loading:
            return "Loading…"
        case .building:
            return "Building…"
        case .ready(let entries):
            if let date = manager.lastBuiltAt {
                return "\(entries) images · \(date.formatted(date: .abbreviated, time: .shortened))"
            }
            return "\(entries) images"
        case .failed(let message):
            return message
        }
    }

    private var buildButtonTitle: String {
        if case .building = manager.indexState { return "Stop building" }
        return manager.indexedCount > 0 ? "Rebuild index" : "Build index"
    }

    private var buildButtonIcon: String {
        if case .building = manager.indexState { return "stop.circle" }
        return "arrow.triangle.2.circlepath"
    }
}

#endif
