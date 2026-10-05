package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.FindFilter
import de.letzgo.stashy.data.Prefs
import kotlin.math.roundToInt

/**
 * Sort options used inside the detail screens (iOS: `StashDBViewModel.SceneSortOption`,
 * `GallerySortOption`, `ImageSortOption`, `PerformerSortOption`, `StudioSortOption`,
 * `TagSortOption`). `raw` is the iOS rawValue (persisted), `label` the iOS `displayName`.
 * Namespaced in [DetailSort] so it can live next to the catalog's own copies until merge.
 */
interface SortChoice {
    val raw: String
    val label: String
    val field: String
    val direction: String
}

object DetailSort {
    /** iOS `randomSort(_:)` — `random_<seed>`; the seed is refreshed when Random is picked again. */
    var randomSeed: Int = (1..1_000_000).random()
        private set
    fun refreshRandomSeed() { randomSeed = (1..1_000_000).random() }

    fun findFilter(page: Int, perPage: Int, sort: SortChoice): FindFilter =
        FindFilter(page, perPage, if (sort.field == "random") "random_$randomSeed" else sort.field, sort.direction)

    enum class Scene(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        Random("random", "Random", "random", "DESC"),
        DateDesc("dateDesc", "Date (Newest First)", "date", "DESC"),
        DateAsc("dateAsc", "Date (Oldest First)", "date", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest First)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        TitleAsc("titleAsc", "Title (A-Z)", "title", "ASC"),
        TitleDesc("titleDesc", "Title (Z-A)", "title", "DESC"),
        DurationDesc("durationDesc", "Duration (Longest First)", "duration", "DESC"),
        DurationAsc("durationAsc", "Duration (Shortest First)", "duration", "ASC"),
        LastPlayedAtDesc("lastPlayedAtDesc", "Last Played (Newest First)", "last_played_at", "DESC"),
        LastPlayedAtAsc("lastPlayedAtAsc", "Last Played (Oldest First)", "last_played_at", "ASC"),
        PlayCountDesc("playCountDesc", "Most Viewed", "play_count", "DESC"),
        PlayCountAsc("playCountAsc", "Least Viewed", "play_count", "ASC"),
        PlayDurationDesc("playDurationDesc", "Watch Time (High-Low)", "play_duration", "DESC"),
        PlayDurationAsc("playDurationAsc", "Watch Time (Low-High)", "play_duration", "ASC"),
        OCounterDesc("oCounterDesc", "Counter (High-Low)", "o_counter", "DESC"),
        OCounterAsc("oCounterAsc", "Counter (Low-High)", "o_counter", "ASC"),
        RatingDesc("ratingDesc", "Rating (High-Low)", "rating", "DESC"),
        RatingAsc("ratingAsc", "Rating (Low-High)", "rating", "ASC");
        companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } }
    }

    enum class Gallery(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        TitleAsc("titleAsc", "Name (A-Z)", "title", "ASC"),
        TitleDesc("titleDesc", "Name (Z-A)", "title", "DESC"),
        DateDesc("dateDesc", "Date (Newest)", "date", "DESC"),
        DateAsc("dateAsc", "Date (Oldest)", "date", "ASC"),
        RatingDesc("ratingDesc", "Rating (High-Low)", "rating", "DESC"),
        RatingAsc("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest)", "created_at", "ASC"),
        UpdatedAtDesc("updatedAtDesc", "Updated (Newest)", "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", "Updated (Oldest)", "updated_at", "ASC"),
        ImageCountDesc("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"),
        ImageCountAsc("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        Random("random", "Random", "random", "DESC");
        companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } }
    }

    enum class Image(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        TitleAsc("titleAsc", "Title (A-Z)", "title", "ASC"),
        TitleDesc("titleDesc", "Title (Z-A)", "title", "DESC"),
        DateDesc("dateDesc", "Date (Newest)", "date", "DESC"),
        DateAsc("dateAsc", "Date (Oldest)", "date", "ASC"),
        RatingDesc("ratingDesc", "Rating (High-Low)", "rating", "DESC"),
        RatingAsc("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest)", "created_at", "ASC"),
        UpdatedAtDesc("updatedAtDesc", "Updated (Newest)", "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", "Updated (Oldest)", "updated_at", "ASC"),
        Random("random", "Random", "random", "DESC");
        companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } }
    }

    enum class Performer(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        Random("random", "Random", "random", "DESC"),
        NameAsc("nameAsc", "Name (A-Z)", "name", "ASC"),
        NameDesc("nameDesc", "Name (Z-A)", "name", "DESC"),
        SceneCountDesc("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"),
        SceneCountAsc("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        ImageCountDesc("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"),
        ImageCountAsc("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        GalleryCountDesc("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"),
        GalleryCountAsc("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        BirthdateDesc("birthdateDesc", "Birthday (Youngest First)", "birthdate", "DESC"),
        BirthdateAsc("birthdateAsc", "Birthday (Oldest First)", "birthdate", "ASC"),
        UpdatedAtDesc("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest First)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        OCountDesc("oCountDesc", "O Count (High-Low)", "o_counter", "DESC"),
        OCountAsc("oCountAsc", "O Count (Low-High)", "o_counter", "ASC"),
        RatingDesc("ratingDesc", "Rating (High-Low)", "rating", "DESC"),
        RatingAsc("ratingAsc", "Rating (Low-High)", "rating", "ASC");
    }

    enum class Studio(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        Random("random", "Random", "random", "DESC"),
        NameAsc("nameAsc", "Name (A-Z)", "name", "ASC"),
        NameDesc("nameDesc", "Name (Z-A)", "name", "DESC"),
        SceneCountDesc("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"),
        SceneCountAsc("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        UpdatedAtDesc("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest First)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest First)", "created_at", "ASC"),
        RatingDesc("ratingDesc", "Rating (High-Low)", "rating", "DESC"),
        RatingAsc("ratingAsc", "Rating (Low-High)", "rating", "ASC"),
        PerformerCountDesc("performerCountDesc", "Performer Count (High-Low)", "performer_count", "DESC"),
        PerformerCountAsc("performerCountAsc", "Performer Count (Low-High)", "performer_count", "ASC"),
        GalleryCountDesc("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"),
        GalleryCountAsc("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        ImageCountDesc("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"),
        ImageCountAsc("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC");
    }

    enum class Tag(override val raw: String, override val label: String, override val field: String, override val direction: String) : SortChoice {
        Random("random", "Random", "random", "DESC"),
        NameAsc("nameAsc", "Name (A-Z)", "name", "ASC"),
        NameDesc("nameDesc", "Name (Z-A)", "name", "DESC"),
        SceneCountDesc("sceneCountDesc", "Scene Count (High-Low)", "scenes_count", "DESC"),
        SceneCountAsc("sceneCountAsc", "Scene Count (Low-High)", "scenes_count", "ASC"),
        ImageCountDesc("imageCountDesc", "Image Count (High-Low)", "images_count", "DESC"),
        ImageCountAsc("imageCountAsc", "Image Count (Low-High)", "images_count", "ASC"),
        GalleryCountDesc("galleryCountDesc", "Gallery Count (High-Low)", "galleries_count", "DESC"),
        GalleryCountAsc("galleryCountAsc", "Gallery Count (Low-High)", "galleries_count", "ASC"),
        MarkerCountDesc("markerCountDesc", "Marker Count (High-Low)", "scene_markers_count", "DESC"),
        MarkerCountAsc("markerCountAsc", "Marker Count (Low-High)", "scene_markers_count", "ASC"),
        PerformerCountDesc("performerCountDesc", "Performer Count (High-Low)", "performers_count", "DESC"),
        PerformerCountAsc("performerCountAsc", "Performer Count (Low-High)", "performers_count", "ASC"),
        UpdatedAtDesc("updatedAtDesc", "Updated (Newest First)", "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", "Updated (Oldest First)", "updated_at", "ASC"),
        CreatedAtDesc("createdAtDesc", "Created (Newest First)", "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", "Created (Oldest First)", "created_at", "ASC");
    }
}

/** iOS: `DetailViewContext` (rawValues are the persisted keys). */
enum class DetailViewContext(val raw: String, val title: String) {
    Performer("performer_detail", "Performer Scenes"),
    Studio("studio_detail", "Studio Scenes"),
    Tag("tag_detail", "Tag Scenes"),
    Gallery("gallery_detail", "Gallery Images"),
    Group("group_detail", "Group Scenes");

    /** iOS `settingsRowTitle`. */
    val settingsRowTitle: String get() = if (this == Gallery) "Images Sort" else "Scenes Sort"
}

/**
 * iOS: `TabManager` detail sort persistence — `DetailViewsSortConfig_<context>_<serverID>`,
 * default `dateDesc`; a session override (sort menu inside the detail screen) wins until restart.
 */
object DetailViewConfig {
    private const val KEY = "DetailViewsSortConfig"
    private val session = mutableMapOf<String, String>()

    fun key(context: DetailViewContext, serverId: String?): String =
        "${KEY}_${context.raw}" + (serverId?.let { "_$it" } ?: "")

    fun persistentSortOption(context: DetailViewContext): String =
        Prefs.string(Prefs.serverKey("${KEY}_${context.raw}")) ?: Prefs.string("${KEY}_${context.raw}") ?: "dateDesc"

    fun sortOption(context: DetailViewContext): String = session[context.raw] ?: persistentSortOption(context)

    fun setSortOption(context: DetailViewContext, raw: String) { session[context.raw] = raw }

    fun setPersistentSortOption(context: DetailViewContext, raw: String) {
        session[context.raw] = raw
        Prefs.setString(Prefs.serverKey("${KEY}_${context.raw}"), raw)
    }

    /** iOS `resolvedDetailSceneSortFallback(for:)`. */
    fun sceneSort(context: DetailViewContext): DetailSort.Scene = DetailSort.Scene.from(sortOption(context)) ?: DetailSort.Scene.DateDesc

    fun imageSort(context: DetailViewContext): DetailSort.Image = DetailSort.Image.from(sortOption(context)) ?: DetailSort.Image.DateDesc
}

/** iOS `DesignTokens.Grid.adaptiveColumnCount`. */
fun adaptiveColumnCount(width: Float, ideal: Float, minimum: Int, maximum: Int): Int {
    if (width <= 0f || ideal <= 0f) return minimum
    return (width / ideal).roundToInt().coerceIn(minimum, maximum)
}

/** iOS `StarRatingView` / fullscreen: rating100 → 0…5 stars. */
fun starsFromRating(rating100: Int?): Int = rating100?.let { Math.round(it / 20.0).toInt().coerceIn(0, 5) } ?: 0
