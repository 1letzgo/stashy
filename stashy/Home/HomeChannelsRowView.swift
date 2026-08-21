
#if !os(tvOS)
import SwiftUI

enum HomeChannelDestination: String {
    case scenes
    case clips

    var label: String {
        switch self {
        case .scenes: return "Scenes"
        case .clips: return "Clips"
        }
    }

    var icon: String {
        switch self {
        case .scenes: return "film"
        case .clips: return "play.rectangle.on.rectangle.fill"
        }
    }
}

/// A dashboard channel: a saved scene or image filter. Tapping one opens Feeds
/// in Scenes or Clips, scoped to that filter.
struct HomeChannel: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let destination: HomeChannelDestination
    let savedFilter: StashDBViewModel.SavedFilter
    let sceneSort: StashDBViewModel.SceneSortOption
    let clipSort: StashDBViewModel.ImageSortOption

    static func sceneFilter(_ filter: StashDBViewModel.SavedFilter) -> HomeChannel {
        HomeChannel(
            id: "channel.scenes.\(filter.id)",
            title: filter.name,
            subtitle: "Saved filter",
            icon: "film",
            destination: .scenes,
            savedFilter: filter,
            sceneSort: filter.resolvedSceneSort ?? .dateDesc,
            clipSort: .dateDesc
        )
    }

    static func clipFilter(_ filter: StashDBViewModel.SavedFilter) -> HomeChannel {
        HomeChannel(
            id: "channel.clips.\(filter.id)",
            title: filter.name,
            subtitle: "Saved filter",
            icon: "play.rectangle.on.rectangle.fill",
            destination: .clips,
            savedFilter: filter,
            sceneSort: .dateDesc,
            clipSort: filter.resolvedImageSort ?? .dateDesc
        )
    }
}

/// Dashboard row of channels. Not backed by the `homeRow*` caches like the other rows,
/// because a channel's artwork is a collage assembled from its own preview page.
struct HomeChannelsRowView: View {
    let config: HomeRowConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    var isFirst: Bool = false

    @State private var previews: [String: [URL]] = [:]
    @State private var isLoadingPreviews = false

    private var channels: [HomeChannel] {
        tabManager.homeChannelItems
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { item in
                guard let filter = viewModel.savedFilters[item.filterId] else { return nil }
                switch item.destination {
                case .scenes: return HomeChannel.sceneFilter(filter)
                case .clips: return HomeChannel.clipFilter(filter)
                }
            }
    }

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let cardWidth = homeCardWidth(for: config, isLarge: false, screenWidth: screenWidth)
        let cardHeight = homeCardHeight(for: config, isLarge: false, screenWidth: screenWidth)

        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.top, isFirst ? 16 : 0)

            if channels.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                channelsScrollView(cardWidth: cardWidth, cardHeight: cardHeight)
            }
        }
        .onAppear { loadChannels() }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            tabManager.syncHomeChannelItems(with: Array(newValue.values))
            loadPreviews()
        }
        .onChange(of: tabManager.homeChannelItems) { _, _ in
            previews = [:]
            isLoadingPreviews = false
            loadPreviews()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            // Saved filters are server-scoped, so previews must not survive a switch.
            previews = [:]
            isLoadingPreviews = false
        }
    }

    private var emptyMessage: String {
        if viewModel.isLoadingSavedFilters { return "Loading channels…" }
        if tabManager.homeChannelItems.isEmpty { return "No saved scene or image filters" }
        return "No channels enabled"
    }

    @ViewBuilder
    private func channelsScrollView(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(channels) { channel in
                    Button {
                        open(channel)
                    } label: {
                        HomeChannelCardView(
                            channel: channel,
                            previewURLs: previews[channel.id] ?? [],
                            width: cardWidth,
                            height: cardHeight
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(width: cardWidth)
                    .id(channel.id)
                }
            }
            .padding(.horizontal, 12)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var header: some View {
        Button {
            coordinator.selectedTab = .reels
        } label: {
            HStack(spacing: 4) {
                Text(config.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ channel: HomeChannel) {
        switch channel.destination {
        case .scenes:
            coordinator.navigateToReelsChannel(filter: channel.savedFilter, sort: channel.sceneSort)
        case .clips:
            coordinator.navigateToReelsClipsChannel(filter: channel.savedFilter, sort: channel.clipSort)
        }
    }

    private func loadChannels() {
        if viewModel.savedFilters.isEmpty && !viewModel.isLoadingSavedFilters {
            viewModel.fetchSavedFilters { _ in
                tabManager.syncHomeChannelItems(with: Array(viewModel.savedFilters.values))
                loadPreviews()
            }
        } else {
            tabManager.syncHomeChannelItems(with: Array(viewModel.savedFilters.values))
        }
        loadPreviews()
    }

    private func loadPreviews() {
        guard !isLoadingPreviews else { return }
        let pending = channels.filter { previews[$0.id] == nil }
        guard !pending.isEmpty else { return }
        isLoadingPreviews = true
        loadPreview(at: 0, from: pending)
    }

    /// One request at a time. Firing every channel together races Stash's SQLite lock —
    /// the first card in the row is the one that usually comes back empty.
    private func loadPreview(at index: Int, from pending: [HomeChannel], retrying: Bool = false) {
        guard index < pending.count else {
            isLoadingPreviews = false
            return
        }
        let channel = pending[index]
        switch channel.destination {
        case .scenes:
            viewModel.fetchScenePage(sortBy: channel.sceneSort, filter: channel.savedFilter, page: 1, perPage: 4) { scenes, _ in
                finishPreview(urls: scenes.compactMap(\.thumbnailURL), at: index, from: pending, retrying: retrying)
            }
        case .clips:
            viewModel.fetchClipPage(sortBy: channel.clipSort, filter: channel.savedFilter, page: 1, perPage: 4) { images, _ in
                finishPreview(urls: images.compactMap(\.thumbnailURL), at: index, from: pending, retrying: retrying)
            }
        }
    }

    private func finishPreview(urls: [URL], at index: Int, from pending: [HomeChannel], retrying: Bool) {
        if urls.isEmpty && !retrying {
            loadPreview(at: index, from: pending, retrying: true)
            return
        }
        previews[pending[index].id] = urls
        loadPreview(at: index + 1, from: pending)
    }
}

// MARK: - Channel card

private struct HomeChannelCardView: View {
    let channel: HomeChannel
    let previewURLs: [URL]
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(width: width, height: height)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack(alignment: .top, spacing: 6) {
                    badge(icon: channel.icon, text: channel.subtitle)
                    Spacer(minLength: 0)
                    badge(icon: channel.destination.icon, text: channel.destination.label)
                }
                Spacer()
            }
            .padding(8)

            Text(channel.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .padding(8)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(appearanceManager.tintColor)
            Text(text.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
        .fixedSize()
    }

    @ViewBuilder
    private var artwork: some View {
        if previewURLs.isEmpty {
            placeholder
        } else if previewURLs.count == 1 {
            thumbnail(previewURLs[0])
        } else {
            HStack(spacing: 1) {
                ForEach(Array(previewURLs.prefix(4).enumerated()), id: \.offset) { _, url in
                    thumbnail(url)
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL) -> some View {
        CustomAsyncImage(url: url) { loader in
            if let image = loader.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .overlay(
                Image(systemName: channel.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            )
    }
}
#endif
