package de.letzgo.stashy.ui.components

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
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
                showToast(tr(R.string.error_add_tag))
                return@launch
            }
            suggestions.removeAll { it.tag.id == suggestion.tag.id }
            showToast(tr(R.string.added_arg, suggestion.tag.name))
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
            if (plan == null) showToast(tr(R.string.nothing_to_tag)) else pendingBulk = plan
        }
    }

    fun applyBulk(plan: AITagBulkPlan) {
        scope.launch {
            val success = AITagSuggestions.applyBulk(plan, target)
            if (!success) {
                showToast(tr(R.string.error_apply_tag))
                return@launch
            }
            showToast(tr(R.string.added_arg_to_arg_items, plan.tag.name, plan.total))
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
                    if (AITagSuggestions.hasModel) tr(R.string.empty_tag_suggestions) else tr(R.string.tag_suggestion_needs_statistics_first),
                    style,
                )
            }
        } else {
            suggestions.forEach { suggestion ->
                val tagId = suggestion.tag.id
                key(tagId) {
                    Box(Modifier.semantics { contentDescription = tr(R.string.action_add_tag_arg, suggestion.tag.name) }) {
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
                                text = { Text(tr(R.string.ignore_tag), color = StashyColors.systemRed) },
                                leadingIcon = { Icon(SF.xmark, null, tint = StashyColors.systemRed) },
                                onClick = {
                                    menuFor = null
                                    AITagSuggestions.dismiss(suggestion, target)
                                    suggestions.removeAll { it.id == suggestion.id }
                                },
                            )
                            if (target.galleryIds.isNotEmpty()) DropdownMenuItem(
                                text = { Text(tr(R.string.action_set_on_all_of_gallery), color = p.text) },
                                leadingIcon = { Icon(SF.photoStack, null, tint = p.text) },
                                onClick = { menuFor = null; planBulk(suggestion.tag, AITagBulkScope.Gallery) },
                            )
                            if (target.performerIds.isNotEmpty()) DropdownMenuItem(
                                text = { Text(tr(R.string.action_set_on_all_of_performer), color = p.text) },
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
        val scopeText = if (plan.scope == AITagBulkScope.Gallery) tr(R.string.this_gallery) else tr(R.string.this_performer)
        val parts = buildList {
            if (plan.imageIds.isNotEmpty()) add(tr(R.string.arg_count_images, plan.imageIds.size))
            if (plan.sceneIds.isNotEmpty()) add(tr(R.string.arg_count_scenes, plan.sceneIds.size))
        }
        StashyAlert(
            title = tr(R.string.confirm_add_arg, plan.tag.name),
            message = tr(R.string.hint_tag_is_added_to_arg, if (parts.size == 2) tr(R.string.arg_and_arg, parts[0], parts[1]) else parts.joinToString(), scopeText),
            onDismiss = { pendingBulk = null },
            confirmLabel = tr(R.string.action_add_to_arg, plan.total),
            dismissLabel = tr(R.string.action_cancel),
            onConfirm = { pendingBulk = null; applyBulk(plan) },
        )
    }
}
