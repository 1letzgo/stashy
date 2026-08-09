
#if !os(tvOS)
import SwiftUI

struct ScenePerformersCard: View {
    let sceneId: String
    let sceneDate: String?
    let performers: [ScenePerformer]
    var onPerformersUpdated: (([ScenePerformer]) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

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
                Text("Performers")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if appearanceManager.isEditModeEnabled {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if performers.isEmpty {
                Text("No performers assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(performers.sorted { $0.name < $1.name }) { scenePerformer in
                            NavigationLink(destination: PerformerDetailView(performer: scenePerformer.toPerformer())) {
                                ZStack(alignment: .bottom) {
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
                                                        .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
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
                                    .background(appearanceManager.tintColor)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))
                                    .overlay(alignment: .topTrailing) {
                                        if let a = age(for: scenePerformer) {
                                            Text("\(a)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(appearanceManager.tintColor)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.secondaryAppBackground, lineWidth: 1.5))
                                        }
                                    }

                                    Text(scenePerformer.name)
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
        .sheet(isPresented: $showingAddSheet) {
            AddPerformerToSceneSheet(
                sceneId: sceneId,
                currentPerformers: performers,
                viewModel: viewModel
            ) { updated in
                onPerformersUpdated?(updated)
            }
        }
    }
}

struct AddPerformerToSceneSheet: View {
    let sceneId: String
    let currentPerformers: [ScenePerformer]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([ScenePerformer]) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var performers: [Performer] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var isCreating = false

    var filtered: [Performer] {
        if searchText.isEmpty { return performers }
        return performers.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Performers")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { performer in
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
                        if !searchText.isEmpty && filtered.isEmpty {
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
        viewModel.updateScenePerformers(sceneId: sceneId, performerIds: ids) { success in
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
#endif
