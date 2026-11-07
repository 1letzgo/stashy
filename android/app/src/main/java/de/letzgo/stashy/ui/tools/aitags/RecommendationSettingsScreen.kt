package de.letzgo.stashy.ui.tools.aitags

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.tools.RecommendationDiscovery
import de.letzgo.stashy.data.tools.RecommendationState
import de.letzgo.stashy.data.tools.SceneRecommendations
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.nativeTopBarPadding
import de.letzgo.stashy.ui.settings.Segmented
import de.letzgo.stashy.ui.tools.GroupedCard
import de.letzgo.stashy.ui.tools.RowDivider
import de.letzgo.stashy.ui.tools.SectionSpacer
import de.letzgo.stashy.ui.tools.SettingsList
import de.letzgo.stashy.ui.tools.SettingsRow
import de.letzgo.stashy.ui.tools.SettingsSectionFooter
import de.letzgo.stashy.ui.tools.SettingsSectionHeader
import java.text.DateFormat
import java.util.Date

/** iOS: `RecommendationSettingsView` (Settings › stashy+ › Recommendations › For You). */
class RecommendationSettingsScreen : Screen {
    override val key: String = "recommendation-settings"

    @Composable
    override fun Content() = RecommendationSettingsView()
}

@Composable
fun RecommendationSettingsView() {
    val p = Theme.palette
    val engine = SceneRecommendations
    val isUnlocked = StashyPlus.isUnlocked
    // Changes take effect when Home shows the row again; leaving here starts the rebuild.
    DisposableEffect(Unit) { onDispose { engine.refreshIfNeeded() } }
    // Feedback for Refresh: a prepared list swaps in instantly and would otherwise go unseen.
    val builtAt = engine.builtAt
    val firstBuiltAt = androidx.compose.runtime.remember { builtAt }
    androidx.compose.runtime.LaunchedEffect(builtAt) {
        if (builtAt != null && firstBuiltAt != null && builtAt != firstBuiltAt && engine.state == RecommendationState.Ready) {
            de.letzgo.stashy.ui.tools.showToast("New suggestions on Home")
        }
    }

    val topBar = nativeTopBarPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        SettingsList(topPadding = topBar) {
            if (!isUnlocked || !engine.isFeatureOn) {
                item {
                    GroupedCard {
                        SettingsRow(
                            if (!isUnlocked) "For You requires stashy+" else "Turn on Tag suggestions or Similar scenes to show For You on Home.",
                            icon = if (!isUnlocked) SF.lock else Icons.Outlined.Info, iconTint = p.secondaryText, titleColor = p.secondaryText,
                        )
                    }
                    SectionSpacer()
                }
            }

            item {
                SettingsSectionHeader("For You", isBeta = true)
                GroupedCard {
                    SettingsRow("Status", icon = SF.sparkles) {
                        Text(statusText(), style = NativeType.bodyMedium, color = p.secondaryText)
                    }
                    RowDivider()
                    SettingsRow(
                        "Refresh suggestions", icon = Icons.Filled.Sync, titleColor = Appearance.tint,
                        enabled = isUnlocked && !engine.isRefreshing, onClick = { engine.rebuild() },
                    ) {
                        if (engine.isRefreshing) androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = p.secondaryText)
                    }
                }
                SettingsSectionFooter("Suggests scenes on Home from what you played, the O-Counts you gave and your ratings. Each card says why it was picked. Everything is worked out on this device from your own server. Move or hide the row in Settings › Home.")
                SectionSpacer()
            }

            item {
                SettingsSectionHeader("Watch history")
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("Look back", style = NativeType.bodyLarge, color = p.text)
                            Segmented(SceneRecommendations.lookbackChoices, engine.lookbackDays, { "${it}d" }) {
                                if (isUnlocked) engine.updateLookback(it)
                            }
                        }
                        RowDivider(16.dp)
                        StepperRow("Suggestions", engine.count, SceneRecommendations.countRange, enabled = isUnlocked) { engine.updateCount(it) }
                    }
                }
                SettingsSectionFooter("Recent plays count more than older ones. Scenes you played in this period are never suggested again. With nothing played in it, your top O-Count and best-rated scenes stand in.")
                SectionSpacer()
            }

            item {
                SettingsSectionHeader("What to suggest")
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                            Segmented(RecommendationDiscovery.entries, engine.discovery, { it.title }) {
                                if (isUnlocked) engine.updateDiscovery(it)
                            }
                        }
                    }
                }
                SettingsSectionFooter(engine.discovery.detail)
                SectionSpacer()
            }

            item {
                SettingsSectionHeader("Influence")
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        WeightRow("Similar to watched", Icons.Outlined.Layers, engine.similarWeight, isUnlocked) { engine.updateSimilar(it) }
                        RowDivider(16.dp)
                        WeightRow("Performers", SF.personFill, engine.performerWeight, isUnlocked) { engine.updatePerformer(it) }
                        RowDivider(16.dp)
                        WeightRow("Studios", SF.building2, engine.studioWeight, isUnlocked) { engine.updateStudio(it) }
                        RowDivider(16.dp)
                        WeightRow("Tags", SF.tag, engine.tagWeight, isUnlocked) { engine.updateTag(it) }
                        RowDivider(16.dp)
                        WeightRow("O-Counts", SF.heartFill, engine.oCountWeight, isUnlocked) { engine.updateOCount(it) }
                        RowDivider(16.dp)
                        WeightRow("Ratings", SF.starFill, engine.ratingWeight, isUnlocked) { engine.updateRating(it) }
                    }
                }
                SettingsSectionFooter("How much each part of your history steers the picks. Similar to watched finds unplayed scenes close to single scenes you watched a lot. Off leaves a part out. With Tag Suggestions statistics built, tags that often go with your favorite tags count as well.")
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

        NativeTopBar("For You")
    }
}

private fun statusText(): String {
    val engine = SceneRecommendations
    return when (engine.state) {
        RecommendationState.Idle -> "Not built yet"
        RecommendationState.Loading -> "Looking…"
        RecommendationState.NoHistory -> "No plays yet"
        RecommendationState.Failed -> engine.failure ?: "Failed"
        RecommendationState.Ready -> if (engine.isRefreshing) "Looking…" else {
            val picks = "${engine.recommendations.size} scenes from ${engine.seedCount} watched"
            engine.builtAt?.let { "$picks · ${DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it))}" } ?: picks
        }
    }
}

private fun weightLabel(value: Float): String = when {
    value < 0.01f -> "Off"
    value < 0.75f -> "Low"
    value < 1.26f -> "Normal"
    value < 1.76f -> "High"
    else -> "Max"
}

/** iOS `weightRow`: label + value, slider 0…2 in quarter steps. */
@Composable
private fun WeightRow(title: String, icon: ImageVector, value: Float, enabled: Boolean, onChange: (Float) -> Unit) {
    val p = Theme.palette
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Appearance.tint, modifier = Modifier.size(24.dp))
            Text(title, style = NativeType.bodyLarge, color = p.text, modifier = Modifier.padding(start = 16.dp).weight(1f))
            Text(weightLabel(value), style = NativeType.bodyLarge, color = p.secondaryText)
        }
        Slider(
            value, { onChange((Math.round(it * 4) / 4f).coerceIn(SceneRecommendations.weightRange)) },
            enabled = enabled, valueRange = SceneRecommendations.weightRange, steps = 7,
            colors = SliderDefaults.colors(
                thumbColor = nativeAccent(), activeTrackColor = nativeAccent(), inactiveTrackColor = p.separator,
                activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent,
            ),
        )
    }
}
