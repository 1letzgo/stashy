//
//  ImagesView.swift
//  stashy
//
//  Created by Daniel Goletz on 19.01.26.
//

#if !os(tvOS)
import SwiftUI

struct ImagesView: View {
    let initialGallery: Gallery?
    /// Keeps the Instagram/Feeds 1/row card when opening a gallery from that layout
    /// (does not change GalleriesView or the persisted `openedGallery` column pref).
    var forceOneColumnFeed: Bool = false
    @StateObject private var ownedViewModel = StashDBViewModel()
    let catalogBrowserViewModel: StashDBViewModel?
    @StateObject private var imageListFilters: DetailLinkedImagesFilterModel

    init(
        gallery: Gallery? = nil,
        catalogBrowserViewModel: StashDBViewModel? = nil,
        forceOneColumnFeed: Bool = false
    ) {
        self.initialGallery = gallery
        self.catalogBrowserViewModel = catalogBrowserViewModel
        self.forceOneColumnFeed = forceOneColumnFeed
        let scope: DetailLinkedImagesScope = gallery.map { .gallery($0.id) } ?? .catalogRoot
        _imageListFilters = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: scope))
    }

    var body: some View {
        ImagesViewBody(
            initialGallery: initialGallery,
            forceOneColumnFeed: forceOneColumnFeed,
            viewModel: initialGallery != nil ? ownedViewModel : (catalogBrowserViewModel ?? ownedViewModel),
            imageListFilters: imageListFilters
        )
    }
}

private struct ImagesViewBody: View {
    @State private var gallery: Gallery?
    var forceOneColumnFeed: Bool = false
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var imageListFilters: DetailLinkedImagesFilterModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject private var coordinator: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tabManager = TabManager.shared

    @State private var lastOpenedImageId: String?
    @State private var sessionKeyCache: [String: String] = [:]
    @State private var showingEditGallerySheet = false
    @State private var isHeaderExpanded = false

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }
    private var isOpenedGallery: Bool { gallery != nil }

    init(
        initialGallery: Gallery?,
        forceOneColumnFeed: Bool,
        viewModel: StashDBViewModel,
        imageListFilters: DetailLinkedImagesFilterModel
    ) {
        _gallery = State(initialValue: initialGallery)
        self.forceOneColumnFeed = forceOneColumnFeed
        self.viewModel = viewModel
        self.imageListFilters = imageListFilters
    }

    /// Same grouping prefs as Feeds → Pics.
    @AppStorage("stashline_group_sets") private var groupIntoSets = true
    @AppStorage("stashline_group_fallback") private var groupFallbackRaw = StashImageSetGroupingPolicy.sessionThenMeta.rawValue

    // Multi-Select State
    @State private var isSelectionMode = false
    @State private var selectedImageIds: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    /// Images catalog vs opened gallery — persisted independently.
    private var cardColumnScope: CatalogCardColumnScope {
        gallery != nil ? .openedGallery : .images
    }

    private var effectiveCardColumns: CatalogCardColumns {
        forceOneColumnFeed ? .one : tabManager.catalogCardColumns(for: cardColumnScope)
    }

    private var columns: [GridItem] {
        effectiveCardColumns.gridItems()
    }

    /// Instagram/Feeds-style 1/row layout (header above image; optional set grouping).
    private var usesOneColumnFeedLayout: Bool {
        effectiveCardColumns == .one && !isSelectionMode
    }

    private var oneColumnFeedPosts: [(id: String, images: [StashImage])] {
        if groupIntoSets {
            return groupedImagePosts
        }
        return displayedImages.map { (id: "single|\($0.id)", images: [$0]) }
    }

    private var groupingPolicy: StashImageSetGroupingPolicy {
        StashImageSetGroupingPolicy(rawValue: groupFallbackRaw) ?? .sessionThenMeta
    }
    
    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        sessionKeyCache.removeAll(keepingCapacity: true)
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

    /// Applies Settings → Default Filters for Images. Returns `true` if selection changed.
    @discardableResult
    private func applyImagesDefaultFilterFromSettingsIfNeeded(force: Bool) -> Bool {
        guard gallery == nil else { return false }
        if !force, imageListFilters.selectedFilter != nil { return false }

        if let defaultId = TabManager.shared.getDefaultFilterId(for: .images),
           let filter = viewModel.savedFilters[defaultId] {
            let already =
                imageListFilters.selectedFilter?.id == filter.id
                && imageListFilters.catalogPresetRowSelection == ListLivePresetTag.serverRow(filter.id)
            imageListFilters.selectedFilter = filter
            imageListFilters.catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
            imageListFilters.syncLiveChipsFromSelectedFilter(viewModel: viewModel)
            return force || !already
        }

        if force {
            let hadSelection =
                imageListFilters.selectedFilter != nil || !imageListFilters.catalogPresetRowSelection.isEmpty
            imageListFilters.selectedFilter = nil
            imageListFilters.catalogPresetRowSelection = ""
            imageListFilters.clearLiveChipsOnly()
            return hadSelection
        }
        return false
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
                VStack(spacing: 0) {
                    if let gallery {
                        openedGalleryHeader(gallery)
                            .padding(16)
                    }
                    StandardLoadingView(message: "Loading images...")
                }
            } else if imagesListShowsConnectionError {
                ConnectionErrorView {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            } else if displayedImages.isEmpty {
                VStack(spacing: 0) {
                    if let gallery {
                        openedGalleryHeader(gallery)
                            .padding(16)
                    }
                    SharedEmptyStateView(
                        icon: "camera.fill",
                        title: "No images found",
                        buttonText: "Reload",
                        onRetry: {
                            imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                        }
                    )
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            if let gallery {
                                openedGalleryHeader(gallery)
                            }
                            gridContent
                        }
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
                    sessionKeyCache.removeAll(keepingCapacity: true)
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(OpenedGalleryNavigationChrome(isOpenedGallery: isOpenedGallery))
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
        .stashyCustomChromeInset(spacing: 0) {
            if isOpenedGallery {
                openedGalleryNavBar
            }
        }
        .sheet(isPresented: $showingEditGallerySheet) {
            if let gallery {
                EditGallerySheet(gallery: gallery, viewModel: viewModel) { updated in
                    self.gallery = updated
                }
            }
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

            if gallery == nil, !coordinator.activeSearchText.isEmpty {
                viewModel.currentImageSearchQuery = coordinator.activeSearchText
                coordinator.activeSearchText = ""
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            } else if gallery != nil, viewModel.galleryImages.isEmpty {
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            } else if gallery == nil {
                // Settings → Default Filters: apply before first fetch when filters are already loaded.
                let appliedDefault = applyImagesDefaultFilterFromSettingsIfNeeded(force: false)
                let defaultPending = TabManager.shared.getDefaultFilterId(for: .images) != nil && viewModel.savedFilters.isEmpty
                if !defaultPending, (appliedDefault || viewModel.allImages.isEmpty) {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            }

            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            guard gallery == nil else { return }
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.images.rawValue {
                _ = applyImagesDefaultFilterFromSettingsIfNeeded(force: true)
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
            sessionKeyCache.removeAll(keepingCapacity: true)
            imageListFilters.catalogPresetRowSelection = ""
            imageListFilters.selectedFilter = nil
            imageListFilters.clearLiveChipsOnly()
            imageListFilters.refreshLocalPresets()
            imageListFilters.refetchImages(viewModel: viewModel, initial: true)
        }
        .onChange(of: viewModel.savedFilters) { _, _ in
            guard gallery == nil else { return }
            if applyImagesDefaultFilterFromSettingsIfNeeded(force: false) {
                // Always refetch after applying Settings default — shared VM may already hold unfiltered rows.
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            } else if !viewModel.isLoadingSavedFilters, viewModel.allImages.isEmpty,
                      imageListFilters.selectedFilter == nil {
                imageListFilters.refetchImages(viewModel: viewModel, initial: true)
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false, gallery == nil,
               !viewModel.isLoadingImages {
                if applyImagesDefaultFilterFromSettingsIfNeeded(force: false) {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                } else if viewModel.allImages.isEmpty, imageListFilters.selectedFilter == nil {
                    imageListFilters.refetchImages(viewModel: viewModel, initial: true)
                }
            }
        }
        .floatingActionBar(isPresented: true, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: displayedImages.isEmpty, errorMessage: viewModel.errorMessage, imageFindListError: viewModel.imageFindListError)) {
            HStack(spacing: 0) {
                if isSelectionMode {
                    CatalogFABIconButton(systemImage: "checkmark.circle.fill") {
                        withAnimation(DesignTokens.Animation.quick) { isSelectionMode = false }
                        selectedImageIds.removeAll()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    if !forceOneColumnFeed {
                        let cardColumns = tabManager.catalogCardColumns(for: cardColumnScope)
                        CatalogFABIconButton(
                            systemImage: cardColumns.toggleIcon,
                            accessibilityLabel: cardColumns.accessibilityLabel,
                            accessibilityHint: "Switches between one and two cards per row"
                        ) {
                            withAnimation(DesignTokens.Animation.quick) {
                                tabManager.toggleCatalogCardColumns(for: cardColumnScope)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    CatalogFABIconButton(systemImage: "checkmark.circle") {
                        withAnimation(DesignTokens.Animation.quick) { isSelectionMode = true }
                    }
                    .frame(maxWidth: .infinity)

                    imagesFilterMenuButton

                    CatalogFilterFABButton(isActive: catalogFilterSortFABActive) {
                        imageListFilters.showFilterSortSheet = true
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

    /// Custom top chrome for opened galleries: Back · Edit (title lives in the header card).
    @ViewBuilder
    private var openedGalleryNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 8)

                if appearanceManager.isEditModeEnabled {
                    Button {
                        HapticManager.light()
                        showingEditGallerySheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .frame(
                                width: StashyExpandingDock.circleSize,
                                height: StashyExpandingDock.circleSize
                            )
                            .background(StashyExpandingDock.inactiveBackground)
                            .clipShape(Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit gallery")
                }
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }

    /// Performer/Tag-style detail header for an opened gallery.
    @ViewBuilder
    private func openedGalleryHeader(_ gallery: Gallery) -> some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        let allDetails = getGalleryHeaderDetails(gallery)
        let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
        let hasExpandableContent = allDetails.count > 4 || !(gallery.details ?? "").isEmpty

        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .top) {
                if let url = gallery.coverURL {
                    CustomAsyncImage(url: url) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .overlay(InlineSpinner(scale: .compact))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .clipped()
                        } else {
                            galleryHeaderPlaceholder(width: imageWidth)
                        }
                    }
                } else {
                    galleryHeaderPlaceholder(width: imageWidth)
                }
            }
            .frame(width: imageWidth, alignment: .top)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? nil : collapsedHeight, alignment: .top)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))

            VStack(alignment: .leading, spacing: 4) {
                Text(gallery.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(isHeaderExpanded ? nil : 1)

                if !visibleDetails.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if isHeaderExpanded, let details = gallery.details, !details.isEmpty {
                    Text(details)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottomTrailing) {
            if hasExpandableContent {
                Button {
                    withAnimation(.spring()) {
                        isHeaderExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.pillAccent)
                        .padding(6)
                        .background(appearanceManager.tintColor.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(8)
            }
        }
    }

    private func galleryHeaderPlaceholder(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24))
                    .foregroundColor(.appAccent.opacity(0.5))
            )
    }

    private func getGalleryHeaderDetails(_ gallery: Gallery) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        let imageCount = max(viewModel.totalGalleryImages, gallery.imageCount ?? 0)
        if imageCount > 0 {
            list.append((label: "IMAGES", value: "\(imageCount)"))
        }
        if let date = gallery.date, !date.isEmpty {
            list.append((label: "DATE", value: date))
        }
        if let studio = gallery.studio {
            list.append((label: "STUDIO", value: studio.name))
        }
        if let performers = gallery.performers, !performers.isEmpty {
            let names = performers.map(\.name).joined(separator: ", ")
            list.append((label: "PERFORMERS", value: names))
        }
        if gallery.organized == true {
            list.append((label: "ORGANIZED", value: "Yes"))
        }
        return list
    }

    private var imagesFilterMenuActive: Bool {
        imageListFilters.selectedFilter != nil || !imageListFilters.catalogPresetRowSelection.isEmpty
    }

    @ViewBuilder
    private var imagesFilterMenuButton: some View {
        let serverFilters = imageListFilters.sortedServerImageFilters(viewModel: viewModel)
        let selection = imageListFilters.catalogPresetRowSelection
        Menu {
            Button {
                imageListFilters.catalogPresetRowSelection = ""
            } label: {
                HStack {
                    Text("No Filter")
                    if selection.isEmpty && imageListFilters.selectedFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !serverFilters.isEmpty {
                Section("Saved Filters") {
                    ForEach(serverFilters) { filter in
                        Button {
                            imageListFilters.catalogPresetRowSelection = ListLivePresetTag.serverRow(filter.id)
                        } label: {
                            HStack {
                                Text(filter.name)
                                if selection == ListLivePresetTag.serverRow(filter.id)
                                    || (selection.isEmpty && imageListFilters.selectedFilter?.id == filter.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            if !imageListFilters.localCatalogPresets.isEmpty {
                Section("Presets") {
                    ForEach(imageListFilters.localCatalogPresets) { preset in
                        Button {
                            imageListFilters.catalogPresetRowSelection = ListLivePresetTag.localRow(preset.id)
                        } label: {
                            HStack {
                                Text(preset.name)
                                if selection == ListLivePresetTag.localRow(preset.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            CatalogQuickFilterFABLabel(isActive: imagesFilterMenuActive)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Filter")
        .accessibilityHint("Chooses a saved filter or preset")
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

    private var groupedImagePosts: [(id: String, images: [StashImage])] {
        StashImageFilenameKeys.buildPosts(
            from: displayedImages,
            sort: imageListFilters.selectedSortOption,
            policy: groupingPolicy,
            groupEnabled: true,
            sessionCache: &sessionKeyCache
        )
    }
    
    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            if usesOneColumnFeedLayout {
                let posts = oneColumnFeedPosts
                ForEach(posts, id: \.id) { post in
                    imageGroupCell(post.images)
                        .onAppear {
                            if post.id == posts.last?.id {
                                loadMoreImagesIfNeeded()
                            }
                        }
                }
            } else {
                ForEach(displayedImages) { image in
                    imageCell(image)
                        .onAppear {
                            if image.id == displayedImages.last?.id {
                                loadMoreImagesIfNeeded()
                            }
                        }
                }
            }
            
            // Loading Indicator
            if viewModel.isLoadingImages || viewModel.isLoadingGalleryImages {
                ProgressView()
                    .padding()
            }
        }
        // Force cell rebuild — LazyVGrid otherwise keeps stale square/16:9 sizes.
        .id(effectiveCardColumns)
    }
    
    /// Images stay square in both column modes (1/row Feeds matches Pics 1:1).
    private var imageCardAspectRatio: CGFloat { 1.0 }

    private func loadMoreImagesIfNeeded() {
        if let gallery = gallery {
            viewModel.loadMoreGalleryImages(galleryId: gallery.id)
        } else {
            viewModel.loadMoreImages()
        }
    }

    private func fullScreenFeedBinding() -> Binding<[StashImage]> {
        Binding(
            get: { displayedImages },
            set: { newImages in
                if gallery != nil {
                    viewModel.galleryImages = newImages
                } else {
                    viewModel.allImages = newImages
                }
            }
        )
    }

    @ViewBuilder
    private func imageGroupCell(_ images: [StashImage]) -> some View {
        ImageGroupCatalogCell(
            images: images,
            aspectRatio: imageCardAspectRatio,
            currentGalleryId: gallery?.id,
            // Fullscreen must page through the whole feed, not only this set/group.
            imagesBinding: fullScreenFeedBinding(),
            onLoadMore: { loadMoreImagesIfNeeded() },
            onOpened: { lastOpenedImageId = $0 }
        )
        .id(images[0].id)
    }

    @ViewBuilder
    private func imageCell(_ image: StashImage) -> some View {
        Group {
            if isSelectionMode {
                Button {
                    toggleSelection(for: image.id)
                } label: {
                    ImageThumbnailCard(image: image, aspectRatio: imageCardAspectRatio)
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
                NavigationLink(destination: FullScreenImageView(
                    images: fullScreenFeedBinding(),
                    selectedImageId: image.id,
                    onLoadMore: {
                        loadMoreImagesIfNeeded()
                    }
                )) {
                    ImageThumbnailCard(image: image, aspectRatio: imageCardAspectRatio)
                }
                .buttonStyle(.plain)
                .id(image.id)
                .simultaneousGesture(TapGesture().onEnded {
                    lastOpenedImageId = image.id
                })
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
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("\(selectedImageIds.count) Selected")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: DesignTokens.Chrome.fabIconSize, weight: .semibold))
                    .foregroundColor(.red)
            }
            .disabled(selectedImageIds.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DesignTokens.Chrome.fabInnerPadding)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .floatingShadow()
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(DesignTokens.Chrome.strokeOpacity), lineWidth: 0.5)
        )
        .frame(height: 44)
        .padding(.horizontal, DesignTokens.Chrome.fabOuterPadding)
        .padding(.bottom, DesignTokens.Chrome.fabBottomPadding)
    }
}
/// 1/row Feeds-style post: header overlay on square image + optional set thumb strip.
private struct ImageGroupCatalogCell: View {
    let images: [StashImage]
    let aspectRatio: CGFloat
    /// When already inside a gallery detail, skip linking back to the same gallery.
    var currentGalleryId: String? = nil
    /// Full feed for fullscreen paging (not limited to this group).
    let imagesBinding: Binding<[StashImage]>
    let onLoadMore: () -> Void
    let onOpened: (String) -> Void

    @State private var visibleImageId: String

    init(
        images: [StashImage],
        aspectRatio: CGFloat,
        currentGalleryId: String? = nil,
        imagesBinding: Binding<[StashImage]>,
        onLoadMore: @escaping () -> Void,
        onOpened: @escaping (String) -> Void
    ) {
        self.images = images
        self.aspectRatio = aspectRatio
        self.currentGalleryId = currentGalleryId
        self.imagesBinding = imagesBinding
        self.onLoadMore = onLoadMore
        self.onOpened = onOpened
        _visibleImageId = State(initialValue: images[0].id)
    }

    private var visibleImage: StashImage {
        images.first(where: { $0.id == visibleImageId }) ?? images[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                NavigationLink(destination: FullScreenImageView(
                    images: imagesBinding,
                    selectedImageId: visibleImageId,
                    onLoadMore: onLoadMore
                )) {
                    ImageThumbnailCard(
                        image: visibleImage,
                        aspectRatio: aspectRatio,
                        showsOverlayChrome: false
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    onOpened(visibleImageId)
                })

                ImageCatalogFeedHeader(image: visibleImage, currentGalleryId: currentGalleryId)
            }

            if images.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(images) { img in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        visibleImageId = img.id
                                    }
                                } label: {
                                    ImageGroupThumbView(
                                        image: img,
                                        size: 56,
                                        isSelected: img.id == visibleImageId
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(img.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: visibleImageId) { _, newId in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .onChange(of: images.map(\.id)) { _, ids in
            if !ids.contains(visibleImageId) {
                visibleImageId = images.first?.id ?? visibleImageId
            }
        }
    }
}

/// Semi-transparent header overlaid on the 1/row thumbnail.
private struct ImageCatalogFeedHeader: View {
    let image: StashImage
    var currentGalleryId: String? = nil
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    private var performers: [GalleryPerformer] {
        image.performers ?? []
    }

    /// Prefer a gallery other than the one currently open (if any).
    private var linkedGallery: ImageGallery? {
        guard let galleries = image.galleries, !galleries.isEmpty else { return nil }
        if let currentGalleryId {
            return galleries.first(where: { $0.id != currentGalleryId })
        }
        return galleries.first
    }

    private var galleryDestination: Gallery? {
        guard let g = linkedGallery else { return nil }
        return Gallery(
            id: g.id,
            title: g.title ?? "Gallery",
            date: nil,
            details: nil,
            imageCount: nil,
            organized: nil,
            createdAt: nil,
            updatedAt: nil,
            studio: nil,
            performers: nil,
            cover: nil
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                    // Avatar → gallery in 1/row feed (not performer detail).
                    if let galleryDestination {
                        NavigationLink(
                            destination: ImagesView(gallery: galleryDestination, forceOneColumnFeed: true)
                        ) {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if performers.isEmpty {
                    Group {
                        if let galleryDestination {
                            NavigationLink(
                                destination: ImagesView(gallery: galleryDestination, forceOneColumnFeed: true)
                            ) {
                                emptyPerformerAvatar
                            }
                            .buttonStyle(.plain)
                        } else {
                            emptyPerformerAvatar
                        }
                    }
                }
            }
            .padding(.trailing, performers.count > 1 ? CGFloat(performers.count - 1) * -10 : 0)

            VStack(alignment: .leading, spacing: 1) {
                if performers.isEmpty {
                    Text(image.title ?? "Unknown")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                } else if performers.count == 1 {
                    NavigationLink(destination: PerformerDetailView(performer: performers[0].toPerformer())) {
                        Text(performers[0].name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                            NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
                                Text(performer.name)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                            }
                            .buttonStyle(.plain)
                            if idx < performers.count - 1 {
                                Text("&")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                    }
                }

                if let studio = image.studio {
                    Text(studio.name)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                }
            }

            Spacer(minLength: 8)

            if let date = image.date {
                Text(date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var emptyPerformerAvatar: some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.35))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 14))
            }
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
    }

    @ViewBuilder
    private func performerAvatar(_ performer: GalleryPerformer, offset: Int) -> some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.35))
            .frame(width: 36, height: 36)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable().scaledToFill()
                        } else {
                            Text(String(performer.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    Text(String(performer.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
            .offset(x: CGFloat(offset) * -10)
    }
}

/// Small square thumb under a grouped catalog image (1/row layout).
private struct ImageGroupThumbView: View {
    let image: StashImage
    var size: CGFloat = 56
    var isSelected: Bool = false
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        let borderWidth: CGFloat = isSelected ? 2 : 0
        let inner = size - borderWidth * 2

        ZStack {
            Color.studioHeaderGray
            if let url = image.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(scale: .compact)
                    } else if let loaded = loader.image {
                        loaded
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if image.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(DesignTokens.Opacity.medium))
                    .clipShape(Circle())
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                .stroke(appearanceManager.tintColor, lineWidth: borderWidth)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }
}

struct ImageThumbnailCard: View {
    let image: StashImage
    var aspectRatio: CGFloat = 1
    /// When false (1/row Feeds layout), chrome lives in the header above the image.
    var showsOverlayChrome: Bool = true
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
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
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if image.isVideo {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(DesignTokens.Opacity.medium))
                            .clipShape(Circle())
                    }
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .id(aspectRatio)

            if showsOverlayChrome {
                // Top Overlay (Studio and Date) — fixed fonts like SceneCardView
                VStack {
                    HStack(alignment: .top) {
                        if let studio = image.studio {
                            Text(studio.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if let date = image.date {
                            Text(date)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(8)

                    Spacer()
                }

                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(image.performers?.first?.name ?? image.title ?? "Image")
                            .font(.headline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let ext = image.fileExtension {
                            Text(ext)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color.secondaryAppBackground)
        .modifier(ImageThumbnailCardChrome(enabled: showsOverlayChrome))
    }
}

private struct ImageThumbnailCardChrome: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .cardShadow()
        } else {
            content
                .contentShape(Rectangle())
        }
    }
}

/// System title for Images catalog; custom chrome + swipe-back for opened galleries.
private struct OpenedGalleryNavigationChrome: ViewModifier {
    let isOpenedGallery: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOpenedGallery {
            content
                .hideSystemNavigationBarForCustomChrome()
                .enableSwipeBackWhenNavBarHidden()
        } else {
            content
                .navigationTitle("Images")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Edit Gallery Sheet

struct EditGallerySheet: View {
    let gallery: Gallery
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (Gallery) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var title: String = ""
    @State private var date: String = ""
    @State private var details: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    TextField("Title", text: $title)
                    TextField("Date (YYYY-MM-DD)", text: $date)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Details") {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .navigationTitle("Edit Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .tint(appearanceManager.tintColor)
                }
            }
            .onAppear {
                title = gallery.title
                date = gallery.date ?? ""
                details = gallery.details ?? ""
            }
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        isSaving = true
        viewModel.updateGalleryDetails(
            galleryId: gallery.id,
            title: trimmedTitle,
            date: optionalTrimmed(date),
            details: optionalTrimmed(details)
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = gallery
                    updated.title = trimmedTitle
                    updated.date = optionalTrimmed(date)
                    updated.details = optionalTrimmed(details)
                    onComplete(updated)
                    ToastManager.shared.show("Gallery updated", icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update gallery", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
