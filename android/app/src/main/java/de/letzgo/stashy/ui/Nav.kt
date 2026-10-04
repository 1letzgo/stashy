package de.letzgo.stashy.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList

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
    Dashboard("Dashboard"), Scenes("Scenes"), Images("Images"), Galleries("Galleries"),
    Performers("Performers"), Studios("Studios"), Tags("Tags"), Groups("Groups"), Markers("Markers");

    val icon get() = when (this) {
        Dashboard -> SF.houseFill; Scenes -> SF.film; Images -> SF.photo; Galleries -> SF.photoStack
        Performers -> SF.personFill; Studios -> SF.building2; Tags -> SF.tag
        Groups -> SF.rectangleStackFill; Markers -> SF.bookmarkFill
    }
}

/** iOS: `NavigationCoordinator` + `TabManager.selectedTab` — one back stack per main tab. */
object Nav {
    var tab by mutableStateOf(MainTab.Home)
    var catalogTab by mutableStateOf(CatalogTab.Dashboard)

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
        if (this.tab == tab) popToRoot(tab) else this.tab = tab
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

    /** Opens a catalog sub-tab on Home (used by dashboard "›" headers, stats tiles, Search "Show All"). */
    fun openCatalog(tab: CatalogTab, sort: String? = null, search: String? = null, noDefaultFilter: Boolean = false) {
        catalogRequest = if (sort != null || search != null || noDefaultFilter) CatalogRequest(tab, sort, search, noDefaultFilter) else null
        this.tab = MainTab.Home
        popToRoot(MainTab.Home)
        catalogTab = tab
    }
}
