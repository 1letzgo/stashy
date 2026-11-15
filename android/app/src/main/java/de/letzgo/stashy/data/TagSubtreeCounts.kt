package de.letzgo.stashy.data

import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** What a tag and its sub-tags hold (`*_count(depth: -1)`), whatever the content switch says. */
@Serializable
data class TagSubtreeCounts(
    val id: String,
    @SerialName("scene_count_all") val sceneCountAll: Int = 0,
    @SerialName("gallery_count_all") val galleryCountAll: Int = 0,
    @SerialName("image_count_all") val imageCountAll: Int = 0,
    @SerialName("performer_count_all") val performerCountAll: Int = 0,
)

/**
 * iOS: `TagSubtreeCountsStore` — the counts with sub-tags of the tag pages opened, so a parent
 * tag without own scenes still offers its Scenes section and "Include sub-tag content".
 */
object TagSubtreeCountsStore {
    private const val QUERY = "query FindTagCountsAll(\$id: ID!) { findTag(id: \$id) { id scene_count_all: scene_count(depth: -1) gallery_count_all: gallery_count(depth: -1) image_count_all: image_count(depth: -1) performer_count_all: performer_count(depth: -1) } }"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val counts = mutableStateMapOf<String, TagSubtreeCounts>()

    fun clear() = counts.clear()

    /** Asks again every time: a tag page opening. */
    fun request(id: String) {
        scope.launch {
            runCatching {
                val tag = GraphQL.data(QUERY, vars("id" to id))["findTag"] ?: return@runCatching null
                GraphQL.decode(TagSubtreeCounts.serializer(), tag)
            }.getOrNull()?.let { counts[it.id] = it }
        }
    }

    fun known(id: String): TagSubtreeCounts? = counts[id]
}
