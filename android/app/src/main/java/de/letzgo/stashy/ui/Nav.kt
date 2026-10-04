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

    /** Opens a catalog sub-tab on Home (used by dashboard "›" headers, stats tiles …). */
    fun openCatalog(tab: CatalogTab) {
        this.tab = MainTab.Home
        popToRoot(MainTab.Home)
        catalogTab = tab
    }
}
