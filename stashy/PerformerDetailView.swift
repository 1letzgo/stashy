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
    @State private var showingSceneDownloadOptions = false
    @State private var performerSceneFilterActive = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    /// Verhindert mehrfaches `loadData()` bei wiederholtem SwiftUI-`onAppear` (leere Performer → identische Refetch-Schleife).
    @State private var hasRunPerformerDetailInitialLoad = false
    @State private var hotOrNotBattleLine: String?
    @State private var showingEditPerformerSheet = false
    /// UIKit pop when `dismiss()` is a no-op under custom chrome (Feeds → Clips/Pics).
    @State private var navigationBackTrigger: UUID?
    @StateObject private var linkedStudios: DetailLinkedStudiosFilterModel
    @StateObject private var linkedTags: DetailLinkedTagsFilterModel
    @StateObject private var linkedGalleries: DetailLinkedGalleriesFilterModel
    /// Scenes tab filter / sort, kept here so it survives the tab remounting `ScenesView`.
    @StateObject private var scenesFilterMemory = ScenesListFilterMemory()
    @StateObject private var linkedImages: DetailLinkedImagesFilterModel
    /// "Appears with" filter / sort — own scope, not shared with the other tabs or the catalog.
    @StateObject private var linkedCoPerformers: DetailLinkedPerformersFilterModel
    /// Images 1/row autoplay: parent ScrollView drag/decelerate.
    @State private var imagesFeedScrolling = false
    /// "Appears with": co-performers sorted by shared scenes; `nil` until loaded (session cache in `CoPerformerCache`).
    @State private var coPerformers: [CoPerformer]?
    @State private var isLoadingCoPerformers = false
    @State private var coPerformersError: String?
    /// Filter + sort key `coPerformers` was loaded for; a different key means reload.
    @State private var coPerformersLoadedKey: String?
    /// Latest load request; older in-flight loads drop their result.
    @State private var coPerformersLoadToken = UUID()

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
        case appearsWith = "Appears with"

        var icon: String {
            switch self {
            case .scenes: return "film"
            case .galleries: return "photo.stack"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            case .images: return "photo"
            case .appearsWith: return "person.2"
            }
        }
    }
    @State private var selectedDetailTab: DetailTab = .scenes
    /// When set (e.g. Feeds Pics/Clips → `.images`), keep that tab and skip scenes/galleries auto-switch.
    private let preferredInitialTab: DetailTab?

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    init(performer: Performer, initialTab: DetailTab? = nil) {
        _performer = State(initialValue: performer)
        self.preferredInitialTab = initialTab
        let sc = performer.sceneCount
        // Do not open the Scenes stack when we have no scene signal; galleries (or other tabs after load) avoid an empty default.
        let resolvedTab: DetailTab = initialTab ?? (sc > 0 ? .scenes : .galleries)
        _selectedDetailTab = State(initialValue: resolvedTab)
        _linkedStudios = StateObject(wrappedValue: DetailLinkedStudiosFilterModel(scope: .performer(performer.id)))
        _linkedTags = StateObject(wrappedValue: DetailLinkedTagsFilterModel(scope: .performer(performer.id)))
        _linkedGalleries = StateObject(wrappedValue: DetailLinkedGalleriesFilterModel(scope: .performer(performer.id)))
        _linkedImages = StateObject(wrappedValue: DetailLinkedImagesFilterModel(scope: .performer(performer.id)))
        _linkedCoPerformers = StateObject(wrappedValue: DetailLinkedPerformersFilterModel(scope: .coPerformers(performer.id), initialSort: .nameAsc))
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

    private var displayPerformer: Performer {
        fullPerformer ?? performer
    }
    
    private var effectiveScenes: Int {
        // A filter / search narrowing the list (even to 0) must not hide the Scenes tab — the
        // user could no longer reach its filter sheet to undo it — nor "Appears with".
        if viewModel.performerDetailScenesInitialFetchCompleted && !viewModel.isPerformerDetailSceneListConstrained {
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
        if effectiveScenes > 0 { tabs.append(.appearsWith) }
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
            case .appearsWith: return coPerformers?.isEmpty ?? true
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
            externalLiveFilterActiveBinding: $performerSceneFilterActive,
            showsFloatingFilterButton: false,
            scrollHeader: AnyView(
                headerView(displayPerformer: displayPerformer, battleLine: hotOrNotBattleLine)
                    .padding(.horizontal, 16)
            ),
            filterMemory: scenesFilterMemory
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
                } else if selectedDetailTab == .appearsWith {
                    appearsWithContent
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
        .modifier(OptionalRefreshable(action: appearsWithRefreshAction))
        .onChange(of: selectedDetailTab, initial: true) { _, tab in
            // Unstructured on purpose: switching tabs mid-load must not cancel the fetch.
            guard tab == .appearsWith else { return }
            Task { await loadCoPerformers(force: false) }
        }
    }

    var body: some View {
        performerDetailWithCoPerformersSheets
    }

    private var performerDetailWithCoPerformersSheets: some View {
        performerDetailWithLinkedGalleriesAndImagesSheets
            .sheet(isPresented: $linkedCoPerformers.showFilterSortSheet) {
                performerDetailCoPerformersFilterSheet
            }
            .onChange(of: linkedCoPerformers.catalogPresetRowSelection) { _, newId in
                linkedCoPerformers.handlePresetSelection(newId, viewModel: viewModel)
            }
            .onChange(of: linkedCoPerformers.refetchGeneration) { _, _ in
                // Unstructured on purpose: closing the sheet must not cancel the fetch.
                Task { await loadCoPerformers(force: false) }
            }
            .alert("Save as new", isPresented: $linkedCoPerformers.showSaveAsCatalogPresetAlert) {
                TextField("Name", text: $linkedCoPerformers.catalogPresetNameInput)
                Button("Save") { linkedCoPerformers.savePresetAs(name: linkedCoPerformers.catalogPresetNameInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save the current sort, filter, and live criteria as a new Stash saved filter.")
            }
            .alert("Rename", isPresented: $linkedCoPerformers.showRenameCatalogPresetAlert) {
                TextField("Name", text: $linkedCoPerformers.renameCatalogPresetInput)
                Button("Save") { linkedCoPerformers.renamePreset(to: linkedCoPerformers.renameCatalogPresetInput, viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rename this preset or saved filter.")
            }
            .alert("Delete filter?", isPresented: $linkedCoPerformers.showDeleteCatalogPresetAlert) {
                Button("Delete", role: .destructive) { linkedCoPerformers.deletePreset(viewModel: viewModel) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(linkedCoPerformers.deletePresetConfirmationText(viewModel: viewModel))
            }
    }

    private var performerDetailWithLinkedStudiosSheets: some View {
        performerDetailCoreChrome
            .sheet(isPresented: $linkedStudios.showFilterSortSheet) {
                performerDetailStudiosFilterSheet
            }
            .onChange(of: linkedStudios.catalogPresetRowSelection) { _, newId in
                linkedStudios.handlePresetSelection(newId, viewModel: viewModel)
            }
            .alert("Save as new", isPresented: $linkedStudios.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedTags.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedGalleries.showSaveAsCatalogPresetAlert) {
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
            .alert("Save as new", isPresented: $linkedImages.showSaveAsCatalogPresetAlert) {
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

    private func goBack() {
        navigationBackTrigger = UUID()
    }

    /// Custom top chrome: Back · section icons · Favorite · Edit (edit mode). Feeds lives in the header.
    @ViewBuilder
    private var performerDetailNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .modifier(StashyChromePillStyle(height: chromePillHeight, accent: true))
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
                                    .stashyChromeFill(
                                        shape: Capsule(style: .continuous),
                                        activeColor: isSelected ? appearanceManager.tintColor : nil
                                    )
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
                            .stashyGlass(shape: Capsule(style: .continuous))
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
                                .stashyGlass(shape: Capsule(style: .continuous))
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
            guard preferredInitialTab == nil else { return }
            if newValue > 0 && shouldAutoSwitchToPerformerGalleriesForEmptyScenes {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: viewModel.totalPerformerScenes) { oldValue, newValue in
            guard preferredInitialTab == nil else { return }
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
            guard preferredInitialTab == nil else { return }
            if !loading, selectedDetailTab == .scenes, effectiveScenes == 0, let first = availableTabs.first {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = first }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            AppLog.debug("🔄 SceneDeleted - Refreshing performer metadata")
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
        .background {
            StashyNavigationBackTrigger(trigger: $navigationBackTrigger) {
                dismiss()
            }
        }
        .stashyDetailChrome(performerDetailChromeConfig) {
            performerDetailNavBar
        }
        .sceneBulkDownloadDialog(
            isPresented: $showingSceneDownloadOptions,
            scope: .performer(id: displayPerformer.id),
            scopeName: displayPerformer.name,
            sceneCount: displayPerformer.sceneCount,
        )
        .sheet(isPresented: $showingEditPerformerSheet) {
            EditPerformerSheet(performer: displayPerformer, viewModel: viewModel, onDeleted: { dismiss() }) { updated in
                applyEditedPerformer(updated)
            }
        }
    }

    // MARK: - Shared detail chrome

    /// Per-tab slots for the embedded list, mirroring the previous floating action bar content.
    private var performerDetailListSlots: CatalogSlotSet {
        var slots = CatalogSlotSet(visibility: performerDetailCatalogFloatingChromeForFooter)
        switch selectedDetailTab {
        case .scenes:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: performerSceneFilterActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                performerLiveFilterSheetPresented = true
            }
            slots.contextual = SceneBulkDownloadChrome.slot {
                showingSceneDownloadOptions = true
            }
        case .galleries:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: linkedGalleries.catalogFilterSortFABActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                linkedGalleries.showFilterSortSheet = true
            }
        case .studios:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: linkedStudios.catalogFilterSortFABActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                linkedStudios.showFilterSortSheet = true
            }
        case .tags:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: linkedTags.catalogFilterSortFABActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                linkedTags.showFilterSortSheet = true
            }
        case .images:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: linkedImages.catalogFilterSortFABActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                linkedImages.showFilterSortSheet = true
            }
        case .groups:
            // No groups filter model yet — hide the bar instead of showing an empty one.
            slots.isPresented = false
        case .appearsWith:
            slots.filterSort = CatalogChromeSlot(
                systemImage: "slider.horizontal.3",
                isActive: linkedCoPerformers.catalogFilterSortFABActive,
                accessibilityLabel: "Filter and sort"
            ) {
                HapticManager.light()
                linkedCoPerformers.showFilterSortSheet = true
            }
        }
        return slots
    }

    private var performerDetailChromeConfig: StashyDetailChromeConfig {
        StashyDetailChromeConfig(listSlots: performerDetailListSlots, insetSpacing: 0)
    }

    @ViewBuilder
    private var performerDetailCoPerformersFilterSheet: some View {
        PerformersCatalogFilterSortSheet(
            serverFilters: linkedCoPerformers.sortedServerPerformerFilters(viewModel: viewModel),
            localPresets: linkedCoPerformers.localCatalogPresets,
            selectedPresetRowId: $linkedCoPerformers.catalogPresetRowSelection,
            criteriaDocument: linkedCoPerformers.criteriaDocument,
            sortOption: linkedCoPerformers.selectedSortOption,
            onSortChange: { linkedCoPerformers.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedCoPerformers.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedCoPerformers.catalogPresetRowSelection = ""
                linkedCoPerformers.selectedFilter = nil
                linkedCoPerformers.clearLiveChipsOnly()
                linkedCoPerformers.criteriaDocument.clear()
                linkedCoPerformers.applyLiveFilter(viewModel: viewModel)
            },
            onRequestSave: { linkedCoPerformers.savePresetOverwrite(viewModel: viewModel) },
            onRequestSaveAs: {
                linkedCoPerformers.catalogPresetNameInput = ""
                linkedCoPerformers.showSaveAsCatalogPresetAlert = true
            },
            onRequestRename: {
                if let sid = ListLivePresetTag.parseServerId(linkedCoPerformers.catalogPresetRowSelection),
                   let n = viewModel.savedFilters[sid]?.name {
                    linkedCoPerformers.renameCatalogPresetInput = n
                } else if let ls = ListLivePresetTag.parseLocalUUIDString(linkedCoPerformers.catalogPresetRowSelection),
                          let uuid = UUID(uuidString: ls),
                          let p = linkedCoPerformers.localCatalogPresets.first(where: { $0.id == uuid }) {
                    linkedCoPerformers.renameCatalogPresetInput = p.name
                }
                linkedCoPerformers.showRenameCatalogPresetAlert = true
            },
            onRequestDelete: { linkedCoPerformers.showDeleteCatalogPresetAlert = true },
            sharedScenesSortSelected: linkedCoPerformers.sortsBySharedScenes,
            onSelectSharedScenesSort: { linkedCoPerformers.selectSharedScenesSort(viewModel: viewModel) }
        )
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            ListLivePresetTag.migrateLegacySelection(&linkedCoPerformers.catalogPresetRowSelection)
            linkedCoPerformers.refreshLocalPresets()
            linkedCoPerformers.applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var performerDetailStudiosFilterSheet: some View {
        StudiosCatalogFilterSortSheet(
            serverFilters: linkedStudios.sortedServerStudioFilters(viewModel: viewModel),
            localPresets: linkedStudios.localCatalogPresets,
            selectedPresetRowId: $linkedStudios.catalogPresetRowSelection,
            criteriaDocument: linkedStudios.criteriaDocument,
            sortOption: linkedStudios.selectedSortOption,
            onSortChange: { linkedStudios.changeSortOption(to: $0, viewModel: viewModel) },
            onApply: { linkedStudios.applyLiveFilter(viewModel: viewModel) },
            onReset: {
                linkedStudios.catalogPresetRowSelection = ""
                linkedStudios.selectedFilter = nil
                linkedStudios.clearLiveChipsOnly()
                linkedStudios.criteriaDocument.clear()
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
    private var performerDetailGalleriesFilterSheet: some View {
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
    private var performerDetailImagesFilterSheet: some View {
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
            showsImagesFeedAutoplaySetting: true,
            cardColumnScope: CatalogCardColumnScope.images
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
        .measuresGridWidth($galleryGridWidth)
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
        .measuresGridWidth($galleryGridWidth)
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
            else if viewModel.hasMoreDetailGroups && !viewModel.detailGroups.isEmpty {
                Color.clear.onAppear { viewModel.fetchDetailGroups(performerId: performer.id, isInitialLoad: false) }
            }
        }
        .measuresGridWidth($galleryGridWidth)
    }
    
    /// Pull-to-refresh only on "Appears with"; other tabs keep their existing (no refresh) behavior.
    private var appearsWithRefreshAction: (() async -> Void)? {
        guard selectedDetailTab == .appearsWith else { return nil }
        return { await loadCoPerformers(force: true) }
    }

    @ViewBuilder
    private var appearsWithContent: some View {
        if let coPerformers, !coPerformers.isEmpty {
            appearsWithGrid(coPerformers)
        } else if isLoadingCoPerformers || coPerformers == nil && coPerformersError == nil {
            VStack {
                InlineSpinner()
                Text("Loading performers...").font(.caption).foregroundColor(.secondary)
            }.padding(.top, 40)
        } else if let coPerformersError {
            InlineEmptyStateView(icon: "exclamationmark.triangle", title: coPerformersError)
        } else {
            InlineEmptyStateView(
                icon: "person.2",
                title: linkedCoPerformers.catalogFilterSortFABActive ? "No performers match this filter" : "No shared scenes"
            )
        }
    }

    /// Same cards / columns as the Performers catalog; the badge shows the shared-scene count.
    /// Tap → scenes with both performers; context menu → the co-performer's detail.
    private func appearsWithGrid(_ coPerformers: [CoPerformer]) -> some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(coPerformers) { co in
                NavigationLink(destination: LazyView {
                    SharedScenesView(first: displayPerformer, second: co.performer)
                }) {
                    PerformerCardView(performer: co.performer, sharedSceneCount: co.sharedSceneCount)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    NavigationLink(destination: LazyView { PerformerDetailView(performer: co.performer) }) {
                        Label("Open Performer", systemImage: "person.crop.circle")
                    }
                }
                .accessibilityLabel(co.performer.name)
                .accessibilityValue("\(co.sharedSceneCount) shared \(co.sharedSceneCount == 1 ? "scene" : "scenes")")
            }
        }
        .measuresGridWidth($galleryGridWidth)
    }

    /// Loads "Appears with" for the current filter + sort. Session cache per performer + filter +
    /// sort (`CoPerformerCache`); `force` (pull-to-refresh) drops it and recounts shared scenes.
    private func loadCoPerformers(force: Bool) async {
        let performerId = performer.id
        let model = linkedCoPerformers
        let queryKey = model.coPerformersQueryKey(viewModel: viewModel)
        if !force, coPerformers != nil, coPerformersLoadedKey == queryKey { return }
        if force {
            CoPerformerCache.shared.invalidate(performerId)
        } else if let cached = CoPerformerCache.shared.get(performerId, queryKey: queryKey) {
            coPerformersLoadToken = UUID()
            coPerformers = cached
            coPerformersLoadedKey = queryKey
            coPerformersError = nil
            isLoadingCoPerformers = false
            return
        }
        let token = UUID()
        coPerformersLoadToken = token
        isLoadingCoPerformers = true
        coPerformersError = nil
        let performerFilter = model.coPerformersPerformerFilter(viewModel: viewModel)
        let sort = model.coPerformersServerSort(viewModel: viewModel)
        do {
            let repository = PerformerRepository()
            let counts: [String: Int]
            if let cachedCounts = CoPerformerCache.shared.counts(performerId) {
                counts = cachedCounts
            } else {
                counts = try await repository.fetchCoPerformerSceneCounts(performerId: performerId)
                CoPerformerCache.shared.setCounts(performerId, counts)
            }
            let result = try await repository.fetchCoPerformers(
                performerId: performerId,
                counts: counts,
                performerFilter: performerFilter,
                sort: sort
            )
            CoPerformerCache.shared.set(performerId, queryKey: queryKey, result)
            guard coPerformersLoadToken == token else { return }
            coPerformers = result
            coPerformersLoadedKey = queryKey
            isLoadingCoPerformers = false
        } catch {
            AppLog.error("Appears with: \(error.localizedDescription)")
            guard coPerformersLoadToken == token else { return }
            isLoadingCoPerformers = false
            if coPerformers == nil { coPerformersError = "Couldn't load performers" }
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
            isFeedScrolling: imagesFeedScrolling,
            viewModel: viewModel
        )
    }
    
    /// Header card (`DetailHeroCard`): the performer image blurred as the compact
    /// band backdrop, the portrait top-cropped in the circle straddling the band edge (keeps the
    /// face visible), name, Feeds pill and stats in the solid section. Two full rows of stats (8 at
    /// the grid's 4 columns) show collapsed, the rest behind the chevron pill. Favorite / Edit / image change stay in the nav bar.
    private func headerView(displayPerformer: Performer, battleLine: String?) -> some View {
        let imageURL = displayPerformer.thumbnailURL
        return DetailHeroCard(
            title: displayPerformer.name,
            items: getPerformerDetails(displayPerformer, battleLine: battleLine)
                .map { DetailHeroItem(label: $0.label, value: $0.value) },
            description: nil,
            showsHero: imageURL != nil,
            heroAccessibilityLabel: "Performer image",
            onHeroTap: nil,
            isExpanded: $isHeaderExpanded,
            collapsedItemLimit: 8,
            placeholderSystemImage: "person.fill",
            backdrop: { performerHeroImage(imageURL, alignment: .center) },
            avatar: { performerHeroImage(imageURL, alignment: .top) },
            accessory: { onImage in
                if showsFeedsNavButton {
                    DetailHeroFeedsButton(onImage: onImage) {
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
                    }
                }
            },
            footer: { EmptyView() }
        )
    }

    /// Performer image filling its frame; `alignment` picks the crop (top for the circle so
    /// the face of a portrait stays visible).
    @ViewBuilder
    private func performerHeroImage(_ url: URL?, alignment: Alignment) -> some View {
        if let url {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image.resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: alignment)
                        .clipped()
                } else if loader.isLoading {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(InlineSpinner(scale: .compact))
                } else {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.appAccent.opacity(0.5))
                        )
                }
            }
        }
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

    private func thumbnailBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .stashyGlass(shape: Capsule())
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

/// `.refreshable` only when an action is provided, so tabs without pull-to-refresh keep their behavior.
private struct OptionalRefreshable: ViewModifier {
    let action: (() async -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

// MARK: - Edit Performer Sheet

struct EditPerformerSheet: View {
    let performer: Performer
    @ObservedObject var viewModel: StashDBViewModel
    var onDeleted: (() -> Void)? = nil
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
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Disambiguation", text: $disambiguation)
                    TextField("Aliases (comma-separated)", text: $aliasesText)
                    TextField("Gender", text: $gender)
                    StashDateField(placeholder: "Birthdate (YYYY-MM-DD)", text: $birthdate)
                    TextField("Country", text: $country)
                    TextField("Ethnicity", text: $ethnicity)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Body") {
                    TextField("Height (cm)", text: $heightText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
                    TextField("Weight (kg)", text: $weightText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
                    TextField("Measurements", text: $measurements)
                    TextField("Fake tits", text: $fakeTits)
                    TextField("Penis length (cm)", text: $penisLengthText)
                        .keyboardType(.decimalPad)
                        .numericKeyboardDoneBar()
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section("Other") {
                    TextField("Career length", text: $careerLength)
                    TextField("Tattoos", text: $tattoos)
                    TextField("Piercings", text: $piercings)
                    TextField("Rating (0–100)", text: $ratingText)
                        .keyboardType(.numberPad)
                        .numericKeyboardDoneBar()
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
                                Label("Delete Performer", systemImage: "trash")
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
            .stashyModalSheetChrome("Edit Performer", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Save",
                    enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && StashDateInput.isAcceptable(birthdate),
                    isBusy: isSaving
                ) { save() }
            }
            .onAppear { hydrate() }
            .alert("Delete Performer", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { performDelete() }
            } message: {
                Text("Delete '\(performer.name)'? This cannot be undone.")
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        viewModel.deletePerformer(performerId: performer.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success:
                    ToastManager.shared.show("Performer deleted", icon: "trash", style: .success)
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

// MARK: - Shared scenes ("Appears with" → card)

/// Scenes with both performers, pushed from an "Appears with" card. Fixed scope like
/// `DirectorDetailView`: the filter is injected, so sort changes stay local to this list.
struct SharedScenesView: View {
    let first: Performer
    let second: Performer

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @State private var isHeaderExpanded = false
    /// UIKit pop when `dismiss()` is a no-op under custom chrome.
    @State private var navigationBackTrigger: UUID?

    var body: some View {
        ScenesView(
            filter: .scenesShared(by: first, and: second),
            hideTitle: true,
            scope: .catalog,
            sharedViewModel: viewModel,
            showsFloatingFilterButton: true,
            scrollHeader: AnyView(
                heroHeader
                    .padding(.horizontal, 16)
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            StashyNavigationBackTrigger(trigger: $navigationBackTrigger) {
                dismiss()
            }
        }
        .stashyDetailChrome(StashyDetailChromeConfig(insetSpacing: 0)) { navBar }
    }

    /// Same `DetailHeroCard` as the other detail screens: blurred band from the first performer,
    /// both avatars side by side (slightly overlapping) on the band edge, each opening that
    /// performer's detail.
    private var heroHeader: some View {
        let backdropURL = first.thumbnailURL ?? second.thumbnailURL
        return DetailHeroCard(
            title: "\(first.name) & \(second.name)",
            items: [DetailHeroItem(label: "SHARED SCENES", value: sharedScenesValue)],
            description: nil,
            showsHero: backdropURL != nil,
            onHeroTap: nil,
            isExpanded: $isHeaderExpanded,
            placeholderSystemImage: "person.2.fill",
            leadingAvatars: AnyView(avatarPair),
            backdrop: { heroImage(backdropURL, alignment: .center) },
            avatar: { EmptyView() },
            accessory: { _ in EmptyView() },
            footer: { EmptyView() }
        )
    }

    private var sharedScenesValue: String {
        if viewModel.totalScenes == 0 && (viewModel.isLoading || viewModel.isLoadingScenes) { return "—" }
        return "\(viewModel.totalScenes)"
    }

    private var avatarPair: some View {
        HStack(spacing: -18) {
            performerAvatarLink(first)
            performerAvatarLink(second)
        }
    }

    private func performerAvatarLink(_ performer: Performer) -> some View {
        NavigationLink(destination: LazyView { PerformerDetailView(performer: performer) }) {
            DetailHeroAvatarCircle(showsImage: performer.thumbnailURL != nil, placeholderSystemImage: "person.fill") {
                heroImage(performer.thumbnailURL, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(performer.name)")
    }

    /// Image filling its frame; `alignment` picks the crop (top for the circles so faces stay visible).
    @ViewBuilder
    private func heroImage(_ url: URL?, alignment: Alignment) -> some View {
        if let url {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image.resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: alignment)
                        .clipped()
                } else if loader.isLoading {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(InlineSpinner(scale: .compact))
                } else {
                    Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.appAccent.opacity(0.5))
                        )
                }
            }
        }
    }

    /// Same top chrome as the performer / studio detail screens: Back pill only.
    @ViewBuilder
    private var navBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                StashyChromeBackButton { navigationBackTrigger = UUID() }
                Spacer(minLength: 8)
            }
            .frame(minHeight: StashyExpandingDock.activeHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }
}

extension StashDBViewModel.SavedFilter {
    /// Scenes featuring both performers (`INCLUDES_ALL`), used by the "Appears with" cards.
    static func scenesShared(by first: Performer, and second: Performer) -> StashDBViewModel.SavedFilter {
        StashDBViewModel.SavedFilter(
            id: "stashy_shared_\(first.id)_\(second.id)",
            name: "\(first.name) & \(second.name)",
            mode: .scenes,
            filter: nil,
            object_filter: .object([
                "performers": .object([
                    "value": .array([.string(first.id), .string(second.id)]),
                    "modifier": .string("INCLUDES_ALL")
                ])
            ]),
            ui_options: nil
        )
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
