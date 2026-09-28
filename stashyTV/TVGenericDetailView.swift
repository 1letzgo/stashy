import SwiftUI

struct TVGenericDetailView<Item: TVDetailItem, Info: View, Content: View>: View {
    let item: Item?
    let isLoading: Bool
    let heroAspectRatio: CGFloat
    let placeholderSystemImage: String
    let heroImageOverride: AnyView?
    /// When set, the header offers continuous playback of everything in this scope.
    let channel: TVChannel?

    @State private var playingChannel: TVChannel?
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @FocusState private var emptyFocus: Bool
    /// Start focus in the header. Without it tvOS put the first scene card in focus and
    /// scrolled the page down on open, cutting off the name and image.
    @FocusState private var headerFocus: Bool
    /// The invisible header anchor for pages without a channel button. Its own state: with
    /// the button and the container bound to one `@FocusState`, tvOS could neither claim
    /// the header programmatically nor move focus back up from the scene grid.
    @FocusState private var headerAnchorFocus: Bool
    /// Set once focus has left the header; from then on loading never pulls focus back.
    @State private var headerFocusReleased = false
    @Environment(\.tvContentWidth) private var contentWidth

    private var sceneSpec: TVGridSpec { .scenes }
    @Environment(\.dismiss) private var dismiss

    /// Der Kanal-Button ist im Leer-Zustand oft das einzige fokussierbare
    /// Element — fehlt er, muss der Zurück-Button den Fokus übernehmen.
    private var showsChannelButton: Bool { channel != nil && stashyPlus.isUnlocked }

    // Scenes related
    let scenes: [Scene]
    let isLoadingScenes: Bool
    let totalScenes: Int
    let hasMoreScenes: Bool
    let loadMoreScenes: () -> Void
    
    @ViewBuilder let infoGrid: (Item) -> Info
    @ViewBuilder let additionalContent: () -> Content

    init(
        item: Item?,
        isLoading: Bool,
        heroAspectRatio: CGFloat,
        placeholderSystemImage: String,
        heroImageOverride: AnyView? = nil,
        channel: TVChannel? = nil,
        scenes: [Scene],
        isLoadingScenes: Bool,
        totalScenes: Int,
        hasMoreScenes: Bool,
        loadMoreScenes: @escaping () -> Void,
        @ViewBuilder infoGrid: @escaping (Item) -> Info,
        @ViewBuilder additionalContent: @escaping () -> Content
    ) {
        self.item = item
        self.isLoading = isLoading
        self.heroAspectRatio = heroAspectRatio
        self.placeholderSystemImage = placeholderSystemImage
        self.heroImageOverride = heroImageOverride
        self.channel = channel
        self.scenes = scenes
        self.isLoadingScenes = isLoadingScenes
        self.totalScenes = totalScenes
        self.hasMoreScenes = hasMoreScenes
        self.loadMoreScenes = loadMoreScenes
        self.infoGrid = infoGrid
        self.additionalContent = additionalContent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header (Hero Section)
                HStack(alignment: .top, spacing: 50) {
                    // Thumbnail / Profile Image
                    heroImage
                    
                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item?.name ?? "")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let channel, stashyPlus.isUnlocked {
                            Button {
                                playingChannel = channel
                            } label: {
                                Label("Play as Channel", systemImage: "play.tv.fill")
                            }
                            .focused($headerFocus)
                        } else {
                            // Without the channel button the header has nothing focusable;
                            // this invisible anchor keeps the opening focus (and scroll) at
                            // the top. It is its own view on purpose: `.focusable(false)` on
                            // the header container disabled focus for the whole subtree, so
                            // Up from the scene grid could never land on the channel button.
                            Color.clear
                                .frame(width: 1, height: 1)
                                .focusable()
                                .focusEffectDisabled()
                                .focused($headerAnchorFocus)
                                .accessibilityHidden(true)
                        }

                        if isLoading {
                            ProgressView().scaleEffect(1.2)
                        } else if let item = item {
                            VStack(alignment: .leading, spacing: 14) {
                                if let details = item.details, !details.isEmpty {
                                    Text(details)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(6)
                                }

                                Divider()
                                    .background(Color.secondary)

                                infoGrid(item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 40)
                // One focus region: Up from any grid column lands on the channel button even
                // where the button and the column do not overlap horizontally.
                .focusSection()

                // Additional Content (e.g. more metadata or specific views)
                additionalContent()

                // Scenes Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill")
                            .font(.title3)
                            .foregroundColor(AppearanceManager.shared.tintColor)
                        Text("Scenes")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if totalScenes > 0 {
                            Text("\(totalScenes)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 60)

                    if isLoadingScenes && scenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                        // Not focusable: the header (channel button or anchor) already gives
                        // the Menu key a target while loading. A focusable spinner took the
                        // opening focus, and when the grid replaced it tvOS moved focus to the
                        // first scene card and scrolled the page down.
                    } else if scenes.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No scenes found")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                // Fokus-Anker. Ohne ihn hat die Detailseite einer
                                // leeren Group/Tag/Studio gar kein fokussierbares
                                // Element, die Menu-Taste erreicht
                                // `tvExitDismissable` nicht und man kommt nicht
                                // mehr heraus. Gleiches Muster wie in
                                // `TVGalleryDetailView`.
                                Button("Back") { dismiss() }
                                    .font(.title3)
                                    .focused($emptyFocus)
                                    .padding(.top, 8)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 60)
                        .onAppear {
                            guard !showsChannelButton else { return }
                            emptyFocus = true
                        }
                    } else {
                        LazyVGrid(columns: sceneSpec.columns(for: contentWidth), spacing: sceneSpec.spacing) {
                            ForEach(scenes) { scene in
                                VStack(alignment: .leading, spacing: 10) {
                                    TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                        TVSceneCardView(scene: scene)
                                    }
                                    
                                    TVSceneCardTitleView(scene: scene)
                                }
                                .frame(width: sceneSpec.columnWidth)
                                .onAppear {
                                    if scene.id == scenes.last?.id && hasMoreScenes {
                                        loadMoreScenes()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, sceneSpec.horizontalPadding)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .background(Color.appBackground)
        .defaultFocus($headerFocus, true)
        // `defaultFocus` only applies to the first layout. When the item or its scenes
        // arrive later, tvOS re-picks focus and lands on the first scene card, scrolling
        // the page down — so re-claim the header until the user has moved away from it.
        .onChange(of: headerFocus) { wasFocused, isFocused in
            if wasFocused && !isFocused { headerFocusReleased = true }
        }
        .onChange(of: headerAnchorFocus) { wasFocused, isFocused in
            if wasFocused && !isFocused { headerFocusReleased = true }
        }
        .onAppear { claimHeaderFocusIfUntouched() }
        .onChange(of: showsChannelButton) { _, _ in claimHeaderFocusIfUntouched() }
        .onChange(of: isLoading) { _, _ in claimHeaderFocusIfUntouched() }
        .onChange(of: scenes.isEmpty) { _, _ in claimHeaderFocusIfUntouched() }
        .dismissOnAppLock { playingChannel = nil }
        .fullScreenCover(item: $playingChannel, onDismiss: {
            playingChannel = nil
        }) { channel in
            TVChannelPlayerView(channel: channel)
        }
    }

    private func claimHeaderFocusIfUntouched() {
        guard !headerFocusReleased else { return }
        DispatchQueue.main.async {
            if showsChannelButton { headerFocus = true } else { headerAnchorFocus = true }
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        // Reine Anzeige — früher ein leerer `Button { } .buttonStyle(.card)`,
        // der auf tvOS Parallax/Card-Scale erzeugte und Selektierbarkeit
        // suggerierte, ohne dass beim Select etwas passierte. Jetzt nicht mehr
        // fokusierbar.
        Group {
            if let heroImageOverride {
                heroImageOverride
            } else
            if let thumbnailURL = item?.thumbnailURL {
                CustomAsyncImage(url: thumbnailURL) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.08))
                            .overlay(ProgressView())
                    } else {
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .focusable(false)
        .frame(width: 400 * heroAspectRatio, height: 400)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
            )
    }
}
