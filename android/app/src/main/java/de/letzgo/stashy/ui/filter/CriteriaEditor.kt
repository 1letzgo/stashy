package de.letzgo.stashy.ui.filter

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.CriteriaDocument
import de.letzgo.stashy.data.CriterionKind
import de.letzgo.stashy.data.CriterionModifier
import de.letzgo.stashy.data.FilterCriterionSummary
import de.letzgo.stashy.data.FilterFieldCatalog
import de.letzgo.stashy.data.FilterFieldDescriptor
import de.letzgo.stashy.data.FilterMapper
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.GenderOption
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.OrientationOption
import de.letzgo.stashy.data.PickerKind
import de.letzgo.stashy.data.ResolutionOption
import de.letzgo.stashy.data.boolOrNull
import de.letzgo.stashy.data.capitalizeWords
import de.letzgo.stashy.data.jsonNumber
import de.letzgo.stashy.data.numberOrNull
import de.letzgo.stashy.data.stringValue
import de.letzgo.stashy.data.with
import de.letzgo.stashy.data.without
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * iOS: `FilterCriteriaApplyScheduler` — collapses a burst of edits into one refetch (450 ms);
 * a pending apply runs immediately when the editor goes away.
 */
private class ApplyScheduler(private val scope: kotlinx.coroutines.CoroutineScope) {
    private var job: Job? = null
    private var pending: (() -> Unit)? = null

    fun schedule(work: () -> Unit) {
        job?.cancel()
        pending = work
        job = scope.launch {
            delay(450)
            pending = null
            work()
        }
    }

    fun flush() {
        val w = pending ?: return
        job?.cancel()
        pending = null
        w()
    }
}

/**
 * iOS: `FilterCriteriaEditorView` — the full Stash criteria editor shared by every catalog sheet.
 * Root level: pinned default criteria first, then set criteria; one card per condition
 * (collapsed = label + summary, tap to expand), "Add condition" menu, nested AND/OR/NOT group cards.
 */
@Composable
fun FilterCriteriaEditor(
    document: CriteriaDocument,
    onChange: () -> Unit,
    modifier: Modifier = Modifier,
    embedsInCard: Boolean = true,
    path: List<String> = emptyList(),
) {
    val scope = rememberCoroutineScope()
    val scheduler = remember { ApplyScheduler(scope) }
    DisposableEffect(Unit) { onDispose { scheduler.flush() } }
    val applyChange = { scheduler.schedule(onChange) }

    val expandedKeys = remember { mutableStateListOf<String>() }
    val stickyKeys = remember { mutableStateListOf<String>() }
    var nestedKey by remember { mutableStateOf<String?>(null) }
    val isRoot = path.isEmpty()

    // Read the document's state so this recomposes on edits.
    document.objectFilter
    val levelKeys = (if (isRoot) document.displayedCriterionKeys() else document.criterionKeys(path)).toMutableList()
    stickyKeys.forEach { if (it !in levelKeys && !CriteriaDocument.isGroupKey(it)) levelKeys.add(it) }
    val groupKeys = document.groupKeys(path)
    val addable = FilterFieldCatalog.addableFields(document.mode, levelKeys.toSet())
    val p = Theme.palette

    val explanation = when (path.lastOrNull()) {
        "OR" -> "Matches when at least one condition below is true."
        "NOT" -> "Excludes everything matching the conditions below."
        "AND" -> "All conditions below must be true."
        else -> "All conditions must be true."
    }

    Column(
        modifier.padding(horizontal = if (embedsInCard) Tokens.Spacing.md else 0.dp).padding(bottom = if (embedsInCard) Tokens.Spacing.xs else 0.dp),
        verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
    ) {
        Text(explanation, Modifier.fillMaxWidth().padding(horizontal = 10.dp), style = IosTypography.caption, color = p.secondaryText)
        if (levelKeys.isEmpty()) {
            Text(
                if (groupKeys.isEmpty()) "No conditions yet — use Add below." else "No direct conditions.",
                Modifier.fillMaxWidth().clip(RoundedCornerShape(Tokens.Radius.card)).background(p.secondaryBackground)
                    .padding(horizontal = Tokens.Spacing.md, vertical = 14.dp),
                style = IosTypography.subheadline, color = p.secondaryText,
            )
        } else {
            levelKeys.forEach { key ->
                val field = FilterFieldCatalog.field(key, document.mode) ?: FilterFieldDescriptor(key, key, CriterionKind.raw)
                val isPinned = isRoot && key in document.pinnedKeys
                CriterionCard(
                    document, field, path, expanded = key in expandedKeys, isPinned = isPinned,
                    onToggle = { if (key in expandedKeys) expandedKeys.remove(key) else { expandedKeys.add(key); if (key !in stickyKeys) stickyKeys.add(key) } },
                    onClear = { wasSet ->
                        document.setCriterion(key, null, path)
                        if (isPinned || wasSet) { if (key !in stickyKeys) stickyKeys.add(key) }
                        if (!isPinned && !wasSet) { stickyKeys.remove(key); expandedKeys.remove(key) }
                        applyChange()
                    },
                    onApply = applyChange,
                    onOpenNested = { nestedKey = key },
                )
            }
        }
        AddConditionBar(addable) { field ->
            if (field.key !in stickyKeys) stickyKeys.add(field.key)
            if (field.key !in expandedKeys) expandedKeys.add(field.key)
        }
        groupKeys.forEach { group -> GroupCard(document, group, path, onChange, applyChange) }
    }

    nestedKey?.let { key ->
        val field = FilterFieldCatalog.field(key, document.mode)
        NestedEditorSheet(
            title = field?.label ?: key,
            mode = field?.nestedMode ?: document.mode,
            initial = document.value(key, path) as? JsonObject ?: JsonObject(emptyMap()),
            onCancel = { nestedKey = null },
            onDone = { dict ->
                document.setCriterion(key, dict.takeIf { it.isNotEmpty() }, path)
                nestedKey = null
                onChange()
            },
        )
    }
}

@Composable
private fun AddConditionBar(addable: List<FilterFieldDescriptor>, onAdd: (FilterFieldDescriptor) -> Unit) {
    val p = Theme.palette
    var open by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(Tokens.Radius.card)).background(p.secondaryBackground)) {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = addable.isNotEmpty()) { open = true }
                .padding(horizontal = Tokens.Spacing.md, vertical = 14.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(SF.plusCircleFill, null, tint = if (addable.isEmpty()) p.secondaryText else Appearance.tint, modifier = Modifier.size(20.dp))
            Spacer(Modifier.size(Tokens.Spacing.xs))
            Text("Add condition", style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = if (addable.isEmpty()) p.secondaryText else p.text)
        }
        Box(Modifier.align(Alignment.TopEnd)) {
            DropdownMenu(open, { open = false }, Modifier.heightIn(max = 420.dp), containerColor = p.secondaryBackground) {
                addable.forEach { f ->
                    DropdownMenuItem(text = { Text(f.label, color = p.text) }, onClick = { open = false; onAdd(f) })
                }
            }
        }
    }
}

/** iOS: `groupTitle(_:)`. */
fun groupTitle(group: String) = when (group) { "AND" -> "All of"; "OR" -> "Any of"; "NOT" -> "None of"; else -> group }

@Composable
private fun GroupCard(document: CriteriaDocument, group: String, path: List<String>, onChange: () -> Unit, applyChange: () -> Unit) {
    val p = Theme.palette
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(Tokens.Radius.card)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(p.background).border(1.dp, Appearance.tint.copy(alpha = 0.35f), shape),
        verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Tokens.Spacing.sm).padding(top = Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            Box {
                Row(
                    Modifier.clip(RoundedCornerShape(50)).background(Appearance.tint).clickable { menu = true }.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(groupTitle(group).uppercase(), style = IosTypography.caption.copy(fontWeight = FontWeight.Bold), color = Color.White)
                    Icon(SF.chevronUpChevronDown, null, tint = Color.White, modifier = Modifier.size(12.dp))
                }
                DropdownMenu(menu, { menu = false }, containerColor = p.secondaryBackground) {
                    CriteriaDocument.GROUP_KEYS.forEach { candidate ->
                        val enabled = candidate == group || candidate !in document.groupKeys(path)
                        DropdownMenuItem(
                            text = { Text(groupTitle(candidate), color = if (enabled) p.text else p.secondaryText) },
                            trailingIcon = if (candidate == group) ({ Icon(SF.checkmark, null, tint = p.text) }) else null,
                            enabled = enabled,
                            onClick = { menu = false; document.changeGroupType(path, group, candidate); applyChange() },
                        )
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            Icon(
                SF.xmarkCircleFill, "Remove ${groupTitle(group)} group", tint = p.secondaryText.copy(alpha = 0.55f),
                modifier = Modifier.size(22.dp).clip(RoundedCornerShape(50)).clickable { document.removeGroup(group, path); applyChange() },
            )
        }
        FilterCriteriaEditor(document, onChange, Modifier.padding(horizontal = Tokens.Spacing.xs).padding(bottom = Tokens.Spacing.xs), embedsInCard = false, path = path + group)
    }
}

@Composable
private fun CriterionCard(
    document: CriteriaDocument,
    field: FilterFieldDescriptor,
    path: List<String>,
    expanded: Boolean,
    isPinned: Boolean,
    onToggle: () -> Unit,
    onClear: (wasSet: Boolean) -> Unit,
    onApply: () -> Unit,
    onOpenNested: () -> Unit,
) {
    val p = Theme.palette
    val value = document.value(field.key, path)
    val isSet = value != null
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Tokens.Radius.card)).background(p.secondaryBackground).padding(horizontal = Tokens.Spacing.md),
    ) {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = FilterSheetLayout.controlCardMinHeight),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.weight(1f).clickable(onClick = onToggle).padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
            ) {
                Text(field.label, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = p.text, maxLines = 1)
                Text(
                    FilterCriterionSummary.text(field, value), Modifier.weight(1f),
                    style = IosTypography.subheadline, color = if (isSet) Appearance.tint else p.secondaryText,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                Icon(if (expanded) SF.chevronUp else SF.chevronDown, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
            }
            if (isSet || !isPinned) {
                Icon(
                    SF.xmarkCircleFill, if (isPinned) "Clear ${field.label}" else "Remove ${field.label}",
                    tint = p.secondaryText.copy(alpha = 0.55f),
                    modifier = Modifier.padding(start = Tokens.Spacing.sm).size(22.dp).clip(RoundedCornerShape(50)).clickable { onClear(isSet) },
                )
            }
        }
        AnimatedVisibility(expanded) {
            Column(Modifier.fillMaxWidth().padding(bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
                CriterionEditorBody(document, field, path, onApply, onOpenNested)
            }
        }
    }
}

@Composable
private fun CriterionEditorBody(document: CriteriaDocument, field: FilterFieldDescriptor, path: List<String>, onApply: () -> Unit, onOpenNested: () -> Unit) {
    val key = field.key
    val dict = document.value(key, path) as? JsonObject ?: JsonObject(emptyMap())
    val setDict: (JsonObject) -> Unit = { document.setCriterion(key, it, path) }
    when (field.kind) {
        CriterionKind.boolean -> BoolRow(document.value(key, path).boolOrNull, { document.setCriterion(key, it?.let { b -> JsonPrimitive(b) }, path) }, onApply)
        CriterionKind.string -> StringRow(dict, setDict, suggestions = FilterFieldCatalog.valueSuggestions(key, document.mode), onChange = onApply)
        CriterionKind.int, CriterionKind.hierarchicalCount -> NumericRow(dict, setDict, isFloat = false, onApply)
        CriterionKind.float -> NumericRow(dict, setDict, isFloat = true, onApply)
        CriterionKind.date, CriterionKind.timestamp -> StringRow(
            dict, setDict, placeholder = if (field.kind == CriterionKind.date) "YYYY-MM-DD" else "Timestamp / relative",
            modifiers = field.kind.defaultModifiers, onChange = onApply,
        )
        CriterionKind.resolution -> ResolutionRow(dict, setDict, onApply)
        CriterionKind.orientation -> OrientationRow(dict, setDict, onApply)
        CriterionKind.gender -> GenderRow(dict, setDict, onApply)
        CriterionKind.circumcision -> CircumcisionRow(dict, setDict, onApply)
        CriterionKind.hierarchicalMulti, CriterionKind.multi -> MultiIdRow(dict, setDict, key, field.kind == CriterionKind.hierarchicalMulti, document.mode, onApply)
        CriterionKind.isMissing -> IsMissingRow(document.value(key, path).stringValue ?: "", { document.setCriterion(key, JsonPrimitive(it), path) }, document.mode, onApply)
        CriterionKind.hasMarkers, CriterionKind.hasChapters -> TrueFalseRow(document.value(key, path).stringValue ?: "", { document.setCriterion(key, JsonPrimitive(it), path) }, onApply)
        CriterionKind.stashID, CriterionKind.stashIDs -> StashIdRow(dict, setDict, multi = field.kind == CriterionKind.stashIDs, onApply)
        CriterionKind.phashDistance -> PhashRow(dict, setDict, onApply)
        CriterionKind.duplication -> DuplicationRow(dict, setDict, onApply)
        CriterionKind.customFields -> CustomFieldsRow(
            (document.value(key, path) as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList(),
            { document.setCriterion(key, JsonArray(it), path) }, onApply,
        )
        CriterionKind.booleanGroup -> {}
        CriterionKind.nestedFilter -> {
            val count = dict.size
            Row(Modifier.clickable(onClick = onOpenNested).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (count == 0) "Edit…" else "$count criterion(s)", style = IosTypography.subheadline, color = Theme.palette.text)
                Icon(de.letzgo.stashy.ui.SF.chevronDown, null, tint = Theme.palette.secondaryText, modifier = Modifier.size(16.dp))
            }
        }
        CriterionKind.raw -> RawJsonRow(dict, setDict, onApply)
    }
}

private fun JsonObject.patch(vararg updates: Pair<String, JsonElement?>): JsonObject {
    var d = this
    updates.forEach { (k, v) -> d = d.with(k, v) }
    return d
}

/** iOS: `FilterModifierPicker` — keeps a stored modifier visible even when no longer offered. */
@Composable
private fun ModifierPicker(modifier: String, options: List<CriterionModifier>, onChange: (String) -> Unit) {
    val current = CriterionModifier.from(modifier)
    val resolved = if (modifier.isNotEmpty() && options.none { it.raw == modifier } && current != null) options + current else options
    MenuPicker(modifier, resolved.map { MenuEntry(it.raw, it.label) }, onSelect = onChange)
}

@Composable
private fun ChipScrollRow(content: @Composable () -> Unit) {
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

@Composable
private fun BoolRow(value: Boolean?, set: (Boolean?) -> Unit, onChange: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CatalogFilterChip("Any", value == null) { set(null); onChange() }
        CatalogFilterChip("Yes", value == true) { set(true); onChange() }
        CatalogFilterChip("No", value == false) { set(false); onChange() }
    }
}

@Composable
private fun StringRow(
    value: JsonObject,
    set: (JsonObject) -> Unit,
    placeholder: String = "Value",
    modifiers: List<CriterionModifier> = CriterionKind.string.defaultModifiers,
    suggestions: List<FilterFieldCatalog.ValueSuggestion> = emptyList(),
    onChange: () -> Unit,
) {
    val modifierRaw = value["modifier"].stringValue ?: "INCLUDES"
    val needsValue = CriterionModifier.from(modifierRaw)?.needsValue ?: true
    ModifierPicker(modifierRaw, modifiers) { set(value.patch("modifier" to JsonPrimitive(it))); onChange() }
    if (needsValue) {
        val current = value["value"].stringValue ?: ""
        // Text edits only update the document; the refetch fires on commit.
        FilterTextField(current, { set(value.patch("value" to JsonPrimitive(it))) }, placeholder, onCommit = onChange)
        if (suggestions.isNotEmpty()) ChipScrollRow {
            suggestions.forEach { s ->
                CatalogFilterChip(s.label, current == s.value) {
                    // A chip is an exact value: switch a fuzzy modifier to equals.
                    var next = value.patch("value" to JsonPrimitive(s.value))
                    if (modifierRaw == "INCLUDES") next = next.patch("modifier" to JsonPrimitive("EQUALS"))
                    set(next); onChange()
                }
            }
        }
    }
}

@Composable
private fun NumericRow(value: JsonObject, set: (JsonObject) -> Unit, isFloat: Boolean, onChange: () -> Unit) {
    val modifierRaw = value["modifier"].stringValue ?: "EQUALS"
    val mod = CriterionModifier.from(modifierRaw)
    ModifierPicker(modifierRaw, (if (isFloat) CriterionKind.float else CriterionKind.int).defaultModifiers) { set(value.patch("modifier" to JsonPrimitive(it))); onChange() }
    if (mod?.needsValue == true) {
        fun text(key: String): String = value["${key}_text"].stringValue ?: value[key].numberOrNull?.let {
            if (!isFloat || it == Math.floor(it)) it.toLong().toString() else it.toString()
        } ?: ""
        fun setText(key: String, raw: String) {
            var next = value
            when {
                raw.isEmpty() -> next = next.without(key).without("${key}_text")
                isFloat && raw.toDoubleOrNull() != null -> next = next.with(key, JsonPrimitive(raw.toDouble())).without("${key}_text")
                !isFloat && raw.toLongOrNull() != null -> next = next.with(key, JsonPrimitive(raw.toLong())).without("${key}_text")
                // Partial input ("-", "1.") stays as text, out of the filter.
                else -> next = next.with("${key}_text", JsonPrimitive(raw))
            }
            set(next)
        }
        val kb = if (isFloat) KeyboardType.Decimal else KeyboardType.Number
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterTextField(text("value"), { setText("value", it) }, "Value", Modifier.weight(1f), kb, onCommit = onChange)
            if (mod.needsSecondValue) FilterTextField(text("value2"), { setText("value2", it) }, "Value 2", Modifier.weight(1f), kb, onCommit = onChange)
        }
    }
}

@Composable
private fun ResolutionRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val modifierRaw = value["modifier"].stringValue ?: "EQUALS"
    val res = value["value"].stringValue ?: ResolutionOption.FullHD.raw
    ModifierPicker(modifierRaw, CriterionKind.resolution.defaultModifiers) { set(value.patch("modifier" to JsonPrimitive(it))); onChange() }
    ChipScrollRow {
        ResolutionOption.entries.forEach { r ->
            CatalogFilterChip(r.label, res == r.raw) { set(value.patch("value" to JsonPrimitive(r.raw))); onChange() }
        }
    }
}

@Composable
private fun OrientationRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val selected = FilterCriterionSummary.stringList(value["value"]).ifEmpty { listOfNotNull(value["value"].stringValue) }.toSet()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OrientationOption.entries.forEach { o ->
            CatalogFilterChip(o.label, o.raw in selected) {
                val next = if (o.raw in selected) selected - o.raw else selected + o.raw
                set(value.patch("value" to JsonArray(next.map { JsonPrimitive(it) }))); onChange()
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GenderRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val modifierRaw = value["modifier"].stringValue ?: "INCLUDES"
    val selected = (FilterCriterionSummary.stringList(value["value_list"]).ifEmpty { FilterCriterionSummary.stringList(value["value"]) }
        .ifEmpty { listOfNotNull(value["value"].stringValue) }).toSet()
    ModifierPicker(modifierRaw, CriterionKind.gender.defaultModifiers) { set(value.patch("modifier" to JsonPrimitive(it))); onChange() }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GenderOption.entries.forEach { g ->
            CatalogFilterChip(g.label, g.raw in selected) {
                val next = (if (g.raw in selected) selected - g.raw else selected + g.raw).sorted()
                set(value.without("value").patch("value_list" to JsonArray(next.map { JsonPrimitive(it) }))); onChange()
            }
        }
    }
}

@Composable
private fun CircumcisionRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val selected = FilterCriterionSummary.stringList(value["value"]).toSet()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("CUT", "UNCUT").forEach { o ->
            CatalogFilterChip(capitalizeWords(o), o in selected) {
                val next = if (o in selected) selected - o else selected + o
                set(value.patch("value" to JsonArray(next.map { JsonPrimitive(it) }), "modifier" to JsonPrimitive("INCLUDES"))); onChange()
            }
        }
    }
}

@Composable
private fun IsMissingRow(value: String, set: (String) -> Unit, mode: FilterMode, onChange: () -> Unit) {
    FilterTextField(value, set, "Property name", onCommit = onChange)
    ChipScrollRow {
        FilterFieldCatalog.isMissingOptions(mode).forEach { c -> CatalogFilterChip(c, value == c) { set(c); onChange() } }
    }
}

@Composable
private fun TrueFalseRow(value: String, set: (String) -> Unit, onChange: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CatalogFilterChip("Yes", value == "true") { set("true"); onChange() }
        CatalogFilterChip("No", value == "false") { set("false"); onChange() }
    }
}

@Composable
private fun StashIdRow(value: JsonObject, set: (JsonObject) -> Unit, multi: Boolean, onChange: () -> Unit) {
    val modifierRaw = value["modifier"].stringValue ?: "NOT_NULL"
    ModifierPicker(modifierRaw, (if (multi) CriterionKind.stashIDs else CriterionKind.stashID).defaultModifiers) { set(value.patch("modifier" to JsonPrimitive(it))); onChange() }
    FilterTextField(value["endpoint"].stringValue ?: "", { set(if (it.isEmpty()) value.without("endpoint") else value.with("endpoint", JsonPrimitive(it))) }, "Endpoint (optional)", onCommit = onChange)
    // `stash_id_endpoint` (StashIDCriterionInput) uses `stash_id`, `stash_ids_endpoint` uses `stash_ids`.
    if (CriterionModifier.from(modifierRaw)?.needsValue != false) {
        val k = if (multi) "stash_ids" else "stash_id"
        FilterTextField(value[k].stringValue ?: "", { set(if (it.isEmpty()) value.without(k) else value.with(k, JsonPrimitive(it))) }, "Stash ID", onCommit = onChange)
    }
}

@Composable
private fun PhashRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    FilterTextField(value["value"].stringValue ?: "", { set(value.with("value", JsonPrimitive(it))) }, "PHash", onCommit = onChange)
    val distance = value["distance"].numberOrNull?.toLong()?.toString() ?: "0"
    FilterTextField(distance, { set(value.with("distance", JsonPrimitive(it.toIntOrNull() ?: 0))); onChange() }, "Distance", keyboardType = KeyboardType.Number)
}

@Composable
private fun DuplicationRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val duplicated = value["duplicated"].boolOrNull ?: true
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CatalogFilterChip("Duplicated", duplicated) { set(value.with("duplicated", JsonPrimitive(true))); onChange() }
        CatalogFilterChip("Unique", !duplicated) { set(value.with("duplicated", JsonPrimitive(false))); onChange() }
    }
    val distance = value["distance"].numberOrNull?.toLong()?.toString() ?: ""
    FilterTextField(distance, { raw ->
        set(if (raw.isEmpty()) value.without("distance") else value.with("distance", JsonPrimitive(raw.toIntOrNull() ?: 0)))
    }, "PHash distance (optional)", keyboardType = KeyboardType.Number, onCommit = onChange)
}

@Composable
private fun CustomFieldsRow(value: List<JsonObject>, set: (List<JsonObject>) -> Unit, onChange: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        value.forEachIndexed { idx, row ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                FilterTextField(row["field"].stringValue ?: "", { t -> set(value.toMutableList().also { it[idx] = row.with("field", JsonPrimitive(t)) }) }, "Field", onCommit = onChange)
                val joined = (row["value"] as? JsonArray)?.joinToString(", ") { it.stringValue ?: it.toString() } ?: ""
                FilterTextField(joined, { t ->
                    val parts = t.split(",").map { JsonPrimitive(it.trim()) }
                    set(value.toMutableList().also { it[idx] = row.with("value", JsonArray(parts)) })
                }, "Value", onCommit = onChange)
                Text("Remove field", Modifier.clickable { set(value.toMutableList().also { it.removeAt(idx) }); onChange() },
                    style = IosTypography.caption, color = StashyColors.systemRed)
            }
        }
        Text("Add custom field", Modifier.clickable {
            set(value + JsonObject(mapOf("field" to JsonPrimitive(""), "value" to JsonArray(emptyList()), "modifier" to JsonPrimitive("EQUALS"))))
            onChange()
        }, style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold), color = Appearance.tint)
    }
}

@Composable
private fun RawJsonRow(value: JsonObject, set: (JsonObject) -> Unit, onChange: () -> Unit) {
    val p = Theme.palette
    var text by remember { mutableStateOf(prettyJson(value)) }
    var error by remember { mutableStateOf<String?>(null) }
    BasicTextField(
        text, { new ->
            text = new
            val obj = runCatching { Json.parseToJsonElement(new) as? JsonObject }.getOrNull()
            if (obj == null) error = "Not a valid JSON object" else { error = null; set(obj) }
        },
        Modifier.fillMaxWidth().heightIn(min = 80.dp).clip(RoundedCornerShape(8.dp)).background(p.background).padding(8.dp),
        textStyle = IosTypography.footnote.copy(color = p.text),
        cursorBrush = SolidColor(Appearance.tint),
    )
    error?.let { Text(it, style = IosTypography.caption, color = StashyColors.systemOrange) }
    DisposableEffect(Unit) { onDispose { onChange() } }
}

private val prettyJsonFormat = kotlinx.serialization.json.Json { prettyPrint = true }
private fun prettyJson(o: JsonObject): String = runCatching { prettyJsonFormat.encodeToString(JsonObject.serializer(), o) }.getOrDefault("{}")

/** iOS: `FilterMultiIdCriterionRow` → `CatalogNamedEntityLiveFilterMultiPickerRow` (tri-state, search, match mode). */
@Composable
private fun MultiIdRow(value: JsonObject, set: (JsonObject) -> Unit, entityKey: String, hierarchical: Boolean, mode: FilterMode, onChange: () -> Unit) {
    val kind = PickerKind.forCriterion(entityKey, mode)
    LaunchedEffect(kind) { kind?.let { FilterPickerOptionsStore.load(it) } }
    val modifierRaw = value["modifier"].stringValue ?: "INCLUDES"
    fun patch(vararg u: Pair<String, JsonElement?>) {
        var d = value.patch(*u)
        if (hierarchical && d["depth"] == null) d = d.with("depth", JsonPrimitive(0))
        if ((d["excludes"] as? JsonArray)?.isEmpty() == true) d = d.without("excludes")
        set(d); onChange()
    }
    MultiEntityPicker(
        selectedIds = FilterMapper.idStrings(value["value"]),
        excludedIds = FilterMapper.idStrings(value["excludes"]),
        matchMode = modifierRaw,
        matchModeOptions = (if (hierarchical) CriterionKind.hierarchicalMulti else CriterionKind.multi).defaultModifiers,
        kind = kind,
        onChange = { inc, exc, m ->
            patch("value" to JsonArray(inc.map { JsonPrimitive(it) }), "excludes" to JsonArray(exc.map { JsonPrimitive(it) }), "modifier" to JsonPrimitive(m))
        },
    )
}

/**
 * iOS: `CatalogNamedEntityLiveFilterMultiPickerRow` — inline list that stays open; rows cycle
 * none → include → exclude; "Any" / "None" (IS_NULL) on top; server name search.
 */
@Composable
fun MultiEntityPicker(
    selectedIds: List<String>,
    excludedIds: List<String>,
    matchMode: String,
    matchModeOptions: List<CriterionModifier>,
    kind: PickerKind?,
    onChange: (included: List<String>, excluded: List<String>, modifier: String) -> Unit,
) {
    val p = Theme.palette
    var expanded by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }
    var pinned by remember { mutableStateOf(emptyList<String>()) }
    val isNone = matchMode == CriterionModifier.IsNull.raw
    val options = kind?.let { FilterPickerOptionsStore.availableOptions(it) } ?: emptyList()
    val isLoading = kind?.let { FilterPickerOptionsStore.isLoading(it) } ?: false
    val rank = pinned.withIndex().associate { it.value to it.index }
    val entries = options.withIndex().sortedWith(compareBy({ rank[it.value.id] ?: Int.MAX_VALUE }, { it.index })).map { it.value }
    val term = searchText.trim()
    val visible = if (term.isEmpty()) entries else entries.filter { it.id in selectedIds || it.name.contains(term, ignoreCase = true) }

    val summary = run {
        if (isNone) return@run "None"
        if (selectedIds.isEmpty() && excludedIds.isEmpty()) return@run "Any"
        val names = entries.filter { it.id in selectedIds }.map { it.name }
        var s = when {
            names.isEmpty() -> if (selectedIds.isEmpty()) "" else "${selectedIds.size} selected"
            names.size <= 2 -> names.joinToString(", ")
            else -> "${names[0]}, ${names[1]} +${names.size - 2}"
        }
        if (excludedIds.isNotEmpty()) {
            val ex = entries.filter { it.id in excludedIds }.map { it.name }
            val listed = if (ex.size <= 2) ex.joinToString(", ") else "${ex[0]} +${ex.size - 1}"
            val suffix = "− ${listed.ifEmpty { excludedIds.size.toString() }}"
            s = if (s.isEmpty()) suffix else "$s · $suffix"
        }
        s
    }

    Column {
        Row(
            Modifier.fillMaxWidth().clickable {
                if (!expanded) pinned = selectedIds + excludedIds.filter { it !in selectedIds }
                expanded = !expanded
                kind?.let { FilterPickerOptionsStore.load(it) }
            }.padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(summary, Modifier.weight(1f), style = IosTypography.subheadline, color = if (selectedIds.isEmpty()) p.secondaryText else p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (isLoading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = p.secondaryText)
            else Icon(if (expanded) SF.chevronUp else SF.chevronDown, null, tint = Appearance.tint, modifier = Modifier.size(18.dp))
        }
        if (expanded) Column(Modifier.padding(bottom = 8.dp)) {
            if (kind != null && !isNone) {
                Row(
                    Modifier.padding(vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(50)).background(p.background).padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(SF.magnifyingglass, null, tint = p.secondaryText, modifier = Modifier.size(14.dp))
                    BasicTextField(
                        searchText, { searchText = it; FilterPickerOptionsStore.search(kind, it) }, Modifier.weight(1f),
                        textStyle = IosTypography.body.copy(color = p.text), singleLine = true, cursorBrush = SolidColor(Appearance.tint),
                        decorationBox = { inner -> Box { if (searchText.isEmpty()) Text("Search", style = IosTypography.body, color = p.tertiaryText); inner() } },
                    )
                    if (FilterPickerOptionsStore.isSearching(kind)) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = p.secondaryText)
                    else if (searchText.isNotEmpty()) Icon(SF.xmarkCircleFill, null, tint = p.secondaryText, modifier = Modifier.size(16.dp).clickable { searchText = ""; FilterPickerOptionsStore.search(kind, "") })
                }
            }
            if (!isNone) Row(Modifier.padding(horizontal = 4.dp).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(SF.checkmarkCircleFill, null, tint = Appearance.tint, modifier = Modifier.size(12.dp))
                Text("included", style = IosTypography.caption2, color = p.secondaryText)
                Icon(SF.xmarkCircleFill, null, tint = StashyColors.systemRed, modifier = Modifier.size(12.dp))
                Text("excluded", style = IosTypography.caption2, color = p.secondaryText)
            }
            if (matchModeOptions.isNotEmpty() && !isNone) {
                var mm by remember { mutableStateOf(false) }
                Box {
                    Row(Modifier.clickable { mm = true }.padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("(${CriterionModifier.from(matchMode)?.label ?: matchMode})", style = IosTypography.subheadline.copy(fontStyle = FontStyle.Italic), color = Appearance.tint)
                        Icon(SF.chevronUpChevronDown, null, tint = Appearance.tint, modifier = Modifier.size(12.dp))
                    }
                    DropdownMenu(mm, { mm = false }, containerColor = p.secondaryBackground) {
                        matchModeOptions.forEach { o ->
                            DropdownMenuItem(
                                text = { Text(o.label, color = p.text) },
                                trailingIcon = if (o.raw == matchMode) ({ Icon(SF.checkmark, null, tint = p.text) }) else null,
                                onClick = { mm = false; onChange(selectedIds, excludedIds, o.raw) },
                            )
                        }
                    }
                }
                HorizontalDivider(color = p.separator)
            }
            PickerOptionRow("Any", if (selectedIds.isEmpty() && excludedIds.isEmpty() && !isNone) 1 else 0) {
                onChange(emptyList(), emptyList(), if (isNone) "INCLUDES" else matchMode)
            }
            HorizontalDivider(color = p.separator)
            PickerOptionRow("None", if (isNone) 1 else 0) { onChange(emptyList(), emptyList(), CriterionModifier.IsNull.raw) }
            if (!isNone) visible.forEach { entry ->
                HorizontalDivider(color = p.separator)
                val state = when (entry.id) { in selectedIds -> 1; in excludedIds -> 2; else -> 0 }
                PickerOptionRow(entry.name, state) {
                    // none → include → exclude → none
                    when (state) {
                        0 -> onChange(selectedIds + entry.id, excludedIds, matchMode)
                        1 -> onChange(selectedIds - entry.id, excludedIds + entry.id, matchMode)
                        else -> onChange(selectedIds, excludedIds - entry.id, matchMode)
                    }
                }
            }
        }
    }
}

/** state: 0 none, 1 included, 2 excluded. */
@Composable
private fun PickerOptionRow(title: String, state: Int, onClick: () -> Unit) {
    val p = Theme.palette
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 9.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(
            when (state) { 1 -> SF.checkmarkCircleFill; 2 -> SF.xmarkCircleFill; else -> SF.circle },
            null,
            tint = when (state) { 1 -> Appearance.tint; 2 -> StashyColors.systemRed; else -> p.secondaryText },
            modifier = Modifier.size(20.dp),
        )
        Text(title, style = IosTypography.subheadline, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** iOS: `nestedEditorSheet(key:)` — a sub-filter (`performers_filter` …) in its own sheet with Cancel / Done. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NestedEditorSheet(title: String, mode: FilterMode, initial: JsonObject, onCancel: () -> Unit, onDone: (JsonObject) -> Unit) {
    val p = Theme.palette
    val doc = remember { CriteriaDocument(mode, initial) }
    ModalBottomSheet(onCancel, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = p.background) {
        Column(Modifier.fillMaxSize().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Cancel", Modifier.clickable(onClick = onCancel), style = IosTypography.body, color = Appearance.tint)
                Text(title, Modifier.weight(1f).padding(horizontal = 8.dp), style = IosTypography.headline, color = p.text, maxLines = 1,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Text("Done", Modifier.clickable { onDone(doc.sanitizedObjectFilter) }, style = IosTypography.headline, color = Appearance.tint)
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(top = Tokens.Spacing.xs)) {
                FilterCriteriaEditor(doc, onChange = {})
            }
        }
    }
}
