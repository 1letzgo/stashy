package de.letzgo.stashy.ui.catalog

import de.letzgo.stashy.ui.bottomBarContentPadding
import de.letzgo.stashy.ui.uniqueItemsIndexed
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.nativeAccent
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.floatingShadow
import de.letzgo.stashy.ui.stashyGlass
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SelectAll

/** iOS: `CatalogChromeSlot`. */
data class CatalogChromeSlot(
    val icon: ImageVector,
    val isActive: Boolean = false,
    val contentDescription: String,
    val action: () -> Unit,
)

/** iOS: `CatalogQuickFilterMenuModel` — slot 2 opens a menu instead of acting directly. */
data class CatalogQuickFilterMenu(
    val isActive: Boolean,
    val contentDescription: String,
    val items: List<QuickMenuItem>,
)

/** One entry of the quick filter menu; `header` rows are section titles (iOS sub-menus, flattened). */
data class QuickMenuItem(val title: String, val checked: Boolean = false, val header: Boolean = false, val divider: Boolean = false, val action: () -> Unit = {})

/**
 * iOS: `CatalogSlotSet` — quick filter · contextual · filter & sort (always far right). All of
 * them sit right-pinned in the Home tab strip; there is no floating bar and no columns toggle
 * (the 1/2 per row choice lives in Settings).
 */
data class CatalogSlots(
    val quickFilter: CatalogQuickFilterMenu? = null,
    val contextual: CatalogChromeSlot? = null,
    val filterSort: CatalogChromeSlot? = null,
    /** iOS `CatalogSelectionChrome`: while active it replaces the other slots (Images multi-select). */
    val selection: CatalogSelectionChrome? = null,
)

/** iOS: `CatalogSelectionChrome` — count · Select all · Delete · Done while selecting. */
data class CatalogSelectionChrome(
    val isActive: Boolean,
    val count: Int,
    val isDeleting: Boolean,
    val onDone: () -> Unit,
    val onSelectAll: () -> Unit,
    val onDelete: () -> Unit,
)

/**
 * Catalog actions of the visible catalog root, shown in the trailing slot of the Home
 * [de.letzgo.stashy.ui.NativeTabStrip] (`CatalogsScreen`). Published by [CatalogScaffold].
 */
object CatalogTopActions {
    var slots by mutableStateOf<CatalogSlots?>(null)
    internal var owner: Any? = null

    val hasActions: Boolean get() = slots?.let { it.quickFilter != null || it.contextual != null || it.filterSort != null || it.selection?.isActive == true } == true
}

/**
 * Android pattern for catalog roots (replaces the iOS `FloatingActionBar` / `CatalogSlotBar`):
 * quick menu, contextual slot and the filter & sort ("Settings") button as app-bar icons pinned
 * at the right of the tab strip (active = `Appearance.tint`, menus as anchored `DropdownMenu`s
 * like [de.letzgo.stashy.ui.TopBarMenuAction]); filter & sort always far right.
 */
@Composable
fun CatalogTopActionIcons(slots: CatalogSlots) {
    slots.selection?.takeIf { it.isActive }?.let { SelectionActions(it); return }
    slots.quickFilter?.let { QuickFilterAction(it) }
    slots.contextual?.let { TopBarSlot(it) }
    slots.filterSort?.let { FilterSortAction(it) }
}

/** Filter & sort ("Settings") button: slider icon, tinted with a dot while a filter / non-default state is set. */
@Composable
internal fun FilterSortAction(slot: CatalogChromeSlot) {
    val accent = nativeAccent()
    androidx.compose.material3.IconButton(onClick = slot.action) {
        BadgedBox(badge = { if (slot.isActive) Badge(containerColor = accent) }) {
            Icon(slot.icon, slot.contentDescription, tint = if (slot.isActive) accent else Theme.palette.text)
        }
    }
}

/** Selection mode actions in the Home strip: "N selected", Select all, Delete (red), Done. */
@Composable
private fun SelectionActions(sel: CatalogSelectionChrome) {
    val p = Theme.palette
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("${sel.count} selected", style = NativeType.labelLarge, color = p.secondaryText, maxLines = 1, modifier = Modifier.padding(horizontal = 4.dp))
        de.letzgo.stashy.ui.TopBarAction(Icons.Filled.SelectAll, "Select all", tint = p.text, enabled = !sel.isDeleting, onClick = sel.onSelectAll)
        de.letzgo.stashy.ui.TopBarAction(
            SF.trash, "Delete", tint = if (sel.count > 0) de.letzgo.stashy.ui.StashyColors.systemRed else p.tertiaryText,
            enabled = sel.count > 0, busy = sel.isDeleting, onClick = sel.onDelete,
        )
        androidx.compose.material3.TextButton(onClick = sel.onDone) { Text("Done", style = NativeType.labelLarge, color = nativeAccent()) }
    }
}

@Composable
private fun TopBarSlot(slot: CatalogChromeSlot) {
    de.letzgo.stashy.ui.TopBarAction(slot.icon, slot.contentDescription, tint = if (slot.isActive) Appearance.tint else Theme.palette.text, onClick = slot.action)
}

@Composable
private fun QuickFilterAction(menu: CatalogQuickFilterMenu) {
    val p = Theme.palette
    de.letzgo.stashy.ui.TopBarMenuAction(SF.line3HorizontalDecrease, menu.contentDescription, tint = if (menu.isActive) Appearance.tint else p.text) { dismiss ->
        menu.items.forEach { item ->
            when {
                item.divider -> HorizontalDivider(color = p.separator)
                item.header -> Text(item.title, Modifier.padding(horizontal = 16.dp, vertical = 6.dp), style = NativeType.labelMedium, color = p.secondaryText)
                else -> DropdownMenuItem(
                    text = { Text(item.title, color = p.text) },
                    trailingIcon = if (item.checked) ({ Icon(SF.checkmark, null, tint = p.text) }) else null,
                    onClick = { dismiss(); item.action() },
                )
            }
        }
    }
}

/** iOS: `SearchClearChip` — Material input chip with the active search term; tap clears it. */
@Composable
fun SearchClearChip(text: String, onClear: () -> Unit, modifier: Modifier = Modifier) {
    val p = Theme.palette
    InputChip(
        selected = true, onClick = onClear, modifier = modifier,
        label = { Text(text, style = NativeType.labelLarge, maxLines = 1) },
        leadingIcon = { Icon(SF.magnifyingglass, null, Modifier.size(18.dp)) },
        trailingIcon = { Icon(SF.xmark, "Clear search", Modifier.size(18.dp)) },
        colors = InputChipDefaults.inputChipColors(
            selectedContainerColor = p.secondaryBackground, selectedLabelColor = p.text,
            selectedLeadingIconColor = p.secondaryText, selectedTrailingIconColor = p.text,
        ),
    )
}

/** iOS: `StatusPlaceholderView` (ConnectionErrorView / SharedEmptyStateView). */
@Composable
fun StatusPlaceholder(icon: ImageVector, title: String, buttonText: String? = null, onAction: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = nativeAccent(), modifier = Modifier.size(64.dp))
        Text(title, style = NativeType.titleLarge, color = Theme.palette.text, textAlign = TextAlign.Center)
        if (buttonText != null && onAction != null) de.letzgo.stashy.ui.NativeButton(buttonText, onClick = onAction)
    }
}

/** iOS: `StandardLoadingView(message:)`. */
@Composable
fun StandardLoading(message: String) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) {
        CircularProgressIndicator(color = Theme.palette.secondaryText)
        Text(message, style = NativeType.bodyMedium, color = Theme.palette.secondaryText)
    }
}

/** Gutter of the catalog grids (Material: 16 dp margins, 8–12 dp gutters). */
val CatalogGridGutter: Dp = 12.dp

/** Texts of a catalog's empty / loading states (iOS per view). */
data class CatalogTexts(val loading: String, val emptyIcon: ImageVector, val emptyTitle: String, val emptyButton: String)

/**
 * Shared body of every catalog root (iOS: the `ZStack` of ConnectionErrorView / StandardLoadingView /
 * empty state / grid + `stashyCatalogChrome`): grid with pull-to-refresh and infinite scroll,
 * search chip, filter sheet host; the slots go to the Home tab strip ([CatalogTopActions]). [columns] maps the available width (dp) to
 * a column count; [header] / [extraSheetCards] are optional.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> CatalogScaffold(
    controller: CatalogController<T>,
    texts: CatalogTexts,
    slots: CatalogSlots,
    columns: (Float) -> Int,
    itemKey: (T) -> Any,
    topPadding: Dp = catalogTopPadding(),
    showsFloatingBar: Boolean = true,
    gridKey: Any? = null,
    /** Replaces the grid when set (Images 1/row feed); gets the content top padding. */
    listBody: (@Composable (topPadding: Dp) -> Unit)? = null,
    item: @Composable (index: Int, item: T) -> Unit,
) {
    val list = controller.list
    val p = Theme.palette
    val hasServer = ServerConfigManager.activeConfig != null
    val showBar = showsFloatingBar && hasServer && !(list.items.isEmpty() && list.error != null)
    // All slots → right-pinned icons in the Home tab strip.
    val token = remember { Any() }
    val published = if (showBar) slots else null
    SideEffect { CatalogTopActions.owner = token; CatalogTopActions.slots = published }
    DisposableEffect(token) { onDispose { if (CatalogTopActions.owner === token) { CatalogTopActions.owner = null; CatalogTopActions.slots = null } } }
    Box(Modifier.fillMaxSize().background(p.background)) {
        when {
            !hasServer -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { controller.refresh() })
            list.items.isEmpty() && (list.isLoading || !list.loadedOnce) -> StandardLoading(texts.loading)
            list.items.isEmpty() && list.error != null -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { controller.refresh() })
            list.items.isEmpty() -> StatusPlaceholder(texts.emptyIcon, texts.emptyTitle, texts.emptyButton, { controller.refresh() })
            else -> PullToRefreshBox(isRefreshing = false, onRefresh = { controller.refresh() }, modifier = Modifier.fillMaxSize()) {
                if (listBody != null) listBody(topPadding) else BoxWithConstraints(Modifier.fillMaxSize()) {
                    val count = columns((maxWidth - 32.dp).value)
                    androidx.compose.runtime.key(gridKey) {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(count),
                            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = topPadding, bottom = bottomBarContentPadding()),
                            verticalArrangement = Arrangement.spacedBy(CatalogGridGutter),
                            horizontalArrangement = Arrangement.spacedBy(CatalogGridGutter),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            if (controller.search.isNotEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    SearchClearChip(controller.search, { controller.search = "" })
                                }
                            }
                            uniqueItemsIndexed(list.items, { itemKey(it).toString() }) { index, value ->
                                LaunchedEffect(index) { list.onItemShown(index) }
                                item(index, value)
                            }
                            loadingFooter(list.isLoading)
                        }
                    }
                }
            }
        }
    }
}

private fun LazyGridScope.loadingFooter(isLoading: Boolean) {
    if (isLoading) item(span = { GridItemSpan(maxLineSpan) }) {
        Box(Modifier.fillMaxWidth().padding(16.dp), Alignment.Center) { CircularProgressIndicator(color = Theme.palette.secondaryText) }
    }
}

/** The filter & sort slot every catalog has (iOS: `slider.horizontal.3`, label "Settings"). */
fun filterSortSlot(controller: CatalogController<*>) =
    CatalogChromeSlot(SF.sliderHorizontal3, controller.isFilterActive, "Settings") { controller.isSheetPresented = true }
