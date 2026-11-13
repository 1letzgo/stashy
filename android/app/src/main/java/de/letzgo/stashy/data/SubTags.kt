package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: `TagHierarchy` (TagRepository.swift), the counterpart of [SubStudios]. Pure logic only —
 * the two settings live in [TagHierarchyStore]:
 * - "Hide sub-tags" (`tags_hide_sub_tags`): the Tags list shows top-level tags only.
 * - "Include sub-tag content" (`tags_include_sub_tag_content`): a tag's page shows what its
 *   sub-tags hold, the cards count it.
 * A tag can have several parents, unlike a studio.
 */
object SubTags {
    const val HIDE_KEY = "tags_hide_sub_tags"
    const val INCLUDE_KEY = "tags_include_sub_tag_content"

    /** `depth` of a `tags` criterion that scopes a list to one tag. */
    fun depth(includeContent: Boolean): Int = if (includeContent) -1 else 0

    /**
     * The extra `tag_filter` criterion of the Tags list: `parent_count = 0` (top-level only)
     * while "Hide sub-tags" is on. A search still finds every tag, and a `parents` or
     * `parent_count` criterion of the user's own wins. `null` = add nothing.
     */
    fun hideCriterion(hide: Boolean, search: String, userCriteria: JsonObject?): JsonObject? {
        if (!hide || search.isNotBlank()) return null
        if (userCriteria?.containsKey("parents") == true || userCriteria?.containsKey("parent_count") == true) return null
        return buildJsonObject {
            put("parent_count", buildJsonObject { put("value", JsonPrimitive(0)); put("modifier", JsonPrimitive("EQUALS")) })
        }
    }

    /** Switching "Hide sub-tags" on also switches "Include sub-tag content" on (it can be switched off again). */
    fun includeAfterHideChange(hideNow: Boolean, includeBefore: Boolean): Boolean = if (hideNow) true else includeBefore

    /** What a tag's page sends for its scenes, galleries, studios, groups and images. */
    fun tagScope(tagId: String, includeContent: Boolean): JsonObject = buildJsonObject {
        put("tags", buildJsonObject {
            put("value", JsonArray(listOf(JsonPrimitive(tagId))))
            put("modifier", JsonPrimitive("INCLUDES"))
            put("depth", JsonPrimitive(depth(includeContent)))
        })
    }

    /** The direct sub-tags of [parentId] (a tag page's "Sub-Tags" section). */
    fun subTagScope(parentId: String): JsonObject = buildJsonObject {
        put("parents", buildJsonObject {
            put("value", JsonArray(listOf(JsonPrimitive(parentId))))
            put("modifier", JsonPrimitive("INCLUDES"))
            put("depth", JsonPrimitive(0))
        })
    }

    /**
     * Stash sorts `scenes_count` by a tag's own scenes only. With "Include sub-tag content" on,
     * the list is fetched whole and sorted by [sortedBySceneCountAll] instead.
     */
    fun sortsBySceneCountAll(sortField: String, includeContent: Boolean): Boolean = sortField == "scenes_count" && includeContent

    /** By scenes including sub-tags (own count as fallback), the name as tie-breaker. */
    fun sortedBySceneCountAll(tags: List<Tag>, ascending: Boolean): List<Tag> {
        val byCount = compareBy<Tag> { it.sceneCountAll ?: it.sceneCount ?: 0 }
        return tags.sortedWith((if (ascending) byCount else byCount.reversed()).thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /**
     * [document] (`findTags` / `findTag`) plus the five `…_count_all` aliases after `...TagFields`
     * while [includeContent] is on. They stay out of the shared fragment: scenes use it for their tags.
     */
    fun withCountsAll(document: String, includeContent: Boolean): String =
        if (!includeContent) document else document.replace(
            "...TagFields",
            "...TagFields\n      scene_count_all: scene_count(depth: -1)\n      image_count_all: image_count(depth: -1)\n" +
                "      gallery_count_all: gallery_count(depth: -1)\n      scene_marker_count_all: scene_marker_count(depth: -1)\n" +
                "      performer_count_all: performer_count(depth: -1)",
        )

    /** First parent's name and the number of further parents; `null` for a top-level tag. */
    fun partOfParts(parents: List<IdName>?): Pair<String, Int>? {
        val first = parents?.firstOrNull() ?: return null
        return (first.name ?: "") to (parents.size - 1)
    }
}

/** iOS: `Tag.partOfText` — "Part of X" / "Part of X +2" for a sub-tag, null for a top-level tag. */
val Tag.partOfText: String? get() = SubTags.partOfParts(parents)?.let { (name, more) ->
    if (more == 0) tr(R.string.arg_part_of, name) else tr(R.string.arg_part_of_and_more, name, more)
}

/** The two sub-tag switches (iOS `TagHierarchy` `@AppStorage`s); state-backed so cards and lists follow a change. */
object TagHierarchyStore {
    private var includeState by mutableStateOf<Boolean?>(null)
    var includeSubTagContent: Boolean
        get() = includeState ?: Prefs.bool(SubTags.INCLUDE_KEY).also { includeState = it }
        set(value) { includeState = value; Prefs.setBool(SubTags.INCLUDE_KEY, value) }

    private var hideState by mutableStateOf<Boolean?>(null)
    /** "Hide sub-tags": the Tags list shows top-level tags only. */
    var hideSubTags: Boolean
        get() = hideState ?: Prefs.bool(SubTags.HIDE_KEY).also { hideState = it }
        set(value) {
            hideState = value
            Prefs.setBool(SubTags.HIDE_KEY, value)
            // A hidden sub-tag's content would be out of reach otherwise.
            includeSubTagContent = SubTags.includeAfterHideChange(value, includeSubTagContent)
        }

    /** False while the setting is unreadable (JVM tests run without [Prefs]). */
    val includesContent: Boolean get() = runCatching { includeSubTagContent }.getOrDefault(false)

    /** `depth` of a `tags` criterion that scopes a list to one tag; 0 while unreadable. */
    val contentDepth: Int get() = SubTags.depth(includesContent)
}
