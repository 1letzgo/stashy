package de.letzgo.stashy.ui.detail

import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SortCatalog
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Test

class DirectorScopeTest {
    /** iOS `SavedFilter.scenesByDirector`: `director: { value, modifier: EQUALS }`, layered last. */
    @Test fun directorScopeWinsOverLiveCriteria() {
        val scope = DirectorDetailScreen.directorScope("Jane Doe")
        val live = JsonObject(mapOf("director" to buildJsonObject { put("value", JsonPrimitive("Other")); put("modifier", JsonPrimitive("INCLUDES")) }))
        val f = CatalogQuery(FilterMode.Scenes, SortCatalog.scenes[1], live = live, scope = scope).entityFilter()!!
        val director = f["director"]!!.jsonObject
        assertEquals(JsonPrimitive("(^|,)\\s*Jane Doe\\s*(,|$)"), director["value"])
        assertEquals(JsonPrimitive("MATCHES_REGEX"), director["modifier"])
    }

    @Test fun splitsCommaSeparatedDirectors() {
        assertEquals(listOf("A One", "B Two"), DirectorDetailScreen.directorNames(" A One, B Two ,A One,"))
        assertEquals(emptyList<String>(), DirectorDetailScreen.directorNames(null))
        assertEquals("(^|,)\\s*J\\.D\\s*(,|$)", DirectorDetailScreen.directorRegex("J.D"))
    }
}
