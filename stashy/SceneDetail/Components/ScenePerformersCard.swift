
#if !os(tvOS)
import SwiftUI

/// "Performers & Studio" — one horizontal row that always starts with the studio,
/// followed by the performers (and the director, if any). Shared by the scene detail
/// page and the opened gallery; the save closures redirect edits away from the
/// scene mutation (e.g. to `galleryUpdate`).
struct ScenePerformersStudioCard: View {
    let sceneId: String
    let sceneDate: String?
    let performers: [ScenePerformer]
    let studio: SceneStudio?
    var director: String?
    var onPerformersUpdated: (([ScenePerformer]) -> Void)?
    var onStudioUpdated: ((SceneStudio?) -> Void)?
    /// Writes the chosen performer IDs somewhere other than the scene (e.g. a gallery).
    /// `nil` keeps the scene mutation.
    var savePerformerIds: (([String], @escaping (Bool) -> Void) -> Void)? = nil
    /// Writes the chosen studio somewhere other than the scene. `nil` keeps the scene mutation.
    var saveStudioId: ((String?, @escaping (Bool) -> Void) -> Void)? = nil
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var activeEditor: Editor?

    private enum Editor: String, Identifiable {
        case studio, performers
        var id: String { rawValue }
    }

    /// Diameter of every tile in the row (studio logo, performer portrait, director).
    fileprivate static let tileSize: CGFloat = 80

    /// The card has something to show, or edit mode wants it visible for assigning.
    static func isVisible(performers: [ScenePerformer], studio: SceneStudio?, director: String? = nil, editing: Bool) -> Bool {
        editing || studio != nil || !performers.isEmpty || director != nil
    }

    private var isEmpty: Bool {
        studio == nil && performers.isEmpty && director == nil
    }

    private func age(for performer: ScenePerformer) -> Int? {
        guard let birthdate = performer.birthdate, !birthdate.isEmpty,
              let releaseDate = sceneDate, !releaseDate.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let dob = fmt.date(from: birthdate),
              let release = fmt.date(from: String(releaseDate.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: release).year
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Performers & Studio")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if appearanceManager.isEditModeEnabled {
                    Menu {
                        Button {
                            activeEditor = .studio
                        } label: {
                            Label("Edit Studio", systemImage: "building.2")
                        }
                        Button {
                            activeEditor = .performers
                        } label: {
                            Label("Edit Performers", systemImage: "person.2")
                        }
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if isEmpty {
                Text("No performers or studio assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        if let studio {
                            NavigationLink(destination: StudioDetailView(studio: studio.toStudio())) {
                                tile(name: studio.name) {
                                    StudioLogoTile(studio: studio)
                                        .frame(width: Self.tileSize, height: Self.tileSize)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(performers.sorted { $0.name < $1.name }) { scenePerformer in
                            NavigationLink(destination: PerformerDetailView(performer: scenePerformer.toPerformer())) {
                                tile(name: scenePerformer.name, badge: age(for: scenePerformer)) {
                                    performerPortrait(scenePerformer)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(SceneDirectors.names(director), id: \.self) { director in
                            NavigationLink(destination: DirectorDetailView(director: director)) {
                                tile(name: director) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.secondaryAppBackground)
                                        Image(systemName: "megaphone.fill")
                                            .font(.system(size: 30, weight: .medium))
                                            .foregroundColor(Color.pillAccent)
                                    }
                                    .frame(width: Self.tileSize, height: Self.tileSize)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(item: $activeEditor) { editor in
            switch editor {
            case .performers:
                AddPerformerToSceneSheet(
                    sceneId: sceneId,
                    currentPerformers: performers,
                    viewModel: viewModel,
                    savePerformerIds: savePerformerIds
                ) { updated in
                    onPerformersUpdated?(updated)
                }
            case .studio:
                AddStudioToSceneSheet(
                    sceneId: sceneId,
                    currentStudio: studio,
                    viewModel: viewModel,
                    saveStudioId: saveStudioId
                ) { updated in
                    onStudioUpdated?(updated)
                }
            }
        }
    }

    @ViewBuilder
    private func performerPortrait(_ scenePerformer: ScenePerformer) -> some View {
        PerformerCirclePortrait(url: scenePerformer.thumbnailURL, size: Self.tileSize)
    }

    private func tile<Content: View>(name: String, badge: Int? = nil, @ViewBuilder content: () -> Content) -> some View {
        CircleNameTile(name: name, badge: badge.map { "\($0)" }, content: content)
    }
}

/// Shared shape language for every "Performers & Studio" item: tinted ring around a circle,
/// optional badge top-right, name pill overlapping the bottom edge. Also used by
/// Performer detail › "Appears with".
struct CircleNameTile<Content: View>: View {
    let name: String
    var badge: String? = nil
    let content: Content
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    init(name: String, badge: String? = nil, @ViewBuilder content: () -> Content) {
        self.name = name
        self.badge = badge
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .padding(4)
                .background(appearanceManager.tintColor)
                .clipShape(Circle())
                .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(appearanceManager.tintColor)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.secondaryAppBackground, lineWidth: 1.5))
                    }
                }

            Text(name)
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    ZStack {
                        Color.secondaryAppBackground
                        appearanceManager.tintColor.opacity(0.1)
                    }
                )
                .foregroundColor(Color.pillAccent)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(appearanceManager.tintColor.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 8)
        }
        .padding(.bottom, 8)
    }
}

/// Round, top-anchored performer portrait used inside `CircleNameTile`.
struct PerformerCirclePortrait: View {
    let url: URL?
    var size: CGFloat = 80
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        if let url {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size, alignment: .top)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                        .frame(width: size, height: size)
                        .skeleton()
                }
            }
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundColor(appearanceManager.tintColor.opacity(0.4))
        }
    }
}

/// Studio logo inside a performer-sized circle on a neutral background. The logo
/// comes from `StudioLogoStore` at the same raster size as `StudioImageView`, so
/// both share one cache entry; studios without their own image show a glyph.
private struct StudioLogoTile: View {
    let studio: SceneStudio
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var logo: UIImage?
    @State private var failed = false

    private static let rasterHeight: CGFloat = 220
    private static let rasterMaxWidth: CGFloat = 660

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.studioHeaderGray(for: appearance.currentTheme))
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    // Inset so wide logos stay inside the circle.
                    .padding(13)
            } else if failed {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .clipShape(Circle())
        .task(id: "\(studio.id)|\(studio.updatedAt ?? "")") {
            // Stash's generic placeholder (`…&default=true`) — show our own glyph instead.
            if studio.imagePath?.contains("default=true") == true {
                logo = nil
                failed = true
                return
            }
            let image = await StudioLogoStore.shared.image(
                studioId: studio.id, updatedAt: studio.updatedAt,
                height: Self.rasterHeight, maxWidth: Self.rasterMaxWidth
            )
            logo = image
            failed = image == nil
        }
    }
}

struct AddPerformerToSceneSheet: View {
    let sceneId: String
    let currentPerformers: [ScenePerformer]
    @ObservedObject var viewModel: StashDBViewModel
    var savePerformerIds: (([String], @escaping (Bool) -> Void) -> Void)? = nil
    var onComplete: ([ScenePerformer]) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var performers: [Performer] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var isCreating = false

    var pinned: [Performer] {
        // Chosen entries always lead the list, whatever the search says.
        performers.filter { selectedIds.contains($0.id) }
    }

    var filtered: [Performer] {
        // The search narrows only the unchosen rest, so a chosen entry never vanishes.
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return performers.filter {
            !selectedIds.contains($0.id) && (term.isEmpty || $0.name.localizedCaseInsensitiveContains(term))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Performers")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(pinned + Array(filtered.prefix(30))) { performer in
                            HStack {
                                Text(performer.name)
                                Spacer()
                                Text("\(performer.sceneCount) scenes").font(.caption).foregroundColor(.secondary)
                                if selectedIds.contains(performer.id) {
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(performer.id) {
                                    selectedIds.remove(performer.id)
                                } else {
                                    selectedIds.insert(performer.id)
                                }
                            }
                        }
                        if filtered.count > 30 {
                            Text("Type more to refine...").font(.caption).foregroundColor(.secondary)
                        }
                        if !searchText.isEmpty && filtered.isEmpty
                            && !pinned.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) }) {
                            Button {
                                createAndSelect()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create \"\(searchText)\"")
                                }
                                .foregroundColor(appearanceManager.tintColor)
                            }
                            .disabled(isCreating)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Edit Performers", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(currentPerformers.map { $0.id })
                isLoading = true
                viewModel.fetchAllPerformers { fetched in
                    DispatchQueue.main.async {
                        self.performers = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func createAndSelect() {
        isCreating = true
        viewModel.createPerformer(name: searchText) { created in
            DispatchQueue.main.async {
                isCreating = false
                if let p = created {
                    performers.append(p)
                    selectedIds.insert(p.id)
                    searchText = ""
                } else {
                    ToastManager.shared.show("Failed to create performer", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let ids = Array(selectedIds)
        let persist = savePerformerIds ?? { ids, done in
            viewModel.updateScenePerformers(sceneId: sceneId, performerIds: ids, completion: done)
        }
        persist(ids) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    let updated = performers.filter { selectedIds.contains($0.id) }.map {
                        ScenePerformer(id: $0.id, name: $0.name, birthdate: $0.birthdate, sceneCount: $0.sceneCount, galleryCount: $0.galleryCount, oCounter: nil, updatedAt: $0.updatedAt)
                    }
                    onComplete(updated)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update performers", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}

/// Add-only performer picker (Feeds "+" next to the performer names). Unlike
/// `AddPerformerToSceneSheet` it never removes anyone and searches on the server
/// (`findPerformers` with `q`), so it scales to large libraries. Performers already
/// on the item are shown as added and can't be toggled. The caller writes the result.
struct AddPerformersPickerSheet: View {
    let existingPerformerIds: Set<String>
    @ObservedObject var viewModel: StashDBViewModel
    var onDone: ([Performer]) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @State private var searchText = ""
    @State private var results: [Performer] = []
    @State private var picked: [Performer] = []
    @State private var isLoading = false

    private static let pageSize = 40

    private var pickedIds: Set<String> { Set(picked.map(\.id)) }

    /// Picks lead the list whatever the search says; the rest follows in server order.
    private var rows: [Performer] {
        picked + results.filter { !pickedIds.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("Search performers…", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                }
                .listRowBackground(Color.secondaryAppBackground)

                Section {
                    if isLoading && results.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if rows.isEmpty {
                        Text(searchText.isEmpty ? "No performers" : "No matches")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(rows) { performer in
                            row(performer)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .applyAppBackground()
            .scrollContentBackground(.hidden)
            .stashyModalSheetChrome("Add Performers", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Done", enabled: !picked.isEmpty) {
                    let chosen = picked
                    dismiss()
                    onDone(chosen)
                }
            }
            // Debounced server search; `task(id:)` cancels the previous run per keystroke.
            .task(id: searchText) {
                let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !term.isEmpty {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if Task.isCancelled { return }
                }
                isLoading = true
                let found = await viewModel.searchPerformersAsync(
                    query: term,
                    limit: Self.pageSize,
                    sort: term.isEmpty ? "scenes_count" : "name",
                    direction: term.isEmpty ? "DESC" : "ASC"
                )
                if Task.isCancelled { return }
                results = found
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private func row(_ performer: Performer) -> some View {
        let alreadyAdded = existingPerformerIds.contains(performer.id)
        let isPicked = pickedIds.contains(performer.id)
        Button {
            guard !alreadyAdded else { return }
            if isPicked {
                picked.removeAll { $0.id == performer.id }
            } else {
                picked.append(performer)
            }
        } label: {
            HStack(spacing: 12) {
                PerformerCirclePortrait(url: performer.thumbnailURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(performer.name)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let d = performer.disambiguation, !d.isEmpty {
                        Text(d).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if alreadyAdded {
                    Text("Added").font(.caption).foregroundColor(.secondary)
                } else {
                    Text("\(performer.sceneCount) scenes").font(.caption).foregroundColor(.secondary)
                }
                Image(systemName: (alreadyAdded || isPicked) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isPicked ? appearanceManager.tintColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .opacity(alreadyAdded ? 0.6 : 1)
    }
}
#endif
