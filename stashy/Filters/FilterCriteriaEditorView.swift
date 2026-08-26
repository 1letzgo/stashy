import SwiftUI

/// Full Stash criteria editor shared by catalog filter sheets and the Tools → Filters tab.
/// Layout matches the legacy live-filter popup: label column + chips/controls in a rounded card.
struct FilterCriteriaEditorView: View {
    @ObservedObject var document: FilterCriteriaDocument
    var onChange: () -> Void = {}
    var embedsInCard: Bool = true

    @State private var nestedEditorKey: String?
    @StateObject private var nestedDocument = FilterCriteriaDocument(mode: .scenes)
    @ObservedObject private var appearance = AppearanceManager.shared

    private var addableFields: [FilterFieldDescriptor] {
        FilterFieldCatalog.addableFields(for: document.mode, excludingKeys: document.presentKeys)
    }

    var body: some View {
        let content = VStack(spacing: 0) {
            if document.criterionKeys.isEmpty {
                Text("No criteria — use Add below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm + 2)
            } else {
                ForEach(document.criterionKeys, id: \.self) { key in
                    criterionRow(key: key)
                    if key != document.criterionKeys.last {
                        Divider().padding(.leading, CatalogFilterSortSheetLayout.labelColumnWidth + 28)
                    }
                }
            }
            Divider().padding(.leading, DesignTokens.Spacing.md)
            Menu {
                ForEach(addableFields) { field in
                    Button(field.label) {
                        document.addDefaultCriterion(for: field)
                        HapticManager.selection()
                        onChange()
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(addableFields.isEmpty ? .secondary : appearance.tintColor)
                    Text("Add criterion")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(addableFields.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm + 2)
                .contentShape(Rectangle())
            }
            .disabled(addableFields.isEmpty)
        }

        Group {
            if embedsInCard {
                content
                    .background(Color.secondaryAppBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.xs)
            } else {
                content
            }
        }
        .sheet(item: Binding(
            get: { nestedEditorKey.map { NestedEditorIdentity(key: $0) } },
            set: { nestedEditorKey = $0?.key }
        )) { identity in
            nestedEditorSheet(key: identity.key)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func criterionRow(key: String) -> some View {
        let field = FilterFieldCatalog.field(key: key, mode: document.mode)
            ?? FilterFieldDescriptor(key: key, label: key, kind: .raw)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Text(field.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    .padding(.top, DesignTokens.Spacing.sm)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    criterionEditor(field: field)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignTokens.Spacing.xs + 2)

                Button {
                    document.removeCriterion(key: key)
                    HapticManager.selection()
                    onChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.top, DesignTokens.Spacing.sm)
                .accessibilityLabel("Remove \(field.label)")
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }
    @ViewBuilder
    private func criterionEditor(field: FilterFieldDescriptor) -> some View {
        switch field.kind {
        case .boolean:
            FilterBoolCriterionRow(value: boolBinding(for: field.key), onChange: onChange)
        case .string:
            FilterStringCriterionRow(value: dictBinding(for: field.key), onChange: onChange)
        case .int, .hierarchicalCount:
            FilterNumericCriterionRow(value: dictBinding(for: field.key), isFloat: false, onChange: onChange)
        case .float:
            FilterNumericCriterionRow(value: dictBinding(for: field.key), isFloat: true, onChange: onChange)
        case .date, .timestamp:
            FilterStringCriterionRow(
                value: dictBinding(for: field.key),
                placeholder: field.kind == .date ? "YYYY-MM-DD" : "Timestamp / relative",
                modifiers: FilterCriterionKind.defaultModifiers(for: field.kind),
                onChange: onChange
            )
        case .resolution:
            FilterResolutionCriterionRow(value: dictBinding(for: field.key), onChange: onChange)
        case .orientation:
            FilterOrientationCriterionRow(value: dictBinding(for: field.key), onChange: onChange)
        case .gender:
            FilterGenderCriterionRow(value: dictBinding(for: field.key), onChange: onChange)
        case .circumcision:
            FilterCircumcisionCriterionRow(value: dictBinding(for: field.key), onChange: onChange)
        case .hierarchicalMulti:
            FilterMultiIdCriterionRow(
                value: dictBinding(for: field.key),
                entityKey: field.key,
                hierarchical: true,
                mode: document.mode,
                onChange: onChange
            )
        case .multi:
            FilterMultiIdCriterionRow(
                value: dictBinding(for: field.key),
                entityKey: field.key,
                hierarchical: false,
                mode: document.mode,
                onChange: onChange
            )
        case .isMissing:
            FilterIsMissingRow(value: stringBinding(for: field.key), onChange: onChange)
        case .hasMarkers, .hasChapters:
            FilterTrueFalseStringRow(value: stringBinding(for: field.key), onChange: onChange)
        case .stashID, .stashIDs:
            FilterStashIDCriterionRow(
                value: dictBinding(for: field.key),
                multi: field.kind == .stashIDs,
                onChange: onChange
            )
        case .phashDistance:
            FilterPhashDistanceRow(value: dictBinding(for: field.key), onChange: onChange)
        case .duplication:
            FilterDuplicationRow(value: dictBinding(for: field.key), onChange: onChange)
        case .customFields:
            FilterCustomFieldsRow(value: customFieldsBinding(for: field.key), onChange: onChange)
        case .booleanGroup, .nestedFilter:
            Button {
                openNestedEditor(key: field.key, nestedMode: field.nestedMode ?? document.mode)
            } label: {
                let count = document.dictValue(forKey: field.key).count
                HStack(spacing: 6) {
                    Text(count == 0 ? "Edit…" : "\(count) criterion(s)")
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        case .raw:
            FilterRawJSONRow(value: dictBinding(for: field.key), onChange: onChange)
        }
    }

    // MARK: - Bindings

    private func dictBinding(for key: String) -> Binding<[String: Any]> {
        Binding(
            get: { document.dictValue(forKey: key) },
            set: { document.setDictCriterion(key: key, dict: $0) }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                if let b = document.value(forKey: key) as? Bool { return b }
                return true
            },
            set: { document.setCriterion(key: key, value: $0) }
        )
    }

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                if let s = document.value(forKey: key) as? String { return s }
                return ""
            },
            set: { document.setCriterion(key: key, value: $0) }
        )
    }

    private func customFieldsBinding(for key: String) -> Binding<[[String: Any]]> {
        Binding(
            get: {
                if let arr = document.value(forKey: key) as? [[String: Any]] { return arr }
                if let arr = document.value(forKey: key) as? [Any] {
                    return arr.compactMap { FilterCriteriaDocument.stringKeyedDict($0) }
                }
                return []
            },
            set: { document.setCriterion(key: key, value: $0) }
        )
    }

    // MARK: - Nested

    private func openNestedEditor(key: String, nestedMode: StashDBViewModel.FilterMode) {
        nestedDocument.reconfigure(mode: nestedMode, objectFilter: document.dictValue(forKey: key))
        nestedEditorKey = key
    }

    private func nestedEditorSheet(key: String) -> some View {
        let title = FilterFieldCatalog.field(key: key, mode: document.mode)?.label ?? key
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    FilterCriteriaEditorView(document: nestedDocument, onChange: {})
                        .padding(.top, DesignTokens.Spacing.xs)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { nestedEditorKey = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let dict = nestedDocument.sanitizedObjectFilter
                        if dict.isEmpty {
                            document.removeCriterion(key: key)
                        } else {
                            document.setDictCriterion(key: key, dict: dict)
                        }
                        nestedEditorKey = nil
                        onChange()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}

private struct NestedEditorIdentity: Identifiable {
    let key: String
    var id: String { key }
}


// MARK: - Field chrome (avoid system roundedBorder — black on dark cards)

private extension View {
    func filterEditorTextFieldChrome() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.xs + 2)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small - 2))
    }

    func filterEditorTextEditorChrome() -> some View {
        self
            .padding(DesignTokens.Spacing.xs)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small - 2))
    }
}

// MARK: - Shared chip helpers

struct FilterEditorChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        CatalogFilterChip(title: title, isActive: isActive, action: action)
    }
}

struct FilterModifierPicker: View {
    @Binding var modifier: String
    var options: [StashCriterionModifier]
    var onChange: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Picker("Modifier", selection: $modifier) {
            ForEach(options) { m in
                Text(m.label).tag(m.rawValue)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(appearance.tintColor)
        .onChange(of: modifier) { _, _ in onChange() }
    }
}

// MARK: - Criterion rows

struct FilterBoolCriterionRow: View {
    @Binding var value: Bool
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CatalogFilterChip(title: "Yes", isActive: value) { value = true; onChange() }
            CatalogFilterChip(title: "No", isActive: !value) { value = false; onChange() }
        }
    }
}

struct FilterStringCriterionRow: View {
    @Binding var value: [String: Any]
    var placeholder: String = "Value"
    var modifiers: [StashCriterionModifier] = FilterCriterionKind.defaultModifiers(for: .string)
    var onChange: () -> Void

    @FocusState private var isFocused: Bool

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.includes.rawValue
    }

    private var needsValue: Bool {
        StashCriterionModifier(rawValue: modifierRaw)?.needsValue ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: { patch(["modifier": $0], commit: true) }
                ),
                options: modifiers,
                onChange: {}
            )
            if needsValue {
                // Text edits only update the document; `onChange` (= refetch) fires on commit.
                TextField(placeholder, text: Binding(
                    get: { value["value"] as? String ?? "" },
                    set: { patch(["value": $0], commit: false) }
                ))
                .filterEditorTextFieldChrome()
                .focused($isFocused)
                .onSubmit { onChange() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { onChange() }
                }
            }
        }
    }

    private func patch(_ updates: [String: Any], commit: Bool) {
        var next = value
        for (k, v) in updates { next[k] = v }
        value = next
        if commit { onChange() }
    }
}

struct FilterNumericCriterionRow: View {
    @Binding var value: [String: Any]
    var isFloat: Bool
    var onChange: () -> Void

    @FocusState private var focusedField: Int?

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.equals.rawValue
    }

    private var mod: StashCriterionModifier? {
        StashCriterionModifier(rawValue: modifierRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: { patch(["modifier": $0], commit: true) }
                ),
                options: FilterCriterionKind.defaultModifiers(for: isFloat ? .float : .int),
                onChange: {}
            )
            if mod?.needsValue == true {
                HStack(spacing: 8) {
                    TextField("Value", text: numberText(key: "value"))
                        .keyboardType(isFloat ? .decimalPad : .numberPad)
                        .filterEditorTextFieldChrome()
                        .focused($focusedField, equals: 0)
                    if mod?.needsSecondValue == true {
                        TextField("Value 2", text: numberText(key: "value2"))
                            .keyboardType(isFloat ? .decimalPad : .numberPad)
                            .filterEditorTextFieldChrome()
                            .focused($focusedField, equals: 1)
                    }
                }
                .onChange(of: focusedField) { _, new in
                    if new == nil { onChange() }
                }
            }
        }
    }

    /// Keeps the raw string so a field can be cleared or hold a partial number ("1.") while typing.
    private func numberText(key: String) -> Binding<String> {
        Binding(
            get: {
                if let s = value["\(key)_text"] as? String { return s }
                if let i = value[key] as? Int { return String(i) }
                if let d = value[key] as? Double { return String(d) }
                if let n = value[key] as? NSNumber { return n.stringValue }
                return ""
            },
            set: { raw in
                var next = value
                if raw.isEmpty {
                    next.removeValue(forKey: key)
                    next.removeValue(forKey: "\(key)_text")
                } else if isFloat, let d = Double(raw) {
                    next[key] = d
                    next.removeValue(forKey: "\(key)_text")
                } else if !isFloat, let i = Int(raw) {
                    next[key] = i
                    next.removeValue(forKey: "\(key)_text")
                } else {
                    // Partial input ("-", "1.") — remember the text, keep the last valid number out of the filter.
                    next["\(key)_text"] = raw
                }
                value = next
            }
        )
    }

    private func patch(_ updates: [String: Any], commit: Bool) {
        var next = value
        for (k, v) in updates { next[k] = v }
        value = next
        if commit { onChange() }
    }
}

struct FilterResolutionCriterionRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.equals.rawValue
    }

    private var resolutionRaw: String {
        (value["value"] as? String) ?? StashResolutionOption.fullHD.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: { update(["modifier": $0]) }
                ),
                options: FilterCriterionKind.defaultModifiers(for: .resolution),
                onChange: onChange
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StashResolutionOption.allCases) { r in
                        CatalogFilterChip(title: r.label, isActive: resolutionRaw == r.rawValue) {
                            update(["value": r.rawValue])
                        }
                    }
                }
            }
        }
    }

    private func update(_ patch: [String: Any]) {
        var next = value
        for (k, v) in patch { next[k] = v }
        value = next
        onChange()
    }
}

struct FilterOrientationCriterionRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void

    private var selected: Set<String> {
        if let arr = value["value"] as? [String] { return Set(arr) }
        if let s = value["value"] as? String { return [s] }
        return []
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StashOrientationOption.allCases) { opt in
                CatalogFilterChip(title: opt.label, isActive: selected.contains(opt.rawValue)) {
                    var next = selected
                    if next.contains(opt.rawValue) { next.remove(opt.rawValue) }
                    else { next.insert(opt.rawValue) }
                    var d = value
                    d["value"] = Array(next)
                    value = d
                    onChange()
                }
            }
        }
    }
}

struct FilterGenderCriterionRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.includes.rawValue
    }

    /// `GenderCriterionInput` carries a single `value` and a multi `value_list`; read both, write `value_list`.
    private var selected: Set<String> {
        if let arr = value["value_list"] as? [String] { return Set(arr) }
        if let arr = value["value"] as? [String] { return Set(arr) }
        if let s = value["value"] as? String { return [s] }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: {
                        var d = value
                        d["modifier"] = $0
                        value = d
                        onChange()
                    }
                ),
                options: FilterCriterionKind.defaultModifiers(for: .gender),
                onChange: onChange
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(StashGenderOption.allCases) { opt in
                    CatalogFilterChip(title: opt.label, isActive: selected.contains(opt.rawValue)) {
                        var next = selected
                        if next.contains(opt.rawValue) { next.remove(opt.rawValue) }
                        else { next.insert(opt.rawValue) }
                        var d = value
                        d.removeValue(forKey: "value")
                        d["value_list"] = Array(next).sorted()
                        value = d
                        onChange()
                    }
                }
            }
        }
    }
}

struct FilterCircumcisionCriterionRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void
    private let options = ["CUT", "UNCUT"]

    private var selected: Set<String> {
        if let arr = value["value"] as? [String] { return Set(arr) }
        return []
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { opt in
                CatalogFilterChip(title: opt.capitalized, isActive: selected.contains(opt)) {
                    var next = selected
                    if next.contains(opt) { next.remove(opt) } else { next.insert(opt) }
                    var d = value
                    d["value"] = Array(next)
                    d["modifier"] = StashCriterionModifier.includes.rawValue
                    value = d
                    onChange()
                }
            }
        }
    }
}

struct FilterIsMissingRow: View {
    @Binding var value: String
    var onChange: () -> Void
    private let common = ["title", "studio", "performers", "tags", "date", "details", "url", "cover", "galleries", "stash_id"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Property name", text: $value)
                .filterEditorTextFieldChrome()
                .onSubmit { onChange() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(common, id: \.self) { c in
                        CatalogFilterChip(title: c, isActive: value == c) {
                            value = c
                            onChange()
                        }
                    }
                }
            }
        }
    }
}

struct FilterTrueFalseStringRow: View {
    @Binding var value: String
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CatalogFilterChip(title: "Yes", isActive: value == "true") { value = "true"; onChange() }
            CatalogFilterChip(title: "No", isActive: value == "false") { value = "false"; onChange() }
        }
    }
}

struct FilterStashIDCriterionRow: View {
    @Binding var value: [String: Any]
    var multi: Bool
    var onChange: () -> Void

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.notNull.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: { patch(["modifier": $0]) }
                ),
                options: FilterCriterionKind.defaultModifiers(for: multi ? .stashIDs : .stashID),
                onChange: onChange
            )
            TextField("Endpoint (optional)", text: Binding(
                get: { value["endpoint"] as? String ?? "" },
                set: {
                    var d = value
                    if $0.isEmpty { d.removeValue(forKey: "endpoint") }
                    else { d["endpoint"] = $0 }
                    value = d
                }
            ))
            .filterEditorTextFieldChrome()
            .onSubmit { onChange() }
            // `StashIDCriterionInput` only has `endpoint`, `stash_id` and `modifier` — no id list.
            if StashCriterionModifier(rawValue: modifierRaw)?.needsValue ?? true {
                TextField("Stash ID", text: Binding(
                    get: { value["stash_id"] as? String ?? "" },
                    set: {
                        var d = value
                        if $0.isEmpty { d.removeValue(forKey: "stash_id") } else { d["stash_id"] = $0 }
                        value = d
                    }
                ))
                .filterEditorTextFieldChrome()
                .onSubmit { onChange() }
            }
        }
    }

    private func patch(_ updates: [String: Any]) {
        var d = value
        for (k, v) in updates { d[k] = v }
        value = d
        onChange()
    }
}

struct FilterPhashDistanceRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("PHash", text: Binding(
                get: { value["value"] as? String ?? "" },
                set: {
                    var d = value
                    d["value"] = $0
                    value = d
                }
            ))
            .filterEditorTextFieldChrome()
            .onSubmit { onChange() }
            TextField("Distance", text: Binding(
                get: {
                    if let i = value["distance"] as? Int { return String(i) }
                    if let n = value["distance"] as? NSNumber { return n.stringValue }
                    return "0"
                },
                set: { patch(["distance": Int($0) ?? 0]) }
            ))
            .keyboardType(.numberPad)
            .filterEditorTextFieldChrome()
        }
    }

    private func patch(_ updates: [String: Any]) {
        var d = value
        for (k, v) in updates { d[k] = v }
        value = d
        onChange()
    }
}

struct FilterDuplicationRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void

    /// `PHashDuplicationCriterionInput { duplicated: Boolean, distance: Int }`.
    private var duplicated: Bool { value["duplicated"] as? Bool ?? true }

    private var distanceText: String {
        if let i = value["distance"] as? Int { return String(i) }
        if let n = value["distance"] as? NSNumber { return n.stringValue }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CatalogFilterChip(title: "Duplicated", isActive: duplicated) { patch(["duplicated": true]) }
                CatalogFilterChip(title: "Unique", isActive: !duplicated) { patch(["duplicated": false]) }
            }
            TextField("PHash distance (optional)", text: Binding(
                get: { distanceText },
                set: { raw in
                    var d = value
                    if raw.isEmpty { d.removeValue(forKey: "distance") }
                    else { d["distance"] = Int(raw) ?? 0 }
                    value = d
                }
            ))
            .keyboardType(.numberPad)
            .filterEditorTextFieldChrome()
            .onSubmit { onChange() }
        }
    }

    private func patch(_ updates: [String: Any]) {
        var d = value
        for (k, v) in updates { d[k] = v }
        value = d
        onChange()
    }
}

struct FilterCustomFieldsRow: View {
    @Binding var value: [[String: Any]]
    var onChange: () -> Void

    /// Stable identity per row so editing/removing does not rebind neighbouring text fields.
    private struct Row: Identifiable {
        let id: Int
        let index: Int
    }

    private var rows: [Row] {
        value.indices.map { idx in
            let field = value[idx]["field"] as? String ?? ""
            return Row(id: field.isEmpty ? idx : field.hashValue, index: idx)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                let idx = row.index
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Field", text: Binding(
                        get: { value.indices.contains(idx) ? (value[idx]["field"] as? String ?? "") : "" },
                        set: {
                            guard value.indices.contains(idx) else { return }
                            var next = value
                            next[idx]["field"] = $0
                            value = next
                        }
                    ))
                    .filterEditorTextFieldChrome()
                    .onSubmit { onChange() }
                    TextField("Value", text: Binding(
                        get: {
                            guard value.indices.contains(idx) else { return "" }
                            if let arr = value[idx]["value"] as? [String] { return arr.joined(separator: ", ") }
                            if let arr = value[idx]["value"] as? [Any] {
                                return arr.map { "\($0)" }.joined(separator: ", ")
                            }
                            return ""
                        },
                        set: {
                            guard value.indices.contains(idx) else { return }
                            let parts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            var next = value
                            next[idx]["value"] = parts
                            value = next
                        }
                    ))
                    .filterEditorTextFieldChrome()
                    .onSubmit { onChange() }
                    Button("Remove field", role: .destructive) {
                        guard value.indices.contains(idx) else { return }
                        var next = value
                        next.remove(at: idx)
                        value = next
                        onChange()
                    }
                    .font(.caption)
                }
            }
            Button("Add custom field") {
                var next = value
                next.append([
                    "field": "",
                    "value": [] as [Any],
                    "modifier": StashCriterionModifier.equals.rawValue
                ])
                value = next
                onChange()
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

struct FilterRawJSONRow: View {
    @Binding var value: [String: Any]
    var onChange: () -> Void
    @State private var text: String = ""
    @State private var parseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .filterEditorTextEditorChrome()
                .onAppear { text = prettyJSON(value) }
                .onChange(of: text) { _, new in
                    guard let data = new.data(using: .utf8) else {
                        parseError = "Invalid text encoding"
                        return
                    }
                    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                        parseError = "Not a valid JSON object"
                        return
                    }
                    parseError = nil
                    value = obj
                }
            if let parseError {
                Label(parseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func prettyJSON(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

/// Multi-ID criterion with entity picker, backed by the shared cached option store.
struct FilterMultiIdCriterionRow: View {
    @Binding var value: [String: Any]
    var entityKey: String
    var hierarchical: Bool
    var mode: StashDBViewModel.FilterMode
    var onChange: () -> Void

    @ObservedObject private var store = FilterPickerOptionsStore.shared

    private var kind: FilterPickerOptionsStore.Kind? {
        FilterPickerOptionsStore.kind(forCriterionKey: entityKey, mode: mode)
    }

    private var options: [FilterEntityOption] {
        kind.map { store.availableOptions($0) } ?? []
    }

    private var isLoading: Bool {
        kind.map { store.isLoading($0) } ?? false
    }

    private var modifierRaw: String {
        (value["modifier"] as? String) ?? StashCriterionModifier.includes.rawValue
    }

    private var selectedIds: [String] {
        FilterMapper.idStrings(from: value["value"])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterModifierPicker(
                modifier: Binding(
                    get: { modifierRaw },
                    set: { patch(["modifier": $0]) }
                ),
                options: FilterCriterionKind.defaultModifiers(for: hierarchical ? .hierarchicalMulti : .multi),
                onChange: {}
            )
            CatalogNamedEntityLiveFilterMultiPickerRow(
                title: "",
                selectedIds: Binding(
                    get: { selectedIds },
                    set: { patch(["value": $0]) }
                ),
                items: options,
                displayName: { $0.name },
                isLoading: isLoading,
                onAppearLoad: loadIfNeeded,
                onSelectionChange: {},
                searchKind: kind
            )
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func patch(_ updates: [String: Any]) {
        var d = value
        for (k, v) in updates { d[k] = v }
        if hierarchical, d["depth"] == nil { d["depth"] = 0 }
        value = d
        onChange()
    }

    private func loadIfNeeded() {
        guard let kind else { return }
        store.load(kind)
    }
}
