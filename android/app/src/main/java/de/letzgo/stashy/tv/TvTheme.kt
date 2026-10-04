package de.letzgo.stashy.tv

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.LocalContentColor
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme
import de.letzgo.stashy.ui.Appearance

/** tvOS points → dp: tvOS lays out on 1920 pt, Android TV on 960 dp. */
fun pt(value: Number): Dp = (value.toFloat() * TvGridSpec.PT).dp

/** tvOS colours (`Color.appBackground` is fixed `#161E2B` on tvOS, the app is always dark). */
object TvColors {
    val background = Color(0xFF161E2B)
    val text = Color.White
    val secondary = Color(0x99EBEBF5)
    val tertiary = Color(0x4DEBEBF5)
    /** `Color.gray.opacity(0.08)` placeholders. */
    val placeholder = Color(0x148E8E93)
    val cardFill = Color.White.copy(alpha = 0.05f)
    val star = Color(0xFFFFD60A)
    val red = Color(0xFFFF453A)
    val green = Color(0xFF30D158)
    val yellow = Color(0xFFFFD60A)
    val tint: Color get() = Appearance.tint
}

/** tvOS Dynamic Type sizes, halved (pt → dp). */
object TvType {
    val largeTitle = TextStyle(fontSize = 38.sp, fontWeight = FontWeight.Bold)
    val title = TextStyle(fontSize = 29.sp, fontWeight = FontWeight.Bold)
    val title2 = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold)
    val title3 = TextStyle(fontSize = 19.sp)
    val headline = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 16.sp)
    val callout = TextStyle(fontSize = 15.sp)
    val subheadline = TextStyle(fontSize = 15.sp)
    val caption = TextStyle(fontSize = 13.sp)
    val caption2 = TextStyle(fontSize = 11.5.sp)
    val monoCaption = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
}

@Composable
fun TvTheme(content: @Composable () -> Unit) {
    val scheme = darkColorScheme(
        primary = Appearance.tint,
        background = TvColors.background,
        surface = TvColors.background,
        onSurface = Color.White,
        onBackground = Color.White,
    )
    MaterialTheme(colorScheme = scheme) {
        CompositionLocalProvider(LocalContentColor provides Color.White, content = content)
    }
}
