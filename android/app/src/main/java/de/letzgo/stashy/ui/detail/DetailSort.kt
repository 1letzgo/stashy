package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import de.letzgo.stashy.data.Prefs
import kotlin.math.roundToInt

/**
 * Detail scene / image sort values (iOS: `StashDBViewModel.SceneSortOption`, `ImageSortOption`)
 * behind the persisted `DetailViewsSortConfig_<context>` defaults. `raw` is the iOS rawValue
 * (persisted), `label` the iOS `displayName`. The detail lists themselves sort through
 * [de.letzgo.stashy.data.SortCatalog] in their filter & sort sheets.
 */
interface SortChoice {
    val raw: String
    val label: String
    val field: String
    val direction: String
}

object DetailSort {
    enum class Scene(override val raw: String, @androidx.annotation.StringRes private val labelRes: Int, override val field: String, override val direction: String) : SortChoice {
        Random("random", R.string.random, "random", "DESC"),
        DateDesc("dateDesc", R.string.date_newest_first, "date", "DESC"),
        DateAsc("dateAsc", R.string.date_oldest_first, "date", "ASC"),
        CreatedAtDesc("createdAtDesc", R.string.created_newest_first, "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", R.string.created_oldest_first, "created_at", "ASC"),
        TitleAsc("titleAsc", R.string.title_z, "title", "ASC"),
        TitleDesc("titleDesc", R.string.title_z_2, "title", "DESC"),
        DurationDesc("durationDesc", R.string.duration_longest_first, "duration", "DESC"),
        DurationAsc("durationAsc", R.string.duration_shortest_first, "duration", "ASC"),
        LastPlayedAtDesc("lastPlayedAtDesc", R.string.last_played_newest_first, "last_played_at", "DESC"),
        LastPlayedAtAsc("lastPlayedAtAsc", R.string.last_played_oldest_first, "last_played_at", "ASC"),
        PlayCountDesc("playCountDesc", R.string.most_viewed, "play_count", "DESC"),
        PlayCountAsc("playCountAsc", R.string.least_viewed, "play_count", "ASC"),
        PlayDurationDesc("playDurationDesc", R.string.watch_time_high_low, "play_duration", "DESC"),
        PlayDurationAsc("playDurationAsc", R.string.watch_time_low_high, "play_duration", "ASC"),
        OCounterDesc("oCounterDesc", R.string.counter_high_low, "o_counter", "DESC"),
        OCounterAsc("oCounterAsc", R.string.counter_low_high, "o_counter", "ASC"),
        RatingDesc("ratingDesc", R.string.rating_high_low, "rating", "DESC"),
        RatingAsc("ratingAsc", R.string.rating_low_high, "rating", "ASC");
    /** Read on use: a constant must not freeze its text at class load. */
    override val label: String get() = tr(labelRes)
        companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } }
    }

    enum class Image(override val raw: String, @androidx.annotation.StringRes private val labelRes: Int, override val field: String, override val direction: String) : SortChoice {
        TitleAsc("titleAsc", R.string.title_z, "title", "ASC"),
        TitleDesc("titleDesc", R.string.title_z_2, "title", "DESC"),
        DateDesc("dateDesc", R.string.date_newest, "date", "DESC"),
        DateAsc("dateAsc", R.string.date_oldest, "date", "ASC"),
        RatingDesc("ratingDesc", R.string.rating_high_low, "rating", "DESC"),
        RatingAsc("ratingAsc", R.string.rating_low_high, "rating", "ASC"),
        CreatedAtDesc("createdAtDesc", R.string.created_newest, "created_at", "DESC"),
        CreatedAtAsc("createdAtAsc", R.string.created_oldest, "created_at", "ASC"),
        UpdatedAtDesc("updatedAtDesc", R.string.updated_newest, "updated_at", "DESC"),
        UpdatedAtAsc("updatedAtAsc", R.string.updated_oldest, "updated_at", "ASC"),
        Random("random", R.string.random, "random", "DESC");
    /** Read on use: a constant must not freeze its text at class load. */
    override val label: String get() = tr(labelRes)
        companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } }
    }

}

/** iOS: `DetailViewContext` (rawValues are the persisted keys). */
enum class DetailViewContext(val raw: String, @androidx.annotation.StringRes private val titleRes: Int) {
    Performer("performer_detail", R.string.performer_scenes),
    Studio("studio_detail", R.string.studio_scenes),
    Tag("tag_detail", R.string.tag_scenes),
    Gallery("gallery_detail", R.string.gallery_images),
    Group("group_detail", R.string.group_scenes);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)

    /** iOS `settingsRowTitle`. */
    val settingsRowTitle: String get() = if (this == Gallery) tr(R.string.images_sort) else tr(R.string.scenes_sort)
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
