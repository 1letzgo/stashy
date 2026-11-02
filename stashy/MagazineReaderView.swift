//
//  MagazineReaderView.swift
//  stashy
//
//  The Magazin reader: a gallery as two-page spreads (side by side in landscape, stacked in
//  portrait), a tap opens one page fullscreen. iOS turns pages with a real page curl.
//

import SwiftUI

// MARK: - Page order

enum MagazinePageOrder {
    /// Numeric file order (`2.jpg` before `10.jpg`). The server has no natural sort on file names
    /// that the app could ask for, so the whole gallery is sorted here after loading.
    static func sorted(_ images: [StashImage]) -> [StashImage] {
        images
            .map { (image: $0, key: sortKey(for: $0)) }
            .sorted { lhs, rhs in
                switch lhs.key.localizedStandardCompare(rhs.key) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.image.id < rhs.image.id
                }
            }
            .map(\.image)
    }

    private static func sortKey(for image: StashImage) -> String {
        let file = image.visual_files?.first
        return file?.path ?? file?.basename ?? image.title ?? image.id
    }
}

// MARK: - Reader

struct MagazineReaderView: View {
    let gallery: Gallery
    let onClose: () -> Void

    private static let loadPageSize = 200

    @State private var pages: [StashImage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var spreadIndex = 0
    @State private var fullscreenPage = 0
    @State private var showsFullscreen = false
    /// Stays false until the saved position is applied, so it cannot be overwritten with page 1.
    @State private var didRestorePosition = false
    @Environment(\.scenePhase) private var scenePhase
    /// Next and previous pages, loaded ahead into `ImageCache`.
    @State private var prefetchers: [URL: ImageLoader] = [:]
    #if os(macOS)
    @FocusState private var hasKeyboardFocus: Bool
    #endif

    private var spreadCount: Int { (pages.count + 1) / 2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
            }

            if showsFullscreen {
                MagazineFullscreenView(pages: pages, page: $fullscreenPage, onClose: closeFullscreen)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await loadPages() }
        .onChange(of: spreadIndex) { _, _ in pageDidChange() }
        .onChange(of: fullscreenPage) { _, _ in pageDidChange() }
        .onChange(of: showsFullscreen) { _, _ in updatePrefetch() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pushReadingPosition() }
        }
        .onAppear { IdleTimerCoordinator.shared.setActive(true, for: "magazineReader") }
        .onDisappear {
            IdleTimerCoordinator.shared.setActive(false, for: "magazineReader")
            cancelPrefetch()
            pushReadingPosition()
        }
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) {
            if showsFullscreen { closeFullscreen() } else { onClose() }
            return .handled
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Could not load pages", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") { Task { await loadPages() } }
            }
        } else if pages.isEmpty {
            ContentUnavailableView("No pages", systemImage: "photo.on.rectangle")
        } else {
            MagazinePager(count: spreadCount, index: $spreadIndex) { index in
                MagazineSpreadView(
                    pages: pagesOfSpread(index),
                    firstPageIndex: index * 2,
                    onSelectPage: openFullscreen
                )
            }
            #if os(macOS)
            .overlay {
                MagazineStepButtons(
                    canGoBack: spreadIndex > 0,
                    canGoForward: spreadIndex < spreadCount - 1,
                    step: step
                )
            }
            #endif
        }
    }

    /// Stays visible while reading: a tap on a page is taken by the fullscreen view.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(gallery.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if !pages.isEmpty {
                Text(pageLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.trailing, spreadIndex > 0 ? 0 : 16)
            }

            if spreadIndex > 0 {
                Button(action: resetReadingPosition) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset position")
            }
        }
    }

    private var pageLabel: String {
        let first = spreadIndex * 2 + 1
        let last = min(first + 1, pages.count)
        return first == last ? "Page \(first) / \(pages.count)" : "Page \(first)–\(last) / \(pages.count)"
    }

    private func pagesOfSpread(_ index: Int) -> [StashImage] {
        Array(pages[(index * 2)..<min(index * 2 + 2, pages.count)])
    }

    private func openFullscreen(_ page: Int) {
        HapticManager.light()
        fullscreenPage = page
        withAnimation(.easeOut(duration: 0.2)) { showsFullscreen = true }
    }

    private func closeFullscreen() {
        spreadIndex = fullscreenPage / 2
        withAnimation(.easeOut(duration: 0.2)) { showsFullscreen = false }
    }

    #if os(macOS)
    private func step(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if showsFullscreen {
                fullscreenPage = min(max(fullscreenPage + delta, 0), pages.count - 1)
            } else {
                spreadIndex = min(max(spreadIndex + delta, 0), max(spreadCount - 1, 0))
            }
        }
    }
    #endif

    private func loadPages() async {
        isLoading = true
        errorMessage = nil
        let repository = GalleryRepository()
        var loaded: [StashImage] = []
        var seen = Set<String>()
        var page = 1
        do {
            while true {
                let result = try await repository.fetchGalleryImages(
                    galleryId: gallery.id,
                    page: page,
                    perPage: Self.loadPageSize,
                    sortBy: .titleAsc
                )
                for image in result.images where seen.insert(image.id).inserted {
                    loaded.append(image)
                }
                if result.images.isEmpty || page * Self.loadPageSize >= result.total { break }
                page += 1
            }
            pages = MagazinePageOrder.sorted(loaded.filter { !$0.isVideo })
            await restoreReadingPosition()
            updatePrefetch()
        } catch {
            if Task.isCancelled { return }
            AppLog.error("Magazin: loading pages failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: Reading position

    private func restoreReadingPosition() async {
        let store = MagazineReadingStore.shared
        await store.sync(galleryIds: [gallery.id])
        if let page = store.entries[gallery.id]?.page, !pages.isEmpty {
            spreadIndex = (min(max(page, 1), pages.count) - 1) / 2
        }
        didRestorePosition = true
        // Opening counts as reading, even without turning a page.
        noteReadingPosition()
    }

    private func resetReadingPosition() {
        HapticManager.light()
        spreadIndex = 0
        MagazineReadingStore.shared.resetPosition(galleryId: gallery.id)
    }

    private func pageDidChange() {
        updatePrefetch()
        noteReadingPosition()
    }

    private func noteReadingPosition() {
        guard didRestorePosition, !pages.isEmpty else { return }
        let page = showsFullscreen ? fullscreenPage : spreadIndex * 2
        MagazineReadingStore.shared.note(page: page + 1, galleryId: gallery.id)
    }

    private func pushReadingPosition() {
        let galleryId = gallery.id
        Task { await MagazineReadingStore.shared.pushIfNeeded(galleryId: galleryId) }
    }

    // MARK: Prefetch

    private func updatePrefetch() {
        guard !pages.isEmpty else { return }
        let visible: Range<Int>
        let neighbours: [Int]
        if showsFullscreen {
            visible = fullscreenPage..<(fullscreenPage + 1)
            neighbours = [fullscreenPage - 1, fullscreenPage + 1, fullscreenPage + 2]
        } else {
            let first = spreadIndex * 2
            visible = first..<(first + 2)
            neighbours = [first - 2, first - 1, first + 2, first + 3]
        }

        let neighbourURLs = neighbours.filter(pages.indices.contains).compactMap { pages[$0].imageURL }
        let visibleURLs = visible.filter(pages.indices.contains).compactMap { pages[$0].imageURL }
        // A page that just became visible keeps its running download; the cache serves the page view.
        let keep = Set(neighbourURLs + visibleURLs)
        for (url, loader) in prefetchers where !keep.contains(url) {
            loader.updateURL(nil)
            prefetchers[url] = nil
        }
        for url in neighbourURLs where prefetchers[url] == nil {
            prefetchers[url] = ImageLoader(url: url)
        }
    }

    private func cancelPrefetch() {
        prefetchers.values.forEach { $0.updateURL(nil) }
        prefetchers = [:]
    }
}

// MARK: - Spread

private struct MagazineSpreadView: View {
    /// One or two pages; the last spread of an odd gallery holds a single page.
    let pages: [StashImage]
    let firstPageIndex: Int
    let onSelectPage: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: 2))
                : AnyLayout(VStackLayout(spacing: 2))
            layout {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, image in
                    MagazinePageImage(image: image)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: alignment(offset: offset, isLandscape: isLandscape)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectPage(firstPageIndex + offset) }
                }
            }
        }
    }

    /// Two pages meet in the middle, like the fold of a magazine.
    private func alignment(offset: Int, isLandscape: Bool) -> Alignment {
        guard pages.count == 2 else { return .center }
        if isLandscape { return offset == 0 ? .trailing : .leading }
        return offset == 0 ? .bottom : .top
    }
}

private struct MagazinePageImage: View {
    let image: StashImage

    var body: some View {
        CustomAsyncImage(url: image.imageURL) { loader in
            if let loaded = loader.image {
                loaded
                    .resizable()
                    .scaledToFit()
            } else if loader.isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Fullscreen

private struct MagazineFullscreenView: View {
    let pages: [StashImage]
    @Binding var page: Int
    let onClose: () -> Void

    @State private var isZoomed = false
    @State private var showsChrome = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            MagazinePager(count: pages.count, index: $page, isPagingEnabled: !isZoomed) { index in
                ZoomableScrollView(isZoomed: $isZoomed, onTap: { _ in
                    withAnimation(.easeOut(duration: 0.15)) { showsChrome.toggle() }
                }) {
                    MagazinePageImage(image: pages[index])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea()
            .onChange(of: page) { _, _ in isZoomed = false }

            if showsChrome {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(page + 1) / \(pages.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
        }
        #if os(macOS)
        .overlay {
            if showsChrome {
                MagazineStepButtons(
                    canGoBack: page > 0,
                    canGoForward: page < pages.count - 1,
                    step: { delta in
                        withAnimation(.easeInOut(duration: 0.25)) { page += delta }
                    }
                )
            }
        }
        #endif
    }
}

// MARK: - Pager

#if os(macOS)
/// macOS has no page curl: a paging scroll view, swiped with the trackpad.
private struct MagazinePager<Page: View>: View {
    let count: Int
    @Binding var index: Int
    var isPagingEnabled = true
    @ViewBuilder let page: (Int) -> Page

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { pageIndex in
                    page(pageIndex)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(pageIndex)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.never)
        .scrollDisabled(!isPagingEnabled)
        .scrollPosition(id: Binding(
            get: { Optional(index) },
            set: { if let newValue = $0 { index = newValue } }
        ))
    }
}

/// A mouse cannot swipe, so the pager gets explicit previous / next buttons.
private struct MagazineStepButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let step: (Int) -> Void

    var body: some View {
        HStack {
            button(systemImage: "chevron.left", isVisible: canGoBack) { step(-1) }
            Spacer()
            button(systemImage: "chevron.right", isVisible: canGoForward) { step(1) }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func button(systemImage: String, isVisible: Bool, action: @escaping () -> Void) -> some View {
        if isVisible {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
#else
/// One side of a sheet. Sheets are double-sided so the flap of a turning page already shows the
/// next page, as in a real book: the front of sheet `n` shows page `n`, its back page `n + 1`.
/// `side` counts both: even = front, odd = back.
private final class MagazineSheetSide<Page: View>: UIHostingController<Page?> {
    let side: Int

    /// The page shown on the front of the sheet this side belongs to.
    var pageIndex: Int { side / 2 }

    init(side: Int, rootView: Page?) {
        self.side = side
        super.init(rootView: rootView)
        // The pager is laid out by SwiftUI; a page must not inset itself a second time.
        safeAreaRegions = []
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Page curl via `UIPageViewController`; SwiftUI has no equivalent.
private struct MagazinePager<Page: View>: UIViewControllerRepresentable {
    let count: Int
    @Binding var index: Int
    var isPagingEnabled = true
    @ViewBuilder let page: (Int) -> Page

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
        )
        controller.view.backgroundColor = .black
        controller.isDoubleSided = true
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.setViewControllers(context.coordinator.sheet(for: index), direction: .forward, animated: false)
        // The curl's own edge taps would swallow the tap that opens a page.
        controller.gestureRecognizers
            .filter { $0 is UITapGestureRecognizer }
            .forEach { $0.isEnabled = false }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        for recognizer in controller.gestureRecognizers where !(recognizer is UITapGestureRecognizer) {
            recognizer.isEnabled = isPagingEnabled
        }

        let sides = controller.viewControllers?.compactMap { $0 as? MagazineSheetSide<Page> } ?? []
        guard let current = sides.first else { return }
        if current.pageIndex == index {
            sides.forEach { $0.rootView = coordinator.content(forSide: $0.side) }
        } else if !coordinator.isTurningPage {
            controller.setViewControllers(
                coordinator.sheet(for: index),
                direction: index > current.pageIndex ? .forward : .reverse,
                animated: false
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MagazinePager
        /// A finger-driven curl is running; a programmatic jump during it would throw.
        var isTurningPage = false

        init(parent: MagazinePager) {
            self.parent = parent
        }

        /// The back of the last sheet has no next page and stays empty.
        func content(forSide side: Int) -> Page? {
            let shownPage = side / 2 + side % 2
            return shownPage < parent.count ? parent.page(shownPage) : nil
        }

        /// With the spine at the edge UIKit takes only the front; it asks for the back when a turn starts.
        func sheet(for index: Int) -> [UIViewController] {
            [host(forSide: index * 2)]
        }

        private func host(forSide side: Int) -> MagazineSheetSide<Page> {
            MagazineSheetSide(side: side, rootView: content(forSide: side))
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? MagazineSheetSide<Page>, current.side > 0 else { return nil }
            return host(forSide: current.side - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let current = viewController as? MagazineSheetSide<Page>, current.side < parent.count * 2 - 1 else { return nil }
            return host(forSide: current.side + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTurningPage = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTurningPage = false
            if let current = pageViewController.viewControllers?.first as? MagazineSheetSide<Page>, parent.index != current.pageIndex {
                parent.index = current.pageIndex
            }
        }

        /// One double-sided sheet with the spine on the left in every orientation; the spread
        /// lays out its own two pages.
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            .min
        }
    }
}
#endif
