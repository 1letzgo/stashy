package de.letzgo.stashy.data

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
enum class SceneSortOption(override val displayName: String, override val sortField: String, override val direction: String) : FeedSort {
    random("Random", "random", "DESC"),
    dateDesc("Date (Newest First)", "date", "DESC"),
    dateAsc("Date (Oldest First)", "date", "ASC"),
    createdAtDesc("Created (Newest First)", "created_at", "DESC"),
    createdAtAsc("Created (Oldest First)", "created_at", "ASC"),
    titleAsc("Title (A-Z)", "title", "ASC"),
    titleDesc("Title (Z-A)", "title", "DESC"),
    durationDesc("Duration (Longest First)", "duration", "DESC"),
    durationAsc("Duration (Shortest First)", "duration", "ASC"),
    lastPlayedAtDesc("Last Played (Newest First)", "last_played_at", "DESC"),
    lastPlayedAtAsc("Last Played (Oldest First)", "last_played_at", "ASC"),
    playCountDesc("Most Viewed", "play_count", "DESC"),
    playCountAsc("Least Viewed", "play_count", "ASC"),
    playDurationDesc("Watch Time (High-Low)", "play_duration", "DESC"),
    playDurationAsc("Watch Time (Low-High)", "play_duration", "ASC"),
    oCounterDesc("Counter (High-Low)", "o_counter", "DESC"),
    oCounterAsc("Counter (Low-High)", "o_counter", "ASC"),
    ratingDesc("Rating (High-Low)", "rating", "DESC"),
    ratingAsc("Rating (Low-High)", "rating", "ASC");

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
enum class SceneMarkerSortOption(override val displayName: String, override val sortField: String, override val direction: String) : FeedSort {
    random("Random", "random", "DESC"),
    createdAtDesc("Created (Newest First)", "created_at", "DESC"),
    createdAtAsc("Created (Oldest First)", "created_at", "ASC"),
    updatedAtDesc("Updated (Newest First)", "updated_at", "DESC"),
    updatedAtAsc("Updated (Oldest First)", "updated_at", "ASC"),
    titleAsc("Title (A-Z)", "title", "ASC"),
    titleDesc("Title (Z-A)", "title", "DESC"),
    secondsAsc("Time (Start)", "seconds", "ASC"),
    secondsDesc("Time (End)", "seconds", "DESC");

    override val raw: String get() = name

    companion object {
        fun from(raw: String?): SceneMarkerSortOption? = entries.firstOrNull { it.name == raw }
    }
}

/** iOS: `StashDBViewModel.ImageSortOption` (Clips, Pics). */
enum class ImageSortOption(override val displayName: String, override val sortField: String, override val direction: String) : FeedSort {
    titleAsc("Title (A-Z)", "title", "ASC"),
    titleDesc("Title (Z-A)", "title", "DESC"),
    dateDesc("Date (Newest)", "date", "DESC"),
    dateAsc("Date (Oldest)", "date", "ASC"),
    ratingDesc("Rating (High-Low)", "rating", "DESC"),
    ratingAsc("Rating (Low-High)", "rating", "ASC"),
    createdAtDesc("Created (Newest)", "created_at", "DESC"),
    createdAtAsc("Created (Oldest)", "created_at", "ASC"),
    updatedAtDesc("Updated (Newest)", "updated_at", "DESC"),
    updatedAtAsc("Updated (Oldest)", "updated_at", "ASC"),
    random("Random", "random", "DESC");

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
data class SortFieldKind(val field: String, val menuLabel: String)

object FeedSortKinds {
    val scene = listOf(
        SortFieldKind("date", "Date"), SortFieldKind("created_at", "Created"), SortFieldKind("title", "Title"),
        SortFieldKind("duration", "Duration"), SortFieldKind("last_played_at", "Last played"),
        SortFieldKind("play_count", "Play count"), SortFieldKind("play_duration", "Watch time"),
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
