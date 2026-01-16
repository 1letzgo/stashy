//
//  DownloadsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit

struct DownloadsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var store = SubscriptionManager.shared
    @State private var showingPaywall = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        } else {
            return [GridItem(.flexible(), spacing: 12)]
        }
    }
    
    var body: some View {
        ZStack {

            
            if !store.isPremium {
                VStack(spacing: 24) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.1))
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "play.square.stack.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.appAccent)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Stashtok VIP Feature")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Become stashy VIP to unlock Stashtok and offline downloads.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    Button {
                        showingPaywall = true
                    } label: {
                        Text("Upgrade for 0,99€ / Month")
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(Color.appAccent)
                            .clipShape(Capsule())
                    }
                    
                    Button {
                        Task {
                            await SubscriptionManager.shared.restorePurchases()
                        }
                    } label: {
                        Text("Restore Purchase")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .sheet(isPresented: $showingPaywall) {
                    PaywallView()
                }
            } else {

                if downloadManager.downloads.isEmpty && downloadManager.activeDownloads.isEmpty {
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
                            .padding(.horizontal)
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
                                        .padding(.horizontal)
                                    
                                    ForEach(Array(downloadManager.activeDownloads.values), id: \.id) { download in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(download.title)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .lineLimit(1)
                                            
                                            ProgressView(value: download.progress)
                                                .tint(appearanceManager.tintColor)
                                            
                                            Text("\(Int(download.progress * 100))%")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                        .background(Color(UIColor.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.top)
                            }
                            
                            // Completed Downloads Section
                            if !downloadManager.downloads.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    if !downloadManager.activeDownloads.isEmpty {
                                        Text("Completed")
                                            .font(.headline)
                                            .padding(.horizontal)
                                    }
                                    
                                    LazyVStack(spacing: 12) {
                                        ForEach(downloadManager.downloads) { downloaded in
                                            NavigationLink(destination: DownloadDetailView(downloaded: downloaded)) {
                                                DownloadedSceneCard(downloaded: downloaded)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.top, downloadManager.activeDownloads.isEmpty ? 16 : 0)
                            }
                        }
                    }
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
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
    @State private var isMuted = !isHeadphonesConnected()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Video Player
                VStack(spacing: 0) {
                    if isPlaybackStarted, let player = player {
                        VideoPlayerView(player: player, isFullscreen: $isFullScreen)
                            .aspectRatio(16/9, contentMode: .fit) // Keep 16:9 for consistency or use nil for 9:16
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                    .fill(Color.black.opacity(0.4))
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
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if player == nil {
                                let videoURL = downloadManager.getLocalVideoURL(for: downloaded)
                                player = createPlayer(for: videoURL)
                                player?.isMuted = isMuted
                            }
                            withAnimation {
                                isPlaybackStarted = true
                            }
                            player?.play()
                        }
                    }
                }
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                
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
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle("Offline Scene")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    let videoURL = downloadManager.getLocalVideoURL(for: downloaded)
                    shareVideo(url: videoURL)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
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
