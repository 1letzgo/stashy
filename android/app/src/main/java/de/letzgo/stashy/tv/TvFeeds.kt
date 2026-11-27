package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.FeedsConfig
import de.letzgo.stashy.data.FeedsSceneStartPosition
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.ImageSortOption
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SavedFiltersStore
import de.letzgo.stashy.data.SceneMarkerSortOption
import de.letzgo.stashy.data.SceneSortOption
import de.letzgo.stashy.data.TabManager

// MARK: - Mode helpers (iOS `ReelsModeType` extension in `TVFeedSession.swift`)

/** iOS `ReelsModeType.icon`. */
val ReelsModeType.tvIcon: ImageVector get() = when (this) {
    ReelsModeType.Markers -> TvIcons.bookmark
    ReelsModeType.Clips -> TvIcons.feedClips
    ReelsModeType.Previews -> TvIcons.feedPreviews
    else -> TvIcons.film
}

/** iOS `sortChoices` — the sort options of a mode as (raw value, label). */
val ReelsModeType.tvSortChoices: List<FeedSort> get() = when (this) {
    ReelsModeType.Markers -> SceneMarkerSortOption.entries
    ReelsModeType.Clips, ReelsModeType.Pics -> ImageSortOption.entries
    else -> SceneSortOption.entries
}

/** iOS `savedFilterMode` — the saved filters a Feeds default filter of this mode comes from. */
val ReelsModeType.tvFilterMode: FilterMode get() = when (this) {
    ReelsModeType.Markers -> FilterMode.SceneMarkers
    ReelsModeType.Clips, ReelsModeType.Pics -> FilterMode.Images
    else -> FilterMode.Scenes
}

/** iOS `defaultSortRaw` — Random while nothing is set. */
val ReelsModeType.tvDefaultSortRaw: String get() = FeedsConfig.defaultSort(this) ?: "random"

// MARK: - Root screen

/**
 * iOS: `TVFeedsView` — root of the Feeds sidebar entry: one card per enabled feed mode that opens
 * the full-screen pager ([TvFeedPlayerRoute]), plus the Feeds settings iOS keeps under
 * Settings › Feeds (continuous play, scenes start position, marker length; per mode: show in
 * Feeds, default sort, default saved filter). Same `TabManager` keys as iOS / tvOS / the phone.
 */
@Composable
fun TvFeeds(session: TvFeedSession, memory: TvFocusMemory) {
    val modes = TvFeedLogic.enabledModes(TabManager.enabledReelsModes)
    val firstCard = remember { FocusRequester() }
    LaunchedEffect(Unit) { SavedFiltersStore.load() }
    LazyColumn(
        Modifier.fillMaxSize().background(TvColors.background),
        contentPadding = PaddingValues(start = pt(80), end = pt(80), top = pt(60), bottom = pt(160)),
        verticalArrangement = Arrangement.spacedBy(pt(12)),
    ) {
        item(key = "title") {
            Column(Modifier.padding(bottom = pt(20)), verticalArrangement = Arrangement.spacedBy(pt(10))) {
                Text(tr(R.string.feeds), style = TvType.largeTitle, color = Color.White)
                Text(tr(R.string.hint_full_screen_one_after_another), style = TvType.title3, color = TvColors.secondary)
            }
        }
        item(key = "modes") {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(pt(40)), contentPadding = PaddingValues(vertical = pt(30), horizontal = pt(4))) {
                items(modes, key = { it.name }) { mode ->
                    ModeCard(
                        mode,
                        (if (mode == modes.first()) Modifier.focusRequester(firstCard) else Modifier).tvFocusMemory(memory, "mode.${mode.name}"),
                    ) { TvNav.push(TvFeedPlayerRoute(session, mode)) }
                }
            }
        }
        item(key = "settings.header") {
            Text(tr(R.string.feed_settings), Modifier.padding(top = pt(30), bottom = pt(8)), style = TvType.title2.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
        }
        item(key = "continuous") {
            TvToggleRow(tr(R.string.continuous_play), TabManager.reelsContinuousPlay, { TabManager.reelsContinuousPlay = it }, Modifier.widthIn(max = pt(1100)))
        }
        item(key = "start") {
            TvPickerRow(
                tr(R.string.scenes_start_at), FeedsSceneStartPosition.entries.map { TvOption(it, it.label) },
                TabManager.feedsSceneStartPosition, { TabManager.feedsSceneStartPosition = it }, Modifier.widthIn(max = pt(1100)),
            )
        }
        item(key = "markerLength") {
            TvPickerRow(
                tr(R.string.marker_length), TabManager.feedsMarkerLengthOptions.map { TvOption(it, "${it.toInt()} s") },
                TabManager.feedsMarkerDefaultSeconds, { TabManager.feedsMarkerDefaultSeconds = it }, Modifier.widthIn(max = pt(1100)),
            )
        }
        TvFeedLogic.tvFeedModes.forEach { mode ->
            item(key = "mode.settings.${mode.name}") { ModeSettings(mode) }
        }
    }
    TvInitialFocus(memory, firstCard, name = "feeds")
}

@Composable
private fun ModeCard(mode: ReelsModeType, modifier: Modifier, onClick: () -> Unit) {
    TvCardButton(onClick, modifier.width(pt(400)).height(pt(260)), radius = pt(16), focusedScale = 1.06f) {
        Column(
            Modifier.fillMaxSize().clip(RoundedCornerShape(pt(16))).background(Color.White.copy(alpha = 0.06f)).padding(pt(30)),
            verticalArrangement = Arrangement.spacedBy(pt(14)),
        ) {
            Icon(mode.tvIcon, null, Modifier.size(pt(54)), tint = TvColors.tint)
            Spacer(Modifier.weight(1f))
            Text(mode.defaultTitle, style = TvType.title2, color = Color.White, maxLines = 1)
            Text(modeSummary(mode), style = TvType.body, color = TvColors.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** iOS `modeSummary`: "<default sort> · <default filter>". */
private fun modeSummary(mode: ReelsModeType): String {
    SavedFiltersStore.version
    val sort = mode.tvSortChoices.firstOrNull { it.raw == mode.tvDefaultSortRaw }?.displayName ?: tr(R.string.random)
    val filterId = FeedsConfig.defaultFilterId(mode) ?: return sort
    val name = SavedFiltersStore.byId[filterId]?.name ?: tr(R.string.saved_filter)
    return "$sort · $name"
}

/** iOS `modeSettings(_:)` — one block per tvOS feed mode. */
@Composable
private fun ModeSettings(mode: ReelsModeType) {
    val enabled = TabManager.configurableReelsModes.firstOrNull { it.type == mode }?.isEnabled ?: false
    Column(Modifier.widthIn(max = pt(1100)), verticalArrangement = Arrangement.spacedBy(pt(12))) {
        Row(Modifier.padding(top = pt(30)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(pt(14))) {
            Icon(mode.tvIcon, null, Modifier.size(pt(34)), tint = TvColors.tint)
            Text(mode.defaultTitle, style = TvType.headline, color = TvColors.tint)
        }
        // iOS: the last enabled mode cannot be switched off (`toggleReelsMode` refuses).
        TvToggleRow(tr(R.string.action_show_in_feeds), enabled, { TabManager.toggleReelsMode(mode) })
        if (enabled) {
            TvPickerRow(
                tr(R.string.default_sort), mode.tvSortChoices.map { TvOption(it.raw, it.displayName) },
                mode.tvDefaultSortRaw, { TabManager.setReelsDefaultSort(mode, it) },
            )
            SavedFiltersStore.version
            val filters = SavedFiltersStore.forMode(mode.tvFilterMode)
            TvPickerRow(
                tr(R.string.default_filter),
                listOf(TvOption("", tr(R.string.none))) + filters.map { TvOption(it.id, it.name) },
                FeedsConfig.defaultFilterId(mode) ?: "",
                { id -> if (id.isEmpty()) FeedsConfig.setDefaultFilter(mode, null, null) else FeedsConfig.setDefaultFilter(mode, id, filters.firstOrNull { it.id == id }?.name) },
            )
        }
    }
}

// MARK: - Routes

/**
 * The overlay asked to go somewhere: close the pager, then push the page onto the same sidebar
 * entry (iOS `handleFeedDismissed` / `TVChannelFeedCover.handleDismiss`).
 */
internal fun TvRoute.navigateFromFeed(destination: TvFeedDestination) {
    TvNav.popTo(this)
    TvNav.pop()
    TvNav.push(
        when (destination) {
            is TvFeedDestination.Scene -> TvSceneDetailRoute(destination.id)
            is TvFeedDestination.Performer -> TvPerformerDetailRoute(destination.id, destination.name)
            is TvFeedDestination.Studio -> TvStudioDetailRoute(destination.id, destination.name)
        },
    )
}

/**
 * iOS: the `fullScreenCover` of `TVFeedsView` — the pager on the Feeds tab's session, which lives
 * as long as the tab, so closing and reopening lands on the same item. Back returns to the mode
 * card that opened it (focus memory).
 */
class TvFeedPlayerRoute(private val session: TvFeedSession, private val mode: ReelsModeType) : TvRoute {
    override val key = "feeds.${mode.name}.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()
    private var activated = false

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!activated) { activated = true; session.activate(mode) } }
        TvFeedPlayer(session, onNavigate = { navigateFromFeed(it) }, onClose = { TvNav.pop() })
    }

    /** Back from the full player (overlay › Play). */
    override fun onReturn() = session.resumeAfterFullPlayer()

    override fun onRemoved() = session.deactivate()
}

/**
 * iOS: `TVChannelFeedHost` — a channel (Dashboard row or "Play as Channel" on a detail page) opens
 * Feeds as a starting point: Scenes with the channel's filter and sort. The session exists only
 * while the channel plays.
 */
class TvChannelFeedRoute(private val channel: TvChannel) : TvRoute {
    private val session = TvFeedSession()
    override val key = "channel.${channel.id}.${System.nanoTime()}"
    override val fullScreen = true
    override val focus = TvFocusMemory()
    private var activated = false

    @Composable
    override fun Content() {
        LaunchedEffect(Unit) { if (!activated) { activated = true; session.activate(channel.feedStart) } }
        TvFeedPlayer(session, onNavigate = { navigateFromFeed(it) }, onClose = { TvNav.pop() })
    }

    override fun onReturn() = session.resumeAfterFullPlayer()

    override fun onRemoved() = session.dispose()
}
