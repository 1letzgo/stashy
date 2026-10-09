
#if !os(tvOS)
import SwiftUI

struct AddStudioToSceneSheet: View {
    let sceneId: String
    let currentStudio: SceneStudio?
    @ObservedObject var viewModel: StashDBViewModel
    var saveStudioId: ((String?, @escaping (Bool) -> Void) -> Void)? = nil
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
        let persist = saveStudioId ?? { id, done in
            viewModel.updateSceneStudio(sceneId: sceneId, studioId: id, completion: done)
        }
        persist(studioId) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    if let sid = studioId, let matched = studios.first(where: { $0.id == sid }) {
                        let updated = SceneStudio(id: matched.id, name: matched.name, updatedAt: matched.updatedAt, imagePath: matched.imagePath)
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
