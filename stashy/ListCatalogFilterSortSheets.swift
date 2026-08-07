//
//  ListCatalogFilterSortSheets.swift
//  stashy
//
//  Unified "Filter & Sort" sheets for Performers, Tags, and Studios catalog views.
//

#if !os(tvOS)
import SwiftUI

enum CatalogFilterSortSheetLayout {
    static let labelColumnWidth: CGFloat = 80
    /// Matches Asc/Desc chip row so Filter and Sort cards share the same height.
    static let controlCardMinHeight: CGFloat = 52
}

extension View {
    /// Shared chrome for Filter / Sort control cards in catalog sheets.
    func catalogFilterSortControlCardChrome() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: CatalogFilterSortSheetLayout.controlCardMinHeight, alignment: .center)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
    }
}

/// Label + trailing toggle — same typography/chrome as Filter / Sort rows.
struct CatalogFilterSortToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }
}

/// Playback toggles for Feeds Filter & Sort sheets (moved out of Settings → Feeds).
struct FeedsPlaybackSettingsCard: View {
    @ObservedObject private var tabManager = TabManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CatalogFilterSortToggleRow(label: "Immersive", isOn: $tabManager.reelsFillHeight)
            CatalogFilterSortToggleRow(label: "Continuous", isOn: $tabManager.reelsContinuousPlay)
        }
    }
}

/// 1/row Images feed: muted autoplay of the centered video after scroll settles.
struct ImagesFeedAutoplaySettingsCard: View {
    @AppStorage("images_feed_video_autoplay") private var videoAutoplay = true

    var body: some View {
        CatalogFilterSortToggleRow(label: "Autoplay", isOn: $videoAutoplay)
    }
}

// MARK: - Shared chips / rows

struct CatalogFilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? appearance.tintColor : Color.secondary.opacity(0.15))
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CatalogFilterRow<Chips: View>: View {
    let label: String
    @ViewBuilder var chips: () -> Chips

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chips()
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Single-select studio for live filters (scenes / images / galleries); `nil` = any.
struct CatalogStudioLiveFilterPickerRow: View {
    @Binding var selectedStudioId: String?
    let studios: [Studio]
    let isLoading: Bool
    var onAppearLoad: () -> Void
    /// Called when the user picks a different studio (or Any).
    var onSelectionChange: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Studio")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Picker("Studio", selection: Binding(
                    get: { selectedStudioId ?? "" },
                    set: { new in
                        let next = new.isEmpty ? nil : new
                        guard next != selectedStudioId else { return }
                        selectedStudioId = next
                        onSelectionChange()
                    }
                )) {
                    Text("Any").tag("")
                    ForEach(studios) { s in
                        Text(s.name).tag(s.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(appearance.tintColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { onAppearLoad() }
    }
}

/// Single-select tag / group / other named entity for scene live filters (`nil` = any).
struct CatalogNamedEntityLiveFilterPickerRow<Item: Identifiable & Equatable>: View where Item.ID == String {
    let title: String
    @Binding var selectedId: String?
    let items: [Item]
    let displayName: (Item) -> String
    let isLoading: Bool
    var onAppearLoad: () -> Void
    var onSelectionChange: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Picker(title, selection: Binding(
                    get: { selectedId ?? "" },
                    set: { new in
                        let next = new.isEmpty ? nil : new
                        guard next != selectedId else { return }
                        selectedId = next
                        onSelectionChange()
                    }
                )) {
                    Text("Any").tag("")
                    ForEach(items) { item in
                        Text(displayName(item)).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(appearance.tintColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { onAppearLoad() }
    }
}

/// Inline multi-select picker for live filters. It intentionally does not use `Picker(.menu)`,
/// because menus close after every tap; this stays open while the user toggles multiple rows.
struct CatalogNamedEntityLiveFilterMultiPickerRow<Item: Identifiable & Equatable>: View where Item.ID == String {
    let title: String
    @Binding var selectedIds: [String]
    let items: [Item]
    let displayName: (Item) -> String
    let isLoading: Bool
    var onAppearLoad: () -> Void
    var onSelectionChange: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var isExpanded = false

    private var selectedSummary: String {
        guard !selectedIds.isEmpty else { return "Any" }
        let selectedNames = items
            .filter { selectedIds.contains($0.id) }
            .map(displayName)
        if selectedNames.isEmpty { return "\(selectedIds.count) selected" }
        if selectedNames.count <= 2 { return selectedNames.joined(separator: ", ") }
        return "\(selectedNames[0]), \(selectedNames[1]) +\(selectedNames.count - 2)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(DesignTokens.Animation.quick) {
                    isExpanded.toggle()
                }
                onAppearLoad()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
                    Text(selectedSummary)
                        .font(.subheadline)
                        .foregroundColor(selectedIds.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(appearance.tintColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isExpanded {
                VStack(spacing: 0) {
                    Button {
                        guard !selectedIds.isEmpty else { return }
                        selectedIds = []
                        onSelectionChange()
                    } label: {
                        multiPickerOptionRow(title: "Any", isSelected: selectedIds.isEmpty)
                    }
                    .buttonStyle(.plain)

                    ForEach(items) { item in
                        Divider().padding(.leading, CatalogFilterSortSheetLayout.labelColumnWidth + 28)
                        Button {
                            toggle(item.id)
                        } label: {
                            multiPickerOptionRow(title: displayName(item), isSelected: selectedIds.contains(item.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { onAppearLoad() }
    }

    private func multiPickerOptionRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Spacer().frame(width: CatalogFilterSortSheetLayout.labelColumnWidth)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? appearance.tintColor : .secondary)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.removeAll { $0 == id }
        } else {
            selectedIds.append(id)
        }
        onSelectionChange()
    }
}

struct CatalogServerManagedFilterNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server filter")
                .font(.headline)
            Text("This saved filter uses criteria stashy cannot simplify here. Edit it in Stash, or pick a different filter or preset.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Performer sort (picker + asc/desc)

private enum PerformerCatalogSortFieldKind: String, CaseIterable, Identifiable {
    case name
    case scenes_count
    case images_count
    case galleries_count
    case birthdate
    case updated_at
    case created_at
    case o_counter
    case rating
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .name: return "Name"
        case .scenes_count: return "Scene count"
        case .images_count: return "Image count"
        case .galleries_count: return "Gallery count"
        case .birthdate: return "Birthday"
        case .updated_at: return "Updated"
        case .created_at: return "Created"
        case .o_counter: return "O Count"
        case .rating: return "Rating"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.PerformerSortOption) -> PerformerCatalogSortFieldKind {
        if option.sortField == "random" { return .random }
        return PerformerCatalogSortFieldKind(rawValue: option.sortField) ?? .scenes_count
    }

    func performerSortOption(ascending: Bool) -> StashDBViewModel.PerformerSortOption {
        switch self {
        case .name: return ascending ? .nameAsc : .nameDesc
        case .scenes_count: return ascending ? .sceneCountAsc : .sceneCountDesc
        case .images_count: return ascending ? .imageCountAsc : .imageCountDesc
        case .galleries_count: return ascending ? .galleryCountAsc : .galleryCountDesc
        case .birthdate: return ascending ? .birthdateAsc : .birthdateDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .o_counter: return ascending ? .oCountAsc : .oCountDesc
        case .rating: return ascending ? .ratingAsc : .ratingDesc
        case .random: return .random
        }
    }
}

private enum PerformerCatalogSortPickerValue: Hashable {
    case known(PerformerCatalogSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.PerformerSortOption) -> PerformerCatalogSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = PerformerCatalogSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: PerformerCatalogSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Tag sort

private enum TagCatalogSortFieldKind: String, CaseIterable, Identifiable {
    case name
    case scenes_count
    case updated_at
    case created_at
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .name: return "Name"
        case .scenes_count: return "Scene count"
        case .updated_at: return "Updated"
        case .created_at: return "Created"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.TagSortOption) -> TagCatalogSortFieldKind {
        if option.sortField == "random" { return .random }
        return TagCatalogSortFieldKind(rawValue: option.sortField) ?? .scenes_count
    }

    func tagSortOption(ascending: Bool) -> StashDBViewModel.TagSortOption {
        switch self {
        case .name: return ascending ? .nameAsc : .nameDesc
        case .scenes_count: return ascending ? .sceneCountAsc : .sceneCountDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .random: return .random
        }
    }
}

private enum TagCatalogSortPickerValue: Hashable {
    case known(TagCatalogSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.TagSortOption) -> TagCatalogSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = TagCatalogSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: TagCatalogSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Studio sort

private enum StudioCatalogSortFieldKind: String, CaseIterable, Identifiable {
    case name
    case scenes_count
    case updated_at
    case created_at
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .name: return "Name"
        case .scenes_count: return "Scene count"
        case .updated_at: return "Updated"
        case .created_at: return "Created"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.StudioSortOption) -> StudioCatalogSortFieldKind {
        if option.sortField == "random" { return .random }
        return StudioCatalogSortFieldKind(rawValue: option.sortField) ?? .name
    }

    func studioSortOption(ascending: Bool) -> StashDBViewModel.StudioSortOption {
        switch self {
        case .name: return ascending ? .nameAsc : .nameDesc
        case .scenes_count: return ascending ? .sceneCountAsc : .sceneCountDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .random: return .random
        }
    }
}

private enum StudioCatalogSortPickerValue: Hashable {
    case known(StudioCatalogSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.StudioSortOption) -> StudioCatalogSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = StudioCatalogSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: StudioCatalogSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Performers sheet

struct PerformersCatalogFilterSortSheet: View {
    var serverFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [PerformerListLiveFilterPreset]
    @Binding var selectedPresetRowId: String
    var liveChipRowsVisible: Bool
    var sortOption: StashDBViewModel.PerformerSortOption
    var onSortChange: (StashDBViewModel.PerformerSortOption) -> Void

    @Binding var liveAgeRange: String?
    @Binding var liveHairColor: String?
    @Binding var liveGender: String?
    @Binding var liveCountry: String?
    @Binding var liveImplants: Bool?
    @Binding var liveFavorite: Bool?
    @Binding var liveMissingField: String?
    @Binding var liveOCounterTag: String?

    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    private var hasSelectedPreset: Bool { !selectedPresetRowId.isEmpty }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPickerCard
                    performerSortCard
                    if liveChipRowsVisible {
                        performerLiveChipsCard
                    } else {
                        CatalogServerManagedFilterNotice()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onRequestSave() } label: {
                            Label("Save", systemImage: "arrow.down.doc")
                        }
                        .disabled(!hasSelectedPreset)
                        Button { onRequestSaveAs() } label: {
                            Label("Save As", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "arrow.down.doc").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Save")
                    Button(action: onRequestRename) {
                        Image(systemName: "pencil")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                    Button(role: .destructive, action: onRequestDelete) {
                        Image(systemName: "trash")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterPickerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Picker("Filter", selection: $selectedPresetRowId) {
                Text("None").tag("")
                if !serverFilters.isEmpty {
                    Section {
                        ForEach(serverFilters) { f in
                            Text(f.name).tag(ListLivePresetTag.serverRow(f.id))
                        }
                    }
                }
                if !localPresets.isEmpty {
                    Section {
                        ForEach(localPresets) { preset in
                            Text(preset.name).tag(ListLivePresetTag.localRow(preset.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Filter")
            .tint(appearance.tintColor)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var performerSortCard: some View {
        let pickerValue = PerformerCatalogSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let randomMode = pickerValue.isRandom
        let unmappedMode = pickerValue.isUnmapped
        let orderDisabled = randomMode || unmappedMode

        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Asc", isActive: ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.performerSortOption(ascending: true))
                }
                CatalogFilterChip(title: "Desc", isActive: !ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.performerSortOption(ascending: false))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .opacity(orderDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderDisabled)
            Spacer(minLength: 8)
            Picker("Sort type", selection: Binding(
                get: { PerformerCatalogSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if PerformerCatalogSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.performerSortOption(ascending: false))
                        } else {
                            onSortChange(newKind.performerSortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(PerformerCatalogSortPickerValue.unmapped(sortField: f))
                }
                ForEach(PerformerCatalogSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(PerformerCatalogSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var performerLiveChipsCard: some View {
        VStack(spacing: 0) {
            CatalogFilterRow(label: "Favorite") {
                CatalogFilterChip(title: "Any", isActive: liveFavorite == nil) { liveFavorite = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: liveFavorite == true) { liveFavorite = true; onApply() }
                CatalogFilterChip(title: "No", isActive: liveFavorite == false) { liveFavorite = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Missing") {
                CatalogFilterChip(title: "Any", isActive: liveMissingField == nil) { liveMissingField = nil; onApply() }
                CatalogFilterChip(title: "Image", isActive: liveMissingField == "image") { liveMissingField = "image"; onApply() }
                CatalogFilterChip(title: "Gender", isActive: liveMissingField == "gender") { liveMissingField = "gender"; onApply() }
                CatalogFilterChip(title: "Hair", isActive: liveMissingField == "hair_color") { liveMissingField = "hair_color"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Gender") {
                CatalogFilterChip(title: "Any", isActive: liveGender == nil) { liveGender = nil; onApply() }
                CatalogFilterChip(title: "Female", isActive: liveGender == "FEMALE") { liveGender = "FEMALE"; onApply() }
                CatalogFilterChip(title: "Male", isActive: liveGender == "MALE") { liveGender = "MALE"; onApply() }
                CatalogFilterChip(title: "Trans (M)", isActive: liveGender == "TRANSGENDER_MALE") { liveGender = "TRANSGENDER_MALE"; onApply() }
                CatalogFilterChip(title: "Trans (F)", isActive: liveGender == "TRANSGENDER_FEMALE") { liveGender = "TRANSGENDER_FEMALE"; onApply() }
                CatalogFilterChip(title: "Intersex", isActive: liveGender == "INTERSEX") { liveGender = "INTERSEX"; onApply() }
                CatalogFilterChip(title: "Non-binary", isActive: liveGender == "NON_BINARY") { liveGender = "NON_BINARY"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Age") {
                CatalogFilterChip(title: "Any", isActive: liveAgeRange == nil) { liveAgeRange = nil; onApply() }
                CatalogFilterChip(title: "18–21", isActive: liveAgeRange == "18-21") { liveAgeRange = "18-21"; onApply() }
                CatalogFilterChip(title: "22–26", isActive: liveAgeRange == "22-26") { liveAgeRange = "22-26"; onApply() }
                CatalogFilterChip(title: "26–30", isActive: liveAgeRange == "26-30") { liveAgeRange = "26-30"; onApply() }
                CatalogFilterChip(title: "30+", isActive: liveAgeRange == "30+") { liveAgeRange = "30+"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Hair") {
                CatalogFilterChip(title: "Any", isActive: liveHairColor == nil) { liveHairColor = nil; onApply() }
                CatalogFilterChip(title: "Blonde", isActive: liveHairColor == "BLONDE") { liveHairColor = "BLONDE"; onApply() }
                CatalogFilterChip(title: "Brunette", isActive: liveHairColor == "BRUNETTE") { liveHairColor = "BRUNETTE"; onApply() }
                CatalogFilterChip(title: "Red", isActive: liveHairColor == "RED") { liveHairColor = "RED"; onApply() }
                CatalogFilterChip(title: "Black", isActive: liveHairColor == "BLACK") { liveHairColor = "BLACK"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Country") {
                CatalogFilterChip(title: "Any", isActive: liveCountry == nil) { liveCountry = nil; onApply() }
                CatalogFilterChip(title: "US", isActive: liveCountry == "US") { liveCountry = "US"; onApply() }
                CatalogFilterChip(title: "Non-US", isActive: liveCountry == "NOT_US") { liveCountry = "NOT_US"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Tits") {
                CatalogFilterChip(title: "Any", isActive: liveImplants == nil) { liveImplants = nil; onApply() }
                CatalogFilterChip(title: "Fake", isActive: liveImplants == true) { liveImplants = true; onApply() }
                CatalogFilterChip(title: "Natural", isActive: liveImplants == false) { liveImplants = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "O Count") {
                CatalogFilterChip(title: "Any", isActive: liveOCounterTag == nil) { liveOCounterTag = nil; onApply() }
                CatalogFilterChip(title: "0", isActive: liveOCounterTag == SceneLiveOCounterChip.equalZero) {
                    liveOCounterTag = SceneLiveOCounterChip.equalZero; onApply()
                }
                CatalogFilterChip(title: "1+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan0) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan0; onApply()
                }
                CatalogFilterChip(title: "5+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan4) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan4; onApply()
                }
                CatalogFilterChip(title: "10+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan9) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan9; onApply()
                }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Tags sheet

struct TagsCatalogFilterSortSheet: View {
    var serverFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [TagListLiveFilterPreset]
    @Binding var selectedPresetRowId: String
    var liveChipRowsVisible: Bool
    var sortOption: StashDBViewModel.TagSortOption
    var onSortChange: (StashDBViewModel.TagSortOption) -> Void
    @Binding var liveFavorite: Bool?
    @Binding var liveHasScenes: Bool
    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    private var hasSelectedPreset: Bool { !selectedPresetRowId.isEmpty }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPickerCard
                    tagSortCard
                    if liveChipRowsVisible {
                        tagLiveChipsCard
                    } else {
                        CatalogServerManagedFilterNotice()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onRequestSave() } label: { Label("Save", systemImage: "arrow.down.doc") }
                            .disabled(!hasSelectedPreset)
                        Button { onRequestSaveAs() } label: { Label("Save As", systemImage: "doc.badge.plus") }
                    } label: {
                        Image(systemName: "arrow.down.doc").fontWeight(.semibold)
                    }
                    Button(action: onRequestRename) {
                        Image(systemName: "pencil")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                    Button(role: .destructive, action: onRequestDelete) {
                        Image(systemName: "trash")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterPickerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Picker("Filter", selection: $selectedPresetRowId) {
                Text("None").tag("")
                if !serverFilters.isEmpty {
                    Section {
                        ForEach(serverFilters) { f in
                            Text(f.name).tag(ListLivePresetTag.serverRow(f.id))
                        }
                    }
                }
                if !localPresets.isEmpty {
                    Section {
                        ForEach(localPresets) { preset in
                            Text(preset.name).tag(ListLivePresetTag.localRow(preset.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var tagSortCard: some View {
        let pickerValue = TagCatalogSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let orderDisabled = pickerValue.isRandom || pickerValue.isUnmapped
        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Asc", isActive: ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.tagSortOption(ascending: true))
                }
                CatalogFilterChip(title: "Desc", isActive: !ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.tagSortOption(ascending: false))
                }
            }
            .opacity(orderDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderDisabled)
            Spacer(minLength: 8)
            Picker("Sort type", selection: Binding(
                get: { TagCatalogSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if TagCatalogSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.tagSortOption(ascending: false))
                        } else {
                            onSortChange(newKind.tagSortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(TagCatalogSortPickerValue.unmapped(sortField: f))
                }
                ForEach(TagCatalogSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(TagCatalogSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var tagLiveChipsCard: some View {
        VStack(spacing: 0) {
            CatalogFilterRow(label: "Favorite") {
                CatalogFilterChip(title: "Any", isActive: liveFavorite == nil) { liveFavorite = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: liveFavorite == true) { liveFavorite = true; onApply() }
                CatalogFilterChip(title: "No", isActive: liveFavorite == false) { liveFavorite = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Scenes") {
                CatalogFilterChip(title: "Any", isActive: !liveHasScenes) { liveHasScenes = false; onApply() }
                CatalogFilterChip(title: "Has scenes", isActive: liveHasScenes) { liveHasScenes = true; onApply() }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Studios sheet

struct StudiosCatalogFilterSortSheet: View {
    var serverFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [StudioListLiveFilterPreset]
    @Binding var selectedPresetRowId: String
    var liveChipRowsVisible: Bool
    var sortOption: StashDBViewModel.StudioSortOption
    var onSortChange: (StashDBViewModel.StudioSortOption) -> Void
    @Binding var liveMinRating: Int
    @Binding var liveFavorite: Bool?
    @Binding var liveScenes: String?
    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    private var hasSelectedPreset: Bool { !selectedPresetRowId.isEmpty }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPickerCard
                    studioSortCard
                    if liveChipRowsVisible {
                        studioLiveChipsCard
                    } else {
                        CatalogServerManagedFilterNotice()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onRequestSave() } label: { Label("Save", systemImage: "arrow.down.doc") }
                            .disabled(!hasSelectedPreset)
                        Button { onRequestSaveAs() } label: { Label("Save As", systemImage: "doc.badge.plus") }
                    } label: {
                        Image(systemName: "arrow.down.doc").fontWeight(.semibold)
                    }
                    Button(action: onRequestRename) {
                        Image(systemName: "pencil")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                    Button(role: .destructive, action: onRequestDelete) {
                        Image(systemName: "trash")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterPickerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Picker("Filter", selection: $selectedPresetRowId) {
                Text("None").tag("")
                if !serverFilters.isEmpty {
                    Section {
                        ForEach(serverFilters) { f in
                            Text(f.name).tag(ListLivePresetTag.serverRow(f.id))
                        }
                    }
                }
                if !localPresets.isEmpty {
                    Section {
                        ForEach(localPresets) { preset in
                            Text(preset.name).tag(ListLivePresetTag.localRow(preset.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var studioSortCard: some View {
        let pickerValue = StudioCatalogSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let orderDisabled = pickerValue.isRandom || pickerValue.isUnmapped
        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Asc", isActive: ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.studioSortOption(ascending: true))
                }
                CatalogFilterChip(title: "Desc", isActive: !ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.studioSortOption(ascending: false))
                }
            }
            .opacity(orderDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderDisabled)
            Spacer(minLength: 8)
            Picker("Sort type", selection: Binding(
                get: { StudioCatalogSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if StudioCatalogSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.studioSortOption(ascending: false))
                        } else {
                            onSortChange(newKind.studioSortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(StudioCatalogSortPickerValue.unmapped(sortField: f))
                }
                ForEach(StudioCatalogSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(StudioCatalogSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var studioLiveChipsCard: some View {
        VStack(spacing: 0) {
            CatalogFilterRow(label: "Favorite") {
                CatalogFilterChip(title: "Any", isActive: liveFavorite == nil) { liveFavorite = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: liveFavorite == true) { liveFavorite = true; onApply() }
                CatalogFilterChip(title: "No", isActive: liveFavorite == false) { liveFavorite = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Rating") {
                CatalogFilterChip(title: "Any", isActive: liveMinRating == 0) { liveMinRating = 0; onApply() }
                CatalogFilterChip(title: "None", isActive: liveMinRating == -1) { liveMinRating = -1; onApply() }
                ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                    CatalogFilterChip(title: "\(star)★", isActive: liveMinRating == star) {
                        liveMinRating = star
                        onApply()
                    }
                }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Scenes") {
                CatalogFilterChip(title: "Any", isActive: liveScenes == nil) { liveScenes = nil; onApply() }
                CatalogFilterChip(title: "Has", isActive: liveScenes == "has") { liveScenes = "has"; onApply() }
                CatalogFilterChip(title: "None", isActive: liveScenes == "none") { liveScenes = "none"; onApply() }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Gallery sort

private enum GalleryCatalogSortFieldKind: String, CaseIterable, Identifiable {
    case title
    case date
    case rating
    case created_at
    case updated_at
    case images_count
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .title: return "Title"
        case .date: return "Date"
        case .rating: return "Rating"
        case .created_at: return "Created"
        case .updated_at: return "Updated"
        case .images_count: return "Image count"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.GallerySortOption) -> GalleryCatalogSortFieldKind {
        if option.sortField == "random" { return .random }
        return GalleryCatalogSortFieldKind(rawValue: option.sortField) ?? .date
    }

    func gallerySortOption(ascending: Bool) -> StashDBViewModel.GallerySortOption {
        switch self {
        case .title: return ascending ? .titleAsc : .titleDesc
        case .date: return ascending ? .dateAsc : .dateDesc
        case .rating: return ascending ? .ratingAsc : .ratingDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .images_count: return ascending ? .imageCountAsc : .imageCountDesc
        case .random: return .random
        }
    }
}

private enum GalleryCatalogSortPickerValue: Hashable {
    case known(GalleryCatalogSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.GallerySortOption) -> GalleryCatalogSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = GalleryCatalogSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: GalleryCatalogSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Galleries sheet

struct GalleriesCatalogFilterSortSheet: View {
    var serverFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [GalleryListLiveFilterPreset]
    @Binding var selectedPresetRowId: String
    var liveChipRowsVisible: Bool
    var sortOption: StashDBViewModel.GallerySortOption
    var onSortChange: (StashDBViewModel.GallerySortOption) -> Void
    @Binding var liveMinRating: Int
    @Binding var liveFavorite: Bool?
    @Binding var liveFiles: String?
    @Binding var liveStudioId: String?
    var studioPickerOptions: [Studio]
    var studioPickerLoading: Bool
    var onStudioPickerSectionAppear: () -> Void
    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    private var hasSelectedPreset: Bool { !selectedPresetRowId.isEmpty }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPickerCard
                    gallerySortCard
                    if liveChipRowsVisible {
                        galleryLiveChipsCard
                    } else {
                        CatalogServerManagedFilterNotice()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onRequestSave() } label: { Label("Save", systemImage: "arrow.down.doc") }
                            .disabled(!hasSelectedPreset)
                        Button { onRequestSaveAs() } label: { Label("Save As", systemImage: "doc.badge.plus") }
                    } label: {
                        Image(systemName: "arrow.down.doc").fontWeight(.semibold)
                    }
                    Button(action: onRequestRename) {
                        Image(systemName: "pencil")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                    Button(role: .destructive, action: onRequestDelete) {
                        Image(systemName: "trash")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterPickerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Picker("Filter", selection: $selectedPresetRowId) {
                Text("None").tag("")
                if !serverFilters.isEmpty {
                    Section {
                        ForEach(serverFilters) { f in
                            Text(f.name).tag(ListLivePresetTag.serverRow(f.id))
                        }
                    }
                }
                if !localPresets.isEmpty {
                    Section {
                        ForEach(localPresets) { preset in
                            Text(preset.name).tag(ListLivePresetTag.localRow(preset.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var gallerySortCard: some View {
        let pickerValue = GalleryCatalogSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let orderDisabled = pickerValue.isRandom || pickerValue.isUnmapped
        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Asc", isActive: ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.gallerySortOption(ascending: true))
                }
                CatalogFilterChip(title: "Desc", isActive: !ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.gallerySortOption(ascending: false))
                }
            }
            .opacity(orderDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderDisabled)
            Spacer(minLength: 8)
            Picker("Sort type", selection: Binding(
                get: { GalleryCatalogSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if GalleryCatalogSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.gallerySortOption(ascending: false))
                        } else {
                            onSortChange(newKind.gallerySortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(GalleryCatalogSortPickerValue.unmapped(sortField: f))
                }
                ForEach(GalleryCatalogSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(GalleryCatalogSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var galleryLiveChipsCard: some View {
        VStack(spacing: 0) {
            CatalogStudioLiveFilterPickerRow(
                selectedStudioId: $liveStudioId,
                studios: studioPickerOptions,
                isLoading: studioPickerLoading,
                onAppearLoad: onStudioPickerSectionAppear,
                onSelectionChange: onApply
            )
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Favorite") {
                CatalogFilterChip(title: "Any", isActive: liveFavorite == nil) { liveFavorite = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: liveFavorite == true) { liveFavorite = true; onApply() }
                CatalogFilterChip(title: "No", isActive: liveFavorite == false) { liveFavorite = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Rating") {
                CatalogFilterChip(title: "Any", isActive: liveMinRating == 0) { liveMinRating = 0; onApply() }
                CatalogFilterChip(title: "None", isActive: liveMinRating == -1) { liveMinRating = -1; onApply() }
                ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                    CatalogFilterChip(title: "\(star)★", isActive: liveMinRating == star) {
                        liveMinRating = star
                        onApply()
                    }
                }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Files") {
                CatalogFilterChip(title: "Any", isActive: liveFiles == nil) { liveFiles = nil; onApply() }
                CatalogFilterChip(title: "Has", isActive: liveFiles == "has") { liveFiles = "has"; onApply() }
                CatalogFilterChip(title: "None", isActive: liveFiles == "none") { liveFiles = "none"; onApply() }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Image sort

private enum ImageCatalogSortFieldKind: String, CaseIterable, Identifiable {
    case title
    case date
    case rating
    case created_at
    case updated_at
    case random

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .title: return "Title"
        case .date: return "Date"
        case .rating: return "Rating"
        case .created_at: return "Created"
        case .updated_at: return "Updated"
        case .random: return "Random"
        }
    }

    static func from(_ option: StashDBViewModel.ImageSortOption) -> ImageCatalogSortFieldKind {
        if option.sortField == "random" { return .random }
        return ImageCatalogSortFieldKind(rawValue: option.sortField) ?? .date
    }

    func imageSortOption(ascending: Bool) -> StashDBViewModel.ImageSortOption {
        switch self {
        case .title: return ascending ? .titleAsc : .titleDesc
        case .date: return ascending ? .dateAsc : .dateDesc
        case .rating: return ascending ? .ratingAsc : .ratingDesc
        case .created_at: return ascending ? .createdAtAsc : .createdAtDesc
        case .updated_at: return ascending ? .updatedAtAsc : .updatedAtDesc
        case .random: return .random
        }
    }
}

private enum ImageCatalogSortPickerValue: Hashable {
    case known(ImageCatalogSortFieldKind)
    case unmapped(sortField: String)

    static func from(_ option: StashDBViewModel.ImageSortOption) -> ImageCatalogSortPickerValue {
        if option.sortField == "random" { return .known(.random) }
        if let k = ImageCatalogSortFieldKind(rawValue: option.sortField) { return .known(k) }
        return .unmapped(sortField: option.sortField)
    }

    var isRandom: Bool {
        if case .known(.random) = self { return true }
        return false
    }

    var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }

    var knownKind: ImageCatalogSortFieldKind? {
        if case .known(let k) = self { return k }
        return nil
    }
}

// MARK: - Images sheet

struct ImagesCatalogFilterSortSheet: View {
    var serverFilters: [StashDBViewModel.SavedFilter]
    var localPresets: [ImageListLiveFilterPreset]
    @Binding var selectedPresetRowId: String
    var filterMenuTitleFallback: String? = nil
    var liveChipRowsVisible: Bool
    /// Hidden for Reels clips (`fetchClips` pins `path` and ignores live `path`).
    var showMediaTypeFilter: Bool = true
    var sortOption: StashDBViewModel.ImageSortOption
    var onSortChange: (StashDBViewModel.ImageSortOption) -> Void
    @Binding var liveMinRating: Int
    @Binding var livePerformerFavorite: Bool?
    @Binding var liveOrganized: String?
    @Binding var liveOCounterTag: String?
    @Binding var liveStudioIds: [String]
    @Binding var liveTagIds: [String]
    @Binding var liveMediaKind: ImageListMediaKind
    var studioPickerOptions: [Studio]
    var studioPickerLoading: Bool
    var onStudioPickerSectionAppear: () -> Void
    var tagPickerOptions: [Tag]
    var tagPickerLoading: Bool
    var onTagPickerSectionAppear: () -> Void
    var onApply: () -> Void
    var onReset: () -> Void
    var onRequestSave: () -> Void
    var onRequestSaveAs: () -> Void
    var onRequestRename: () -> Void
    var onRequestDelete: () -> Void
    /// When `true`, shows Immersive Scaling / Continuous Play (Feeds clips sheet).
    var showsFeedsPlaybackSettings: Bool = false
    /// When `true`, shows 1/row Images video autoplay toggle.
    var showsImagesFeedAutoplaySetting: Bool = false

    @ObservedObject private var appearance = AppearanceManager.shared
    private var hasSelectedPreset: Bool { !selectedPresetRowId.isEmpty }

    private var filterMenuCollapsedTitle: String {
        if selectedPresetRowId.isEmpty { return "None" }
        if let sid = ListLivePresetTag.parseServerId(selectedPresetRowId),
           let f = serverFilters.first(where: { $0.id == sid }) {
            return f.name
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(selectedPresetRowId),
           let uuid = UUID(uuidString: ls),
           let p = localPresets.first(where: { $0.id == uuid }) {
            return p.name
        }
        if let fb = filterMenuTitleFallback?.trimmingCharacters(in: .whitespacesAndNewlines), !fb.isEmpty {
            return fb
        }
        return "None"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterPickerCard
                    imageSortCard
                    if showMediaTypeFilter {
                        imageMediaTypeCard
                    }
                    if showsFeedsPlaybackSettings {
                        FeedsPlaybackSettingsCard()
                    }
                    if showsImagesFeedAutoplaySetting {
                        ImagesFeedAutoplaySettingsCard()
                    }
                    if liveChipRowsVisible {
                        imageLiveChipsCard
                    } else {
                        CatalogServerManagedFilterNotice()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onRequestSave() } label: { Label("Save", systemImage: "arrow.down.doc") }
                            .disabled(!hasSelectedPreset)
                        Button { onRequestSaveAs() } label: { Label("Save As", systemImage: "doc.badge.plus") }
                    } label: {
                        Image(systemName: "arrow.down.doc").fontWeight(.semibold)
                    }
                    Button(action: onRequestRename) {
                        Image(systemName: "pencil")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                    Button(role: .destructive, action: onRequestDelete) {
                        Image(systemName: "trash")
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasSelectedPreset)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filterPickerCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Filter")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            Menu {
                Button("None") {
                    selectedPresetRowId = ""
                }
                ForEach(serverFilters) { f in
                    Button(f.name) {
                        selectedPresetRowId = ListLivePresetTag.serverRow(f.id)
                    }
                }
                ForEach(localPresets) { preset in
                    Button(preset.name) {
                        selectedPresetRowId = ListLivePresetTag.localRow(preset.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text(filterMenuCollapsedTitle)
                        .font(.body)
                        .foregroundColor(appearance.tintColor)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(appearance.tintColor)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .catalogFilterSortControlCardChrome()
    }

    private var imageSortCard: some View {
        let pickerValue = ImageCatalogSortPickerValue.from(sortOption)
        let ascending = sortOption.direction == "ASC"
        let orderDisabled = pickerValue.isRandom || pickerValue.isUnmapped
        return HStack(alignment: .center, spacing: 12) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Asc", isActive: ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.imageSortOption(ascending: true))
                }
                CatalogFilterChip(title: "Desc", isActive: !ascending && !orderDisabled) {
                    guard let k = pickerValue.knownKind, !orderDisabled else { return }
                    onSortChange(k.imageSortOption(ascending: false))
                }
            }
            .opacity(orderDisabled ? 0.4 : 1)
            .allowsHitTesting(!orderDisabled)
            Spacer(minLength: 8)
            Picker("Sort type", selection: Binding(
                get: { ImageCatalogSortPickerValue.from(sortOption) },
                set: { newVal in
                    switch newVal {
                    case .known(let newKind):
                        if newKind == .random {
                            onSortChange(.random)
                        } else if ImageCatalogSortPickerValue.from(sortOption).isRandom {
                            onSortChange(newKind.imageSortOption(ascending: false))
                        } else {
                            onSortChange(newKind.imageSortOption(ascending: sortOption.direction == "ASC"))
                        }
                    case .unmapped:
                        break
                    }
                }
            )) {
                if case .unmapped(let f) = pickerValue {
                    Text("Other (\(f))").tag(ImageCatalogSortPickerValue.unmapped(sortField: f))
                }
                ForEach(ImageCatalogSortFieldKind.allCases) { k in
                    Text(k.menuLabel).tag(ImageCatalogSortPickerValue.known(k))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(appearance.tintColor)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var imageMediaTypeCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Type")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: CatalogFilterSortSheetLayout.labelColumnWidth, alignment: .leading)
            HStack(spacing: 6) {
                CatalogFilterChip(title: "Any", isActive: liveMediaKind == .all) { liveMediaKind = .all; onApply() }
                CatalogFilterChip(title: "Image", isActive: liveMediaKind == .stillImage) { liveMediaKind = .stillImage; onApply() }
                CatalogFilterChip(title: "Video", isActive: liveMediaKind == .video) { liveMediaKind = .video; onApply() }
            }
            Spacer(minLength: 0)
        }
        .catalogFilterSortControlCardChrome()
    }

    private var imageLiveChipsCard: some View {
        VStack(spacing: 0) {
            CatalogNamedEntityLiveFilterMultiPickerRow(
                title: "Studio",
                selectedIds: $liveStudioIds,
                items: studioPickerOptions,
                displayName: { $0.name },
                isLoading: studioPickerLoading,
                onAppearLoad: onStudioPickerSectionAppear,
                onSelectionChange: onApply
            )
            Divider().padding(.leading, 16)
            CatalogNamedEntityLiveFilterMultiPickerRow(
                title: "Tag",
                selectedIds: $liveTagIds,
                items: tagPickerOptions,
                displayName: { $0.name },
                isLoading: tagPickerLoading,
                onAppearLoad: onTagPickerSectionAppear,
                onSelectionChange: onApply
            )
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Perf. fav.") {
                CatalogFilterChip(title: "Any", isActive: livePerformerFavorite == nil) { livePerformerFavorite = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: livePerformerFavorite == true) { livePerformerFavorite = true; onApply() }
                CatalogFilterChip(title: "No", isActive: livePerformerFavorite == false) { livePerformerFavorite = false; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Rating") {
                CatalogFilterChip(title: "Any", isActive: liveMinRating == 0) { liveMinRating = 0; onApply() }
                CatalogFilterChip(title: "None", isActive: liveMinRating == -1) { liveMinRating = -1; onApply() }
                ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                    CatalogFilterChip(title: "\(star)★", isActive: liveMinRating == star) {
                        liveMinRating = star
                        onApply()
                    }
                }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "Organized") {
                CatalogFilterChip(title: "Any", isActive: liveOrganized == nil) { liveOrganized = nil; onApply() }
                CatalogFilterChip(title: "Yes", isActive: liveOrganized == "true") { liveOrganized = "true"; onApply() }
                CatalogFilterChip(title: "No", isActive: liveOrganized == "false") { liveOrganized = "false"; onApply() }
            }
            Divider().padding(.leading, 16)
            CatalogFilterRow(label: "O Count") {
                CatalogFilterChip(title: "Any", isActive: liveOCounterTag == nil) { liveOCounterTag = nil; onApply() }
                CatalogFilterChip(title: "0", isActive: liveOCounterTag == SceneLiveOCounterChip.equalZero) {
                    liveOCounterTag = SceneLiveOCounterChip.equalZero; onApply()
                }
                CatalogFilterChip(title: "1+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan0) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan0; onApply()
                }
                CatalogFilterChip(title: "5+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan4) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan4; onApply()
                }
                CatalogFilterChip(title: "10+", isActive: liveOCounterTag == SceneLiveOCounterChip.greaterThan9) {
                    liveOCounterTag = SceneLiveOCounterChip.greaterThan9; onApply()
                }
            }
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Scene live chips (shared by Reels + catalog-style callers)

/// Holds the same chip-backed scene criteria as ``ScenesView``’s live filter sheet (subset of `SceneFilterType`).
struct SceneLiveChipRowState: Equatable {
    var minRating: Int = 0
    var organized: Bool? = nil
    var interactive: Bool? = nil
    var orientation: String? = nil
    var performerCount: Int? = nil
    var resolution: String? = nil
    var performerFavorite: Bool? = nil
    var oCounterTag: String? = nil
    /// Studio ids for `studios` `INCLUDES`; empty = any.
    var studioIds: [String] = []
    /// Tag ids for `tags` `INCLUDES`; empty = any.
    var tagIds: [String] = []
    /// Group ids for `groups` `INCLUDES`; empty = any.
    var groupIds: [String] = []

    var isLiveFilterActive: Bool {
        minRating != 0 || organized != nil || interactive != nil || orientation != nil
            || performerCount != nil || resolution != nil || performerFavorite != nil || oCounterTag != nil
            || !studioIds.isEmpty || !tagIds.isEmpty || !groupIds.isEmpty
    }

    func activeLiveFilterDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if minRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if minRating > 0 {
            dict["rating100"] = ["value": (minRating * 20), "modifier": "EQUALS"]
        }
        if let org = organized { dict["organized"] = org }
        if let interactive { dict["interactive"] = interactive }
        if let orientation {
            dict["orientation"] = ["value": [orientation]]
        }
        if let count = performerCount {
            if count == 3 {
                dict["performer_count"] = ["value": 2, "modifier": "GREATER_THAN"]
            } else {
                dict["performer_count"] = ["value": count, "modifier": "EQUALS"]
            }
        }
        if let resolution {
            dict["resolution"] = ["value": resolution, "modifier": "EQUALS"]
        }
        if let fav = performerFavorite { dict["performer_favorite"] = fav }
        if let tag = oCounterTag, let oc = sceneLiveOCounterCriterion(from: tag) {
            dict["o_counter"] = oc
        }
        if !studioIds.isEmpty {
            dict["studios"] = ["modifier": "INCLUDES", "value": studioIds]
        }
        if !tagIds.isEmpty {
            dict["tags"] = ["modifier": "INCLUDES", "value": tagIds]
        }
        if !groupIds.isEmpty {
            dict["groups"] = ["modifier": "INCLUDES", "value": groupIds]
        }
        return dict
    }

    func effectiveLiveFilter(for selectedFilter: StashDBViewModel.SavedFilter?) -> [String: Any] {
        var dict: [String: Any] = SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(selectedFilter)
            ? activeLiveFilterDict()
            : [:]
        if !studioIds.isEmpty {
            dict["studios"] = ["modifier": "INCLUDES", "value": studioIds]
        }
        if !tagIds.isEmpty {
            dict["tags"] = ["modifier": "INCLUDES", "value": tagIds]
        }
        if !groupIds.isEmpty {
            dict["groups"] = ["modifier": "INCLUDES", "value": groupIds]
        }
        if minRating == -1 {
            dict["rating100"] = ["modifier": "IS_NULL"]
        } else if minRating > 0, dict["rating100"] == nil {
            dict["rating100"] = ["value": (minRating * 20), "modifier": "EQUALS"]
        }
        return dict
    }

    mutating func clearChipsOnly() {
        minRating = 0
        organized = nil
        interactive = nil
        orientation = nil
        performerCount = nil
        resolution = nil
        performerFavorite = nil
        oCounterTag = nil
        studioIds = []
        tagIds = []
        groupIds = []
    }

    mutating func mapLiveFragmentToChips(_ frag: [String: Any]) {
        let frag = FilterMapper.sanitize(frag, isMarker: false)
        if let rating = frag["rating100"] as? [String: Any] {
            let mod = (rating["modifier"] as? String) ?? ""
            if mod == "IS_NULL" {
                minRating = -1
            } else if let raw = rating["value"], let v = Self.intFromLiveJSON(raw) {
                minRating = max(0, min(5, v / 20))
            } else {
                minRating = 0
            }
        } else {
            minRating = 0
        }
        organized = Self.boolFromLiveJSON(frag["organized"])
        interactive = Self.boolFromLiveJSON(frag["interactive"])
        if let orient = frag["orientation"] as? [String: Any], let vals = orient["value"] as? [String], let first = vals.first {
            orientation = first
        } else if let orient = frag["orientation"] as? [String: Any], let vals = orient["value"] as? [Any] {
            orientation = vals.compactMap { $0 as? String }.first
        } else {
            orientation = nil
        }
        if let pc = frag["performer_count"] as? [String: Any], let raw = pc["value"], let v = Self.intFromLiveJSON(raw) {
            let mod = (pc["modifier"] as? String) ?? "EQUALS"
            if mod == "GREATER_THAN", v == 2 {
                performerCount = 3
            } else {
                performerCount = v
            }
        } else {
            performerCount = nil
        }
        if let res = frag["resolution"] as? [String: Any], let s = res["value"] as? String {
            resolution = s
        } else {
            resolution = nil
        }
        performerFavorite = Self.boolFromLiveJSON(frag["performer_favorite"])
        if let oc = frag["o_counter"] as? [String: Any],
           let mod = oc["modifier"] as? String,
           let raw = oc["value"],
           let v = Self.intFromLiveJSON(raw) {
            oCounterTag = "\(mod):\(v)"
        } else {
            oCounterTag = nil
        }
        studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: frag["studios"])
        tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: frag["tags"])
        groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: frag["groups"])
    }

    mutating func syncLiveChipsToMatchSelectedFilter(_ selectedFilter: StashDBViewModel.SavedFilter?, savedFilters: [String: StashDBViewModel.SavedFilter]) {
        guard let f = selectedFilter else {
            clearChipsOnly()
            return
        }
        if let meta = f.stashyScenePresetMetadata {
            let base: StashDBViewModel.SavedFilter?
            if let bid = meta.baseSavedFilterId, let b = savedFilters[bid] {
                base = b
            } else {
                base = nil
            }
            if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(base) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearChipsOnly()
                studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["studios"])
                tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["tags"])
                groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: meta.liveFragment["groups"])
            }
        } else if SceneLiveChipFilterSupport.savedFilterSupportsLiveChipEditor(f) {
            if let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearChipsOnly()
            }
        } else {
            clearChipsOnly()
            let flat: [String: Any]? = {
                if let raw = f.filterDict { return FilterMapper.sanitize(raw, isMarker: false) }
                if let obj = f.object_filter, let objDict = obj.value as? [String: Any] {
                    return FilterMapper.sanitize(objDict, isMarker: false)
                }
                return nil
            }()
            if let flat {
                studioIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: flat["studios"])
                tagIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: flat["tags"])
                groupIds = SceneLiveChipFilterSupport.includesIds(fromCriterion: flat["groups"])
            }
        }
    }

    private static func boolFromLiveJSON(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let d = value as? [String: Any], let inner = d["value"] { return boolFromLiveJSON(inner) }
        if let s = value as? String {
            let lower = s.lowercased()
            if ["true", "1", "yes"].contains(lower) { return true }
            if ["false", "0", "no"].contains(lower) { return false }
        }
        return nil
    }

    private static func intFromLiveJSON(_ value: Any) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}

#endif
