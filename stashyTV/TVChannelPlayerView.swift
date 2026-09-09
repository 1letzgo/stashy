//
//  TVChannelPlayerView.swift
//  stashyTV
//
//  Continuous channel playback with previous / next skip.
//

import SwiftUI
import Combine
import UIKit

/// A continuous-playback channel: built-in sorts, the server's saved scene filters,
/// or every scene of a single performer, studio or tag.
struct TVChannel: Identifiable, Hashable {
    /// Entity-scoped channels, keyed by the GraphQL scene-filter field they filter on.
    enum Scope: String, Hashable {
        case performer = "performers"
        case studio = "studios"
        case tag = "tags"
        case group = "groups"

        /// Stash-Seite: alles außer `performers` ist ein
        /// `HierarchicalMultiCriterionInput`.
        var isHierarchical: Bool {
            self != .performer
        }

        var label: String {
            switch self {
            case .performer: return "Performer"
            case .studio: return "Studio"
            case .tag: return "Tag"
            case .group: return "Group"
            }
        }

        var icon: String {
            switch self {
            case .performer: return "person.fill"
            case .studio: return "building.2.fill"
            case .tag: return "tag.fill"
            case .group: return "rectangle.stack.fill"
            }
        }
    }

    enum Kind: Hashable {
        case recentlyReleased
        case recentlyAdded
        case savedFilter
        case scoped(Scope, id: String)
    }

    let kind: Kind
    let title: String
    let savedFilter: StashDBViewModel.SavedFilter?

    var id: String {
        switch kind {
        case .recentlyReleased: return "channel.recentlyReleased"
        case .recentlyAdded: return "channel.recentlyAdded"
        case .savedFilter: return "channel.filter.\(savedFilter?.id ?? title)"
        case .scoped(let scope, let id): return "channel.\(scope.rawValue).\(id)"
        }
    }

    var sortBy: StashDBViewModel.SceneSortOption {
        switch kind {
        case .recentlyAdded: return .createdAtDesc
        case .savedFilter: return savedFilter?.resolvedSceneSort ?? .dateDesc
        default: return .dateDesc
        }
    }

    var icon: String {
        switch kind {
        case .recentlyReleased: return "sparkles.tv.fill"
        case .recentlyAdded: return "plus.rectangle.on.folder.fill"
        case .savedFilter: return "line.3.horizontal.decrease.circle.fill"
        case .scoped(let scope, _): return scope.icon
        }
    }

    var subtitle: String {
        switch kind {
        case .savedFilter: return "Saved filter"
        case .scoped(let scope, _): return scope.label
        default: return "Channel"
        }
    }

    /// Scene filter passed to `fetchScenePage`. Entity-scoped channels build an
    /// ad-hoc filter, since they have no counterpart on the server.
    var sceneFilter: StashDBViewModel.SavedFilter? {
        switch kind {
        case .scoped(let scope, let entityID):
            var criterion: [String: StashJSONValue] = [
                "modifier": .string("INCLUDES"),
                "value": .array([.string(entityID)])
            ]
            // `studios`, `tags` und `groups` sind in Stash
            // `HierarchicalMultiCriterionInput` und brauchen `depth`; nur
            // `performers` ist ein einfaches `MultiCriterionInput`.
            // Der Rest der App setzt das überall (siehe `FilterFieldCatalog`
            // und die Scope-Filter im StashDBViewModel) — hier fehlte es.
            if scope.isHierarchical {
                criterion["depth"] = .int(0)
            }
            return StashDBViewModel.SavedFilter(
                id: id,
                name: title,
                mode: .scenes,
                filter: nil,
                object_filter: .object([scope.rawValue: .object(criterion)]),
                ui_options: nil
            )
        default:
            return savedFilter
        }
    }

    static let recentlyReleased = TVChannel(
        kind: .recentlyReleased,
        title: "Recently Released",
        savedFilter: nil
    )

    static let recentlyAdded = TVChannel(
        kind: .recentlyAdded,
        title: "Recently Added",
        savedFilter: nil
    )

    static func performer(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.performer, id: id), title: name, savedFilter: nil)
    }

    static func studio(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.studio, id: id), title: name, savedFilter: nil)
    }

    static func tag(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.tag, id: id), title: name, savedFilter: nil)
    }

    static func group(id: String, name: String) -> TVChannel {
        TVChannel(kind: .scoped(.group, id: id), title: name, savedFilter: nil)
    }
}

@MainActor
final class TVChannelSession: ObservableObject {
    let channel: TVChannel
    let catalog = StashDBViewModel()
    let player = TVAetherPlaybackModel()

    @Published var scenes: [Scene] = []
    @Published var currentIndex = 0
    @Published var isLoading = true
    @Published var isSwitching = false
    @Published var errorMessage: String?

    private var totalCount = 0
    private var currentPage = 0
    private var isLoadingMore = false
    private var playedSceneIDs = Set<String>()
    private var skipFailures = 0
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 20
    private let maxSkipFailures = 5

    var currentScene: Scene? {
        guard scenes.indices.contains(currentIndex) else { return nil }
        return scenes[currentIndex]
    }

    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { !scenes.isEmpty }

    var indexLabel: String {
        let total = max(totalCount, scenes.count)
        guard total > 0 else { return "" }
        return "\(currentIndex + 1) / \(total)"
    }

    init(channel: TVChannel) {
        self.channel = channel
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.onPlaybackEnded = { [weak self] in
            self?.playNext()
        }
    }

    func start() {
        isLoading = true
        errorMessage = nil
        catalog.fetchScenePage(
            sortBy: channel.sortBy,
            filter: channel.sceneFilter,
            page: 1,
            perPage: pageSize
        ) { [weak self] scenes, total in
            guard let self else { return }
            self.scenes = scenes
            self.totalCount = total
            self.currentPage = 1
            self.isLoading = false
            if scenes.isEmpty {
                self.errorMessage = "No scenes in this channel"
            } else {
                self.play(index: 0)
            }
        }
    }

    /// Hält die Wiedergabe an, solange das Cover selbst noch auf dem Schirm ist
    /// (Back-Command). Die Engine bleibt stehen, damit SwiftUI die Surface nicht
    /// mitten im Dismiss abbaut.
    func stop() {
        player.onPlaybackEnded = nil
        player.suspend()
    }

    /// Kompletter Abbau nach dem Dismiss (onDisappear).
    func teardown() {
        player.onPlaybackEnded = nil
        player.clear()
    }

    func playPrevious() {
        guard canGoPrevious else { return }
        play(index: currentIndex - 1)
    }

    func playNext() {
        if currentIndex + 1 < scenes.count {
            play(index: currentIndex + 1)
            return
        }
        if scenes.count < totalCount {
            loadMore { [weak self] in
                self?.playNext()
            }
            return
        }
        guard !scenes.isEmpty else { return }
        play(index: 0)
    }

    /// Jump straight to a scene picked from the Up Next panel.
    func play(sceneAt index: Int) {
        guard index != currentIndex else { return }
        play(index: index)
    }

    /// Keeps the Up Next panel filled while the user browses ahead of playback.
    func loadMoreScenesForBrowsing() {
        loadMore(completion: nil)
    }

    private func play(index: Int) {
        guard scenes.indices.contains(index) else { return }
        let scene = scenes[index]
        currentIndex = index
        isSwitching = true
        prefetchIfNeeded()

        guard let url = scene.aetherVideoURL else {
            handleMissingStream()
            return
        }
        skipFailures = 0
        if playedSceneIDs.insert(scene.id).inserted {
            catalog.addScenePlay(sceneId: scene.id)
        }
        let subtitle = scene.studio?.name
        // One engine across the whole channel: `playNext` reuses the session
        // (`prepareForItemReplacement`) instead of rebuilding the route per scene.
        if player.hasEngine {
            player.playNext(url: url,
                            sceneId: scene.id,
                            viewModel: catalog,
                            title: scene.displayTitle,
                            subtitle: subtitle,
                            artworkURL: scene.thumbnailURL,
                            fallbackSources: scene.transcodeFallbackURLs,
                            fallbackDeclaredDuration: scene.sceneDuration)
        } else {
            player.setup(url: url,
                         sceneId: scene.id,
                         viewModel: catalog,
                         startAt: 0,
                         title: scene.displayTitle,
                         subtitle: subtitle,
                         artworkURL: scene.thumbnailURL,
                         fallbackSources: scene.transcodeFallbackURLs,
                         fallbackDeclaredDuration: scene.sceneDuration)
        }
        isSwitching = false
    }

    private func handleMissingStream() {
        skipFailures += 1
        isSwitching = false
        if skipFailures >= maxSkipFailures {
            errorMessage = "Unable to play scenes in this channel"
            return
        }
        playNext()
    }

    private func prefetchIfNeeded() {
        guard !isLoadingMore, scenes.count < totalCount, currentIndex >= scenes.count - 5 else { return }
        loadMore(completion: nil)
    }

    private func loadMore(completion: (() -> Void)?) {
        guard !isLoadingMore, scenes.count < totalCount else {
            completion?()
            return
        }
        isLoadingMore = true
        let nextPage = currentPage + 1
        catalog.fetchScenePage(
            sortBy: channel.sortBy,
            filter: channel.sceneFilter,
            page: nextPage,
            perPage: pageSize
        ) { [weak self] pageScenes, total in
            guard let self else { return }
            self.isLoadingMore = false
            self.totalCount = total
            self.currentPage = nextPage
            let existing = Set(self.scenes.map(\.id))
            self.scenes.append(contentsOf: pageScenes.filter { !existing.contains($0.id) })
            completion?()
        }
    }
}

struct TVChannelPlayerView: View {
    @StateObject private var session: TVChannelSession
    @Environment(\.dismiss) private var dismiss
    @State private var isClosing = false

    init(channel: TVChannel) {
        _session = StateObject(wrappedValue: TVChannelSession(channel: channel))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if session.player.hasEngine {
                TVAetherPlayerView(
                    model: session.player,
                    title: session.currentScene?.displayTitle ?? "Untitled",
                    subtitle: subtitle,
                    posterURL: session.currentScene?.thumbnailURL,
                    canGoPrevious: session.canGoPrevious,
                    canGoNext: session.canGoNext,
                    onPrevious: { session.playPrevious() },
                    onNext: { session.playNext() },
                    panelExtra: {
                        TVChannelUpNextView(session: session)
                            .frame(height: 360)
                    },
                    onExit: { close() }
                )
                .ignoresSafeArea()
            } else if session.isLoading || session.isSwitching {
                ProgressView()
                    .scaleEffect(1.6)
            }

            if let errorMessage = session.errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Close") { close() }
                        .font(.title3)
                }
            }
        }
        // Nur solange keine Engine läuft: der Ladezweig ist nur ein Spinner auf
        // Schwarz, ohne Fokus-Ziel erreicht die Menu-Taste `onExitCommand` nicht.
        //
        // Sobald der Player da ist, **muss** der Fokus bei ihm liegen — ein
        // fokussierbarer Container darüber nimmt ihm die Transport-Steuerung,
        // also Pause, Scrubbing und „Up Next". Im Fehlerzweig übernimmt der
        // Close-Button die Rolle des Ankers.
        .focusable(!session.player.hasEngine && session.errorMessage == nil)
        .onAppear { session.start() }
        .onDisappear { session.teardown() }
        .onExitCommand { close() }
    }

    /// Channel name plus position, shown in the player's native info panel.
    private var subtitle: String {
        let label = session.indexLabel
        return label.isEmpty ? session.channel.title : "\(session.channel.title) · \(label)"
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        session.stop()
        dismiss()
    }
}

// MARK: - Up Next panel

/// Lives in the player's info panel and lists what the channel plays next. Selecting a card
/// jumps straight to that scene instead of skipping through everything in between.
private struct TVChannelUpNextView: View {
    @ObservedObject var session: TVChannelSession

    private struct Entry: Identifiable {
        let index: Int
        let scene: Scene
        var id: String { "\(index)-\(scene.id)" }
    }

    private var entries: [Entry] {
        let start = session.currentIndex + 1
        guard start < session.scenes.count else { return [] }
        return session.scenes[start...].enumerated().map { Entry(index: start + $0.offset, scene: $0.element) }
    }

    var body: some View {
        SwiftUI.Group {
            if entries.isEmpty {
                Text("End of channel")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { session.loadMoreScenesForBrowsing() }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 30) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    session.play(sceneAt: entry.index)
                                } label: {
                                    TVSceneCardView(scene: entry.scene, width: 340, height: 191)
                                }
                                .buttonStyle(.card)

                                TVSceneCardTitleView(scene: entry.scene)
                            }
                            .frame(width: 340)
                            .onAppear {
                                if entry.index >= session.scenes.count - 3 {
                                    session.loadMoreScenesForBrowsing()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 50)
                    .padding(.vertical, 30)
                }
            }
        }
    }
}
