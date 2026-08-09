
#if !os(tvOS)
import SwiftUI

struct SceneTagsCard: View {
    let sceneId: String
    let tags: [Tag]?
    var onTagsUpdated: (([Tag]) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @Binding var isTagsExpanded: Bool
    @Binding var tagsTotalHeight: CGFloat
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

    private let collapsedHeight: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags")
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

            if let tags = tags, !tags.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        WrappedHStack(items: tags) { tag in
                            NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                                HStack(spacing: 4) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(tag.name)
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.pillAccent.opacity(0.1))
                                .foregroundColor(Color.pillAccent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    tagsTotalHeight = geo.size.height
                                }
                                .onChange(of: geo.size.height) { _, newValue in
                                    tagsTotalHeight = newValue
                                }
                            }
                        )
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
            } else {
                Text("No tags assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(isPresented: $showingAddSheet) {
            AddTagToSceneSheet(
                sceneId: sceneId,
                currentTags: tags ?? [],
                viewModel: viewModel
            ) { updated in
                onTagsUpdated?(updated)
            }
        }
    }
}

struct AddTagToSceneSheet: View {
    let sceneId: String
    let currentTags: [Tag]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([Tag]) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var allTags: [Tag] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var isCreating = false

    var filtered: [Tag] {
        if searchText.isEmpty { return allTags }
        return allTags.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Tags")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { tag in
                            HStack {
                                Text(tag.name)
                                if let count = tag.sceneCount {
                                    Spacer()
                                    Text("\(count) scenes").font(.caption).foregroundColor(.secondary)
                                }
                                if selectedIds.contains(tag.id) {
                                    Spacer()
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(tag.id) {
                                    selectedIds.remove(tag.id)
                                } else {
                                    selectedIds.insert(tag.id)
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
            .stashyModalSheetChrome("Edit Tags", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(currentTags.map { $0.id })
                isLoading = true
                viewModel.fetchAllTags { fetched in
                    DispatchQueue.main.async {
                        self.allTags = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func createAndSelect() {
        isCreating = true
        viewModel.createTag(name: searchText) { created in
            DispatchQueue.main.async {
                isCreating = false
                if let t = created {
                    allTags.append(t)
                    selectedIds.insert(t.id)
                    searchText = ""
                } else {
                    ToastManager.shared.show("Failed to create tag", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let ids = Array(selectedIds)
        viewModel.updateSceneTags(sceneId: sceneId, tagIds: ids) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    let updated = allTags.filter { selectedIds.contains($0.id) }
                    onComplete(updated)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update tags", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
