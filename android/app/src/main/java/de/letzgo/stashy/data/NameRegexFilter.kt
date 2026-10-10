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

    /** Chip fragment `{ <key>: criterion }` for [mode]; empty when unsupported, blank or invalid. */
    fun chip(mode: FilterMode, input: String): JsonObject {
        val key = key(mode) ?: return JsonObject(emptyMap())
        val c = criterion(input) ?: return JsonObject(emptyMap())
        return JsonObject(mapOf(key to c))
    }

    /**
     * Pulls a chip-shaped criterion (MATCHES_REGEX with the `(?i)` prefix) back out of a loaded
     * preset / saved filter: returns the field text and the remaining criteria. Anything else on
     * that key stays in the criteria for the advanced editor.
     */
    fun extract(mode: FilterMode, dict: JsonObject): Pair<String, JsonObject> {
        val key = key(mode) ?: return "" to dict
        val c = dict[key] as? JsonObject ?: return "" to dict
        if ((c["modifier"] as? JsonPrimitive)?.content != MODIFIER) return "" to dict
        val value = (c["value"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return "" to dict
        if (!value.startsWith(CASE_INSENSITIVE_PREFIX)) return "" to dict
        val text = normalized(value.removePrefix(CASE_INSENSITIVE_PREFIX))
        if (text.isEmpty() || !isValid(text)) return "" to dict
        val rest = LinkedHashMap<String, JsonElement>(dict).apply { remove(key) }
        return text to JsonObject(rest)
    }

    /** `base` with the chip on top (chip wins for its key). */
    fun layered(base: JsonObject, mode: FilterMode, input: String): JsonObject {
        val chip = chip(mode, input)
        if (chip.isEmpty()) return base
        return JsonObject(LinkedHashMap<String, JsonElement>(base).apply { putAll(chip) })
    }
}
