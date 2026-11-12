package de.letzgo.stashy.data.tools

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
        "SCENES" -> tr(R.string.scenes)
        "SCENE_MARKERS" -> tr(R.string.markers)
        "PERFORMERS" -> tr(R.string.performers)
        "STUDIOS" -> tr(R.string.studios)
        "TAGS" -> tr(R.string.tags)
        "GALLERIES" -> tr(R.string.galleries)
        "IMAGES" -> tr(R.string.images)
        "GROUPS" -> tr(R.string.groups)
        else -> tr(R.string.other)
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
        if (keys.isEmpty()) return tr(R.string.empty_criteria)
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
            "title" to tr(R.string.title),
            "code" to tr(R.string.code),
            "details" to tr(R.string.details),
            "director" to tr(R.string.director),
            "oshash" to "OSHash",
            "checksum" to tr(R.string.checksum),
            "phash_distance" to tr(R.string.phash_distance),
            "path" to tr(R.string.path),
            "file_count" to tr(R.string.file_count),
            "rating100" to tr(R.string.rating),
            "organized" to tr(R.string.organized),
            "o_counter" to tr(R.string.o_count),
            "duplicated" to tr(R.string.duplicated),
            "resolution" to tr(R.string.resolution),
            "orientation" to tr(R.string.orientation),
            "framerate" to tr(R.string.framerate),
            "bitrate" to tr(R.string.bitrate),
            "video_codec" to tr(R.string.video_codec),
            "audio_codec" to tr(R.string.audio_codec),
            "duration" to tr(R.string.duration_s),
            "has_markers" to tr(R.string.has_markers),
            "is_missing" to tr(R.string.is_missing),
            "studios" to tr(R.string.studios),
            "groups" to tr(R.string.groups),
            "galleries" to tr(R.string.galleries),
            "tags" to tr(R.string.tags),
            "tag_count" to tr(R.string.tag_count),
            "performer_tags" to tr(R.string.performer_tags),
            "performer_favorite" to tr(R.string.performer_favorite),
            "performer_age" to tr(R.string.performer_age),
            "performers" to tr(R.string.performers),
            "performer_count" to tr(R.string.performer_count),
            "stash_ids_endpoint" to tr(R.string.stash_ids),
            "stash_id_count" to tr(R.string.stash_id_count),
            "url" to "URL",
            "interactive" to tr(R.string.interactive),
            "interactive_speed" to tr(R.string.interactive_speed),
            "captions" to tr(R.string.captions),
            "resume_time" to tr(R.string.resume_time),
            "play_count" to tr(R.string.play_count),
            "play_duration" to tr(R.string.play_duration),
            "last_played_at" to tr(R.string.last_played),
            "date" to tr(R.string.date),
            "production_date" to tr(R.string.production_date),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "galleries_filter" to tr(R.string.galleries_filter),
            "performers_filter" to tr(R.string.performers_filter),
            "studios_filter" to tr(R.string.studios_filter),
            "tags_filter" to tr(R.string.tags_filter),
            "groups_filter" to tr(R.string.groups_filter),
            "markers_filter" to tr(R.string.markers_filter),
            "files_filter" to tr(R.string.files_filter),
            "custom_fields" to tr(R.string.custom_fields),
            "movies" to tr(R.string.movies),
            "phash" to "PHash",
            "stash_id_endpoint" to tr(R.string.stash_id_legacy),
            "movies_filter" to tr(R.string.movies_filter),
        ),
        "PERFORMERS" to mapOf(
            "name" to tr(R.string.name),
            "disambiguation" to tr(R.string.disambiguation),
            "details" to tr(R.string.details),
            "filter_favorites" to tr(R.string.favourite),
            "birth_year" to tr(R.string.birth_year),
            "age" to tr(R.string.age),
            "ethnicity" to tr(R.string.ethnicity),
            "country" to tr(R.string.country),
            "eye_color" to tr(R.string.eye_color),
            "height_cm" to tr(R.string.height_cm),
            "measurements" to tr(R.string.measurements),
            "fake_tits" to tr(R.string.implants),
            "penis_length" to tr(R.string.penis_length),
            "circumcised" to tr(R.string.circumcised),
            "career_length" to tr(R.string.career_length_years),
            "career_start" to tr(R.string.career_start),
            "career_end" to tr(R.string.career_end),
            "tattoos" to tr(R.string.tattoos),
            "piercings" to tr(R.string.piercings),
            "aliases" to tr(R.string.aliases),
            "gender" to tr(R.string.gender),
            "is_missing" to tr(R.string.is_missing),
            "tags" to tr(R.string.tags),
            "tag_count" to tr(R.string.tag_count),
            "scene_count" to tr(R.string.scene_count),
            "marker_count" to tr(R.string.marker_count),
            "image_count" to tr(R.string.image_count),
            "gallery_count" to tr(R.string.gallery_count),
            "play_count" to tr(R.string.play_count),
            "o_counter" to tr(R.string.o_count),
            "stash_ids_endpoint" to tr(R.string.stash_ids),
            "rating100" to tr(R.string.rating),
            "url" to "URL",
            "hair_color" to tr(R.string.hair_color),
            "weight" to tr(R.string.weight),
            "death_year" to tr(R.string.death_year),
            "studios" to tr(R.string.studios),
            "groups" to tr(R.string.groups),
            "performers" to tr(R.string.performers),
            "ignore_auto_tag" to tr(R.string.ignore_auto_tag),
            "birthdate" to tr(R.string.birthdate),
            "death_date" to tr(R.string.death_date),
            "scenes_filter" to tr(R.string.scenes_filter),
            "images_filter" to tr(R.string.images_filter),
            "galleries_filter" to tr(R.string.galleries_filter),
            "tags_filter" to tr(R.string.tags_filter),
            "markers_filter" to tr(R.string.markers_filter),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "custom_fields" to tr(R.string.custom_fields),
            "stash_id_endpoint" to tr(R.string.stash_id_legacy),
        ),
        "STUDIOS" to mapOf(
            "name" to tr(R.string.name),
            "details" to tr(R.string.details),
            "parents" to tr(R.string.parents),
            "stash_ids_endpoint" to tr(R.string.stash_ids),
            "tags" to tr(R.string.tags),
            "is_missing" to tr(R.string.is_missing),
            "rating100" to tr(R.string.rating),
            "favorite" to tr(R.string.favourite),
            "scene_count" to tr(R.string.scene_count),
            "image_count" to tr(R.string.image_count),
            "gallery_count" to tr(R.string.gallery_count),
            "group_count" to tr(R.string.group_count),
            "tag_count" to tr(R.string.tag_count),
            "url" to "URL",
            "aliases" to tr(R.string.aliases),
            "child_count" to tr(R.string.child_count),
            "ignore_auto_tag" to tr(R.string.ignore_auto_tag),
            "organized" to tr(R.string.organized),
            "scenes_filter" to tr(R.string.scenes_filter),
            "images_filter" to tr(R.string.images_filter),
            "galleries_filter" to tr(R.string.galleries_filter),
            "groups_filter" to tr(R.string.groups_filter),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "custom_fields" to tr(R.string.custom_fields),
        ),
        "GALLERIES" to mapOf(
            "id" to "ID",
            "title" to tr(R.string.title),
            "details" to tr(R.string.details),
            "checksum" to tr(R.string.checksum),
            "path" to tr(R.string.path),
            "file_count" to tr(R.string.file_count),
            "is_missing" to tr(R.string.is_missing),
            "is_zip" to tr(R.string.is_zip),
            "rating100" to tr(R.string.rating),
            "organized" to tr(R.string.organized),
            "average_resolution" to tr(R.string.avg_resolution),
            "has_chapters" to tr(R.string.has_chapters),
            "scenes" to tr(R.string.scenes),
            "studios" to tr(R.string.studios),
            "tags" to tr(R.string.tags),
            "tag_count" to tr(R.string.tag_count),
            "performer_tags" to tr(R.string.performer_tags),
            "performers" to tr(R.string.performers),
            "performer_count" to tr(R.string.performer_count),
            "performer_favorite" to tr(R.string.performer_favorite),
            "performer_age" to tr(R.string.performer_age),
            "image_count" to tr(R.string.image_count),
            "url" to "URL",
            "date" to tr(R.string.date),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "code" to tr(R.string.code),
            "photographer" to tr(R.string.photographer),
            "scenes_filter" to tr(R.string.scenes_filter),
            "images_filter" to tr(R.string.images_filter),
            "performers_filter" to tr(R.string.performers_filter),
            "studios_filter" to tr(R.string.studios_filter),
            "tags_filter" to tr(R.string.tags_filter),
            "files_filter" to tr(R.string.files_filter),
            "custom_fields" to tr(R.string.custom_fields),
        ),
        "IMAGES" to mapOf(
            "title" to tr(R.string.title),
            "details" to tr(R.string.details),
            "id" to "ID",
            "checksum" to tr(R.string.checksum),
            "phash_distance" to tr(R.string.phash_distance),
            "path" to tr(R.string.path),
            "file_count" to tr(R.string.file_count),
            "rating100" to tr(R.string.rating),
            "date" to tr(R.string.date),
            "url" to "URL",
            "organized" to tr(R.string.organized),
            "o_counter" to tr(R.string.o_count),
            "resolution" to tr(R.string.resolution),
            "orientation" to tr(R.string.orientation),
            "is_missing" to tr(R.string.is_missing),
            "studios" to tr(R.string.studios),
            "tags" to tr(R.string.tags),
            "tag_count" to tr(R.string.tag_count),
            "performer_tags" to tr(R.string.performer_tags),
            "performers" to tr(R.string.performers),
            "performer_count" to tr(R.string.performer_count),
            "performer_favorite" to tr(R.string.performer_favorite),
            "performer_age" to tr(R.string.performer_age),
            "galleries" to tr(R.string.galleries),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "code" to tr(R.string.code),
            "photographer" to tr(R.string.photographer),
            "galleries_filter" to tr(R.string.galleries_filter),
            "performers_filter" to tr(R.string.performers_filter),
            "studios_filter" to tr(R.string.studios_filter),
            "tags_filter" to tr(R.string.tags_filter),
            "files_filter" to tr(R.string.files_filter),
            "custom_fields" to tr(R.string.custom_fields),
        ),
        "TAGS" to mapOf(
            "name" to tr(R.string.name),
            "sort_name" to tr(R.string.sort_name),
            "aliases" to tr(R.string.aliases),
            "favorite" to tr(R.string.favourite),
            "description" to tr(R.string.description),
            "is_missing" to tr(R.string.is_missing),
            "scene_count" to tr(R.string.scene_count),
            "image_count" to tr(R.string.image_count),
            "gallery_count" to tr(R.string.gallery_count),
            "performer_count" to tr(R.string.performer_count),
            "studio_count" to tr(R.string.studio_count),
            "group_count" to tr(R.string.group_count),
            "marker_count" to tr(R.string.marker_count),
            "parents" to tr(R.string.parents),
            "children" to tr(R.string.children),
            "parent_count" to tr(R.string.parent_count),
            "child_count" to tr(R.string.child_count),
            "ignore_auto_tag" to tr(R.string.ignore_auto_tag),
            "stash_ids_endpoint" to tr(R.string.stash_ids),
            "scenes_filter" to tr(R.string.scenes_filter),
            "images_filter" to tr(R.string.images_filter),
            "galleries_filter" to tr(R.string.galleries_filter),
            "groups_filter" to tr(R.string.groups_filter),
            "performers_filter" to tr(R.string.performers_filter),
            "studios_filter" to tr(R.string.studios_filter),
            "markers_filter" to tr(R.string.markers_filter),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "custom_fields" to tr(R.string.custom_fields),
        ),
        "GROUPS" to mapOf(
            "name" to tr(R.string.name),
            "director" to tr(R.string.director),
            "synopsis" to tr(R.string.synopsis),
            "duration" to tr(R.string.duration_s),
            "rating100" to tr(R.string.rating),
            "studios" to tr(R.string.studios),
            "is_missing" to tr(R.string.is_missing),
            "url" to "URL",
            "performers" to tr(R.string.performers),
            "tags" to tr(R.string.tags),
            "tag_count" to tr(R.string.tag_count),
            "date" to tr(R.string.date),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "o_counter" to tr(R.string.o_count),
            "containing_groups" to tr(R.string.containing_groups),
            "sub_groups" to tr(R.string.sub_groups),
            "containing_group_count" to tr(R.string.containing_group_count),
            "sub_group_count" to tr(R.string.sub_group_count),
            "scene_count" to tr(R.string.scene_count),
            "scenes_filter" to tr(R.string.scenes_filter),
            "studios_filter" to tr(R.string.studios_filter),
            "custom_fields" to tr(R.string.custom_fields),
        ),
        "SCENE_MARKERS" to mapOf(
            "tags" to tr(R.string.tags),
            "scene_tags" to tr(R.string.scene_tags),
            "performers" to tr(R.string.performers),
            "scenes" to tr(R.string.scenes),
            "duration" to tr(R.string.duration_s),
            "created_at" to tr(R.string.created),
            "updated_at" to tr(R.string.updated),
            "scene_date" to tr(R.string.scene_date),
            "scene_created_at" to tr(R.string.scene_created),
            "scene_updated_at" to tr(R.string.scene_updated),
            "scene_filter" to tr(R.string.scene_filter),
        ),
    )
}
