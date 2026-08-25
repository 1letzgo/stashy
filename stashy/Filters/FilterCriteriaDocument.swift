import Foundation
import Combine

/// Editable `object_filter` document for one Stash `FilterMode`.
@MainActor
final class FilterCriteriaDocument: ObservableObject {
    private(set) var mode: StashDBViewModel.FilterMode
    @Published private(set) var objectFilter: [String: Any] {
        didSet { syncKeyOrder() }
    }

    /// Anzeige-Reihenfolge der Kriterien. Neu hinzugefügte hängen **hinten** an, damit ein
    /// frisch hinzugefügtes Modul im Editor unter den bestehenden erscheint statt alphabetisch
    /// dazwischen zu springen. Mehrere auf einmal (Laden eines Filters) werden stabil vorsortiert.
    private var keyOrder: [String] = []

    init(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any] = [:]) {
        self.mode = mode
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
        self.keyOrder = Self.defaultSortedKeys(Array(self.objectFilter.keys), mode: mode)
    }

    /// Reconfigure for nested editors (AND/OR/NOT / `*_filter`) without allocating a new object.
    func reconfigure(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any]) {
        self.mode = mode
        // Anderer Modus = andere Felder: Reihenfolge komplett neu aufbauen.
        keyOrder = []
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
        objectWillChange.send()
    }

    /// Entfernte Keys raus, neue hinten anhängen. Ein einzelner neuer Key (``addDefaultCriterion``)
    /// landet damit immer zuletzt; ein ganzer Satz (``load``) wird stabil vorsortiert.
    private func syncKeyOrder() {
        let present = Set(objectFilter.keys)
        keyOrder.removeAll { !present.contains($0) }
        let missing = present.subtracting(keyOrder)
        guard !missing.isEmpty else { return }
        keyOrder.append(contentsOf: Self.defaultSortedKeys(Array(missing), mode: mode))
    }

    /// Ausgangsordnung für Keys ohne Einfüge-Historie: AND/OR/NOT zuerst, dann nach Label.
    private static func defaultSortedKeys(_ keys: [String], mode: StashDBViewModel.FilterMode) -> [String] {
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

    var isMarkerMode: Bool { mode == .sceneMarkers }

    var sanitizedObjectFilter: [String: Any] {
        Self.sanitize(objectFilter, mode: mode)
    }

    var criterionKeys: [String] {
        let present = Set(objectFilter.keys)
        var out = keyOrder.filter { present.contains($0) }
        let missing = present.subtracting(out)
        if !missing.isEmpty {
            out.append(contentsOf: Self.defaultSortedKeys(Array(missing), mode: mode))
        }
        return out
    }

    var presentKeys: Set<String> { Set(objectFilter.keys) }

    func load(_ dict: [String: Any]?) {
        // Fremd geladenes Dictionary hat keine Einfüge-Historie — Ordnung neu aufbauen.
        keyOrder = []
        objectFilter = Self.sanitize(dict ?? [:], mode: mode)
    }

    func replaceObjectFilter(_ dict: [String: Any]) {
        keyOrder = []
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

    /// Adds an empty criterion. Never overwrites an existing one — `addableFields` already hides present keys.
    func addDefaultCriterion(for field: FilterFieldDescriptor) {
        guard objectFilter[field.key] == nil else { return }
        let value = FilterCriterionKind.defaultValue(for: field.kind, nestedMode: field.nestedMode)
        setCriterion(key: field.key, value: value)
    }

    /// Advanced criteria as the base, quick chips layered on top — an active chip always wins for
    /// its own key, so tapping a chip is never silently overruled by a criterion of the same name.
    /// Returns `nil` when nothing is active, matching the `liveFilter:` fetch parameter.
    func merged(with chipFilter: [String: Any]) -> [String: Any]? {
        var dict = sanitizedObjectFilter
        for (key, value) in chipFilter {
            dict[key] = value
        }
        return dict.isEmpty ? nil : dict
    }

    /// Number of criteria currently set — used for "n active" badges.
    var activeCriterionCount: Int { sanitizedObjectFilter.count }

    var isEmpty: Bool { sanitizedObjectFilter.isEmpty }

    func dictValue(forKey key: String) -> [String: Any] {
        Self.stringKeyedDict(objectFilter[key]) ?? [:]
    }

    func setDictCriterion(key: String, dict: [String: Any]) {
        setCriterion(key: key, value: dict)
    }

    // MARK: - Sanitize

    static func sanitize(_ dict: [String: Any], mode: StashDBViewModel.FilterMode) -> [String: Any] {
        sanitizeNonisolated(dict, mode: mode)
    }

    nonisolated static func sanitizeNonisolated(_ dict: [String: Any], mode: StashDBViewModel.FilterMode) -> [String: Any] {
        let mapped = FilterMapper.sanitize(deepStringKeyed(dict), isMarker: mode == .sceneMarkers)
        return stripEditorScratchKeys(mapped)
    }

    /// Removes UI-only scratch values (partially typed numbers) so they never reach the server.
    nonisolated static func stripEditorScratchKeys(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in dict {
            if key.hasSuffix("_text") { continue }
            if let nested = stringKeyedDict(value) {
                let cleaned = stripEditorScratchKeys(nested)
                if cleaned.isEmpty, !nested.isEmpty { continue }
                out[key] = cleaned
            } else if let arr = value as? [Any] {
                out[key] = arr.map { item -> Any in
                    if let d = stringKeyedDict(item) { return stripEditorScratchKeys(d) }
                    return item
                }
            } else {
                out[key] = value
            }
        }
        return out
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
