package de.letzgo.stashy.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import de.letzgo.stashy.data.Prefs

/**
 * Settings › Design › Appearance › "Auto-hide tab bar" (Prefs `tabBarAutoHide`, default off).
 * iOS keeps its tab bar fixed (`tabBarMinimizeBehavior(.never)`); this is Android-only.
 *
 * When on, [AppShell] slides the bottom bar away while a list scrolls down and brings it back
 * on scrolling up, at the top edge of a list, on tab / screen changes and for content too short
 * to scroll (it never scrolls, so the bar never hides). Scrolling inside sheets and dialogs
 * runs in their own window and never reaches [connection], so the bar does not move there.
 *
 * Feeds › Pics is a plain list and uses [connection] like every other list. The pager modes
 * (Scenes, Markers, Clips, Previews) suspend the scroll tracking and drive the bar themselves
 * through [FeedsTabBarPolicy] (hide on a swipe to a later row, show on the first row and when
 * the tap-to-toggle chrome comes back).
 */
object TabBarAutoHide {
    const val PREF_KEY = "tabBarAutoHide"

    private var enabledState by mutableStateOf(Prefs.bool(PREF_KEY, false))

    var enabled: Boolean
        get() = enabledState
        set(value) {
            enabledState = value
            Prefs.setBool(PREF_KEY, value)
            if (!value) show()
        }

    /** True while the bar is slid out of view. */
    var hidden by mutableStateOf(false)
        private set

    /** Scroll tracking off for surfaces that drive the bar themselves (Feeds pager); set by [AppShell]. */
    internal var suspended = false

    /** Slide duration of the bar; content that follows it (Feeds overlay) uses the same. */
    const val ANIMATION_MS = 220

    private val tracker = TabBarScrollTracker()

    fun show() {
        tracker.reset()
        hidden = false
    }

    /** Slides the bar away (no-op while the setting is off). */
    fun hide() {
        if (!enabled) return
        tracker.reset()
        hidden = true
    }

    /** Applies a [FeedsTabBarPolicy] / [TabBarScrollTracker] decision: `true` hide, `false` show. */
    fun apply(decision: Boolean?) {
        when (decision) {
            true -> hide()
            false -> show()
            null -> {}
        }
    }

    /** Distance (px) a scroll must travel in one direction before the bar reacts. */
    var thresholdPx = 48f

    /** Installed with `Modifier.nestedScroll` around the tab content in [AppShell]. */
    val connection = object : NestedScrollConnection {
        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (!enabled || suspended) return Offset.Zero
            tracker.onScroll(consumed.y, available.y, thresholdPx)?.let { hidden = it }
            return Offset.Zero
        }
    }
}

/**
 * Pure direction tracker behind [TabBarAutoHide]: accumulates consumed vertical scroll and
 * reports `true` (hide) after [threshold] px of scrolling down, `false` (show) after the same
 * distance up — or immediately when a drag hits the top edge (unconsumed downward pull).
 * Returns `null` while nothing changes.
 */
class TabBarScrollTracker {
    private var accumulated = 0f

    fun reset() { accumulated = 0f }

    /**
     * [consumedY] / [availableY] follow Compose's nested-scroll sign: negative = content moves
     * up (the user scrolls down the list), positive = content moves down (scrolling back up).
     */
    fun onScroll(consumedY: Float, availableY: Float, threshold: Float): Boolean? {
        // Pulling past the top edge: the list is at its start, the bar belongs there.
        if (availableY > 0f && consumedY >= 0f) { accumulated = 0f; return false }
        if (consumedY == 0f) return null
        // Direction change restarts the distance.
        if ((consumedY < 0f) != (accumulated < 0f) && accumulated != 0f) accumulated = 0f
        accumulated += consumedY
        return when {
            accumulated <= -threshold -> { accumulated = 0f; true }
            accumulated >= threshold -> { accumulated = 0f; false }
            else -> null
        }
    }
}

/**
 * Auto-hide decisions for the Feeds pager modes (one full-screen row per page), where scroll
 * distance means nothing: the bar hides when the user swipes on to a later row and comes back
 * on the first row or when the Feeds chrome is tapped back in. All results: `true` hide,
 * `false` show, `null` leave the bar as it is.
 */
object FeedsTabBarPolicy {
    /**
     * A page settled after a scroll from [from] to [to]. [userSwipe] is false for programmatic
     * moves (continuous-play advance, restore); [overlayOpen] while a sheet or dialog is up.
     */
    fun onPageSettled(from: Int, to: Int, userSwipe: Boolean, overlayOpen: Boolean): Boolean? = when {
        to == 0 -> false
        from == to -> null
        overlayOpen || !userSwipe -> null
        to > from -> true
        else -> null
    }

    /** The tap-to-toggle chrome changed: coming back brings the bar with it. */
    fun onChromeVisibilityChanged(visible: Boolean): Boolean? = if (visible) false else null

    /**
     * Bottom inset (any unit) the Feeds info overlay / scrubber and filled media keep free:
     * the full bar while it shows, sliding down to the system [navInset] as [barShownFraction]
     * goes 1 → 0, and only [navInset] while the chrome itself is hidden.
     */
    fun overlayInset(chromeVisible: Boolean, barShownFraction: Float, barHeight: Float, navInset: Float): Float =
        if (!chromeVisible) navInset
        else navInset + (barHeight - navInset).coerceAtLeast(0f) * barShownFraction.coerceIn(0f, 1f)
}
