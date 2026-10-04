package de.letzgo.stashy.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Prefs

/** iOS: `AppTheme` (raw values identical, stored under `kPreferredTheme`). */
enum class AppTheme(val raw: String) {
    System("System"), Light("Light"), Dark("Dark"), DarkBlue("Dark Blue");
    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: DarkBlue }
}

/** iOS: `AppearanceManager` — theme, tint, O-counter icon, glass transparency, edit mode. */
object Appearance {
    var theme by mutableStateOf(AppTheme.from(Prefs.string("kPreferredTheme")))
        private set
    var tint by mutableStateOf(loadTint())
        private set
    var oCounterIcon by mutableStateOf(Prefs.string("kOCounterIcon") ?: "heart")
        private set
    var glassTransparency by mutableStateOf(if (Prefs.has("kGlassTransparency")) Prefs.float("kGlassTransparency").coerceIn(0.2f, 1f) else 1f)
        private set
    var isEditModeEnabled by mutableStateOf(Prefs.bool("kEditModeEnabled", true))
        private set

    fun updateTheme(value: AppTheme) { theme = value; Prefs.setString("kPreferredTheme", value.raw) }
    fun updateTint(color: Color) {
        tint = color
        Prefs.setFloat("kTintColorRed", color.red); Prefs.setFloat("kTintColorGreen", color.green)
        Prefs.setFloat("kTintColorBlue", color.blue); Prefs.setFloat("kTintColorAlpha", color.alpha)
    }
    fun updateOCounterIcon(value: String) { oCounterIcon = value; Prefs.setString("kOCounterIcon", value) }
    fun updateGlassTransparency(value: Float) { glassTransparency = value; Prefs.setFloat("kGlassTransparency", value) }
    fun updateEditMode(value: Boolean) { isEditModeEnabled = value; Prefs.setBool("kEditModeEnabled", value) }

    private fun loadTint(): Color =
        if (Prefs.has("kTintColorRed")) Color(Prefs.float("kTintColorRed"), Prefs.float("kTintColorGreen"), Prefs.float("kTintColorBlue"), Prefs.float("kTintColorAlpha", 1f))
        else StashyColors.defaultTint

    /** iOS: `presets` (Stashy Brown, Blue, Red …) with the iOS system colours. */
    val presets = listOf(
        "Stashy Brown" to StashyColors.appAccent,
        "Blue" to Color(0xFF0A84FF), "Red" to Color(0xFFFF453A), "Orange" to Color(0xFFFF9F0A),
        "Green" to Color(0xFF30D158), "Purple" to Color(0xFFBF5AF2), "Pink" to Color(0xFFFF375F),
        "Gray" to StashyColors.defaultTint,
    )
}

/** iOS colours (`Color.appAccent`, `appBackground(for:)` …). */
object StashyColors {
    val appAccent = Color(0xFF644C3D)
    val defaultTint = Color(0xFF8E8E93) // iOS .gray

    // iOS system palette used across cards and badges.
    val systemBlue = Color(0xFF0A84FF)
    val systemGreen = Color(0xFF30D158)
    val systemOrange = Color(0xFFFF9F0A)
    val systemPurple = Color(0xFFBF5AF2)
    val systemPink = Color(0xFFFF375F)
    val systemRed = Color(0xFFFF453A)
    val systemYellow = Color(0xFFFFD60A)
    val systemTeal = Color(0xFF40C8E0)
    val systemIndigo = Color(0xFF5E5CE6)
}

/** Resolved palette for the current theme (what `Color.appBackground` etc. return on iOS). */
data class Palette(
    val isDark: Boolean,
    val background: Color,
    val secondaryBackground: Color,
    val studioHeader: Color,
    val text: Color,
    val secondaryText: Color,
    val tertiaryText: Color,
    val separator: Color,
    val pillAccent: Color,
)

object Theme {
    val palette: Palette
        @Composable get() {
            val systemDark = isSystemInDarkTheme()
            return when (Appearance.theme) {
                AppTheme.DarkBlue -> Palette(
                    true, Color(0xFF1E293B), Color(0xFF334155), Color(0xFF2A3A52),
                    Color.White, Color(0x99EBEBF5), Color(0x4DEBEBF5), Color(0x33FFFFFF), Color.White.copy(alpha = 0.9f),
                )
                AppTheme.Dark -> dark()
                AppTheme.Light -> light()
                AppTheme.System -> if (systemDark) dark() else light()
            }
        }

    private fun dark() = Palette(
        true, Color(0xFF000000), Color(0xFF1C1C1E), Color(0xFF3A3A3C),
        Color.White, Color(0x99EBEBF5), Color(0x4DEBEBF5), Color(0x33FFFFFF), Appearance.tint,
    )
    private fun light() = Palette(
        false, Color(0xFFF2F2F7), Color(0xFFFFFFFF), Color(0xFF3A3A3C),
        Color.Black, Color(0x993C3C43), Color(0x4D3C3C43), Color(0x33000000), Appearance.tint,
    )
}

/** iOS: `DesignTokens`. */
object Tokens {
    object Radius { val card = 12.dp; val button = 14.dp; val small = 10.dp; val tiny = 4.dp }
    object Spacing { val xxs = 4.dp; val xs = 8.dp; val sm = 12.dp; val md = 16.dp; val lg = 20.dp; val xl = 24.dp }
    object Chrome { val fabHeight = 36.dp; val contentTopGap = 8.dp; const val strokeOpacity = 0.07f }
    object Grid { val spacing = 12.dp; val contentPadding = 16.dp; val idealPosterCardWidth = 220.dp }
}

@Composable
fun StashyTheme(content: @Composable () -> Unit) {
    val p = Theme.palette
    val scheme = if (p.isDark) darkColorScheme(
        primary = Appearance.tint, background = p.background, surface = p.secondaryBackground,
        onBackground = p.text, onSurface = p.text, surfaceVariant = p.secondaryBackground,
        surfaceContainer = p.secondaryBackground, surfaceContainerHigh = p.secondaryBackground,
    ) else lightColorScheme(
        primary = Appearance.tint, background = p.background, surface = p.secondaryBackground,
        onBackground = p.text, onSurface = p.text,
    )
    MaterialTheme(colorScheme = scheme, typography = IosTypography.material, content = content)
}
