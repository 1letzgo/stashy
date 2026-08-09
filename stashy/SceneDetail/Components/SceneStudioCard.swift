
#if !os(tvOS)
import SwiftUI

struct SceneStudioCard: View {
    let sceneId: String
    let studio: SceneStudio?
    var onStudioUpdated: ((SceneStudio?) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Studio")
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

            if let studio = studio {
                VStack {
                    NavigationLink(destination: StudioDetailView(studio: studio.toStudio())) {
                        studioCardContent(studio: studio)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            } else {
                Text("No studio assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(isPresented: $showingAddSheet) {
            AddStudioToSceneSheet(
                sceneId: sceneId,
                currentStudio: studio,
                viewModel: viewModel
            ) { updated in
                onStudioUpdated?(updated)
            }
        }
    }

    private func studioCardContent(studio: SceneStudio) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                StudioImageView(studio: studio.toStudio())
                    .padding(8)
            }
            .frame(width: 110, height: 105)
            .background(appearanceManager.tintColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card).stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))

            Text(studio.name)
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

struct AddStudioToSceneSheet: View {
    let sceneId: String
    let currentStudio: SceneStudio?
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: (SceneStudio?) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var studios: [Studio] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedId: String = ""
    @State private var isSaving = false
    @State private var isCreating = false

    var filtered: [Studio] {
        if searchText.isEmpty { return studios }
        return studios.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Studio")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { studio in
                            HStack {
                                Text(studio.name)
                                Spacer()
                                Text("\(studio.sceneCount) scenes").font(.caption).foregroundColor(.secondary)
                                if selectedId == studio.id {
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedId == studio.id {
                                    selectedId = ""
                                } else {
                                    selectedId = studio.id
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
            .stashyModalSheetChrome("Set Studio", onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: "Save", enabled: !isSaving, isBusy: isSaving) { save() }
            }
            .onAppear {
                selectedId = currentStudio?.id ?? ""
                isLoading = true
                viewModel.fetchAllStudios { fetched in
                    DispatchQueue.main.async {
                        self.studios = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func createAndSelect() {
        isCreating = true
        viewModel.createStudio(name: searchText) { created in
            DispatchQueue.main.async {
                isCreating = false
                if let s = created {
                    studios.append(s)
                    selectedId = s.id
                    searchText = ""
                } else {
                    ToastManager.shared.show("Failed to create studio", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let studioId: String? = (selectedId == "__none__") ? nil : (selectedId.isEmpty ? nil : selectedId)
        viewModel.updateSceneStudio(sceneId: sceneId, studioId: studioId) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    if let sid = studioId, let matched = studios.first(where: { $0.id == sid }) {
                        let updated = SceneStudio(id: matched.id, name: matched.name, updatedAt: matched.updatedAt)
                        onComplete(updated)
                    } else {
                        onComplete(nil)
                    }
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update studio", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
