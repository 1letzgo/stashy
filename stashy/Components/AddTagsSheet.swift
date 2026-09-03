//
//  AddTagsSheet.swift
//  stashy
//
//  Search, multi-select, create a missing tag, save in one mutation — for whatever
//  the tag row belongs to: a scene, a marker, a clip or a picture. Reached from the
//  "+" chip in Feeds and the fullscreen image viewer.
//

#if !os(tvOS)

import SwiftUI

struct AddTagsSheet: View {
    let target: AITagTarget
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Tag]) -> Void

    private var currentTags: [Tag] { target.tags }

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared

    @State private var allTags: [Tag] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var isCreating = false
    /// tag id → how often this item's performers carry it (statistics model).
    @State private var performerCounts: [String: Int] = [:]

    private var filtered: [Tag] {
        if searchText.isEmpty { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// How often a tag is used on the kind of item being edited — the sort key, and
    /// what the row shows on the right.
    private func usage(of tag: Tag) -> Int {
        switch target.kind {
        case .image: return tag.imageCount ?? 0
        case .scene, .marker: return tag.sceneCount ?? 0
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Tags")) {
                    TextField("Search...", text: $searchText)

                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                Text(usageLabel(for: tag))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if selectedIds.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(tag.id) {
                                    selectedIds.remove(tag.id)
                                } else {
                                    selectedIds.insert(tag.id)
                                }
                            }
                        }

                        if filtered.count > 30 {
                            Text("Type more to refine...").font(.caption).foregroundColor(.secondary)
                        }

                        if !searchText.isEmpty && filtered.isEmpty {
                            Button {
                                createAndSelect()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create \"\(searchText)\"")
                                }
                                .foregroundColor(appearanceManager.tintColor)
                            }
                            .disabled(isCreating)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Edit Tags", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(currentTags.map(\.id))
                performerCounts = AITagSuggestionManager.shared.performerTagCounts(for: target)

                // The statistics build already captured the whole tag list. Reusing it
                // opens the picker instantly instead of waiting on a 1000-tag query.
                let known = AITagSuggestionManager.shared.vocabulary
                if !known.isEmpty {
                    apply(fetched: known)
                    return
                }

                isLoading = true
                let sortField = target.kind == .image ? "images_count" : "scenes_count"
                viewModel.fetchAllTags(sortField: sortField) { fetched in
                    DispatchQueue.main.async {
                        apply(fetched: fetched)
                    }
                }
            }
        }
    }

    private func apply(fetched: [Tag]) {
        // Tags the item already carries may sit outside the fetched page.
        var merged = fetched
        for tag in currentTags where !merged.contains(where: { $0.id == tag.id }) {
            merged.append(tag)
        }
        // With only the top 30 rows on screen, ordering decides what is reachable at all.
        // The item's own tags stay on top so they can be removed; then what this
        // performer is usually tagged with, which beats what the library uses most.
        let currentIds = Set(currentTags.map(\.id))
        let counts = performerCounts
        allTags = merged.sorted { lhs, rhs in
            let lhsCurrent = currentIds.contains(lhs.id)
            let rhsCurrent = currentIds.contains(rhs.id)
            if lhsCurrent != rhsCurrent { return lhsCurrent }
            let lhsPerformer = counts[lhs.id] ?? 0
            let rhsPerformer = counts[rhs.id] ?? 0
            if lhsPerformer != rhsPerformer { return lhsPerformer > rhsPerformer }
            let lhsUsage = usage(of: lhs)
            let rhsUsage = usage(of: rhs)
            if lhsUsage != rhsUsage { return lhsUsage > rhsUsage }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        isLoading = false
    }

    private func createAndSelect() {
        isCreating = true
        viewModel.createTag(name: searchText) { created in
            DispatchQueue.main.async {
                isCreating = false
                guard let tag = created else {
                    ToastManager.shared.show("Failed to create tag", icon: "exclamationmark.triangle", style: .error)
                    return
                }
                allTags.append(tag)
                selectedIds.insert(tag.id)
                searchText = ""
            }
        }
    }

    private func usageLabel(for tag: Tag) -> String {
        // A performer count says far more here than the library total, so it wins the
        // one line of space the row has.
        if let performerCount = performerCounts[tag.id], performerCount > 0 {
            return "\(performerCount)× performer"
        }
        let count = usage(of: tag)
        switch target.kind {
        case .image: return "\(count) images"
        case .scene, .marker: return "\(count) scenes"
        }
    }

    private func save() {
        isSaving = true
        // A marker's primary tag cannot be unselected here — it is a separate field in
        // Stash, so it stays whatever it was.
        var ids = selectedIds
        if let primary = target.primaryTagId { ids.insert(primary) }
        let updated = allTags.filter { ids.contains($0.id) }

        Task {
            let success = await AITagSuggestionManager.shared.write(tags: updated, to: target)
            isSaving = false
            guard success else {
                ToastManager.shared.show("Failed to update tags", icon: "exclamationmark.triangle", style: .error)
                return
            }
            onComplete(updated)
            dismiss()
        }
    }
}

#endif
