//
//  TVDashboardView.swift
//  stashyTV
//
//  Dashboard for tvOS — Netflix/Prime style rows. Which rows and in what order comes
//  from `TabManager.homeRows` (Settings › Home Rows), the same store iOS uses.
//

import SwiftUI

struct TVDashboardView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject private var configManager = ServerConfigManager.shared
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared

    /// Row contents by type. Local state (not the view model's caches) so live updates
    /// can patch them in place.
    @State private var sceneRows: [HomeRowType: [Scene]] = [:]
    @State private var performerRows: [HomeRowType: [Performer]] = [:]
    @State private var studioRows: [HomeRowType: [Studio]] = [:]
    @State private var galleryRows: [HomeRowType: [Gallery]] = [:]
    /// Rows with a fetch in flight. Rows not yet fetched count as loading too
    /// (`hasLoaded`), so the first frame shows the spinner, not the empty state.
    @State private var loadingRows: Set<HomeRowType> = []
    @State private var loadedRows: Set<HomeRowType> = []

    private static let rowLimit = 15

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
        .dismissOnAppLock { playingChannel = nil }
        .fullScreenCover(item: $playingChannel, onDismiss: {
            playingChannel = nil
            // Fortschritte aus dem Kanal-Player nachholen, die während der
            // Wiedergabe bewusst nicht verarbeitet wurden (s. u.).
            refreshContinueWatching()
        }) { channel in
            TVChannelPlayerView(channel: channel)
        }
        .onAppear { loadData(forceRefresh: true) }
        // Settings › Home Rows: a newly enabled row needs its content.
        .onChange(of: tabManager.homeRows) { _, _ in
            loadMissingRows()
        }
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
            // Rows belong to the old server as well.
            sceneRows = [:]
            performerRows = [:]
            studioRows = [:]
            galleryRows = [:]
            loadingRows = []
            loadedRows = []
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

    /// Wendet eine Änderung auf alle Szenen-Reihen an.
    private func mutateRows(_ transform: (inout [Scene]) -> Void) {
        for key in Array(sceneRows.keys) {
            guard var list = sceneRows[key] else { continue }
            let before = list
            transform(&list)
            if list != before { sceneRows[key] = list }
        }
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
        // „Top Rated" ist nach Bewertung sortiert — die Reihenfolge kann sich
        // geändert haben, das lässt sich nicht in-place patchen.
        refreshRowIfEnabled(.topRating3Min)
    }

    private func refreshContinueWatching() {
        refreshRowIfEnabled(.lastPlayed)
    }

    private func refreshRowIfEnabled(_ type: HomeRowType) {
        guard hasValidConfig, let row = enabledRows.first(where: { $0.type == type }) else { return }
        fetchRow(row, forceRefresh: true)
    }

    // MARK: - Content Rows

    /// Enabled rows in the user's order. Statistics has no TV form; Channels drops out
    /// on its own without stashy+ (`channels` is empty then).
    private var enabledRows: [HomeRowConfig] {
        tabManager.homeRows.filter { $0.isEnabled && $0.type.isAvailableOnTV }
    }

    private var isAnyRowLoading: Bool {
        enabledRows.contains { row in
            row.type != .channels && (loadingRows.contains(row.type) || !loadedRows.contains(row.type))
        }
    }

    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 50) {
            if isAnyRowLoading && recentContentIsEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
                .padding(.top, 40)
            }

            ForEach(enabledRows) { row in
                rowView(for: row)
            }

            if !isAnyRowLoading && recentContentIsEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "film.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(enabledRows.isEmpty ? "All Home rows are turned off" : "No scenes to show yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if enabledRows.isEmpty {
                        Text("Turn rows on in Settings › Home Rows.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Button("Reload") { loadData(forceRefresh: true) }
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            }
        }
        .padding(.bottom, 80)
    }

    @ViewBuilder
    private func rowView(for row: HomeRowConfig) -> some View {
        let title = row.type.tvTitle
        switch row.type {
        case .channels:
            if !channels.isEmpty {
                channelsRow
                    .focusSection()
            }
        case .statistics:
            EmptyView()
        case .lastPlayed:
            if let scenes = sceneRows[row.type], !scenes.isEmpty {
                sceneRow(title: title, scenes: scenes, sortBy: .lastPlayedAtDesc,
                         cardWidth: 560, cardHeight: 315)
                    .focusSection()
            }
        case .newest3Min, .lastAdded3Min, .mostViewed3Min, .topCounter3Min, .topRating3Min, .random:
            if let scenes = sceneRows[row.type], !scenes.isEmpty {
                sceneRow(title: title, scenes: scenes, sortBy: Self.sceneSort(for: row.type))
                    .focusSection()
            }
        case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
            if let performers = performerRows[row.type], !performers.isEmpty {
                cardRow(title: title, items: performers) { performer in
                    TVNavButton(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                        TVPerformerCardView(performer: performer)
                    }
                }
                .focusSection()
            }
        case .newStudios, .studiosHighestSceneCount:
            if let studios = studioRows[row.type], !studios.isEmpty {
                cardRow(title: title, items: studios) { studio in
                    TVNavButton(value: TVStudioLink(id: studio.id, name: studio.name)) {
                        TVStudioCardView(studio: studio)
                    }
                }
                .focusSection()
            }
        case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
            if let galleries = galleryRows[row.type], !galleries.isEmpty {
                cardRow(title: title, items: galleries) { gallery in
                    TVNavButton(value: TVGalleryLink(id: gallery.id, title: gallery.displayName)) {
                        TVGalleryCardView(gallery: gallery)
                    }
                }
                .focusSection()
            }
        }
    }

    /// The "See All" target of a scene row: the Scenes grid in the row's sort.
    private static func sceneSort(for type: HomeRowType) -> StashDBViewModel.SceneSortOption {
        switch type {
        case .lastPlayed: return .lastPlayedAtDesc
        case .lastAdded3Min: return .createdAtDesc
        case .mostViewed3Min: return .playCountDesc
        case .topCounter3Min: return .oCounterDesc
        case .topRating3Min: return .ratingDesc
        case .random: return .random
        default: return .dateDesc
        }
    }

    private var recentContentIsEmpty: Bool {
        sceneRows.values.allSatisfy(\.isEmpty)
            && performerRows.values.allSatisfy(\.isEmpty)
            && studioRows.values.allSatisfy(\.isEmpty)
            && galleryRows.values.allSatisfy(\.isEmpty)
            && (channels.isEmpty || !enabledRows.contains { $0.type == .channels })
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

    private func fetchHomeRows(forceRefresh: Bool) {
        for row in enabledRows where row.type != .channels {
            fetchRow(row, forceRefresh: forceRefresh)
        }
    }

    /// Rows switched on in Settings while Home was alive.
    private func loadMissingRows() {
        guard hasValidConfig else { return }
        for row in enabledRows where row.type != .channels && !loadedRows.contains(row.type) {
            fetchRow(row, forceRefresh: false)
        }
        if enabledRows.contains(where: { $0.type == .channels }) {
            fetchChannels()
        }
    }

    /// One row through the same `StashDBViewModel` fetches as the iOS Home.
    private func fetchRow(_ row: HomeRowConfig, forceRefresh: Bool) {
        let type = row.type
        let limit = Self.rowLimit
        loadingRows.insert(type)
        let finish = {
            loadingRows.remove(type)
            loadedRows.insert(type)
        }
        switch type {
        case .channels, .statistics:
            loadingRows.remove(type)
        case .newPerformers, .performersHighestSceneCount, .performersHighestOCount, .performersHighestRating:
            viewModel.fetchPerformersForHomeRow(config: row, limit: limit, forceRefresh: forceRefresh) { performers in
                performerRows[type] = performers
                finish()
            }
        case .newStudios, .studiosHighestSceneCount:
            viewModel.fetchStudiosForHomeRow(config: row, limit: limit, forceRefresh: forceRefresh) { studios in
                studioRows[type] = studios
                finish()
            }
        case .newGalleries, .recentlyUpdatedGalleries, .galleriesHighestImageCount:
            viewModel.fetchGalleriesForHomeRow(config: row, limit: limit, forceRefresh: forceRefresh) { galleries in
                galleryRows[type] = galleries
                finish()
            }
        case .lastPlayed, .lastAdded3Min, .newest3Min, .mostViewed3Min, .topCounter3Min, .topRating3Min, .random:
            viewModel.fetchScenesForHomeRow(config: row, limit: limit, forceRefresh: forceRefresh) { scenes in
                sceneRows[type] = scenes
                finish()
            }
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

    // MARK: - Performer / Studio / Gallery Rows

    /// Horizontal row of cards that bring their own size and caption.
    @ViewBuilder
    private func cardRow<Item: Identifiable, Card: View>(
        title: String,
        items: [Item],
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 30) {
                    ForEach(items) { item in
                        card(item)
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
