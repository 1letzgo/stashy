package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: the sub-studio helpers of `StudioCountsStore` (`hidesSubStudios`, `contentDepth`). Pure
 * logic only — the two settings live in [StudioCountsStore]:
 * - "Hide sub-studios" (`studios_hide_sub_studios`): the Studios list shows top-level studios only.
 * - "Include sub-studio content" (`studio_counts_include_sub_studios`, older than the switch,
 *   hence its name): a studio's page shows what its sub-studios hold, and the cards count it.
 */
object SubStudios {
    const val HIDE_KEY = "studios_hide_sub_studios"
    const val INCLUDE_KEY = "studio_counts_include_sub_studios"

    /** `depth` of a `studios` criterion that scopes a list to one studio. */
    fun depth(includeContent: Boolean): Int = if (includeContent) -1 else 0

    /**
     * The extra `studio_filter` criterion of the Studios list: `parents IS_NULL` (top-level only)
     * while "Hide sub-studios" is on. A search still finds every studio, and a `parents`
     * criterion of the user's own wins. `null` = add nothing.
     */
    fun hideCriterion(hide: Boolean, search: String, userCriteria: JsonObject?): JsonObject? {
        if (!hide || search.isNotBlank() || userCriteria?.containsKey("parents") == true) return null
        return buildJsonObject { put("parents", buildJsonObject { put("modifier", JsonPrimitive("IS_NULL")) }) }
    }

    /** [criteria] with [hideCriterion] layered on, or [criteria] itself when nothing is added. */
    fun withHide(criteria: JsonObject?, hide: Boolean, search: String): JsonObject? {
        val extra = hideCriterion(hide, search, criteria) ?: return criteria
        return JsonObject((criteria ?: JsonObject(emptyMap())) + extra)
    }

    /** Switching "Hide sub-studios" on also switches "Include sub-studio content" on (it can be switched off again). */
    fun includeAfterHideChange(hideNow: Boolean, includeBefore: Boolean): Boolean = if (hideNow) true else includeBefore

    /**
     * What a studio's page sends for [mode]: the studio as a `studios` criterion with the depth
     * of the content switch. Stash's `TagFilterType` has no `studios`, so a studio's tags are
     * those of its scenes. Sub-studios (direct children only) use `parents` instead.
     */
    fun studioScope(mode: FilterMode, studioId: String, includeContent: Boolean): JsonObject {
        val studios = buildJsonObject {
            put("studios", buildJsonObject {
                put("value", JsonArray(listOf(JsonPrimitive(studioId))))
                put("modifier", JsonPrimitive("INCLUDES"))
                put("depth", JsonPrimitive(depth(includeContent)))
            })
        }
        return if (mode == FilterMode.Tags) buildJsonObject { put("scenes_filter", studios) } else studios
    }

    /**
     * Stash sorts `scenes_count` by a studio's own scenes only. With "Include sub-studio content"
     * on, the list is fetched whole and sorted by [sortedBySceneCountAll] instead.
     */
    fun sortsBySceneCountAll(sortField: String, includeContent: Boolean): Boolean = sortField == "scenes_count" && includeContent

    /** By scenes including sub-studios (own count as fallback), the name as tie-breaker. */
    fun sortedBySceneCountAll(studios: List<Studio>, ascending: Boolean): List<Studio> {
        val byCount = compareBy<Studio> { it.sceneCountAll ?: it.sceneCount ?: 0 }
        return studios.sortedWith((if (ascending) byCount else byCount.reversed()).thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** `findStudios` plus each studio's `scene_count_all` (`scene_count(depth: -1)`, also on Stash 0.31). */
    fun withSceneCountAll(document: String): String =
        document.replace("...StudioFields", "...StudioFields\n      scene_count_all: scene_count(depth: -1)")
}
