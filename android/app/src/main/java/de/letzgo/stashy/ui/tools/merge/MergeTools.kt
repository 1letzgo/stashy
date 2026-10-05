package de.letzgo.stashy.ui.tools.merge

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MergeType
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.tools.MergePreset
import de.letzgo.stashy.data.tools.MergePresetEntry
import de.letzgo.stashy.data.tools.MergePresetStore
import de.letzgo.stashy.data.tools.MergeItemIndex
import de.letzgo.stashy.data.tools.MergeRepository
import de.letzgo.stashy.data.tools.MergeSort
import de.letzgo.stashy.data.tools.MergeStudio
import de.letzgo.stashy.data.tools.MergeTag
import de.letzgo.stashy.data.tools.MergeableItem
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Chevron
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.Tokens
import de.letzgo.stashy.ui.tools.NoServerPlaceholder
import de.letzgo.stashy.ui.tools.SmallSpinner
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.ToolsBottomPadding
import de.letzgo.stashy.ui.tools.ToolsTokens
import de.letzgo.stashy.ui.tools.showToast
import de.letzgo.stashy.ui.tools.toolsTopPadding
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// iOS: `MergeTools.swift` (`MergeToolsView`, `MergeDestinationSheet`, `StudioMergeToolsView`)
// and `TagMergeToolsView.swift`.

/** iOS: `MergeToolsConfig` — everything that differs between tags and studios. */
class MergeToolsConfig<T : MergeableItem>(
    /** Only for the template key (`tags`, `studios`). */
    val kind: String,
    val noun: String,
    val nounPlural: String,
    val loadAll: suspend () -> List<T>,
    val merge: suspend (sourceIds: List<String>, destinationId: String) -> Unit,
    /** After a successful merge (invalidate caches …). */
    val didMerge: () -> Unit = {},
)

/** iOS: `MergeToolsLayout`. */
private object MergeToolsLayout {
    /** Rows added per reveal step. */
    const val PAGE_SIZE = 50
    /** Template pills and the run-all button share one height. */
    val presetPillHeight: Dp = 44.dp
}

/**
 * iOS: `TagMergeToolsView` — merges several tags into one. Stash rewrites everything that points
 * at the sources (`tagsMerge`) and deletes them.
 */
@Composable
fun TagMergeToolView() {
    val config = remember {
        MergeToolsConfig<MergeTag>(
            kind = "tags", noun = "tag", nounPlural = "tags",
            loadAll = { MergeRepository.fetchEveryTagForMerge() },
            merge = { sources, destination -> MergeRepository.mergeTags(sources, destination) },
        )
    }
    MergeToolsView(config)
}

/**
 * iOS: `StudioMergeToolsView` — Stash has no `studiosMerge`; [MergeRepository.mergeStudios] moves
 * scenes, galleries, images, groups and child studios by bulk update and deletes the sources.
 */
@Composable
fun StudioMergeToolView() {
    val config = remember {
        MergeToolsConfig<MergeStudio>(
            kind = "studios", noun = "studio", nounPlural = "studios",
            loadAll = { MergeRepository.fetchEveryStudioForMerge() },
            merge = { sources, destination -> MergeRepository.mergeStudios(sources, destination) },
        )
    }
    MergeToolsView(config)
}

/**
 * iOS: `MergeToolsView` — load once, filter locally. Pinned header (destination, templates, list
 * heading), a card list with the search as first row, and the merge bar at the bottom.
 */
@Composable
fun <T : MergeableItem> MergeToolsView(config: MergeToolsConfig<T>) {
    val nounTitle = config.nounPlural.replaceFirstChar { it.uppercase() }
    if (ServerConfigManager.activeConfig == null) {
        NoServerPlaceholder(Icons.Filled.MergeType, "Connect to a Stash server to merge $nounTitle.")
        return
    }
    // Each server has its own list and templates.
    key(ServerConfigManager.activeConfig?.id) { MergeToolsContent(config, nounTitle) }
}

private data class RunnablePreset<T>(val preset: MergePreset, val destination: T, val sources: List<T>)

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun <T : MergeableItem> MergeToolsContent(config: MergeToolsConfig<T>, nounTitle: String) {
    val p = Theme.palette
    val tint = Appearance.tint
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val presets = remember { MergePresetStore(config.kind) }

    var allItems by remember { mutableStateOf<List<T>>(emptyList()) }
    // Set together with `allItems`; templates resolve their entries through it.
    var itemIndex by remember { mutableStateOf(MergeItemIndex<T>()) }
    var isLoading by remember { mutableStateOf(false) }
    var visibleCount by remember { mutableIntStateOf(MergeToolsLayout.PAGE_SIZE) }
    var searchText by remember { mutableStateOf("") }
    var sources by remember { mutableStateOf<Set<String>>(emptySet()) }
    var destination by remember { mutableStateOf<T?>(null) }
    var showingDestinationPicker by remember { mutableStateOf(false) }
    var showingConfirmation by remember { mutableStateOf(false) }
    var showingRunAllConfirmation by remember { mutableStateOf(false) }
    var showingSavePrompt by remember { mutableStateOf(false) }
    var showingSaveChoice by remember { mutableStateOf(false) }
    var presetName by remember { mutableStateOf("") }
    var presetToDelete by remember { mutableStateOf<MergePreset?>(null) }
    // Last applied template — "Save" then offers to update it.
    var activePreset by remember { mutableStateOf<MergePreset?>(null) }
    var isMerging by remember { mutableStateOf(false) }

    fun setItems(items: List<T>) {
        allItems = items
        itemIndex = MergeItemIndex(items)
    }

    // Selected first: with few visible rows the order decides what stays reachable.
    val filtered: List<T> = run {
        val base = allItems.filter { it.id != destination?.id }
        val matches = if (searchText.isEmpty()) base else base.filter { it.name.contains(searchText, ignoreCase = true) }
        matches.sortedWith { l, r ->
            val ls = l.id in sources
            val rs = r.id in sources
            if (ls != rs) (if (ls) -1 else 1) else MergeSort.compare(l.name, r.name)
        }
    }
    val selectedSources: List<T> = allItems.filter { it.id in sources }
    val canMerge = destination != null && sources.isNotEmpty() && !isMerging
    val canSavePreset = (destination != null || activePreset != null) && sources.isNotEmpty() && !isMerging
    val hasSelection = destination != null || sources.isNotEmpty() || searchText.isNotEmpty()

    fun resolveSources(preset: MergePreset): Pair<List<T>, List<MergePresetEntry>> {
        val destinationId = itemIndex.resolve(preset.destination)?.id
        val resolved = mutableListOf<T>()
        val unresolved = mutableListOf<MergePresetEntry>()
        val seen = mutableSetOf<String>()
        for (entry in preset.sources) {
            val item = itemIndex.resolve(entry)
            if (item == null) { unresolved.add(entry); continue }
            // What points at the destination is already merged.
            if (item.id == destinationId || !seen.add(item.id)) continue
            resolved.add(item)
        }
        return resolved to unresolved
    }

    /** Entries of the applied template that are missing on the server — they stay in it. */
    fun missingPresetSources(): List<MergePresetEntry> {
        val active = activePreset ?: return emptyList()
        return active.sources.filter { itemIndex.resolve(it) == null }
    }

    fun runnablePresets(): List<RunnablePreset<T>> = presets.presets.mapNotNull { preset ->
        val dest = itemIndex.resolve(preset.destination) ?: return@mapNotNull null
        val resolved = resolveSources(preset).first
        if (resolved.isEmpty()) null else RunnablePreset(preset, dest, resolved)
    }

    fun presetSubtitle(preset: MergePreset, missing: Int): String {
        val total = preset.sources.size
        val noun = if (total == 1) "source" else "sources"
        if (allItems.isEmpty()) return "$total $noun"
        return "${total - missing} of $total $noun on the server"
    }

    fun nounFor(count: Int) = if (count == 1) config.noun else config.nounPlural

    fun load() {
        visibleCount = MergeToolsLayout.PAGE_SIZE
        isLoading = true
        scope.launch {
            try {
                val items = config.loadAll()
                setItems(items.sortedWith(MergeSort.byName()))
                isLoading = false
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                isLoading = false
                showToast("Failed to load ${config.nounPlural}")
            }
        }
    }

    fun entry(item: T) = MergePresetEntry(item.id, item.name, item.mergeStashIds)

    fun isPresetActive(preset: MergePreset): Boolean {
        val dest = destination ?: return false
        val resolvedDest = itemIndex.resolve(preset.destination) ?: return false
        if (dest.id != resolvedDest.id) return false
        return sources == resolveSources(preset).first.map { it.id }.toSet()
    }

    fun apply(preset: MergePreset) {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        val (resolved, unresolved) = resolveSources(preset)
        val resolvedDest = itemIndex.resolve(preset.destination)
        destination = resolvedDest
        sources = resolved.map { it.id }.toSet()
        searchText = ""
        activePreset = preset
        val missingNames = unresolved.map { it.displayName }.toMutableList()
        if (resolvedDest == null) missingNames.add(0, preset.destination.displayName)
        if (missingNames.isNotEmpty()) {
            val shown = missingNames.take(3).joinToString(", ")
            val rest = missingNames.size - minOf(3, missingNames.size)
            showToast("Not on this server (kept in template): $shown${if (rest > 0) " +$rest more" else ""}", long = true)
        }
    }

    fun savePreset() {
        val dest = destination ?: return
        if (sources.isEmpty()) return
        val name = presetName.trim()
        if (name.isEmpty()) return
        val preset = MergePreset(name = name, destination = entry(dest), sources = selectedSources.map { entry(it) } + missingPresetSources())
        presets.save(preset)
        activePreset = preset
        showToast("Template saved")
    }

    fun updateActivePreset() {
        val active = activePreset ?: return
        if (sources.isEmpty()) return
        // Destination missing on the server: the stored one stays.
        val destEntry = destination?.let { entry(it) } ?: active.destination
        presets.update(active.id, destEntry, selectedSources.map { entry(it) } + missingPresetSources())
        activePreset = presets.presets.firstOrNull { it.id == active.id }
        showToast("Template updated")
    }

    fun clearSelection() {
        sources = emptySet()
        destination = null
        searchText = ""
        activePreset = null
    }

    fun toggle(item: T) {
        sources = if (item.id in sources) sources - item.id else sources + item.id
    }

    fun merge() {
        val dest = destination ?: return
        if (sources.isEmpty()) return
        val sourceIds = sources.toList()
        val mergedCount = sourceIds.size
        isMerging = true
        scope.launch {
            try {
                config.merge(sourceIds, dest.id)
                isMerging = false
                sources = emptySet()
                setItems(allItems.filterNot { it.id in sourceIds })
                config.didMerge()
                showToast("$mergedCount ${nounFor(mergedCount)} merged into ${dest.name}")
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                isMerging = false
                showToast("Merge failed: ${e.message}", long = true)
            }
        }
    }

    /** Runs every template in turn; the index is refreshed after each one. */
    fun runAllPresets() {
        val jobs = runnablePresets()
        if (jobs.isEmpty() || isMerging) return
        isMerging = true
        sources = emptySet()
        destination = null
        activePreset = null
        scope.launch {
            var mergedTotal = 0
            val failed = mutableListOf<String>()
            for (job in jobs) {
                val resolvedNow = resolveSources(job.preset).first
                if (resolvedNow.isEmpty()) continue
                val sourceIds = resolvedNow.map { it.id }
                try {
                    config.merge(sourceIds, job.destination.id)
                    mergedTotal += sourceIds.size
                    setItems(allItems.filterNot { it.id in sourceIds })
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    failed.add(job.preset.name)
                }
            }
            isMerging = false
            if (mergedTotal > 0) config.didMerge()
            if (failed.isEmpty()) {
                showToast("$mergedTotal ${nounFor(mergedTotal)} merged from ${jobs.size} templates")
            } else {
                val more = if (failed.size > 3) " +${failed.size - 3}" else ""
                showToast("$mergedTotal merged, failed: ${failed.take(3).joinToString(", ")}$more", long = true)
            }
            load()
        }
    }

    LaunchedEffect(Unit) { if (allItems.isEmpty()) load() }
    LaunchedEffect(searchText) { visibleCount = MergeToolsLayout.PAGE_SIZE }

    Column(Modifier.fillMaxSize().background(p.background)) {
        // MARK: Pinned header — destination, templates and list heading stay visible.
        Column(
            Modifier.fillMaxWidth()
                .background(p.background)
                .padding(horizontal = ToolsTokens.contentPadding)
                .padding(top = toolsTopPadding() + ToolsTokens.menuTopPadding, bottom = Tokens.Spacing.xs),
        ) {
            DestinationField(destination?.name, destination?.mergeUsageSummary) { showingDestinationPicker = true }

            if (presets.presets.isNotEmpty()) {
                val runnable = runnablePresets().size
                Row(
                    Modifier.fillMaxWidth().padding(top = Tokens.Spacing.xs),
                    horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Icon only: the pills carry the names, this must not look like another template.
                    val runEnabled = runnable > 0 && !isMerging
                    Box(
                        Modifier.width(40.dp).height(MergeToolsLayout.presetPillHeight)
                            .clip(RoundedCornerShape(50))
                            .background(p.secondaryBackground)
                            .clickable(enabled = runEnabled) { showingRunAllConfirmation = true },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.PlaylistPlay, "Run all templates",
                            tint = if (runnable > 0) tint else p.secondaryText, modifier = Modifier.size(20.dp),
                        )
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs)) {
                        items(presets.presets, key = { it.id }) { preset ->
                            val active = isPresetActive(preset)
                            val missing = resolveSources(preset).second.size
                            val fg = if (active) Color.White else p.text
                            Column(
                                Modifier.height(MergeToolsLayout.presetPillHeight)
                                    .clip(RoundedCornerShape(50))
                                    .background(if (active) tint else p.secondaryBackground)
                                    // Long press → delete (with confirmation).
                                    .combinedClickable(
                                        onClick = { apply(preset) },
                                        onLongClick = {
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            presetToDelete = preset
                                        },
                                    )
                                    .padding(horizontal = Tokens.Spacing.sm),
                                verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Icon(SF.bookmarkFill, null, tint = fg, modifier = Modifier.size(11.dp))
                                    Text(preset.name, style = IosTypography.footnote.copy(fontWeight = FontWeight.Medium), color = fg, maxLines = 1)
                                }
                                Text(
                                    presetSubtitle(preset, missing), style = IosTypography.caption2,
                                    color = fg, maxLines = 1, modifier = Modifier.alpha(0.75f),
                                )
                            }
                        }
                    }
                }
            }

            // Category heading over the list, Settings style.
            Text(
                nounTitle.uppercase(), style = IosTypography.footnote, color = p.secondaryText,
                modifier = Modifier.fillMaxWidth().padding(top = Tokens.Spacing.md),
            )
        }

        // MARK: List card — search as first row, then the rows it filters.
        val shown = filtered.take(visibleCount)
        val showsMoreFooter = shown.isNotEmpty() && (visibleCount < filtered.size || isLoading)
        val divider = p.text.copy(alpha = 0.15f)
        LazyColumn(
            Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(start = ToolsTokens.contentPadding, end = ToolsTokens.contentPadding, bottom = Tokens.Spacing.sm),
        ) {
            val stateRowLast = shown.isEmpty()
            item(key = "search") {
                Column(Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(first = true, last = false))) {
                    MergeSearchField("Search ${config.nounPlural}", searchText, { searchText = it }, Modifier.padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm))
                    Box(Modifier.fillMaxWidth().height(0.5.dp).background(divider))
                }
            }
            when {
                isLoading && allItems.isEmpty() -> item(key = "loading") {
                    Row(
                        Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, stateRowLast)).padding(vertical = Tokens.Spacing.lg),
                        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SmallSpinner()
                        Text("Loading...", style = IosTypography.subheadline, color = p.secondaryText)
                    }
                }
                filtered.isEmpty() -> item(key = "empty") {
                    Text(
                        if (allItems.isEmpty()) "This server has no ${config.nounPlural} yet." else "No matches",
                        style = IosTypography.callout, color = p.secondaryText,
                        modifier = Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, true)).padding(Tokens.Spacing.md),
                    )
                }
                else -> {
                    itemsIndexed(shown, key = { _, item -> "row-" + item.id }) { index, item ->
                        if (index == shown.lastIndex) {
                            LaunchedEffect(item.id, filtered.size) {
                                if (visibleCount < filtered.size) visibleCount += MergeToolsLayout.PAGE_SIZE
                            }
                        }
                        val last = index == shown.lastIndex && !showsMoreFooter
                        Column(Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, last))) {
                            if (index > 0) Box(Modifier.fillMaxWidth().padding(start = Tokens.Spacing.md).height(0.5.dp).background(divider))
                            MergeItemRow(item.name, item.mergeUsageSummary, checked = item.id in sources) { toggle(item) }
                        }
                    }
                    if (showsMoreFooter) item(key = "more") {
                        Column(Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, true))) {
                            Box(Modifier.fillMaxWidth().padding(start = Tokens.Spacing.md).height(0.5.dp).background(divider))
                            Row(
                                Modifier.fillMaxWidth().padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm),
                                horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                SmallSpinner()
                                Text("Loading more...", style = IosTypography.caption, color = p.secondaryText)
                            }
                        }
                    }
                }
            }
        }

        // MARK: Merge bar
        Column(
            Modifier.fillMaxWidth().background(p.background)
                .padding(horizontal = ToolsTokens.contentPadding)
                .padding(top = Tokens.Spacing.sm, bottom = ToolsBottomPadding),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
        ) {
            val dest = destination
            if (canMerge && dest != null) {
                Text("${sources.size} ${nounFor(sources.size)} → ${dest.name}", style = IosTypography.caption, color = p.secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier.weight(1f)
                        .alpha(if (canMerge || isMerging) 1f else 0.5f)
                        .clip(RoundedCornerShape(Tokens.Radius.button))
                        .background(tint)
                        .clickable(enabled = canMerge) { showingConfirmation = true }
                        .padding(vertical = Tokens.Spacing.sm),
                    horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (isMerging) SmallSpinner(Color.White)
                    Text(if (isMerging) "Merging..." else "Merge $nounTitle", style = IosTypography.body.copy(fontWeight = FontWeight.SemiBold), color = Color.White)
                }
                MergeSecondaryButton("Save", canSavePreset) {
                    val active = activePreset
                    if (active != null && presets.presets.any { it.id == active.id }) {
                        showingSaveChoice = true
                    } else {
                        presetName = destination?.name ?: ""
                        showingSavePrompt = true
                    }
                }
                MergeSecondaryButton("Clear", hasSelection && !isMerging) { clearSelection() }
            }
        }
    }

    // MARK: Sheets & alerts

    if (showingDestinationPicker) {
        MergeDestinationSheet(
            items = allItems,
            excludedIds = sources,
            sectionTitle = "Search $nounTitle",
            onPick = { picked ->
                destination = picked
                sources = sources - picked.id
                showingDestinationPicker = false
            },
            onCancel = { showingDestinationPicker = false },
        )
    }

    if (showingConfirmation) {
        val dest = destination
        StashyAlert(
            title = "Merge ${config.nounPlural}?",
            message = dest?.let { "${selectedSources.joinToString(", ") { s -> s.name }} will be merged into ${it.name} and then deleted. This cannot be undone." } ?: "",
            onDismiss = { showingConfirmation = false },
            confirmLabel = "Merge", destructive = true, dismissLabel = "Cancel",
            onConfirm = { showingConfirmation = false; merge() },
        )
    }

    if (showingRunAllConfirmation) {
        val runnable = runnablePresets()
        val sourceCount = runnable.sumOf { it.sources.size }
        val skipped = presets.presets.size - runnable.size
        var text = "${runnable.size} of ${presets.presets.size} templates have something to merge: " +
            "$sourceCount ${nounFor(sourceCount)} will be merged into their destinations, one template after another."
        if (skipped > 0) text += " $skipped ${if (skipped == 1) "template has" else "templates have"} nothing to do right now and will be skipped."
        text += " This cannot be undone."
        StashyAlert(
            title = "Run all templates?", message = text,
            onDismiss = { showingRunAllConfirmation = false },
            confirmLabel = "Merge all", destructive = true, dismissLabel = "Cancel",
            onConfirm = { showingRunAllConfirmation = false; runAllPresets() },
        )
    }

    if (showingSavePrompt) {
        MergeSavePrompt(
            name = presetName,
            onNameChange = { presetName = it },
            onSave = { showingSavePrompt = false; savePreset() },
            onCancel = { showingSavePrompt = false },
        )
    }

    presetToDelete?.let { preset ->
        StashyAlert(
            title = "Delete template?",
            message = "\"${preset.name}\" will be removed from this device.",
            onDismiss = { presetToDelete = null },
            confirmLabel = "Delete", destructive = true, dismissLabel = "Cancel",
            onConfirm = {
                presets.delete(preset)
                if (activePreset?.id == preset.id) activePreset = null
                presetToDelete = null
            },
        )
    }

    if (showingSaveChoice) {
        val active = activePreset
        val actions = buildList<Pair<String, () -> Unit>> {
            if (active != null) add("Update \"${active.name}\"" to { showingSaveChoice = false; updateActivePreset() })
            add("Save as new" to {
                showingSaveChoice = false
                presetName = destination?.name ?: ""
                showingSavePrompt = true
            })
        }
        MergeChoiceDialog("Save template", actions) { showingSaveChoice = false }
    }
}

private fun cardShape(first: Boolean, last: Boolean): RoundedCornerShape {
    val r = Tokens.Radius.card
    return RoundedCornerShape(
        topStart = if (first) r else 0.dp, topEnd = if (first) r else 0.dp,
        bottomStart = if (last) r else 0.dp, bottomEnd = if (last) r else 0.dp,
    )
}

/** The destination picker field — first field of the header, carries its own label. */
@Composable
private fun DestinationField(name: String?, summary: String?, onClick: () -> Unit) {
    val p = Theme.palette
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(Tokens.Radius.card))
            .background(p.secondaryBackground)
            .clickable(onClick = onClick)
            .heightIn(min = 22.dp)
            .padding(horizontal = Tokens.Spacing.sm, vertical = Tokens.Spacing.xs + 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (name != null) {
                Text("Merge into", style = IosTypography.caption, color = p.secondaryText)
                Text(name, style = IosTypography.body, color = p.text)
                if (summary != null) Text(summary, style = IosTypography.caption, color = p.secondaryText)
            } else {
                Text("Merge into…", style = IosTypography.body, color = p.secondaryText)
            }
        }
        Icon(Icons.Chevron, null, tint = p.secondaryText, modifier = Modifier.size(18.dp))
    }
}

/** One list row: name, usage line, checkmark when selected as a source. */
@Composable
private fun MergeItemRow(name: String, summary: String, checked: Boolean, onClick: () -> Unit) {
    val p = Theme.palette
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.sm),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, style = IosTypography.body, color = p.text)
            Text(summary, style = IosTypography.caption, color = p.secondaryText)
        }
        if (checked) Icon(Icons.Filled.Check, null, tint = Appearance.tint, modifier = Modifier.size(20.dp))
    }
}

/** iOS: the search row of the card / `ToolsSearchField` — the shared Material search pill on the card. */
@Composable
private fun MergeSearchField(prompt: String, text: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) =
    NativeSearchField(text, onChange, prompt, modifier, containerColor = Theme.palette.background)

@Composable
private fun MergeSecondaryButton(title: String, enabled: Boolean, onClick: () -> Unit) {
    val p = Theme.palette
    Text(
        title,
        style = IosTypography.body.copy(fontWeight = FontWeight.SemiBold), color = p.text,
        modifier = Modifier
            .alpha(if (enabled) 1f else 0.4f)
            .clip(RoundedCornerShape(Tokens.Radius.button))
            .background(p.secondaryBackground)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm),
    )
}

/** iOS: `.alert("Save template") { TextField("Name") … }`. */
@Composable
private fun MergeSavePrompt(name: String, onNameChange: (String) -> Unit, onSave: () -> Unit, onCancel: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    AlertDialog(
        onDismissRequest = onCancel,
        containerColor = p.secondaryBackground,
        titleContentColor = p.text,
        title = { Text("Save template", style = IosTypography.headline) },
        text = {
            NativeTextField(name, onNameChange, label = null, placeholder = "Name", autoCorrect = true)
        },
        confirmButton = { TextButton(onClick = onSave) { Text("Save", color = tint, fontWeight = FontWeight.SemiBold) } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel", color = tint) } },
    )
}

/** iOS alert with several stacked buttons plus Cancel. */
@Composable
private fun MergeChoiceDialog(title: String, actions: List<Pair<String, () -> Unit>>, onCancel: () -> Unit) {
    val p = Theme.palette
    val tint = Appearance.tint
    AlertDialog(
        onDismissRequest = onCancel,
        containerColor = p.secondaryBackground,
        titleContentColor = p.text,
        title = { Text(title, style = IosTypography.headline) },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                actions.forEach { (label, action) ->
                    TextButton(onClick = action) { Text(label, color = tint, fontWeight = FontWeight.SemiBold) }
                }
                TextButton(onClick = onCancel) { Text("Cancel", color = tint) }
            }
        },
    )
}

/**
 * iOS: `MergeDestinationSheet` — same search form as the tool page, filtered locally, items handed
 * over from the tool page so nothing is loaded here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T : MergeableItem> MergeDestinationSheet(
    items: List<T>,
    excludedIds: Set<String>,
    sectionTitle: String,
    onPick: (T) -> Unit,
    onCancel: () -> Unit,
) {
    val p = Theme.palette
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var searchText by remember { mutableStateOf("") }
    var visibleCount by remember { mutableIntStateOf(MergeToolsLayout.PAGE_SIZE) }
    LaunchedEffect(searchText) { visibleCount = MergeToolsLayout.PAGE_SIZE }
    val filtered = items.filter { it.id !in excludedIds }.let { base ->
        if (searchText.isEmpty()) base else base.filter { it.name.contains(searchText, ignoreCase = true) }
    }
    val shown = filtered.take(visibleCount)
    val divider = p.text.copy(alpha = 0.15f)

    ModalBottomSheet(onDismissRequest = onCancel, sheetState = state, containerColor = p.background, dragHandle = null) {
        Column(Modifier.fillMaxSize()) {
            // iOS: `stashyModalSheetChrome("Merge into", onBack:)`.
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
                Text("Merge into", style = IosTypography.headline, color = p.text, modifier = Modifier.align(Alignment.Center))
                Text(
                    "Cancel", style = IosTypography.body, color = Appearance.tint,
                    modifier = Modifier.align(Alignment.CenterStart).clickable(onClick = onCancel),
                )
            }
            LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp)) {
                item(key = "header") {
                    Text(sectionTitle.uppercase(), style = IosTypography.footnote, color = p.secondaryText, modifier = Modifier.padding(start = 16.dp, bottom = 8.dp))
                }
                item(key = "search") {
                    Column(Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(true, shown.isEmpty()))) {
                        MergeSearchField("Search...", searchText, { searchText = it }, Modifier.padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm))
                    }
                }
                val more = visibleCount < filtered.size
                itemsIndexed(shown, key = { _, item -> item.id }) { index, item ->
                    if (index == shown.lastIndex) {
                        LaunchedEffect(item.id, filtered.size) {
                            if (visibleCount < filtered.size) visibleCount += MergeToolsLayout.PAGE_SIZE
                        }
                    }
                    Column(Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, index == shown.lastIndex && !more))) {
                        Box(Modifier.fillMaxWidth().padding(start = Tokens.Spacing.md).height(0.5.dp).background(divider))
                        MergeItemRow(item.name, item.mergeUsageSummary, checked = false) { onPick(item) }
                    }
                }
                if (more) item(key = "more") {
                    Row(
                        Modifier.fillMaxWidth().background(p.secondaryBackground, cardShape(false, true))
                            .padding(horizontal = Tokens.Spacing.md, vertical = Tokens.Spacing.sm),
                        horizontalArrangement = Arrangement.spacedBy(Tokens.Spacing.xs),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SmallSpinner()
                        Text("Loading more...", style = IosTypography.caption, color = p.secondaryText)
                    }
                }
                item { Spacer(Modifier.height(32.dp)) }
            }
        }
    }
}
