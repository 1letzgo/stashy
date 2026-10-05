package de.letzgo.stashy.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.AITagTarget
import de.letzgo.stashy.ui.scene.EntityPickerSheet
import de.letzgo.stashy.ui.scene.PickerEntry

/**
 * iOS: `Components/AddTagsSheet` — "Edit Tags": search, multi-select, create a missing tag,
 * save in one mutation through `AITagSuggestions.write` (which also folds the change into the
 * suggestion statistics and broadcasts `TagsUpdated`). Rows are ordered like iOS: the item's own
 * tags, then what its performers usually carry, then library usage, then name.
 */
@Composable
fun AddTagsSheet(target: AITagTarget, onDismiss: () -> Unit, onComplete: (List<Tag>) -> Unit) {
    val byId = remember { mutableMapOf<String, Tag>() }
    val performerCounts = remember(target.id) { AITagSuggestions.performerTagCounts(target) }
    val currentIds = remember(target.id) { target.tags.map { it.id }.toSet() }

    fun usage(tag: Tag): Int = when (target.kind) {
        AITagTarget.Kind.Image -> tag.imageCount ?: 0
        AITagTarget.Kind.Scene, AITagTarget.Kind.Marker -> tag.sceneCount ?: 0
    }
    fun usageLabel(tag: Tag): String {
        performerCounts[tag.id]?.takeIf { it > 0 }?.let { return "$it× performer" }
        val n = usage(tag)
        return if (target.kind == AITagTarget.Kind.Image) "$n images" else "$n scenes"
    }
    fun entry(tag: Tag) = PickerEntry(tag.id, tag.name, usageLabel(tag))

    EntityPickerSheet(
        "Edit Tags", "Search Tags", currentIds, multiple = true,
        load = {
            // The statistics build already holds the whole tag list; reuse it like iOS.
            val fetched = AITagSuggestions.vocabulary.ifEmpty {
                SceneEditing.allTags(if (target.kind == AITagTarget.Kind.Image) "images_count" else "scenes_count")
            }
            // Tags the item already carries may sit outside the fetched page.
            val merged = fetched + target.tags.filter { t -> fetched.none { it.id == t.id } }
            merged.forEach { byId[it.id] = it }
            merged.sortedWith(
                compareByDescending<Tag> { it.id in currentIds }
                    .thenByDescending { performerCounts[it.id] ?: 0 }
                    .thenByDescending { usage(it) }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name },
            ).map(::entry)
        },
        create = { name -> SceneEditing.createTag(name).also { byId[it.id] = it }.let(::entry) },
        createFailedText = "Failed to create tag",
        save = { ids ->
            // A marker's primary tag is a separate field and stays whatever it was.
            val all = (ids + listOfNotNull(target.primaryTagId)).distinct()
            val tags = all.mapNotNull { byId[it] ?: target.tags.firstOrNull { t -> t.id == it } }
            check(AITagSuggestions.write(tags, target))
        },
        saveFailedText = "Failed to update tags",
        onSaved = { picked ->
            val ids = (picked.map { it.id } + listOfNotNull(target.primaryTagId)).distinct()
            onComplete(ids.mapNotNull { byId[it] })
        },
        onDismiss = onDismiss,
    )
}
