package de.letzgo.stashy.ui.scene

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.GalleryCover
import de.letzgo.stashy.data.GroupStub
import de.letzgo.stashy.data.ImagePaths
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneEditing
import de.letzgo.stashy.data.SceneGalleryStub
import de.letzgo.stashy.data.SceneGroupEntry
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.IosTypography
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.NativeDivider
import de.letzgo.stashy.ui.NativeListItem
import de.letzgo.stashy.ui.NativeSearchField
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.nativeAccent
import de.letzgo.stashy.ui.player.PlaybackFormat
import de.letzgo.stashy.ui.player.PlayerIcons
import kotlinx.coroutines.launch

/** Text field row of a form section — the shared Material field ([NativeTextField]). */
@Composable
fun FormTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, singleLine: Boolean = true, keyboardType: KeyboardType = KeyboardType.Text, textAlign: TextAlign = TextAlign.Start) {
    NativeTextField(
        value, onChange, label = null, modifier = modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        placeholder = placeholder.ifEmpty { null },
        keyboard = keyboardType,
        singleLine = singleLine, minLines = 5,
        autoCorrect = true,
        textAlign = textAlign,
    )
}

/** Search row of a form section — the shared Material search pill on the card. */
@Composable
private fun FormSearchField(value: String, onChange: (String) -> Unit, placeholder: String) =
    NativeSearchField(value, onChange, placeholder, Modifier.padding(horizontal = 12.dp, vertical = 8.dp), containerColor = Theme.palette.background)

@Composable
private fun FormRow(onClick: (() -> Unit)? = null, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    // Material list item metrics (56 dp, 16 dp insets, bodyLarge), like the Settings rows.
    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalTextStyle provides NativeType.bodyLarge) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

@Composable
private fun LoadingRow(text: String = "Loading...") {
    NativeListItem(text, headlineColor = Theme.palette.secondaryText, leading = {
        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp, color = Theme.palette.secondaryText)
    })
}

/** iOS: `EditSceneTitleSheet` ("Edit Scene": Title + Description). */
@Composable
fun EditSceneTitleSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (String?, String?) -> Unit) {
    var title by remember { mutableStateOf(scene.displayTitle) }
    var details by remember { mutableStateOf(scene.details.orEmpty()) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    SceneModalSheet("Edit Scene", onDismiss, actionTitle = "Save", actionEnabled = !saving, actionBusy = saving, onAction = {
        saving = true
        val t = title.ifEmpty { null }; val d = details.ifEmpty { null }
        scope.launch {
            if (runCatching { SceneEditing.updateTitleAndDetails(scene.id, t, d) }.isSuccess) { onSaved(t, d); onDismiss() }
            else { saving = false; SceneToast.show("Failed to update scene", PlayerIcons.close, SceneToast.Style.Error) }
        }
    }) {
        FormSection("Title") { FormTextField(title, { title = it }, "Title", Modifier.fillMaxWidth()) }
        FormSection("Description") { FormTextField(details, { details = it }, "", Modifier.fillMaxWidth().heightIn(min = 120.dp), singleLine = false) }
    }
}

/** A row of a picker list (iOS sheets: name, "N scenes", checkmark). */
data class PickerEntry(val id: String, val name: String, val subtitle: String?)

/**
 * iOS: `AddPerformerToSceneSheet` / `AddStudioToSceneSheet` / `AddTagToSceneSheet` /
 * `AddGroupToSceneSheet` — search field, first 30 matches, tap to toggle, "Create "<text>""
 * when nothing matches, Save writes the selection.
 */
@Composable
fun EntityPickerSheet(
    title: String,
    searchHeader: String,
    initialSelection: Set<String>,
    multiple: Boolean,
    load: suspend () -> List<PickerEntry>,
    create: suspend (String) -> PickerEntry,
    createFailedText: String,
    save: suspend (List<String>) -> Unit,
    saveFailedText: String,
    onSaved: (List<PickerEntry>) -> Unit,
    onDismiss: () -> Unit,
) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    val entries = remember { mutableStateListOf<PickerEntry>() }
    val selected = remember { mutableStateListOf<String>().apply { addAll(initialSelection) } }
    var loading by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { entries.addAll(runCatching { load() }.getOrDefault(emptyList())); loading = false }
    // Chosen entries always lead the list, whatever the search says; the search narrows only the
    // unchosen rest, so a chosen entry never vanishes.
    val pinned = entries.filter { it.id in selected }
    val filtered = entries.filter { it.id !in selected && (search.isEmpty() || it.name.contains(search, ignoreCase = true)) }
    val anyMatch = filtered.isNotEmpty() || pinned.any { it.name.contains(search, ignoreCase = true) }

    SceneModalSheet(title, onDismiss, actionTitle = "Save", actionEnabled = !saving, actionBusy = saving, onAction = {
        saving = true
        val ids = selected.toList()
        scope.launch {
            if (runCatching { save(ids) }.isSuccess) { onSaved(entries.filter { it.id in ids }); onDismiss() }
            else { saving = false; SceneToast.show(saveFailedText, PlayerIcons.close, SceneToast.Style.Error) }
        }
    }) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            NativeSearchField(search, { search = it }, searchHeader, Modifier.padding(top = 8.dp))
            FormSection(null) {
                if (loading) LoadingRow()
                else {
                    (pinned + filtered.take(30)).forEachIndexed { index, e ->
                        if (index > 0) NativeDivider()
                        FormRow({ if (e.id in selected) selected.remove(e.id) else { if (!multiple) selected.clear(); selected.add(e.id) } }) {
                            Text(e.name, Modifier.weight(1f), color = p.text)
                            e.subtitle?.let { Text(it, style = NativeType.bodyMedium, color = p.secondaryText) }
                            if (e.id in selected) { Spacer(Modifier.width(8.dp)); Icon(PlayerIcons.check, null, tint = nativeAccent(), modifier = Modifier.size(24.dp)) }
                        }
                    }
                    if (filtered.size > 30) Text("Type more to refine...", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    if (search.isNotEmpty() && !anyMatch) {
                        FormRow(if (creating) null else ({
                            creating = true
                            val name = search
                            scope.launch {
                                runCatching { create(name) }.onSuccess { e ->
                                    entries.add(e); if (!multiple) selected.clear(); selected.add(e.id); search = ""
                                }.onFailure { SceneToast.show(createFailedText, PlayerIcons.close, SceneToast.Style.Error) }
                                creating = false
                            }
                        })) {
                            Icon(PlayerIcons.plusCircle, null, tint = Appearance.tint, modifier = Modifier.size(20.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Create \"$search\"", color = Appearance.tint)
                        }
                    }
                }
            }
        }
    }
}

private fun count(n: Int?, unit: String) = n?.let { "$it $unit" }

@Composable
fun EditPerformersSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (List<Performer>) -> Unit) {
    val byId = remember { mutableMapOf<String, Performer>() }
    EntityPickerSheet(
        "Edit Performers", "Search Performers", scene.performers.map { it.id }.toSet(), multiple = true,
        load = { SceneEditing.allPerformers().onEach { byId[it.id] = it }.map { PickerEntry(it.id, it.name, count(it.sceneCount ?: 0, "scenes")) } },
        create = { name -> SceneEditing.createPerformer(name).also { byId[it.id] = it }.let { PickerEntry(it.id, it.name, count(it.sceneCount ?: 0, "scenes")) } },
        createFailedText = "Failed to create performer",
        save = { SceneEditing.updatePerformers(scene.id, it) }, saveFailedText = "Failed to update performers",
        onSaved = { picked -> onSaved(picked.mapNotNull { byId[it.id] }) }, onDismiss = onDismiss,
    )
}

@Composable
fun EditStudioSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (Studio?) -> Unit) {
    val byId = remember { mutableMapOf<String, Studio>() }
    EntityPickerSheet(
        "Set Studio", "Search Studio", setOfNotNull(scene.studio?.id), multiple = false,
        load = { SceneEditing.allStudios().onEach { byId[it.id] = it }.map { PickerEntry(it.id, it.name, count(it.sceneCount ?: 0, "scenes")) } },
        create = { name -> SceneEditing.createStudio(name).also { byId[it.id] = it }.let { PickerEntry(it.id, it.name, count(it.sceneCount ?: 0, "scenes")) } },
        createFailedText = "Failed to create studio",
        save = { SceneEditing.updateStudio(scene.id, it.firstOrNull()) }, saveFailedText = "Failed to update studio",
        onSaved = { picked -> onSaved(picked.firstOrNull()?.let { byId[it.id] }) }, onDismiss = onDismiss,
    )
}

@Composable
fun EditTagsSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (List<Tag>) -> Unit) {
    val byId = remember { mutableMapOf<String, Tag>() }
    EntityPickerSheet(
        "Edit Tags", "Search Tags", scene.tags.orEmpty().map { it.id }.toSet(), multiple = true,
        load = { SceneEditing.allTags().onEach { byId[it.id] = it }.map { PickerEntry(it.id, it.name, count(it.sceneCount, "scenes")) } },
        create = { name -> SceneEditing.createTag(name).also { byId[it.id] = it }.let { PickerEntry(it.id, it.name, count(it.sceneCount, "scenes")) } },
        createFailedText = "Failed to create tag",
        save = { SceneEditing.updateTags(scene.id, it) }, saveFailedText = "Failed to update tags",
        onSaved = { picked -> onSaved(picked.mapNotNull { byId[it.id] }) }, onDismiss = onDismiss,
    )
}

@Composable
fun EditGroupsSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (List<SceneGroupEntry>) -> Unit) {
    val byId = remember { mutableMapOf<String, GroupStub>() }
    EntityPickerSheet(
        "Edit Groups", "Search Groups", scene.groups.orEmpty().map { it.group.id }.toSet(), multiple = true,
        load = {
            SceneEditing.allGroups().onEach { byId[it.id] = GroupStub(it.id, it.name, it.frontImagePath, it.updatedAt) }
                .map { PickerEntry(it.id, it.name, count(it.sceneCount, "scenes")) }
        },
        create = { name -> SceneEditing.createGroup(name).also { byId[it.id] = GroupStub(it.id, it.name, it.frontImagePath, it.updatedAt) }.let { PickerEntry(it.id, it.name, count(it.sceneCount, "scenes")) } },
        createFailedText = "Failed to create group",
        save = { SceneEditing.updateGroups(scene.id, it) }, saveFailedText = "Failed to update groups",
        onSaved = { picked -> onSaved(picked.mapNotNull { byId[it.id] }.map { SceneGroupEntry(it, null) }) }, onDismiss = onDismiss,
    )
}

/**
 * iOS: `AddGalleryToSceneSheet` — galleries of the scene's performers first ("Galleries from
 * Scene Performers"); typing searches all galleries ("Other Galleries").
 */
@Composable
fun EditGalleriesSheet(scene: Scene, onDismiss: () -> Unit, onSaved: (List<SceneGalleryStub>) -> Unit) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    val performerIds = scene.performers.map { it.id }
    val selected = remember { mutableStateListOf<String>().apply { addAll(scene.galleries.orEmpty().map { it.id }) } }
    var performerGalleries by remember { mutableStateOf<List<Gallery>>(emptyList()) }
    var allGalleries by remember { mutableStateOf<List<Gallery>>(emptyList()) }
    var didLoadAll by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (performerIds.isNotEmpty()) performerGalleries = runCatching { SceneEditing.galleriesForEdit(performerIds) }.getOrDefault(emptyList())
        else { allGalleries = runCatching { SceneEditing.galleriesForEdit(emptyList()) }.getOrDefault(emptyList()); didLoadAll = true }
        loading = false
    }
    val searching = search.isNotBlank()
    LaunchedEffect(searching) {
        if (searching && !didLoadAll) {
            didLoadAll = true; loading = true
            allGalleries = runCatching { SceneEditing.galleriesForEdit(emptyList()) }.getOrDefault(emptyList()); loading = false
        }
    }
    fun filter(list: List<Gallery>): List<Gallery> {
        val q = search.trim().lowercase()
        return if (q.isEmpty()) list else list.filter { it.displayTitle.lowercase().contains(q) }
    }
    val performerSet = performerGalleries.map { it.id }.toSet()

    @Composable
    fun row(g: Gallery, divider: Boolean) {
        if (divider) NativeDivider()
        FormRow({ if (g.id in selected) selected.remove(g.id) else selected.add(g.id) }) {
            Box(Modifier.size(52.dp).clip(RoundedCornerShape(8.dp)).background(Appearance.tint.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
                Icon(PlayerIcons.gallery, null, tint = Appearance.tint.copy(alpha = 0.5f), modifier = Modifier.size(18.dp))
                g.coverURL?.let { AsyncImage(it, null, Modifier.size(52.dp), contentScale = ContentScale.Crop) }
            }
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(g.displayTitle, color = p.text, maxLines = 2)
                g.imageCount?.let { Text("$it images", style = NativeType.bodyMedium, color = p.secondaryText) }
            }
            Icon(if (g.id in selected) PlayerIcons.checkCircle else PlayerIcons.circle, null, tint = if (g.id in selected) Appearance.tint else p.secondaryText)
        }
    }

    SceneModalSheet("Edit Galleries", onDismiss, actionTitle = "Save", actionEnabled = !saving, actionBusy = saving, onAction = {
        saving = true
        val ids = selected.toList()
        scope.launch {
            if (runCatching { SceneEditing.updateGalleries(scene.id, ids) }.isSuccess) {
                val byId = (scene.galleries.orEmpty().map { SceneGalleryStub(it.id, it.title, it.date, it.imageCount, it.updatedAt, it.cover) } +
                    (performerGalleries + allGalleries).map { SceneGalleryStub(it.id, it.title, it.date, it.imageCount, it.updatedAt, it.cover) }).associateBy { it.id }
                onSaved(ids.mapNotNull { byId[it] }); onDismiss()
            } else { saving = false; SceneToast.show("Failed to update galleries", PlayerIcons.close, SceneToast.Style.Error) }
        }
    }) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            NativeSearchField(search, { search = it }, "Search Galleries", Modifier.padding(top = 8.dp))
            if (loading && performerGalleries.isEmpty() && allGalleries.isEmpty()) FormSection(null) { LoadingRow() }
            else {
                if (performerIds.isNotEmpty()) FormSection(if (searching) "From Scene Performers" else "Galleries from Scene Performers") {
                    val list = filter(performerGalleries)
                    if (list.isEmpty()) Text(if (searching) "No matching performer galleries" else "No galleries for linked performers", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    else list.take(if (searching) 30 else 50).forEachIndexed { i, g -> row(g, i > 0) }
                }
                if (searching) FormSection(if (performerIds.isEmpty()) "Galleries" else "Other Galleries") {
                    val others = filter(allGalleries).filter { it.id !in performerSet }
                    when {
                        !didLoadAll || loading -> LoadingRow()
                        others.isEmpty() -> Text("No matching galleries", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                        else -> {
                            others.take(30).forEachIndexed { i, g -> row(g, i > 0) }
                            if (others.size > 30) Text("Type more to refine...", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                        }
                    }
                } else if (performerIds.isEmpty()) FormSection("All Galleries") {
                    allGalleries.take(30).forEachIndexed { i, g -> row(g, i > 0) }
                    if (allGalleries.size > 30) Text("Type to search...", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                }
            }
        }
    }
}

/**
 * iOS: `AddMarkerSheet` — start time, optional end time (seconds or MM:SS, quick picks
 * +30/+60/+90 s), primary tag (scene tags first, 20 shown). The marker is named after its tag.
 * After creating: refresh, then generate marker previews and screenshots (refresh again when done).
 */
@Composable
fun AddMarkerSheet(scene: Scene, seconds: Double, onDismiss: () -> Unit, onComplete: () -> Unit) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    val sceneTagIds = scene.tags.orEmpty().map { it.id }.toSet()
    var tags by remember { mutableStateOf<List<Tag>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var primaryTagId by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var endText by remember { mutableStateOf("") }
    var quick by remember { mutableStateOf<Int?>(null) }
    var creating by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { tags = runCatching { SceneEditing.allTags() }.getOrDefault(emptyList()); loading = false }
    val title = tags.firstOrNull { it.id == primaryTagId }?.name.orEmpty()
    val base = if (search.isEmpty()) tags else tags.filter { it.name.lowercase().contains(search.lowercase()) }
    val filtered = base.filter { it.id in sceneTagIds } + base.filter { it.id !in sceneTagIds }
    fun quickEnd(d: Int) = PlaybackFormat.markerTime(seconds + d)

    SceneModalSheet("Add Marker", onDismiss, actionTitle = "Add", actionEnabled = primaryTagId.isNotEmpty() && title.isNotEmpty() && !creating, actionBusy = creating, onAction = {
        creating = true
        val end = PlaybackFormat.parseTime(endText)
        scope.launch {
            val created = runCatching { SceneEditing.createMarker(scene.id, title, seconds, end, primaryTagId) }
            creating = false
            if (created.isFailure) return@launch
            onDismiss()
            onComplete()
            // Not in this sheet's scope: dismissing cancelled it, so the jobs never reached Stash.
            SceneEditing.generateForNewMarker(scene.id) { onComplete() }
        }
    }) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            FormSection("Marker Details") {
                FormRow { Text("Start Time:", Modifier.weight(1f), color = p.text); Text(PlaybackFormat.markerTime(seconds), color = p.secondaryText) }
                NativeDivider()
                Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("End Time (optional):", color = p.text)
                    FormTextField(endText, { v -> endText = v; quick?.let { if (v != quickEnd(it)) quick = null } }, "Seconds or MM:SS", Modifier.weight(1f), keyboardType = KeyboardType.Number, textAlign = TextAlign.End)
                }
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(30, 60, 90).forEach { d ->
                        val on = quick == d
                        Text(
                            "+${d}s",
                            Modifier.weight(1f).clip(RoundedCornerShape(50)).background(if (on) Appearance.tint else p.background)
                                .clickable { if (on) { quick = null; endText = "" } else { quick = d; endText = quickEnd(d) } }.padding(vertical = 8.dp),
                            style = IosTypography.subheadline.copy(fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center),
                            color = if (on) Color.White else p.text,
                        )
                    }
                }
            }
            FormSection("Primary Tag") {
                NativeSearchField(search, { search = it }, "Search Tags...", Modifier.padding(8.dp))
                when {
                    loading -> LoadingRow("Loading tags...")
                    tags.isEmpty() -> Text("No tags found on server", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    else -> {
                        filtered.take(20).forEach { tag ->
                            NativeDivider()
                            FormRow({ primaryTagId = tag.id }) {
                                Text(tag.name, Modifier.weight(1f), color = p.text)
                                tag.sceneCount?.let { Text("$it", style = NativeType.bodyMedium, color = p.secondaryText) }
                                if (primaryTagId == tag.id) { Spacer(Modifier.width(8.dp)); Icon(PlayerIcons.check, null, tint = nativeAccent(), modifier = Modifier.size(24.dp)) }
                            }
                        }
                        if (filtered.size > 20) Text("Type more to refine search...", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                        else if (search.isNotEmpty() && filtered.isEmpty()) Text("No tags match '$search'", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    }
                }
            }
        }
    }
}

/**
 * iOS: `SetTagImageFromFrameSheet` ("Generate Tag Cover") — the captured frame, scene tags
 * first (most used first), search over all tags; Apply sets the tag image.
 */
@Composable
fun SetTagImageFromFrameSheet(imageDataURL: String, sceneTags: List<Tag>, onDismiss: () -> Unit) {
    val p = Theme.palette
    val scope = rememberCoroutineScope()
    var allTags by remember { mutableStateOf<List<Tag>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var search by remember { mutableStateOf("") }
    var selectedId by remember { mutableStateOf(sortedByFrequency(sceneTags).firstOrNull()?.id) }
    var saving by remember { mutableStateOf(false) }
    val preview = remember(imageDataURL) {
        runCatching {
            val bytes = Base64.decode(imageDataURL.substringAfter(','), Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
        }.getOrNull()
    }
    LaunchedEffect(Unit) {
        val ranked = sortedByFrequency(runCatching { SceneEditing.allTags() }.getOrDefault(emptyList()))
        allTags = ranked; loading = false
        if (selectedId == null) {
            val byId = ranked.associateBy { it.id }
            selectedId = (sortedByFrequency(sceneTags.map { byId[it.id] ?: it }).firstOrNull() ?: ranked.firstOrNull())?.id
        }
    }
    val source = when {
        search.isNotEmpty() -> allTags
        sceneTags.isNotEmpty() -> { val byId = allTags.associateBy { it.id }; sceneTags.map { byId[it.id] ?: it } }
        else -> allTags
    }
    val selectable = sortedByFrequency(if (search.isEmpty()) source else source.filter { it.name.lowercase().contains(search.lowercase()) })

    SceneModalSheet("Generate Tag Cover", onDismiss, actionTitle = "Apply", actionEnabled = selectedId != null, actionBusy = saving, onAction = {
        val tagId = selectedId ?: return@SceneModalSheet
        saving = true
        scope.launch {
            val ok = runCatching { SceneEditing.setTagImage(tagId, imageDataURL) }.isSuccess
            saving = false
            if (ok) {
                val name = (sceneTags + allTags).firstOrNull { it.id == tagId }?.name ?: "Tag"
                SceneToast.show("Image updated for $name", PlayerIcons.tag, SceneToast.Style.Success)
                onDismiss()
            } else SceneToast.show("Failed to update tag image", PlayerIcons.close, SceneToast.Style.Error)
        }
    }) {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            preview?.let { Image(it, null, Modifier.fillMaxWidth().height(160.dp).padding(top = 4.dp, bottom = 8.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Fit) }
            FormSection(if (search.isEmpty() && sceneTags.isNotEmpty()) "Scene Tags" else "Tags", footer = "The selected tag’s image will be replaced with this video frame.") {
                NativeSearchField(search, { search = it }, "Search Tags...", Modifier.padding(8.dp))
                when {
                    loading && allTags.isEmpty() -> LoadingRow("Loading tags...")
                    selectable.isEmpty() -> Text(if (search.isEmpty()) "No tags available" else "No tags match '$search'", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    else -> {
                        selectable.take(40).forEach { tag ->
                            NativeDivider()
                            FormRow({ selectedId = tag.id }) {
                                Box(Modifier.size(64.dp, 36.dp).clip(RoundedCornerShape(8.dp)).background(Color.Gray.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
                                    if (tag.hasImage) AsyncImage(tag.imageURL, null, Modifier.size(64.dp, 36.dp), contentScale = ContentScale.Crop)
                                    else Icon(PlayerIcons.tag, null, tint = p.secondaryText, modifier = Modifier.size(14.dp))
                                }
                                Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                                    Text(tag.name, color = p.text)
                                    if (sceneTags.any { it.id == tag.id }) Text("On this scene", style = NativeType.bodyMedium, color = p.secondaryText)
                                }
                                if (selectedId == tag.id) Icon(PlayerIcons.check, null, tint = nativeAccent(), modifier = Modifier.size(24.dp))
                            }
                        }
                        if (selectable.size > 40) Text("Type more to refine search...", Modifier.padding(16.dp), style = NativeType.bodyMedium, color = p.secondaryText)
                    }
                }
            }
        }
    }
}

/** Most-used tags first (`scene_count` desc), name as tiebreaker. */
internal fun sortedByFrequency(tags: List<Tag>): List<Tag> =
    tags.sortedWith(compareByDescending<Tag> { it.sceneCount ?: 0 }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })

