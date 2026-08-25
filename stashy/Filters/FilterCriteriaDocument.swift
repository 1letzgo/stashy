import Foundation
import Combine

/// Editable `object_filter` document for one Stash `FilterMode`.
@MainActor
final class FilterCriteriaDocument: ObservableObject {
    private(set) var mode: StashDBViewModel.FilterMode
    @Published private(set) var objectFilter: [String: Any]

    init(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any] = [:]) {
        self.mode = mode
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
    }

    /// Reconfigure for nested editors (AND/OR/NOT / `*_filter`) without allocating a new object.
    func reconfigure(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any]) {
        self.mode = mode
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
        objectWillChange.send()
    }

    var isMarkerMode: Bool { mode == .sceneMarkers }

    var sanitizedObjectFilter: [String: Any] {
        Self.sanitize(objectFilter, mode: mode)
    }

    var criterionKeys: [String] {
        let keys = Array(objectFilter.keys)
        let priority = ["AND", "OR", "NOT"]
        return keys.sorted { a, b in
            let ia = priority.firstIndex(of: a) ?? Int.max
            let ib = priority.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            let la = FilterFieldCatalog.field(key: a, mode: mode)?.label ?? a
            let lb = FilterFieldCatalog.field(key: b, mode: mode)?.label ?? b
            return la.localizedCaseInsensitiveCompare(lb) == .orderedAscending
        }
    }

    var presentKeys: Set<String> { Set(objectFilter.keys) }

    func load(_ dict: [String: Any]?) {
        objectFilter = Self.sanitize(dict ?? [:], mode: mode)
    }

    func replaceObjectFilter(_ dict: [String: Any]) {
        objectFilter = Self.sanitize(dict, mode: mode)
    }

    func clear() {
        objectFilter = [:]
    }

    func value(forKey key: String) -> Any? {
        objectFilter[key]
    }

    func setCriterion(key: String, value: Any?) {
        var next = objectFilter
        if let value {
            next[key] = value
        } else {
            next.removeValue(forKey: key)
        }
        objectFilter = next
    }

    func removeCriterion(key: String) {
        var next = objectFilter
        next.removeValue(forKey: key)
        objectFilter = next
    }

    func addDefaultCriterion(for field: FilterFieldDescriptor) {
        guard objectFilter[field.key] == nil || field.kind == .booleanGroup else { return }
        let value = FilterCriterionKind.defaultValue(for: field.kind, nestedMode: field.nestedMode)
        setCriterion(key: field.key, value: value)
    }

    func dictValue(forKey key: String) -> [String: Any] {
        Self.stringKeyedDict(objectFilter[key]) ?? [:]
    }

    func setDictCriterion(key: String, dict: [String: Any]) {
        setCriterion(key: key, value: dict)
    }

    // MARK: - Sanitize

    static func sanitize(_ dict: [String: Any], mode: StashDBViewModel.FilterMode) -> [String: Any] {
        FilterMapper.sanitize(Self.deepStringKeyed(dict), isMarker: mode == .sceneMarkers)
    }

    nonisolated static func sanitizeNonisolated(_ dict: [String: Any], mode: StashDBViewModel.FilterMode) -> [String: Any] {
        FilterMapper.sanitize(deepStringKeyed(dict), isMarker: mode == .sceneMarkers)
    }

    nonisolated static func stringKeyedDict(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let d = value as? [String: Any] { return d }
        if let ns = value as? NSDictionary {
            var out: [String: Any] = [:]
            out.reserveCapacity(ns.count)
            for (k, v) in ns {
                guard let ks = k as? String else { continue }
                out[ks] = v
            }
            return out
        }
        return nil
    }

    nonisolated static func deepStringKeyed(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            out[k] = deepConvert(v)
        }
        return out
    }

    nonisolated private static func deepConvert(_ value: Any) -> Any {
        if let d = stringKeyedDict(value) {
            return deepStringKeyed(d)
        }
        if let arr = value as? [Any] {
            return arr.map { deepConvert($0) }
        }
        if let arr = value as? NSArray {
            return arr.map { deepConvert($0) }
        }
        return value
    }
}

extension StashDBViewModel.SavedFilter {
    /// Sanitized criteria suitable for the full filter editor.
    func criteriaObjectFilter() -> [String: Any] {
        let raw = filterDict ?? [:]
        return FilterCriteriaDocument.sanitizeNonisolated(raw, mode: mode)
    }
}
