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

    private var filtered: [Tag] {
        if searchText.isEmpty { return allTags }
        return allTags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                                if let count = usageCount(for: tag) {
                                    Spacer()
                                    Text(count).font(.caption).foregroundColor(.secondary)
                                }
                                if selectedIds.contains(tag.id) {
                                    Spacer()
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
                isLoading = true
                viewModel.fetchAllTags { fetched in
                    DispatchQueue.main.async {
                        // Tags the image already carries may sit outside the fetched page.
                        var merged = fetched
                        for tag in currentTags where !merged.contains(where: { $0.id == tag.id }) {
                            merged.append(tag)
                        }
                        self.allTags = merged
                        self.isLoading = false
                    }
                }
            }
        }
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

    private func usageCount(for tag: Tag) -> String? {
        switch target.kind {
        case .image:
            return tag.imageCount.map { "\($0) images" }
        case .scene, .marker:
            return tag.sceneCount.map { "\($0) scenes" }
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
            let success = await AITagSuggestionManager.write(tags: updated, to: target)
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
