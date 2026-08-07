

#if !os(tvOS)
import SwiftUI
import AVKit

struct SceneVideoPlayerCard: View {
    @Binding var activeScene: Scene
    @Binding var player: AVPlayer?
    @Binding var isPlaybackStarted: Bool
    @Binding var isFullscreen: Bool
    @Binding var isPreviewing: Bool

    @ObservedObject var appearanceManager = AppearanceManager.shared

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
                    VideoPlayerView(player: player, isFullscreen: $isFullscreen)
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

    @State private var showingEditTitleSheet = false

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

                if activeScene.sceneDuration != nil || activeScene.date != nil {
                    HStack {
                        if let duration = activeScene.sceneDuration {
                            Text("Duration: \(formatMetaTime(duration))")
                        }

                        Spacer()

                        if let date = activeScene.date {
                            Text("Released: \(date)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
    }

    @ViewBuilder
    private var metadataSwipeBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ratingMenu

                Spacer(minLength: 4)
                oCounterButton

                if let playCount = activeScene.playCount, playCount > 0 {
                    Spacer(minLength: 4)
                    infoPill(icon: "play.circle", text: "\(playCount)")
                }

                Spacer(minLength: 4)
                addMarkerButton
                Spacer(minLength: 4)
                qualityMenu
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
            infoPill(icon: "plus.square.fill.on.square.fill", text: "Marker", color: .green)
        }
        .buttonStyle(.plain)
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
                            let res = activeScene.files?.first?.height
                            let label: String = {
                                guard let h = res else { return "Direct Stream" }
                                if h >= 2160 { return "Original · 4K" }
                                if h >= 1080 { return "Original · 1080p" }
                                if h >= 720 { return "Original · 720p" }
                                return "Original · \(h)p"
                            }()
                            Label {
                                Text(label)
                            } icon: {
                                if let current = currentStreamURLString,
                                   let direct = URL(string: directURL.absoluteString),
                                   URLComponents(string: current)?.path == URLComponents(url: direct, resolvingAgainstBaseURL: false)?.path {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                let currentLabel: String = {
                    if let current = currentStreamURLString,
                       let active = streams.first(where: { isCurrentlyPlaying($0) || $0.url == current }) {
                        return active.label
                    }
                    if let firstFile = activeScene.files?.first, let height = firstFile.height {
                        return height >= 2160 ? "4K" : (height >= 1080 ? "1080p" : (height >= 720 ? "720p" : "\(height)p"))
                    }
                    return "Quality"
                }()
                infoPill(icon: "video.fill", text: currentLabel, color: .blue)
            }
        } else if let firstFile = activeScene.files?.first, let height = firstFile.height {
            let res = height >= 2160 ? "4K" : (height >= 1080 ? "1080p" : (height >= 720 ? "720p" : "\(height)p"))
            infoPill(icon: "video.fill", text: res, color: .blue)
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
            .navigationTitle("Edit Scene")
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
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
