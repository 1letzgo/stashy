package de.letzgo.stashy.ui.tools.aitags

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.StashyPlus
import de.letzgo.stashy.data.tools.AITagModelState
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.SimilarScenes
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeSwitch
import de.letzgo.stashy.ui.NativeTopBar
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.nativeTopBarPadding
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.IconButtonDefaults
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Screen
import de.letzgo.stashy.ui.StashyColors
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.tools.GroupedCard
import de.letzgo.stashy.ui.tools.RowDivider
import de.letzgo.stashy.ui.tools.SectionSpacer
import de.letzgo.stashy.ui.tools.SettingsList
import de.letzgo.stashy.ui.tools.SettingsRow
import de.letzgo.stashy.ui.tools.SettingsSectionFooter
import de.letzgo.stashy.ui.tools.SettingsSectionHeader
import java.text.DateFormat
import java.util.Date

/**
 * iOS: `AITagsSettingsView` (Settings → Recommendations) — stashy+ hub: tag suggestions, Similar
 * Scenes and the For You row share one statistics model; For You is on while either switch is.
 */
class AITagsSettingsScreen : Screen {
    override val key: String = "ai-tags-settings"

    @Composable
    override fun Content() = AITagsSettingsView()
}

private val TITLE: String get() = tr(R.string.recommendations)

@Composable
fun AITagsSettingsView() {
    val p = Theme.palette
    val tint = Appearance.tint
    val manager = AITagSuggestions
    val similar = SimilarScenes
    val isUnlocked = StashyPlus.isUnlocked
    val state = manager.state
    val isBuilding = state is AITagModelState.Building

    LaunchedEffect(Unit) { manager.loadIfNeeded() }

    val topBar = nativeTopBarPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        SettingsList(topPadding = topBar) {
            if (!isUnlocked) {
                item {
                    GroupedCard {
                        SettingsRow(tr(R.string.recommendations_require_stashy_plus), icon = SF.lock, iconTint = p.secondaryText, titleColor = p.secondaryText)
                    }
                    SettingsSectionFooter(tr(R.string.hint_unlock_stashy_plus_to_use))
                    SectionSpacer()
                }
            }

            // MARK: Features
            item {
                SettingsSectionHeader(tr(R.string.features), isBeta = true)
                GroupedCard {
                    ToggleRow(tr(R.string.tag_suggestions), SF.tag, checked = isUnlocked && manager.isEnabled, enabled = isUnlocked) {
                        if (isUnlocked) manager.isEnabled = it
                    }
                    RowDivider()
                    ToggleRow(tr(R.string.similar_scenes), Icons.Outlined.Layers, checked = isUnlocked && similar.isEnabled, enabled = isUnlocked) {
                        if (isUnlocked) similar.isEnabled = it
                    }
                }
                SectionSpacer()
            }

            // MARK: For You
            item {
                SettingsSectionHeader(tr(R.string.for_you_on_home), isBeta = true)
                GroupedCard {
                    val forYou = de.letzgo.stashy.data.tools.SceneRecommendations
                    ToggleRow(
                        tr(R.string.for_you), SF.wand,
                        checked = isUnlocked && forYou.hasStatistics && forYou.isEnabled,
                        enabled = isUnlocked && forYou.hasStatistics,
                    ) { if (isUnlocked) forYou.updateEnabled(it) }
                    RowDivider()
                    SettingsRow(tr(R.string.for_you_settings), SF.sliderHorizontal3, enabled = isUnlocked, onClick = { Nav.push(RecommendationSettingsScreen()) })
                }
                SettingsSectionFooter(
                    if (de.letzgo.stashy.data.tools.SceneRecommendations.hasStatistics)
                        tr(R.string.hint_scenes_picked_from_your_plays)
                    else tr(R.string.hint_needs_tag_suggestions_or_similar)
                )
                SectionSpacer()
            }

            // MARK: Forgotten Favorites
            item {
                val forgotten = de.letzgo.stashy.data.tools.ForgottenFavorites
                SettingsSectionHeader(tr(R.string.forgotten_favorites_on_home), isBeta = true)
                GroupedCard {
                    ToggleRow(
                        tr(R.string.forgotten_favorites), SF.arrowClockwise,
                        checked = isUnlocked && forgotten.hasStatistics && forgotten.isEnabled,
                        enabled = isUnlocked && forgotten.hasStatistics,
                    ) { if (isUnlocked) forgotten.updateEnabled(it) }
                    RowDivider()
                    SettingsRow(tr(R.string.forgotten_favorites_settings), SF.sliderHorizontal3, enabled = isUnlocked, onClick = { Nav.push(ForgottenFavoritesSettingsScreen()) })
                }
                SettingsSectionFooter(
                    if (forgotten.hasStatistics)
                        tr(R.string.hint_top_scenes_you_have_not)
                    else tr(R.string.hint_needs_tag_suggestions_or_similar)
                )
                SectionSpacer()
            }

            // MARK: Statistics
            item {
                SettingsSectionHeader(tr(R.string.statistics))
                GroupedCard {
                    SettingsRow(tr(R.string.status), icon = SF.chartBar) {
                        Text(statusText(state, manager.lastBuiltAt), style = NativeType.bodyMedium, color = p.secondaryText, textAlign = TextAlign.End)
                    }
                    RowDivider()
                    if (state is AITagModelState.Building) {
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            LinearProgressIndicator(
                                progress = { manager.buildProgress.toFloat() },
                                modifier = Modifier.fillMaxWidth(),
                                color = nativeAccent(), trackColor = p.separator,
                            )
                            Text("${state.processed} of ${state.total} items", style = NativeType.bodySmall, color = p.secondaryText)
                        }
                        RowDivider()
                        SettingsRow(tr(R.string.action_stop), icon = Icons.Outlined.StopCircle, iconTint = StashyColors.systemRed, titleColor = StashyColors.systemRed, onClick = { manager.cancelWork() })
                    } else {
                        SettingsRow(
                            if (manager.hasModel) tr(R.string.rebuild_statistics) else tr(R.string.build_statistics),
                            icon = Icons.Filled.Sync, titleColor = tint,
                            enabled = manager.needsStatistics, onClick = { manager.rebuild() },
                        )
                    }
                }
                SettingsSectionFooter(tr(R.string.refreshed_every_12_hours))
                SectionSpacer()
            }

            // MARK: Tuning
            item {
                SettingsSectionHeader(tr(R.string.tuning))
                Box(Modifier.alpha(if (isUnlocked) 1f else 0.5f)) {
                    GroupedCard {
                        StepperRow(tr(R.string.tags_per_item), manager.maxSuggestions, 1..20, enabled = isUnlocked && manager.isEnabled) { manager.maxSuggestions = it }
                        RowDivider(16.dp)
                        StepperRow(tr(R.string.similar_scenes), similar.maxCount, 4..8, enabled = isUnlocked && similar.isEnabled) { similar.maxCount = it }
                        RowDivider(16.dp)
                        val count = manager.dismissedTagCount
                        SettingsRow(
                            tr(R.string.ignored_tags), icon = Icons.Outlined.ThumbDown, titleColor = tint,
                            enabled = isUnlocked && count > 0, onClick = { manager.resetDismissals() },
                        ) {
                            Text(if (count == 0) tr(R.string.none) else "$count · ${tr(R.string.action_reset).lowercase()}", style = NativeType.bodyMedium, color = p.secondaryText)
                        }
                    }
                }
            }
        }

        // iOS: `stashySettingsDetailChrome(title)` — Material top app bar.
        NativeTopBar(TITLE)
    }
}

private fun statusText(state: AITagModelState, lastBuiltAt: Long?): String = when (state) {
    AITagModelState.Idle -> tr(R.string.not_built)
    AITagModelState.Loading -> tr(R.string.loading)
    is AITagModelState.Building -> tr(R.string.counting_menu)
    is AITagModelState.Ready -> lastBuiltAt?.let {
        "${tr(R.string.arg_items, state.items)} · ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))}"
    } ?: tr(R.string.arg_items, state.items)
    is AITagModelState.Failed -> state.message
}

/** iOS: `Toggle(isOn:) { Label(…) }` — Material switch row. */
@Composable
private fun ToggleRow(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    SettingsRow(title, icon = icon, enabled = enabled, onClick = { onChange(!checked) }) {
        NativeSwitch(checked, onChange, enabled)
    }
}

/** iOS: `Stepper(value:in:)` — value plus Material tonal −/+ icon buttons. */
@Composable
internal fun StepperRow(title: String, value: Int, range: IntRange, enabled: Boolean, onChange: (Int) -> Unit) {
    val p = Theme.palette
    val colors = IconButtonDefaults.filledTonalIconButtonColors(
        containerColor = nativeAccent().copy(alpha = 0.16f), contentColor = p.text,
        disabledContainerColor = p.text.copy(alpha = 0.06f), disabledContentColor = p.text.copy(alpha = 0.38f),
    )
    SettingsRow(title, enabled = enabled) {
        FilledTonalIconButton({ onChange(value - 1) }, enabled = enabled && value > range.first, colors = colors) { Icon(Icons.Filled.Remove, tr(R.string.decrement)) }
        Text("$value", style = NativeType.titleMedium, color = p.text, textAlign = TextAlign.Center, maxLines = 1, modifier = Modifier.widthIn(min = 28.dp))
        FilledTonalIconButton({ onChange(value + 1) }, enabled = enabled && value < range.last, colors = colors) { Icon(Icons.Filled.Add, tr(R.string.increment)) }
    }
}
