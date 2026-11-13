package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlin.random.Random

/**
 * One sort option of a list (iOS: the `*SortOption` enums in `StashDBViewModel` — `rawValue`,
 * `displayName`, `sortField`, `direction`). The raw values are identical so persisted defaults
 * (`AppTabsConfig.sortOption`, `ui_options.stashy.sortRaw`) round-trip with iOS.
 */
data class SortOption(val raw: String, val label: String, val field: String, val direction: String) {
    /** Random or For You: one order, no direction (For You is answered by the app, see [isForYou]). */
    val isRandom: Boolean get() = this.field == "random" || isForYou
    /** iOS `SceneSortOption.forYou`: the stashy+ For You list, up to 25, in place of a server sort. */
    val isForYou: Boolean get() = this.field == FOR_YOU_FIELD

    companion object {
        const val FOR_YOU_FIELD = "for_you"
    }
    val isAscending: Boolean get() = direction == "ASC"
}

/** Field entry of the sheet's sort picker (iOS: `*CatalogSortFieldKind` / `SceneLiveSortFieldKind`). */
data class SortFieldKind(val field: String, val menuLabel: String)

/** iOS: `FilterSortCatalog` + the per-entity sort enums and sheet field kinds. */
/** iOS `SceneSortOption.sceneNumber*`: a scene's number inside a group, only on a group's scenes. */
object GroupSceneSort {
    const val FIELD = "group_scene_number"
    val Asc = SortOption("sceneNumberAsc", tr(R.string.scene_no_ascending), FIELD, "ASC")
    val Desc = SortOption("sceneNumberDesc", tr(R.string.scene_no_descending), FIELD, "DESC")
    val options = listOf(Asc, Desc)
}

object SortCatalog {
    private fun o(raw: String, label: String, field: String, dir: String) = SortOption(raw, label, field, dir)

    val scenes = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("forYou", tr(R.string.for_you), SortOption.FOR_YOU_FIELD, "DESC"),
        o("dateDesc", tr(R.string.date_newest_first), "date", "DESC"), o("dateAsc", tr(R.string.date_oldest_first), "date", "ASC"),
        o("productionDateDesc", tr(R.string.production_date_newest_first), "production_date", "DESC"), o("productionDateAsc", tr(R.string.production_date_oldest_first), "production_date", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
        o("titleAsc", tr(R.string.title_z), "title", "ASC"), o("titleDesc", tr(R.string.title_z_2), "title", "DESC"),
        o("durationDesc", tr(R.string.duration_longest_first), "duration", "DESC"), o("durationAsc", tr(R.string.duration_shortest_first), "duration", "ASC"),
        o("lastPlayedAtDesc", tr(R.string.last_played_newest_first), "last_played_at", "DESC"), o("lastPlayedAtAsc", tr(R.string.last_played_oldest_first), "last_played_at", "ASC"),
        o("playCountDesc", tr(R.string.most_viewed), "play_count", "DESC"), o("playCountAsc", tr(R.string.least_viewed), "play_count", "ASC"),
        o("playDurationDesc", tr(R.string.watch_time_high_low), "play_duration", "DESC"), o("playDurationAsc", tr(R.string.watch_time_low_high), "play_duration", "ASC"),
        o("oCounterDesc", tr(R.string.counter_high_low), "o_counter", "DESC"), o("oCounterAsc", tr(R.string.counter_low_high), "o_counter", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
    )

    val markers = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest_first), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest_first), "updated_at", "ASC"),
        o("titleAsc", tr(R.string.title_z), "title", "ASC"), o("titleDesc", tr(R.string.title_z_2), "title", "DESC"),
        o("secondsAsc", tr(R.string.time_start), "seconds", "ASC"), o("secondsDesc", tr(R.string.time_end), "seconds", "DESC"),
    )

    val images = listOf(
        o("titleAsc", tr(R.string.title_z), "title", "ASC"), o("titleDesc", tr(R.string.title_z_2), "title", "DESC"),
        o("dateDesc", tr(R.string.date_newest), "date", "DESC"), o("dateAsc", tr(R.string.date_oldest), "date", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest), "created_at", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest), "updated_at", "ASC"),
        o("performerAgeDesc", tr(R.string.performer_age_oldest_first), "performer_age", "DESC"), o("performerAgeAsc", tr(R.string.performer_age_youngest_first), "performer_age", "ASC"),
        o("random", tr(R.string.random), "random", "DESC"),
    )

    val galleries = listOf(
        o("titleAsc", tr(R.string.name_z), "title", "ASC"), o("titleDesc", tr(R.string.name_z_2), "title", "DESC"),
        o("dateDesc", tr(R.string.date_newest), "date", "DESC"), o("dateAsc", tr(R.string.date_oldest), "date", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest), "created_at", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest), "updated_at", "ASC"),
        o("imageCountDesc", tr(R.string.image_count_high_low), "images_count", "DESC"), o("imageCountAsc", tr(R.string.image_count_low_high), "images_count", "ASC"),
        o("performerAgeDesc", tr(R.string.performer_age_oldest_first), "performer_age", "DESC"), o("performerAgeAsc", tr(R.string.performer_age_youngest_first), "performer_age", "ASC"),
        o("random", tr(R.string.random), "random", "DESC"),
    )

    val performers = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("nameAsc", tr(R.string.name_z), "name", "ASC"), o("nameDesc", tr(R.string.name_z_2), "name", "DESC"),
        o("sceneCountDesc", tr(R.string.scene_count_high_low), "scenes_count", "DESC"), o("sceneCountAsc", tr(R.string.scene_count_low_high), "scenes_count", "ASC"),
        o("imageCountDesc", tr(R.string.image_count_high_low), "images_count", "DESC"), o("imageCountAsc", tr(R.string.image_count_low_high), "images_count", "ASC"),
        o("galleryCountDesc", tr(R.string.gallery_count_high_low), "galleries_count", "DESC"), o("galleryCountAsc", tr(R.string.gallery_count_low_high), "galleries_count", "ASC"),
        o("birthdateDesc", tr(R.string.birthday_youngest_first), "birthdate", "DESC"), o("birthdateAsc", tr(R.string.birthday_oldest_first), "birthdate", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest_first), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest_first), "updated_at", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
        o("oCountDesc", tr(R.string.o_count_high_low), "o_counter", "DESC"), o("oCountAsc", tr(R.string.o_count_low_high), "o_counter", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
    )

    val studios = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("nameAsc", tr(R.string.name_z), "name", "ASC"), o("nameDesc", tr(R.string.name_z_2), "name", "DESC"),
        o("sceneCountDesc", tr(R.string.scene_count_high_low), "scenes_count", "DESC"), o("sceneCountAsc", tr(R.string.scene_count_low_high), "scenes_count", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest_first), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest_first), "updated_at", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
        o("performerCountDesc", tr(R.string.performer_count_high_low), "performer_count", "DESC"), o("performerCountAsc", tr(R.string.performer_count_low_high), "performer_count", "ASC"),
        o("galleryCountDesc", tr(R.string.gallery_count_high_low), "galleries_count", "DESC"), o("galleryCountAsc", tr(R.string.gallery_count_low_high), "galleries_count", "ASC"),
        o("imageCountDesc", tr(R.string.image_count_high_low), "images_count", "DESC"), o("imageCountAsc", tr(R.string.image_count_low_high), "images_count", "ASC"),
        o("oCounterDesc", tr(R.string.o_count_high_low), "o_counter", "DESC"), o("oCounterAsc", tr(R.string.o_count_low_high), "o_counter", "ASC"),
        o("oCounterAllDesc", tr(R.string.o_count_incl_sub_studios_high), "o_counter_all", "DESC"), o("oCounterAllAsc", tr(R.string.o_count_incl_sub_studios_low), "o_counter_all", "ASC"),
        o("performerCountAllDesc", tr(R.string.performer_count_incl_sub_studios_high), "performer_count_all", "DESC"), o("performerCountAllAsc", tr(R.string.performer_count_incl_sub_studios_low), "performer_count_all", "ASC"),
        o("markerCountDesc", tr(R.string.marker_count_high_low), "scene_markers_count", "DESC"), o("markerCountAsc", tr(R.string.marker_count_low_high), "scene_markers_count", "ASC"),
    )

    val tags = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("nameAsc", tr(R.string.name_z), "name", "ASC"), o("nameDesc", tr(R.string.name_z_2), "name", "DESC"),
        o("sceneCountDesc", tr(R.string.scene_count_high_low), "scenes_count", "DESC"), o("sceneCountAsc", tr(R.string.scene_count_low_high), "scenes_count", "ASC"),
        o("imageCountDesc", tr(R.string.image_count_high_low), "images_count", "DESC"), o("imageCountAsc", tr(R.string.image_count_low_high), "images_count", "ASC"),
        o("galleryCountDesc", tr(R.string.gallery_count_high_low), "galleries_count", "DESC"), o("galleryCountAsc", tr(R.string.gallery_count_low_high), "galleries_count", "ASC"),
        o("markerCountDesc", tr(R.string.marker_count_high_low), "scene_markers_count", "DESC"), o("markerCountAsc", tr(R.string.marker_count_low_high), "scene_markers_count", "ASC"),
        o("performerCountDesc", tr(R.string.performer_count_high_low), "performers_count", "DESC"), o("performerCountAsc", tr(R.string.performer_count_low_high), "performers_count", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest_first), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest_first), "updated_at", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
    )

    val groups = listOf(
        o("random", tr(R.string.random), "random", "DESC"),
        o("nameAsc", tr(R.string.name_z), "name", "ASC"), o("nameDesc", tr(R.string.name_z_2), "name", "DESC"),
        o("sceneCountDesc", tr(R.string.scene_count_high_low), "scenes_count", "DESC"), o("sceneCountAsc", tr(R.string.scene_count_low_high), "scenes_count", "ASC"),
        o("galleryCountDesc", tr(R.string.gallery_count_high_low), "galleries_count", "DESC"), o("galleryCountAsc", tr(R.string.gallery_count_low_high), "galleries_count", "ASC"),
        o("performerCountDesc", tr(R.string.performer_count_high_low), "performer_count", "DESC"), o("performerCountAsc", tr(R.string.performer_count_low_high), "performer_count", "ASC"),
        o("dateDesc", tr(R.string.date_newest_first), "date", "DESC"), o("dateAsc", tr(R.string.date_oldest_first), "date", "ASC"),
        o("ratingDesc", tr(R.string.rating_high_low), "rating", "DESC"), o("ratingAsc", tr(R.string.rating_low_high), "rating", "ASC"),
        o("updatedAtDesc", tr(R.string.updated_newest_first), "updated_at", "DESC"), o("updatedAtAsc", tr(R.string.updated_oldest_first), "updated_at", "ASC"),
        o("createdAtDesc", tr(R.string.created_newest_first), "created_at", "DESC"), o("createdAtAsc", tr(R.string.created_oldest_first), "created_at", "ASC"),
    )

    /** Sort fields older servers reject as invalid (iOS: `requiresStash032`). */
    private fun requires032(mode: FilterMode, field: String): Boolean = when (mode) {
        FilterMode.Scenes -> field == "production_date"
        FilterMode.Images, FilterMode.Galleries -> field == "performer_age"
        FilterMode.Studios -> field in setOf("performer_count", "performer_count_all", "o_counter", "o_counter_all", "scene_markers_count")
        else -> false
    }

    private fun available(mode: FilterMode, field: String) =
        // runCatching: the engine reads app prefs, which plain unit tests do not have.
        if (field == SortOption.FOR_YOU_FIELD) mode == FilterMode.Scenes && runCatching { de.letzgo.stashy.data.tools.SceneRecommendations.isAvailable }.getOrDefault(false)
        else !requires032(mode, field) || ServerCapabilities.supports032

    fun choices(mode: FilterMode): List<SortOption> = allChoices(mode).filter { available(mode, it.field) }

    private fun allChoices(mode: FilterMode): List<SortOption> = when (mode) {
        FilterMode.Scenes -> scenes
        FilterMode.SceneMarkers -> markers
        FilterMode.Images -> images
        FilterMode.Galleries -> galleries
        FilterMode.Performers -> performers
        FilterMode.Studios -> studios
        FilterMode.Tags -> tags
        FilterMode.Groups -> groups
        FilterMode.Unknown -> emptyList()
    }

    fun option(mode: FilterMode, raw: String?): SortOption? = raw?.let { r -> choices(mode).firstOrNull { it.raw == r } }

    /** iOS: `FilterSortCatalog.choice(forRaw:pair:mode:)` — `sortRaw` first, then the `find_filter` pair. */
    fun choice(mode: FilterMode, raw: String?, pair: Pair<String, String>?): SortOption? {
        val list = choices(mode)
        if (raw != null) list.firstOrNull { it.raw == raw }?.let { return it }
        if (pair == null) return null
        val field = pair.first.lowercase()
        val direction = pair.second.uppercase()
        if (field.startsWith("random")) return list.firstOrNull { it.field == "random" }
        list.firstOrNull { it.field.lowercase() == field && it.direction.uppercase() == direction }?.let { return it }
        if (field == "rating100" || field == "rating") {
            return list.firstOrNull { it.field.lowercase().startsWith("rating") && it.direction.uppercase() == direction }
        }
        return null
    }

    /**
     * [fieldKinds] with list-specific [extra] sorts first (menu label = option label up to " (").
     * [optionFor] / [optionAfterPickingField] take the same [extra] list.
     */
    fun fieldKinds(mode: FilterMode, extra: List<SortOption>): List<SortFieldKind> =
        extra.distinctBy { it.field }.map { SortFieldKind(it.field, it.label.substringBefore(" (")) } + fieldKinds(mode)

    fun optionFor(mode: FilterMode, field: String, ascending: Boolean, extra: List<SortOption>): SortOption? =
        extra.firstOrNull { it.field == field && it.isAscending == ascending } ?: optionFor(mode, field, ascending)

    fun optionAfterPickingField(mode: FilterMode, current: SortOption, field: String, extra: List<SortOption>): SortOption? = when {
        extra.none { it.field == field } -> optionAfterPickingField(mode, current, field)
        // Shared-style counts start with the most first, like a fresh numeric sort.
        current.isRandom -> optionFor(mode, field, false, extra)
        else -> optionFor(mode, field, current.isAscending, extra)
    }

    /** Field kinds offered by each sheet's sort picker, in iOS order. */
    fun fieldKinds(mode: FilterMode): List<SortFieldKind> = allFieldKinds(mode).filter { available(mode, it.field) }

    private fun allFieldKinds(mode: FilterMode): List<SortFieldKind> = when (mode) {
        FilterMode.Scenes -> listOf(
            SortFieldKind("date", tr(R.string.date)), SortFieldKind("production_date", tr(R.string.production_date)), SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("title", tr(R.string.title)),
            SortFieldKind("duration", tr(R.string.duration)), SortFieldKind("last_played_at", tr(R.string.last_played)), SortFieldKind("play_count", tr(R.string.play_count)),
            SortFieldKind("play_duration", tr(R.string.watch_time)), SortFieldKind("o_counter", tr(R.string.o_count)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("random", tr(R.string.random)), SortFieldKind(SortOption.FOR_YOU_FIELD, tr(R.string.for_you)),
        )
        FilterMode.SceneMarkers -> listOf(
            SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("title", tr(R.string.title)),
            SortFieldKind("seconds", tr(R.string.time)), SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Performers -> listOf(
            SortFieldKind("name", tr(R.string.name)), SortFieldKind("scenes_count", tr(R.string.scene_count)), SortFieldKind("images_count", tr(R.string.image_count)),
            SortFieldKind("galleries_count", tr(R.string.gallery_count)), SortFieldKind("birthdate", tr(R.string.birthday)), SortFieldKind("updated_at", tr(R.string.updated)),
            SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("o_counter", tr(R.string.o_count)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Tags -> listOf(
            SortFieldKind("name", tr(R.string.name)), SortFieldKind("scenes_count", tr(R.string.scene_count)), SortFieldKind("images_count", tr(R.string.image_count)),
            SortFieldKind("galleries_count", tr(R.string.gallery_count)), SortFieldKind("scene_markers_count", tr(R.string.marker_count)),
            SortFieldKind("performers_count", tr(R.string.performer_count)), SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("created_at", tr(R.string.created)),
            SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Studios -> listOf(
            SortFieldKind("name", tr(R.string.name)), SortFieldKind("scenes_count", tr(R.string.scene_count)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("performer_count", tr(R.string.performer_count)), SortFieldKind("performer_count_all", tr(R.string.performer_count_incl_sub_studios)),
            SortFieldKind("o_counter", tr(R.string.o_count)), SortFieldKind("o_counter_all", tr(R.string.o_count_incl_sub_studios)), SortFieldKind("scene_markers_count", tr(R.string.marker_count)),
            SortFieldKind("galleries_count", tr(R.string.gallery_count)), SortFieldKind("images_count", tr(R.string.image_count)), SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("created_at", tr(R.string.created)),
            SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Galleries -> listOf(
            SortFieldKind("title", tr(R.string.title)), SortFieldKind("date", tr(R.string.date)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("images_count", tr(R.string.image_count)),
            SortFieldKind("performer_age", tr(R.string.performer_age)), SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Images -> listOf(
            SortFieldKind("title", tr(R.string.title)), SortFieldKind("date", tr(R.string.date)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("performer_age", tr(R.string.performer_age)), SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Groups -> listOf(
            SortFieldKind("name", tr(R.string.name)), SortFieldKind("scenes_count", tr(R.string.scene_count)), SortFieldKind("galleries_count", tr(R.string.gallery_count)),
            SortFieldKind("performer_count", tr(R.string.performer_count)), SortFieldKind("date", tr(R.string.date)), SortFieldKind("rating", tr(R.string.rating)),
            SortFieldKind("updated_at", tr(R.string.updated)), SortFieldKind("created_at", tr(R.string.created)), SortFieldKind("random", tr(R.string.random)),
        )
        FilterMode.Unknown -> emptyList()
    }

    /** iOS: `<Kind>.performerSortOption(ascending:)` etc. — option for a field kind + direction. */
    fun optionFor(mode: FilterMode, field: String, ascending: Boolean): SortOption? {
        val list = choices(mode)
        if (field == "random") return list.firstOrNull { it.field == "random" }
        if (field == SortOption.FOR_YOU_FIELD) return list.firstOrNull { it.isForYou }
        return list.firstOrNull { it.field == field && it.isAscending == ascending }
    }

    /**
     * iOS: picking a new field in the sheet — random stays random, coming from random uses
     * descending, otherwise the current direction is kept.
     */
    fun optionAfterPickingField(mode: FilterMode, current: SortOption, field: String): SortOption? = when {
        field == "random" -> optionFor(mode, "random", false)
        current.isRandom -> optionFor(mode, field, false)
        else -> optionFor(mode, field, current.isAscending)
    }

    /** Default sort per catalog when nothing is configured (iOS view fallbacks). */
    fun defaultRaw(mode: FilterMode): String = when (mode) {
        FilterMode.Scenes -> "dateDesc"
        FilterMode.Performers -> "sceneCountDesc"
        FilterMode.Studios -> "nameAsc"
        FilterMode.Tags -> "sceneCountDesc"
        FilterMode.Galleries, FilterMode.Images -> "dateDesc"
        FilterMode.Groups -> "nameAsc"
        FilterMode.SceneMarkers -> "createdAtDesc"
        FilterMode.Unknown -> "dateDesc"
    }
}

/**
 * iOS: `StashDBViewModel.RandomSeedKind` + `randomSort(_:)` — one stable seed per content kind
 * so "Random" pages consistently; choosing Random again reshuffles.
 */
object RandomSeeds {
    private val seeds = HashMap<FilterMode, Int>()

    @Synchronized fun seed(mode: FilterMode): Int = seeds.getOrPut(mode) { Random.nextInt(1, 1_000_001) }
    @Synchronized fun refresh(mode: FilterMode) { seeds[mode] = Random.nextInt(1, 1_000_001) }

    /** `random_<seed>` for random sorts, the plain field otherwise. */
    fun sortField(mode: FilterMode, option: SortOption): String = if (option.isRandom) "random_${seed(mode)}" else option.field
}

/** iOS: `PerformerBadgeType.forSort` — which count the performer card shows. */
enum class PerformerBadgeType {
    SceneCount, ImageCount, GalleryCount, OCount, Rating;

    companion object {
        fun forSort(sort: SortOption): PerformerBadgeType = when (sort.raw) {
            "sceneCountAsc", "sceneCountDesc" -> SceneCount
            "imageCountAsc", "imageCountDesc" -> ImageCount
            "galleryCountAsc", "galleryCountDesc" -> GalleryCount
            "oCountAsc", "oCountDesc" -> OCount
            "ratingAsc", "ratingDesc" -> Rating
            else -> SceneCount
        }
    }
}

/**
 * iOS: `CatalogCardBadge` — the one count a studio, tag or group card shows: what its list is
 * sorted by, the scene count for every other sort. A count the model lacks falls back to scenes.
 */
enum class CatalogCardBadge {
    Scenes, Images, Galleries, Performers, PerformersAll, Markers, OCount, OCountAll, Rating;

    companion object {
        /** From a sort option's server sort field. */
        fun forField(field: String): CatalogCardBadge = when (field) {
            "images_count" -> Images
            "galleries_count" -> Galleries
            "performer_count", "performers_count" -> Performers
            "performer_count_all" -> PerformersAll
            "scene_markers_count" -> Markers
            "o_counter" -> OCount
            "o_counter_all" -> OCountAll
            "rating" -> Rating
            else -> Scenes
        }
        fun forSort(sort: SortOption): CatalogCardBadge = forField(sort.field)
    }
}

/** A card's shown badge and count; null only when even the scene count is unknown. */
typealias BadgeCount = Pair<CatalogCardBadge, Int>

private fun badgeOrScenes(badge: CatalogCardBadge, value: Int?, scenes: Int?): BadgeCount? =
    if (value != null) badge to value else scenes?.let { CatalogCardBadge.Scenes to it }

/** The counts over all sub-tags while "Include sub-tag content" is on and the tag came with them (iOS `TagCardView.shownCount`). */
fun Tag.badgeCount(badge: CatalogCardBadge): BadgeCount? {
    val all = TagHierarchyStore.includesContent
    return badgeOrScenes(
        badge,
        when (badge) {
            CatalogCardBadge.Scenes -> (if (all) sceneCountAll else null) ?: sceneCount
            CatalogCardBadge.Images -> (if (all) imageCountAll else null) ?: imageCount
            CatalogCardBadge.Galleries -> (if (all) galleryCountAll else null) ?: galleryCount
            CatalogCardBadge.Performers, CatalogCardBadge.PerformersAll -> (if (all) performerCountAll else null) ?: performerCount
            CatalogCardBadge.Markers -> (if (all) sceneMarkerCountAll else null) ?: sceneMarkerCount
            else -> null
        },
        (if (all) sceneCountAll else null) ?: sceneCount,
    )
}

fun StashGroup.badgeCount(badge: CatalogCardBadge): BadgeCount? = badgeOrScenes(
    badge,
    when (badge) {
        CatalogCardBadge.Scenes -> sceneCount
        CatalogCardBadge.Performers, CatalogCardBadge.PerformersAll -> performerCount
        CatalogCardBadge.Rating -> rating100
        else -> null
    },
    sceneCount,
)
