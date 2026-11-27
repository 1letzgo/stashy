package de.letzgo.stashy.tv

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stashy.data.CatalogQuery
import de.letzgo.stashy.data.FilterMode
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.SortCatalog
import de.letzgo.stashy.data.resolvedSort
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/** iOS: `TVChannel.Scope` — entity-scoped channels, keyed by the scene-filter field. */
enum class TvChannelScope(val raw: String, @androidx.annotation.StringRes private val labelRes: Int) {
    Performer("performers", R.string.performer), Studio("studios", R.string.studio), Tag("tags", R.string.tag), Group("groups", R.string.group);
    /** Read on use: a constant must not freeze its text at class load. */
    val label: String get() = tr(labelRes)

    /** Everything but `performers` is a `HierarchicalMultiCriterionInput` (needs `depth`). */
    val isHierarchical: Boolean get() = this != Performer
}

/**
 * iOS: `TVChannel` — a built-in sort, a saved scene filter, or every scene of one performer,
 * studio, tag or group (stashy+). Like on iOS it is a starting point for Feeds (Scenes with the
 * channel's filter and sort, [feedStart] → [TvChannelFeedRoute]), not a player of its own.
 */
data class TvChannel(
    val kind: Kind,
    val title: String,
    val savedFilter: SavedFilter? = null,
    val scope: TvChannelScope? = null,
    val entityId: String? = null,
) {
    enum class Kind { RecentlyReleased, RecentlyAdded, SavedFilter, Scoped }

    val id: String get() = when (kind) {
        Kind.RecentlyReleased -> "channel.recentlyReleased"
        Kind.RecentlyAdded -> "channel.recentlyAdded"
        Kind.SavedFilter -> "channel.filter.${savedFilter?.id ?: title}"
        Kind.Scoped -> "channel.${scope?.raw}.$entityId"
    }

    val sortRaw: String get() = when (kind) {
        Kind.RecentlyAdded -> "createdAtDesc"
        Kind.SavedFilter -> savedFilter?.resolvedSort(FilterMode.Scenes)?.raw ?: "dateDesc"
        else -> "dateDesc"
    }

    val subtitle: String get() = when (kind) {
        Kind.SavedFilter -> tr(R.string.saved_filter)
        Kind.Scoped -> scope?.label ?: tr(R.string.channel)
        else -> tr(R.string.channel)
    }

    /** Ad-hoc scene filter of an entity channel (it has no counterpart on the server). */
    fun scopeFilter(): JsonObject? {
        if (kind != Kind.Scoped) return null
        val s = scope ?: return null
        val id = entityId ?: return null
        val criterion = buildJsonObject {
            put("modifier", JsonPrimitive("INCLUDES"))
            put("value", JsonArray(listOf(JsonPrimitive(id))))
            if (s.isHierarchical) put("depth", JsonPrimitive(0))
        }
        return buildJsonObject { put(s.raw, criterion) }
    }

    /** iOS `feedStart` — what the channel hands to Feeds: its saved filter or entity criterion, and its sort. */
    val feedStart: TvFeedChannelStart
        get() = TvFeedChannelStart(id, title, if (kind == Kind.SavedFilter) savedFilter else null, scopeFilter(), sortRaw)

    /** The channel's scenes as a catalog query (Dashboard channel previews). */
    fun query(): CatalogQuery = CatalogQuery(
        mode = FilterMode.Scenes,
        sort = SortCatalog.option(FilterMode.Scenes, sortRaw) ?: SortCatalog.option(FilterMode.Scenes, "dateDesc")!!,
        base = if (kind == Kind.SavedFilter) savedFilter else null,
        scope = scopeFilter(),
    )

    companion object {
        val recentlyReleased = TvChannel(Kind.RecentlyReleased, tr(R.string.recently_released))
        val recentlyAdded = TvChannel(Kind.RecentlyAdded, tr(R.string.recently_added))
        fun savedFilter(filter: SavedFilter) = TvChannel(Kind.SavedFilter, filter.name, savedFilter = filter)
        fun performer(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Performer, entityId = id)
        fun studio(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Studio, entityId = id)
        fun tag(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Tag, entityId = id)
        fun group(id: String, name: String) = TvChannel(Kind.Scoped, name, scope = TvChannelScope.Group, entityId = id)
    }
}

val TvChannel.icon: ImageVector get() = when (kind) {
    TvChannel.Kind.RecentlyReleased -> TvIcons.sparklesTv
    TvChannel.Kind.RecentlyAdded -> TvIcons.plusFolder
    TvChannel.Kind.SavedFilter -> TvIcons.filterFill
    TvChannel.Kind.Scoped -> when (scope) {
        TvChannelScope.Performer -> TvIcons.person
        TvChannelScope.Studio -> TvIcons.building
        TvChannelScope.Tag -> TvIcons.tag
        else -> TvIcons.stack
    }
}
