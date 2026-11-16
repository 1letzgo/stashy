package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * iOS `DeleteActions` / `@DeleteActionsShown` (SharedUtilities.swift): Settings › Design ›
 * Editing › "Show Delete Button", one switch for every Delete of library content (scenes, images,
 * galleries, markers, performers, studios, tags, groups) on pages, in menus, selection bars and
 * Feeds. Off hides them, not just disables them. Not covered: downloads, servers, saved filters /
 * presets, caches, server maintenance tasks. Compose state, so screens on display follow at once.
 */
object DeleteActions {
    const val KEY = "ShowsDeleteButton"
    /** The former Feeds-only switch (default off, so only stored once someone flipped it). */
    private const val LEGACY_FEEDS_KEY = "ReelsShowsDeleteButton"

    var isShown by mutableStateOf(load())
        private set

    fun update(value: Boolean) { isShown = value; Prefs.setBool(KEY, value) }

    /** After a settings import. */
    fun reload() { isShown = load() }

    /**
     * Once: starts from the old Feeds value when the user ever set it, otherwise on. After that
     * the old key is never read again.
     */
    private fun load(): Boolean {
        if (!Prefs.has(KEY)) {
            Prefs.setBool(KEY, if (Prefs.has(LEGACY_FEEDS_KEY)) Prefs.bool(LEGACY_FEEDS_KEY) else true)
        }
        return Prefs.bool(KEY, true)
    }
}
