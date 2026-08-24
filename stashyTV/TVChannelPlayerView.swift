//
//  TVChannelPlayerView.swift
//  stashyTV
//
//  Continuous channel playback with previous / next skip.
//

import SwiftUI
import AVKit
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
            return StashDBViewModel.SavedFilter(
                id: id,
                name: title,
                mode: .scenes,
                filter: nil,
                object_filter: .object([
                    scope.rawValue: .object([
                        "modifier": .string("INCLUDES"),
                        "value": .array([.string(entityID)])
                    ])
                ]),
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
    let player = TVPlayerViewModel()

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
    /// (Back-Command). Der Player bleibt veröffentlicht, damit SwiftUI die
    /// AVPlayerViewController-Hierarchie nicht mitten im Dismiss abbaut.
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
        player.saveProgress()
        prefetchIfNeeded()

        catalog.fetchSceneStreams(sceneId: scene.id) { [weak self] streams in
            guard let self else { return }
            let quality = ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
            guard let url = tvPlaybackURL(for: scene, streams: streams, quality: quality) else {
                self.handleMissingStream()
                return
            }
            self.skipFailures = 0
            if self.playedSceneIDs.insert(scene.id).inserted {
                self.catalog.addScenePlay(sceneId: scene.id)
            }
            self.player.setupPlayer(url: url, sceneId: scene.id, viewModel: self.catalog, startAt: 0)
            self.isSwitching = false
            self.prefetchNextStreams()
        }
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

    private func prefetchNextStreams() {
        let next = currentIndex + 1
        guard scenes.indices.contains(next) else { return }
        catalog.fetchSceneStreams(sceneId: scenes[next].id) { _ in }
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

            if let player = session.player.player {
                TVChannelVideoPlayer(
                    player: player,
                    session: session,
                    sceneID: session.currentScene?.id,
                    title: session.currentScene?.title ?? "Untitled",
                    subtitle: subtitle,
                    canGoPrevious: session.canGoPrevious,
                    canGoNext: session.canGoNext,
                    onPrevious: { session.playPrevious() },
                    onNext: { session.playNext() }
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

// MARK: - Player with transport bar skip controls

/// Wraps `AVPlayerViewController` so Previous / Next live in the native transport bar:
/// they appear and disappear together with the rest of the playback controls and are
/// reachable with the remote, which a SwiftUI `VideoPlayer` overlay cannot do.
private struct TVChannelVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let session: TVChannelSession
    let sceneID: String?
    let title: String
    let subtitle: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player

        let coordinator = context.coordinator
        coordinator.previousAction = UIAction(
            title: "Previous",
            image: UIImage(systemName: "backward.end.fill")
        ) { [weak coordinator] _ in coordinator?.onPrevious() }
        coordinator.nextAction = UIAction(
            title: "Next",
            image: UIImage(systemName: "forward.end.fill")
        ) { [weak coordinator] _ in coordinator?.onNext() }

        // Upcoming scenes as a tab in the native info panel (swipe down during playback).
        let upNext = UIHostingController(rootView: TVChannelUpNextView(session: session))
        upNext.title = "Up Next"
        upNext.view.backgroundColor = .clear
        upNext.preferredContentSize = CGSize(width: 0, height: 360)
        controller.customInfoViewControllers = [upNext]

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPrevious = onPrevious
        coordinator.onNext = onNext
        coordinator.metadata = metadataItems

        if controller.player !== player {
            controller.player = player
            coordinator.appliedSceneID = nil
        }
        coordinator.observe(player: player)

        if coordinator.appliedSceneID != sceneID {
            coordinator.appliedSceneID = sceneID
            coordinator.applyPresentation(to: controller.player?.currentItem)
        }

        guard let previousAction = coordinator.previousAction,
              let nextAction = coordinator.nextAction else { return }

        // Reassigning the array moves focus back to the start of the transport bar,
        // so only rebuild it when the enabled state actually changes.
        let enabled = [canGoPrevious, canGoNext]
        if coordinator.appliedEnabledState != enabled {
            coordinator.appliedEnabledState = enabled
            previousAction.attributes = canGoPrevious ? [] : .disabled
            nextAction.attributes = canGoNext ? [] : .disabled
            controller.transportBarCustomMenuItems = [previousAction, nextAction]
        }
    }

    private func metadataItems() -> [AVMetadataItem] {
        [
            metadataItem(identifier: .commonIdentifierTitle, value: title),
            metadataItem(identifier: .iTunesMetadataTrackSubTitle, value: subtitle)
        ]
    }

    private func metadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    final class Coordinator {
        var onPrevious: () -> Void = {}
        var onNext: () -> Void = {}
        var metadata: () -> [AVMetadataItem] = { [] }
        var previousAction: UIAction?
        var nextAction: UIAction?
        var appliedSceneID: String?
        var appliedEnabledState: [Bool]?

        private weak var observedPlayer: AVPlayer?
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?

        /// Each scene arrives as a fresh player item, and SwiftUI updates can run before the
        /// swap. Driving the item setup from the swap itself keeps title and chapter handling
        /// tied to the item that is actually playing.
        func observe(player: AVPlayer) {
            guard observedPlayer !== player else { return }
            observedPlayer = player
            itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                let item = player.currentItem
                DispatchQueue.main.async { self?.applyPresentation(to: item) }
            }
        }

        func applyPresentation(to item: AVPlayerItem?) {
            guard let item else { return }
            item.externalMetadata = metadata()
            clearChapters(on: item)
            // Chapter markers can surface only once the asset finished loading.
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                DispatchQueue.main.async { self?.clearChapters(on: item) }
            }
        }

        /// The info panel shows a Chapters tab as soon as the item carries navigation markers.
        /// Channel playback only wants Info and Up Next.
        private func clearChapters(on item: AVPlayerItem) {
            guard !item.navigationMarkerGroups.isEmpty else { return }
            item.navigationMarkerGroups = []
        }
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
