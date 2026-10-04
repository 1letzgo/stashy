package de.letzgo.stashy.ui.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stashy.data.Gallery
import de.letzgo.stashy.data.Performer
import de.letzgo.stashy.data.SavedFilter
import de.letzgo.stashy.data.Scene
import de.letzgo.stashy.data.SceneMarker
import de.letzgo.stashy.data.StashGroup
import de.letzgo.stashy.data.StashImage
import de.letzgo.stashy.data.Studio
import de.letzgo.stashy.data.Tag
import de.letzgo.stashy.ui.detail.GalleryDetailScreen
import de.letzgo.stashy.ui.detail.GroupDetailScreen
import de.letzgo.stashy.ui.detail.ImageViewerScreen
import de.letzgo.stashy.ui.detail.PerformerDetailScreen
import de.letzgo.stashy.ui.detail.StudioDetailScreen
import de.letzgo.stashy.ui.detail.TagDetailScreen
import de.letzgo.stashy.ui.MainTab
import de.letzgo.stashy.ui.Nav
import de.letzgo.stashy.ui.scene.SceneDetailScreen

/**
 * Where Dashboard and Search cards lead (iOS `NavigationLink(destination: …DetailView)`).
 */
object DetailLinks {
    fun scene(s: Scene) = Nav.push(SceneDetailScreen(s.id, s))
    /** iOS: marker → `SceneDetailView(scene, autoPlay: true)` at the marker's start. */
    fun marker(m: SceneMarker) { m.scene?.let { Nav.push(SceneDetailScreen(it.id, it.copy(resumeTime = m.seconds), autoPlay = true)) } }
    fun performer(p: Performer) = Nav.push(PerformerDetailScreen(p.id, p))
    fun studio(s: Studio) = Nav.push(StudioDetailScreen(s.id, s))
    fun tag(t: Tag) = Nav.push(TagDetailScreen(t.id, t))
    fun gallery(g: Gallery) = Nav.push(GalleryDetailScreen(g.id, g))
    fun group(g: StashGroup) = Nav.push(GroupDetailScreen(g.id, g))
    /** iOS: `FullScreenImageView(images:selectedImageId:)` over the search results. */
    fun image(images: List<StashImage>, selected: StashImage) = Nav.push(ImageViewerScreen(images, images.indexOf(selected).coerceAtLeast(0)))
}

/** iOS `HomeChannelDestination`. */
enum class HomeChannelDestination(val label: String) { Scenes("Scenes"), Clips("Clips") }

/**
 * A dashboard channel opened into Feeds (iOS `navigateToReelsChannel(filter:sort:)` /
 * `navigateToReelsClipsChannel`). [sort] is the iOS sort raw value.
 */
data class FeedsChannelRequest(val filter: SavedFilter, val destination: HomeChannelDestination, val sort: String)

/**
 * Hand-off to Feeds. TODO(feeds): replace with the Feeds feature's channel entry (or read and
 * clear [pending] when the Feeds tab appears).
 */
object FeedsChannelLink {
    var pending by mutableStateOf<FeedsChannelRequest?>(null)

    fun open(request: FeedsChannelRequest) {
        pending = request
        Nav.select(MainTab.Feeds)
    }
}
