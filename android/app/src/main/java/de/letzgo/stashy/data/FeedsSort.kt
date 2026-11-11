package de.letzgo.stashy.data

import de.letzgo.stashy.R
import de.letzgo.stashy.UiText
import de.letzgo.stashy.tr
/*
 * Sort options used by the Feeds tab. Raw values (enum names), labels, GraphQL fields and
 * directions are identical to iOS (`StashDBViewModel.SceneSortOption`,
 * `SceneMarkerSortOption`, `ImageSortOption`), so the per-server `ReelsModesConfig`
 * (`defaultSortOption`) stays interchangeable.
 */

/** Common surface of the three sort enums. */
interface FeedSort {
    val raw: String
    val displayName: String
    val sortField: String
    val direction: String
    val isRandom: Boolean get() = sortField == "random"
}

/** iOS: `StashDBViewModel.SceneSortOption`. */
enum class SceneSortOption(private val displayNameText: UiText, override val sortField: String, override val direction: String) : FeedSort {
    random(UiText(R.string.random), "random", "DESC"),
    dateDesc(UiText(R.string.date_newest_first), "date", "DESC"),
    dateAsc(UiText(R.string.date_oldest_first), "date", "ASC"),
    createdAtDesc(UiText(R.string.created_newest_first), "created_at", "DESC"),
    createdAtAsc(UiText(R.string.created_oldest_first), "created_at", "ASC"),
    titleAsc(UiText(R.string.title_z), "title", "ASC"),
    titleDesc(UiText(R.string.title_z_2), "title", "DESC"),
    durationDesc(UiText(R.string.duration_longest_first), "duration", "DESC"),
    durationAsc(UiText(R.string.duration_shortest_first), "duration", "ASC"),
    lastPlayedAtDesc(UiText(R.string.last_played_newest_first), "last_played_at", "DESC"),
    lastPlayedAtAsc(UiText(R.string.last_played_oldest_first), "last_played_at", "ASC"),
    playCountDesc(UiText(R.string.most_viewed), "play_count", "DESC"),
    playCountAsc(UiText(R.string.least_viewed), "play_count", "ASC"),
    playDurationDesc(UiText(R.string.watch_time_high_low), "play_duration", "DESC"),
    playDurationAsc(UiText(R.string.watch_time_low_high), "play_duration", "ASC"),
    oCounterDesc(UiText(R.string.counter_high_low), "o_counter", "DESC"),
    oCounterAsc(UiText(R.string.counter_low_high), "o_counter", "ASC"),
    ratingDesc(UiText(R.string.rating_high_low), "rating", "DESC"),
    ratingAsc(UiText(R.string.rating_low_high), "rating", "ASC");
    /** Read on use: a constant must not freeze its text at class load. */
    override val displayName: String get() = displayNameText.text

    override val raw: String get() = name

    companion object {
        fun from(raw: String?): SceneSortOption? = entries.firstOrNull { it.name == raw }

        /** iOS: `init?(graphqlField:direction:)` (saved filter `find_filter`). */
        fun fromGraphQL(field: String?, direction: String?): SceneSortOption? {
            val f = field?.lowercase() ?: return null
            if (f.startsWith("random")) return random
            val asc = direction?.uppercase() == "ASC"
            val key = if (f == "rating100") "rating" else f
            return entries.firstOrNull { it.sortField == key && it != random && (it.direction == "ASC") == asc }
                ?: entries.firstOrNull { it.sortField == key && it != random }
        }
    }
}

/** iOS: `StashDBViewModel.SceneMarkerSortOption`. */
enum class SceneMarkerSortOption(private val displayNameText: UiText, override val sortField: String, override val direction: String) : FeedSort {
    random(UiText(R.string.random), "random", "DESC"),
    createdAtDesc(UiText(R.string.created_newest_first), "created_at", "DESC"),
    createdAtAsc(UiText(R.string.created_oldest_first), "created_at", "ASC"),
    updatedAtDesc(UiText(R.string.updated_newest_first), "updated_at", "DESC"),
    updatedAtAsc(UiText(R.string.updated_oldest_first), "updated_at", "ASC"),
    titleAsc(UiText(R.string.title_z), "title", "ASC"),
    titleDesc(UiText(R.string.title_z_2), "title", "DESC"),
    secondsAsc(UiText(R.string.time_start), "seconds", "ASC"),
    secondsDesc(UiText(R.string.time_end), "seconds", "DESC");
    /** Read on use: a constant must not freeze its text at class load. */
    override val displayName: String get() = displayNameText.text

    override val raw: String get() = name

    companion object {
        fun from(raw: String?): SceneMarkerSortOption? = entries.firstOrNull { it.name == raw }
    }
}

/** iOS: `StashDBViewModel.ImageSortOption` (Clips, Pics). */
enum class ImageSortOption(private val displayNameText: UiText, override val sortField: String, override val direction: String) : FeedSort {
    titleAsc(UiText(R.string.title_z), "title", "ASC"),
    titleDesc(UiText(R.string.title_z_2), "title", "DESC"),
    dateDesc(UiText(R.string.date_newest), "date", "DESC"),
    dateAsc(UiText(R.string.date_oldest), "date", "ASC"),
    ratingDesc(UiText(R.string.rating_high_low), "rating", "DESC"),
    ratingAsc(UiText(R.string.rating_low_high), "rating", "ASC"),
    createdAtDesc(UiText(R.string.created_newest), "created_at", "DESC"),
    createdAtAsc(UiText(R.string.created_oldest), "created_at", "ASC"),
    updatedAtDesc(UiText(R.string.updated_newest), "updated_at", "DESC"),
    updatedAtAsc(UiText(R.string.updated_oldest), "updated_at", "ASC"),
    random(UiText(R.string.random), "random", "DESC");
    /** Read on use: a constant must not freeze its text at class load. */
    override val displayName: String get() = displayNameText.text

    override val raw: String get() = name

    companion object {
        fun from(raw: String?): ImageSortOption? = entries.firstOrNull { it.name == raw }

        /** iOS: `ImageSortOption.init?(graphqlField:direction:)`. */
        fun fromGraphQL(field: String?, direction: String?): ImageSortOption? {
            val f = field?.lowercase() ?: return null
            if (f.startsWith("random")) return random
            val asc = direction?.uppercase() == "ASC"
            val key = if (f == "rating100") "rating" else f
            return entries.firstOrNull { it.sortField == key && it != random && (it.direction == "ASC") == asc }
        }
    }
}

/**
 * Sort "field kinds" of the Filter & Sort sheets (iOS `SceneLiveSortFieldKind`,
 * `MarkerLiveSortFieldKind`, images sheet): one menu entry per field plus Asc/Desc chips.
 */

object FeedSortKinds {
    val scene = listOf(
        SortFieldKind("date", "Date"), SortFieldKind("created_at", "Created"), SortFieldKind("title", "Title"),
        SortFieldKind("duration", "Duration"), SortFieldKind("last_played_at", "Last Played"),
        SortFieldKind("play_count", "Play Count"), SortFieldKind("play_duration", "Watch time"),
        SortFieldKind("o_counter", "O Count"), SortFieldKind("rating", "Rating"), SortFieldKind("random", "Random"),
    )
    val marker = listOf(
        SortFieldKind("created_at", "Created"), SortFieldKind("updated_at", "Updated"), SortFieldKind("title", "Title"),
        SortFieldKind("seconds", "Time"), SortFieldKind("random", "Random"),
    )
    val image = listOf(
        SortFieldKind("title", "Title"), SortFieldKind("date", "Date"), SortFieldKind("rating", "Rating"),
        SortFieldKind("created_at", "Created"), SortFieldKind("updated_at", "Updated"), SortFieldKind("random", "Random"),
    )

    /**
     * iOS: `sceneSortOption(ascending:)` & co. Picks the option of [all] with [field] and the
     * wanted direction (random has no direction).
     */
    fun <T : FeedSort> option(all: List<T>, field: String, ascending: Boolean): T? {
        if (field == "random") return all.firstOrNull { it.isRandom }
        return all.firstOrNull { it.sortField == field && (it.direction == "ASC") == ascending }
            ?: all.firstOrNull { it.sortField == field }
    }
}
