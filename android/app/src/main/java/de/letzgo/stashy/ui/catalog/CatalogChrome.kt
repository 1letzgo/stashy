package de.letzgo.stashy.ui.catalog

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
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.TabBarClearance
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.floatingShadow
import de.letzgo.stashy.ui.stashyGlass

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

/** iOS: `CatalogSlotSet` — columns · quick filter · contextual · filter & sort (always far right). */
data class CatalogSlots(
    val columns: CatalogChromeSlot? = null,
    val quickFilter: CatalogQuickFilterMenu? = null,
    val contextual: CatalogChromeSlot? = null,
    val filterSort: CatalogChromeSlot? = null,
)

/** Space the floating action bar reserves above the tab bar. */
val FloatingBarClearance: Dp = 36.dp + 6.dp + 12.dp

/** Bottom offset of the floating action bar: just above the floating tab bar (iOS safe-area inset). */
@Composable
fun floatingBarBottomPadding(): Dp = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 80.dp + 6.dp

/** iOS: `FloatingActionBar` + `CatalogSlotBar` — 36pt glass capsule with equally weighted slots. */
@Composable
fun CatalogFloatingBar(slots: CatalogSlots, modifier: Modifier = Modifier) {
    Row(
        modifier
            .padding(horizontal = 24.dp)
            .fillMaxWidth()
            .height(36.dp)
            .floatingShadow(RoundedCornerShape(50))
            .stashyGlass(RoundedCornerShape(50))
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        slots.columns?.let { SlotButton(it, Modifier.weight(1f)) }
        slots.quickFilter?.let { QuickFilterSlot(it, Modifier.weight(1f)) }
        slots.contextual?.let { SlotButton(it, Modifier.weight(1f)) }
        slots.filterSort?.let { SlotButton(it, Modifier.weight(1f)) }
    }
}

@Composable
private fun SlotGlyph(icon: ImageVector, isActive: Boolean, contentDescription: String) {
    Box {
        Icon(icon, contentDescription, tint = if (isActive) Appearance.tint else Color.White, modifier = Modifier.size(20.dp))
        if (isActive) Box(Modifier.align(Alignment.TopEnd).offset(x = 3.dp, y = (-3).dp).size(7.dp).clip(CircleShape).background(Appearance.tint))
    }
}

@Composable
private fun SlotButton(slot: CatalogChromeSlot, modifier: Modifier) {
    Box(modifier.fillMaxHeight().clickable(onClick = slot.action), contentAlignment = Alignment.Center) {
        SlotGlyph(slot.icon, slot.isActive, slot.contentDescription)
    }
}

@Composable
private fun QuickFilterSlot(menu: CatalogQuickFilterMenu, modifier: Modifier) {
    var open by remember { mutableStateOf(false) }
    val p = Theme.palette
    Box(modifier.fillMaxHeight().clickable { open = true }, contentAlignment = Alignment.Center) {
        Icon(SF.line3HorizontalDecrease, menu.contentDescription, tint = if (menu.isActive) Appearance.tint else Color.White, modifier = Modifier.size(20.dp))
        DropdownMenu(open, { open = false }, containerColor = p.secondaryBackground) {
            menu.items.forEach { item ->
                when {
                    item.divider -> HorizontalDivider(color = p.separator)
                    item.header -> Text(item.title, Modifier.padding(horizontal = 16.dp, vertical = 6.dp), style = IosTypography.footnote.copy(fontWeight = FontWeight.SemiBold), color = p.secondaryText)
                    else -> DropdownMenuItem(
                        text = { Text(item.title, color = p.text) },
                        trailingIcon = if (item.checked) ({ Icon(SF.checkmark, null, tint = p.text) }) else null,
                        onClick = { open = false; item.action() },
                    )
                }
            }
        }
    }
}

/** iOS: `SearchClearChip` — shows the active search term and clears it on tap. */
@Composable
fun SearchClearChip(text: String, onClear: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.6f)).clickable(onClick = onClear)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(SF.xmark, "Clear search", tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(12.dp))
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.9f), maxLines = 1)
    }
}

/** iOS: `StatusPlaceholderView` (ConnectionErrorView / SharedEmptyStateView). */
@Composable
fun StatusPlaceholder(icon: ImageVector, title: String, buttonText: String? = null, onAction: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(64.dp))
        Text(title, style = IosTypography.title3.copy(fontWeight = FontWeight.Bold), color = Theme.palette.text, textAlign = TextAlign.Center)
        if (buttonText != null && onAction != null) {
            Button(onAction, colors = ButtonDefaults.buttonColors(containerColor = Appearance.tint, contentColor = Color.White)) {
                Text(buttonText, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/** iOS: `StandardLoadingView(message:)`. */
@Composable
fun StandardLoading(message: String) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) {
        CircularProgressIndicator(color = Theme.palette.secondaryText)
        Text(message, style = IosTypography.subheadline, color = Theme.palette.secondaryText)
    }
}

/** Texts of a catalog's empty / loading states (iOS per view). */
data class CatalogTexts(val loading: String, val emptyIcon: ImageVector, val emptyTitle: String, val emptyButton: String)

/**
 * Shared body of every catalog root (iOS: the `ZStack` of ConnectionErrorView / StandardLoadingView /
 * empty state / grid + `stashyCatalogChrome`): grid with pull-to-refresh and infinite scroll,
 * search chip, floating action bar, filter sheet host. [columns] maps the available width (dp) to
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
    item: @Composable (index: Int, item: T) -> Unit,
) {
    val list = controller.list
    val p = Theme.palette
    val hasServer = ServerConfigManager.activeConfig != null
    Box(Modifier.fillMaxSize().background(p.background)) {
        when {
            !hasServer -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { controller.refresh() })
            list.items.isEmpty() && (list.isLoading || !list.loadedOnce) -> StandardLoading(texts.loading)
            list.items.isEmpty() && list.error != null -> StatusPlaceholder(SF.server, "Server not reachable", "Retry Connection", { controller.refresh() })
            list.items.isEmpty() -> StatusPlaceholder(texts.emptyIcon, texts.emptyTitle, texts.emptyButton, { controller.refresh() })
            else -> PullToRefreshBox(isRefreshing = false, onRefresh = { controller.refresh() }, modifier = Modifier.fillMaxSize()) {
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val count = columns((maxWidth - 32.dp).value)
                    androidx.compose.runtime.key(gridKey) {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(count),
                            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = topPadding, bottom = TabBarClearance + FloatingBarClearance + 16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            if (controller.search.isNotEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
                                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    SearchClearChip(controller.search, { controller.search = "" })
                                }
                            }
                            itemsIndexed(list.items, key = { _, it -> itemKey(it) }) { index, value ->
                                LaunchedEffect(index) { list.onItemShown(index) }
                                item(index, value)
                            }
                            loadingFooter(list.isLoading)
                        }
                    }
                }
            }
        }
        val showBar = showsFloatingBar && hasServer && !(list.items.isEmpty() && list.error != null)
        if (showBar) CatalogFloatingBar(slots, Modifier.align(Alignment.BottomCenter).padding(bottom = floatingBarBottomPadding()))
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
