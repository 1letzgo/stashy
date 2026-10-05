package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.FindFilter
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.vars
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.findPage
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlin.math.min

/**
 * Newest-first page walks for bulk downloads (iOS: `fetchScenesForDownload`,
 * `fetchGalleryImagesForDownload`, `fetchTagImagesForDownload`, `fetchImagesForDownload`).
 * Errors end the walk with what was collected so far, like iOS.
 */
object DownloadsFetch {
    /** Safety valve for very large sets (iOS: `page > 50`). */
    private const val MAX_PAGES = 50

    suspend fun scenes(sceneFilter: JsonObject, limit: Int?): List<Scene> {
        val collected = mutableListOf<Scene>()
        var total = 0
        var page = 1
        val perPage = min(limit ?: 100, 100)
        while (true) {
            val result = try {
                findPage("findScenes", "findScenes", "scenes", Scene.serializer(), FindFilter(page, perPage, "date", "DESC"), "scene_filter", sceneFilter)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                break
            }
            total = result.count
            collected += result.items
            if (limit != null && collected.size >= limit) return collected.take(limit)
            if (result.items.size < perPage || collected.size >= total) break
            page++
            if (page > MAX_PAGES) break
        }
        return collected
    }

    /** Images matching [imageFilter] (null/empty = all), newest first; returns (images, server total). */
    suspend fun images(imageFilter: JsonObject?, limit: Int?): Pair<List<StashImage>, Int> {
        val collected = mutableListOf<StashImage>()
        var total = 0
        var page = 1
        val perPage = min(limit ?: 200, 200)
        val filter = imageFilter?.takeIf { it.isNotEmpty() }
        while (true) {
            val result = try {
                findPage("findImages", "findImages", "images", StashImage.serializer(), FindFilter(page, perPage, "date", "DESC"), "image_filter", filter)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                break
            }
            total = result.count
            collected += result.items
            if (limit != null && collected.size >= limit) return collected.take(limit) to total
            if (result.items.size < perPage || collected.size >= total) break
            page++
            if (page > MAX_PAGES) break
        }
        return collected to total
    }

    suspend fun galleryImages(galleryId: String, limit: Int?) =
        images(criterion("galleries", galleryId, depth = false), limit)

    suspend fun tagImages(tagId: String, limit: Int?) =
        images(criterion("tags", tagId, depth = true), limit)

    suspend fun filterImages(imageFilter: JsonObject, limit: Int?) = images(imageFilter, limit)

    private const val IMAGE_TITLES_QUERY =
        "query DownloadImageTitles(\$ids: [ID!], \$filter: FindFilterType) { findImages(ids: \$ids, filter: \$filter) " +
            "{ images { id title created_at visual_files { ... on BaseFile { __typename path basename } } } } }"

    /**
     * Title backfill for older image downloads: id → (created_at, title or file name) for the
     * given image ids on the active server. Null when the lookup failed (offline, old server).
     */
    suspend fun imageDownloadTitles(ids: List<String>): Map<String, Pair<String?, String>>? {
        val result = mutableMapOf<String, Pair<String?, String>>()
        for (chunk in ids.chunked(200)) {
            val images = try {
                val data = GraphQL.data(IMAGE_TITLES_QUERY, vars("ids" to chunk, "filter" to mapOf("per_page" to -1)))
                GraphQL.decode(ListSerializer(StashImage.serializer()), data["findImages"].obj?.get("images") ?: JsonArray(emptyList()))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                return null
            }
            images.forEach { image -> image.downloadTitle?.let { result[image.id] = image.createdAt to it } }
        }
        return result
    }

    private fun criterion(key: String, id: String, depth: Boolean) = buildJsonObject {
        put(key, buildJsonObject {
            put("value", JsonArray(listOf(JsonPrimitive(id))))
            put("modifier", JsonPrimitive("INCLUDES"))
            if (depth) put("depth", JsonPrimitive(0))
        })
    }
}
