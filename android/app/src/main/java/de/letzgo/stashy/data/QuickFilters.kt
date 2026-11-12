package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// iOS: `CatalogQuickFilters.swift` — pure logic of the quick sort strip, the active-filter chips
// and the quick-filter section of the filter sheet. Everything reads and writes the same
// `CriteriaDocument`, so a quick chip, the active-filter chip and the advanced editor agree.

/** iOS: `CatalogQuickSortCatalog` — the handful of sorts worth one tap per catalog. */
object CatalogQuickSortCatalog {
    data class Field(val field: String, val label: String)

    private fun f(field: String, label: String) = Field(field, label)

    /** Curated chips per catalog; everything else stays in the sheet. */
    fun fields(mode: FilterMode): List<Field> = when (mode) {
        FilterMode.Scenes -> listOf(
            f("date", tr(R.string.date)), f("created_at", tr(R.string.added)), f("rating", tr(R.string.rating)), f("o_counter", tr(R.string.o_count)),
            f("duration", tr(R.string.duration)), f("last_played_at", tr(R.string.last_played)), f("play_count", tr(R.string.play_count)), f("random", tr(R.string.random)),
            f(SortOption.FOR_YOU_FIELD, tr(R.string.for_you)),
        )
        FilterMode.Performers -> listOf(
            f("scenes_count", tr(R.string.scenes)), f("images_count", tr(R.string.images)), f("galleries_count", tr(R.string.galleries)),
            f("name", tr(R.string.name)), f("o_counter", tr(R.string.o_count)), f("rating", tr(R.string.rating)),
            f("created_at", tr(R.string.added)), f("birthdate", tr(R.string.birthday)), f("random", tr(R.string.random)),
        )
        FilterMode.Studios -> listOf(
            f("scenes_count", tr(R.string.scenes)), f("images_count", tr(R.string.images)), f("galleries_count", tr(R.string.galleries)),
            f("name", tr(R.string.name)), f("rating", tr(R.string.rating)), f("created_at", tr(R.string.added)), f("random", tr(R.string.random)),
        )
        FilterMode.Tags -> listOf(
            f("scenes_count", tr(R.string.scenes)), f("images_count", tr(R.string.images)), f("galleries_count", tr(R.string.galleries)),
            f("name", tr(R.string.name)), f("created_at", tr(R.string.added)), f("random", tr(R.string.random)),
        )
        // iOS lists `image_count` here, but the gallery sort field is `images_count` on both platforms.
        FilterMode.Galleries -> listOf(
            f("date", tr(R.string.date)), f("created_at", tr(R.string.added)), f("rating", tr(R.string.rating)), f("images_count", tr(R.string.images)),
            f("title", tr(R.string.title)), f("random", tr(R.string.random)),
        )
        FilterMode.Images -> listOf(
            f("date", tr(R.string.date)), f("created_at", tr(R.string.added)), f("rating", tr(R.string.rating)), f("o_counter", tr(R.string.o_count)),
            f("title", tr(R.string.title)), f("random", tr(R.string.random)),
        )
        FilterMode.Groups -> listOf(
            f("name", tr(R.string.name)), f("date", tr(R.string.date)), f("rating", tr(R.string.rating)), f("scenes_count", tr(R.string.scenes)),
            f("created_at", tr(R.string.added)), f("random", tr(R.string.random)),
        )
        FilterMode.SceneMarkers -> listOf(f("created_at", tr(R.string.added)), f("title", tr(R.string.title)), f("seconds", tr(R.string.time)), f("random", tr(R.string.random)))
        FilterMode.Unknown -> emptyList()
    }

    fun isRandom(field: String): Boolean = field.startsWith("random")

    /** Names read A→Z first; counts, dates and ratings read highest/newest first. */
    fun defaultAscending(field: String): Boolean = field == "name" || field == "title"

    /** iOS: `CatalogListQuickBar.sortFields` — curated fields the mode's sort catalog actually has. */
    fun availableFields(mode: FilterMode): List<Field> {
        val available = SortCatalog.choices(mode).map { it.field }.toSet()
        return fields(mode).filter { field ->
            if (isRandom(field.field)) available.any { isRandom(it) } else field.field in available
        }
    }

    /** Whether [field]'s chip shows as active for [current]. */
    fun isActive(current: SortOption, field: String): Boolean =
        if (isRandom(field)) isRandom(current.field) else current.field == field

    /**
     * Sort after tapping [field]: the active field flips direction (Random stays Random — the
     * caller re-rolls the seed), any other field starts in its natural direction.
     */
    fun next(mode: FilterMode, current: SortOption, field: String): SortOption? {
        if (isRandom(field)) return SortCatalog.optionFor(mode, "random", false)
        if (field == SortOption.FOR_YOU_FIELD) return SortCatalog.optionFor(mode, field, false)
        if (current.field == field) return SortCatalog.optionFor(mode, field, !current.isAscending)
        val natural = defaultAscending(field)
        return SortCatalog.optionFor(mode, field, natural) ?: SortCatalog.optionFor(mode, field, !natural)
    }
}

/** iOS: `QuickFilterChoice`. */
data class QuickFilterChoice(
    val id: String,
    /** Chip text in the sheet ("3★", "Under 10 min"). */
    val label: String,
    /** Text of the active-filter chip above the list ("3★+"). */
    val activeLabel: String,
    val value: JsonElement,
)

/** iOS: `QuickFilterSection`. */
sealed class QuickFilterSection {
    abstract val key: String
    abstract val title: String

    /** One of a fixed set of values, plus "Any". */
    data class Choices(override val key: String, override val title: String, val anyLabel: String, val choices: List<QuickFilterChoice>) : QuickFilterSection()

    /** Most-used entities (tags) as toggle chips, with a name search. */
    data class Entities(override val key: String, override val title: String) : QuickFilterSection()
}

/** iOS: `QuickFilterCatalog`. */
object QuickFilterCatalog {
    fun sections(mode: FilterMode): List<QuickFilterSection> {
        val tags = QuickFilterSection.Entities("tags", tr(R.string.tags))
        val all: List<QuickFilterSection> = when (mode) {
            FilterMode.Scenes -> listOf(tags, rating, sceneDuration, resolution, orientation, organized, watched, oCount)
            FilterMode.Performers -> listOf(gender, favorite("filter_favorites"), rating, age, oCount, tags)
            FilterMode.Studios -> listOf(favorite("favorite"), rating, tags)
            FilterMode.Tags -> listOf(favorite("favorite"), hasScenes)
            FilterMode.Galleries -> listOf(tags, rating, organized)
            FilterMode.Images -> listOf(tags, rating, organized, oCount)
            FilterMode.Groups -> listOf(tags, rating)
            FilterMode.SceneMarkers -> listOf(tags)
            FilterMode.Unknown -> emptyList()
        }
        // Never offer a key the mode does not know (catalogs differ between Stash versions).
        val known = FilterFieldCatalog.fields(mode).map { it.key }.toSet()
        return all.filter { it.key in known }
    }

    /** Active-filter label when [value] is exactly one of the quick choices for [key]. */
    fun activeLabel(key: String, value: JsonElement?, mode: FilterMode): String? = matchingChoice(key, value, mode)?.activeLabel

    /** The quick choice of [key] whose payload equals [value], if any. */
    fun matchingChoice(key: String, value: JsonElement?, mode: FilterMode): QuickFilterChoice? {
        val target = canonical(value) ?: return null
        val section = sections(mode).firstOrNull { it.key == key } as? QuickFilterSection.Choices ?: return null
        return section.choices.firstOrNull { canonical(it.value) == target }
    }

    /**
     * Criteria the quick chips cannot show (iOS `CatalogFilterCriteriaBody.advancedOnlyCount`) —
     * a reason to open the advanced editor by default.
     */
    fun advancedOnlyCount(dict: JsonObject, mode: FilterMode): Int {
        val sections = sections(mode)
        return dict.count { (key, value) ->
            when (val section = sections.firstOrNull { it.key == key }) {
                null -> true
                is QuickFilterSection.Entities -> false
                is QuickFilterSection.Choices -> activeLabel(section.key, value, mode) == null
            }
        }
    }

    /**
     * Stable form for comparing criterion payloads regardless of key order or number type
     * (`19` vs `19.0` vs `"19"` stays distinct only by string-ness, like iOS JSON).
     */
    fun canonical(value: JsonElement?): JsonElement? = when (value) {
        null, is JsonNull -> null
        is JsonObject -> JsonObject(value.entries.sortedBy { it.key }.associate { (k, v) -> k to (canonical(v) ?: JsonNull) })
        is JsonArray -> JsonArray(value.map { canonical(it) ?: JsonNull })
        is JsonPrimitive -> when {
            value.isString -> value
            value.booleanOrNull != null -> value
            else -> value.numberOrNull?.let { jsonNumber(it) } ?: value
        }
    }

    private fun obj(vararg pairs: Pair<String, Any>): JsonObject = JsonObject(linkedMapOf(*pairs.map { (k, v) ->
        k to when (v) {
            is String -> JsonPrimitive(v)
            is Int -> JsonPrimitive(v)
            is List<*> -> JsonArray(v.map { JsonPrimitive(it as String) })
            else -> error("unsupported")
        }
    }.toTypedArray()))

    // Stash stores ratings as 0–100; n stars = rating100 > n·20 − 1.
    private val rating = QuickFilterSection.Choices(
        "rating100", tr(R.string.minimum_rating), tr(R.string.any),
        (1..5).map { stars ->
            QuickFilterChoice("r$stars", "$stars★", "$stars★+", obj("modifier" to "GREATER_THAN", "value" to stars * 20 - 1))
        },
    )

    private val sceneDuration = QuickFilterSection.Choices(
        "duration", tr(R.string.duration), tr(R.string.any_length),
        listOf(
            QuickFilterChoice("short", tr(R.string.under_10_min), "< 10 min", obj("modifier" to "LESS_THAN", "value" to 600)),
            QuickFilterChoice("mid", tr(R.string.duration_10_30_min), tr(R.string.duration_10_30_min), obj("modifier" to "BETWEEN", "value" to 600, "value2" to 1800)),
            QuickFilterChoice("long", tr(R.string.over_30_min), "> 30 min", obj("modifier" to "GREATER_THAN", "value" to 1800)),
        ),
    )

    // `GREATER_THAN` a resolution class means "above that class", so 720p+ is "> 540p".
    private val resolution = QuickFilterSection.Choices(
        "resolution", tr(R.string.quality), tr(R.string.any_quality),
        listOf(
            QuickFilterChoice("720", "720p+", "720p+", obj("modifier" to "GREATER_THAN", "value" to ResolutionOption.WebHD.raw)),
            QuickFilterChoice("1080", "1080p+", "1080p+", obj("modifier" to "GREATER_THAN", "value" to ResolutionOption.StandardHD.raw)),
            QuickFilterChoice("4k", "4K+", "4K+", obj("modifier" to "GREATER_THAN", "value" to ResolutionOption.QuadHD.raw)),
        ),
    )

    private val organized = QuickFilterSection.Choices(
        "organized", tr(R.string.organized), tr(R.string.any),
        listOf(
            QuickFilterChoice("yes", tr(R.string.organized), tr(R.string.organized), JsonPrimitive(true)),
            QuickFilterChoice("no", tr(R.string.not_organized), tr(R.string.not_organized), JsonPrimitive(false)),
        ),
    )

    private val watched = QuickFilterSection.Choices(
        "play_count", tr(R.string.watched), tr(R.string.any),
        listOf(
            QuickFilterChoice("unwatched", tr(R.string.unwatched), tr(R.string.unwatched), obj("modifier" to "EQUALS", "value" to 0)),
            QuickFilterChoice("watched", tr(R.string.watched), tr(R.string.watched), obj("modifier" to "GREATER_THAN", "value" to 0)),
        ),
    )

    private val orientation = QuickFilterSection.Choices(
        "orientation", tr(R.string.orientation), tr(R.string.any),
        OrientationOption.entries.map { o ->
            QuickFilterChoice(o.raw, o.label, o.label, kotlinx.serialization.json.buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(o.raw))))
            })
        },
    )

    private val oCount = QuickFilterSection.Choices(
        "o_counter", tr(R.string.o_count), tr(R.string.any),
        listOf(
            QuickFilterChoice("o0", tr(R.string.none), tr(R.string.empty_o), obj("modifier" to "EQUALS", "value" to 0)),
            QuickFilterChoice("o1", "1+", "O 1+", obj("modifier" to "GREATER_THAN", "value" to 0)),
            QuickFilterChoice("o5", "5+", "O 5+", obj("modifier" to "GREATER_THAN", "value" to 4)),
            QuickFilterChoice("o10", "10+", "O 10+", obj("modifier" to "GREATER_THAN", "value" to 9)),
        ),
    )

    private val gender = QuickFilterSection.Choices(
        "gender", tr(R.string.gender), tr(R.string.any),
        listOf(
            "FEMALE" to tr(R.string.female), "MALE" to tr(R.string.male), "TRANSGENDER_FEMALE" to tr(R.string.trans_female),
            "TRANSGENDER_MALE" to tr(R.string.trans_male), "NON_BINARY" to tr(R.string.non_binary),
        ).map { (raw, label) ->
            QuickFilterChoice(raw, label, label, obj("modifier" to "INCLUDES", "value_list" to listOf(raw)))
        },
    )

    private val age = QuickFilterSection.Choices(
        "age", tr(R.string.age), tr(R.string.any_age),
        listOf(
            QuickFilterChoice("18", "18–25", tr(R.string.age_18_25), obj("modifier" to "BETWEEN", "value" to 18, "value2" to 25)),
            QuickFilterChoice("26", "26–35", tr(R.string.age_26_35), obj("modifier" to "BETWEEN", "value" to 26, "value2" to 35)),
            QuickFilterChoice("36", "36+", tr(R.string.age_36_plus), obj("modifier" to "GREATER_THAN", "value" to 35)),
        ),
    )

    private val hasScenes = QuickFilterSection.Choices(
        "scene_count", tr(R.string.scenes), tr(R.string.any),
        listOf(
            QuickFilterChoice("has", tr(R.string.has_scenes), tr(R.string.has_scenes), obj("modifier" to "GREATER_THAN", "value" to 0)),
            QuickFilterChoice("none", tr(R.string.empty_scenes), tr(R.string.empty_scenes), obj("modifier" to "EQUALS", "value" to 0)),
        ),
    )

    private fun favorite(key: String) = QuickFilterSection.Choices(
        key, tr(R.string.favourite), tr(R.string.any),
        listOf(
            QuickFilterChoice("yes", tr(R.string.favorites), tr(R.string.favorites), JsonPrimitive(true)),
            QuickFilterChoice("no", tr(R.string.not_favorite), tr(R.string.not_favorite), JsonPrimitive(false)),
        ),
    )

    /**
     * iOS: `CatalogListQuickBar.chipLabel` — text of an active-filter chip. [names] maps entity
     * ids to names (picker store); multi-entity criteria with ≤ 2 ids show the names.
     */
    fun chipLabel(key: String, value: JsonElement, mode: FilterMode, names: Map<String, String>): String {
        activeLabel(key, value, mode)?.let { return it }
        if (CriteriaDocument.isGroupKey(key)) return when (key) { "AND" -> tr(R.string.all_of); "OR" -> tr(R.string.any_of); else -> tr(R.string.none_of) }
        val field = FilterFieldCatalog.field(key, mode) ?: return capitalizeWords(key.replace("_", " "))
        val dict = value as? JsonObject
        if ((field.kind == CriterionKind.hierarchicalMulti || field.kind == CriterionKind.multi) && dict != null) {
            val included = FilterMapper.idStrings(dict["value"])
            val excluded = FilterMapper.idStrings(dict["excludes"])
            val prefix = if (key == "tags") "#" else ""
            val total = included.size + excluded.size
            if (total in 1..2) {
                val parts = included.mapNotNull { names[it]?.let { n -> prefix + n } } +
                    excluded.mapNotNull { names[it]?.let { n -> "−$prefix$n" } }
                if (parts.size == total) return parts.joinToString(", ")
            }
        }
        return "${field.label}: ${FilterCriterionSummary.text(field, value)}"
    }

    /**
     * iOS: `QuickEntityFilterSection.toggle` — toggles [id] in the criterion's `value` list,
     * keeping its modifier, depth and exclusions; `null` = remove the criterion.
     */
    fun toggledEntityCriterion(current: JsonObject, id: String, hierarchical: Boolean): JsonObject? {
        val ids = FilterMapper.idStrings(current["value"]).toMutableList()
        if (!ids.remove(id)) ids.add(id)
        val excluded = FilterMapper.idStrings(current["excludes"])
        if (ids.isEmpty() && excluded.isEmpty()) return null
        val m = LinkedHashMap<String, JsonElement>(current)
        m["value"] = JsonArray(ids.map { JsonPrimitive(it) })
        m["modifier"] = JsonPrimitive(entityModifier(current))
        if (hierarchical && m["depth"] == null) m["depth"] = JsonPrimitive(0)
        return JsonObject(m)
    }

    /** Match mode of a quick entity criterion — "All" (`INCLUDES_ALL`) unless set. */
    fun entityModifier(current: JsonObject): String = current["modifier"].stringValue ?: CriterionModifier.IncludesAll.raw
}
