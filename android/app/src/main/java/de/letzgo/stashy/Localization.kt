package de.letzgo.stashy

import android.content.Context
import androidx.annotation.StringRes
import de.letzgo.stashy.data.Prefs
import java.io.File

/**
 * Shared-key localization. Every UI text has one key that Android and iOS / tvOS / macOS share
 * (iOS: `tr("<key>")`). Keys and translations are kept in Tolgee (project "stashy",
 * tools/l10n/README.md); the `strings.xml` files under `res/values-*` are pulled from there.
 *
 * Works outside composables too (data models, sort and filter labels), so the whole app uses one
 * call. Arguments fill `%1$s`, `%2$s` … and are shown as text, like a string template.
 */
object Localization {
    @Volatile internal var context: Context? = null

    fun init(context: Context) {
        val app = context.applicationContext
        this.context = AppLanguage.localized(app)
    }
}

/**
 * The language of stashy's own texts. Beta: English unless the user picks another one in
 * Settings; "system" follows the device. Chosen once per launch; a change restarts the app at once.
 * iOS: `AppLanguage` in Localization.swift (same key and values).
 */
object AppLanguage {
    const val STORAGE_KEY = "app_language"
    const val SYSTEM = "system"
    private const val DEFAULT = "en"

    /** Languages with a translation in Tolgee, named in their own language. */
    val options: List<Pair<String, String>> = listOf(
        "en" to "English", "de" to "Deutsch", "es" to "Español", "fr" to "Français",
        "it" to "Italiano", "nl" to "Nederlands", "sv" to "Svenska", "da" to "Dansk",
        "nb" to "Norsk bokmål", "pl" to "Polski", "pt-BR" to "Português (Brasil)",
        "tr" to "Türkçe", "ru" to "Русский", "ar" to "العربية", "ja" to "日本語",
        "ko" to "한국어", "zh-Hans" to "简体中文", "zh-Hant" to "繁體中文",
    )

    /** The stored choice (what the picker shows). */
    val stored: String get() = Prefs.string(STORAGE_KEY) ?: DEFAULT

    /** The choice this launch runs with. */
    var active: String = DEFAULT
        private set

    /**
     * Stores [code] and restarts the app so every text, also the labels built once into static
     * lists, comes up in the new language. iOS rebuilds its interface in place instead.
     */
    fun selectAndRestart(context: Context, code: String) {
        Prefs.commitString(STORAGE_KEY, code)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        context.startActivity(android.content.Intent.makeRestartActivityTask(launch.component))
        Runtime.getRuntime().exit(0)
    }

    private val translationCache = java.util.concurrent.ConcurrentHashMap<Int, Set<String>>()

    /**
     * Whether [text] is the text of [id] in any of the app's languages (or an older English wording
     * of it), e.g. a default title stored while another language was active.
     */
    fun isTranslation(text: String, @StringRes id: Int): Boolean {
        val fold = { s: String -> s.lowercase().filter { it.isLetterOrDigit() } }
        val target = fold(text)
        if (target.isEmpty()) return false
        val context = Localization.context ?: return false
        val all = translationCache.getOrPut(id) {
            options.map { it.first }.mapNotNull { code ->
                runCatching {
                    val config = android.content.res.Configuration(context.resources.configuration)
                    config.setLocale(java.util.Locale.forLanguageTag(code))
                    fold(context.createConfigurationContext(config).getString(id))
                }.getOrNull()
            }.toSet()
        }
        return target in all
    }

    /** For formatting (weekdays, dates) in the app's language. */
    val locale: java.util.Locale
        get() = if (active == SYSTEM) java.util.Locale.getDefault() else java.util.Locale.forLanguageTag(active)

    fun name(code: String): String =
        if (code == SYSTEM) tr(R.string.device_language) else options.firstOrNull { it.first == code }?.second ?: code

    /**
     * First start (nothing chosen, no server yet): take the device language when stashy has it, so
     * the setup wizard already speaks it. Existing installs keep English until changed.
     */
    private fun chooseDeviceLanguageOnFirstStart() {
        if (Prefs.string(STORAGE_KEY) != null || Prefs.has("stashy_saved_servers") || Prefs.has("stashy_server_config")) return
        val codes = options.map { it.first }
        val list = android.os.LocaleList.getDefault()
        val match = (0 until list.size()).asSequence().map { list[it] }.mapNotNull { locale ->
            val lang = locale.language
            when {
                lang == "pt" -> "pt-BR"
                lang == "zh" -> if (locale.script == "Hant" || locale.country in setOf("TW", "HK", "MO")) "zh-Hant" else "zh-Hans"
                lang == "no" || lang == "nn" -> "nb"
                else -> lang
            }.takeIf { it in codes }
        }.firstOrNull()
        Prefs.setString(STORAGE_KEY, match ?: DEFAULT)
    }

    /** [context] with the chosen language for resources; the device language for "system". */
    internal fun localized(context: Context): Context {
        runCatching { chooseDeviceLanguageOnFirstStart() }
        active = runCatching { Prefs.string(STORAGE_KEY) }.getOrNull() ?: DEFAULT
        if (active == SYSTEM) return context
        val config = android.content.res.Configuration(context.resources.configuration)
        config.setLocale(java.util.Locale.forLanguageTag(active))
        return context.createConfigurationContext(config)
    }
}

/**
 * Without arguments the text is not formatted, so a `%` from Tolgee shows as it is whether or not
 * the export escaped it as `%%`.
 */
fun tr(@StringRes id: Int, vararg args: Any?): String {
    val texts = args.map { it.toString() }.toTypedArray()
    val context = Localization.context ?: return JvmStrings.format(id, texts)
    if (texts.isEmpty()) return context.getString(id).replace("%%", "%")
    return context.getString(id, *texts)
}

/**
 * Plain JVM unit tests run without Android resources: English straight from `values/strings.xml`
 * (the tests run in the module folder), so they see the same text as the app. Never used in the app.
 */
private object JvmStrings {
    private val byId: Map<Int, String> by lazy {
        val file = listOf("src/main/res/values/strings.xml", "app/src/main/res/values/strings.xml")
            .map(::File).firstOrNull { it.exists() } ?: return@lazy emptyMap()
        val byName = Regex("<string name=\"([^\"]+)\">(.*?)</string>").findAll(file.readText())
            .associate { it.groupValues[1] to unescape(it.groupValues[2]) }
        R.string::class.java.fields.mapNotNull { f -> byName[f.name]?.let { f.getInt(null) to it } }.toMap()
    }

    fun format(id: Int, args: Array<String>): String {
        val text = byId[id] ?: return "#$id"
        return if (args.isEmpty()) text.replace("%%", "%") else String.format(text, *args)
    }

    private fun unescape(raw: String): String {
        var s = raw
        if (s.length >= 2 && s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length - 1)
        s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
        val out = StringBuilder()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '\\' && i + 1 < s.length) {
                out.append(when (val n = s[i + 1]) { 'n' -> '\n'; 't' -> '\t'; else -> n })
                i += 2
            } else {
                out.append(c)
                i++
            }
        }
        return out.toString()
    }
}
