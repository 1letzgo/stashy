package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.util.Locale
import de.letzgo.stashy.data.CriterionKind.*

/** iOS: `StashDBViewModel.FilterMode` (raw values = Stash `FilterMode`). */
enum class FilterMode(val raw: String) {
    Scenes("SCENES"), Performers("PERFORMERS"), Studios("STUDIOS"), Galleries("GALLERIES"),
    Images("IMAGES"), Tags("TAGS"), Groups("GROUPS"), SceneMarkers("SCENE_MARKERS"), Unknown("UNKNOWN");

    companion object {
        fun from(raw: String?): FilterMode = entries.firstOrNull { it.raw == raw?.uppercase() } ?: Unknown
    }
}

/** iOS: `StashCriterionModifier` (filters.graphql `CriterionModifier`). */
enum class CriterionModifier(val raw: String, val label: String) {
    Equals("EQUALS", "Equals"), NotEquals("NOT_EQUALS", "Not equals"), GreaterThan("GREATER_THAN", "Greater than"),
    LessThan("LESS_THAN", "Less than"), IsNull("IS_NULL", "Is null"), NotNull("NOT_NULL", "Not null"),
    IncludesAll("INCLUDES_ALL", "Includes all"), Includes("INCLUDES", "Includes"), Excludes("EXCLUDES", "Excludes"),
    MatchesRegex("MATCHES_REGEX", "Matches regex"), NotMatchesRegex("NOT_MATCHES_REGEX", "Not matches regex"),
    Between("BETWEEN", "Between"), NotBetween("NOT_BETWEEN", "Not between");

    val needsValue: Boolean get() = this != IsNull && this != NotNull
    val needsSecondValue: Boolean get() = this == Between || this == NotBetween

    companion object {
        fun from(raw: String?): CriterionModifier? = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS: `FilterCriterionKind` (lower-case cases like Swift). */
enum class CriterionKind {
    string, int, float, boolean, date, timestamp, resolution, orientation, gender, circumcision,
    hierarchicalMulti, multi, stashID, stashIDs, phashDistance, duplication, customFields, isMissing,
    hasMarkers, hasChapters, hierarchicalCount, booleanGroup, nestedFilter, raw;

    val defaultModifiers: List<CriterionModifier> get() {
        return when (this) {
            string -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals, CriterionModifier.Includes, CriterionModifier.Excludes, CriterionModifier.MatchesRegex, CriterionModifier.NotMatchesRegex, CriterionModifier.IsNull, CriterionModifier.NotNull)
            int, float, hierarchicalCount, date, timestamp -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals, CriterionModifier.GreaterThan, CriterionModifier.LessThan, CriterionModifier.Between, CriterionModifier.NotBetween, CriterionModifier.IsNull, CriterionModifier.NotNull)
            resolution -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals, CriterionModifier.GreaterThan, CriterionModifier.LessThan)
            orientation, gender, circumcision -> listOf(CriterionModifier.Includes, CriterionModifier.Excludes, CriterionModifier.Equals, CriterionModifier.NotEquals)
            // No `EXCLUDES` - the picker's red state writes the `excludes` list instead.
            hierarchicalMulti, multi -> listOf(CriterionModifier.Includes, CriterionModifier.IncludesAll, CriterionModifier.IsNull, CriterionModifier.NotNull)
            stashID, stashIDs -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals, CriterionModifier.Includes, CriterionModifier.Excludes, CriterionModifier.IsNull, CriterionModifier.NotNull)
            phashDistance -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals)
            else -> emptyList()
        }
    }

    /** iOS: `FilterCriterionKind.defaultValue(for:nestedMode:mode:)`. */
    fun defaultValue(mode: FilterMode): JsonElement {
        fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(linkedMapOf(*pairs))
        fun s(v: String) = JsonPrimitive(v)
        return when (this) {
            boolean -> JsonPrimitive(true)
            string -> obj("value" to s(""), "modifier" to s("INCLUDES"))
            int, float, hierarchicalCount -> obj("value" to JsonPrimitive(0), "modifier" to s("EQUALS"))
            date, timestamp -> obj("value" to s(""), "modifier" to s("EQUALS"))
            resolution -> obj("value" to s("FULL_HD"), "modifier" to s("EQUALS"))
            orientation -> obj("value" to JsonArray(listOf(s("LANDSCAPE"))))
            gender -> obj("value_list" to JsonArray(listOf(s("FEMALE"))), "modifier" to s("INCLUDES"))
            circumcision -> obj("value" to JsonArray(listOf(s("CUT"))), "modifier" to s("INCLUDES"))
            hierarchicalMulti -> obj("value" to JsonArray(emptyList()), "modifier" to s("INCLUDES"), "depth" to JsonPrimitive(0))
            multi -> obj("value" to JsonArray(emptyList()), "modifier" to s("INCLUDES"))
            stashID, stashIDs -> obj("modifier" to s("NOT_NULL"))
            phashDistance -> obj("value" to s(""), "distance" to JsonPrimitive(0), "modifier" to s("EQUALS"))
            duplication -> obj("duplicated" to JsonPrimitive(true))
            customFields -> JsonArray(listOf(obj("field" to s(""), "value" to JsonArray(emptyList()), "modifier" to s("EQUALS"))))
            isMissing -> s(FilterFieldCatalog.isMissingOptions(mode).firstOrNull() ?: "title")
            hasMarkers, hasChapters -> s("true")
            booleanGroup, nestedFilter, raw -> JsonObject(emptyMap())
        }
    }
}

/** iOS: `StashResolutionOption`. */
enum class ResolutionOption(val raw: String, val label: String) {
    VeryLow("VERY_LOW", "144p"), Low("LOW", "240p"), R360p("R360P", "360p"), Standard("STANDARD", "480p"),
    WebHD("WEB_HD", "540p"), StandardHD("STANDARD_HD", "720p"), FullHD("FULL_HD", "1080p"), QuadHD("QUAD_HD", "1440p"),
    FourK("FOUR_K", "4K"), FiveK("FIVE_K", "5K"), SixK("SIX_K", "6K"), SevenK("SEVEN_K", "7K"), EightK("EIGHT_K", "8K"), Huge("HUGE", "8K+"),
}

/** iOS: `StashOrientationOption`. */
enum class OrientationOption(val raw: String, val label: String) { Landscape("LANDSCAPE", "Landscape"), Portrait("PORTRAIT", "Portrait"), Square("SQUARE", "Square") }

/** iOS: `StashGenderOption` (label = raw with spaces, capitalized). */
enum class GenderOption(val raw: String) {
    Male("MALE"), Female("FEMALE"), TransgenderMale("TRANSGENDER_MALE"), TransgenderFemale("TRANSGENDER_FEMALE"),
    Intersex("INTERSEX"), NonBinary("NON_BINARY");
    val label: String get() = capitalizeWords(raw.replace("_", " "))
}

/** Swift `String.capitalized`: first letter of every word upper, rest lower. */
fun capitalizeWords(s: String): String =
    s.split(" ").joinToString(" ") { w -> w.lowercase().replaceFirstChar { it.titlecase(Locale.ROOT) } }

/** iOS: `FilterEntityOption`. */
data class FilterEntityOption(val id: String, val name: String)

/** iOS: `FilterFieldDescriptor`. */
data class FilterFieldDescriptor(
    val key: String,
    val label: String,
    val kind: CriterionKind,
    val nestedMode: FilterMode? = null,
    val isDeprecated: Boolean = false,
)

/** iOS: `FilterFieldCatalog` — every criterion per mode, same keys/labels/order. */
object FilterFieldCatalog {
    private fun f(key: String, label: String, kind: CriterionKind, nested: FilterMode? = null, deprecated: Boolean = false) =
        FilterFieldDescriptor(key, label, kind, nested, deprecated)

    private val boolOps = listOf(
        f("AND", "AND", booleanGroup), f("OR", "OR", booleanGroup), f("NOT", "NOT", booleanGroup),
    )

    fun fields(mode: FilterMode): List<FilterFieldDescriptor> = when (mode) {
        FilterMode.Scenes -> sceneFields
        FilterMode.Performers -> performerFields
        FilterMode.Studios -> studioFields
        FilterMode.Galleries -> galleryFields
        FilterMode.Images -> imageFields
        FilterMode.Tags -> tagFields
        FilterMode.Groups -> groupFields
        FilterMode.SceneMarkers -> markerFields
        FilterMode.Unknown -> emptyList()
    }

    fun field(key: String, mode: FilterMode): FilterFieldDescriptor? = fields(mode).firstOrNull { it.key == key }

    fun addableFields(mode: FilterMode, excludingKeys: Set<String>): List<FilterFieldDescriptor> =
        fields(mode).filter { !it.isDeprecated && it.kind != CriterionKind.booleanGroup && it.key !in excludingKeys }

    private val sceneFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("id", "ID", int), f("title", "Title", string), f("code", "Code", string), f("details", "Details", string),
            f("director", "Director", string), f("oshash", "OSHash", string), f("checksum", "Checksum", string),
            f("phash_distance", "PHash distance", phashDistance), f("path", "Path", string), f("file_count", "File count", int),
            f("rating100", "Rating", int), f("organized", "Organized", boolean), f("o_counter", "O-Count", int),
            f("duplicated", "Duplicated", duplication), f("resolution", "Resolution", resolution),
            f("orientation", "Orientation", orientation), f("framerate", "Framerate", int), f("bitrate", "Bitrate", int),
            f("video_codec", "Video codec", string), f("audio_codec", "Audio codec", string), f("duration", "Duration (s)", int),
            f("has_markers", "Has markers", hasMarkers), f("is_missing", "Is missing", isMissing),
            f("studios", "Studios", hierarchicalMulti), f("groups", "Groups", hierarchicalMulti), f("galleries", "Galleries", multi),
            f("tags", "Tags", hierarchicalMulti), f("tag_count", "Tag count", int), f("performer_tags", "Performer tags", hierarchicalMulti),
            f("performer_favorite", "Performer favorite", boolean), f("performer_age", "Performer age", int),
            f("performers", "Performers", multi), f("performer_count", "Performer count", int),
            f("stash_ids_endpoint", "Stash IDs", stashIDs), f("stash_id_count", "Stash ID count", int), f("url", "URL", string),
            f("interactive", "Interactive", boolean), f("interactive_speed", "Interactive speed", int), f("captions", "Captions", string),
            f("resume_time", "Resume time", int), f("play_count", "Play count", int), f("play_duration", "Play duration", int),
            f("last_played_at", "Last played", timestamp), f("date", "Date", date), f("production_date", "Production date", date),
            f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp),
            f("galleries_filter", "Galleries filter", nestedFilter, FilterMode.Galleries),
            f("performers_filter", "Performers filter", nestedFilter, FilterMode.Performers),
            f("studios_filter", "Studios filter", nestedFilter, FilterMode.Studios),
            f("tags_filter", "Tags filter", nestedFilter, FilterMode.Tags),
            f("groups_filter", "Groups filter", nestedFilter, FilterMode.Groups),
            f("markers_filter", "Markers filter", nestedFilter, FilterMode.SceneMarkers),
            f("files_filter", "Files filter", raw), f("custom_fields", "Custom fields", customFields),
            f("movies", "Movies", multi, deprecated = true), f("phash", "PHash", string, deprecated = true),
            f("stash_id_endpoint", "Stash ID (legacy)", stashID, deprecated = true),
            f("movies_filter", "Movies filter", nestedFilter, FilterMode.Groups, deprecated = true),
        )
    }

    private val performerFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", "Name", string), f("disambiguation", "Disambiguation", string), f("details", "Details", string),
            f("filter_favorites", "Favorite", boolean), f("birth_year", "Birth year", int), f("age", "Age", int),
            f("ethnicity", "Ethnicity", string), f("country", "Country", string), f("eye_color", "Eye color", string),
            f("height_cm", "Height (cm)", int), f("measurements", "Measurements", string), f("fake_tits", "Implants", string),
            f("penis_length", "Penis length", float), f("circumcised", "Circumcised", circumcision),
            f("career_length", "Career length (years)", int), f("career_start", "Career start", date), f("career_end", "Career end", date),
            f("tattoos", "Tattoos", string), f("piercings", "Piercings", string), f("aliases", "Aliases", string),
            f("gender", "Gender", gender), f("is_missing", "Is missing", isMissing), f("tags", "Tags", hierarchicalMulti),
            f("tag_count", "Tag count", int), f("scene_count", "Scene count", int), f("marker_count", "Marker count", int),
            f("image_count", "Image count", int), f("gallery_count", "Gallery count", int), f("play_count", "Play count", int),
            f("o_counter", "O-Count", int), f("stash_ids_endpoint", "Stash IDs", stashIDs), f("rating100", "Rating", int),
            f("url", "URL", string), f("hair_color", "Hair color", string), f("weight", "Weight", int), f("death_year", "Death year", int),
            f("studios", "Studios", hierarchicalMulti), f("groups", "Groups", hierarchicalMulti), f("performers", "Performers", multi),
            f("ignore_auto_tag", "Ignore auto-tag", boolean), f("birthdate", "Birthdate", date), f("death_date", "Death date", date),
            f("scenes_filter", "Scenes filter", nestedFilter, FilterMode.Scenes),
            f("images_filter", "Images filter", nestedFilter, FilterMode.Images),
            f("galleries_filter", "Galleries filter", nestedFilter, FilterMode.Galleries),
            f("tags_filter", "Tags filter", nestedFilter, FilterMode.Tags),
            f("markers_filter", "Markers filter", nestedFilter, FilterMode.SceneMarkers),
            f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp), f("custom_fields", "Custom fields", customFields),
            f("stash_id_endpoint", "Stash ID (legacy)", stashID, deprecated = true),
        )
    }

    private val studioFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", "Name", string), f("details", "Details", string), f("parents", "Parents", multi),
            f("stash_ids_endpoint", "Stash IDs", stashIDs), f("tags", "Tags", hierarchicalMulti), f("is_missing", "Is missing", isMissing),
            f("rating100", "Rating", int), f("favorite", "Favorite", boolean), f("scene_count", "Scene count", int),
            f("image_count", "Image count", int), f("gallery_count", "Gallery count", int), f("group_count", "Group count", int),
            f("tag_count", "Tag count", int), f("url", "URL", string), f("aliases", "Aliases", string), f("child_count", "Child count", int),
            f("ignore_auto_tag", "Ignore auto-tag", boolean), f("organized", "Organized", boolean),
            f("scenes_filter", "Scenes filter", nestedFilter, FilterMode.Scenes),
            f("images_filter", "Images filter", nestedFilter, FilterMode.Images),
            f("galleries_filter", "Galleries filter", nestedFilter, FilterMode.Galleries),
            f("groups_filter", "Groups filter", nestedFilter, FilterMode.Groups),
            f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp), f("custom_fields", "Custom fields", customFields),
        )
    }

    private val galleryFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("id", "ID", int), f("title", "Title", string), f("details", "Details", string), f("checksum", "Checksum", string),
            f("path", "Path", string), f("file_count", "File count", int), f("is_missing", "Is missing", isMissing),
            f("is_zip", "Is zip", boolean), f("rating100", "Rating", int), f("organized", "Organized", boolean),
            f("average_resolution", "Avg resolution", resolution), f("has_chapters", "Has chapters", hasChapters),
            f("scenes", "Scenes", multi), f("studios", "Studios", hierarchicalMulti), f("tags", "Tags", hierarchicalMulti),
            f("tag_count", "Tag count", int), f("performer_tags", "Performer tags", hierarchicalMulti), f("performers", "Performers", multi),
            f("performer_count", "Performer count", int), f("performer_favorite", "Performer favorite", boolean),
            f("performer_age", "Performer age", int), f("image_count", "Image count", int), f("url", "URL", string),
            f("date", "Date", date), f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp),
            f("code", "Code", string), f("photographer", "Photographer", string),
            f("scenes_filter", "Scenes filter", nestedFilter, FilterMode.Scenes),
            f("images_filter", "Images filter", nestedFilter, FilterMode.Images),
            f("performers_filter", "Performers filter", nestedFilter, FilterMode.Performers),
            f("studios_filter", "Studios filter", nestedFilter, FilterMode.Studios),
            f("tags_filter", "Tags filter", nestedFilter, FilterMode.Tags),
            f("files_filter", "Files filter", raw), f("custom_fields", "Custom fields", customFields),
        )
    }

    private val imageFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("title", "Title", string), f("details", "Details", string), f("id", "ID", int), f("checksum", "Checksum", string),
            f("phash_distance", "PHash distance", phashDistance), f("path", "Path", string), f("file_count", "File count", int),
            f("rating100", "Rating", int), f("date", "Date", date), f("url", "URL", string), f("organized", "Organized", boolean),
            f("o_counter", "O-Count", int), f("resolution", "Resolution", resolution), f("orientation", "Orientation", orientation),
            f("is_missing", "Is missing", isMissing), f("studios", "Studios", hierarchicalMulti), f("tags", "Tags", hierarchicalMulti),
            f("tag_count", "Tag count", int), f("performer_tags", "Performer tags", hierarchicalMulti), f("performers", "Performers", multi),
            f("performer_count", "Performer count", int), f("performer_favorite", "Performer favorite", boolean),
            f("performer_age", "Performer age", int), f("galleries", "Galleries", multi), f("created_at", "Created", timestamp),
            f("updated_at", "Updated", timestamp), f("code", "Code", string), f("photographer", "Photographer", string),
            f("galleries_filter", "Galleries filter", nestedFilter, FilterMode.Galleries),
            f("performers_filter", "Performers filter", nestedFilter, FilterMode.Performers),
            f("studios_filter", "Studios filter", nestedFilter, FilterMode.Studios),
            f("tags_filter", "Tags filter", nestedFilter, FilterMode.Tags),
            f("files_filter", "Files filter", raw), f("custom_fields", "Custom fields", customFields),
        )
    }

    private val tagFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", "Name", string), f("sort_name", "Sort name", string), f("aliases", "Aliases", string),
            f("favorite", "Favorite", boolean), f("description", "Description", string), f("is_missing", "Is missing", isMissing),
            f("scene_count", "Scene count", hierarchicalCount), f("image_count", "Image count", hierarchicalCount),
            f("gallery_count", "Gallery count", hierarchicalCount), f("performer_count", "Performer count", hierarchicalCount),
            f("studio_count", "Studio count", hierarchicalCount), f("group_count", "Group count", hierarchicalCount),
            f("marker_count", "Marker count", hierarchicalCount), f("parents", "Parents", hierarchicalMulti),
            f("children", "Children", hierarchicalMulti), f("parent_count", "Parent count", int), f("child_count", "Child count", int),
            f("ignore_auto_tag", "Ignore auto-tag", boolean), f("stash_ids_endpoint", "Stash IDs", stashIDs),
            f("scenes_filter", "Scenes filter", nestedFilter, FilterMode.Scenes),
            f("images_filter", "Images filter", nestedFilter, FilterMode.Images),
            f("galleries_filter", "Galleries filter", nestedFilter, FilterMode.Galleries),
            f("groups_filter", "Groups filter", nestedFilter, FilterMode.Groups),
            f("performers_filter", "Performers filter", nestedFilter, FilterMode.Performers),
            f("studios_filter", "Studios filter", nestedFilter, FilterMode.Studios),
            f("markers_filter", "Markers filter", nestedFilter, FilterMode.SceneMarkers),
            f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp), f("custom_fields", "Custom fields", customFields),
        )
    }

    private val groupFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", "Name", string), f("director", "Director", string), f("synopsis", "Synopsis", string),
            f("duration", "Duration (s)", int), f("rating100", "Rating", int), f("studios", "Studios", hierarchicalMulti),
            f("is_missing", "Is missing", isMissing), f("url", "URL", string), f("performers", "Performers", multi),
            f("tags", "Tags", hierarchicalMulti), f("tag_count", "Tag count", int), f("date", "Date", date),
            f("created_at", "Created", timestamp), f("updated_at", "Updated", timestamp), f("o_counter", "O-Count", int),
            f("containing_groups", "Containing groups", hierarchicalMulti), f("sub_groups", "Sub groups", hierarchicalMulti),
            f("containing_group_count", "Containing group count", int), f("sub_group_count", "Sub group count", int),
            f("scene_count", "Scene count", int), f("scenes_filter", "Scenes filter", nestedFilter, FilterMode.Scenes),
            f("studios_filter", "Studios filter", nestedFilter, FilterMode.Studios), f("custom_fields", "Custom fields", customFields),
        )
    }

    private val markerFields: List<FilterFieldDescriptor> = run {
        listOf(
            f("tags", "Tags", hierarchicalMulti), f("scene_tags", "Scene tags", hierarchicalMulti), f("performers", "Performers", multi),
            f("scenes", "Scenes", multi), f("duration", "Duration (s)", float), f("created_at", "Created", timestamp),
            f("updated_at", "Updated", timestamp), f("scene_date", "Scene date", date), f("scene_created_at", "Scene created", timestamp),
            f("scene_updated_at", "Scene updated", timestamp), f("scene_filter", "Scene filter", nestedFilter, FilterMode.Scenes),
        )
    }

    /** iOS: `ValueSuggestion` — chip under a text criterion (`value` sent, `label` shown). */
    data class ValueSuggestion(val value: String, val label: String = value)

    fun valueSuggestions(key: String, mode: FilterMode): List<ValueSuggestion> = when {
        mode == FilterMode.Performers && key == "hair_color" -> listOf("Blonde", "Brunette", "Brown", "Black", "Red", "Auburn", "Grey", "White", "Bald", "Various").map { ValueSuggestion(it) }
        mode == FilterMode.Performers && key == "eye_color" -> listOf("Blue", "Brown", "Green", "Grey", "Hazel", "Amber").map { ValueSuggestion(it) }
        mode == FilterMode.Performers && key == "ethnicity" -> listOf("Caucasian", "Black", "Asian", "Indian", "Latin", "Middle Eastern", "Mixed", "Other").map { ValueSuggestion(it) }
        mode == FilterMode.Performers && key == "fake_tits" -> listOf("Natural", "Fake").map { ValueSuggestion(it) }
        mode == FilterMode.Performers && key == "country" -> countrySuggestions
        mode == FilterMode.Scenes && key == "video_codec" -> listOf("h264", "hevc", "av1", "vp9", "vp8", "mpeg4", "wmv3", "mpeg2video").map { ValueSuggestion(it) }
        mode == FilterMode.Scenes && key == "audio_codec" -> listOf("aac", "mp3", "ac3", "eac3", "opus", "vorbis", "flac", "pcm_s16le").map { ValueSuggestion(it) }
        mode == FilterMode.Scenes && key == "captions" -> listOf("en", "de", "fr", "es", "it", "ja", "ru", "pt").map { ValueSuggestion(it) }
        else -> emptyList()
    }

    private val countrySuggestions: List<ValueSuggestion> by lazy {
        val preferred = listOf("US", "GB", "DE", "CZ", "HU", "RU", "FR", "ES", "IT", "BR", "CA", "AU", "JP", "NL", "PL", "UA", "CO", "MX", "SE", "AT", "CH")
        fun name(code: String) = Locale("", code).displayCountry.takeIf { it.isNotBlank() } ?: code
        val rest = Locale.getISOCountries().filter { it.length == 2 && it !in preferred }
            .map { ValueSuggestion(it, name(it)) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
        preferred.map { ValueSuggestion(it, name(it)) } + rest
    }

    /** iOS: `isMissingOptions(for:)` — Stash's `is-missing.ts` lists per entity. */
    fun isMissingOptions(mode: FilterMode): List<String> = when (mode) {
        FilterMode.Scenes -> listOf("title", "code", "details", "director", "url", "date", "production_date", "rating",
            "cover", "galleries", "studio", "group", "performers", "tags", "stash_id")
        FilterMode.Images -> listOf("title", "details", "photographer", "url", "date", "code", "rating", "galleries", "studio", "performers", "tags")
        FilterMode.Performers -> listOf("image", "url", "details", "aliases", "gender", "birthdate", "death_date", "disambiguation",
            "ethnicity", "country", "hair_color", "eye_color", "height", "weight", "measurements", "fake_tits", "penis_length",
            "circumcised", "career_start", "career_end", "tattoos", "piercings", "tags", "rating", "stash_id")
        FilterMode.Galleries -> listOf("title", "code", "details", "photographer", "url", "date", "rating", "cover", "studio", "performers", "tags", "scenes")
        FilterMode.Tags -> listOf("image", "aliases", "description", "stash_id")
        FilterMode.Studios -> listOf("image", "stash_id", "details", "url", "aliases", "tags", "rating")
        FilterMode.Groups -> listOf("aliases", "description", "director", "date", "url", "rating", "studio", "performers", "tags", "front_image", "back_image", "scenes")
        FilterMode.SceneMarkers, FilterMode.Unknown -> emptyList()
    }

    /** iOS: `defaultCriterionKeys(for:)` — pinned rows the filter sheet always shows. */
    fun defaultCriterionKeys(mode: FilterMode): List<String> {
        val keys = when (mode) {
            FilterMode.Scenes -> listOf("tags", "performers", "studios", "rating100", "o_counter", "organized", "resolution")
            FilterMode.Performers -> listOf("filter_favorites", "gender", "age", "hair_color", "country", "fake_tits", "o_counter", "tags")
            FilterMode.Studios -> listOf("favorite", "rating100", "scene_count", "tags")
            FilterMode.Tags -> listOf("favorite", "scene_count", "image_count", "parents")
            FilterMode.Galleries -> listOf("tags", "performers", "studios", "rating100", "performer_favorite", "image_count")
            FilterMode.Images -> listOf("tags", "performers", "studios", "rating100", "o_counter", "organized")
            FilterMode.Groups -> listOf("studios", "tags", "performers", "rating100", "date")
            FilterMode.SceneMarkers -> listOf("tags", "scene_tags", "performers", "duration")
            FilterMode.Unknown -> emptyList()
        }
        val known = fields(mode).map { it.key }.toSet()
        return keys.filter { it in known }
    }
}

/** iOS: `FilterCriterionSummary` — one-liner for collapsed criterion cards. */
object FilterCriterionSummary {
    const val ANY = "Any"

    fun text(field: FilterFieldDescriptor, value: JsonElement?): String {
        if (value == null || value.isJsonNull) return ANY
        return when (field.kind) {
            CriterionKind.boolean -> value.boolOrNull?.let { if (it) "Yes" else "No" } ?: ANY
            CriterionKind.isMissing, CriterionKind.hasMarkers, CriterionKind.hasChapters -> {
                val s = value.stringValue?.takeIf { it.isNotEmpty() } ?: return ANY
                if (field.kind == CriterionKind.isMissing) capitalizeWords(s.replace("_", " ")) else if (s == "true") "Yes" else "No"
            }
            CriterionKind.booleanGroup -> ANY
            CriterionKind.nestedFilter, CriterionKind.raw -> {
                val n = (value as? JsonObject)?.size ?: 0
                if (n == 0) ANY else "$n criteria"
            }
            CriterionKind.customFields -> {
                val n = (value as? JsonArray)?.size ?: 0
                if (n == 0) ANY else "$n field(s)"
            }
            else -> (value as? JsonObject)?.let { dictSummary(field, it) } ?: ANY
        }
    }

    private fun dictSummary(field: FilterFieldDescriptor, dict: JsonObject): String {
        val modifier = CriterionModifier.from(dict["modifier"].stringValue)
        if (modifier == CriterionModifier.IsNull) return "Not set"
        if (modifier == CriterionModifier.NotNull) return "Any value"
        when (field.kind) {
            CriterionKind.hierarchicalMulti, CriterionKind.multi -> {
                val inc = FilterMapper.idStrings(dict["value"]).size
                val exc = FilterMapper.idStrings(dict["excludes"]).size
                if (inc == 0 && exc == 0) return ANY
                return listOfNotNull(if (inc > 0) "$inc selected" else null, if (exc > 0) "$exc excluded" else null).joinToString(", ")
            }
            CriterionKind.gender, CriterionKind.circumcision -> {
                val list = stringList(dict["value_list"]).ifEmpty { stringList(dict["value"]) }
                if (list.isEmpty()) dict["value"].stringValue?.let { return prettify(it) }
                if (list.isEmpty()) return ANY
                return list.joinToString(", ") { prettify(it) }
            }
            CriterionKind.orientation -> {
                val list = stringList(dict["value"])
                return if (list.isEmpty()) ANY else list.joinToString(", ") { prettify(it) }
            }
            CriterionKind.duplication -> {
                val dup = dict["duplicated"].boolOrNull ?: return ANY
                return if (dup) "Duplicated" else "Unique"
            }
            CriterionKind.stashID, CriterionKind.stashIDs -> return modifier?.label ?: ANY
            else -> {}
        }
        val value = displayValue(dict["value"])
        val value2 = displayValue(dict["value2"])
        if (value.isEmpty()) return ANY
        val symbol = compactModifier(modifier)
        if (value2.isNotEmpty() && modifier?.needsSecondValue == true) return "$symbol $value – $value2".trim()
        return if (symbol.isEmpty()) value else "$symbol $value"
    }

    private fun compactModifier(m: CriterionModifier?): String = when (m) {
        CriterionModifier.NotEquals -> "≠"
        CriterionModifier.GreaterThan -> ">"
        CriterionModifier.LessThan -> "<"
        CriterionModifier.NotBetween -> "not"
        CriterionModifier.Includes, CriterionModifier.IncludesAll -> "contains"
        CriterionModifier.Excludes -> "without"
        CriterionModifier.MatchesRegex -> "regex"
        CriterionModifier.NotMatchesRegex -> "not regex"
        else -> ""
    }

    private fun displayValue(raw: JsonElement?): String {
        raw.stringValue?.let { return it }
        val d = raw.numberOrNull ?: return ""
        return if (d == Math.floor(d)) d.toLong().toString() else d.toString()
    }

    private fun prettify(raw: String) = capitalizeWords(raw.replace("_", " "))

    fun stringList(el: JsonElement?): List<String> = (el as? JsonArray)?.mapNotNull { it.stringValue } ?: emptyList()
}

/** Builds `{ value, modifier }` criteria in code. */
fun criterion(value: Any?, modifier: String): JsonObject = buildJsonObject {
    if (value != null) put("value", value.toJson())
    put("modifier", JsonPrimitive(modifier))
}
