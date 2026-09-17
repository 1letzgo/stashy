//
//  DownloadsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct DownloadsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var jobStore = DownloadSyncJobStore.shared
    /// Own view model: the sync jobs need the server's saved filters.
    @StateObject private var viewModel = StashDBViewModel()

    @State private var gridWidth: CGFloat = 0
    @State private var showingJobSheet = false
    @State private var showingRunAllConfirmation = false
    @State private var jobToDelete: DownloadSyncJob?

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

            VStack(spacing: 0) {
            syncJobRow

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
                        // Running transfers first, then what waits for a slot — both full width.
                        let active = downloadManager.activeDownloads.values
                            .filter { !downloadManager.queuedSceneIds.contains($0.id) }
                            .sorted { $0.title < $1.title }
                        let queued = downloadManager.activeDownloads.values
                            .filter { downloadManager.queuedSceneIds.contains($0.id) }
                            .sorted { $0.title < $1.title }

                        if !active.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                downloadsSectionHeading("Active Downloads")
                                VStack(spacing: 12) {
                                    ForEach(active, id: \.id) { download in
                                        activeDownloadRow(download)
                                    }
                                }
                                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                            }
                        }

                        if !queued.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                downloadsSectionHeading("Queued")
                                VStack(spacing: 12) {
                                    ForEach(queued, id: \.id) { download in
                                        queuedDownloadRow(download)
                                    }
                                }
                                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                            }
                        }

                        // Completed Downloads Section
                        if !downloadManager.downloads.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                downloadsSectionHeading("Scenes")
                                
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(downloadManager.downloads) { downloaded in
                                        NavigationLink(destination: DownloadDetailView(downloaded: downloaded)) {
                                            DownloadedSceneCard(downloaded: downloaded)
                                        }
                                        .buttonStyle(.plain)
                                        .stashySwipeActions([
                                            StashySwipeAction(title: "Delete", systemImage: "trash", tint: AppearanceManager.shared.tintColor, isDestructive: true) {
                                                downloadManager.deleteDownload(id: downloaded.id)
                                            }
                                        ])
                                    }
                                }
                                .measuresGridWidth($gridWidth)
                                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                            }
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
                    .padding(.top, DesignTokens.Tools.menuTopPadding)
                    .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                }
            }
            }
        }
        .onAppear {
            jobStore.load()
            if viewModel.savedFilters.isEmpty { viewModel.fetchSavedFilters() }
        }
        .sheet(isPresented: $showingJobSheet) {
            DownloadSyncJobSheet(savedFilters: viewModel.savedFilters) { job in
                jobStore.add(job)
            }
        }
        .alert("Run all jobs?", isPresented: $showingRunAllConfirmation) {
            Button("Run all") {
                DownloadSyncJobRunner.runAll(jobStore.jobs, filters: viewModel.savedFilters, viewModel: viewModel)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each job downloads its configured number of newest items. Items already downloaded are skipped.")
        }
        .alert("Delete job?", isPresented: Binding(get: { jobToDelete != nil }, set: { if !$0 { jobToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let job = jobToDelete { jobStore.remove(job) }
                jobToDelete = nil
            }
            Button("Cancel", role: .cancel) { jobToDelete = nil }
        } message: {
            Text(jobToDelete.map { "\($0.filterName) stays on the server; only the job goes away." } ?? "")
        }
    }

    /// A transfer in flight: title, progress bar, percentage.
    @ViewBuilder
    private func activeDownloadRow(_ download: ActiveDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(download.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            // Images count files, scene files count bytes — both report a fraction.
            ProgressView(value: min(max(download.progress, 0), 1))
                .tint(appearanceManager.tintColor)
            Text(progressCaption(for: download))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    /// "42% · 12,3 MB of 280 MB · 4,1 MB/s", or "7 of 50 images" for an image download.
    private func progressCaption(for download: ActiveDownload) -> String {
        var parts: [String] = ["\(Int(min(max(download.progress, 0), 1) * 100))%"]
        if download.totalUnits > 0 {
            parts.append("\(download.completedUnits) of \(download.totalUnits) images")
        } else if download.totalSize > 0 {
            parts.append("\(ByteCountFormatter.string(fromByteCount: download.downloadedSize, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: download.totalSize, countStyle: .file))")
        } else if download.downloadedSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: download.downloadedSize, countStyle: .file))
        }
        if download.speed > 0 {
            parts.append("\(ByteCountFormatter.string(fromByteCount: Int64(download.speed), countStyle: .file))/s")
        }
        return parts.joined(separator: " · ")
    }

    /// Waiting for one of the two transfer slots.
    @ViewBuilder
    private func queuedDownloadRow(_ download: ActiveDownload) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(download.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Queued")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    // MARK: - Sync jobs

    /// Heading, run-all button and one pill per job — the same shape the merge templates use.
    @ViewBuilder
    private var syncJobRow: some View {
        VStack(alignment: .leading, spacing: 12) {
        downloadsSectionHeading("Sync Jobs")
        HStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                showingRunAllConfirmation = true
            } label: {
                Image(systemName: "play.square.stack.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(jobStore.jobs.isEmpty ? .secondary : appearanceManager.tintColor)
                    .frame(width: 40, height: 44)
                    .background(Color.secondaryAppBackground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(jobStore.jobs.isEmpty)
            .accessibilityLabel("Run all sync jobs")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(jobStore.jobs) { job in
                        Button {
                            HapticManager.light()
                            DownloadSyncJobRunner.run(job, filters: viewModel.savedFilters, viewModel: viewModel)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Image(systemName: job.kind.icon)
                                        .font(.caption2)
                                    Text(job.filterName)
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(1)
                                }
                                Text(job.amountLabel)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .opacity(0.75)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .frame(height: 44)
                            .background(Color.secondaryAppBackground)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        // Long press deletes, as on the merge template pills.
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                HapticManager.light()
                                jobToDelete = job
                            }
                        )
                    }

                    Button {
                        showingJobSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(appearanceManager.tintColor)
                            .frame(width: 40, height: 44)
                            .background(Color.secondaryAppBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New sync job")
                }
            }
        }
        .padding(.horizontal, DesignTokens.Tools.contentPadding)
        }
        .padding(.top, DesignTokens.Tools.menuTopPadding)
        .padding(.bottom, DesignTokens.Spacing.md)
    }
}

/// Picks a saved filter and the number of newest items one run should fetch.
private struct DownloadSyncJobSheet: View {
    let savedFilters: [String: StashDBViewModel.SavedFilter]
    let onSave: (DownloadSyncJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var selectedFilterId: String?
    @State private var amount: Int = 5
    @State private var downloadsEverything = false
    @State private var search = ""

    private var usableFilters: [StashDBViewModel.SavedFilter] {
        savedFilters.values
            .filter { $0.mode == .scenes || $0.mode == .images }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Filter name", text: $search)
                        .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                } header: {
                    sectionHeader("Search …")
                }

                Section {
                    ForEach(usableFilters) { filter in
                        // Plain row with a tap gesture: a `Button` inside a themed list row
                        // did not reliably register the tap.
                        HStack(spacing: DesignTokens.Spacing.sm) {
                                Image(systemName: filter.mode == .scenes ? "film" : "photo")
                                    .foregroundStyle(.secondary)
                                Text(filter.name)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                                Spacer()
                            if selectedFilterId == filter.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(appearance.tintColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedFilterId = filter.id }
                        .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                        .listRowSeparatorTint(Color.primary.opacity(0.15))
                    }
                    if usableFilters.isEmpty {
                        Text("No scene or image filters on this server")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                    }
                } header: {
                    sectionHeader("Filter")
                }

                Section {
                    Toggle(isOn: $downloadsEverything) {
                        Text("All matching items")
                    }
                    .tint(appearance.tintColor)
                    .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))

                    if !downloadsEverything {
                        Stepper("Newest \(amount)", value: $amount, in: 1...500, step: amount < 20 ? 1 : 10)
                            .listRowBackground(Color.secondaryAppBackground(for: appearance.currentTheme))
                    }
                } header: {
                    sectionHeader("Amount per run")
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(DesignTokens.Spacing.md)
            .contentMargins(.horizontal, DesignTokens.Tools.contentPadding, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground(for: appearance.currentTheme))
            // Room for the pinned save button below the form.
            .contentMargins(.bottom, 12, for: .scrollContent)
            .stashyModalSheetChrome("New sync job", onBack: { dismiss() })
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let id = selectedFilterId, let filter = savedFilters[id] else { return }
                    onSave(DownloadSyncJob(
                        filterId: id,
                        filterName: filter.name,
                        kind: filter.mode == .images ? .images : .scenes,
                        amount: downloadsEverything ? 0 : amount
                    ))
                    dismiss()
                } label: {
                    Text("Save job")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.secondaryAppBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedFilterId == nil)
                .padding(.horizontal, DesignTokens.Tools.contentPadding)
                // Just enough air above so the button does not touch the last row.
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(Color.appBackground(for: appearance.currentTheme))
            }
        }
    }

    /// Small caps header, as in Tools › Filters.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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

                // Watched progress, as on the online scene cards.
                if let resume = downloaded.resumeTime, resume > 0,
                   let duration = downloaded.duration, duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.25))
                            Rectangle()
                                .fill(appearanceManager.tintColor)
                                .frame(width: geo.size.width * min(1, resume / duration))
                        }
                    }
                    .frame(width: 130, height: 3)
                    .frame(width: 130, height: 100, alignment: .bottom)
                }

                // Duration Badge (Bottom Right)
                if let duration = downloaded.duration, duration > 0 {
                    Text(formatDuration(duration))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .stashyGlass(shape: Capsule())
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
    @State private var engine: AetherSceneEngine?
    @State private var isPlaybackStarted = false
    /// Latest playhead, written back to the download metadata every few seconds.
    @State private var localPlayhead: Double = 0
    @State private var lastResumeWrite: Date = .distantPast
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
                    .foregroundColor(.white)
                    .modifier(StashyChromePillStyle(height: chromePillHeight, accent: true))
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
                        .stashyGlass(shape: Capsule(style: .continuous))
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
                    if isPlaybackStarted, let engine, !isFullScreen {
                        AetherSceneSurface(
                            engine: engine,
                            posterURL: nil,
                            isMuted: $isMuted,
                            onSeek: { seconds in seekTo(seconds) },
                            onToggleFullscreen: { isFullScreen = true },
                            isFullscreen: false
                        )
                        .aspectRatio(16/9, contentMode: .fit) // Keep 16:9 for consistency or use nil for 9:16
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    } else if isPlaybackStarted, isFullScreen {
                        // The fullscreen cover owns the engine's layer while it is up.
                        Color.black
                            .aspectRatio(16/9, contentMode: .fit)
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
                            
                            // Resume / play, the same pair the online scene page shows.
                            if let resume = storedResumeTime, resume > 0 {
                                VStack(spacing: 16) {
                                    Button {
                                        startPlayback(resume: true)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "clock.arrow.circlepath")
                                            Text("Resume from \(formatDuration(resume))")
                                                .fontWeight(.bold)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(appearanceManager.tintColor)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        startPlayback(resume: false)
                                    } label: {
                                        Text("Start from beginning")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(appearanceManager.tintColor)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
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
                        }
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .overlay(alignment: .bottom) {
                            if let resume = storedResumeTime, resume > 0,
                               let duration = downloaded.duration, duration > 0 {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Color.white.opacity(0.25))
                                        Rectangle()
                                            .fill(appearanceManager.tintColor)
                                            .frame(width: geo.size.width * min(1, resume / duration))
                                    }
                                }
                                .frame(height: 4)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard storedResumeTime == nil else { return }
                            startPlayback()
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
        .fullScreenCover(isPresented: $isFullScreen) {
            fullscreenPlayer
        }
        .unmutesOnHardwareVolume($isMuted)
        .onChange(of: isMuted) { _, muted in
            engine?.isMuted = muted
        }
        .onDisappear {
            teardownPlayer()
        }
    }

    /// Own fullscreen presentation: the same engine, rebound to a full-bleed surface.
    @ViewBuilder
    private var fullscreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let engine {
                AetherSceneSurface(
                    engine: engine,
                    posterURL: nil,
                    isMuted: $isMuted,
                    onSeek: { seconds in seekTo(seconds) },
                    onToggleFullscreen: { isFullScreen = false },
                    isFullscreen: true
                )
                .ignoresSafeArea()
            }
        }
    }

    /// Position stored for this file, kept live so it shows right after playback ends.
    private var storedResumeTime: Double? {
        downloadManager.downloads.first(where: { $0.id == downloaded.id })?.resumeTime
    }

    /// Local file URL — the engine skips auth headers for `file://`.
    private func startPlayback(resume: Bool = true) {
        let videoURL = downloadManager.getLocalVideoURL(for: downloaded)
        let storedResume = downloadManager.downloads.first(where: { $0.id == downloaded.id })?.resumeTime
        let startAt: Double? = resume ? storedResume : nil

        if engine == nil {
            guard let created = try? AetherSceneEngine() else {
                AppLog.error("DownloadDetailView: playback engine could not be created")
                ToastManager.shared.show(
                    "Playback engine unavailable",
                    icon: "exclamationmark.triangle",
                    style: .error
                )
                return
            }
            created.isMuted = isMuted
            created.audioSessionPolicy = .playback
            engine = created
            created.onTime = { time, duration in
                guard time >= 0 else { return }
                localPlayhead = time
                // Same cadence as the online tracker: every 10 s, plus once on teardown.
                if Date().timeIntervalSince(lastResumeWrite) >= 10 {
                    lastResumeWrite = Date()
                    downloadManager.updateLocalResumeTime(id: downloaded.id, seconds: time, duration: duration)
                }
            }
            Task { @MainActor in
                await created.load(url: videoURL, startAt: (startAt ?? 0) > 1 ? startAt : nil, autoplay: true)
            }
        }

        withAnimation {
            isPlaybackStarted = true
        }
        engine?.play()
    }

    private func seekTo(_ seconds: Double) {
        guard let engine else { return }
        Task { @MainActor in
            await engine.seek(to: seconds)
        }
    }

    /// `@State` release is not deterministic — the engine has to be stopped by hand.
    private func teardownPlayer() {
        guard !isFullScreen, let engine else { return }
        if localPlayhead > 0 {
            downloadManager.updateLocalResumeTime(
                id: downloaded.id,
                seconds: localPlayhead,
                duration: engine.duration > 0 ? engine.duration : downloaded.duration
            )
        }
        engine.onTime = nil
        engine.stop()
        self.engine = nil
        isPlaybackStarted = false
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
            downloadsSectionHeading(title)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entries) { entry in
                    NavigationLink(destination: DownloadedGalleryDetailView(entryId: entry.id)) {
                        DownloadedGalleryCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .stashySwipeActions(swipeActions(for: entry))
                }
            }
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
        }
    }

    /// Sync and delete for a downloaded gallery / tag — behind a swipe to the left on the row.
    private func swipeActions(for entry: DownloadedGallery) -> [StashySwipeAction] {
        var actions: [StashySwipeAction] = []
        if !entry.isSingleImage {
            actions.append(StashySwipeAction(title: "Sync", systemImage: "arrow.triangle.2.circlepath", tint: .gray) {
                if entry.resolvedKind == .tag {
                    downloadManager.syncTagImages(entryId: entry.id, limit: nil)
                } else {
                    downloadManager.syncGallery(id: entry.id, limit: nil)
                }
            })
        }
        actions.append(StashySwipeAction(title: "Delete", systemImage: "trash", tint: AppearanceManager.shared.tintColor, isDestructive: true) {
            downloadManager.deleteGalleryDownload(id: entry.id)
        })
        return actions
    }

    /// Small caps footnote, flush with the content edge — same header look as the other Tools.
    @ViewBuilder
    func downloadsSectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, DesignTokens.Tools.contentPadding)
    }
}

/// Row for a downloaded gallery or single image, with sync / delete actions.
struct DownloadedGalleryCard: View {
    let entry: DownloadedGallery
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared

    private var isSyncing: Bool { downloadManager.activeDownloads[entry.id] != nil }

    var body: some View {
        // Cover flush with the card's leading edge, straight on the right — the scene cards
        // are built the same way.
        HStack(spacing: 0) {
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
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
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
                .padding(.trailing, DesignTokens.Spacing.sm)
                .accessibilityLabel("Cancel download")
            }
            // No "more" button: the row's actions live behind a swipe to the left.
        }
        .frame(height: 72)
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
        .frame(width: 96, height: 72)
        .clipped()
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
                .stashyGlass(shape: Capsule(style: .continuous))
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
                                        .stashyGlass(shape: Capsule())
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
                    .foregroundColor(.white)
                    .modifier(StashyChromePillStyle(height: chromePillHeight, accent: true))
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

    /// Only videos have something to scrub. A still shows no bar at all — an invisible one
    /// still took up its height under the caption.
    @ViewBuilder
    private var scrubberBar: some View {
        if currentImage?.isVideo == true {
            IsolatedScrubberBar(state: scrubberState, isUIVisible: showUI)
        }
    }

    /// Performer · title line, the trailing control stack and the tag row — the same three
    /// pieces the online viewer's `feedsStyleInfoOverlay` shows, fed from the metadata stored
    /// at download time.
    @ViewBuilder
    private var infoOverlay: some View {
        if let image = currentImage {
            let performers = image.performerNames ?? []
            let tags = image.tagNames ?? []
            let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isVideo = image.isVideo

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        if let performer = performers.first {
                            // No cached profile picture offline — initials stand in for the
                            // round thumbnail the online viewer shows.
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
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 8)

                    // Mute · Play stacked on the trailing edge. Rating and the O-counter are
                    // server state, so the offline viewer has no use for them.
                    VStack(alignment: .trailing, spacing: 8) {
                        ChromePillIconButton(
                            systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            enabled: isVideo,
                            accessibilityLabel: isMuted ? "Ton an" : "Stumm"
                        ) {
                            if isVideo {
                                isMuted.toggle()
                                ScenePlayerMute.persist(isMuted)
                            }
                        }

                        ChromePillIconButton(
                            systemImage: isPlaying ? "pause.fill" : "play.fill",
                            enabled: isVideo,
                            accessibilityLabel: isPlaying ? "Pause" : "Play"
                        ) {
                            if isVideo { isPlaying.toggle() }
                        }
                    }
                }
                .padding(.horizontal, StashyExpandingDock.edgePadding)

                // Hashtags on their own full-width row under the title / controls row.
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
                        .padding(.horizontal, StashyExpandingDock.edgePadding)
                    }
                    .frame(height: 24)
                    .padding(.top, 6)
                }
            }
            .padding(.bottom, 2)
            .colorScheme(.dark)
            .opacity(showUI ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showUI)
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

/// Offline counterpart to `GalleryItemView`: same engine embedding, same autoplay rule —
/// only the active page plays. The source is a local file, so `load` skips the auth headers.
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
    /// One engine per page, reused across item changes.
    @State private var engine: AetherSceneEngine?

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
                if engine == nil { setupPlayer() }
                if isPlaying { engine?.play() }
            } else {
                engine?.pause()
            }
        }
        .unmutesOnHardwareVolume($isMuted)
        .onChange(of: isMuted) { _, muted in
            engine?.isMuted = muted
        }
        .onChange(of: isPlaying) { _, playing in
            guard isActiveItem else { return }
            if playing { engine?.play() } else { engine?.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stashyPauseBackgroundPlayers)) { _ in
            engine?.pause()
            isPlaying = false
        }
        .onChange(of: scrubberState.seekTarget) { _, target in
            guard isActiveItem, let target, let engine else { return }
            Task { @MainActor in
                await engine.seek(to: target)
                if self.isPlaying { engine.play() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAnimated, let data = try? Data(contentsOf: url) {
            AnimatedWebView(data: data, fillMode: false)
        } else if image.isVideo {
            if let engine {
                AetherVideoSurface(engine: engine, videoGravity: .resizeAspect)
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
        let fileURL = url
        let autoplay = isActiveItem && isPlaying

        if let existing = engine {
            existing.isMuted = isMuted
            bindEngineCallbacks(on: existing)
            existing.prepareForItemReplacement()
            Task { @MainActor in
                await existing.load(url: fileURL, startAt: nil, autoplay: autoplay)
            }
            return
        }

        guard let created = try? AetherSceneEngine() else {
            AppLog.error("DownloadedGalleryItemView: playback engine could not be created")
            return
        }
        created.isMuted = isMuted
        created.audioSessionPolicy = .playback
        created.setVideoGravity(.resizeAspect)
        bindEngineCallbacks(on: created)
        engine = created
        Task { @MainActor in
            await created.load(url: fileURL, startAt: nil, autoplay: autoplay)
        }
    }

    /// Time into the scrubber; the loop is the engine's own, matching the online viewer.
    private func bindEngineCallbacks(on engine: AetherSceneEngine) {
        engine.loopsAtEnd = true
        let scrubber = scrubberState
        engine.onTime = { time, duration in
            guard self.isActiveItem else { return }
            if !scrubber.seeking {
                scrubber.time = time
            }
            if duration > 0, !duration.isNaN {
                scrubber.duration = duration
            }
        }
    }

    /// `@State` release is not deterministic — the engine has to be stopped by hand.
    private func teardownPlayer() {
        guard let engine else { return }
        engine.onTime = nil
        engine.stop()
        self.engine = nil
    }
}

#endif
