package de.letzgo.stashy.data.tools

import de.letzgo.stashy.data.GraphQL
import de.letzgo.stashy.data.Json
import de.letzgo.stashy.data.Net
import de.letzgo.stashy.data.Page
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.ServerConfigManager
import de.letzgo.stashy.data.obj
import de.letzgo.stashy.data.stringOrNull
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * iOS: the network side of `HotOrNotViewModel` + `HotOrNotBattleDisplay`
 * (`stashy/HotOrNotToolsView.swift`): `hotOrNotFindPerformers` queries, the persisted pool
 * settings and the `performerUpdate` mutation that writes `rating100` and the Ascension
 * `custom_fields`.
 */
object MatchRepository {
    /** iOS `UserDefaults` keys (global, not per server — same as iOS). */
    const val GENDERS_KEY = "stashy.hotOrNot.selectedGenders"
    const val DUEL_MODE_KEY = "stashy.hotOrNot.duelMode"

    /** iOS: `HotOrNotLeaderboardPaging.perPage`. */
    const val LEADERBOARD_PER_PAGE = 50

    private const val DOCUMENT = "hotOrNotFindPerformers"

    private val UPDATE_MUTATION = """
        mutation HotOrNotPerformerUpdate(${'$'}input: PerformerUpdateInput!) {
          performerUpdate(input: ${'$'}input) { id rating100 }
        }
    """

    /** iOS: `HotOrNotPoolSettingsView.genderRows`. */
    val genderRows: List<Pair<String, String>> = listOf(
        "FEMALE" to "Female",
        "MALE" to "Male",
        "TRANSGENDER_FEMALE" to "Transgender (female)",
        "TRANSGENDER_MALE" to "Transgender (male)",
        "NON_BINARY" to "Non-binary",
        "INTERSEX" to "Intersex",
    )

    // MARK: Prefs

    /** iOS: `HotOrNotBattleDisplay.loadGenders()` — JSON array of gender codes, default `FEMALE`. */
    fun loadGenders(): Set<String> {
        val raw = Prefs.string(GENDERS_KEY) ?: return setOf("FEMALE")
        val list = runCatching { Json.decodeFromString(ListSerializer(String.serializer()), raw) }.getOrNull()
        return list?.takeIf { it.isNotEmpty() }?.toSet() ?: setOf("FEMALE")
    }

    /** iOS: `saveGenders` — sorted JSON array. */
    fun saveGenders(genders: Set<String>) {
        Prefs.setString(GENDERS_KEY, JsonArray(genders.sorted().map { JsonPrimitive(it) }).toString())
    }

    fun loadDuelMode(): MatchDuelMode = MatchDuelMode.migrating(Prefs.string(DUEL_MODE_KEY))
    fun saveDuelMode(mode: MatchDuelMode) = Prefs.setString(DUEL_MODE_KEY, mode.raw)

    // MARK: Queries

    /** iOS: `performerFilter` — selected genders, performers with an image only. */
    fun performerFilter(genders: Set<String>): JsonObject = buildJsonObject {
        put("gender", buildJsonObject {
            put("value_list", JsonArray(genders.sorted().map { JsonPrimitive(it) }))
            put("modifier", JsonPrimitive("INCLUDES"))
        })
        put("NOT", buildJsonObject { put("is_missing", JsonPrimitive("image")) })
    }

    private suspend fun find(genders: Set<String>, filter: JsonObject): Page<Performer> {
        val data = GraphQL.named(DOCUMENT, buildJsonObject {
            put("performer_filter", performerFilter(genders))
            put("filter", filter)
        })
        val obj = data["findPerformers"].obj ?: return Page(0, emptyList())
        val list = obj["performers"]?.let { GraphQL.decode(ListSerializer(Performer.serializer()), it) }.orEmpty()
        val count = obj["count"].stringOrNull?.toIntOrNull() ?: list.size
        return Page(count, list)
    }

    private fun filter(vararg pairs: Pair<String, Any>): JsonObject = buildJsonObject {
        pairs.forEach { (k, v) ->
            put(k, when (v) { is Int -> JsonPrimitive(v); else -> JsonPrimitive(v.toString()) })
        }
    }

    /** Whole pool by rating (`per_page: -1`) — used for every duel pairing. */
    suspend fun pool(genders: Set<String>): Page<Performer> =
        find(genders, filter("per_page" to -1, "sort" to "rating", "direction" to "DESC"))

    /** iOS: `preparePlacementStarters` source — 100 random performers. */
    suspend fun starterCandidates(genders: Set<String>): Page<Performer> =
        find(genders, filter("per_page" to 100, "sort" to "random"))

    /** iOS: `refreshLeaderboard` / `loadMoreLeaderboard` — Charts page (1-based). */
    suspend fun leaderboardPage(genders: Set<String>, page: Int): Page<Performer> =
        find(genders, filter("page" to page, "per_page" to LEADERBOARD_PER_PAGE, "sort" to "rating", "direction" to "DESC"))

    /**
     * iOS: `HotOrNotBattleDisplay.fetchRankSlashTotal(performerId:)` — `"rank/total"` of a
     * performer in the Match pool (Performer detail header), or null when not listed / on error.
     */
    suspend fun fetchRankSlashTotal(performerId: String): String? {
        val genders = loadGenders()
        val perPage = LEADERBOARD_PER_PAGE
        var totalCount = 0
        var page = 1
        try {
            while (true) {
                val res = leaderboardPage(genders, page)
                val list = res.items
                if (page == 1) totalCount = res.count
                val idx = list.indexOfFirst { it.id == performerId }
                if (idx >= 0) {
                    val rank = (page - 1) * perPage + idx + 1
                    return "$rank/${maxOf(totalCount, rank)}"
                }
                if (list.size < perPage || page * perPage >= totalCount) break
                page++
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            return null
        }
        return null
    }

    /** iOS: `thumbnailURL(for:)` — absolute `image_path`, else `<base>/performer/<id>/image`, signed. */
    fun thumbnailURL(p: Performer): String? {
        val path = p.imagePath
        val bust = { url: String -> Net.signed(de.letzgo.stashy.data.ImageBusters.apply(url, de.letzgo.stashy.data.ImageBusters.Kind.Performer, p.id)) }
        if (path != null && (path.startsWith("http://") || path.startsWith("https://"))) return bust(path)
        val config = ServerConfigManager.activeConfig?.takeIf { it.hasValidConfig } ?: return null
        return bust("${config.baseURL}/performer/${p.id}/image")
    }

    // MARK: Mutation

    /**
     * iOS: `pushPerformerUpdate(performer:newRating:won:opponentId:opponentName:)` — writes
     * `rating100` plus `custom_fields.partial` (`hotornot_stats`, `performer_record`).
     */
    suspend fun pushPerformerUpdate(performer: Performer, newRating: Int, won: Boolean?, opponentId: String, opponentName: String) {
        val input = MatchElo.buildPerformerUpdate(performer, newRating, won, opponentId, opponentName)
        val data = GraphQL.data(UPDATE_MUTATION.trimIndent(), buildJsonObject { put("input", input) })
        if (data["performerUpdate"] !is JsonObject) throw Exception("Update failed")
    }
}
