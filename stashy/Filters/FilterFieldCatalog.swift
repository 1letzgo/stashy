import Foundation

struct FilterFieldDescriptor: Identifiable, Hashable {
    let key: String
    let label: String
    let kind: FilterCriterionKind
    var nestedMode: StashDBViewModel.FilterMode? = nil
    var isDeprecated: Bool = false

    var id: String { key }

    /// Sub-filters (`scenes_filter`, …) and the raw `files_filter` work in the API, but the web UI
    /// neither offers them nor keeps them when it re-saves a filter.
    var isAppOnly: Bool { kind == .nestedFilter || kind == .raw }
}

enum FilterFieldCatalog {
    static func fields(for mode: StashDBViewModel.FilterMode) -> [FilterFieldDescriptor] {
        switch mode {
        case .scenes: return availableOnServer(sceneFields)
        case .performers: return performerFields
        case .studios: return studioFields
        case .galleries: return availableOnServer(galleryFields)
        case .images: return availableOnServer(imageFields)
        case .tags: return tagFields
        case .groups: return groupFields
        case .sceneMarkers: return markerFields
        case .unknown: return []
        }
    }

    /// Fields only Stash 0.32+ knows; an older server rejects the whole query over one of them.
    private static let stash032Keys: Set<String> = ["production_date", "folder", "parent_folder"]

    private static func availableOnServer(_ fields: [FilterFieldDescriptor]) -> [FilterFieldDescriptor] {
        StashServerCapabilities.supports032 ? fields : fields.filter { !stash032Keys.contains($0.key) }
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
            // The multi Stash ID list is covered by "Stash ID" (the web UI's criterion).
            if field.kind == .stashIDs { return false }
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

    private static var sceneFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "title", label: tr("title"), kind: .string),
        .init(key: "code", label: tr("code"), kind: .string),
        .init(key: "details", label: tr("details"), kind: .string),
        .init(key: "director", label: tr("director"), kind: .string),
        .init(key: "oshash", label: "OSHash", kind: .string),
        .init(key: "checksum", label: tr("checksum"), kind: .string),
        .init(key: "phash_distance", label: tr("phash_distance"), kind: .phashDistance),
        .init(key: "path", label: tr("path"), kind: .string),
        .init(key: "file_count", label: tr("file_count"), kind: .int),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "organized", label: tr("organized"), kind: .boolean),
        .init(key: "o_counter", label: tr("o_count"), kind: .int),
        .init(key: "duplicated", label: tr("duplicated"), kind: .duplication),
        .init(key: "resolution", label: tr("resolution"), kind: .resolution),
        .init(key: "orientation", label: tr("orientation"), kind: .orientation),
        .init(key: "framerate", label: tr("framerate"), kind: .int),
        .init(key: "bitrate", label: tr("bitrate"), kind: .int),
        .init(key: "video_codec", label: tr("video_codec"), kind: .string),
        .init(key: "audio_codec", label: tr("audio_codec"), kind: .string),
        .init(key: "duration", label: tr("duration_s"), kind: .int),
        .init(key: "has_markers", label: tr("has_markers"), kind: .hasMarkers),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "studios", label: tr("studios"), kind: .hierarchicalMulti),
        .init(key: "groups", label: tr("groups"), kind: .hierarchicalMulti),
        .init(key: "galleries", label: tr("galleries"), kind: .multi),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "performer_tags", label: tr("performer_tags"), kind: .hierarchicalMulti),
        .init(key: "performer_favorite", label: tr("performer_favorite"), kind: .boolean),
        .init(key: "performer_age", label: tr("performer_age"), kind: .int),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "performer_count", label: tr("performer_count"), kind: .int),
        .init(key: "stash_ids_endpoint", label: tr("stash_ids"), kind: .stashIDs),
        .init(key: "stash_id_count", label: tr("stash_id_count"), kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "interactive", label: tr("interactive"), kind: .boolean),
        .init(key: "interactive_speed", label: tr("interactive_speed"), kind: .int),
        .init(key: "captions", label: tr("captions"), kind: .string),
        .init(key: "resume_time", label: tr("resume_time"), kind: .int),
        .init(key: "play_count", label: tr("play_count"), kind: .int),
        .init(key: "play_duration", label: tr("play_duration"), kind: .int),
        .init(key: "last_played_at", label: tr("last_played"), kind: .timestamp),
        .init(key: "date", label: tr("date"), kind: .date),
        .init(key: "production_date", label: tr("production_date"), kind: .date),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "galleries_filter", label: tr("galleries_filter"), kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "performers_filter", label: tr("performers_filter"), kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: tr("studios_filter"), kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: tr("tags_filter"), kind: .nestedFilter, nestedMode: .tags),
        .init(key: "groups_filter", label: tr("groups_filter"), kind: .nestedFilter, nestedMode: .groups),
        .init(key: "markers_filter", label: tr("markers_filter"), kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "folder", label: tr("folder"), kind: .hierarchicalMulti),
        .init(key: "files_filter", label: tr("files_filter"), kind: .raw),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields),
        .init(key: "movies", label: tr("movies"), kind: .multi, isDeprecated: true),
        .init(key: "phash", label: "PHash", kind: .string, isDeprecated: true),
        .init(key: "stash_id_endpoint", label: tr("stash_id"), kind: .stashID),
        .init(key: "movies_filter", label: tr("movies_filter"), kind: .nestedFilter, nestedMode: .groups, isDeprecated: true)
    ]
    }

    // MARK: - Performers

    private static var performerFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "name", label: tr("name"), kind: .string),
        .init(key: "disambiguation", label: tr("disambiguation"), kind: .string),
        .init(key: "details", label: tr("details"), kind: .string),
        .init(key: "filter_favorites", label: tr("favourite"), kind: .boolean),
        .init(key: "birth_year", label: tr("birth_year"), kind: .int),
        .init(key: "age", label: tr("age"), kind: .int),
        .init(key: "ethnicity", label: tr("ethnicity"), kind: .string),
        .init(key: "country", label: tr("country"), kind: .string),
        .init(key: "eye_color", label: tr("eye_color"), kind: .string),
        .init(key: "height_cm", label: tr("height_cm"), kind: .int),
        .init(key: "measurements", label: tr("measurements"), kind: .string),
        .init(key: "fake_tits", label: tr("implants"), kind: .string),
        .init(key: "penis_length", label: tr("penis_length"), kind: .float),
        .init(key: "circumcised", label: tr("circumcised"), kind: .circumcision),
        .init(key: "career_start", label: tr("career_start"), kind: .date),
        .init(key: "career_end", label: tr("career_end"), kind: .date),
        .init(key: "tattoos", label: tr("tattoos"), kind: .string),
        .init(key: "piercings", label: tr("piercings"), kind: .string),
        .init(key: "aliases", label: tr("aliases"), kind: .string),
        .init(key: "gender", label: tr("gender"), kind: .gender),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "scene_count", label: tr("scene_count"), kind: .int),
        .init(key: "marker_count", label: tr("marker_count"), kind: .int),
        .init(key: "image_count", label: tr("image_count"), kind: .int),
        .init(key: "gallery_count", label: tr("gallery_count"), kind: .int),
        .init(key: "play_count", label: tr("play_count"), kind: .int),
        .init(key: "o_counter", label: tr("o_count"), kind: .int),
        .init(key: "stash_ids_endpoint", label: tr("stash_ids"), kind: .stashIDs),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "hair_color", label: tr("hair_color"), kind: .string),
        .init(key: "weight", label: tr("weight"), kind: .int),
        .init(key: "death_year", label: tr("death_year"), kind: .int),
        .init(key: "studios", label: tr("studios"), kind: .hierarchicalMulti),
        .init(key: "groups", label: tr("groups"), kind: .hierarchicalMulti),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "ignore_auto_tag", label: tr("ignore_auto_tag"), kind: .boolean),
        .init(key: "birthdate", label: tr("birthdate"), kind: .date),
        .init(key: "death_date", label: tr("death_date"), kind: .date),
        .init(key: "scenes_filter", label: tr("scenes_filter"), kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: tr("images_filter"), kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: tr("galleries_filter"), kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "tags_filter", label: tr("tags_filter"), kind: .nestedFilter, nestedMode: .tags),
        .init(key: "markers_filter", label: tr("markers_filter"), kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields),
        .init(key: "stash_id_endpoint", label: tr("stash_id"), kind: .stashID)
    ]
    }

    // MARK: - Studios

    private static var studioFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "name", label: tr("name"), kind: .string),
        .init(key: "details", label: tr("details"), kind: .string),
        .init(key: "parents", label: tr("parents"), kind: .multi),
        .init(key: "stash_ids_endpoint", label: tr("stash_ids"), kind: .stashIDs),
        .init(key: "stash_id_endpoint", label: tr("stash_id"), kind: .stashID),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "favorite", label: tr("favourite"), kind: .boolean),
        .init(key: "scene_count", label: tr("scene_count"), kind: .int),
        .init(key: "image_count", label: tr("image_count"), kind: .int),
        .init(key: "gallery_count", label: tr("gallery_count"), kind: .int),
        .init(key: "group_count", label: tr("group_count"), kind: .int),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "aliases", label: tr("aliases"), kind: .string),
        .init(key: "child_count", label: tr("child_count"), kind: .int),
        .init(key: "ignore_auto_tag", label: tr("ignore_auto_tag"), kind: .boolean),
        .init(key: "organized", label: tr("organized"), kind: .boolean),
        .init(key: "scenes_filter", label: tr("scenes_filter"), kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: tr("images_filter"), kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: tr("galleries_filter"), kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "groups_filter", label: tr("groups_filter"), kind: .nestedFilter, nestedMode: .groups),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields)
    ]
    }

    // MARK: - Galleries

    private static var galleryFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "title", label: tr("title"), kind: .string),
        .init(key: "details", label: tr("details"), kind: .string),
        .init(key: "checksum", label: tr("checksum"), kind: .string),
        .init(key: "path", label: tr("path"), kind: .string),
        .init(key: "file_count", label: tr("file_count"), kind: .int),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "is_zip", label: tr("is_zip"), kind: .boolean),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "organized", label: tr("organized"), kind: .boolean),
        .init(key: "average_resolution", label: tr("avg_resolution"), kind: .resolution),
        .init(key: "has_chapters", label: tr("has_chapters"), kind: .hasChapters),
        .init(key: "scenes", label: tr("scenes"), kind: .multi),
        .init(key: "studios", label: tr("studios"), kind: .hierarchicalMulti),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "performer_tags", label: tr("performer_tags"), kind: .hierarchicalMulti),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "performer_count", label: tr("performer_count"), kind: .int),
        .init(key: "performer_favorite", label: tr("performer_favorite"), kind: .boolean),
        .init(key: "performer_age", label: tr("performer_age"), kind: .int),
        .init(key: "image_count", label: tr("image_count"), kind: .int),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "date", label: tr("date"), kind: .date),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "code", label: tr("code"), kind: .string),
        .init(key: "photographer", label: tr("photographer"), kind: .string),
        .init(key: "scenes_filter", label: tr("scenes_filter"), kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: tr("images_filter"), kind: .nestedFilter, nestedMode: .images),
        .init(key: "performers_filter", label: tr("performers_filter"), kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: tr("studios_filter"), kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: tr("tags_filter"), kind: .nestedFilter, nestedMode: .tags),
        .init(key: "parent_folder", label: tr("folder"), kind: .hierarchicalMulti),
        .init(key: "files_filter", label: tr("files_filter"), kind: .raw),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields)
    ]
    }

    // MARK: - Images

    private static var imageFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "title", label: tr("title"), kind: .string),
        .init(key: "details", label: tr("details"), kind: .string),
        .init(key: "id", label: "ID", kind: .int),
        .init(key: "checksum", label: tr("checksum"), kind: .string),
        .init(key: "phash_distance", label: tr("phash_distance"), kind: .phashDistance),
        .init(key: "path", label: tr("path"), kind: .string),
        .init(key: "file_count", label: tr("file_count"), kind: .int),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "date", label: tr("date"), kind: .date),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "organized", label: tr("organized"), kind: .boolean),
        .init(key: "o_counter", label: tr("o_count"), kind: .int),
        .init(key: "resolution", label: tr("resolution"), kind: .resolution),
        .init(key: "orientation", label: tr("orientation"), kind: .orientation),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "studios", label: tr("studios"), kind: .hierarchicalMulti),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "performer_tags", label: tr("performer_tags"), kind: .hierarchicalMulti),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "performer_count", label: tr("performer_count"), kind: .int),
        .init(key: "performer_favorite", label: tr("performer_favorite"), kind: .boolean),
        .init(key: "performer_age", label: tr("performer_age"), kind: .int),
        .init(key: "galleries", label: tr("galleries"), kind: .multi),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "code", label: tr("code"), kind: .string),
        .init(key: "photographer", label: tr("photographer"), kind: .string),
        .init(key: "galleries_filter", label: tr("galleries_filter"), kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "performers_filter", label: tr("performers_filter"), kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: tr("studios_filter"), kind: .nestedFilter, nestedMode: .studios),
        .init(key: "tags_filter", label: tr("tags_filter"), kind: .nestedFilter, nestedMode: .tags),
        .init(key: "folder", label: tr("folder"), kind: .hierarchicalMulti),
        .init(key: "files_filter", label: tr("files_filter"), kind: .raw),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields)
    ]
    }

    // MARK: - Tags

    private static var tagFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "name", label: tr("name"), kind: .string),
        .init(key: "sort_name", label: tr("sort_name"), kind: .string),
        .init(key: "aliases", label: tr("aliases"), kind: .string),
        .init(key: "favorite", label: tr("favourite"), kind: .boolean),
        .init(key: "description", label: tr("description"), kind: .string),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "scene_count", label: tr("scene_count"), kind: .hierarchicalCount),
        .init(key: "image_count", label: tr("image_count"), kind: .hierarchicalCount),
        .init(key: "gallery_count", label: tr("gallery_count"), kind: .hierarchicalCount),
        .init(key: "performer_count", label: tr("performer_count"), kind: .hierarchicalCount),
        .init(key: "studio_count", label: tr("studio_count"), kind: .hierarchicalCount),
        .init(key: "group_count", label: tr("group_count"), kind: .hierarchicalCount),
        .init(key: "marker_count", label: tr("marker_count"), kind: .hierarchicalCount),
        .init(key: "parents", label: tr("parents"), kind: .hierarchicalMulti),
        .init(key: "children", label: tr("children"), kind: .hierarchicalMulti),
        .init(key: "parent_count", label: tr("parent_count"), kind: .int),
        .init(key: "child_count", label: tr("child_count"), kind: .int),
        .init(key: "ignore_auto_tag", label: tr("ignore_auto_tag"), kind: .boolean),
        .init(key: "stash_ids_endpoint", label: tr("stash_ids"), kind: .stashIDs),
        .init(key: "stash_id_endpoint", label: tr("stash_id"), kind: .stashID),
        .init(key: "scenes_filter", label: tr("scenes_filter"), kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "images_filter", label: tr("images_filter"), kind: .nestedFilter, nestedMode: .images),
        .init(key: "galleries_filter", label: tr("galleries_filter"), kind: .nestedFilter, nestedMode: .galleries),
        .init(key: "groups_filter", label: tr("groups_filter"), kind: .nestedFilter, nestedMode: .groups),
        .init(key: "performers_filter", label: tr("performers_filter"), kind: .nestedFilter, nestedMode: .performers),
        .init(key: "studios_filter", label: tr("studios_filter"), kind: .nestedFilter, nestedMode: .studios),
        .init(key: "markers_filter", label: tr("markers_filter"), kind: .nestedFilter, nestedMode: .sceneMarkers),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields)
    ]
    }

    // MARK: - Groups

    private static var groupFields: [FilterFieldDescriptor] {
boolOps() + [
        .init(key: "name", label: tr("name"), kind: .string),
        .init(key: "director", label: tr("director"), kind: .string),
        .init(key: "synopsis", label: tr("synopsis"), kind: .string),
        .init(key: "duration", label: tr("duration_s"), kind: .int),
        .init(key: "rating100", label: tr("rating"), kind: .int),
        .init(key: "studios", label: tr("studios"), kind: .hierarchicalMulti),
        .init(key: "is_missing", label: tr("is_missing"), kind: .isMissing),
        .init(key: "url", label: "URL", kind: .string),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "tag_count", label: tr("tag_count"), kind: .int),
        .init(key: "date", label: tr("date"), kind: .date),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "o_counter", label: tr("o_count"), kind: .int),
        .init(key: "containing_groups", label: tr("containing_groups"), kind: .hierarchicalMulti),
        .init(key: "sub_groups", label: "Sub-Groups", kind: .hierarchicalMulti),
        .init(key: "containing_group_count", label: tr("containing_group_count"), kind: .int),
        .init(key: "sub_group_count", label: tr("sub_group_count"), kind: .int),
        .init(key: "scene_count", label: tr("scene_count"), kind: .int),
        .init(key: "scenes_filter", label: tr("scenes_filter"), kind: .nestedFilter, nestedMode: .scenes),
        .init(key: "studios_filter", label: tr("studios_filter"), kind: .nestedFilter, nestedMode: .studios),
        .init(key: "custom_fields", label: tr("custom_fields"), kind: .customFields)
    ]
    }

    // MARK: - Value suggestions

    /// A selectable value chip under a text criterion. `value` is what goes to the server,
    /// `label` what the chip shows (countries: ISO code vs. localized name).
    struct ValueSuggestion: Identifiable, Hashable {
        let value: String
        let label: String
        var id: String { value }
        init(_ value: String, _ label: String? = nil) {
            self.value = value
            self.label = label ?? value
        }
    }

    /// Common values for free-text criteria, per entity and field. Stash keeps these as plain
    /// strings, so the lists are the conventions its own UI and scrapers produce; the text
    /// field stays open for anything else.
    static func valueSuggestions(key: String, mode: StashDBViewModel.FilterMode) -> [ValueSuggestion] {
        switch (mode, key) {
        case (.performers, "hair_color"):
            return ["Blonde", "Brunette", "Brown", "Black", "Red", "Auburn", "Grey", "White", "Bald", "Various"].map { .init($0) }
        case (.performers, "eye_color"):
            return ["Blue", "Brown", "Green", "Grey", "Hazel", "Amber"].map { .init($0) }
        case (.performers, "ethnicity"):
            return ["Caucasian", "Black", "Asian", "Indian", "Latin", "Middle Eastern", "Mixed", "Other"].map { .init($0) }
        case (.performers, "fake_tits"):
            return ["Natural", "Fake"].map { .init($0) }
        case (.performers, "country"):
            return countrySuggestions
        case (.scenes, "video_codec"):
            return ["h264", "hevc", "av1", "vp9", "vp8", "mpeg4", "wmv3", "mpeg2video"].map { .init($0) }
        case (.scenes, "audio_codec"):
            return ["aac", "mp3", "ac3", "eac3", "opus", "vorbis", "flac", "pcm_s16le"].map { .init($0) }
        case (.scenes, "captions"):
            return ["en", "de", "fr", "es", "it", "ja", "ru", "pt"].map { .init($0) }
        default:
            return []
        }
    }

    /// ISO 3166-1 alpha-2 codes (what Stash stores), shown with their localized names. The most
    /// common production countries first, then the rest alphabetically by name.
    private static let countrySuggestions: [ValueSuggestion] = {
        let preferred = ["US", "GB", "DE", "CZ", "HU", "RU", "FR", "ES", "IT", "BR", "CA", "AU", "JP", "NL", "PL", "UA", "CO", "MX", "SE", "AT", "CH"]
        let locale = Locale.current
        func name(_ code: String) -> String { locale.localizedString(forRegionCode: code) ?? code }
        let rest = Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && !preferred.contains($0) }
            .map { ValueSuggestion($0, name($0)) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return preferred.map { ValueSuggestion($0, name($0)) } + rest
    }()

    // MARK: - is_missing

    /// Property names Stash accepts for `is_missing`, per entity — mirrors the option lists in
    /// Stash's `list-filter/criteria/is-missing.ts`. Each entity has its own set; the scene list
    /// used to be offered everywhere, which produced criteria the server silently ignored.
    static func isMissingOptions(for mode: StashDBViewModel.FilterMode) -> [String] {
        switch mode {
        case .scenes:
            return ["title", "code", "details", "director", "url", "date", "production_date", "rating",
                    "cover", "galleries", "studio", "group", "performers", "tags", "stash_id"]
        case .images:
            return ["title", "details", "photographer", "url", "date", "code", "rating",
                    "galleries", "studio", "performers", "tags"]
        case .performers:
            return ["image", "url", "details", "aliases", "gender", "birthdate", "death_date", "disambiguation",
                    "ethnicity", "country", "hair_color", "eye_color", "height", "weight", "measurements",
                    "fake_tits", "penis_length", "circumcised", "career_start", "career_end", "tattoos",
                    "piercings", "tags", "rating", "stash_id"]
        case .galleries:
            return ["title", "code", "details", "photographer", "url", "date", "rating", "cover",
                    "studio", "performers", "tags", "scenes"]
        case .tags:
            return ["image", "aliases", "description", "stash_id"]
        case .studios:
            return ["image", "stash_id", "details", "url", "aliases", "tags", "rating"]
        case .groups:
            return ["aliases", "description", "director", "date", "url", "rating", "studio",
                    "performers", "tags", "front_image", "back_image", "scenes"]
        case .sceneMarkers, .unknown:
            return []
        }
    }

    // MARK: - Markers

    private static var markerFields: [FilterFieldDescriptor] {
[
        .init(key: "tags", label: tr("tags"), kind: .hierarchicalMulti),
        .init(key: "scene_tags", label: tr("scene_tags"), kind: .hierarchicalMulti),
        .init(key: "performers", label: tr("performers"), kind: .multi),
        .init(key: "scenes", label: tr("scenes"), kind: .multi),
        .init(key: "duration", label: tr("duration_s"), kind: .float),
        .init(key: "created_at", label: tr("created"), kind: .timestamp),
        .init(key: "updated_at", label: tr("updated"), kind: .timestamp),
        .init(key: "scene_date", label: tr("scene_date"), kind: .date),
        .init(key: "scene_created_at", label: tr("scene_created"), kind: .timestamp),
        .init(key: "scene_updated_at", label: tr("scene_updated"), kind: .timestamp),
        .init(key: "scene_filter", label: tr("scene_filter"), kind: .nestedFilter, nestedMode: .scenes)
    ]
    }
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
    static var anyText: String { tr("any") }

    static func text(for field: FilterFieldDescriptor, value: Any?) -> String {
        guard let value else { return anyText }
        switch field.kind {
        case .boolean:
            guard let b = value as? Bool else { return anyText }
            return b ? tr("yes") : tr("no")
        case .isMissing, .hasMarkers, .hasChapters:
            guard let s = value as? String, !s.isEmpty else { return anyText }
            if field.kind == .isMissing { return s.replacingOccurrences(of: "_", with: " ").capitalized }
            return s == "true" ? tr("yes") : tr("no")
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
        if modifier == .isNull { return tr("not_set") }
        if modifier == .notNull { return tr("any_value") }

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
            return dup ? tr("duplicated") : tr("unique")
        case .stashID, .stashIDs:
            return modifier?.label ?? anyText
        default:
            break
        }

        // Timestamps read "2026-11-03 00:00", not the GraphQL "…T00:00".
        let readable: (String) -> String = { field.kind == .timestamp ? $0.replacingOccurrences(of: "T", with: " ") : $0 }
        let value = readable(displayValue(dict["value"]))
        let value2 = readable(displayValue(dict["value2"]))
        guard !value.isEmpty else { return anyText }
        if modifier == .matchesRegex || modifier == .notMatchesRegex {
            return regexText(value, negated: modifier == .notMatchesRegex)
        }
        let symbol = compactModifier(modifier)
        if let value2 = value2.isEmpty ? nil : value2, modifier?.needsSecondValue == true {
            return "\(symbol) \(value) – \(value2)"
        }
        return symbol.isEmpty ? value : "\(symbol) \(value)"
    }

    /// A regex in plain words: the name search's case-insensitive `(?i)` prefix is dropped,
    /// and a pattern that is just text reads as that text in quotes.
    private static func regexText(_ pattern: String, negated: Bool) -> String {
        var text = pattern
        if text.hasPrefix(FilterCriteriaDocument.nameSearchRegexPrefix) {
            text.removeFirst(FilterCriteriaDocument.nameSearchRegexPrefix.count)
        }
        let isPlainText = text.rangeOfCharacter(from: CharacterSet(charactersIn: "\\^$.|?*+()[]{}")) == nil
        if isPlainText { return negated ? "without “\(text)”" : "“\(text)”" }
        return negated ? "not matching \(text)" : "matches \(text)"
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
