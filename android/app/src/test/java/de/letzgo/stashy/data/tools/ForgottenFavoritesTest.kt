package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.Scene
import org.junit.Assert.assertEquals
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
        assertEquals(listOf("topOOld", "topPlaysOld"), items.map { it.id })
    }

    @Test fun playsOnlyAndLongerWindow() {
        val (items, _) = pickForgottenFavorites(scenes, days = 150, pool = 4, ranking = ForgottenFavoritesRanking.Plays, nowMillis = now)
        assertEquals(listOf("topPlaysOld", "midOld"), items.map { it.id })
    }

    @Test fun oCountOnly() {
        val (items, pool) = pickForgottenFavorites(scenes, days = 30, pool = 10, ranking = ForgottenFavoritesRanking.OCount, nowMillis = now)
        assertEquals(2, pool)
        assertEquals(listOf("topOOld", "topPlaysOld"), items.map { it.id })
    }
}
