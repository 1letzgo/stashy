
#if !os(tvOS)
import SwiftUI

struct SceneGalleriesCard: View {
    let sceneId: String
    let galleries: [Gallery]?
    let performers: [ScenePerformer]
    var onGalleriesUpdated: (([Gallery]) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

    private let thumbSize: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Galleries")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if appearanceManager.isEditModeEnabled {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if let galleries = galleries, !galleries.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(galleries) { gallery in
                        SceneGalleryImageStrip(
                            gallery: gallery,
                            thumbSize: thumbSize,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.bottom, 12)
            } else {
                Text("No galleries assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(isPresented: $showingAddSheet) {
            AddGalleryToSceneSheet(
                sceneId: sceneId,
                currentGalleries: galleries ?? [],
                performerIds: performers.map(\.id),
                viewModel: viewModel
            ) { updated in
                onGalleriesUpdated?(updated)
            }
        }
    }
}

private struct SceneGalleryImageStrip: View {
    let gallery: Gallery
    let thumbSize: CGFloat
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var images: [StashImage] = []
    @State private var isLoading = false

    private var cornerRadius: CGFloat { DesignTokens.CornerRadius.card * 0.75 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    galleryLinkTile
                }
                .buttonStyle(.plain)

                ForEach(images) { image in
                    NavigationLink(
                        destination: FullScreenImageView(
                            images: $images,
                            selectedImageId: image.id
                        )
                    ) {
                        imageThumb(image)
                    }
                    .buttonStyle(.plain)
                }

                if isLoading && images.isEmpty {
                    ProgressView()
                        .frame(width: thumbSize, height: thumbSize)
                }
            }
            .padding(.horizontal, 12)
        }
        .task(id: gallery.id) {
            await loadImages()
        }
    }

    private var galleryLinkTile: some View {
        ZStack {
            appearanceManager.tintColor.opacity(0.1)
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20, weight: .medium))
                Text(galleryImageCountLabel)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .foregroundColor(appearanceManager.tintColor)
            .padding(.horizontal, 4)
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(appearanceManager.tintColor.opacity(0.35), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel("\(gallery.displayName), \(galleryImageCountLabel) images")
    }

    private var galleryImageCountLabel: String {
        if let count = gallery.imageCount {
            return "\(count)"
        }
        return "—"
    }

    private func imageThumb(_ image: StashImage) -> some View {
        Group {
            if let url = image.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if let img = loader.image {
                        img
                            .resizable()
                            .scaledToFill()
                    } else {
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.gray.opacity(DesignTokens.Opacity.placeholder)
            Image(systemName: "photo")
                .foregroundColor(.secondary)
        }
    }

    @MainActor
    private func loadImages() async {
        isLoading = true
        let galleryId = gallery.id
        let fetched: [StashImage] = await withCheckedContinuation { continuation in
            viewModel.fetchGalleryPreviewImages(galleryId: galleryId, limit: 40) { images in
                continuation.resume(returning: images)
            }
        }
        images = fetched
        isLoading = false
    }
}

struct AddGalleryToSceneSheet: View {
    let sceneId: String
    let currentGalleries: [Gallery]
    let performerIds: [String]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Gallery]) -> Void

    @Environment(\.dismiss) var dismiss
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
                Section(header: Text("Search Galleries")) {
                    TextField("Search...", text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                loadAllGalleriesIfNeeded()
                            }
                        }
                }
                .listRowBackground(Color.secondaryAppBackground)

                if isLoading && performerGalleries.isEmpty && allGalleries.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                } else {
                    if !performerIds.isEmpty {
                        Section(header: Text(showingSearchResults ? "From Scene Performers" : "Galleries from Scene Performers")) {
                            if filteredPerformerGalleries.isEmpty {
                                Text(showingSearchResults ? "No matching performer galleries" : "No galleries for linked performers")
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
                        Section(header: Text(performerIds.isEmpty ? "Galleries" : "Other Galleries")) {
                            if !didLoadAll && isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else if filteredOtherGalleries.isEmpty {
                                Text("No matching galleries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(filteredOtherGalleries.prefix(30)) { gallery in
                                    galleryRow(gallery)
                                }
                                if filteredOtherGalleries.count > 30 {
                                    Text("Type more to refine...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    } else if performerIds.isEmpty {
                        Section(header: Text("All Galleries")) {
                            if allGalleries.isEmpty && isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else {
                                ForEach(allGalleries.prefix(30)) { gallery in
                                    galleryRow(gallery)
                                }
                                if allGalleries.count > 30 {
                                    Text("Type to search...")
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
            .stashyModalSheetChrome("Edit Galleries", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
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
                    Text("\(count) images")
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
                    ToastManager.shared.show("Failed to update galleries", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
