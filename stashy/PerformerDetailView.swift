//
//  PerformerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

import SwiftUI


struct PerformerDetailView: View {
    let performer: Performer
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var refreshTrigger = UUID()
    @State private var isHeaderExpanded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var fullPerformer: Performer?
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "performer_detail") ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        selectedSortOption = newOption
        
        // Save to TabManager (Session)
        TabManager.shared.setDetailSortOption(for: "performer_detail", option: newOption.rawValue)
        
        // Force view refresh
        refreshTrigger = UUID()
        
        // Fetch new data immediately
        viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: newOption, isInitialLoad: true)
    }
    
    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        } else {
            return [GridItem(.flexible(), spacing: 12)]
        }
    }
    
    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
             return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        }
    }

    private var displayPerformer: Performer {
        fullPerformer ?? performer
    }
    
    private var effectiveScenes: Int {
        max(viewModel.totalPerformerScenes, displayPerformer.sceneCount)
    }
    
    private var effectiveGalleries: Int {
        max(viewModel.totalPerformerGalleries, displayPerformer.galleryCount ?? 0)
    }
    
    private var showTabSwitcher: Bool {
        effectiveScenes > 0 && effectiveGalleries > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView(displayPerformer: displayPerformer)

                if selectedDetailTab == .scenes {
                    if !viewModel.performerScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingPerformerScenes {
                        VStack {
                            ProgressView()
                            Text("Loading scenes...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No scenes found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else {
                    if !viewModel.performerGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingPerformerGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .onAppear {
            loadData()
            isFavorite = performer.favorite ?? false
        }
        .onChange(of: viewModel.totalPerformerGalleries) { oldValue, newValue in
            // Switch to galleries only if no scenes exist and galleries are found
            if !viewModel.isLoadingPerformerScenes && viewModel.totalPerformerScenes == 0 && newValue > 0 {
                selectedDetailTab = .galleries
            }
        }
        .onChange(of: viewModel.totalPerformerScenes) { oldValue, newValue in
            if newValue > 0 {
                // If scenes are found, always favor scenes tab (as requested)
                selectedDetailTab = .scenes
            } else if newValue == 0 && viewModel.totalPerformerGalleries > 0 {
                // If scenes explicitly become 0 (or are 0 after load), switch to galleries
                selectedDetailTab = .galleries
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            print("🔄 SceneDeleted - Re-loading performer data")
            viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: selectedSortOption, isInitialLoad: true)
            loadPerformerMetadata()
        }
        .navigationTitle("")
#if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                if showTabSwitcher {
                    Picker("View", selection: $selectedDetailTab) {
                        Text("Scenes").tag(DetailTab.scenes)
                        Text("Galleries").tag(DetailTab.galleries)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                } else {
                    Text(displayPerformer.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                     Button {
                         guard !isUpdatingFavorite else { return }
                         isUpdatingFavorite = true
                         let newState = !isFavorite
                         isFavorite = newState
                         
                         viewModel.togglePerformerFavorite(performerId: performer.id, favorite: newState) { success in
                             DispatchQueue.main.async {
                                 if !success {
                                     isFavorite = !newState
                                 }
                                 isUpdatingFavorite = false
                             }
                         }
                     } label: {
                         Image(systemName: isFavorite ? "heart.fill" : "heart")
                             .foregroundColor(isFavorite ? .red : appearanceManager.tintColor)
                     }

                    if selectedDetailTab == .scenes {
                        sceneSortMenu
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views & Methods
    
    private func loadData() {
        if viewModel.performerScenes.isEmpty && !viewModel.isLoadingPerformerScenes {
            viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        if viewModel.performerGalleries.isEmpty && !viewModel.isLoadingPerformerGalleries {
            viewModel.fetchPerformerGalleries(performerId: performer.id, isInitialLoad: true)
        }
        
        // Only load metadata if we don't have enough details (like gender/ethnicity)
        if performer.gender == nil || performer.ethnicity == nil {
            loadPerformerMetadata()
        }
    }
    
    private func loadPerformerMetadata() {
        viewModel.fetchPerformer(performerId: performer.id) { fetchedPerformer in
             if let p = fetchedPerformer {
                 self.fullPerformer = p
             }
        }
    }
    
    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.performerScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingPerformerScenes {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more scenes...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
            } else if viewModel.hasMorePerformerScenes {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMorePerformerScenes(performerId: performer.id) }
            }
        }
        .id(refreshTrigger)
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.performerGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingPerformerGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMorePerformerGalleries {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMorePerformerGalleries(performerId: performer.id) }
             }
        }
    }
    
    private var sceneSortMenu: some View {
        Menu {
            ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                Button(action: { changeSortOption(to: option) }) {
                    HStack {
                        Text(option.displayName)
                        if option == selectedSortOption { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
             Image(systemName: "arrow.up.arrow.down").foregroundColor(appearanceManager.tintColor)
        }
    }

    private func headerView(displayPerformer: Performer) -> some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait, flush to edges, cropped from top
            ZStack(alignment: .bottom) {
                if let thumbnailURL = displayPerformer.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(0.1))
                                .overlay(ProgressView().scaleEffect(0.6))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            defaultThumbnailContent(width: imageWidth)
                        }
                    }
                } else {
                    defaultThumbnailContent(width: imageWidth)
                }
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(0.1))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name and Stats
                HStack(alignment: .top, spacing: 8) {
                    Text(displayPerformer.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)
                    
                    Spacer()
                    
                    // Stats Badges (Top Right)
                    HStack(spacing: 4) {
                        let galleryCount = displayPerformer.galleryCount ?? viewModel.totalPerformerGalleries
                        if galleryCount > 0 {
                            cardBadge(icon: "photo.stack", text: "\(galleryCount)")
                        }
                        cardBadge(icon: "film", text: "\(displayPerformer.sceneCount)")
                        
                        // StashTok Button
                        Button(action: {
                            let sp = ScenePerformer(id: displayPerformer.id, name: displayPerformer.name, sceneCount: displayPerformer.sceneCount, galleryCount: displayPerformer.galleryCount)
                            coordinator.navigateToReels(performer: sp)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.square.stack")
                                    .font(.system(size: 10, weight: .bold))
                                Text("StashTok")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // Grid for Performer Info
                let allDetails = getPerformerDetails(displayPerformer)
                let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
                
                if !visibleDetails.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            Group {
                let allDetails = getPerformerDetails(displayPerformer)
                if allDetails.count > 4 {
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

    private func cardBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(appearanceManager.tintColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(appearanceManager.tintColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(0.1))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(Image(systemName: "person.fill").font(.system(size: 32)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func thumbnailBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }

    private func detailStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(appearanceManager.tintColor)
            Text(text).font(.caption).fontWeight(.bold).foregroundColor(.primary)
        }
    }

    private func getPerformerDetails(_ p: Performer) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        if let val = p.gender, !val.isEmpty { list.append((label: "GENDER", value: val)) }
        if let val = p.fakeTits, !val.isEmpty { list.append((label: "Tits", value: val)) }
        if let val = p.birthdate, !val.isEmpty { list.append((label: "BORN", value: val)) }
        if let val = p.country, !val.isEmpty { list.append((label: "COUNTRY", value: val)) }
        if let val = p.ethnicity, !val.isEmpty { list.append((label: "ETHNICITY", value: val)) }
        if let val = p.height, val > 0 { list.append((label: "HEIGHT", value: "\(val) cm")) }
        if let val = p.weight, val > 0 { list.append((label: "WEIGHT", value: "\(val) kg")) }
        if let val = p.measurements, !val.isEmpty { list.append((label: "MEASUREMENTS", value: val)) }
        if let val = p.careerLength, !val.isEmpty { list.append((label: "CAREER", value: val)) }
        if let val = p.tattoos, !val.isEmpty { list.append((label: "TATTOOS", value: val)) }
        if let val = p.piercings, !val.isEmpty { list.append((label: "PIERCINGS", value: val)) }
        
        return list
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let samplePerformer = Performer(
        id: "1",
        name: "Sample Performer",
        disambiguation: "Test",
        birthdate: "1990-01-01",
        country: "Germany",
        imagePath: nil,
        sceneCount: 5,
        galleryCount: 1,
        gender: "Female",
        ethnicity: "Caucasian",
        height: 165,
        weight: 55,
        measurements: "34-24-34",
        fakeTits: "No",
        careerLength: "5 years",
        tattoos: "None",
        piercings: "Navel",
        aliasList: ["Jane Doe", "J.D."],
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil
    )
    PerformerDetailView(performer: samplePerformer)
}
