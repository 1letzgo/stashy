//
//  TVMarkersView.swift
//  stashyTV
//
//  Scene markers across the library — the tvOS counterpart of the iOS Markers list.
//  Select plays the marker's scene from the marker's time; the player's down panel then
//  lists the scene's other markers, as in scene detail.
//

import SwiftUI

struct TVMarkersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @StateObject private var playerModel = TVAetherPlaybackModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @State private var sortBy: StashDBViewModel.SceneMarkerSortOption
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    // Same once-per-lifetime rule as `TVScenesView`: "No Filter" must survive a pop.
    @State private var didApplyDefaultFilter = false
    @State private var focusResetToken = 0
    @FocusState private var focusedMarkerID: String?

    /// The scene of the marker being played; feeds the player's title and marker rail.
    @State private var playingScene: Scene?
    /// Marker whose scene is being fetched — guards double selects while it loads.
    @State private var pendingMarkerID: String?

    init() {
        let stored = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getSortOption(for: .markers) ?? "")
        _sortBy = State(initialValue: stored ?? .createdAtDesc)
    }

    private static let sortOrder: [StashDBViewModel.SceneMarkerSortOption] = [
        .random, .createdAtDesc, .createdAtAsc, .updatedAtDesc, .updatedAtAsc,
        .titleAsc, .titleDesc, .secondsAsc, .secondsDesc
    ]

    private var sortOptions: [TVPickerOption<StashDBViewModel.SceneMarkerSortOption>] {
        Self.sortOrder.map { TVPickerOption($0, $0.displayName) }
    }

    var body: some View {
        TVCatalogGrid(
            items: viewModel.sceneMarkers,
            hasValidConfig: hasValidConfig,
            errorMessage: viewModel.errorMessage,
            isLoading: viewModel.isLoading,
            isLoadingMore: viewModel.isLoadingMarkers && !viewModel.sceneMarkers.isEmpty,
            hasMore: viewModel.hasMoreMarkers,
            columnWidth: 410,
            emptySystemImage: "bookmark",
            emptyTitle: "No markers found",
            loadingText: "Loading markers…",
            errorTitle: "Error loading markers",
            focusResetToken: focusResetToken,
            loadMore: { viewModel.loadMoreMarkers() },
            reload: { reload() },
            focusedID: $focusedMarkerID,
            header: {
                STVHeaderView(
                    sortMenu: {
                        TVOptionPickerButton(
                            title: "Sort By",
                            icon: "arrow.up.arrow.down",
                            options: sortOptions,
                            selection: $sortBy
                        )
                    },
                    filterMenu: {
                        TVFilterPickerButton(filters: savedFilters, selection: $selectedFilter)
                    }
                )
            },
            card: { marker in
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        play(marker)
                    } label: {
                        TVMarkerCardView(marker: marker, isLoading: pendingMarkerID == marker.id)
                    }
                    .buttonStyle(.card)
                    TVMarkerCardTitleView(marker: marker)
                }
            }
        )
        .onChange(of: sortBy) { _, _ in
            focusResetToken += 1
            fetch()
        }
        .onChange(of: selectedFilter) { _, _ in
            focusResetToken += 1
            fetch()
        }
        .onAppear {
            guard hasValidConfig else { return }
            viewModel.fetchSavedFilters { _ in
                applyDefaultFilterIfNeeded()
            }
            if viewModel.sceneMarkers.isEmpty {
                fetch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            didApplyDefaultFilter = false
            playingScene = nil
            pendingMarkerID = nil
            viewModel.sceneMarkers = []
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            if hasValidConfig && viewModel.sceneMarkers.isEmpty {
                fetch()
            }
        }
        .dismissOnAppLock { playerModel.isShowingPlayer = false }
        .fullScreenCover(isPresented: $playerModel.isShowingPlayer, onDismiss: {
            playerModel.clear()
            playingScene = nil
        }) {
            TVAetherPlayerView(
                model: playerModel,
                title: playingScene?.displayTitle ?? "Untitled Scene",
                subtitle: playingScene?.studio?.name ?? "",
                posterURL: playingScene?.thumbnailURL,
                onDisappear: { playerModel.saveProgress() },
                panelExtra: {
                    // Same rail as in scene detail: jump between this scene's markers.
                    let markers = playingScene?.sceneMarkers ?? []
                    if !markers.isEmpty {
                        TVMarkerRailView(
                            markers: markers,
                            currentTime: playerModel.engine?.currentTime ?? 0,
                            onSelect: { marker in
                                guard let engine = playerModel.engine else { return }
                                Task {
                                    await engine.seek(to: marker.seconds)
                                    engine.play()
                                }
                            }
                        )
                    }
                }
            )
        }
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    private var savedFilters: [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .sceneMarkers }
            .sorted { $0.name < $1.name }
    }

    private func fetch() {
        viewModel.fetchSceneMarkers(sortBy: sortBy, filter: selectedFilter)
    }

    private func applyDefaultFilterIfNeeded() {
        guard !didApplyDefaultFilter else { return }
        didApplyDefaultFilter = true
        guard selectedFilter == nil,
              let filterId = tabManager.getDefaultMarkerFilterId(for: .markers),
              let filter = viewModel.savedFilters[filterId] else { return }
        selectedFilter = filter
    }

    private func reload() {
        guard hasValidConfig else { return }
        viewModel.testConnection()
        fetch()
    }

    // MARK: - Playback

    /// The marker list carries only a slim scene (no studio, captions or marker list), so
    /// the full scene is fetched first. If that fails, the slim one still plays.
    private func play(_ marker: SceneMarker) {
        guard let markerScene = marker.scene, pendingMarkerID == nil else { return }
        pendingMarkerID = marker.id
        viewModel.fetchSceneDetails(sceneId: markerScene.id) { fetched in
            guard pendingMarkerID == marker.id else { return }
            pendingMarkerID = nil
            let scene = fetched ?? markerScene.toScene()
            guard let url = scene.aetherVideoURL else { return }
            playingScene = scene
            playerModel.setup(url: url,
                              sceneId: scene.id,
                              viewModel: viewModel,
                              startAt: marker.seconds,
                              title: scene.displayTitle,
                              subtitle: scene.studio?.name,
                              artworkURL: scene.thumbnailURL,
                              fallbackSources: scene.transcodeFallbackURLs,
                              fallbackDeclaredDuration: scene.sceneDuration,
                              scene: scene)
        }
    }
}

// MARK: - Cards

/// 16:9 marker card in the scene card's look: screenshot, the marker's own preview clip
/// after 2 s of focus, its time and primary tag.
struct TVMarkerCardView: View {
    let marker: SceneMarker
    var width: CGFloat = 410
    var height: CGFloat = 230
    var isLoading: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnail
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            TVFocusPreview(url: marker.previewURL, width: width, height: height, cornerRadius: 10)

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isFocused ? 0.3 : 1.0)

            VStack {
                HStack(alignment: .top) {
                    if let tag = marker.primaryTag?.name, !tag.isEmpty {
                        badge(tag.uppercased())
                    }
                    Spacer()
                    badge(TVMarkerCardView.timeLabel(marker.seconds))
                        .monospacedDigit()
                }
                .padding(12)
                Spacer()
            }

            if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .tracking(1)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = marker.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else if loader.isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.08))
                        .overlay(ProgressView().scaleEffect(0.8))
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "bookmark")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
    }

    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct TVMarkerCardTitleView: View {
    let marker: SceneMarker

    private var title: String {
        if let title = marker.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let tag = marker.primaryTag?.name, !tag.isEmpty { return tag }
        return "Marker"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(1)

            if let sceneTitle = marker.scene?.toScene().displayTitle, !sceneTitle.isEmpty {
                Text(sceneTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let performers = marker.scene?.performers, !performers.isEmpty {
                Text(performers.prefix(3).map { $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
