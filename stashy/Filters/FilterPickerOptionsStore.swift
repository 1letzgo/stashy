import Foundation
import Combine
import SwiftUI

/// Shared, cached entity options (studios / tags / groups / performers) for the criteria editor pickers.
///
/// Every criterion row used to own a `StashDBViewModel`, so a sheet with five multi-ID criteria
/// opened five server connections and refetched the same lists. One store, one view model, one fetch
/// per entity kind and server session.
@MainActor
final class FilterPickerOptionsStore: ObservableObject {
    static let shared = FilterPickerOptionsStore()

    enum Kind: String {
        case studios, tags, groups, performers
        case imageTags, imageStudios, galleryStudios
    }

    @Published private(set) var options: [String: [FilterEntityOption]] = [:]
    @Published private(set) var loading: Set<String> = []

    private lazy var viewModel = StashDBViewModel()
    private var pending: [String: [([FilterEntityOption]) -> Void]] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.invalidate() }
        }
    }

    func invalidate() {
        options = [:]
        loading = []
        pending = [:]
    }

    func cached(_ kind: Kind) -> [FilterEntityOption] { options[kind.rawValue] ?? [] }
    func isLoading(_ kind: Kind) -> Bool { loading.contains(kind.rawValue) }

    /// Resolves the entity kind a criterion key refers to, e.g. `performer_tags` → tags.
    static func kind(forCriterionKey key: String, mode: StashDBViewModel.FilterMode) -> Kind? {
        let k = key.lowercased()
        // Tag checks come first: `performer_tags` / `scene_tags` are tag pickers, not performer pickers.
        if k.contains("tag") {
            return mode == .images ? .imageTags : .tags
        }
        if k.contains("studio") {
            switch mode {
            case .images: return .imageStudios
            case .galleries: return .galleryStudios
            default: return .studios
            }
        }
        if k.contains("group") || k.contains("movie") { return .groups }
        if k.contains("performer") { return .performers }
        return nil
    }

    func load(_ kind: Kind, completion: (([FilterEntityOption]) -> Void)? = nil) {
        let key = kind.rawValue
        if let cachedList = options[key], !cachedList.isEmpty {
            completion?(cachedList)
            return
        }
        if let completion { pending[key, default: []].append(completion) }
        guard !loading.contains(key) else { return }
        loading.insert(key)

        let finish: ([FilterEntityOption]) -> Void = { [weak self] list in
            guard let self else { return }
            self.options[key] = list
            self.loading.remove(key)
            let waiters = self.pending.removeValue(forKey: key) ?? []
            waiters.forEach { $0(list) }
        }

        switch kind {
        case .studios, .imageStudios, .galleryStudios:
            let pickerMode: StashDBViewModel.LiveFilterStudioPickerMode = {
                switch kind {
                case .imageStudios: return .imagesHasImages
                case .galleryStudios: return .galleriesHasGalleries
                default: return .scenesHasScenes
                }
            }()
            viewModel.fetchStudiosForLiveFilterPicker(mode: pickerMode) { list in
                Task { @MainActor in finish(list.map { FilterEntityOption(id: $0.id, name: $0.name) }) }
            }
        case .tags:
            viewModel.fetchTagsForSceneLiveFilterPicker { list in
                Task { @MainActor in finish(list.map { FilterEntityOption(id: $0.id, name: $0.name) }) }
            }
        case .imageTags:
            viewModel.fetchTagsForImageLiveFilterPicker { list in
                Task { @MainActor in finish(list.map { FilterEntityOption(id: $0.id, name: $0.name) }) }
            }
        case .groups:
            viewModel.fetchGroupsForSceneLiveFilterPicker { list in
                Task { @MainActor in finish(list.map { FilterEntityOption(id: $0.id, name: $0.name) }) }
            }
        case .performers:
            viewModel.fetchPerformersForFilterPicker { list in
                Task { @MainActor in finish(list) }
            }
        }
    }
}
