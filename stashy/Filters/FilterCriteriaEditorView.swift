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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ForEach(document.criterionKeys, id: \.self) { key in
                    criterionRow(key: key)
                    if key != document.criterionKeys.last {
                        Divider().padding(.leading, CatalogFilterSortSheetLayout.labelColumnWidth + 28)
                    }
                }
            }
            Divider().padding(.leading, 16)
            Menu {
                ForEach(addableFields) { field in
                    Button(field.label) {
                        document.addDefaultCriterion(for: field)
                        onChange()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(appearance.tintColor)
                    Text("Add criterion")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .disabled(addableFields.isEmpty)
        }

        Group {
            if embedsInCard {
                content
                    .background(Color.secondaryAppBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
            HStack(alignment: .top, spacing: 12) {
                Text(field.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    criterionEditor(field: field)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)

                Button {
                    document.removeCriterion(key: key)
                    onChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .accessibilityLabel("Remove \(field.label)")
            }
            .padding(.horizontal, 16)
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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FilterCriteriaEditorView(
                        document: nestedDocument,
                        onChange: {},
                        embedsInCard: true
                    )
                    .padding(.top, 8)
                }
            }
            .background(Color.appBackground)
            .catalogSettingsSheetChrome(
                hasSelectedPreset: true,
                onReset: { nestedDocument.clear() },
                onRequestSave: {
                    document.setDictCriterion(key: key, dict: nestedDocument.sanitizedObjectFilter)
                    nestedEditorKey = nil
                    onChange()
                },
                onRequestSaveAs: {
                    document.setDictCriterion(key: key, dict: nestedDocument.sanitizedObjectFilter)
                    nestedEditorKey = nil
                    onChange()
                },
                onRequestRename: {},
                onRequestDelete: {
                    nestedDocument.clear()
                }
            )
            // Override chrome title via empty rename/delete disabled feel — use simple Done bar instead.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button("Cancel") { nestedEditorKey = nil }
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done") {
                        document.setDictCriterion(key: key, dict: nestedDocument.sanitizedObjectFilter)
                        nestedEditorKey = nil
                        onChange()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(appearance.tintColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationViewStyle(.stack)
        .presentationDetents([.large])
        .presentationBackground(Color(UIColor.systemGroupedBackground))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func filterEditorTextEditorChrome() -> some View {
        self
            .padding(8)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    set: { update(["modifier": $0]) }
                ),
                options: modifiers,
                onChange: onChange
            )
            if needsValue {
                TextField(placeholder, text: Binding(
                    get: { value["value"] as? String ?? "" },
                    set: { update(["value": $0]) }
                ))
                .filterEditorTextFieldChrome()
                .onSubmit { onChange() }
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

struct FilterNumericCriterionRow: View {
    @Binding var value: [String: Any]
    var isFloat: Bool
    var onChange: () -> Void

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
                    set: { update(["modifier": $0]) }
                ),
                options: FilterCriterionKind.defaultModifiers(for: isFloat ? .float : .int),
                onChange: onChange
            )
            if mod?.needsValue == true {
                HStack(spacing: 8) {
                    TextField("Value", text: numberText(key: "value"))
                        .keyboardType(isFloat ? .decimalPad : .numberPad)
                        .filterEditorTextFieldChrome()
                    if mod?.needsSecondValue == true {
                        TextField("Value 2", text: numberText(key: "value2"))
                            .keyboardType(isFloat ? .decimalPad : .numberPad)
                            .filterEditorTextFieldChrome()
                    }
                }
            }
        }
    }

    private func numberText(key: String) -> Binding<String> {
        Binding(
            get: {
                if let i = value[key] as? Int { return String(i) }
                if let d = value[key] as? Double { return String(d) }
                if let n = value[key] as? NSNumber { return n.stringValue }
                return ""
            },
            set: { raw in
                if isFloat {
                    update([key: Double(raw) ?? 0])
                } else {
                    update([key: Int(raw) ?? 0])
                }
            }
        )
    }

    private func update(_ patch: [String: Any]) {
        var next = value
        for (k, v) in patch { next[k] = v }
        value = next
        onChange()
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

    private var selected: Set<String> {
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
                        d["value"] = Array(next)
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
                .onChange(of: value) { _, _ in onChange() }
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
                    onChange()
                }
            ))
            .filterEditorTextFieldChrome()
            if multi {
                TextField("Stash IDs (comma-separated)", text: Binding(
                    get: {
                        if let arr = value["stash_ids"] as? [String] { return arr.joined(separator: ", ") }
                        return ""
                    },
                    set: {
                        let parts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        patch(["stash_ids": parts])
                    }
                ))
                .filterEditorTextFieldChrome()
            } else {
                TextField("Stash ID", text: Binding(
                    get: { value["stash_id"] as? String ?? "" },
                    set: { patch(["stash_id": $0]) }
                ))
                .filterEditorTextFieldChrome()
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
                set: { patch(["value": $0]) }
            ))
            .filterEditorTextFieldChrome()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggle("PHash", key: "phash")
            toggle("URL", key: "url")
            toggle("Stash ID", key: "stash_id")
            toggle("Title", key: "title")
        }
    }

    private func toggle(_ title: String, key: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { value[key] as? Bool ?? false },
            set: {
                var d = value
                d[key] = $0
                value = d
                onChange()
            }
        ))
    }
}

struct FilterCustomFieldsRow: View {
    @Binding var value: [[String: Any]]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(value.indices), id: \.self) { idx in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Field", text: Binding(
                        get: { value[idx]["field"] as? String ?? "" },
                        set: {
                            var rows = value
                            rows[idx]["field"] = $0
                            value = rows
                            onChange()
                        }
                    ))
                    .filterEditorTextFieldChrome()
                    TextField("Value", text: Binding(
                        get: {
                            if let arr = value[idx]["value"] as? [String] { return arr.joined(separator: ", ") }
                            if let arr = value[idx]["value"] as? [Any] {
                                return arr.map { "\($0)" }.joined(separator: ", ")
                            }
                            return ""
                        },
                        set: {
                            let parts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            var rows = value
                            rows[idx]["value"] = parts
                            value = rows
                            onChange()
                        }
                    ))
                    .filterEditorTextFieldChrome()
                    Button("Remove field", role: .destructive) {
                        var rows = value
                        rows.remove(at: idx)
                        value = rows
                        onChange()
                    }
                    .font(.caption)
                }
            }
            Button("Add custom field") {
                var rows = value
                rows.append([
                    "field": "",
                    "value": [] as [Any],
                    "modifier": StashCriterionModifier.equals.rawValue
                ])
                value = rows
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

    var body: some View {
        TextEditor(text: $text)
            .filterEditorTextEditorChrome()
            .onAppear { text = prettyJSON(value) }
            .onChange(of: text) { _, new in
                if let data = new.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    value = obj
                    onChange()
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

/// Multi-ID criterion with entity picker — owns its own ViewModel so sheets never crash on missing EnvironmentObject.
struct FilterMultiIdCriterionRow: View {
    @Binding var value: [String: Any]
    var entityKey: String
    var hierarchical: Bool
    var mode: StashDBViewModel.FilterMode
    var onChange: () -> Void

    @StateObject private var pickerViewModel = StashDBViewModel()
    @State private var options: [FilterEntityOption] = []
    @State private var loading = false
    @State private var didLoad = false

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
                onChange: onChange
            )
            CatalogNamedEntityLiveFilterMultiPickerRow(
                title: "",
                selectedIds: Binding(
                    get: { selectedIds },
                    set: { patch(["value": $0]) }
                ),
                items: options,
                displayName: { $0.name },
                isLoading: loading,
                onAppearLoad: loadIfNeeded,
                onSelectionChange: {
                    if hierarchical, value["depth"] == nil {
                        patch(["depth": 0])
                    } else {
                        onChange()
                    }
                }
            )
        }
        .onAppear { loadIfNeeded() }
    }

    private func patch(_ updates: [String: Any]) {
        var d = value
        for (k, v) in updates { d[k] = v }
        if hierarchical, d["depth"] == nil { d["depth"] = 0 }
        value = d
        onChange()
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loading = true
        let key = entityKey.lowercased()
        if key.contains("studio") {
            let studioMode: StashDBViewModel.LiveFilterStudioPickerMode = {
                switch mode {
                case .images: return .imagesHasImages
                case .galleries: return .galleriesHasGalleries
                default: return .scenesHasScenes
                }
            }()
            pickerViewModel.fetchStudiosForLiveFilterPicker(mode: studioMode) { list in
                options = list.map { FilterEntityOption(id: $0.id, name: $0.name) }
                loading = false
            }
        } else if key.contains("tag") {
            if mode == .images {
                pickerViewModel.fetchTagsForImageLiveFilterPicker { list in
                    options = list.map { FilterEntityOption(id: $0.id, name: $0.name) }
                    loading = false
                }
            } else {
                pickerViewModel.fetchTagsForSceneLiveFilterPicker { list in
                    options = list.map { FilterEntityOption(id: $0.id, name: $0.name) }
                    loading = false
                }
            }
        } else if key.contains("group") || key.contains("movie") {
            pickerViewModel.fetchGroupsForSceneLiveFilterPicker { list in
                options = list.map { FilterEntityOption(id: $0.id, name: $0.name) }
                loading = false
            }
        } else if key.contains("performer") {
            pickerViewModel.fetchPerformersForFilterPicker { list in
                options = list
                loading = false
            }
        } else {
            loading = false
        }
    }
}
