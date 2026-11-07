package de.letzgo.stashy.ui.catalog

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SortByAlpha
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Cake
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogQuickSortCatalog
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.CatalogTab
import de.letzgo.stashy.ui.Chevron
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.oCounterIcon

/**
 * iOS: `HomeBreadcrumbRow` — set by [CatalogsScreen] around the open catalog. While true, the
 * catalog's sort and settings button live in the Home strip ([HomeBreadcrumbStrip]) and only the
 * active-filter chips stay above the list ([CatalogListQuickBar] `chipsOnly`).
 */
val LocalHomeBreadcrumb = compositionLocalOf { false }

/**
 * iOS: the catalog row of the Home breadcrumb — Home › views menu (all library views, named), and
 * at the right the list's own actions, its sort menu (icon + direction) and settings button.
 * The dashboard keeps the icon strip ([CatalogsScreen] `TopNavStrip`), like iOS.
 */
@Composable
internal fun HomeBreadcrumbStrip(tabs: List<CatalogTab>) {
    val p = Theme.palette
    val actions = CatalogTopActions.slots
    val controller = CatalogTopActions.controller
    Column(
        Modifier.fillMaxWidth().background(p.background)
            .windowInsetsPadding(WindowInsets.statusBars),
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            // Without a visible dashboard (Settings › Home Tabs) there is no Home to go back to.
            if (CatalogTab.Dashboard in tabs) {
                IconButton(onClick = { Nav.catalogTab = CatalogTab.Dashboard }) {
                    Icon(SF.houseFill, "Home", tint = p.secondaryText)
                }
                Icon(Icons.Chevron, null, tint = p.tertiaryText, modifier = Modifier.size(18.dp))
            }
            LibraryMenu(tabs.filter { it != CatalogTab.Dashboard })
            Spacer(Modifier.weight(1f))
            val selection = actions?.selection?.takeIf { it.isActive }
            if (selection != null) {
                CatalogTopActionIcons(actions)
            } else {
                // Quick menu / contextual slot as before; the settings button comes last, after the sort.
                actions?.let { CatalogTopActionIcons(it.copy(filterSort = null)) }
                if (controller != null) {
                    SortMenu(controller)
                    SettingsButton(controller)
                } else {
                    actions?.filterSort?.let { FilterSortAction(it) }
                }
            }
            Spacer(Modifier.width(4.dp))
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(p.separator))
    }
}

/** iOS `HomeViewsMenu`: the open view's name, highlighted; the menu lists every library view. */
@Composable
private fun LibraryMenu(tabs: List<CatalogTab>) {
    var open by remember { mutableStateOf(false) }
    val current = Nav.catalogTab
    Box {
        Row(
            Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(12.dp)).clickable { open = true }
                .padding(horizontal = 10.dp)
                .semantics(mergeDescendants = true) { contentDescription = "Library, ${current.title}" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(current.title, style = MaterialTheme.typography.titleSmall, color = nativeAccent(), maxLines = 1)
            Icon(SF.chevronUpChevronDown, null, tint = nativeAccent(), modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            tabs.forEach { tab ->
                DropdownMenuItem(
                    text = { Text(tab.title) },
                    leadingIcon = { Icon(tab.icon, null) },
                    trailingIcon = { if (tab == current) Icon(SF.checkmark, null) },
                    onClick = { open = false; Nav.catalogTab = tab },
                )
            }
        }
    }
}

/** iOS: the quick-sort menu — collapsed it shows the active field's icon and the direction. */
@Composable
private fun SortMenu(controller: CatalogController<*>) {
    val p = Theme.palette
    var open by remember { mutableStateOf(false) }
    val sort = controller.sort
    val fields = controller.extraSorts.distinctBy { it.field }
        .map { CatalogQuickSortCatalog.Field(it.field, it.label.substringBefore(" (")) } +
        CatalogQuickSortCatalog.availableFields(controller.mode)
    val active = fields.firstOrNull { CatalogQuickSortCatalog.isActive(sort, it.field) }
    val direction = when {
        sort.isRandom -> null
        sort.isAscending -> SF.arrowUp
        else -> SF.arrowDown
    }
    Box {
        Row(
            Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(12.dp)).clickable { open = true }
                .padding(horizontal = 8.dp)
                .semantics(mergeDescendants = true) {
                    contentDescription = "Sort, ${active?.label ?: "custom"}, ${if (sort.isAscending) "ascending" else "descending"}"
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Icon(sortIcon(active?.field ?: sort.field), null, tint = p.text, modifier = Modifier.size(22.dp))
            if (direction != null) Icon(direction, null, tint = p.text, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            fields.forEach { field ->
                val isActive = CatalogQuickSortCatalog.isActive(sort, field.field)
                DropdownMenuItem(
                    text = { Text(field.label) },
                    leadingIcon = { Icon(sortIcon(field.field), null) },
                    trailingIcon = { if (isActive) Icon(SF.checkmark, null) },
                    // The active field again flips its direction (Random re-rolls), like the chips did.
                    onClick = { open = false; controller.quickSort(field.field) },
                )
            }
            if (!sort.isRandom) {
                HorizontalDivider()
                listOf(true to "Ascending", false to "Descending").forEach { (ascending, label) ->
                    DropdownMenuItem(
                        text = { Text(label) },
                        leadingIcon = { Icon(if (ascending) SF.arrowUp else SF.arrowDown, null) },
                        trailingIcon = { if (sort.isAscending == ascending) Icon(SF.checkmark, null) },
                        onClick = {
                            open = false
                            if (sort.isAscending != ascending) {
                                SortCatalog.optionFor(controller.mode, sort.field, ascending, controller.extraSorts)
                                    ?.let { controller.changeSort(it) }
                            }
                        },
                    )
                }
            }
        }
    }
}

/** The list's filter & sort sheet; the badge marks an active filter (iOS: tint dot). */
@Composable
private fun SettingsButton(controller: CatalogController<*>) {
    val accent = nativeAccent()
    val active = controller.isFilterActive
    IconButton(onClick = { controller.isSheetPresented = true }) {
        BadgedBox(badge = { if (active) Badge(containerColor = accent) }) {
            Icon(SF.sliderHorizontal3, "Filter and sort settings", tint = Theme.palette.text)
        }
    }
}

/** iOS `CatalogQuickSortCatalog.icon(for:)`: one symbol per quick sort field. */
@Composable
private fun sortIcon(field: String): ImageVector = when {
    CatalogQuickSortCatalog.isRandom(field) -> SF.shuffle
    field == de.letzgo.stashy.data.SortOption.FOR_YOU_FIELD -> SF.sparkles
    else -> when (field) {
        "date" -> SF.calendar
        "created_at" -> Icons.Outlined.AddCircleOutline
        "rating" -> SF.star
        "o_counter" -> oCounterIcon(Appearance.oCounterIcon)
        "duration" -> SF.clock
        "last_played_at" -> Icons.Outlined.History
        "play_count" -> Icons.Outlined.PlayCircle
        "scenes_count" -> SF.film
        "images_count" -> SF.photo
        "name", "title" -> Icons.Filled.SortByAlpha
        "birthdate" -> Icons.Outlined.Cake
        "seconds" -> Icons.Outlined.Timer
        "group_scene_number" -> SF.number
        else -> SF.arrowUpArrowDown
    }
}
