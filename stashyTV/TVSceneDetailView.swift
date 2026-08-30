//
//  TVSceneDetailView.swift
//  stashyTV
//
//  Scene detail for tvOS — Netflix/Prime style
//

import SwiftUI
import AVKit
import Combine

struct TVSceneDetailView: View {
    let sceneId: String

    @ObservedObject private var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @StateObject private var playerViewModel = TVPlayerViewModel()
    @State private var sceneDetail: Scene?
    @State private var sceneStreams: [SceneStream] = []
    @State private var isLoadingDetail = true
    @State private var isLoadingStreams = true
    @State private var hasAddedPlay = false
    @State private var selectedQuality: StreamingQuality? = nil
    @State private var showingRatingPicker = false
    @State private var showingQualityPicker = false
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
                isLoadingStreams = false
            }
        }
        .onPlayPauseCommand {
            // On the detail surface: start playback. Native VideoPlayer owns Play/Pause in cover.
            guard let scene = sceneDetail, !playerViewModel.isShowingPlayer else { return }
            startPlayback(for: scene)
        }
        .defaultFocus($focusedHeroAction, .play)
        .fullScreenCover(isPresented: $playerViewModel.isShowingPlayer, onDismiss: {
            playerViewModel.clear()
            loadData()
        }) {
            if let player = playerViewModel.player {
                TVVideoPlayerView(player: player, isPresented: $playerViewModel.isShowingPlayer) {
                    // Failsafe — save progress falls fullScreenCover ohne `onDismiss` weggeht.
                    playerViewModel.saveProgress()
                }
            } else {
                // Fallback, wenn der Player nicht erzeugt werden konnte oder fehlschlägt.
                TVPlayerErrorView(error: playerViewModel.error) {
                    playerViewModel.isShowingPlayer = false
                }
            }
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
            isLoadingStreams = false
            return
        }

        isLoadingDetail = true
        isLoadingStreams = true

        viewModel.fetchSceneDetails(sceneId: sceneId) { scene in
            self.sceneDetail = scene
            self.isLoadingDetail = false
        }

        viewModel.fetchSceneStreams(sceneId: sceneId) { streams in
            self.sceneStreams = streams
            self.isLoadingStreams = false
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
        let hasStream = !sceneStreams.isEmpty || scene.paths?.stream != nil
        let isWaiting = isLoadingDetail || isLoadingStreams
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

                heroCardButton {
                    showingQualityPicker = true
                } label: {
                    heroActionLabel(icon: "rectangle.stack", title: currentQuality.displayName)
                }
                .confirmationDialog("Quality", isPresented: $showingQualityPicker, titleVisibility: .visible) {
                    ForEach(StreamingQuality.allCases, id: \.self) { q in
                        Button(q.displayName) { selectedQuality = q }
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

    private var currentQuality: StreamingQuality {
        selectedQuality ?? ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
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
        
        let quality = selectedQuality ?? ServerConfigManager.shared.activeConfig?.defaultQuality ?? .original
        if let streamURL = tvPlaybackURL(for: scene, streams: sceneStreams, quality: quality) {
            playerViewModel.setupPlayer(url: streamURL, sceneId: scene.id, viewModel: viewModel, startAt: startTime)
        }
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

// MARK: - Player View Model

class TVPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isShowingPlayer = false
    @Published var error: Error?
    /// Called when the current item finishes. Used by channel continuous play.
    var onPlaybackEnded: (() -> Void)?

    private var statusObserver: NSKeyValueObservation?
    private var progressTimer: AnyCancellable?
    /// Nach System-Spulen bleibt der Player oft bei rate 0; Apple-TV+-ähnlich wieder anspielen.
    private var timeJumpedObserver: NSObjectProtocol?
    private var playbackEndedObserver: NSObjectProtocol?
    /// Lifecycle-Observer für robuste Resume-Saves (Home-Knopf, Sleep, App-Switch).
    private var willResignActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    /// Coalesces repeated remote scrubs; we restore steady-state buffering only
    /// after the user has stopped seeking for a short moment.
    private var scrubSettleWorkItem: DispatchWorkItem?
    private var sceneId: String?
    private var viewModel: StashDBViewModel?
    /// Avoid duplicate seek/play when `status` KVO fires more than once at `.readyToPlay`.
    private var didApplyInitialPlayback = false
    /// `saveProgress()` already ran in `suspend()` — skip the duplicate in `clear()`.
    private var isSuspended = false

    init() {
        let center = NotificationCenter.default
        willResignActiveObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveProgress()
        }
        didEnterBackgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveProgress()
        }
    }

    deinit {
        // Defensive cleanup: falls `clear()` vor Dealloc nicht aufgerufen wurde
        // (z.B. Parent-View wird während fullScreenCover entfernt), verhindern
        // wir hier leaking Observer / Timer und späte KVO-Callbacks auf toten VMs.
        if let t = willResignActiveObserver { NotificationCenter.default.removeObserver(t) }
        if let t = didEnterBackgroundObserver { NotificationCenter.default.removeObserver(t) }
        removeTimeJumpedObserver()
        removePlaybackEndedObserver()
        statusObserver = nil
        progressTimer = nil
        scrubSettleWorkItem?.cancel()
        scrubSettleWorkItem = nil
    }

    func setupPlayer(url: URL, sceneId: String, viewModel: StashDBViewModel, startAt timestamp: Double = 0) {
        AppLog.debug("🚀 TV PLAYER VM: Setting up player for URL: \(redactedURLString(url)) at \(timestamp)s")
        self.sceneId = sceneId
        self.viewModel = viewModel
        self.didApplyInitialPlayback = false

        // Never gated on headphones: on Apple TV the set's speakers are the normal output, so the
        // rule would start every playback silent.
        let newPlayer = createPlayer(for: url, muted: false)
        let previousPlayer = self.player
        self.player = newPlayer
        self.isShowingPlayer = true
        previousPlayer?.pause()
        previousPlayer?.replaceCurrentItem(with: nil)

        let startSeconds = max(0, timestamp)

        statusObserver = newPlayer.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self, weak newPlayer] item, _ in
            guard let self, let newPlayer else { return }
            DispatchQueue.main.async {
                guard self.player === newPlayer else { return }
                if item.status == .failed {
                    self.error = item.error
                    AppLog.debug("❌ TV PLAYER VM: Playback FAILED: \(item.error?.localizedDescription ?? "Unknown error")")
                    if let error = item.error as NSError? {
                        AppLog.debug("❌ TV PLAYER VM: Error domain: \(error.domain), code: \(error.code)")
                        AppLog.debug("❌ TV PLAYER VM: Error user info: \(error.userInfo)")
                    }
                } else if item.status == .readyToPlay {
                    AppLog.debug("✅ TV PLAYER VM: Player item READY to play")
                    self.applyInitialPlaybackIfNeeded(player: newPlayer, startSeconds: startSeconds)
                }
            }
        }

        progressTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.saveProgress()
            }

        registerAutoResumeAfterScrub(on: newPlayer)
        if let item = newPlayer.currentItem {
            registerPlaybackEndedObserver(on: item)
        }
    }

    private func registerAutoResumeAfterScrub(on player: AVPlayer) {
        removeTimeJumpedObserver()
        guard let item = player.currentItem else { return }
        timeJumpedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            guard let self, let player else { return }
            if let item = player.currentItem {
                // During scrub bursts (remote seek), prefer a short buffer so
                // seeks stay responsive instead of re-buffering deeply.
                configureForVOD(item, isScrubbing: true)
            }

            // Restore normal playback buffering once seek activity settles.
            self.scrubSettleWorkItem?.cancel()
            let settleWork = DispatchWorkItem { [weak player] in
                guard let item = player?.currentItem else { return }
                configureForVOD(item, isScrubbing: false)
            }
            self.scrubSettleWorkItem = settleWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: settleWork)

            // tvOS frequently leaves rate at 0 after scrub; auto-resume for a
            // smoother "Apple TV+"-like experience.
            if player.rate == 0 {
                player.play()
            }
        }
    }

    private func registerPlaybackEndedObserver(on item: AVPlayerItem) {
        removePlaybackEndedObserver()
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            let vm = self
            Task { @MainActor in
                vm?.onPlaybackEnded?()
            }
        }
    }

    private func removePlaybackEndedObserver() {
        if let token = playbackEndedObserver {
            NotificationCenter.default.removeObserver(token)
            playbackEndedObserver = nil
        }
    }

    private func removeTimeJumpedObserver() {
        if let token = timeJumpedObserver {
            NotificationCenter.default.removeObserver(token)
            timeJumpedObserver = nil
        }
    }

    /// Seeking before `readyToPlay` (especially HLS/transcodes) causes UI hangs and endless buffering after scrubs.
    private func applyInitialPlaybackIfNeeded(player: AVPlayer, startSeconds: Double) {
        guard !didApplyInitialPlayback else { return }
        didApplyInitialPlayback = true

        let item = player.currentItem
        let durationSec = item?.duration.seconds ?? 0
        var start = startSeconds
        if durationSec.isFinite, durationSec > 0 {
            start = min(start, max(0, durationSec - 0.5))
        }

        if start > 0.25 {
            let target = CMTime(seconds: start, preferredTimescale: 600)
            let tol = CMTime(seconds: 2, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, let player, self.player === player else { return }
                    player.play()
                }
            }
        } else {
            player.play()
        }
    }

    func saveProgress() {
        guard let player = player,
              let sceneId = sceneId,
              let viewModel = viewModel else { return }
        
        let currentTime = player.currentTime().seconds
        if currentTime > 0 {
            // Prefer the dedicated activity tracker when available; otherwise at least
            // persist resume. Play-duration deltas are accumulated on iOS Scene Detail / Feeds.
            AppLog.debug("💾 TV PLAYER VM: Saving progress: \(currentTime)s for \(sceneId)")
            let duration = player.currentItem?.duration.seconds ?? 0
            var resume = currentTime
            if duration.isFinite, duration > 0, (100.0 / duration) * currentTime >= 98 {
                resume = 0
            }
            viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: resume, playDuration: 0)
            NotificationCenter.default.post(
                name: NSNotification.Name("SceneResumeTimeUpdated"),
                object: nil,
                userInfo: ["sceneId": sceneId, "resumeTime": resume]
            )
        }
    }

    /// Stoppt Timer/Observer und pausiert, lässt den veröffentlichten `player` aber stehen.
    /// `player = nil` während das fullScreenCover noch dismissed wird reißt die noch
    /// sichtbare AVPlayerViewController-Hierarchie weg — auf tvOS ein sicherer Force-Close
    /// beim Back-Exit aus dem Kanal-Player. Für diesen Moment gibt es `suspend()`;
    /// `clear()` läuft erst in `onDisappear`, wenn das Cover bereits entfernt ist.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        saveProgress()
        scrubSettleWorkItem?.cancel()
        scrubSettleWorkItem = nil
        removeTimeJumpedObserver()
        removePlaybackEndedObserver()
        progressTimer = nil
        statusObserver = nil
        didApplyInitialPlayback = true
        player?.pause()
    }

    func clear() {
        if !isSuspended {
            saveProgress()
        }
        isSuspended = false
        scrubSettleWorkItem?.cancel()
        scrubSettleWorkItem = nil
        removeTimeJumpedObserver()
        removePlaybackEndedObserver()
        progressTimer = nil
        statusObserver = nil
        didApplyInitialPlayback = true
        let p = player
        player = nil
        sceneId = nil
        viewModel = nil
        p?.pause()
        p?.replaceCurrentItem(with: nil)
    }
}

// MARK: - Embedded Video Player for tvOS Full Screen Cover

struct TVVideoPlayerView: View {
    let player: AVPlayer
    @Binding var isPresented: Bool
    var onDisappear: (() -> Void)? = nil

    var body: some View {
        VideoPlayer(player: player) {
            // Empty overlay - VideoPlayer provides native tvOS controls
        }
        .ignoresSafeArea()
        .onExitCommand {
            // Menu button should close the player, not exit the app.
            isPresented = false
        }
        .onDisappear {
            onDisappear?()
        }
    }
}

// MARK: - Player Error Fallback (fullScreenCover)

/// Wird angezeigt, wenn `setupPlayer` `isShowingPlayer = true` gesetzt hat, der
/// `AVPlayer` aber nicht erzeugt werden konnte oder `.failed` ist — ohne diese
/// View bliebe das fullScreenCover leer und ohne Dismiss-Affordance.
private struct TVPlayerErrorView: View {
    let error: Error?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                Text("Unable to play this scene")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                if let error {
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                }
                Button("Close", action: onDismiss)
                    .font(.title3)
            }
        }
        .onExitCommand { onDismiss() }
    }
}
