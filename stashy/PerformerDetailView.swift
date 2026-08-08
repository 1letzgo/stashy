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
    @Environment(\.dismiss) private var dismiss
    @State private var isHeaderExpanded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var fullPerformer: Performer?
    @State private var performerLiveFilterSheetPresented = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    /// Verhindert mehrfaches `loadData()` bei wiederholtem SwiftUI-`onAppear` (leere Performer → identische Refetch-Schleife).
    @State private var hasRunPerformerDetailInitialLoad = false
    @State private var hotOrNotBattleLine: String?
    @State private var showingEditPerformerSheet = false
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    /// Images 1/row autoplay: parent ScrollView drag/decelerate.
    @State private var imagesFeedScrolling = false

    private var showsFeedsNavButton: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            case .images: return "photo"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

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
        ScenesView(
            hideTitle: true,
            scope: .performer(performerId: performer.id),
            sharedViewModel: viewModel,
            externalLiveFilterSheetBinding: $performerLiveFilterSheetPresented,
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(
                headerView(displayPerformer: displayPerformer, battleLine: hotOrNotBattleLine)
                    .padding(.horizontal, 16)
            )
        )
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
                            InlineSpinner()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        InlineEmptyStateView(icon: "photo.on.rectangle", title: "No galleries found")
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
                    InlineEmptyStateView(icon: "film", title: "No scenes found")
                }
            }
            .padding(16)
        }
        .onScrollPhaseChange { _, newPhase in
            // Only track while Images is visible — avoids extra work on other tabs.
            guard selectedDetailTab == .images else {
                if imagesFeedScrolling { imagesFeedScrolling = false }
                return
            }
            imagesFeedScrolling = newPhase != .idle
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

    /// Extra gap between section icons ↔ favorite/edit actions.
    private var navActionGroupSpacing: CGFloat { 7 }

    /// Custom top chrome: Back · section icons · Favorite · Edit (edit mode). Feeds lives in the header.
    @ViewBuilder
    private var performerDetailNavBar: some View {
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

                if showTabSwitcher {
                    HStack(spacing: 6) {
                        ForEach(availableTabs, id: \.self) { tab in
                            let isSelected = selectedDetailTab == tab
                            Button {
                                guard !isSelected else { return }
                                HapticManager.light()
                                withAnimation(StashyExpandingDock.selectionAnimation) {
                                    selectedDetailTab = tab
                                }
                            } label: {
                                Image(systemName: tab.icon)
                                    .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                                    .foregroundColor(
                                        isSelected
                                            ? .white
                                            : .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                                    )
                                    .frame(
                                        width: StashyExpandingDock.circleSize,
                                        height: StashyExpandingDock.circleSize
                                    )
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? appearanceManager.tintColor
                                                    : StashyExpandingDock.inactiveBackground
                                            )
                                    }
                                    .clipShape(Capsule(style: .continuous))
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tab.rawValue)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }

                if showTabSwitcher {
                    Spacer()
                        .frame(width: navActionGroupSpacing)
                }

                HStack(spacing: 6) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                            .foregroundColor(
                                isFavorite
                                    ? .red
                                    : .white.opacity(StashyExpandingDock.inactiveIconOpacity)
                            )
                            .frame(
                                width: StashyExpandingDock.circleSize,
                                height: StashyExpandingDock.circleSize
                            )
                            .background(StashyExpandingDock.inactiveBackground)
                            .clipShape(Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingFavorite)
                    .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")

                    if appearanceManager.isEditModeEnabled {
                        Button {
                            HapticManager.light()
                            showingEditPerformerSheet = true
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
                        .accessibilityLabel("Edit performer")
                    }
                }
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)

        }
    }

    private func toggleFavorite() {
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
        .hideSystemNavigationBarForCustomChrome()
        .enableSwipeBackWhenNavBarHidden()
        .stashyCustomChromeInset(spacing: 0) {
            performerDetailNavBar
        }
        .sheet(isPresented: $showingEditPerformerSheet) {
            EditPerformerSheet(performer: displayPerformer, viewModel: viewModel) { updated in
                applyEditedPerformer(updated)
            }
        }
        .floatingActionBar(isPresented: true, catalogChrome: performerDetailCatalogFloatingChromeForFooter) {
            HStack(spacing: 0) {
                if selectedDetailTab == .scenes {
                    CatalogFilterFABButton(isActive: true) {
                        HapticManager.light()
                        performerLiveFilterSheetPresented = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    CatalogFilterFABButton(isActive: linkedGalleries.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedGalleries.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .studios {
                    CatalogFilterFABButton(isActive: linkedStudios.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedStudios.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .tags {
                    CatalogFilterFABButton(isActive: linkedTags.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedTags.showFilterSortSheet = true
                    }
                    .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    let cardColumns = tabManager.catalogCardColumns(for: CatalogCardColumnScope.images)
                    CatalogFABIconButton(
                        systemImage: cardColumns.toggleIcon,
                        accessibilityLabel: cardColumns.accessibilityLabel,
                        accessibilityHint: "Switches between one and two cards per row"
                    ) {
                        withAnimation(DesignTokens.Animation.quick) {
                            tabManager.toggleCatalogCardColumns(for: CatalogCardColumnScope.images)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    CatalogFilterFABButton(isActive: linkedImages.catalogFilterSortFABActive) {
                        HapticManager.light()
                        linkedImages.showFilterSortSheet = true
                    }
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
            onRequestDelete: { linkedImages.showDeleteCatalogPresetAlert = true },
            showsImagesFeedAutoplaySetting: true
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            linkedImages.prepareCatalogFilterSortSheetUI(viewModel: viewModel)
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
        LinkedImagesCatalogGrid(
            images: $viewModel.detailImages,
            sortOption: linkedImages.selectedSortOption,
            isLoading: viewModel.isLoadingDetailImages,
            hasMore: viewModel.hasMoreDetailImages,
            onLoadMore: { linkedImages.refetchImages(viewModel: viewModel, initial: false) },
            multiColumnGridItems: galleryColumns,
            isFeedScrolling: imagesFeedScrolling
        )
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
                                .overlay(InlineSpinner(scale: .compact))
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
                // Header: Name and Feeds
                HStack(alignment: .top, spacing: 8) {
                    Text(displayPerformer.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)

                    Spacer()

                    if showsFeedsNavButton {
                        Button(action: {
                            let sp = ScenePerformer(
                                id: displayPerformer.id,
                                name: displayPerformer.name,
                                birthdate: displayPerformer.birthdate,
                                sceneCount: displayPerformer.sceneCount,
                                galleryCount: displayPerformer.galleryCount,
                                oCounter: displayPerformer.oCounter,
                                updatedAt: nil
                            )
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

    private func applyEditedPerformer(_ updated: Performer) {
        performer = updated
        if fullPerformer != nil {
            fullPerformer = updated
        }
    }
}

// MARK: - Edit Performer Sheet

struct EditPerformerSheet: View {
    let performer: Performer
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (Performer) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var name: String = ""
    @State private var disambiguation: String = ""
    @State private var birthdate: String = ""
    @State private var country: String = ""
    @State private var gender: String = ""
    @State private var ethnicity: String = ""
    @State private var heightText: String = ""
    @State private var weightText: String = ""
    @State private var measurements: String = ""
    @State private var fakeTits: String = ""
    @State private var penisLengthText: String = ""
    @State private var careerLength: String = ""
    @State private var tattoos: String = ""
    @State private var piercings: String = ""
    @State private var aliasesText: String = ""
    @State private var ratingText: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Disambiguation", text: $disambiguation)
                    TextField("Aliases (comma-separated)", text: $aliasesText)
                    TextField("Gender", text: $gender)
                    TextField("Birthdate (YYYY-MM-DD)", text: $birthdate)
                    TextField("Country", text: $country)
                    TextField("Ethnicity", text: $ethnicity)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Body") {
                    TextField("Height (cm)", text: $heightText)
                        .keyboardType(.numberPad)
                    TextField("Weight (kg)", text: $weightText)
                        .keyboardType(.numberPad)
                    TextField("Measurements", text: $measurements)
                    TextField("Fake tits", text: $fakeTits)
                    TextField("Penis length (cm)", text: $penisLengthText)
                        .keyboardType(.decimalPad)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Other") {
                    TextField("Career length", text: $careerLength)
                    TextField("Tattoos", text: $tattoos)
                    TextField("Piercings", text: $piercings)
                    TextField("Rating (0–100)", text: $ratingText)
                        .keyboardType(.numberPad)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .navigationTitle("Edit Performer")
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .tint(appearanceManager.tintColor)
                }
            }
            .onAppear { hydrate() }
        }
    }

    private func hydrate() {
        name = performer.name
        disambiguation = performer.disambiguation ?? ""
        birthdate = performer.birthdate ?? ""
        country = performer.country ?? ""
        gender = performer.gender ?? ""
        ethnicity = performer.ethnicity ?? ""
        heightText = performer.height.map(String.init) ?? ""
        weightText = performer.weight.map(String.init) ?? ""
        measurements = performer.measurements ?? ""
        fakeTits = performer.fakeTits ?? ""
        penisLengthText = performer.penis_length.map { String($0) } ?? ""
        careerLength = performer.careerLength ?? ""
        tattoos = performer.tattoos ?? ""
        piercings = performer.piercings ?? ""
        aliasesText = (performer.aliasList ?? []).joined(separator: ", ")
        ratingText = performer.rating100.map(String.init) ?? ""
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let height = Int(heightText.trimmingCharacters(in: .whitespacesAndNewlines))
        let weight = Int(weightText.trimmingCharacters(in: .whitespacesAndNewlines))
        let penisLength = Double(penisLengthText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        let rating = Int(ratingText.trimmingCharacters(in: .whitespacesAndNewlines)).map { min(100, max(0, $0)) }

        isSaving = true
        viewModel.updatePerformerDetails(
            performerId: performer.id,
            name: trimmedName,
            disambiguation: optionalTrimmed(disambiguation),
            birthdate: optionalTrimmed(birthdate),
            country: optionalTrimmed(country),
            gender: optionalTrimmed(gender),
            ethnicity: optionalTrimmed(ethnicity),
            height: height,
            weight: weight,
            measurements: optionalTrimmed(measurements),
            fakeTits: optionalTrimmed(fakeTits),
            penisLength: penisLength,
            careerLength: optionalTrimmed(careerLength),
            tattoos: optionalTrimmed(tattoos),
            piercings: optionalTrimmed(piercings),
            aliasList: aliases.isEmpty ? nil : aliases,
            rating100: rating
        ) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    var updated = performer
                    updated.name = trimmedName
                    updated.disambiguation = optionalTrimmed(disambiguation)
                    updated.birthdate = optionalTrimmed(birthdate)
                    updated.country = optionalTrimmed(country)
                    updated.gender = optionalTrimmed(gender)
                    updated.ethnicity = optionalTrimmed(ethnicity)
                    updated.height = height
                    updated.weight = weight
                    updated.measurements = optionalTrimmed(measurements)
                    updated.fakeTits = optionalTrimmed(fakeTits)
                    updated.penis_length = penisLength
                    updated.careerLength = optionalTrimmed(careerLength)
                    updated.tattoos = optionalTrimmed(tattoos)
                    updated.piercings = optionalTrimmed(piercings)
                    updated.aliasList = aliases.isEmpty ? nil : aliases
                    updated.rating100 = rating
                    onComplete(updated)
                    ToastManager.shared.show("Performer updated", icon: "checkmark.circle", style: .success)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update performer", icon: "exclamationmark.triangle", style: .error)
                }
            }
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
