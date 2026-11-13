

#if !os(tvOS)
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(AetherEngine)
import AetherEngine
#endif

struct SceneVideoPlayerCard: View {
    @Binding var activeScene: Scene
    /// Non-nil once playback has started.
    let aetherEngine: AetherSceneEngine?
    @Binding var isPlaybackStarted: Bool
    @Binding var isFullscreen: Bool
    @Binding var isPreviewing: Bool
    /// `pressing` fires on touch-down, not after `minimumDuration`. Starting the preview there
    /// removed the play buttons under the finger, so a plain tap on Play only flashed the
    /// preview and needed a second tap. The preview now waits until the press really holds.
    @State private var pendingPreviewStart: DispatchWorkItem?
    /// Owned by SceneDetailView; the engine surface draws its own mute button.
    @Binding var isMuted: Bool
    /// Add-marker flow (the detail view owns the sheet); nil hides the button.
    var onAddMarker: (() -> Void)? = nil

    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var subtitleController: SubtitleController
    @ObservedObject var transcriptionController: SceneLiveTranscriptionController
    /// Sonderfunktionen im "…"-Menü des Players; geteilt mit dem Fullscreen-Cover.
    @ObservedObject var extrasController: ScenePlayerExtrasController
    /// The scene's scrubber sprite sheet, built once by the host.
    var scrubSprites: SceneScrubSprites?

    @StateObject private var previewPlayer = AetherPreviewPlayer()

    var onSeek: (Double) -> Void
    /// "Mark as Finished" on the cover, beside Resume and Start.
    var onMarkFinished: () -> Void = {}
    var onStartPlayback: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            videoPlayerArea
            markerScrollView
        }
        .scenePlayerExtrasSheets(controller: extrasController, scope: .inline)
    }

    @ViewBuilder
    private var videoPlayerArea: some View {
        VStack(spacing: 0) {
            if activeScene.aetherVideoURL != nil || aetherEngine != nil {
                if isPlaybackStarted, let aether = aetherEngine {
                    // While the host's fullscreen cover is up it hosts the engine's layer, so
                    // the inline surface steps aside instead of fighting it for the layer.
                    Group {
                        if isFullscreen {
                            Color.black
                        } else {
                            AetherSceneSurface(
                                engine: aether,
                                posterURL: activeScene.thumbnailURL,
                                isMuted: $isMuted,
                                onSeek: onSeek,
                                liveCaptionText: subtitleController.isLiveCaptionsActive
                                    ? subtitleController.currentText
                                    : "",
                                onToggleFullscreen: {
                                    // No slide-up: the cover is there at once, so a landscape video
                                    // can turn right away instead of after the animation.
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) { isFullscreen = true }
                                },
                                markers: activeScene.timeBarMarkers,
                                onAddMarker: onAddMarker,
                                extraMenuItems: { extrasController.menuItems() },
                                subtitleMenuExtras: { extrasController.aiSubtitleMenuItems() },
                                onHostSubtitleOff: { extrasController.turnOffAISubtitles() },
                                onOptionsMenuClosed: { extrasController.optionsMenuClosed() },
                                scrubSprites: scrubSprites
                            )
                        }
                    }
                    // Width first, then the ratio — same order as the thumbnail. The other way
                    // round the surface's own ideal size wins, which on macOS is a small box.
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit)
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
    /// File height → short quality label (`4K`, `1080p`, …), same rule as the player menu.
    private var coverResolutionLabel: String? {
        guard let height = activeScene.files?.first?.height, height > 0 else { return nil }
        if height >= 2160 { return "4K" }
        if height >= 1080 { return "1080p" }
        if height >= 720 { return "720p" }
        return "\(height)p"
    }

    /// The file's frame rate ("30 fps", "29.97 fps"), its own pill after the resolution.
    private var coverFrameRateLabel: String? {
        guard let fps = activeScene.files?.first?.frameRate, fps > 0 else { return nil }
        let rounded = (fps * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        return "\(text) fps"
    }

    private func coverInfoPill(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .stashyGlass(shape: Capsule())
    }

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
            if isPreviewing {
                GeometryReader { geo in
                    AetherPreviewSurface(player: previewPlayer)
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
            }
        }
        .overlay(alignment: .topTrailing) {
            // Source quality on the cover, before playback starts (the player shows it in
            // its options menu once running).
            if !isPreviewing, coverResolutionLabel != nil || coverFrameRateLabel != nil {
                HStack(spacing: 6) {
                    if let resolution = coverResolutionLabel {
                        coverInfoPill(resolution, systemImage: "video.fill")
                    }
                    if let frameRate = coverFrameRateLabel {
                        coverInfoPill(frameRate, systemImage: "speedometer")
                    }
                }
                .padding(10)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if !isPreviewing,
               let resumeTime = activeScene.resumeTime, resumeTime > 0,
               let duration = activeScene.sceneDuration, duration > 0 {
                resumeProgressBar(progress: PlaybackFraction.of(resumeTime, in: duration))
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
            pendingPreviewStart?.cancel()
            pendingPreviewStart = nil
            if pressing {
                let work = DispatchWorkItem { startPreview() }
                pendingPreviewStart = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            } else if isPreviewing {
                stopPreview()
            }
        }, perform: {})
        .onDisappear {
            pendingPreviewStart?.cancel()
            previewPlayer.stop(release: true)
        }
    }

    @ViewBuilder
    private func resumeProgressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var resumeButtons: some View {
        VStack(spacing: 16) {
            Button(action: { onStartPlayback(true) }) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(tr("action_resume_from_arg", formatTime(activeScene.resumeTime ?? 0)))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(appearanceManager.tintColor)
                .foregroundColor(Color.onAppTint)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 5)
            }
            
            HStack(spacing: 8) {
                Button(action: { onStartPlayback(false) }) {
                    resumeSecondaryLabel(tr("action_start_from_beginning"), systemImage: nil)
                }
                Button(action: onMarkFinished) {
                    resumeSecondaryLabel(tr("action_mark_as_finished"), systemImage: "checkmark")
                }
            }
            .padding(.horizontal, 8)
        }
        // These sit on a 16:9 cover and must not outgrow it.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func resumeSecondaryLabel(_ title: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(Color.onAppTint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(appearanceManager.tintColor)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 3)
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
                    Text(tr("video_not_available"))
                        .foregroundColor(.secondary)
                }
            )
    }

    private var markerStripTopPadding: CGFloat {
        let playing = isPlaybackStarted && aetherEngine != nil
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
            // The titles sat right on the card's edge; they need room to breathe under them.
            .padding(.bottom, 12)
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
                    .font(.system(size: 11))
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
            Text(marker.title ?? tr("marker_at_arg", formatTime(marker.seconds)))
                .font(.system(size: 11))
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
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
        previewPlayer.start(url: previewURL)
        withAnimation(.easeIn(duration: 0.2)) {
            isPreviewing = true
        }
    }

    private func stopPreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPreviewing = false
        }
        previewPlayer.stop(release: true)
    }

}

// MARK: - Scene metadata (separate card under the player)

private enum SceneMetadataPillStyle {
    static let height: CGFloat = 28
}

struct SceneDetailMetadataCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var activeScene: Scene
    /// Non-nil once playback has started.
    let aetherEngine: AetherSceneEngine?
    @Binding var isHeaderExpanded: Bool
    @Binding var showingAddMarkerSheet: Bool
    @Binding var capturedMarkerTime: Double
    @Binding var playbackSpeed: Double

    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingEditTitleSheet = false
    @State private var productionDate: String?

    var onSeek: (Double) -> Void
    var onTitleUpdated: ((String?, String?) -> Void)?
    var onMarkFinished: () -> Void = {}
    @ObservedObject private var lastPlayedHidden = LastPlayedHiddenStore.shared

    private var hasSceneMarkers: Bool {
        !(activeScene.sceneMarkers?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(activeScene.displayTitle ?? tr("unknown_title"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded || dynamicTypeSize.isAccessibilitySize ? nil : 2)
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

            if let details = activeScene.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(isHeaderExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                    .overlay(alignment: .bottomTrailing) {
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
                    }
            }

            metadataSwipeBar
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, hasSceneMarkers ? 4 : 12)
        .sheet(isPresented: $showingEditTitleSheet) {
            EditSceneTitleSheet(
                sceneId: activeScene.id,
                // Pre-fills the file-name fallback so an untitled scene can be named
                // by editing the name it already shows, rather than an empty field.
                currentTitle: activeScene.displayTitle,
                currentDetails: activeScene.details,
                currentProductionDate: productionDate,
                viewModel: viewModel,
                onProductionDateSaved: { productionDate = $0 }
            ) { newTitle, newDetails in
                onTitleUpdated?(newTitle, newDetails)
            }
        }
        .task(id: activeScene.id) {
            productionDate = await SceneProductionDate.fetch(sceneId: activeScene.id)
        }
    }

    @ViewBuilder
    private var metadataSwipeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // One line while everything fits; narrow columns and large text give the stars
            // their own line, so the date and duration never truncate.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    timePills
                    Spacer(minLength: 4)
                    countPills
                    Spacer(minLength: 4)
                    ratingMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        timePills
                        countPills
                    }
                    ratingMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    timePills
                    countPills
                    ratingMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            if let productionDate, !productionDate.isEmpty {
                Text(tr("produced_arg", productionDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var timePills: some View {
        HStack(spacing: 8) {
            if let date = activeScene.date {
                infoPill(icon: "calendar", text: date)
            }
            if let duration = activeScene.sceneDuration {
                infoPill(icon: "clock", text: formatMetaTime(duration))
            }
        }
    }

    private var countPills: some View {
        HStack(spacing: 8) {
            playCountPill
            oCounterButton
        }
    }

    /// The play count; a tap opens what can be done about the scene's playback state:
    /// "Mark as Finished" while it has a resume point and "Remove from Last Played" once it
    /// was played. A plain pill when neither applies.
    @ViewBuilder
    private var playCountPill: some View {
        let pill = infoPill(icon: "play.circle", text: "\(activeScene.playCount ?? 0)")
        let canFinish = (activeScene.resumeTime ?? 0) > 0 && aetherEngine == nil
        let wasPlayed = (activeScene.playCount ?? 0) > 0 || activeScene.lastPlayedAt != nil
        if canFinish || wasPlayed {
            Menu {
                if canFinish {
                    Button(action: onMarkFinished) {
                        Label(tr("action_mark_as_finished"), systemImage: "checkmark.circle")
                    }
                }
                if wasPlayed {
                    if lastPlayedHidden.isHidden(activeScene) {
                        Button {
                            lastPlayedHidden.unhide(activeScene.id)
                        } label: {
                            Label(tr("action_show_in_last_played_again"), systemImage: "eye")
                        }
                    } else {
                        Button {
                            lastPlayedHidden.hide(activeScene.id)
                            ToastManager.shared.show(tr("removed_from_last_played"), icon: "eye.slash")
                        } label: {
                            Label(tr("action_remove_from_last_played"), systemImage: "eye.slash")
                        }
                    }
                }
            } label: {
                pill
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(tr("play_count"))
            .accessibilityValue("\(activeScene.playCount ?? 0)")
        } else {
            pill
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
            infoPill(icon: AppearanceManager.shared.oCounterIconFilled, text: "\(activeScene.oCounter ?? 0)")
        }
        .buttonStyle(.plain)
        .oCounterRemovalMenu(
            count: activeScene.oCounter ?? 0,
            onRemoveOne: { removeOCounter(.decrement) },
            onReset: { removeOCounter(.reset) }
        )
    }

    private func removeOCounter(_ mutation: StashDBViewModel.OCounterMutation) {
        let original = activeScene.oCounter ?? 0
        activeScene = activeScene.withOCounter(mutation == .reset ? 0 : max(0, original - 1))
        viewModel.mutateSceneOCounter(sceneId: activeScene.id, mutation) { newCount in
            if let count = newCount {
                activeScene = activeScene.withOCounter(count)
            } else {
                activeScene = activeScene.withOCounter(original)
                ToastManager.shared.show(tr("error_counter_update"), icon: "exclamationmark.triangle", style: .error)
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
                    let ratedScene = activeScene.withRating(newRating)
                    DispatchQueue.main.async {
                        activeScene = ratedScene
                    }

                    viewModel.updateSceneRating(sceneId: activeScene.id, rating100: newRating) { success in
                        if success {
                            ratedScene.postListMetadataUpdated()
                        } else {
                            DispatchQueue.main.async {
                                activeScene = originalScene
                                ToastManager.shared.show(tr("error_update_rating"), icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            )
        }
        .padding(.horizontal, 8)
        .frame(height: SceneMetadataPillStyle.height)
        .background(Color.pillAccent.opacity(0.1))
        .foregroundColor(Color.pillAccent)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func infoPill(icon: String, text: String, color: Color = Color.pillAccent) -> some View {
        pillContainer(color: color) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func pillContainer<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: SceneMetadataPillStyle.height)
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

    @Environment(\.stashyDismiss) private var dismiss
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
                        TextField(tr("placeholder_search_tags"), text: $searchText)

                        if isLoadingTags && allTags.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView(tr("loading_tags"))
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if selectableTags.isEmpty {
                            Text(searchText.isEmpty ? tr("empty_tags_available") : tr("empty_tags_match_arg", searchText))
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
                                                Text(tr("on_this_scene"))
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
                                Text(tr("type_more_to_refine_search_menu"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text(searchText.isEmpty && !sceneTags.isEmpty ? tr("scene_tags") : tr("tags"))
                    } footer: {
                        Text(tr("hint_selected_tags_image_will_be"))
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("action_generate_tag_cover"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(
                    title: tr("action_apply"),
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
                    let tagName = (sceneTags + allTags).first(where: { $0.id == tagId })?.name ?? tr("tag")
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
                        tr("image_updated_for_arg", tagName),
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
                        tr("error_update_tag_image"),
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
    var currentProductionDate: String? = nil
    @ObservedObject var viewModel: StashDBViewModel
    var onProductionDateSaved: (String?) -> Void = { _ in }
    var onComplete: (String?, String?) -> Void

    @Environment(\.stashyDismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var productionDate: String = ""
    @State private var isSaving = false
    private let showsProductionDate = StashServerCapabilities.supports032

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(tr("title"))) {
                    TextField(tr("title"), text: $title)
                    if SceneTitleNormalizer.normalized(title) != title {
                        normalizeButton { title = SceneTitleNormalizer.normalized(title) }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section(header: Text(tr("description"))) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                    if SceneTitleNormalizer.normalizedDescription(details) != details {
                        normalizeButton { details = SceneTitleNormalizer.normalizedDescription(details) }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)

                if showsProductionDate {
                    Section(header: Text(tr("production_date"))) {
                        TextField(tr("placeholder_date"), text: $productionDate)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .listRowBackground(Color.secondaryAppBackground)
                }
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome(tr("action_edit_scene"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: tr("action_save"), enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                title = currentTitle ?? ""
                details = currentDetails ?? ""
                productionDate = currentProductionDate ?? ""
            }
        }
    }

    private func normalizeButton(_ action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Label(tr("normalize"), systemImage: "wand.and.stars")
                .font(.subheadline.weight(.medium))
                .foregroundColor(appearanceManager.tintColor)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func save() {
        let newDate = productionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !showsProductionDate || SceneProductionDate.isValid(newDate) else {
            ToastManager.shared.show(tr("action_use_yyyy_yyyy_mm_or"), icon: "exclamationmark.triangle", style: .error)
            return
        }
        isSaving = true
        let newTitle: String? = title.isEmpty ? nil : title
        let newDetails: String? = details.isEmpty ? nil : details
        viewModel.updateSceneTitleAndDetails(sceneId: sceneId, title: newTitle, details: newDetails) { success in
            Task { @MainActor in
                var saved = success
                if saved, showsProductionDate, newDate != (currentProductionDate ?? "") {
                    saved = await SceneProductionDate.update(sceneId: sceneId, date: newDate)
                    if saved { onProductionDateSaved(newDate.isEmpty ? nil : newDate) }
                }
                isSaving = false
                if saved {
                    onComplete(newTitle, newDetails)
                    dismiss()
                } else {
                    ToastManager.shared.show(tr("error_update_scene"), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

#endif
