package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.VisualFile
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

// iOS: the fetch / mutate half of `RateMeViewModel` (`stashy/RateMeToolsView.swift`).

@Serializable
internal data class RateMePerformerDTO(val id: String, val name: String? = null)

@Serializable
internal data class RateMeScenePaths(val screenshot: String? = null, val preview: String? = null)

@Serializable
internal data class RateMeSceneDTO(
    val id: String,
    val title: String? = null,
    val rating100: Int? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    val paths: RateMeScenePaths? = null,
    val performers: List<RateMePerformerDTO>? = null,
)

@Serializable
internal data class RateMeImagePaths(val image: String? = null, val preview: String? = null, val thumbnail: String? = null)

@Serializable
internal data class RateMeImageFile(
    @SerialName("__typename") val typename: String? = null,
    val path: String? = null,
    val basename: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val duration: Double? = null,
)

@Serializable
internal data class RateMeImageDTO(
    val id: String,
    val title: String? = null,
    val rating100: Int? = null,
    @SerialName("o_counter") val oCounter: Int? = null,
    val paths: RateMeImagePaths? = null,
    @SerialName("visual_files") val visualFiles: List<RateMeImageFile>? = null,
    val performers: List<RateMePerformerDTO>? = null,
)

/** iOS: `RateMeViewModel.Item`. */
data class RateMeItem(
    val id: String,
    val title: String,
    /** Still thumbnail (scene screenshot / image thumbnail). */
    val thumbnailURL: String?,
    /** Scene preview clip (`paths.preview`), when present. */
    val previewURL: String?,
    /** Full image media — used for image videos (`paths.image`). */
    val videoURL: String?,
    val isVideo: Boolean,
    /** width ÷ height when known (images); scenes always 16:9. */
    val aspectRatio: Float?,
    /** Joined performer names. */
    val performerNames: String?,
    val oCounter: Int,
    val mode: RateMeMode,
    /** Minimal [StashImage] for opening the image viewer (images mode). */
    val openableImage: StashImage?,
) {
    val playbackURL: String? get() = when (mode) {
        RateMeMode.Scenes -> previewURL
        RateMeMode.Images -> if (isVideo) videoURL else null
    }
}

/** One fetch: the next item (null = none left) and `findX.count` (iOS `remainingHint`). */
data class RateMeFetchResult(val item: RateMeItem?, val remainingHint: Int?)

object RateMeRepository {
    const val MODE_KEY = "stashy.rateMe.mode"
    const val IMAGE_MEDIA_KIND_KEY = "stashy.rateMe.imageMediaKind"

    fun loadMode(): RateMeMode = RateMeMode.from(Prefs.string(MODE_KEY)) ?: RateMeMode.Scenes
    fun saveMode(mode: RateMeMode) = Prefs.setString(MODE_KEY, mode.raw)
    fun loadImageMediaKind(): RateMeImageMediaKind = RateMeImageMediaKind.from(Prefs.string(IMAGE_MEDIA_KIND_KEY)) ?: RateMeImageMediaKind.All
    fun saveImageMediaKind(kind: RateMeImageMediaKind) = Prefs.setString(IMAGE_MEDIA_KIND_KEY, kind.raw)

    /** iOS: `signedMediaURL` — absolute URLs signed as is, relative paths under the server base URL. */
    fun signedMediaURL(path: String?): String? {
        if (path.isNullOrEmpty()) return null
        if (path.startsWith("http://") || path.startsWith("https://")) return Net.signed(path)
        val config = ServerConfigManager.activeConfig?.takeIf { it.hasValidConfig } ?: return null
        return Net.signed("${config.baseURL}${if (path.startsWith("/")) "" else "/"}$path")
    }

    // MARK: Fetch

    /** iOS: `fetchUnratedScene()` — [skipIDs] is mutated like the iOS model's `skipIDs`. */
    suspend fun fetchUnratedScene(theme: RateMeTheme, skipIDs: MutableSet<String>): RateMeFetchResult {
        var hint: Int? = null
        repeat(RateMeLogic.MAX_PAGE_ATTEMPTS) {
            val data = GraphQL.named("findScenesCompact", buildJsonObject {
                put("filter", RateMeLogic.pageFilter(theme))
                put("scene_filter", RateMeLogic.unratedFilter(theme))
            })
            val result = data["findScenes"].obj
            hint = result?.get("count").stringOrNull?.toIntOrNull()
            val page = decodeList(result?.get("scenes"), RateMeSceneDTO.serializer())
            if (page.isEmpty()) return RateMeFetchResult(null, hint)
            val scene = page.firstOrNull { it.id !in skipIDs }
            if (scene == null) {
                // Everything on this page was skipped. A fixed sort would return it again.
                if (RateMeLogic.resetsSkipsOnExhaustedPage(theme, RateMeMode.Scenes)) skipIDs.clear()
                return@repeat
            }
            val preview = signedMediaURL(scene.paths?.preview)
            return RateMeFetchResult(
                RateMeItem(
                    id = scene.id,
                    title = RateMeLogic.displayTitle(scene.title, RateMeMode.Scenes),
                    thumbnailURL = signedMediaURL(scene.paths?.screenshot),
                    previewURL = preview,
                    videoURL = null,
                    isVideo = preview != null,
                    aspectRatio = 16f / 9f,
                    performerNames = RateMeLogic.joinedNames(scene.performers.orEmpty().map { it.name }),
                    oCounter = scene.oCounter ?: 0,
                    mode = RateMeMode.Scenes,
                    openableImage = null,
                ),
                hint,
            )
        }
        return RateMeFetchResult(null, hint)
    }

    /** iOS: `fetchUnratedImage()`. */
    suspend fun fetchUnratedImage(theme: RateMeTheme, kind: RateMeImageMediaKind, skipIDs: MutableSet<String>): RateMeFetchResult {
        var hint: Int? = null
        repeat(RateMeLogic.MAX_PAGE_ATTEMPTS) {
            val data = GraphQL.named("findImages", buildJsonObject {
                put("filter", RateMeLogic.pageFilter(theme))
                put("image_filter", RateMeLogic.unratedImageFilter(theme, kind))
            })
            val result = data["findImages"].obj
            hint = result?.get("count").stringOrNull?.toIntOrNull()
            val page = decodeList(result?.get("images"), RateMeImageDTO.serializer())
            if (page.isEmpty()) return RateMeFetchResult(null, hint)
            val image = page.firstOrNull { it.id !in skipIDs }
            if (image == null) {
                if (RateMeLogic.resetsSkipsOnExhaustedPage(theme, RateMeMode.Images)) skipIDs.clear()
                return@repeat
            }
            val first = image.visualFiles?.firstOrNull()
            val isVideo = RateMeLogic.isVideoImage(first?.basename, first?.path, image.paths?.image)
            val thumb = signedMediaURL(image.paths?.thumbnail) ?: signedMediaURL(image.paths?.preview)
            val media = signedMediaURL(image.paths?.image)
            val openable = StashImage(
                id = image.id,
                title = image.title,
                rating100 = image.rating100,
                oCounter = image.oCounter,
                paths = ImagePaths(thumbnail = image.paths?.thumbnail, preview = image.paths?.preview, image = image.paths?.image),
                visualFiles = image.visualFiles?.mapNotNull { f ->
                    if (f.path.isNullOrEmpty()) null
                    else VisualFile(
                        typename = f.typename ?: if (isVideo) "VideoFile" else "ImageFile",
                        path = f.path, basename = f.basename, width = f.width, height = f.height, duration = f.duration,
                    )
                },
                performers = image.performers?.mapNotNull { p ->
                    p.name?.trim()?.takeIf { it.isNotEmpty() }?.let { IdName(p.id, it) }
                },
            )
            return RateMeFetchResult(
                RateMeItem(
                    id = image.id,
                    title = RateMeLogic.displayTitle(image.title, RateMeMode.Images),
                    thumbnailURL = thumb ?: media,
                    previewURL = null,
                    videoURL = if (isVideo) media else null,
                    isVideo = isVideo,
                    aspectRatio = RateMeLogic.imageAspect(first?.width, first?.height, isVideo),
                    performerNames = RateMeLogic.joinedNames(image.performers.orEmpty().map { it.name }),
                    oCounter = image.oCounter ?: 0,
                    mode = RateMeMode.Images,
                    openableImage = openable,
                ),
                hint,
            )
        }
        return RateMeFetchResult(null, hint)
    }

    private fun <T> decodeList(element: JsonElement?, serializer: kotlinx.serialization.KSerializer<T>): List<T> {
        if (element == null || element is JsonNull) return emptyList()
        return GraphQL.decode(ListSerializer(serializer), element)
    }

    // MARK: Mutations (never run against the shared test server)

    private val SCENE_UPDATE = """
        mutation RateMeSceneUpdate(${'$'}input: SceneUpdateInput!) {
          sceneUpdate(input: ${'$'}input) { id rating100 }
        }
    """.trimIndent()

    private val IMAGE_UPDATE = """
        mutation RateMeImageUpdate(${'$'}input: ImageUpdateInput!) {
          imageUpdate(input: ${'$'}input) { id rating100 }
        }
    """.trimIndent()

    private val SCENE_INCREMENT_O = """
        mutation RateMeSceneIncrementO(${'$'}id: ID!) {
          sceneIncrementO(id: ${'$'}id)
        }
    """.trimIndent()

    /** Stash ≥ 0.27 dropped `sceneIncrementO`; `sceneAddO` is its replacement. */
    private val SCENE_ADD_O = """
        mutation RateMeSceneAddO(${'$'}id: ID!) {
          sceneAddO(id: ${'$'}id) { count }
        }
    """.trimIndent()

    private val IMAGE_INCREMENT_O = """
        mutation RateMeImageIncrementO(${'$'}id: ID!) {
          imageIncrementO(id: ${'$'}id)
        }
    """.trimIndent()

    private val SCENE_DESTROY = """
        mutation RateMeSceneDestroy(${'$'}input: SceneDestroyInput!) {
          sceneDestroy(input: ${'$'}input)
        }
    """.trimIndent()

    private val IMAGE_DESTROY = """
        mutation RateMeImageDestroy(${'$'}input: ImageDestroyInput!) {
          imageDestroy(input: ${'$'}input)
        }
    """.trimIndent()

    /** iOS: `mutateRating` — `rating100: null` clears the rating. */
    fun ratingInput(id: String, rating100: Int?): JsonObject = buildJsonObject {
        put("id", JsonPrimitive(id))
        put("rating100", rating100?.let { JsonPrimitive(it) } ?: JsonNull)
    }

    /** iOS: `mutateDestroy` input — deletes files and generated media. */
    fun destroyInput(id: String): JsonObject = buildJsonObject {
        put("id", JsonPrimitive(id))
        put("delete_file", JsonPrimitive(true))
        put("delete_generated", JsonPrimitive(true))
    }

    suspend fun mutateRating(id: String, mode: RateMeMode, rating100: Int?): Boolean {
        val (doc, field) = if (mode == RateMeMode.Scenes) SCENE_UPDATE to "sceneUpdate" else IMAGE_UPDATE to "imageUpdate"
        val data = GraphQL.data(doc, buildJsonObject { put("input", ratingInput(id, rating100)) })
        return data[field] is JsonObject
    }

    /** iOS: `mutateIncrementO` — returns the new count when the server reports it. */
    suspend fun mutateIncrementO(id: String, mode: RateMeMode): Int? {
        val vars = buildJsonObject { put("id", JsonPrimitive(id)) }
        if (mode == RateMeMode.Images) {
            return GraphQL.data(IMAGE_INCREMENT_O, vars)["imageIncrementO"].stringOrNull?.toIntOrNull()
        }
        return try {
            GraphQL.data(SCENE_INCREMENT_O, vars)["sceneIncrementO"].stringOrNull?.toIntOrNull()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Newer Stash: the field no longer exists → use `sceneAddO`.
            if (e.message?.contains("sceneIncrementO") == true || e.message?.contains("schema not compatible") == true ||
                e.message?.contains("Cannot query field") == true
            ) {
                GraphQL.data(SCENE_ADD_O, vars)["sceneAddO"].obj?.get("count").stringOrNull?.toIntOrNull()
            } else throw e
        }
    }

    suspend fun mutateDestroy(id: String, mode: RateMeMode): Boolean {
        val (doc, field) = if (mode == RateMeMode.Scenes) SCENE_DESTROY to "sceneDestroy" else IMAGE_DESTROY to "imageDestroy"
        val data = GraphQL.data(doc, buildJsonObject { put("input", destroyInput(id)) })
        return data[field].stringOrNull == "true"
    }
}

/**
 * iOS: `FilterPickerOptionsStore` (the kinds RateMe uses) — cached "most used" lists per kind
 * plus name-search hits merged on top. Reset when the active server changes.
 */
object RateMePickerOptions {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var serverId: String? = null
    var options by mutableStateOf<Map<RateMePickerKind, List<RateMeOption>>>(emptyMap()); private set
    var loading by mutableStateOf<Set<RateMePickerKind>>(emptySet()); private set
    var searchResults by mutableStateOf<Map<RateMePickerKind, List<RateMeOption>>>(emptyMap()); private set
    var searching by mutableStateOf<Set<RateMePickerKind>>(emptySet()); private set
    private val searchJobs = mutableMapOf<RateMePickerKind, Job>()

    /** iOS: `sceneLiveFilterPickerMaxResults`. */
    private const val PICKER_MAX = 50

    private fun checkServer() {
        val id = ServerConfigManager.activeConfig?.id
        if (id != serverId) {
            serverId = id
            options = emptyMap(); loading = emptySet(); searchResults = emptyMap(); searching = emptySet()
            searchJobs.values.forEach { it.cancel() }
            searchJobs.clear()
        }
    }

    fun isLoading(kind: RateMePickerKind) = kind in loading
    fun isSearching(kind: RateMePickerKind) = kind in searching

    /** iOS: `availableOptions` — cached list plus every search hit, de-duplicated by id. */
    fun availableOptions(kind: RateMePickerKind): List<RateMeOption> {
        val base = options[kind].orEmpty()
        val extra = searchResults[kind].orEmpty()
        if (extra.isEmpty()) return base
        val seen = base.map { it.id }.toMutableSet()
        return base + extra.filter { seen.add(it.id) }
    }

    /** iOS: `load(_:)`. */
    fun load(kind: RateMePickerKind) {
        checkServer()
        if (options[kind].orEmpty().isNotEmpty() || kind in loading) return
        loading = loading + kind
        scope.launch {
            val list = runCatching { fetch(kind) }.getOrElse { emptyList() }
            options = options + (kind to list)
            loading = loading - kind
        }
    }

    /** iOS: `search(_:query:)` — ≥ 2 characters, newest call wins, hits merged. */
    fun search(kind: RateMePickerKind, query: String) {
        checkServer()
        val term = query.trim()
        searchJobs.remove(kind)?.cancel()
        if (term.length < 2) {
            searching = searching - kind
            return
        }
        searching = searching + kind
        searchJobs[kind] = scope.launch {
            val hits = runCatching { searchServer(kind, term) }.getOrElse {
                if (it is CancellationException) throw it
                emptyList()
            }
            searching = searching - kind
            val merged = searchResults[kind].orEmpty().toMutableList()
            val seen = merged.map { it.id }.toMutableSet()
            hits.forEach { if (seen.add(it.id)) merged += it }
            searchResults = searchResults + (kind to merged)
        }
    }

    private fun countFilter(field: String) = buildJsonObject {
        put(field, buildJsonObject { put("value", JsonPrimitive(0)); put("modifier", JsonPrimitive("GREATER_THAN")) })
    }

    private fun findFilter(perPage: Int, sort: String, page: Int? = 1) = buildJsonObject {
        page?.let { put("page", JsonPrimitive(it)) }
        put("per_page", JsonPrimitive(perPage))
        put("sort", JsonPrimitive(sort))
        put("direction", JsonPrimitive("DESC"))
    }

    private suspend fun run(document: String, field: String, listField: String, variables: JsonObject): List<RateMeOption> {
        val data = GraphQL.named(document, variables)
        val arr = data[field].obj?.get(listField) as? JsonArray ?: return emptyList()
        return arr.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val id = o["id"].stringOrNull ?: return@mapNotNull null
            RateMeOption(id, o["name"].stringOrNull ?: "")
        }
    }

    /** iOS: `fetchPerformersForFilterPicker` / `fetchStudiosForLiveFilterPicker` / `fetchTagsFor…LiveFilterPicker`. */
    private suspend fun fetch(kind: RateMePickerKind): List<RateMeOption> = when (kind) {
        RateMePickerKind.Performers -> run("findPerformers", "findPerformers", "performers", buildJsonObject {
            put("filter", findFilter(1000, "scenes_count", page = null))
            put("performer_filter", JsonObject(emptyMap()))
        })
        RateMePickerKind.Studios -> run("findStudios", "findStudios", "studios", buildJsonObject {
            put("filter", findFilter(PICKER_MAX, "scenes_count"))
            put("studio_filter", countFilter("scene_count"))
        })
        RateMePickerKind.ImageStudios -> run("findStudios", "findStudios", "studios", buildJsonObject {
            put("filter", findFilter(PICKER_MAX, "images_count"))
            put("studio_filter", countFilter("image_count"))
        })
        RateMePickerKind.Tags -> run("findTags", "findTags", "tags", buildJsonObject {
            put("filter", findFilter(PICKER_MAX, "scenes_count"))
            put("tag_filter", countFilter("scene_count"))
        })
        RateMePickerKind.ImageTags -> run("findTags", "findTags", "tags", buildJsonObject {
            put("filter", findFilter(PICKER_MAX, "images_count"))
            put("tag_filter", countFilter("image_count"))
        })
    }

    /** iOS: `searchFilterPickerOptions` — name search over the full list (limit 60). */
    private suspend fun searchServer(kind: RateMePickerKind, term: String): List<RateMeOption> {
        val vars = buildJsonObject {
            put("filter", buildJsonObject {
                put("page", JsonPrimitive(1)); put("per_page", JsonPrimitive(60)); put("q", JsonPrimitive(term))
            })
        }
        return when (kind) {
            RateMePickerKind.Performers -> run("findPerformers", "findPerformers", "performers", vars)
            RateMePickerKind.Studios, RateMePickerKind.ImageStudios -> run("findStudios", "findStudios", "studios", vars)
            RateMePickerKind.Tags, RateMePickerKind.ImageTags -> run("findTags", "findTags", "tags", vars)
        }
    }
}
