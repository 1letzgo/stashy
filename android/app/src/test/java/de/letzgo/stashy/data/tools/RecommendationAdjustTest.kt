package de.letzgo.stashy.data.tools

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecommendationAdjustTest {
    private fun adj(kind: RecommendationAdjustment.Kind, id: String, factor: Double) =
        RecommendationAdjustment(kind, id, id, factor)

    @Test fun hiddenItemHidesTheScene() {
        val a = RecommendationAdjust(listOf(adj(RecommendationAdjustment.Kind.Studio, "s1", 0.0)))
        assertTrue(a.hides(listOf("p1"), "s1", listOf("t1")))
        assertFalse(a.hides(listOf("p1"), "s2", listOf("t1")))
    }

    @Test fun factorsMultiplyAndAreClamped() {
        val a = RecommendationAdjust(listOf(
            adj(RecommendationAdjustment.Kind.Performer, "p1", 2.0),
            adj(RecommendationAdjustment.Kind.Tag, "t1", 0.5),
        ))
        assertEquals(1.0, a.multiplier(listOf("p1"), null, listOf("t1")), 1e-9)
        assertEquals(2.0, a.multiplier(listOf("p1"), null, emptyList()), 1e-9)
        val big = RecommendationAdjust(listOf(
            adj(RecommendationAdjustment.Kind.Performer, "p1", 3.0),
            adj(RecommendationAdjustment.Kind.Performer, "p2", 3.0),
        ))
        assertEquals(8.0, big.multiplier(listOf("p1", "p2"), null, emptyList()), 1e-9)
    }

    @Test fun boostPutsTurnedUpItemsInTheProfile() {
        val a = RecommendationAdjust(listOf(
            adj(RecommendationAdjustment.Kind.Performer, "p1", 3.0),
            adj(RecommendationAdjustment.Kind.Tag, "t1", 2.0),
            adj(RecommendationAdjustment.Kind.Studio, "s1", 0.5),
        ))
        val performers = HashMap<String, Double>(); val studios = HashMap<String, Double>(); val tags = HashMap<String, Double>()
        a.boost(performers, studios, tags)
        assertEquals(1.0, performers["p1"]!!, 1e-9)
        assertEquals(0.125, tags["t1"]!!, 1e-9)
        assertFalse("s1" in studios)
    }

    @Test fun jsonMatchesIos() {
        val json = de.letzgo.stashy.data.Json.encodeToString(RecommendationAdjustment.serializer(), adj(RecommendationAdjustment.Kind.Tag, "7", 1.5))
        assertTrue(json, json.contains("\"kind\":\"tag\""))
        assertTrue(json, json.contains("\"itemId\":\"7\""))
    }
}
