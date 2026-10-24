//
//  CatalogQuickFilters.swift
//  stashy
//
//  Quick sort strip and active-filter chips above every catalog list, plus the quick-filter
//  card at the top of the filter sheets. Everything reads and writes the same
//  `FilterCriteriaDocument`, so a quick chip, the active-filter chip and the advanced editor
//  always show the same criterion.
//

#if !os(tvOS)
import SwiftUI

// MARK: - Sort options

/// Every catalog sort enum already exposes Stash's `sort` field and direction.
protocol CatalogQuickSortable: CaseIterable, Hashable {
    var sortField: String { get }
    var direction: String { get }
}

extension StashDBViewModel.SceneSortOption: CatalogQuickSortable {}
extension StashDBViewModel.PerformerSortOption: CatalogQuickSortable {}
extension StashDBViewModel.StudioSortOption: CatalogQuickSortable {}
extension StashDBViewModel.TagSortOption: CatalogQuickSortable {}
extension StashDBViewModel.GallerySortOption: CatalogQuickSortable {}
extension StashDBViewModel.ImageSortOption: CatalogQuickSortable {}
extension StashDBViewModel.GroupSortOption: CatalogQuickSortable {}
extension StashDBViewModel.SceneMarkerSortOption: CatalogQuickSortable {}

enum CatalogQuickSortCatalog {
    struct Field: Hashable {
        let field: String
        let label: String
    }

    /// The handful of sorts worth one tap per catalog; everything else stays in the sheet.
    static func fields(for mode: StashDBViewModel.FilterMode) -> [Field] {
        switch mode {
        case .scenes:
            return [.init(field: "date", label: "Date"), .init(field: "created_at", label: "Added"),
                    .init(field: "rating", label: "Rating"), .init(field: "o_counter", label: "O Count"),
                    .init(field: "duration", label: "Duration"), .init(field: "last_played_at", label: "Last played"),
                    .init(field: "play_count", label: "Plays"), .init(field: "random", label: "Random")]
        case .performers:
            return [.init(field: "scenes_count", label: "Scenes"), .init(field: "name", label: "Name"),
                    .init(field: "o_counter", label: "O Count"), .init(field: "rating", label: "Rating"),
                    .init(field: "created_at", label: "Added"), .init(field: "birthdate", label: "Birthday"),
                    .init(field: "random", label: "Random")]
        case .studios:
            return [.init(field: "scenes_count", label: "Scenes"), .init(field: "name", label: "Name"),
                    .init(field: "rating", label: "Rating"), .init(field: "created_at", label: "Added"),
                    .init(field: "random", label: "Random")]
        case .tags:
            return [.init(field: "scenes_count", label: "Scenes"), .init(field: "name", label: "Name"),
                    .init(field: "created_at", label: "Added"), .init(field: "random", label: "Random")]
        case .galleries:
            return [.init(field: "date", label: "Date"), .init(field: "created_at", label: "Added"),
                    .init(field: "rating", label: "Rating"), .init(field: "images_count", label: "Images"),
                    .init(field: "title", label: "Title"), .init(field: "random", label: "Random")]
        case .images:
            return [.init(field: "date", label: "Date"), .init(field: "created_at", label: "Added"),
                    .init(field: "rating", label: "Rating"), .init(field: "o_counter", label: "O Count"),
                    .init(field: "title", label: "Title"), .init(field: "random", label: "Random")]
        case .groups:
            return [.init(field: "name", label: "Name"), .init(field: "date", label: "Date"),
                    .init(field: "rating", label: "Rating"), .init(field: "scenes_count", label: "Scenes"),
                    .init(field: "created_at", label: "Added"), .init(field: "random", label: "Random")]
        case .sceneMarkers:
            return [.init(field: "created_at", label: "Added"), .init(field: "title", label: "Title"),
                    .init(field: "seconds", label: "Time"), .init(field: "random", label: "Random")]
        case .unknown:
            return []
        }
    }

    static func isRandom(_ field: String) -> Bool { field.hasPrefix("random") }

    /// Names read A→Z first; counts, dates and ratings read highest/newest first.
    static func defaultAscending(_ field: String) -> Bool {
        field == "name" || field == "title"
    }

    static func option<Option: CatalogQuickSortable>(_ type: Option.Type, field: String, ascending: Bool) -> Option? {
        if isRandom(field) { return Option.allCases.first { isRandom($0.sortField) } }
        return Option.allCases.first { $0.sortField == field && ($0.direction == "ASC") == ascending }
    }

    /// Sort after tapping `field`: the active field flips direction (Random re-rolls), any other
    /// field starts in its natural direction.
    static func next<Option: CatalogQuickSortable>(after current: Option, tapping field: String) -> Option? {
        if isRandom(field) { return option(Option.self, field: field, ascending: false) }
        if current.sortField == field {
            return option(Option.self, field: field, ascending: current.direction != "ASC")
        }
        let natural = defaultAscending(field)
        return option(Option.self, field: field, ascending: natural)
            ?? option(Option.self, field: field, ascending: !natural)
    }
}

// MARK: - Quick filter definitions

struct QuickFilterChoice: Identifiable {
    let id: String
    /// Chip text in the sheet ("3★", "Under 10 min").
    let label: String
    /// Text of the active-filter chip above the list ("Rating 3★+").
    let activeLabel: String
    let value: Any
}

enum QuickFilterSection: Identifiable {
    /// One of a fixed set of values, plus "Any".
    case choices(key: String, title: String, anyLabel: String, choices: [QuickFilterChoice])
    /// Most-used entities (tags) as toggle chips, with a name search.
    case entities(key: String, title: String)

    var id: String { key }

    var key: String {
        switch self {
        case .choices(let key, _, _, _), .entities(let key, _): return key
        }
    }
}

enum QuickFilterCatalog {
    static func sections(for mode: StashDBViewModel.FilterMode) -> [QuickFilterSection] {
        let all: [QuickFilterSection]
        switch mode {
        case .scenes:
            all = [.entities(key: "tags", title: "Tags"), rating, sceneDuration, resolution, organized, watched]
        case .performers:
            all = [gender, favorite(key: "filter_favorites"), rating, age, .entities(key: "tags", title: "Tags")]
        case .studios:
            all = [favorite(key: "favorite"), rating, .entities(key: "tags", title: "Tags")]
        case .tags:
            all = [favorite(key: "favorite"), hasScenes]
        case .galleries, .images:
            all = [.entities(key: "tags", title: "Tags"), rating, organized]
        case .groups:
            all = [.entities(key: "tags", title: "Tags"), rating]
        case .sceneMarkers:
            all = [.entities(key: "tags", title: "Tags")]
        case .unknown:
            all = []
        }
        // Never offer a key the mode does not know (catalogs differ between Stash versions).
        let known = Set(FilterFieldCatalog.fields(for: mode).map(\.key))
        return all.filter { known.contains($0.key) }
    }

    /// Active-filter label when `value` is exactly one of the quick choices for `key`.
    static func activeLabel(key: String, value: Any, mode: StashDBViewModel.FilterMode) -> String? {
        guard let target = canonical(value) else { return nil }
        for section in sections(for: mode) {
            guard case .choices(let k, _, _, let choices) = section, k == key else { continue }
            return choices.first { canonical($0.value) == target }?.activeLabel
        }
        return nil
    }

    /// Stable text form for comparing criterion payloads regardless of key order or number type.
    static func canonical(_ value: Any?) -> String? {
        guard let value else { return nil }
        let normalized: Any = FilterCriteriaDocument.stringKeyedDict(value)
            .map { FilterCriteriaDocument.deepStringKeyed($0) } ?? value
        guard let data = try? JSONSerialization.data(
            withJSONObject: normalized, options: [.sortedKeys, .fragmentsAllowed]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Stash stores ratings as 0–100; n stars = rating100 ≥ n·20.
    private static let rating = QuickFilterSection.choices(
        key: "rating100", title: "Minimum rating", anyLabel: "Any",
        choices: (1...5).map { stars in
            QuickFilterChoice(
                id: "r\(stars)", label: "\(stars)★", activeLabel: "\(stars)★+",
                value: ["modifier": "GREATER_THAN", "value": stars * 20 - 1]
            )
        }
    )

    private static let sceneDuration = QuickFilterSection.choices(
        key: "duration", title: "Duration", anyLabel: "Any length",
        choices: [
            .init(id: "short", label: "Under 10 min", activeLabel: "< 10 min",
                  value: ["modifier": "LESS_THAN", "value": 600]),
            .init(id: "mid", label: "10–30 min", activeLabel: "10–30 min",
                  value: ["modifier": "BETWEEN", "value": 600, "value2": 1800]),
            .init(id: "long", label: "Over 30 min", activeLabel: "> 30 min",
                  value: ["modifier": "GREATER_THAN", "value": 1800]),
        ]
    )

    // `GREATER_THAN` a resolution class means "above that class", so 720p+ is "> 540p".
    private static let resolution = QuickFilterSection.choices(
        key: "resolution", title: "Quality", anyLabel: "Any quality",
        choices: [
            .init(id: "720", label: "720p+", activeLabel: "720p+",
                  value: ["modifier": "GREATER_THAN", "value": StashResolutionOption.webHD.rawValue]),
            .init(id: "1080", label: "1080p+", activeLabel: "1080p+",
                  value: ["modifier": "GREATER_THAN", "value": StashResolutionOption.standardHD.rawValue]),
            .init(id: "4k", label: "4K+", activeLabel: "4K+",
                  value: ["modifier": "GREATER_THAN", "value": StashResolutionOption.quadHD.rawValue]),
        ]
    )

    private static let organized = QuickFilterSection.choices(
        key: "organized", title: "Organized", anyLabel: "Any",
        choices: [
            .init(id: "yes", label: "Organized", activeLabel: "Organized", value: true),
            .init(id: "no", label: "Not organized", activeLabel: "Not organized", value: false),
        ]
    )

    private static let watched = QuickFilterSection.choices(
        key: "play_count", title: "Watched", anyLabel: "Any",
        choices: [
            .init(id: "unwatched", label: "Unwatched", activeLabel: "Unwatched",
                  value: ["modifier": "EQUALS", "value": 0]),
            .init(id: "watched", label: "Watched", activeLabel: "Watched",
                  value: ["modifier": "GREATER_THAN", "value": 0]),
        ]
    )

    private static let gender = QuickFilterSection.choices(
        key: "gender", title: "Gender", anyLabel: "Any",
        choices: [
            ("FEMALE", "Female"), ("MALE", "Male"), ("TRANSGENDER_FEMALE", "Trans female"),
            ("TRANSGENDER_MALE", "Trans male"), ("NON_BINARY", "Non-binary"),
        ].map { raw, label in
            QuickFilterChoice(id: raw, label: label, activeLabel: label,
                              value: ["modifier": "INCLUDES", "value_list": [raw]])
        }
    )

    private static let age = QuickFilterSection.choices(
        key: "age", title: "Age", anyLabel: "Any age",
        choices: [
            .init(id: "18", label: "18–25", activeLabel: "Age 18–25",
                  value: ["modifier": "BETWEEN", "value": 18, "value2": 25]),
            .init(id: "26", label: "26–35", activeLabel: "Age 26–35",
                  value: ["modifier": "BETWEEN", "value": 26, "value2": 35]),
            .init(id: "36", label: "36+", activeLabel: "Age 36+",
                  value: ["modifier": "GREATER_THAN", "value": 35]),
        ]
    )

    private static let hasScenes = QuickFilterSection.choices(
        key: "scene_count", title: "Scenes", anyLabel: "Any",
        choices: [
            .init(id: "has", label: "Has scenes", activeLabel: "Has scenes",
                  value: ["modifier": "GREATER_THAN", "value": 0]),
            .init(id: "none", label: "No scenes", activeLabel: "No scenes",
                  value: ["modifier": "EQUALS", "value": 0]),
        ]
    )

    private static func favorite(key: String) -> QuickFilterSection {
        .choices(
            key: key, title: "Favorite", anyLabel: "Any",
            choices: [
                .init(id: "yes", label: "Favorites", activeLabel: "Favorites", value: true),
                .init(id: "no", label: "Not favorite", activeLabel: "Not favorite", value: false),
            ]
        )
    }
}

// MARK: - List header: quick sort + active filters

/// Sits at the top of a catalog list and scrolls away with it — not pinned.
struct CatalogListQuickBar<Option: CatalogQuickSortable>: View {
    let mode: StashDBViewModel.FilterMode
    let sort: Option
    let onSort: (Option) -> Void
    @ObservedObject var document: FilterCriteriaDocument
    /// Name of the selected saved filter / preset, shown as a removable chip.
    var presetName: String? = nil
    var onClearPreset: (() -> Void)? = nil
    /// Called after a chip removed a criterion; the host refetches.
    var onFiltersChanged: () -> Void = {}
    var onOpenFilters: (() -> Void)? = nil

    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var pickerOptions = FilterPickerOptionsStore.shared

    private static var shadowRoom: CGFloat { 12 }

    private var sortFields: [CatalogQuickSortCatalog.Field] {
        let available = Set(Option.allCases.map(\.sortField))
        return CatalogQuickSortCatalog.fields(for: mode).filter { field in
            CatalogQuickSortCatalog.isRandom(field.field)
                ? available.contains { CatalogQuickSortCatalog.isRandom($0) }
                : available.contains(field.field)
        }
    }

    private var activeChips: [(key: String, label: String)] {
        let dict = document.sanitizedObjectFilter
        var keys = document.criterionKeys.filter { dict[$0] != nil }
        keys.append(contentsOf: dict.keys.filter { !keys.contains($0) }.sorted())
        return keys.map { ($0, chipLabel(key: $0, value: dict[$0] as Any)) }
    }

    var body: some View {
        // Same pills, sizes and spacing as the Tools section rows (`ToolsPillMenuRow`).
        VStack(alignment: .leading, spacing: DesignTokens.Tools.menuBottomPadding) {
            HStack(spacing: 0) {
                // Pinned: only the sort pills scroll, the settings button stays put.
                if let onOpenFilters {
                    settingsButton(action: onOpenFilters)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: StashyExpandingDock.itemSpacing) {
                        ForEach(sortFields, id: \.self) { field in
                            sortChip(field)
                        }
                    }
                    // The selected pill's glow (radius 6, y 3) must fit inside the clipped
                    // scroll area on every side, or it shows as a hard-edged box.
                    .padding(.vertical, Self.shadowRoom)
                    // A bit more air after the pinned settings button than between the pills.
                    .padding(.leading, onOpenFilters == nil ? 0 : 16)
                    .padding(.trailing, DesignTokens.Tools.contentPadding)
                }
                .padding(.vertical, -Self.shadowRoom)
            }
            .padding(.leading, DesignTokens.Tools.contentPadding)
            let chips = activeChips
            if !chips.isEmpty || presetName != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let presetName {
                            removableChip(icon: "bookmark.fill", text: presetName) {
                                onClearPreset?()
                            }
                        }
                        ForEach(chips, id: \.key) { chip in
                            removableChip(icon: nil, text: chip.label) {
                                HapticManager.light()
                                document.removeCriterion(key: chip.key)
                                onFiltersChanged()
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Tools.contentPadding)
                }
            }
        }
        .padding(.top, DesignTokens.Tools.menuTopPadding)
        .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
    }

    /// Replaces the chrome's former "Settings" slot; the dot marks an active filter.
    private func settingsButton(action: @escaping () -> Void) -> some View {
        let filtered = presetName != nil || !document.isEmpty
        return Button(action: action) {
            // Same glass circle as the chrome's nav buttons (`StashyExpandingDockChip`).
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: StashyExpandingDock.iconSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
                .frame(width: StashyExpandingDock.circleSize, height: StashyExpandingDock.circleSize)
                .stashyChromeFill(shape: Circle(), activeColor: nil)
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if filtered {
                        Circle()
                            .fill(appearance.tintColor)
                            .frame(width: 9, height: 9)
                            .offset(x: -1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter and sort settings")
    }

    private func sortChip(_ field: CatalogQuickSortCatalog.Field) -> some View {
        let isActive = CatalogQuickSortCatalog.isRandom(field.field)
            ? CatalogQuickSortCatalog.isRandom(sort.sortField)
            : sort.sortField == field.field
        let icon: String? = {
            guard isActive else { return nil }
            if CatalogQuickSortCatalog.isRandom(field.field) { return "shuffle" }
            return sort.direction == "ASC" ? "arrow.up" : "arrow.down"
        }()
        return Button {
            HapticManager.selection()
            if let next = CatalogQuickSortCatalog.next(after: sort, tapping: field.field) {
                onSort(next)
            }
        } label: {
            HStack(spacing: 4) {
                Text(field.label)
                    .lineLimit(1)
                if let icon {
                    Image(systemName: icon).font(.caption.weight(.bold))
                }
            }
            .font(.subheadline.weight(.semibold))
            // Chrome nav chip look: tinted glass when active, plain glass otherwise, no glow.
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(StashyExpandingDock.inactiveIconOpacity))
            .padding(.horizontal, StashyExpandingDock.activeHorizontalPadding)
            .frame(height: StashyExpandingDock.activeHeight)
            .stashyChromeFill(
                shape: Capsule(style: .continuous),
                activeColor: isActive ? appearance.tintColor : nil
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(field.label)")
    }

    private func removableChip(icon: String?, text: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(text).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundColor(appearance.tintColor)
            .background(appearance.tintColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(text)")
    }

    private func chipLabel(key: String, value: Any) -> String {
        if let quick = QuickFilterCatalog.activeLabel(key: key, value: value, mode: mode) {
            return quick
        }
        if FilterCriteriaDocument.isGroupKey(key) {
            return "\(key) group"
        }
        guard let field = FilterFieldCatalog.field(key: key, mode: mode) else {
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if field.kind == .hierarchicalMulti || field.kind == .multi,
           let dict = FilterCriteriaDocument.stringKeyedDict(value) {
            let names = pickerOptions.knownLabels()
            let included = FilterMapper.idStrings(from: dict["value"])
            let excluded = FilterMapper.idStrings(from: dict["excludes"])
            let prefix = key == "tags" ? "#" : ""
            if included.count + excluded.count <= 2 {
                let parts = included.compactMap { names[$0].map { prefix + $0 } }
                    + excluded.compactMap { names[$0].map { "−" + prefix + $0 } }
                if parts.count == included.count + excluded.count, !parts.isEmpty {
                    return parts.joined(separator: ", ")
                }
            }
        }
        return "\(field.label): \(FilterCriterionSummary.text(for: field, value: value))"
    }
}

// MARK: - Sheet body: quick filters + collapsible advanced editor

/// Replaces the bare criteria editor in every filter sheet: quick chips first, the full
/// Stash criteria editor one tap deeper.
struct CatalogFilterCriteriaBody: View {
    @ObservedObject var document: FilterCriteriaDocument
    var onChange: () -> Void

    @State private var showsAdvanced: Bool?

    private var sections: [QuickFilterSection] { QuickFilterCatalog.sections(for: document.mode) }

    /// Criteria the quick chips cannot show — a reason to open the advanced editor by default.
    private var advancedOnlyCount: Int {
        let dict = document.sanitizedObjectFilter
        return dict.filter { key, value in
            guard let section = sections.first(where: { $0.key == key }) else { return true }
            switch section {
            case .entities: return false
            case .choices: return QuickFilterCatalog.activeLabel(key: key, value: value, mode: document.mode) == nil
            }
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !sections.isEmpty {
                QuickFiltersCard(document: document, sections: sections, onChange: onChange)
            }
            // Header and editor read as one block, so they sit closer than the quick sections.
            VStack(alignment: .leading, spacing: 4) {
                advancedHeader
                if showsAdvanced ?? (advancedOnlyCount > 0) {
                    FilterCriteriaEditorView(document: document, onChange: onChange)
                }
            }
        }
        // Space after the sort card, and room below the last card instead of ending flush.
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    private var advancedHeader: some View {
        let expanded = showsAdvanced ?? (advancedOnlyCount > 0)
        return Button {
            withAnimation(DesignTokens.Animation.quick) { showsAdvanced = !expanded }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                Text("Advanced criteria")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                if advancedOnlyCount > 0 {
                    Text("\(advancedOnlyCount)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .catalogFilterSortControlCardChrome()
    }
}

struct QuickFiltersCard: View {
    @ObservedObject var document: FilterCriteriaDocument
    let sections: [QuickFilterSection]
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(sections) { section in
                switch section {
                case .choices(let key, let title, let anyLabel, let choices):
                    choiceSection(key: key, title: title, anyLabel: anyLabel, choices: choices)
                case .entities(let key, let title):
                    QuickEntityFilterSection(document: document, key: key, title: title, onChange: onChange)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func choiceSection(key: String, title: String, anyLabel: String, choices: [QuickFilterChoice]) -> some View {
        let current = QuickFilterCatalog.canonical(document.sanitizedObjectFilter[key])
        let selected = choices.first { QuickFilterCatalog.canonical($0.value) == current }
        return VStack(alignment: .leading, spacing: 10) {
            QuickFilterSectionTitle(title)
            FlowLayout(spacing: 8) {
                CatalogFilterChip(title: anyLabel, isActive: current == nil) {
                    guard current != nil else { return }
                    document.removeCriterion(key: key)
                    onChange()
                }
                ForEach(choices) { choice in
                    CatalogFilterChip(title: choice.label, isActive: selected?.id == choice.id) {
                        if selected?.id == choice.id {
                            document.removeCriterion(key: key)
                        } else {
                            document.setCriterion(key: key, value: choice.value)
                        }
                        onChange()
                    }
                }
            }
        }
    }
}

private struct QuickFilterSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
    }
}

/// Most-used tags as toggle chips plus a name search; writes the same `value` id list the
/// advanced editor's picker uses, keeping its modifier, depth and exclusions.
private struct QuickEntityFilterSection: View {
    @ObservedObject var document: FilterCriteriaDocument
    let key: String
    let title: String
    var onChange: () -> Void

    @ObservedObject private var store = FilterPickerOptionsStore.shared
    @State private var query = ""

    private static let visibleCount = 12

    private var kind: FilterPickerOptionsStore.Kind? {
        FilterPickerOptionsStore.kind(forCriterionKey: key, mode: document.mode)
    }

    private var currentDict: [String: Any] { document.dictValue(forKey: key) }
    private var selectedIds: [String] { FilterMapper.idStrings(from: currentDict["value"]) }

    private var modifier: String {
        (currentDict["modifier"] as? String) ?? StashCriterionModifier.includesAll.rawValue
    }

    private var visibleOptions: [FilterEntityOption] {
        guard let kind else { return [] }
        let all = store.availableOptions(kind)
        let term = query.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty {
            return Array(all.filter { $0.name.localizedCaseInsensitiveContains(term) }.prefix(30))
        }
        // Top list keeps its order so a tapped chip never moves under the finger; picked
        // long-tail entries (from a search) go in front.
        let top = Array(store.cached(kind).prefix(Self.visibleCount))
        let topIds = Set(top.map(\.id))
        let selected = Set(selectedIds)
        let pickedExtra = all.filter { selected.contains($0.id) && !topIds.contains($0.id) }
        return pickedExtra + top
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                QuickFilterSectionTitle(title)
                Spacer()
                if selectedIds.count > 1 {
                    Picker("Match", selection: Binding(
                        get: { modifier },
                        set: { newValue in
                            var dict = currentDict
                            dict["modifier"] = newValue
                            document.setCriterion(key: key, value: dict)
                            onChange()
                        }
                    )) {
                        Text("All").tag(StashCriterionModifier.includesAll.rawValue)
                        Text("Any").tag(StashCriterionModifier.includes.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search \(title.lowercased())", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            FlowLayout(spacing: 8) {
                ForEach(visibleOptions, id: \.id) { option in
                    CatalogFilterChip(
                        title: (key == "tags" ? "#" : "") + option.name,
                        isActive: selectedIds.contains(option.id)
                    ) {
                        toggle(option.id)
                    }
                }
            }
            if let kind, store.isLoading(kind) || store.isSearching(kind) {
                ProgressView().controlSize(.small)
            } else if visibleOptions.isEmpty {
                Text(query.isEmpty ? "Search to find \(title.lowercased())." : "No matches.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if let kind { store.load(kind) }
        }
        .onChange(of: query) { _, newValue in
            if let kind { store.search(kind, query: newValue) }
        }
    }

    private func toggle(_ id: String) {
        HapticManager.light()
        var ids = selectedIds
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        var dict = currentDict
        let excluded = FilterMapper.idStrings(from: dict["excludes"])
        if ids.isEmpty && excluded.isEmpty {
            document.removeCriterion(key: key)
        } else {
            dict["value"] = ids
            dict["modifier"] = modifier
            if FilterFieldCatalog.field(key: key, mode: document.mode)?.kind == .hierarchicalMulti, dict["depth"] == nil {
                dict["depth"] = 0
            }
            document.setCriterion(key: key, value: dict)
        }
        onChange()
    }
}
#endif
