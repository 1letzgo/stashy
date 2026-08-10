

#if !os(tvOS)
import SwiftUI
import AVKit
import UIKit

struct SceneVideoPlayerCard: View {
    @Binding var activeScene: Scene
    @Binding var player: AVPlayer?
    @Binding var isPlaybackStarted: Bool
    @Binding var isFullscreen: Bool
    @Binding var isPreviewing: Bool

    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var subtitleController: SubtitleController

    @State private var previewPlayer: AVPlayer?

    var onSeek: (Double) -> Void
    var onStartPlayback: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            videoPlayerArea
            markerScrollView
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }

    @ViewBuilder
    private var videoPlayerArea: some View {
        VStack(spacing: 0) {
            if activeScene.videoURL != nil {
                if isPlaybackStarted, let player = player {
                    VideoPlayerView(
                        player: player,
                        isFullscreen: $isFullscreen,
                        subtitleText: subtitleController.currentText
                    )
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 12,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 12
                            )
                        )
                } else {
                    thumbnailWithOverlay
                }
            } else {
                videoUnavailablePlaceholder
            }
        }
    }

    @ViewBuilder
    private var thumbnailWithOverlay: some View {
        ZStack {
            // Background / Thumbnail
            GeometryReader { geo in
                if let url = activeScene.thumbnailURL {
                    CustomAsyncImage(url: url) { @MainActor loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .skeleton()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
            }
            
            // Video Preview Overlay
            if isPreviewing, let previewPlayer = previewPlayer {
                GeometryReader { geo in
                    AspectFillVideoPlayer(player: previewPlayer)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            
            // Play Buttons Overlay
            if !isPreviewing {
                if let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                    resumeButtons
                } else {
                    largePlayButton
                }
                
                if let resumeTime = activeScene.resumeTime, resumeTime > 0, let duration = activeScene.sceneDuration, duration > 0 {
                    ProgressView(value: resumeTime, total: duration)
                        .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                        .frame(height: 6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.secondaryAppBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
        )
        .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
            if pressing { startPreview() } else { stopPreview() }
        }, perform: {})
    }

    @ViewBuilder
    private var resumeButtons: some View {
        VStack(spacing: 16) {
            Button(action: { onStartPlayback(true) }) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Resume from \(formatTime(activeScene.resumeTime ?? 0))")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(appearanceManager.tintColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 5)
            }
            
            Button(action: { onStartPlayback(false) }) {
                Text("Start from beginning")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appearanceManager.tintColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 3)
            }
        }
    }

    @ViewBuilder
    private var largePlayButton: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(DesignTokens.Opacity.medium))
                .frame(width: 70, height: 70)
                .blur(radius: 1)
            
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .offset(x: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onStartPlayback(false) }
    }

    @ViewBuilder
    private var videoUnavailablePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12
                )
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Video not available")
                        .foregroundColor(.secondary)
                }
            )
    }

    private var markerStripTopPadding: CGFloat {
        let playing = isPlaybackStarted && player != nil
        return playing ? 10 : 8
    }

    @ViewBuilder
    private var markerScrollView: some View {
        if let markers = activeScene.sceneMarkers, !markers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                        Button(action: { onSeek(marker.seconds) }) {
                            markerThumbnail(marker)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, markerStripTopPadding)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func markerThumbnail(_ marker: SceneMarker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = marker.thumbnailURL {
                    CustomAsyncImage(url: url) { @MainActor loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 45)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: 80, height: 45)
                                .skeleton()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 45)
                        .overlay(Image(systemName: "bookmark").foregroundColor(.secondary))
                }
                
                // Timestamp label
                Text(formatTime(marker.seconds))
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Marker Title
            Text(marker.title ?? "Marker at \(formatTime(marker.seconds))")
                .font(.system(size: 10))
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 80, alignment: .leading)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func startPreview() {
        guard let previewURL = activeScene.previewURL else { return }
        if previewPlayer == nil {
            previewPlayer = createMutedPreviewPlayer(for: previewURL)
        }
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
        previewPlayer?.play()
    }
    
    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
        previewPlayer?.pause()
        previewPlayer?.seek(to: CMTime.zero)
    }

}

// MARK: - Scene metadata (separate card under the player)

struct SceneDetailMetadataCard: View {
    @Binding var activeScene: Scene
    @Binding var player: AVPlayer?
    @Binding var isHeaderExpanded: Bool
    @Binding var showingAddMarkerSheet: Bool
    @Binding var capturedMarkerTime: Double
    @Binding var playbackSpeed: Double

    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var subtitleController: SubtitleController

    @State private var showingEditTitleSheet = false
    @State private var showingSetTagImageSheet = false
    @State private var showingSetSceneCoverConfirm = false
    @State private var isCapturingTagFrame = false
    @State private var isSettingSceneCover = false
    @State private var capturedTagImageDataURL: String?

    var onSeek: (Double) -> Void
    var onTitleUpdated: ((String?, String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(activeScene.title ?? "Unbekannter Titel")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer()
                    if appearanceManager.isEditModeEnabled {
                        Button {
                            showingEditTitleSheet = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                }
            }

            metadataSwipeBar

            if let details = activeScene.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(isHeaderExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .padding(.bottom, (activeScene.details?.isEmpty ?? true) ? 0 : 20)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .overlay(alignment: .bottomTrailing) {
            if let details = activeScene.details, !details.isEmpty {
                Button(action: {
                    withAnimation(.spring()) { isHeaderExpanded.toggle() }
                }) {
                    Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(6)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(8)
            }
        }
        .onChange(of: player) { _, newPlayer in
            if let item = newPlayer?.currentItem {
                StashVideoSyncManager.shared.setup(for: item)
            }
        }
        .onAppear {
            if let item = player?.currentItem {
                StashVideoSyncManager.shared.setup(for: item)
            }
        }
        .sheet(isPresented: $showingEditTitleSheet) {
            EditSceneTitleSheet(
                sceneId: activeScene.id,
                currentTitle: activeScene.title,
                currentDetails: activeScene.details,
                viewModel: viewModel
            ) { newTitle, newDetails in
                onTitleUpdated?(newTitle, newDetails)
            }
        }
        .sheet(isPresented: $showingSetTagImageSheet) {
            if let imageDataURL = capturedTagImageDataURL {
                SetTagImageFromFrameSheet(
                    imageDataURL: imageDataURL,
                    sceneTags: activeScene.tags ?? [],
                    viewModel: viewModel
                )
            }
        }
        .alert("Replace Scene Cover?", isPresented: $showingSetSceneCoverConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                captureAndSetSceneCover()
            }
        } message: {
            Text("The current video frame will replace this scene’s cover image. This cannot be undone from the app.")
        }
    }

    @ViewBuilder
    private var metadataSwipeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ratingMenu
                Spacer(minLength: 4)
                oCounterButton
                Spacer(minLength: 4)
                infoPill(icon: "play.circle", text: "\(activeScene.playCount ?? 0)")
                if let duration = activeScene.sceneDuration {
                    Spacer(minLength: 4)
                    infoPill(icon: "clock", text: formatMetaTime(duration))
                }
                if let date = activeScene.date {
                    Spacer(minLength: 4)
                    infoPill(icon: "calendar", text: date)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                addMarkerButton
                Spacer(minLength: 4)
                setTagImageButton
                Spacer(minLength: 4)
                setSceneCoverButton
                Spacer(minLength: 4)
                qualityMenu
                if activeScene.hasCaptions {
                    Spacer(minLength: 4)
                    captionsMenu
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var oCounterButton: some View {
        Button(action: {
            HapticManager.light()
            viewModel.incrementOCounter(sceneId: activeScene.id) { newCount in
                if let count = newCount {
                    DispatchQueue.main.async { activeScene = activeScene.withOCounter(count) }
                }
            }
        }) {
            infoPill(icon: AppearanceManager.shared.oCounterIconFilled, text: "\(activeScene.oCounter ?? 0)", color: .red)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var addMarkerButton: some View {
        Button(action: {
            capturedMarkerTime = player?.currentTime().seconds ?? 0
            showingAddMarkerSheet = true
        }) {
            infoPill(icon: "plus.square.fill.on.square.fill", text: "Add marker", color: .green)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var setTagImageButton: some View {
        Button(action: captureTagImageFrameAndPresentSheet) {
            infoPill(
                icon: isCapturingTagFrame ? "hourglass" : "tag.fill",
                text: "Tag Image",
                color: .orange
            )
        }
        .buttonStyle(.plain)
        // Only dim this pill while it is busy — do not couple to Scene Cover.
        .disabled(isCapturingTagFrame)
        .opacity(isCapturingTagFrame ? 0.7 : 1)
        .accessibilityLabel("Set tag image from current frame")
    }

    @ViewBuilder
    private var setSceneCoverButton: some View {
        Button {
            guard !isSettingSceneCover, !isCapturingTagFrame else { return }
            HapticManager.light()
            showingSetSceneCoverConfirm = true
        } label: {
            infoPill(
                icon: isSettingSceneCover ? "hourglass" : "photo",
                text: "Scene Cover",
                color: .purple
            )
        }
        .buttonStyle(.plain)
        .disabled(isSettingSceneCover)
        .opacity(isSettingSceneCover ? 0.7 : 1)
        .accessibilityLabel("Set scene cover from current frame")
    }

    private func currentCaptureTime() -> CMTime {
        let seconds: Double = {
            let t = player?.currentTime().seconds ?? 0
            return t.isFinite && t >= 0 ? t : 0
        }()
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func captureTagImageFrameAndPresentSheet() {
        guard !isCapturingTagFrame, !isSettingSceneCover else { return }
        isCapturingTagFrame = true
        HapticManager.light()

        Task { @MainActor in
            let dataURL = await captureVideoFrameDataURL(
                from: player,
                fallbackURL: activeScene.videoURL,
                at: currentCaptureTime()
            )
            isCapturingTagFrame = false
            guard let dataURL else {
                ToastManager.shared.show(
                    "Could not capture video frame",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }
            capturedTagImageDataURL = dataURL
            showingSetTagImageSheet = true
        }
    }

    private func captureAndSetSceneCover() {
        guard !isSettingSceneCover, !isCapturingTagFrame else { return }
        isSettingSceneCover = true

        Task { @MainActor in
            let dataURL = await captureVideoFrameDataURL(
                from: player,
                fallbackURL: activeScene.videoURL,
                at: currentCaptureTime()
            )
            guard let dataURL else {
                isSettingSceneCover = false
                ToastManager.shared.show(
                    "Could not capture video frame",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }

            viewModel.setSceneCoverImage(sceneId: activeScene.id, image: dataURL) { success in
                DispatchQueue.main.async {
                    isSettingSceneCover = false
                    if success {
                        let bust = ISO8601DateFormatter().string(from: Date())
                        activeScene = activeScene.withUpdatedAt(bust)
                        ToastManager.shared.show(
                            "Scene cover updated",
                            icon: "photo",
                            style: .success
                        )
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SceneCoverUpdated"),
                            object: nil,
                            userInfo: [
                                "sceneId": activeScene.id,
                                "updatedAt": bust
                            ]
                        )
                    } else {
                        ToastManager.shared.show(
                            "Failed to update scene cover",
                            icon: "exclamationmark.triangle",
                            style: .error
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ratingMenu: some View {
        HStack(spacing: 4) {
            StarRatingView(
                rating100: activeScene.rating100,
                isInteractive: true,
                size: 14,
                spacing: 2,
                onRatingChanged: { newRating in
                    let originalScene = activeScene
                    DispatchQueue.main.async {
                        activeScene = activeScene.withRating(newRating)
                    }

                    viewModel.updateSceneRating(sceneId: activeScene.id, rating100: newRating) { success in
                        if !success {
                            DispatchQueue.main.async {
                                activeScene = originalScene
                                ToastManager.shared.show("Failed to update rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.pillAccent.opacity(0.1))
        .foregroundColor(Color.pillAccent)
        .clipShape(Capsule())
    }

    private func switchPlayerStream(to url: URL) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let wasPlaying = (player.rate > 0) || (player.timeControlStatus == .playing)

        let newItem = makeVODPlayerItem(for: url)
        player.replaceCurrentItem(with: newItem)
        player.seek(to: currentTime, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity)
        player.rate = Float(playbackSpeed)
        if wasPlaying { player.play() }

        StashVideoSyncManager.shared.setup(for: newItem)
    }

    private func resolutionFromLabel(_ label: String) -> Int? {
        let cleaned = label.lowercased()
            .replacingOccurrences(of: "p", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Int(cleaned)
    }

    private func sortByResolutionDesc(_ a: SceneStream, _ b: SceneStream) -> Bool {
        (resolutionFromLabel(a.label) ?? 0) > (resolutionFromLabel(b.label) ?? 0)
    }

    /// File height → short quality chip text (`4K`, `1080p`, …).
    private var sourceResolutionLabel: String? {
        guard let height = activeScene.files?.first?.height, height > 0 else { return nil }
        if height >= 2160 { return "4K" }
        if height >= 1080 { return "1080p" }
        if height >= 720 { return "720p" }
        return "\(height)p"
    }

    private func isDirectStreamLabel(_ label: String) -> Bool {
        label.lowercased().contains("direct stream")
    }

    /// Prefer resolution over Stash's "Direct stream" label on the quality chip.
    private func displayLabel(for stream: SceneStream) -> String {
        if isDirectStreamLabel(stream.label), let res = sourceResolutionLabel {
            return res
        }
        return stream.label
    }

    private var currentStreamURLString: String? {
        (player?.currentItem?.asset as? AVURLAsset)?.url.absoluteString
    }

    private func isCurrentlyPlaying(_ stream: SceneStream) -> Bool {
        guard let current = currentStreamURLString else { return false }
        guard let lhs = URLComponents(string: current),
              let rhs = URLComponents(string: stream.url) else {
            return current == stream.url
        }
        return lhs.host == rhs.host && lhs.path == rhs.path
    }

    private func isPlayingDirectStream(_ directURL: URL) -> Bool {
        guard let current = currentStreamURLString,
              let currentPath = URLComponents(string: current)?.path,
              let directPath = URLComponents(url: directURL, resolvingAgainstBaseURL: false)?.path else {
            return false
        }
        return currentPath == directPath
    }

    @ViewBuilder
    private var qualityMenu: some View {
        let streams = activeScene.streams ?? []
        let hls = streams.filter { $0.mime_type == "application/vnd.apple.mpegurl" }
            .sorted(by: sortByResolutionDesc)
        let mp4 = streams.filter { $0.mime_type == "video/mp4" }
            .filter { !$0.label.lowercased().contains("mkv") }
            .sorted(by: sortByResolutionDesc)
        let directStreamURL: URL? = {
            guard let path = activeScene.paths?.stream else { return nil }
            return URL(string: path)
        }()

        if !hls.isEmpty || !mp4.isEmpty || directStreamURL != nil {
            Menu {
                if !hls.isEmpty {
                    Section("HLS · Adaptive") {
                        ForEach(hls, id: \.url) { stream in
                            Button(action: {
                                if let url = URL(string: stream.url) { switchPlayerStream(to: url) }
                            }) {
                                Label {
                                    Text(stream.label)
                                } icon: {
                                    if isCurrentlyPlaying(stream) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if !mp4.isEmpty {
                    Section("MP4 · Transcoded") {
                        ForEach(mp4, id: \.url) { stream in
                            Button(action: {
                                if let url = URL(string: stream.url) { switchPlayerStream(to: url) }
                            }) {
                                Label {
                                    Text(stream.label)
                                } icon: {
                                    if isCurrentlyPlaying(stream) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if let directURL = directStreamURL {
                    Section("Original") {
                        Button(action: { switchPlayerStream(to: directURL) }) {
                            let label: String = {
                                if let res = sourceResolutionLabel { return "Original · \(res)" }
                                return "Original"
                            }()
                            Label {
                                Text(label)
                            } icon: {
                                if isPlayingDirectStream(directURL) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                let currentLabel: String = {
                    if let directURL = directStreamURL, isPlayingDirectStream(directURL) {
                        return sourceResolutionLabel ?? "Original"
                    }
                    if let current = currentStreamURLString,
                       let active = streams.first(where: { isCurrentlyPlaying($0) || $0.url == current }) {
                        return displayLabel(for: active)
                    }
                    return sourceResolutionLabel ?? "Quality"
                }()
                infoPill(icon: "video.fill", text: currentLabel, color: .blue)
            }
        } else if let res = sourceResolutionLabel {
            infoPill(icon: "video.fill", text: res, color: .blue)
        }
    }

    @ViewBuilder
    private var captionsMenu: some View {
        let captions = activeScene.captions ?? []
        Menu {
            Button {
                subtitleController.select(nil)
            } label: {
                Label {
                    Text("Off")
                } icon: {
                    if subtitleController.selectedCaption == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Section("Subtitles") {
                ForEach(captions) { caption in
                    Button {
                        subtitleController.select(caption)
                    } label: {
                        Label {
                            Text(caption.displayName)
                        } icon: {
                            if subtitleController.selectedCaption == caption {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            let label = subtitleController.selectedCaption?.shortLabel ?? "CC"
            infoPill(
                icon: "captions.bubble.fill",
                text: label,
                color: subtitleController.selectedCaption == nil ? .secondary : .purple
            )
        }
    }

    @ViewBuilder
    private func infoPill(icon: String, text: String, color: Color = Color.pillAccent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private func formatMetaTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

/// Picks a tag and applies a previously captured video frame as its image.
struct SetTagImageFromFrameSheet: View {
    let imageDataURL: String
    let sceneTags: [Tag]
    @ObservedObject var viewModel: StashDBViewModel

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    @State private var searchText = ""
    @State private var allTags: [Tag] = []
    @State private var isLoadingTags = false
    @State private var isSaving = false
    @State private var selectedTagId: String?

    private var previewImage: UIImage? {
        guard let comma = imageDataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(imageDataURL[imageDataURL.index(after: comma)...])) else {
            return nil
        }
        return UIImage(data: data)
    }

    private var selectableTags: [Tag] {
        let source: [Tag]
        if !searchText.isEmpty {
            source = allTags
        } else if !sceneTags.isEmpty {
            // Prefer full tag rows (with scene_count) when already loaded.
            let byId = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
            source = sceneTags.map { byId[$0.id] ?? $0 }
        } else {
            source = allTags
        }
        let filtered: [Tag]
        if searchText.isEmpty {
            filtered = source
        } else {
            let q = searchText.lowercased()
            filtered = source.filter { $0.name.lowercased().contains(q) }
        }
        return Self.sortedByFrequency(filtered)
    }

    /// Most-used tags first (`scene_count` desc), name as tiebreaker.
    private static func sortedByFrequency(_ tags: [Tag]) -> [Tag] {
        tags.sorted { lhs, rhs in
            let l = lhs.sceneCount ?? 0
            let r = rhs.sceneCount ?? 0
            if l != r { return l > r }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }

                Form {
                    Section {
                        TextField("Search Tags...", text: $searchText)

                        if isLoadingTags && allTags.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("Loading tags...")
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if selectableTags.isEmpty {
                            Text(searchText.isEmpty ? "No tags available" : "No tags match '\(searchText)'")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(selectableTags.prefix(40), id: \.id) { tag in
                                Button {
                                    selectedTagId = tag.id
                                } label: {
                                    HStack(spacing: 10) {
                                        tagThumbnail(tag)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tag.name)
                                                .foregroundColor(.primary)
                                            if sceneTags.contains(where: { $0.id == tag.id }) {
                                                Text("On this scene")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if selectedTagId == tag.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(appearanceManager.tintColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            if selectableTags.count > 40 {
                                Text("Type more to refine search...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text(searchText.isEmpty && !sceneTags.isEmpty ? "Scene Tags" : "Tags")
                    } footer: {
                        Text("The selected tag’s image will be replaced with this video frame.")
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Set Tag Image", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: "Apply",
                    enabled: selectedTagId != nil,
                    isBusy: isSaving
                ) {
                    applySelectedTagImage()
                }
            }
            .onAppear {
                if selectedTagId == nil {
                    selectedTagId = Self.sortedByFrequency(sceneTags).first?.id
                }
                guard allTags.isEmpty else { return }
                isLoadingTags = true
                viewModel.fetchAllTags { fetched in
                    DispatchQueue.main.async {
                        let ranked = Self.sortedByFrequency(fetched)
                        allTags = ranked
                        isLoadingTags = false
                        if selectedTagId == nil {
                            let byId = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
                            let sceneRanked = Self.sortedByFrequency(sceneTags.map { byId[$0.id] ?? $0 })
                            selectedTagId = (sceneRanked.first ?? ranked.first)?.id
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagThumbnail(_ tag: Tag) -> some View {
        Group {
            if let url = tag.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if let image = loader.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        tagPlaceholder
                    }
                }
            } else {
                tagPlaceholder
            }
        }
        .frame(width: 64, height: 36) // 16:9
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tagPlaceholder: some View {
        ZStack {
            Color.gray.opacity(DesignTokens.Opacity.placeholder)
            Image(systemName: "tag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private func applySelectedTagImage() {
        guard let tagId = selectedTagId else { return }
        isSaving = true
        viewModel.setTagImage(tagId: tagId, image: imageDataURL) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    let tagName = (sceneTags + allTags).first(where: { $0.id == tagId })?.name ?? "Tag"
                    let bust = UUID().uuidString
                    let config = ServerConfigManager.shared.activeConfig ?? ServerConfigManager.shared.loadConfig()
                    let newImagePath: String = {
                        if let base = config?.baseURL {
                            return "\(base)/tag/\(tagId)/image?bust=\(bust)"
                        }
                        return "/tag/\(tagId)/image?bust=\(bust)"
                    }()
                    let updatedAt = ISO8601DateFormatter().string(from: Date())
                    ToastManager.shared.show(
                        "Image updated for \(tagName)",
                        icon: "tag.circle.fill",
                        style: .success
                    )
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TagImageUpdated"),
                        object: nil,
                        userInfo: [
                            "tagId": tagId,
                            "newImagePath": newImagePath,
                            "updatedAt": updatedAt
                        ]
                    )
                    dismiss()
                } else {
                    ToastManager.shared.show(
                        "Failed to update tag image",
                        icon: "exclamationmark.triangle",
                        style: .error
                    )
                }
            }
        }
    }
}

struct EditSceneTitleSheet: View {
    let sceneId: String
    let currentTitle: String?
    let currentDetails: String?
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (String?, String?) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Title")) {
                    TextField("Title", text: $title)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(header: Text("Description")) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Edit Scene", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                title = currentTitle ?? ""
                details = currentDetails ?? ""
            }
        }
    }

    private func save() {
        isSaving = true
        let newTitle: String? = title.isEmpty ? nil : title
        let newDetails: String? = details.isEmpty ? nil : details
        viewModel.updateSceneTitleAndDetails(sceneId: sceneId, title: newTitle, details: newDetails) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    onComplete(newTitle, newDetails)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update scene", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
