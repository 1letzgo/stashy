package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.SavedFilter
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull

// Pure logic of Tools › Filters (iOS: `FiltersToolsView.swift`, `StashDBViewModel.SavedFilter`,
// `renameSavedFilter`). Free of Android APIs so plain JUnit tests can run it.

/**
 * One server saved filter plus the legacy UI `filter` JSON string that `Models.SavedFilter`
 * does not carry (iOS: `SavedFilter.filter`, read by `filterDict` / `encodedSortPair`).
 */
data class FiltersToolEntry(val filter: SavedFilter, val legacyFilter: String? = null)

/** One list section (iOS: `grouped` tuple). [mode] is the raw `FilterMode` (`SCENES` …). */
data class FiltersToolSection(val mode: String, val entries: List<FiltersToolEntry>)

object FiltersLogic {
    /** iOS: `FiltersToolsView.listedModes` (order of the sections and of the "+" menu). */
    val listedModes = listOf("SCENES", "SCENE_MARKERS", "PERFORMERS", "STUDIOS", "TAGS", "GALLERIES", "IMAGES", "GROUPS")

    /** iOS: `FilterMode(from:)` — case-insensitive, unknown values become `UNKNOWN`. */
    fun normalizedMode(raw: String?): String {
        val upper = raw?.uppercase().orEmpty()
        return if (upper in listedModes) upper else "UNKNOWN"
    }

    /** iOS: `FiltersToolsView.modeTitle(_:)`. */
    fun modeTitle(mode: String): String = when (normalizedMode(mode)) {
        "SCENES" -> "Scenes"
        "SCENE_MARKERS" -> "Markers"
        "PERFORMERS" -> "Performers"
        "STUDIOS" -> "Studios"
        "TAGS" -> "Tags"
        "GALLERIES" -> "Galleries"
        "IMAGES" -> "Images"
        "GROUPS" -> "Groups"
        else -> "Other"
    }

    /**
     * iOS: `filteredFilters` + `grouped` — name search (trimmed, case-insensitive), sorted by name,
     * grouped in [listedModes] order; empty sections and `UNKNOWN` filters are dropped.
     */
    fun grouped(entries: Collection<FiltersToolEntry>, search: String): List<FiltersToolSection> {
        val q = search.trim().lowercase()
        val filtered = entries
            .filter { q.isEmpty() || it.filter.name.lowercase().contains(q) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.filter.name })
        return listedModes.mapNotNull { mode ->
            val list = filtered.filter { normalizedMode(it.filter.mode) == mode }
            if (list.isEmpty()) null else FiltersToolSection(mode, list)
        }
    }

    /** iOS: `SavedFilter.filterDict` — `object_filter`, else the legacy UI filter JSON. */
    fun filterDict(entry: FiltersToolEntry): JsonObject? =
        entry.filter.objectFilter as? JsonObject ?: legacyJson(entry.legacyFilter)

    private fun legacyJson(raw: String?): JsonObject? =
        raw?.takeIf { it.isNotBlank() }?.let { runCatching { Json.parseToJsonElement(it) as? JsonObject }.getOrNull() }

    /**
     * Criteria keys shown in the row summary (iOS: `criteriaObjectFilter().keys.sorted()`).
     * Approximation of `FilterCriteriaDocument.sanitizeNonisolated`: drops editor scratch keys
     * (`*_text`), nulls and empty objects.
     */
    fun criteriaKeys(entry: FiltersToolEntry): List<String> {
        val dict = entry.filter.objectFilter as? JsonObject ?: legacyJson(entry.legacyFilter)?.let { legacy ->
            // A legacy UI blob holds sort/paging next to the criteria — not criteria.
            JsonObject(legacy.filterKeys { it !in legacyNonCriteriaKeys })
        } ?: return emptyList()
        return dict.filter { (key, value) ->
            !key.endsWith("_text") && value !is JsonNull && !(value is JsonObject && value.isEmpty())
        }.keys.sorted()
    }

    private val legacyNonCriteriaKeys = setOf(
        "sort", "sortby", "sortBy", "sortdir", "sortDirection", "direction", "dir",
        "q", "page", "perPage", "per_page", "disp", "c", "mode",
    )

    /** iOS: `criteriaSummary(_:)` — "Rating, Tags, Studios…", or "No criteria". */
    fun criteriaSummary(entry: FiltersToolEntry): String {
        val keys = criteriaKeys(entry)
        if (keys.isEmpty()) return "No criteria"
        val mode = normalizedMode(entry.filter.mode)
        val labels = keys.map { fieldLabel(it, mode) ?: it }
        return labels.take(4).joinToString(", ") + if (labels.size > 4) "…" else ""
    }

    /** iOS: `FilterFieldCatalog.field(key:mode:)?.label`. */
    fun fieldLabel(key: String, mode: String): String? =
        if (key == "AND" || key == "OR" || key == "NOT") key else fieldLabels[normalizedMode(mode)]?.get(key)

    /** iOS: `SavedFilter.encodedSortPair` — `find_filter`, then the legacy UI JSON. */
    fun encodedSortPair(entry: FiltersToolEntry): Pair<String, String>? {
        val ff = entry.filter.findFilter
        val sort = (ff?.get("sort") as? JsonPrimitive)?.contentOrNull?.trim()
        if (!sort.isNullOrEmpty()) {
            val dir = (ff?.get("direction") as? JsonPrimitive)?.contentOrNull?.trim()
            return sort to (dir?.takeIf { it.isNotEmpty() } ?: "DESC")
        }
        val dict = legacyJson(entry.legacyFilter) ?: return null
        fun str(key: String) = (dict[key] as? JsonPrimitive)?.contentOrNull
        val field = str("sort") ?: str("sortby") ?: str("sortBy")
        val dir = str("direction") ?: str("sortdir") ?: str("sortDirection") ?: str("dir")
        if (field.isNullOrEmpty()) return null
        return field to (dir?.takeIf { it.isNotEmpty() } ?: "DESC")
    }

    /**
     * iOS: `renameSavedFilter` → `saveFullObjectFilter` — the `SaveFilterInput` that renames a
     * filter without touching criteria, sort or stashy metadata. Criteria are sent back in the
     * stored (web UI) shape; `ui_options.stashy.liveFragment` is kept (or `{}`), other
     * `ui_options` keys are preserved.
     */
    fun renameInput(entry: FiltersToolEntry, newName: String): JsonObject? {
        val name = newName.trim()
        if (name.isEmpty()) return null
        val f = entry.filter
        val (sortField, direction) = encodedSortPair(entry) ?: ("date" to "DESC")
        val ui = f.uiOptions as? JsonObject ?: JsonObject(emptyMap())
        val stashy = ui["stashy"] as? JsonObject ?: JsonObject(emptyMap())
        val newStashy = JsonObject(stashy + ("liveFragment" to (stashy["liveFragment"] as? JsonObject ?: JsonObject(emptyMap()))))
        return buildJsonObject {
            put("id", JsonPrimitive(f.id))
            put("mode", JsonPrimitive(normalizedMode(f.mode)))
            put("name", JsonPrimitive(name))
            put("find_filter", buildJsonObject {
                put("sort", JsonPrimitive(sortField))
                put("direction", JsonPrimitive(direction))
            })
            put("object_filter", filterDict(entry) ?: JsonObject(emptyMap()))
            put("ui_options", JsonObject(ui + ("stashy" to newStashy)))
        }
    }

    /** Parses one `findSavedFilters` row into an entry (keeps the legacy `filter` string). */
    fun entry(row: JsonElement): FiltersToolEntry? {
        val obj = row as? JsonObject ?: return null
        val filter = runCatching { Json.decodeFromJsonElement(SavedFilter.serializer(), obj) }.getOrNull() ?: return null
        val legacy = (obj["filter"] as? JsonPrimitive)?.contentOrNull
        return FiltersToolEntry(filter, legacy)
    }

    fun entries(rows: JsonArray): List<FiltersToolEntry> = rows.mapNotNull { entry(it) }

    /** iOS: `FilterFieldCatalog` labels per mode (generated from `FilterFieldCatalog.swift`). */
    val fieldLabels: Map<String, Map<String, String>> = mapOf(
        "SCENES" to mapOf(
            "id" to "ID",
            "title" to "Title",
            "code" to "Code",
            "details" to "Details",
            "director" to "Director",
            "oshash" to "OSHash",
            "checksum" to "Checksum",
            "phash_distance" to "PHash distance",
            "path" to "Path",
            "file_count" to "File count",
            "rating100" to "Rating",
            "organized" to "Organized",
            "o_counter" to "O-Count",
            "duplicated" to "Duplicated",
            "resolution" to "Resolution",
            "orientation" to "Orientation",
            "framerate" to "Framerate",
            "bitrate" to "Bitrate",
            "video_codec" to "Video codec",
            "audio_codec" to "Audio codec",
            "duration" to "Duration (s)",
            "has_markers" to "Has markers",
            "is_missing" to "Is missing",
            "studios" to "Studios",
            "groups" to "Groups",
            "galleries" to "Galleries",
            "tags" to "Tags",
            "tag_count" to "Tag count",
            "performer_tags" to "Performer tags",
            "performer_favorite" to "Performer favorite",
            "performer_age" to "Performer age",
            "performers" to "Performers",
            "performer_count" to "Performer count",
            "stash_ids_endpoint" to "Stash IDs",
            "stash_id_count" to "Stash ID count",
            "url" to "URL",
            "interactive" to "Interactive",
            "interactive_speed" to "Interactive speed",
            "captions" to "Captions",
            "resume_time" to "Resume time",
            "play_count" to "Play count",
            "play_duration" to "Play duration",
            "last_played_at" to "Last played",
            "date" to "Date",
            "production_date" to "Production date",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "galleries_filter" to "Galleries filter",
            "performers_filter" to "Performers filter",
            "studios_filter" to "Studios filter",
            "tags_filter" to "Tags filter",
            "groups_filter" to "Groups filter",
            "markers_filter" to "Markers filter",
            "files_filter" to "Files filter",
            "custom_fields" to "Custom fields",
            "movies" to "Movies",
            "phash" to "PHash",
            "stash_id_endpoint" to "Stash ID (legacy)",
            "movies_filter" to "Movies filter",
        ),
        "PERFORMERS" to mapOf(
            "name" to "Name",
            "disambiguation" to "Disambiguation",
            "details" to "Details",
            "filter_favorites" to "Favorite",
            "birth_year" to "Birth year",
            "age" to "Age",
            "ethnicity" to "Ethnicity",
            "country" to "Country",
            "eye_color" to "Eye color",
            "height_cm" to "Height (cm)",
            "measurements" to "Measurements",
            "fake_tits" to "Implants",
            "penis_length" to "Penis length",
            "circumcised" to "Circumcised",
            "career_length" to "Career length (years)",
            "career_start" to "Career start",
            "career_end" to "Career end",
            "tattoos" to "Tattoos",
            "piercings" to "Piercings",
            "aliases" to "Aliases",
            "gender" to "Gender",
            "is_missing" to "Is missing",
            "tags" to "Tags",
            "tag_count" to "Tag count",
            "scene_count" to "Scene count",
            "marker_count" to "Marker count",
            "image_count" to "Image count",
            "gallery_count" to "Gallery count",
            "play_count" to "Play count",
            "o_counter" to "O-Count",
            "stash_ids_endpoint" to "Stash IDs",
            "rating100" to "Rating",
            "url" to "URL",
            "hair_color" to "Hair color",
            "weight" to "Weight",
            "death_year" to "Death year",
            "studios" to "Studios",
            "groups" to "Groups",
            "performers" to "Performers",
            "ignore_auto_tag" to "Ignore auto-tag",
            "birthdate" to "Birthdate",
            "death_date" to "Death date",
            "scenes_filter" to "Scenes filter",
            "images_filter" to "Images filter",
            "galleries_filter" to "Galleries filter",
            "tags_filter" to "Tags filter",
            "markers_filter" to "Markers filter",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "custom_fields" to "Custom fields",
            "stash_id_endpoint" to "Stash ID (legacy)",
        ),
        "STUDIOS" to mapOf(
            "name" to "Name",
            "details" to "Details",
            "parents" to "Parents",
            "stash_ids_endpoint" to "Stash IDs",
            "tags" to "Tags",
            "is_missing" to "Is missing",
            "rating100" to "Rating",
            "favorite" to "Favorite",
            "scene_count" to "Scene count",
            "image_count" to "Image count",
            "gallery_count" to "Gallery count",
            "group_count" to "Group count",
            "tag_count" to "Tag count",
            "url" to "URL",
            "aliases" to "Aliases",
            "child_count" to "Child count",
            "ignore_auto_tag" to "Ignore auto-tag",
            "organized" to "Organized",
            "scenes_filter" to "Scenes filter",
            "images_filter" to "Images filter",
            "galleries_filter" to "Galleries filter",
            "groups_filter" to "Groups filter",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "custom_fields" to "Custom fields",
        ),
        "GALLERIES" to mapOf(
            "id" to "ID",
            "title" to "Title",
            "details" to "Details",
            "checksum" to "Checksum",
            "path" to "Path",
            "file_count" to "File count",
            "is_missing" to "Is missing",
            "is_zip" to "Is zip",
            "rating100" to "Rating",
            "organized" to "Organized",
            "average_resolution" to "Avg resolution",
            "has_chapters" to "Has chapters",
            "scenes" to "Scenes",
            "studios" to "Studios",
            "tags" to "Tags",
            "tag_count" to "Tag count",
            "performer_tags" to "Performer tags",
            "performers" to "Performers",
            "performer_count" to "Performer count",
            "performer_favorite" to "Performer favorite",
            "performer_age" to "Performer age",
            "image_count" to "Image count",
            "url" to "URL",
            "date" to "Date",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "code" to "Code",
            "photographer" to "Photographer",
            "scenes_filter" to "Scenes filter",
            "images_filter" to "Images filter",
            "performers_filter" to "Performers filter",
            "studios_filter" to "Studios filter",
            "tags_filter" to "Tags filter",
            "files_filter" to "Files filter",
            "custom_fields" to "Custom fields",
        ),
        "IMAGES" to mapOf(
            "title" to "Title",
            "details" to "Details",
            "id" to "ID",
            "checksum" to "Checksum",
            "phash_distance" to "PHash distance",
            "path" to "Path",
            "file_count" to "File count",
            "rating100" to "Rating",
            "date" to "Date",
            "url" to "URL",
            "organized" to "Organized",
            "o_counter" to "O-Count",
            "resolution" to "Resolution",
            "orientation" to "Orientation",
            "is_missing" to "Is missing",
            "studios" to "Studios",
            "tags" to "Tags",
            "tag_count" to "Tag count",
            "performer_tags" to "Performer tags",
            "performers" to "Performers",
            "performer_count" to "Performer count",
            "performer_favorite" to "Performer favorite",
            "performer_age" to "Performer age",
            "galleries" to "Galleries",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "code" to "Code",
            "photographer" to "Photographer",
            "galleries_filter" to "Galleries filter",
            "performers_filter" to "Performers filter",
            "studios_filter" to "Studios filter",
            "tags_filter" to "Tags filter",
            "files_filter" to "Files filter",
            "custom_fields" to "Custom fields",
        ),
        "TAGS" to mapOf(
            "name" to "Name",
            "sort_name" to "Sort name",
            "aliases" to "Aliases",
            "favorite" to "Favorite",
            "description" to "Description",
            "is_missing" to "Is missing",
            "scene_count" to "Scene count",
            "image_count" to "Image count",
            "gallery_count" to "Gallery count",
            "performer_count" to "Performer count",
            "studio_count" to "Studio count",
            "group_count" to "Group count",
            "marker_count" to "Marker count",
            "parents" to "Parents",
            "children" to "Children",
            "parent_count" to "Parent count",
            "child_count" to "Child count",
            "ignore_auto_tag" to "Ignore auto-tag",
            "stash_ids_endpoint" to "Stash IDs",
            "scenes_filter" to "Scenes filter",
            "images_filter" to "Images filter",
            "galleries_filter" to "Galleries filter",
            "groups_filter" to "Groups filter",
            "performers_filter" to "Performers filter",
            "studios_filter" to "Studios filter",
            "markers_filter" to "Markers filter",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "custom_fields" to "Custom fields",
        ),
        "GROUPS" to mapOf(
            "name" to "Name",
            "director" to "Director",
            "synopsis" to "Synopsis",
            "duration" to "Duration (s)",
            "rating100" to "Rating",
            "studios" to "Studios",
            "is_missing" to "Is missing",
            "url" to "URL",
            "performers" to "Performers",
            "tags" to "Tags",
            "tag_count" to "Tag count",
            "date" to "Date",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "o_counter" to "O-Count",
            "containing_groups" to "Containing groups",
            "sub_groups" to "Sub groups",
            "containing_group_count" to "Containing group count",
            "sub_group_count" to "Sub group count",
            "scene_count" to "Scene count",
            "scenes_filter" to "Scenes filter",
            "studios_filter" to "Studios filter",
            "custom_fields" to "Custom fields",
        ),
        "SCENE_MARKERS" to mapOf(
            "tags" to "Tags",
            "scene_tags" to "Scene tags",
            "performers" to "Performers",
            "scenes" to "Scenes",
            "duration" to "Duration (s)",
            "created_at" to "Created",
            "updated_at" to "Updated",
            "scene_date" to "Scene date",
            "scene_created_at" to "Scene created",
            "scene_updated_at" to "Scene updated",
            "scene_filter" to "Scene filter",
        ),
    )
}
