package de.letzgo.stashy.ui.tools.magazine

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.IdName
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.tools.MagazineChapter
import de.letzgo.stashy.data.tools.MagazineLogic
import de.letzgo.stashy.ui.Appearance
import de.letzgo.stashy.ui.NativeCardShape
import de.letzgo.stashy.ui.NativeSheetTopBar
import de.letzgo.stashy.ui.NativeTextField
import de.letzgo.stashy.ui.NativeTonalButton
import de.letzgo.stashy.ui.NativeType
import de.letzgo.stashy.ui.SF
import de.letzgo.stashy.ui.Theme
import de.letzgo.stashy.ui.components.SelectChip

private enum class PagePickerMode(val title: String) { Chapters("Chapters"), Pages("Pages") }

/** iOS: `MagazinePagePickerSheet` — by number, from the page list, or by chapter when there are any. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MagazinePagePickerSheet(
    pages: List<StashImage>,
    chapters: List<MagazineChapter>,
    currentPage: Int,
    currentChapterId: String?,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val p = Theme.palette
    var input by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(if (chapters.isEmpty()) PagePickerMode.Pages else PagePickerMode.Chapters) }
    val entered = MagazineLogic.enteredPage(input, pages.size)
    fun select(page: Int) {
        onSelect(page)
        onDismiss()
    }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = p.background) {
        Column(Modifier.fillMaxHeight().navigationBarsPadding().imePadding()) {
            NativeSheetTopBar("Go to page", onDismiss)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                NativeTextField(
                    input, { value -> input = value.filter(Char::isDigit) }, null, Modifier.weight(1f),
                    placeholder = "Page (1–${pages.size})", keyboard = KeyboardType.Number, leadingIcon = SF.number,
                    imeAction = ImeAction.Go, keyboardActions = KeyboardActions(onGo = { entered?.let(::select) }),
                )
                NativeTonalButton("Go", enabled = entered != null) { entered?.let(::select) }
            }
            if (chapters.isNotEmpty()) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PagePickerMode.entries.forEach { option ->
                        SelectChip(option.title, selected = mode == option, onClick = { mode = option })
                    }
                }
            }
            key(mode) {
                val initial = when (mode) {
                    PagePickerMode.Chapters -> chapters.indexOfFirst { it.id == currentChapterId }
                    PagePickerMode.Pages -> currentPage
                }
                val listState = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(initial - 2, 0))
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f), listState,
                    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    when (mode) {
                        PagePickerMode.Chapters -> itemsIndexed(chapters, key = { _, it -> it.id }) { _, chapter ->
                            val page = MagazineLogic.chapterPage(chapter, pages.size)
                            PickerRow(chapter.id == currentChapterId, { select(page) }) {
                                Text(chapter.title, Modifier.weight(1f), style = NativeType.bodyMedium, color = p.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                Text("Page ${page + 1}", style = NativeType.bodySmall, color = p.secondaryText)
                            }
                        }
                        PagePickerMode.Pages -> itemsIndexed(pages, key = { _, it -> it.id }) { index, image ->
                            PickerRow(index == currentPage, { select(index) }) {
                                AsyncImage(
                                    image.thumbnailURL, null,
                                    Modifier.size(width = 36.dp, height = 50.dp).clip(RoundedCornerShape(4.dp)).background(Color.Gray.copy(alpha = 0.2f)),
                                    contentScale = ContentScale.Crop,
                                )
                                Text("Page ${index + 1}", Modifier.weight(1f), style = NativeType.bodyMedium, color = p.text)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PickerRow(isCurrent: Boolean, onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(NativeCardShape)
            .background(Theme.palette.secondaryBackground).clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        content()
        if (isCurrent) Icon(SF.checkmark, "Current", Modifier.size(16.dp), tint = Appearance.tint)
        else Spacer(Modifier.size(16.dp))
    }
}

/** iOS: `MagazineDetailsSheet` — what the open gallery is. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun MagazineDetailsSheet(gallery: Gallery, tags: List<IdName>, pageCount: Int, chapterCount: Int, onDismiss: () -> Unit) {
    val p = Theme.palette
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = p.background) {
        Column(Modifier.navigationBarsPadding()) {
            NativeSheetTopBar("Details", onDismiss)
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                DetailsCard {
                    Text(gallery.displayTitle, style = NativeType.titleMedium, color = p.text)
                    Fact("Pages", "$pageCount")
                    if (chapterCount > 0) Fact("Chapters", "$chapterCount")
                    gallery.studio?.name?.takeIf { it.isNotEmpty() }?.let { Fact("Studio", it) }
                    gallery.date?.takeIf { it.isNotEmpty() }?.let { Fact("Date", it) }
                    gallery.rating100?.let { Fact("Rating", MagazineLogic.ratingLabel(it)) }
                }
                gallery.performers?.takeIf { it.isNotEmpty() }?.let { performers ->
                    DetailsSection("Performers") {
                        Text(performers.joinToString(", ") { it.name }, style = NativeType.bodyMedium, color = p.text)
                    }
                }
                if (tags.isNotEmpty()) {
                    DetailsSection("Tags") {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            tags.forEach { tag ->
                                Box(Modifier.clip(CircleShape).background(p.background).padding(horizontal = 10.dp, vertical = 5.dp)) {
                                    Text(tag.name ?: tag.title.orEmpty(), style = NativeType.labelMedium, color = p.text)
                                }
                            }
                        }
                    }
                }
                gallery.details?.takeIf { it.isNotEmpty() }?.let { details ->
                    DetailsSection("Details") { Text(details, style = NativeType.bodyMedium, color = p.text) }
                }
            }
        }
    }
}

@Composable
private fun DetailsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title.uppercase(), style = NativeType.labelMedium, color = Theme.palette.secondaryText)
        DetailsCard(content)
    }
}

@Composable
private fun DetailsCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(NativeCardShape).background(Theme.palette.secondaryBackground).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}

@Composable
private fun Fact(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = NativeType.bodyMedium, color = Theme.palette.secondaryText)
        Spacer(Modifier.size(8.dp))
        Text(value, style = NativeType.bodyMedium, color = Theme.palette.text)
    }
}
