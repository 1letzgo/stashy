package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.ln

class SimilarScenesScoringTest {

    private fun scene(id: String, performers: List<String> = emptyList(), tags: List<Tag> = emptyList(), studio: String? = null) = Scene(
        id = id,
        performers = performers.map { Performer(id = it) },
        tags = tags,
        studio = studio?.let { Studio(id = it) },
    )

    private val niche = Tag(id = "niche", sceneCount = 1)
    private val common = Tag(id = "common", sceneCount = 100)
    private val mid = Tag(id = "mid", sceneCount = 10)

    @Test
    fun rarityIsNormalisedIdfWithFloor() {
        assertEquals(1.0, SimilarScenesScoring.rarity(1, 100), 1e-9)
        assertEquals(0.5, SimilarScenesScoring.rarity(10, 100), 1e-9)
        assertEquals(1.0, SimilarScenesScoring.rarity(null, 100), 1e-9)
        assertEquals(SimilarScenesScoring.MIN_RARITY, SimilarScenesScoring.rarity(100, 100), 1e-9)
        assertEquals(SimilarScenesScoring.MIN_RARITY, SimilarScenesScoring.rarity(99, 100), 1e-9)
        assertEquals(SimilarScenesScoring.MIN_RARITY, SimilarScenesScoring.rarity(1, 1), 1e-9)
        assertEquals(ln(50.0) / ln(100.0), SimilarScenesScoring.rarity(2, 100), 1e-9)
    }

    @Test
    fun scoreWeightsPerformersTagsAndStudio() {
        val rarity = mapOf("mid" to 0.5)
        val candidate = scene("x", performers = listOf("p1", "p2"), tags = listOf(mid), studio = "s")
        val score = SimilarScenesScoring.score(candidate, setOf("p1", "p2", "p3"), setOf("mid"), rarity, "s", emptyMap())
        assertEquals(2 * 3.0 + 1.5 * 0.5 + 1.0, score, 1e-9)
    }

    @Test
    fun relatedBonusIsCapped() {
        val candidate = scene("x", tags = listOf(Tag(id = "r1"), Tag(id = "r2"), Tag(id = "r3")))
        val related = mapOf("r1" to 1.0, "r2" to 1.0, "r3" to 1.0)
        val score = SimilarScenesScoring.score(candidate, emptySet(), setOf("src"), emptyMap(), null, related)
        assertEquals(2.0 * 0.5, score, 1e-9)
        val small = SimilarScenesScoring.score(candidate, emptySet(), setOf("src"), emptyMap(), null, mapOf("r1" to 0.4))
        assertEquals(0.2, small, 1e-9)
    }

    @Test
    fun rankOrdersByScoreAndExcludesTheSource() {
        val source = scene("src", performers = listOf("p"), tags = listOf(niche, common), studio = "s")
        val candidates = listOf(
            source,
            scene("studioOnly", studio = "s"),                          // 1.0
            scene("performer", performers = listOf("p")),               // 3.0
            scene("nicheTag", tags = listOf(niche)),                    // 1.5
            scene("commonTag", tags = listOf(common)),                  // 1.5 · 0.15
            scene("nothing", performers = listOf("other")),             // 0 → dropped
        )
        val ranked = SimilarScenesScoring.rank(
            candidates, setOf("p"), source.tags!!, "s", totalScenes = 100, excludingSceneId = "src",
        )
        assertEquals(listOf("performer", "nicheTag", "studioOnly", "commonTag"), ranked.map { it.id })
        assertTrue(ranked.none { it.id == "src" })
    }

    @Test
    fun tiesBreakByIdAndMaxCountLimits() {
        val candidates = listOf("c", "a", "b").map { scene(it, studio = "s") }
        val ranked = SimilarScenesScoring.rank(candidates, emptySet(), emptyList(), "s", 10, "src", maxCount = 2)
        assertEquals(listOf("a", "b"), ranked.map { it.id })
    }

    @Test
    fun relatedTagsLiftAnOtherwiseEqualCandidate() {
        val candidates = listOf(scene("a", studio = "s"), scene("b", studio = "s", tags = listOf(Tag(id = "rel"))))
        val ranked = SimilarScenesScoring.rank(candidates, emptySet(), listOf(Tag(id = "src")), "s", 10, "x", related = mapOf("rel" to 0.8))
        assertEquals(listOf("b", "a"), ranked.map { it.id })
    }

    @Test
    fun signatureDependsOnMetadataNotOrder() {
        val one = scene("1", performers = listOf("b", "a"), tags = listOf(Tag(id = "t2"), Tag(id = "t1")), studio = "s")
        val two = scene("1", performers = listOf("a", "b"), tags = listOf(Tag(id = "t1"), Tag(id = "t2")), studio = "s")
        assertEquals("1|p:a,b|t:t1,t2|s:s", SimilarScenesScoring.signature(one))
        assertEquals(SimilarScenesScoring.signature(one), SimilarScenesScoring.signature(two))
        assertTrue(SimilarScenesScoring.signature(scene("1")) != SimilarScenesScoring.signature(one))
    }
}
