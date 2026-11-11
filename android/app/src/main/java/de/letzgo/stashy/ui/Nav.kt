package de.letzgo.stashy.ui

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import de.letzgo.stashy.data.AppTab
import de.letzgo.stashy.data.FilterMode

/**
 * A pushed screen (iOS: a `NavigationLink` destination). Features declare their own
 * implementations next to their UI, so no central route enum has to be edited.
 */
interface Screen {
    /** Stable identity for state saving inside the stack. */
    val key: String
    /** Full-screen content (players, viewers) hides the floating tab bar. */
    val hidesTabBar: Boolean get() = false
    @Composable fun Content()
}

/** iOS: main `AppTab`s of the floating tab bar (+ search). */
enum class MainTab { Home, Feeds, Tools, Settings, Search }

/** iOS: `CatalogsView.CatalogsTab` (order and icons identical). */
enum class CatalogTab(val title: String) {
    Dashboard(tr(R.string.dashboard)), Scenes(tr(R.string.scenes)), Images(tr(R.string.images)), Galleries(tr(R.string.galleries)),
    Performers(tr(R.string.performers)), Studios(tr(R.string.studios)), Tags(tr(R.string.tags)), Groups(tr(R.string.groups)), Markers(tr(R.string.markers)), Magazine(tr(R.string.magazin));

    val icon get() = when (this) {
        Dashboard -> SF.houseFill; Scenes -> SF.film; Images -> SF.photo; Galleries -> SF.photoStack
        Performers -> SF.personFill; Studios -> SF.building2; Tags -> SF.tag
        Groups -> SF.rectangleStackFill; Markers -> SF.bookmarkFill; Magazine -> SF.magazine
    }

    /** iOS `TabManager` `AppTab` of this catalog (order / visibility / defaults). */
    val appTab: AppTab get() = when (this) {
        Dashboard -> AppTab.Dashboard; Scenes -> AppTab.Scenes; Images -> AppTab.Images; Galleries -> AppTab.Galleries
        Performers -> AppTab.Performers; Studios -> AppTab.Studios; Tags -> AppTab.Tags
        Groups -> AppTab.Groups; Markers -> AppTab.Markers; Magazine -> AppTab.Magazine
    }

    /** List mode of the catalog (null for the dashboard). */
    val filterMode: FilterMode? get() = appTab.filterMode

    companion object {
        fun from(tab: AppTab): CatalogTab? = entries.firstOrNull { it.appTab == tab }
        fun forMode(mode: FilterMode): CatalogTab? = entries.firstOrNull { it.filterMode == mode }
    }
}

/** iOS: `NavigationCoordinator` + `TabManager.selectedTab` — one back stack per main tab. */
object Nav {
    var tab by mutableStateOf(MainTab.Home)
    var catalogTab by mutableStateOf(CatalogTab.Dashboard)

    /**
     * A tab root that hides the floating tab bar (iOS `.toolbar(.hidden, for: .tabBar)`, e.g.
     * Feeds with its chrome toggled off). Only honoured while that root is showing.
     */
    var rootHidesTabBar by mutableStateOf(false)

    /** Counts re-selections of the already active tab (iOS: Feeds restarts from the top). */
    val reselects = androidx.compose.runtime.mutableStateMapOf<MainTab, Int>()

    private val stacks = MainTab.entries.associateWith { mutableStateListOf<Screen>() }

    fun stack(tab: MainTab = this.tab): SnapshotStateList<Screen> = stacks.getValue(tab)

    val top: Screen? get() = stack().lastOrNull()

    fun push(screen: Screen) { stack().add(screen) }

    fun pop(): Boolean {
        val s = stack()
        if (s.isEmpty()) return false
        s.removeAt(s.lastIndex)
        return true
    }

    fun popToRoot(tab: MainTab = this.tab) = stack(tab).clear()

    /** Tapping the active tab again pops to its root (iOS behaviour). */
    fun select(tab: MainTab) {
        if (this.tab == tab) {
            popToRoot(tab)
            reselects[tab] = (reselects[tab] ?: 0) + 1
        } else this.tab = tab
    }

    /**
     * What the catalog opened by [openCatalog] should apply (iOS `navigateToScenes(sort:search:)` …).
     * [sort] is the iOS sort raw value (`createdAtDesc`, `sceneCountDesc` …). The catalog reads it
     * when it becomes visible and clears it via [consumeCatalogRequest].
     */
    data class CatalogRequest(val tab: CatalogTab, val sort: String? = null, val search: String? = null, val noDefaultFilter: Boolean = false)

    var catalogRequest by mutableStateOf<CatalogRequest?>(null)
        private set

    /** Returns and clears the pending request for [tab] (null if none). */
    fun consumeCatalogRequest(tab: CatalogTab): CatalogRequest? =
        catalogRequest?.takeIf { it.tab == tab }?.also { catalogRequest = null }

    /**
     * Opens a catalog sub-tab on Home (dashboard "›" headers, stats tiles, Search "Show All") —
     * iOS `navigateToScenes(sort:search:noDefaultFilter:)` …; Images with a search term skip the
     * default filter like iOS `navigateToImages(search:)`.
     */
    fun openCatalog(tab: CatalogTab, sort: String? = null, search: String? = null, noDefaultFilter: Boolean = false) {
        val skipDefault = noDefaultFilter || (tab == CatalogTab.Images && !search.isNullOrEmpty())
        catalogRequest = if (sort != null || search != null || skipDefault) CatalogRequest(tab, sort, search, skipDefault) else null
        this.tab = MainTab.Home
        popToRoot(MainTab.Home)
        catalogTab = tab
    }
}
