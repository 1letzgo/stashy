package de.letzgo.stashy.data

import org.junit.Assert.assertEquals
import org.junit.Test

class DetailRepositoryTest {
    @Test fun scopeCriterionLikeIos() {
        assertEquals(
            """{"performers":{"value":["7"],"modifier":"INCLUDES"}}""",
            DetailRepository.scope("performers", "7").toString(),
        )
    }

    @Test fun mutationVariablesKeepNulls() {
        // iOS sends NSNull for cleared optional fields so Stash actually clears them.
        assertEquals(
            """{"input":{"id":"1","url":null}}""",
            vars("input" to mapOf("id" to "1", "url" to null)).toString(),
        )
    }
}
