
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
    /// The user's own SF Symbol (long press on Home), nil = the category logo.
    var customIcon: String? = nil

    /// Key of the matching `HomeChannelItemConfig`.
    var itemId: String { "\(destination.rawValue).\(savedFilter.id)" }
    var logoIcon: String { customIcon ?? destination.icon }

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
                var channel: HomeChannel
                switch item.destination {
                case .scenes: channel = HomeChannel.sceneFilter(filter)
                case .clips: channel = HomeChannel.clipFilter(filter)
                }
                channel.customIcon = item.icon
                return channel
            }
    }

    @Environment(\.homeContentWidth) private var screenWidth
    @State private var iconPickerChannel: HomeChannel?
    @State private var menuChannelId: String?
    @State private var pressedChannelId: String?

    var body: some View {
        let cardWidth = homeCardWidth(for: config, isLarge: false, screenWidth: screenWidth)
        let cardHeight = homeCardHeight(for: config, isLarge: false, screenWidth: screenWidth)

        VStack(alignment: .leading, spacing: 12) {
            header

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
        .sheet(item: $iconPickerChannel) { channel in
            HomeChannelIconPicker(channel: channel) { icon in
                tabManager.setHomeChannelIcon(channel.itemId, icon: icon)
            }
        }
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
                    HomeChannelCardView(
                        channel: channel,
                        width: cardWidth,
                        height: cardHeight,
                        isPressed: pressedChannelId == channel.id
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .onTapGesture { open(channel) }
                    // Long press: the card tints in its own shape, then a compact popup opens on
                    // it. Not `.contextMenu` (lifts a rounded platter) and not `Menu` (grows a
                    // round blob out of a card this size).
                    .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                        withAnimation(.easeOut(duration: 0.15)) {
                            pressedChannelId = pressing ? channel.id : nil
                        }
                    }) {
                        HapticManager.medium()
                        menuChannelId = channel.id
                    }
                    .popover(isPresented: Binding(
                        get: { menuChannelId == channel.id },
                        set: { if !$0 { menuChannelId = nil } }
                    ), arrowEdge: .bottom) {
                        channelMenu(channel)
                            .presentationCompactAdaptation(.popover)
                    }
                    // Same ··· menu as below a For You card, here inside the card.
                    .overlay(alignment: .bottomTrailing) {
                        Menu {
                            channelMenuItems(channel)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                        .padding(.bottom, 4)
                        .accessibilityLabel("Channel options")
                    }
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
    private func channelMenuItems(_ channel: HomeChannel) -> some View {
        Button {
            iconPickerChannel = channel
        } label: {
            Label("Change Icon…", systemImage: "square.grid.2x2")
        }
        if channel.customIcon != nil {
            Button {
                tabManager.setHomeChannelIcon(channel.itemId, icon: nil)
            } label: {
                Label("Reset Icon", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// The long-press popup: the same rows as the ··· menu.
    private func channelMenu(_ channel: HomeChannel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Change Icon…", systemImage: "square.grid.2x2") {
                menuChannelId = nil
                // The sheet waits until the popup is gone, or it never shows.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    iconPickerChannel = channel
                }
            }
            if channel.customIcon != nil {
                Divider()
                menuRow("Reset Icon", systemImage: "arrow.uturn.backward") {
                    menuChannelId = nil
                    tabManager.setHomeChannelIcon(channel.itemId, icon: nil)
                }
            }
        }
        .frame(minWidth: 220)
        .padding(.vertical, 6)
    }

    private func menuRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Plain label, not a link: the row's cards each open their own channel, and a header that
    /// jumped to Feeds in general only ever led somewhere the user did not ask for.
    @ViewBuilder
    private var header: some View {
        HStack(spacing: 4) {
            Text(config.title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
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
    /// Held for a long press: tinted in the accent colour, same shape.
    var isPressed: Bool = false
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            logoBackdrop

            appearanceManager.tintColor
                .opacity(isPressed ? 0.3 : 0)

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
                // Room for the ··· menu in the bottom-right corner.
                .padding(.trailing, 28)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    /// Category logo on the shared card surface — replaces the former thumbnail collage.
    private var logoBackdrop: some View {
        ZStack {
            Color.secondaryAppBackground

            Image(systemName: channel.logoIcon)
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
                .font(.system(size: 11, weight: .bold))
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

// MARK: - Icon picker

/// Grid of SF Symbols for one channel. Picking one saves it at once and closes the sheet.
private struct HomeChannelIconPicker: View {
    let channel: HomeChannel
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared

    /// SF Symbols by theme; every name checked against the system symbol set.
    static let groups: [(title: String, symbols: [String])] = [
        ("Media", ["film", "film.stack", "play.rectangle.on.rectangle.fill", "play.circle.fill", "play.square.stack.fill", "tv.fill", "video.fill", "camera.fill", "camera.aperture", "photo.fill", "photo.stack.fill", "photo.on.rectangle.angled", "rectangle.stack.fill", "square.stack.3d.up.fill", "popcorn.fill", "movieclapper.fill", "ticket.fill", "sparkles.tv.fill", "livephoto", "camera.macro", "viewfinder"]),
        ("Favorites", ["star.fill", "heart.fill", "heart.circle.fill", "suit.heart.fill", "bolt.heart.fill", "flame.fill", "sparkles", "crown.fill", "trophy.fill", "rosette", "medal.fill", "hand.thumbsup.fill", "bookmark.fill", "tag.fill", "flag.fill", "pin.fill", "diamond.fill", "seal.fill", "checkmark.seal.fill", "star.circle.fill"]),
        ("Mood", ["face.smiling", "face.smiling.inverse", "eyes", "eye.fill", "mouth.fill", "nose.fill", "ear.fill", "hand.raised.fill", "hands.clap.fill", "hand.wave.fill", "theatermasks.fill", "wand.and.stars", "moon.zzz.fill", "bubbles.and.sparkles.fill", "heart.text.square.fill"]),
        ("Nature", ["sun.max.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill", "snowflake", "drop.fill", "leaf.fill", "tree.fill", "flame", "tornado", "rainbow", "sunset.fill", "water.waves", "mountain.2.fill", "globe.europe.africa.fill", "pawprint.fill", "bird.fill", "fish.fill", "ladybug.fill", "tortoise.fill", "hare.fill", "cat.fill", "dog.fill"]),
        ("People", ["person.fill", "person.2.fill", "person.3.fill", "figure.stand", "figure.dance", "figure.walk", "figure.run", "figure.yoga", "figure.pool.swim", "figure.strengthtraining.traditional", "figure.2.arms.open", "figure.and.child.holdinghands", "person.crop.circle.fill", "person.badge.plus", "figure.socialdance", "figure.mind.and.body"]),
        ("Places", ["house.fill", "bed.double.fill", "sofa.fill", "shower.fill", "bathtub.fill", "car.fill", "airplane", "tram.fill", "sailboat.fill", "beach.umbrella.fill", "tent.fill", "building.2.fill", "building.columns.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "party.popper.fill", "balloon.2.fill"]),
        ("Things", ["music.note", "headphones", "mic.fill", "gamecontroller.fill", "lock.fill", "key.fill", "gift.fill", "clock.fill", "calendar", "hourglass", "shuffle", "repeat", "infinity", "bell.fill", "envelope.fill", "paperplane.fill", "lightbulb.fill", "dice.fill", "puzzlepiece.fill", "paintbrush.fill", "scissors", "gym.bag.fill", "dumbbell.fill", "tshirt.fill", "shoe.fill", "eyeglasses", "sunglasses.fill", "crown", "gift"]),
        ("Shapes", ["circle.fill", "square.fill", "triangle.fill", "hexagon.fill", "octagon.fill", "capsule.fill", "seal", "circle.hexagongrid.fill", "square.grid.2x2.fill", "circle.grid.3x3.fill", "staroflife.fill", "burst.fill", "atom", "number", "questionmark", "exclamationmark.triangle.fill"])
    ]

    private var current: String { channel.logoIcon }

    private func symbolButton(_ symbol: String) -> some View {
        Button {
            // The category logo itself counts as "no custom icon".
            onPick(symbol == channel.destination.icon ? nil : symbol)
            dismiss()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(symbol == current ? Color.onAppTint : appearanceManager.tintColor)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .fill(symbol == current ? appearanceManager.tintColor : Color.secondaryAppBackground)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(symbol == current ? .isSelected : [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Self.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle(channel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if channel.customIcon != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Reset") {
                            onPick(nil)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
