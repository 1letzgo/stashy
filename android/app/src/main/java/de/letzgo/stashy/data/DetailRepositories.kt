package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Entity fetches and mutations for the detail screens (iOS: the `fetchDetail*`, `toggle*Favorite`,
 * `update*Details`, `delete*` and image O-counter / rating functions of `StashDBViewModel`).
 * Mutation texts are the iOS `GraphQLQueries` strings.
 */
object DetailRepository {

    /** `{"value": [id], "modifier": "INCLUDES"}` — the criterion iOS builds for every scope. */
    fun includes(id: String): JsonObject = buildJsonObject {
        put("value", JsonArray(listOf(JsonPrimitive(id))))
        put("modifier", JsonPrimitive("INCLUDES"))
    }

    fun scope(key: String, id: String): JsonObject = buildJsonObject { put(key, includes(id)) }

    /**
     * Older Stash servers reject some iOS scopes (`tag_filter.performers`, `studio_filter.groups` …).
     * Then the same criterion is retried through the entity's `scenes_filter`, which every
     * supported server knows. Only Performers / Studios / Tags / Groups tabs retry, and never the
     * child-studio scope (`parents` is a real `StudioFilterType` key). The scope stays the last
     * layer of the retried query, so the fallback can't widen the list either.
     */
    fun sceneFilterFallback(query: CatalogQuery): CatalogQuery? {
        val scope = query.scope?.takeIf { it.isNotEmpty() } ?: return null
        if (query.mode !in SCENE_FALLBACK_MODES || scope.containsKey("parents")) return null
        return query.copy(scope = buildJsonObject { put("scenes_filter", scope) })
    }

    private val SCENE_FALLBACK_MODES = setOf(FilterMode.Performers, FilterMode.Studios, FilterMode.Tags, FilterMode.Groups)

    /** One page of a detail tab's scoped catalog query, with the [sceneFilterFallback] retry. */
    suspend fun <T> findScoped(query: CatalogQuery, page: Int, perPage: Int): Page<T> = try {
        CatalogRepository.find(query, page, perPage)
    } catch (e: GraphQLError) {
        val fallback = sceneFilterFallback(query) ?: throw e
        CatalogRepository.find(fallback, page, perPage)
    }

    // MARK: Entities

    suspend fun performer(id: String): Performer? =
        findPage("findPerformers", "findPerformers", "performers", Performer.serializer(), FindFilter(1, 1), extra = mapOf("ids" to listOf(id))).items.firstOrNull()

    suspend fun studio(id: String): Studio? {
        val data = GraphQL.named("findStudio", vars("id" to id))
        return data["findStudio"]?.takeIf { it !is JsonNull }?.let { GraphQL.decode(Studio.serializer(), it) }
    }

    suspend fun tag(id: String): Tag? {
        val data = GraphQL.named("findTag", vars("id" to id))
        return data["findTag"]?.takeIf { it !is JsonNull }?.let { GraphQL.decode(Tag.serializer(), it) }
    }

    /** `findGroups(ids:)` — `findGroup.graphql` asks for `gallery_count`, which v0.31 servers lack. */
    suspend fun group(id: String): StashGroup? =
        findPage("findGroups", "findGroups", "groups", StashGroup.serializer(), FindFilter(1, 1), extra = mapOf("ids" to listOf(id))).items.firstOrNull()

    suspend fun gallery(id: String): Gallery? =
        findPage("findGalleries", "findGalleries", "galleries", Gallery.serializer(), FindFilter(1, 1), extra = mapOf("ids" to listOf(id))).items.firstOrNull()

    // MARK: Favorites

    private suspend fun mutate(query: String, variables: JsonObject, field: String): JsonObject? =
        GraphQL.data(query, variables)[field] as? JsonObject

    private suspend fun input(query: String, field: String, input: Map<String, Any?>): Boolean =
        runCatching { mutate(query, vars("input" to input), field) != null }.getOrDefault(false)

    suspend fun setPerformerFavorite(id: String, favorite: Boolean) =
        input("mutation PerformerUpdate(\$input: PerformerUpdateInput!) { performerUpdate(input: \$input) { id favorite } }", "performerUpdate", mapOf("id" to id, "favorite" to favorite))

    suspend fun setStudioFavorite(id: String, favorite: Boolean) =
        input("mutation StudioUpdate(\$input: StudioUpdateInput!) { studioUpdate(input: \$input) { id favorite } }", "studioUpdate", mapOf("id" to id, "favorite" to favorite))

    suspend fun setTagFavorite(id: String, favorite: Boolean) =
        input("mutation TagUpdate(\$input: TagUpdateInput!) { tagUpdate(input: \$input) { id favorite } }", "tagUpdate", mapOf("id" to id, "favorite" to favorite))

    // MARK: Edit sheets (iOS `update*Details`: empty optional fields are sent as null)

    suspend fun updatePerformer(id: String, edit: PerformerEdit): Boolean = input(
        "mutation PerformerUpdate(\$input: PerformerUpdateInput!) { performerUpdate(input: \$input) { id name disambiguation birthdate country gender ethnicity height_cm weight measurements fake_tits penis_length career_length tattoos piercings alias_list rating100 } }",
        "performerUpdate",
        mapOf(
            "id" to id, "name" to edit.name, "disambiguation" to edit.disambiguation, "birthdate" to edit.birthdate,
            "country" to edit.country, "gender" to edit.gender, "ethnicity" to edit.ethnicity, "height_cm" to edit.heightCm,
            "weight" to edit.weight, "measurements" to edit.measurements, "fake_tits" to edit.fakeTits,
            "penis_length" to edit.penisLength, "career_length" to edit.careerLength, "tattoos" to edit.tattoos,
            "piercings" to edit.piercings, "alias_list" to edit.aliasList, "rating100" to edit.rating100,
        ),
    )

    suspend fun updateStudio(id: String, name: String, url: String?, details: String?, rating100: Int?) = input(
        "mutation StudioUpdate(\$input: StudioUpdateInput!) { studioUpdate(input: \$input) { id name url details rating100 } }",
        "studioUpdate", mapOf("id" to id, "name" to name, "url" to url, "details" to details, "rating100" to rating100),
    )

    suspend fun updateTag(id: String, name: String, description: String?) = input(
        "mutation TagUpdate(\$input: TagUpdateInput!) { tagUpdate(input: \$input) { id name description } }",
        "tagUpdate", mapOf("id" to id, "name" to name, "description" to description),
    )

    suspend fun updateGroup(id: String, name: String, date: String?, synopsis: String?, rating100: Int?) = input(
        "mutation GroupUpdate(\$input: GroupUpdateInput!) { groupUpdate(input: \$input) { id name date synopsis rating100 } }",
        "groupUpdate", mapOf("id" to id, "name" to name, "date" to date, "synopsis" to synopsis, "rating100" to rating100),
    )

    suspend fun updateGallery(id: String, title: String, date: String?, details: String?) = input(
        "mutation GalleryUpdate(\$input: GalleryUpdateInput!) { galleryUpdate(input: \$input) { id title date details } }",
        "galleryUpdate", mapOf("id" to id, "title" to title, "date" to date, "details" to details),
    )

    /** `galleryUpdate(performer_ids:)` — the opened gallery's Performers card. Throws on failure (picker shows the error). */
    suspend fun updateGalleryPerformers(id: String, performerIds: List<String>) {
        GraphQL.data(
            "mutation GalleryUpdate(\$input: GalleryUpdateInput!) { galleryUpdate(input: \$input) { id } }",
            vars("input" to mapOf("id" to id, "performer_ids" to performerIds)),
        )
    }

    /** `galleryUpdate(studio_id:)` — null clears the studio. Throws on failure. */
    suspend fun updateGalleryStudio(id: String, studioId: String?) {
        GraphQL.data(
            "mutation GalleryUpdate(\$input: GalleryUpdateInput!) { galleryUpdate(input: \$input) { id } }",
            vars("input" to mapOf("id" to id, "studio_id" to studioId)),
        )
    }

    // MARK: Create (iOS `create*` — used by the scene detail pickers)

    suspend fun createPerformer(name: String): Performer? = create(
        "mutation PerformerCreate(\$input: PerformerCreateInput!) { performerCreate(input: \$input) { id name scene_count gallery_count updated_at } }",
        "performerCreate", name, Performer.serializer(),
    )

    suspend fun createStudio(name: String): Studio? = create(
        "mutation StudioCreate(\$input: StudioCreateInput!) { studioCreate(input: \$input) { id name scene_count updated_at } }",
        "studioCreate", name, Studio.serializer(),
    )

    suspend fun createTag(name: String): Tag? = create(
        "mutation TagCreate(\$input: TagCreateInput!) { tagCreate(input: \$input) { id name scene_count } }",
        "tagCreate", name, Tag.serializer(),
    )

    suspend fun createGroup(name: String): StashGroup? = create(
        "mutation GroupCreate(\$input: GroupCreateInput!) { groupCreate(input: \$input) { id name updated_at front_image_path scene_count } }",
        "groupCreate", name, StashGroup.serializer(),
    )

    private suspend fun <T> create(query: String, field: String, name: String, ser: kotlinx.serialization.KSerializer<T>): T? =
        runCatching { mutate(query, vars("input" to mapOf("name" to name)), field)?.let { GraphQL.decode(ser, it) } }.getOrNull()

    // MARK: Delete (iOS `deleteEntity` — throws with the server message)

    suspend fun deletePerformer(id: String) = destroy("mutation PerformerDestroy(\$id: ID!) { performerDestroy(input: { id: \$id }) }", "performerDestroy", vars("id" to id))
    suspend fun deleteStudio(id: String) = destroy("mutation StudioDestroy(\$id: ID!) { studioDestroy(input: { id: \$id }) }", "studioDestroy", vars("id" to id))
    suspend fun deleteTag(id: String) = destroy("mutation TagDestroy(\$id: ID!) { tagDestroy(input: { id: \$id }) }", "tagDestroy", vars("id" to id))
    suspend fun deleteGroup(id: String) = destroy("mutation GroupDestroy(\$id: ID!) { groupDestroy(input: { id: \$id }) }", "groupDestroy", vars("id" to id))
    suspend fun deleteGallery(id: String) = destroy(
        "mutation GalleryDestroy(\$ids: [ID!]!, \$deleteFile: Boolean, \$deleteGenerated: Boolean) { galleryDestroy(input: { ids: \$ids, delete_file: \$deleteFile, delete_generated: \$deleteGenerated }) }",
        "galleryDestroy", vars("ids" to listOf(id), "deleteFile" to false, "deleteGenerated" to true),
    )

    private suspend fun destroy(query: String, field: String, variables: JsonObject) {
        val data = GraphQL.data(query, variables)
        val ok = (data[field] as? JsonPrimitive)?.content == "true"
        if (!ok) throw GraphQLError.Query("Delete failed")
    }

    // MARK: Images (fullscreen viewer)

    /** Returns the new count, or null on failure (iOS `incrementImageOCounter` / `mutateImageOCounter`). */
    suspend fun imageOCounter(id: String, mutation: OCounterMutation): Int? = runCatching {
        val field = when (mutation) {
            OCounterMutation.Increment -> "imageIncrementO"
            OCounterMutation.Decrement -> "imageDecrementO"
            OCounterMutation.Reset -> "imageResetO"
        }
        GraphQL.data("mutation OCounterChange(\$id: ID!) { $field(id: \$id) }", vars("id" to id))[field]?.jsonPrimitive?.intOrNull
    }.getOrNull()

    suspend fun setImageRating(id: String, rating100: Int?): Boolean = input(
        "mutation ImageUpdate(\$input: ImageUpdateInput!) { imageUpdate(input: \$input) { id rating100 } }",
        "imageUpdate", mapOf("id" to id, "rating100" to rating100),
    )

    /** iOS `deleteImage`: destroy the record, then delete its files (best effort). */
    suspend fun deleteImage(id: String): Boolean {
        val fileIds = runCatching {
            val data = GraphQL.data("query FindImageFiles(\$id: ID!) { findImage(id: \$id) { visual_files { ... on BaseFile { id } } } }", vars("id" to id))
            (data["findImage"].obj?.get("visual_files").arr ?: JsonArray(emptyList())).mapNotNull { it.obj?.get("id").stringOrNull }
        }.getOrDefault(emptyList())
        val destroyed = runCatching {
            GraphQL.data("mutation ImageDestroy(\$id: ID!) { imageDestroy(input: { id: \$id }) }", vars("id" to id))["imageDestroy"] != null
        }.getOrDefault(false)
        if (!destroyed) return false
        if (fileIds.isNotEmpty()) runCatching {
            GraphQL.data("mutation DeleteFiles(\$ids: [ID!]!) { deleteFiles(ids: \$ids) }", vars("ids" to fileIds))
        }
        return true
    }

    /** Outcome of [setPerformerImage]: the new `image_path` (null when Stash returned none). */
    data class PerformerImageUpdate(val imagePath: String?)

    /**
     * iOS `setPerformerImage` (`performerUpdate(image:)` with a URL Stash downloads itself).
     * Returns null on failure, else the new `image_path` (carries the new `?t=`) — refetched
     * when the mutation response lacks it.
     */
    suspend fun setPerformerImage(performerId: String, imageURL: String): PerformerImageUpdate? {
        val result = runCatching {
            mutate(
                "mutation PerformerUpdate(\$input: PerformerUpdateInput!) { performerUpdate(input: \$input) { id image_path } }",
                vars("input" to mapOf("id" to performerId, "image" to imageURL)), "performerUpdate",
            )
        }.getOrNull() ?: return null
        val path = (result["image_path"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content?.takeIf { it.isNotBlank() }
            ?: runCatching { performer(performerId)?.imagePath }.getOrNull()
        return PerformerImageUpdate(path)
    }

    /** iOS `AITagSuggestionManager.write(tags:to: .image)` — replaces the image's tag ids. */
    suspend fun setImageTags(imageId: String, tagIds: List<String>): Boolean = input(
        "mutation ImageUpdate(\$input: ImageUpdateInput!) { imageUpdate(input: \$input) { id tags { id name } } }",
        "imageUpdate", mapOf("id" to imageId, "tag_ids" to tagIds),
    )
}

/** Values of `EditPerformerSheet` (empty strings already mapped to null). */
data class PerformerEdit(
    val name: String,
    val disambiguation: String?,
    val birthdate: String?,
    val country: String?,
    val gender: String?,
    val ethnicity: String?,
    val heightCm: Int?,
    val weight: Int?,
    val measurements: String?,
    val fakeTits: String?,
    val penisLength: Double?,
    val careerLength: String?,
    val tattoos: String?,
    val piercings: String?,
    val aliasList: List<String>?,
    val rating100: Int?,
)
