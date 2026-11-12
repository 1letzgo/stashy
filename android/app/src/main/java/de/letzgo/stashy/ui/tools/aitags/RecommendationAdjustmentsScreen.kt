package de.letzgo.stashy.ui.tools.aitags

import de.letzgo.stashy.R
import de.letzgo.stashy.tr
import androidx.compose.foundation.background
import de.letzgo.stashy.ui.NativeSheetTopBar
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.tools.AITagSuggestions
import de.letzgo.stashy.data.tools.RecommendationAdjustment
import de.letzgo.stashy.data.tools.SceneRecommendations
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.NativeConfirmDialog
import de.letzgo.stashy.ui.NativeSearchField
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
import de.letzgo.stashy.ui.tools.SmallSpinner
import de.letzgo.stashy.ui.tools.showToast

internal val RecommendationAdjustment.Kind.icon: ImageVector
    get() = when (this) {
        RecommendationAdjustment.Kind.Performer -> SF.personFill
        RecommendationAdjustment.Kind.Studio -> SF.building2
        RecommendationAdjustment.Kind.Tag -> SF.tag
    }

internal val RecommendationAdjustment.Kind.addTitle: String
    get() = when (this) {
        RecommendationAdjustment.Kind.Performer -> tr(R.string.action_add_performer)
        RecommendationAdjustment.Kind.Studio -> tr(R.string.action_add_studio)
        RecommendationAdjustment.Kind.Tag -> tr(R.string.action_add_tag)
    }

/** iOS: `RecommendationAdjustmentsView` (Settings › For You › Adjustments). */
class RecommendationAdjustmentsScreen : Screen {
    override val key: String = "recommendation-adjustments"

    @Composable
    override fun Content() = RecommendationAdjustmentsView()
}

@Composable
private fun RecommendationAdjustmentsView() {
    val p = Theme.palette
    val engine = SceneRecommendations
    var confirmsRemoveAll by remember { mutableStateOf(false) }
    var addKind by remember { mutableStateOf<RecommendationAdjustment.Kind?>(null) }
    val topBar = nativeTopBarPadding()
    Box(Modifier.fillMaxSize().background(p.background)) {
        SettingsList(topPadding = topBar) {
            RecommendationAdjustment.Kind.entries.forEach { kind ->
                val entries = engine.adjustments.filter { it.kind == kind }
                item(key = kind.name) {
                    SettingsSectionHeader(kind.title)
                    GroupedCard {
                        SettingsRow(kind.addTitle, SF.plusCircleFill, titleColor = Appearance.tint, onClick = { addKind = kind })
                        entries.forEach { entry ->
                            RowDivider(16.dp)
                            AdjustmentRow(entry)
                        }
                    }
                    SectionSpacer()
                }
            }
            item {
                SettingsSectionFooter(tr(R.string.hint_hidden_never_shows_it_above))
                SectionSpacer()
            }
            if (engine.adjustments.isNotEmpty()) {
                item {
                    GroupedCard {
                        SettingsRow(tr(R.string.action_remove_all), SF.trash, iconTint = StashyColors.systemRed, titleColor = StashyColors.systemRed, onClick = { confirmsRemoveAll = true })
                    }
                }
            }
        }
        NativeTopBar(tr(R.string.adjustments))
    }
    addKind?.let { kind -> AdjustmentPickerSheet(kind) { addKind = null } }
    if (confirmsRemoveAll) {
        NativeConfirmDialog(
            tr(R.string.confirm_remove_all_adjustments), null,
            onDismiss = { confirmsRemoveAll = false }, confirmLabel = tr(R.string.action_remove_all), destructive = true,
            onConfirm = { engine.removeAllAdjustments(); confirmsRemoveAll = false },
        )
    }
}

/** iOS `RecommendationAdjustmentPicker`: every performer, studio or tag of the scene index; tap adds at 1×. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun AdjustmentPickerSheet(kind: RecommendationAdjustment.Kind, onDismiss: () -> Unit) {
    val p = Theme.palette
    val engine = SceneRecommendations
    var search by remember { mutableStateOf("") }
    var names by remember { mutableStateOf<List<Pair<String, String>>?>(null) }
    LaunchedEffect(kind) {
        AITagSuggestions.loadIfNeeded()
        val index = AITagSuggestions.sceneIndex()
        val map = when (kind) {
            RecommendationAdjustment.Kind.Performer -> index?.performerNames
            RecommendationAdjustment.Kind.Studio -> index?.studioNames
            RecommendationAdjustment.Kind.Tag -> index?.tagNames
        }.orEmpty()
        names = map.entries.map { it.key to it.value }.sortedBy { it.second.lowercase() }
    }
    val taken = engine.adjustments.filter { it.kind == kind }.map { it.itemId }.toSet()
    val term = search.trim()
    val hits = names.orEmpty().filter { it.first !in taken && (term.isEmpty() || it.second.contains(term, ignoreCase = true)) }.take(200)
    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss, containerColor = p.background,
        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxSize().navigationBarsPadding().imePadding()) {
            NativeSheetTopBar(kind.addTitle, onDismiss)
            Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                NativeSearchField(search, { search = it })
            }
            androidx.compose.foundation.lazy.LazyColumn(Modifier.weight(1f).padding(top = 8.dp)) {
                when {
                    names == null -> item { SettingsRow(tr(R.string.loading)) { SmallSpinner() } }
                    hits.isEmpty() -> item {
                        SettingsRow(if (names.isNullOrEmpty()) SceneRecommendations.PREPARING_MESSAGE else tr(R.string.nothing_found), titleColor = p.secondaryText)
                    }
                    else -> hits.forEachIndexed { i, (id, name) ->
                        item(key = id) {
                            if (i > 0) RowDivider()
                            SettingsRow(name, kind.icon, onClick = {
                                engine.setAdjustment(kind, id, name, 1.0)
                                onDismiss()
                            })
                        }
                    }
                }
            }
        }
    }
}

/** iOS `row(_:)`: name, value, slider from Hidden (0) to 3× in tenths, plus remove. */
@Composable
private fun AdjustmentRow(entry: RecommendationAdjustment) {
    val p = Theme.palette
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 6.dp, bottom = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(if (entry.isHidden) Icons.Outlined.VisibilityOff else entry.kind.icon, null, tint = Appearance.tint, modifier = Modifier.size(24.dp))
            Text(entry.name, style = NativeType.bodyLarge, color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 16.dp).weight(1f))
            Text(RecommendationAdjustment.label(entry.factor), style = NativeType.bodyLarge,
                color = if (entry.isHidden) StashyColors.systemRed else p.secondaryText)
            IconButton({ SceneRecommendations.removeAdjustment(entry.kind, entry.itemId) }) {
                Icon(SF.trash, tr(R.string.action_remove), tint = p.secondaryText, modifier = Modifier.size(20.dp))
            }
        }
        Slider(
            entry.factor.toFloat(),
            { SceneRecommendations.setAdjustment(entry.kind, entry.itemId, entry.name, Math.round(it * 10) / 10.0) },
            valueRange = 0f..3f, modifier = Modifier.padding(end = 12.dp),
            colors = SliderDefaults.colors(
                thumbColor = nativeAccent(), activeTrackColor = nativeAccent(), inactiveTrackColor = p.separator,
                activeTickColor = Color.Transparent, inactiveTickColor = Color.Transparent,
            ),
        )
    }
}

/** iOS `RecommendationAdjustMenu`: the ··· button below a For You card. */
@Composable
fun RecommendationAdjustButton(scene: Scene, tint: Color) {
    val p = Theme.palette
    var open by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf<Triple<RecommendationAdjustment.Kind, String, String>?>(null) }
    var showsTags by remember { mutableStateOf(false) }
    Box {
        IconButton({ open = true; chosen = null; showsTags = false }, Modifier.size(28.dp, 20.dp)) {
            Icon(SF.ellipsis, tr(R.string.adjust_suggestions), tint = tint, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = p.secondaryBackground) {
            val choice = chosen
            if (choice != null) {
                val (kind, id, name) = choice
                fun apply(factor: Double) {
                    SceneRecommendations.setAdjustment(kind, id, name, factor)
                    SceneRecommendations.applyAdjustmentsNow()
                    showToast(when {
                        factor < RecommendationAdjustment.HIDDEN_BELOW -> tr(R.string.arg_wont_be_suggested, name)
                        factor < 1 -> tr(R.string.less_of_arg, name)
                        else -> tr(R.string.more_of_arg, name)
                    })
                    open = false
                }
                Text(name, style = NativeType.labelLarge, color = p.secondaryText, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                MenuItem(tr(R.string.more_like_this), Icons.Outlined.ThumbUp) { apply(RecommendationAdjustment.MORE) }
                MenuItem(tr(R.string.less_like_this), Icons.Outlined.ThumbDown) { apply(RecommendationAdjustment.LESS) }
                MenuItem(tr(R.string.never_suggest), Icons.Outlined.VisibilityOff, StashyColors.systemRed) { apply(0.0) }
                if (SceneRecommendations.adjustment(kind, id) != null) {
                    MenuItem(tr(R.string.back_to_normal), Icons.AutoMirrored.Filled.Undo) {
                        SceneRecommendations.removeAdjustment(kind, id)
                        SceneRecommendations.applyAdjustmentsNow()
                        open = false
                    }
                }
            } else if (showsTags) {
                scene.tags.orEmpty().take(15).forEach { tag ->
                    ItemEntry(RecommendationAdjustment.Kind.Tag, tag.id, tag.name) { chosen = it }
                }
            } else {
                scene.performers.take(4).forEach { ItemEntry(RecommendationAdjustment.Kind.Performer, it.id, it.name) { c -> chosen = c } }
                scene.studio?.let { ItemEntry(RecommendationAdjustment.Kind.Studio, it.id, it.name) { c -> chosen = c } }
                if (!scene.tags.isNullOrEmpty()) MenuItem(tr(R.string.tags), SF.tag) { showsTags = true }
            }
        }
    }
}

@Composable
private fun ItemEntry(kind: RecommendationAdjustment.Kind, id: String, name: String, onChoose: (Triple<RecommendationAdjustment.Kind, String, String>) -> Unit) {
    val current = SceneRecommendations.adjustment(kind, id)
    MenuItem(
        current?.let { "$name · ${RecommendationAdjustment.label(it.factor)}" } ?: name,
        if (current?.isHidden == true) Icons.Outlined.VisibilityOff else kind.icon,
    ) { onChoose(Triple(kind, id, name)) }
}

@Composable
private fun MenuItem(title: String, icon: ImageVector, color: Color = Theme.palette.text, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, style = NativeType.bodyLarge, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(icon, null, tint = if (color == Theme.palette.text) Appearance.tint else color) },
        onClick = onClick,
    )
}
