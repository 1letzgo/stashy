//
//  StashLineView.swift
//  stashy

#if !os(tvOS)
import SwiftUI

struct StashLineView: View {
    let externalPerformerFilter: GalleryPerformer?
    @State private var performerFilter: GalleryPerformer?
    let isEmbedded: Bool
    var onPerformerTap: ((GalleryPerformer) -> Void)? = nil

    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Wenn von außen (Reels-Pics-Mode) ein Filter-Model injiziert wird, hält `@StateObject` die Referenz
    /// stabil über die Lebensdauer dieser Embed-Instanz — Sort/Filter/Live-Chips überleben damit Moduswechsel,
    /// solange die übergeordnete `ReelsViewBody` lebt. Standalone (Push aus Detail-View) erzeugt ein eigenes Model.
    @StateObject private var stashLineListFilters: DetailLinkedImagesFilterModel
    /// Wahr, wenn das Filter-Model von außen injiziert wurde — dann bestimmt der Parent (z. B. `ReelsViewBody`)
    /// die initiale Sort/Filter-Wiederherstellung; `onAppear` darf nicht mehr überschreiben.
    private let usesExternalListFilters: Bool
    /// Monoton steigend — triggert `ScrollViewReader.scrollTo` nach Filter-/Sort-Reload (Anfang der neuen Liste).
    @State private var programmaticScrollGeneration: Int = 0
    @State private var programmaticScrollRowId: String?
    @State private var cachedPosts: [StashLinePost] = []
    /// Vollbild-Galerie auf Feed-Ebene (nicht pro `LazyVStack`-Zeile).
    @State private var fullScreenImages: [StashImage] = []
    @State private var fullScreenPresentation: StashLineFullScreenPresentation?
    @State private var lastFullScreenImageIds: Set<String> = []
    /// Performer-Detail wie die Bild-Galerie: `fullScreenCover` auf Feed-Ebene (kein Push / kein Scroll-Sprung).
    @State private var performerDetailPresented: GalleryPerformer?
    @State private var sessionKeyCache: [String: String] = [:] // imageId -> sessionKey ("" if absent)
    @State private var shouldScrollToTopAfterReload: Bool = false
    @AppStorage("stashline_include_gifs") private var includeGifsInTimeline = false
    @AppStorage("stashline_group_sets") private var groupIntoSets = true
    @AppStorage("stashline_group_fallback") private var groupFallbackRaw = StashImageSetGroupingPolicy.sessionThenMeta.rawValue
    init(
        performerFilter: GalleryPerformer? = nil,
        isEmbedded: Bool = false,
        onPerformerTap: ((GalleryPerformer) -> Void)? = nil,
        externalListFilters: DetailLinkedImagesFilterModel? = nil
    ) {
        self.externalPerformerFilter = performerFilter
        _performerFilter = State(initialValue: performerFilter)
        self.isEmbedded = isEmbedded
        self.onPerformerTap = onPerformerTap
        if let ext = externalListFilters {
            _stashLineListFilters = StateObject(wrappedValue: ext)
            self.usesExternalListFilters = true
        } else {
            _stashLineListFilters = StateObject(
                wrappedValue: DetailLinkedImagesFilterModel(scope: .reelsStashLine, initialSort: .dateDesc)
            )
            self.usesExternalListFilters = false
        }
    }

    private func performSearch() {
        sessionKeyCache.removeAll(keepingCapacity: true)
        stashLineListFilters.reelsStashLinePerformerId = performerFilter?.id
        stashLineListFilters.refetchImages(viewModel: viewModel, initial: true)
    }

    private var groupingPolicy: StashImageSetGroupingPolicy {
        StashImageSetGroupingPolicy(rawValue: groupFallbackRaw) ?? .sessionThenMeta
    }

    /// Ein Trigger statt mehrerer `onChange`-Kaskaden — vermeidet doppelte `computeGroupedPosts()`-Läufe pro Update.
    private var stashLineGroupingFingerprint: String {
        let imgs = viewModel.allImages
        let head = imgs.first?.id ?? ""
        let mid = imgs.count > 2 ? imgs[imgs.count / 2].id : ""
        let tailSample = imgs.suffix(5).map(\.id).joined(separator: ",")
        return "\(stashLineListFilters.selectedSortOption.rawValue)|\(groupIntoSets)|\(groupFallbackRaw)|\(imgs.count)|\(head)|\(mid)|\(tailSample)"
    }

    /// Nach Filter-/Sort-/Live-Wechsel: bei nächstem Ende von `isLoadingImages` auf den ersten Post der neu geladenen Liste springen.
    private func prepareScrollToTopAfterNextFetch() {
        shouldScrollToTopAfterReload = true
    }

    /// `scrollTo` nutzt dieselbe ID wie `.id(post.id)` an der ganzen Zeile, damit `LazyVStack` die Zelle materialisieren kann.
    private func requestProgrammaticScrollToPostRowIfInFeed(postId: String?) {
        guard let postId, !postId.isEmpty else { return }
        guard cachedPosts.contains(where: { $0.id == postId }) else { return }
        programmaticScrollRowId = postId
        programmaticScrollGeneration += 1
    }

    private func rebuildGroupedPosts() {
        cachedPosts = computeGroupedPosts()
    }

    /// Live-listener from FullScreen rating / o_counter mutations — keep feed + open cover in sync.
    private func patchCachedAndFullScreenImage(imageId: String, transform: (StashImage) -> StashImage) {
        cachedPosts = cachedPosts.map { post in
            guard post.images.contains(where: { $0.id == imageId }) else { return post }
            return StashLinePost(id: post.id, images: post.images.map { $0.id == imageId ? transform($0) : $0 })
        }
        if let idx = fullScreenImages.firstIndex(where: { $0.id == imageId }) {
            fullScreenImages[idx] = transform(fullScreenImages[idx])
        }
    }

    private var floatingBarContent: some View {
        HStack(spacing: 0) {
            CatalogFilterFABButton(
                isActive: stashLineListFilters.catalogFilterSortFABActive,
                accessibilityLabel: "Filter und Sortierung"
            ) {
                stashLineListFilters.showFilterSortSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingImages && viewModel.allImages.isEmpty {
                StandardLoadingView(message: "Loading StashLine...")
            } else if viewModel.allImages.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.allImages.isEmpty {
                SharedEmptyStateView(
                    icon: "camera.fill",
                    title: "No images found",
                    buttonText: "Load Images",
                    onRetry: { performSearch() }
                )
            } else {
                feedContent
            }
        }
        .navigationBarHidden(true)
        .enableSwipeBackWhenNavBarHidden()
        .if(!isEmbedded && performerFilter != nil) { view in
            view.stashyCustomChromeInset(spacing: 0) {
                StashySectionChromeBar {
                    HStack(spacing: 8) {
                        Button(action: { dismiss() }) {
                            HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                Text("Back")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                            .modifier(StashyChromePillStyle(height: StashyExpandingDock.activeHeight))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: StashyExpandingDock.activeHeight)
                    .padding(.horizontal, StashyExpandingDock.edgePadding)
                    .padding(.vertical, 8)
                }
            }
        }
        .floatingActionBar(isPresented: !isEmbedded, catalogChrome: CatalogFloatingChromeState(hasActiveServerConfig: configManager.activeConfig != nil, primaryListIsEmpty: viewModel.allImages.isEmpty, errorMessage: viewModel.errorMessage, imageFindListError: viewModel.imageFindListError)) {
            floatingBarContent
        }
        .sheet(isPresented: $stashLineListFilters.showFilterSortSheet) {
            ImagesCatalogFilterSortSheet(
                serverFilters: stashLineListFilters.sortedServerImageFilters(viewModel: viewModel),
                localPresets: stashLineListFilters.localCatalogPresets,
                selectedPresetRowId: $stashLineListFilters.catalogPresetRowSelection,
                filterMenuTitleFallback: stashLineListFilters.selectedFilter?.name,
                liveChipRowsVisible: stashLineListFilters.imageLiveChipRowsVisible,
                showMediaTypeFilter: stashLineListFilters.showImageMediaTypeFilter,
                sortOption: stashLineListFilters.selectedSortOption,
                onSortChange: { changeSortOption(to: $0) },
                liveMinRating: $stashLineListFilters.liveFilterMinRating,
                livePerformerFavorite: $stashLineListFilters.liveFilterPerformerFavorite,
                liveOrganized: $stashLineListFilters.liveFilterOrganized,
                liveOCounterTag: $stashLineListFilters.liveFilterOCounterTag,
                liveStudioIds: $stashLineListFilters.liveFilterStudioIds,
                liveTagIds: $stashLineListFilters.liveFilterTagIds,
                liveMediaKind: $stashLineListFilters.liveFilterMediaKind,
                studioPickerOptions: stashLineListFilters.studioPickerOptions,
                studioPickerLoading: stashLineListFilters.studioPickerLoading,
                onStudioPickerSectionAppear: { stashLineListFilters.loadStudioPickerOptions(viewModel: viewModel) },
                tagPickerOptions: stashLineListFilters.tagPickerOptions,
                tagPickerLoading: stashLineListFilters.tagPickerLoading,
                onTagPickerSectionAppear: { stashLineListFilters.loadTagPickerOptions(viewModel: viewModel) },
                onApply: {
                    prepareScrollToTopAfterNextFetch()
                    stashLineListFilters.applyLiveFilter(viewModel: viewModel)
                },
                onReset: {
                    prepareScrollToTopAfterNextFetch()
                    stashLineListFilters.catalogPresetRowSelection = ""
                    stashLineListFilters.selectedFilter = nil
                    stashLineListFilters.clearLiveChipsOnly()
                    stashLineListFilters.refetchImages(viewModel: viewModel, initial: true)
                },
                onRequestSave: { stashLineListFilters.savePresetOverwrite(viewModel: viewModel) },
                onRequestSaveAs: {
                    stashLineListFilters.catalogPresetNameInput = ""
                    stashLineListFilters.showSaveAsCatalogPresetAlert = true
                },
                onRequestRename: {
                    if let sid = ListLivePresetTag.parseServerId(stashLineListFilters.catalogPresetRowSelection),
                       let n = viewModel.savedFilters[sid]?.name {
                        stashLineListFilters.renameCatalogPresetInput = n
                    } else if let ls = ListLivePresetTag.parseLocalUUIDString(stashLineListFilters.catalogPresetRowSelection),
                              let uuid = UUID(uuidString: ls),
                              let p = stashLineListFilters.localCatalogPresets.first(where: { $0.id == uuid }) {
                        stashLineListFilters.renameCatalogPresetInput = p.name
                    }
                    stashLineListFilters.showRenameCatalogPresetAlert = true
                },
                onRequestDelete: { stashLineListFilters.showDeleteCatalogPresetAlert = true }
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appBackground)
            .onAppear {
                stashLineListFilters.prepareCatalogFilterSortSheetUI(viewModel: viewModel)
            }
        }
        .alert("Speichern unter", isPresented: $stashLineListFilters.showSaveAsCatalogPresetAlert) {
            TextField("Name", text: $stashLineListFilters.catalogPresetNameInput)
            Button("Speichern") {
                stashLineListFilters.savePresetAs(name: stashLineListFilters.catalogPresetNameInput, viewModel: viewModel)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Sortierung, Filter und Live-Kriterien als neuen Stash-Bildfilter speichern.")
        }
        .alert("Umbenennen", isPresented: $stashLineListFilters.showRenameCatalogPresetAlert) {
            TextField("Name", text: $stashLineListFilters.renameCatalogPresetInput)
            Button("Speichern") {
                stashLineListFilters.renamePreset(to: stashLineListFilters.renameCatalogPresetInput, viewModel: viewModel)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Preset oder gespeicherten Filter umbenennen.")
        }
        .alert("Filter löschen?", isPresented: $stashLineListFilters.showDeleteCatalogPresetAlert) {
            Button("Löschen", role: .destructive) {
                stashLineListFilters.deletePreset(viewModel: viewModel)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(stashLineListFilters.deletePresetConfirmationText(viewModel: viewModel))
        }
        .onChange(of: stashLineListFilters.catalogPresetRowSelection) { _, newId in
            guard stashLineListFilters.showFilterSortSheet else { return }
            prepareScrollToTopAfterNextFetch()
            stashLineListFilters.handlePresetSelection(newId, viewModel: viewModel)
        }
        .onAppear {
            // Im embedded Reels-Pics-Mode hat der Parent bereits aus der Session restored;
            // hier nicht mehr mit TabManager-Defaults überschreiben — und sofort laden
            // (sonst: Default-Filter-ID gesetzt + selectedFilter schon vom Parent → nie performSearch).
            if usesExternalListFilters {
                if viewModel.allImages.isEmpty {
                    performSearch()
                }
            } else {
                let sortStr = TabManager.shared.getSortOption(for: .stashline) ?? "dateDesc"
                if let sort = StashDBViewModel.ImageSortOption(rawValue: sortStr) {
                    stashLineListFilters.selectedSortOption = sort
                }
                if TabManager.shared.getDefaultFilterId(for: .stashline) == nil || !viewModel.savedFilters.isEmpty {
                    if viewModel.allImages.isEmpty {
                        performSearch()
                    }
                }
                viewModel.fetchSavedFilters()
            }
            rebuildGroupedPosts()
        }
        .onChange(of: stashLineGroupingFingerprint) { _, _ in
            rebuildGroupedPosts()
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            guard !usesExternalListFilters else { return }
            if stashLineListFilters.selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .stashline),
                   let filter = newValue[defaultId] {
                    stashLineListFilters.selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    if viewModel.allImages.isEmpty {
                        performSearch()
                    }
                }
            } else if viewModel.allImages.isEmpty && !viewModel.isLoadingImages {
                performSearch()
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            guard !usesExternalListFilters else { return }
            if oldValue == true && isLoading == false {
                if viewModel.allImages.isEmpty && !viewModel.isLoadingImages && stashLineListFilters.selectedFilter == nil {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.isLoadingImages) { wasLoading, isLoading in
            guard wasLoading && !isLoading else { return }
            // Zuerst Gruppierung mit den **neuen** allImages, sonst war cachedPosts evtl. noch der alte
            // Stand und programmatisches Scrollen trifft nicht den ersten Post der neuen Liste.
            rebuildGroupedPosts()

            if shouldScrollToTopAfterReload {
                shouldScrollToTopAfterReload = false
                let firstId = cachedPosts.first?.id
                DispatchQueue.main.async {
                    requestProgrammaticScrollToPostRowIfInFeed(postId: firstId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            stashLineListFilters.selectedFilter = nil
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            guard let targetId = notification.userInfo?["performerId"] as? String,
                  let newPath = notification.userInfo?["newImagePath"] as? String else { return }
            if var p = performerFilter, p.id == targetId {
                p.image_path = newPath
                performerFilter = p
            }
            // Update cachedPosts in-place so the avatar refreshes without
            // replacing the array (which would cause the scroll view to jump).
            cachedPosts = cachedPosts.map { post in
                let updatedImages = post.images.map { img -> StashImage in
                    guard var mutablePerformers = img.performers,
                          let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId })
                    else { return img }
                    var mutableImg = img
                    mutablePerformers[pIndex].image_path = newPath
                    mutableImg.performers = mutablePerformers
                    return mutableImg
                }
                return StashLinePost(id: post.id, images: updatedImages)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageRatingUpdated"))) { notification in
            guard let imageId = notification.userInfo?["imageId"] as? String else { return }
            let rating100 = notification.userInfo?["rating100"] as? Int
            patchCachedAndFullScreenImage(imageId: imageId) { $0.withRating(rating100) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageOCounterUpdated"))) { notification in
            guard let imageId = notification.userInfo?["imageId"] as? String,
                  let oCounter = notification.userInfo?["oCounter"] as? Int else { return }
            patchCachedAndFullScreenImage(imageId: imageId) { $0.withOCounter(oCounter) }
        }
        .onChange(of: performerFilter) { _, _ in
            performSearch()
        }
        .onChange(of: includeGifsInTimeline) { _, _ in
            performSearch()
        }
        .onChange(of: externalPerformerFilter) { _, newValue in
            performerFilter = newValue
        }
        .fullScreenCover(item: $fullScreenPresentation) { presentation in
            NavigationStack {
                FullScreenImageView(
                    images: $fullScreenImages,
                    selectedImageId: presentation.selectedImageId,
                    onLoadMore: nil
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            fullScreenPresentation = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $performerDetailPresented) { performer in
            NavigationStack {
                PerformerDetailView(performer: performer.toPerformer())
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                performerDetailPresented = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(appearanceManager.tintColor)
                            }
                        }
                    }
            }
        }
        .onChange(of: fullScreenImages.count) { _, _ in
            let newIds = Set(fullScreenImages.map(\.id))
            let removed = lastFullScreenImageIds.subtracting(newIds)
            guard !removed.isEmpty else {
                lastFullScreenImageIds = newIds
                return
            }
            viewModel.allImages.removeAll { removed.contains($0.id) }
            lastFullScreenImageIds = newIds
        }
    }

    @ViewBuilder
    private func profileHeader(performer: GalleryPerformer) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Avatar
                // Avatar — wie Bild-Vollbild: Detail per `fullScreenCover` auf Feed-Ebene, kein Push.
                Button {
                    performerDetailPresented = performer
                } label: {
                    Group {
                        if let url = performer.thumbnailURL {
                            CustomAsyncImage(url: url) { loader in
                                if loader.isLoading {
                                    Circle().fill(Color.gray.opacity(0.3))
                                } else if let img = loader.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Circle().fill(Color.gray.opacity(0.3))
                                        .overlay(Text(performer.name.prefix(1)).font(.title2.bold()).foregroundColor(.white))
                                }
                            }
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                                .overlay(Text(performer.name.prefix(1)).font(.title2.bold()).foregroundColor(.white))
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
                }
                .buttonStyle(.plain)

                // Stats
                VStack(alignment: .leading, spacing: 8) {
                    Text(performer.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        statColumn(value: viewModel.totalImages, label: "Images")
                        Divider().frame(height: 32).padding(.horizontal, 12)
                        statColumn(value: cachedPosts.count, label: "Sets")
                        Divider().frame(height: 32).padding(.horizontal, 12)
                        statColumn(value: viewModel.allImages.reduce(0) { $0 + ($1.o_counter ?? 0) }, label: "Counter")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            Divider()
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.primary)
            if label.contains(".") {
                Image(systemName: label)
                    .font(.system(size: 11))
                    .foregroundColor(appearanceManager.tintColor)
            } else {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        prepareScrollToTopAfterNextFetch()
        stashLineListFilters.changeSortOption(to: newOption, viewModel: viewModel)
    }

    private func computeGroupedPosts() -> [StashLinePost] {
        let built = StashImageFilenameKeys.buildPosts(
            from: viewModel.allImages,
            sort: stashLineListFilters.selectedSortOption,
            policy: groupingPolicy,
            groupEnabled: groupIntoSets,
            sessionCache: &sessionKeyCache
        )
        return built.map { StashLinePost(id: $0.id, images: $0.images) }
    }

    private var feedContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let performer = performerFilter, !isEmbedded {
                        profileHeader(performer: performer)
                    }
                    ForEach(Array(cachedPosts.enumerated()), id: \.element.id) { idx, post in
                        StashLinePostView(post: post, viewModel: viewModel, onPerformerTap: onPerformerTap != nil ? { performer in
                            onPerformerTap?(performer)
                        } : nil, onRequestFullScreen: { images, selectedId in
                            fullScreenImages = images
                            lastFullScreenImageIds = Set(images.map(\.id))
                            fullScreenPresentation = StashLineFullScreenPresentation(selectedImageId: selectedId)
                        }, onRequestPerformerDetail: { performerDetailPresented = $0 })
                        .id(post.id)
                        .onAppear {
                            let tailPrefetch = 4
                            let threshold = max(0, cachedPosts.count - tailPrefetch)
                            if idx >= threshold {
                                viewModel.loadMoreImages()
                            }
                        }
                    }

                    if viewModel.isLoadingImages {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else if viewModel.hasMoreImages && !viewModel.allImages.isEmpty {
                        Color.clear.frame(height: 1)
                            .onAppear { viewModel.loadMoreImages() }
                    }
                }
            }
            .refreshable { performSearch() }
            .onChange(of: programmaticScrollGeneration) { _, _ in
                guard let id = programmaticScrollRowId, !id.isEmpty else { return }
                let delayNs: UInt64 = isEmbedded ? 160_000_000 : 50_000_000
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: delayNs)
                    scrollProxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }
}

// MARK: - Post Model

private struct StashLineFullScreenPresentation: Identifiable {
    let id = UUID()
    let selectedImageId: String
}

struct StashLinePost: Identifiable {
    let id: String
    let images: [StashImage]

    /// Stable feed identity — prefer `groupKey` from `StashImageFilenameKeys.buildPosts`.
    init(id: String, images: [StashImage]) {
        self.id = id
        self.images = images
    }

    init(images: [StashImage]) {
        self.images = images
        self.id = images.first.map { "single|\($0.id)" } ?? UUID().uuidString
    }

    var primaryImage: StashImage { images[0] }
    var isSet: Bool { images.count > 1 }
}

// MARK: - Post View

struct StashLinePostView: View {
    let post: StashLinePost
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    var onPerformerTap: ((GalleryPerformer) -> Void)? = nil
    /// Vollbild-Galerie wird auf `StashLineView`-Ebene präsentiert (ein `fullScreenCover`, kein Scroll-Binding).
    var onRequestFullScreen: (([StashImage], String) -> Void)? = nil
    /// Performer-Detail wie Bild-Vollbild: Parent zeigt `fullScreenCover`.
    var onRequestPerformerDetail: ((GalleryPerformer) -> Void)? = nil

    @State private var showHeartAnimation = false
    @State private var heartScale: CGFloat = 0
    @State private var heartOpacity: Double = 0
    @State private var oCounters: [String: Int]
    @State private var ratings: [String: Int]
    @State private var visibleCarouselImageId: String
    @State private var isExpanded = false
    /// Bei mehreren Bildern: Seitenverhältnis der Gruppe im expandierten Zustand bleibt vom **hier** gewählten Bild,
    /// bis erneut doppelt getippt wird — unabhängig vom Wischen zu anderen Seiten.
    @State private var expandedHeightAnchorIndex: Int? = nil
    @AppStorage("stashline_load_full_images") private var loadFullImages: Bool = true
    @AppStorage("stashline_square_crop") private var squareCrop = false

    private let actionIconSize: CGFloat = 16
    private let setThumbnailSize: CGFloat = 52
    private let actionIconFrame: CGFloat = 22

    private var carouselIndex: Int {
        post.images.firstIndex(where: { $0.id == visibleCarouselImageId }) ?? 0
    }

    var image: StashImage {
        post.images.first(where: { $0.id == visibleCarouselImageId }) ?? post.images[0]
    }
    var localOCounter: Int { oCounters[image.id] ?? image.o_counter ?? 0 }
    var localRating: Int { ratings[image.id] ?? image.rating100 ?? 0 }
    
    private func actionIcon(_ systemName: String, tint: Color? = nil, scale: CGFloat = 1) -> some View {
        Image(systemName: systemName)
            .font(.system(size: actionIconSize, weight: .semibold))
            .frame(width: actionIconFrame, height: actionIconFrame, alignment: .center)
            .scaleEffect(scale)
            .foregroundColor(tint ?? appearanceManager.tintColor)
    }

    init(
        post: StashLinePost,
        viewModel: StashDBViewModel,
        onPerformerTap: ((GalleryPerformer) -> Void)? = nil,
        onRequestFullScreen: (([StashImage], String) -> Void)? = nil,
        onRequestPerformerDetail: ((GalleryPerformer) -> Void)? = nil
    ) {
        self.post = post
        self.viewModel = viewModel
        self.onPerformerTap = onPerformerTap
        self.onRequestFullScreen = onRequestFullScreen
        self.onRequestPerformerDetail = onRequestPerformerDetail
        self._oCounters = State(initialValue: [:])
        self._ratings = State(initialValue: [:])
        self._visibleCarouselImageId = State(initialValue: post.images.first?.id ?? "")
    }

    private func preserveVisibleCarouselIfPossible() {
        let ids = Set(post.images.map(\.id))
        if ids.contains(visibleCarouselImageId) { return }
        visibleCarouselImageId = post.images.first?.id ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            postHeader

            // Image + overlaid action bar
            imageArea
                .overlay(alignment: .bottom) { actionBar }
                .overlay(alignment: .topLeading) {
                    if !squareCrop {
                        Button {
                            onRequestFullScreen?(post.images, image.id)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                .clipShape(Circle())
                        }
                        .padding(.top, image.isGifFile ? 42 : 10)
                        .padding(.leading, 10)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageRatingUpdated"))) { notification in
                    guard let imageId = notification.userInfo?["imageId"] as? String,
                          post.images.contains(where: { $0.id == imageId }) else { return }
                    ratings[imageId] = notification.userInfo?["rating100"] as? Int ?? 0
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ImageOCounterUpdated"))) { notification in
                    guard let imageId = notification.userInfo?["imageId"] as? String,
                          let oCounter = notification.userInfo?["oCounter"] as? Int,
                          post.images.contains(where: { $0.id == imageId }) else { return }
                    oCounters[imageId] = oCounter
                }

            if squareCrop && post.isSet {
                setThumbnailCarousel
            }

            HStack(alignment: .top) {
                if let title = image.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                Spacer()
                
                HStack(spacing: 16) {
                    if let performers = image.performers, !performers.isEmpty {
                        if performers.count == 1, let performer = performers.first {
                            Button {
                                onRequestPerformerDetail?(performer)
                            } label: {
                                actionIcon("person.fill", scale: 1.15)
                            }
                        } else {
                            Menu {
                                ForEach(performers) { performer in
                                    Button(performer.name) {
                                        onRequestPerformerDetail?(performer)
                                    }
                                }
                            } label: {
                                actionIcon("person.fill", scale: 1.15)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if let tags = image.tags, !tags.isEmpty {
                tagLine(tags: tags)
            }

            Spacer().frame(height: 12)
            Divider()
        }
        .onChange(of: post.images.map(\.id)) { _, _ in
            preserveVisibleCarouselIfPossible()
        }
    }

    private var postHeader: some View {
        let performers = image.performers ?? []
        return HStack(spacing: 10) {
            // Performers
            HStack(spacing: 0) {
                ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                    if onPerformerTap != nil {
                        Button {
                            onRequestPerformerDetail?(performer)
                        } label: {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if performers.isEmpty {
                    Circle()
                        .fill(appearanceManager.tintColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundColor(appearanceManager.tintColor)
                                .font(.system(size: 14))
                        }
                }
            }
            // negative spacing for overlap when multiple
            .padding(.trailing, performers.count > 1 ? CGFloat(performers.count - 1) * -10 : 0)

            // Names
            VStack(alignment: .leading, spacing: 1) {
                if performers.isEmpty {
                    Text("Unknown")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                } else if performers.count == 1 {
                    let performer = performers[0]
                    if let onPerformerTap = onPerformerTap {
                        Button(action: { onPerformerTap(performer) }) {
                            Text(performer.name)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                            Text(performer.name)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                            if let onPerformerTap = onPerformerTap {
                                Button(action: { onPerformerTap(performer) }) {
                                    Text(performer.name)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                                    Text(performer.name)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                            if idx < performers.count - 1 {
                                Text("&")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if let studio = image.studio {
                    Text(studio.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let date = image.date {
                Text(date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func performerAvatar(_ performer: GalleryPerformer, offset: Int) -> some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable().scaledToFill()
                        } else {
                            Text(String(performer.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                } else {
                    Text(String(performer.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
            .offset(x: CGFloat(offset) * -10)
    }

    // MARK: - Image

    /// Eingeklappt: Höhe nach dem **ersten** Bild. Expandiert: Höhe nach dem Bild am `expandedHeightAnchorIndex`
    /// (beim Doppel-Tap gesetzt), nicht nach der aktuell sichtbaren Carousel-Seite.
    private var groupDisplayAspectRatio: CGFloat {
        let anchor: StashImage
        if isExpanded, post.isSet, let hIdx = expandedHeightAnchorIndex, post.images.indices.contains(hIdx) {
            anchor = post.images[hIdx]
        } else if isExpanded {
            anchor = post.images.first ?? image
        } else {
            anchor = post.images.first ?? image
        }
        return nativeAspectRatio(for: anchor)
    }

    private var displayAspectRatio: CGFloat {
        squareCrop ? 1.0 : groupDisplayAspectRatio
    }

    private func nativeAspectRatio(for img: StashImage) -> CGFloat {
        if let w = img.visual_files?.first?.width, let h = img.visual_files?.first?.height, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 1.0
    }

    /// Doppel-Tap auf einer Carousel-Seite bzw. dem Einzelbild: Expand/Collapse und klare Zuordnung zum Seitenindex
    /// (vermeidet, dass `scrollPosition` und äußeres Tap-Gesture noch auf Seite 1 stehen, obwohl Seite 2 sichtbar ist).
    private func handleStashLineImageDoubleTap(carouselPageIndex index: Int) {
        guard !squareCrop else { return }
        guard post.images.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            if post.isSet {
                if isExpanded {
                    if index == carouselIndex {
                        isExpanded = false
                        expandedHeightAnchorIndex = nil
                    } else {
                        visibleCarouselImageId = post.images[index].id
                    }
                } else {
                    visibleCarouselImageId = post.images[index].id
                    expandedHeightAnchorIndex = index
                    isExpanded = true
                }
            } else {
                isExpanded.toggle()
                expandedHeightAnchorIndex = isExpanded ? 0 : nil
            }
        }
    }

    private func openFullScreen(imageId: String) {
        onRequestFullScreen?(post.images, imageId)
    }

    /// Feed always shows still thumbnails for GIFs; full animation is fullscreen-only.
    private func feedImageURL(for img: StashImage) -> URL? {
        if img.isGifFile {
            return img.thumbnailURL
        }
        return loadFullImages ? (img.imageURL ?? img.previewURL ?? img.thumbnailURL) : img.thumbnailURL
    }

    private var gifBadgeLabel: some View {
        Text("GIF")
            .font(.caption2).fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(DesignTokens.Opacity.badge))
            .clipShape(Capsule())
            .padding(8)
    }

    private var imageArea: some View {
        ZStack(alignment: .bottom) {
            if post.isSet {
                ZStack(alignment: .topTrailing) {
                    TabView(selection: $visibleCarouselImageId) {
                        ForEach(post.images) { img in
                            singleImageView(img)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    if !squareCrop,
                                       let index = post.images.firstIndex(where: { $0.id == img.id }) {
                                        handleStashLineImageDoubleTap(carouselPageIndex: index)
                                    }
                                }
                                .onTapGesture {
                                    if squareCrop {
                                        openFullScreen(imageId: img.id)
                                    }
                                }
                                .tag(img.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(displayAspectRatio, contentMode: .fit)

                    // Page indicator pill — top right
                    Text("\(carouselIndex + 1)/\(post.images.count)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .padding(8)
                }
            } else {
                GeometryReader { geo in
                    singleImageView(image)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if !squareCrop {
                                handleStashLineImageDoubleTap(carouselPageIndex: 0)
                            }
                        }
                        .onTapGesture {
                            if squareCrop {
                                openFullScreen(imageId: image.id)
                            }
                        }
                }
                .aspectRatio(displayAspectRatio, contentMode: .fit)
                .clipped()
            }

            // Counter burst animation
            if showHeartAnimation {
                Image(systemName: appearanceManager.oCounterIconFilled)
                    .font(.system(size: 80))
                    .foregroundColor(appearanceManager.tintColor.opacity(0.9))
                    .scaleEffect(heartScale)
                    .opacity(heartOpacity)
                    .shadow(color: .black.opacity(0.3), radius: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            if image.isGifFile {
                gifBadgeLabel
            }
        }
    }

    @ViewBuilder
    private func singleImageView(_ img: StashImage) -> some View {
        ZStack {
            Color.studioHeaderGray
            if let url = feedImageURL(for: img) {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let loaded = loader.image {
                        Group {
                            if squareCrop {
                                loaded
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                loaded
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .clipped()
    }

    private var setThumbnailCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(post.images.enumerated()), id: \.offset) { index, img in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                visibleCarouselImageId = img.id
                            }
                        } label: {
                            setThumbnail(for: img, isSelected: img.id == visibleCarouselImageId)
                        }
                        .buttonStyle(.plain)
                        .id(img.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: visibleCarouselImageId) { _, newId in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(visibleCarouselImageId, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func setThumbnail(for img: StashImage, isSelected: Bool) -> some View {
        let borderWidth: CGFloat = isSelected ? 2 : 0
        let size = setThumbnailSize - borderWidth * 2

        ZStack {
            Color.studioHeaderGray
            if let url = img.thumbnailURL {
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
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                .stroke(appearanceManager.tintColor, lineWidth: borderWidth)
        }
        .frame(width: setThumbnailSize, height: setThumbnailSize)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            // O-counter pill (left)
            Button(action: { incrementOCounter() }) {
                HStack(spacing: 4) {
                    Image(systemName: localOCounter > 0 ? appearanceManager.oCounterIconFilled : appearanceManager.oCounterIcon)
                        .font(.system(size: 16))
                        .foregroundColor(localOCounter > 0 ? appearanceManager.tintColor : .white)
                    Text("\(localOCounter)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Rating pill (right)
            StarRatingView(
                rating100: localRating,
                isInteractive: true,
                size: 16,
                spacing: 4,
                isVertical: false
            ) { newRating in
                let imageId = image.id
                let originalRating = localRating
                ratings[imageId] = newRating ?? 0
                viewModel.updateImageRating(imageId: imageId, rating100: newRating) { success in
                    if !success {
                        DispatchQueue.main.async { self.ratings[imageId] = originalRating }
                        ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(DesignTokens.Opacity.badge))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Tag Line

    private func tagLine(tags: [Tag]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(8)) { tag in
                    Text("#\(tag.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    // MARK: - O-Counter Logic

    private func incrementOCounter() {
        let imageId = image.id
        let originalCount = localOCounter
        oCounters[imageId] = originalCount + 1

        // Burst animation
        showHeartAnimation = true
        heartScale = 0.3
        heartOpacity = 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            heartScale = 1.2
        }
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) {
            heartOpacity = 0
            heartScale = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showHeartAnimation = false
            heartScale = 0
        }

        // Persist via increment mutation (same as ReelsView clips)
        viewModel.incrementImageOCounter(imageId: imageId) { returnedCount in
            if let count = returnedCount {
                DispatchQueue.main.async { self.oCounters[imageId] = count }
            } else {
                DispatchQueue.main.async {
                    self.oCounters[imageId] = originalCount
                    ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
    
}
#endif
