package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Stash ignores `birth_year` / `age` inside `performers_filter`; the app sends them as a
 * `birthdate` range there (`FilterMapper.performerAgeAsBirthdate`). Same as iOS.
 */
class PerformerAgeSubFilterTest {
    private fun obj(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject
    private val today = LocalDate.of(2026, 11, 9)

    @Test
    fun birthYearBecomesABirthdateRange() {
        val out = FilterMapper.performerAgeAsBirthdate(
            obj("""{"performers_filter":{"birth_year":{"value":1995,"modifier":"EQUALS"}}}"""), today,
        )
        assertEquals(
            obj("""{"performers_filter":{"birthdate":{"value":"1995-01-01","value2":"1995-12-31","modifier":"BETWEEN"}}}"""),
            out,
        )
        val after = FilterMapper.performerAgeAsBirthdate(
            obj("""{"performers_filter":{"birth_year":{"value":1990,"modifier":"GREATER_THAN"}}}"""), today,
        )
        assertEquals(obj("""{"value":"1990-12-31","modifier":"GREATER_THAN"}"""),
            after["performers_filter"]!!.jsonObject["birthdate"])
    }

    @Test
    fun ageCountsFromToday() {
        fun range(json: String) = FilterMapper.performerAgeAsBirthdate(obj(json), today)["performers_filter"]!!
            .jsonObject["birthdate"]
        // Younger than 30: born after 2026-11-09 minus 30 years.
        assertEquals(obj("""{"value":"1996-11-09","modifier":"GREATER_THAN"}"""),
            range("""{"performers_filter":{"age":{"value":30,"modifier":"LESS_THAN"}}}"""))
        // Older than 30: aged 31+, born on or before 1995-11-09.
        assertEquals(obj("""{"value":"1995-11-10","modifier":"LESS_THAN"}"""),
            range("""{"performers_filter":{"age":{"value":30,"modifier":"GREATER_THAN"}}}"""))
        // Exactly 30: born 1995-11-10 … 1996-11-09.
        assertEquals(obj("""{"value":"1995-11-10","value2":"1996-11-09","modifier":"BETWEEN"}"""),
            range("""{"performers_filter":{"age":{"value":30,"modifier":"EQUALS"}}}"""))
        // 20 to 30.
        assertEquals(obj("""{"value":"1995-11-10","value2":"2006-11-09","modifier":"BETWEEN"}"""),
            range("""{"performers_filter":{"age":{"value":30,"value2":20,"modifier":"BETWEEN"}}}"""))
    }

    @Test
    fun anExistingBirthdateMovesIntoAnd() {
        val out = FilterMapper.performerAgeAsBirthdate(
            obj("""{"performers_filter":{"birthdate":{"value":"","modifier":"NOT_NULL"},"birth_year":{"value":1995,"modifier":"EQUALS"}}}"""),
            today,
        )["performers_filter"]!!.jsonObject
        assertEquals(obj("""{"value":"1995-01-01","value2":"1995-12-31","modifier":"BETWEEN"}"""), out["birthdate"])
        assertEquals(obj("""{"birthdate":{"value":"","modifier":"NOT_NULL"}}"""), out["AND"])
    }

    @Test
    fun performerQueriesAndOtherKeysStayAsTheyAre() {
        val direct = obj("""{"birth_year":{"value":1990,"modifier":"GREATER_THAN"},"age":{"value":30,"modifier":"LESS_THAN"}}""")
        assertTrue(FilterMapper.performerAgeAsBirthdate(direct, today) === direct)
        val plain = obj("""{"performers_filter":{"height_cm":{"value":180,"modifier":"EQUALS"}}}""")
        assertTrue(FilterMapper.performerAgeAsBirthdate(plain, today) === plain)
    }

    @Test
    fun queryVariablesRewritesInsideSceneFilters() {
        val vars = obj("""{"scene_filter":{"performers_filter":{"age":{"modifier":"NOT_NULL","value":0}}}}""")
        val sent = FilterMapper.queryVariables(vars)
        assertEquals(obj("""{"value":"","modifier":"NOT_NULL"}"""),
            sent["scene_filter"]!!.jsonObject["performers_filter"]!!.jsonObject["birthdate"])
    }
}
