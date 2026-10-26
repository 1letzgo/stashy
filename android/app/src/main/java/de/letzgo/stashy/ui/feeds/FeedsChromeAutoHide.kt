package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.data.ReelsModeType

/**
 * iOS `reelsUpdateChromeAutoHide`: short-video style, the section chrome (mode dock, Filter &
 * Sort, criterion chips) fades out when a finger starts paging and stays out while watching;
 * only a tap on the media, a sheet / dialog or a mode switch brings it back.
 *
 * Only a user drag hides it — continuous play and restores move the pager too and must not blink
 * the chrome. Pics never hides. The tab bar keeps its own policy ([de.letzgo.stashy.ui.FeedsTabBarPolicy]).
 */
object FeedsChromeAutoHide {
    /** A drag started on the pager: hide unless Pics, a sheet / dialog or a zoom is up. */
    fun hidesOnDrag(mode: ReelsModeType, overlayOpen: Boolean, zoomed: Boolean): Boolean =
        mode != ReelsModeType.Pics && !overlayOpen && !zoomed

    /** A tap on the media first brings swipe-hidden chrome back instead of toggling it off. */
    fun tapReveals(scrollHidden: Boolean): Boolean = scrollHidden
}
