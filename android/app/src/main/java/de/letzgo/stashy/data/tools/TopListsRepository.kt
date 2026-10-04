package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.FindFilter
import de.letzgo.stashy.data.Page
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.data.findPage

/**
 * iOS: the `fetchScenes/Performers/Studios/Tags(sortedBy:page:)` helpers of `TopListsViewModel`,
 * which call the shared repositories with no search and no saved filter.
 * Uses the shared `findScenes` / `findPerformers` / `findStudios` / `findTags` documents.
 */
object TopListsRepository {
    private fun filter(metric: TopListsMetric, page: Int) =
        FindFilter(page = page, perPage = TOP_LIST_PAGE_SIZE, sort = metric.sortField, direction = metric.direction)

    suspend fun scenes(metric: TopListsSceneMetric, page: Int = 1): Page<Scene> =
        findPage("findScenes", "findScenes", "scenes", Scene.serializer(), filter(metric, page))

    suspend fun performers(metric: TopListsPerformerMetric, page: Int = 1): Page<Performer> =
        findPage("findPerformers", "findPerformers", "performers", Performer.serializer(), filter(metric, page))

    suspend fun studios(metric: TopListsStudioMetric, page: Int = 1): Page<Studio> =
        findPage("findStudios", "findStudios", "studios", Studio.serializer(), filter(metric, page))

    suspend fun tags(metric: TopListsTagMetric, page: Int = 1): Page<Tag> =
        findPage("findTags", "findTags", "tags", Tag.serializer(), filter(metric, page))
}
