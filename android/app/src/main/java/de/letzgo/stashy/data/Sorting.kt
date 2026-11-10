package de.letzgo.stashy.data

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
    val Asc = SortOption("sceneNumberAsc", "Scene No. (Ascending)", FIELD, "ASC")
    val Desc = SortOption("sceneNumberDesc", "Scene No. (Descending)", FIELD, "DESC")
    val options = listOf(Asc, Desc)
}

object SortCatalog {
    private fun o(raw: String, label: String, field: String, dir: String) = SortOption(raw, label, field, dir)

    val scenes = listOf(
        o("random", "Random", "random", "DESC"),
        o("forYou", "For You", SortOption.FOR_YOU_FIELD, "DESC"),
        o("dateDesc", "Date (Newest First)", "date", "DESC"), o("dateAsc", "Date (Oldest First)", "date", "ASC"),
        o("productionDateDesc", "Production Date (Newest First)", "production_date", "DESC"), o("productionDateAsc", "Production Date (Oldest First)", "production_date", "ASC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        o("titleAsc", "Title (A-Z)", "title", "ASC"), o("titleDesc", "Title (Z-A)", "title", "DESC"),
        o("durationDesc", "Duration (Longest First)", "duration", "DESC"), o("durationAsc", "Duration (Shortest First)", "duration", "ASC"),
        o("lastPlayedAtDesc", "Last Played (Newest First)", "last_played_at", "DESC"), o("lastPlayedAtAsc", "Last Played (Oldest First)", "last_played_at", "ASC"),
        o("playCountDesc", "Most Viewed", "play_count", "DESC"), o("playCountAsc", "Least Viewed", "play_count", "ASC"),
        o("playDurationDesc", "Watch Time (High-Low)", "play_duration", "DESC"), o("playDurationAsc", "Watch Time (Low-High)", "play_duration", "ASC"),
        o("oCounterDesc", "Counter (High-Low)", "o_counter", "DESC"), o("oCounterAsc", "Counter (Low-High)", "o_counter", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
    )

    val markers = listOf(
        o("random", "Random", "random", "DESC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        o("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        o("titleAsc", "Title (A-Z)", "title", "ASC"), o("titleDesc", "Title (Z-A)", "title", "DESC"),
        o("secondsAsc", "Time (Start)", "seconds", "ASC"), o("secondsDesc", "Time (End)", "seconds", "DESC"),
    )

    val images = listOf(
        o("titleAsc", "Title (A-Z)", "title", "ASC"), o("titleDesc", "Title (Z-A)", "title", "DESC"),
        o("dateDesc", "Date (Newest)", "date", "DESC"), o("dateAsc", "Date (Oldest)", "date", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        o("createdAtDesc", "Created (Newest)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest)", "created_at", "ASC"),
        o("updatedAtDesc", "Updated (Newest)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest)", "updated_at", "ASC"),
        o("performerAgeDesc", "Performer Age (Oldest First)", "performer_age", "DESC"), o("performerAgeAsc", "Performer Age (Youngest First)", "performer_age", "ASC"),
        o("random", "Random", "random", "DESC"),
    )

    val galleries = listOf(
        o("titleAsc", "Name (A-Z)", "title", "ASC"), o("titleDesc", "Name (Z-A)", "title", "DESC"),
        o("dateDesc", "Date (Newest)", "date", "DESC"), o("dateAsc", "Date (Oldest)", "date", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        o("createdAtDesc", "Created (Newest)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest)", "created_at", "ASC"),
        o("updatedAtDesc", "Updated (Newest)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest)", "updated_at", "ASC"),
        o("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"), o("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        o("performerAgeDesc", "Performer Age (Oldest First)", "performer_age", "DESC"), o("performerAgeAsc", "Performer Age (Youngest First)", "performer_age", "ASC"),
        o("random", "Random", "random", "DESC"),
    )

    val performers = listOf(
        o("random", "Random", "random", "DESC"),
        o("nameAsc", "Name (A-Z)", "name", "ASC"), o("nameDesc", "Name (Z-A)", "name", "DESC"),
        o("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"), o("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        o("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"), o("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        o("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"), o("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        o("birthdateDesc", "Birthday (Youngest First)", "birthdate", "DESC"), o("birthdateAsc", "Birthday (Oldest First)", "birthdate", "ASC"),
        o("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        o("oCountDesc", "O Count (High-Low)", "o_counter", "DESC"), o("oCountAsc", "O Count (Low-High)", "o_counter", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
    )

    val studios = listOf(
        o("random", "Random", "random", "DESC"),
        o("nameAsc", "Name (A-Z)", "name", "ASC"), o("nameDesc", "Name (Z-A)", "name", "DESC"),
        o("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"), o("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        o("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        o("performerCountDesc", "Performer Count (High-Low)", "performer_count", "DESC"), o("performerCountAsc", "Performer Count (Low-High)", "performer_count", "ASC"),
        o("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"), o("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        o("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"), o("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        o("oCounterDesc", "O Count (High-Low)", "o_counter", "DESC"), o("oCounterAsc", "O Count (Low-High)", "o_counter", "ASC"),
        o("oCounterAllDesc", "O Count incl. Sub-Studios (High-Low)", "o_counter_all", "DESC"), o("oCounterAllAsc", "O Count incl. Sub-Studios (Low-High)", "o_counter_all", "ASC"),
        o("performerCountAllDesc", "Performer Count incl. Sub-Studios (High-Low)", "performer_count_all", "DESC"), o("performerCountAllAsc", "Performer Count incl. Sub-Studios (Low-High)", "performer_count_all", "ASC"),
        o("markerCountDesc", "Marker Count (High-Low)", "scene_markers_count", "DESC"), o("markerCountAsc", "Marker Count (Low-High)", "scene_markers_count", "ASC"),
    )

    val tags = listOf(
        o("random", "Random", "random", "DESC"),
        o("nameAsc", "Name (A-Z)", "name", "ASC"), o("nameDesc", "Name (Z-A)", "name", "DESC"),
        o("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"), o("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        o("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"), o("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        o("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"), o("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        o("markerCountDesc", "Marker Count (High-Low)", "scene_markers_count", "DESC"), o("markerCountAsc", "Marker Count (Low-High)", "scene_markers_count", "ASC"),
        o("performerCountDesc", "Performer Count (High-Low)", "performers_count", "DESC"), o("performerCountAsc", "Performer Count (Low-High)", "performers_count", "ASC"),
        o("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
    )

    val groups = listOf(
        o("random", "Random", "random", "DESC"),
        o("nameAsc", "Name (A-Z)", "name", "ASC"), o("nameDesc", "Name (Z-A)", "name", "DESC"),
        o("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"), o("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        o("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"), o("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        o("performerCountDesc", "Performer Count (High-Low)", "performer_count", "DESC"), o("performerCountAsc", "Performer Count (Low-High)", "performer_count", "ASC"),
        o("dateDesc", "Date (Newest First)", "date", "DESC"), o("dateAsc", "Date (Oldest First)", "date", "ASC"),
        o("ratingDesc", "Rating (High-Low)", "rating", "DESC"), o("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        o("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"), o("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        o("createdAtDesc", "Created (Newest First)", "created_at", "DESC"), o("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
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
            SortFieldKind("date", "Date"), SortFieldKind("production_date", "Production date"), SortFieldKind("created_at", "Created"), SortFieldKind("title", "Title"),
            SortFieldKind("duration", "Duration"), SortFieldKind("last_played_at", "Last played"), SortFieldKind("play_count", "Play count"),
            SortFieldKind("play_duration", "Watch time"), SortFieldKind("o_counter", "O Count"), SortFieldKind("rating", "Rating"),
            SortFieldKind("random", "Random"), SortFieldKind(SortOption.FOR_YOU_FIELD, "For You"),
        )
        FilterMode.SceneMarkers -> listOf(
            SortFieldKind("created_at", "Created"), SortFieldKind("updated_at", "Updated"), SortFieldKind("title", "Title"),
            SortFieldKind("seconds", "Time"), SortFieldKind("random", "Random"),
        )
        FilterMode.Performers -> listOf(
            SortFieldKind("name", "Name"), SortFieldKind("scenes_count", "Scene count"), SortFieldKind("images_count", "Image count"),
            SortFieldKind("galleries_count", "Gallery count"), SortFieldKind("birthdate", "Birthday"), SortFieldKind("updated_at", "Updated"),
            SortFieldKind("created_at", "Created"), SortFieldKind("o_counter", "O Count"), SortFieldKind("rating", "Rating"),
            SortFieldKind("random", "Random"),
        )
        FilterMode.Tags -> listOf(
            SortFieldKind("name", "Name"), SortFieldKind("scenes_count", "Scene count"), SortFieldKind("images_count", "Image count"),
            SortFieldKind("galleries_count", "Gallery count"), SortFieldKind("scene_markers_count", "Marker count"),
            SortFieldKind("performers_count", "Performer count"), SortFieldKind("updated_at", "Updated"), SortFieldKind("created_at", "Created"),
            SortFieldKind("random", "Random"),
        )
        FilterMode.Studios -> listOf(
            SortFieldKind("name", "Name"), SortFieldKind("scenes_count", "Scene count"), SortFieldKind("rating", "Rating"),
            SortFieldKind("performer_count", "Performer count"), SortFieldKind("performer_count_all", "Performer count incl. sub-studios"),
            SortFieldKind("o_counter", "O Count"), SortFieldKind("o_counter_all", "O Count incl. sub-studios"), SortFieldKind("scene_markers_count", "Marker count"),
            SortFieldKind("galleries_count", "Gallery count"), SortFieldKind("images_count", "Image count"), SortFieldKind("updated_at", "Updated"), SortFieldKind("created_at", "Created"),
            SortFieldKind("random", "Random"),
        )
        FilterMode.Galleries -> listOf(
            SortFieldKind("title", "Title"), SortFieldKind("date", "Date"), SortFieldKind("rating", "Rating"),
            SortFieldKind("created_at", "Created"), SortFieldKind("updated_at", "Updated"), SortFieldKind("images_count", "Image count"),
            SortFieldKind("performer_age", "Performer age"), SortFieldKind("random", "Random"),
        )
        FilterMode.Images -> listOf(
            SortFieldKind("title", "Title"), SortFieldKind("date", "Date"), SortFieldKind("rating", "Rating"),
            SortFieldKind("created_at", "Created"), SortFieldKind("updated_at", "Updated"), SortFieldKind("performer_age", "Performer age"), SortFieldKind("random", "Random"),
        )
        FilterMode.Groups -> listOf(
            SortFieldKind("name", "Name"), SortFieldKind("scenes_count", "Scene count"), SortFieldKind("galleries_count", "Gallery count"),
            SortFieldKind("performer_count", "Performer count"), SortFieldKind("date", "Date"), SortFieldKind("rating", "Rating"),
            SortFieldKind("updated_at", "Updated"), SortFieldKind("created_at", "Created"), SortFieldKind("random", "Random"),
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

fun Tag.badgeCount(badge: CatalogCardBadge): BadgeCount? = badgeOrScenes(
    badge,
    when (badge) {
        CatalogCardBadge.Scenes -> sceneCount
        CatalogCardBadge.Images -> imageCount
        CatalogCardBadge.Galleries -> galleryCount
        CatalogCardBadge.Performers, CatalogCardBadge.PerformersAll -> performerCount
        CatalogCardBadge.Markers -> sceneMarkerCount
        else -> null
    },
    sceneCount,
)

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
