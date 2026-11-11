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
    /// Chapters and tags; a failure just leaves the reader without them.
    @State private var info = GalleryReaderInfo(chapters: [], tags: [])
    @State private var activeSheet: MagazineReaderSheet?
    #if os(macOS)
    @FocusState private var hasKeyboardFocus: Bool
    #endif

    private var spreadCount: Int { (pages.count + 1) / 2 }

    /// 0-based; on a spread its first page.
    private var currentPage: Int { showsFullscreen ? fullscreenPage : spreadIndex * 2 }

    private var chapters: [GalleryReaderInfo.Chapter] {
        info.chapters.sorted { $0.image_index < $1.image_index }
    }

    /// The chapter of the last page on screen: a chapter can start on a spread's second page.
    private var currentChapter: GalleryReaderInfo.Chapter? {
        let lastVisiblePage = showsFullscreen ? fullscreenPage : currentPage + 1
        return chapters.last { $0.image_index - 1 <= lastVisiblePage }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                content
            }

            if showsFullscreen {
                MagazineFullscreenView(
                    pages: pages,
                    page: $fullscreenPage,
                    onClose: closeFullscreen,
                    onShowPagePicker: { activeSheet = .pagePicker }
                )
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $activeSheet, onDismiss: restoreKeyboardFocus) { sheet in
            switch sheet {
            case .pagePicker:
                MagazinePagePickerSheet(
                    pages: pages,
                    chapters: chapters,
                    currentPage: currentPage,
                    currentChapterId: currentChapter?.id,
                    onSelect: jump(toPage:)
                )
            case .details:
                MagazineDetailsSheet(gallery: gallery, tags: info.tags, pageCount: pages.count, chapterCount: chapters.count)
            }
        }
        .task { await loadPages() }
        .task { await loadInfo() }
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
                Label(tr("error_load_pages"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(tr("action_try_again")) { Task { await loadPages() } }
            }
        } else if pages.isEmpty {
            ContentUnavailableView(tr("empty_pages"), systemImage: "photo.on.rectangle")
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

            Button { activeSheet = .details } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(gallery.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let currentChapter {
                        Text(currentChapter.title)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("gallery_details"))

            Spacer(minLength: 0)

            if !pages.isEmpty {
                Button { activeSheet = .pagePicker } label: {
                    HStack(spacing: 3) {
                        Text(pageLabel)
                            .font(.caption.monospacedDigit())
                            .fixedSize()
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("action_go_to_page"))
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
                .accessibilityLabel(tr("action_reset_position"))
            }
        }
    }

    private var pageLabel: String {
        let first = spreadIndex * 2 + 1
        let last = min(first + 1, pages.count)
        return first == last ? tr("page_arg_arg", first, pages.count) : tr("page_arg_arg_arg", first, last, pages.count)
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

    private func jump(toPage page: Int) {
        HapticManager.light()
        if showsFullscreen {
            fullscreenPage = page
        } else {
            spreadIndex = page / 2
        }
    }

    private func restoreKeyboardFocus() {
        #if os(macOS)
        hasKeyboardFocus = true
        #endif
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

    private func loadInfo() async {
        do {
            info = try await GalleryRepository().fetchReaderInfo(galleryId: gallery.id)
        } catch {
            AppLog.debug("Magazin: chapters and tags not loaded: \(error.localizedDescription)")
        }
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
        MagazineReadingStore.shared.note(page: currentPage + 1, galleryId: gallery.id)
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

// MARK: - Sheets

private enum MagazineReaderSheet: String, Identifiable {
    case pagePicker, details
    var id: String { rawValue }
}

/// Go to a page by number, from the page list, or by chapter when the gallery has any.
private struct MagazinePagePickerSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case chapters = "Chapters"
        case pages = "Pages"
        var id: String { rawValue }
        var title: String { self == .chapters ? tr("chapters") : tr("pages") }
    }

    let pages: [StashImage]
    let chapters: [GalleryReaderInfo.Chapter]
    let currentPage: Int
    let currentChapterId: String?
    let onSelect: (Int) -> Void

    @Environment(\.stashyDismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var pageInput = ""
    @State private var mode: Mode

    init(
        pages: [StashImage],
        chapters: [GalleryReaderInfo.Chapter],
        currentPage: Int,
        currentChapterId: String?,
        onSelect: @escaping (Int) -> Void
    ) {
        self.pages = pages
        self.chapters = chapters
        self.currentPage = currentPage
        self.currentChapterId = currentChapterId
        self.onSelect = onSelect
        _mode = State(initialValue: chapters.isEmpty ? .pages : .chapters)
    }

    /// 0-based page the input stands for; nil while it is no page of this gallery.
    private var enteredPage: Int? {
        guard let number = Int(pageInput.trimmingCharacters(in: .whitespaces)), (1...pages.count).contains(number) else { return nil }
        return number - 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                pageField
                if !chapters.isEmpty { modeChips }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            switch mode {
                            case .chapters:
                                ForEach(chapters) { chapter in
                                    chapterRow(chapter).id(chapter.id)
                                }
                            case .pages:
                                ForEach(pages.indices, id: \.self) { index in
                                    pageRow(index).id(index)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .onAppear { scrollToCurrent(proxy) }
                    .onChange(of: mode) { _, _ in scrollToCurrent(proxy) }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .stashyModalSheetChrome(tr("action_go_to_page"), onBack: { dismiss() })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 480)
        #endif
    }

    private var pageField: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            TextField(tr("page_1_arg", pages.count), text: $pageInput)
                .font(.subheadline)
                .keyboardType(.numberPad)
                .onSubmit(goToEnteredPage)
            // The number pad has no return key.
            CatalogFilterChip(title: tr("action_go"), isActive: enteredPage != nil, action: goToEnteredPage)
                .disabled(enteredPage == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .padding(.horizontal, 16)
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { option in
                CatalogFilterChip(title: option.title, isActive: mode == option) { mode = option }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func chapterRow(_ chapter: GalleryReaderInfo.Chapter) -> some View {
        // A chapter can point past the pages the reader kept (it leaves out videos).
        let page = min(max(chapter.image_index - 1, 0), pages.count - 1)
        return row(isCurrent: chapter.id == currentChapterId, action: { select(page) }) {
            Text(chapter.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(tr("page_arg", page + 1))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func pageRow(_ index: Int) -> some View {
        row(isCurrent: index == currentPage, action: { select(index) }) {
            CustomAsyncImage(url: pages[index].thumbnailURL) { loader in
                if let loaded = loader.image {
                    loaded
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(tr("page_arg", index + 1))
                .font(.subheadline.weight(.medium).monospacedDigit())
            Spacer(minLength: 8)
        }
    }

    private func row<Content: View>(
        isCurrent: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                content()
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appearance.tintColor)
                    .opacity(isCurrent ? 1 : 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        }
        .buttonStyle(.plain)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        switch mode {
        case .chapters:
            if let currentChapterId { proxy.scrollTo(currentChapterId, anchor: .center) }
        case .pages:
            proxy.scrollTo(currentPage, anchor: .center)
        }
    }

    private func goToEnteredPage() {
        guard let enteredPage else { return }
        select(enteredPage)
    }

    private func select(_ page: Int) {
        onSelect(page)
        dismiss()
    }
}

/// What the open gallery is: the list's fields plus the tags, which the list does not keep.
private struct MagazineDetailsSheet: View {
    let gallery: Gallery
    let tags: [GalleryReaderInfo.Tag]
    let pageCount: Int
    let chapterCount: Int

    @Environment(\.stashyDismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    card {
                        Text(gallery.displayName)
                            .font(.headline)
                        fact("Pages", "\(pageCount)")
                        if chapterCount > 0 { fact("Chapters", "\(chapterCount)") }
                        if let studio = gallery.studio { fact(tr("studio"), studio.name) }
                        if let date = gallery.date, !date.isEmpty { fact(tr("date"), date) }
                        if let rating = gallery.rating100 {
                            fact(tr("rating"), String(format: "%g / 5", Double(rating) / 20))
                        }
                    }
                    if let performers = gallery.performers, !performers.isEmpty {
                        section(tr("performers")) {
                            card { Text(performers.map(\.name).joined(separator: ", ")).font(.subheadline) }
                        }
                    }
                    if !tags.isEmpty {
                        section(tr("tags")) {
                            card {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags) { tag in
                                        Text(tag.name)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.appBackground, in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    if let details = gallery.details, !details.isEmpty {
                        section(tr("details")) {
                            card { Text(details).font(.subheadline) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .stashyModalSheetChrome(tr("details"), onBack: { dismiss() })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
        }
        .font(.subheadline)
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
            // On an iPhone Duo the fold is the magazine's own fold: one page on each side of
            // it, nothing underneath. It also decides the direction when the display is taller
            // than wide (fold across) or the other way round.
            let fold = geometry.foldRegion
            let isLandscape = fold?.isVertical ?? (geometry.size.width > geometry.size.height)
            let spacing = fold.map { isLandscape ? $0.frame.width : $0.frame.height } ?? 2
            let layout = isLandscape
                ? AnyLayout(HStackLayout(spacing: spacing))
                : AnyLayout(VStackLayout(spacing: spacing))
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
                // The last page of an odd gallery stays on its side of the fold.
                if fold != nil, pages.count == 1 {
                    Color.clear
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
    let onShowPagePicker: () -> Void

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

                    Button(action: onShowPagePicker) {
                        HStack(spacing: 3) {
                            Text("\(page + 1) / \(pages.count)")
                                .font(.caption.monospacedDigit())
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("action_go_to_page"))
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
