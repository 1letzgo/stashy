
#if !os(tvOS)
import SwiftUI

struct SceneGroupsCard: View {
    let sceneId: String
    let groups: [SceneGroupEntry]
    var onGroupsUpdated: (([SceneGroupEntry]) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Groups")
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

            if groups.isEmpty {
                Text("No groups assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(groups.sorted { $0.group.name < $1.group.name }) { entry in
                        NavigationLink(destination: GroupDetailView(selectedGroup: entry.group.toStashGroup())) {
                            groupCardContent(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(isPresented: $showingAddSheet) {
            AddGroupToSceneSheet(
                sceneId: sceneId,
                currentGroups: groups,
                viewModel: viewModel
            ) { updated in
                onGroupsUpdated?(updated)
            }
        }
    }

    private func groupCardContent(entry: SceneGroupEntry) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if let url = entry.group.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 105)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .frame(width: 70, height: 105)
                                .skeleton()
                        }
                    }
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .frame(width: 70, height: 105)
                        .foregroundColor(appearanceManager.tintColor.opacity(0.4))
                }
            }
            .frame(width: 70, height: 105)
            .background(appearanceManager.tintColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))

            Text(entry.group.name)
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
        .frame(maxWidth: .infinity)
    }
}

struct AddGroupToSceneSheet: View {
    let sceneId: String
    let currentGroups: [SceneGroupEntry]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([SceneGroupEntry]) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var allGroups: [StashGroup] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false
    @State private var isCreating = false

    var filtered: [StashGroup] {
        if searchText.isEmpty { return allGroups }
        return allGroups.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Groups")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { group in
                            HStack {
                                Text(group.name)
                                Spacer()
                                if let count = group.scene_count {
                                    Text("\(count) scenes").font(.caption).foregroundColor(.secondary)
                                }
                                if selectedIds.contains(group.id) {
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(group.id) {
                                    selectedIds.remove(group.id)
                                } else {
                                    selectedIds.insert(group.id)
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
            .stashyModalSheetChrome("Edit Groups", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedIds = Set(currentGroups.map { $0.group.id })
                isLoading = true
                viewModel.fetchAllGroupsForScene { fetched in
                    DispatchQueue.main.async {
                        self.allGroups = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func createAndSelect() {
        isCreating = true
        viewModel.createGroup(name: searchText) { created in
            DispatchQueue.main.async {
                isCreating = false
                if let g = created {
                    allGroups.append(g)
                    selectedIds.insert(g.id)
                    searchText = ""
                } else {
                    ToastManager.shared.show("Failed to create group", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let ids = Array(selectedIds)
        viewModel.updateSceneGroups(sceneId: sceneId, groupIds: ids) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    let updated: [SceneGroupEntry] = allGroups.filter { selectedIds.contains($0.id) }.map { g in
                        SceneGroupEntry(group: SceneGroupInfo(id: g.id, name: g.name, updatedAt: g.updatedAt, frontImagePath: g.front_image_path), sceneIndex: nil)
                    }
                    onComplete(updated)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update groups", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
