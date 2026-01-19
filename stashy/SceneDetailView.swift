//
//  SceneDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI
import AVFoundation
import AVKit

struct SceneDetailView: View {
    let scene: Scene
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeScene: Scene
    @StateObject private var viewModel = StashDBViewModel()
    
    init(scene: Scene) {
        self.scene = scene
        _activeScene = State(initialValue: scene)
    }
    @State private var player: AVPlayer?
    @State private var showDeleteWithFilesConfirmation = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var isHeaderExpanded = false
    @State private var isTagsExpanded = false
    @State private var isFullscreen = false
    @State private var isPlaybackStarted = false
    @State private var tagsTotalHeight: CGFloat = 0
    @State private var showingPaywall = false
    @State private var isMuted = !isHeadphonesConnected()
    @State private var hasAddedPlay = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    // Preview Video State
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewing = false
    @State private var isPressing = false
    
    // Extracted toolbar content to reduce body complexity
    @ToolbarContentBuilder
    private var sceneToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                // Download Button
                if downloadManager.isDownloaded(id: activeScene.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if let activeDownload = downloadManager.activeDownloads[activeScene.id] {
                    ZStack {
                        Circle()
                            .stroke(appearanceManager.tintColor.opacity(0.3), lineWidth: 2.5)
                        
                        Circle()
                            .trim(from: 0, to: activeDownload.progress)
                            .stroke(appearanceManager.tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: activeDownload.progress)
                    }
                    .frame(width: 18, height: 18)
                } else {
                    Button {
                        if SubscriptionManager.shared.isPremium {
                            downloadManager.downloadScene(activeScene)
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }

                // Delete Button
                Button(role: .destructive) {
                    showDeleteWithFilesConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
    }

    private var videoPlayerCard: some View {
        VStack(spacing: 0) {
            if activeScene.videoURL != nil {
                if isPlaybackStarted, let player = player {
                    VideoPlayerView(player: player, isFullscreen: $isFullscreen)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Preview/Poster state with Play Button
                    ZStack {
                        // Background / Thumbnail - constrained to 16:9
                        GeometryReader { geo in
                            if let url = activeScene.thumbnailURL {
                                CustomAsyncImage(url: url) { loader in
                                    if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .clipped()
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.1))
                                            .skeleton()
                                    }
                                }
                            } else {
                                // No thumbnail - show placeholder
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
                        
                        // Play Buttons Overlay (Hide when previewing)
                        if !isPreviewing {
                            if let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                                VStack(spacing: 16) {
                                    Button(action: { startPlayback(resume: true) }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "clock.arrow.circlepath")
                                            Text("Resume from \(formatTime(resumeTime))")
                                                .fontWeight(.bold)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(appearanceManager.tintColor)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.3), radius: 5)
                                    }
                                    
                                    Button(action: { startPlayback(resume: false) }) {
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
                            } else {
                                // Large Play Button Overlay
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.4))
                                        .frame(width: 70, height: 70)
                                        .blur(radius: 1)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 2) // Visually center the play triangle
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    startPlayback(resume: false)
                                }
                            }
                            
                            // Persistent Progress Bar at the bottom of the thumbnail area
                            if let resumeTime = activeScene.resumeTime, resumeTime > 0, let duration = activeScene.sceneDuration, duration > 0 {
                                ProgressView(value: resumeTime, total: duration)
                                    .progressViewStyle(LinearProgressViewStyle(tint: appearanceManager.tintColor))
                                    .frame(height: 4)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                        isPressing = pressing
                        if pressing {
                            startPreview()
                        } else {
                            stopPreview()
                        }
                    }, perform: {})
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title and Rating in same row
            HStack(alignment: .top) {
                Text(activeScene.title ?? "Unbekannter Titel")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 12) {
                    StarRatingView(
                        rating100: activeScene.rating100,
                        isInteractive: true,
                        size: 16,
                        spacing: 2
                    ) { newRating in
                        viewModel.updateSceneRating(sceneId: activeScene.id, rating100: newRating) { success in
                            if success {
                                DispatchQueue.main.async {
                                    var updatedScene = self.activeScene
                                    updatedScene = updatedScene.withRating(newRating)
                                    self.activeScene = updatedScene
                                }
                            }
                        }
                    }
                    
                    // O-Counter (Manual)
                    Button(action: {
                        viewModel.incrementOCounter(sceneId: activeScene.id) { newCount in
                            if let count = newCount {
                                DispatchQueue.main.async {
                                    self.activeScene = self.activeScene.withOCounter(count)
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text("\(activeScene.oCounter ?? 0)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Metadata Line
            HStack(spacing: 16) {
                if let date = activeScene.date {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(appearanceManager.tintColor)
                        Text(date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let duration = activeScene.sceneDuration {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(appearanceManager.tintColor)
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let playCount = activeScene.playCount, playCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(appearanceManager.tintColor)
                        Text("\(playCount) plays")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundColor(appearanceManager.tintColor)
                        Text("Resume: \(formatTime(resumeTime))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Description Section
            if let details = activeScene.details, !details.isEmpty {
                Text(details)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(isHeaderExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .padding(.bottom, (activeScene.details?.isEmpty ?? true) ? 0 : 20) // Extra space for button if description exists
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            Group {
                if let details = activeScene.details, !details.isEmpty {
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
    }

    private var markersCard: some View {
        Group {
            if let markers = activeScene.sceneMarkers, !markers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(markers.sorted { $0.seconds < $1.seconds }) { marker in
                                Button(action: {
                                    seekTo(marker.seconds)
                                }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Marker Image
                                        ZStack(alignment: .bottomTrailing) {
                                            if let url = marker.thumbnailURL {
                                                CustomAsyncImage(url: url) { loader in
                                                    if let image = loader.image {
                                                        image
                                                             .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 80, height: 45)
                                                            .clipped()
                                                    } else {
                                                        Rectangle()
                                                            .fill(Color.gray.opacity(0.1))
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
                                                .background(Color.black.opacity(0.6))
                                                .foregroundColor(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .padding(.top, 12)
                    }
                }
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
        }
    }

    private var performersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performers")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(activeScene.performers.sorted { $0.name < $1.name }) { scenePerformer in
                    NavigationLink(destination: PerformerDetailView(performer: scenePerformer.toPerformer())) {
                        ZStack(alignment: .bottom) {
                            // Thumbnail Circle
                            ZStack {
                                if let url = scenePerformer.thumbnailURL {
                                     CustomAsyncImage(url: url) { loader in
                                         if let image = loader.image {
                                             image
                                                 .resizable()
                                                 .scaledToFill()
                                                 .frame(width: 80, height: 80, alignment: .top)
                                                 .clipShape(Circle())
                                         } else {
                                             Circle()
                                                 .fill(Color.gray.opacity(0.1))
                                                 .frame(width: 80, height: 80)
                                                 .skeleton()
                                         }
                                     }
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 80, height: 80)
                                        .foregroundColor(appearanceManager.tintColor.opacity(0.4))
                                }
                            }
                            .padding(4)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.2), lineWidth: 1))
                            
                            // Name Pill Overlaid at Bottom
                            Text(scenePerformer.name)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(appearanceManager.tintColor)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .offset(y: 8) // Push it slightly over the bottom edge
                        }
                        .padding(.bottom, 8) // Make room for the offset name
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var studioCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Studio")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let studio = activeScene.studio {
                VStack {
                    NavigationLink(destination: StudioDetailView(studio: studio.toStudio())) {
                        ZStack(alignment: .bottom) {
                            // Dummy Studio Thumbnail (Circle)
                            ZStack {
                                Image(systemName: "building.2.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
                                    .foregroundColor(appearanceManager.tintColor.opacity(0.4))
                            }
                            .frame(width: 80, height: 80)
                            .padding(4)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.2), lineWidth: 1))
                            
                            // Name Pill Overlaid at Bottom
                            Text(studio.name)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(appearanceManager.tintColor)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                .offset(y: 8)
                        }
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var galleriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Galleries")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let galleries = activeScene.galleries, !galleries.isEmpty {
                WrappedHStack(items: galleries) { gallery in
                    NavigationLink(destination: GalleryDetailView(gallery: gallery)) {
                        HStack(spacing: 6) {
                            if let url = gallery.coverURL {
                                CustomAsyncImage(url: url) { loader in
                                    if let image = loader.image {
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 14, height: 14)
                                            .foregroundColor(appearanceManager.tintColor.opacity(0.5))
                                            .frame(width: 32, height: 32)
                                            .background(appearanceManager.tintColor.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                }
                            } else {
                                Image(systemName: "photo.on.rectangle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(appearanceManager.tintColor.opacity(0.5))
                                    .frame(width: 32, height: 32)
                                    .background(appearanceManager.tintColor.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            
                            Text("Images")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .padding(.leading, 4)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .foregroundColor(appearanceManager.tintColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                Text("No linked galleries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    private var tagsCard: some View {
        let collapsedHeight: CGFloat = 68 // Exakt 2 Zeilen
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            
            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let tags = activeScene.tags {
                        WrappedHStack(items: tags) { tag in
                            NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                                 Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(appearanceManager.tintColor.opacity(0.1))
                                    .foregroundColor(appearanceManager.tintColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    tagsTotalHeight = geo.size.height
                                }
                                .onChange(of: geo.size.height) { old, newValue in
                                    tagsTotalHeight = newValue
                                }
                            }
                        )
                    }
                }
                .frame(maxHeight: isTagsExpanded ? .none : collapsedHeight, alignment: .topLeading)
                .clipped()
                
                if tagsTotalHeight > collapsedHeight {
                    Button(action: {
                        withAnimation(.spring()) {
                            isTagsExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isTagsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // Extracted main content to reduce body complexity
    private var mainContentView: some View {
        ScrollView {
            VStack(spacing: 12) {
                videoPlayerCard
                
                markersCard
                
                infoCard

                if !activeScene.performers.isEmpty || activeScene.studio != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if !activeScene.performers.isEmpty {
                            performersCard
                        }
                        
                        if activeScene.studio != nil {
                            studioCard
                        }
                    }
                }

                if let galleries = activeScene.galleries, !galleries.isEmpty {
                    galleriesCard
                }
                
                if let tags = activeScene.tags, !tags.isEmpty {
                    tagsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        mainContentView
            .background(Color.appBackground)
            .navigationTitle(scene.title ?? "Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                sceneToolbarContent
            }
        .alert("Really delete scene and files?", isPresented: $showDeleteWithFilesConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteSceneWithFiles()
            }
        } message: {
            Text("The scene '\(activeScene.title ?? "Unknown Title")' and all associated files will be permanently deleted. This action cannot be undone.")
        }
        .onAppear {
            // Ensure state is reset when view appears
            print("🔍 Scene Data (Initial): ID=\(activeScene.id), PlayCount=\(activeScene.playCount ?? -1), ResumeTime=\(activeScene.resumeTime ?? -1)")
            isFullscreen = false
            
            // Refresh scene details to get latest resume time and play count
            viewModel.fetchSceneDetails(sceneId: activeScene.id) { updatedScene in
                if let updated = updatedScene {
                    DispatchQueue.main.async {
                        self.activeScene = updated
                        print("✅ Scene data refreshed: ResumeTime=\(updated.resumeTime ?? 0)")
                    }
                }
            }
        }
        .onDisappear {
            if !isFullscreen {
                player?.pause()
            }
            stopPreview()
            
            // Determine current resume time
            let currentTime = player?.currentTime().seconds
            let effectiveResumeTime = (currentTime != nil && currentTime! > 0) ? currentTime! : activeScene.resumeTime
            
            // Save and notify parent views if we have a resume time
            if let resumeTime = effectiveResumeTime, resumeTime > 0 {
                let sceneId = activeScene.id
                
                // Only save to server if player was used
                if currentTime != nil && currentTime! > 0 {
                    viewModel.updateSceneResumeTime(sceneId: sceneId, resumeTime: resumeTime) { success in
                        if success {
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("SceneResumeTimeUpdated"),
                                    object: nil,
                                    userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                                )
                            }
                        }
                    }
                } else {
                    // Just notify with existing resume time (no save needed)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SceneResumeTimeUpdated"),
                        object: nil,
                        userInfo: ["sceneId": sceneId, "resumeTime": resumeTime]
                    )
                }
            }
        }
        .onChange(of: isMuted) { _, newValue in
            player?.isMuted = newValue
        }
        .onReceive(timer) { _ in
            // Periodically save progress while playing
            if let player = player, player.timeControlStatus == .playing {
                let currentTime = player.currentTime().seconds
                if currentTime > 0 {
                    viewModel.updateSceneResumeTime(sceneId: activeScene.id, resumeTime: currentTime)
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private func startPlayback(resume: Bool) {
        guard let videoURL = activeScene.videoURL else { return }
        
        if player == nil {
            player = createPlayer(for: videoURL)
            player?.isMuted = isMuted
            
            if resume, let resumeTime = activeScene.resumeTime, resumeTime > 0 {
                let targetTime = CMTime(seconds: resumeTime, preferredTimescale: 600)
                player?.seek(to: targetTime)
            }
        } else if resume, let resumeTime = activeScene.resumeTime, resumeTime > 0 {
             let targetTime = CMTime(seconds: resumeTime, preferredTimescale: 600)
             player?.seek(to: targetTime)
        }
        
        withAnimation {
            isPlaybackStarted = true
        }
        player?.play()
        
        if !hasAddedPlay {
            viewModel.addScenePlay(sceneId: activeScene.id)
            hasAddedPlay = true
        }
    }

    private func deleteSceneWithFiles() {
        guard let config = ServerConfigManager.shared.loadConfig(),
              config.hasValidConfig else {
            print("❌ No valid server configuration found")
            return
        }

        // Collect all file IDs for deleteFiles
        let fileIds = scene.files?.compactMap { $0.id } ?? []

        print("🗂️ Scene '\(scene.title ?? "Unknown")' has \(fileIds.count) files to delete: \(fileIds)")

        // Step 1: Delete scene metadata
        let sceneMutation = """
        mutation {
            sceneDestroy(input: { id: "\(scene.id)" })
        }
        """

        let sceneRequestBody: [String: Any] = ["query": sceneMutation]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let sceneJsonData = try? JSONSerialization.data(withJSONObject: sceneRequestBody) else {
            print("❌ Error creating Scene deletion request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // API Key hinzufügen, falls vorhanden
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            print("🗑️ DELETE SCENE: API Key is being used")
        }
        
        request.httpBody = sceneJsonData

        print("🌐 Sending request to: \(url.absoluteString)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error during deletion: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 HTTP Status Code: \(httpResponse.statusCode)")

                    if let data = data,
                       let responseString = String(data: data, encoding: .utf8) {
                        print("📄 Server Response: \(responseString)")
                    }

                    if httpResponse.statusCode == 200 {
                        // Prüfe die GraphQL-Response
                        if let data = data {
                            do {
                                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                    if let dataDict = jsonResponse["data"] as? [String: Any],
                                       dataDict["sceneDestroy"] != nil {
                                        print("✅ Scene metadata successfully deleted!")

                                        // Step 2: Delete files if present
                                        if !fileIds.isEmpty {
                                            self.deleteSceneFiles(fileIds: fileIds, config: config)
                                        } else {
                                            print("ℹ️ No files to delete")
                                            NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": self.scene.id])
                                            self.dismiss()
                                        }
                                    } else if let errors = jsonResponse["errors"] as? [[String: Any]] {
                                        print("❌ GraphQL Error:")
                                        for error in errors {
                                            if let message = error["message"] as? String {
                                                print("   \(message)")
                                            }
                                        }
                                    } else {
                                        print("❌ Unexpected GraphQL response: \(jsonResponse)")
                                    }
                                }
                            } catch {
                                print("❌ Error parsing JSON response: \(error)")
                            }
                        }
                    } else {
                        print("❌ HTTP error \(httpResponse.statusCode) during scene deletion")
                    }
                } else {
                    print("❌ No HTTP Response received")
                }
            }
        }.resume()
    }

    private func deleteSceneFiles(fileIds: [String], config: ServerConfig) {
        print("🗂️ Deleting \(fileIds.count) files: \(fileIds)")

        // deleteFiles Mutation
        let filesMutation = """
        mutation DeleteFiles($ids: [ID!]!) {
            deleteFiles(ids: $ids)
        }
        """

        let variables: [String: Any] = [
            "ids": fileIds
        ]

        let requestBody: [String: Any] = [
            "query": filesMutation,
            "variables": variables
        ]

        guard let url = URL(string: "\(config.baseURL)/graphql"),
              let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Error creating files deletion request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // API Key hinzufügen, falls vorhanden
        if let apiKey = config.secureApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            print("🗑️ DELETE FILES: API Key is being used")
        }
        
        request.httpBody = jsonData

        print("🌐 Sending Files-Delete request to: \(url.absoluteString)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error while deleting files: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Files-Delete HTTP Status Code: \(httpResponse.statusCode)")

                    if let data = data,
                       let responseString = String(data: data, encoding: .utf8) {
                        print("📄 Files-Delete Server Response: \(responseString)")
                    }

                    if httpResponse.statusCode == 200 {
                        // Prüfe die GraphQL-Response für deleteFiles
                        if let data = data {
                            do {
                                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                                    if let dataDict = jsonResponse["data"] as? [String: Any],
                                       dataDict["deleteFiles"] != nil {
                                        print("✅ Files successfully deleted!")
                                        print("🎉 Scene and all files have been completely removed!")
                                        NotificationCenter.default.post(name: NSNotification.Name("SceneDeleted"), object: nil, userInfo: ["sceneId": self.scene.id])
                                        self.dismiss()
                                    } else if let errors = jsonResponse["errors"] as? [[String: Any]] {
                                        print("❌ Error while deleting files:")
                                        for error in errors {
                                            if let message = error["message"] as? String {
                                                print("   \(message)")
                                            }
                                        }
                                    } else {
                                        print("❌ Unexpected GraphQL response for deleteFiles: \(jsonResponse)")
                                    }
                                }
                            } catch {
                                print("❌ Error parsing JSON response for deleteFiles: \(error)")
                            }
                        }
                    } else {
                        print("❌ HTTP Error \(httpResponse.statusCode) while deleting files")
                    }
                } else {
                    print("❌ No HTTP Response for Files-Delete received")
                }
            }
        }.resume()
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
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
        previewPlayer?.seek(to: .zero)
    }
    
    private func seekTo(_ seconds: Double) {
        if !isPlaybackStarted {
            startPlayback(resume: false)
        }
        
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        player?.play()
    }
}

// Extensions for Scene conversion

// Extend Scene to include videoURL computed property
// Extend Scene to include videoURL computed property
// REMOVED: Now in StashDBViewModel.swift

// Extension to convert ScenePerformer to Performer for navigation
extension ScenePerformer {
    var thumbnailURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/performer/\(id)/image")
    }

    func toPerformer() -> Performer {
        return Performer(
            id: self.id,
            name: self.name,
            disambiguation: nil,
            birthdate: nil,
            country: nil,
            imagePath: nil,
            sceneCount: self.sceneCount ?? 0,
            galleryCount: self.galleryCount ?? 0,
            gender: nil,
            ethnicity: nil,
            height: nil,
            weight: nil,
            measurements: nil,
            fakeTits: nil,
            careerLength: nil,
            tattoos: nil,
            piercings: nil,
            aliasList: nil,
            favorite: nil,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

// Extension to convert SceneStudio to Studio for navigation
extension SceneStudio {
    func toStudio() -> Studio {
        return Studio(
            id: self.id,
            name: self.name,
            url: nil,
            sceneCount: 0,
            performerCount: nil,
            galleryCount: nil,
            details: nil,
            imagePath: nil,
            favorite: nil,
            rating100: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

// Simple WrappedHStack for Flow Layout
struct WrappedHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
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

