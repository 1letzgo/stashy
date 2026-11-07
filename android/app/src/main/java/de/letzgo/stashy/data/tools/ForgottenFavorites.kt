package de.letzgo.stashy.data.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.StashyPlus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

/** iOS: `ForgottenFavoritesRanking` (raw values identical). */
enum class ForgottenFavoritesRanking(val raw: String, val title: String, val detail: String) {
    Plays("plays", "Plays", "Favorites are your most played scenes."),
    OCount("oCount", "O-Count", "Favorites are your scenes with the highest O-Count."),
    Both("both", "Both", "Favorites are your most played scenes and those with the highest O-Count.");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Both }
}

/** iOS: `ForgottenFavorite`. */
data class ForgottenFavorite(val scene: Scene, val lastPlayed: Long?, val plays: Int, val oCount: Int) {
    val id: String get() = scene.id

    /** Below the card: how long it has been. */
    val label: String get() {
        val last = lastPlayed ?: return if (plays == 0) "Never played" else "Not played in a long time"
        val days = ((System.currentTimeMillis() - last) / 86_400_000L).coerceAtLeast(0).toInt()
        return when {
            days < 60 -> "Last played $days days ago"
            days < 730 -> "Last played ${days / 30} months ago"
            else -> "Last played ${days / 365} years ago"
        }
    }
}

enum class ForgottenFavoritesState { Idle, Loading, Ready, Preparing }

/**
 * iOS: `ForgottenFavoritesEngine` (stashy+) — scenes among the most played or most O-Counted
 * that have not been played for a while, from the local scene index alone.
 */
object ForgottenFavorites {
    private const val KEY_ENABLED = "forgotten_favorites_enabled"
    private const val KEY_DAYS = "forgotten_favorites_days"
    private const val KEY_POOL = "forgotten_favorites_pool"
    private const val KEY_RANKING = "forgotten_favorites_ranking"

    val dayChoices = listOf(30, 60, 90, 180, 365)
    val poolChoices = listOf(10, 25, 50, 100)
    /** At most this many cards in the row. */
    const val ROW_LIMIT = 20

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var isEnabled by mutableStateOf(Prefs.bool(KEY_ENABLED, true)); private set
    var days by mutableStateOf(Prefs.int(KEY_DAYS, 60).takeIf { it in dayChoices } ?: 60); private set
    var pool by mutableStateOf(Prefs.int(KEY_POOL, 25).takeIf { it in poolChoices } ?: 25); private set
    var ranking by mutableStateOf(ForgottenFavoritesRanking.fromRaw(Prefs.string(KEY_RANKING))); private set

    fun updateEnabled(v: Boolean) { isEnabled = v; Prefs.setBool(KEY_ENABLED, v); if (!v) reset() }
    fun updateDays(v: Int) { days = v; Prefs.setInt(KEY_DAYS, v); settingsChanged() }
    fun updatePool(v: Int) { pool = v; Prefs.setInt(KEY_POOL, v); settingsChanged() }
    fun updateRanking(v: ForgottenFavoritesRanking) { ranking = v; Prefs.setString(KEY_RANKING, v.raw); settingsChanged() }

    val hasCustomSettings: Boolean get() = days != 60 || pool != 25 || ranking != ForgottenFavoritesRanking.Both
    fun resetSettings() { updateDays(60); updatePool(25); updateRanking(ForgottenFavoritesRanking.Both) }

    var items by mutableStateOf<List<ForgottenFavorite>>(emptyList()); private set
    var state by mutableStateOf(ForgottenFavoritesState.Idle); private set
    /** How many scenes made the favourites pool — shown in Settings. */
    var poolCount by mutableStateOf(0); private set

    val hasStatistics: Boolean get() = AITagSuggestions.isEnabled || SimilarScenes.isEnabled
    val isFeatureOn: Boolean get() = isEnabled && hasStatistics
    val isAvailable: Boolean get() = StashyPlus.isUnlocked && isFeatureOn
    /** Built and nothing forgotten: Home leaves the row out. */
    val isEmptyAndReady: Boolean get() = state == ForgottenFavoritesState.Ready && items.isEmpty()

    private var job: Job? = null
    private var generation = 0
    private var builtForServer: String? = null

    fun reset() {
        job?.cancel(); job = null
        generation++
        items = emptyList(); poolCount = 0
        state = ForgottenFavoritesState.Idle
    }

    /** Within a session the row stays as it is; only an empty one (or a new server) builds. */
    fun refreshIfNeeded() {
        if (!isAvailable) return
        val server = ServerConfigManager.activeConfig?.id
        if (server != builtForServer) { reset(); builtForServer = server }
        if (job != null || state != ForgottenFavoritesState.Idle) return
        rebuild()
    }

    /** A statistics build finished: a row still waiting for the first index fills now. */
    fun onIndexBuilt() {
        if (state == ForgottenFavoritesState.Preparing) rebuild()
    }

    private fun settingsChanged() {
        if (state != ForgottenFavoritesState.Idle) rebuild()
    }

    fun rebuild() {
        if (!isAvailable) return
        job?.cancel()
        val gen = ++generation
        if (items.isEmpty()) state = ForgottenFavoritesState.Loading
        val days = days; val pool = pool; val ranking = ranking
        val recent = loadRecentPicks()
        job = scope.launch {
            AITagSuggestions.loadIfNeeded()
            val index = AITagSuggestions.sceneIndex()?.takeIf { it.scenes.isNotEmpty() }
            if (gen != generation) return@launch
            if (index == null) {
                items = emptyList(); poolCount = 0
                state = ForgottenFavoritesState.Preparing
                job = null
                scope.launch { AITagSuggestions.ensureStatistics() }
                return@launch
            }
            val (picked, count) = withContext(Dispatchers.Default) { pickForgottenFavorites(index.scenes, days, pool, ranking, recent) }
            if (gen != generation) return@launch
            items = picked; poolCount = count
            // Shown now: these step back in the next lists.
            saveRecentPicks(picked.map { it.id }, recent)
            state = ForgottenFavoritesState.Ready
            job = null
        }
    }

    /** Pull to refresh on Home: the index may have new plays since the last list. */
    suspend fun rebuildAndWait() {
        withContext(Dispatchers.Main) { rebuild() }
        job?.join()
    }

    // MARK: Recent lists (iOS `loadRecentPicks` / `saveRecentPicks`), device-local, one per server.

    private const val LAST_PICKS_PREFIX = "forgotten_favorites_last_picks_"
    private const val REMEMBERED_LISTS = 3
    private val lastPicksKey: String? get() = ServerConfigManager.activeConfig?.id?.let { "$LAST_PICKS_PREFIX$it" }

    private fun loadRecentPicks(): List<Set<String>> {
        val raw = lastPicksKey?.let(Prefs::string) ?: return emptyList()
        return runCatching {
            de.letzgo.stashy.data.Json.decodeFromString(ListSerializer(ListSerializer(String.serializer())), raw).map { it.toSet() }
        }.getOrDefault(emptyList())
    }

    private fun saveRecentPicks(ids: List<String>, previous: List<Set<String>>) {
        val key = lastPicksKey ?: return
        if (ids.isEmpty()) return
        val lists = listOf(ids) + previous.take(REMEMBERED_LISTS - 1).map { it.toList() }
        Prefs.setString(key, de.letzgo.stashy.data.Json.encodeToString(ListSerializer(ListSerializer(String.serializer())), lists))
    }
}

/**
 * iOS `ForgottenFavoritesEngine.pick`: the favourites pool (top [pool] per ranking), minus everything
 * played within [days]. Like For You, each build draws a new random order and scenes shown in the
 * [recent] lists go to the back, so app start and pull to refresh bring others.
 */
fun pickForgottenFavorites(
    scenes: List<LocalSceneIndex.Entry>, days: Int, pool: Int, ranking: ForgottenFavoritesRanking,
    recent: List<Set<String>> = emptyList(),
    nowMillis: Long = System.currentTimeMillis(),
    random: kotlin.random.Random = kotlin.random.Random.Default,
): Pair<List<ForgottenFavorite>, Int> {
    val rank = HashMap<String, Int>()
    fun take(ranked: List<LocalSceneIndex.Entry>) {
        ranked.take(pool).forEachIndexed { position, e -> rank[e.id] = minOf(rank[e.id] ?: Int.MAX_VALUE, position) }
    }
    if (ranking != ForgottenFavoritesRanking.OCount) {
        take(scenes.filter { it.pc > 0 }.sortedWith(compareByDescending<LocalSceneIndex.Entry> { it.pc }.thenByDescending { it.oc }))
    }
    if (ranking != ForgottenFavoritesRanking.Plays) {
        take(scenes.filter { it.oc > 0 }.sortedWith(compareByDescending<LocalSceneIndex.Entry> { it.oc }.thenByDescending { it.pc }))
    }
    val cutoff = nowMillis - days * 86_400_000L
    val byId = scenes.associateBy { it.id }
    val forgotten = rank.mapNotNull { (id, position) ->
        val e = byId[id] ?: return@mapNotNull null
        if (e.scene == null) return@mapNotNull null
        if (e.lp != null && e.lp > cutoff) return@mapNotNull null
        e to position
    }
        // Shown in fewer recent lists first, random within each group.
        .map { (e, _) -> Triple(e, recent.count { e.id in it }, random.nextDouble()) }
        .sortedWith(compareBy<Triple<LocalSceneIndex.Entry, Int, Double>> { it.second }.thenBy { it.third })
        .take(ForgottenFavorites.ROW_LIMIT)
        .map { (e, _, _) -> ForgottenFavorite(e.scene!!, e.lp, e.pc, e.oc) }
    return forgotten to rank.size
}
