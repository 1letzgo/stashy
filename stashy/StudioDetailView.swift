//
//  StudioDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct StudioDetailView: View {
    /// The fold of an open iPhone Duo, when it runs top to bottom through this view.
    @State private var detailFold: FoldRegion?
    @State private var studio: Studio
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.stashyDismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var studioLiveFilterSheetPresented = false
    @State private var showingSceneDownloadOptions = false
    @State private var studioSceneFilterActive = false
    @StateObject private var linkedPerformers: DetailLinkedPerformersFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedChildStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    /// Scenes tab filter / sort, kept here so it survives the tab remounting `ScenesView`.
    @StateObject private var scenesFilterMemory: ScenesListFilterMemory
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false
    /// The studio logo opened full screen.
    @State private var showingLogoFullscreen = false
    @State private var showingEditStudioSheet = false

    private var showsFeedsNavButton: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case performers = "Performers"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"

        /// The name on screen; the raw value is data.
        var title: String {
            switch self {
            case .scenes: return tr("scenes")
            case .galleries: return tr("galleries")
            case .studios: return tr("studios")
            case .performers: return tr("performers")
            case .tags: return tr("tags")
            case .groups: return tr("groups")
            case .images: return tr("images")
            }
        }

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .studios: return "building.2"
            case .performers: return "person.fill"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            case .images: return "photo"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab

    /// `filterPerformerId`: opened from that performer's page — its scenes, galleries and images
    /// start filtered on the performer.
    @ObservedObject private var studioCounts = StudioCountsStore.shared
    @AppStorage(StudioCountsStore.includeSubStudiosKey) private var includeSubStudios = false

    init(studio: Studio, filterPerformerId: String? = nil) {
        _studio = State(initialValue: studio)
        let sc = studio.sceneCount
        let gal = studio.galleryCount ?? 0
        _selectedDetailTab = State(initialValue: sc > 0 ? .scenes : (gal > 0 ? .galleries : .scenes))
        _linkedPerformers = StateObject(wrappedValue: DetailLinkedPerformersFilterModel(scope: .studio(studio.id), initialSort: .nameAsc))
        _linkedTags = StateObject(wrappedValue: DetailLinkedTagsFilterModel(scope: .studio(studio.id)))
        _linkedChildStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .parentStudio(studio.id)))
        let galleries = DetailLinkedGalleriesFilterModel(scope: .studio(studio.id))
        let images = DetailLinkedImagesFilterModel(scope: .studio(studio.id))
        if let filterPerformerId {
            galleries.criteriaDocument.load(PerformerScopedDetail.criteria(performerId: filterPerformerId))
            images.criteriaDocument.load(PerformerScopedDetail.criteria(performerId: filterPerformerId))
        }
        _linkedGalleries = StateObject(wrappedValue: galleries)
        _linkedImages = StateObject(wrappedValue: images)
        _scenesFilterMemory = StateObject(wrappedValue: PerformerScopedDetail.scenesMemory(performerId: filterPerformerId))
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

    @State private var galleryGridWidth: CGFloat = 0

    private var galleryColumns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: galleryGridWidth,
            ideal: DesignTokens.Grid.idealPosterCardWidth,
            minimum: 2,
            maximum: 8
        )
    }

    @ViewBuilder
    private var studioScenesStack: some View {
        ScenesView(
            hideTitle: true,
            scope: .studio(studioId: studio.id),
            sharedViewModel: viewModel,
            externalLiveFilterSheetBinding: $studioLiveFilterSheetPresented,
            externalLiveFilterActiveBinding: $studioSceneFilterActive,
            showsFloatingFilterButton: false,
            // Open iPhone Duo: the header has its own column left of the fold.
            scrollHeader: detailFold == nil
                ? AnyView(headerCard.padding(.horizontal, 16))
                : AnyView(EmptyView()),
            filterMemory: scenesFilterMemory
        )
        .environment(\.detailBreadcrumb, detailCrumb)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Back · section dropdown, like the overviews' breadcrumb (PerformerDetail template).
    private var detailCrumb: DetailBreadcrumb {
        DetailBreadcrumb(
            sections: availableTabs.map { .init(id: $0.rawValue, title: $0.title, systemImage: $0.icon) },
            selectionID: selectedDetailTab.rawValue,
            onSelect: { id in
                if let tab = DetailTab(rawValue: id) { selectedDetailTab = tab }
            },
            onBack: { dismiss() }
        )
    }

    /// Top chrome. The Scenes list draws this row itself (`detailBreadcrumbChrome`); every
    /// other section gets it here with its sort menu and settings.
    @ViewBuilder
    private var studioDetailNavBar: some View {
        if selectedDetailTab != .scenes {
            StashySectionChromeBar {
                DetailBreadcrumbRow(crumb: detailCrumb) { sectionControls }
                    .padding(.horizontal, StashyExpandingDock.edgePadding)
                    .padding(.vertical, 6)
            }
        }
    }

    /// Sort menu and filter / sort settings of the shown section.
    @ViewBuilder
    private var sectionControls: some View {
        HStack(spacing: 6) {
            switch selectedDetailTab {
            case .galleries:
                CatalogQuickSortMenu(mode: .galleries, sort: linkedGalleries.selectedSortOption) {
                    linkedGalleries.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .images:
                CatalogQuickSortMenu(mode: .images, sort: linkedImages.selectedSortOption) {
                    linkedImages.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .studios:
                CatalogQuickSortMenu(mode: .studios, sort: linkedChildStudios.selectedSortOption) {
                    linkedChildStudios.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .performers:
                CatalogQuickSortMenu(mode: .performers, sort: linkedPerformers.selectedSortOption) {
                    linkedPerformers.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .tags:
                CatalogQuickSortMenu(mode: .tags, sort: linkedTags.selectedSortOption) {
                    linkedTags.changeSortOption(to: $0, viewModel: viewModel)
                }
            case .scenes, .groups:
                EmptyView()
            }
            if let filter = sectionFilterSlot {
                DetailTopBarSlotButton(slot: filter)
            }
        }
    }

    /// The shown section's filter and sort sheet (Groups has none yet).
    private var sectionFilterSlot: CatalogChromeSlot? {
        func slot(active: Bool, open: @escaping () -> Void) -> CatalogChromeSlot {
            CatalogChromeSlot(systemImage: "slider.horizontal.3", isActive: active, accessibilityLabel: tr("action_filter_and_sort_2")) {
                HapticManager.light()
                open()
            }
        }
        switch selectedDetailTab {
        case .scenes: return slot(active: studioSceneFilterActive) { studioLiveFilterSheetPresented = true }
        case .galleries: return slot(active: linkedGalleries.catalogFilterSortFABActive) { linkedGalleries.showFilterSortSheet = true }
        case .performers: return slot(active: linkedPerformers.catalogFilterSortFABActive) { linkedPerformers.showFilterSortSheet = true }
        case .tags: return slot(active: linkedTags.catalogFilterSortFABActive) { linkedTags.showFilterSortSheet = true }
        case .studios: return slot(active: linkedChildStudios.catalogFilterSortFABActive) { linkedChildStudios.showFilterSortSheet = true }
        case .images: return slot(active: linkedImages.catalogFilterSortFABActive) { linkedImages.showFilterSortSheet = true }
        case .groups: return nil
        }
    }

    private func toggleFavorite() {
        guard !isUpdatingFavorite else { return }
        HapticManager.light()
        isUpdatingFavorite = true
        let newState = !isFavorite
        withAnimation(DesignTokens.Animation.quick) { isFavorite = newState }

        viewModel.toggleStudioFavorite(studioId: studio.id, favorite: newState) { success in
            DispatchQueue.main.async {
                if !success {
                    isFavorite = !newState
                    ToastManager.shared.show(tr("error_update_favorite"), icon: "exclamationmark.triangle", style: .error)
                } else {
                    studio.favorite = newState
                }
                isUpdatingFavorite = false
            }
        }
    }

    @ViewBuilder
    private var nonScenesStudioScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                if detailFold == nil {
                    headerCard
                }

                if selectedDetailTab == .galleries {
                    if !viewModel.studioGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingStudioGalleries {
                        loadingView(message: tr("loading_galleries"))
                    } else {
                        InlineEmptyStateView(icon: "photo.on.rectangle", title: tr("empty_galleries_found"))
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
            .alert(tr("action_save_as_new"), isPresented: $linkedPerformers.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedPerformers.catalogPresetNameInput)
                Button(tr("action_save")) { linkedPerformers.savePresetAs(name: linkedPerformers.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedPerformers.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedPerformers.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedPerformers.renamePreset(to: linkedPerformers.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedPerformers.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedPerformers.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
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
            .alert(tr("action_save_as_new"), isPresented: $linkedTags.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedTags.catalogPresetNameInput)
                Button(tr("action_save")) { linkedTags.savePresetAs(name: linkedTags.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedTags.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedTags.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedTags.renamePreset(to: linkedTags.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedTags.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedTags.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
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
            .alert(tr("action_save_as_new"), isPresented: $linkedChildStudios.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedChildStudios.catalogPresetNameInput)
                Button(tr("action_save")) { linkedChildStudios.savePresetAs(name: linkedChildStudios.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedChildStudios.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedChildStudios.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedChildStudios.renamePreset(to: linkedChildStudios.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedChildStudios.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedChildStudios.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
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
            .alert(tr("action_save_as_new"), isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedGalleries.catalogPresetNameInput)
                Button(tr("action_save")) { linkedGalleries.savePresetAs(name: linkedGalleries.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedGalleries.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedGalleries.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedGalleries.renamePreset(to: linkedGalleries.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedGalleries.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedGalleries.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(linkedGalleries.deletePresetConfirmationText(viewModel: viewModel))
            }
            .sheet(isPresented: $linkedImages.showFilterSortSheet) {
                studioDetailImagesFilterSheet
            }
            .onChange(of: linkedImages.catalogPresetRowSelection) { _, newId in
                linkedImages.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert(tr("action_save_as_new"), isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedImages.catalogPresetNameInput)
                Button(tr("action_save")) { linkedImages.savePresetAs(name: linkedImages.catalogPresetNameInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_save_current_sort_filter_and"))
            }
            .alert(tr("action_rename"), isPresented: $linkedImages.showRenameCatalogPresetAlert) {
                TextField(tr("name"), text: $linkedImages.renameCatalogPresetInput)
                Button(tr("action_save")) { linkedImages.renamePreset(to: linkedImages.renameCatalogPresetInput, viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(tr("hint_rename_this_preset_or_saved"))
            }
            .alert(tr("confirm_delete_filter"), isPresented: $linkedImages.showDeleteCatalogPresetAlert) {
                Button(tr("action_delete"), role: .destructive) { linkedImages.deletePreset(viewModel: viewModel) }
                Button(tr("action_cancel"), role: .cancel) {}
            } message: {
                Text(linkedImages.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    @ViewBuilder
    private var studioTabContent: some View {
        if selectedDetailTab == .scenes {
            studioScenesStack
        } else {
            nonScenesStudioScroll
        }
    }

    @ViewBuilder
    private var studioDetailCoreChrome: some View {
        Group {
            if let fold = detailFold {
                HStack(spacing: fold.frame.width) {
                    ScrollView {
                        headerCard.padding(16)
                    }
                    .frame(width: max(0, fold.frame.minX))
                    studioTabContent
                }
            } else {
                studioTabContent
            }
        }
        .onGeometryChange(for: FoldRegion?.self) { proxy in
            proxy.foldRegion.flatMap { $0.isVertical ? $0 : nil }
        } action: { detailFold = $0 }
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
                    self.studio = updated
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
        .task(id: studio.id) { studioCounts.request(studio.id, refresh: true) }
        .sceneBulkDownloadDialog(
            isPresented: $showingSceneDownloadOptions,
            scope: .studio(id: studio.id),
            scopeName: studio.name,
            sceneCount: studio.sceneCount,
        )
        .stashyDetailChrome(studioDetailChromeConfig) {
            studioDetailNavBar
        }
        .sheet(isPresented: $showingEditStudioSheet) {
            EditStudioSheet(studio: studio, viewModel: viewModel, onDeleted: { dismiss() }) { updated in
                studio = updated
            }
        }
    }

    // MARK: - Shared detail chrome

    /// Favorite and Edit sit in the floating bar with the list's actions, not in the top chrome.
    private var entityActionSlots: [CatalogChromeSlot] {
        var actions = [CatalogChromeSlot(
            systemImage: isFavorite ? "heart.fill" : "heart",
            accessibilityLabel: isFavorite ? tr("action_remove_favorite") : tr("action_add_favorite"),
            tint: isFavorite ? .red : nil
        ) {
            guard !isUpdatingFavorite else { return }
            toggleFavorite()
        }]
        if appearanceManager.isEditModeEnabled {
            actions.append(CatalogChromeSlot(systemImage: "pencil", accessibilityLabel: tr("action_edit_studio")) {
                HapticManager.light()
                showingEditStudioSheet = true
            })
        }
        return actions
    }

    /// Per-tab slots for the embedded list, mirroring the previous floating action bar content.
    private var studioDetailListSlots: CatalogSlotSet {
        var slots = CatalogSlotSet(visibility: studioDetailCatalogFloatingChromeForFooter)
        slots.entityActions = entityActionSlots
        // Filter & sort live in the top bar now (breadcrumb row); the bar keeps the actions.
        if selectedDetailTab == .scenes {
            slots.contextual = SceneBulkDownloadChrome.slot {
                showingSceneDownloadOptions = true
            }
        }
        return slots
    }

    private var studioDetailChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(listSlots: studioDetailListSlots, insetSpacing: 0)
    }

    @ViewBuilder
    private var studioDetailPerformersFilterSheet: some View {
        PerformersCatalogFilterSortSheet(
            serverFilters: linkedPerformers.sortedServerPerformerFilters(viewModel: viewModel),
            localPresets: linkedPerformers.localCatalogPresets,
            selectedPresetRowId: $linkedPerformers.catalogPresetRowSelection,
            criteriaDocument: linkedPerformers.criteriaDocument,
            sortOption: linkedPerformers.selectedSortOption,
            onSortChange: { linkedPerformers.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedPerformers.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedPerformers.catalogPresetRowSelection = ""
                linkedPerformers.selectedFilter = nil
                linkedPerformers.clearLiveChipsOnly()
                linkedPerformers.criteriaDocument.clear()
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
            criteriaDocument: linkedTags.criteriaDocument,
            sortOption: linkedTags.selectedSortOption,
            onSortChange: { linkedTags.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedTags.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedTags.catalogPresetRowSelection = ""
                linkedTags.selectedFilter = nil
                linkedTags.clearLiveChipsOnly()
                linkedTags.criteriaDocument.clear()
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
            criteriaDocument: linkedChildStudios.criteriaDocument,
            sortOption: linkedChildStudios.selectedSortOption,
            onSortChange: { linkedChildStudios.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedChildStudios.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedChildStudios.catalogPresetRowSelection = ""
                linkedChildStudios.selectedFilter = nil
                linkedChildStudios.clearLiveChipsOnly()
                linkedChildStudios.criteriaDocument.clear()
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
            criteriaDocument: linkedGalleries.criteriaDocument,
            sortOption: linkedGalleries.selectedSortOption,
            onSortChange: { linkedGalleries.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedGalleries.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedGalleries.catalogPresetRowSelection = ""
                linkedGalleries.selectedFilter = nil
                linkedGalleries.clearLiveChipsOnly()
                linkedGalleries.criteriaDocument.clear()
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
            criteriaDocument: linkedImages.criteriaDocument,
            filterMenuTitleFallback: linkedImages.selectedFilter?.name,
            showMediaTypeFilter: linkedImages.showImageMediaTypeFilter,
            sortOption: linkedImages.selectedSortOption,
            onSortChange: { linkedImages.changeSortOption(to: $0, viewModel: viewModel) },
            liveMediaKind: $linkedImages.liveFilterMediaKind,
            onApply: { linkedImages.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedImages.catalogPresetRowSelection = ""
                linkedImages.selectedFilter = nil
                linkedImages.clearLiveChipsOnly()
                linkedImages.criteriaDocument.clear()
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
            onRequestDelete: { linkedImages.showDeleteCatalogPresetAlert = true },
            cardColumnScope: CatalogCardColumnScope.images
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            linkedImages.prepareCatalogFilterSortSheetUI(viewModel: viewModel)
        }
    }
    
    // MARK: - Subviews

    /// Stash serves a generic placeholder (`…&default=true`) for studios without a logo;
    /// those get the plain card instead of a hero.
    private var studioHasCustomImage: Bool {
        guard let path = studio.imagePath, !path.isEmpty else { return false }
        return !path.contains("default=true")
    }

    /// Header card (`DetailHeroCard`). The studio image is a logo, so it is never cropped:
    /// aspect-fit with padding inside the avatar circle on the studio-logo backdrop, with a
    /// blurred, tinted copy as the band backdrop. Logos come from `StudioLogoStore` via
    /// `StudioImageView`. Favorite / Edit live in the nav bar.
    private var headerCard: some View {
        let url = (studio.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let linkURL = url.isEmpty ? nil : URL(string: url)
        return DetailHeroCard(
            title: studio.name,
            items: getStudioDetails(studio).map { DetailHeroItem(label: $0.label, value: $0.value) },
            description: studio.details,
            showsHero: studioHasCustomImage,
            heroAccessibilityLabel: tr("studio_logo"),
            onHeroTap: { showingLogoFullscreen = true },
            isExpanded: $isHeaderExpanded,
            placeholderSystemImage: AppTab.studios.icon,
            backdrop: {
                ZStack {
                    Color.studioHeaderGray(for: appearanceManager.currentTheme)
                    StudioImageView(studio: studio)
                    appearanceManager.tintColor.opacity(0.18)
                }
            },
            avatar: {
                // Logo: aspect-fit on the logo backdrop, never cropped by the circle.
                ZStack {
                    Color.studioHeaderGray(for: appearanceManager.currentTheme)
                    StudioImageView(studio: studio)
                        .padding(14)
                }
            },
            accessory: { onImage in
                if showsFeedsNavButton {
                    DetailHeroFeedsButton(onImage: onImage) {
                        let sceneStudio = SceneStudio(
                            id: studio.id,
                            name: studio.name,
                            updatedAt: studio.updatedAt
                        )
                        coordinator.navigateToReels(studio: sceneStudio, mode: nil)
                    }
                }
            },
            footer: {
                if let linkURL {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("URL")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Link(destination: linkURL) {
                            Text(url)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, (studio.details ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 10 : 6)
                    .padding(.trailing, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
        .fullScreenCover(isPresented: $showingLogoFullscreen) {
            // A logo, so fitted on the logo grey rather than cropped.
            DetailHeroFullscreenViewer {
                StudioImageView(studio: studio)
                    .padding(24)
            }
        }
    }

    private func getStudioDetails(_ s: Studio) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // Add Scenes and Galleries as the first row (matching PerformerDetailView)
        let counts = studioCounts.display(for: s, includeSubStudios: includeSubStudios)
        list.append((label: "SCENES", value: "\(includeSubStudios ? counts.scenes : effectiveScenesCount)"))
        
        let galleries = includeSubStudios ? (counts.galleries ?? 0) : effectiveGalleriesCount
        if galleries > 0 {
            list.append((label: "GALLERIES", value: "\(galleries)"))
        } else {
             // Optional: Add placeholder if needed for grid alignment, but usually fine to omit
        }
        
        if let count = counts.performers, count > 0 {
            list.append((label: "PERFORMERS", value: "\(count)"))
        }

        if let oCount = counts.oCount, oCount > 0 {
            list.append((label: tr("o_count").uppercased(), value: "\(oCount)"))
        }

        if let rating = s.rating100 {
            list.append((label: "RATING", value: "\(rating)%"))
        }

        // URL renders as its own tappable row under the hero (footer).

        return list
    }

    private func miniBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .stashyGlass(shape: Capsule())
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
                loadingIndicator(message: tr("loading_more_galleries"))
            } else if viewModel.hasMoreStudioGalleries && !viewModel.studioGalleries.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioGalleries(studioId: studio.id) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
    }
    
    private func loadingView(message: String) -> some View {
        VStack {
            Spacer()
            InlineSpinner(label: message)
            Spacer()
        }
        .frame(height: 200)
    }

    private func loadingIndicator(message: String) -> some View {
        PaginationLoadingFooter(message: message)
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
                    StudioCardView(studio: subStudio, badge: CatalogCardBadge(sortField: linkedChildStudios.selectedSortOption.sortField))
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { linkedChildStudios.refetchStudios(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
    }
    
    private var performerGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailPerformers) { performer in
                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                    PerformerCardView(performer: performer, badgeType: .forSort(linkedPerformers.selectedSortOption))
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailPerformers {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(tr("loading_more_performers")).font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
            } else if viewModel.hasMoreDetailPerformers {
                Color.clear.frame(height: 1).onAppear {
                    linkedPerformers.refetchPerformers(viewModel: viewModel, initial: false)
                }
            }
        }
        .measuresGridWidth($galleryGridWidth)
    }
    
    private var tagGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailTags) { tag in
                NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                    TagCardView(tag: tag, badge: CatalogCardBadge(sortField: linkedTags.selectedSortOption.sortField))
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailTags { ProgressView().padding() }
            else if viewModel.hasMoreDetailTags {
                Color.clear.onAppear { linkedTags.refetchTags(viewModel: viewModel, initial: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
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
        .measuresGridWidth($galleryGridWidth)
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
        .measuresGridWidth($galleryGridWidth)
    }
}

// MARK: - Edit Studio Sheet

struct EditStudioSheet: View {
    let studio: Studio
    @ObservedObject var viewModel: StashDBViewModel
    var onDeleted: (() -> Void)? = nil
    var onComplete: (Studio) -> Void

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var details: String = ""
    @State private var ratingText: String = ""
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section(tr("identity")) {
                    TextField(tr("name"), text: $name)
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField(tr("rating_0_100"), text: $ratingText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(tr("description")) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                InlineSpinner(tint: .red)
                            } else {
                                Label(tr("action_delete_studio"), systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving || isDeleting)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("action_edit_studio"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: tr("action_save"),
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear {
                name = studio.name
                url = studio.url ?? ""
                details = studio.details ?? ""
                ratingText = studio.rating100.map(String.init) ?? ""
            }
            .alert(tr("action_delete_studio"), isPresented: $showingDeleteConfirmation) {
                Button(tr("action_cancel"), role: .cancel) { }
                Button(tr("action_delete"), role: .destructive) { performDelete() }
            } message: {
                Text(tr("hint_delete_arg_this_cannot_be", studio.name))
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        viewModel.deleteStudio(studioId: studio.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    ToastManager.shared.show(tr("studio_deleted"), icon: "trash", style: .success)
                    dismiss()
                    // Pop the detail only once the sheet is gone — both in one runloop
                    // leaves the navigation stack inconsistent.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onDeleted?() }
                case .failure(let error):
                    ToastManager.shared.show(error.localizedDescription, icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let rating = Int(ratingText.trimmingCharacters(in: .whitespacesAndNewlines)).map { min(100, max(0, $0)) }

        isSaving = true
        viewModel.updateStudioDetails(
            studioId: studio.id,
            name: trimmedName,
            url: optionalTrimmed(url),
            details: optionalTrimmed(details),
            rating100: rating
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = studio
                    updated.name = trimmedName
                    updated.url = optionalTrimmed(url)
                    updated.details = optionalTrimmed(details)
                    updated.rating100 = rating
                    onComplete(updated)
                    ToastManager.shared.show(tr("studio_updated"), icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show(tr("error_update_studio"), icon: "exclamationmark.triangle", style: .error)
                }
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
        details: tr("hint_this_is_sample_studio_description"),
        imagePath: nil,
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil
    )
    StudioDetailView(studio: sampleStudio)
}
#endif
