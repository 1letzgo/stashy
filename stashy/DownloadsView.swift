//
//  DownloadsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI
import AVKit

struct DownloadsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    
    @State private var gridWidth: CGFloat = 0

    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: 360,
            minimum: 1,
            maximum: 6
        )
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if downloadManager.downloads.isEmpty && downloadManager.galleryDownloads.isEmpty && downloadManager.activeDownloads.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 64))
                        .foregroundColor(appearanceManager.tintColor)
                    
                    Text("No Downloads yet")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Downloaded scenes will appear here for offline viewing.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Tools.contentPadding)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Active Downloads Section
                        if !downloadManager.activeDownloads.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Active Downloads")
                                    .font(.headline)
                                    .padding(.horizontal, DesignTokens.Tools.contentPadding)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(Array(downloadManager.activeDownloads.values).sorted { $0.title < $1.title }, id: \.id) { download in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(download.title)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                        
                                            if download.totalSize > 0 {
                                                ProgressView(value: download.progress)
                                                    .tint(appearanceManager.tintColor)
                                            
                                                Text("\(Int(download.progress * 100))%")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                ProgressView()
                                                    .progressViewStyle(.linear)
                                                    .tint(appearanceManager.tintColor)
                                            
                                                Text("\(ByteCountFormatter.string(fromByteCount: download.downloadedSize, countStyle: .file)) downloaded")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding()
                                        .background(Color.secondaryAppBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                                        .subtleShadow()
                                    }
                                }
                                .measuresGridWidth($gridWidth)
                                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                            }
                            .padding(.top, DesignTokens.Tools.menuTopPadding)
                        }
                        
                        // Completed Downloads Section
                        if !downloadManager.downloads.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Scenes")
                                    .font(.headline)
                                    .padding(.horizontal, DesignTokens.Tools.contentPadding)
                                
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(downloadManager.downloads) { downloaded in
                                        NavigationLink(destination: DownloadDetailView(downloaded: downloaded)) {
                                            DownloadedSceneCard(downloaded: downloaded)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .measuresGridWidth($gridWidth)
                                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                            }
                            .padding(.top, downloadManager.activeDownloads.isEmpty ? DesignTokens.Tools.menuTopPadding : 0)
                        }

                        let galleryEntries = downloadManager.galleryDownloads.filter { $0.resolvedKind != .tag }
                        let tagEntries = downloadManager.galleryDownloads.filter { $0.resolvedKind == .tag }

                        if !galleryEntries.isEmpty {
                            downloadSection("Galleries & Images", entries: galleryEntries)
                        }
                        if !tagEntries.isEmpty {
                            downloadSection("Tags", entries: tagEntries)
                        }
                    }
                    .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DownloadedSceneCard: View {
    let downloaded: DownloadedScene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thumbnail on the left
            ZStack(alignment: .bottomLeading) {
                let thumbURL = downloadManager.getLocalThumbnailURL(for: downloaded)
                if let data = try? Data(contentsOf: thumbURL), let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 130, height: 100)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 130, height: 100)
                        .overlay(Image(systemName: "film").foregroundColor(.secondary))
                }
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.green)
                    .clipShape(Circle())
                    .padding(4)

                // Duration Badge (Bottom Right)
                if let duration = downloaded.duration, duration > 0 {
                    Text(formatDuration(duration))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .padding(4)
                        .frame(maxWidth: 130, maxHeight: 100, alignment: .bottomTrailing)
                }
            }
            
            // Content on the right
            VStack(alignment: .leading, spacing: 4) {
                Text(downloaded.title ?? "Unknown Title")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Spacer()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if let studio = downloaded.studioName {
                            HStack(spacing: 4) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 8))
                                Text(studio)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .foregroundColor(appearanceManager.tintColor)
                            .clipShape(Capsule())
                        }
                        
                        ForEach(downloaded.performerNames.prefix(3), id: \.self) { name in
                            HStack(spacing: 3) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 8))
                                Text(name)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .foregroundColor(appearanceManager.tintColor)
                            .clipShape(Capsule())
                        }
                        
                        if downloaded.performerNames.count > 3 {
                            Text("+\(downloaded.performerNames.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            Spacer()
        }
        .frame(height: 100)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .subtleShadow()
    }
    
    private func formatDuration(_ seconds: Double) -> String {
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

struct DownloadDetailView: View {
    let downloaded: DownloadedScene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var player: AVPlayer?
    @State private var isPlaybackStarted = false
    @State private var isFullScreen = false
    @State private var isHeaderExpanded = false
    @State private var isMuted = ScenePlayerMute.initialValue()
    @Environment(\.dismiss) var dismiss

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    /// Custom top chrome: Back · Share.
    @ViewBuilder
    private var downloadDetailNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 8)

                Button {
                    HapticManager.light()
                    let videoURL = downloadManager.getLocalVideoURL(for: downloaded)
                    shareVideo(url: videoURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                        .frame(
                            width: StashyExpandingDock.circleSize,
                            height: StashyExpandingDock.circleSize
                        )
                        .background(StashyExpandingDock.inactiveBackground)
                        .clipShape(Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share")
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Video Player
                VStack(spacing: 0) {
                    if isPlaybackStarted, let player = player {
                        VideoPlayerView(player: player, isFullscreen: $isFullScreen)
                            .aspectRatio(16/9, contentMode: .fit) // Keep 16:9 for consistency or use nil for 9:16
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    } else {
                        ZStack {
                            let thumbURL = downloadManager.getLocalThumbnailURL(for: downloaded)
                            if let data = try? Data(contentsOf: thumbURL), let uiImage = UIImage(data: data) {
                                GeometryReader { geo in
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                }
                            } else {
                                Color.black
                            }
                            
                            // Large Play Button Overlay
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
                        }
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if player == nil {
                                let videoURL = downloadManager.getLocalVideoURL(for: downloaded)
                                player = createPlayer(for: videoURL, muted: isMuted)
                            }
                            withAnimation {
                                isPlaybackStarted = true
                            }
                            player?.play()
                        }
                    }
                }
                .cardShadow()
                
                // Info Card
                VStack(alignment: .leading, spacing: 10) {
                    // Title
                    Text(downloaded.title ?? "Unknown Title")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Metadata Row
                    HStack(spacing: 16) {
                        if let date = downloaded.date {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(appearanceManager.tintColor)
                                Text(date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let duration = downloaded.duration, duration > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundColor(appearanceManager.tintColor)
                                Text(formatDuration(duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let details = downloaded.details, !details.isEmpty {
                        Text(details)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineLimit(isHeaderExpanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .padding(12)
                .padding(.bottom, (downloaded.details?.isEmpty ?? true) ? 0 : 20)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .cardShadow()
                .overlay(
                    Group {
                        if let details = downloaded.details, !details.isEmpty {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isHeaderExpanded.toggle()
                                }
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
                    },
                    alignment: .bottomTrailing
                )

                // Combined Metadata Card (Studio & Performers)
                if !downloaded.performerNames.isEmpty || downloaded.studioName != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let studio = downloaded.studioName {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Studio")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption)
                                    Text(studio)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(appearanceManager.tintColor.opacity(0.1))
                                .foregroundColor(appearanceManager.tintColor)
                                .clipShape(Capsule())
                            }
                        }
                        
                        if !downloaded.performerNames.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Performers")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                
                                OfflineWrappedHStack(items: downloaded.performerNames.map { IdentifiableString(value: $0) }) { item in
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.circle.fill")
                                            .font(.caption)
                                        
                                        Text(item.value)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(appearanceManager.tintColor.opacity(0.1))
                                    .foregroundColor(appearanceManager.tintColor)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondaryAppBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .cardShadow()
                }
                
                // Delete Button
                Button(role: .destructive) {
                    downloadManager.deleteDownload(id: downloaded.id)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Download")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(appearanceManager.tintColor.opacity(0.1))
                    .foregroundColor(appearanceManager.tintColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .applyAppBackground()
        .hideSystemNavigationBarForCustomChrome()
        .enableSwipeBackWhenNavBarHidden()
        .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
            downloadDetailNavBar
        }
    }
    
    private func shareVideo(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // For iPad support
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            activityVC.popoverPresentationController?.permittedArrowDirections = []
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
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

// Simple WrappedHStack for Flow Layout
struct OfflineWrappedHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    let content: (Data.Element) -> Content
    let spacing: CGFloat = 8
    
    @State private var totalHeight: CGFloat = .zero
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }
    
    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                self.content(item)
                    .padding([.horizontal, .vertical], 4)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > g.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item.id == self.items.last?.id {
                            width = 0 // last item
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: {d in
                        let result = height
                        if item.id == self.items.last?.id {
                            height = 0 // last item
                        }
                        return result
                    })
            }
        }.background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return .clear
        }
    }
}

extension DownloadsView {
    @ViewBuilder
    func downloadSection(_ title: String, entries: [DownloadedGallery]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, DesignTokens.Tools.contentPadding)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries) { entry in
                    NavigationLink(destination: DownloadedGalleryDetailView(entryId: entry.id)) {
                        DownloadedGalleryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
        }
        .padding(.top, DesignTokens.Tools.menuTopPadding)
    }
}

/// Row for a downloaded gallery or single image, with sync / delete actions.
struct DownloadedGalleryCard: View {
    let entry: DownloadedGallery
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared

    private var isSyncing: Bool { downloadManager.activeDownloads[entry.id] != nil }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isSyncing {
                Button {
                    downloadManager.cancelGalleryDownload(id: entry.id)
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            } else {
                Menu {
                    if !entry.isSingleImage {
                        Button {
                            sync(limit: nil)
                        } label: {
                            Label("Sync newest", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            sync(limit: DownloadManager.galleryNewestBatchSize)
                        } label: {
                            Label("Sync newest \(DownloadManager.galleryNewestBatchSize)", systemImage: "arrow.down.to.line")
                        }
                        Divider()
                    }
                    Button(role: .destructive) {
                        downloadManager.deleteGalleryDownload(id: entry.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private func sync(limit: Int?) {
        if entry.resolvedKind == .tag {
            downloadManager.syncTagImages(entryId: entry.id, limit: limit)
        } else {
            downloadManager.syncGallery(id: entry.id, limit: limit)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if entry.isSingleImage {
            parts.append("Single image")
        } else if let total = entry.serverImageCount, total > entry.images.count {
            parts.append("\(entry.images.count) of \(total) images")
        } else {
            parts.append("\(entry.images.count) image(s)")
        }
        if let studio = entry.studioName, !studio.isEmpty { parts.append(studio) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var cover: some View {
        let size: CGFloat = 56
        Group {
            if let url = downloadManager.localCoverURL(for: entry),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                    .overlay {
                        Image(systemName: {
                            switch entry.resolvedKind {
                            case .image: return "photo"
                            case .tag: return "tag"
                            case .gallery: return "photo.stack"
                            }
                        }())
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small))
    }
}


/// Offline viewer for a downloaded gallery (or single image). Reads straight from disk, so it
/// works with no server connection.
struct DownloadedGalleryDetailView: View {
    let entryId: String
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    private var entry: DownloadedGallery? {
        downloadManager.downloadedGallery(id: entryId)
    }

    @State private var gridWidth: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private var isSyncing: Bool { downloadManager.activeDownloads[entryId] != nil }

    /// Square cells; same 12pt spacing and width-based column count as `ImagesView`.
    private var columns: [GridItem] {
        DesignTokens.Grid.adaptiveColumns(
            width: gridWidth,
            ideal: 180,
            minimum: 2,
            maximum: 6
        )
    }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(entry.images.enumerated()), id: \.element.id) { index, image in
                            NavigationLink {
                                DownloadedGalleryFullScreenView(images: entry.images, startIndex: index)
                            } label: {
                                thumbnail(image)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .measuresGridWidth($gridWidth)
                    .padding(DesignTokens.Tools.contentPadding)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Download no longer available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .hideSystemNavigationBarForCustomChrome()
        .enableSwipeBackWhenNavBarHidden()
        .stashyCustomChromeInset(spacing: DesignTokens.Chrome.contentTopGap) {
            galleryDetailNavBar
        }
    }

    /// Custom top chrome: Back · title · Sync newest / Sync newest 50 / Delete.
    @ViewBuilder
    private var galleryDetailNavBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                StashyChromeBackButton { dismiss() }

                Text(entry?.displayTitle ?? "Download")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSyncing {
                    chromeCircleButton(
                        systemImage: "stop.circle",
                        label: "Cancel download",
                        tint: .red
                    ) {
                        HapticManager.light()
                        downloadManager.cancelGalleryDownload(id: entryId)
                    }
                } else {
                    if entry?.isSingleImage == false {
                        chromeCircleButton(
                            systemImage: "arrow.triangle.2.circlepath",
                            label: "Sync newest"
                        ) {
                            HapticManager.light()
                            sync(limit: nil)
                        }

                        chromeCircleButton(
                            systemImage: "arrow.down.to.line",
                            label: "Sync newest \(DownloadManager.galleryNewestBatchSize)"
                        ) {
                            HapticManager.light()
                            sync(limit: DownloadManager.galleryNewestBatchSize)
                        }
                    }

                    chromeCircleButton(
                        systemImage: "trash",
                        label: "Delete",
                        tint: .red
                    ) {
                        HapticManager.light()
                        downloadManager.deleteGalleryDownload(id: entryId)
                        dismiss()
                    }
                }
            }
            .frame(minHeight: StashyExpandingDock.activeHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }

    /// Circular chrome action button, same metrics as the Share button in `DownloadDetailView`.
    @ViewBuilder
    private func chromeCircleButton(
        systemImage: String,
        label: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundColor(tint ?? .white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(
                    width: StashyExpandingDock.circleSize,
                    height: StashyExpandingDock.circleSize
                )
                .background(StashyExpandingDock.inactiveBackground)
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sync(limit: Int?) {
        guard let entry else { return }
        if entry.resolvedKind == .tag {
            downloadManager.syncTagImages(entryId: entryId, limit: limit)
        } else {
            downloadManager.syncGallery(id: entryId, limit: limit)
        }
    }

    /// Same construction as `GalleryCardView`: image, 40%-height gradient, title in `.headline`.
    @ViewBuilder
    private func thumbnail(_ image: DownloadedGalleryImage) -> some View {
        let url = downloadManager.thumbnailURL(for: image)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        ZStack {
                            Color.gray.opacity(0.2)
                            if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: image.isVideo ? "film" : "photo.on.rectangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()

                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geometry.size.height * 0.4)

                        VStack {
                            HStack {
                                Spacer()
                                if image.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(8)

                            Spacer()

                            HStack(alignment: .bottom) {
                                Text(image.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                     ? image.title! : "Untitled")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                        }
                    }
                }
            )
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .cardShadow()
    }
}

/// Offline counterpart to `FullScreenImageView`. Mirrors it deliberately: vertical paging,
/// zoom, tap-to-hide chrome, top nav bar and a bottom info row — only the data comes from disk.
struct DownloadedGalleryFullScreenView: View {
    let images: [DownloadedGalleryImage]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var navigationBackTrigger: UUID?
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var currentVisibleId: String?
    @State private var showUI = true
    @State private var isZoomed = false
    @State private var isMuted: Bool = ScenePlayerMute.initialValue()
    @State private var isPlaying = true
    @State private var scrubberState = ScrubberState()

    private var activeId: String {
        currentVisibleId ?? (images.indices.contains(startIndex) ? images[startIndex].id : (images.first?.id ?? ""))
    }

    private var currentImage: DownloadedGalleryImage? {
        images.first { $0.id == activeId }
    }

    private var currentIndex: Int {
        images.firstIndex { $0.id == activeId } ?? 0
    }

    private var chromePillHeight: CGFloat { StashyExpandingDock.activeHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(images) { image in
                            page(image)
                                .scrollDisabled(isZoomed)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .background(Color.black)
                                .id(image.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollDisabled(isZoomed)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentVisibleId)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .ignoresSafeArea()
            }
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea()
            .statusBarHidden(!showUI)
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            // Custom chrome hides the nav bar, which also kills the edge swipe — restore it.
            .enableSwipeBackWhenNavBarHidden()
            .background {
                StashyNavigationBackTrigger(trigger: $navigationBackTrigger) {
                    dismiss()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showUI, !StashyChromePlacement.prefersBottom {
                    navBar.transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if showUI, StashyChromePlacement.prefersBottom {
                        navBar.transition(.opacity)
                    }
                    playbackControls
                    infoOverlay
                    scrubberBar
                }
                .allowsHitTesting(showUI)
            }
            .onChange(of: currentVisibleId) { _, _ in
                // New page starts playing and resets the scrubber, like the online viewer.
                isPlaying = true
                scrubberState.time = 0
                scrubberState.duration = 1
                scrubberState.seeking = false
                scrubberState.seekTarget = nil
            }
            .animation(.easeInOut(duration: 0.2), value: showUI)
            .task {
                guard currentVisibleId == nil else { return }
                currentVisibleId = activeId
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(activeId, anchor: .top)
            }
        }
    }

    private var navBar: some View {
        StashySectionChromeBar {
            HStack(spacing: 8) {
                Button { navigationBackTrigger = UUID() } label: {
                    HStack(spacing: StashyExpandingDock.iconLabelSpacing) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                        Text("Back")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer(minLength: 8)

                Text("\(currentIndex + 1) / \(images.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                    .modifier(StashyChromePillStyle(height: chromePillHeight))
            }
            .frame(minHeight: chromePillHeight)
            .padding(.horizontal, StashyExpandingDock.edgePadding)
            .padding(.vertical, 8)
        }
    }

    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// Mute and play/pause, in their own row above the caption — same arrangement as Feeds.
    @ViewBuilder
    private var playbackControls: some View {
        let isVideo = currentImage?.isVideo ?? false
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ChromeCircleButton(
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                enabled: isVideo,
                accessibilityLabel: isMuted ? "Ton an" : "Stumm"
            ) {
                if isVideo {
                    isMuted.toggle()
                    ScenePlayerMute.persist(isMuted)
                }
            }
            ChromeCircleButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                enabled: isVideo,
                accessibilityLabel: isPlaying ? "Pause" : "Play"
            ) {
                if isVideo { isPlaying.toggle() }
            }
        }
        .padding(.horizontal, StashyExpandingDock.edgePadding)
        .padding(.bottom, 8)
        .colorScheme(.dark)
        .opacity(showUI ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: showUI)
    }

    /// Only videos have something to scrub; stills keep the height so the chrome does not jump.
    @ViewBuilder
    private var scrubberBar: some View {
        IsolatedScrubberBar(state: scrubberState, isUIVisible: showUI)
            .opacity((currentImage?.isVideo ?? false) ? 1 : 0)
            .allowsHitTesting(currentImage?.isVideo ?? false)
    }

    /// Performer · title line plus tag chips — same layout and typography as the online viewer's
    /// `feedsStyleInfoOverlay`, fed from the metadata stored at download time.
    @ViewBuilder
    private var infoOverlay: some View {
        if let image = currentImage {
            let performers = image.performerNames ?? []
            let tags = image.tagNames ?? []
            let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !performers.isEmpty || !title.isEmpty || !tags.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    if let performer = performers.first {
                        // No cached profile picture offline — initials stand in for the round
                        // thumbnail the online viewer shows.
                        Circle()
                            .fill(appearance.tintColor.opacity(0.2))
                            .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                            .overlay {
                                Text(Self.initials(for: performer))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .overlay(Circle().stroke(appearance.tintColor, lineWidth: 2))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let performer = performers.first {
                            Text(performer)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            if !title.isEmpty {
                                Text("-")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }

                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                }
                            }
                        }
                        .frame(height: 20)
                    }
                    }
                }
                .padding(.horizontal, StashyExpandingDock.edgePadding)
                .padding(.bottom, 2)
                .colorScheme(.dark)
                .opacity(showUI ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showUI)
            }
        }
    }

    @ViewBuilder
    private func page(_ image: DownloadedGalleryImage) -> some View {
        DownloadedGalleryItemView(
            image: image,
            currentVisibleId: $currentVisibleId,
            fallbackActiveId: activeId,
            showUI: $showUI,
            isZoomed: $isZoomed,
            isMuted: $isMuted,
            isPlaying: $isPlaying,
            scrubberState: scrubberState
        )
    }
}

/// Offline counterpart to `GalleryItemView`: same player embedding (`FullScreenVideoPlayer` over
/// `AVPlayerLayer`, not AVKit's `VideoPlayer`), same autoplay rule — only the active page plays.
struct DownloadedGalleryItemView: View {
    let image: DownloadedGalleryImage
    @Binding var currentVisibleId: String?
    let fallbackActiveId: String
    @Binding var showUI: Bool
    @Binding var isZoomed: Bool
    @Binding var isMuted: Bool
    @Binding var isPlaying: Bool
    let scrubberState: ScrubberState

    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    /// The player the observer belongs to — removing it from another instance raises a fatal
    /// AVFoundation exception.
    @State private var timeObserverPlayer: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    private var isActiveItem: Bool {
        image.id == (currentVisibleId ?? fallbackActiveId)
    }

    /// Local file extension — the metadata only flags video, animation has to come from the path.
    private var isAnimated: Bool {
        let ext = (image.localPath as NSString).pathExtension.uppercased()
        return ext == "GIF" || ext == "WEBP"
    }

    private var url: URL { downloadManager.localURL(for: image) }

    var body: some View {
        ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
            withAnimation(.easeInOut(duration: 0.4)) { showUI.toggle() }
        }) {
            content
        }
        .onAppear {
            if image.isVideo, isActiveItem { setupPlayer() }
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: currentVisibleId) { _, _ in
            guard image.isVideo else { return }
            if isActiveItem {
                if player == nil { setupPlayer() }
                if isPlaying { player?.play() }
            } else {
                player?.pause()
            }
        }
        .onChange(of: isMuted) { _, muted in
            player?.isMuted = muted
        }
        .onChange(of: isPlaying) { _, playing in
            guard isActiveItem else { return }
            if playing { player?.play() } else { player?.pause() }
        }
        .onChange(of: scrubberState.seekTarget) { _, target in
            guard isActiveItem, let target else { return }
            player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAnimated, let data = try? Data(contentsOf: url) {
            AnimatedWebView(data: data, fillMode: false)
        } else if image.isVideo {
            if let player {
                FullScreenVideoPlayer(player: player, videoGravity: .resizeAspect)
            } else {
                Color.black
            }
        } else if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                Text("File missing")
            }
            .foregroundColor(.white)
        }
    }

    private func setupPlayer() {
        teardownPlayer()
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = isMuted
        newPlayer.actionAtItemEnd = .none
        player = newPlayer
        if isActiveItem, isPlaying { newPlayer.play() }

        // Loop, matching the online viewer's continuous playback. The token is kept so the
        // observer can actually be removed later — block observers ignore `removeObserver(self:)`.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        timeObserverPlayer = newPlayer
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak newPlayer] time in
            guard let newPlayer, isActiveItem else { return }
            if !scrubberState.seeking {
                scrubberState.time = time.seconds
            }
            if let duration = newPlayer.currentItem?.duration.seconds, duration > 0, !duration.isNaN {
                scrubberState.duration = duration
            }
        }
    }

    private func teardownPlayer() {
        if let timeObserver {
            timeObserverPlayer?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }
}

#endif
