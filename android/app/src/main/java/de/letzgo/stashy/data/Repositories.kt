package de.letzgo.stashy.data

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** iOS: `FindFilterType` (page is 1-based; per_page -1 = all). */
data class FindFilter(
    val page: Int = 1,
    val perPage: Int = 40,
    val sort: String? = null,
    val direction: String = "DESC",
    val q: String? = null,
) {
    fun json(): JsonObject = buildJsonObject {
        put("page", JsonPrimitive(page))
        put("per_page", JsonPrimitive(perPage))
        sort?.let { put("sort", JsonPrimitive(it)) }
        put("direction", JsonPrimitive(direction))
        q?.takeIf { it.isNotBlank() }?.let { put("q", JsonPrimitive(it)) }
    }
}

/**
 * Generic `find<X>` caller for the shared .graphql documents: runs [document] with
 * `filter` + the entity filter under [filterVar], and reads `{ count, <listField> }` of [field].
 */
suspend fun <T> findPage(
    document: String,
    field: String,
    listField: String,
    item: kotlinx.serialization.KSerializer<T>,
    filter: FindFilter,
    filterVar: String? = null,
    entityFilter: JsonObject? = null,
    extra: Map<String, Any?> = emptyMap(),
): Page<T> {
    val variables = buildJsonObject {
        put("filter", filter.json())
        if (filterVar != null && entityFilter != null) put(filterVar, entityFilter)
        extra.forEach { (k, v) -> put(k, v.toJson()) }
    }
    val data = GraphQL.named(document, variables)
    val obj = data[field].obj ?: throw GraphQLError.Query("Missing $field")
    val count = obj["count"].stringOrNull?.toIntOrNull() ?: 0
    val items = GraphQL.decode(ListSerializer(item), obj[listField] ?: kotlinx.serialization.json.JsonArray(emptyList()))
    return Page(count, items)
}

object ScenesRepository {
    suspend fun find(filter: FindFilter, sceneFilter: JsonObject? = null): Page<Scene> =
        findPage("findScenes", "findScenes", "scenes", Scene.serializer(), filter, "scene_filter", sceneFilter)

    suspend fun scene(id: String): Scene? {
        val data = GraphQL.named("findScene", vars("id" to id))
        return data["findScene"]?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.let { GraphQL.decode(Scene.serializer(), it) }
    }
}
