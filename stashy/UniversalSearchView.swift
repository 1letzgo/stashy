//
//  UniversalSearchView.swift
//  stashy
//

#if !os(tvOS)
import SwiftUI

struct UniversalSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.dismissSearch) private var dismissSearch
    
    @State private var searchText = ""
    @State private var isSearching = false
    /// The running search. Every keystroke used to start 8 parallel queries with no
    /// cancellation, and a slow earlier answer could land after — and replace — a newer one.
    @State private var searchTask: Task<Void, Never>?
    
    // Search results
    @State private var performers: [Performer] = []
    @State private var studios: [Studio] = []
    @State private var tags: [Tag] = []
    @State private var scenes: [Scene] = []
    @State private var images: [StashImage] = []
    @State private var galleries: [Gallery] = []
    @State private var groups: [StashGroup] = []
    @State private var markers: [SceneMarker] = []
    
    // Per-category result limits
    private let scenesLimit = 20
    private let imagesLimit = 20
    private let performersLimit = 20
    private let galleriesLimit = 20
    private let tagsLimit = 50
    private let studiosLimit = 50
    private let groupsLimit = 20
    private let markersLimit = 20
    
    /// Result rows in the order of the views on Home (Settings › Home Tabs), hidden views left out.
    private var orderedSections: [AppTab] {
        let resultTypes: Set<AppTab> = [.scenes, .images, .galleries, .performers, .studios, .tags, .groups, .markers]
        return tabManager.tabs
            .filter { resultTypes.contains($0.id) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.id }
    }

    /// Card sizes of the Home rows, so results read like the dashboard.
    private let landscapeCardWidth: CGFloat = 125 * 16 / 9
    private let squareCardSide: CGFloat = 125
    private static let performerRowConfig = HomeRowConfig(
        id: UUID(), title: "", isEnabled: true, sortOrder: 0, type: .newPerformers
    )

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            // A fixed sibling of the content below: it keeps focus when the content switches
            // between the empty state and the results (first letter, clearing).
            RegularWidthSearchField(text: $searchText)
            Group {
                if configManager.activeConfig == nil {
                    // No server configured: the only way forward is Settings.
                    ConnectionErrorView { coordinator.selectedTab = .settings }
                } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    // The search starts at two characters; one is not "no results".
                    emptySearchView
                } else {
                    searchResultsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
            .navigationTitle(tr("search"))
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .modifier(SystemSearchField(text: $searchText))
            .onChange(of: searchText) { oldValue, newValue in
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.count < 2 {
                    clearResults()
                } else {
                    performSearch()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
                guard let targetId = notification.userInfo?["performerId"] as? String,
                      let newPath = notification.userInfo?["newImagePath"] as? String else { return }

                var updatedPerformers = performers
                for i in updatedPerformers.indices where updatedPerformers[i].id == targetId {
                    updatedPerformers[i].imagePath = newPath
                }
                performers = updatedPerformers

                var updatedGalleries = galleries
                for i in updatedGalleries.indices {
                    guard var mutablePerformers = updatedGalleries[i].performers,
                          let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId }) else { continue }
                    mutablePerformers[pIndex].image_path = newPath
                    updatedGalleries[i].performers = mutablePerformers
                }
                galleries = updatedGalleries
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text(tr("search_your_library"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(tr("hint_find_scenes_images_performers_studios"))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Also under the keyboard: its rounded top corners show what lies behind it.
        .background { Color.appBackground.ignoresSafeArea() }
    }
    
    // MARK: - Search Results
    
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if isSearching {
                    StandardLoadingView(message: "Searching...", fillsScreen: false)
                } else {
                    ForEach(orderedSections, id: \.self) { section in
                        sectionView(for: section)
                    }

                    if orderedSections.allSatisfy({ isEmpty($0) }) {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)

                            Text(tr("empty_results_for_arg", searchText))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background { Color.appBackground.ignoresSafeArea() }
    }

    private func isEmpty(_ tab: AppTab) -> Bool {
        switch tab {
        case .scenes: return scenes.isEmpty
        case .images: return images.isEmpty
        case .galleries: return galleries.isEmpty
        case .performers: return performers.isEmpty
        case .studios: return studios.isEmpty
        case .tags: return tags.isEmpty
        case .groups: return groups.isEmpty
        case .markers: return markersWithScene.isEmpty
        default: return true
        }
    }

    /// A marker card opens its scene at the marker; one without a scene has nowhere to go.
    private var markersWithScene: [SceneMarker] {
        markers.filter { $0.scene != nil }
    }

    // MARK: - Section Views

    /// The same cards as the Home rows and the catalog lists.
    @ViewBuilder
    private func sectionView(for tab: AppTab) -> some View {
        switch tab {
        case .scenes where !scenes.isEmpty:
            resultRow(tr("scenes"), items: scenes, showAll: {
                coordinator.navigateToScenes(search: searchText, noDefaultFilter: true)
            }, destination: { SceneDetailView(scene: $0) }) { scene in
                HomeSceneCardView(scene: scene, isLarge: false)
            }
        case .images where !images.isEmpty:
            resultRow(tr("images"), items: images, showAll: {
                coordinator.navigateToImages(search: searchText)
            }, destination: { FullScreenImageView(images: $images, selectedImageId: $0.id) }) { image in
                // The list's pills do not fit a 125 pt card: the picture with a Home-style caption.
                ImageThumbnailCard(image: image, showsOverlayChrome: false)
                    .frame(width: squareCardSide, height: squareCardSide)
                    .overlay(alignment: .bottomLeading) { imageCaption(image) }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            }
        case .galleries where !galleries.isEmpty:
            resultRow(tr("galleries"), items: galleries, showAll: {
                coordinator.navigateToGalleries(search: searchText)
            }, destination: { ImagesView(gallery: $0) }) { gallery in
                GalleryCardView(gallery: gallery, compactTitle: true)
                    .frame(width: squareCardSide, height: squareCardSide)
            }
        case .performers where !performers.isEmpty:
            resultRow(tr("performers"), items: performers, showAll: {
                coordinator.navigateToPerformers(search: searchText)
            }, destination: { PerformerDetailView(performer: $0) }) { performer in
                HomePerformerCardView(performer: performer, config: Self.performerRowConfig, screenWidth: 0)
            }
        case .studios where !studios.isEmpty:
            resultRow(tr("studios"), items: studios, showAll: {
                coordinator.navigateToStudios(search: searchText)
            }, destination: { StudioDetailView(studio: $0) }) { studio in
                StudioCardView(studio: studio)
                    .frame(width: landscapeCardWidth)
            }
        case .tags where !tags.isEmpty:
            resultRow(tr("tags"), items: tags, showAll: {
                coordinator.navigateToTags(search: searchText)
            }, destination: { TagDetailView(selectedTag: $0) }) { tag in
                TagCardView(tag: tag)
                    .frame(width: landscapeCardWidth)
            }
        case .groups where !groups.isEmpty:
            resultRow(tr("groups"), items: groups, showAll: {
                coordinator.navigateToGroups(search: searchText)
            }, destination: { GroupDetailView(selectedGroup: $0) }) { group in
                GroupCardView(group: group)
                    .frame(width: squareCardSide)
            }
        case .markers where !markersWithScene.isEmpty:
            resultRow(tr("markers"), items: markersWithScene, showAll: {
                coordinator.navigateToMarkers(search: searchText)
            }, destination: { marker in
                SceneDetailView(scene: marker.scene!.toScene().withResumeTime(marker.seconds), autoPlay: true)
            }) { marker in
                MarkerCardView(marker: marker)
                    .frame(width: landscapeCardWidth)
            }
        default:
            EmptyView()
        }
    }

    /// The Images list card's name (first performer, else title, else file name) on a dark
    /// fade, like the titles on the Home cards.
    @ViewBuilder
    private func imageCaption(_ image: StashImage) -> some View {
        let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = image.performers?.first?.name
            ?? (title?.isEmpty == false ? title : nil)
            ?? image.visual_files?.first?.basename
        if let name, !name.isEmpty {
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundColor(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
                .background(
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                )
                .allowsHitTesting(false)
        }
    }

    /// One result row, laid out like a Home row: title with a chevron (opens the full list
    /// searched for the same text), cards in a horizontal scroller below.
    private func resultRow<Item: Identifiable, Card: View, Destination: View>(
        _ title: String,
        items: [Item],
        showAll: @escaping () -> Void,
        @ViewBuilder destination: @escaping (Item) -> Destination,
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: showAll) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("hint_shows_all_arg_matching_search", title.lowercased()))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(destination: searchPushDestination { destination(item) }) {
                            card(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    /// Dismisses the Search field so pushed custom-chrome details are not covered by the native search bar.
    @ViewBuilder
    private func searchPushDestination<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .onAppear { dismissSearch() }
    }

    // MARK: - Search Logic
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            clearResults()
            return
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            clearResults()
            return
        }
        
        isSearching = true
        searchTask?.cancel()

        // Run all searches in parallel using async let
        searchTask = Task { @MainActor in
            // Debounce: typing cancels this before any request goes out.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let performersTask = viewModel.searchPerformersAsync(query: query, limit: performersLimit)
            async let studiosTask = viewModel.searchStudiosAsync(query: query, limit: studiosLimit)
            async let tagsTask = viewModel.searchTagsAsync(query: query, limit: tagsLimit)
            async let scenesTask = viewModel.searchScenesAsync(query: query, limit: scenesLimit)
            async let imagesTask = viewModel.searchImagesAsync(query: query, limit: imagesLimit)
            async let galleriesTask = viewModel.searchGalleriesAsync(query: query, limit: galleriesLimit)
            async let groupsTask = viewModel.searchGroupsAsync(query: query, limit: groupsLimit)
            async let markersTask = viewModel.searchMarkersAsync(query: query, limit: markersLimit)
            
            // Await all results
            let (performersResult, studiosResult, tagsResult, scenesResult, imagesResult, galleriesResult, groupsResult, markersResult) = await (
                performersTask,
                studiosTask,
                tagsTask,
                scenesTask,
                imagesTask,
                galleriesTask,
                groupsTask,
                markersTask
            )
            
            // Drop answers for a query the user already typed past.
            guard !Task.isCancelled,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

            // Update state on main actor
            performers = performersResult
            studios = studiosResult
            tags = tagsResult
            scenes = scenesResult
            images = imagesResult
            galleries = galleriesResult
            groups = groupsResult
            markers = markersResult
            isSearching = false
        }
    }
    
    private func clearResults() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        performers = []
        studios = []
        tags = []
        scenes = []
        images = []
        galleries = []
        groups = []
        markers = []
    }
}

/// At regular width (iPad, open iPhone Duo) the system puts a search tab's field beside the
/// floating tab bar (on narrower windows only a round button), and while it is active it hides
/// the tab bar with no way back. There the field is the page's own bar above the results
/// (`RegularWidthSearchField`) and the tab bar stays; compact width keeps the system field.
private struct SystemSearchField: ViewModifier {
    @Binding var text: String
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            content
        } else {
            content.searchable(text: $text, prompt: tr("placeholder_search_everything"))
        }
        #else
        content.searchable(text: $text, prompt: tr("placeholder_search_everything"))
        #endif
    }
}

/// The page's own search field at regular width; nothing at compact width (system field).
private struct RegularWidthSearchField: View {
    @Binding var text: String
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .regular {
            InlineSearchField(text: $text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        #endif
    }
}

#if os(iOS)
private struct InlineSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(tr("placeholder_search_everything"), text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { isFocused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("action_clear_search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .stashyGlass(shape: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}
#endif

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in containerWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > containerWidth && x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: containerWidth, height: y + maxHeight)
        }
    }
}
#endif
