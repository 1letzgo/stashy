package de.letzgo.stashy.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class SharedScenesScopeTest {
    @Test fun scopeIsIncludesAllOfBothPerformers() {
        assertEquals(
            """{"performers":{"value":["12","34"],"modifier":"INCLUDES_ALL"}}""",
            Json.encodeToString(JsonObject.serializer(), CoPerformerLogic.sharedScenesScope("12", "34")),
        )
    }

    @Test fun scopeWinsOverLivePerformerCriteria() {
        val live = JsonObject(mapOf("performers" to buildJsonObject {
            put("value", JsonArray(listOf(JsonPrimitive("99")))); put("modifier", JsonPrimitive("INCLUDES"))
        }))
        val f = CatalogQuery(FilterMode.Scenes, SortCatalog.scenes[1], live = live, scope = CoPerformerLogic.sharedScenesScope("1", "2")).entityFilter()!!
        val performers = f["performers"]!!.jsonObject
        assertEquals(JsonArray(listOf(JsonPrimitive("1"), JsonPrimitive("2"))), performers["value"])
        assertEquals(JsonPrimitive("INCLUDES_ALL"), performers["modifier"])
    }
}
