
#if !os(tvOS)
import SwiftUI

struct AddGalleryToSceneSheet: View {
    let sceneId: String
    let currentGalleries: [Gallery]
    let performerIds: [String]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Gallery]) -> Void

    @Environment(\.stashyDismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var performerGalleries: [Gallery] = []
    @State private var allGalleries: [Gallery] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var didLoadAll = false

    private var filteredPerformerGalleries: [Gallery] {
        filter(performerGalleries)
    }

    private var filteredOtherGalleries: [Gallery] {
        let performerSet = Set(performerGalleries.map(\.id))
        return filter(allGalleries).filter { !performerSet.contains($0.id) }
    }

    private var showingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(tr("search_galleries"))) {
                    TextField(tr("placeholder_search"), text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                loadAllGalleriesIfNeeded()
                            }
                        }
                }
                .listRowBackground(Color.secondaryAppBackground)

                if isLoading && performerGalleries.isEmpty && allGalleries.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView(tr("loading_ellipsis")); Spacer() }.padding()
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                } else {
                    if !performerIds.isEmpty {
                        Section(header: Text(showingSearchResults ? tr("from_scene_performers") : tr("galleries_from_scene_performers"))) {
                            if filteredPerformerGalleries.isEmpty {
                                Text(showingSearchResults ? tr("empty_matching_performer_galleries") : tr("empty_galleries_for_linked_performers"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filteredPerformerGalleries.prefix(showingSearchResults ? 30 : 50)) { gallery in
                                    galleryRow(gallery)
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    }

                    if showingSearchResults {
                        Section(header: Text(performerIds.isEmpty ? tr("galleries") : tr("other_galleries"))) {
                            if !didLoadAll && isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else if filteredOtherGalleries.isEmpty {
                                Text(tr("empty_matching_galleries"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filteredOtherGalleries.prefix(30)) { gallery in
                                    galleryRow(gallery)
                                }
                                if filteredOtherGalleries.count > 30 {
                                    Text(tr("type_more_to_refine_menu"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    } else if performerIds.isEmpty {
                        Section(header: Text(tr("all_galleries"))) {
                            if allGalleries.isEmpty && isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else {
                                ForEach(allGalleries.prefix(30)) { gallery in
                                    galleryRow(gallery)
                                }
                                if allGalleries.count > 30 {
                                    Text(tr("type_to_search_menu"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    }
                }
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("action_edit_galleries"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: tr("action_save"), enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(currentGalleries.map { $0.id })
                loadInitial()
            }
        }
    }

    private func galleryRow(_ gallery: Gallery) -> some View {
        HStack(spacing: 12) {
            galleryPreview(gallery)
            VStack(alignment: .leading, spacing: 2) {
                Text(gallery.displayName)
                    .font(.body)
                    .lineLimit(2)
                if let count = gallery.imageCount {
                    Text(tr(count == 1 ? "arg_count_image" : "arg_count_images", count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if selectedIds.contains(gallery.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(appearanceManager.tintColor)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedIds.contains(gallery.id) {
                selectedIds.remove(gallery.id)
            } else {
                selectedIds.insert(gallery.id)
            }
        }
    }

    @ViewBuilder
    private func galleryPreview(_ gallery: Gallery) -> some View {
        let size: CGFloat = 52
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(appearanceManager.tintColor.opacity(0.12))
            if let url = gallery.coverURL {
                CustomAsyncImage(url: url) { loader in
                    if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18))
                            .foregroundColor(appearanceManager.tintColor.opacity(0.5))
                    }
                }
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18))
                    .foregroundColor(appearanceManager.tintColor.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func filter(_ galleries: [Gallery]) -> [Gallery] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return galleries }
        return galleries.filter {
            $0.title.lowercased().contains(q) || $0.displayName.lowercased().contains(q)
        }
    }

    private func loadInitial() {
        isLoading = true
        let group = DispatchGroup()

        if !performerIds.isEmpty {
            group.enter()
            viewModel.fetchGalleriesForSceneEdit(performerIds: performerIds) { fetched in
                DispatchQueue.main.async {
                    self.performerGalleries = fetched
                    group.leave()
                }
            }
        } else {
            group.enter()
            viewModel.fetchGalleriesForSceneEdit(performerIds: []) { fetched in
                DispatchQueue.main.async {
                    self.allGalleries = fetched
                    self.didLoadAll = true
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            self.isLoading = false
        }
    }

    private func loadAllGalleriesIfNeeded() {
        guard !didLoadAll else { return }
        didLoadAll = true
        isLoading = true
        viewModel.fetchGalleriesForSceneEdit(performerIds: []) { fetched in
            DispatchQueue.main.async {
                self.allGalleries = fetched
                self.isLoading = false
            }
        }
    }

    private func save() {
        isSaving = true
        let ids = Array(selectedIds)
        viewModel.updateSceneGalleries(sceneId: sceneId, galleryIds: ids) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var byId: [String: Gallery] = [:]
                    for g in performerGalleries + allGalleries + currentGalleries {
                        byId[g.id] = g
                    }
                    let updated = ids.compactMap { byId[$0] }
                    onComplete(updated)
                    dismiss()
                } else {
                    ToastManager.shared.show(tr("error_update_galleries"), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
