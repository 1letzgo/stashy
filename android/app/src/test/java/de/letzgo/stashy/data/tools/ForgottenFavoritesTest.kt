package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Scene
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ForgottenFavoritesTest {
    private val now = 1_800_000_000_000L
    private fun daysAgo(d: Int) = now - d * 86_400_000L
    private fun entry(id: String, pc: Int, oc: Int, lastPlayedDaysAgo: Int?) =
        LocalSceneIndex.Entry(id = id, pc = pc, oc = oc, lp = lastPlayedDaysAgo?.let(::daysAgo), scene = Scene(id = id))

    private val scenes = listOf(
        entry("topPlaysRecent", pc = 50, oc = 0, lastPlayedDaysAgo = 3),
        entry("topPlaysOld", pc = 40, oc = 1, lastPlayedDaysAgo = 200),
        entry("topOOld", pc = 2, oc = 9, lastPlayedDaysAgo = 120),
        entry("midOld", pc = 10, oc = 0, lastPlayedDaysAgo = 400),
        entry("neverPlayed", pc = 0, oc = 0, lastPlayedDaysAgo = null),
    )

    @Test fun bothRankingsSkipRecentlyPlayed() {
        val (items, pool) = pickForgottenFavorites(scenes, days = 60, pool = 2, ranking = ForgottenFavoritesRanking.Both, nowMillis = now)
        // Top 2 plays: topPlaysRecent, topPlaysOld; top 2 O: topOOld (rank 0), topPlaysOld (rank 1).
        assertEquals(3, pool)
        assertEquals(setOf("topOOld", "topPlaysOld"), items.map { it.id }.toSet())
    }

    @Test fun playsOnlyAndLongerWindow() {
        val (items, _) = pickForgottenFavorites(scenes, days = 150, pool = 4, ranking = ForgottenFavoritesRanking.Plays, nowMillis = now)
        assertEquals(setOf("topPlaysOld", "midOld"), items.map { it.id }.toSet())
    }

    @Test fun oCountOnly() {
        val (items, pool) = pickForgottenFavorites(scenes, days = 30, pool = 10, ranking = ForgottenFavoritesRanking.OCount, nowMillis = now)
        assertEquals(2, pool)
        assertEquals(setOf("topOOld", "topPlaysOld"), items.map { it.id }.toSet())
    }

    @Test fun recentlyShownGoToTheBack() {
        val many = (1..30).map { entry("s$it", pc = 100 - it, oc = 0, lastPlayedDaysAgo = 400) }
        val shown = many.take(20).map { it.id }.toSet()
        val (items, _) = pickForgottenFavorites(many, days = 60, pool = 30, ranking = ForgottenFavoritesRanking.Plays,
            recent = listOf(shown), nowMillis = now, random = kotlin.random.Random(1))
        // The 10 not shown last time come first, then 10 of the shown ones.
        assertEquals(many.drop(20).map { it.id }.toSet(), items.take(10).map { it.id }.toSet())
        assertEquals(20, items.size)
    }

    @Test fun orderChangesWithTheDraw() {
        val many = (1..30).map { entry("s$it", pc = 100 - it, oc = 0, lastPlayedDaysAgo = 400) }
        val a = pickForgottenFavorites(many, 60, 30, ForgottenFavoritesRanking.Plays, nowMillis = now, random = kotlin.random.Random(1)).first
        val b = pickForgottenFavorites(many, 60, 30, ForgottenFavoritesRanking.Plays, nowMillis = now, random = kotlin.random.Random(2)).first
        assertTrue(a.map { it.id } != b.map { it.id })
    }
}
