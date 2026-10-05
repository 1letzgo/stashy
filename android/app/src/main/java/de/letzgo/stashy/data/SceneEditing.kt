package de.letzgo.stashy.data

import kotlinx.coroutines.delay
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Inline documents iOS keeps in `GraphQLQueries.swift` (the shared `.graphql` files cover the
 * rest: `sceneSaveActivity`, `sceneAddPlay`, `sceneIncrementO`, `metadataIdentify`, …).
 */
object SceneQueries {
    const val sceneUpdateRating = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id rating100 } }"
    const val sceneUpdateOrganized = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id organized } }"
    const val sceneUpdatePerformers = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id performers { id name scene_count gallery_count o_counter updated_at } } }"
    const val sceneUpdateStudio = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id studio { id name updated_at } } }"
    const val sceneUpdateTags = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id tags { id name } } }"
    const val sceneUpdateGroups = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id groups { group { id name updated_at front_image_path } scene_index } } }"
    const val sceneUpdateGalleries = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id galleries { id title date image_count updated_at cover { id paths { thumbnail } } } } }"
    const val sceneUpdateTitleDetails = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id title details } }"
    const val sceneUpdateCoverImage = "mutation SceneUpdate(\$input: SceneUpdateInput!) { sceneUpdate(input: \$input) { id } }"
    const val sceneMarkerCreate = "mutation SceneMarkerCreate(\$input: SceneMarkerCreateInput!) { sceneMarkerCreate(input: \$input) { id title seconds screenshot } }"
    const val sceneMarkerUpdate = "mutation SceneMarkerUpdate(\$input: SceneMarkerUpdateInput!) { sceneMarkerUpdate(input: \$input) { id title seconds end_seconds } }"
    const val sceneMarkerDestroy = "mutation SceneMarkerDestroy(\$id: ID!) { sceneMarkerDestroy(id: \$id) }"
    const val deleteFiles = "mutation DeleteFiles(\$ids: [ID!]!) { deleteFiles(ids: \$ids) }"
    const val findGroupsForScene = "query FindGroups(\$filter: FindFilterType) { findGroups(filter: \$filter) { groups { id name updated_at front_image_path scene_count } } }"
    const val findGalleriesForScene = "query FindGalleries(\$filter: FindFilterType, \$gallery_filter: GalleryFilterType) { findGalleries(filter: \$filter, gallery_filter: \$gallery_filter) { galleries { id title date image_count updated_at cover { id paths { thumbnail } } } } }"
    const val performerCreate = "mutation PerformerCreate(\$input: PerformerCreateInput!) { performerCreate(input: \$input) { id name scene_count gallery_count updated_at } }"
    const val studioCreate = "mutation StudioCreate(\$input: StudioCreateInput!) { studioCreate(input: \$input) { id name scene_count updated_at } }"
    const val groupCreate = "mutation GroupCreate(\$input: GroupCreateInput!) { groupCreate(input: \$input) { id name updated_at front_image_path scene_count } }"
    const val tagCreate = "mutation TagCreate(\$input: TagCreateInput!) { tagCreate(input: \$input) { id name scene_count } }"
    const val tagUpdateImage = "mutation TagUpdate(\$input: TagUpdateInput!) { tagUpdate(input: \$input) { id image_path } }"
    fun oCounterChange(field: String) = "mutation OCounterChange(\$id: ID!) { $field(id: \$id) }"
}

/** iOS: `StashDBViewModel.OCounterMutation`. */
enum class OCounterMutation { Increment, Decrement, Reset }

/** iOS: `StashJob` (`findJob`). */
data class StashJob(val id: String, val status: String, val description: String?, val error: String?)

/**
 * Scene detail reads and writes (iOS: the scene-related functions of `StashDBViewModel` —
 * `fetchSceneDetails`, `updateSceneResumeTime`, `addScenePlay`, `mutateSceneOCounter`,
 * `updateSceneRating`, the edit sheets' `updateScene*`, `createSceneMarker`,
 * `setSceneCoverImage`, `deleteSceneWithFiles`, `triggerIdentify`, `waitForJob` …).
 * All functions throw [GraphQLError] on failure; callers map that to a toast like iOS.
 */
object SceneEditing {
    private fun input(vararg pairs: Pair<String, Any?>) = vars("input" to pairs.toMap())

    /** iOS: `updateSceneResumeTime(sceneId:resumeTime:playDuration:)` — `sceneSaveActivity`. */
    suspend fun saveActivity(sceneId: String, resumeTime: Double?, playDuration: Double) {
        if (!TabManager.tracksActivity(sceneId)) return
        val v = buildJsonObject {
            put("id", JsonPrimitive(sceneId))
            resumeTime?.let { put("resume_time", JsonPrimitive(round2(it))) }
            put("playDuration", JsonPrimitive(round2(maxOf(0.0, playDuration))))
        }
        GraphQL.named("sceneSaveActivity", v)
    }

    private fun round2(v: Double) = Math.round(v * 100) / 100.0

    /** iOS: `addScenePlay` — returns the new count. */
    suspend fun addPlay(sceneId: String): Int? {
        if (!TabManager.tracksActivity(sceneId)) return null
        val data = GraphQL.named("sceneAddPlay", vars("id" to sceneId, "times" to emptyList<String>()))
        return data["sceneAddPlay"].obj?.get("count")?.jsonPrimitive?.content?.toDoubleOrNull()?.toInt()
    }

    /** iOS: `mutateSceneOCounter` — returns the new count. */
    suspend fun mutateOCounter(sceneId: String, mutation: OCounterMutation): Int? = when (mutation) {
        OCounterMutation.Increment -> try {
            GraphQL.named("sceneIncrementO", vars("id" to sceneId))["sceneIncrementO"]?.jsonPrimitive?.intOrNull
        } catch (e: GraphQLError) {
            if (e is GraphQLError.Network || e is GraphQLError.Unauthorized) throw e
            // Stash ≥ 0.31 dropped `sceneIncrementO`; `sceneAddO` (no times = now) is its successor.
            historyCount("sceneAddO", sceneId)
        }
        OCounterMutation.Decrement -> try {
            GraphQL.data(SceneQueries.oCounterChange("sceneDecrementO"), vars("id" to sceneId))["sceneDecrementO"]?.jsonPrimitive?.intOrNull
        } catch (e: GraphQLError) {
            if (e is GraphQLError.Network || e is GraphQLError.Unauthorized) throw e
            // Successor of `sceneDecrementO`: removes the most recent O entry.
            historyCount("sceneDeleteO", sceneId)
        }
        OCounterMutation.Reset -> GraphQL.data(SceneQueries.oCounterChange("sceneResetO"), vars("id" to sceneId))["sceneResetO"]?.jsonPrimitive?.intOrNull
    }

    private suspend fun historyCount(field: String, sceneId: String): Int? =
        GraphQL.data("mutation OHistory(\$id: ID!) { $field(id: \$id) { count } }", vars("id" to sceneId))[field].obj?.get("count")?.jsonPrimitive?.intOrNull

    suspend fun updateRating(sceneId: String, rating100: Int?) {
        GraphQL.data(SceneQueries.sceneUpdateRating, input("id" to sceneId, "rating100" to rating100))
    }

    suspend fun updateOrganized(sceneId: String, organized: Boolean) {
        GraphQL.data(SceneQueries.sceneUpdateOrganized, input("id" to sceneId, "organized" to organized))
    }

    suspend fun updateTitleAndDetails(sceneId: String, title: String?, details: String?) {
        GraphQL.data(SceneQueries.sceneUpdateTitleDetails, input("id" to sceneId, "title" to title, "details" to details))
    }

    suspend fun updatePerformers(sceneId: String, ids: List<String>) {
        GraphQL.data(SceneQueries.sceneUpdatePerformers, input("id" to sceneId, "performer_ids" to ids))
    }

    suspend fun updateStudio(sceneId: String, studioId: String?) {
        GraphQL.data(SceneQueries.sceneUpdateStudio, input("id" to sceneId, "studio_id" to studioId))
    }

    suspend fun updateTags(sceneId: String, ids: List<String>) {
        GraphQL.data(SceneQueries.sceneUpdateTags, input("id" to sceneId, "tag_ids" to ids))
    }

    suspend fun updateGroups(sceneId: String, ids: List<String>) {
        GraphQL.data(SceneQueries.sceneUpdateGroups, input("id" to sceneId, "groups" to ids.map { mapOf("group_id" to it) }))
    }

    suspend fun updateGalleries(sceneId: String, ids: List<String>) {
        GraphQL.data(SceneQueries.sceneUpdateGalleries, input("id" to sceneId, "gallery_ids" to ids))
    }

    /** iOS: `setSceneCoverImage` — `image` is a `data:image/jpeg;base64,…` URL. */
    suspend fun setCoverImage(sceneId: String, image: String) {
        GraphQL.data(SceneQueries.sceneUpdateCoverImage, input("id" to sceneId, "cover_image" to image))
    }

    /** iOS: `setTagImage` (Use frame as tag image). */
    suspend fun setTagImage(tagId: String, image: String) {
        GraphQL.data(SceneQueries.tagUpdateImage, input("id" to tagId, "image" to image))
    }

    /** iOS: `createSceneMarker` — returns the created marker. */
    suspend fun createMarker(sceneId: String, title: String, seconds: Double, endSeconds: Double?, primaryTagId: String): SceneMarker {
        val fields = mutableMapOf<String, Any?>("scene_id" to sceneId, "title" to title, "seconds" to seconds, "primary_tag_id" to primaryTagId)
        if (endSeconds != null) fields["end_seconds"] = endSeconds
        val data = GraphQL.data(SceneQueries.sceneMarkerCreate, vars("input" to fields))
        return GraphQL.decode(SceneMarker.serializer(), data["sceneMarkerCreate"] ?: throw GraphQLError.Query("Marker not created"))
    }

    suspend fun updateMarker(markerId: String, title: String?, seconds: Double?, endSeconds: Double?, primaryTagId: String?) {
        val fields = mutableMapOf<String, Any?>("id" to markerId)
        title?.let { fields["title"] = it }
        seconds?.let { fields["seconds"] = it }
        fields["end_seconds"] = endSeconds
        primaryTagId?.let { fields["primary_tag_id"] = it }
        GraphQL.data(SceneQueries.sceneMarkerUpdate, vars("input" to fields))
    }

    suspend fun deleteMarker(markerId: String) {
        GraphQL.data(SceneQueries.sceneMarkerDestroy, vars("id" to markerId))
    }

    /** iOS: `deleteSceneWithFiles` — `sceneDestroy`, then `deleteFiles` for every file id. */
    suspend fun deleteSceneWithFiles(scene: Scene) {
        GraphQL.named("sceneDestroy", vars("input" to mapOf("id" to scene.id)))
        val fileIds = scene.files?.mapNotNull { it.id }.orEmpty()
        if (fileIds.isNotEmpty()) GraphQL.data(SceneQueries.deleteFiles, vars("ids" to fileIds))
    }

    /** iOS: `triggerGenerateReturningJobId` — only the enabled flags plus the scope. */
    suspend fun generate(flags: Map<String, Boolean>, sceneIds: List<String>): String? {
        val input = flags.filterValues { it }.toMutableMap<String, Any?>()
        if (sceneIds.isNotEmpty()) input["sceneIDs"] = sceneIds
        return GraphQL.named("metadataGenerate", vars("input" to input))["metadataGenerate"].stringOrNull
    }

    suspend fun generateMarkerScreenshots(sceneId: String) = generate(mapOf("markerScreenshots" to true, "overwrite" to true), listOf(sceneId))
    suspend fun generateMarkerPreviews(sceneId: String) = generate(mapOf("markers" to true, "markerImagePreviews" to true), listOf(sceneId))

    suspend fun findJob(id: String): StashJob? {
        val job = GraphQL.named("findJob", vars("input" to mapOf("id" to id)))["findJob"].obj ?: return null
        return StashJob(job["id"].stringOrNull ?: id, job["status"].stringOrNull ?: "", job["description"].stringOrNull, job["error"].stringOrNull)
    }

    /** iOS: `waitForJob` — `(success, message)`; a job that vanished after it was seen counts as finished. */
    suspend fun waitForJob(id: String, timeoutSeconds: Int = 180, finishedText: String = "Identify finished"): Pair<Boolean, String> {
        val deadline = System.currentTimeMillis() + timeoutSeconds * 1000L
        var sawJob = false
        while (true) {
            val job = runCatching { findJob(id) }.getOrNull()
            if (job != null) {
                sawJob = true
                when (job.status.uppercase()) {
                    "FINISHED" -> return true to (job.description ?: finishedText)
                    "FAILED" -> return false to (job.error ?: "Identify failed")
                    "CANCELLED" -> return false to "Identify was cancelled"
                }
                if (System.currentTimeMillis() > deadline) return false to "Identify timed out"
            } else {
                if (sawJob) return true to finishedText
                if (System.currentTimeMillis() > deadline) return false to "Identify job not found"
            }
            delay(1000)
        }
    }

    /**
     * iOS: `triggerIdentify(sceneIDs:)` — server identify defaults (or all stash-boxes with the
     * iOS fallback options). Returns `(message, jobId)`; throws with the iOS message on failure.
     */
    suspend fun identify(sceneIds: List<String>): Pair<String, String?> {
        val config = GraphQL.named("configuration")["configuration"].obj
        val boxes = config?.get("general").obj?.get("stashBoxes").arr.orEmpty().mapNotNull { it.obj }
        if (boxes.isEmpty()) throw GraphQLError.Query("No Stash-Box endpoints configured on this server.")
        val identifyDefaults = config?.get("defaults").obj?.get("identify").obj
        val defaultSources = identifyDefaults?.get("sources").arr.orEmpty().mapNotNull { it.obj }
        val sources: List<Map<String, Any?>> = if (defaultSources.isNotEmpty()) {
            defaultSources.mapNotNull { src ->
                val endpoint = src["source"].obj?.get("stash_box_endpoint").stringOrNull ?: return@mapNotNull null
                val entry = mutableMapOf<String, Any?>("source" to mapOf("stash_box_endpoint" to endpoint))
                src["options"].obj?.let { entry["options"] = identifyOptions(it) }
                entry
            }
        } else boxes.map { mapOf("source" to mapOf("stash_box_endpoint" to it["endpoint"].stringOrNull)) }
        val options: Any = identifyDefaults?.get("options").obj?.let { identifyOptions(it) } ?: mapOf(
            "fieldOptions" to listOf(
                mapOf("field" to "title", "strategy" to "OVERWRITE"),
                mapOf("field" to "studio", "strategy" to "MERGE", "createMissing" to true),
                mapOf("field" to "performers", "strategy" to "MERGE", "createMissing" to true),
                mapOf("field" to "tags", "strategy" to "MERGE", "createMissing" to true),
            ),
            "setCoverImage" to true, "setOrganized" to false, "includeMalePerformers" to false,
            "skipMultipleMatches" to true, "skipSingleNamePerformers" to true,
        )
        val input = mapOf("sources" to sources, "options" to options, "sceneIDs" to sceneIds)
        val jobId = GraphQL.named("metadataIdentify", vars("input" to input))["metadataIdentify"].stringOrNull
        val names = boxes.joinToString(", ") { it["name"].stringOrNull ?: it["endpoint"].stringOrNull.orEmpty() }
        val message = if (sceneIds.size == 1) "Identify started for this scene using: $names" else "Identify started using: $names"
        return message to jobId?.takeIf { it.isNotEmpty() }
    }

    /** iOS: `identifyOptionsDict` — nulls dropped, `performerGenders` wins over `includeMalePerformers`. */
    private fun identifyOptions(o: JsonObject): Map<String, Any?> {
        val dict = mutableMapOf<String, Any?>()
        o["fieldOptions"].arr?.let { list ->
            dict["fieldOptions"] = list.mapNotNull { it.obj }.map { f ->
                buildMap<String, Any?> {
                    put("field", f["field"].stringOrNull); put("strategy", f["strategy"].stringOrNull)
                    f["createMissing"].stringOrNull?.toBooleanStrictOrNull()?.let { put("createMissing", it) }
                }
            }
        }
        fun bool(k: String) = o[k].stringOrNull?.toBooleanStrictOrNull()
        bool("setCoverImage")?.let { dict["setCoverImage"] = it }
        bool("setOrganized")?.let { dict["setOrganized"] = it }
        val genders = o["performerGenders"].arr?.mapNotNull { it.stringOrNull }
        if (!genders.isNullOrEmpty()) dict["performerGenders"] = genders else dict["includeMalePerformers"] = bool("includeMalePerformers") ?: false
        bool("skipMultipleMatches")?.let { dict["skipMultipleMatches"] = it }
        o["skipMultipleMatchTag"].stringOrNull?.let { dict["skipMultipleMatchTag"] = it }
        bool("skipSingleNamePerformers")?.let { dict["skipSingleNamePerformers"] = it }
        o["skipSingleNamePerformerTag"].stringOrNull?.let { dict["skipSingleNamePerformerTag"] = it }
        return dict
    }

    // MARK: - Pickers (edit sheets)

    /** iOS: `fetchAllTags` — 1000 by scene count. */
    suspend fun allTags(sort: String = "scenes_count"): List<Tag> =
        findPage("findTags", "findTags", "tags", Tag.serializer(), FindFilter(1, 1000, sort = sort), "tag_filter", JsonObject(emptyMap())).items

    /** iOS: `fetchAllPerformers`. */
    suspend fun allPerformers(): List<Performer> =
        findPage("findPerformers", "findPerformers", "performers", Performer.serializer(), FindFilter(1, 1000, sort = "scenes_count"), "performer_filter", JsonObject(emptyMap())).items

    /** iOS: `fetchAllStudios`. */
    suspend fun allStudios(): List<Studio> =
        findPage("findStudios", "findStudios", "studios", Studio.serializer(), FindFilter(1, 1000, sort = "scenes_count"), "studio_filter", JsonObject(emptyMap())).items

    /** iOS: `fetchAllGroupsForScene` (all, by name). */
    suspend fun allGroups(): List<StashGroup> {
        val data = GraphQL.data(SceneQueries.findGroupsForScene, vars("filter" to mapOf("per_page" to -1, "sort" to "name", "direction" to "ASC")))
        return GraphQL.decode(ListSerializer(StashGroup.serializer()), data["findGroups"].obj?.get("groups") ?: JsonArray(emptyList()))
    }

    /** iOS: `fetchGalleriesForSceneEdit` — galleries of these performers, or all when empty. */
    suspend fun galleriesForEdit(performerIds: List<String>): List<Gallery> {
        val pairs = mutableListOf<Pair<String, Any?>>("filter" to mapOf("per_page" to -1, "sort" to "title", "direction" to "ASC"))
        if (performerIds.isNotEmpty()) pairs += "gallery_filter" to mapOf("performers" to mapOf("value" to performerIds, "modifier" to "INCLUDES"))
        val data = GraphQL.data(SceneQueries.findGalleriesForScene, vars(*pairs.toTypedArray()))
        return GraphQL.decode(ListSerializer(Gallery.serializer()), data["findGalleries"].obj?.get("galleries") ?: JsonArray(emptyList()))
    }

    /** iOS: `fetchGalleryPreviewImages` — first [limit] images by path. */
    suspend fun galleryPreviewImages(galleryId: String, limit: Int = 40): List<StashImage> =
        findPage(
            "findImages", "findImages", "images", StashImage.serializer(),
            FindFilter(1, limit, sort = "path", direction = "ASC"), "image_filter",
            buildJsonObject { put("galleries", vars("value" to listOf(galleryId), "modifier" to "INCLUDES")) },
        ).items

    suspend fun createPerformer(name: String): Performer =
        GraphQL.decode(Performer.serializer(), GraphQL.data(SceneQueries.performerCreate, input("name" to name))["performerCreate"] ?: JsonNull)

    suspend fun createStudio(name: String): Studio =
        GraphQL.decode(Studio.serializer(), GraphQL.data(SceneQueries.studioCreate, input("name" to name))["studioCreate"] ?: JsonNull)

    suspend fun createGroup(name: String): StashGroup =
        GraphQL.decode(StashGroup.serializer(), GraphQL.data(SceneQueries.groupCreate, input("name" to name))["groupCreate"] ?: JsonNull)

    suspend fun createTag(name: String): Tag =
        GraphQL.decode(Tag.serializer(), GraphQL.data(SceneQueries.tagCreate, input("name" to name))["tagCreate"] ?: JsonNull)
}
