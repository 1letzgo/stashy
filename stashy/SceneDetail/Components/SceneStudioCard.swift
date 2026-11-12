
#if !os(tvOS)
import SwiftUI

struct AddStudioToSceneSheet: View {
    let sceneId: String
    let currentStudio: SceneStudio?
    @ObservedObject var viewModel: StashDBViewModel
    var saveStudioId: ((String?, @escaping (Bool) -> Void) -> Void)? = nil
    var onComplete: (SceneStudio?) -> Void

    @Environment(\.stashyDismiss) var dismiss
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
                Section(header: Text(tr("search_studio"))) {
                    TextField(tr("placeholder_search_2"), text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView(tr("loading")); Spacer() }.padding()
                    } else {
                        ForEach(filtered.prefix(30)) { studio in
                            HStack {
                                Text(studio.name)
                                Spacer()
                                Text(tr("arg_count_scenes", studio.sceneCount)).font(.caption).foregroundColor(.secondary)
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
                            Text(tr("type_more_to_refine_menu")).font(.caption).foregroundColor(.secondary)
                        }
                        if !searchText.isEmpty && filtered.isEmpty {
                            Button {
                                createAndSelect()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text(tr("action_create_arg", searchText))
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
            .stashyModalSheetChrome(tr("action_set_studio"), onBack: { dismiss() }) {
                StashyChromeTrailingTextButton(title: tr("action_save"), enabled: !isSaving, isBusy: isSaving) { save() }
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
                    ToastManager.shared.show(tr("error_create_studio"), icon: "exclamationmark.triangle", style: .error)
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
                    ToastManager.shared.show(tr("error_update_studio"), icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
