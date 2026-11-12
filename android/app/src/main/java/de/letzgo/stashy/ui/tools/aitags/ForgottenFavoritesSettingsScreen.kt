package de.letzgo.stashy.ui.tools.aitags

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.tools.ForgottenFavorites
import de.letzgo.stashy.data.tools.ForgottenFavoritesRanking
import de.letzgo.stashy.data.tools.ForgottenFavoritesState
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeTopBarPadding
import de.letzgo.stashy.ui.settings.Segmented
import de.letzgo.stashy.ui.tools.GroupedCard
import de.letzgo.stashy.ui.tools.RowDivider
import de.letzgo.stashy.ui.tools.SectionSpacer
import de.letzgo.stashy.ui.tools.SettingsList
import de.letzgo.stashy.ui.tools.SettingsRow
import de.letzgo.stashy.ui.tools.SettingsSectionFooter
import de.letzgo.stashy.ui.tools.SettingsSectionHeader

/** iOS: `ForgottenFavoritesSettingsView` (Settings › stashy+ › Recommendations › Forgotten Favorites). */
class ForgottenFavoritesSettingsScreen : Screen {
    override val key: String = "forgotten-favorites-settings"

    @Composable
    override fun Content() = ForgottenFavoritesSettingsView()
}

@Composable
fun ForgottenFavoritesSettingsView() {
    val p = Theme.palette
    val engine = ForgottenFavorites
    val isUnlocked = StashyPlus.isUnlocked
    LaunchedEffect(Unit) { engine.refreshIfNeeded() }

    val topBar = nativeTopBarPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        SettingsList(topPadding = topBar) {
            if (!isUnlocked || !engine.isFeatureOn) {
                item {
                    GroupedCard {
                        SettingsRow(
                            if (!isUnlocked) tr(R.string.forgotten_favorites_requires_stashy_plus)
                            else if (engine.hasStatistics) tr(R.string.hint_forgotten_favorites_is_off_turn)
                            else tr(R.string.hint_turn_on_tag_suggestions_or_similar),
                            icon = if (!isUnlocked) SF.lock else Icons.Outlined.Info, iconTint = p.secondaryText, titleColor = p.secondaryText,
                        )
                    }
                    SectionSpacer()
                }
            }

            item {
                SettingsSectionHeader(tr(R.string.forgotten_favorites), isBeta = true)
                GroupedCard {
                    SettingsRow(tr(R.string.status), icon = SF.arrowClockwise) {
                        Text(statusText(), style = NativeType.bodyMedium, color = p.secondaryText)
                    }
                }
                SettingsSectionFooter(tr(R.string.hint_favorites_you_have_not_played))
                SectionSpacer()
            }

            item {
                SettingsSectionHeader(tr(R.string.not_played_for))
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Segmented(ForgottenFavorites.dayChoices, engine.days, { daysTitle(it) }) {
                                if (isUnlocked) engine.updateDays(it)
                            }
                        }
                    }
                }
                SectionSpacer()
            }

            item {
                SettingsSectionHeader(tr(R.string.favorites))
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(tr(R.string.ranked_by), style = NativeType.bodyLarge, color = p.text)
                            Segmented(ForgottenFavoritesRanking.entries, engine.ranking, { it.title }) {
                                if (isUnlocked) engine.updateRanking(it)
                            }
                        }
                        RowDivider(16.dp)
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(tr(R.string.top), style = NativeType.bodyLarge, color = p.text)
                            Segmented(ForgottenFavorites.poolChoices, engine.pool, { "$it" }) {
                                if (isUnlocked) engine.updatePool(it)
                            }
                        }
                    }
                }
                SectionSpacer()
            }

            item {
                GroupedCard {
                    SettingsRow(
                        tr(R.string.action_reset_to_defaults), icon = Icons.AutoMirrored.Filled.Undo,
                        iconTint = if (engine.hasCustomSettings) StashyColors.systemRed else p.secondaryText,
                        titleColor = if (engine.hasCustomSettings) StashyColors.systemRed else p.secondaryText,
                        enabled = isUnlocked && engine.hasCustomSettings, onClick = { engine.resetSettings() },
                    )
                }
            }
        }

        NativeTopBar(tr(R.string.forgotten_favorites))
    }
}

private fun daysTitle(days: Int): String = when (days) {
    365 -> "1 year"
    180 -> "6 mo"
    else -> "$days d"
}

private fun statusText(): String {
    val engine = ForgottenFavorites
    return when (engine.state) {
        ForgottenFavoritesState.Idle -> tr(R.string.not_built_yet)
        ForgottenFavoritesState.Loading -> tr(R.string.looking_menu)
        ForgottenFavoritesState.Preparing -> tr(R.string.waiting_for_statistics)
        ForgottenFavoritesState.Ready -> tr(R.string.arg_of_arg_favorites, engine.items.size, engine.poolCount)
    }
}
