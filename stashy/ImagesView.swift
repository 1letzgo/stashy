//
//  ImagesView.swift
//  stashy
//
//  Created by Daniel Goletz on 19.01.26.
//

#if !os(tvOS)
import SwiftUI

struct ImagesView: View {
    let gallery: Gallery?
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    @StateObject private var imageListFilters: DetailLinkedImagesFilterModel

    init(gallery: Gallery? = nil, catalogBrowserViewModel: StashDBViewModel? = nil) {
        self.gallery = gallery
        self.catalogBrowserViewModel = catalogBrowserViewModel
        let scope: DetailLinkedImagesScope = gallery.map { .gallery($0.id) } ?? .catalogRoot
        _imageListFilters = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: scope))
    }

    var body: some View {
        ImagesViewBody(
            gallery: gallery,
            viewModel: gallery != nil ? ownedViewModel : (catalogBrowserViewModel ?? ownedViewModel),
            imageListFilters: imageListFilters
        )
    }
}

private struct ImagesViewBody: View {
    let gallery: Gallery?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var imageListFilters: DetailLinkedImagesFilterModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var lastOpenedImageId: String?

    // Multi-Select State
    @State private var isSelectionMode = false
    @State private var selectedImageIds: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    // Dynamic Columns to match GalleriesView
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }
    
    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        if gallery == nil {
            TabManager.shared.setSortOption(for: .images, option: newOption.rawValue)
        } else {
            TabManager.shared.setDetailSortOption(for: DetailViewContext.gallery.rawValue, option: newOption.rawValue)
        }
        imageListFilters.changeSortOption(to: newOption, viewModel: viewModel)
    }

    private var catalogFilterSortFABActive: Bool {
        imageListFilters.catalogFilterSortFABActive
    }

    /// Wie `ScenesView`: nur echte Bildlisten-Ladevorgänge blockieren, nicht `viewModel.isLoading` von anderen Queries.
    private var showsBlockingInitialLoad: Bool {
        if gallery != nil {
            viewModel.isLoadingGalleryImages && viewModel.galleryImages.isEmpty
        } else {
            viewModel.isLoadingImages && viewModel.allImages.isEmpty
        }
    }

    /// Verbindungs- bzw. Ladefehler für die Bildliste (`imageFindListError` ist gegen Races mit `fetchSavedFilters` stabil).
    private var imagesListShowsConnectionError: Bool {
        displayedImages.isEmpty && (viewModel.imageFindListError != nil || viewModel.errorMessage != nil)
    }

    var body: some View {
        imagesCoreChrome
            .sheet(isPresented: $imageListFilters.showFilterSortSheet, content: imagesFilterSortSheet)
            .onChange(of: imageListFilters.catalogPresetRowSelection) { _, newId in
                imageListFilters.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $imageListFilters.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $imageListFilters.catalogPresetNameInput)
                Button("Save") { imageListFilters.savePresetAs(name: imageListFilters.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $imageListFilters.showRenameCatalogPresetAlert) {
                TextField("Name", text: $imageListFilters.renameCatalogPresetInput)
                Button("Save") { imageListFilters.renamePreset(to: imageListFilters.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $imageListFilters.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { imageListFilters.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(imageListFilters.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var imagesCoreChrome: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            } else if showsBlockingInitialLoad {
                StandardLoadingView(message: "Loading images...")
            } else if imagesListShowsConnectionError {
                ConnectionErrorView {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            } else if displayedImages.isEmpty {
                SharedEmptyStateView(
                    icon: "camera.fill",
                    title: "No images found",
                    buttonText: "Reload",
                    onRetry: {
                        imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                    }
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        gridContent
                            .padding(16)
                            .padding(.bottom, isSelectionMode ? 80 : 0) // Add padding for floating bar
                    }
                    .onAppear {
                        if let id = lastOpenedImageId {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        }
                    }
                }
                .refreshable {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(gallery?.title ?? "Images")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .overlay(alignment: .bottom) {
            if isSelectionMode {
                floatingDeleteBar
            }
        }
        .alert("Delete \(selectedImageIds.count) images?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSelectedImages()
            }
        } message: {
            Text("These images will be permanently deleted. This action cannot be undone.")
        }
        .onAppear {
            // Apply default sort option
            let defaultSortStr: String
            if gallery != nil {
                defaultSortStr = TabManager.shared.getDetailSortOption(for: DetailViewContext.gallery.rawValue) ?? "dateDesc"
            } else {
                defaultSortStr = TabManager.shared.getSortOption(for: .images) ?? "dateDesc"
            }
            
            if let defaultSort = StashDBViewModel.ImageSortOption(rawValue: defaultSortStr) {
                 imageListFilters.selectedSortOption = defaultSort
                 viewModel.currentImageSortOption = defaultSort
                 if gallery != nil {
                     viewModel.currentGalleryImageSortOption = defaultSort
                 }
            }

            // Wie GalleriesView: bei gesetztem Standard-Filter erst laden, wenn Saved Filters da sind
            // (oder kein Standard), sonst bleibt die Liste leer ohne Request → kein „Server not reachable“.
            if gallery != nil, viewModel.galleryImages.isEmpty {
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            } else if gallery == nil, viewModel.allImages.isEmpty {
                if TabManager.shared.getDefaultFilterId(for: .images) == nil || !viewModel.savedFilters.isEmpty {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            }

            if gallery == nil, !coordinator.activeSearchText.isEmpty {
                coordinator.activeSearchText = ""
            }

            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            guard gallery == nil else { return }
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.images.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .images),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    imageListFilters.selectedFilter = newFilter
                    imageListFilters.syncLiveChipsFromSelectedFilter(viewModel: viewModel)
                } else {
                    imageListFilters.selectedFilter = nil
                    imageListFilters.syncLiveChipsFromSelectedFilter(viewModel: viewModel)
                }
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            guard gallery == nil else { return }
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.images.rawValue {
                let raw = TabManager.shared.getPersistentSortOption(for: .images) ?? "dateDesc"
                let newSort = StashDBViewModel.ImageSortOption(rawValue: raw) ?? .dateDesc
                changeSortOption(to: newSort)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            imageListFilters.catalogPresetRowSelection = ""
            imageListFilters.selectedFilter = nil
            imageListFilters.clearLiveChipsOnly()
            imageListFilters.refreshLocalPresets()
            imageListFilters.refetchImages(viewModel: viewModel, initial: true)
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            if imageListFilters.selectedFilter == nil && gallery == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .images),
                   let filter = newValue[defaultId] {
                    imageListFilters.selectedFilter = filter
                    imageListFilters.syncLiveChipsFromSelectedFilter(viewModel: viewModel)
                    if viewModel.allImages.isEmpty {
                        imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                    }
                } else if !viewModel.isLoadingSavedFilters {
                    if viewModel.allImages.isEmpty {
                        imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false, gallery == nil,
               viewModel.allImages.isEmpty, !viewModel.isLoadingImages,
               imageListFilters.selectedFilter == nil {
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            }
        }
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: displayedImages.isEmpty, errorMessage: viewModel.errorMessage, imageFindListError: viewModel.imageFindListError)) {
            HStack(spacing: 0) {
                if isSelectionMode {
                    Button {
                         withAnimation(DesignTokens.Animation.quick) { isSelectionMode = false }
                         selectedImageIds.removeAll()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        withAnimation(DesignTokens.Animation.quick) { isSelectionMode = true }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        imageListFilters.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if catalogFilterSortFABActive {
                                    Circle()
                                        .fill(appearanceManager.tintColor)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageDeleted"))) { notification in
            if let imageId = notification.userInfo?["imageId"] as? String {
                viewModel.removeImage(id: imageId)
            }
        }
    }

    @ViewBuilder
    private func imagesFilterSortSheet() -> some View {
        ImagesCatalogFilterSortSheet(
            serverFilters: imageListFilters.sortedServerImageFilters(viewModel: viewModel),
            localPresets: imageListFilters.localCatalogPresets,
            selectedPresetRowId: $imageListFilters.catalogPresetRowSelection,
            filterMenuTitleFallback: imageListFilters.selectedFilter?.name,
            liveChipRowsVisible: imageListFilters.imageLiveChipRowsVisible,
            showMediaTypeFilter: imageListFilters.showImageMediaTypeFilter,
            sortOption: imageListFilters.selectedSortOption,
            onSortChange: { changeSortOption(to: $0) },
            liveMinRating: $imageListFilters.liveFilterMinRating,
            livePerformerFavorite: $imageListFilters.liveFilterPerformerFavorite,
            liveOrganized: $imageListFilters.liveFilterOrganized,
            liveOCounterTag: $imageListFilters.liveFilterOCounterTag,
            liveStudioIds: $imageListFilters.liveFilterStudioIds,
            liveTagIds: $imageListFilters.liveFilterTagIds,
            liveMediaKind: $imageListFilters.liveFilterMediaKind,
            studioPickerOptions: imageListFilters.studioPickerOptions,
            studioPickerLoading: imageListFilters.studioPickerLoading,
            onStudioPickerSectionAppear: { imageListFilters.loadStudioPickerOptions(viewModel: viewModel) },
            tagPickerOptions: imageListFilters.tagPickerOptions,
            tagPickerLoading: imageListFilters.tagPickerLoading,
            onTagPickerSectionAppear: { imageListFilters.loadTagPickerOptions(viewModel: viewModel) },
            onApply: { imageListFilters.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                imageListFilters.catalogPresetRowSelection = ""
                imageListFilters.selectedFilter = nil
                imageListFilters.clearLiveChipsOnly()
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            },
            onRequestSave: { imageListFilters.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                imageListFilters.catalogPresetNameInput = ""
                imageListFilters.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(imageListFilters.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    imageListFilters.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(imageListFilters.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = imageListFilters.localCatalogPresets.first(where: { $0.id == uuid }) {
                    imageListFilters.renameCatalogPresetInput = p.name
                }
                imageListFilters.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { imageListFilters.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            var sel = imageListFilters.catalogPresetRowSelection
            ListLivePresetTag.migrateLegacySelection(&sel)
            imageListFilters.catalogPresetRowSelection = sel
            imageListFilters.refreshLocalPresets()
            imageListFilters.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
            imageListFilters.applyResolvedCatalogPresetPickerRowIfNeeded(viewModel: viewModel)
        }
    }
    
    private var displayedImages: [StashImage] {
        gallery != nil ? viewModel.galleryImages : viewModel.allImages
    }
    
    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(displayedImages) { image in
                imageCell(image)
            }
            
            // Loading Indicator
            if viewModel.isLoadingImages || viewModel.isLoadingGalleryImages {
                ProgressView()
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func imageCell(_ image: StashImage) -> some View {
        Group {
            if isSelectionMode {
                Button {
                    toggleSelection(for: image.id)
                } label: {
                    ImageThumbnailCard(image: image)
                        .overlay(
                            ZStack {
                                if selectedImageIds.contains(image.id) {
                                    Color.black.opacity(DesignTokens.Opacity.medium)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title)
                                        .foregroundColor(appearanceManager.tintColor)
                                } else {
                                    Color.clear
                                    Image(systemName: "circle")
                                        .font(.title)
                                        .foregroundColor(.white.opacity(0.7))
                                        .shadow(radius: 2)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: FullScreenImageView(images: Binding(
                    get: { displayedImages },
                    set: { newImages in
                        if gallery != nil {
                            viewModel.galleryImages = newImages
                        } else {
                            viewModel.allImages = newImages
                        }
                    }
                ), selectedImageId: image.id, onLoadMore: {
                    if let gallery = gallery {
                        viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                    } else {
                        viewModel.loadMoreImages()
                    }
                })) {
                    ImageThumbnailCard(image: image)
                }
                .buttonStyle(.plain)
                .id(image.id)
                .simultaneousGesture(TapGesture().onEnded {
                    lastOpenedImageId = image.id
                })
            }
        }
        // Pagination trigger
        .onAppear {
            if image.id == displayedImages.last?.id {
                print("Last image appeared. Loading more...")
                if let gallery = gallery {
                    viewModel.loadMoreGalleryImages(galleryId: gallery.id)
                } else {
                    viewModel.loadMoreImages()
                }
            }
        }
    }
    
    // MARK: - Multi-Select Logic
    
    private func toggleSelection(for id: String) {
        if selectedImageIds.contains(id) {
            selectedImageIds.remove(id)
        } else {
            selectedImageIds.insert(id)
        }
    }
    
    private func deleteSelectedImages() {
        isDeleting = true
        let idsToDelete = Array(selectedImageIds)
        
        // Simple batch delete (could be optimized with a dedicated batch API if available)
        // For now, we'll just iterate. This is not atomic but functional.
        let group = DispatchGroup()
        
        for id in idsToDelete {
            group.enter()
            viewModel.deleteImage(imageId: id) { _ in
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let count = idsToDelete.count
            isDeleting = false
            selectedImageIds.removeAll()
            withAnimation(DesignTokens.Animation.quick) { isSelectionMode = false }
            ToastManager.shared.show("\(count) image\(count == 1 ? "" : "s") deleted", icon: "trash", style: .success)

            imageListFilters.refetchImages(viewModel: viewModel, initial: true)
        }
    }
    
    private var floatingDeleteBar: some View {
        HStack(spacing: 16) {
             Text("\(selectedImageIds.count) Selected")
                 .font(.subheadline)
                 .fontWeight(.bold)
                 .foregroundColor(.primary)
             
             Button(role: .destructive) {
                 showDeleteConfirmation = true
             } label: {
                 Image(systemName: "trash")
                     .foregroundColor(.red)
             }
             .disabled(selectedImageIds.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.secondaryAppBackground.opacity(0.95))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .floatingShadow()
        .padding(.bottom, 20)
    }
}
struct ImageThumbnailCard: View {
    let image: StashImage
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Image
                    ZStack {
                        Color.gray.opacity(DesignTokens.Opacity.placeholder)
                        
                        if let url = image.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if loader.isLoading {
                                    ProgressView()
                                } else if let uiImage = loader.image {
                                    uiImage
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    
                    // Video Play Icon Overlay
                    if image.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(DesignTokens.Opacity.medium))
                            .clipShape(Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Gradient Overlay
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.5)
                    
                    // Badges Layer
                    VStack {
                        // Top Badges
                        HStack(alignment: .top) {
                             // Studio (Top Left)
                             if let studio = image.studio {
                                 Text(studio.name)
                                     .font(.system(size: 8, weight: .bold))
                                     .lineLimit(1)
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 5)
                                     .padding(.vertical, 2)
                                     .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                     .clipShape(Capsule())
                             }
                             
                             Spacer()
                             
                             // Date (Top Right)
                             if let date = image.date {
                                 Text(date)
                                     .font(.system(size: 8, weight: .bold))
                                     .lineLimit(1)
                                     .foregroundColor(.white)
                                     .padding(.horizontal, 5)
                                     .padding(.vertical, 2)
                                     .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                     .clipShape(Capsule())
                             }
                        }
                        .padding(6)
                        
                        Spacer()
                        
                        // Bottom Layer
                        HStack(alignment: .bottom) {
                            // Performer Name (Bottom Left)
                            if let performers = image.performers, let first = performers.first {
                                Text(first.name)
                                    .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(radius: 2)
                            } else {
                                // Fallback to title/filename
                                Text(image.title ?? "Image")
                                    .font(.system(size: geometry.size.width * 0.08, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(radius: 2)
                            }
                            
                            Spacer()
                            
                            // Format Badge (Bottom Right)
                            if let ext = image.fileExtension {
                                Text(ext)
                                    .font(.system(size: 8, weight: .bold))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(DesignTokens.Opacity.strong))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
#endif
