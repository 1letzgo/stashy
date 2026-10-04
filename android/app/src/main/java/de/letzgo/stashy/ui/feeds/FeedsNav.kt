package de.letzgo.stashy.ui.feeds

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.FeedsQuery
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImageSortOption
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SceneSortOption
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav

/** iOS: `HomeChannelSourceKind` — where a dashboard channel opens (raw values `scenes`, `clips`). */
enum class FeedsChannelDestination { scenes, clips }

/**
 * iOS: `ReelsDeepLink` — what a hand-off into Feeds carries. Built by [FeedsNav]; consumed once by
 * the Feeds screen (which always rebuilds its timeline for it).
 */
data class FeedsDeepLink(
    val performer: IdName? = null,
    val tags: List<IdName> = emptyList(),
    val studio: IdName? = null,
    /** `ReelsMode` raw value ("Scenes", "Markers", "Clips", "Previews", "Pics"). */
    val mode: String? = null,
    /** Channel: saved scene filter (Feeds → Scenes) and its sort raw value. */
    val sceneFilter: SavedFilter? = null,
    val sceneSort: String? = null,
    /** Channel: saved image filter (Feeds → Clips) and its sort raw value. */
    val clipFilter: SavedFilter? = null,
    val clipSort: String? = null,
) {
    val isEmpty: Boolean get() = performer == null && tags.isEmpty() && studio == null && mode == null &&
        sceneFilter == null && sceneSort == null && clipFilter == null && clipSort == null
}

/**
 * Public entry into the Feeds tab (iOS: `NavigationCoordinator.navigateToReels*`). Switches to
 * the Feeds tab, pops it to its root and hands over the link; the feed restarts from the top.
 */
object FeedsNav {
    /** Pending link, consumed by `FeedsScreen`. */
    var pending by mutableStateOf<FeedsDeepLink?>(null)
        private set

    /** Bumped per hand-off so an already visible Feeds screen re-applies. */
    var token by mutableStateOf(0)
        private set

    /**
     * Dashboard channel (iOS `HomeChannelsRowView.open` → `navigateToReelsChannel` /
     * `navigateToReelsClipsChannel`). [sortRaw] is a `SceneSortOption` / `ImageSortOption` raw
     * value; null resolves it from the filter like iOS `HomeChannel.sceneFilter(_:)` /
     * `clipFilter(_:)` (`resolvedSceneSort ?? .dateDesc`).
     */
    fun openChannel(filter: SavedFilter, destination: FeedsChannelDestination, sortRaw: String? = null) {
        val link = when (destination) {
            FeedsChannelDestination.scenes -> FeedsDeepLink(
                mode = ReelsModeType.scenes.modeRaw, sceneFilter = filter,
                sceneSort = sortRaw ?: (FeedsQuery.resolvedSceneSort(filter) ?: SceneSortOption.dateDesc).raw,
            )
            FeedsChannelDestination.clips -> FeedsDeepLink(
                mode = ReelsModeType.clips.modeRaw, clipFilter = filter,
                clipSort = sortRaw ?: (FeedsQuery.resolvedImageSort(filter) ?: ImageSortOption.dateDesc).raw,
            )
        }
        open(link)
    }

    /** Channel by the iOS `HomeChannelItemConfig.destination` raw value ("scenes" / "clips"). */
    fun openChannel(filter: SavedFilter, destinationRaw: String, sortRaw: String? = null) =
        openChannel(filter, FeedsChannelDestination.entries.firstOrNull { it.name == destinationRaw } ?: FeedsChannelDestination.scenes, sortRaw)

    /**
     * Performer / tag / studio → Feeds (iOS `navigateToReels(performer:tags:studio:mode:)`).
     * [mode] is a `ReelsMode` raw value; null = the first enabled mode.
     */
    fun openFiltered(performer: IdName? = null, tags: List<IdName> = emptyList(), studio: IdName? = null, mode: String? = null) =
        open(FeedsDeepLink(performer = performer, tags = tags, studio = studio, mode = mode))

    /** iOS `navigateToStashLine(performer:)` — Pics for one performer. */
    fun openPics(performer: IdName) = open(FeedsDeepLink(performer = performer, mode = ReelsModeType.pics.modeRaw))

    fun open(link: FeedsDeepLink) {
        pending = link
        token++
        Nav.popToRoot(MainTab.Feeds)
        Nav.tab = MainTab.Feeds
    }

    internal fun consume(): FeedsDeepLink? = pending.also { pending = null }
}
