//
//  AITagSuggestionBar.swift
//  stashy
//
//  Chip row with on-device tag suggestions for a single image (clip or pic).
//  Renders nothing at all unless AI Tags is unlocked *and* switched on, so the
//  Reels / fullscreen chrome stays byte-identical for everyone else.
//

#if !os(tvOS)

import SwiftUI

struct AITagSuggestionBar: View {
    let image: StashImage
    /// Called with the image's new tag list after a suggestion was accepted.
    var onTagsChanged: ([Tag]) -> Void

    @ObservedObject private var manager = AITagSuggestionManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var suggestions: [AITagSuggestion] = []
    @State private var isAnalyzing = false
    @State private var didRun = false
    @State private var acceptingTagId: String?

    /// Chips only — the caller puts them into its own tag row, so suggestions sit
    /// inline with the tags the item already has.
    var body: some View {
        if manager.isActive {
            content
                .task(id: image.id) { await prepare() }
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 6) {
            if isAnalyzing {
                HStack(spacing: 4) {
                    // scaleEffect alone keeps the spinner's 20pt intrinsic size, which made
                    // this pill taller than every tag chip next to it.
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.white)
                        .frame(width: 10, height: 10)
                    Text("Analyzing…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.3))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            } else if suggestions.isEmpty {
                // Only worth saying on an untagged item — where a missing suggestion is the
                // whole story. On an already tagged one it is just noise under the tag row.
                if didRun, (image.tags ?? []).isEmpty {
                    Text("No tag suggestions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(appearanceManager.tintColor)

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
                    Image(systemName: "plus")
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
                withAnimation { suggestions.removeAll { $0.id == suggestion.id } }
            } label: {
                Label("Dismiss suggestion", systemImage: "xmark")
            }
        }
        .accessibilityLabel("Add tag \(suggestion.tag.name)")
    }

    // MARK: - Actions

    private func prepare() async {
        suggestions = []
        didRun = false
        isAnalyzing = false
        acceptingTagId = nil

        if let cached = manager.cachedSuggestions(for: image) {
            suggestions = cached
            didRun = true
            return
        }

        // Let a fast scroll pass by before spending Vision on an item nobody stopped at —
        // the task is cancelled the moment the feed moves to the next id.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        await analyze(force: false)
    }

    private func analyze(force: Bool) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        let result = await manager.suggestions(for: image, forceRefresh: force)
        // The feed may have moved on while Vision was running.
        guard !Task.isCancelled else { return }
        let existing = Set((image.tags ?? []).map(\.id))
        var pending = result.filter { !existing.contains($0.tag.id) }

        // Auto-accept takes the confident ones straight to the server; whatever stays
        // below the bar remains a tap-to-add chip.
        if manager.autoAccept {
            let confident = pending.filter { $0.confidence >= manager.autoAcceptThreshold }
            if !confident.isEmpty {
                pending.removeAll { suggestion in
                    confident.contains { $0.tag.id == suggestion.tag.id }
                }
                if let newTags = await manager.accept(confident, on: image) {
                    HapticManager.success()
                    let names = confident.map { "#\($0.tag.name)" }.joined(separator: " ")
                    ToastManager.shared.show("Auto-added \(names)")
                    onTagsChanged(newTags)
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            suggestions = pending
        }
        isAnalyzing = false
        didRun = true
    }

    private func accept(_ suggestion: AITagSuggestion) {
        guard acceptingTagId == nil else { return }
        acceptingTagId = suggestion.tag.id
        HapticManager.light()
        Task {
            let newTags = await manager.accept(suggestion, on: image)
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
