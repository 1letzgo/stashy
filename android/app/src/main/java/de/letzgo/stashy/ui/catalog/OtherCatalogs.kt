package de.letzgo.stashy.ui.catalog

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import de.letzgo.stashy.ui.EmptyState
import de.letzgo.stashy.ui.SF

// Placeholders until the catalog port lands (iOS: ImagesView, GalleriesView, PerformersView,
// StudiosView, TagsView, Groups, MarkersView).
@Composable fun ImagesCatalog() = Pending("Images")
@Composable fun GalleriesCatalog() = Pending("Galleries")
@Composable fun PerformersCatalog() = Pending("Performers")
@Composable fun StudiosCatalog() = Pending("Studios")
@Composable fun TagsCatalog() = Pending("Tags")
@Composable fun GroupsCatalog() = Pending("Groups")
@Composable fun MarkersCatalog() = Pending("Markers")

@Composable
internal fun Pending(title: String) = Box(Modifier.fillMaxSize(), Alignment.Center) { EmptyState(SF.cubeBox, title, "Coming soon") }
