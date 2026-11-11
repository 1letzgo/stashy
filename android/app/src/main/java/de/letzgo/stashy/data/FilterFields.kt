package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
enum class CriterionModifier(val raw: String, @androidx.annotation.StringRes private val labelRes: Int) {
    Equals("EQUALS", R.string.equals), NotEquals("NOT_EQUALS", R.string.not_equals), GreaterThan("GREATER_THAN", R.string.greater_than),
    LessThan("LESS_THAN", R.string.less_than), IsNull("IS_NULL", R.string.is_null), NotNull("NOT_NULL", R.string.not_null),
    IncludesAll("INCLUDES_ALL", R.string.includes_all), Includes("INCLUDES", R.string.includes), Excludes("EXCLUDES", R.string.excludes),
    MatchesRegex("MATCHES_REGEX", R.string.matches_regex), NotMatchesRegex("NOT_MATCHES_REGEX", R.string.not_matches_regex),
    Between("BETWEEN", R.string.between), NotBetween("NOT_BETWEEN", R.string.not_between);
    /** Read on use: a constant must not freeze its text at class load. */
    val label: String get() = tr(labelRes)

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
            int, float, hierarchicalCount, date -> listOf(CriterionModifier.Equals, CriterionModifier.NotEquals, CriterionModifier.GreaterThan, CriterionModifier.LessThan, CriterionModifier.Between, CriterionModifier.NotBetween, CriterionModifier.IsNull, CriterionModifier.NotNull)
            // Stash's MandatoryTimestamp set (created / updated / last played).
            timestamp -> listOf(CriterionModifier.GreaterThan, CriterionModifier.LessThan, CriterionModifier.Between, CriterionModifier.NotBetween)
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
            date -> obj("value" to s(""), "modifier" to s("EQUALS"))
            // Complete from the start (today 00:00), so the row is never dropped as half-filled.
            timestamp -> obj("value" to s(FilterTimestampFormat.format(java.time.LocalDate.now().atStartOfDay())), "modifier" to s("GREATER_THAN"))
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

/** GraphQL `Timestamp` text the app writes ("2024-01-31T13:45", local time, like the web UI). */
object FilterTimestampFormat {
    private val formatter = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm", Locale.US)

    fun format(dateTime: java.time.LocalDateTime): String = dateTime.format(formatter)

    /** Accepts "2024-01-31T13:45", "2024-01-31 13:45" (web UI) and a bare date. */
    fun parse(text: String): java.time.LocalDateTime? {
        val t = text.trim().replace(" ", "T")
        runCatching { return java.time.LocalDateTime.parse(t.take(16), formatter) }
        return runCatching { java.time.LocalDate.parse(t.take(10)).atStartOfDay() }.getOrNull()
    }
}

/** iOS: `StashResolutionOption`. */
enum class ResolutionOption(val raw: String, val label: String) {
    VeryLow("VERY_LOW", "144p"), Low("LOW", "240p"), R360p("R360P", "360p"), Standard("STANDARD", "480p"),
    WebHD("WEB_HD", "540p"), StandardHD("STANDARD_HD", "720p"), FullHD("FULL_HD", "1080p"), QuadHD("QUAD_HD", "1440p"),
    FourK("FOUR_K", "4K"), FiveK("FIVE_K", "5K"), SixK("SIX_K", "6K"), SevenK("SEVEN_K", "7K"), EightK("EIGHT_K", "8K"), Huge("HUGE", "8K+"),
}

/** iOS: `StashOrientationOption`. */
enum class OrientationOption(val raw: String, @androidx.annotation.StringRes private val labelRes: Int) { Landscape("LANDSCAPE", R.string.landscape), Portrait("PORTRAIT", R.string.portrait), Square("SQUARE", R.string.square);

    /** Read on use: a constant must not freeze its text at class load. */
    val label: String get() = tr(labelRes)
}

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
        FilterMode.Scenes -> availableOnServer(sceneFields)
        FilterMode.Performers -> performerFields
        FilterMode.Studios -> studioFields
        FilterMode.Galleries -> availableOnServer(galleryFields)
        FilterMode.Images -> availableOnServer(imageFields)
        FilterMode.Tags -> tagFields
        FilterMode.Groups -> groupFields
        FilterMode.SceneMarkers -> markerFields
        FilterMode.Unknown -> emptyList()
    }

    /** Fields only Stash 0.32+ knows; an older server rejects the whole query over one of them. */
    private val stash032Keys = setOf("production_date", "folder", "parent_folder")

    private fun availableOnServer(fields: List<FilterFieldDescriptor>): List<FilterFieldDescriptor> =
        if (ServerCapabilities.supports032) fields else fields.filter { it.key !in stash032Keys }

    fun field(key: String, mode: FilterMode): FilterFieldDescriptor? = fields(mode).firstOrNull { it.key == key }

    /**
     * Fields the user can still add. The multi Stash ID list is covered by "Stash ID". Sub-filters
     * and the raw files filter are offered, marked "App only" in the menu: the web UI drops them
     * when it re-saves a filter.
     */
    fun addableFields(mode: FilterMode, excludingKeys: Set<String>): List<FilterFieldDescriptor> =
        fields(mode).filter {
            !it.isDeprecated && it.kind != CriterionKind.booleanGroup && it.key !in excludingKeys &&
                it.kind != CriterionKind.stashIDs
        }

    private val sceneFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("id", "ID", int), f("title", tr(R.string.title), string), f("code", tr(R.string.code), string), f("details", tr(R.string.details), string),
            f("director", tr(R.string.director), string), f("oshash", "OSHash", string), f("checksum", tr(R.string.checksum), string),
            f("phash_distance", tr(R.string.phash_distance), phashDistance), f("path", tr(R.string.path), string), f("file_count", tr(R.string.file_count), int),
            f("rating100", tr(R.string.rating), int), f("organized", tr(R.string.organized), boolean), f("o_counter", tr(R.string.o_count), int),
            f("duplicated", tr(R.string.duplicated), duplication), f("resolution", tr(R.string.resolution), resolution),
            f("orientation", tr(R.string.orientation), orientation), f("framerate", tr(R.string.framerate), int), f("bitrate", tr(R.string.bitrate), int),
            f("video_codec", tr(R.string.video_codec), string), f("audio_codec", tr(R.string.audio_codec), string), f("duration", tr(R.string.duration_s), int),
            f("has_markers", tr(R.string.has_markers), hasMarkers), f("is_missing", tr(R.string.is_missing), isMissing),
            f("studios", tr(R.string.studios), hierarchicalMulti), f("groups", tr(R.string.groups), hierarchicalMulti), f("galleries", tr(R.string.galleries), multi),
            f("tags", tr(R.string.tags), hierarchicalMulti), f("tag_count", tr(R.string.tag_count), int), f("performer_tags", tr(R.string.performer_tags), hierarchicalMulti),
            f("performer_favorite", tr(R.string.performer_favorite), boolean), f("performer_age", tr(R.string.performer_age), int),
            f("performers", tr(R.string.performers), multi), f("performer_count", tr(R.string.performer_count), int),
            f("stash_ids_endpoint", tr(R.string.stash_ids), stashIDs), f("stash_id_count", tr(R.string.stash_id_count), int), f("url", "URL", string),
            f("interactive", tr(R.string.interactive), boolean), f("interactive_speed", tr(R.string.interactive_speed), int), f("captions", tr(R.string.captions), string),
            f("resume_time", tr(R.string.resume_time), int), f("play_count", tr(R.string.play_count), int), f("play_duration", tr(R.string.play_duration), int),
            f("last_played_at", tr(R.string.last_played), timestamp), f("date", tr(R.string.date), date), f("production_date", tr(R.string.production_date), date),
            f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp),
            f("galleries_filter", tr(R.string.galleries_filter), nestedFilter, FilterMode.Galleries),
            f("performers_filter", tr(R.string.performers_filter), nestedFilter, FilterMode.Performers),
            f("studios_filter", tr(R.string.studios_filter), nestedFilter, FilterMode.Studios),
            f("tags_filter", tr(R.string.tags_filter), nestedFilter, FilterMode.Tags),
            f("groups_filter", tr(R.string.groups_filter), nestedFilter, FilterMode.Groups),
            f("markers_filter", tr(R.string.markers_filter), nestedFilter, FilterMode.SceneMarkers),
            f("folder", tr(R.string.folder), hierarchicalMulti),
            f("files_filter", tr(R.string.files_filter), raw), f("custom_fields", tr(R.string.custom_fields), customFields),
            f("movies", tr(R.string.movies), multi, deprecated = true), f("phash", "PHash", string, deprecated = true),
            f("stash_id_endpoint", tr(R.string.stash_id), stashID),
            f("movies_filter", tr(R.string.movies_filter), nestedFilter, FilterMode.Groups, deprecated = true),
        )
    }

    private val performerFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", tr(R.string.name), string), f("disambiguation", tr(R.string.disambiguation), string), f("details", tr(R.string.details), string),
            f("filter_favorites", tr(R.string.favourite), boolean), f("birth_year", tr(R.string.birth_year), int), f("age", tr(R.string.age), int),
            f("ethnicity", tr(R.string.ethnicity), string), f("country", tr(R.string.country), string), f("eye_color", tr(R.string.eye_color), string),
            f("height_cm", tr(R.string.height_cm), int), f("measurements", tr(R.string.measurements), string), f("fake_tits", tr(R.string.implants), string),
            f("penis_length", tr(R.string.penis_length), float), f("circumcised", tr(R.string.circumcised), circumcision),
            f("career_start", tr(R.string.career_start), date), f("career_end", tr(R.string.career_end), date),
            f("tattoos", tr(R.string.tattoos), string), f("piercings", tr(R.string.piercings), string), f("aliases", tr(R.string.aliases), string),
            f("gender", tr(R.string.gender), gender), f("is_missing", tr(R.string.is_missing), isMissing), f("tags", tr(R.string.tags), hierarchicalMulti),
            f("tag_count", tr(R.string.tag_count), int), f("scene_count", tr(R.string.scene_count), int), f("marker_count", tr(R.string.marker_count), int),
            f("image_count", tr(R.string.image_count), int), f("gallery_count", tr(R.string.gallery_count), int), f("play_count", tr(R.string.play_count), int),
            f("o_counter", tr(R.string.o_count), int), f("stash_ids_endpoint", tr(R.string.stash_ids), stashIDs), f("rating100", tr(R.string.rating), int),
            f("url", "URL", string), f("hair_color", tr(R.string.hair_color), string), f("weight", tr(R.string.weight), int), f("death_year", tr(R.string.death_year), int),
            f("studios", tr(R.string.studios), hierarchicalMulti), f("groups", tr(R.string.groups), hierarchicalMulti), f("performers", tr(R.string.performers), multi),
            f("ignore_auto_tag", tr(R.string.ignore_auto_tag), boolean), f("birthdate", tr(R.string.birthdate), date), f("death_date", tr(R.string.death_date), date),
            f("scenes_filter", tr(R.string.scenes_filter), nestedFilter, FilterMode.Scenes),
            f("images_filter", tr(R.string.images_filter), nestedFilter, FilterMode.Images),
            f("galleries_filter", tr(R.string.galleries_filter), nestedFilter, FilterMode.Galleries),
            f("tags_filter", tr(R.string.tags_filter), nestedFilter, FilterMode.Tags),
            f("markers_filter", tr(R.string.markers_filter), nestedFilter, FilterMode.SceneMarkers),
            f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp), f("custom_fields", tr(R.string.custom_fields), customFields),
            f("stash_id_endpoint", tr(R.string.stash_id), stashID),
        )
    }

    private val studioFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", tr(R.string.name), string), f("details", tr(R.string.details), string), f("parents", tr(R.string.parents), multi),
            f("stash_ids_endpoint", tr(R.string.stash_ids), stashIDs), f("stash_id_endpoint", tr(R.string.stash_id), stashID),
            f("tags", tr(R.string.tags), hierarchicalMulti), f("is_missing", tr(R.string.is_missing), isMissing),
            f("rating100", tr(R.string.rating), int), f("favorite", tr(R.string.favourite), boolean), f("scene_count", tr(R.string.scene_count), int),
            f("image_count", tr(R.string.image_count), int), f("gallery_count", tr(R.string.gallery_count), int), f("group_count", tr(R.string.group_count), int),
            f("tag_count", tr(R.string.tag_count), int), f("url", "URL", string), f("aliases", tr(R.string.aliases), string), f("child_count", tr(R.string.child_count), int),
            f("ignore_auto_tag", tr(R.string.ignore_auto_tag), boolean), f("organized", tr(R.string.organized), boolean),
            f("scenes_filter", tr(R.string.scenes_filter), nestedFilter, FilterMode.Scenes),
            f("images_filter", tr(R.string.images_filter), nestedFilter, FilterMode.Images),
            f("galleries_filter", tr(R.string.galleries_filter), nestedFilter, FilterMode.Galleries),
            f("groups_filter", tr(R.string.groups_filter), nestedFilter, FilterMode.Groups),
            f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp), f("custom_fields", tr(R.string.custom_fields), customFields),
        )
    }

    private val galleryFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("id", "ID", int), f("title", tr(R.string.title), string), f("details", tr(R.string.details), string), f("checksum", tr(R.string.checksum), string),
            f("path", tr(R.string.path), string), f("file_count", tr(R.string.file_count), int), f("is_missing", tr(R.string.is_missing), isMissing),
            f("is_zip", tr(R.string.is_zip), boolean), f("rating100", tr(R.string.rating), int), f("organized", tr(R.string.organized), boolean),
            f("average_resolution", tr(R.string.avg_resolution), resolution), f("has_chapters", tr(R.string.has_chapters), hasChapters),
            f("scenes", tr(R.string.scenes), multi), f("studios", tr(R.string.studios), hierarchicalMulti), f("tags", tr(R.string.tags), hierarchicalMulti),
            f("tag_count", tr(R.string.tag_count), int), f("performer_tags", tr(R.string.performer_tags), hierarchicalMulti), f("performers", tr(R.string.performers), multi),
            f("performer_count", tr(R.string.performer_count), int), f("performer_favorite", tr(R.string.performer_favorite), boolean),
            f("performer_age", tr(R.string.performer_age), int), f("image_count", tr(R.string.image_count), int), f("url", "URL", string),
            f("date", tr(R.string.date), date), f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp),
            f("code", tr(R.string.code), string), f("photographer", tr(R.string.photographer), string),
            f("scenes_filter", tr(R.string.scenes_filter), nestedFilter, FilterMode.Scenes),
            f("images_filter", tr(R.string.images_filter), nestedFilter, FilterMode.Images),
            f("performers_filter", tr(R.string.performers_filter), nestedFilter, FilterMode.Performers),
            f("studios_filter", tr(R.string.studios_filter), nestedFilter, FilterMode.Studios),
            f("tags_filter", tr(R.string.tags_filter), nestedFilter, FilterMode.Tags),
            f("parent_folder", tr(R.string.folder), hierarchicalMulti),
            f("files_filter", tr(R.string.files_filter), raw), f("custom_fields", tr(R.string.custom_fields), customFields),
        )
    }

    private val imageFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("title", tr(R.string.title), string), f("details", tr(R.string.details), string), f("id", "ID", int), f("checksum", tr(R.string.checksum), string),
            f("phash_distance", tr(R.string.phash_distance), phashDistance), f("path", tr(R.string.path), string), f("file_count", tr(R.string.file_count), int),
            f("rating100", tr(R.string.rating), int), f("date", tr(R.string.date), date), f("url", "URL", string), f("organized", tr(R.string.organized), boolean),
            f("o_counter", tr(R.string.o_count), int), f("resolution", tr(R.string.resolution), resolution), f("orientation", tr(R.string.orientation), orientation),
            f("is_missing", tr(R.string.is_missing), isMissing), f("studios", tr(R.string.studios), hierarchicalMulti), f("tags", tr(R.string.tags), hierarchicalMulti),
            f("tag_count", tr(R.string.tag_count), int), f("performer_tags", tr(R.string.performer_tags), hierarchicalMulti), f("performers", tr(R.string.performers), multi),
            f("performer_count", tr(R.string.performer_count), int), f("performer_favorite", tr(R.string.performer_favorite), boolean),
            f("performer_age", tr(R.string.performer_age), int), f("galleries", tr(R.string.galleries), multi), f("created_at", tr(R.string.created), timestamp),
            f("updated_at", tr(R.string.updated), timestamp), f("code", tr(R.string.code), string), f("photographer", tr(R.string.photographer), string),
            f("galleries_filter", tr(R.string.galleries_filter), nestedFilter, FilterMode.Galleries),
            f("performers_filter", tr(R.string.performers_filter), nestedFilter, FilterMode.Performers),
            f("studios_filter", tr(R.string.studios_filter), nestedFilter, FilterMode.Studios),
            f("tags_filter", tr(R.string.tags_filter), nestedFilter, FilterMode.Tags),
            f("folder", tr(R.string.folder), hierarchicalMulti),
            f("files_filter", tr(R.string.files_filter), raw), f("custom_fields", tr(R.string.custom_fields), customFields),
        )
    }

    private val tagFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", tr(R.string.name), string), f("sort_name", tr(R.string.sort_name), string), f("aliases", tr(R.string.aliases), string),
            f("favorite", tr(R.string.favourite), boolean), f("description", tr(R.string.description), string), f("is_missing", tr(R.string.is_missing), isMissing),
            f("scene_count", tr(R.string.scene_count), hierarchicalCount), f("image_count", tr(R.string.image_count), hierarchicalCount),
            f("gallery_count", tr(R.string.gallery_count), hierarchicalCount), f("performer_count", tr(R.string.performer_count), hierarchicalCount),
            f("studio_count", tr(R.string.studio_count), hierarchicalCount), f("group_count", tr(R.string.group_count), hierarchicalCount),
            f("marker_count", tr(R.string.marker_count), hierarchicalCount), f("parents", tr(R.string.parents), hierarchicalMulti),
            f("children", tr(R.string.children), hierarchicalMulti), f("parent_count", tr(R.string.parent_count), int), f("child_count", tr(R.string.child_count), int),
            f("ignore_auto_tag", tr(R.string.ignore_auto_tag), boolean), f("stash_ids_endpoint", tr(R.string.stash_ids), stashIDs),
            f("stash_id_endpoint", tr(R.string.stash_id), stashID),
            f("scenes_filter", tr(R.string.scenes_filter), nestedFilter, FilterMode.Scenes),
            f("images_filter", tr(R.string.images_filter), nestedFilter, FilterMode.Images),
            f("galleries_filter", tr(R.string.galleries_filter), nestedFilter, FilterMode.Galleries),
            f("groups_filter", tr(R.string.groups_filter), nestedFilter, FilterMode.Groups),
            f("performers_filter", tr(R.string.performers_filter), nestedFilter, FilterMode.Performers),
            f("studios_filter", tr(R.string.studios_filter), nestedFilter, FilterMode.Studios),
            f("markers_filter", tr(R.string.markers_filter), nestedFilter, FilterMode.SceneMarkers),
            f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp), f("custom_fields", tr(R.string.custom_fields), customFields),
        )
    }

    private val groupFields: List<FilterFieldDescriptor> = run {
        boolOps + listOf(
            f("name", tr(R.string.name), string), f("director", tr(R.string.director), string), f("synopsis", tr(R.string.synopsis), string),
            f("duration", tr(R.string.duration_s), int), f("rating100", tr(R.string.rating), int), f("studios", tr(R.string.studios), hierarchicalMulti),
            f("is_missing", tr(R.string.is_missing), isMissing), f("url", "URL", string), f("performers", tr(R.string.performers), multi),
            f("tags", tr(R.string.tags), hierarchicalMulti), f("tag_count", tr(R.string.tag_count), int), f("date", tr(R.string.date), date),
            f("created_at", tr(R.string.created), timestamp), f("updated_at", tr(R.string.updated), timestamp), f("o_counter", tr(R.string.o_count), int),
            f("containing_groups", tr(R.string.containing_groups), hierarchicalMulti), f("sub_groups", "Sub-Groups", hierarchicalMulti),
            f("containing_group_count", tr(R.string.containing_group_count), int), f("sub_group_count", tr(R.string.sub_group_count), int),
            f("scene_count", tr(R.string.scene_count), int), f("scenes_filter", tr(R.string.scenes_filter), nestedFilter, FilterMode.Scenes),
            f("studios_filter", tr(R.string.studios_filter), nestedFilter, FilterMode.Studios), f("custom_fields", tr(R.string.custom_fields), customFields),
        )
    }

    private val markerFields: List<FilterFieldDescriptor> = run {
        listOf(
            f("tags", tr(R.string.tags), hierarchicalMulti), f("scene_tags", tr(R.string.scene_tags), hierarchicalMulti), f("performers", tr(R.string.performers), multi),
            f("scenes", tr(R.string.scenes), multi), f("duration", tr(R.string.duration_s), float), f("created_at", tr(R.string.created), timestamp),
            f("updated_at", tr(R.string.updated), timestamp), f("scene_date", tr(R.string.scene_date), date), f("scene_created_at", tr(R.string.scene_created), timestamp),
            f("scene_updated_at", tr(R.string.scene_updated), timestamp), f("scene_filter", tr(R.string.scene_filter), nestedFilter, FilterMode.Scenes),
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
    val ANY = tr(R.string.any)

    fun text(field: FilterFieldDescriptor, value: JsonElement?): String {
        if (value == null || value.isJsonNull) return ANY
        return when (field.kind) {
            CriterionKind.boolean -> value.boolOrNull?.let { if (it) tr(R.string.yes) else tr(R.string.no) } ?: ANY
            CriterionKind.isMissing, CriterionKind.hasMarkers, CriterionKind.hasChapters -> {
                val s = value.stringValue?.takeIf { it.isNotEmpty() } ?: return ANY
                if (field.kind == CriterionKind.isMissing) capitalizeWords(s.replace("_", " ")) else if (s == "true") tr(R.string.yes) else tr(R.string.no)
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
        if (modifier == CriterionModifier.IsNull) return tr(R.string.not_set)
        if (modifier == CriterionModifier.NotNull) return tr(R.string.any_value)
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
                return if (dup) tr(R.string.duplicated) else tr(R.string.unique)
            }
            CriterionKind.stashID, CriterionKind.stashIDs -> return modifier?.label ?: ANY
            else -> {}
        }
        val value = displayValue(dict["value"])
        val value2 = displayValue(dict["value2"])
        if (value.isEmpty()) return ANY
        if (modifier == CriterionModifier.MatchesRegex || modifier == CriterionModifier.NotMatchesRegex) {
            return regexText(value, negated = modifier == CriterionModifier.NotMatchesRegex)
        }
        val symbol = compactModifier(modifier)
        if (value2.isNotEmpty() && modifier?.needsSecondValue == true) return "$symbol $value – $value2".trim()
        return if (symbol.isEmpty()) value else "$symbol $value"
    }

    /**
     * iOS `regexText`: a regex in plain words — the name search's case-insensitive `(?i)` prefix
     * is dropped, and a pattern that is just text reads as that text in quotes.
     */
    private fun regexText(pattern: String, negated: Boolean): String {
        val text = pattern.removePrefix(NameRegexFilter.CASE_INSENSITIVE_PREFIX)
        val isPlainText = text.none { it in "\\^$.|?*+()[]{}" }
        return when {
            isPlainText -> if (negated) "without “$text”" else "“$text”"
            negated -> "not matching $text"
            else -> "matches $text"
        }
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
