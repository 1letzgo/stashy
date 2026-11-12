package de.letzgo.stashy.data.tools

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

// Pure RateMe logic (iOS `RateMeViewModel` in `stashy/RateMeToolsView.swift`) — no Android APIs,
// unit tested in `RateMeLogicTest`.

/** iOS: `RateMeViewModel.Mode` (raw values persisted under `stashy.rateMe.mode`). */
enum class RateMeMode(val raw: String, @androidx.annotation.StringRes private val labelRes: Int) {
    Scenes("scenes", R.string.scenes),
    Images("images", R.string.images);
    /** Read on use: a constant must not freeze its text at class load. */
    val label: String get() = tr(labelRes)

    companion object {
        fun from(raw: String?): RateMeMode? = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS: `ImageListMediaKind` (raw values persisted under `stashy.rateMe.imageMediaKind`). */
enum class RateMeImageMediaKind(val raw: String) {
    All("all"),
    StillImage("stillImage"),
    Video("video");

    /** iOS: `RateMeToolsView.mediaKindTitle`. */
    val title: String get() = when (this) {
        All -> tr(R.string.any_media)
        StillImage -> tr(R.string.images)
        Video -> tr(R.string.videos)
    }

    /** iOS: `pathCriterion` — `ImageFilterType.path` with `MATCHES_REGEX`. */
    val pathCriterion: JsonObject? get() = when (this) {
        All -> null
        StillImage -> buildJsonObject {
            put("value", JsonPrimitive(STILL_IMAGE_PATH_REGEX)); put("modifier", JsonPrimitive("MATCHES_REGEX"))
        }
        Video -> buildJsonObject {
            put("value", JsonPrimitive(VIDEO_PATH_REGEX)); put("modifier", JsonPrimitive("MATCHES_REGEX"))
        }
    }

    companion object {
        const val STILL_IMAGE_PATH_REGEX = "(?i)\\.(jpe?g|png|webp|gif)$"
        const val VIDEO_PATH_REGEX = "(?i)\\.(mp4|mov|m4v|webm|mkv)$"
        fun from(raw: String?): RateMeImageMediaKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS: `FilterEntityOption`. */
data class RateMeOption(val id: String, val name: String)

/** iOS: `RateMeViewModel.Theme` — what a round draws from. */
sealed class RateMeTheme {
    data object Random : RateMeTheme()
    data object Newest : RateMeTheme()
    data object MostPlayed : RateMeTheme()
    data class Performer(val option: RateMeOption) : RateMeTheme()
    data class Studio(val option: RateMeOption) : RateMeTheme()
    data class Tag(val option: RateMeOption) : RateMeTheme()

    val id: String get() = when (this) {
        Random -> "random"
        Newest -> "newest"
        MostPlayed -> "mostPlayed"
        is Performer -> "performer-${option.id}"
        is Studio -> "studio-${option.id}"
        is Tag -> "tag-${option.id}"
    }

    val label: String get() = when (this) {
        Random -> tr(R.string.random)
        Newest -> tr(R.string.newest)
        MostPlayed -> tr(R.string.most_played)
        is Performer -> option.name
        is Studio -> option.name
        is Tag -> option.name
    }
}

/** iOS: `RateMeToolsView.ThemePickerKind`. */
enum class RateMeThemePickerKind(val raw: String, @androidx.annotation.StringRes private val titleRes: Int) {
    Performer("performer", R.string.performer),
    Studio("studio", R.string.studio),
    Tag("tag", R.string.tag);
    /** Read on use: a constant must not freeze its text at class load. */
    val title: String get() = tr(titleRes)

    fun theme(option: RateMeOption): RateMeTheme = when (this) {
        Performer -> RateMeTheme.Performer(option)
        Studio -> RateMeTheme.Studio(option)
        Tag -> RateMeTheme.Tag(option)
    }

    /** iOS: `pickedTheme(for:)`. */
    fun picked(theme: RateMeTheme): RateMeTheme? = when {
        this == Performer && theme is RateMeTheme.Performer -> theme
        this == Studio && theme is RateMeTheme.Studio -> theme
        this == Tag && theme is RateMeTheme.Tag -> theme
        else -> null
    }

    /** iOS: `RateMeThemePickerSheet.storeKind`. */
    fun storeKind(mode: RateMeMode): RateMePickerKind = when (this) {
        Performer -> RateMePickerKind.Performers
        Studio -> if (mode == RateMeMode.Scenes) RateMePickerKind.Studios else RateMePickerKind.ImageStudios
        Tag -> if (mode == RateMeMode.Scenes) RateMePickerKind.Tags else RateMePickerKind.ImageTags
    }
}

/** The `FilterPickerOptionsStore.Kind`s RateMe uses. */
enum class RateMePickerKind { Performers, Studios, ImageStudios, Tags, ImageTags }

object RateMeLogic {
    const val PAGE_SIZE = 20
    /** iOS: four page fetches before giving up when everything was skipped. */
    const val MAX_PAGE_ATTEMPTS = 4

    /** iOS: `availableFixedThemes` — images have no play count. */
    fun availableFixedThemes(mode: RateMeMode): List<RateMeTheme> =
        if (mode == RateMeMode.Scenes) listOf(RateMeTheme.Random, RateMeTheme.Newest, RateMeTheme.MostPlayed)
        else listOf(RateMeTheme.Random, RateMeTheme.Newest)

    /** iOS: `themeCriteria`. */
    fun themeCriteria(theme: RateMeTheme): JsonObject = when (theme) {
        RateMeTheme.Random, RateMeTheme.Newest, RateMeTheme.MostPlayed -> JsonObject(emptyMap())
        is RateMeTheme.Performer -> buildJsonObject {
            put("performers", buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(theme.option.id))))
                put("modifier", JsonPrimitive("INCLUDES"))
            })
        }
        is RateMeTheme.Studio -> buildJsonObject {
            put("studios", buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(theme.option.id))))
                put("modifier", JsonPrimitive("INCLUDES"))
                put("depth", JsonPrimitive(0))
            })
        }
        is RateMeTheme.Tag -> buildJsonObject {
            put("tags", buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(theme.option.id))))
                put("modifier", JsonPrimitive("INCLUDES"))
                put("depth", JsonPrimitive(0))
            })
        }
    }

    /** iOS: `unratedFilter` — `IntCriterionInput.value` is required by GraphQL even for IS_NULL. */
    fun unratedFilter(theme: RateMeTheme): JsonObject = JsonObject(
        themeCriteria(theme) + ("rating100" to buildJsonObject {
            put("modifier", JsonPrimitive("IS_NULL")); put("value", JsonPrimitive(0))
        }),
    )

    /** iOS: `unratedImageFilter` — plus the media-kind `path` regex. */
    fun unratedImageFilter(theme: RateMeTheme, kind: RateMeImageMediaKind): JsonObject {
        val base = unratedFilter(theme)
        val path = kind.pathCriterion ?: return base
        return JsonObject(base + ("path" to path))
    }

    /** iOS: `pageFilter` sort — `random_<seed>` (Stash rejects bare `random`), Newest, Most played. */
    fun sort(theme: RateMeTheme, random: Random = Random.Default): Pair<String, String> = when (theme) {
        RateMeTheme.Newest -> "created_at" to "DESC"
        RateMeTheme.MostPlayed -> "play_count" to "DESC"
        else -> "random_${random.nextInt(0, 100_000_000)}" to "ASC"
    }

    /** iOS: `pageFilter` — a page of 20 so skipped items can be stepped over. */
    fun pageFilter(theme: RateMeTheme, random: Random = Random.Default): JsonObject {
        val (sort, direction) = sort(theme, random)
        return buildJsonObject {
            put("per_page", JsonPrimitive(PAGE_SIZE))
            put("sort", JsonPrimitive(sort))
            put("direction", JsonPrimitive(direction))
        }
    }

    /** Whether a fully skipped page resets the skip list (fixed sorts return the same page again). */
    fun resetsSkipsOnExhaustedPage(theme: RateMeTheme, mode: RateMeMode): Boolean =
        if (mode == RateMeMode.Scenes) theme == RateMeTheme.Newest || theme == RateMeTheme.MostPlayed
        else theme == RateMeTheme.Newest

    /** iOS: `isVideoImage` — extension of basename / path / image URL (query stripped). */
    fun isVideoImage(basename: String?, path: String?, imageURL: String?): Boolean {
        val videoExtensions = setOf("MP4", "MOV", "M4V", "WEBM", "MKV")
        for (candidate in listOfNotNull(basename, path, imageURL)) {
            val clean = candidate.substringBefore('?')
            val last = clean.substringAfterLast('/')
            val ext = if (last.contains('.')) last.substringAfterLast('.').uppercase() else ""
            if (ext in videoExtensions) return true
        }
        return false
    }

    /** iOS: image aspect — `width / height` when known, else 16:9 for videos and 1 for stills. */
    fun imageAspect(width: Int?, height: Int?, isVideo: Boolean): Float =
        if (width != null && height != null && width > 0 && height > 0) width.toFloat() / height
        else if (isVideo) 16f / 9f else 1f

    /** Trimmed, non-empty names joined by ", "; null when none. */
    fun joinedNames(names: List<String?>): String? =
        names.mapNotNull { it?.trim()?.takeIf { s -> s.isNotEmpty() } }.joinToString(", ").takeIf { it.isNotEmpty() }

    /** iOS: trimmed title or the "Untitled …" fallback. */
    fun displayTitle(title: String?, mode: RateMeMode): String =
        title?.trim()?.takeIf { it.isNotEmpty() } ?: if (mode == RateMeMode.Scenes) tr(R.string.untitled_scene) else tr(R.string.untitled_image)

    /** iOS: "No unrated scenes left in Random." */
    fun noneLeftMessage(mode: RateMeMode, theme: RateMeTheme): String =
        tr(R.string.empty_unrated_arg_left_in_arg, mode.label.lowercase(), theme.label)

    fun deleteConfirmationTitle(mode: RateMeMode): String =
        if (mode == RateMeMode.Scenes) tr(R.string.confirm_really_delete_scene_and_files) else tr(R.string.confirm_really_delete_image_and_files)

    fun deleteConfirmationMessage(mode: RateMeMode, itemTitle: String?): String {
        val name = itemTitle ?: if (mode == RateMeMode.Scenes) tr(R.string.this_scene) else tr(R.string.this_image)
        return tr(R.string.hint_arg_and_all_associated_files, name)
    }

    // MARK: StarRatingView

    /** iOS: `StarRatingView.stars` — `round(rating / 20)` clamped to 0…5. */
    fun stars(rating100: Int?): Int {
        val r = rating100 ?: return 0
        return min(5, max(0, MatchElo.swiftRound(r / 20.0).toInt()))
    }

    /** iOS: `rating100FromStars` — 0 stars = no rating. */
    fun rating100FromStars(stars: Int): Int? = if (stars > 0) stars * 20 else null

    /** iOS: tapping star [index] (1…5); tapping the current star clears the rating. */
    fun ratingAfterTap(current: Int?, index: Int): Int? =
        if (index == stars(current)) null else rating100FromStars(index)
}
