package de.letzgo.stashy.ui.tools.aitags

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
                            if (!isUnlocked) "Forgotten Favorites requires stashy+"
                            else if (engine.hasStatistics) "Forgotten Favorites is off. Turn it on in Recommendations to show it on Home."
                            else "Turn on Tag suggestions or Similar scenes to show Forgotten Favorites on Home.",
                            icon = if (!isUnlocked) SF.lock else Icons.Outlined.Info, iconTint = p.secondaryText, titleColor = p.secondaryText,
                        )
                    }
                    SectionSpacer()
                }
            }

            item {
                SettingsSectionHeader("Forgotten Favorites", isBeta = true)
                GroupedCard {
                    SettingsRow("Status", icon = SF.arrowClockwise) {
                        Text(statusText(), style = NativeType.bodyMedium, color = p.secondaryText)
                    }
                }
                SettingsSectionFooter("Scenes among your favorites that you have not played for a while. Everything is worked out on this device. Move or hide the row in Settings › Home.")
                SectionSpacer()
            }

            item {
                SettingsSectionHeader("Not played for")
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Segmented(ForgottenFavorites.dayChoices, engine.days, { daysTitle(it) }) {
                                if (isUnlocked) engine.updateDays(it)
                            }
                        }
                    }
                }
                SettingsSectionFooter("A favorite shows up once you have not played it for this long.")
                SectionSpacer()
            }

            item {
                SettingsSectionHeader("Favorites")
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Ranked by", style = NativeType.bodyLarge, color = p.text)
                            Segmented(ForgottenFavoritesRanking.entries, engine.ranking, { it.title }) {
                                if (isUnlocked) engine.updateRanking(it)
                            }
                        }
                        RowDivider(16.dp)
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Top", style = NativeType.bodyLarge, color = p.text)
                            Segmented(ForgottenFavorites.poolChoices, engine.pool, { "$it" }) {
                                if (isUnlocked) engine.updatePool(it)
                            }
                        }
                    }
                }
                SettingsSectionFooter("${engine.ranking.detail} Only the top ${engine.pool} of each count.")
                SectionSpacer()
            }

            item {
                GroupedCard {
                    SettingsRow(
                        "Reset to defaults", icon = Icons.AutoMirrored.Filled.Undo,
                        iconTint = if (engine.hasCustomSettings) StashyColors.systemRed else p.secondaryText,
                        titleColor = if (engine.hasCustomSettings) StashyColors.systemRed else p.secondaryText,
                        enabled = isUnlocked && engine.hasCustomSettings, onClick = { engine.resetSettings() },
                    )
                }
            }
        }

        NativeTopBar("Forgotten Favorites")
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
        ForgottenFavoritesState.Idle -> "Not built yet"
        ForgottenFavoritesState.Loading -> "Looking…"
        ForgottenFavoritesState.Preparing -> "Waiting for statistics"
        ForgottenFavoritesState.Ready -> "${engine.items.size} of ${engine.poolCount} favorites"
    }
}
