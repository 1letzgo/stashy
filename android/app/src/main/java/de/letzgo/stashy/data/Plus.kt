package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.BuildConfig

/**
 * iOS: `StashyPlusManager` — single gate for stashy+ features. Play Billing implementation
 * follows (products de.stashy.plus.m / .y / .l). Debug builds are unlocked like on iOS.
 */
object StashyPlus {
    var isUnlocked by mutableStateOf(BuildConfig.DEBUG || Prefs.bool("stashy_plus_unlocked"))
        internal set
}
