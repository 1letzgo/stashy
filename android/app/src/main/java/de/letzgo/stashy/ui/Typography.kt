package de.letzgo.stashy.ui

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle

/**
 * The iOS Dynamic Type role names the port grew up with, now resolved to the Material 3 type
 * scale ([NativeType]) so every screen reads like a native Android app. Prefer [NativeType] in
 * new code; these names stay so existing call sites keep their semantic role.
 */
object IosTypography {
    val largeTitle: TextStyle get() = NativeType.headlineLarge
    val title: TextStyle get() = NativeType.headlineMedium
    val title2: TextStyle get() = NativeType.headlineSmall
    val title3: TextStyle get() = NativeType.titleLarge
    val headline: TextStyle get() = NativeType.titleMedium
    val body: TextStyle get() = NativeType.bodyLarge
    val callout: TextStyle get() = NativeType.bodyLarge
    val subheadline: TextStyle get() = NativeType.bodyMedium
    val footnote: TextStyle get() = NativeType.bodySmall
    val caption: TextStyle get() = NativeType.bodySmall
    val caption2: TextStyle get() = NativeType.labelSmall

    /** The app's MaterialTheme typography: the stock Material 3 scale. */
    val material: Typography get() = NativeType
}
