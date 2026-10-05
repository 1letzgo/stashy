package de.letzgo.stashy.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AssignmentInd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.AITagBulkPlan
import de.letzgo.stashy.data.tools.AITagBulkScope
import de.letzgo.stashy.data.tools.AITagSuggestion
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.tools.StashyAlert
import de.letzgo.stashy.ui.tools.showToast
import kotlinx.coroutines.launch

/**
 * iOS: `AITagSuggestionBar` — chip row with tag suggestions for one item (scene, marker, picture).
 * Renders nothing unless Tag Suggestions is unlocked *and* switched on. Chips only: the caller puts
 * them into its own tag row. Tapping a chip adds the tag — the write (`sceneUpdate` /
 * `imageUpdate` / `sceneMarkerUpdate` with the full `tag_ids`) is done by [AITagSuggestions.accept];
 * [onTagsChanged] then receives the item's new tag list. Long press: Ignore Tag, Set on all of
 * gallery / performer (with a confirmation that names the real count).
 *
 * The chips are the shared Material ones of [TagChipRow] ([TagSuggestionChip]); [style] follows
 * the row ([TagChipStyle.OverMedia] on Feeds / viewer chrome, [TagChipStyle.Surface] on cards).
 */
@Composable
fun AITagSuggestionBar(
    target: AITagTarget,
    modifier: Modifier = Modifier,
    style: TagChipStyle = TagChipStyle.OverMedia,
    onTagsChanged: (List<Tag>) -> Unit,
) {
    if (!AITagSuggestions.isActive) return
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current

    val suggestions = remember { mutableStateListOf<AITagSuggestion>() }
    var didRun by remember { mutableStateOf(false) }
    var acceptingTagId by remember { mutableStateOf<String?>(null) }
    var pendingBulk by remember { mutableStateOf<AITagBulkPlan?>(null) }
    var isPlanningBulk by remember { mutableStateOf(false) }
    var menuFor by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(target.id) {
        suggestions.clear()
        didRun = false
        acceptingTagId = null
        val cached = AITagSuggestions.cachedSuggestions(target)
        if (cached != null) {
            suggestions.addAll(cached)
            didRun = true
            return@LaunchedEffect
        }
        val result = AITagSuggestions.suggestions(target)
        val existing = target.tags.map { it.id }.toSet()
        suggestions.clear()
        suggestions.addAll(result.filter { it.tag.id !in existing })
        didRun = true
    }

    fun accept(suggestion: AITagSuggestion) {
        if (acceptingTagId != null) return
        acceptingTagId = suggestion.tag.id
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        scope.launch {
            val newTags = AITagSuggestions.accept(suggestion, target)
            acceptingTagId = null
            if (newTags == null) {
                showToast("Could not add tag")
                return@launch
            }
            suggestions.removeAll { it.tag.id == suggestion.tag.id }
            showToast("Added #${suggestion.tag.name}")
            onTagsChanged(newTags)
        }
    }

    /** Counts first, asks second: a bulk write can touch hundreds of items. */
    fun planBulk(tag: Tag, bulkScope: AITagBulkScope) {
        if (isPlanningBulk) return
        isPlanningBulk = true
        scope.launch {
            val plan = AITagSuggestions.planBulkApply(tag, bulkScope, target)
            isPlanningBulk = false
            if (plan == null) showToast("Nothing to tag") else pendingBulk = plan
        }
    }

    fun applyBulk(plan: AITagBulkPlan) {
        scope.launch {
            val success = AITagSuggestions.applyBulk(plan, target)
            if (!success) {
                showToast("Could not apply tag")
                return@launch
            }
            showToast("Added #${plan.tag.name} to ${plan.total} items")
            // The item itself is part of the batch, so its own row has to follow.
            if (target.tags.none { it.id == plan.tag.id }) onTagsChanged(target.tags + plan.tag)
            suggestions.removeAll { it.tag.id == plan.tag.id }
        }
    }

    Row(modifier, horizontalArrangement = Arrangement.spacedBy(TagChips.spacing), verticalAlignment = Alignment.CenterVertically) {
        if (suggestions.isEmpty()) {
            // Only worth saying on an untagged item.
            if (didRun && target.tags.isEmpty()) {
                TagRowHint(
                    if (AITagSuggestions.hasModel) "No tag suggestions" else "Tag Suggestion needs statistics first",
                    style,
                )
            }
        } else {
            suggestions.forEach { suggestion ->
                val tagId = suggestion.tag.id
                key(tagId) {
                    Box(Modifier.semantics { contentDescription = "Add tag ${suggestion.tag.name}" }) {
                        TagSuggestionChip(
                            name = suggestion.tag.name,
                            detail = "${Math.round(suggestion.confidence * 100)}%",
                            style = style,
                            accepting = acceptingTagId == tagId,
                            enabled = acceptingTagId == null,
                            onClick = { accept(suggestion) },
                            onLongPress = {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                menuFor = tagId
                            },
                        )
                        // iOS: `.contextMenu`.
                        val p = Theme.palette
                        DropdownMenu(
                            expanded = menuFor == tagId,
                            onDismissRequest = { menuFor = null },
                            containerColor = p.secondaryBackground,
                        ) {
                            DropdownMenuItem(
                                text = { Text("Ignore Tag", color = StashyColors.systemRed) },
                                leadingIcon = { Icon(SF.xmark, null, tint = StashyColors.systemRed) },
                                onClick = {
                                    menuFor = null
                                    AITagSuggestions.dismiss(suggestion, target)
                                    suggestions.removeAll { it.id == suggestion.id }
                                },
                            )
                            if (target.galleryIds.isNotEmpty()) DropdownMenuItem(
                                text = { Text("Set on all of gallery", color = p.text) },
                                leadingIcon = { Icon(SF.photoStack, null, tint = p.text) },
                                onClick = { menuFor = null; planBulk(suggestion.tag, AITagBulkScope.Gallery) },
                            )
                            if (target.performerIds.isNotEmpty()) DropdownMenuItem(
                                text = { Text("Set on all of performer", color = p.text) },
                                leadingIcon = { Icon(Icons.Outlined.AssignmentInd, null, tint = p.text) },
                                onClick = { menuFor = null; planBulk(suggestion.tag, AITagBulkScope.Performer) },
                            )
                        }
                    }
                }
            }
        }
    }

    pendingBulk?.let { plan ->
        val scopeText = if (plan.scope == AITagBulkScope.Gallery) "this gallery" else "this performer"
        val parts = buildList {
            if (plan.imageIds.isNotEmpty()) add("${plan.imageIds.size} images")
            if (plan.sceneIds.isNotEmpty()) add("${plan.sceneIds.size} scenes")
        }
        StashyAlert(
            title = "Add #${plan.tag.name}?",
            message = "The tag is added to ${parts.joinToString(" and ")} of $scopeText. Items that already have it stay unchanged.",
            onDismiss = { pendingBulk = null },
            confirmLabel = "Add to ${plan.total}",
            dismissLabel = "Cancel",
            onConfirm = { pendingBulk = null; applyBulk(plan) },
        )
    }
}
