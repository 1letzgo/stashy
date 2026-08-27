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
    /// Name-search hits merged on top of the cached "most used" list, so a picked long-tail
    /// entry still resolves to a name after the search text is cleared.
    @Published private(set) var searchResults: [String: [FilterEntityOption]] = [:]
    @Published private(set) var searching: Set<String> = []
    private var searchTokens: [String: UUID] = [:]

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
        searchResults = [:]
        searching = []
        searchTokens = [:]
    }

    func cached(_ kind: Kind) -> [FilterEntityOption] { options[kind.rawValue] ?? [] }
    func isLoading(_ kind: Kind) -> Bool { loading.contains(kind.rawValue) }
    func isSearching(_ kind: Kind) -> Bool { searching.contains(kind.rawValue) }
    /// Name-search hits collected this session for `kind`.
    func searchHits(_ kind: Kind) -> [FilterEntityOption] { searchResults[kind.rawValue] ?? [] }

    /// entity id → display name across every cached kind, for writing the web UI's `{id,label}`
    /// pairs into a saved filter. Ids are unique per entity type; a collision across types would
    /// only mislabel, never mis-filter.
    func knownLabels() -> [String: String] {
        var out: [String: String] = [:]
        for list in options.values {
            for option in list { out[option.id] = option.name }
        }
        for list in searchResults.values {
            for option in list { out[option.id] = option.name }
        }
        return out
    }

    /// Cached most-used list plus every search hit seen this session, de-duplicated by id.
    func availableOptions(_ kind: Kind) -> [FilterEntityOption] {
        let base = cached(kind)
        let extra = searchResults[kind.rawValue] ?? []
        guard !extra.isEmpty else { return base }
        var seen = Set(base.map(\.id))
        var merged = base
        for option in extra where !seen.contains(option.id) {
            seen.insert(option.id)
            merged.append(option)
        }
        return merged
    }

    /// Queries the server by name. Results are merged into ``availableOptions`` rather than
    /// replacing the cached list, so previously picked entries never lose their label.
    /// Only the newest call per kind is applied — earlier keystrokes are discarded.
    func search(_ kind: Kind, query: String) {
        let key = kind.rawValue
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            searchTokens[key] = UUID()
            searching.remove(key)
            return
        }
        let token = UUID()
        searchTokens[key] = token
        searching.insert(key)
        viewModel.searchFilterPickerOptions(kind: kind, query: term) { [weak self] results in
            Task { @MainActor in
                guard let self, self.searchTokens[key] == token else { return }
                self.searching.remove(key)
                var merged = self.searchResults[key] ?? []
                var seen = Set(merged.map(\.id))
                for option in results where !seen.contains(option.id) {
                    seen.insert(option.id)
                    merged.append(option)
                }
                self.searchResults[key] = merged
            }
        }
    }

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
