import Foundation

struct FilterFieldDescriptor: Identifiable, Hashable {
    let key: String
    let label: String
    let kind: FilterCriterionKind
    var nestedMode: StashDBViewModel.FilterMode? = nil
    var isDeprecated: Bool = false

    var id: String { key }
}

enum FilterFieldCatalog {
    static func fields(for mode: StashDBViewModel.FilterMode) -> [FilterFieldDescriptor] {
        switch mode {
        case .scenes: return sceneFields
        case .performers: return performerFields
        case .studios: return studioFields
        case .galleries: return galleryFields
        case .images: return imageFields
        case .tags: return tagFields
        case .groups: return groupFields
        case .sceneMarkers: return markerFields
        case .unknown: return []
        }
    }

    static func field(key: String, mode: StashDBViewModel.FilterMode) -> FilterFieldDescriptor? {
        fields(for: mode).first { $0.key == key }
    }

    /// Fields the user can still add. Boolean groups are excluded: AND/OR/NOT are structure, not
    /// fields, and listing them next to "Rating" was the main source of confusion. The editor
    /// offers them through its own "Add group" control instead.
    static func addableFields(for mode: StashDBViewModel.FilterMode, excludingKeys: Set<String>) -> [FilterFieldDescriptor] {
        fields(for: mode).filter { field in
            if field.isDeprecated { return false }
            if field.kind == .booleanGroup { return false }
            return !excludingKeys.contains(field.key)
        }
    }

    // MARK: - Shared helpers

    private static func boolOps() -> [FilterFieldDescriptor] {
        [
            .init(key: "AND", label: "AND", kind: .booleanGroup),
            .init(key: "OR", label: "OR", kind: .booleanGroup),
            .init(key: "NOT", label: "NOT", kind: .booleanGroup)
        ]
    }

    // MARK: - Scenes

    private static let sceneFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "title", label: "Title", kind: .string),
        .init(key: "code", label: "Code", kind: .string),
        .init(key: "details", label: "Details", kind: .string),
        .init(key: "director", label: "Director", kind: .string),
        .init(key: "oshash", label: "OSHash", kind: .string),
        .init(key: "checksum", label: "Checksum", kind: .string),
        .init(key: "phash_distance", label: "PHash distance", kind: .phashDistance),
        .init(key: "path", label: "Path", kind: .string),
        .init(key: "file_count", label: "File count", kind: .int),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "organized", label: "Organized", kind: .boolean),
        .init(key: "o_counter", label: "O-Count", kind: .int),
        .init(key: "duplicated", label: "Duplicated", kind: .duplication),
        .init(key: "resolution", label: "Resolution", kind: .resolution),
        .init(key: "orientation", label: "Orientation", kind: .orientation),
        .init(key: "framerate", label: "Framerate", kind: .int),
        .init(key: "bitrate", label: "Bitrate", kind: .int),
        .init(key: "video_codec", label: "Video codec", kind: .string),
        .init(key: "audio_codec", label: "Audio codec", kind: .string),
        .init(key: "duration", label: "Duration (s)", kind: .int),
        .init(key: "has_markers", label: "Has markers", kind: .hasMarkers),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "studios", label: "Studios", kind: .hierarchicalMulti),
        .init(key: "groups", label: "Groups", kind: .hierarchicalMulti),
        .init(key: "galleries", label: "Galleries", kind: .multi),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "performer_tags", label: "Performer tags", kind: .hierarchicalMulti),
        .init(key: "performer_favorite", label: "Performer favorite", kind: .boolean),
        .init(key: "performer_age", label: "Performer age", kind: .int),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "performer_count", label: "Performer count", kind: .int),
        .init(key: "stash_ids_endpoint", label: "Stash IDs", kind: .stashIDs),
        .init(key: "stash_id_count", label: "Stash ID count", kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "interactive", label: "Interactive", kind: .boolean),
        .init(key: "interactive_speed", label: "Interactive speed", kind: .int),
        .init(key: "captions", label: "Captions", kind: .string),
        .init(key: "resume_time", label: "Resume time", kind: .int),
        .init(key: "play_count", label: "Play count", kind: .int),
        .init(key: "play_duration", label: "Play duration", kind: .int),
        .init(key: "last_played_at", label: "Last played", kind: .timestamp),
        .init(key: "date", label: "Date", kind: .date),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "galleries_filter", label: "Galleries filter", kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "performers_filter", label: "Performers filter", kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: "Studios filter", kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: "Tags filter", kind: .nestedFilter, nestedMode: .tags),
        .init(key: "groups_filter", label: "Groups filter", kind: .nestedFilter, nestedMode: .groups),
        .init(key: "markers_filter", label: "Markers filter", kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "files_filter", label: "Files filter", kind: .raw),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields),
        .init(key: "movies", label: "Movies", kind: .multi, isDeprecated: true),
        .init(key: "phash", label: "PHash", kind: .string, isDeprecated: true),
        .init(key: "stash_id_endpoint", label: "Stash ID (legacy)", kind: .stashID, isDeprecated: true),
        .init(key: "movies_filter", label: "Movies filter", kind: .nestedFilter, nestedMode: .groups, isDeprecated: true)
    ]

    // MARK: - Performers

    private static let performerFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "name", label: "Name", kind: .string),
        .init(key: "disambiguation", label: "Disambiguation", kind: .string),
        .init(key: "details", label: "Details", kind: .string),
        .init(key: "filter_favorites", label: "Favorite", kind: .boolean),
        .init(key: "birth_year", label: "Birth year", kind: .int),
        .init(key: "age", label: "Age", kind: .int),
        .init(key: "ethnicity", label: "Ethnicity", kind: .string),
        .init(key: "country", label: "Country", kind: .string),
        .init(key: "eye_color", label: "Eye color", kind: .string),
        .init(key: "height_cm", label: "Height (cm)", kind: .int),
        .init(key: "measurements", label: "Measurements", kind: .string),
        .init(key: "fake_tits", label: "Implants", kind: .string),
        .init(key: "penis_length", label: "Penis length", kind: .float),
        .init(key: "circumcised", label: "Circumcised", kind: .circumcision),
        .init(key: "career_start", label: "Career start", kind: .date),
        .init(key: "career_end", label: "Career end", kind: .date),
        .init(key: "tattoos", label: "Tattoos", kind: .string),
        .init(key: "piercings", label: "Piercings", kind: .string),
        .init(key: "aliases", label: "Aliases", kind: .string),
        .init(key: "gender", label: "Gender", kind: .gender),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "scene_count", label: "Scene count", kind: .int),
        .init(key: "marker_count", label: "Marker count", kind: .int),
        .init(key: "image_count", label: "Image count", kind: .int),
        .init(key: "gallery_count", label: "Gallery count", kind: .int),
        .init(key: "play_count", label: "Play count", kind: .int),
        .init(key: "o_counter", label: "O-Count", kind: .int),
        .init(key: "stash_ids_endpoint", label: "Stash IDs", kind: .stashIDs),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "hair_color", label: "Hair color", kind: .string),
        .init(key: "weight", label: "Weight", kind: .int),
        .init(key: "death_year", label: "Death year", kind: .int),
        .init(key: "studios", label: "Studios", kind: .hierarchicalMulti),
        .init(key: "groups", label: "Groups", kind: .hierarchicalMulti),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "ignore_auto_tag", label: "Ignore auto-tag", kind: .boolean),
        .init(key: "birthdate", label: "Birthdate", kind: .date),
        .init(key: "death_date", label: "Death date", kind: .date),
        .init(key: "scenes_filter", label: "Scenes filter", kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: "Images filter", kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: "Galleries filter", kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "tags_filter", label: "Tags filter", kind: .nestedFilter, nestedMode: .tags),
        .init(key: "markers_filter", label: "Markers filter", kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields),
        .init(key: "stash_id_endpoint", label: "Stash ID (legacy)", kind: .stashID, isDeprecated: true)
    ]

    // MARK: - Studios

    private static let studioFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "name", label: "Name", kind: .string),
        .init(key: "details", label: "Details", kind: .string),
        .init(key: "parents", label: "Parents", kind: .multi),
        .init(key: "stash_ids_endpoint", label: "Stash IDs", kind: .stashIDs),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "favorite", label: "Favorite", kind: .boolean),
        .init(key: "scene_count", label: "Scene count", kind: .int),
        .init(key: "image_count", label: "Image count", kind: .int),
        .init(key: "gallery_count", label: "Gallery count", kind: .int),
        .init(key: "group_count", label: "Group count", kind: .int),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "aliases", label: "Aliases", kind: .string),
        .init(key: "child_count", label: "Child count", kind: .int),
        .init(key: "ignore_auto_tag", label: "Ignore auto-tag", kind: .boolean),
        .init(key: "organized", label: "Organized", kind: .boolean),
        .init(key: "scenes_filter", label: "Scenes filter", kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: "Images filter", kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: "Galleries filter", kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "groups_filter", label: "Groups filter", kind: .nestedFilter, nestedMode: .groups),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields)
    ]

    // MARK: - Galleries

    private static let galleryFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "title", label: "Title", kind: .string),
        .init(key: "details", label: "Details", kind: .string),
        .init(key: "checksum", label: "Checksum", kind: .string),
        .init(key: "path", label: "Path", kind: .string),
        .init(key: "file_count", label: "File count", kind: .int),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "is_zip", label: "Is zip", kind: .boolean),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "organized", label: "Organized", kind: .boolean),
        .init(key: "average_resolution", label: "Avg resolution", kind: .resolution),
        .init(key: "has_chapters", label: "Has chapters", kind: .hasChapters),
        .init(key: "scenes", label: "Scenes", kind: .multi),
        .init(key: "studios", label: "Studios", kind: .hierarchicalMulti),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "performer_tags", label: "Performer tags", kind: .hierarchicalMulti),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "performer_count", label: "Performer count", kind: .int),
        .init(key: "performer_favorite", label: "Performer favorite", kind: .boolean),
        .init(key: "performer_age", label: "Performer age", kind: .int),
        .init(key: "image_count", label: "Image count", kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "date", label: "Date", kind: .date),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "code", label: "Code", kind: .string),
        .init(key: "photographer", label: "Photographer", kind: .string),
        .init(key: "scenes_filter", label: "Scenes filter", kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: "Images filter", kind: .nestedFilter, nestedMode: .images),
        .init(key: "performers_filter", label: "Performers filter", kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: "Studios filter", kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: "Tags filter", kind: .nestedFilter, nestedMode: .tags),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields)
    ]

    // MARK: - Images

    private static let imageFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "title", label: "Title", kind: .string),
        .init(key: "details", label: "Details", kind: .string),
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "checksum", label: "Checksum", kind: .string),
        .init(key: "phash_distance", label: "PHash distance", kind: .phashDistance),
        .init(key: "path", label: "Path", kind: .string),
        .init(key: "file_count", label: "File count", kind: .int),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "date", label: "Date", kind: .date),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "organized", label: "Organized", kind: .boolean),
        .init(key: "o_counter", label: "O-Count", kind: .int),
        .init(key: "resolution", label: "Resolution", kind: .resolution),
        .init(key: "orientation", label: "Orientation", kind: .orientation),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "studios", label: "Studios", kind: .hierarchicalMulti),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "performer_tags", label: "Performer tags", kind: .hierarchicalMulti),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "performer_count", label: "Performer count", kind: .int),
        .init(key: "performer_favorite", label: "Performer favorite", kind: .boolean),
        .init(key: "performer_age", label: "Performer age", kind: .int),
        .init(key: "galleries", label: "Galleries", kind: .multi),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "code", label: "Code", kind: .string),
        .init(key: "photographer", label: "Photographer", kind: .string),
        .init(key: "galleries_filter", label: "Galleries filter", kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "performers_filter", label: "Performers filter", kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: "Studios filter", kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: "Tags filter", kind: .nestedFilter, nestedMode: .tags),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields)
    ]

    // MARK: - Tags

    private static let tagFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "name", label: "Name", kind: .string),
        .init(key: "sort_name", label: "Sort name", kind: .string),
        .init(key: "aliases", label: "Aliases", kind: .string),
        .init(key: "favorite", label: "Favorite", kind: .boolean),
        .init(key: "description", label: "Description", kind: .string),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "scene_count", label: "Scene count", kind: .hierarchicalCount),
        .init(key: "image_count", label: "Image count", kind: .hierarchicalCount),
        .init(key: "gallery_count", label: "Gallery count", kind: .hierarchicalCount),
        .init(key: "performer_count", label: "Performer count", kind: .hierarchicalCount),
        .init(key: "studio_count", label: "Studio count", kind: .hierarchicalCount),
        .init(key: "group_count", label: "Group count", kind: .hierarchicalCount),
        .init(key: "marker_count", label: "Marker count", kind: .hierarchicalCount),
        .init(key: "parents", label: "Parents", kind: .hierarchicalMulti),
        .init(key: "children", label: "Children", kind: .hierarchicalMulti),
        .init(key: "parent_count", label: "Parent count", kind: .int),
        .init(key: "child_count", label: "Child count", kind: .int),
        .init(key: "ignore_auto_tag", label: "Ignore auto-tag", kind: .boolean),
        .init(key: "stash_ids_endpoint", label: "Stash IDs", kind: .stashIDs),
        .init(key: "scenes_filter", label: "Scenes filter", kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: "Images filter", kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: "Galleries filter", kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "groups_filter", label: "Groups filter", kind: .nestedFilter, nestedMode: .groups),
        .init(key: "performers_filter", label: "Performers filter", kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: "Studios filter", kind: .nestedFilter, nestedMode: .studios),
        .init(key: "markers_filter", label: "Markers filter", kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields)
    ]

    // MARK: - Groups

    private static let groupFields: [FilterFieldDescriptor] = boolOps() + [
        .init(key: "name", label: "Name", kind: .string),
        .init(key: "director", label: "Director", kind: .string),
        .init(key: "synopsis", label: "Synopsis", kind: .string),
        .init(key: "duration", label: "Duration (s)", kind: .int),
        .init(key: "rating100", label: "Rating", kind: .int),
        .init(key: "studios", label: "Studios", kind: .hierarchicalMulti),
        .init(key: "is_missing", label: "Is missing", kind: .isMissing),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "tag_count", label: "Tag count", kind: .int),
        .init(key: "date", label: "Date", kind: .date),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "o_counter", label: "O-Count", kind: .int),
        .init(key: "containing_groups", label: "Containing groups", kind: .hierarchicalMulti),
        .init(key: "sub_groups", label: "Sub groups", kind: .hierarchicalMulti),
        .init(key: "containing_group_count", label: "Containing group count", kind: .int),
        .init(key: "sub_group_count", label: "Sub group count", kind: .int),
        .init(key: "scene_count", label: "Scene count", kind: .int),
        .init(key: "scenes_filter", label: "Scenes filter", kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "studios_filter", label: "Studios filter", kind: .nestedFilter, nestedMode: .studios),
        .init(key: "custom_fields", label: "Custom fields", kind: .customFields)
    ]

    // MARK: - Markers

    private static let markerFields: [FilterFieldDescriptor] = [
        .init(key: "tags", label: "Tags", kind: .hierarchicalMulti),
        .init(key: "scene_tags", label: "Scene tags", kind: .hierarchicalMulti),
        .init(key: "performers", label: "Performers", kind: .multi),
        .init(key: "scenes", label: "Scenes", kind: .multi),
        .init(key: "duration", label: "Duration (s)", kind: .float),
        .init(key: "created_at", label: "Created", kind: .timestamp),
        .init(key: "updated_at", label: "Updated", kind: .timestamp),
        .init(key: "scene_date", label: "Scene date", kind: .date),
        .init(key: "scene_created_at", label: "Scene created", kind: .timestamp),
        .init(key: "scene_updated_at", label: "Scene updated", kind: .timestamp),
        .init(key: "scene_filter", label: "Scene filter", kind: .nestedFilter, nestedMode: .scenes)
    ]
}

// MARK: - Sort catalog

/// One selectable sort entry, mode-agnostic.
struct FilterSortChoice: Identifiable, Hashable {
    /// stashy `ui_options.stashy.sortRaw` (the `*SortOption` raw value).
    let raw: String
    let label: String
    /// GraphQL `find_filter.sort`.
    let field: String
    /// `ASC` / `DESC`.
    let direction: String

    var id: String { raw }
}

/// Bridges the typed `StashDBViewModel.*SortOption` enums to a `FilterMode`-keyed list, so the
/// filter editor (Tools → Filters) can offer the same sort choices as the catalog sheets.
protocol FilterSortChoiceConvertible: CaseIterable, RawRepresentable where RawValue == String {
    var displayName: String { get }
    var direction: String { get }
    var sortField: String { get }
}

extension StashDBViewModel.SceneSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.SceneMarkerSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.ImageSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.GallerySortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.PerformerSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.StudioSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.TagSortOption: FilterSortChoiceConvertible {}
extension StashDBViewModel.GroupSortOption: FilterSortChoiceConvertible {}

enum FilterSortCatalog {
    static func choices(for mode: StashDBViewModel.FilterMode) -> [FilterSortChoice] {
        switch mode {
        case .scenes: return map(StashDBViewModel.SceneSortOption.self)
        case .sceneMarkers: return map(StashDBViewModel.SceneMarkerSortOption.self)
        case .images: return map(StashDBViewModel.ImageSortOption.self)
        case .galleries: return map(StashDBViewModel.GallerySortOption.self)
        case .performers: return map(StashDBViewModel.PerformerSortOption.self)
        case .studios: return map(StashDBViewModel.StudioSortOption.self)
        case .tags: return map(StashDBViewModel.TagSortOption.self)
        case .groups: return map(StashDBViewModel.GroupSortOption.self)
        case .unknown: return []
        }
    }

    /// Resolves the sort a saved filter currently carries: stashy `sortRaw` first, then the
    /// encoded `find_filter` pair.
    static func choice(forRaw raw: String?, pair: (field: String, direction: String)?, mode: StashDBViewModel.FilterMode) -> FilterSortChoice? {
        let list = choices(for: mode)
        if let raw, let hit = list.first(where: { $0.raw == raw }) { return hit }
        guard let pair else { return nil }
        let field = pair.field.lowercased()
        let direction = pair.direction.uppercased()
        if field.hasPrefix("random") { return list.first(where: { $0.field == "random" }) }
        if let hit = list.first(where: { $0.field.lowercased() == field && $0.direction.uppercased() == direction }) {
            return hit
        }
        // Stash writes both `rating` and `rating100` depending on version.
        if field == "rating100" || field == "rating" {
            return list.first(where: { $0.field.lowercased().hasPrefix("rating") && $0.direction.uppercased() == direction })
        }
        return nil
    }

    private static func map<T: FilterSortChoiceConvertible>(_ type: T.Type) -> [FilterSortChoice] {
        T.allCases.map {
            FilterSortChoice(raw: $0.rawValue, label: $0.displayName, field: $0.sortField, direction: $0.direction)
        }
    }
}

// MARK: - Default (pinned) criteria per mode

extension FilterFieldCatalog {
    /// Kriterien, die eine Filter-Sheet **immer** zeigt — auch ohne gesetzten Wert.
    /// Ersetzt die früheren Quick-Chips: eine Liste statt Chips + Advanced-Editor nebeneinander.
    /// Reihenfolge = Anzeigereihenfolge ganz oben; alles Weitere kommt über „Add condition“ darunter.
    static func defaultCriterionKeys(for mode: StashDBViewModel.FilterMode) -> [String] {
        let keys: [String]
        switch mode {
        case .scenes:
            keys = ["tags", "performers", "studios", "rating100", "o_counter", "organized", "resolution"]
        case .performers:
            keys = ["filter_favorites", "gender", "age", "hair_color", "country", "fake_tits", "o_counter", "tags"]
        case .studios:
            keys = ["favorite", "rating100", "scene_count", "tags"]
        case .tags:
            keys = ["favorite", "scene_count", "image_count", "parents"]
        case .galleries:
            keys = ["tags", "performers", "studios", "rating100", "performer_favorite", "image_count"]
        case .images:
            keys = ["tags", "performers", "studios", "rating100", "o_counter", "organized"]
        case .groups:
            keys = ["studios", "tags", "performers", "rating100", "date"]
        case .sceneMarkers:
            keys = ["tags", "scene_tags", "performers", "duration"]
        case .unknown:
            keys = []
        }
        // Nie ein Feld anbieten, das der Modus gar nicht kennt.
        let known = Set(fields(for: mode).map(\.key))
        return keys.filter { known.contains($0) }
    }
}

// MARK: - Collapsed row summaries

/// Einzeiler für eingeklappte Kriterien-Karten ("≥ 5", "3 selected", "Female").
enum FilterCriterionSummary {
    static let anyText = "Any"

    static func text(for field: FilterFieldDescriptor, value: Any?) -> String {
        guard let value else { return anyText }
        switch field.kind {
        case .boolean:
            guard let b = value as? Bool else { return anyText }
            return b ? "Yes" : "No"
        case .isMissing, .hasMarkers, .hasChapters:
            guard let s = value as? String, !s.isEmpty else { return anyText }
            if field.kind == .isMissing { return s.replacingOccurrences(of: "_", with: " ").capitalized }
            return s == "true" ? "Yes" : "No"
        case .booleanGroup:
            return anyText
        case .nestedFilter, .raw:
            let count = (FilterCriteriaDocument.stringKeyedDict(value) ?? [:]).count
            return count == 0 ? anyText : "\(count) criteria"
        case .customFields:
            let count = (value as? [Any])?.count ?? 0
            return count == 0 ? anyText : "\(count) field(s)"
        default:
            guard let dict = FilterCriteriaDocument.stringKeyedDict(value) else { return anyText }
            return dictSummary(field: field, dict: dict)
        }
    }

    private static func dictSummary(field: FilterFieldDescriptor, dict: [String: Any]) -> String {
        let modifierRaw = (dict["modifier"] as? String) ?? ""
        let modifier = StashCriterionModifier(rawValue: modifierRaw)
        if modifier == .isNull { return "Not set" }
        if modifier == .notNull { return "Any value" }

        switch field.kind {
        case .hierarchicalMulti, .multi:
            let included = FilterMapper.idStrings(from: dict["value"]).count
            let excluded = FilterMapper.idStrings(from: dict["excludes"]).count
            if included == 0 && excluded == 0 { return anyText }
            var parts: [String] = []
            if included > 0 { parts.append("\(included) selected") }
            if excluded > 0 { parts.append("\(excluded) excluded") }
            return parts.joined(separator: ", ")
        case .gender, .circumcision:
            let list = (dict["value_list"] as? [String]) ?? (dict["value"] as? [String]) ?? []
            if list.isEmpty, let single = dict["value"] as? String { return prettify(single) }
            if list.isEmpty { return anyText }
            return list.map(prettify).joined(separator: ", ")
        case .orientation:
            let list = (dict["value"] as? [String]) ?? []
            return list.isEmpty ? anyText : list.map(prettify).joined(separator: ", ")
        case .duplication:
            guard let dup = dict["duplicated"] as? Bool else { return anyText }
            return dup ? "Duplicated" : "Unique"
        case .stashID, .stashIDs:
            return modifier?.label ?? anyText
        default:
            break
        }

        let value = displayValue(dict["value"])
        let value2 = displayValue(dict["value2"])
        guard !value.isEmpty else { return anyText }
        let symbol = compactModifier(modifier)
        if let value2 = value2.isEmpty ? nil : value2, modifier?.needsSecondValue == true {
            return "\(symbol) \(value) – \(value2)"
        }
        return symbol.isEmpty ? value : "\(symbol) \(value)"
    }

    private static func compactModifier(_ modifier: StashCriterionModifier?) -> String {
        switch modifier {
        case .equals: return ""
        case .notEquals: return "≠"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .between: return ""
        case .notBetween: return "not"
        case .includes, .includesAll: return "contains"
        case .excludes: return "without"
        case .matchesRegex: return "regex"
        case .notMatchesRegex: return "not regex"
        default: return ""
        }
    }

    private static func displayValue(_ raw: Any?) -> String {
        guard let raw else { return "" }
        if let s = raw as? String { return s }
        if let i = raw as? Int { return String(i) }
        if let d = raw as? Double { return d == d.rounded() ? String(Int(d)) : String(d) }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private static func prettify(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
