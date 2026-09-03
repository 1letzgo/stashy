//
//  AITagSuggestionBar.swift
//  stashy
//
//  Chip row with tag suggestions for one item — scene, marker, clip or picture.
//  Renders nothing at all unless AI Tags is unlocked *and* switched on, so the
//  Reels / fullscreen chrome stays byte-identical for everyone else.
//

#if !os(tvOS)

import SwiftUI

struct AITagSuggestionBar: View {
    let target: AITagTarget
    /// Called with the item's new tag list after a suggestion was accepted.
    var onTagsChanged: ([Tag]) -> Void

    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var suggestions: [AITagSuggestion] = []
    @State private var didRun = false
    @State private var acceptingTagId: String?
    @State private var pendingBulk: AITagSuggestionManager.BulkPlan?
    @State private var isPlanningBulk = false

    /// Chips only — the caller puts them into its own tag row, so suggestions sit
    /// inline with the tags the item already has.
    var body: some View {
        if manager.isActive {
            content
                .task(id: target.id) { await prepare() }
                .alert(item: $pendingBulk) { plan in
                    Alert(
                        title: Text("Add #\(plan.tag.name)?"),
                        message: Text(bulkMessage(for: plan)),
                        primaryButton: .default(Text("Add to \(plan.total)")) {
                            applyBulk(plan)
                        },
                        secondaryButton: .cancel()
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 6) {
            if suggestions.isEmpty {
                // Only worth saying on an untagged item — where a missing suggestion is the
                // whole story. On an already tagged one it is just noise under the tag row.
                if didRun, target.tags.isEmpty {
                    Text(manager.hasModel ? "No tag suggestions" : "Tag Suggestion needs statistics first")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
            } else {
                ForEach(suggestions) { suggestion in
                    chip(for: suggestion)
                }
            }
        }
    }

    private func chip(for suggestion: AITagSuggestion) -> some View {
        Button {
            accept(suggestion)
        } label: {
            HStack(spacing: 4) {
                if acceptingTagId == suggestion.tag.id {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.white)
                        .frame(width: 9, height: 9)
                } else {
                    // The sparkles mark each chip as a suggestion, so the row needs no
                    // separate marker in front of them.
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                }
                Text("#\(suggestion.tag.name)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(Int((suggestion.confidence * 100).rounded()))%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(appearanceManager.tintColor.opacity(0.22))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(appearanceManager.tintColor.opacity(0.55), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(acceptingTagId != nil)
        .contextMenu {
            Button(role: .destructive) {
                manager.dismiss(suggestion, on: target)
                HapticManager.light()
                withAnimation { suggestions.removeAll { $0.id == suggestion.id } }
            } label: {
                Label("Ignore Tag", systemImage: "xmark")
            }

            if !target.galleryIds.isEmpty {
                Button {
                    planBulk(suggestion.tag, scope: .gallery)
                } label: {
                    Label("Set on all of gallery", systemImage: "photo.stack")
                }
            }

            if !target.performerIds.isEmpty {
                Button {
                    planBulk(suggestion.tag, scope: .performer)
                } label: {
                    Label("Set on all of performer", systemImage: "person.text.rectangle")
                }
            }
        }
        .accessibilityLabel("Add tag \(suggestion.tag.name)")
    }

    // MARK: - Actions

    private func prepare() async {
        suggestions = []
        didRun = false
        acceptingTagId = nil

        if let cached = manager.cachedSuggestions(for: target) {
            suggestions = cached
            didRun = true
            return
        }
        await lookUp()
    }

    private func lookUp() async {
        let result = await manager.suggestions(for: target)
        // The feed may have moved on while the model was still loading.
        guard !Task.isCancelled else { return }
        let existing = Set(target.tags.map(\.id))
        withAnimation(.easeInOut(duration: 0.2)) {
            suggestions = result.filter { !existing.contains($0.tag.id) }
        }
        didRun = true
    }

    private func bulkMessage(for plan: AITagSuggestionManager.BulkPlan) -> String {
        let scope = plan.scope == .gallery ? "this gallery" : "this performer"
        var parts: [String] = []
        if !plan.imageIds.isEmpty { parts.append("\(plan.imageIds.count) images") }
        if !plan.sceneIds.isEmpty { parts.append("\(plan.sceneIds.count) scenes") }
        return "The tag is added to \(parts.joined(separator: " and ")) of \(scope). Items that already have it stay unchanged."
    }

    /// Counts first, asks second: a bulk write can touch hundreds of items, and undoing
    /// it means removing the tag one by one.
    private func planBulk(_ tag: Tag, scope: AITagSuggestionManager.BulkScope) {
        guard !isPlanningBulk else { return }
        isPlanningBulk = true
        Task {
            let plan = await manager.planBulkApply(tag, scope: scope, target: target)
            isPlanningBulk = false
            guard let plan else {
                ToastManager.shared.show("Nothing to tag", icon: "info.circle", style: .info)
                return
            }
            pendingBulk = plan
        }
    }

    private func applyBulk(_ plan: AITagSuggestionManager.BulkPlan) {
        Task {
            let success = await manager.applyBulk(plan, target: target)
            guard success else {
                HapticManager.error()
                ToastManager.shared.show("Could not apply tag", icon: "exclamationmark.triangle.fill", style: .error)
                return
            }
            HapticManager.success()
            ToastManager.shared.show("Added #\(plan.tag.name) to \(plan.total) items")
            // The item itself is part of the batch, so its own row has to follow.
            if !target.tags.contains(where: { $0.id == plan.tag.id }) {
                onTagsChanged(target.tags + [plan.tag])
            }
            withAnimation { suggestions.removeAll { $0.tag.id == plan.tag.id } }
        }
    }

    private func accept(_ suggestion: AITagSuggestion) {
        guard acceptingTagId == nil else { return }
        acceptingTagId = suggestion.tag.id
        HapticManager.light()
        Task {
            let newTags = await manager.accept(suggestion, on: target)
            acceptingTagId = nil
            guard let newTags else {
                HapticManager.error()
                ToastManager.shared.show("Could not add tag", icon: "exclamationmark.triangle.fill", style: .error)
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions.removeAll { $0.tag.id == suggestion.tag.id }
            }
            HapticManager.success()
            ToastManager.shared.show("Added #\(suggestion.tag.name)")
            onTagsChanged(newTags)
        }
    }
}

#endif
