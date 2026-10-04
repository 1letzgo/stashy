package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashID
import de.letzgo.stashy.data.arr
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import de.letzgo.stashy.data.vars
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import java.text.Collator
import java.util.Locale
import java.util.UUID

// iOS: `MergeTools.swift` (models, presets, index) + `TagRepository` / `StudioRepository`
// merge functions. Tools → Merge Tags / Merge Studios.

private val MergeJson = kotlinx.serialization.json.Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
    isLenient = true
    encodeDefaults = true
}

// MARK: - Mergeable items

/** iOS: `MergeableItem` — what the merge page needs from an entry. */
interface MergeableItem {
    val id: String
    val name: String
    val mergeUsageSummary: String
    /** Stable features for templates: a scraper re-creates a merged source under a new id. */
    val mergeStashIds: List<MergePresetStashId>
    val mergeAliases: List<String>
}

/** iOS: `Tag` as returned by `findTagsForMerge` (with aliases and stash_ids). */
@Serializable
data class MergeTag(
    override val id: String,
    override val name: String = "",
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("gallery_count") val galleryCount: Int? = null,
    @SerialName("scene_marker_count") val sceneMarkerCount: Int? = null,
    @SerialName("performer_count") val performerCount: Int? = null,
    val aliases: List<String>? = null,
    @SerialName("stash_ids") val stashIds: List<StashID>? = null,
) : MergeableItem {
    override val mergeStashIds: List<MergePresetStashId> get() = MergePresetStashId.from(stashIds)
    override val mergeAliases: List<String> get() = aliases.orEmpty()
    override val mergeUsageSummary: String get() {
        val parts = mutableListOf<String>()
        MergeUsage.append(parts, sceneCount, "scene")
        MergeUsage.append(parts, imageCount, "image")
        MergeUsage.append(parts, galleryCount, "gallery", plural = "galleries")
        MergeUsage.append(parts, performerCount, "performer")
        MergeUsage.append(parts, sceneMarkerCount, "marker")
        return if (parts.isEmpty()) "Unused" else parts.joinToString(" · ")
    }
}

/** iOS: `Studio` as returned by `findStudiosForMerge`. */
@Serializable
data class MergeStudio(
    override val id: String,
    override val name: String = "",
    @SerialName("scene_count") val sceneCount: Int? = null,
    @SerialName("image_count") val imageCount: Int? = null,
    @SerialName("gallery_count") val galleryCount: Int? = null,
    @SerialName("performer_count") val performerCount: Int? = null,
    val aliases: List<String>? = null,
    @SerialName("stash_ids") val stashIds: List<StashID>? = null,
) : MergeableItem {
    override val mergeStashIds: List<MergePresetStashId> get() = MergePresetStashId.from(stashIds)
    override val mergeAliases: List<String> get() = aliases.orEmpty()
    override val mergeUsageSummary: String get() {
        val parts = mutableListOf<String>()
        MergeUsage.append(parts, sceneCount, "scene")
        MergeUsage.append(parts, imageCount, "image")
        MergeUsage.append(parts, galleryCount, "gallery", plural = "galleries")
        MergeUsage.append(parts, performerCount, "performer")
        return if (parts.isEmpty()) "Unused" else parts.joinToString(" · ")
    }
}

/** iOS: `MergeUsage`. */
object MergeUsage {
    fun append(parts: MutableList<String>, value: Int?, singular: String, plural: String? = null) {
        if (value == null || value <= 0) return
        parts.add("$value ${if (value == 1) singular else (plural ?: singular + "s")}")
    }
}

/** iOS `localizedCaseInsensitiveCompare` for name sorting. */
object MergeSort {
    private val collator: Collator = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }
    fun compare(a: String, b: String): Int = collator.compare(a, b)
    fun <T : MergeableItem> byName(): Comparator<T> = Comparator { l, r -> compare(l.name, r.name) }
}

// MARK: - Presets (local)

/** iOS: `MergePresetStashId` — endpoint + id, the only identity that survives a re-scrape. */
@Serializable
data class MergePresetStashId(val endpoint: String, val stashId: String) {
    companion object {
        fun from(ids: List<StashID>?): List<MergePresetStashId> = ids.orEmpty().mapNotNull { id ->
            val endpoint = id.endpoint?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val stashId = id.stashId?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            MergePresetStashId(endpoint, stashId)
        }
    }
}

/** iOS: `MergePresetEntry` — id plus name and stash_ids, so a re-created entry is found again. */
@Serializable
data class MergePresetEntry(
    val id: String = "",
    val name: String = "",
    val stashIds: List<MergePresetStashId> = emptyList(),
) {
    val displayName: String get() = name.ifEmpty { id }
}

/** iOS: `MergePreset` — destination + sources, stored only on this device, per server. */
data class MergePreset(
    val id: String = UUID.randomUUID().toString().uppercase(),
    val name: String,
    val destination: MergePresetEntry,
    val sources: List<MergePresetEntry>,
)

/**
 * iOS: `MergePreset` Codable — writes the new format, reads the legacy one
 * (`destinationId`, `destinationName`, `sourceIds`) as entries without identity features.
 */
object MergePresetCodec {
    fun encode(presets: List<MergePreset>): String = buildJsonArray {
        presets.forEach { p ->
            add(buildJsonObject {
                put("id", JsonPrimitive(p.id))
                put("name", JsonPrimitive(p.name))
                put("destination", MergeJson.encodeToJsonElement(MergePresetEntry.serializer(), p.destination))
                put("sources", MergeJson.encodeToJsonElement(ListSerializer(MergePresetEntry.serializer()), p.sources))
            })
        }
    }.toString()

    fun decode(text: String?): List<MergePreset> {
        if (text.isNullOrBlank()) return emptyList()
        val array = runCatching { MergeJson.parseToJsonElement(text) as? JsonArray }.getOrNull() ?: return emptyList()
        return array.mapNotNull { el -> runCatching { decodeOne(el.jsonObject) }.getOrNull() }
    }

    private fun decodeOne(o: JsonObject): MergePreset {
        val id = o["id"].stringOrNull ?: UUID.randomUUID().toString().uppercase()
        val name = o["name"].stringOrNull ?: ""
        val dest = o["destination"]
        return if (dest is JsonObject) {
            MergePreset(
                id = id, name = name,
                destination = MergeJson.decodeFromJsonElement(MergePresetEntry.serializer(), dest),
                sources = o["sources"]?.let { MergeJson.decodeFromJsonElement(ListSerializer(MergePresetEntry.serializer()), it) }.orEmpty(),
            )
        } else {
            MergePreset(
                id = id, name = name,
                destination = MergePresetEntry(o["destinationId"].stringOrNull ?: "", o["destinationName"].stringOrNull ?: ""),
                sources = o["sourceIds"].arr?.mapNotNull { it.stringOrNull }?.map { MergePresetEntry(it) }.orEmpty(),
            )
        }
    }
}

// MARK: - Resolving preset entries

/**
 * iOS: `MergeItemIndex` — id → item, stash_id → item, lowercased name / alias → item.
 * Resolution order: exact id, stash_id, name, alias; the first hit wins.
 */
class MergeItemIndex<T : MergeableItem>(items: List<T> = emptyList()) {
    private val byId = HashMap<String, T>()
    private val byStashId = HashMap<String, T>()
    private val byName = HashMap<String, T>()
    private val byAlias = HashMap<String, T>()

    init {
        for (item in items) {
            byId[item.id] = item
            for (s in item.mergeStashIds) byStashId.putIfAbsent(key(s), item)
            val n = item.name.lowercase()
            if (n.isNotEmpty()) byName.putIfAbsent(n, item)
            for (alias in item.mergeAliases) {
                val k = alias.lowercase()
                if (k.isNotEmpty()) byAlias.putIfAbsent(k, item)
            }
        }
    }

    private fun key(s: MergePresetStashId) = "${s.endpoint}\u0001${s.stashId}"

    fun resolve(entry: MergePresetEntry): T? {
        if (entry.id.isNotEmpty()) byId[entry.id]?.let { return it }
        for (s in entry.stashIds) byStashId[key(s)]?.let { return it }
        val n = entry.name.lowercase()
        if (n.isEmpty()) return null
        return byName[n] ?: byAlias[n]
    }
}

/**
 * iOS: `MergePresetStore` — stored under `MergePresets_<kind>_<serverID>` (tags and studios
 * separately, invisible to other servers). Android keeps the JSON as a string pref.
 */
class MergePresetStore(val kind: String) {
    var presets by mutableStateOf<List<MergePreset>>(emptyList())
        private set

    init { load() }

    private val key: String get() {
        val serverId = ServerConfigManager.activeConfig?.id ?: "default"
        return "MergePresets_${kind}_$serverId"
    }

    fun load() { presets = MergePresetCodec.decode(Prefs.string(key)) }

    /** Same name overwrites — otherwise duplicates pile up. */
    fun save(preset: MergePreset) {
        presets = (presets.filterNot { it.name.equals(preset.name, ignoreCase = true) } + preset)
            .sortedWith { a, b -> MergeSort.compare(a.name, b.name) }
        persist()
    }

    /** Replace destination/sources of an existing template; name and id stay. */
    fun update(id: String, destination: MergePresetEntry, sources: List<MergePresetEntry>) {
        if (presets.none { it.id == id }) return
        presets = presets.map { if (it.id == id) it.copy(destination = destination, sources = sources) else it }
        persist()
    }

    fun delete(preset: MergePreset) {
        presets = presets.filterNot { it.id == preset.id }
        persist()
    }

    private fun persist() = Prefs.setString(key, MergePresetCodec.encode(presets))
}

// MARK: - Repository

/** iOS: `StudioMergeError`. */
sealed class StudioMergeError(message: String) : Exception(message) {
    object NoData : StudioMergeError("Server returned no data")
    class Incomplete(n: Int) : StudioMergeError("$n items could not be moved — nothing was deleted")
    object DestroyFailed : StudioMergeError("Sources could not be deleted")
}

/** iOS: merge parts of `TagRepository` and `StudioRepository`. */
object MergeRepository {
    private const val PER_PAGE = 500

    /**
     * iOS: `TagRepository.mergeTags` — Stash rewrites scenes, images, galleries, performers and
     * markers of the sources onto the destination and deletes the sources (`tagsMerge`).
     */
    suspend fun mergeTags(sourceIds: List<String>, destinationId: String) {
        GraphQL.named("tagsMerge", vars("input" to mapOf("source" to sourceIds, "destination" to destinationId)))
    }

    /** iOS: `fetchEveryTagForMerge` — every tag with aliases/stash_ids; falls back to `findTags`. */
    suspend fun fetchEveryTagForMerge(): List<MergeTag> = try {
        fetchEvery("findTagsForMerge", "findTags", "tags", MergeTag.serializer())
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (e: Exception) {
        fetchEvery("findTags", "findTags", "tags", MergeTag.serializer())
    }

    /** iOS: `fetchEveryStudioForMerge`; falls back to `findStudios`. */
    suspend fun fetchEveryStudioForMerge(): List<MergeStudio> = try {
        fetchEvery("findStudiosForMerge", "findStudios", "studios", MergeStudio.serializer())
    } catch (e: kotlinx.coroutines.CancellationException) {
        throw e
    } catch (e: Exception) {
        fetchEvery("findStudios", "findStudios", "studios", MergeStudio.serializer())
    }

    private suspend fun <T> fetchEvery(doc: String, field: String, listField: String, ser: kotlinx.serialization.KSerializer<T>): List<T> {
        val collected = mutableListOf<T>()
        var page = 1
        while (true) {
            val data = GraphQL.named(doc, vars("filter" to mapOf("page" to page, "per_page" to PER_PAGE, "sort" to "name", "direction" to "ASC")))
            val obj = data[field].obj
            val total = obj?.get("count").stringOrNull?.toIntOrNull() ?: 0
            val items = obj?.get(listField)?.let { GraphQL.decode(ListSerializer(ser), it) }.orEmpty()
            collected.addAll(items)
            if (items.size < PER_PAGE) break
            if (total > 0 && collected.size >= total) break
            page += 1
            if (page > 60) break // safety valve against a backend that always returns full pages
        }
        return collected
    }

    private class StudioLinks {
        val scenes = mutableListOf<String>()
        val galleries = mutableListOf<String>()
        val images = mutableListOf<String>()
        val groups = mutableListOf<String>()
        val children = mutableListOf<String>()
    }

    /**
     * iOS: `StudioRepository.mergeStudios` — Stash has no `studiosMerge`: collect links, move them
     * with bulk updates, count again, and only then delete the sources.
     */
    suspend fun mergeStudios(sourceIds: List<String>, destinationId: String) {
        if (sourceIds.isEmpty()) return
        val links = collectLinks(sourceIds)
        reassign("bulkSceneUpdateStudio", links.scenes, "studioId", destinationId)
        reassign("bulkGalleryUpdateStudio", links.galleries, "studioId", destinationId)
        reassign("bulkImageUpdateStudio", links.images, "studioId", destinationId)
        reassign("bulkGroupUpdateStudio", links.groups, "studioId", destinationId)
        reassign("bulkStudioUpdateParent", links.children.filter { it != destinationId }, "parentId", destinationId)

        val remaining = collectLinks(sourceIds)
        val leftovers = remaining.scenes.size + remaining.galleries.size + remaining.images.size + remaining.groups.size +
            remaining.children.count { it != destinationId }
        if (leftovers != 0) throw StudioMergeError.Incomplete(leftovers)

        val destroyed = GraphQL.named("studiosDestroy", vars("ids" to sourceIds))
        if ((destroyed["studiosDestroy"] as? JsonPrimitive)?.booleanOrNull != true) throw StudioMergeError.DestroyFailed
    }

    /** Paged instead of `per_page: -1`, which does not behave the same on every server version. */
    private suspend fun collectLinks(studioIds: List<String>): StudioLinks {
        val links = StudioLinks()
        var page = 1
        while (true) {
            val data = GraphQL.named("findStudioMergeSources", vars("studios" to studioIds, "page" to page, "perPage" to PER_PAGE))
            fun part(field: String, list: String, into: MutableList<String>): Int {
                val o = data[field].obj ?: throw StudioMergeError.NoData
                into.addAll(ids(o[list]))
                return o["count"].stringOrNull?.toIntOrNull() ?: 0
            }
            val maxCount = maxOf(
                part("findScenes", "scenes", links.scenes),
                part("findGalleries", "galleries", links.galleries),
                part("findImages", "images", links.images),
                part("findGroups", "groups", links.groups),
                part("findStudios", "studios", links.children),
            )
            if (page * PER_PAGE >= maxCount || page >= 200) break
            page += 1
        }
        return links
    }

    private fun ids(el: JsonElement?): List<String> = el.arr?.mapNotNull { it.obj?.get("id").stringOrNull }.orEmpty()

    /** Bulk updates in chunks of 500 — huge studios would otherwise be one giant request. */
    private suspend fun reassign(mutation: String, ids: List<String>, key: String, target: String) {
        if (ids.isEmpty()) return
        ids.chunked(500).forEach { chunk ->
            GraphQL.named(mutation, vars("ids" to chunk, key to target))
        }
    }
}
