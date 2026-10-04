package de.letzgo.stashy.ui.tools

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stashy.R
import de.letzgo.stashy.data.Prefs
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Theme

/**
 * iOS: `StashyAppIcon` (raw values and labels identical). Android swaps the launcher entry
 * between `activity-alias`es in the manifest (`.Launcher<Name>`), one per icon.
 */
enum class StashyAppIcon(val raw: String, val label: String, val aliasName: String, @DrawableRes val preview: Int) {
    SystemDefault("systemDefault", "Default", "LauncherDefault", R.drawable.app_icon_choice_default),
    Light("light", "Light", "LauncherLight", R.drawable.app_icon_choice_light),
    Brown("brown", "Brown", "LauncherBrown", R.drawable.app_icon_choice_brown),
    Blue("blue", "Blue", "LauncherBlue", R.drawable.app_icon_choice_blue),
    Purple("purple", "Purple", "LauncherPurple", R.drawable.app_icon_choice_purple),
    Pink("pink", "Pink", "LauncherPink", R.drawable.app_icon_choice_pink),
    Rainbow("rainbow", "Rainbow", "LauncherRainbow", R.drawable.app_icon_choice_rainbow),
    Gold("gold", "Gold", "LauncherGold", R.drawable.app_icon_choice_gold);

    companion object { fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SystemDefault }
}

/**
 * iOS: `AppIconManager` — stashy+ alternate app icons. The enabled alias is the source of truth;
 * the choice is mirrored in prefs (`stashy_app_icon`) so the picker renders instantly.
 */
object AppIcons {
    private const val PREF_KEY = "stashy_app_icon"
    private const val CLASS_PREFIX = "de.letzgo.stashy."

    var current by mutableStateOf(StashyAppIcon.from(Prefs.string(PREF_KEY)))
        private set

    /** iOS: `select(_:)` — refuses without stashy+ (toast like iOS). */
    fun select(icon: StashyAppIcon, context: Context = Prefs.appContext) {
        if (!StashyPlus.isUnlocked) {
            showToast("Custom app icons are part of stashy+. Unlock in Settings")
            return
        }
        set(icon, context)
    }

    /** Applies [icon] unconditionally (enables its alias, disables all others). */
    fun set(icon: StashyAppIcon, context: Context = Prefs.appContext) {
        if (icon == current && isEnabled(context, icon)) return
        val pm = context.packageManager
        runCatching {
            // Enable the new entry first so the app never has zero launcher entries.
            pm.setComponentEnabledSetting(component(context, icon), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            StashyAppIcon.entries.filter { it != icon }.forEach {
                pm.setComponentEnabledSetting(component(context, it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
            current = icon
            Prefs.setString(PREF_KEY, icon.raw)
        }.onFailure { showToast(it.message ?: "This device cannot change the app icon") }
    }

    /** iOS: `revertToDefaultIfNeeded()` — called when stashy+ is no longer active. */
    fun revertToDefaultIfNeeded(context: Context = Prefs.appContext) {
        if (current != StashyAppIcon.SystemDefault || !isEnabled(context, StashyAppIcon.SystemDefault)) set(StashyAppIcon.SystemDefault, context)
    }

    /** Re-reads the enabled alias (e.g. after a restore from backup). */
    fun sync(context: Context = Prefs.appContext) {
        val enabled = StashyAppIcon.entries.firstOrNull { isEnabled(context, it) } ?: StashyAppIcon.SystemDefault
        current = enabled
        Prefs.setString(PREF_KEY, enabled.raw)
    }

    private fun component(context: Context, icon: StashyAppIcon) = ComponentName(context.packageName, CLASS_PREFIX + icon.aliasName)

    private fun isEnabled(context: Context, icon: StashyAppIcon): Boolean {
        val state = context.packageManager.getComponentEnabledSetting(component(context, icon))
        return when (state) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> icon == StashyAppIcon.SystemDefault // manifest default
        }
    }
}

/** iOS: `StashyPlusAppIconSettings` — adaptive grid of 60 pt icon tiles with labels. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AppIconPicker(modifier: Modifier = Modifier) {
    val haptics = LocalHapticFeedback.current
    val p = Theme.palette
    FlowRow(
        modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        StashyAppIcon.entries.forEach { icon ->
            val selected = AppIcons.current == icon
            val shape = RoundedCornerShape(14.dp)
            Column(
                Modifier.width(72.dp).clickable(remember { MutableInteractionSource() }, null) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    AppIcons.select(icon)
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Image(
                    painterResource(icon.preview), icon.label,
                    Modifier.size(60.dp).clip(shape)
                        .border(if (selected) 2.5.dp else 1.dp, if (selected) Appearance.tint else p.text.copy(alpha = 0.2f), shape),
                    contentScale = ContentScale.Fit,
                )
                Text(icon.label, fontSize = 11.sp, color = p.secondaryText)
            }
        }
    }
}
