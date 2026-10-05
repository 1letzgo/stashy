package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull

/**
 * Network side of the Feeds tab (iOS: the Reels fetches and mutations of `StashDBViewModel`).
 * Queries come from the shared `.graphql` documents; the small mutations iOS keeps inline in
 * `GraphQLQueries.swift` are inlined here the same way.
 */
object FeedsRepository {
    suspend fun scenes(variables: JsonObject): Page<Scene> = page("findScenes", "findScenes", "scenes", Scene.serializer(), variables)
    suspend fun markers(variables: JsonObject): Page<SceneMarker> = page("findSceneMarkers", "findSceneMarkers", "scene_markers", SceneMarker.serializer(), variables)
    suspend fun images(variables: JsonObject): Page<StashImage> = page("findImages", "findImages", "images", StashImage.serializer(), variables)

    private suspend fun <T> page(doc: String, field: String, list: String, item: kotlinx.serialization.KSerializer<T>, variables: JsonObject): Page<T> {
        val data = GraphQL.named(doc, variables)
        val obj = data[field].obj ?: throw GraphQLError.Query("Missing $field")
        val count = obj["count"].stringOrNull?.toIntOrNull() ?: 0
        return Page(count, GraphQL.decode(ListSerializer(item), obj[list] ?: JsonArray(emptyList())))
    }

    private const val SAVED_FILTERS = """
        query FindSavedFilters(${'$'}mode: FilterMode) {
          findSavedFilters(mode: ${'$'}mode) { id name mode find_filter { q page per_page sort direction } object_filter ui_options }
        }"""

    /** iOS: `fetchSavedFilters` — all modes; callers filter by `mode`. */
    suspend fun savedFilters(): List<SavedFilter> {
        val data = GraphQL.data(SAVED_FILTERS.trimIndent())
        return GraphQL.decode(ListSerializer(SavedFilter.serializer()), data["findSavedFilters"] ?: JsonArray(emptyList()))
    }

    // MARK: - Mutations (iOS `GraphQLQueries` / `StashDBViewModel`)

    /** iOS: `sceneUpdateRatingMutation`. */
    suspend fun updateSceneRating(id: String, rating100: Int?): Boolean = runCatching {
        GraphQL.data(
            "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id rating100 } }",
            vars("input" to mapOf("id" to id, "rating100" to rating100)),
        )["sceneUpdate"] is JsonObject
    }.getOrDefault(false)

    /** iOS: `imageUpdateRatingMutation`. */
    suspend fun updateImageRating(id: String, rating100: Int?): Boolean = runCatching {
        GraphQL.data(
            "mutation ImageUpdate(\$input: ImageUpdateInput!) { imageUpdate(input: \$input) { id rating100 } }",
            vars("input" to mapOf("id" to id, "rating100" to rating100)),
        )["imageUpdate"] is JsonObject
    }.getOrDefault(false)

    /** iOS: `OCounterMutation`. */
    enum class OMutation { Increment, Decrement, Reset }

    /** iOS: `mutateSceneOCounter` / `mutateImageOCounter` — returns the new count or null. */
    suspend fun mutateOCounter(id: String, isImage: Boolean, mutation: OMutation): Int? {
        val prefix = if (isImage) "image" else "scene"
        val field = prefix + when (mutation) { OMutation.Increment -> "IncrementO"; OMutation.Decrement -> "DecrementO"; OMutation.Reset -> "ResetO" }
        return runCatching {
            (GraphQL.data("mutation OCounterChange(\$id: ID!) { $field(id: \$id) }", vars("id" to id))[field] as? JsonPrimitive)?.intOrNull
        }.getOrNull()
    }

    /** iOS: `addScenePlay` (`sceneAddPlay`, `SceneAddPlay.graphql`). */
    suspend fun addScenePlay(id: String): Int? = if (!TabManager.tracksPlaybackActivity) null else runCatching {
        val data = GraphQL.named("sceneAddPlay", buildJsonObject { put("id", JsonPrimitive(id)); put("times", JsonArray(emptyList())) })
        (data["sceneAddPlay"].obj?.get("count") as? JsonPrimitive)?.intOrNull
    }.getOrNull()

    /** iOS: `addSceneMarkerPlay` (`sceneMarkerIncrementPlayMutation`). Servers without marker play counts answer with an error → null. */
    suspend fun addSceneMarkerPlay(id: String): Int? = runCatching {
        val data = GraphQL.data("mutation SceneMarkerIncrementPlay(\$id: ID!) { sceneMarkerUpdate(input: { id: \$id }) { id play_count } }", vars("id" to id))
        (data["sceneMarkerUpdate"].obj?.get("play_count") as? JsonPrimitive)?.intOrNull
    }.getOrNull()

    /** iOS: `deleteSceneWithFiles` — destroys the scene, then its files. */
    suspend fun deleteSceneWithFiles(scene: Scene): Boolean = runCatching {
        GraphQL.data("mutation SceneDestroy(\$id: ID!) { sceneDestroy(input: { id: \$id }) }", vars("id" to scene.id))
        val fileIds = scene.files?.mapNotNull { it.id }.orEmpty()
        if (fileIds.isNotEmpty()) runCatching {
            GraphQL.data("mutation DeleteFiles(\$ids: [ID!]!) { deleteFiles(ids: \$ids) }", vars("ids" to fileIds))
        }
        true
    }.getOrDefault(false)

    /** iOS: `deleteImage(imageId:)` (`imageDestroy`). */
    suspend fun deleteImage(id: String): Boolean = runCatching {
        GraphQL.data("mutation ImageDestroy(\$id: ID!) { imageDestroy(input: { id: \$id }) }", vars("id" to id))
        true
    }.getOrDefault(false)
}
