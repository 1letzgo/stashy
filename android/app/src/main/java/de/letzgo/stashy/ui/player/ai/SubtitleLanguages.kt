package de.letzgo.stashy.ui.player.ai

import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.ui.player.PlayerTrack
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.util.Locale

/**
 * iOS: `SubtitleTargetLanguage` (SharedUtilities.swift) — the user's subtitle / AI caption target
 * language (Settings › stashy+ › "My subtitle language"), same UserDefaults key. The pure helpers
 * take the stored value as a parameter so they stay unit-testable.
 */
object SubtitleTargetLanguage {
    const val STORAGE_KEY = "stashy_subtitle_target_language"

    val selectableLanguageCodes = listOf(
        "de", "en", "fr", "es", "it", "nl", "pt", "pl", "ru", "ja", "zh", "ko",
        "ar", "hi", "tr", "sv", "da", "nb", "fi", "cs", "hu", "uk", "el", "he", "vi", "th", "id", "ro",
    )

    /** iOS: `defaultLanguageCode` — the device's first preferred language. */
    val defaultLanguageCode: String get() = languageCode(Locale.getDefault().toLanguageTag()) ?: "en"

    fun load(): String = loadFrom(runCatching { Prefs.string(STORAGE_KEY) }.getOrNull())

    fun loadFrom(stored: String?, deviceDefault: String = defaultLanguageCode): String {
        val raw = stored?.trim().orEmpty()
        return if (raw.isNotEmpty()) normalized(raw, deviceDefault) else deviceDefault
    }

    fun normalized(code: String, deviceDefault: String = defaultLanguageCode): String {
        val trimmed = code.trim().lowercase()
        if (trimmed.isEmpty()) return deviceDefault
        val base = languageCode(trimmed) ?: trimmed
        return if (base in selectableLanguageCodes || base == deviceDefault) base else deviceDefault
    }

    fun persist(code: String) = Prefs.setString(STORAGE_KEY, normalized(code))

    /** iOS: `displayName(for:)` — localized with the device locale like iOS `Locale.current`. */
    fun displayName(code: String, display: Locale = Locale.getDefault()): String {
        val id = code.replace('_', '-')
        val name = Locale.forLanguageTag(id).let { if (id.contains('-')) it.getDisplayName(display) else it.getDisplayLanguage(display) }
        return name.takeIf { it.isNotEmpty() && !it.equals(id, ignoreCase = true) }
            ?.replaceFirstChar { it.titlecase(display) } ?: id.uppercase()
    }

    /** iOS: `pickerOptions()` — selectable + device default + stored, sorted by name. */
    fun pickerOptions(): List<Pair<String, String>> {
        val codes = (selectableLanguageCodes + defaultLanguageCode + load()).toSet()
        return codes.map { it to displayName(it) }.sortedBy { it.second }
    }

    /** iOS: `languageCode(from:)` — base subtag; 2- and 3-letter codes stay intact. */
    fun languageCode(identifier: String): String? {
        val id = identifier.lowercase().replace('_', '-')
        val dash = id.indexOf('-')
        if (dash >= 0) return id.substring(0, dash).ifEmpty { null }
        if (id.length == 2 || id.length == 3) return id
        return if (id.length >= 2) id.take(2) else id.ifEmpty { null }
    }

    private val languageAliases = mapOf(
        "german" to "de", "deutsch" to "de", "ger" to "de", "deu" to "de",
        "english" to "en", "englisch" to "en", "eng" to "en",
        "french" to "fr", "français" to "fr", "francais" to "fr", "französisch" to "fr", "fra" to "fr", "fre" to "fr",
        "spanish" to "es", "español" to "es", "espanol" to "es", "spanisch" to "es", "spa" to "es",
        "italian" to "it", "italiano" to "it", "italienisch" to "it", "ita" to "it",
        "dutch" to "nl", "nederlands" to "nl", "niederländisch" to "nl", "nld" to "nl", "dut" to "nl",
        "portuguese" to "pt", "português" to "pt", "portugues" to "pt", "portugiesisch" to "pt", "por" to "pt",
        "polish" to "pl", "polski" to "pl", "polnisch" to "pl", "pol" to "pl",
        "russian" to "ru", "russisch" to "ru", "rus" to "ru",
        "japanese" to "ja", "japanisch" to "ja", "jpn" to "ja",
        "chinese" to "zh", "mandarin" to "zh", "chinesisch" to "zh", "zho" to "zh", "chi" to "zh",
        "cantonese" to "yue", "kantonesisch" to "yue", "yue" to "yue", "cmn" to "zh",
        "korean" to "ko", "koreanisch" to "ko", "kor" to "ko",
        "arabic" to "ar", "arabisch" to "ar", "ara" to "ar",
        "hindi" to "hi", "hin" to "hi",
        "turkish" to "tr", "türkisch" to "tr", "türkçe" to "tr", "tur" to "tr",
        "swedish" to "sv", "svenska" to "sv", "schwedisch" to "sv", "swe" to "sv",
        "danish" to "da", "dansk" to "da", "dänisch" to "da", "dan" to "da",
        "norwegian" to "nb", "norsk" to "nb", "norwegisch" to "nb", "nor" to "nb",
        "finnish" to "fi", "suomi" to "fi", "finnisch" to "fi", "fin" to "fi",
        "czech" to "cs", "čeština" to "cs", "cestina" to "cs", "tschechisch" to "cs", "ces" to "cs", "cze" to "cs",
        "hungarian" to "hu", "magyar" to "hu", "ungarisch" to "hu", "hun" to "hu",
        "ukrainian" to "uk", "ukrainisch" to "uk", "ukr" to "uk",
        "greek" to "el", "griechisch" to "el", "ell" to "el", "gre" to "el",
        "hebrew" to "he", "hebräisch" to "he", "heb" to "he", "iw" to "he",
        "vietnamese" to "vi", "vietnamesisch" to "vi", "vie" to "vi",
        "thai" to "th", "thailändisch" to "th", "tha" to "th",
        "indonesian" to "id", "bahasa indonesia" to "id", "indonesisch" to "id", "ind" to "id",
        "romanian" to "ro", "rumänisch" to "ro", "romana" to "ro", "ron" to "ro", "rum" to "ro",
    )

    /** iOS: `canonicalCode(from:)` — `de`, `de-DE`, `German`, `deu` → ISO code, else null. */
    fun canonicalCode(raw: String?): String? {
        val value = raw?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        languageAliases[value]?.let { return it }
        val base = languageCode(value) ?: return null
        languageAliases[base]?.let { return it }
        return base.takeIf { (it.length == 2 || it.length == 3) && isKnownISOCode(it) }
    }

    /** iOS: `normalizedSceneLanguageTag(from:)` — keeps regions (`zh-CN`, `yue-CN`, `en-GB`). */
    fun normalizedSceneLanguageTag(raw: String?): String? {
        val value = raw?.trim()?.replace('_', '-')?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val sceneNames = mapOf(
            "cantonese" to "yue-CN", "kantonesisch" to "yue-CN", "yue" to "yue-CN",
            "chinese" to "zh-CN", "chinesisch" to "zh-CN", "mandarin" to "zh-CN", "zh" to "zh-CN",
        )
        sceneNames[value]?.let { return it }
        languageAliases[value]?.let { return it }
        val lang = languageCode(value) ?: value
        return value.takeIf { (lang.length == 2 || lang.length == 3) && isKnownISOCode(lang) }
    }

    private val iso2: Set<String> by lazy { Locale.getISOLanguages().toSet() }
    private val iso3: Set<String> by lazy { iso2.mapNotNull { runCatching { Locale(it).isO3Language }.getOrNull() }.toSet() }

    private fun isKnownISOCode(code: String): Boolean =
        code == "yue" || code == "cmn" || code in iso2 || code in iso3

    fun sameLanguage(a: String?, b: String?): Boolean {
        val x = a?.let { languageCode(it) } ?: return false
        val y = b?.let { languageCode(it) } ?: return false
        return x == y
    }

    /** iOS: `aliasCode(forName:)`. */
    fun aliasCode(name: String): String? = languageAliases[name.trim().lowercase()]
}

/** iOS: `SceneTeleprompterMode` — which language AI captions are shown in. */
enum class SceneTeleprompterMode(val raw: String) {
    Off("off"), English("english"), UserLanguage("userLanguage");

    val title: String get() = when (this) { Off -> "Off"; English -> "English"; UserLanguage -> "My language" }

    /** Language the captions are shown in (iOS `captionTargetCode`). */
    fun captionTargetCode(userLanguage: String = SubtitleTargetLanguage.load()): String? = when (this) {
        Off -> null; English -> "en"; UserLanguage -> userLanguage
    }

    companion object {
        /** Last AI CC choice — restored when playback starts again (iOS `preferredModeKey`). */
        private const val PREFERRED_MODE_KEY = "stashy_ai_cc_preferred_mode"

        fun fromRaw(raw: String?): SceneTeleprompterMode = when (raw) {
            "sceneLanguage", "english" -> English
            "userLanguage" -> UserLanguage
            else -> Off
        }

        val preferred: SceneTeleprompterMode get() = fromRaw(runCatching { Prefs.string(PREFERRED_MODE_KEY) }.getOrNull())

        fun persist(mode: SceneTeleprompterMode) = Prefs.setString(PREFERRED_MODE_KEY, mode.raw)
    }
}

/** iOS: `Scene.spokenLanguageCode` — Stash custom field `language`, codes or names. */
val Scene.spokenLanguageCode: String?
    get() = SubtitleTargetLanguage.normalizedSceneLanguageTag((customFields?.get("language") as? JsonPrimitive)?.contentOrNull)

/** iOS: `Scene.withSpokenLanguage(_:)`. */
fun Scene.withSpokenLanguage(code: String?): Scene {
    val fields = (customFields ?: kotlinx.serialization.json.JsonObject(emptyMap())).toMutableMap()
    if (code.isNullOrEmpty()) fields.remove("language") else fields["language"] = JsonPrimitive(code)
    return copy(customFields = kotlinx.serialization.json.JsonObject(fields))
}

/**
 * iOS: `ScenePlayerExtrasController.audioTrackLanguageTag()` — the spoken language the playing
 * audio track declares (ISO 639-2/B codes mapped), falling back to a language name in its label.
 */
object AudioTrackLanguage {
    private val bibliographic = mapOf(
        "ger" to "de", "fre" to "fr", "dut" to "nl", "chi" to "zh", "cze" to "cs", "gre" to "el",
        "per" to "fa", "rum" to "ro", "slo" to "sk", "alb" to "sq", "arm" to "hy", "baq" to "eu",
        "bur" to "my", "geo" to "ka", "ice" to "is", "mac" to "mk", "mao" to "mi", "may" to "ms",
        "tib" to "bo", "wel" to "cy",
    )
    private val nonLanguageTags = setOf("und", "mul", "zxx", "mis", "qaa", "unknown", "none")

    fun tag(tracks: List<PlayerTrack>, activeId: String?): String? {
        val track = tracks.firstOrNull { it.id == activeId } ?: tracks.firstOrNull() ?: return null
        return tag(track.language, track.label)
    }

    fun tag(language: String?, label: String?): String? {
        val raw = language?.trim()?.lowercase()
        if (!raw.isNullOrEmpty() && raw !in nonLanguageTags) {
            val base = raw.replace('_', '-').substringBefore('-')
            val alpha2 = bibliographic[base] ?: iso3To2(base) ?: base
            SubtitleTargetLanguage.normalizedSceneLanguageTag(alpha2)?.let { return it }
        }
        // Label like "English · AAC · 2ch" — try the first word.
        val name = label?.substringBefore('·')?.trim().orEmpty()
        val alias = SubtitleTargetLanguage.aliasCode(name) ?: return null
        return SubtitleTargetLanguage.normalizedSceneLanguageTag(alias)
    }

    private fun iso3To2(code: String): String? {
        if (code.length != 3) return null
        return Locale.getISOLanguages().firstOrNull { runCatching { Locale(it).isO3Language }.getOrNull() == code }
    }
}
