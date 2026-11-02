package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.arr
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * iOS: `MagazineReadingStore` — last read page per gallery. Stash's gallery `custom_fields` are the
 * shared source across devices (and with the iOS app); a local per-server copy covers offline
 * reading and servers without those fields.
 */
object MagazineReadingStore {
    val entries = mutableStateMapOf<String, MagazineEntry>()

    private val scope = MainScope()
    private val serializer = MapSerializer(String.serializer(), MagazineEntry.serializer())
    private var loadedSuffix: String? = null

    private val suffix: String get() = ServerConfigManager.activeConfig?.id ?: "none"
    private val storageKey: String get() = "stashy.magazine.progress_$suffix"

    /** Reloads the local copy after a server switch. */
    fun ensureLoaded() {
        if (loadedSuffix == suffix) return
        loadedSuffix = suffix
        entries.clear()
        Prefs.string(storageKey)?.let { raw ->
            runCatching { Json.decodeFromString(serializer, raw) }.getOrNull()?.let(entries::putAll)
        }
    }

    private fun save() = Prefs.setString(storageKey, Json.encodeToString(serializer, entries.toMap()))

    /** Local only; the server gets it on [pushIfNeeded], because every `galleryUpdate` also bumps `updated_at`. */
    fun note(page: Int, galleryId: String) {
        ensureLoaded()
        // Seconds only: iOS' `ISO8601DateFormatter` does not read fractions.
        val now = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()
        entries[galleryId] = MagazineEntry(page, now, isSynced = false)
        save()
    }

    /** Back to the first page, here and on the server. */
    fun resetPosition(galleryId: String) {
        note(1, galleryId)
        pushInBackground(galleryId)
    }

    fun pushInBackground(galleryId: String) {
        scope.launch { pushIfNeeded(galleryId) }
    }

    /**
     * Merges the server's positions in. Failure (offline, server without gallery custom fields)
     * just leaves the local copy in charge.
     */
    suspend fun sync(galleryIds: List<String>) {
        if (galleryIds.isEmpty()) return
        ensureLoaded()
        val startedOn = suffix
        try {
            val remote = MagazineRepository.customFields(galleryIds)
            if (startedOn != suffix) return
            var changed = false
            val unsynced = mutableListOf<String>()
            for (id in galleryIds) {
                val local = entries[id]
                val entry = MagazineLogic.entryFromFields(remote[id])
                if (entry != null && MagazineLogic.remoteWins(entry, local)) {
                    if (local != entry) { entries[id] = entry; changed = true }
                } else if (local?.isSynced == false) {
                    unsynced += id
                }
            }
            if (changed) save()
            // E.g. the app was killed while reading before it could push.
            unsynced.forEach { pushIfNeeded(it) }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }

    private suspend fun pushIfNeeded(galleryId: String) {
        ensureLoaded()
        val entry = entries[galleryId]?.takeUnless { it.isSynced } ?: return
        val startedOn = suffix
        try {
            MagazineRepository.updatePosition(galleryId, entry)
            // Reading may have moved on during the request; that position still has to go out.
            if (startedOn != suffix || entries[galleryId] != entry) return
            entries[galleryId] = entry.copy(isSynced = true)
            save()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }
}

/** iOS: `MagazineDefaultFilter` — Settings › Tools: the saved gallery filter Magazin opens with, per server. */
object MagazineDefaultFilter {
    /** Bumped on every change so a menu or an open list reads the new value. */
    private var version by mutableIntStateOf(0)

    private val key: String get() = "stashy.magazine.defaultFilter_${ServerConfigManager.activeConfig?.id ?: "none"}"

    val id: String? get() {
        version
        return Prefs.string(key)
    }

    fun set(filterId: String?) {
        Prefs.setString(key, filterId)
        version++
    }
}

/** iOS: the Magazin part of `GalleryRepository`. */
object MagazineRepository {
    private const val PAGE_SIZE = 200

    /** Separate from `GalleryFields`: that fragment has to keep working on servers without gallery custom fields. */
    suspend fun customFields(galleryIds: List<String>): Map<String, kotlinx.serialization.json.JsonObject?> {
        val variables = buildJsonObject {
            putJsonObject("filter") { put("per_page", galleryIds.size) }
            putJsonArray("ids") { galleryIds.forEach { add(JsonPrimitive(it)) } }
        }
        val data = GraphQL.named("findGalleriesCustomFields", variables)
        val galleries = data["findGalleries"].obj?.get("galleries").arr ?: JsonArray(emptyList())
        return galleries.mapNotNull { element ->
            val gallery = element.obj ?: return@mapNotNull null
            val id = gallery["id"].stringOrNull ?: return@mapNotNull null
            id to gallery["custom_fields"].obj
        }.toMap()
    }

    suspend fun updatePosition(galleryId: String, entry: MagazineEntry) {
        val variables = buildJsonObject {
            putJsonObject("input") {
                put("id", galleryId)
                putJsonObject("custom_fields") {
                    putJsonObject("partial") {
                        put(MagazineLogic.PAGE_FIELD, entry.page)
                        put(MagazineLogic.READ_AT_FIELD, entry.readAt)
                    }
                }
            }
        }
        GraphQL.named("galleryUpdateCustomFields", variables)
    }

    /** Every image of the gallery: the natural file order only exists client-side. */
    suspend fun pages(galleryId: String): List<StashImage> {
        val loaded = LinkedHashMap<String, StashImage>()
        var page = 1
        while (true) {
            val variables = buildJsonObject {
                putJsonObject("filter") {
                    put("page", page)
                    put("per_page", PAGE_SIZE)
                    put("sort", "title")
                    put("direction", "ASC")
                }
                putJsonObject("image_filter") {
                    putJsonObject("galleries") {
                        putJsonArray("value") { add(JsonPrimitive(galleryId)) }
                        put("modifier", "INCLUDES")
                    }
                }
            }
            val result = GraphQL.named("findImages", variables)["findImages"].obj
            val images = GraphQL.decode(
                ListSerializer(StashImage.serializer()),
                result?.get("images") ?: JsonArray(emptyList()),
            )
            images.forEach { loaded.putIfAbsent(it.id, it) }
            val total = result?.get("count")?.jsonPrimitive?.int ?: 0
            if (images.isEmpty() || page * PAGE_SIZE >= total) break
            page++
        }
        return MagazineLogic.pages(loaded.values.toList())
    }
}
