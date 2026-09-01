//
//  AddTagToImageSheet.swift
//  stashy
//
//  Image counterpart to `AddTagToSceneSheet`: search, multi-select, create a missing
//  tag, save in one mutation. Reached from the "+" chip in the tag row of Feeds
//  (Clips) and the fullscreen image viewer.
//

#if !os(tvOS)

import SwiftUI

struct AddTagToImageSheet: View {
    let imageId: String
    let currentTags: [Tag]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Tag]) -> Void

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
                                if let count = tag.imageCount {
                                    Spacer()
                                    Text("\(count) images").font(.caption).foregroundColor(.secondary)
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

    private func save() {
        isSaving = true
        viewModel.updateImageTags(imageId: imageId, tagIds: Array(selectedIds)) { success in
            DispatchQueue.main.async {
                isSaving = false
                guard success else {
                    ToastManager.shared.show("Failed to update tags", icon: "exclamationmark.triangle", style: .error)
                    return
                }
                onComplete(allTags.filter { selectedIds.contains($0.id) })
                dismiss()
            }
        }
    }
}

#endif
