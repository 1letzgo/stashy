//
//  TVDashboardView.swift
//  stashyTV
//
//  Dashboard for tvOS — Netflix/Prime style rows
//

import SwiftUI

struct TVDashboardView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var recentlyPlayedScenes: [Scene] = []
    @State private var recentlyReleasedScenes: [Scene] = []
    @State private var recentlyAddedScenes: [Scene] = []
    @State private var topRatedScenes: [Scene] = []
    @State private var randomScenes: [Scene] = []

    @State private var isLoadingPlayed: Bool = true
    @State private var isLoadingReleased: Bool = true
    @State private var isLoadingAdded: Bool = true
    @State private var isLoadingTopRated: Bool = true
    @State private var isLoadingRandom: Bool = true

    @State private var channelPreviews: [String: [Scene]] = [:]
    @State private var isLoadingChannelPreviews = false
    @State private var playingChannel: TVChannel?
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabBarPlacement) private var tabBarPlacement

    /// Der 60pt-Abstand oben stammt aus der Zeit der oberen Tab-Leiste. Mit der
    /// Sidebar ist oben nichts mehr — und seit der Refresh-Button weg ist, stand
    /// die erste Reihe deutlich zu tief.
    private var topInset: CGFloat {
        tabBarPlacement == .topBar ? 60 : 16
    }

    var body: some View {
        Group {
            if !hasValidConfig {
                TVConnectionErrorView(title: "Server not reachable", subtitle: "Add a server in Settings.") { loadData() }
            } else {
                ScrollView([.vertical], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                            .frame(height: topInset)

                        // MARK: Content Rows
                        contentRows
                    }
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
            }
        }
        .background(Color.appBackground)
        .fullScreenCover(item: $playingChannel, onDismiss: {
            playingChannel = nil
            // Fortschritte aus dem Kanal-Player nachholen, die während der
            // Wiedergabe bewusst nicht verarbeitet wurden (s. u.).
            refreshContinueWatching()
        }) { channel in
            TVChannelPlayerView(channel: channel)
        }
        .onAppear { loadData(forceRefresh: true) }
        // Nicht auf `ServerConfigChanged` laden: `handleServerChange` bricht alle GraphQL-Tasks ab —
        // ein sofortiges `loadData()` würde nur leer/cancelled enden. Stattdessen nach init neu laden.
        .onReceive(NotificationCenter.default.publisher(for: .stashServerInitializationFinished)) { _ in
            loadData(forceRefresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { _ in
            // Nicht mitten in der Kanal-Wiedergabe neu laden: Der 10s-Progress-Save des
            // Players feuert dieses Notification laufend — jede Reaktion erzeugt Netzwerk-
            // und Render-Churn unter dem aktiven fullScreenCover. Nachgeholt in `onDismiss`.
            guard playingChannel == nil else { return }
            refreshContinueWatching()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Saved filters are server-scoped, so previews must not survive a switch.
            channelPreviews = [:]
            playingChannel = nil
            isLoadingChannelPreviews = false
        }
        // Kanäle nachträglich einblenden, wenn stashy+ im Settings gekauft wurde.
        .onReceive(NotificationCenter.default.publisher(for: .stashyPlusUnlocked)) { _ in
            fetchChannels()
        }
        // `sceneLiveUpdates(using:)` patcht `viewModel.scenes` — die Reihen hier
        // liegen aber in lokalem State, deshalb eigene Handler.
        // Neue Szenen auf dem Server kann keine Notification melden. Statt eines
        // Refresh-Buttons: nachladen, wenn die App aus dem Hintergrund zurückkommt.
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active, oldPhase == .background else { return }
            guard playingChannel == nil else { return }
            loadData(forceRefresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { note in
            guard let id = note.userInfo?["sceneId"] as? String else { return }
            mutateRows { $0.removeAll { $0.id == id } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneUpdated"))) { note in
            guard let updated = Scene.fromListMetadataNotification(note) else { return }
            patchScene(id: updated.id) { $0.mergingListMetadata(from: updated) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneOCounterUpdated"))) { note in
            guard let id = note.userInfo?["sceneId"] as? String,
                  let count = note.userInfo?["oCounter"] as? Int else { return }
            patchScene(id: id) { $0.withOCounter(count) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneRatingUpdated"))) { note in
            guard let id = note.userInfo?["sceneId"] as? String else { return }
            let rating = note.userInfo?["rating100"] as? Int
            patchScene(id: id) { $0.withRating(rating) }
            // „Top Rated" ist nach Bewertung sortiert — die Reihenfolge kann sich
            // geändert haben, das lässt sich nicht in-place patchen.
            refreshTopRated()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScenePlayAdded"))) { note in
            guard let id = note.userInfo?["sceneId"] as? String else { return }
            patchScene(id: id) { $0.withPlayCount(($0.playCount ?? 0) + 1) }
            // „Continue Watching" ist nach `lastPlayedAt` sortiert.
            guard playingChannel == nil else { return }
            refreshContinueWatching()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneCoverUpdated"))) { note in
            guard let id = note.userInfo?["sceneId"] as? String,
                  let updatedAt = note.userInfo?["updatedAt"] as? String else { return }
            patchScene(id: id) { $0.withUpdatedAt(Scene.newerUpdatedAt($0.updatedAt, updatedAt)) }
        }
    }

    // MARK: - Live-Updates der Reihen

    /// Wendet eine Änderung auf alle fünf Reihen an.
    private func mutateRows(_ transform: (inout [Scene]) -> Void) {
        transform(&recentlyPlayedScenes)
        transform(&recentlyReleasedScenes)
        transform(&recentlyAddedScenes)
        transform(&topRatedScenes)
        transform(&randomScenes)
    }

    /// Ersetzt eine Szene in allen Reihen, in denen sie vorkommt.
    private func patchScene(id: String, _ transform: @escaping (Scene) -> Scene) {
        mutateRows { list in
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            let updated = transform(list[idx])
            guard updated != list[idx] else { return }
            list[idx] = updated
        }
    }

    private func refreshTopRated() {
        guard hasValidConfig else { return }
        let topRatedConfig = HomeRowConfig(
            id: UUID(),
            title: "Top Rated",
            isEnabled: true,
            sortOrder: 3,
            type: .topRating3Min
        )
        viewModel.fetchScenesForHomeRow(config: topRatedConfig, limit: 15, forceRefresh: true) { scenes in
            topRatedScenes = scenes
        }
    }
    
    // MARK: - Content Rows
    
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 50) {
            if isLoadingPlayed || isLoadingReleased || isLoadingAdded || isLoadingTopRated || isLoadingRandom {
                if recentContentIsEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }

            if !recentlyPlayedScenes.isEmpty {
                sceneRow(
                    title: "Continue Watching",
                    scenes: recentlyPlayedScenes,
                    sortBy: .lastPlayedAtDesc,
                    cardWidth: 560,
                    cardHeight: 315
                )
                .focusSection()
            }

            if !channels.isEmpty {
                channelsRow
                    .focusSection()
            }

            if !recentlyReleasedScenes.isEmpty {
                sceneRow(
                    title: "New Releases",
                    scenes: recentlyReleasedScenes,
                    sortBy: .dateDesc
                )
                .focusSection()
            }

            if !recentlyAddedScenes.isEmpty {
                sceneRow(
                    title: "Recently Added",
                    scenes: recentlyAddedScenes,
                    sortBy: .createdAtDesc
                )
                .focusSection()
            }

            if !topRatedScenes.isEmpty {
                sceneRow(
                    title: "Top Rated",
                    scenes: topRatedScenes,
                    sortBy: .ratingDesc
                )
                .focusSection()
            }

            if !randomScenes.isEmpty {
                sceneRow(
                    title: "Random Picks",
                    scenes: randomScenes,
                    sortBy: .random
                )
                .focusSection()
            }

            if !isLoadingPlayed && !isLoadingReleased && !isLoadingAdded && !isLoadingTopRated && !isLoadingRandom && recentContentIsEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No scenes to show yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Reload") { loadData(forceRefresh: true) }
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            }
        }
        .padding(.bottom, 80)
    }

    private var recentContentIsEmpty: Bool {
        recentlyPlayedScenes.isEmpty
            && recentlyReleasedScenes.isEmpty
            && recentlyAddedScenes.isEmpty
            && topRatedScenes.isEmpty
            && randomScenes.isEmpty
    }

    private var hasValidConfig: Bool { configManager.activeConfig?.hasValidConfig == true }

    // MARK: - Channels

    private var channels: [TVChannel] {
        // stashy+-Feature: ohne Entitlement gar keine Kanäle ausliefern,
        // dann verschwinden Zeile und Previews automatisch.
        guard stashyPlus.isUnlocked else { return [] }
        let filters = viewModel.savedFilters.values
            .filter { $0.mode == .scenes }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { TVChannel(kind: .savedFilter, title: $0.name, savedFilter: $0) }
        return [.recentlyReleased, .recentlyAdded] + filters
    }

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false) {
        guard hasValidConfig else { return }
        fetchHomeRows(forceRefresh: forceRefresh)
        fetchChannels()
    }

    private func fetchChannels() {
        guard stashyPlus.isUnlocked else { return }
        viewModel.fetchSavedFilters { _ in
            loadChannelPreviews()
        }
        loadChannelPreviews()
    }

    private func loadChannelPreviews() {
        let pending = channels.filter { channelPreviews[$0.id] == nil }
        guard !pending.isEmpty else { return }
        if isLoadingChannelPreviews { return }
        isLoadingChannelPreviews = true
        loadChannelPreview(at: 0, from: pending)
    }

    private func loadChannelPreview(at index: Int, from pending: [TVChannel], retrying: Bool = false) {
        guard index < pending.count else {
            isLoadingChannelPreviews = false
            // Saved filters may have arrived while the first two built-in cards were loading.
            let leftover = channels.filter { channelPreviews[$0.id] == nil }
            if !leftover.isEmpty {
                isLoadingChannelPreviews = true
                loadChannelPreview(at: 0, from: leftover)
            }
            return
        }
        let channel = pending[index]
        viewModel.fetchScenePage(sortBy: channel.sortBy, filter: channel.sceneFilter, page: 1, perPage: 4) { scenes, _ in
            if scenes.isEmpty && !retrying {
                loadChannelPreview(at: index, from: pending, retrying: true)
                return
            }
            channelPreviews[channel.id] = scenes
            loadChannelPreview(at: index + 1, from: pending)
        }
    }

    private func refreshContinueWatching() {
        guard hasValidConfig else { return }
        isLoadingPlayed = true
        let playedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Played",
            isEnabled: true,
            sortOrder: 0,
            type: .lastPlayed
        )
        viewModel.fetchScenesForHomeRow(config: playedConfig, limit: 15, forceRefresh: true) { scenes in
            recentlyPlayedScenes = scenes
            isLoadingPlayed = false
        }
    }

    private func fetchHomeRows(forceRefresh: Bool) {
        isLoadingPlayed = true
        let playedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Played",
            isEnabled: true,
            sortOrder: 0,
            type: .lastPlayed
        )
        viewModel.fetchScenesForHomeRow(config: playedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyPlayedScenes = scenes
            isLoadingPlayed = false
        }

        isLoadingReleased = true
        let releasedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Released",
            isEnabled: true,
            sortOrder: 1,
            type: .newest3Min
        )
        viewModel.fetchScenesForHomeRow(config: releasedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyReleasedScenes = scenes
            isLoadingReleased = false
        }

        isLoadingAdded = true
        let addedConfig = HomeRowConfig(
            id: UUID(),
            title: "Recently Added",
            isEnabled: true,
            sortOrder: 2,
            type: .lastAdded3Min
        )
        viewModel.fetchScenesForHomeRow(config: addedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            recentlyAddedScenes = scenes
            isLoadingAdded = false
        }

        isLoadingTopRated = true
        let topRatedConfig = HomeRowConfig(
            id: UUID(),
            title: "Top Rated",
            isEnabled: true,
            sortOrder: 3,
            type: .topRating3Min
        )
        viewModel.fetchScenesForHomeRow(config: topRatedConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            topRatedScenes = scenes
            isLoadingTopRated = false
        }

        isLoadingRandom = true
        let randomConfig = HomeRowConfig(
            id: UUID(),
            title: "Random",
            isEnabled: true,
            sortOrder: 4,
            type: .random
        )
        viewModel.fetchScenesForHomeRow(config: randomConfig, limit: 15, forceRefresh: forceRefresh) { scenes in
            randomScenes = scenes
            isLoadingRandom = false
        }
    }

    // MARK: - Channels Row

    @ViewBuilder
    private var channelsRow: some View {
        let cardWidth: CGFloat = 400
        let cardHeight: CGFloat = 225

        VStack(alignment: .leading, spacing: 18) {
            Text("Channels")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(channels) { channel in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                playingChannel = channel
                            } label: {
                                TVChannelCardView(
                                    channel: channel,
                                    scenes: channelPreviews[channel.id] ?? [],
                                    width: cardWidth + 10,
                                    height: cardHeight + 5
                                )
                            }
                            .buttonStyle(.card)

                            Text(channel.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: cardWidth)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Scene Row

    @ViewBuilder
    private func sceneRow(title: String, scenes: [Scene], sortBy: StashDBViewModel.SceneSortOption, cardWidth: CGFloat = 400, cardHeight: CGFloat = 225) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section heading (Static)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 50)

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene, width: cardWidth + 10, height: cardHeight + 5)
                            }
                            
                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: cardWidth)
                    }

                    // See All Card at the end
                    TVNavButton(value: TVSceneListLink(sortBy: sortBy)) {
                        VStack(spacing: 20) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("See All")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}

/// Channel card matching the scene card look of the surrounding dashboard rows.
private struct TVChannelCardView: View {
    let channel: TVChannel
    let scenes: [Scene]
    var width: CGFloat = 410
    var height: CGFloat = 230
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .black.opacity(0.3), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isFocused ? 0.3 : 1.0)

            VStack {
                HStack(alignment: .top) {
                    Label(channel.subtitle.uppercased(), systemImage: channel.icon)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .tracking(1)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
                Spacer()
            }

            VStack {
                Spacer()
                Text(channel.title)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var artwork: some View {
        if scenes.isEmpty {
            placeholder
        } else if scenes.count == 1 {
            thumbnail(for: scenes[0])
        } else {
            HStack(spacing: 2) {
                ForEach(Array(scenes.prefix(4))) { scene in
                    thumbnail(for: scene)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for scene: Scene) -> some View {
        if let url = scene.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.08))
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
                Image(systemName: channel.icon)
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            )
    }
}
