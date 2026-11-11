package de.letzgo.stashy.ui.feeds

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SortByAlpha
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Cake
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.MenuItemColors
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CatalogQuickSortCatalog
import de.letzgo.stashy.data.FeedSort
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.ReelsModeType
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.oCounterIcon

/**
 * iOS: `reelsSortMenu` → `CatalogQuickSortMenu` — the quick sort of the open feed, read and
 * written through the same paths as the feed's Filter & Sort sheet.
 */
class FeedsSortMenuState(
    /** The mode's quick sort fields the feed's sort enum actually offers. */
    val fields: List<CatalogQuickSortCatalog.Field>,
    /** `sortField` of the active sort. */
    val field: String,
    val isAscending: Boolean,
    /** A field picked in the menu: the active one flips its direction (Random re-rolls). */
    val onField: (String) -> Unit,
    /** "Ascending" / "Descending" picked. */
    val onDirection: (Boolean) -> Unit,
) {
    val isRandom: Boolean
        get() = randomField(this.field)

    fun isActive(f: String): Boolean = if (randomField(f)) isRandom else f == field

    private fun randomField(f: String): Boolean = CatalogQuickSortCatalog.isRandom(f)
}

/** Catalog whose quick sort fields a feed offers (iOS: scenes / sceneMarkers / images). */
private fun quickSortMode(mode: ReelsModeType): FilterMode = when (mode) {
    ReelsModeType.Scenes, ReelsModeType.Verticals, ReelsModeType.Previews -> FilterMode.Scenes
    ReelsModeType.Markers -> FilterMode.SceneMarkers
    ReelsModeType.Clips, ReelsModeType.Pics -> FilterMode.Images
}

/**
 * Sort menu state of [mode]. Pics goes through its `CatalogController` (like the Images sheet);
 * every other feed through [FeedsModel.setSort], the sheet's own path, after [beforeChange]
 * (tears the player pool down, like the sheet's `onSort`).
 */
fun feedsSortMenuState(model: FeedsModel, mode: ReelsModeType, beforeChange: () -> Unit): FeedsSortMenuState {
    if (mode == ReelsModeType.Pics) {
        val c = model.pics
        val sort = c.sort
        val fields = c.extraSorts.distinctBy { it.field }
            .map { CatalogQuickSortCatalog.Field(it.field, it.label.substringBefore(" (")) } +
            CatalogQuickSortCatalog.availableFields(c.mode)
        return FeedsSortMenuState(
            fields = fields,
            field = sort.field,
            isAscending = sort.isAscending,
            onField = { c.quickSort(it) },
            onDirection = { asc ->
                if (asc != sort.isAscending) SortCatalog.optionFor(c.mode, sort.field, asc, c.extraSorts)?.let { c.changeSort(it) }
            },
        )
    }
    val options = model.sortOptions(mode)
    val current = model.sort(mode)
    val available = options.map { it.sortField }.toSet()
    val fields = CatalogQuickSortCatalog.fields(quickSortMode(mode)).filter { f ->
        if (CatalogQuickSortCatalog.isRandom(f.field)) available.any { CatalogQuickSortCatalog.isRandom(it) } else f.field in available
    }
    fun option(field: String, ascending: Boolean): FeedSort? =
        options.firstOrNull { it.sortField == field && (it.direction == "ASC") == ascending }
    val currentAscending = current.direction == "ASC"
    return FeedsSortMenuState(
        fields = fields,
        field = current.sortField,
        isAscending = currentAscending,
        onField = { field ->
            // iOS `CatalogQuickSortCatalog.next(after:tapping:)`.
            val next = when {
                CatalogQuickSortCatalog.isRandom(field) -> options.firstOrNull { it.isRandom }
                field == current.sortField -> option(field, !currentAscending)
                else -> {
                    val natural = CatalogQuickSortCatalog.defaultAscending(field)
                    option(field, natural) ?: option(field, !natural)
                }
            }
            next?.let { beforeChange(); model.setSort(mode, it) }
        },
        onDirection = { asc ->
            if (asc != currentAscending) option(current.sortField, asc)?.let { beforeChange(); model.setSort(mode, it) }
        },
    )
}

/** Menu rows in the normal content colour (icons and checkmarks too), not the accent. */
@Composable
internal fun feedsMenuItemColors(): MenuItemColors {
    val content = Theme.palette.text
    return MenuDefaults.itemColors(textColor = content, leadingIconColor = content, trailingIconColor = content)
}

/**
 * iOS `CatalogQuickSortMenu` in Feeds: plain glass pill (not tinted, like the settings button)
 * with the active field's icon, its direction (none for Random) and an up/down chevron; the menu
 * lists the quick fields with a checkmark and, unless Random, an Order section.
 */
@Composable
fun FeedsSortMenu(state: FeedsSortMenuState) {
    var open by remember { mutableStateOf(false) }
    val active = state.fields.firstOrNull { state.isActive(it.field) }
    val tint = Color.White.copy(alpha = FeedsDock.inactiveIconOpacity)
    val colors = feedsMenuItemColors()
    Box {
        Row(
            Modifier
                .chromePill()
                .noIndicationClick { open = true }
                .padding(horizontal = FeedsDock.activeHorizontalPadding)
                .semantics(mergeDescendants = true) {
                    contentDescription = "Sort, ${active?.label ?: "custom"}" +
                        if (state.isRandom) "" else if (state.isAscending) ", ascending" else ", descending"
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(feedsSortIcon(active?.field ?: state.field), null, tint = tint, modifier = Modifier.size(FeedsDock.iconSize))
            if (!state.isRandom) Icon(if (state.isAscending) SF.arrowUp else SF.arrowDown, null, tint = tint, modifier = Modifier.size(13.dp))
            Icon(SF.chevronUpChevronDown, null, tint = tint, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = Theme.palette.secondaryBackground, shape = RoundedCornerShape(12.dp)) {
            state.fields.forEach { field ->
                DropdownMenuItem(
                    text = { Text(field.label) },
                    leadingIcon = { Icon(feedsSortIcon(field.field), null) },
                    trailingIcon = { if (state.isActive(field.field)) Icon(SF.checkmark, tr(R.string.selected)) },
                    colors = colors,
                    onClick = { open = false; state.onField(field.field) },
                )
            }
            if (!state.isRandom) {
                HorizontalDivider()
                listOf(true to tr(R.string.ascending), false to tr(R.string.descending)).forEach { (ascending, label) ->
                    DropdownMenuItem(
                        text = { Text(label) },
                        leadingIcon = { Icon(if (ascending) SF.arrowUp else SF.arrowDown, null) },
                        trailingIcon = { if (state.isAscending == ascending) Icon(SF.checkmark, tr(R.string.selected)) },
                        colors = colors,
                        onClick = { open = false; state.onDirection(ascending) },
                    )
                }
            }
        }
    }
}

/** iOS `CatalogQuickSortCatalog.icon(for:)` (same symbols as the Home breadcrumb's sort menu). */
@Composable
private fun feedsSortIcon(field: String): ImageVector = when {
    CatalogQuickSortCatalog.isRandom(field) -> SF.shuffle
    else -> when (field) {
        "date" -> SF.calendar
        "created_at" -> Icons.Outlined.AddCircleOutline
        "rating" -> SF.star
        "o_counter" -> oCounterIcon(Appearance.oCounterIcon)
        "duration" -> SF.clock
        "last_played_at" -> Icons.Outlined.History
        "play_count" -> Icons.Outlined.PlayCircle
        "name", "title" -> Icons.Filled.SortByAlpha
        "birthdate" -> Icons.Outlined.Cake
        "seconds" -> Icons.Outlined.Timer
        else -> SF.arrowUpArrowDown
    }
}
