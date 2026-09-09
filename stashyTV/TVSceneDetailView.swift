//
//  TVSceneDetailView.swift
//  stashyTV
//
//  Scene detail for tvOS — Netflix/Prime style
//

import SwiftUI
import Combine

struct TVSceneDetailView: View {
    let sceneId: String

    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @StateObject private var playerModel = TVAetherPlaybackModel()
    @State private var sceneDetail: Scene?
    @State private var isLoadingDetail = true
    @State private var hasAddedPlay = false
    @State private var showingRatingPicker = false
    @FocusState private var focusedHeroAction: HeroAction?

    private enum HeroAction: Hashable {
        case play
        case restart
    }

    /// Same idea as iOS `ScenesView`: list/detail only treat transport/config as “connection” errors.
    private var hasValidActiveServer: Bool {
        guard let config = configManager.activeConfig else { return false }
        return config.hasValidConfig
    }

    private var shouldShowConnectionFailure: Bool {
        let msg = viewModel.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !msg.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            
            // Full Screen Hero Background
            if let scene = sceneDetail {
                heroBackground(scene: scene)
            }
            
            ScrollView(showsIndicators: false) {
                if !hasValidActiveServer {
                    TVConnectionErrorView(
                        title: "Server not reachable",
                        subtitle: "Add a server in Settings.",
                        onRetry: retryConnectionAndReload
                    )
                } else if isLoadingDetail {
                    VStack {
                        Spacer(minLength: 400)
                        ProgressView().scaleEffect(1.5)
                        Spacer(minLength: 400)
                    }
                    .frame(maxWidth: .infinity)
                    // Fokus-Ziel für die Menu-Taste während des Ladens.
                    .focusable()
                } else if let scene = sceneDetail {
                    VStack(alignment: .leading, spacing: 50) {
                        
                        // Hero Content Overlay (Title, Metadata, Actions)
                        heroContent(scene: scene)
                            .padding(.top, 120) // Push content down over the background
                        
                        // Markers
                        if let markers = scene.sceneMarkers, !markers.isEmpty {
                            markersSection(markers: markers, scene: scene)
                                .focusSection()
                        }

                        // Metadata Tags
                        if let tags = scene.tags, !tags.isEmpty {
                            tagsSection(tags: tags)
                                .focusSection()
                        }

                        // Performers (Cast)
                        if !scene.performers.isEmpty {
                            performersSection(performers: scene.performers)
                                .focusSection()
                        }

                        // Studio
                        if let studio = scene.studio {
                            studioSection(studio: studio)
                                .focusSection()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 60)
                    .padding(.bottom, 100)
                } else if shouldShowConnectionFailure {
                    TVConnectionErrorView(
                        title: "Server not reachable",
                        subtitle: viewModel.errorMessage,
                        onRetry: retryConnectionAndReload
                    )
                } else {
                    sceneNotFoundView
                }
            }
        }
        .navigationTitle("")
        .onAppear {
            if hasValidActiveServer {
                loadData()
            } else {
                isLoadingDetail = false
            }
        }
        .onPlayPauseCommand {
            // On the detail surface: start playback. Native VideoPlayer owns Play/Pause in cover.
            guard let scene = sceneDetail, !playerModel.isShowingPlayer else { return }
            startPlayback(for: scene)
        }
        .defaultFocus($focusedHeroAction, .play)
        .fullScreenCover(isPresented: $playerModel.isShowingPlayer, onDismiss: {
            playerModel.clear()
            loadData()
        }) {
            TVAetherPlayerView(
                model: playerModel,
                title: sceneDetail?.displayTitle ?? "Untitled Scene",
                subtitle: sceneDetail?.studio?.name ?? "",
                posterURL: sceneDetail?.thumbnailURL,
                onDisappear: {
                    // Failsafe — save progress falls fullScreenCover ohne `onDismiss` weggeht.
                    playerModel.saveProgress()
                }
            )
        }
    }

    /// Scene missing or GraphQL returned null without a network error (e.g. deleted on server).
    private var sceneNotFoundView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 300)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Failed to load scene details")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Retry") {
                retryConnectionAndReload()
            }
            .font(.title3)
            Spacer(minLength: 300)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data Loading

    /// Re-test reachability then reload — mirrors iOS list screens calling `performSearch` after `ConnectionErrorView`.
    private func retryConnectionAndReload() {
        viewModel.testConnection()
        loadData()
    }

    private func loadData() {
        guard hasValidActiveServer else {
            isLoadingDetail = false
            return
        }

        isLoadingDetail = true

        viewModel.fetchSceneDetails(sceneId: sceneId) { scene in
            self.sceneDetail = scene
            self.isLoadingDetail = false
        }
    }

    // MARK: - Hero Sections

    @ViewBuilder
    private func heroBackground(scene: Scene) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if let thumbnailURL = scene.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Color.appBackground
                        }
                    }
                } else {
                     Color.appBackground
                }

                // Subtle overall darkening
                Color.black.opacity(0.1)

                // Complex Gradient Overlay to fade into the black background and side
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.9), Color.appBackground.opacity(0.5), .clear, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                
                // Bottom linear gradient to ground the content
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.9), Color.appBackground.opacity(0.4), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func heroContent(scene: Scene) -> some View {
        let hasStream = scene.aetherVideoURL != nil
        let isWaiting = isLoadingDetail
        let hasProgress = (scene.resumeTime ?? 0) > 0
        
        VStack(alignment: .leading, spacing: 16) {
            
            // 1. Studio/Category (Optional top line)
            if let studio = scene.studio {
                Text(studio.name.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .tracking(2)
            }

            // 2. Main Title
            Text(scene.displayTitle ?? "Untitled Scene")
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 3. Synopsis / Details (Optional, below title)
            if let details = scene.details, !details.isEmpty {
                Text(details)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .frame(maxWidth: 1000, alignment: .leading)
            }

            // 4. Metadata Line (Duration, Res) + Progress Bar
            HStack(spacing: 24) {
                if let duration = scene.sceneDuration, duration > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(formattedDuration(duration))
                    }
                    .font(.headline)
                }

                if let resolution = resolutionString(for: scene) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                        Text(resolution)
                    }
                    .font(.headline)
                }

                // Rating Pill
                if let rating100 = scene.rating100, rating100 > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", Double(rating100) / 20.0))
                    }
                    .font(.headline)
                }

                // O-Count Pill
                if let oCounter = scene.oCounter, oCounter > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.circle")
                        Text("\(oCounter)")
                    }
                    .font(.headline)
                }
                
                // Progress Bar inline with metadata
                if let resumeTime = scene.resumeTime, resumeTime > 0,
                   let duration = scene.sceneDuration, duration > 0,
                   duration.isFinite, resumeTime.isFinite {
                    let progress = max(0.0, min(1.0, resumeTime / duration))
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.headline)
                        
                        GeometryReader { geo in
                            let safeWidth: CGFloat = (geo.size.width.isFinite && geo.size.width > 0) ? geo.size.width : 0
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.3))
                                Rectangle().fill(AppearanceManager.shared.tintColor)
                                    .frame(width: safeWidth * CGFloat(progress))
                            }
                        }
                        .frame(width: 200, height: 4)
                        .clipShape(Capsule())
                    }
                }
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 8)

            // 5. Action Buttons — playback group | meta group
            HStack(alignment: .center, spacing: 20) {
                heroCardButton(focus: .play, disabled: !hasStream || (isWaiting && !hasStream)) {
                    startPlayback(for: scene)
                } label: {
                    heroActionLabel(
                        icon: isWaiting && !hasStream ? nil : (hasStream ? "play.fill" : "xmark.circle"),
                        title: {
                            if isWaiting && !hasStream { return "Loading" }
                            if hasStream { return hasProgress ? "Resume" : "Play" }
                            return "No Stream"
                        }(),
                        showProgress: isWaiting && !hasStream
                    )
                }

                if hasProgress {
                    heroCardButton(focus: .restart) {
                        startPlayback(for: scene, at: 0)
                    } label: {
                        heroActionLabel(icon: "arrow.counterclockwise", title: "Restart")
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 3, height: Self.heroButtonHeight)
                    .padding(.horizontal, 8)
                    .focusable(false)
                    .accessibilityHidden(true)

                heroCardButton {
                    viewModel.incrementOCounter(sceneId: scene.id) { newCount in
                        guard let count = newCount else { return }
                        if let current = sceneDetail {
                            sceneDetail = current.withOCounter(count)
                        }
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SceneOCounterUpdated"),
                            object: nil,
                            userInfo: ["sceneId": scene.id, "oCounter": count]
                        )
                    }
                } label: {
                    heroActionLabel(icon: "heart.circle.fill", title: "\(scene.oCounter ?? 0)")
                }

                heroCardButton {
                    showingRatingPicker = true
                } label: {
                    heroActionLabel(icon: "star.fill", title: ratingLabel(for: scene))
                }
                .confirmationDialog("Rating", isPresented: $showingRatingPicker, titleVisibility: .visible) {
                    ForEach((0...5).reversed(), id: \.self) { stars in
                        Button(stars == 0 ? "No Rating" : String(repeating: "★", count: stars)) {
                            let value: Int? = (stars == 0) ? nil : (stars * 20)
                            viewModel.updateSceneRating(sceneId: scene.id, rating100: value) { _ in
                                if let current = sceneDetail {
                                    sceneDetail = current.withRating(value)
                                }
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("SceneRatingUpdated"),
                                    object: nil,
                                    userInfo: ["sceneId": scene.id, "rating100": value as Any]
                                )
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let heroButtonWidth: CGFloat = 250
    private static let heroButtonHeight: CGFloat = 72

    @ViewBuilder
    private func heroCardButton(
        focus: HeroAction? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let button = Button(action: action, label: label)
            .frame(width: Self.heroButtonWidth, height: Self.heroButtonHeight)
            .buttonStyle(.card)
            .disabled(disabled)
        if let focus {
            button.focused($focusedHeroAction, equals: focus)
        } else {
            button
        }
    }

    @ViewBuilder
    private func heroActionLabel(icon: String?, title: String, showProgress: Bool = false) -> some View {
        HStack(spacing: 12) {
            if showProgress {
                ProgressView()
            } else if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .imageScale(.medium)
            }
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func currentRatingStars(_ scene: Scene) -> Int {
        guard let r = scene.rating100, r > 0 else { return 0 }
        return Int(round(Double(r) / 20.0))
    }

    private func ratingLabel(for scene: Scene) -> String {
        let stars = currentRatingStars(scene)
        return stars == 0 ? "Rate" : "\(stars)/5"
    }

    private func resolutionString(for scene: Scene) -> String? {
        guard let file = scene.files?.first, let h = file.height else { return nil }
        if h >= 2160 { return "4K" }
        if h >= 1080 { return "HD" }
        if h >= 720 { return "720p" }
        return "SD"
    }

    // MARK: - Playback

    private func startPlayback(for scene: Scene, at timestamp: Double? = nil) {
        let startTime = timestamp ?? scene.resumeTime ?? 0
        AppLog.debug("🎬 TV: Starting playback for scene \(scene.id) at \(startTime)s")

        if !hasAddedPlay {
            viewModel.addScenePlay(sceneId: scene.id) { newCount in
                if let count = newCount {
                    DispatchQueue.main.async {
                        if var updatedScene = sceneDetail {
                            updatedScene = updatedScene.withPlayCount(count)
                            self.sceneDetail = updatedScene
                        }
                    }
                }
            }
            hasAddedPlay = true
            // Damit Listen und Dashboard das mitbekommen — iOS postet das an
            // derselben Stelle (`SceneDetailView.registerScenePlay`).
            NotificationCenter.default.post(
                name: NSNotification.Name("ScenePlayAdded"),
                object: nil,
                userInfo: ["sceneId": scene.id]
            )
        }
        
        guard let streamURL = scene.aetherVideoURL else { return }
        playerModel.setup(url: streamURL,
                          sceneId: scene.id,
                          viewModel: viewModel,
                          startAt: startTime,
                          title: scene.displayTitle,
                          subtitle: scene.studio?.name,
                          artworkURL: scene.thumbnailURL,
                          fallbackSources: scene.transcodeFallbackURLs,
                          fallbackDeclaredDuration: scene.sceneDuration)
    }

    // MARK: - Markers Section

    @ViewBuilder
    private func markersSection(markers: [SceneMarker], scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "bookmark.fill", title: "Markers", count: markers.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                startPlayback(for: scene, at: marker.seconds)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    if let url = marker.thumbnailURL {
                                        CustomAsyncImage(url: url) { loader in
                                            if let image = loader.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 260, height: 146)
                                                    .clipped()
                                            } else {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.08))
                                                    .frame(width: 260, height: 146)
                                                    .overlay(ProgressView().scaleEffect(0.8))
                                            }
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.08))
                                            .frame(width: 260, height: 146)
                                            .overlay(Image(systemName: "bookmark")
                                                .font(.largeTitle)
                                                .foregroundColor(.secondary))
                                    }
                                
                                    // Timestamp
                                    Text(formattedDuration(marker.seconds))
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        .padding(8)
                                }
                            }
                            .buttonStyle(.card)
                            
                            Text(marker.title ?? "Untitled Marker")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .frame(width: 260, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Performers & Studio Section

    @ViewBuilder
    private func performersSection(performers: [ScenePerformer]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "person.2.fill", title: "Performers", count: performers.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(performers) { performer in
                        TVNavButton(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            VStack(alignment: .leading, spacing: 12) {
                                performerThumbnail(performer: performer)
                                    .frame(width: 180, height: 270)
                                    .clipped()

                                Text(performer.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.top, 4)
                            }
                            .frame(width: 180)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
    }

    @ViewBuilder
    private func studioSection(studio: SceneStudio) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "building.2.fill", title: "Studio")

            TVNavButton(value: TVStudioLink(id: studio.id, name: studio.name)) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        TVStudioImageView(studioId: studio.id, studioName: studio.name, contentMode: .fit)
                            .padding(25)
                    }
                    .frame(width: 320, height: 180)

                    Text(studio.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                }
                .frame(width: 320)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func performerThumbnail(performer: ScenePerformer) -> some View {
        if let url = performer.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    performerPlaceholder
                }
            }
        } else {
            performerPlaceholder
        }
    }

    private var performerPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            )
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(icon: "tag.fill", title: "Tags", count: tags.count)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(tags) { tag in
                        TVNavButton(value: TVTagLink(id: tag.id, name: tag.name)) {
                            Text(tag.name)
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 40)
            }
            // tvOS focus: make this row a separate focus section so the user can move up/down
            // from any tag (not only after returning to the first item).
            .focusSection()
        }
    }


    // MARK: - Reusable Section Heading

    private func sectionHeading(icon: String, title: String, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppearanceManager.shared.tintColor)
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            if let count = count {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
