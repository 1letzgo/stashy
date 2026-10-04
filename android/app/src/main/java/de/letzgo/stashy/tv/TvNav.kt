package de.letzgo.stashy.tv

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * A pushed TV page (iOS: a typed `navigationDestination` value or a `fullScreenCover`).
 * Routes hold their own model, so a page keeps its state while something covers it.
 */
interface TvRoute {
    val key: String
    /** Covers the sidebar (players, image viewer, forms) like a `fullScreenCover`. */
    val fullScreen: Boolean get() = false
    val focus: TvFocusMemory
    @Composable fun Content()
    /** Called when the page on top of this one was popped (iOS `onDismiss` of a cover). */
    fun onReturn() {}
    /** Called when the route leaves the stack for good. */
    fun onRemoved() {}
}

/**
 * iOS: `TVNavigationStore` + the selection of `TVMainTabView` — the sidebar selection and one
 * back stack per sidebar entry, outside the composition.
 */
object TvNav {
    private val stacks = TvStacks<TvRoute>(TvRootTab.fixed)
    var selected by mutableStateOf(TvRootTab.Home); private set
    /** Bumped on every stack change (the stacks themselves are not snapshot state). */
    var version by mutableIntStateOf(0); private set
    /** True while the sidebar holds focus (screens then leave their opening focus alone). */
    var sidebarFocused = false

    /** Bumped to move focus into the sidebar (Back on a tab root). */
    var sidebarFocusRequest by mutableIntStateOf(0); private set
    /** Focus memory of the tab roots. */
    private val rootFocus = HashMap<TvRootTab, TvFocusMemory>()

    /** Set by the shell: the focus memory of a tab's root screen (its model owns it). */
    var rootMemoryProvider: ((TvRootTab) -> TvFocusMemory?)? = null

    fun rootMemory(tab: TvRootTab): TvFocusMemory = rootMemoryProvider?.invoke(tab) ?: rootFocus.getOrPut(tab) { TvFocusMemory() }

    fun stack(tab: TvRootTab = selected): List<TvRoute> { version; return stacks.stack(tab) }
    fun top(tab: TvRootTab = selected): TvRoute? { version; return stacks.top(tab) }

    fun push(route: TvRoute) {
        stacks.push(selected, route)
        version++
    }

    /** One level back; false at the tab root. */
    fun pop(): Boolean {
        val popped = stacks.pop(selected) ?: return false
        popped.onRemoved()
        val now = stacks.top(selected)
        if (now != null) { now.focus.restore = true; now.onReturn() } else rootMemory(selected).restore = true
        version++
        return true
    }

    /** Pops everything above [route] (stays on it). */
    fun popTo(route: TvRoute) {
        while (stacks.top(selected) != null && stacks.top(selected) !== route) {
            if (!pop()) break
        }
    }

    fun select(tab: TvRootTab) {
        val current = selected
        val removed = if (tab == current) stacks.stack(tab) else if (current == TvRootTab.Settings) stacks.stack(TvRootTab.Settings) else emptyList()
        selected = stacks.select(current, tab)
        removed.forEach { it.onRemoved() }
        version++
    }

    fun focusSidebar() { sidebarFocusRequest++ }

    /** iOS: `dismissOnAppLock` — covers close when the app locks. */
    fun dismissFullScreen() {
        TvRootTab.entries.forEach { tab ->
            while (true) {
                val top = stacks.top(tab) ?: break
                if (!top.fullScreen) break
                stacks.pop(tab)?.onRemoved()
            }
        }
        version++
    }

    /** Server switch: pushed pages belong to the old server. */
    fun reset() {
        TvRootTab.entries.forEach { tab -> stacks.stack(tab).forEach { it.onRemoved() } }
        stacks.reset()
        rootFocus.clear()
        version++
    }

    /** iOS: a hidden active library section falls back to Home. */
    fun validate(visible: Set<TvRootTab>) {
        val next = stacks.validated(selected, visible)
        if (next != selected) { selected = next; version++ }
    }
}
