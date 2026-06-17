//
//  StudioDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct StudioDetailView: View {
    let studio: Studio
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var studioLiveFilterSheetPresented = false
    @StateObject private var linkedPerformers: DetailLinkedPerformersFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedChildStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false // Added state for expansion
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case performers = "Performers"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"
    }
    @State private var selectedDetailTab: DetailTab

    init(studio: Studio) {
        self.studio = studio
        let sc = studio.sceneCount
        let gal = studio.galleryCount ?? 0
        _selectedDetailTab = State(initialValue: sc > 0 ? .scenes : (gal > 0 ? .galleries : .scenes))
        _linkedPerformers = StateObject(wrappedValue: DetailLinkedPerformersFilterModel(scope: .studio(studio.id), initialSort: .nameAsc))
        _linkedTags = StateObject(wrappedValue: DetailLinkedTagsFilterModel(scope: .studio(studio.id)))
        _linkedChildStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .parentStudio(studio.id)))
        _linkedGalleries = StateObject(wrappedValue: DetailLinkedGalleriesFilterModel(scope: .studio(studio.id)))
        _linkedImages = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: .studio(studio.id)))
    }

    // Computed properties for counts
    private var effectiveScenesCount: Int {
        max(viewModel.totalStudioScenes, studio.sceneCount)
    }
    
    private var effectiveGalleriesCount: Int {
        max(viewModel.totalStudioGalleries, studio.galleryCount ?? 0)
    }
    
    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenesCount > 0 { tabs.append(.scenes) }
        if effectiveGalleriesCount > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailPerformers > 0 { tabs.append(.performers) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    private var studioDetailCatalogFloatingChromeForFooter: CatalogFloatingChromeState {
        let primaryEmpty: Bool = {
            switch selectedDetailTab {
            case .scenes: return viewModel.studioScenes.isEmpty
            case .galleries: return viewModel.studioGalleries.isEmpty
            case .studios: return viewModel.detailStudios.isEmpty
            case .performers: return viewModel.detailPerformers.isEmpty
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

    @ViewBuilder
    private var studioScenesStack: some View {
        VStack(spacing: 12) {
            headerCard
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScenesView(
                hideTitle: true,
                scope: .studio(studioId: studio.id),
                sharedViewModel: viewModel,
                externalLiveFilterSheetBinding: $studioLiveFilterSheetPresented,
                showsFloatingFilterButton: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var nonScenesStudioScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard

                if selectedDetailTab == .galleries {
                    if !viewModel.studioGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingStudioGalleries {
                        loadingView(message: "Loading galleries...")
                    } else {
                        emptyView(message: "No galleries found", icon: "photo.on.rectangle")
                    }
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .performers {
                    performerGrid
                } else if selectedDetailTab == .tags {
                    tagGrid
                } else if selectedDetailTab == .groups {
                    groupGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                }
            }
            .padding(16)
        }
    }

    var body: some View {
        studioDetailWithLinkedGalleriesAndImagesSheets
    }

    /// Aufgeteilt, damit der SwiftUI-Typinferenz-Compiler nicht an `body` scheitert.
    private var studioDetailWithLinkedPerformersSheets: some View {
        studioDetailCoreChrome
            .sheet(isPresented: $linkedPerformers.showFilterSortSheet) {
                studioDetailPerformersFilterSheet
            }
            .onChange(of: linkedPerformers.catalogPresetRowSelection) { _, newId in
                linkedPerformers.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedPerformers.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedPerformers.catalogPresetNameInput)
                Button("Save") { linkedPerformers.savePresetAs(name: linkedPerformers.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedPerformers.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedPerformers.renameCatalogPresetInput)
                Button("Save") { linkedPerformers.renamePreset(to: linkedPerformers.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedPerformers.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedPerformers.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedPerformers.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var studioDetailWithLinkedTagsSheets: some View {
        studioDetailWithLinkedPerformersSheets
            .sheet(isPresented: $linkedTags.showFilterSortSheet) {
                studioDetailTagsFilterSheet
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

    private var studioDetailWithLinkedChildStudiosSheets: some View {
        studioDetailWithLinkedTagsSheets
            .sheet(isPresented: $linkedChildStudios.showFilterSortSheet) {
                studioDetailChildStudiosFilterSheet
            }
            .onChange(of: linkedChildStudios.catalogPresetRowSelection) { _, newId in
                linkedChildStudios.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save As", isPresented: $linkedChildStudios.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedChildStudios.catalogPresetNameInput)
                Button("Save") { linkedChildStudios.savePresetAs(name: linkedChildStudios.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedChildStudios.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedChildStudios.renameCatalogPresetInput)
                Button("Save") { linkedChildStudios.renamePreset(to: linkedChildStudios.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedChildStudios.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedChildStudios.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedChildStudios.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var studioDetailWithLinkedGalleriesAndImagesSheets: some View {
        studioDetailWithLinkedChildStudiosSheets
            .sheet(isPresented: $linkedGalleries.showFilterSortSheet) {
                studioDetailGalleriesFilterSheet
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
                studioDetailImagesFilterSheet
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

    @ViewBuilder
    private var studioDetailCoreChrome: some View {
        Group {
            if selectedDetailTab == .scenes {
                studioScenesStack
            } else {
                nonScenesStudioScroll
            }
        }
        .applyAppBackground()
        .onAppear {
            // If we know from the passed studio object that there are no scenes but there are galleries,
            // switch immediately so the user sees content.
            if effectiveScenesCount == 0 && effectiveGalleriesCount > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
            loadData()
            // Fetch updated studio details (like favorite status) which might be missing from list view objects
            viewModel.fetchStudio(studioId: studio.id) { updatedStudio in
                if let updated = updatedStudio {
                    self.isFavorite = updated.favorite ?? false
                } else {
                    self.isFavorite = studio.favorite ?? false
                }
            }
        }
        .onChange(of: viewModel.isLoadingStudioScenes) { oldValue, newValue in
            if !newValue && effectiveScenesCount == 0 && effectiveGalleriesCount > 0
                && !viewModel.isStudioDetailSceneListConstrained {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: effectiveGalleriesCount) { oldValue, newValue in
            if !viewModel.isLoadingStudioScenes && effectiveScenesCount == 0 && newValue > 0
                && !viewModel.isStudioDetailSceneListConstrained {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: effectiveScenesCount) { oldValue, newValue in
            if newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else if newValue == 0 && !viewModel.isLoadingStudioScenes && effectiveGalleriesCount > 0
                && !viewModel.isStudioDetailSceneListConstrained {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .sceneLiveUpdates(using: viewModel)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(studio.name)
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
        .floatingActionBar(isPresented: true, catalogChrome: studioDetailCatalogFloatingChromeForFooter) {
            HStack(spacing: 0) {
                Button {
                    guard !isUpdatingFavorite else { return }
                    HapticManager.light()
                    isUpdatingFavorite = true
                    let newState = !isFavorite
                    withAnimation(DesignTokens.Animation.quick) { isFavorite = newState }

                    viewModel.toggleStudioFavorite(studioId: studio.id, favorite: newState) { success in
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
                        studioLiveFilterSheetPresented = true
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
                } else if selectedDetailTab == .performers {
                    Button {
                        HapticManager.light()
                        linkedPerformers.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedPerformers.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedPerformers.catalogFilterSortFABActive {
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
                } else if selectedDetailTab == .studios {
                    Button {
                        HapticManager.light()
                        linkedChildStudios.showFilterSortSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(linkedChildStudios.catalogFilterSortFABActive ? appearanceManager.tintColor : .primary)
                            .overlay(alignment: .topTrailing) {
                                if linkedChildStudios.catalogFilterSortFABActive {
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
    private var studioDetailPerformersFilterSheet: some View {
        PerformersCatalogFilterSortSheet(
            serverFilters: linkedPerformers.sortedServerPerformerFilters(viewModel: viewModel),
            localPresets: linkedPerformers.localCatalogPresets,
            selectedPresetRowId: $linkedPerformers.catalogPresetRowSelection,
            liveChipRowsVisible: linkedPerformers.performerLiveChipRowsVisible,
            sortOption: linkedPerformers.selectedSortOption,
            onSortChange: { linkedPerformers.changeSortOption(to: $0, viewModel: viewModel) },
            liveAgeRange: $linkedPerformers.liveFilterAgeRange,
            liveHairColor: $linkedPerformers.liveFilterHairColor,
            liveGender: $linkedPerformers.liveFilterGender,
            liveCountry: $linkedPerformers.liveFilterCountry,
            liveImplants: $linkedPerformers.liveFilterImplants,
            liveFavorite: $linkedPerformers.liveFilterFavorite,
            liveMissingField: $linkedPerformers.liveFilterMissingField,
            liveOCounterTag: $linkedPerformers.liveFilterOCounterTag,
            onApply: { linkedPerformers.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedPerformers.catalogPresetRowSelection = ""
                linkedPerformers.selectedFilter = nil
                linkedPerformers.clearLiveChipsOnly()
                linkedPerformers.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedPerformers.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedPerformers.catalogPresetNameInput = ""
                linkedPerformers.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedPerformers.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedPerformers.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedPerformers.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedPerformers.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedPerformers.renameCatalogPresetInput = p.name
                }
                linkedPerformers.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedPerformers.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedPerformers.catalogPresetRowSelection)
            linkedPerformers.refreshLocalPresets()
            linkedPerformers.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var studioDetailTagsFilterSheet: some View {
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
    private var studioDetailChildStudiosFilterSheet: some View {
        StudiosCatalogFilterSortSheet(
            serverFilters: linkedChildStudios.sortedServerStudioFilters(viewModel: viewModel),
            localPresets: linkedChildStudios.localCatalogPresets,
            selectedPresetRowId: $linkedChildStudios.catalogPresetRowSelection,
            liveChipRowsVisible: linkedChildStudios.studioLiveChipRowsVisible,
            sortOption: linkedChildStudios.selectedSortOption,
            onSortChange: { linkedChildStudios.changeSortOption(to: $0, viewModel: viewModel) },
            liveMinRating: $linkedChildStudios.liveFilterMinRating,
            liveFavorite: $linkedChildStudios.liveFilterFavorite,
            liveScenes: $linkedChildStudios.liveFilterScenes,
            onApply: { linkedChildStudios.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedChildStudios.catalogPresetRowSelection = ""
                linkedChildStudios.selectedFilter = nil
                linkedChildStudios.clearLiveChipsOnly()
                linkedChildStudios.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedChildStudios.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedChildStudios.catalogPresetNameInput = ""
                linkedChildStudios.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedChildStudios.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedChildStudios.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedChildStudios.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedChildStudios.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedChildStudios.renameCatalogPresetInput = p.name
                }
                linkedChildStudios.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedChildStudios.showDeleteCatalogPresetAlert = true }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedChildStudios.catalogPresetRowSelection)
            linkedChildStudios.refreshLocalPresets()
            linkedChildStudios.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var studioDetailGalleriesFilterSheet: some View {
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
    private var studioDetailImagesFilterSheet: some View {
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
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(studio.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
            }
            
            // Info List
            let details = getStudioDetails(studio)
            // User wants "hide starting from 3rd line".
            // Line 1: Details 1-2
            // Line 2: Details 3-4 OR URL (if <= 2 details)
            // So we always allow up to 4 details (2 rows) visible if no URL conflict,
            // or if URL exists but we prioritize details 3-4 over URL to maximize info density?
            // User complaint: "You hide the second row [Item 3] already".
            // So we MUST show Item 3+4 if present. This takes 2 rows.
            // If 2 rows taken by details, URL (Row 3) must be hidden.
            let visibleDetails = isHeaderExpanded ? details : Array(details.prefix(4))
            let hasURL = studio.url != nil && !studio.url!.isEmpty
            
            if !visibleDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
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
            
            // URL Link (Always on its own row)
            // Show if expanded OR if we have space (details <= 2, i.e. 1 row used)
            if hasURL && (isHeaderExpanded || details.count <= 2) {
                 VStack(alignment: .leading, spacing: 2) {
                     Text("URL")
                         .font(.system(size: 8))
                         .foregroundColor(.secondary)
                         .textCase(.uppercase)
                     Link(destination: URL(string: studio.url!) ?? URL(string: "https://google.com")!) {
                         Text(studio.url!)
                             .font(.system(size: 11, weight: .bold))
                             .foregroundColor(appearanceManager.tintColor)
                             .lineLimit(1)
                     }
                 }
            }
            
            // Description (Full width if present)
            if let desc = studio.details, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.leading, 140 + 12) // Logo width + spacing
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 115, alignment: .topLeading) // Ensure minimum height for logo and top alignment
        .overlay(
            ZStack {
                Color.studioHeaderGray
                StudioImageView(studio: studio)
                    .padding(8)
            }
            .frame(width: 140)
            , alignment: .leading
        )
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .overlay(
            Group {
                let details = getStudioDetails(studio)
                let hasURL = studio.url != nil && !studio.url!.isEmpty
                
                // Button needed if:
                // 1. More details than shown (count > 4)
                // 2. URL exists but is hidden (count > 2)
                if details.count > 4 || (hasURL && details.count > 2) {
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

    private func getStudioDetails(_ s: Studio) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // Add Scenes and Galleries as the first row (matching PerformerDetailView)
        list.append((label: "SCENES", value: "\(effectiveScenesCount)"))
        
        if effectiveGalleriesCount > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleriesCount)"))
        } else {
             // Optional: Add placeholder if needed for grid alignment, but usually fine to omit
        }
        
        if let count = s.performerCount, count > 0 {
            list.append((label: "PERFORMERS", value: "\(count)"))
        }
        
        // URL is now handled separately in the view to ensure it gets its own row
        
        return list
    }

    private func miniBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
    }
    
    private func labelBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(Color.pillAccent)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.studioGalleries) { gallery in
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    GalleryCardView(gallery: gallery)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingStudioGalleries {
                loadingIndicator(message: "Loading more galleries...")
            } else if viewModel.hasMoreStudioGalleries && !viewModel.studioGalleries.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioGalleries(studioId: studio.id) }
            }
        }
    }
    
    private func loadingView(message: String) -> some View {
        VStack {
            Spacer()
            ProgressView(message)
            Spacer()
        }.frame(height: 200)
    }
    
    private func emptyView(message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title3)
                .foregroundColor(.secondary)
        }.padding(.top, 40)
    }
    
    private func loadingIndicator(message: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(message).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func loadData() {
        if viewModel.studioGalleries.isEmpty && !viewModel.isLoadingStudioGalleries {
            linkedGalleries.refetchGalleries(viewModel: viewModel, initial: true)
        }
        
        viewModel.fetchSavedFilters()
        linkedPerformers.refetchPerformers(viewModel: viewModel, initial: true)
        linkedTags.refetchTags(viewModel: viewModel, initial: true)
        linkedChildStudios.refetchStudios(viewModel: viewModel, initial: true)
        viewModel.fetchDetailGroups(studioId: studio.id)
        if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
            linkedImages.refetchImages(viewModel: viewModel, initial: true)
        }
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailStudios) { subStudio in
                NavigationLink(destination: StudioDetailView(studio: subStudio)) {
                    StudioCardView(studio: subStudio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { linkedChildStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
        }
    }
    
    private var performerGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailPerformers) { performer in
                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                    PerformerCardView(performer: performer)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailPerformers {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more performers...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
            } else if viewModel.hasMoreDetailPerformers {
                Color.clear.frame(height: 1).onAppear {
                    linkedPerformers.refetchPerformers(viewModel: viewModel, initial: false)
                }
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
            else if viewModel.hasMoreDetailTags {
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
            else if viewModel.hasMoreDetailGroups {
                Color.clear.onAppear { viewModel.fetchDetailGroups(studioId: studio.id, isInitialLoad: false) }
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
            else if viewModel.hasMoreDetailImages {
                Color.clear.onAppear { linkedImages.refetchImages(viewModel: viewModel, initial: false) }
            }
        }
    }
}

#Preview {
    let sampleStudio = Studio(
        id: "1",
        name: "Sample Studio",
        url: "https://samplestudio.com",
        sceneCount: 25,
        performerCount: 5,
        galleryCount: 10,
        details: "This is a sample studio description that might span multiple lines.",
        imagePath: nil,
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil
    )
    StudioDetailView(studio: sampleStudio)
}
#endif
