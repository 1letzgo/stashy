package de.letzgo.stashy.ui.filter

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.data.CatalogQuickSortCatalog
import de.letzgo.stashy.data.CriteriaDocument
import de.letzgo.stashy.data.CriterionKind
import de.letzgo.stashy.data.CriterionModifier
import de.letzgo.stashy.data.FilterFieldCatalog
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.PickerKind
import de.letzgo.stashy.data.QuickFilterCatalog
import de.letzgo.stashy.data.QuickFilterSection
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.catalog.CatalogController
import de.letzgo.stashy.ui.settings.Segmented
import kotlinx.serialization.json.JsonObject

// iOS: `CatalogQuickFilters.swift` — quick sort strip and active-filter chips above every
// catalog list, plus the quick-filter section at the top of the filter sheets. Logic lives in
// `data/QuickFilters.kt`.

/**
 * Lets a full-width row ignore the [horizontal] content padding of its lazy list, so the chip
 * rows scroll edge to edge (iOS puts the 16 pt inset inside the horizontal `ScrollView`).
 */
fun Modifier.bleedHorizontally(horizontal: Dp): Modifier = layout { measurable, constraints ->
    val extra = (horizontal * 2).roundToPx()
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(placeable.width, placeable.height) { placeable.place(0, 0) }
}

/**
 * iOS: `CatalogListQuickBar` — sits at the top of a catalog list and scrolls away with it (not
 * pinned): a filters button and one chip per curated sort field, then (only when something is
 * active) a removable chip for the selected saved filter / preset and one per criterion.
 */
@Composable
fun CatalogListQuickBar(controller: CatalogController<*>, modifier: Modifier = Modifier) {
    val mode = controller.mode
    val sort = controller.sort
    val document = controller.criteria
    val presetName = controller.activePresetName
    val dict = document.sanitizedObjectFilter
    val keys = document.criterionKeys(emptyList()).filter { dict[it] != null }.let { ordered ->
        ordered + dict.keys.filter { it !in ordered }.sorted()
    }
    // Entity names for "#Tag" chips: make sure the matching option lists are loaded.
    val entityKinds = keys.mapNotNull { key ->
        val kind = FilterFieldCatalog.field(key, mode)?.kind
        if (kind == CriterionKind.multi || kind == CriterionKind.hierarchicalMulti) PickerKind.forCriterion(key, mode) else null
    }.distinct()
    LaunchedEffect(entityKinds) { entityKinds.forEach { FilterPickerOptionsStore.load(it) } }
    val names = if (entityKinds.isEmpty()) emptyMap() else FilterPickerOptionsStore.knownLabels()

    Column(modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // The settings button is pinned at the leading edge; only the sort chips scroll.
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            FiltersButton(
                isActive = presetName != null || keys.isNotEmpty(),
                modifier = Modifier.padding(start = 16.dp, end = 8.dp),
            ) { controller.isSheetPresented = true }
            Row(
                Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(end = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
            CatalogQuickSortCatalog.availableFields(mode).forEach { field ->
                val active = CatalogQuickSortCatalog.isActive(sort, field.field)
                val icon = when {
                    !active -> null
                    CatalogQuickSortCatalog.isRandom(field.field) -> SF.shuffle
                    sort.isAscending -> SF.arrowUp
                    else -> SF.arrowDown
                }
                SortChip(field.label, active, icon) { controller.quickSort(field.field) }
            }
            }
        }
        if (keys.isNotEmpty() || presetName != null) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Same as the sheet's Reset: clear preset and criteria, refetch.
                if (presetName != null) RemovableChip(SF.bookmarkFill, presetName) { controller.reset() }
                keys.forEach { key ->
                    val label = QuickFilterCatalog.chipLabel(key, dict[key]!!, mode, names)
                    RemovableChip(null, label) {
                        document.removeCriterion(key)
                        controller.applyLive()
                    }
                }
            }
        }
    }
}

@Composable
/**
 * iOS: the quick bar's pinned settings button — slider icon in a 38×30 capsule (the icon the old
 * chrome "Settings" button used), tint dot at top-trailing while a preset or criterion is active.
 */
private fun FiltersButton(isActive: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(modifier.size(width = 38.dp, height = 30.dp).semantics(mergeDescendants = true) { contentDescription = "Filter and sort settings" }) {
        Box(
            Modifier.matchParentSize().clip(RoundedCornerShape(50)).background(Theme.palette.secondaryBackground).clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(SF.sliderHorizontal3, null, tint = Theme.palette.text, modifier = Modifier.size(16.dp))
        }
        if (isActive) Box(Modifier.align(Alignment.TopEnd).size(8.dp).clip(CircleShape).background(Appearance.tint))
    }
}

@Composable
private fun SortChip(label: String, active: Boolean, icon: ImageVector?, onClick: () -> Unit) {
    val p = Theme.palette
    val fg = if (active) Color.White else p.text
    Row(
        Modifier.height(30.dp).clip(RoundedCornerShape(50)).background(if (active) Appearance.tint else p.secondaryBackground)
            .clickable(onClick = onClick).padding(horizontal = 12.dp)
            .semantics { contentDescription = "Sort by $label" },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = fg, maxLines = 1)
        if (icon != null) Icon(icon, null, tint = fg, modifier = Modifier.size(14.dp))
    }
}

@Composable
private fun RemovableChip(icon: ImageVector?, text: String, onRemove: () -> Unit) {
    val tint = Appearance.tint
    Row(
        Modifier.height(26.dp).clip(RoundedCornerShape(50)).background(tint.copy(alpha = 0.15f))
            .clickable(onClick = onRemove).padding(horizontal = 10.dp)
            .semantics { contentDescription = "Remove $text" },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) Icon(icon, null, tint = tint, modifier = Modifier.size(12.dp))
        Text(text, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = tint, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Icon(SF.xmark, null, tint = tint, modifier = Modifier.size(12.dp))
    }
}

// MARK: - Sheet body: quick filters + collapsible advanced editor

/**
 * iOS: `CatalogFilterCriteriaBody` — replaces the bare criteria editor in every filter sheet:
 * quick chips first, the full Stash criteria editor behind a collapsible "Advanced criteria"
 * header (collapsed by default, open when the document holds criteria the chips can't show).
 */
@Composable
fun CatalogFilterCriteriaBody(document: CriteriaDocument, onChange: () -> Unit) {
    val sections = QuickFilterCatalog.sections(document.mode)
    val advancedOnly = QuickFilterCatalog.advancedOnlyCount(document.sanitizedObjectFilter, document.mode)
    var showsAdvanced by rememberSaveable { mutableStateOf<Boolean?>(null) }
    val expanded = showsAdvanced ?: (advancedOnly > 0)
    // iOS metrics: 20 between the quick sections and the "Advanced criteria" header.
    Column {
        if (sections.isNotEmpty()) {
            QuickFiltersCard(document, sections, onChange)
            Spacer(Modifier.height(20.dp))
        }
        AdvancedHeader(expanded, advancedOnly) { showsAdvanced = !expanded }
        if (expanded) {
            Spacer(Modifier.height(16.dp))
            FilterCriteriaEditor(document, onChange = onChange)
        }
    }
}

@Composable
private fun AdvancedHeader(expanded: Boolean, count: Int, onToggle: () -> Unit) {
    val p = Theme.palette
    Row(
        Modifier.controlCardChrome().background(p.secondaryBackground).clickable(onClick = onToggle)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(SF.sliderHorizontal3, null, tint = p.secondaryText, modifier = Modifier.size(20.dp))
        Text("Advanced criteria", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = p.text)
        if (count > 0) Text(
            "$count",
            Modifier.clip(RoundedCornerShape(50)).background(p.secondaryText.copy(alpha = 0.2f)).padding(horizontal = 7.dp, vertical = 2.dp),
            style = IosTypography.caption.copy(fontWeight = FontWeight.Bold), color = p.text,
        )
        Spacer(Modifier.weight(1f))
        Icon(SF.chevronDown, null, tint = p.secondaryText, modifier = Modifier.size(20.dp).rotate(if (expanded) 180f else 0f))
    }
}

/** iOS: `QuickFiltersCard`. */
@Composable
private fun QuickFiltersCard(document: CriteriaDocument, sections: List<QuickFilterSection>, onChange: () -> Unit) {
    // Flat like iOS (no header): sections on the cards' 16 dp edge, 22 apart.
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        sections.forEach { section ->
            when (section) {
                is QuickFilterSection.Choices -> ChoiceSection(document, section, onChange)
                is QuickFilterSection.Entities -> QuickEntityFilterSection(document, section.key, section.title, onChange)
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Theme.palette.secondaryText)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChoiceSection(document: CriteriaDocument, section: QuickFilterSection.Choices, onChange: () -> Unit) {
    val current = document.sanitizedObjectFilter[section.key]
    val selected = QuickFilterCatalog.matchingChoice(section.key, current, document.mode)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle(section.title)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CatalogFilterChip(section.anyLabel, current == null) {
                if (current != null) { document.removeCriterion(section.key); onChange() }
            }
            section.choices.forEach { choice ->
                CatalogFilterChip(choice.label, selected?.id == choice.id) {
                    if (selected?.id == choice.id) document.removeCriterion(section.key)
                    else document.setCriterion(section.key, choice.value)
                    onChange()
                }
            }
        }
    }
}

/**
 * iOS: `QuickEntityFilterSection` — most-used tags as toggle chips plus a name search; writes
 * the same `value` id list the advanced editor's picker uses, keeping its modifier, depth and
 * exclusions. Options come from the shared [FilterPickerOptionsStore].
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuickEntityFilterSection(document: CriteriaDocument, key: String, title: String, onChange: () -> Unit) {
    val p = Theme.palette
    val kind = PickerKind.forCriterion(key, document.mode)
    var query by remember { mutableStateOf("") }
    LaunchedEffect(kind) { kind?.let { FilterPickerOptionsStore.load(it) } }

    val currentDict = document.objectFilter[key] as? JsonObject ?: JsonObject(emptyMap())
    val selectedIds = FilterMapper.idStrings(currentDict["value"])
    val modifier = QuickFilterCatalog.entityModifier(currentDict)
    val hierarchical = FilterFieldCatalog.field(key, document.mode)?.kind == CriterionKind.hierarchicalMulti
    val prefix = if (key == "tags") "#" else ""

    val visible = if (kind == null) emptyList() else {
        val all = FilterPickerOptionsStore.availableOptions(kind)
        val term = query.trim()
        if (term.isNotEmpty()) all.filter { it.name.contains(term, ignoreCase = true) }.take(30)
        else {
            val selected = selectedIds.toSet()
            val labels = FilterPickerOptionsStore.knownLabels()
            val byId = all.associateBy { it.id }
            val picked = selectedIds.mapNotNull { id -> byId[id] ?: labels[id]?.let { de.letzgo.stashy.data.FilterEntityOption(id, it) } }
            picked + FilterPickerOptionsStore.cached(kind).filter { it.id !in selected }.take(VISIBLE_ENTITY_COUNT)
        }
    }

    fun toggle(id: String) {
        val next = QuickFilterCatalog.toggledEntityCriterion(currentDict, id, hierarchical)
        if (next == null) document.removeCriterion(key) else document.setCriterion(key, next)
        onChange()
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionTitle(title, Modifier.weight(1f))
            if (selectedIds.size > 1) {
                Segmented(
                    listOf(CriterionModifier.IncludesAll.raw, CriterionModifier.Includes.raw), modifier,
                    { if (it == CriterionModifier.IncludesAll.raw) "All" else "Any" },
                    Modifier.width(140.dp),
                ) { raw ->
                    if (raw != modifier) {
                        document.setCriterion(key, JsonObject(LinkedHashMap(currentDict).apply { put("modifier", kotlinx.serialization.json.JsonPrimitive(raw)) }))
                        onChange()
                    }
                }
            }
        }
        if (kind != null) NativeSearchField(
            query, { query = it; FilterPickerOptionsStore.search(kind, it) }, "Search ${title.lowercase()}",
            loading = FilterPickerOptionsStore.isSearching(kind),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            visible.forEach { option ->
                CatalogFilterChip(prefix + option.name, option.id in selectedIds) { toggle(option.id) }
            }
        }
        when {
            kind != null && FilterPickerOptionsStore.isLoading(kind) ->
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = p.secondaryText)
            visible.isEmpty() -> Text(
                if (query.isEmpty()) "Search to find ${title.lowercase()}." else "No matches.",
                style = IosTypography.caption, color = p.secondaryText,
            )
        }
    }
}

private const val VISIBLE_ENTITY_COUNT = 12
