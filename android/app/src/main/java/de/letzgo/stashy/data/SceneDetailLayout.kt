package de.letzgo.stashy.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * The cards below the (fixed) video player on the phone scene detail page, in their default
 * order. [id] is the stable key stored in prefs; [isHalfWidth] cards pair up side by side with an
 * adjacent half-width card in landscape.
 */
enum class SceneDetailCard(val id: String, val title: String, val isHalfWidth: Boolean = false) {
    Details("details", "Details"),
    Heatmap("heatmap", "Heatmap"),
    SimilarScenes("similarScenes", "Similar Scenes"),
    PerformersStudio("performersStudio", "Performers & Studio"),
    Groups("groups", "Groups", isHalfWidth = true),
    Tags("tags", "Tags", isHalfWidth = true),
    Galleries("galleries", "Galleries");

    companion object {
        val defaultOrder: List<SceneDetailCard> get() = entries
        fun fromId(id: String): SceneDetailCard? = entries.firstOrNull { it.id == id }
    }
}

/** Pure order/visibility logic (unit-tested). */
object SceneDetailLayoutLogic {
    /** Comma-separated ids → list (blank entries dropped). */
    fun parse(raw: String?): List<String> = raw.orEmpty().split(',').map { it.trim() }.filter { it.isNotEmpty() }

    fun encode(ids: List<String>): String = ids.joinToString(",")

    /**
     * Stored ids → full card order: known ids in stored order (duplicates dropped, unknown ids
     * ignored), then every card missing from the stored list appended in default order.
     */
    fun resolveOrder(stored: List<String>): List<SceneDetailCard> {
        val known = stored.mapNotNull { SceneDetailCard.fromId(it) }.distinct()
        return known + SceneDetailCard.defaultOrder.filter { it !in known }
    }

    fun resolveHidden(stored: List<String>): Set<SceneDetailCard> = stored.mapNotNull { SceneDetailCard.fromId(it) }.toSet()

    fun <T> move(list: List<T>, from: Int, to: Int): List<T> {
        if (from !in list.indices || to !in list.indices || from == to) return list
        return list.toMutableList().apply { add(to, removeAt(from)) }
    }

    /**
     * Visible cards grouped into layout rows: in landscape two adjacent half-width cards share a
     * row; everything else (and every card in portrait) gets a row of its own.
     */
    fun rows(order: List<SceneDetailCard>, hidden: Set<SceneDetailCard>, landscape: Boolean): List<List<SceneDetailCard>> {
        val visible = order.filter { it !in hidden }
        if (!landscape) return visible.map { listOf(it) }
        val rows = mutableListOf<List<SceneDetailCard>>()
        var i = 0
        while (i < visible.size) {
            val card = visible[i]
            val next = visible.getOrNull(i + 1)
            if (card.isHalfWidth && next?.isHalfWidth == true) { rows += listOf(card, next); i += 2 }
            else { rows += listOf(card); i += 1 }
        }
        return rows
    }
}

/** Settings › Design › Scene View — global (not per-server) card order and visibility. */
object SceneDetailLayout {
    private const val ORDER_KEY = "sceneDetailCardOrder"
    private const val HIDDEN_KEY = "sceneDetailHiddenCards"

    var order by mutableStateOf(SceneDetailLayoutLogic.resolveOrder(SceneDetailLayoutLogic.parse(Prefs.string(ORDER_KEY))))
        private set
    var hidden by mutableStateOf(SceneDetailLayoutLogic.resolveHidden(SceneDetailLayoutLogic.parse(Prefs.string(HIDDEN_KEY))))
        private set

    val isDefault: Boolean get() = order == SceneDetailCard.defaultOrder && hidden.isEmpty()

    fun move(from: Int, to: Int) {
        order = SceneDetailLayoutLogic.move(order, from, to)
        Prefs.setString(ORDER_KEY, SceneDetailLayoutLogic.encode(order.map { it.id }))
    }

    fun setVisible(card: SceneDetailCard, visible: Boolean) {
        hidden = if (visible) hidden - card else hidden + card
        Prefs.setString(HIDDEN_KEY, SceneDetailLayoutLogic.encode(SceneDetailCard.defaultOrder.filter { it in hidden }.map { it.id }))
    }

    fun reset() {
        order = SceneDetailCard.defaultOrder
        hidden = emptySet()
        Prefs.remove(ORDER_KEY)
        Prefs.remove(HIDDEN_KEY)
    }
}
