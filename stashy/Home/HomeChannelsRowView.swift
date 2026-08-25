
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
    let destination: HomeChannelDestination
    let savedFilter: StashDBViewModel.SavedFilter
    let sceneSort: StashDBViewModel.SceneSortOption
    let clipSort: StashDBViewModel.ImageSortOption

    static func sceneFilter(_ filter: StashDBViewModel.SavedFilter) -> HomeChannel {
        HomeChannel(
            id: "channel.scenes.\(filter.id)",
            title: filter.name,
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
            destination: .clips,
            savedFilter: filter,
            sceneSort: .dateDesc,
            clipSort: filter.resolvedImageSort ?? .dateDesc
        )
    }
}

/// Dashboard row of channels. Cards show the channel's category logo (scenes / clips)
/// on a square tile — no thumbnails, so the row needs no per-channel preview fetch.
struct HomeChannelsRowView: View {
    let config: HomeRowConfig
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    var isFirst: Bool = false

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
            }
        } else {
            tabManager.syncHomeChannelItems(with: Array(viewModel.savedFilters.values))
        }
    }
}

// MARK: - Channel card

private struct HomeChannelCardView: View {
    let channel: HomeChannel
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            logoBackdrop

            VStack {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    badge(icon: channel.destination.icon, text: channel.destination.label)
                }
                Spacer(minLength: 0)
            }
            .padding(8)

            Text(channel.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(8)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    /// Category logo on the shared card surface — replaces the former thumbnail collage.
    private var logoBackdrop: some View {
        ZStack {
            Color.secondaryAppBackground

            Image(systemName: channel.destination.icon)
                .font(.system(size: min(width, height) * 0.34, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
                // Logo sits slightly above center so the two-line title never crowds it.
                .offset(y: -height * 0.06)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(appearanceManager.tintColor)
            Text(text.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // Page colour reads as a recess on the card surface (the old black capsule
        // was built for a photo backdrop).
        .background(Color.appBackground)
        .clipShape(Capsule())
        .fixedSize()
    }
}
#endif
