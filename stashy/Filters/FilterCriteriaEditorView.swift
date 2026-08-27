import SwiftUI

/// Full Stash criteria editor shared by catalog filter sheets and the Tools → Filters tab.
/// Layout matches the legacy live-filter popup: label column + chips/controls in a rounded card.
struct FilterCriteriaEditorView: View {
    @ObservedObject var document: FilterCriteriaDocument
    var onChange: () -> Void = {}
    var embedsInCard: Bool = true
    /// Shown in the header row next to "Add group" (e.g. the filter mode). Root level only.
    var levelTitle: String? = nil
    /// Chain of group keys from the root, e.g. `["OR", "NOT"]`. Empty = top level.
    var path: [String] = []

    @State private var nestedEditorKey: String?
    @StateObject private var nestedDocument = FilterCriteriaDocument(mode: .scenes)
    @ObservedObject private var appearance = AppearanceManager.shared

    private var levelKeys: [String] { document.criterionKeys(at: path) }
    private var groupKeys: [String] { document.groupKeys(at: path) }

    private var addableFields: [FilterFieldDescriptor] {
        FilterFieldCatalog.addableFields(
            for: document.mode,
            excludingKeys: Set(document.node(at: path).keys)
        )
    }

    /// Explains what this level does. The old UI showed AND/OR/NOT as if they were fields,
    /// which hid the fact that criteria on one level are always ANDed.
    private var levelExplanation: String {
        switch path.last {
        case "OR": return "Matches when at least one condition below is true."
        case "NOT": return "Excludes everything matching the conditions below."
        case "AND": return "All conditions below must be true."
        default: return "All conditions must be true."
        }
    }

    var body: some View {
        // One card per level: this level's own conditions, then a separate card per group.
        // Nesting used to be an indent inside a single card, which read as "more of the same list".
        VStack(spacing: DesignTokens.Spacing.sm) {
            if path.isEmpty {
                headerRow
            }
            levelExplanationLine
            if levelKeys.isEmpty {
                emptyStateCard
            } else {
                ForEach(levelKeys, id: \.self) { key in
                    criterionCard(key: key)
                }
            }
            addBarCard
            ForEach(groupKeys, id: \.self) { group in
                groupCard(group)
            }
        }
        .padding(.horizontal, embedsInCard ? DesignTokens.Spacing.md : 0)
        .padding(.bottom, embedsInCard ? DesignTokens.Spacing.xs : 0)
        // Tapping another row closes an open number pad instead of leaving it covering the sheet.
        .dismissesKeyboardOnTap()
        .sheet(item: Binding(
            get: { nestedEditorKey.map { NestedEditorIdentity(key: $0) } },
            set: { nestedEditorKey = $0?.key }
        )) { identity in
            nestedEditorSheet(key: identity.key)
        }
    }

    /// This level's own conditions. Also the drop target for the level — the group cards carry
    /// their own, so a drop always lands on exactly the level it was released over.
    /// Says how the conditions on this level combine. Sits above the cards, not inside one,
    /// because it describes the whole level rather than any single condition.
    private var levelExplanationLine: some View {
        Text(levelExplanation)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.xs + 2)
    }

    /// One condition per card — a shared card made every criterion look like a row of the same
    /// list, which hid where one condition ends and the next begins.
    private func criterionCard(key: String) -> some View {
        criterionRow(key: key)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private var emptyStateCard: some View {
        Text(groupKeys.isEmpty ? "No conditions yet — use Add below." : "No direct conditions.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm + 2)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private var addBarCard: some View {
        addBar
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    // MARK: - Level chrome

    private var headerRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let levelTitle, !levelTitle.isEmpty {
                Text(levelTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs + 2)
    }

    private var addBar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Spacer(minLength: 0)
            Menu {
                ForEach(addableFields) { field in
                    Button(field.label) {
                        document.addDefaultCriterion(for: field, at: path)
                        HapticManager.selection()
                        onChange()
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(addableFields.isEmpty ? .secondary : appearance.tintColor)
                    Text("Add condition")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(addableFields.isEmpty ? .secondary : .primary)
                }
                .contentShape(Rectangle())
            }
            .disabled(addableFields.isEmpty)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm + 2)
    }

    /// One nested AND/OR/NOT group as its own card.
    ///
    /// New groups can no longer be created — include/exclude on a single criterion covers what
    /// they were used for. Existing ones (typically written by the Stash web UI) are still shown
    /// so they can be inspected or deleted, instead of silently riding along in every save.
    @ViewBuilder
    private func groupCard(_ group: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Menu {
                    ForEach(FilterCriteriaDocument.groupKeys, id: \.self) { candidate in
                        Button {
                            document.changeGroupType(at: path, from: group, to: candidate)
                            HapticManager.selection()
                            onChange()
                        } label: {
                            if candidate == group {
                                Label(Self.groupTitle(candidate), systemImage: "checkmark")
                            } else {
                                Text(Self.groupTitle(candidate))
                            }
                        }
                        // Merging into an existing group of that type would drop criteria.
                        .disabled(candidate != group && document.groupKeys(at: path).contains(candidate))
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.groupTitle(group).uppercased())
                            .font(.caption.weight(.bold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(appearance.tintColor))
                }

                Spacer(minLength: 0)

                Button {
                    document.removeGroup(group, at: path)
                    HapticManager.selection()
                    onChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(Self.groupTitle(group)) group")
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.top, DesignTokens.Spacing.sm)

            FilterCriteriaEditorView(
                document: document,
                onChange: onChange,
                embedsInCard: false,
                path: path + [group]
            )
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.bottom, DesignTokens.Spacing.xs)
        }
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(appearance.tintColor.opacity(0.35), lineWidth: 1)
        )
    }

    static func groupTitle(_ group: String) -> String {
        switch group {
        case "AND": return "All of"
        case "OR": return "Any of"
        case "NOT": return "None of"
        default: return group
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func criterionRow(key: String) -> some View {
        let field = FilterFieldCatalog.field(key: key, mode: document.mode)
            ?? FilterFieldDescriptor(key: key, label: key, kind: .raw)

        // Name as the card's heading, controls on their own line below — a fixed label column
        // left the value side barely half the width on an iPhone.
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                Text(field.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Button {
                    document.setCriterion(key: key, value: nil, at: path)
                    HapticManager.selection()
                    onChange()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.55))
                        // Keeps the delete target clear of the expand chevron on the row below,
                        // which sits only a few points away on a collapsed card.
                        .padding(.leading, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(field.label)")
            }
            .padding(.top, DesignTokens.Spacing.sm)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                criterionEditor(field: field)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, DesignTokens.Spacing.xs + 2)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
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
        case .booleanGroup:
            // AND/OR/NOT are rendered as inset group blocks, never as a criterion row.
            EmptyView()
        case .nestedFilter:
            Button {
                openNestedEditor(key: field.key, nestedMode: field.nestedMode ?? document.mode)
            } label: {
                let count = (FilterCriteriaDocument.stringKeyedDict(document.value(forKey: field.key, at: path)) ?? [:]).count
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
            get: { FilterCriteriaDocument.stringKeyedDict(document.value(forKey: key, at: path)) ?? [:] },
            set: { document.setCriterion(key: key, value: $0, at: path) }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: {
                if let b = document.value(forKey: key, at: path) as? Bool { return b }
                return true
            },
            set: { document.setCriterion(key: key, value: $0, at: path) }
        )
    }

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                if let s = document.value(forKey: key, at: path) as? String { return s }
                return ""
            },
            set: { document.setCriterion(key: key, value: $0, at: path) }
        )
    }

    private func customFieldsBinding(for key: String) -> Binding<[[String: Any]]> {
        Binding(
            get: {
                if let arr = document.value(forKey: key, at: path) as? [[String: Any]] { return arr }
                if let arr = document.value(forKey: key, at: path) as? [Any] {
                    return arr.compactMap { FilterCriteriaDocument.stringKeyedDict($0) }
                }
                return []
            },
            set: { document.setCriterion(key: key, value: $0, at: path) }
        )
    }

    // MARK: - Nested

    private func openNestedEditor(key: String, nestedMode: StashDBViewModel.FilterMode) {
        let current = FilterCriteriaDocument.stringKeyedDict(document.value(forKey: key, at: path)) ?? [:]
        nestedDocument.reconfigure(mode: nestedMode, objectFilter: current)
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
                        document.setCriterion(key: key, value: dict.isEmpty ? nil : dict, at: path)
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

    /// Keeps a stored modifier visible even when it is no longer offered (e.g. an older filter
    /// still on `EXCLUDES`), so the picker never renders blank.
    private var resolvedOptions: [StashCriterionModifier] {
        guard !modifier.isEmpty,
              !options.contains(where: { $0.rawValue == modifier }),
              let current = StashCriterionModifier(rawValue: modifier) else { return options }
        return options + [current]
    }

    var body: some View {
        Picker("Modifier", selection: $modifier) {
            ForEach(resolvedOptions) { m in
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
                        .numericKeyboardDoneBar()
                        .filterEditorTextFieldChrome()
                        .focused($focusedField, equals: 0)
                    if mod?.needsSecondValue == true {
                        TextField("Value 2", text: numberText(key: "value2"))
                            .keyboardType(isFloat ? .decimalPad : .numberPad)
                            .numericKeyboardDoneBar()
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
            .numericKeyboardDoneBar()
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
            .numericKeyboardDoneBar()
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

    private var excludedIds: [String] {
        FilterMapper.idStrings(from: value["excludes"])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CatalogNamedEntityLiveFilterMultiPickerRow(
                title: "",
                selectedIds: Binding(
                    get: { selectedIds },
                    set: { patch(["value": $0]) }
                ),
                // Mirrors the web UI: one criterion carries both the included and the excluded
                // ids, so "tag A but not tag B" needs no NOT group at all.
                excludedIds: Binding(
                    get: { excludedIds },
                    set: { patch(["excludes": $0]) }
                ),
                // Match mode lives inside the list, not in a dropdown beside it — with per-value
                // yes/no the plain "Includes" case is the default and needs no control of its own.
                matchMode: Binding(
                    get: { modifierRaw },
                    set: { patch(["modifier": $0]) }
                ),
                matchModeOptions: FilterCriterionKind.defaultModifiers(
                    for: hierarchical ? .hierarchicalMulti : .multi
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
        // Never ship an empty `excludes` — Stash treats the key as present and it shows up in
        // saved filters as noise.
        if let excludes = d["excludes"] as? [String], excludes.isEmpty {
            d.removeValue(forKey: "excludes")
        }
        value = d
        onChange()
    }

    private func loadIfNeeded() {
        guard let kind else { return }
        store.load(kind)
    }
}
