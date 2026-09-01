import Foundation
import Combine

/// Editable `object_filter` document for one Stash `FilterMode`.
@MainActor
final class FilterCriteriaDocument: ObservableObject {
    private(set) var mode: StashDBViewModel.FilterMode
    @Published private(set) var objectFilter: [String: Any] {
        didSet { syncKeyOrder() }
    }

    /// Anzeige-Reihenfolge der Kriterien **je Ebene** (Schlüssel: der Gruppenpfad, "" = Wurzel).
    /// Neu hinzugefügte hängen **hinten** an, damit ein frisch hinzugefügtes Modul im Editor unter
    /// den bestehenden erscheint statt alphabetisch dazwischen zu springen. Mehrere auf einmal
    /// (Laden eines Filters) werden stabil vorsortiert.
    private var keyOrders: [String: [String]] = [:]

    private var keyOrder: [String] {
        get { keyOrders[""] ?? [] }
        set { keyOrders[""] = newValue }
    }

    /// Keys the editor always shows on the root level, even without a value — the "wichtigste
    /// Kriterien" of a mode. Replaces the old quick-chip card: one list instead of chips plus a
    /// separate advanced editor.
    private(set) var pinnedKeys: [String] = []

    init(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any] = [:], pinsDefaults: Bool = false) {
        self.mode = mode
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
        self.keyOrders = ["": Self.defaultSortedKeys(Array(self.objectFilter.keys), mode: mode)]
        if pinsDefaults {
            self.pinnedKeys = FilterFieldCatalog.defaultCriterionKeys(for: mode)
        }
    }

    /// Root-level display order: pinned first (catalog order), then everything else as inserted.
    func displayedCriterionKeys() -> [String] {
        let present = criterionKeys(at: [])
        var out = pinnedKeys
        out.append(contentsOf: present.filter { !pinnedKeys.contains($0) })
        return out
    }

    /// Reconfigure for nested editors (AND/OR/NOT / `*_filter`) without allocating a new object.
    func reconfigure(mode: StashDBViewModel.FilterMode, objectFilter: [String: Any]) {
        self.mode = mode
        // Nested editors (AND/OR/NOT, `*_filter`) pin nothing — pins are a root-sheet affordance.
        pinnedKeys = []
        // Anderer Modus = andere Felder: Reihenfolge komplett neu aufbauen.
        keyOrders = [:]
        self.objectFilter = Self.sanitize(objectFilter, mode: mode)
        objectWillChange.send()
    }

    /// Entfernte Keys raus, neue hinten anhängen. Ein einzelner neuer Key (``addDefaultCriterion``)
    /// landet damit immer zuletzt; ein ganzer Satz (``load``) wird stabil vorsortiert.
    /// Nur die Wurzel — verschachtelte Ebenen pflegt ``noteInsertion`` beim Schreiben.
    private func syncKeyOrder() {
        let present = Set(objectFilter.keys)
        var order = keyOrder
        order.removeAll { !present.contains($0) }
        let missing = present.subtracting(order)
        if !missing.isEmpty {
            order.append(contentsOf: Self.defaultSortedKeys(Array(missing), mode: mode))
        }
        keyOrder = order
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
        keyOrders = [:]
        objectFilter = Self.sanitize(dict ?? [:], mode: mode)
    }

    func replaceObjectFilter(_ dict: [String: Any]) {
        keyOrders = [:]
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

    // MARK: - Group tree
    //
    // Stash nests boolean groups inside `object_filter`: keys other than AND/OR/NOT are plain
    // criteria and implicitly ANDed, while `AND` / `OR` / `NOT` hold a nested filter of the same
    // shape. A path is the chain of group keys from the root, e.g. `["OR", "NOT"]`.

    static let groupKeys = ["AND", "OR", "NOT"]

    static func isGroupKey(_ key: String) -> Bool { groupKeys.contains(key) }

    /// Dictionary at `path`, or an empty one when the path does not exist (yet).
    func node(at path: [String]) -> [String: Any] {
        var current = objectFilter
        for step in path {
            guard let next = Self.stringKeyedDict(current[step]) else { return [:] }
            current = next
        }
        return current
    }

    /// Plain criteria at `path`, in display order.
    func criterionKeys(at path: [String]) -> [String] {
        let dict = node(at: path)
        let present = Set(dict.keys).subtracting(Self.groupKeys)
        let order = keyOrders[Self.orderKey(path)] ?? []
        var out = order.filter { present.contains($0) }
        out.append(contentsOf: Self.defaultSortedKeys(Array(present.subtracting(out)), mode: mode))
        return out
    }

    /// Nested groups at `path`, always in AND / OR / NOT order so the tree never reshuffles.
    func groupKeys(at path: [String]) -> [String] {
        let dict = node(at: path)
        return Self.groupKeys.filter { dict[$0] != nil }
    }

    func value(forKey key: String, at path: [String]) -> Any? {
        node(at: path)[key]
    }

    func setCriterion(key: String, value: Any?, at path: [String]) {
        guard !path.isEmpty else {
            setCriterion(key: key, value: value)
            return
        }
        var root = objectFilter
        Self.mutate(&root, path: path) { node in
            if let value { node[key] = value } else { node.removeValue(forKey: key) }
        }
        if value != nil { noteInsertion(of: key, at: path) }
        objectFilter = root
    }

    /// Adds an empty criterion at `path`. Never overwrites an existing one.
    func addDefaultCriterion(for field: FilterFieldDescriptor, at path: [String]) {
        guard node(at: path)[field.key] == nil else { return }
        let value = FilterCriterionKind.defaultValue(for: field.kind, nestedMode: field.nestedMode)
        setCriterion(key: field.key, value: value, at: path)
    }

    /// Creates an empty group. No-op when that group already exists at `path`.
    func addGroup(_ group: String, at path: [String]) {
        guard Self.isGroupKey(group), node(at: path)[group] == nil else { return }
        var root = objectFilter
        if path.isEmpty {
            root[group] = [String: Any]()
        } else {
            Self.mutate(&root, path: path) { $0[group] = [String: Any]() }
        }
        objectFilter = root
    }

    /// Removes a group **and everything inside it**.
    func removeGroup(_ group: String, at path: [String]) {
        var root = objectFilter
        if path.isEmpty {
            root.removeValue(forKey: group)
        } else {
            Self.mutate(&root, path: path) { $0.removeValue(forKey: group) }
        }
        objectFilter = root
    }

    /// Retypes a group in place (AND ⇄ OR ⇄ NOT), keeping its contents.
    /// No-op when the target type already exists at that path — merging two groups would
    /// silently drop criteria.
    func changeGroupType(at path: [String], from oldGroup: String, to newGroup: String) {
        guard oldGroup != newGroup, Self.isGroupKey(newGroup) else { return }
        let parent = node(at: path)
        guard let contents = Self.stringKeyedDict(parent[oldGroup]), parent[newGroup] == nil else { return }
        var root = objectFilter
        let apply: (inout [String: Any]) -> Void = { node in
            node.removeValue(forKey: oldGroup)
            node[newGroup] = contents
        }
        if path.isEmpty { apply(&root) } else { Self.mutate(&root, path: path, apply) }
        // Display order lives under the old path — move it so the group keeps its layout.
        let oldOrder = keyOrders.removeValue(forKey: Self.orderKey(path + [oldGroup]))
        keyOrders[Self.orderKey(path + [newGroup])] = oldOrder
        objectFilter = root
    }

    /// Walks `path`, creating missing levels, and applies `body` to the node it lands on.
    private static func mutate(
        _ dict: inout [String: Any],
        path: [String],
        _ body: (inout [String: Any]) -> Void
    ) {
        guard let step = path.first else {
            body(&dict)
            return
        }
        var child = stringKeyedDict(dict[step]) ?? [:]
        mutate(&child, path: Array(path.dropFirst()), body)
        dict[step] = child
    }

    private static func orderKey(_ path: [String]) -> String { path.joined(separator: "/") }

    private func noteInsertion(of key: String, at path: [String]) {
        let orderKey = Self.orderKey(path)
        var order = keyOrders[orderKey] ?? []
        order.removeAll { $0 == key }
        order.append(key)
        keyOrders[orderKey] = order
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

    /// Inverse of ``merged(with:)``: `base` first, this document's criteria on top.
    ///
    /// Feeds still derive a base fragment from the selected saved filter (studios / tags / groups),
    /// but the editor is the surface the user actually sees — so an edited criterion must win over
    /// the mirrored one, otherwise clearing it in the sheet would have no effect.
    func layered(over base: [String: Any]) -> [String: Any]? {
        var dict = base
        for (key, value) in sanitizedObjectFilter {
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
