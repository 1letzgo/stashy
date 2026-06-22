//
//  PerformerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct PerformerDetailView: View {
    @State var performer: Performer
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var isHeaderExpanded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var fullPerformer: Performer?
    @State private var performerLiveFilterSheetPresented = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    /// Verhindert mehrfaches `loadData()` bei wiederholtem SwiftUI-`onAppear` (leere Performer → identische Refetch-Schleife).
    @State private var hasRunPerformerDetailInitialLoad = false
    @State private var hotOrNotBattleLine: String?
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    init(performer: Performer) {
        _performer = State(initialValue: performer)
        let sc = performer.sceneCount
        // Do not open the Scenes stack when we have no scene signal; galleries (or other tabs after load) avoid an empty default.
        let initialTab: DetailTab = sc > 0 ? .scenes : .galleries
        _selectedDetailTab = State(initialValue: initialTab)
        _linkedStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .performer(performer.id)))
        _linkedTags = StateObject(wrappedValue: DetailLinkedTagsFilterModel(scope: .performer(performer.id)))
        _linkedGalleries = StateObject(wrappedValue: DetailLinkedGalleriesFilterModel(scope: .performer(performer.id)))
        _linkedImages = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: .performer(performer.id)))
    }

    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
             return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        }
    }

    private var displayPerformer: Performer {
        fullPerformer ?? performer
    }
    
    private var effectiveScenes: Int {
        if viewModel.performerDetailScenesInitialFetchCompleted {
            return viewModel.totalPerformerScenes
        }
        return max(viewModel.totalPerformerScenes, displayPerformer.sceneCount)
    }
    
    private var effectiveGalleries: Int {
        max(viewModel.totalPerformerGalleries, displayPerformer.galleryCount ?? 0)
    }
    
    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveGalleries > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    private var performerDetailCatalogFloatingChromeForFooter: CatalogFloatingChromeState {
        let primaryEmpty: Bool = {
            switch selectedDetailTab {
            case .scenes: return viewModel.performerScenes.isEmpty
            case .galleries: return viewModel.performerGalleries.isEmpty
            case .studios: return viewModel.detailStudios.isEmpty
            case .tags: return viewModel.detailTags.isEmpty
            case .groups: return viewModel.detailGroups.isEmpty
            case .images: return viewModel.detailImages.isEmpty
            }
        }()
        return CatalogFloatingChromeState(
            hasActiveServerConfig: configManager.activeConfig != nil,
            primaryListIsEmpty: primaryEmpty,
            errorMessage: viewModel.errorMessage,
            imageFindListError: viewModel.imageFindListError
        )
    }

    private var shouldAutoSwitchToPerformerGalleriesForEmptyScenes: Bool {
        viewModel.totalPerformerScenes == 0
            && !viewModel.isLoadingPerformerScenes
            && viewModel.totalPerformerGalleries > 0
            && effectiveScenes == 0
            && !viewModel.isPerformerDetailSceneListConstrained
    }

    @ViewBuilder
    private var performerScenesStack: some View {
        VStack(spacing: 12) {
            headerView(displayPerformer: displayPerformer, battleLine: hotOrNotBattleLine)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScenesView(
                hideTitle: true,
                scope: .performer(performerId: performer.id),
                sharedViewModel: viewModel,
                externalLiveFilterSheetBinding: $performerLiveFilterSheetPresented,
                showsFloatingFilterButton: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var nonScenesScrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView(displayPerformer: displayPerformer, battleLine: hotOrNotBattleLine)

                if selectedDetailTab == .galleries {
                    if !viewModel.performerGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingPerformerGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .tags {
                    tagGrid
                } else if selectedDetailTab == .groups {
                    groupGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                } else if selectedDetailTab == .scenes {
                    Text("No scenes found")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
    }

    var body: some View {
        performerDetailWithLinkedGalleriesAndImagesSheets
    }

    private var performerDetailWithLinkedStudiosSheets: some View {
        performerDetailCoreChrome
            .sheet(isPresented: $linkedStudios.showFilterSortSheet) {
                performerDetailStudiosFilterSheet
            }
            .onChange(of: linkedStudios.catalogPresetRowSelection) { _, newId in
                linkedStudios.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedStudios.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedStudios.catalogPresetNameInput)
                Button("Save") { linkedStudios.savePresetAs(name: linkedStudios.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedStudios.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedStudios.renameCatalogPresetInput)
                Button("Save") { linkedStudios.renamePreset(to: linkedStudios.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedStudios.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedStudios.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedStudios.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var performerDetailWithLinkedTagsSheets: some View {
        performerDetailWithLinkedStudiosSheets
            .sheet(isPresented: $linkedTags.showFilterSortSheet) {
                performerDetailTagsFilterSheet
            }
            .onChange(of: linkedTags.catalogPresetRowSelection) { _, newId in
                linkedTags.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedTags.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedTags.catalogPresetNameInput)
                Button("Save") { linkedTags.savePresetAs(name: linkedTags.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedTags.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedTags.renameCatalogPresetInput)
                Button("Save") { linkedTags.renamePreset(to: linkedTags.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedTags.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedTags.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedTags.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var performerDetailWithLinkedGalleriesAndImagesSheets: some View {
        performerDetailWithLinkedTagsSheets
            .sheet(isPresented: $linkedGalleries.showFilterSortSheet) {
                performerDetailGalleriesFilterSheet
            }
            .onChange(of: linkedGalleries.catalogPresetRowSelection) { _, newId in
                linkedGalleries.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedGalleries.catalogPresetNameInput)
                Button("Save") { linkedGalleries.savePresetAs(name: linkedGalleries.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedGalleries.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedGalleries.renameCatalogPresetInput)
                Button("Save") { linkedGalleries.renamePreset(to: linkedGalleries.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedGalleries.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedGalleries.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedGalleries.deletePresetConfirmationText(viewModel: viewModel))
            }
            .sheet(isPresented: $linkedImages.showFilterSortSheet) {
                performerDetailImagesFilterSheet
            }
            .onChange(of: linkedImages.catalogPresetRowSelection) { _, newId in
                linkedImages.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedImages.catalogPresetNameInput)
                Button("Save") { linkedImages.savePresetAs(name: linkedImages.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedImages.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedImages.renameCatalogPresetInput)
                Button("Save") { linkedImages.renamePreset(to: linkedImages.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedImages.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedImages.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedImages.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    /// Scenes stack only when we know or assume scenes exist; avoids landing on an empty `ScenesView` when counts are zero.
    private var showsPerformerScenesStack: Bool {
        selectedDetailTab == .scenes && (effectiveScenes > 0 || viewModel.isLoadingPerformerScenes)
    }

    private var performerDetailCoreChrome: some View {
        Group {
            if showsPerformerScenesStack {
                performerScenesStack
            } else {
                nonScenesScrollContent
            }
        }
        .applyAppBackground()
        .task(id: displayPerformer.id) {
            hotOrNotBattleLine = nil
            if let line = await HotOrNotBattleDisplay.fetchRankSlashTotal(performerId: displayPerformer.id) {
                hotOrNotBattleLine = line
            }
        }
        .onAppear {
            if !hasRunPerformerDetailInitialLoad {
                hasRunPerformerDetailInitialLoad = true
                loadData()
            }
            isFavorite = performer.favorite ?? false
        }
        .onChange(of: viewModel.totalPerformerGalleries) { oldValue, newValue in
            if newValue > 0 && shouldAutoSwitchToPerformerGalleriesForEmptyScenes {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: viewModel.totalPerformerScenes) { oldValue, newValue in
            if newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else if shouldAutoSwitchToPerformerGalleriesForEmptyScenes {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            } else if newValue == 0, !viewModel.isLoadingPerformerScenes, selectedDetailTab == .scenes, effectiveScenes == 0 {
                if let first = availableTabs.first {
                    withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = first }
                }
            }
        }
        .onChange(of: viewModel.isLoadingPerformerScenes) { _, loading in
            if !loading, selectedDetailTab == .scenes, effectiveScenes == 0, let first = availableTabs.first {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = first }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            print("🔄 SceneDeleted - Refreshing performer metadata")
            loadPerformerMetadata()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            guard let targetId = notification.userInfo?["performerId"] as? String,
                  let newPath = notification.userInfo?["newImagePath"] as? String else { return }
            if performer.id == targetId {
                performer.imagePath = newPath
            }
            if fullPerformer?.id == targetId {
                fullPerformer?.imagePath = newPath
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayPerformer.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if showTabSwitcher {
                    Menu {
                        ForEach(availableTabs, id: \.self) { tab in
                            Button(action: {
                                withAnimation(DesignTokens.Animation.quick) {
                                    selectedDetailTab = tab
                                }
                            }) {
                                HStack {
                                    Text(tab.rawValue)
                                    if selectedDetailTab == tab {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedDetailTab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .floatingActionBar(isPresented: true, catalogChrome: performerDetailCatalogFloatingChromeForFooter) {
            HStack(spacing: 0) {
                Button {
                    guard !isUpdatingFavorite else { return }
                    HapticManager.light()
                    isUpdatingFavorite = true
                    let newState = !isFavorite
                    withAnimation(DesignTokens.Animation.quick) { isFavorite = newState }

                    viewModel.togglePerformerFavorite(performerId: performer.id, favorite: newState) { success in
                        DispatchQueue.main.async {
                            if !success {
                                isFavorite = !newState
                                ToastManager.shared.show("Failed to update favorite", icon: "exclamationmark.triangle", style: .error)
                            }
                            isUpdatingFavorite = false
                        }
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : appearanceManager.tintColor)
                }
                .frame(maxWidth: .infinity)

                if selectedDetailTab == .scenes {
                    Button {
                        HapticManager.light()
                        performerLiveFilterSheetPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    .accessibilityLabel("Filter and sort")
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    Button {
                        HapticManager.light()
                        linkedGalleries.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedGalleries.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedGalleries.catalogFilterSortFABActive {
                                    Circle()
                                        .fill(appearanceManager.tintColor)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel("Filter and sort")
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .studios {
                    Button {
                        HapticManager.light()
                        linkedStudios.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedStudios.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedStudios.catalogFilterSortFABActive {
                                    Circle()
                                        .fill(appearanceManager.tintColor)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel("Filter and sort")
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .tags {
                    Button {
                        HapticManager.light()
                        linkedTags.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedTags.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedTags.catalogFilterSortFABActive {
                                    Circle()
                                        .fill(appearanceManager.tintColor)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel("Filter and sort")
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    Button {
                        HapticManager.light()
                        linkedImages.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedImages.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedImages.catalogFilterSortFABActive {
                                    Circle()
                                        .fill(appearanceManager.tintColor)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel("Filter and sort")
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var performerDetailStudiosFilterSheet: some View {
        StudiosCatalogFilterSortSheet(
            serverFilters: linkedStudios.sortedServerStudioFilters(viewModel: viewModel),
            localPresets: linkedStudios.localCatalogPresets,
            selectedPresetRowId: $linkedStudios.catalogPresetRowSelection,
            liveChipRowsVisible: linkedStudios.studioLiveChipRowsVisible,
            sortOption: linkedStudios.selectedSortOption,
            onSortChange: { linkedStudios.changeSortOption(to: $0, viewModel: viewModel) },
            liveMinRating: $linkedStudios.liveFilterMinRating,
            liveFavorite: $linkedStudios.liveFilterFavorite,
            liveScenes: $linkedStudios.liveFilterScenes,
            onApply: { linkedStudios.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedStudios.catalogPresetRowSelection = ""
                linkedStudios.selectedFilter = nil
                linkedStudios.clearLiveChipsOnly()
                linkedStudios.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedStudios.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedStudios.catalogPresetNameInput = ""
                linkedStudios.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedStudios.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedStudios.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedStudios.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedStudios.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedStudios.renameCatalogPresetInput = p.name
                }
                linkedStudios.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedStudios.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedStudios.catalogPresetRowSelection)
            linkedStudios.refreshLocalPresets()
            linkedStudios.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var performerDetailTagsFilterSheet: some View {
        TagsCatalogFilterSortSheet(
            serverFilters: linkedTags.sortedServerTagFilters(viewModel: viewModel),
            localPresets: linkedTags.localCatalogPresets,
            selectedPresetRowId: $linkedTags.catalogPresetRowSelection,
            liveChipRowsVisible: linkedTags.tagLiveChipRowsVisible,
            sortOption: linkedTags.selectedSortOption,
            onSortChange: { linkedTags.changeSortOption(to: $0, viewModel: viewModel) },
            liveFavorite: $linkedTags.liveFilterFavorite,
            liveHasScenes: $linkedTags.liveFilterHasScenes,
            onApply: { linkedTags.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedTags.catalogPresetRowSelection = ""
                linkedTags.selectedFilter = nil
                linkedTags.clearLiveChipsOnly()
                linkedTags.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedTags.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedTags.catalogPresetNameInput = ""
                linkedTags.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedTags.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedTags.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedTags.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedTags.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedTags.renameCatalogPresetInput = p.name
                }
                linkedTags.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedTags.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedTags.catalogPresetRowSelection)
            linkedTags.refreshLocalPresets()
            linkedTags.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var performerDetailGalleriesFilterSheet: some View {
        GalleriesCatalogFilterSortSheet(
            serverFilters: linkedGalleries.sortedServerGalleryFilters(viewModel: viewModel),
            localPresets: linkedGalleries.localCatalogPresets,
            selectedPresetRowId: $linkedGalleries.catalogPresetRowSelection,
            liveChipRowsVisible: linkedGalleries.galleryLiveChipRowsVisible,
            sortOption: linkedGalleries.selectedSortOption,
            onSortChange: { linkedGalleries.changeSortOption(to: $0, viewModel: viewModel) },
            liveMinRating: $linkedGalleries.liveFilterMinRating,
            liveFavorite: $linkedGalleries.liveFilterFavorite,
            liveFiles: $linkedGalleries.liveFilterFiles,
            liveStudioId: $linkedGalleries.liveFilterStudioId,
            studioPickerOptions: linkedGalleries.studioPickerOptions,
            studioPickerLoading: linkedGalleries.studioPickerLoading,
            onStudioPickerSectionAppear: { linkedGalleries.loadStudioPickerOptions(viewModel: viewModel) },
            onApply: { linkedGalleries.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedGalleries.catalogPresetRowSelection = ""
                linkedGalleries.selectedFilter = nil
                linkedGalleries.clearLiveChipsOnly()
                linkedGalleries.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedGalleries.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedGalleries.catalogPresetNameInput = ""
                linkedGalleries.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedGalleries.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedGalleries.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedGalleries.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedGalleries.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedGalleries.renameCatalogPresetInput = p.name
                }
                linkedGalleries.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedGalleries.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            var sel = linkedGalleries.catalogPresetRowSelection
            ListLivePresetTag.migrateLegacySelection(&sel)
            linkedGalleries.catalogPresetRowSelection = sel
            linkedGalleries.refreshLocalPresets()
            linkedGalleries.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var performerDetailImagesFilterSheet: some View {
        ImagesCatalogFilterSortSheet(
            serverFilters: linkedImages.sortedServerImageFilters(viewModel: viewModel),
            localPresets: linkedImages.localCatalogPresets,
            selectedPresetRowId: $linkedImages.catalogPresetRowSelection,
            filterMenuTitleFallback: linkedImages.selectedFilter?.name,
            liveChipRowsVisible: linkedImages.imageLiveChipRowsVisible,
            showMediaTypeFilter: linkedImages.showImageMediaTypeFilter,
            sortOption: linkedImages.selectedSortOption,
            onSortChange: { linkedImages.changeSortOption(to: $0, viewModel: viewModel) },
            liveMinRating: $linkedImages.liveFilterMinRating,
            livePerformerFavorite: $linkedImages.liveFilterPerformerFavorite,
            liveOrganized: $linkedImages.liveFilterOrganized,
            liveOCounterTag: $linkedImages.liveFilterOCounterTag,
            liveStudioIds: $linkedImages.liveFilterStudioIds,
            liveTagIds: $linkedImages.liveFilterTagIds,
            liveMediaKind: $linkedImages.liveFilterMediaKind,
            studioPickerOptions: linkedImages.studioPickerOptions,
            studioPickerLoading: linkedImages.studioPickerLoading,
            onStudioPickerSectionAppear: { linkedImages.loadStudioPickerOptions(viewModel: viewModel) },
            tagPickerOptions: linkedImages.tagPickerOptions,
            tagPickerLoading: linkedImages.tagPickerLoading,
            onTagPickerSectionAppear: { linkedImages.loadTagPickerOptions(viewModel: viewModel) },
            onApply: { linkedImages.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedImages.catalogPresetRowSelection = ""
                linkedImages.selectedFilter = nil
                linkedImages.clearLiveChipsOnly()
                linkedImages.refetchImages(viewModel: viewModel, initial: true)
            },
            onRequestSave: { linkedImages.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedImages.catalogPresetNameInput = ""
                linkedImages.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedImages.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedImages.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedImages.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedImages.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedImages.renameCatalogPresetInput = p.name
                }
                linkedImages.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedImages.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            var sel = linkedImages.catalogPresetRowSelection
            ListLivePresetTag.migrateLegacySelection(&sel)
            linkedImages.catalogPresetRowSelection = sel
            linkedImages.refreshLocalPresets()
            linkedImages.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
            linkedImages.applyResolvedCatalogPresetPickerRowIfNeeded(viewModel: viewModel)
        }
    }
    
    // MARK: - Helper Views & Methods
    
    private func loadData() {
        if viewModel.performerGalleries.isEmpty && !viewModel.isLoadingPerformerGalleries {
            linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
        }
        
        if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
            linkedImages.refetchImages(viewModel: viewModel, initial: true)
        }
        viewModel.fetchSavedFilters()
        linkedStudios.refetchStudios(viewModel: viewModel, initial: true)
        linkedTags.refetchTags(viewModel: viewModel, initial: true)
        if viewModel.detailGroups.isEmpty && !viewModel.isLoadingDetailGroups {
            viewModel.fetchDetailGroups(performerId: performer.id)
        }
        
        // Always load full metadata to ensure we have counts and details
        loadPerformerMetadata()
    }
    
    private func loadPerformerMetadata() {
        viewModel.fetchPerformer(performerId: performer.id) { fetchedPerformer in
             if let p = fetchedPerformer {
                 self.fullPerformer = p
                 self.isFavorite = p.favorite ?? false
             }
        }
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.performerGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingPerformerGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMorePerformerGalleries && !viewModel.performerGalleries.isEmpty {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMorePerformerGalleries(performerId: performer.id) }
             }
        }
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailStudios) { studio in
                NavigationLink(destination: StudioDetailView(studio: studio)) {
                    StudioCardView(studio: studio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios && !viewModel.detailStudios.isEmpty {
                Color.clear.onAppear { linkedStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
        }
    }
    
    private var tagGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailTags) { tag in
                NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                    TagCardView(tag: tag)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailTags { ProgressView().padding() }
            else if viewModel.hasMoreDetailTags && !viewModel.detailTags.isEmpty {
                Color.clear.onAppear { linkedTags.refetchTags(viewModel: viewModel, initial: false) }
            }
        }
    }
    
    private var groupGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailGroups) { group in
                NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                    GroupCardView(group: group)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailGroups { ProgressView().padding() }
            else if viewModel.hasMoreDetailGroups && !viewModel.detailGroups.isEmpty {
                Color.clear.onAppear { viewModel.fetchDetailGroups(performerId: performer.id, isInitialLoad: false) }
            }
        }
    }
    
    private var imageGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailImages) { image in
                NavigationLink(destination: FullScreenImageView(images: .constant(viewModel.detailImages), selectedImageId: image.id)) {
                    ImageThumbnailCard(image: image)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailImages { ProgressView().padding() }
            else if viewModel.hasMoreDetailImages && !viewModel.detailImages.isEmpty {
                Color.clear.onAppear { linkedImages.refetchImages(viewModel: viewModel, initial: false) }
            }
        }
    }
    
    private func headerView(displayPerformer: Performer, battleLine: String?) -> some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait, flush to edges, cropped from top
            ZStack(alignment: .top) {
                if let thumbnailURL = displayPerformer.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .overlay(ProgressView().scaleEffect(0.6))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .clipped()
                        } else {
                            defaultThumbnailContent(width: imageWidth)
                        }
                    }
                } else {
                    defaultThumbnailContent(width: imageWidth)
                }
            }
            .frame(width: imageWidth, alignment: .top)
            .frame(minHeight: collapsedHeight)
            // Wenn ausgeklappt: Zeilenhöhe = Detailbereich, kein Füllen des übergeordneten VStack (siehe fixedSize am Header)
            .frame(maxHeight: isHeaderExpanded ? nil : collapsedHeight, alignment: .top)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name and Stats
                HStack(alignment: .top, spacing: 8) {
                    Text(displayPerformer.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)
                    
                    Spacer()
                    
                    // Feeds Button (Top Right)
                    if tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true {
                        Button(action: {
                            let sp = ScenePerformer(id: displayPerformer.id, name: displayPerformer.name, birthdate: displayPerformer.birthdate, sceneCount: displayPerformer.sceneCount, galleryCount: displayPerformer.galleryCount, oCounter: displayPerformer.oCounter, updatedAt: nil)
                            coordinator.navigateToReels(performer: sp, mode: nil)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: AppTab.reels.icon)
                                    .font(.system(size: 12, weight: .bold))
                                Text("Feeds")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(Color.pillAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // Grid for Performer Info
                let allDetails = getPerformerDetails(displayPerformer, battleLine: battleLine)
                let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
                
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
        // Nur so hoch wie Inhalt (Name/Details), nicht so hoch wie die komplette übergeordnete Fläche
        .fixedSize(horizontal: false, vertical: true)
        .overlay(
            Group {
                let allDetails = getPerformerDetails(displayPerformer, battleLine: battleLine)
                if allDetails.count > 4 {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.pillAccent)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func cardBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(Color.pillAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(appearanceManager.tintColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(Image(systemName: "person.fill").font(.system(size: 32)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func thumbnailBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
    }

    private func detailStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(Color.pillAccent)
            Text(text).font(.caption).fontWeight(.bold).foregroundColor(.primary)
        }
    }

    private func getPerformerDetails(_ p: Performer, battleLine: String?) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // First row: scenes + galleries; third slot is rating (Stash 0–100).
        list.append((label: "SCENES", value: "\(p.sceneCount)"))
        let galleryDisplay = max(p.galleryCount ?? 0, viewModel.totalPerformerGalleries)
        list.append((label: "GALLERIES", value: "\(galleryDisplay)"))
        list.append((label: "RATING", value: p.rating100.map { String($0) } ?? "—"))
        if let battleLine, !battleLine.isEmpty {
            list.append((label: "BATTLE", value: battleLine))
        }
        
        if let val = p.gender, !val.isEmpty { list.append((label: "GENDER", value: val)) }
        
        let gender = p.gender?.uppercased() ?? ""
        if gender.contains("FEMALE") {
            if let val = p.fakeTits, !val.isEmpty { list.append((label: "Tits", value: val)) }
        } else if gender.contains("MALE") || gender == "MAN" {
            if let val = p.penis_length, val > 0 { list.append((label: "Penis", value: "\(val) cm")) }
        } else {
            // For other genders (Non-binary, etc.), show whatever data is available
            if let val = p.fakeTits, !val.isEmpty { list.append((label: "Tits", value: val)) }
            if let val = p.penis_length, val > 0 { list.append((label: "Penis", value: "\(val) cm")) }
        }
        if let val = p.birthdate, !val.isEmpty { list.append((label: "BORN", value: val)) }
        if let val = p.country, !val.isEmpty { list.append((label: "COUNTRY", value: val)) }
        if let val = p.ethnicity, !val.isEmpty { list.append((label: "ETHNICITY", value: val)) }
        if let val = p.height, val > 0 { list.append((label: "HEIGHT", value: "\(val) cm")) }
        if let val = p.weight, val > 0 { list.append((label: "WEIGHT", value: "\(val) kg")) }
        if let val = p.measurements, !val.isEmpty { list.append((label: "MEASUREMENTS", value: val)) }
        if let val = p.careerLength, !val.isEmpty { list.append((label: "CAREER", value: val)) }
        if let val = p.tattoos, !val.isEmpty { list.append((label: "TATTOOS", value: val)) }
        if let val = p.piercings, !val.isEmpty { list.append((label: "PIERCINGS", value: val)) }
        
        return list
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let samplePerformer = Performer(
        id: "1",
        name: "Sample Performer",
        disambiguation: "Test",
        birthdate: "1990-01-01",
        country: "Germany",
        imagePath: nil,
        sceneCount: 5,
        galleryCount: 1,
        gender: "Female",
        ethnicity: "Caucasian",
        height: 165,
        weight: 55,
        measurements: "34-24-34",
        fakeTits: "No",
        penis_length: nil,
        careerLength: "5 years",
        tattoos: "None",
        piercings: "Navel",
        aliasList: ["Jane Doe", "J.D."],
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil,
        oCounter: 0
    )
    PerformerDetailView(performer: samplePerformer)
}
#endif
