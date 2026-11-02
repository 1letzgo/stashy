package de.letzgo.stashy.data

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The catalog sheet's mini search field ("Name or regex"): a live chip criterion on the entity's
 * name / title, `{ value: "(?i)<input>", modifier: MATCHES_REGEX }` (Stash evaluates Go RE2).
 * Input is validated locally first; invalid patterns are never sent.
 */
object NameRegexFilter {
    const val CASE_INSENSITIVE_PREFIX = "(?i)"
    const val MODIFIER = "MATCHES_REGEX"

    /** Criterion key per mode; `null` where the filter type has no name/title (markers). */
    fun key(mode: FilterMode): String? = when (mode) {
        FilterMode.Performers, FilterMode.Studios, FilterMode.Tags, FilterMode.Groups -> "name"
        FilterMode.Scenes, FilterMode.Galleries, FilterMode.Images -> "title"
        FilterMode.SceneMarkers, FilterMode.Unknown -> null
    }

    fun isSupported(mode: FilterMode): Boolean = key(mode) != null

    /** Trimmed input; blank means "no filter". */
    fun normalized(input: String): String = input.trim()

    /** True when [input] is blank (clears the filter) or compiles as a case-insensitive pattern. */
    fun isValid(input: String): Boolean {
        val text = normalized(input)
        if (text.isEmpty()) return true
        return runCatching { Regex(CASE_INSENSITIVE_PREFIX + text) }.isSuccess
    }

    /** `{ value: "(?i)<input>", modifier: MATCHES_REGEX }`, or `null` for blank / invalid input. */
    fun criterion(input: String): JsonObject? {
        val text = normalized(input)
        if (text.isEmpty() || !isValid(text)) return null
        return JsonObject(mapOf("value" to JsonPrimitive(CASE_INSENSITIVE_PREFIX + text), "modifier" to JsonPrimitive(MODIFIER)))
    }

    /**
     * Tags (iOS `searchesAliases`): Stash's `name` criterion ignores aliases, so the field there
     * writes `AND: { name: R, OR: { aliases: R } }` instead of a root `name` — inside AND, so it
     * stays ANDed with every other criterion (a root `OR` would be "all the rest OR alias").
     */
    fun searchesAliases(mode: FilterMode): Boolean = mode == FilterMode.Tags

    const val ALIAS_GROUP_KEY = "AND"
    const val ALIASES_KEY = "aliases"

    /** The pattern (without `(?i)`) of a chip-shaped criterion, else `null`. */
    private fun ownedPattern(element: JsonElement?): String? {
        val c = element as? JsonObject ?: return null
        if ((c["modifier"] as? JsonPrimitive)?.content != MODIFIER) return null
        val value = (c["value"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        if (!value.startsWith(CASE_INSENSITIVE_PREFIX)) return null
        return value.removePrefix(CASE_INSENSITIVE_PREFIX)
    }

    /**
     * iOS `aliasSearchPattern`: the field's pattern when [dict]'s root `AND` is exactly the alias
     * search group `{ name: R, OR: { aliases: R } }` (tags only), else `null`.
     */
    fun aliasSearchPattern(mode: FilterMode, dict: JsonObject): String? {
        if (!searchesAliases(mode)) return null
        val key = key(mode) ?: return null
        val group = dict[ALIAS_GROUP_KEY] as? JsonObject ?: return null
        if (group.keys != setOf(key, "OR")) return null
        val pattern = ownedPattern(group[key]) ?: return null
        val alt = group["OR"] as? JsonObject ?: return null
        if (alt.keys != setOf(ALIASES_KEY) || ownedPattern(alt[ALIASES_KEY]) != pattern) return null
        return pattern
    }

    /** True when the alias group may take the root `AND` of [criteria] (free, or already the field's). */
    private fun aliasGroupFits(mode: FilterMode, criteria: JsonObject): Boolean =
        searchesAliases(mode) && (ALIAS_GROUP_KEY !in criteria || aliasSearchPattern(mode, criteria) != null)

    /**
     * Chip fragment for [mode]; empty when unsupported, blank or invalid. Usually `{ <key>: criterion }`;
     * for tags `{ AND: { name: criterion, OR: { aliases: criterion } } }` as long as the [criteria] it
     * is layered on have no root `AND` of their own — otherwise the plain `name` regex (fallback).
     */
    fun chip(mode: FilterMode, input: String, criteria: JsonObject = JsonObject(emptyMap())): JsonObject {
        val key = key(mode) ?: return JsonObject(emptyMap())
        val c = criterion(input) ?: return JsonObject(emptyMap())
        if (aliasGroupFits(mode, criteria)) {
            val group = JsonObject(mapOf(key to c, "OR" to JsonObject(mapOf(ALIASES_KEY to c))))
            return JsonObject(mapOf(ALIAS_GROUP_KEY to group))
        }
        return JsonObject(mapOf(key to c))
    }

    /**
     * Pulls a chip-shaped criterion (MATCHES_REGEX with the `(?i)` prefix) back out of a loaded
     * preset / saved filter: returns the field text and the remaining criteria. Anything else on
     * that key stays in the criteria for the advanced editor.
     */
    fun extract(mode: FilterMode, dict: JsonObject): Pair<String, JsonObject> {
        val key = key(mode) ?: return "" to dict
        // Tags: the alias search group goes back into the field as a whole.
        aliasSearchPattern(mode, dict)?.let { pattern ->
            val text = normalized(pattern)
            if (text.isNotEmpty() && isValid(text)) {
                return text to JsonObject(LinkedHashMap<String, JsonElement>(dict).apply { remove(ALIAS_GROUP_KEY) })
            }
        }
        val text = normalized(ownedPattern(dict[key]) ?: return "" to dict)
        if (text.isEmpty() || !isValid(text)) return "" to dict
        val rest = LinkedHashMap<String, JsonElement>(dict).apply { remove(key) }
        return text to JsonObject(rest)
    }

    /**
     * `base` with the chip on top (chip wins for its key). [criteria] are the editor criteria the
     * result is merged onto later; they decide whether the tags chip may use the root `AND`.
     */
    fun layered(base: JsonObject, mode: FilterMode, input: String, criteria: JsonObject = JsonObject(emptyMap())): JsonObject {
        val chip = chip(mode, input, criteria)
        if (chip.isEmpty()) return base
        return JsonObject(LinkedHashMap<String, JsonElement>(base).apply { putAll(chip) })
    }
}
